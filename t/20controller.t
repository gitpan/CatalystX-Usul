# @(#)$Id: 20controller.t 1116 2012-03-11 23:05:42Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1116 $ =~ /\d+/gmx );
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
