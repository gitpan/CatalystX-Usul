# @(#)Ident: ;

package CatalystX::Usul::Roles::Simple;

use strict;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions   qw(is_member throw);
use CatalystX::Usul::Constraints qw(File);

extends q(CatalystX::Usul::Roles);

has 'filename' => is => 'ro', isa => Str, default => q(roles-simple.json);

has 'path'     => is => 'ro', isa => File, builder => '_build_path',
   lazy        => TRUE;

has 'schema'   => is => 'ro', isa => Object, builder => '_build_schema',
   lazy        => TRUE;

# Factory methods

sub add_user_to_role {
   my ($self, $role, $user) = @_;

   my $user_obj = $self->users->find_user( $user );

   is_member $role, $user_obj->roles and return;

   $self->_roles->push
      ( { items => [ $user ], list => q(users), name => $role } );
   return;
}

sub create {
   my ($self, $role) = @_; $self->_roles->create( { name => $role } ); return;
}

sub delete {
   my ($self, $role) = @_; $self->_assert_role( $role )->delete; return;
}

sub remove_user_from_role {
   my ($self, $role, $user) = @_;

   my $user_obj = $self->users->find_user( $user );

#   is_member $role, $user_obj->roles or return;

   $self->_roles->splice
      ( { items => [ $user ], list => q(users), name => $role } );
   return;
}

# Private methods

sub _assert_role {
   my $self     = shift;
   my $role     = shift or throw 'Role not specified';
   my $role_obj = $self->_roles->find( { name => $role } )
      or throw error => 'Role [_1] unknown', args => [ $role ];

   return $role_obj;
}

sub _build_path {
   my $self = shift;
   my $path = $self->io( [ $self->config->ctrldir, $self->filename ] );

   $path->is_file or $path->touch;
   $path->is_file or throw error => 'Path [_1] not found', args => [ $path ];
   return $path;
}

sub _build_schema {
   my $attr    = {
      path     => $_[ 0 ]->path,
      result_source_attributes => {
         roles => { attributes => [ qw(users) ],
                    defaults   => { users => [] }, }, },
      storage_class => q(JSON),
   };

   return $_[ 0 ]->file->dataclass_schema( $attr );
}

sub _load {
   my $self  = shift;
   my $cache = $self->cache;
   my $mtime = $self->path->stat->{mtime};
   my $updt  = delete $cache->{_dirty} ? TRUE : FALSE;

   $updt or $updt = $mtime == ($cache->{_mtime} || 0) ? FALSE : TRUE;

   $updt or return ($cache->{roles}); $cache->{_mtime} = $mtime;

   $cache->{roles} = { %{ $self->schema->load->{roles} || {} } };

   return ($cache->{roles});
}

sub _roles {
   return $_[ 0 ]->schema->resultset( q(roles) );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Roles::Simple - Role management file storage

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   use CatalystX::Usul::Roles::Simple;

   my $class = CatalystX::Usul::Roles::Simple;

   my $role_obj = $class->new( $attr );

=head1 Description

Methods to manipulate user roles in the simple user store. This class
implements the methods required by it's base class
L<CatalystX::Usul::Roles>

=head1 Configuration and Environment

Defines the following list of attributes

=over 3

=item C<filename>

A string which defaults to F<roles-simple.json>

=item C<path>

A path to a file which contains the roles database

=item C<schema>

A L<File::DataClass::Schema> object

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

=item L<CatalystX::Usul::Moose>

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
