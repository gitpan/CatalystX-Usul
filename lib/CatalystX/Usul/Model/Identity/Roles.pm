package CatalystX::Usul::Model::Identity::Roles;

# @(#)$Id: Roles.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Model);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

__PACKAGE__->mk_accessors( qw(auth_realms users_obj _cache _id2name
                              _user2role) );

sub add_roles_to_user {
   my ($self, $args) = @_; my ($msg, $role, $user);

   $self->throw( q(eNoUser) ) unless ($user = $args->{user});

   for $role (@{ $self->query_array( $args->{field} ) }) {
      $self->f_add_user_to_role( $role, $user );
      $msg .= $msg ? q(, ).$role : $role;
   }

   $self->add_result_msg( q(roles_added), $user, $msg );
   return;
}

sub add_users_to_role {
   my ($self, $args) = @_; my ($msg, $role, $user);

   unless ($role = $args->{role} and $self->is_role( $role )) {
      $self->throw( error => q(eUnknownRole), arg1 => $role );
   }

   for $user (@{ $self->query_array( $args->{field} ) }) {
      $self->f_add_user_to_role( $role, $user );
      $msg .= $msg ? q(, ).$user : $user;
   }

   $self->add_result_msg( q(users_added), $role, $msg );
   return;
}

sub create {
   my $self = shift; my $s = $self->context->stash; my $name;

   $self->throw( q(eNoRole) ) unless ($name = $self->query_value( q(name) ));

   if ($self->is_role( $name )) {
      $self->throw( error => q(eRoleExists), arg1 => $name );
   }

   $name = $self->check_field( $s->{form}->{name}.q(.name), $name );
   $self->f_create( $name );
   $self->add_result_msg( q(role_created), $name );
   return $name;
}

sub delete {
   my $self = shift; my $role;

   $self->throw( q(eNoRole) ) unless ($role = $self->query_value( q(role) ));

   unless ($self->is_role( $role )) {
      $self->throw( error => q(eUnknownRole), arg1 => $role );
   }

   $self->f_delete( $role );
   $self->add_result_msg( q(role_deleted), $role );
   return;
}

sub get_member_list {
   my ($self, $role) = @_; my (%found, @members) = ((), ()); my $role_ref;

   return unless ($role_ref = $self->_get_role( $role ));

   if ($role_ref->{users}) {
      for (@{ $role_ref->{users} }) {
         push @members, $_ unless ($found{ $_ }); $found{ $_ } = 1;
      }
   }

   if (defined $self->users_obj and $role_ref->{id}) {
      for ($self->users_obj->get_users_by_rid( $role_ref->{id} )) {
         push @members, $_ unless ($found{ $_ }); $found{ $_ } = 1;
      }
   }

   return sort @members;
}

sub get_name {
   my ($self, $rid) = @_;

   return unless (defined $rid);

   my (undef, $id2name) = $self->_load;

   return exists $id2name->{ $rid } ? $id2name->{ $rid } : q();
}

sub get_rid {
   my ($self, $role) = @_; my $role_ref;

   return unless ($role_ref = $self->_get_role( $role ));
   return defined $role_ref->{id} ? $role_ref->{id} : undef;
}

sub get_roles {
   my ($self, $user, $rid) = @_; my ($role, @roles, @tmp, %tmp);

   $self->throw( q(eNoUser) ) unless ($user);

   my ($cache, $id2name, $user2role) = $self->_load;

   # Get either all roles or a specific users roles
   if (lc $user eq q(all)) { @roles = keys %{ $cache } }
   else {
      @roles = exists $user2role->{ $user } ? @{ $user2role->{ $user } } : ();
   }

   @tmp = sort { lc $a cmp lc $b } @roles;

   # If checking a specific user then add its primary role name
   if (lc $user ne q(all)) {
      if (not defined $rid and defined $self->users_obj) {
         $rid = $self->users_obj->get_primary_rid( $user );
      }

      $role = defined $rid && exists $id2name->{ $rid }
            ? $id2name->{ $rid } : q();

      unshift @tmp, $role if ($role);
   }

   # Deduplicate list of roles
   @roles = (); %tmp = ();

   for (@tmp) { unless ($tmp{ $_ }) { push @roles, $_; $tmp{ $_ } = 1 } }

   return @roles;
}

sub is_member_of_role {
   my ($self, $role, $user) = @_;

   return unless ($self->is_role( $role ) && $user);

   return $self->is_member( $user, $self->get_member_list( $role ) );
}

sub is_role {
   my ($self, $role) = @_;

   return 0 unless ($role);

   my ($cache) = $self->_load;

   return exists $cache->{ $role } ? 1 : 0;
}

sub remove_roles_from_user {
   my ($self, $args) = @_; my ($msg, $role, $user);

   $self->throw( q(eNoUser) ) unless ($user = $args->{user});

   for $role (@{ $self->query_array( $args->{field} ) }) {
      $self->f_remove_user_from_role( $role, $user );
      $msg .= $msg ? q(, ).$role : $role;
   }

   $self->add_result_msg( q(roles_removed), $user, $msg );
   return;
}

sub remove_users_from_role {
   my ($self, $args) = @_; my ($msg, $role, $user);

   unless ($role = $args->{role} and $self->is_role( $role )) {
      $self->throw( error => q(eUnknownRole), arg1 => $role );
   }

   for $user (@{ $self->query_array( $args->{field} ) }) {
      $self->f_remove_user_from_role( $role, $user );
      $msg .= $msg ? q(, ).$user : $user;
   }

   $self->add_result_msg( q(users_removed), $role, $msg );
   return;
}

sub role_manager_form {
   my ($self, $realm, $role) = @_; my ($e, @members, @roles, @users);

   eval {
      @members = $self->get_member_list( $role );
      @roles   = $self->get_roles( q(all) );
      @users   = grep { !$self->is_member( $_, @members ) }
                 @{ $self->users_obj->retrieve( q([^\?]+), q() )->user_list };
   };

   return $self->add_error( $e ) if ($e = $self->catch);

   my $s      = $self->context->stash; $s->{pwidth} -= 10;
   my $first  = $role eq $s->{newtag} ? q(.name) : q(.role);
   my $values = [ q(), sort keys %{ $self->auth_realms } ];
   my $form   = $s->{form}->{name};

   unshift @roles, q(), $s->{newtag};

   $self->clear_form(   { firstfld => $form.$first } );
   $self->add_field(    { default  => $realm,
                          id       => $form.q(.realm),
                          values   => $values } );
   $self->add_field(    { default  => $role,
                          id       => $form.q(.role),
                          values   => \@roles } );
   $self->group_fields( { id       => $form.q(.select), nitems => 2 } );

   return unless ($role);

   if ($role eq $s->{newtag}) {
      $self->add_field(    { ajaxid  => $form.q(.name) } );
      $self->group_fields( { id      => $form.q(.create), nitems => 1 } );
      $self->add_buttons(  qw(Insert) );
   }
   else {
      $self->add_field(    { all     => \@users,
                             current => \@members,
                             id      => $form.q(.users) } );
      $self->group_fields( { id      => $form.q(.add_remove), nitems => 1 } );
      $self->add_buttons(  qw(Update Delete) );
   }

   return;
}

sub update {
   my ($self, $role) = @_; my $s = $self->context->stash; my ($args, $nusers);

   if ($nusers = $self->query_value( q(users_n_added) )) {
      $args = { field => q(users_added), role => $role };
      $s->{role_model}->add_users_to_role( $args );
   }

   if ($nusers = $self->query_value( q(users_n_deleted) )) {
      $args = { field => q(users_deleted), role => $role };
      $s->{role_model}->remove_users_from_role( $args );
   }

   return;
}

# Private methods

sub _get_role {
   my ($self, $role) = @_;

   return unless ($role);

   my ($cache) = $self->_load;

   return exists $cache->{ $role } ? $cache->{ $role } : q();
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Identity::Roles - Manage the roles and their members

=head1 Version

0.1.$Revision: 402 $

=head1 Synopsis

   use CatalystX::Usul::Model::Identity::Roles::DBIC;

   my $class    = CatalystX::Usul::Model::Identity::Roles::DBIC;
   my $role_obj = $class->new( $app, $config );

=head1 Description

Implements the base class for role data stores. Each factory subclass
should inherit from this and implement the required list of methods

=head1 Subroutines/Methods

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

Returns the list of members of a given role

=head2 get_name

   $role = $role_obj->get_name( $rid );

Returns the role name of the given role id

=head2 get_rid

   $rid = $role_obj->get_rid( $role );

Returns the role id of the given role name

=head2 get_roles

   @roles = $role_obj->get_roles( $user, $rid );

Returns the list of roles that the given user is a member of. If the
user I<all> is specified then a list of all roles is returned. If a
specific user is passed then the C<$rid> will be used as that users
primary role id. If C<$rid> is not specified then the primary role
id will be looked up via the user object C<< $self->user_ref >>

=head2 is_member_of_role

   $bool = $role_obj->is_member_of_role( $role, $user );

Returns true if the given user is a member of the given role, returns
false otherwise

=head2 is_role

   $bool = $role_obj->is_role( $role );

Returns true if C<$role> exists, false otherwise

=head2 remove_roles_from_user

   $role_obj->remove_roles_from_user( $args );

Removes a user from one or more roles

=head2 remove_users_from_role

   $role_obj->remove_users_from_role( $args );

Removes one or more users from a role

=head2 role_manager_form

   $role_obj->role_form;

Adds data to the stash which displays the role management screen

=head2 update

   $role_obj->update;

Called as an action from the the management screen. This method determines
if users have been added and/or removed from the selected role and calls
L</add_users_to_role> and/or L</remove_users_from_role> as appropriate

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

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
