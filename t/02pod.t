#!/usr/bin/perl

# @(#)$Id: 02pod.t 334 2008-12-20 02:50:09Z pjf $

use strict;
use warnings;
use Test::More;

eval { use Test::Pod 1.14; };

plan skip_all => 'Test::Pod 1.14 required' if ($@);

all_pod_files_ok();

# Local Variables:
# mode: perl
# tab-width: 3
# End:
