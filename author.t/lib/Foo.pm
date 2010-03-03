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




__PACKAGE__->register_rpc_method_names( qw( sum ) );

1;
