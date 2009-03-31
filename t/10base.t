#!/usr/bin/perl

# @(#)$Id: 10base.t 411 2009-03-30 23:05:17Z pjf $

use strict;
use warnings;
use English qw(-no_match_vars);
use Exception::Class ( q(TestException) => { fields => [ qw(arg1 arg2) ] } );
use File::Spec::Functions;
use FindBin  qw( $Bin );
use lib (catdir( $Bin, updir, q(lib) ));
use Test::More;

BEGIN {
#   if ($ENV{AUTOMATED_TESTING} || $ENV{PERL_CR_SMOKER_CURRENT}
#       || ($ENV{PERL5OPT} || q()) =~ m{ CPAN-Reporter }mx
#       || ($ENV{PERL5_CPANPLUS_IS_RUNNING} && $ENV{PERL5_CPAN_IS_RUNNING})) {
#      plan skip_all => q(CPAN Testing stopped);
#   }

   plan tests => 18;
}

use_ok q(CatalystX::Usul);

my $ref = CatalystX::Usul->new();

ok( $ref->is_member( 2, 1, 2, 3 ), q(is_member) );

ok( $ref->str2time( q(2007-07-30 01:05:32), q(BST) )
    eq q(1185753932), q(str2time/1) );

ok( $ref->str2time( q(30/7/2007 01:05:32), q(BST) )
    eq q(1185753932), q(str2time/2) );

ok( $ref->str2time( q(30/7/2007), q(BST) ) eq q(1185750000),
    q(str2time/3) );

ok( $ref->str2time( q(2007.07.30), q(BST) ) eq q(1185750000),
    q(str2time/4) );

ok( $ref->str2time( q(1970/01/01), q(GMT) ) eq q(0), q(str2time/epoch) );

ok( $ref->time2str( q(%Y-%m-%d), 0 ) eq q(1970-01-01), q(time2str/1) );

ok( $ref->time2str( q(%Y-%m-%d %H:%M:%S), 1185753932 )
    eq q(2007-07-30 01:05:32), q(time2str/2) );

ok( q().$ref->str2date_time( q(11/9/2007 14:12) )
    eq q(2007-09-11T13:12:00), q(str2date_time) );

my $prefix = $ref->app_prefix( q(Test::Application) );

ok( $prefix eq q(test_application), q(app_prefix) );

eval { $ref->throw( error => q(eNoMessage) ) };
my $e = $ref->catch();

ok( $e->as_string eq q(eNoMessage), q(try/throw/catch) );

my $appl = $ref->home2appl( q(/opt/myapp/v0.1/lib/MyApp) );

ok( $appl eq q(/opt/myapp/v0.1), q(home2appl) );

my $tempfile = $ref->tempfile;

ok( $tempfile, q(call/tempfile) );

$ref->io( $tempfile->pathname )->touch;

ok( -f $tempfile->pathname, q(touch/tempfile) );

$ref->delete_tmp_files;

ok( ! -f $tempfile->pathname, q(delete_tmp_files) );

ok( $ref->unescape_TT( $ref->escape_TT( q([% test %]) ) ) eq q([% test %]),
    q(escape_TT/unscape_TT));

my $io = $ref->io( q(t) ); my $entry;

while (defined ($entry = $io->next)) {
   last if ($entry->filename eq q(10base.t));
}

ok( (defined $entry and $entry->filename eq q(10base.t)), q(IO::next) );

# Local Variables:
# mode: perl
# tab-width: 3
# End:
