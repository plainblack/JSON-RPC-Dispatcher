package JSON::RPC::Dispatcher::App;

use Moose;
use JSON::RPC::Dispatcher;
use Sub::Name;

=head1 NAME

JSON::RPC::Dispatcher::App - A base class for creating object oriented apps with JRD.

=head1 SYNOPSIS

 # create your app
 package MyApp;

 use Moose;
 extends 'JSON::RPC::Dispatcher::App';

 sub sum {
    my ($self, $params) = @_;
    my $sum = 0;
    $sum += $_ for @{$params};
    return $sum;
 }

 sub guess {
    my ($self, $proc) = @_;
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

 __PACKAGE__->register_rpc_method_names( qw( sum ) );
 __PACKAGE__->register_advanced_rpc_method_names( qw( guess ) );

 1;

 # app.psgi
 MyApp->new->to_app;

=head1 DESCRIPTION

This package gives you a base class to make it easy to create object-oriented JSON-RPC applications. This is a huge benefit when writing a larger app or suite of applications rather than just exposing a procedure or two. If you build out classes of methods using JSON::RPC::Dispatcher::App, and then use L<Plack::App::URLMap> to mount each module on a different URL, you can make a pretty powerful application server in very little time.

=head1 METHODS

The following methods are available from this class.

=head2 new ( )

A L<Moose> generated constructor.

When you subclass you can easily add your own attributes using L<Moose>'s C<has> function, and they will be accessible to your RPCs like this:

 package MyApp;

 use Moose;
 extends 'JSON::RPC::Dispatcher::App';

 has db => (
    is          => 'ro',
    required    => 1,
 );

 sub make_it_go {
     my ($self, $params) = @_;
     my $sth = $self->db->prepare("select * from foo");
     ...
 }

 __PACKAGE__->register_rpc_method_names( qw(make_it_go) );

 1;

 # app.psgi
 my $db = DBI->connect(...);
 MyApp->new(db=>$db)->to_app;

=cut

#--------------------------------------------------------

=head2 register_rpc_method_names ( names )

Class method. Registers a list of method names using L<JSON::RPC::Dispatcher>'s C<register> method.

=head3 names

The list of method names to register.

=cut

sub register_rpc_method_names {
    my ($class, @methods) = @_;
    my $name = $class."::_rpc_method_names";
    no strict 'refs';
    *{$name} = Sub::Name::subname($name, sub { 
        my @old_names = ();
        my $super = $class.'::SUPER';
        if ($super->can('_rpc_method_names')) {
            @old_names = $super->_rpc_method_names;
        }
        return (@old_names, @methods); 
    } );
}


#--------------------------------------------------------

=head2 register_advanced_rpc_method_names ( names )

Class method. Registers a list of method names using L<JSON::RPC::Dispatcher>'s C<register_advanced> method.

=head3 names

The list of method names to register.

=cut

sub register_advanced_rpc_method_names {
    my ($class, @methods) = @_;
    my $name = $class."::_advanced_rpc_method_names";
    no strict 'refs';
    *{$name} = Sub::Name::subname($name, sub {
        my @old_names = ();
        my $super = $class.'::SUPER';
        if ($super->can('_advanced_rpc_method_names')) {
            @old_names = $super->_advanced_rpc_method_names;
        }
        return (@old_names, @methods); 
    } );
}

#--------------------------------------------------------

=head2 to_app ( )

Generates a PSGI/L<Plack> compatible app.

=cut

sub to_app {
    my $self = shift;
    my $rpc = JSON::RPC::Dispatcher->new;
    my $ref;
    if ($ref = $self->can('_rpc_method_names')) {
        foreach my $method ($ref->()) {
            $rpc->register($method, sub {  $self->$method(@_) });
        }
    }
    if ($ref = $self->can('_advanced_rpc_method_names')) {
        foreach my $method ($ref->()) {
            $rpc->register_advanced($method, sub {  $self->$method(@_) });
        }
    }
    $rpc->to_app;
}


=head1 LEGAL

JSON::RPC::Dispatcher is Copyright 2009 Plain Black Corporation (L<http://www.plainblack.com/>) and is licensed under the same terms as Perl itself.

=cut

no Moose;
__PACKAGE__->meta->make_immutable;

