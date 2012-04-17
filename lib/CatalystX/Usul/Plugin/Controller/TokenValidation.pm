# @(#)$Id: TokenValidation.pm 1181 2012-04-17 19:06:07Z pjf $

package CatalystX::Usul::Plugin::Controller::TokenValidation;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.7.%d', q$Rev: 1181 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(create_token);
use CatalystX::Usul::Time qw(str2time time2str);

sub add_token {
   # Add the CSRF token to the form
   my ($self, $c) = @_; my ($mtoken, $token);

   my $s       = $c->stash;
   my $name    = $s->{token} or return;
   my $max_age = $c->config->{max_token_age} || 900;

   exists $c->action->attributes->{ q(NoToken) } and return;

   # There are two implementations differentiated by $max_age < 0
   if ($max_age > 0) {
      # This method does not use the session store so it's browser tab safe
      my $minted = time2str();
      my $seed   = $minted.q(_).$self->secret.q(_).$s->{user};

      $token  = create_token $seed;
      $mtoken = $minted.q(_).$token;
   }
   else { $token = $mtoken = $c->session->{ $name } = create_token }

   # Add the token to the current form as a hidden field
   $self->_model( $c )->add_hidden( $name, $mtoken );
   $s->{debug} and $self->log_debug( "Added token $token" );
   return;
}

sub do_not_add_token {
   my ($self, $c) = @_; return delete $c->stash->{token};
}

sub remove_token {
   # Delete the CSRF token from the request parameters
   my ($self, $c) = @_; my $name = $c->config->{token} or return;

   delete $c->req->params->{ $name };
   return;
}

sub validate_token {
   # Test if the CSRF toke in the session store matches the one in the req.
   my ($self, $c) = @_; my $s = $c->stash; my $token;

   my $name    = $c->config->{token} or return;
   my $request = $self->_model( $c )->query_value( $name ) || NUL;
   my $max_age = $c->config->{max_token_age} || 900;

   if ($max_age > 0) {
      my $now    = time;
      my $minted = (split m{ _ }mx, $request)[0] || NUL;
      my $then   = $minted ? str2time( $minted ) : $now;
      my $seed   = $minted.q(_).$self->secret.q(_).$s->{user};

      if ($now - $then > $max_age) {
         $self->log_info( "Token too old $minted" ); $self->remove_token( $c );
         return FALSE;
      }

      $token = $minted.q(_).(create_token $seed);
   }
   else { $token = $c->session->{ $name } }

   $token or return TRUE;

   my $res = $request eq $token;

   if ($s->{debug} and not $res) {
      $self->log_debug( "Received token $request" );
      $self->log_debug( "Expected token $token" );
   }

   return $res;
}

# Private methods

sub _model {
   my ($self, $c) = @_; return $c->model( $self->model_base_class );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Plugin::Controller::TokenValidation - CSRF form tokens

=head1 Version

0.7.$Revision: 1181 $

=head1 Synopsis

   # In controller base class
   sub end {
      my ($self, $c) = @_;

      if ($c->stash->{token} && $self->can( q(add_token) )) {
         $self->add_token( $c );
      }

      $c->forward( q(render) );
      return;
   }

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

=head1 Subroutines/Methods

=head2 add_token

Adds a CSRF token to the form

=head2 do_not_add_token

Deletes the I<token> attribute from the stash, thus preventing the
token from being added to the response

=head2 remove_token

Removes the validated token from the form so that it is not mistaken
for a regular input field

=head2 validate_token

Checks to see if the token stored in the session matches the one posted
back in the form

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul>

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

Copyright (c) 2011 Peter Flanigan. All rights reserved

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
