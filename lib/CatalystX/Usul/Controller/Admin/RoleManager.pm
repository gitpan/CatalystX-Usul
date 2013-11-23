# @(#)Ident: ;

package CatalystX::Usul::Controller::Admin::RoleManager;

use strict;
use version; our $VERSION = qv( sprintf '0.14.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;

BEGIN { extends q(CatalystX::Usul::Controller) }

with q(CatalystX::Usul::TraitFor::Controller::ModelHelper);
with q(CatalystX::Usul::TraitFor::Controller::PersistentState);

__PACKAGE__->config( namespace => q(admin), );

sub role_base : Chained(common) PathPart(users) CaptureArgs(0) {
   my ($self, $c) = @_;

   $c->stash->{role_params} = $self->get_uri_query_params( $c );

   return $self->stash_identity_model( $c );
}

sub role_manager : Chained(role_base) Args HasActions {
   my ($self, $c, $role) = @_; return $c->stash->{role_model}->form( $role );
}

sub role_manager_delete : ActionFor(role_manager.delete) {
   my ($self, $c) = @_; my $s = $c->stash;

   $s->{role_model}->delete; $self->set_uri_args( $c, $s->{newtag} );
   return TRUE;
}

sub role_manager_insert : ActionFor(role_manager.insert) {
   my ($self, $c) = @_;

   $self->set_uri_args( $c, $c->stash->{role_model}->create );
   return TRUE;
}

sub role_manager_update : ActionFor(role_manager.update) {
   my ($self, $c) = @_; return $c->stash->{role_model}->update_users;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin::RoleManager - Maintains role membership

=head1 Version

Describes v0.14.$Rev: 1 $

=head1 Synopsis

   package YourApp::Controller::Admin;

   use CatalystX::Usul::Moose;

   BEGIN { extends q(CatalystX::Usul::Controller::Admin) }

   __PACKAGE__->build_subcontrollers;

=head1 Description

Adds/removes users to/from roles (groups). Works for multiple authentication
realms

=head1 Subroutines/Methods

=head2 role_base

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

=item L<CatalystX::Usul::TraitFor::Controller::ModelHelper>

=item L<CatalystX::Usul::TraitFor::Controller::PersistentState>

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

Copyright (c) 2013 Peter Flanigan. All rights reserved

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
