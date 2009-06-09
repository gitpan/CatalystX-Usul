# @(#)$Id: Identity.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::Model::Identity;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model);

use CatalystX::Usul::Model::Roles;
use CatalystX::Usul::Model::Users;
use Class::C3;
use Scalar::Util qw(weaken);

__PACKAGE__->mk_accessors( qw(auth_comp role_class roles user_class
                              users _auth_realms _default_realm ) );

sub new {
   my ($self, $app, @rest) = @_;

   my $new = $self->next::method( $app, @rest );

   $new->auth_realms  ( $app, $new->auth_comp );
   $new->default_realm( $app, $new->auth_comp );

   return $new;
}

sub aliases {
   return shift->users->aliases;
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

   $new->roles( $c->model( $new->role_class ) );
   $new->users( $c->model( $new->user_class ) );

   $new->roles->auth_realms( $new->auth_realms );
   $new->users->auth_realms( $new->auth_realms );

   $new->roles->users( $new->users ); weaken( $new->roles->{users} );
   $new->users->roles( $new->roles ); weaken( $new->users->{roles} );

   $new->roles->role_domain->user_domain( $new->users->user_domain );
   $new->users->user_domain->role_domain( $new->roles->role_domain );

   weaken( $new->roles->role_domain->{user_domain} );
   weaken( $new->users->user_domain->{role_domain} );

   $new->users->profiles->roles( $new->roles );

   weaken( $new->users->profiles->{roles} );

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

sub profiles {
   return shift->users->profiles;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Identity - Identity model with multiple backend stores

=head1 Version

0.1.$Revision: 562 $

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

=head2 aliases

Returns instance of I<MailAliases> class

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

=head2 profiles

Returns instance of I<UserProfiles> class

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::Model::MailAliases>

=item L<CatalystX::Usul::Model::Roles>

=item L<CatalystX::Usul::Model::UserProfiles>

=item L<CatalystX::Usul::Model::Users>

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
