#!/usr/bin/perl

# @(#)$Id: 11utils.t 411 2009-03-30 23:05:17Z pjf $

use strict;
use warnings;
use English qw(-no_match_vars);
use Exception::Class ( q(TestException) => { fields => [ qw(arg1 arg2) ] } );
use File::Spec::Functions;
use FindBin  qw( $Bin );
use lib (catdir( $Bin, updir, q(lib) ));
use Test::More;

BEGIN {
#   if ($ENV{AUTOMATED_TESTING} || $ENV{PERL_CR_SMOKER_CURRENT}
#       || ($ENV{PERL5OPT} || q()) =~ m{ CPAN-Reporter }mx
#       || ($ENV{PERL5_CPANPLUS_IS_RUNNING} && $ENV{PERL5_CPAN_IS_RUNNING})) {
#      plan skip_all => q(CPAN Testing stopped);
#   }

   plan tests => 3;
}

use_ok q(CatalystX::Usul::Programs);

my $ref = CatalystX::Usul::Programs->new( n => 1 );

ok( $ref->child_list( $PID ) == 1, q(child_list) );

ok( $ref->run_cmd( q(echo "Hello World") )->out eq q(Hello World),
    q(run_cmd) );

# Local Variables:
# mode: perl
# tab-width: 3
# End:
