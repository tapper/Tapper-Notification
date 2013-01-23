package Tapper::Notification::Daemon;

use 5.010;

use strict;
use warnings;

use Tapper::Notification;
use Moose;
use Tapper::Config;
use Log::Log4perl;

with 'MooseX::Daemonize';


after start => sub {
                    my $self = shift;

                    return unless $self->is_daemon;

                    my $logconf = Tapper::Config->subconfig->{files}{log4perl_cfg};
                    Log::Log4perl->init($logconf);

                    $self->initialize_server;
                    $self->server->server_loop;
                   }
;

=head2 initialize_server

Initialize and start daemon according to config.

=cut

sub initialize_server
{
        my $self = shift;

        my $daemon = Tapper::Notification->new;
        $daemon->loop;
}
;

=head2 run

Frontend to subcommands: start, status, restart, stop.

=cut

sub run
{
        my $self = shift;

        my ($command) = @ARGV ? @ARGV : @_;
        return unless $command && grep /^$command$/, qw(start status restart stop);
        $self->$command;
        say $self->status_message;
}
;


1;
