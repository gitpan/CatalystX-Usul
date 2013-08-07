# @(#)$Id: 12schema.t 1323 2013-08-07 18:26:42Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.8.%d', q$Rev: 1323 $ =~ /\d+/gmx );
use File::Spec::Functions;
use FindBin qw( $Bin );
use lib catdir( $Bin, updir, q(lib) ), catdir( $Bin, q(lib) );

use Module::Build;
use Test::More;

my $reason;

BEGIN {
   my $builder = eval { Module::Build->current };

   $builder and $reason = $builder->notes->{stop_tests};
   $reason  and $reason =~ m{ \A TESTS: }mx and plan skip_all => $reason;
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
