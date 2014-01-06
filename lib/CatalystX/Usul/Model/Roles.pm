# @(#)Ident: ;

package CatalystX::Usul::Model::Roles;

use strict;
use version; our $VERSION = qv( sprintf '0.15.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(is_member throw);
use TryCatch;

extends q(CatalystX::Usul::Model);
with    q(CatalystX::Usul::TraitFor::Model::StashHelper);
with    q(CatalystX::Usul::TraitFor::Model::QueryingRequest);

has 'user_model_class' => is => 'ro', isa => NonEmptySimpleStr,
   required            => TRUE;

sub build_per_context_instance {
   my ($self, $c, @rest) = @_; my $clone = $self->next::method( $c, @rest );

   my $users = $c->model( $clone->user_model_class );

   $clone->domain_model( $users->domain_model->roles );
   return $clone;
}

sub add_roles_to_user {
   my ($self, $args) = @_; my $roles; my $count = 0;

   my $user = $args->{user} or throw 'User not specified';

   for my $role (@{ $args->{items} || [] }) {
      $self->domain_model->add_user_to_role( $role, $user );
      $roles .= $roles ? q(, ).$role : $role; $count++;
   }

   $count and
      $self->add_result_msg( 'User [_1] added to roles: [_2]', $user, $roles );

   return $count;
}

sub add_users_to_role {
   my ($self, $args) = @_; my ($role, $users); my $count = 0;

   ($role = $args->{role} and $self->is_role( $role ))
      or throw error => 'Role [_1] unknown', args => [ $role ];

   for my $user (@{ $args->{items} || [] }) {
      $self->domain_model->add_user_to_role( $role, $user );
      $users .= $users ? q(, ).$user : $user; $count++;
   }

   $count and
      $self->add_result_msg( 'Role [_1] added users : [_2]', $role, $users );

   return $count;
}

sub create {
   my $self = shift;
   my $s    = $self->context->stash;
   my $name = $self->query_value( q(name) ) or throw 'Role not specified';

   $self->is_role( $name )
      and throw error => 'Role [_1] already exists', args => [ $name ];
   $name = $self->check_field( $s->{form}->{name}.q(.name), $name );
   $self->domain_model->create( $name );
   $self->add_result_msg( 'Role [_1] created', $name );
   return $name;
}

sub delete {
   my $self = shift;
   my $role = $self->query_value( q(role) ) or throw 'Role not specified';

   $self->is_role( $role )
      or throw error => 'Role [_1] unknown', args => [ $role ];
   $self->domain_model->delete( $role );
   $self->add_result_msg( 'Role [_1] deleted', $role );
   return TRUE;
}

sub get_member_list {
   my ($self, @rest) = @_; return $self->domain_model->get_member_list( @rest );
}

sub get_roles {
   my ($self, @rest) = @_; return $self->domain_model->get_roles( @rest );
}

sub is_role {
   my ($self, @rest) = @_; return $self->domain_model->is_role( @rest );
}

sub remove_roles_from_user {
   my ($self, $args) = @_; my $count = 0; my $roles;

   my $user = $args->{user} or throw 'User not specified';

   for my $role (@{ $args->{items} || [] }) {
      $self->domain_model->remove_user_from_role( $role, $user );
      $roles .= $roles ? q(, ).$role : $role; $count++;
   }

   $count and
      $self->add_result_msg( 'User [_1] removed roles: [_2]', $user, $roles );

   return $count;
}

sub remove_users_from_role {
   my ($self, $args) = @_; my ($role, $users); my $count = 0;

   ($role = $args->{role} and $self->is_role( $role ))
      or throw error => 'Role [_1] unknown', args => [ $role ];

   for my $user (@{ $args->{items} || [] }) {
      $self->domain_model->remove_user_from_role( $role, $user );
      $users .= $users ? q(, ).$user : $user; $count++;
   }

   $count and
      $self->add_result_msg( 'Role [_1] removed users: [_2]', $role, $users );

   return $count;
}

sub role_manager_form {
   my ($self, $role) = @_; my (@members, @roles, @users);

   try {
      @roles   = $self->get_roles( q(all) );
      @members = $self->get_member_list( $role );
      @users   = grep { not is_member $_, @members }
                     @{ $self->domain_model->users->list( q([^\?]+) ) };
   }
   catch ($e) { return $self->add_error( $e ) }

   my $c      = $self->context;
   my $s      = $c->stash; $s->{pwidth} -= 10;
   my $form   = $s->{form}->{name};
   my $realm  = $s->{role_params}->{realm} || NUL;
   my $first  = $role && $role eq $s->{newtag} ? q(.name) : q(.role);
   my @realms = grep { $_ ne q(default) } sort keys %{ $c->auth_realms };

   unshift @roles, NUL, $s->{newtag};

   $self->clear_form  ( { firstfld => $form.$first } );
   $self->add_field   ( { default  => $realm,
                          id       => "${form}.realm",
                          values   => [ NUL, @realms ] } );
   $self->add_field   ( { default  => $role,
                          id       => "${form}.role",
                          values   => \@roles } );
   $self->group_fields( { id       => "${form}.select" } );

   $role or return;

   if ($role eq $s->{newtag}) {
      $self->add_field   ( { id      => "${form}.name" } );
      $self->group_fields( { id      => "${form}.create" } );
      $self->add_buttons ( qw(Insert) );
      return;
   }

   $self->add_field   ( { all     => \@users,
                          current => \@members,
                          id      => "${form}.users" } );
   $self->group_fields( { id      => "${form}.add_remove" } );
   $self->add_buttons ( qw(Update Delete) );
   return;
}

sub update_roles {
   my $self = shift;
   my $user = $self->query_value( q(user) ) or throw 'User not specified';

   $self->update_group_membership( {
      add_method    => sub { $self->add_roles_to_user( @_ ) },
      delete_method => sub { $self->remove_roles_from_user( @_ ) },
      field         => q(groups),
      method_args   => { user => $user },
   } ) or throw 'Roles not selected';

   return TRUE;
}

sub update_users {
   my $self = shift;
   my $role = $self->query_value( q(role) ) or throw 'Role not specified';

   $self->update_group_membership( {
      add_method    => sub { $self->add_users_to_role( @_ ) },
      delete_method => sub { $self->remove_users_from_role( @_ ) },
      field         => q(users),
      method_args   => { role => $role },
   } ) or throw 'Users not selected';

   return TRUE;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Roles - Manage the roles and their members

=head1 Version

Describes v0.15.$Rev: 1 $

=head1 Synopsis

   package YourApp::Model::Roles;

   use CatalystX::Usul::Moose;

   extends q(CatalystX::Usul::Model::Roles);

=head1 Description

Manage the roles and their members

=head1 Configuration and Environment

Defines the following list of attributes

=over 3

=item user_model_class

A required non empty simple string. Passed by L</build_per_context_instance>
to the Catalyst L<model|Catalyst/model> method

=back

=head1 Subroutines/Methods

=head2 build_per_context_instance

Sets our domain model to that of our user model's, domain model's roles
object

=head2 add_roles_to_user

   $role_obj->add_roles_to_user( $args );

Adds the user to one or more roles. The user is passed in
C<< $args->{user} >> and C<< $args->{field} >> is the field to extract
from the request object. Calls C<f_add_user_to_role> in the
factory subclass to add one user to one role. A suitable message from
the stash C<$s> is added to the result div upon success

=head2 add_users_to_role

   $role_obj->add_users_to_role( $args );

Adds one or more users to the specified role. The role is passed in
C<< $args->{role} >> and C<< $args->{field} >> is the field to extract
from the request object. Calls C<f_add_user_to_role> in the
factory subclass to add one user to one role. A suitable message from
the stash C<$s> is added to the result div upon success

=head2 create

   $role_obj->create;

Creates a new role. The I<name> field from the request object is
passed to C<f_create> in the factory subclass. A suitable message from
the stash C<$s> is added to the result div upon success

=head2 delete

   $role_obj->delete;

Deletes an existing role. The I<role> field from the request object
is passed to the C<f_delete> method in the factory subclass. A
suitable message from the stash C<$s> is added to the result div

=head2 get_member_list

   @members = $role_obj->get_member_list( $role );

Returns the list of members of a given role. Exposes method in the
L<domain model|CatalystX::Usul::Roles/get_member_list>

=head2 get_roles

   @roles = $role_obj->get_roles( $user, $rid );

Returns the list of roles that the given user is a member of. Exposes
method in the L<domain model|CatalystX::Usul::Roles/get_roles>

=head2 is_role

   $bool = $role_obj->is_role( $role );

Returns true if C<$role> exists, false otherwise. Exposes method in the
L<domain model|CatalystX::Usul::Roles/is_role>

=head2 remove_roles_from_user

   $role_obj->remove_roles_from_user( $args );

Removes a user from one or more roles

=head2 remove_users_from_role

   $role_obj->remove_users_from_role( $args );

Removes one or more users from a role

=head2 role_manager_form

   $role_obj->role_form;

Adds data to the stash which displays the role management screen

=head2 update_roles

   $role_obj->update_roles;

Called as an action from the the management screen. This method determines
if roles have been added and/or removed from the selected user and calls
L</add_roles_to_user> and/or L</remove_roles_from_user> as appropriate

=head2 update_users

   $role_obj->update_users;

Called as an action from the the management screen. This method determines
if users have been added and/or removed from the selected role and calls
L</add_users_to_role> and/or L</remove_users_from_role> as appropriate

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::TraitFor::Model::QueryingRequest>

=item L<CatalystX::Usul::TraitFor::Model::StashHelper>

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

Copyright (c) 2014 Peter Flanigan. All rights reserved

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
