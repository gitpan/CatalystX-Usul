# @(#)Ident: Simple.pm 2014-01-15 16:34 pjf ;

package CatalystX::Usul::Users::Simple;

use strict;
use version; our $VERSION = qv( sprintf '0.17.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions   qw( io throw );
use CatalystX::Usul::Constraints qw( File );
use Unexpected::Functions        qw( PathNotFound Unspecified );

extends q(CatalystX::Usul::Users);

has 'field_map'    => is => 'ro',   isa => HashRef, default => sub { {} };

has 'filename'     => is => 'ro',   isa => Str, default => q(users-simple.json);

has 'get_features' => is => 'ro',   isa => HashRef,
   default         => sub { { roles => [ q(roles) ], session => TRUE, } };

has 'path'         => is => 'lazy', isa => File;

has 'schema'       => is => 'lazy', isa => Object;

# Interface methods

sub activate_account {
   my ($self, $file) = @_;

   my $username = $self->dequeue_activation_file( $file );

   $self->_execute( sub {
      my $user = $self->assert_user( $username ); $user->active( TRUE );

      $user->update; return;
   } );

   return ('User [_1] account activated', $username);
}

sub assert_user {
   my $self     = shift;
   my $username = shift or throw class => Unspecified, args => [ 'user' ];
   my $user = $self->_users->find( { name => $username } )
      or throw error => 'User [_1] unknown', args => [ $username ];

   return $user;
}

sub create {
   my ($self, $args) = @_; my $fields;

   my $username = $args->{username};
   my $p_name   = delete $args->{profile};
   my $profile  = $self->profiles->find( $p_name );
   my $passwd   = $args->{password} || $profile->passwd || $self->def_passwd;
   my $src      = $self->_source;

   $args->{crypted_password} = $passwd !~ m{ [*!] }msx
                             ? $self->_encrypt_password( $passwd ) : $passwd;

   for (@{ $src->attributes }) {
      defined $args->{ $_ } and $fields->{ $_ } = $args->{ $_ };
   }

   $fields->{name} = $username; $self->_users->create( $fields );

   $self->roles->is_member_of_role( $p_name, $username )
      or $self->roles->add_user_to_role( $p_name, $username );

   if ($profile->roles) {
      for my $role (split m{ , }mx, $profile->roles) {
         $self->roles->is_member_of_role( $role, $username )
            or $self->roles->add_user_to_role( $role, $username );
      }
   }

   return ('User [_1] account created', $username);
}

sub delete {
   $_[ 0 ]->assert_user( $_[ 1 ] )->delete;

   return ('User [_1] account deleted', $_[ 1 ]);
}

sub update {
   my ($self, $args) = @_; my $src = $self->_source;

   my $user = $self->assert_user( $args->{username} );

   for (grep { exists $args->{ $_ } } @{ $src->attributes }) {
      $user->$_( $args->{ $_ } );
   }

   $user->update; return ('User [_1] account updated', $user->username);
}

sub update_password {
   my ($self, @rest) = @_; my ($force, $username) = @rest;

   my $user = $self->assert_user( $username );

   $user->crypted_password( $self->encrypt_password( @rest ) );
   $user->pwlast( $force ? 0 : int time / 86_400 );
   $user->update; return ('User [_1] password updated', $username);
}

sub user_report {
   my ($self, $args) = @_; my $class = blessed $self;

   throw error => 'Class [_1] user report not supported', args => [ $class ];

   return;
}

# Private methods

sub _build_path {
   my $self = shift;
   my $path = io [ $self->config->ctrldir, $self->filename ];

   $path->is_file or $path->touch;
   $path->is_file or throw class => PathNotFound, args => [ $path ];
   return $path;
}

sub _build_schema {
   my $attr    = {
      path     => $_[ 0 ]->path,
      result_source_attributes => {
         users => { attributes => [ $_[ 0 ]->user_attributes ],
                    defaults   => {}, }, },
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

   $updt or return ($cache->{users}); $cache->{_mtime} = $mtime;

   $cache->{users} = { %{ $self->schema->load->{users} || {} } };

   return ($cache->{users});
}

sub _source {
   return $_[ 0 ]->schema->source( q(users) );
}

sub _users {
   return $_[ 0 ]->schema->resultset( q(users) );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Users::Simple - User data store in local files

=head1 Version

Describes v0.17.$Rev: 1 $

=head1 Synopsis

   use CatalystX::Usul::Users::Simple;

   my $class = CatalystX::Usul::Users::Simple;

   my $user = $class->new( $attr );

=head1 Description

Stores user account information in a JSON file in the control directory

=head1 Configuration and Environment

Defined the following attributes

=over 3

=item field_map

A hash ref which maps the field names used by the user model onto the field
names used by the data store

=item filename

The name of the file containing the user accounts. A string which
defaults to I<users-simple.json>

=item get_features

A hash ref which details the features supported by this user data store

=item path

A path to a file that contains the user accounts

=item schema

An instance of L<File::DataClass::Schema> using the JSON storage class

=back

=head1 Subroutines/Methods

=head2 activate_account

Searches the user store for the supplied user name and if it exists sets
the active column to true

=head2 assert_user

Returns a L<CatalystX::Usul::Response::User> object for the
specified user or throws an exception if the user does not exist

=head2 change_password

Changes the users password

=head2 check_password

Checks the users password

=head2 create

Create a new user account, populate the home directory and create a
mail alias for the users email address to the new account

=head2 delete

Delete the users mail alias and then delete the account

=head2 get_primary_rid

Returns the users primary role (group) id from the user account file

=head2 get_user

Returns a hashref containing the data fields for the requested user. Maps
the field name specific to the store to those used by the user model

=head2 get_users_by_rid

Returns the list of users the share the given primary role (group) id

=head2 is_user

Returns true if the user exists, false otherwise

=head2 list

Returns the list of usernames matching the given pattern

=head2 set_password

Sets the users password to a given value

=head2 update

Updates the user account information

=head2 update_password

Updates the users password in the database

=head2 user_report

Creates a report about the user accounts in this store

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Users>

=item L<CatalystX::Usul::Moose>

=item L<CatalystX::Usul::Constraints>

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
