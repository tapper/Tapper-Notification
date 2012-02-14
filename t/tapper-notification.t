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
use Tapper::Model 'model';

my $string = "
log4perl.rootLogger           = FATAL, root
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
$mock_mail->mock('notify',sub{my (undef, @local_results) = @_;push @results,\@local_results; return 0});

my $notify = Tapper::Notification->new();
isa_ok($notify, 'Tapper::Notification');

$notify->run();
is_deeply(\@results, [[ 'anton@mail.net', 'Testrun id 42 finished' ]], 'Expected arguments to mail notifier for test "testrun with given id finished"');
@results = ();
my $event = model('ReportsDB')->resultset('NotificationEvent')->new({
                                                                     type => 'report_received',
                                                                     message => { report_id =>  101,}  # thats the report with real TAPDOM
                                                                    }
                                                                   );
$event->insert();

$notify->run();
is_deeply(\@results, [[ 'anton@mail.net', 'Report received' ]], 'Expected arguments to mail notifier for test "report with given id received"');


@results = ();
$event = model('ReportsDB')->resultset('NotificationEvent')->new({
                                                                     type => 'testrun_finished',
                                                                     message => { testrun_id =>  23,}
                                                                    }
                                                                   );
$event->insert();
$notify->run();
is_deeply(\@results, [[ 'anton@mail.net', 'Report received' ]], 'Expected arguments to mail notifier for test "Success change for last 2 testruns with same topic as current one"');


done_testing;
