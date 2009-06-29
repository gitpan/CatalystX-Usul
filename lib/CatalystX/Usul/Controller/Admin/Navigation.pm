# @(#)$Id: Navigation.pm 590 2009-06-13 12:48:05Z pjf $

package CatalystX::Usul::Controller::Admin::Navigation;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 590 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Controller);

my $NUL = q();
my $SEP = q(/);

__PACKAGE__->config( namespace => q(admin), realm_class => q(IdentityUnix) );

__PACKAGE__->mk_accessors( qw(realm_class) );

sub navigation_base : Chained(common) PathPart(configuration) CaptureArgs(0) {
   my ($self, $c) = @_; my $s = $c->stash;

   my $model = $c->model( $self->realm_class );

   $s->{level_model} = $c->model( q(Config::Levels) );
   $s->{room_model}  = $c->model( q(Config::Rooms) );
   $s->{auth_models} = [];

   for my $realm (keys %{ $model->auth_realms }) {
      push @{ $s->{auth_models} },
           $c->model( $model->auth_realms->{ $realm } );
   }

   return;
}

sub access_control : Chained(navigation_base) Args HasActions {
   my ($self, $c, $namespace, $name) = @_;

   $namespace = $self->set_key( $c, q(level), $namespace ) || $NUL;
   $name      = $self->set_key( $c, q(room),  $name      );
   $c->model( q(Navigation) )->form( $namespace, $name   );
   return;
}

sub access_control_set : ActionFor(access_control.set) {
   my ($self, $c) = @_;

   my ($model, $file, $name) = $self->_get_action_parameters( $c );

   $model->set_state( { file => $file, name => $name } );
   return 1;
}

sub access_control_update : ActionFor(access_control.update) {
   my ($self, $c) = @_; my $msg;

   my ($model, $file, $name) = $self->_get_action_parameters( $c );

   if ($model->query_value( q(user_groups_n_deleted) )) {
      $msg = $file eq q(default) ? q(revokedLevel) : q(revokedRoom);
      $model->remove_from_attribute_list( { file  => $file,
                                            name  => $name,
                                            field => q(user_groups_deleted),
                                            list  => q(acl),
                                            msg   => $msg } );
   }

   if ($model->query_value( q(user_groups_n_added) )) {
      $msg = $file eq q(default) ? q(grantedLevel) : q(grantedRoom);
      $model->add_to_attribute_list( { file  => $file,
                                       name  => $name,
                                       field => q(user_groups_added),
                                       list  => q(acl),
                                       msg   => $msg } );
   }

   return 1;
}

sub room_manager : Chained(navigation_base) Args HasActions {
   my ($self, $c, $namespace, $name) = @_;

   $namespace = $self->set_key( $c, q(level), $namespace ) || $NUL;
   $name      = $self->set_key( $c, q(room),  $name      );
   $c->model( q(Navigation) )->form( $namespace, $name );
   return;
}

sub room_manager_delete : ActionFor(room_manager.delete) {
   my ($self, $c) = @_;

   my ($model, $file, $name) = $self->_get_action_parameters( $c );

   $model->delete( { file => $file, name => $name } );
   return 1;
 }

sub room_manager_save : ActionFor(room_manager.save)
                        ActionFor(room_manager.insert) {
   my ($self, $c) = @_;

   my $name = $c->model( q(Base) )->query_value( q(name) ) || $NUL;

   $self->set_key( $c, q(room), $name );

   my ($model, $file) = $self->_get_action_parameters( $c );

   $model->create_or_update( { file => $file, name => $name } );
   return 1;
}

# Private methods

sub _get_action_parameters {
   my ($self, $c) = @_; my $s = $c->stash; my ($name, $namespace);

   unless ($namespace = $self->get_key( $c, q(level) )) {
      $self->throw( 'No namespace for action specified' );
   }

   unless ($name = $self->get_key( $c, q(room) )) {
      $self->throw( 'No name for action specified' );
   }

   if ($name eq q(..Level..)) {
      return ($s->{level_model}, q(default), $namespace);
   }

   return ($s->{room_model}, $namespace, $name);
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin::Navigation - Menu maintenance actions

=head1 Version

0.3.$Revision: 590 $

=head1 Synopsis

   package MyApp::Controller::Admin;

   use base qw(CatalystX::Usul::Controller::Admin);

   __PACKAGE__->build_subcontrollers;

=head1 Description

Controller CRUD actions for the navigation menu

=head1 Subroutines/Methods

=head2 navigation_base

Midpoint that stashes the models used by the endpoint actions

=head2 access_control

Maintains the ACLs on the navigation menus actions. An ACL is a list
of users and roles (groups) that have access to that action. The is an
ACL for the whole controller and ACLs for each action. The ACL I<any>
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

Sets the selected actions state to one of; I<open>, I<hidden>, or I<closed>

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
