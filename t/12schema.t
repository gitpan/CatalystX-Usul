# @(#)$Id: 12schema.t 582 2009-06-12 11:04:32Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 582 $ =~ /\d+/gmx );
use File::Spec::Functions;
use FindBin qw( $Bin );
use lib catdir( $Bin, updir, q(lib) );

use Test::More;

BEGIN {
   if ($ENV{AUTOMATED_TESTING} || $ENV{PERL_CR_SMOKER_CURRENT}
       || ($ENV{PERL5OPT} || q()) =~ m{ CPAN-Reporter }mx) {
      plan skip_all => q(CPAN Testing stopped);
   }

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
