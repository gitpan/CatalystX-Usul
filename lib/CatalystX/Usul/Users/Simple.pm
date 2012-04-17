# @(#)$Id: Simple.pm 1181 2012-04-17 19:06:07Z pjf $

package CatalystX::Usul::Users::Simple;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.7.%d', q$Rev: 1181 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Users);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(throw);
use File::DataClass::Schema;
use Scalar::Util qw(blessed);

my %FEATURES  = ( roles => [ q(roles) ], session => TRUE, );
my %FIELD_MAP =
   ( active           => q(active),        crypted_password => q(password),
     email_address    => q(email_address), first_name       => q(first_name),
     home_phone       => q(home_phone),    last_name        => q(last_name),
     location         => q(location),      project          => q(project),
     username         => q(username),      work_phone       => q(work_phone),
   );

__PACKAGE__->mk_accessors( qw(ctrldir file path schema) );

sub new {
   my ($class, $app, $attrs) = @_; my $ac = $app->config || {};

   $attrs->{ctrldir} ||= $ac->{ctrldir};
   $attrs->{file   } ||= q(users-simple.json);

   my $new = $class->next::method( $app, $attrs );

   $new->path  ( $new->_build_path   );
   $new->schema( $new->_build_schema );
   return $new;
}

# Interface methods

sub assert_user {
   my $self     = shift;
   my $user     = shift or throw 'User not specified';
   my $user_obj = $self->_users->find( { name => $user } )
      or throw error => 'User [_1] unknown', args => [ $user ];

   return $user_obj;
}

sub create {
   my ($self, $args) = @_; my $fields;

   my $user    = $args->{username};
   my $pname   = delete $args->{profile};
   my $profile = $self->profiles->find( $pname );
   my $passwd  = $args->{password} || $profile->passwd || $self->def_passwd;

   $passwd !~ m{ [*!] }msx
      and $args->{password} = $self->_encrypt_password( $passwd );

   $fields->{ $_ } = $args->{ $_ } for (values %FIELD_MAP);
   $fields->{name} = $user;

   $self->_users->create( $fields );

   $self->roles->is_member_of_role( $pname, $user )
      or $self->roles->add_user_to_role( $pname, $user );

   $profile->roles or return;

   for my $role (split m{ , }mx, $profile->roles) {
      $self->roles->is_member_of_role( $role, $user )
         or $self->roles->add_user_to_role( $role, $user );
   }

   return;
}

sub delete {
   my ($self, $user) = @_; $self->assert_user( $user )->delete; return;
}

sub get_features {
   return \%FEATURES;
}

sub get_field_map {
   return \%FIELD_MAP;
}

sub update {
   my ($self, $args) = @_;

   my $user_obj = $self->assert_user( $args->{username} );

   for (values %FIELD_MAP) {
      exists $args->{ $_ } and $user_obj->$_( $args->{ $_ } );
   }

   $user_obj->update;
   return;
}

sub update_password {
   my ($self, @rest) = @_; my ($force, $user) = @rest;

   my $user_obj = $self->assert_user( $user );

   $user_obj->password( $self->encrypt_password( @rest ) );
#   $user_obj->pwlast( $force ? 0 : int time / 86_400 );
   $user_obj->update;
   return;
}

sub user_report {
   my ($self, $args) = @_; return;
}

# Private methods

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
         users => { attributes => [ values %FIELD_MAP ],
                    defaults   => {}, }, },
      storage_class => q(JSON),
   };

   return File::DataClass::Schema->new( $attrs );
}

sub _load {
   my $self = shift; return ({ %{ $self->schema->load->{users} || {} } });
}

sub _users {
   return shift->schema->resultset( q(users) );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Users::Simple - User data store in local files

=head1 Version

0.7.$Revision: 1181 $

=head1 Synopsis

   use CatalystX::Usul::Users::Unix;

   my $class = CatalystX::Usul::Users::Unix;

   my $user_obj = $class->new( $attrs, $app );

=head1 Description

User storage model for the Unix operating system. This model makes use
of a B<setuid> wrapper to read and write the files; F</etc/passwd>,
F</etc/shadow> and F</etc/group>. It inherits from
L<CatalystX::Usul::Model::Identity::Users> and implements the required
list of factory methods

=head1 Subroutines/Methods

=head2 new

Constructor defined four attributes; I<binsdir> the path to the programs,
I<ppath> the path to the passwd file, I<profdir> the path to the directory
which contains boilerplate "dot" file for populating the home directory,
and I<spath> the path to the shadow password file

=head2 get_features

Returns a hashref of features supported by this store. Can be checked using
L<supports|CatalystX::Usul::Model>

=head2 activate_account

Activation is not currently supported by this store

=head2 assert_user

Returns a L<File::DataClass> user object for the specified user or
throws an exception if the user does not exist

=head2 change_password

Calls the setuserid wrapper to change the users password

=head2 check_password

Calls the setuserid wrapper to check the users password

=head2 create

Calls the setuserid wrapper to create a new user account, populate the
home directory and create a mail alias for the users email address to
the new account

=head2 delete

Calls the setuserid wrapper to delete the users mail alias and then delete
the account

=head2 get_field_map

Returns a reference to the package scoped variable C<%FIELD_MAP>

=head2 get_primary_rid

Returns the users primary role (group) id from the F</etc/passwd> file

=head2 get_user

Returns a hashref containing the data fields for the requested user. Maps
the field name specific to the store to those used by the identity model

=head2 get_users_by_rid

Returns the list of users the share the given primary role (group) id

=head2 is_user

Returns true if the user exists, false otherwise

=head2 list

Returns the list of usernames matching the given pattern

=head2 set_password

Calls the setuserid wrapper to set the users password to a given value

=head2 update

Calls the setuserid wrapper to update the user account information

=head2 update_password

Updates the users password in the database

=head2 user_report

Calls the setuserid wrapper to create a report about the user accounts
in this store

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model::Identity::Users>

=item L<Unix::PasswdFile>

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
