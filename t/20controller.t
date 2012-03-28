# @(#)$Id: 20controller.t 1139 2012-03-28 23:49:18Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1139 $ =~ /\d+/gmx );
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

isa_ok( $controller, q(MyApp::Controller::Root) );

done_testing;

unlink q(/tmp/ipc_srlock.lck);
unlink q(/tmp/ipc_srlock.shm);

# Local Variables:
# mode: perl
# tab-width: 3
# End: