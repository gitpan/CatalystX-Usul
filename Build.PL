# @(#)$Id: Build.PL 1320 2013-07-31 17:31:20Z pjf $

use strict;
use warnings;
use inc::Bob; # Module::Build subclass
use version; our $VERSION = qv( sprintf '0.8.%d', q$Rev: 1320 $ =~ /\d+/gmx );

Bob->new( {
   module    => q(CatalystX::Usul),
   home_page => q(http://www.roxsoft.co.uk),
   requires  => {
      'perl'                                       => 5.01,
      'namespace::autoclean'                       => 0.13,
      'namespace::sweep'                           => 0.006,
      'Catalyst'                                   => 5.9002,
      'Catalyst::Action::RenderView'               => 0.16,
      'Catalyst::Model::DBIC::Schema'              => 0.48,
      'Catalyst::Plugin::Authentication'           => 0.10016,
      'Catalyst::Plugin::ConfigComponents'         => q(0.6.0),
      'Catalyst::Plugin::ConfigLoader'             => 0.19,
      'Catalyst::Plugin::InflateMore'              => q(0.5.0),
      'Catalyst::Plugin::Session'                  => 0.31,
      'Catalyst::Plugin::Session::State::Cookie'   => 0.17,
      'Catalyst::Plugin::Session::Store::FastMmap' => 0.14,
      'Catalyst::Plugin::Static::Simple'           => 0.30,
      'Catalyst::Plugin::StatusMessage'            => 1.002000,
      'Catalyst::View::TT'                         => 0.36,
      'CatalystX::Component::Traits'               => 0.16,
      'Class::Null'                                => 2.101420,
      'Class::Usul'                                => q(0.21.3),
      'Crypt::Eksblowfish'                         => 0.009,
      'Data::Pageset'                              => 1.06,
      'Data::Serializer'                           => 0.53,
      'Data::Validation'                           => q(0.10.0),
      'DBIx::Class'                                => 0.08009,
      'Email::Sender'                              => 0.093380,
      'Email::MIME'                                => 1.906,
      'Encode'                                     => 2.12,
      'Encode::Guess'                              => 2.00,
      'File::DataClass'                            => q(0.20.10),
      'File::Gettext'                              => q(0.18.0),
      'File::MailAlias'                            => q(0.16.0),
      'File::UnixAuth'                             => q(0.16.0),
      'HTML::FillInForm'                           => 2.00,
      'HTML::FormWidgets'                          => q(0.18.0),
      'HTML::Parser'                               => 3.69,
      'HTTP::Date'                                 => 6.02,
      'HTTP::Message'                              => 6.06,
      'IO::Interactive'                            => q(0.0.6),
      'Imager'                                     => 0.90,
      'JSON'                                       => 2.50,
      'MIME::Types'                                => 1.31,
      'Moo'                                        => 1.002000,
      'Moose'                                      => 2.0802,
      'MooseX::AttributeShortcuts'                 => 0.014,
      'MooseX::Types'                              => 0.35,
      'MooseX::Types::LoadableClass'               => 0.008,
      'MooX::Options'                              => 3.83,
      'Parse::HTTP::UserAgent'                     => 0.33,
      'PPI'                                        => 1.215,
      'PPI::HTML'                                  => 1.08,
      'SQL::Translator'                            => 0.11016,
      'Sub::Exporter'                              => 0.982,
      'Template'                                   => 2.22,
      'Time::Elapsed'                              => 0.29,
      'TryCatch'                                   => 1.003000,
      'XML::Simple'                                => 2.18, },
   recommends                   => {
      'App::cpanminus'          => 1.6005,
      'Crypt::PassGen'          => 0.05,
      'GD::SecurityImage'       => 1.70,
      'IPC::Run'                => 0.84,
      'Pod::ProjectDocs'        => 0.36,
      'Syntax::Highlight::Perl' => 1.00, },
   configure_requires           => {
      'version'                 => 0.88,
      'Module::Build'           => 0.4004, },
   build_requires               => {
      'version'                 => 0.88,
      'Module::Build'           => 0.4004,
      'Class::Null'             => 1.09, },
} )->create_build_script; # Goal!

# Local Variables:
# eval: (load-project-state "catalystx-usul")
# mode: perl
# tab-title: CX::Usul
# tab-width: 3
# End:
