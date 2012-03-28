# @(#)$Id: 10functions.t 1097 2012-01-28 23:31:29Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1097 $ =~ /\d+/gmx );
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

   plan tests => 21;
}

use CatalystX::Usul::Functions qw(app_prefix arg_list class2appdir distname env_prefix product escape_TT unescape_TT home2appl is_member strip_leader sum trim);

ok( app_prefix( q(Test::Application) ) eq q(test_application), q(app_prefix) );

my $list = arg_list( 'key1' => 'value1', 'key2' => 'value2' );

ok( $list->{key2} eq q(value2), q(arg_list) );

ok( class2appdir( q(App::Munchies) ) eq q(app-munchies),
    q(class2appdir) );

ok( distname( q(App::Munchies) ) eq q(App-Munchies), q(distname) );

ok( env_prefix( q(App::Munchies) ) eq q(APP_MUNCHIES), q(env_prefix) );

ok( unescape_TT( escape_TT( q([% test %]) ) ) eq q([% test %]),
    q(escape_TT/unscape_TT));

ok( home2appl( catdir( qw(opt myapp v0.1 lib MyApp) ) )
    eq catdir( qw(opt myapp v0.1) ), q(home2appl) );

ok( is_member( 2, 1, 2, 3 ), q(is_member) );

ok( product( 1, 2, 3, 4) == 24, q(product) );

ok( strip_leader( q(test: dummy) ) eq q(dummy), q(strip_leader) );

ok( sum( 1, 2, 3, 4 ) == 10, q(sum) );

ok( trim( q(  test string  ) ) eq q(test string), q(trim) );

use_ok q(CatalystX::Usul);

use CatalystX::Usul::Functions qw(create_token throw);

my $ref = CatalystX::Usul->new( Class::Null->new, {
   config => { localedir => catfile( qw(t locale) ) } } );

ok( $ref->basename( catfile( qw(fake root dummy) ) ) eq q(dummy),
    q(basename) );

eval { throw( error => q(eNoMessage) ) }; my $e = $@;

ok( $e->as_string =~ m{ eNoMessage }msx, q(try/throw/catch) );

ok( $ref->catdir( q(dir1), q(dir2) ) =~ m{ dir1 . dir2 }mx, q(catdir) );

ok( $ref->catfile( q(dir1), q(file1) ) =~ m{ dir1 . file1 }mx, q(catfile) );

ok( $ref->classfile( q(App::Munchies) ) eq catfile( qw(App Munchies.pm) ),
    q(classfile) );

my $token = create_token( q(test) );

ok( $token eq q(ee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db27ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff)
    || $token
       eq q(9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08)
    || $token eq q(a94a8fe5ccb19ba61c4c0873d391e987982fbbd3)
    || $token eq q(098f6bcd4621d373cade4e832627b4f6),
    q(create_token) );

ok( $ref->dirname( catfile( qw(dir1 file1) ) ) eq q(dir1), q(dirname) );

my $io = $ref->io( q(t) ); my $entry;

while (defined ($entry = $io->next)) {
   last if ($entry->filename eq q(10functions.t));
}

ok( (defined $entry and $entry->filename eq q(10functions.t)), q(IO::next) );

# Local Variables:
# mode: perl
# tab-width: 3
# End:
