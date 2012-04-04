# @(#)$Id: Identity.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Model::Identity;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model);

use MRO::Compat;
use Scalar::Util qw(weaken);

__PACKAGE__->mk_accessors( qw(auth_comp role_class roles user_class
                              users _auth_realms _default_realm ) );

sub COMPONENT {
   my ($class, $app, $attrs) = @_;

   my $new = $class->next::method( $app, $attrs );

   $new->auth_realms  ( $app, $new->auth_comp );
   $new->default_realm( $app, $new->auth_comp );

   return $new;
}

sub auth_realms {
   my ($self, $app, $component) = @_;

   return $self->_auth_realms if     ($self->_auth_realms);
   return {}                  unless ($app and $component);

   my $realms = $app->config->{ $component }->{realms};
   my %auths  = map   { $_ => $realms->{ $_ }->{store}->{model_class} }
                keys %{ $realms };

   return $self->_auth_realms( \%auths );
}

sub build_per_context_instance {
   my ($self, $c, @rest) = @_;

   my $new   = $self->next::method( $c, @rest );
   my $roles = $new->roles( $c->model( $new->role_class ) );
   my $users = $new->users( $c->model( $new->user_class ) );

   $new->roles->auth_realms( $new->auth_realms );
   $new->users->auth_realms( $new->auth_realms );

   $new->roles->users( $users ); weaken( $new->roles->{users} );
   $new->users->roles( $roles ); weaken( $new->users->{roles} );

   $new->roles->domain_model->users( $new->users->domain_model );
   $new->users->domain_model->roles( $new->roles->domain_model );

   weaken( $new->roles->domain_model->{users} );
   weaken( $new->users->domain_model->{roles} );

   return $new;
}

sub default_realm {
   my ($self, $app, $component) = @_;

   $self->_default_realm and return $self->_default_realm;
   ($app and $component) or return;

   my $realm = $app->config->{ $component }->{default_realm};

   return $self->_default_realm( $realm );
}

sub find_user {
   my ($self, @rest) = @_; return $self->users->find_user( @rest );
}

sub get_identity_model_name {
   my ($self, $default, $realm) = @_;

   $realm ||= $self->default_realm; my $model_name;

   exists $self->auth_realms->{ $realm } or $realm = $self->default_realm;

   unless ($realm and $model_name = $self->auth_realms->{ $realm }) {
      my $msg = 'Defaulting identity model [_1]';

      $self->log_warning( $self->loc( $msg, $model_name = $default ) );
   }

   return ($model_name, $realm);
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Identity - Identity model with multiple backend stores

=head1 Version

0.6.$Revision: 1165 $

=head1 Synopsis

   package MyApp::Model::Identity;

   use base qw(CatalystX::Usul::Model::Identity);

   1;

=head1 Description

Provides an identity model with multiple backend data stores. The model
supports; create, read, update and delete operations in addition to;
authentication, password changing, password setting, account registration
and account activation

=head1 Subroutines/Methods

=head2 COMPONENT

Constructor creates instances of the subclasses. The I<roles> and I<users>
subclasses a loaded at runtime since the backend store is a config option

=head2 auth_realms

Returns a hash ref whose keys are the realm names and whose values are
the model class names

=head2 build_per_context_instance

Calls C<build_per_context_instance> on each of the subclasses; C<aliases>,
C<profiles>, C<roles>, and C<users>

=head2 default_realm

Returns the name of the default realm

=head2 find_user

Calls and returns the value from the C<find_user> method on the I<users>
subclass

=head2 get_identity_model_name

Looks the supplied realm name up in the L</auth_realms> and returns the
model class name. The realm name defaults to the I<default_realm>
attribute

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<Scalar::Util>

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
