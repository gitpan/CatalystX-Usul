# @(#)$Id: 22file.t 1165 2012-04-03 10:40:39Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
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

   plan tests => 19;
}

use_ok 'CatalystX::Usul';

my $cu = CatalystX::Usul->new( Class::Null->new, { tempdir => q(t) } );

isa_ok $cu, 'CatalystX::Usul'; is $cu->tempdir, q(t), 'tempdir';

my $tf = [ qw(t test.xml) ];

ok( (grep { m{ name }msx } $cu->io( $tf )->getlines)[ 0 ] =~ m{ library }msx,
    'io' );

ok -d $cu->abs_path( $Bin, catdir( updir, q(lib) ) ), 'abs_path';

is $cu->basename( $cu->tempdir ), q(t), 'basename';

ok -d $cu->catdir( qw(t locale) ), 'catdir';

ok -f $cu->catfile( @{ $tf } ), 'catfile';

ok $cu->classfile( 'CatalystX::Usul' ) =~ m{ Usul\.pm }msx, 'classfile';

is $cu->dirname( $tf ), q(t), 'dirname';

my $fdcs = $cu->file_dataclass_schema->load( $tf );

is $fdcs->{credentials}->{library}->{driver}, q(mysql), 'file_dataclass_schema';

unlink catfile( qw(t ipc_srlock.lck) );
unlink catfile( qw(t ipc_srlock.shm) );

ok $cu->find_source( 'CatalystX::Usul' ) =~ m{ Usul\.pm \z }msx, 'find_source';

is $cu->status_for( $tf )->{size}, 237, 'status_for';

my $symlink = catfile( qw(t symlink) );

$cu->symlink( q(t), q(test.xml), [ qw(t symlink) ] );

ok -e $symlink, 'symlink'; -e _ and unlink $symlink;

my $tempfile = $cu->tempfile;

ok( $tempfile, q(call/tempfile) );

is ref $tempfile->io_handle, q(File::Temp), 'tempfile';

$cu->io( $tempfile->pathname )->touch;

ok( -f $tempfile->pathname, q(touch/tempfile) );

$cu->delete_tmp_files;

ok( ! -f $tempfile->pathname, q(delete_tmp_files) );

ok $cu->tempname =~ m{ $PID .{4} }msx, 'tempname';

# Local Variables:
# mode: perl
# tab-width: 3
# End:
