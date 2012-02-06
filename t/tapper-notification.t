use strict;
use warnings;
use 5.010;

#################################################
#                                               #
# This test checks whether messages in order    #
# are handled correctly.                        #
#                                               #
#################################################

use Test::More;
use Tapper::Schema::TestTools;
use Test::Fixture::DBIC::Schema;
use Test::MockModule;
use Log::Log4perl;

my $string = "
log4perl.rootLogger           = DEBUG, root
log4perl.appender.root        = Log::Log4perl::Appender::Screen
log4perl.appender.root.stderr = 1
log4perl.appender.root.layout = SimpleLayout";
Log::Log4perl->init(\$string);

# -----------------------------------------------------------------------------------------------------------------
construct_fixture( schema  => testrundb_schema, fixture => 't/fixtures/testrundb/testrun_with_preconditions.yml' );
construct_fixture( schema  => reportsdb_schema, fixture => 't/fixtures/reportsdb/report.yml' );
# -----------------------------------------------------------------------------------------------------------------

BEGIN{
        use_ok('Tapper::Notification');
}

my $mock_mail = Test::MockModule->new('Tapper::Notification::Plugin::Mail');
my @results;
$mock_mail->mock('notify',sub{my (undef, @local_results) = @_; @results = @local_results; return 0});

my $notify = Tapper::Notification->new();
isa_ok($notify, 'Tapper::Notification');

$notify->run();

is_deeply(\@results, [ 'anton@mail.net', 'Testrun id 23 finished' ], 'Expected arguments to mail notifier');


done_testing;
