package JSON::RPC::Dispatcher;

=head1 NAME

JSON::RPC::Dispatcher - A JSON-RPC 2.0 server.

=head1 SYNOPSIS

 # app.psgi
 use JSON::RPC::Dispatcher;

 my $rpc = JSON::RPC::Dispatcher->new;

 sub add_em {
    my $params = shift;
    my $sum = 0;
    $sum += $_ for @{$params};
    return $sum;
 }
 $rpc->register( 'sum', \&add_em );

 $rpc->to_app;

Then run it:

 plackup app.psgi

Now you can then call this service via a GET like:

 http://example.com/?method=sum;params=[2,3,5];id=1

Or by posting JSON to it like this:

 {"jsonrpc":"2.0","method":"sum","params":[2,3,5],"id":"1"}

And you'd get back:

 {"jsonrpc":"2.0","result":10,"id":"1"}
 
=head1 DESCRIPTION

Using this app you can make any PSGI/L<Plack> aware server a JSON-RPC 2.0 server. This will allow you to expose your custom functionality as a web service in a relatiely tiny amount of code, as you can see above.

This module follows the draft specficiation for JSON-RPC 2.0. More information can be found at L<http://groups.google.com/group/json-rpc/web/json-rpc-1-2-proposal>.

=head2 Advanced RPC

You can also get access to the procedure's internal data structures to do more advanced things. You do this by using the C<register_advanced> method as in this example.

 use JSON::RPC::Dispatcher;
 my $rpc = JSON::RPC::Dispatcher->new;

 sub guess {
    my $proc = shift;
    my $guess = $proc->params->[0];
    if ($guess == 10) {
	    return 'Correct!';
    }
    elsif ($guess > 10) {
	    $proc->error_code(986);
    	$proc->error_message('Too high.');
    }
    else {
	    $proc->error_code(987);
    	$proc->error_message('Too low.');
    }
    $proc->error_data($guess);
    return undef;
 }

 $rpc->register_advanced( 'guess', \&guess );

 $rpc->to_app;

In the above example the guess subroutine gets direct access to the L<JSON::RPC::Dispatcher::Procedure> object. This happens by calling C<register_advanced> rather than C<register>. By doing this you can set custom error codes, which can be used by your client application to implement more advanced functionality. You could also use this to throw exceptions for parameter validation and many other uses.

B<NOTE:> If you don't care about setting error codes and just want to set an error message, you can simply C<die> in your RPC and your die message will be inserted into the C<error_data> method.

=cut


use Moose;
use bytes;
extends qw(Plack::Component);
use Plack::Request;
use JSON;
use JSON::RPC::Dispatcher::Procedure;

#--------------------------------------------------------
has error_code => (
    is          => 'rw',
    default     => undef,
    predicate   => 'has_error_code',
);

#--------------------------------------------------------
has error_message => (
    is      => 'rw',
    default => undef,
);

#--------------------------------------------------------
has error_data  => (
    is      => 'rw',
    default => undef,
);

#--------------------------------------------------------
has rpcs => (
    is      => 'rw',
    default => sub { {} },
);

#--------------------------------------------------------
sub register_advanced {
    my ($self, $name, $sub) = @_;
    my $rpcs = $self->rpcs;
    $rpcs->{$name}{sub} = $sub;
    $self->rpcs($rpcs);
}

#--------------------------------------------------------
sub register {
    my ($self, $name, $sub) = @_;
    my $rpcs = $self->rpcs;
    $rpcs->{$name}{sub} = $sub;
    $rpcs->{$name}{simple} = 1;
    $self->rpcs($rpcs);
}

#--------------------------------------------------------
sub acquire_procedures {
    my ($self, $request) = @_;
    if ($request->method eq 'POST') {
        return $self->acquire_procedures_from_post($request->raw_body);
    }
    elsif ($request->method eq 'GET') {
        return [ $self->acquire_procedure_from_get($request->query_parameters) ];
    }
    else {
        $self->error_code(-32600);
        $self->error_message('Invalid Request.');
        $self->error_data('Invalid method type: '.$request->method);
        return [];
    }
}

#--------------------------------------------------------
sub acquire_procedures_from_post {
    my ($self, $body) = @_;
    my $request = eval{from_json($body)};
    if ($@) {
        $self->error_code(-32700);
        $self->error_message('Parse error.');
        $self->error_data($body);
        return undef;
    }
    else {
        if (ref $request eq 'ARRAY') {
            my @procs;
            foreach my $proc (@{$request}) {
                push @procs, $self->acquire_procedure_from_hashref($proc);
            }
            return \@procs;
        }
        elsif (ref $request eq 'HASH') {
            return [ $self->acquire_procedure_from_hashref($request) ];
        }
        else {
            $self->error_code(-32600);
            $self->error_message('Invalid request.');
            $self->error_data($request);
            return undef;
        }
    }
}

#--------------------------------------------------------
sub acquire_procedure_from_hashref {
    my ($self, $hashref) = @_;
    my $proc = JSON::RPC::Dispatcher::Procedure->new;
    $proc->method($hashref->{method});
    $proc->id($hashref->{id});
    $proc->params($hashref->{params}) if exists $hashref->{params};
    return $proc;
}

#--------------------------------------------------------
sub acquire_procedure_from_get {
    my ($self, $params) = @_;
    my $proc = JSON::RPC::Dispatcher::Procedure->new;
    $proc->method($params->{method});
    $proc->id($params->{id});
    my $decoded_params = (exists $params->{params}) ? eval{from_json($params->{params})} : undef;
    if ($@) {
        $proc->error_code(-32602);
        $proc->error_message('Invalid params');
        $proc->error_data($params->{params});
    }
    else {
        $proc->params($decoded_params) if defined $decoded_params;
    }
    return $proc;
}

#--------------------------------------------------------
sub translate_error_code_to_status {
    my ($self, $code) = @_;
    $code ||= '';
    my %trans = (
        ''          => 200,
        '-32600'    => 400,
        '-32601'    => 404,
    );
    my $status = $trans{$code};
    $status ||= 500;
    return $status;
}

#--------------------------------------------------------
sub handle_procedures {
    my ($self, $procs) = @_;
    my @responses;
    my $rpcs = $self->rpcs;
    foreach my $proc (@{$procs}) {
        my $is_notification = ($proc->id eq '') ? 1 : 0;
        unless ($proc->has_error_code) {
            my $rpc = $rpcs->{$proc->method};
            if (defined $rpc) {
                my $params = ($rpc->{simple}) ? $proc->params : $proc;
                my $result = eval{$rpc->{sub}->($params)};
                if ($@) {
                    $proc->internal_error($@);
                }
                else {
                    $proc->result($result);
                }
            }
            else {
                $proc->method_not_found($proc->method);
            }
        }

        # remove not needed elements per section 5 of the spec
        my $response = $proc->response;
        if (exists $response->{error}{code}) {
            delete $response->{result};
        }
        else {
            delete $response->{error};
        }

        # remove responses on notifications per section 4.1 of the spec
        unless ($is_notification) {
            push @responses, $response;
        }
    }

    # return the appropriate response, for batch or not
    if (scalar(@responses) > 1) {
        return \@responses;
    }
    else {
        return $responses[0];
    }
}

#--------------------------------------------------------
sub call {
    my ($self, $env) = @_;

    my $request = Plack::Request->new($env);
    my $procs = $self->acquire_procedures($request);

    my $rpc_response;
    if ($self->has_error_code) {
        $rpc_response = { 
            jsonrpc => '2.0',
            error   => {
                code    => $self->error_code,
                message => $self->error_message,
                data    => $self->error_data,
            },
        };
    }
    else {
        $rpc_response = $self->handle_procedures($procs);
    }

    my $response = $request->new_response;
    if ($rpc_response) {
        $response->status($self->translate_error_code_to_status( (ref $rpc_response eq 'HASH' && exists $rpc_response->{error}) ? $rpc_response->{error}{code} : '' ));
        $response->content_type('application/json-rpc');
        my $json = to_json($rpc_response);
        $response->content_length(bytes::length($json));
        $response->body($json);
    }
    else { # is a notification only request
        $response->status(204);
    }
    return $response->finalize;
}

=head1 PREREQS

L<Moose> 
L<JSON> 
L<Plack>
L<Plack::Request>
L<Test::More>

=head1 TODO

Once the JSON-RPC 2.0 spec is finalized, this module may need to change to support any last minute changes or additions.

=head1 SUPPORT

=over

=item Repository

L<http://github.com/plainblack/JSON-RPC-Dispatcher>

=item Bug Reports

L<http://rt.cpan.org/Public/Dist/Display.html?Name=JSON-RPC-Dispatcher>

=back

=head1 SEE ALSO

You may also want to check out these other modules, especially if you're looking for something that works with JSON-RPC 1.x.

=over 

=item Dispatchers

Other modules that compete directly with this module, though perhaps on other protocol versions.

=over

=item L<JSON::RPC>

An excellent and fully featured both client and server for JSON-RPC 1.1.

=item L<POE::Component::Server::JSONRPC>

A JSON-RPC 1.0 server for POE. I couldn't get it to work, and it doesn't look like it's maintained.

=item L<Catalyst::Plugin::Server::JSONRPC>

A JSON-RPC 1.1 dispatcher for Catalyst.

=item L<CGI-JSONRPC>

A CGI/Apache based JSON-RPC 1.1 dispatcher. Looks to be abandoned in alpha state. Also includes L<Apache2::JSONRPC>.

=item L<AnyEvent::JSONRPC::Lite>

An L<AnyEvent> JSON-RPC 1.x dispatcher. 

=item L<Sledge::Plugin::JSONRPC>

JSON-RPC 1.0 dispatcher for Sledge MVC framework.

=back

=item Clients

Modules that you'd use to access various dispatchers.

=over

=item L<JSON::RPC::Common>

A JSON-RPC client for 1.0, 1.1, and 2.0. Haven't used it, but looks pretty feature complete.

=item L<RPC::JSON>

A simple and good looking JSON::RPC 1.x client. I haven't tried it though.

=back

=back

=head1 AUTHOR

JT Smith <jt_at_plainblack_com>

=head1 LEGAL

JSON::RPC::Dispatcher is Copyright 2009 Plain Black Corporation (L<http://www.plainblack.com/>) and is licensed under the same terms as Perl itself.

=cut

1;
