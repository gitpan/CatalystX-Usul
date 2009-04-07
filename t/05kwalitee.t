#!/usr/bin/perl

# @(#)$Id: 12schema.t 108 2008-06-03 18:21:07Z pjf $

use strict;
use warnings;
use File::Spec::Functions;
use FindBin  qw( $Bin );
use Test::More;

BEGIN {
   if (!-e catfile( $Bin, updir, q(MANIFEST.SKIP) )) {
      plan skip_all => 'Kwalitee test only for developers';
   }
}

eval { require Test::Kwalitee; };

plan skip_all => 'Test::Kwalitee not installed' if ($@);

Test::Kwalitee->import();

# Local Variables:
# mode: perl
# tab-width: 3
# End:
