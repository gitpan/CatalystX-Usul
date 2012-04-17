# @(#)$Id: 10functions.t 1181 2012-04-17 19:06:07Z pjf $

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
use File::Spec;
use Test::More;

BEGIN {
   my $current = eval { Module::Build->current };

   $current and $current->notes->{stop_tests}
            and plan skip_all => $current->notes->{stop_tests};
}

use CatalystX::Usul::Functions qw(:all);

ok app_prefix( q(Test::Application) ) eq q(test_application), 'app_prefix';

my $list = arg_list( 'key1' => 'value1', 'key2' => 'value2' );

ok $list->{key2} eq q(value2), 'arg_list';

ok class2appdir( q(App::Munchies) ) eq q(app-munchies), 'class2appdir';

ok distname( q(App::Munchies) ) eq q(App-Munchies), 'distname';

ok env_prefix( q(App::Munchies) ) eq q(APP_MUNCHIES), 'env_prefix';

ok unescape_TT( escape_TT( q([% test %]) ) ) eq q([% test %]),
   'escape_TT/unscape_TT';

ok home2appl( catdir( qw(opt myapp v0.1 lib MyApp) ) )
   eq catdir( qw(opt myapp v0.1) ), 'home2appl';

ok is_arrayref( [] ), 'is_arrayref - true';
ok ! is_arrayref( {} ), 'is_arrayref - false';

ok is_hashref( {} ), 'is_hashref - true';
ok ! is_hashref( [] ), 'is_hashref - false';

ok is_member( 2, 1, 2, 3 ), 'is_member - true';
ok ! is_member( 4, 1, 2, 3 ), 'is_member - false';

my $src  = { 'key2' => 'value2', }; my $dest = {};

merge_attributes $dest, $src, { 'key1' => 'value3', }, [ 'key1', 'key2', ];

ok $dest->{key1} eq q(value3), 'merge_attributes - default';
ok $dest->{key2} eq q(value2), 'merge_attributes - source';

ok my_prefix( catfile( 'dir', 'prefix_name' ) ) eq 'prefix', 'my_prefix';

ok product( 1, 2, 3, 4 ) == 24, 'product';

ok strip_leader( q(test: dummy) ) eq q(dummy), 'strip_leader';

ok sum( 1, 2, 3, 4 ) == 10, 'sum';

ok trim( q(  test string  ) ) eq q(test string), 'trim';

use_ok q(CatalystX::Usul);

use CatalystX::Usul::Functions qw(create_token throw);

my $ref = CatalystX::Usul->new( Class::Null->new, {
   config => { localedir => catfile( qw(t locale) ) } } );

ok $ref->basename( catfile( qw(fake root dummy) ) ) eq q(dummy), 'basename';

eval { throw( error => q(eNoMessage) ) }; my $e = $@;

ok $e->as_string =~ m{ eNoMessage }msx, 'try/throw/catch';

ok $ref->catdir( q(dir1), q(dir2) ) =~ m{ dir1 . dir2 }mx, 'catdir';

ok $ref->catfile( q(dir1), q(file1) ) =~ m{ dir1 . file1 }mx, 'catfile';

ok $ref->classfile( q(App::Munchies) ) eq catfile( qw(App Munchies.pm) ),
   'classfile';

my $token = create_token( q(test) );

ok $token eq q(ee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db27ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff)
   || $token
      eq q(9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08)
   || $token eq q(a94a8fe5ccb19ba61c4c0873d391e987982fbbd3)
   || $token eq q(098f6bcd4621d373cade4e832627b4f6), 'create_token';

ok $ref->dirname( catfile( qw(dir1 file1) ) ) eq q(dir1), 'dirname';

my $io = $ref->io( q(t) ); my $entry;

while (defined ($entry = $io->next)) {
   $entry->filename eq q(10functions.t) and last;
}

ok defined $entry && $entry->filename eq q(10functions.t), 'IO::next';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
