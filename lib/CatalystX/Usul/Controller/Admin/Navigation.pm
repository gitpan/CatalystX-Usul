package CatalystX::Usul::Controller::Admin::Navigation;

# @(#)$Id: Navigation.pm 406 2009-03-30 01:53:50Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Controller);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 406 $ =~ /\d+/gmx );

__PACKAGE__->config( namespace => q(admin), realm_class => q(IdentityUnix) );

__PACKAGE__->mk_accessors( qw(realm_class) );

my $SEP = q(/);

sub navigation_base : Chained(common) PathPart(navigation) CaptureArgs(0) {
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

   $namespace = $self->set_key( $c, q(level), $namespace );
   $name      = $self->set_key( $c, q(room),  $name      );
   $c->model( q(Navigation) )->form( $namespace, $name   );
   return;
}

sub access_control_set : ActionFor(access_control.set) {
   my ($self, $c) = @_; my ($file, $level, $model, $name, $room);

   unless ($level = $self->get_key( $c, q(level) )) {
      $self->throw( q(eNoLevelName) );
   }

   unless ($room = $self->get_key( $c, q(room) )) {
      $self->throw( q(eNoRoomName)  );
   }

   if ($room eq q(..Level..)) {
      $model = $c->model( q(Config::Levels) );
      $file  = q(default); $name = $level;
   }
   else {
      $model = $c->model( q(Config::Rooms) );
      $file  = $level; $name = $room;
   }

   $model->set_state( { file => $file, name => $name } );
   return 1;
}

sub access_control_update : ActionFor(access_control.update) {
   my ($self, $c) = @_; my ($file, $level, $model, $msg, $name, $room);

   unless ($level = $self->get_key( $c, q(level) )) {
      $self->throw( q(eNoLevelName) );
   }

   unless ($room = $self->get_key( $c, q(room) )) {
      $self->throw( q(eNoRoomName)  );
   }

   if ($room eq q(..Level..)) {
      $model = $c->model( q(Config::Levels) );
      $file  = q(default); $name = $level;
   }
   else {
      $model = $c->model( q(Config::Rooms) );
      $file  = $level; $name = $room;
   }

   if ($model->query_value( q(user_groups_n_deleted) )) {
      $msg = $room eq q(..Level..) ? q(revokedLevel) : q(revokedRoom);
      $model->remove_from_attribute_list( { file  => $file,
                                            name  => $name,
                                            field => q(user_groups_deleted),
                                            list  => q(acl),
                                            msg   => $msg } );
   }

   if ($model->query_value( q(user_groups_n_added) )) {
      $msg = $room eq q(..Level..) ? q(grantedLevel) : q(grantedRoom);
      $model->add_to_attribute_list( { file  => $file,
                                       name  => $name,
                                       field => q(user_groups_added),
                                       list  => q(acl),
                                       msg   => $msg } );
   }

   return 1;
}

sub navigation_manager : Chained(navigation_base) PathPart('') Args(0) {
   my ($self, $c) = @_;

   return $self->redirect_to_path( $c, $SEP.q(access_control) );
}

sub room_manager : Chained(navigation_base) Args HasActions {
   my ($self, $c, $namespace, $name) = @_;

   $namespace = $self->set_key( $c, q(level), $namespace ) || q();
   $name      = $self->set_key( $c, q(room),  $name      );
   $c->model( q(Navigation) )->form( $namespace, $name );
   return;
}

sub room_manager_delete : ActionFor(room_manager.delete) {
   my ($self, $c) = @_; my ($file, $level, $model, $name, $room);

   unless ($level = $self->get_key( $c, q(level) )) {
      $self->throw( q(eNoLevelName) );
   }

   unless ($room = $self->get_key( $c, q(room) )) {
      $self->throw( q(eNoRoomName)  );
   }

   if ($room eq q(..Level..)) {
      $model = $c->model( q(Config::Levels) );
      $file  = q(default); $name = $level;
   }
   else {
      $model = $c->model( q(Config::Rooms) );
      $file  = $level; $name = $room;
   }

   $model->delete( { file => $file, name => $name } );
   return 1;
 }

sub room_manager_save : ActionFor(room_manager.save)
                        ActionFor(room_manager.insert) {
   my ($self, $c) = @_; my ($file, $level, $model, $name, $room);

   unless ($level = $self->get_key( $c, q(level) )) {
      $self->throw( q(eNoLevelName) );
   }

   $room = $self->get_key( $c, q(room) );
   $name = $c->model( q(Config) )->query_value( q(name) );

   if ($room eq q(..Level..)) {
      $self->throw( q(eNoLevelName) ) unless ($name);

      $model = $c->model( q(Config::Levels) ); $file = q(default);
   }
   else {
      $self->throw( q(eNoRoomName) ) unless ($name);

      $model = $c->model( q(Config::Rooms) ); $file = $level;
   }

   $model->create_or_update( { file => $file, name => $name } );
   return 1;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin::Navigation - Menu maintenance actions

=head1 Version

0.1.$Revision: 406 $

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

=head2 navigation_manager

Redirects to the L</room_manager>

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
