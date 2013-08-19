# @(#)Ident: ;

package CatalystX::Usul::Controller::Admin::Navigation;

use strict;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;

BEGIN { extends q(CatalystX::Usul::Controller) }

with q(CatalystX::Usul::TraitFor::Controller::PersistentState);

__PACKAGE__->config( namespace => q(admin), );

has 'name_class'      => is => 'ro', isa => Str, default => q(Config::Rooms);

has 'namespace_class' => is => 'ro', isa => Str, default => q(Config::Levels);

has 'namespace_tag'   => is => 'ro', isa => Str, default => q(..Level..);

sub navigation_base : Chained(common) PathPart(configuration) CaptureArgs(0) {
   my ($self, $c) = @_; my $s = $c->stash;

   my $realm_model = $c->model( $self->realm_class );

   $s->{auth_models    } =
      [       map  { $c->model( $_ ) }
              map  { $realm_model->user_model_classes->{ $_ } }
             grep  { $_ ne q(default) }
        sort keys %{ $c->auth_realms } ];
   $s->{name_model     } = $c->model( $self->name_class );
   $s->{namespace_model} = $c->model( $self->namespace_class );
   return;
}

sub access_control : Chained(navigation_base) Args HasActions {
   my ($self, $c, @args) = @_;

   return $c->stash->{nav_model}->form( $self->_get_model_args( $c, @args ) );
}

sub access_control_set : ActionFor(access_control.set) {
   my ($self, $c, @args) = @_;

   my ($ns, $name, $model) = $self->_get_model_args( $c, @args );

   $model->set_state( $ns, $name );
   return TRUE;
}

sub access_control_update : ActionFor(access_control.update) {
   my ($self, $c, @args) = @_;

   my ($ns, $name, $model, $is_namespace) = $self->_get_model_args( $c, @args );
   my $prefix  = $is_namespace ? 'Namespace' : 'Action';
   my $added   = "${prefix} [_1] access for [_2] granted";
   my $deleted = "${prefix} [_1] access for [_2] revoked";

   return $model->update_list( $ns, { field      => q(user_groups),
                                      name       => $name,
                                      list       => q(acl),
                                      msgs       => {
                                         added   => $added,
                                         deleted => $deleted } } );
}

sub room_manager : Chained(navigation_base) PathPart(navigation) Args
                   HasActions {
   my ($self, $c, @args) = @_;

   return $c->stash->{nav_model}->form( $self->_get_model_args( $c, @args ) );
}

sub room_manager_delete : ActionFor(room_manager.delete) {
   my ($self, $c, @args) = @_;

   my ($ns, $name, $model) = $self->_get_model_args( $c, @args );

   $model->delete( $ns, $name );
   $self->set_uri_args( $c, $ns, $c->stash->{newtag} );
   return TRUE;
}

sub room_manager_save : ActionFor(room_manager.save)
                        ActionFor(room_manager.insert) {
   my ($self, $c, @args) = @_;

   my ($ns, $name, $model) = $self->_get_model_args( $c, @args );

   $self->set_uri_args( $c, $ns, $model->create_or_update( $ns, $name ) );
   return TRUE;
}

# Private methods

sub _get_model_args {
   my ($self, $c, $ns, $name) = @_; my $s = $c->stash;

   $name ||= $self->namespace_tag;

   return $name eq $self->namespace_tag
        ? ($ns, $name, $s->{namespace_model}, TRUE)
        : ($ns, $name, $s->{name_model     }, FALSE);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin::Navigation - Menu maintenance actions

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   package YourApp::Controller::Admin;

   use CatalystX::Usul::Moose;

   BEGIN { extends q(CatalystX::Usul::Controller::Admin) }

   __PACKAGE__->build_subcontrollers;

=head1 Description

Controller CRUD actions for the navigation menu

=head1 Subroutines/Methods

=head2 navigation_base

Midpoint that stashes the models used by the endpoint actions

=head2 access_control

Maintains the ACLs on the navigation menus actions. An ACL is a list
of users and roles (groups) that have access to that action. The is an
ACL for the whole controller and ACLs for each action. The ACL C<any>
allows anonymous access

The action's state can be set to:

=over 3

=item open

Action shows up in the navigation menu and is accessible

=item hidden

The action is accessible but does not appear in the navigation menu

=item closed

The action is unavailable

=back

=head2 access_control_set

Sets the selected actions state to one of; C<open>, C<hidden>, or C<closed>

=head2 access_control_update

Changes the ACL on the selected action

=head2 room_manager

Maintains the navigation menu display text, the flyover help text and the
list of meta keywords for search engines

=head2 room_manager_delete

Deletes the navigation menu entry for the selected action

=head2 room_manager_save

Creates or updates the navigation menu entry for the selected action

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Controller>

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
