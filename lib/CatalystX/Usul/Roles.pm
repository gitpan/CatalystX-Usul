# @(#)$Id: Roles.pm 1139 2012-03-28 23:49:18Z pjf $

package CatalystX::Usul::Roles;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1139 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(is_member throw);

__PACKAGE__->mk_accessors( qw(cache users) );

sub new {
   my ($class, $app, $attrs) = @_;

   $attrs->{cache} ||= {};

   return $class->next::method( $app, $attrs );
}

sub get_member_list {
   my ($self, $role) = @_; my (%found, @members) = ((), ());

   my $role_ref = $self->_get_role( $role ) or return;

   if ($role_ref->{users}) {
      for (@{ $role_ref->{users} }) {
         $found{ $_ } or push @members, $_; $found{ $_ } = TRUE;
      }
   }

   if (defined $self->users and $role_ref->{id}) {
      for ($self->users->get_users_by_rid( $role_ref->{id} )) {
         $found{ $_ } or push @members, $_; $found{ $_ } = TRUE;
      }
   }

   return sort @members;
}

sub get_name {
   my ($self, $rid) = @_; defined $rid or return;

   my (undef, $id2name) = $self->_load; defined $id2name or return;

   return exists $id2name->{ $rid } ? $id2name->{ $rid } : NUL;
}

sub get_rid {
   my ($self, $role) = @_;

   my $role_ref = $self->_get_role( $role ) or return;

   return defined $role_ref->{id} ? $role_ref->{id} : undef;
}

sub get_roles {
   my ($self, $user, $rid) = @_; $user or throw 'User not specified';

   my ($cache, $id2name, $user2role) = $self->_load; my @roles;

   # Get either all roles or a specific users roles
   if (lc $user eq q(all)) { @roles = keys %{ $cache } }
   elsif (defined $user2role) {
      @roles = exists $user2role->{ $user } ? @{ $user2role->{ $user } } : ();
   }
   else {
      @roles = grep  { is_member $user, $cache->{ $_ }->{users} }
               keys %{ $cache };
   }

   my @tmp = sort { lc $a cmp lc $b } @roles;

   # If checking a specific user then add its primary role name
   if (lc $user ne q(all)) {
      if (not defined $rid and defined $self->users) {
         $rid = $self->users->get_primary_rid( $user );
      }

      if (defined $rid and defined $id2name and exists $id2name->{ $rid }) {
         unshift @tmp, $id2name->{ $rid };
      }
   }

   # Deduplicate list of roles
   my %tmp = (); @roles = ();

   for (@tmp) { unless ($tmp{ $_ }) { push @roles, $_; $tmp{ $_ } = TRUE } }

   return @roles;
}

sub is_member_of_role {
   my ($self, $role, $user) = @_;

   ($user and $self->is_role( $role )) or return;

   return is_member $user, $self->get_member_list( $role );
}

sub is_role {
   return $_[ 0 ]->_get_role( $_[ 1 ] ) ? TRUE : FALSE;
}

# Private methods

sub _cache_results {
   my ($self, $key) = @_; my $cache = { %{ $self->cache } };

   $self->lock->reset( k => $key );

   return ($cache->{roles}, $cache->{id2name}, $cache->{user2role});
}

sub _get_role {
   my ($self, $role) = @_; $role or return; my ($cache) = $self->_load;

   return exists $cache->{ $role } ? $cache->{ $role } : NUL;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Roles - Manage the roles and their members

=head1 Version

0.5.$Revision: 1139 $

=head1 Synopsis

   use CatalystX::Usul::Roles::DBIC;

   my $class    = CatalystX::Usul::Roles::DBIC;
   my $role_obj = $class->new( $app, $config );

=head1 Description

Implements the base class for role data stores. Each factory subclass
should inherit from this and implement the required list of methods

=head1 Subroutines/Methods

=head2 new

Constructor.

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
id will be looked up via the user object

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
