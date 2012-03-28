# @(#)$Id: 11ipc.t 1139 2012-03-28 23:49:18Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1139 $ =~ /\d+/gmx );
use File::Spec::Functions qw( catdir catfile tmpdir updir );
use FindBin qw( $Bin );
use lib catdir( $Bin, updir, q(lib) );

use English qw( -no_match_vars );
use File::Basename;
use Module::Build;
use Test::More;

BEGIN {
   my $current = eval { Module::Build->current };

   $current and $current->notes->{stop_tests}
            and plan skip_all => $current->notes->{stop_tests};

   plan tests => 8;
}

use_ok q(CatalystX::Usul::Programs);

my $ref = CatalystX::Usul::Programs->new( {
   config  => { appldir   => File::Spec->curdir,
                localedir => catdir( qw(t locale) ) },
   homedir => q(t), n => 1 } );

ok( $ref->run_cmd( q(echo "Hello World") )->out eq q(Hello World),
    q(run_cmd system) );

eval { $ref->run_cmd( q(false) ) };

ok( $EVAL_ERROR, q(run_cmd system unexpected rv) );

ok( $ref->run_cmd( q(false), { expected_rv => 1 } ),
    q(run_cmd system expected rv) );

ok( $ref->run_cmd( [ q(echo), "Hello World" ] )->out eq q(Hello World),
    q(run_cmd IPC::Run) );

eval { $ref->run_cmd( [ q(false) ] ) };

ok( $EVAL_ERROR, q(run_cmd IPC::Run unexpected rv) );

ok( $ref->run_cmd( [ q(false) ], { expected_rv => 1 } ),
    q(run_cmd IPC::Run expected rv) );

my $path = catfile( $ref->tempdir, basename( $PROGRAM_NAME, q(.t) ).q(.log) );

ok( -f $path, q(log_file) );

unlink $path;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
