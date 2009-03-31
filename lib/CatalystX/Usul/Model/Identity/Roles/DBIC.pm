package CatalystX::Usul::Model::Identity::Roles::DBIC;

# @(#)$Id: DBIC.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Model::Identity::Roles);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

__PACKAGE__->config( _dirty => 1 );

__PACKAGE__->mk_accessors( qw(dbic_role_class dbic_user_roles_class
                              role_model user_roles_model _dirty) );

sub build_per_context_instance {
   my ($self, $c, @rest) = @_; my $class;

   my $new = $self->next::method( $c, @rest );

   $class = $new->users_obj->dbic_user_class;
   $new->users_obj->user_model( $c->model( $class ) );

   $class = $new->dbic_role_class;
   $new->role_model( $c->model( $class ) );

   $class = $new->dbic_user_roles_class;
   $new->user_roles_model( $c->model( $class ) );

   return $new;
}

# Factory methods

sub f_add_user_to_role {
   my ($self, $role, $user) = @_; my $e;

   my $rid      = $self->get_rid( $role );
   my $user_obj = $self->users_obj->find_user( $user );

   unless ($self->is_member( $role, @{ $user_obj->roles } )) {
      eval { $self->user_roles_model->create
                ( { role_id => $rid, user_id => $user_obj->uid } ) };

      $self->throw( $e ) if ($e = $self->catch);

      $self->_dirty( 1 );
   }

   return;
}

sub f_create {
   my ($self, $role) = @_; my $e;

   eval { $self->role_model->create( { role => $role } ) };

   $self->throw( $e ) if ($e = $self->catch);

   $self->_dirty( 1 );
   return;
}

sub f_delete {
   my ($self, $role) = @_;

   $self->lock->set( k => __PACKAGE__ );
   my $role_obj = $self->role_model->search( { role => $role } );

   unless (defined $role_obj) {
      $self->lock->reset( k => __PACKAGE__ );
      $self->throw( error => q(eUnknownRole), arg1 => $role );
   }

   $role_obj->delete; $self->_dirty( 1 );
   $self->lock->reset( k => __PACKAGE__ );
   return;
}

sub f_remove_user_from_role {
   my ($self, $role, $user) = @_;

   my $rid      = $self->get_rid( $role );
   my $user_obj = $self->users_obj->find_user( $user );

   if ($self->is_member( $role, @{ $user_obj->roles } )) {
      $self->lock->set( k => __PACKAGE__ );

      my $user_roles_obj = $self->user_roles_model->search
         ( { role_id => $rid, user_id => $user_obj->uid } );

      unless (defined $user_roles_obj) {
         $self->lock->reset( k => __PACKAGE__ );
         $self->throw( error => q(eUserNotInRole),
                       arg1  => $role, arg2 => $user );
      }

      $user_roles_obj->delete; $self->_dirty( 1 );
      $self->lock->reset( k => __PACKAGE__ );
   }

   return;
}

# Private methods

sub _load {
   my $self = shift;
   my ($attr, $cache, $id2name, $role, $role_obj, $rs);
   my ($user, $user_roles_obj, $user2role);

   $self->lock->set( k => __PACKAGE__ );

   unless ($self->_dirty) {
      $cache     = { %{ $self->_cache     } };
      $id2name   = { %{ $self->_id2name   } };
      $user2role = { %{ $self->_user2role } };
      $self->lock->reset( k => __PACKAGE__ );
      return ($cache, $id2name, $user2role);
   }

   $self->_cache( {} ); $self->_id2name( {} ); $self->_user2role( {} );
   $rs   = $self->role_model->search();

   while (defined ($role_obj = $rs->next)) {
      $role = $role_obj->get_column( q(role) );
      $self->_cache->{ $role } = { id => $role_obj->id, users => [] };
      $self->_id2name->{ $role_obj->id } = $role;
   }

   $attr = { include_columns => [ q(role.role), q(user.username) ],
             join            => [ q(role), q(user) ] };
   $rs   = $self->user_roles_model->search( {}, $attr );

   while (defined ($user_roles_obj = $rs->next)) {
      $role = $user_roles_obj->get_column( q(role) );
      $user = $user_roles_obj->get_column( q(username) );

      $self->_user2role->{ $user } = [] unless ($self->_user2role->{ $user });

      push @{ $self->_cache->{ $role }->{users} }, $user;
      push @{ $self->_user2role->{ $user } }, $role;
   }

   $cache     = { %{ $self->_cache     } };
   $id2name   = { %{ $self->_id2name   } };
   $user2role = { %{ $self->_user2role } };
   $self->_dirty( 0 );
   $self->lock->reset( k => __PACKAGE__ );
   return ($cache, $id2name, $user2role);
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Identity::Roles::DBIC - Role management database storage

=head1 Version

0.1.$Revision: 402 $

=head1 Synopsis

   use CatalystX::Usul::Model::Identity::Roles::DBIC;

   my $class = CatalystX::Usul::Model::Identity::Roles::DBIC;

   my $role_obj = $class->new( $app, $config );

=head1 Description

Methods to manipulate the I<roles> and I<user_roles> table in a
database using L<DBIx::Class>. This class implements the methods
required by it's base class

=head1 Subroutines/Methods

=head2 build_per_context_instance

Make copies of DBIC model references available only after the application
setup is complete

=head2 f_add_user_to_role

   $role_obj->f_add_user_to_role( $role, $user );

Adds the specified user to the specified role

=head2 f_create

   $role_obj->f_create( $role );

Creates a new role with the given name

=head2 f_delete

   $role_obj->f_delete( $role );

Deletes the specified role

=head2 f_remove_user_from_role

   $role_obj->f_remove_user_to_role( $role, $user );

Removes the specified user to the specifed role

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model::Identity::Roles>

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
