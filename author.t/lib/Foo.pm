package Foo;

use lib '../lib';

use Moose;
extends 'JSON::RPC::Dispatcher::App';

sub sum {
    my ($self, @params) = @_;
    my $sum = 0;
    $sum += $_ for @params;
    return $sum;
}

sub ip_address {
    my ($self, $plack_request) = @_;
    return $plack_request->address;
}


__PACKAGE__->register_rpc_method_names( 'sum', { name => 'ip_address', options => { with_plack_request => 1 }} );

1;
