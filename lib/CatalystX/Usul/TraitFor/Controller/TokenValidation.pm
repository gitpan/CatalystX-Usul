# @(#)Ident: TokenValidation.pm 2013-10-19 17:46 pjf ;

package CatalystX::Usul::TraitFor::Controller::TokenValidation;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.17.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Moose::Role;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw( create_token );
use Class::Usul::Time          qw( str2time time2str );

requires qw( end redirect_to_path usul );

around 'end' => sub {
   my ($next, $self, $c, @args) = @_;

   exists $c->action->attributes->{ 'NoToken' }
      or $self->_add_validation_token( $c, @args );

   return $self->$next( $c, @args );
};

around 'redirect_to_path' => sub {
   my ($next, $self, $c, @args) = @_; delete $c->stash->{token};

   return $self->$next( $c, @args );
};

sub remove_token {
   # Delete the CSRF token from the request parameters
   my ($self, $c) = @_; my $name = $c->config->{token} or return;

   delete $c->req->params->{ $name };
   return;
}

sub validate_token {
   # Test if the CSRF token in the session store matches the one in the req.
   my ($self, $c) = @_; my $s = $c->stash; my $token;

   my $name    = $c->config->{token} or return;
   my $request = $self->_model( $c )->query_value( $name ) || NUL;
   my $max_age = $c->config->{max_token_age} || 900;

   if ($max_age > 0) {
      my $now    = time;
      my $minted = (split m{ _ }mx, $request)[ 0 ] || NUL;
      my $then   = $minted ? str2time( $minted ) : $now;
      my $salt   = $self->usul->config->salt;
      my $seed   = "${minted}_${salt}_".$s->{user}->username;

      if ($now - $then > $max_age) {
         $self->log->info( "Token too old ${minted}" );
         $self->remove_token( $c ); return FALSE;
      }

      $token = "${minted}_".__create_token( $seed );
   }
   else { $token = $c->session->{ $name } }

   $token or return TRUE; my $res = $request eq $token;

   if ($s->{debug} and not $res) {
      $self->log->debug( "Received token ${request}" );
      $self->log->debug( "Expected token ${token}" );
   }

   $self->remove_token( $c );
   return $res;
}

# Private methods
sub _add_validation_token { # Add the CSRF token to the form
   my ($self, $c) = @_; my ($mtoken, $token);

   my $s       = $c->stash;
   my $name    = $s->{token} or return;
   my $max_age = $c->config->{max_token_age} || 900;

   # There are two implementations differentiated by $max_age < 0
   if ($max_age > 0) {
      # This method does not use the session store so it's browser tab safe
      my $minted = time2str();
      my $salt   = $self->usul->config->salt;
      my $seed   = "${minted}_${salt}_".$s->{user}->username;

      $token = __create_token( $seed ); $mtoken = "${minted}_${token}";
   }
   else { $token = $mtoken = $c->session->{ $name } = __create_token() }

   # Add the token to the current form as a hidden field
   $self->_model( $c )->add_hidden( $name, $mtoken );
   $s->{debug} and $self->log->debug( "Added token ${mtoken}" );
   return;
}

sub _model {
   return $_[ 1 ]->model( $_[ 0 ]->config_class );
}

# Private functions
sub __create_token {
   return substr create_token( $_[ 0 ] ), 0, 32;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Plugin::Controller::TokenValidation - CSRF form tokens

=head1 Version

Describes v0.17.$Rev: 1 $

=head1 Synopsis

   # In custom action class
   if ($controller->can( q(validate_token) ) && _should_validate( $c )) {
      unless ($controller->validate_token( $c )) {
         return $self->_invalid_token( @args )
            ? $self->next::method( @rest ) : undef;
      }

      $controller->remove_token( $c );
   }

=head1 Description

Generates and validates CSRF form tokens

=head1 Configuration and Environment

Requires; C<end> and C<redirect_to_path> methods

Controller methods with the C<NoToken> code attribute do not have a token
added

=head1 Subroutines/Methods

=head2 _add_validation_token

Around the controller C<end> method, adds a CSRF token to the form

=head2 remove_token

Removes the validated token from the form so that it is not mistaken
for a regular input field

=head2 validate_token

Checks to see if the token stored in the session matches the one posted
back in the form

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul::Time>

=item L<Moose::Role>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Author

Peter Flanigan, C<< <Support at RoxSoft.co.uk> >>

=head1 License and Copyright

Copyright (c) 2014 Peter Flanigan. All rights reserved

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE

=cut

# Local Variables:
# mode: perl
# tab-width: 3
# End:
