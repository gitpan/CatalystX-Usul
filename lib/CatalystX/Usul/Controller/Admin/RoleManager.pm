package CatalystX::Usul::Controller::Admin::RoleManager;

# @(#)$Id: RoleManager.pm 401 2009-03-27 00:17:37Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Controller);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 401 $ =~ /\d+/gmx );

__PACKAGE__->config( namespace => q(admin), realm_class => q(IdentityUnix) );

__PACKAGE__->mk_accessors( qw(realm_class) );

sub roles_base : Chained(common) PathPart('') CaptureArgs(0) {
   my ($self, $c) = @_; my $s = $c->stash;

   my $model = $c->model( $self->realm_class );
   my $realm = $self->get_key( $c, q(realm) ) || $model->default_realm;
   my $class = $realm ? $model->auth_realms->{ $realm } : $self->realm_class;

   $s->{role_model} = $c->model( $class )->roles;

   my $role  = $self->get_key( $c, q(role) );

   if ($role && $role ne $s->{newtag} && !$s->{role_model}->is_role( $role )) {
      $self->set_key( $c, q(role), q() );
   }

   return;
}

sub role_manager : Chained(roles_base) Args HasActions {
   my ($self, $c, $realm, $role) = @_;

   $realm = $self->set_key( $c, q(realm), $realm );
   $role  = $self->set_key( $c, q(role),  $role  );
   $c->stash->{role_model}->form( $realm, $role );
   return;
}

sub role_manager_delete : ActionFor(role_manager.delete) {
   my ($self, $c) = @_;

   $c->stash->{role_model}->delete;
   $self->set_key( $c, q(role), $c->stash->{newtag} );
   return 1;
}

sub role_manager_insert : ActionFor(role_manager.insert) {
   my ($self, $c) = @_;

   my $role = $c->stash->{role_model}->create;

   $self->set_key( $c, q(role), $role );
   return 1;
}

sub role_manager_update : ActionFor(role_manager.update) {
   my ($self, $c) = @_;

   $c->stash->{role_model}->update( $self->get_key( $c, q(role) ) );
   return 1;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin::RoleManager - Maintains role membership

=head1 Version

0.1.$Revision: 401 $

=head1 Synopsis

   package MyApp::Controller::Admin;

   use base qw(CatalystX::Usul::Controller::Admin);

   __PACKAGE__->build_subcontrollers;

=head1 Description

Adds/removes users to/from roles (groups). Works for multiple authentication
realms

=head1 Subroutines/Methods

=head2 roles_base

Midpoint that stashes the models used by the endpoints

=head2 role_manager

Displays the list of all users and the list of users in the currently
selected role. Allows users to be moved from one list to the other

=head2 role_manager_delete

Deletes the selected role

=head2 role_manager_insert

Creates a new role

=head2 role_manager_update

Updates the membership list for the selected role

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Controller>

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
