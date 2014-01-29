# @(#)Ident: 13traits.t 2014-01-09 16:35 pjf ;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.35.%d', q$Rev: 1 $ =~ /\d+/gmx );
use File::Spec::Functions   qw( catdir catfile updir );
use FindBin                 qw( $Bin );
use lib                 catdir( $Bin, updir, 'lib' );

use Test::More;
use Test::Requires { version => 0.88 };
use Module::Build;

my $notes = {}; my $perl_ver;

BEGIN {
   my $builder = eval { Module::Build->current };
      $builder and $notes = $builder->notes;
      $perl_ver = $notes->{min_perl_version} || 5.008;
}

use Test::Requires         "${perl_ver}";
use Class::Usul::Functions qw( exception );
use File::Basename         qw( basename );

{  package MyLCProg;

   use Moo;

   extends 'Class::Usul::Programs';
   with    'CatalystX::Usul::TraitFor::LoadingClasses';

   1;
}

my $name    = basename( $0, qw( .t ) );
my $logfile = catfile( 't', "${name}.log" );
my $prog    = MyLCProg->new( appclass => 'Class::Usul',
                             config   => { logsdir => 't', tempdir => 't', },
                             method   => 'dump_self',
                             noask    => 1,
                             quiet    => 1, );

$prog->build_subcomponents( 'Class::Usul::Config' );

is $prog->config->pwidth, 60, 'build_subcomponents';

$prog->setup_plugins;

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
