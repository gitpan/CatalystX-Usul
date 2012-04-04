# @(#)$Id: 18programs.t 1165 2012-04-03 10:40:39Z pjf $

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
}

use_ok q(CatalystX::Usul::Programs);

my $prog = CatalystX::Usul::Programs->new( {
   config  => { appldir   => File::Spec->curdir,
                localedir => catdir( qw(t locale) ) },
   homedir => q(t), n => 1 } );

my $meta = $prog->get_meta( q(META.yml) );

ok $meta->name eq q(CatalystX-Usul), 'meta file class';

unlink $prog->logfile;

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
