package CatalystX::Usul::Plugin::Controller::TokenValidation;

# @(#)$Id: TokenValidation.pm 403 2009-03-28 04:09:04Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 403 $ =~ /\d+/gmx );

my $NUL = q();

sub add_token {
   # Add the CSRF token to the form
   my ($self, $c) = @_; my ($minted, $mtoken, $seed, $token);

   my $s       = $c->stash;
   my $name    = $s->{token};
   my $max_age = $c->config->{max_token_age} || 900;

   # There are two implementations differentiated by $max_age < 0
   if ($max_age > 0) {
      # This method does not use the session store so it's browser tab safe
      $minted = $self->stamp;
      $seed   = $minted.q(_).$s->{form}->{action}.q(_).$s->{user};
      $token  = $self->create_token( $self->secret.$seed );
      $mtoken = $minted.q(_).$token;
   }
   else { $token = $mtoken = $c->session->{ $name } = $self->create_token }

   # Add the token to the current form as a hidden field
   $c->model( q(Base) )->add_hidden( $name, $mtoken );

   $self->log_debug( "Added token $token" ) if ($s->{debug});
   return;
}

sub end {
   my ($self, $c) = @_; $self->add_token( $c ) if $c->stash->{token}; return;
}

sub remove_token {
   # Delete the CSRF token from the request parameters
   my ($self, $c) = @_; my $name;

   return unless ($name = $c->config->{token});

   delete $c->req->params->{ $name };
   return;
}

sub validate_token {
   # Test if the CSRF toke in the session store matches the one in the req.
   my ($self, $c) = @_; my $s = $c->stash; my ($name, $token);

   return unless ($name = $c->config->{token});

   my $request = $c->model( q(Base) )->query_value( $name ) || $NUL;
   my $max_age = $c->config->{max_token_age} || 900;

   if ($max_age > 0) {
      my $now    = time;
      my $minted = (split m{ _ }mx, $request)[0] || $NUL;
      my $then   = $minted ? $self->str2time( $minted ) : $now;
      my $seed   = $minted.q(_).$s->{form}->{action}.q(_).$s->{user};

      if ($now - $then > $max_age) {
         $self->log_info( "Token too old $seed" );
         return 0;
      }

      $token = $minted.q(_).$self->create_token( $self->secret.$seed );
   }
   else { $token = $c->session->{ $name } }

   return 1 unless ($token);

   my $res = $request eq $token;

   if ($s->{debug} && !$res) {
      $self->log_debug( "Received token $request" );
      $self->log_debug( "Expected token $token" );
   }

   return $res;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Plugin::Controller::TokenValidation - CSRF form tokens

=head1 Version

0.1.$Revision: 403 $

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

=head2 end

Called by the end method in the base controller, this method calls
L</add_token> if the current page should contain a token

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

Copyright (c) 2008 Peter Flanigan. All rights reserved

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
