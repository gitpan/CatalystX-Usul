#!/usr/bin/perl

# @(#)$Id: 03podcoverage.t 344 2009-01-17 12:31:02Z pjf $

use strict;
use warnings;
use File::Spec::Functions;
use FindBin  qw( $Bin );
use lib (catdir( $Bin, updir, q(lib) ));
use Test::More;

if (!-e catfile( $Bin, updir, q(MANIFEST.SKIP) )) {
   plan skip_all => 'POD coverage test only for developers';
}

eval { use Test::Pod::Coverage 1.04; };

plan skip_all => 'Test::Pod::Coverage 1.04 required' if ($@);

all_pod_coverage_ok();

# Local Variables:
# mode: perl
# tab-width: 3
# End:
