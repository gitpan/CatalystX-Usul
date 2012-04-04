# @(#)$Id: 12schema.t 1165 2012-04-03 10:40:39Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use File::Spec::Functions;
use FindBin qw( $Bin );
use lib catdir( $Bin, updir, q(lib) );

use Module::Build;
use Test::More;

BEGIN {
   my $current = eval { Module::Build->current };

   $current and $current->notes->{stop_tests}
            and plan skip_all => $current->notes->{stop_tests};

   plan tests => 3;
}

use Class::Null;

use_ok q(CatalystX::Usul::Schema);

my $ref = q(CatalystX::Usul::Schema);

ok( $ref->get_connect_info( { ctlfile => q(t/test.xml), prefix => q(munchies), tempdir => q(t), }, q(library), )->[0] eq q(dbi:mysql:database=library;host=localhost;port=3306), q(connect_info) );

my $encrypted = $ref->encrypt( q(munchies), q(test) );

ok( $ref->decrypt( q(munchies), $encrypted ) eq q(test), q(encrypt/decrypt) );

# Local Variables:
# mode: perl
# tab-width: 3
# End:
