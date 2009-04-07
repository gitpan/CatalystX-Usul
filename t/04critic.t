#!/usr/bin/perl

# @(#)$Id: 04critic.t 430 2009-04-06 20:00:20Z pjf $

use strict;
use warnings;
use File::Spec::Functions;
use FindBin  qw( $Bin );
use Test::More;

BEGIN {
   if (!-e catfile( $Bin, updir, q(MANIFEST.SKIP) )) {
      plan skip_all => 'Critic test only for developers';
   }
}

eval { require Test::Perl::Critic };

plan skip_all => 'Test::Perl::Critic not installed' if ($@);

unless ($ENV{TEST_CRITIC}) {
   plan skip_all => 'Environment variable TEST_CRITIC not set';
}

Test::Perl::Critic->import( -profile => catfile( q(t), q(critic.rc) ) );

all_critic_ok();

# Local Variables:
# mode: perl
# tab-width: 3
# End:
