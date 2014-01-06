# @(#)Ident: 10compile.t 2013-08-19 18:56 pjf ;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.15.%d', q$Rev: 1 $ =~ /\d+/gmx );
use File::Spec::Functions   qw( catdir updir );
use FindBin                 qw( $Bin );
use lib                 catdir( $Bin, updir, 'lib' );

use Module::Build;
use Test::More;

my $notes = {}; my $perl_ver;

BEGIN {
   my $builder = eval { Module::Build->current };
      $builder and $notes = $builder->notes;
      $perl_ver = $notes->{min_perl_version} || 5.008;
}

use Test::Requires "${perl_ver}";

use_ok 'CatalystX::Usul::Constraints';
use_ok 'CatalystX::Usul::Model';
use_ok 'CatalystX::Usul::View';
use_ok 'CatalystX::Usul::Controller';
use_ok 'CatalystX::Usul::Admin';
use_ok 'CatalystX::Usul::Model::Navigation';
use_ok 'CatalystX::Usul::Controller::Root';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
