# @(#)$Id: DBIC.pm 1139 2012-03-28 23:49:18Z pjf $

package CatalystX::Usul::Roles::DBIC;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1139 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Roles);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(is_member sub_name throw);
use TryCatch;

__PACKAGE__->mk_accessors( qw(dbic_role_class dbic_user_roles_class
                              dbic_role_model dbic_user_roles_model) );

sub new {
   my ($class, $app, $attrs) = @_;

   my $new = $class->next::method( $app, $attrs );

   $new->cache->{dirty} = TRUE;
   $new->dbic_role_model( $app->model( $new->dbic_role_class ) );
   $new->dbic_user_roles_model( $app->model( $new->dbic_user_roles_class ) );

   return $new;
}

# Factory methods

sub add_user_to_role {
   my ($self, $role, $user) = @_;

   return $self->_execute( sub {
      my $role_id  = $self->get_rid( $role )
         or throw error => 'Role [_1] unknown', args => [ $role ];
      my $user_obj = $self->users->find_user( $user );

      is_member $role, $user_obj->roles and return;

      $self->dbic_user_roles_model->create
         ( { role_id => $role_id, user_id => $user_obj->uid } );
   } );
}

sub create {
   my ($self, $role) = @_;

   return $self->_execute( sub {
      $self->dbic_role_model->create( { role => $role } );
   } );
}

sub delete {
   my ($self, $role) = @_;

   return $self->_execute( sub {
      my $role_obj = $self->dbic_role_model->search( { role => $role } );

      defined $role_obj
         or throw error => 'Role [_1] unknown', args => [ $role ];

      $role_obj->delete;
   } );
}

sub remove_user_from_role {
   my ($self, $role, $user) = @_;

   return $self->_execute( sub {
      my $role_id  = $self->get_rid( $role )
         or throw error => 'Role [_1] unknown', args => [ $role ];
      my $user_obj = $self->users->find_user( $user );

      is_member $role, $user_obj->roles or return;

      my $user_roles_obj = $self->dbic_user_roles_model->search
         ( { role_id => $role_id, user_id => $user_obj->uid } );

      defined $user_roles_obj
         or throw error => 'User [_1] not in role [_2]',
                  args  => [ $user, $role ];

      $user_roles_obj->delete;
   } );
}

# Private methods

sub _execute {
   my ($self, $f) = @_; my $key = __PACKAGE__.q(::_execute); my $res;

   $self->debug and $self->log_debug( __PACKAGE__.q(::).(sub_name 1) );
   $self->lock->set( k => $key );

   try        { $res = $f->() }
   catch ($e) { $self->lock->reset( k => $key ); throw $e }

   $self->cache->{dirty} = TRUE;
   $self->lock->reset( k => $key );
   return $res;
}

sub _load {
   my $self = shift; my $key = __PACKAGE__.q(::_load);

   $self->lock->set( k => $key );

   $self->cache->{dirty} or return $self->_cache_results( $key );

   my @keys = keys %{ $self->cache }; delete $self->cache->{ $_ } for (@keys);

   try {
      my ($role_obj, $user_roles_obj);
      my $rs = $self->dbic_role_model->search();

      while (defined ($role_obj = $rs->next)) {
         my $role = $role_obj->get_column( q(role) );

         $self->cache->{roles}->{ $role }
            = { id => $role_obj->id, users => [] };
         $self->cache->{id2name}->{ $role_obj->id } = $role;
      }

      my $attr = { include_columns => [ q(role_rel.role),
                                        q(user_rel.username) ],
                   join            => [ q(role_rel), q(user_rel) ] };

      $rs = $self->dbic_user_roles_model->search( {}, $attr );

      while (defined ($user_roles_obj = $rs->next)) {
         my $role = $user_roles_obj->role_rel->role;
         my $user = $user_roles_obj->user_rel->username;

         $self->cache->{user2role}->{ $user }
            or $self->cache->{user2role}->{ $user } = [];

         push @{ $self->cache->{roles}->{ $role }->{users} }, $user;
         push @{ $self->cache->{user2role}->{ $user } }, $role;
      }

      $self->cache->{dirty} = FALSE;
   }
   catch ($e) { $self->lock->reset( k => $key ); throw $e }

   return $self->_cache_results( $key );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Roles::DBIC - Role management database storage

=head1 Version

0.5.$Revision: 1139 $

=head1 Synopsis

   use CatalystX::Usul::Roles::DBIC;

   my $class = CatalystX::Usul::Roles::DBIC;

   my $role_obj = $class->new( $attrs, $app );

=head1 Description

Methods to manipulate the I<roles> and I<user_roles> table in a
database using L<DBIx::Class>. This class implements the methods
required by it's base class

=head1 Subroutines/Methods

=head2 new

Constructor

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
