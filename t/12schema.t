# @(#)$Id: 12schema.t 1290 2012-10-31 01:42:57Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.8.%d', q$Rev: 1290 $ =~ /\d+/gmx );
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

use MyApp;
use CatalystX::Usul::Model::Schema;

my $class = q(CatalystX::Usul::Model::Schema);
my $attr  = { ctlfile  => q(t/test.json),
              database => q(library),
              prefix   => q(munchies),
              tempdir  => q(t), };
my $dsn   = q(dbi:mysql:database=library;host=localhost;port=3306);

is $class->get_connect_info( 'MyApp', $attr )->[ 0 ], $dsn, 'Connect info';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
