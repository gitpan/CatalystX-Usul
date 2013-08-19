# @(#)$Ident: 20controller.t 2013-08-19 19:03 pjf ;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );
use File::Spec::Functions   qw( catdir catfile updir );
use FindBin                 qw( $Bin );
use lib                 catdir( $Bin, updir, 'lib' ), catdir( $Bin, 'lib' );

use Module::Build;
use Test::More;

my $notes = {}; my $perl_ver;

BEGIN {
   my $builder = eval { Module::Build->current };
      $builder and $notes = $builder->notes;
      $perl_ver = $notes->{min_perl_version} || 5.008;
}

use Test::Requires "${perl_ver}";
use Catalyst::Test 'MyApp';

my (undef, $context) = ctx_request( q() );

my $controller = $context->controller( 'Root' );

isa_ok $controller, 'MyApp::Controller::Root';

$controller->begin( $context ); my $s = $context->stash;

ok $s->{application} eq 'MyApp', 'Loads default config';

#$controller->dumper( $context->stash );

done_testing;

unlink catfile( qw( t ipc_srlock.lck ) );
unlink catfile( qw( t ipc_srlock.shm ) );
unlink catfile( qw( t controller.log ) );

# Local Variables:
# mode: perl
# tab-width: 3
# End:
