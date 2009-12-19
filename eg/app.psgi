use lib '../lib';
use JSON::RPC::Dispatcher;

my $rpc = JSON::RPC::Dispatcher->new;

$rpc->register( 'ping', sub { return 'pong' } );
$rpc->register( 'echo', sub { return $_[0]->[0] } );

sub add_em {
    my $params = shift;
    my $sum = 0;
    $sum += $_ for @{$params};
    return $sum;
}

$rpc->register( 'sum', \&add_em );

# Want to do some fancy error handling? 
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

