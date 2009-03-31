package CatalystX::Usul::PersistentState;

# @(#)$Id: PersistentState.pm 403 2009-03-28 04:09:04Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Base);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 403 $ =~ /\d+/gmx );

my $NUL = q();

sub get_key {
   my ($self, $c, $name) = @_; my $ckeys = $c->stash->{ckeys};

   return exists $ckeys->{ $name } ? $ckeys->{ $name } : $NUL;
}

sub load_keys {
   # Recover the previous key field values for the requested
   # controller. Select the first true value from; the request
   # parameters, the session store, a default value as defined
   # in the config and loaded into the stash
   my ($self, $c) = @_; my ($conf_keys, $val);

   my $s = $c->stash; my $model = $c->model( q(Base) );

   if ($conf_keys = $s->{keys}->{ $s->{form}->{name} }) {
      my $session = $c->session->{ $self->session_key( $c ) };

      $self->reset_keys( $c ); # Clear the per request keys

      while (my ($key, $conf) = each %{ $conf_keys->{vals} }) {
         unless (defined ($val = $model->query_value( $key ))) {
            unless (defined ($val = $session->{ $key })) {
               if (($val = $conf->{key})
                   && ($val =~ m{ \[% \s+ (.*) \s+ %\] }msx)) {
                  $val = $s->{ $1 } if ($1);
               }

               $val ||= $NUL;
            }
         }

         $self->set_key( $c, $key, $val ); # This will persist across requests
      }
   }

   return;
}

sub reset_keys {
   my ($self, $c) = @_; $c->stash( ckeys => {} ); return;
}

sub session_key {
   my ($self, $c) = @_; return $c->action->namespace || q(root);
}

sub set_key {
   # Save the value in the session for this controller
   my ($self, $c, $name, $val) = @_;

   return $self->get_key( $c, $name ) unless (defined $val);

   my $skey = $self->session_key( $c );

   $c->stash->{ckeys}->{ $name } = $c->session->{ $skey }->{ $name } = $val;

   return $val;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::PersistentState - Set/Get state information on/from the session store

=head1 Version

0.1.$Revision: 403 $

=head1 Synopsis

   use CatalystX::Usul::PersistentState;

=head1 Description

Uses the session store to provide state information that is persistent across
requests

=head1 Subroutines/Methods

=head2 get_key

   my $value = $self->get_key( $c, $key_name );

Returns a value for a given key from stash which was populated by
L</load_keys>

=head2 load_keys

Recovers the key(s) for the current endpoint. First it will look at
then request parameters, if they are not set it will look in the
session store, if that is not set then it will use the
configuration defaults if they exist, inflating values from the stash if
necessary

=head2 reset_keys

   $self->reset_keys( $c );

Resets this requests keys in the stash

=head2 session_key

   $self->session_key( $c );

Returns the session store key for the current controller

=head2 set_key

   $self->set_key( $c, $key_name, $value );

Sets a key/value pair in the session store

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Base>

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
