# @(#)$Id: 11ipc.t 1181 2012-04-17 19:06:07Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.7.%d', q$Rev: 1181 $ =~ /\d+/gmx );
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

use CatalystX::Usul::Programs;
use CatalystX::Usul::Constants qw(EXCEPTION_CLASS);

{  package Logger;

   sub new {
      return bless {}, q(Logger);
   }

   sub AUTOLOAD {
      my $self = shift; warn ''.(join ' ', @_);
   }

   sub DESTROY {}
}

my $perl = $EXECUTABLE_NAME;
my $prog = CatalystX::Usul::Programs->new( {
   config  => { appldir   => File::Spec->curdir,
                localedir => catdir( qw(t locale) ),
                tempdir   => q(t), },
   homedir => q(t),
   log     => Logger->new,
   n       => 1, } );
my $cmd  = "${perl} -e 'print \"Hello World\"'";

is $prog->run_cmd( $cmd )->out, q(Hello World), 'run_cmd system';

$cmd = "${perl} -e 'exit 1'";

eval { $prog->run_cmd( $cmd ) }; my $error = $EVAL_ERROR;

ok $error, 'run_cmd system unexpected rv';

is ref $error, EXCEPTION_CLASS, 'exception is right class';

ok $prog->run_cmd( $cmd, { expected_rv => 1 } ), 'run_cmd system expected rv';

$cmd = [ $perl, '-e', 'print "Hello World"' ];

is $prog->run_cmd( $cmd )->out, "Hello World", 'run_cmd IPC::Run';

eval { $prog->run_cmd( [ $perl, '-e', 'exit 1' ] ) };

ok $EVAL_ERROR, 'run_cmd IPC::Run unexpected rv';

ok $prog->run_cmd( [ $perl, '-e', 'exit 1' ], { expected_rv => 1 } ),
   'run_cmd IPC::Run expected rv';

# This fails on some platforms. The stderr is not redirected as expected
#eval { $prog->run_cmd( "unknown_command_xa23sd3", { debug => 1 } ) };

#ok $EVAL_ERROR =~ m{ unknown_command }mx, 'unknown command';

my $path = catfile( $prog->tempdir, basename( $PROGRAM_NAME, q(.t) ).q(.log) );

-f $path and unlink $path;

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
