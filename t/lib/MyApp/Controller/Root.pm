package MyApp::Controller::Root;

use Moose;

BEGIN { extends q(CatalystX::Usul::Controller) }

__PACKAGE__->config->{namespace} = '';

sub default : Path {}

1;
