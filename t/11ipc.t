# @(#)$Id: 11ipc.t 1147 2012-03-30 14:07:07Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1147 $ =~ /\d+/gmx );
use File::Spec::Functions qw( catdir catfile tmpdir updir );
use FindBin qw( $Bin );
use lib catdir( $Bin, updir, q(lib) );

use English qw( -no_match_vars );
use File::Basename;
use Module::Build;
use Test::More;

BEGIN {
   my $current = eval { Module::Build->current };

   $current and $current->notes->{stop_tests}
            and plan skip_all => $current->notes->{stop_tests};
}

use_ok q(CatalystX::Usul::Programs);

my $perl = $^X;
my $ref  = CatalystX::Usul::Programs->new( {
   config  => { appldir   => File::Spec->curdir,
                localedir => catdir( qw(t locale) ) },
   homedir => q(t), n => 1 } );
my $cmd  = "${perl} -e 'print \"Hello World\"'";

ok $ref->run_cmd( $cmd )->out eq q(Hello World), 'run_cmd system';

$cmd = "${perl} -e 'exit 1'";

eval { $ref->run_cmd( $cmd ) }; my $error = $EVAL_ERROR;

ok $error, 'run_cmd system unexpected rv';

ok ref $error eq $ref->exception_class, 'exception is right class';

ok $ref->run_cmd( $cmd, { expected_rv => 1 } ), 'run_cmd system expected rv';

$cmd = [ $perl, '-e', 'print "Hello World"' ];

ok $ref->run_cmd( $cmd )->out eq "Hello World", 'run_cmd IPC::Run';

eval { $ref->run_cmd( [ $perl, '-e', 'exit 1' ] ) };

ok $EVAL_ERROR, 'run_cmd IPC::Run unexpected rv';

ok $ref->run_cmd( [ $perl, '-e', 'exit 1' ], { expected_rv => 1 } ),
   'run_cmd IPC::Run expected rv';

eval { $ref->run_cmd( "unknown_command_xa23sd3" ) }; $error = $EVAL_ERROR;

ok $error =~ m{ unknown_command }mx, 'unknown command';

my $path = catfile( $ref->tempdir, basename( $PROGRAM_NAME, q(.t) ).q(.log) );

ok -f $path, 'log_file';

unlink $path;

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
