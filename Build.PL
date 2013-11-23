# @(#)$Ident: Build.PL 2013-08-26 21:23 pjf ;

use strict;
use warnings;

use Module::Build 0.4004;

sub whimper { print {*STDOUT} $_[ 0 ]."\n"; exit 0 }

my $perl_ver = 5.010001;
my $name     = 'CatalystX-Usul'; $name =~ s{ - }{::}gmx;

$] >= $perl_ver or $ENV{PERL5_CPANPLUS_IS_VERSION}
   or whimper "Minimum required Perl version is ${perl_ver}";

Module::Build->subclass( code => do { local $/; <DATA> } )->new(
  'module_name' => $name,
  'notes'       => { min_perl_version => $perl_ver },
  'build_requires' => {
    'Class::Null' => '1.09',
    'Module::Build' => '0.4004',
    'Test::Requires' => '0.06',
    'version' => '0.88'
  },
  'configure_requires' => {
    'Module::Build' => '0.4004',
    'version' => '0.88'
  },
  'recommends' => {
    'App::cpanminus' => '1.6005',
    'Crypt::PassGen' => '0.05',
    'GD::SecurityImage' => '1.70',
    'IPC::Run' => '0.84',
    'Pod::ProjectDocs' => '0.36',
    'Syntax::Highlight::Perl' => '1.00'
  },
  'requires' => {
    'Catalyst' => '5.9002',
    'Catalyst::Action::RenderView' => '0.16',
    'Catalyst::Model::DBIC::Schema' => '0.48',
    'Catalyst::Plugin::Authentication' => '0.10016',
    'Catalyst::Plugin::ConfigComponents' => 'v0.8.0',
    'Catalyst::Plugin::ConfigLoader' => '0.19',
    'Catalyst::Plugin::InflateMore' => 'v0.7.0',
    'Catalyst::Plugin::Session' => '0.31',
    'Catalyst::Plugin::Session::State::Cookie' => '0.17',
    'Catalyst::Plugin::Session::Store::FastMmap' => '0.14',
    'Catalyst::Plugin::Static::Simple' => '0.30',
    'Catalyst::Plugin::StatusMessage' => '1.002000',
    'Catalyst::View::TT' => '0.36',
    'CatalystX::Component::Traits' => '0.16',
    'Class::Load' => '0.18',
    'Class::Null' => '2.101420',
    'Class::Usul' => 'v0.33.0',
    'Crypt::Eksblowfish' => '0.009',
    'DBIx::Class' => '0.08009',
    'Data::Pageset' => '1.06',
    'Data::Serializer' => '0.53',
    'Data::Validation' => 'v0.14.0',
    'Email::MIME' => '1.906',
    'Email::Sender' => '0.093380',
    'Encode' => '2.12',
    'Encode::Guess' => '2.00',
    'File::DataClass' => 'v0.25.0',
    'File::Gettext' => 'v0.20.0',
    'File::MailAlias' => 'v0.19.0',
    'File::UnixAuth' => 'v0.19.0',
    'HTML::FillInForm' => '2.00',
    'HTML::FormWidgets' => 'v0.21.0',
    'HTML::Parser' => '3.69',
    'HTTP::Date' => '6.02',
    'HTTP::Message' => '6.06',
    'IO::Interactive' => 'v0.0.6',
    'Imager' => '0.90',
    'Import::Into' => '1.001000',
    'JSON' => '2.50',
    'MIME::Types' => '1.31',
    'Moo' => '1.003000',
    'Moose' => '2.0802',
    'MooseX::AttributeShortcuts' => '0.014',
    'MooseX::Types' => '0.35',
    'MooseX::Types::Common' => '0.001008',
    'MooseX::Types::LoadableClass' => '0.008',
    'PPI' => '1.215',
    'PPI::HTML' => '1.08',
    'Parse::HTTP::UserAgent' => '0.33',
    'SQL::Translator' => '0.11016',
    'Sub::Exporter' => '0.982',
    'Template' => '2.22',
    'Time::Elapsed' => '0.29',
    'TryCatch' => '1.003000',
    'XML::Simple' => '2.18',
    'namespace::autoclean' => '0.13',
    'namespace::sweep' => '0.006',
    'perl' => '5.010001'
  },

)->create_build_script;

exit 0;

__DATA__

sub _normalize_prereqs { # Dynamic config
   my $self = shift; my $p = $self->SUPER::_normalize_prereqs; return $p;
}
