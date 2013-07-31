# @(#)$Id: 20controller.t 1290 2012-10-31 01:42:57Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.8.%d', q$Rev: 1290 $ =~ /\d+/gmx );
use File::Spec::Functions;
use FindBin qw( $Bin );
use lib catdir( $Bin, updir, q(lib) ), catdir( $Bin, q(lib) );

use Module::Build;
use Test::More;

BEGIN {
   my $current = eval { Module::Build->current };

   $current and $current->notes->{stop_tests}
            and plan skip_all => $current->notes->{stop_tests};
}

use Catalyst::Test q(MyApp);

my (undef, $context) = ctx_request( '' );

my $controller = $context->controller( q(Root) );

isa_ok $controller, q(MyApp::Controller::Root);

$controller->begin( $context ); my $s = $context->stash;

ok $s->{application} eq q(MyApp), 'Loads default config';

#$controller->dumper( $context->stash );

done_testing;

unlink catfile( qw(t ipc_srlock.lck) );
unlink catfile( qw(t ipc_srlock.shm) );
unlink catfile( qw(t controller.log) );

# Local Variables:
# mode: perl
# tab-width: 3
# End:
