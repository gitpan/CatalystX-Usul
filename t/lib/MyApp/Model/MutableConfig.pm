package MyApp::Model::MutableConfig;

use strict;

use Moose;

extends qw(CatalystX::Usul::Model::Config);

has '+keys_attr' => writer => '_set_keys_attr';

__PACKAGE__->meta->make_immutable;

no Moose;

1;
