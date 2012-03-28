# @(#)$Id: 16exception.t 1092 2011-12-16 20:38:17Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1092 $ =~ /\d+/gmx );
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

   plan tests => 5;
}

use_ok 'CatalystX::Usul::Programs';

my $ref = CatalystX::Usul::Programs->new( {
   config  => { appldir => File::Spec->curdir, tempdir => q(t), },
   homedir => q(t), n => 1 } );

eval { $ref->run_cmd( q(cat flap) ) }; my $error = $EVAL_ERROR;

ok( ref $error eq $ref->exception_class, 'exception is right class' );

ok( $error->rv, 'has non zero return value' );

ok( $error->message =~ m{ no \s+ such \s+ file }imx, 'message matches' );

my $path = catfile( $ref->tempdir, basename( $PROGRAM_NAME, q(.t) ).q(.log) );

ok( -f $path, 'log_file' );

unlink $path;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
