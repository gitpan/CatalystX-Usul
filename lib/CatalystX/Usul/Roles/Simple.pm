# @(#)$Id: Simple.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Roles::Simple;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Roles);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(is_member throw);
use File::DataClass::Schema;
use Scalar::Util qw(blessed);

__PACKAGE__->mk_accessors( qw(ctrldir file path schema) );

sub new {
   my ($class, $app, $attrs) = @_; my $ac = $app->config || {};

   $attrs->{ctrldir} ||= $ac->{ctrldir};
   $attrs->{file   } ||= q(roles-simple.json);

   my $new = $class->next::method( $app, $attrs );

   $new->path  ( $new->_build_path   );
   $new->schema( $new->_build_schema );
   return $new;
}

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

   is_member $role, $user_obj->roles or return;

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
   my $path = $self->path || $self->catfile( $self->ctrldir, $self->file );

   $path          or throw 'Path not specified';
   blessed $path  or $path = $self->io( $path );
   $path->is_file or $path->touch;
   $path->is_file or throw error => 'Path [_1] not found', args => [ $path ];
   return $path;
}

sub _build_schema {
   my $self    = shift;
   my $attrs   = {
      ioc_obj  => $self,
      path     => $self->path,
      result_source_attributes => {
         roles => { attributes => [ qw(users) ],
                    defaults   => { users => [] }, }, },
      storage_class => q(JSON),
   };

   return File::DataClass::Schema->new( $attrs );
}

sub _load {
   my $self = shift; return ({ %{ $self->schema->load->{roles} || {} } });
}

sub _roles {
   return shift->schema->resultset( q(roles) );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Roles::Simple - Role management file storage

=head1 Version

0.6.$Revision: 1165 $

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
