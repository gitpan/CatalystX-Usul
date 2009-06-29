# @(#)$Id: 11utils.t 606 2009-06-26 07:14:36Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 606 $ =~ /\d+/gmx );
use File::Spec::Functions;
use FindBin qw( $Bin );
use lib catdir( $Bin, updir, q(lib) );

use Exception::Class ( q(TestException) => { fields => [ qw(args) ] } );
use English qw( -no_match_vars );
use File::Basename;
use File::Spec::Functions qw( tmpdir );
use Test::More;

BEGIN {
   if ($ENV{AUTOMATED_TESTING} || $ENV{PERL_CR_SMOKER_CURRENT}
       || ($ENV{PERL5OPT} || q()) =~ m{ CPAN-Reporter }mx) {
      plan skip_all => q(CPAN Testing stopped);
   }

   plan tests => 4;
}

use_ok q(CatalystX::Usul::Programs);

my $ref = CatalystX::Usul::Programs->new( n => 1 );

ok( $ref->child_list( $PID ) == 1, q(child_list) );

ok( $ref->run_cmd( q(echo "Hello World") )->out eq q(Hello World),
    q(run_cmd) );

my $path = catfile( tmpdir, basename( $PROGRAM_NAME, q(.t) ).q(.log) );

ok( -f $path, q(log_file) );

unlink $path;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
