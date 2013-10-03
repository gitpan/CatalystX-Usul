# @(#)$Ident: 14config.t 2013-08-19 19:04 pjf ;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.13.%d', q$Rev: 1 $ =~ /\d+/gmx );
use File::Spec::Functions   qw( catdir catfile updir );
use FindBin                 qw( $Bin );
use lib                 catdir( $Bin, updir, 'lib' ), catdir( $Bin, 'lib' );

use Module::Build;
use Test::More;

my $notes = {}; my $perl_ver;

BEGIN {
   my $builder = eval { Module::Build->current };
      $builder and $notes = $builder->notes;
      $perl_ver = $notes->{min_perl_version} || 5.008;
}

use Test::Requires "${perl_ver}";
use English qw( -no_match_vars );
use Catalyst::Test 'MyApp';

my (undef, $context) = ctx_request( '/' );

$context->stash( language => q(de), newtag  => q(..New..) );

my $model = $context->model( q(MutableConfig) );

isa_ok $model, 'MyApp::Model::MutableConfig';

my $cfg = $model->load( q(default) );

like $cfg->{ '_vcs_default' }, qr{ @\(\#\)\$Id: }mx, 'Has reference element 1';

is ref $cfg->{namespace}->{entrance}->{acl}, q(ARRAY), 'Detects arrays';

eval { $model->create_or_update }; my $e = $EVAL_ERROR; $EVAL_ERROR = undef;

like $e->as_string, qr{ Result \s+ source \s+ not \s+ specified }msx,
    'Result source not specified';

$model->_set_keys_attr( q(an_element_name) );

eval { $model->create_or_update }; $e = $EVAL_ERROR; $EVAL_ERROR = undef;

like $e->as_string, qr{ Result \s+ source \s+ an_element_name \s+ unknown }msx,
    'Result source an_element_name unknown';

$model->_set_keys_attr( q(globals) );

eval { $model->create_or_update }; $e = $EVAL_ERROR; $EVAL_ERROR = undef;

like $e->as_string, qr{ Config \s+ file \s+ name \s+ not \s+ specified }msx,
    'File path not specified';

my $file = q(default); eval { $model->create_or_update( $file ) };

$e = $EVAL_ERROR; $EVAL_ERROR = undef;

like $e->as_string, qr{ No \s+ element \s+ name \s+ specified }msx,
    'No element name specified';

$model = $context->model( q(Config::Levels) );

isa_ok $model, 'MyApp::Model::Config::Levels';

my $args = {}; my $name;

eval { $name = $model->create_or_update( $file, q(dummy) ) };

$e = $EVAL_ERROR; $EVAL_ERROR = undef;

ok !$e, 'Creates dummy level';
is $name, q(dummy), 'Returns element name on create';

$cfg = $model->load( qw(default) );

my $acl = $cfg->{namespace}->{dummy}->{acl}->[0];

is $acl, q(any), 'Dummy namespace defaults';

eval { $model->create_or_update( $file, q(dummy) ) };

$e = $EVAL_ERROR; $EVAL_ERROR = undef;

like $e, qr{ element \s+ dummy \s+ already \s+ exists }msx,
    'Detects existing record';

eval { $model->delete( $file, $name ) };

$e = $EVAL_ERROR; $EVAL_ERROR = undef;

ok !$e, 'Deletes dummy namespace'; $e and warn "${e}\n";

eval { $model->delete( $file, $name ) };

$e = $EVAL_ERROR; $EVAL_ERROR = undef;

like $e, qr{ element \s+ dummy \s+ does \s+ not \s+ exist }msx,
    'Detects non existance on delete';

my @res = $model->search( $file, { acl => q(@support) } );

is $res[0]->{name}, q(admin), 'Can search';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
