# @(#)$Id: DBIC.pm 576 2009-06-09 23:23:46Z pjf $

package CatalystX::Usul::Roles::DBIC;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 576 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Roles);

__PACKAGE__->config( _dirty => 1 );

__PACKAGE__->mk_accessors( qw(dbic_role_class dbic_user_roles_class
                              dbic_role_model dbic_user_roles_model _dirty) );

# Factory methods

sub add_user_to_role {
   my ($self, $role, $user) = @_; my $e;

   my $rid      = $self->get_rid( $role );
   my $user_obj = $self->user_domain->find_user( $user );

   unless ($self->is_member( $role, @{ $user_obj->roles } )) {
      eval { $self->dbic_user_roles_model->create
                ( { role_id => $rid, user_id => $user_obj->uid } ) };

      $self->throw( $e ) if ($e = $self->catch);

      $self->_dirty( 1 );
   }

   return;
}

sub create {
   my ($self, $role) = @_; my $e;

   eval { $self->dbic_role_model->create( { role => $role } ) };

   $self->throw( $e ) if ($e = $self->catch);

   $self->_dirty( 1 );
   return;
}

sub delete {
   my ($self, $role) = @_;

   $self->lock->set( k => __PACKAGE__ );

   my $role_obj = $self->dbic_role_model->search( { role => $role } );

   unless (defined $role_obj) {
      $self->lock->reset( k => __PACKAGE__ );
      $self->throw( error => 'Role [_1] unknown', args => [ $role ] );
   }

   $role_obj->delete; $self->_dirty( 1 );
   $self->lock->reset( k => __PACKAGE__ );
   return;
}

sub remove_user_from_role {
   my ($self, $role, $user) = @_;

   my $rid      = $self->get_rid( $role );
   my $user_obj = $self->user_domain->find_user( $user );

   if ($self->is_member( $role, @{ $user_obj->roles } )) {
      $self->lock->set( k => __PACKAGE__ );

      my $user_roles_obj = $self->dbic_user_roles_model->search
         ( { role_id => $rid, user_id => $user_obj->uid } );

      unless (defined $user_roles_obj) {
         $self->lock->reset( k => __PACKAGE__ );
         $self->throw( error => 'User [_1] not in role [_2]',
                       args  => [ $user, $role ] );
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
   $rs   = $self->dbic_role_model->search();

   while (defined ($role_obj = $rs->next)) {
      $role = $role_obj->get_column( q(role) );
      $self->_cache->{ $role } = { id => $role_obj->id, users => [] };
      $self->_id2name->{ $role_obj->id } = $role;
   }

   $attr = { include_columns => [ q(role.role), q(user.username) ],
             join            => [ q(role), q(user) ] };
   $rs   = $self->dbic_user_roles_model->search( {}, $attr );

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

CatalystX::Usul::Roles::DBIC - Role management database storage

=head1 Version

0.3.$Revision: 576 $

=head1 Synopsis

   use CatalystX::Usul::Roles::DBIC;

   my $class = CatalystX::Usul::Roles::DBIC;

   my $role_obj = $class->new( $app, $config );

=head1 Description

Methods to manipulate the I<roles> and I<user_roles> table in a
database using L<DBIx::Class>. This class implements the methods
required by it's base class

=head1 Subroutines/Methods

=head2 build_per_context_instance

Make copies of DBIC model references available only after the application
setup is complete

=head2 add_user_to_role

   $role_obj->add_user_to_role( $role, $user );

Adds the specified user to the specified role

=head2 create

   $role_obj->create( $role );

Creates a new role with the given name

=head2 delete

   $role_obj->delete( $role );

Deletes the specified role

=head2 remove_user_from_role

   $role_obj->remove_user_to_role( $role, $user );

Removes the specified user to the specifed role

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Roles>

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
