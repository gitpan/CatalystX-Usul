# @(#)$Id: 23time.t 1181 2012-04-17 19:06:07Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.7.%d', q$Rev: 1181 $ =~ /\d+/gmx );
use File::Spec::Functions;
use FindBin qw( $Bin );
use lib catdir( $Bin, updir, q(lib) );

use Class::Null;
use Exception::Class ( q(TestException) => { fields => [ qw(arg1 arg2) ] } );
use English qw( -no_match_vars );
use Module::Build;
use Test::More;

BEGIN {
   my $current = eval { Module::Build->current };

   $current and $current->notes->{stop_tests}
            and plan skip_all => $current->notes->{stop_tests};
}

use Math::BigInt;

Math::BigInt->config()->{lib} eq q(Math::BigInt::GMP)
   and plan skip_all => 'Math::BigInt::GMP installed RT#33816';

use CatalystX::Usul::Time qw(str2date_time str2time time2str);

ok time2str( undef, 0 ) eq q(1970-01-01 01:00:00), 'stamp';

my $dt = q().str2date_time( q(11/9/2007 14:12), q(GMT) );

ok $dt eq q(2007-09-11T14:12:00), 'str2date_time';

$dt ne q(2007-09-11T14:12:00) and warn "str2date_time is ${dt}\n";

ok str2time( q(2007-07-30 01:05:32), q(BST) ) eq q(1185753932), 'str2time/1';

ok str2time( q(30/7/2007 01:05:32), q(BST) ) eq q(1185753932), 'str2time/2';

ok str2time( q(30/7/2007), q(BST) ) eq q(1185750000), 'str2time/3';

ok str2time( q(2007.07.30), q(BST) ) eq q(1185750000), 'str2time/4';

ok str2time( q(1970/01/01), q(GMT) ) eq q(0), 'str2time/epoch';

ok time2str( q(%Y-%m-%d), 0 ) eq q(1970-01-01), 'time2str/1';

ok time2str( q(%Y-%m-%d %H:%M:%S), 1185753932, q(BST) )
   eq q(2007-07-30 01:05:32), 'time2str/2';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
