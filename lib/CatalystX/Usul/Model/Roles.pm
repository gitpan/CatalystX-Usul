# @(#)$Id: Roles.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::Model::Roles;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model);

use Class::C3;

__PACKAGE__->mk_accessors( qw(auth_realms domain_attributes domain_class
                              role_domain users) );

sub new {
   my ($self, $app, @rest) = @_;

   my $new       = $self->next::method( $app, @rest );
   my $dom_class = $new->domain_class;

   $self->ensure_class_loaded( $dom_class );

   my $dom_attrs = $new->domain_attributes || {};

   $new->role_domain( $dom_class->new( $app, $dom_attrs ) );

   return $new;
}

sub build_per_context_instance {
   my ($self, $c, @rest) = @_;

   my $new = $self->next::method( $c, @rest );

   my $dom_attrs = $new->domain_attributes;

   my $rdm = $new->role_domain( $new->domain_class->new( $c, $dom_attrs ) );

   if ($rdm->can( q(dbic_role_class) )) {
      my $class;

      if ($class = $rdm->dbic_role_class) {
         $rdm->dbic_role_model( $c->model( $class ) );
      }

      if ($class = $rdm->dbic_user_roles_class) {
         $rdm->dbic_user_roles_model( $c->model( $class ) );
      }
   }

   return $new;
}

sub add_roles_to_user {
   my ($self, $args) = @_; my ($msg, $role, $user);

   $self->throw( 'No user specified' ) unless ($user = $args->{user});

   for $role (@{ $self->query_array( $args->{field} ) }) {
      $self->role_domain->add_user_to_role( $role, $user );
      $msg .= $msg ? q(, ).$role : $role;
   }

   $self->add_result_msg( q(roles_added), $user, $msg );
   return;
}

sub add_users_to_role {
   my ($self, $args) = @_; my ($msg, $role, $user);

   unless ($role = $args->{role} and $self->is_role( $role )) {
      $self->throw( error => 'Role [_1] unknown', args => [ $role ] );
   }

   for $user (@{ $self->query_array( $args->{field} ) }) {
      $self->role_domain->add_user_to_role( $role, $user );
      $msg .= $msg ? q(, ).$user : $user;
   }

   $self->add_result_msg( q(users_added), $role, $msg );
   return;
}

sub create {
   my $self = shift; my $s = $self->context->stash; my $name;

   unless ($name = $self->query_value( q(name) )) {
      $self->throw( 'No role specified' );
   }

   if ($self->is_role( $name )) {
      $self->throw( error => 'Role [_1] already exists', args => [ $name ] );
   }

   $name = $self->check_field( $s->{form}->{name}.q(.name), $name );
   $self->role_domain->create( $name );
   $self->add_result_msg( q(role_created), $name );
   return $name;
}

sub delete {
   my $self = shift; my $role;

   unless ($role = $self->query_value( q(role) )) {
      $self->throw( 'No role specified' );
   }

   unless ($self->is_role( $role )) {
      $self->throw( error => 'Role [_1] unknown', args => [ $role ] );
   }

   $self->role_domain->delete( $role );
   $self->add_result_msg( q(role_deleted), $role );
   return;
}

sub get_member_list {
   my ($self, @rest) = @_;

   return $self->role_domain->get_member_list( @rest );
}

sub get_roles {
   my ($self, @rest) = @_; return $self->role_domain->get_roles( @rest );
}

sub is_role {
   my ($self, @rest) = @_; return $self->role_domain->is_role( @rest );
}

sub remove_roles_from_user {
   my ($self, $args) = @_; my ($msg, $role, $user);

   $self->throw( 'No user specified' ) unless ($user = $args->{user});

   for $role (@{ $self->query_array( $args->{field} ) }) {
      $self->role_domain->remove_user_from_role( $role, $user );
      $msg .= $msg ? q(, ).$role : $role;
   }

   $self->add_result_msg( q(roles_removed), $user, $msg );
   return;
}

sub remove_users_from_role {
   my ($self, $args) = @_; my ($msg, $role, $user);

   unless ($role = $args->{role} and $self->is_role( $role )) {
      $self->throw( error => 'Role [_1] unknown', args => [ $role ] );
   }

   for $user (@{ $self->query_array( $args->{field} ) }) {
      $self->role_domain->remove_user_from_role( $role, $user );
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
                 @{ $self->users->retrieve( q([^\?]+), q() )->user_list };
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
   my ($self, $role) = @_; my $args;

   if ($self->query_value( q(users_n_added) )) {
      $args = { field => q(users_added), role => $role };
      $self->add_users_to_role( $args );
   }

   if ($self->query_value( q(users_n_deleted) )) {
      $args = { field => q(users_deleted), role => $role };
      $self->remove_users_from_role( $args );
   }

   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Roles - Manage the roles and their members

=head1 Version

0.1.$Revision: 562 $

=head1 Synopsis

   package YourApp::Model::Roles;

   use CatalystX::Usul::Model::Roles;

   sub new {
      my ($self, $app, $config) = @_;

      my $role_obj = CatalystX::Usul::Model::Roles->new( $app, $config );
   }

=head1 Description

=head1 Subroutines/Methods

=head2 new

=head2 build_per_context_instance

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
