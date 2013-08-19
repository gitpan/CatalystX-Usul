# @(#)$Ident: 12schema.t 2013-08-19 19:04 pjf ;

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
