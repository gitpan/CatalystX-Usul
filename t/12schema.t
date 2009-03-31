#!/usr/bin/perl

# @(#)$Id: 12schema.t 411 2009-03-30 23:05:17Z pjf $

use strict;
use warnings;
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

use_ok q(CatalystX::Usul::Schema);

my $ref = CatalystX::Usul::Schema->new();

ok( $ref->connect_info( q(t/test.xml), q(library), q(munchies) )->[0] eq q(dbi:mysql:database=library;host=localhost;port=3306), q(connect_info) );

my $encrypted = $ref->encrypt( q(munchies), q(test) );

ok( $ref->decrypt( q(munchies), $encrypted ) eq q(test), q(encrypt/decrypt) );

# Local Variables:
# mode: perl
# tab-width: 3
# End:
