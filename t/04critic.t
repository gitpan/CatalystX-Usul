# @(#)$Id: 04critic.t 485 2009-05-21 22:49:51Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 485 $ =~ /\d+/gmx );
use File::Spec::Functions;
use FindBin qw( $Bin );
use lib catdir( $Bin, updir, q(lib) );

use English qw(-no_match_vars);
use Test::More;

BEGIN {
   if (!-e catfile( $Bin, updir, q(MANIFEST.SKIP) )) {
      plan skip_all => 'Critic test only for developers';
   }
}

eval { require Test::Perl::Critic; };

plan skip_all => 'Test::Perl::Critic not installed' if ($EVAL_ERROR);

unless ($ENV{TEST_CRITIC}) {
   plan skip_all => 'Environment variable TEST_CRITIC not set';
}

Test::Perl::Critic->import( -profile => catfile( q(t), q(critic.rc) ) );

all_critic_ok();

# Local Variables:
# mode: perl
# tab-width: 3
# End:
