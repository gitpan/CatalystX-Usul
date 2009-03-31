package CatalystX::Usul::Model::Identity;

# @(#)$Id: Identity.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Model);
use CatalystX::Usul::Model::MailAliases;
use CatalystX::Usul::Model::UserProfiles;
use Class::C3;
use Scalar::Util qw(weaken);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

__PACKAGE__->mk_accessors( qw(aliases auth_comp profiles role_class
                              roles shells user_class users
                              _auth_realms _default_realm ) );

sub new {
   my ($self, $app, @rest) = @_;

   my $new = $self->next::method( $app, @rest );

   my $auth_realms   = $new->auth_realms  ( $app, $new->auth_comp );
   my $default_realm = $new->default_realm( $app, $new->auth_comp );

   $new->aliases( CatalystX::Usul::Model::MailAliases->new( $app, @rest ) );

   my $profile_class = q(CatalystX::Usul::Model::UserProfiles);

   $new->profiles( $profile_class->new( $app, @rest ) );

   my $role_class = __PACKAGE__.q(::).$new->role_class;

   $new->ensure_class_loaded( $role_class                     );
   $new->roles              ( $role_class->new( $app, @rest ) );
   $new->roles->auth_realms ( $auth_realms                    );

   my $user_class = __PACKAGE__.q(::).$new->user_class;

   $new->ensure_class_loaded( $user_class                     );
   $new->users              ( $user_class->new( $app, @rest ) );
   $new->users->auth_realms ( $auth_realms                    );

   $new->_init;

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

   my $new = $self->next::method( $c, @rest );

   $new->aliases ( $new->aliases->build_per_context_instance ( $c, @rest ) );
   $new->profiles( $new->profiles->build_per_context_instance( $c, @rest ) );
   $new->roles   ( $new->roles->build_per_context_instance   ( $c, @rest ) );
   $new->users   ( $new->users->build_per_context_instance   ( $c, @rest ) );

   $new->_init;

   return $new;
}

sub default_realm {
   my ($self, $app, $component) = @_;

   return $self->_default_realm if     ($self->_default_realm);
   return                       unless ($app and $component);

   $self->_default_realm( $app->config->{ $component }->{default_realm} );
   return $self->_default_realm;
}

sub find_user {
   my ($self, @rest) = @_; return $self->users->find_user( @rest );
}

# Private methods

sub _init {
   my $self = shift;

   $self->profiles->roles_model( $self->roles    );
   $self->roles->users_obj     ( $self->users    );
   $self->users->aliases_ref   ( $self->aliases  );
   $self->users->profiles_ref  ( $self->profiles );
   $self->users->roles_obj     ( $self->roles    );

   weaken( $self->profiles->{roles_model} );
   weaken( $self->roles->{users_obj}      );
   weaken( $self->users->{aliases_ref}    );
   weaken( $self->users->{profiles_ref}   );
   weaken( $self->users->{roles_obj}      );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Identity - Identity model with multiple backend stores

=head1 Version

0.1.$Revision: 402 $

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

=head2 new

Constructor creates instances of the subclasses. The I<roles> and I<users>
subclasses a loaded at runtime since the backend store is a config option

=head2 auth_realms

Returns a hash ref whose keys are the realm names and whose values are
the model classes

=head2 build_per_context_instance

Calls C<build_per_context_instance> on each of the subclasses; C<aliases>,
C<profiles>, C<roles>, and C<users>

=head2 default_realm

Returns the name of the default realm

=head2 find_user

Calls and returns the value from the C<find_user> method on the I<users>
subclass

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::Model::MailAliases>

=item L<CatalystX::Usul::Model::UserProfiles>

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
