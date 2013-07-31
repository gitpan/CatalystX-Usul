# @(#)Ident: 10compile.t 2013-06-23 01:32 pjf ;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 1319 $ =~ /\d+/gmx );
use File::Spec::Functions   qw( catdir updir );
use FindBin                 qw( $Bin );
use lib                 catdir( $Bin, updir, 'lib' );

use Module::Build;
use Test::More;

my $reason;

BEGIN {
   my $builder = eval { Module::Build->current };

   $builder and $reason = $builder->notes->{stop_tests};
   $reason  and $reason =~ m{ \A TESTS: }mx and plan skip_all => $reason;
}

use_ok 'CatalystX::Usul::Constraints';
use_ok 'CatalystX::Usul::Model';
use_ok 'CatalystX::Usul::View';
use_ok 'CatalystX::Usul::Controller';
use_ok 'CatalystX::Usul::Admin';
use_ok 'CatalystX::Usul::Model::Navigation';
use_ok 'CatalystX::Usul::Controller::Root';

done_testing;

#SKIP: {
#   $reason and $reason =~ m{ \A tests: }mx and skip $reason, 1;
#}

# Local Variables:
# mode: perl
# tab-width: 3
# End:
