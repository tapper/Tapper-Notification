#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'Tapper::Notification' );
}

diag( "Testing Tapper::Notification $Tapper::Notification::VERSION, Perl $], $^X" );
