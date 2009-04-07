#!/usr/bin/perl

# @(#)$Id: 14config.t 434 2009-04-07 19:11:38Z pjf $

use strict;
use warnings;
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

   plan tests => 13;
}

{
   package MyApp;

   use Catalyst qw(ConfigComponents);

   __PACKAGE__->config
      ( "Model::Config"          => {
           base_class            => q(CatalystX::Usul::Model::Config),
           schema_attributes     => {
              storage_attributes => { class => q(XML::Simple) } } },
        "Model::Config::Levels"  => {
           base_class            => q(CatalystX::Usul::Model::Config::Levels),
           schema_attributes     => {
              storage_attributes => { class => q(XML::Simple) } } } );

   __PACKAGE__->setup;
}

$ENV{REMOTE_ADDR} = '127.0.0.1';
$ENV{SERVER_NAME} = 'localhost';
$ENV{SERVER_PORT} = '80';

my $context = MyApp->prepare;

$context->stash( lang => q(en), messages => {}, newtag => q(..New..) );

my $model = $context->model( q(Config) );

isa_ok( $model, 'MyApp::Model::Config' );

my $cfg = $model->load_files( qw(t/default.xml t/default_en.xml) );

ok( $cfg->{ '_cvs_default' } =~ m{ @\(\#\)\$Id: }mx,
    'Has reference element 1' );
ok( $cfg->{ '_cvs_lang_default' } =~ m{ @\(\#\)\$Id: }mx,
    'Has reference element 2' );
ok( ref $cfg->{levels}->{entrance}->{acl} eq q(ARRAY), 'Detects arrays' );

eval { $model->create_or_update }; my $e = $model->catch;

ok( $e->as_string eq q(eNoFile), 'Detects misssin file parameter' );

my $args = {}; $args->{file} = q(t/default.xml);

eval { $model->create( $args ) }; $e = $model->catch;

ok( $e->as_string eq q(eNoName), 'Detects misssin name parameter' );

$model = $context->model( q(Config::Levels) );

isa_ok( $model, 'MyApp::Model::Config::Levels' );

$args->{name} = q(dummy);

eval { $model->create( $args ) }; $e = $model->catch;

ok ( !$e, 'Creates dummy level' );

$cfg = $model->load_files( qw(t/default.xml t/default_en.xml) );

ok( $cfg->{levels}->{dummy}->{acl}->[ 0 ] eq q(any), 'Dummy level defaults' );

eval { $model->create( $args ) }; $e = $model->catch;

ok( $e->as_string eq q(eAlreadyExists), 'Detects existing record' );

eval { $model->delete( $args ) }; $e = $model->catch;

ok ( !$e, 'Deletes dummy level' );

eval { $model->delete( $args ) }; $e = $model->catch;

ok( $e->as_string eq q(eNotUpdated), 'Detects non existance on delete' );

my @res = $model->search( q(t/default.xml), { acl => q(@support) } );

ok( $res[ 0 ] && $res[ 0 ]->{name} eq q(admin), 'Can search' );

# Local Variables:
# mode: perl
# tab-width: 3
# End:
