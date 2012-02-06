use strict;
use warnings;

use inc::Module::Install;

name     'Tapper-Notification';
all_from 'lib/Tapper/Notification.pm';
author   'AMD OSRC Tapper Team <tapper@amd64.org>';
license  'freebsd';

author_requires 'Module::Install::WriteAll';

build_requires 'Test::More';
build_requires 'Test::Perl::Critic'          => 0;

requires 'Tapper::Base';
requires 'Tapper::Config' => '3.000010';
requires 'App::Daemon';
requires 'Try::Tiny';
auto_install;

install_script glob('bin/*');


WriteAll;

