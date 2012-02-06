package Tapper::Notification;

use 5.010;
use warnings;
use strict;

use Moose;
use Tapper::Model 'model';
use Tapper::Config;
use YAML::Syck 'Load';
use Log::Log4perl;
use Try::Tiny;

extends 'Tapper::Base';

has cfg => (is => 'rw', default => sub { Tapper::Config->subconfig} );

our $VERSION = '3.000001';

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
        return 1;
}

=head2 notify_user

Send notification to user.

@param Result::Notification - subscription that triggered the notification

=cut

sub notify_user
{
        my ($self, $subscription) = @_;
        my $text = $subscription->comment || "Notification is here"; # XXX better wording

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
                        use Data::Dumper;
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
        Log::Log4perl->init($self->cfg->{files}{log4perl_cfg});

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
