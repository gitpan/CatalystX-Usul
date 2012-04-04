package MyApp::Controller::Root;

use Moose;

BEGIN { extends q(CatalystX::Usul::Controller) }

__PACKAGE__->config->{namespace} = '';

sub default : Path {}

sub about : Chained(/) Args(0) Public {
   my ($self, $c) = @_; $self->set_popup( $c, q(close) );

   return $c->model( $self->help_class )->form;
}

sub help : Chained(/) Args Public {
   return shift->next::method( @_ );
}


1;
