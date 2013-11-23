# @(#)Ident: ;

package CatalystX::Usul::Roles::DBIC;

use strict;
use version; our $VERSION = qv( sprintf '0.14.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(is_member sub_name throw);
use TryCatch;

extends q(CatalystX::Usul::Roles);

has 'dbic_role_model'       => is => 'ro', isa => Object,
   builder                  => '_build_dbic_role_model',
   lazy                     => TRUE;

has 'dbic_user_roles_model' => is => 'ro', isa => Object,
   builder                  => '_build_dbic_user_roles_model',
   lazy                     => TRUE;

# Factory methods

sub add_user_to_role {
   my ($self, $rolename, $username) = @_;

   return $self->_execute( sub {
      my $role_id = $self->get_rid( $rolename )
         or throw error => 'Role [_1] unknown', args => [ $rolename ];
      my $user    = $self->users->find_user( $username );

      is_member $rolename, $user->roles and return;

      $self->dbic_user_roles_model->create
         ( { role_id => $role_id, user_id => $user->uid } );
   } );
}

sub create {
   my ($self, $rolename) = @_;

   return $self->_execute( sub {
      $self->dbic_role_model->create( { role => $rolename } );
   } );
}

sub delete {
   my ($self, $rolename) = @_;

   return $self->_execute( sub {
      my $role = $self->dbic_role_model->search( { role => $rolename } );

      defined $role
         or throw error => 'Role [_1] unknown', args => [ $rolename ];

      $role->delete;
   } );
}

sub remove_user_from_role {
   my ($self, $rolename, $username) = @_;

   return $self->_execute( sub {
      my $role_id = $self->get_rid( $rolename )
         or throw error => 'Role [_1] unknown', args => [ $rolename ];
      my $user    = $self->users->find_user( $username );

      is_member $rolename, $user->roles or return;

      my $user_roles = $self->dbic_user_roles_model->search
         ( { role_id => $role_id, user_id => $user->uid } );

      defined $user_roles
         or throw error => 'User [_1] not in role [_2]',
                  args  => [ $username, $rolename ];

      $user_roles->delete;
   } );
}

# Private methods

sub _build_dbic_role_model {
   return $_[ 0 ]->users->dbic_role_model;
}

sub _build_dbic_user_roles_model {
   return $_[ 0 ]->users->dbic_user_roles_model;
}

sub _execute {
   my ($self, $f) = @_; my $key = __PACKAGE__.q(::_execute); my $res;

   $self->debug and $self->log->debug( __PACKAGE__.q(::).(sub_name 1) );
   $self->lock->set( k => $key );

   try        { $res = $f->() }
   catch ($e) { $self->lock->reset( k => $key ); throw $e }

   $self->cache->{_dirty} = TRUE;
   $self->lock->reset( k => $key );
   return $res;
}

sub _load {
   my $self = shift; my $key = __PACKAGE__.q(::_load);

   $self->lock->set( k => $key ); my $cache = $self->cache;

   delete $cache->{_dirty} or return $self->_cache_results( $key );

   delete $cache->{ $_ } for (keys %{ $cache });

   try {
      my ($role_obj, $user_roles_obj);
      my $rs = $self->dbic_role_model->search();

      while (defined ($role_obj = $rs->next)) {
         my $role = $role_obj->get_column( q(role) );

         $cache->{roles}->{ $role } = { id => $role_obj->id, users => [] };
         $cache->{id2name}->{ $role_obj->id } = $role;
      }

      my $attr = { include_columns => [ q(role_rel.role),
                                        q(user_rel.username) ],
                   join            => [ q(role_rel), q(user_rel) ] };

      $rs = $self->dbic_user_roles_model->search( {}, $attr );

      while (defined ($user_roles_obj = $rs->next)) {
         my $role = $user_roles_obj->role_rel->role;
         my $user = $user_roles_obj->user_rel->username;

         $cache->{user2role}->{ $user }
            or $cache->{user2role}->{ $user } = [];

         push @{ $cache->{roles}->{ $role }->{users} }, $user;
         push @{ $cache->{user2role}->{ $user } }, $role;
      }
   }
   catch ($e) { $self->lock->reset( k => $key ); throw $e }

   return $self->_cache_results( $key );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Roles::DBIC - Role management database storage

=head1 Version

Describes v0.14.$Rev: 1 $

=head1 Synopsis

   use CatalystX::Usul::Roles::DBIC;

   my $class = CatalystX::Usul::Roles::DBIC;

   my $role_obj = $class->new( $attr );

=head1 Description

Methods to manipulate the I<roles> and I<user_roles> table in a
database using L<DBIx::Class>. This class implements the methods
required by it's base class

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item dbic_role_model

The schema object for the roles table

=item dbic_user_roles_model

The schema object form the user_roles join table

=back

=head1 Subroutines/Methods

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

Removes the specified user to the specified role

=head1 Diagnostics

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
