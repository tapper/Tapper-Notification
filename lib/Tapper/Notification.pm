package Tapper::Notification;

use 5.010;
use warnings;
use strict;

use Moose;
use Tapper::Model 'model';
use Tapper::Config;
use Try::Tiny;
use Hash::Merge::Simple 'merge';
use Language::Expr;

use Data::DPath qw/dpath/;
use Tapper::Reports::DPath qw/reportdata /;


extends 'Tapper::Base';

has cfg => (is => 'rw', default => sub { Tapper::Config->subconfig} );

our $VERSION = '3.000001';

# We have these variables global to have them available in condition
# match functions in notification subscriptions. If they were not global
# the functions used in these conditions would need to have them in the API
our ($testrun, $report);

=head1 NAME

Tapper::Notification - Tapper - Daemon and plugins to handle MCP notifications

=head1 SYNOPSIS

The notification system is responsible for telling people that a certain
condition they subscribed to has occured.

    use Tapper::Notification;

    my $daemon = Tapper::Notification->new();
    $daemon->run();


=head1 FUNCTIONS

=head2 get_events

Read all pending events from database. Try no more than timeout seconds

@return success - Resultset class containing all available events

=cut

sub get_events
{
        my ($self) = @_;

        my $events;
        $events = model('ReportsDB')->resultset('NotificationEvent')->search();

        return $events;
}

=head2 get_subscriptions

Get all subscriptions for a given event type.

@param string - type of the event

@return Tapper::Schema::ReportsDB::ResultSet::Notification

=cut

sub get_subscriptions
{
        my ($self, $type) = @_;
        my $subscriptions = model('ReportsDB')->resultset('Notification')->search({event => $type});
        return $subscriptions;
}


=head2 get_testrun_data

Get all neccessary testrun data related to given testrun id.

@param int - testrun id

@return hash ref - testrun data

=cut

sub get_testrun_data
{
        my ($self, $testrun_id) = @_;
        my $testrun      = model('TestrunDB')->resultset('Testrun')->find({id => $testrun_id},{ result_class => 'DBIx::Class::ResultClass::HashRefInflator' });
        my $job          = model('TestrunDB')->resultset('TestrunScheduling')->find({testrun_id => $testrun_id},{ result_class => 'DBIx::Class::ResultClass::HashRefInflator' });
        my $user         = model('TestrunDB')->resultset('User')->find($testrun->{owner_user_id});
        $testrun         = merge($job, $testrun);
        $testrun->{user} = $user ? $user->login : 'unknown';
        return $testrun;
}

=head2 get_report_data

Get all neccessary report data related to given report id.

@param int - report id

@return hash ref - report data

=cut

sub get_report_data
{
        my ($self, $report_id) = @_;
        my $report = model('ReportsDB')->resultset('Report')->find($report_id);
        my $report_hash = Tapper::Reports::DPath::_as_data($report);
        return $report_hash;
}

=head2 get_testrun_success

Get the overall success of the testrun with given id. If an error
occurs, the function returns undef. This is most probably because the
given testrun has no reports and thus no testrun stats can be found.

@param int - testrun id

@return success - success rate in percent
@return error   - undef

=cut

sub get_testrun_success
{
        my ($testrun_id) = @_;
        my $stats = model('ReportsDB')->resultset('ReportgroupTestrunStats')->search({testrun_id => $testrun_id});
        return undef if not $stats->count;
        return ($stats->first->success_ratio == 100) ? 'pass' : 'fail';
}

=head2 testrun_success_change

Return whether the last given testruns of a given condition have a
different success state as the current one.

@param string - search string to define matching testruns
@param int    - number of testruns to look back

@return boolean - success change (yes/no)?

=cut

sub testrun_success_change
{
        my ($search, $lookback) = @_;
        my $testruns = model('TestrunDB')->resultset('Testrun')->search($search);
        my $success;
        while ($lookback-- and my $this_testrun = $testruns->next) {
                # the testrun that triggered this check is not part of the backlog since we want
                # to check its success against the success of the testruns before this one
                do {$lookback++, next} if $this_testrun->id == $testrun->{id};
                my $this_success = get_testrun_success($this_testrun->id);
                # this testrun has no reports, ignore it and don't count it against lookback
                do {$lookback++, next} if not defined $this_success;

                $success = $this_success if not defined($success);
                # last $lookback tests did not have the same success state
                return 0 if not $this_success ~~ $success;
        }
        my $testrun_success = get_testrun_success($testrun->{id});

        return 1 if defined($testrun_success) and defined($success) and $testrun_success ne $success;
        return 0;
}

=head2 matches

Check whether the given notification condition matches on the given
event, i.e. whether we need to notify the user.

@param string - condition
@param Result::NotificationEvent - event

@return true/false based on condition

=cut

sub matches
{
        my ($self, $condition, $event) = @_;
        given($event->type){
                when ('testrun_finished') {
                        $testrun             = $self->get_testrun_data($event->message->{testrun_id});
                }
                when ('report_received')  {
                        $report       = $self->get_report_data($event->message->{report_id});
                };
                default { return };
        }

        my $le = Language::Expr->new;
        $le->interpreted(1);

        $le->var('report' => $report, 'testrun' => $testrun);
        $le->func(testrun     => sub { return ( @_ ? $testrun->{$_[0]} : $testrun ) if $testrun });
        $le->func(report      => sub { return ( @_ ? $report->{$_[0]}  : $report  ) if $report  });
        $le->func(deep_search => sub { return dpath($_[1])->match($_[0]) } );
        $le->func(reportdata  => sub { return reportdata @_ } );
        $le->func(testrun_success_change  => sub { testrun_success_change @_ });

        my $success;

        # # FIXME: testrun_success_change triggers a bug in perl. As soon as this bug is fixed we can switch
        # # to using Language::Expr for all functions
        # if ($condition =~ m/^testrun_success_change(.+)/) {
        #         $success = eval "testrun_success_change($1)";
        # } else {
        #         $success = $le->eval($condition);
        # }
        $success = $le->eval($condition);

        return  $success;
}

=head2 notify_user

Send notification to user.

@param Result::Notification - subscription that triggered the notification

=cut

sub notify_user
{
        my ($self, $subscription) = @_;
        my $text = $subscription->comment;
        if (not $text) {
                $text = "Your notification subscription matched a Tapper event.\n".
                  "The following subscription was triggered:\n\n".
                    "Event type: ".$subscription->event.
                      "\nCondition: ".$subscription->condition."\n";
        }


        my $contact      = $subscription->user->contacts->first;
        my $plugin       = ucfirst($contact->protocol);
        my $plugin_class = "Tapper::Notification::Plugin::${plugin}";
        eval "use $plugin_class"; ## no critic

        if ($@) {
                $self->log->error( "Could not load $plugin_class: $@" );
        } else {
                try{
                no strict 'refs'; ## no critic
                $self->log->info("Call ${plugin_class}::notify()");
                my $cfg = $self->cfg->{notification}{sender}{plugins}{$plugin};
                my $obj = ${plugin_class}->new({cfg => $cfg});
                $obj->notify($contact->address, $text);
                } catch {
                        $self->log->error("Error occured: $_");
                }
        }

        return;
}

=head2 run

Run the Notification daemon once.

=cut

sub run
{
        my ($self) = @_;

        my $events = $self->get_events;
        while (my $event = $events->next) {
                my $subscriptions = $self->get_subscriptions($event->type);
                while (my $subscription = $subscriptions->next) {
                        if ($self->matches($subscription->condition, $event)) {


                                $self->notify_user($subscription);
                        }
                        $subscription->delete unless $subscription->persist;
                }
                $event->delete;
        }
        return;
}

=head2 loop

Run the Notification daemon in an endless loop.

=cut

sub loop
{
        my ($self) = @_;
        while () {
                $self->run();
                sleep $self->cfg->{times}{notification_poll_intervall} || 1;
        }
}


=head1 AUTHOR

AMD OSRC Tapper Team, C<< <tapper at amd64.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-tapper-notification at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Tapper-Notification>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Tapper::Notification


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Tapper-Notification>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Tapper-Notification>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Tapper-Notification>

=item * Search CPAN

L<http://search.cpan.org/dist/Tapper-Notification/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2011 AMD OSRC Tapper Team, all rights reserved.

This program is released under the following license: freebsd


=cut

1; # End of Tapper::Notification
