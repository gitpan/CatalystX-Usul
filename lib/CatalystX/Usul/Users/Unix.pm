# @(#)Ident: ;

package CatalystX::Usul::Users::Unix;

use strict;
use version; our $VERSION = qv( sprintf '0.13.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions   qw( exception throw );
use English                      qw( -no_match_vars );
use CatalystX::Usul::Constraints qw( File Path );
use File::Spec::Functions        qw( catdir );
use File::UnixAuth;
use TryCatch;

extends q(CatalystX::Usul::Users);

has 'get_features' => is => 'ro',   isa => HashRef,
   default         => sub { { fields  => { homedir => TRUE, shells => TRUE },
                              roles   => [ 'roles' ],
                              session => TRUE, } };

has 'passwd_file'  => is => 'lazy', isa => File, coerce => TRUE,
   default         => sub { [ NUL, qw(etc passwd) ] };

has 'passwd_obj'   => is => 'lazy', isa => Object;

has '+passwd_type' => default => 'SHA-512';

has '+role_class'  => default => sub { 'CatalystX::Usul::Roles::Unix' };

has 'shadow_file'  => is => 'lazy', isa => File, coerce => TRUE,
   default         => sub { [ NUL, qw( etc shadow ) ] };

has 'shadow_obj'   => is => 'lazy', isa => Object;


has '_field_map'   => is => 'ro',   isa => HashRef,
   default         => sub { { password => 'crypted_password', id => 'uid', } };

# Interface methods
sub assert_user {
   return shift->_assert_user( @_ );
}

sub change_password {
   my ($self, @rest) = @_; my ($username) = @rest;

   # TODO: Write to temp file to hide command line
   my $out = $self->_run_as_root( q(update_password), @rest );

   $self->_reset_mod_times;
   return ($out, $username);
}

sub create {
   my ($self, $fields) = @_; $fields ||= {};

   my $username = $fields->{username};
   my $tempfile = $self->_write_params( $fields );
   my $out      = $self->_run_as_root( q(create_account), $tempfile->pathname );

   $self->_reset_mod_times;

   $self->is_user( $username ) and $fields->{populate}
      and $out .= "\n".$self->_run_as_root
         ( q(populate_account), $tempfile->pathname );

   # Add entry to the mail aliases file
   $self->is_user( $username ) and $fields->{email_address}
      and $out .= "\n".($self->aliases->create
                        ( { %{ $fields }, name => $username } ))[ 1 ];

   return ($out, $username);
}

sub delete {
   my ($self, $username) = @_;

   try        { $self->aliases->delete( { name => $username } ) }
   catch ($e) { $self->log->error( exception $e ) }

   my $out = $self->_run_as_root( q(delete_account), $username );

   $self->_reset_mod_times;
   return ($out, $username);
}

sub disable_account {
   my ($self, $username) = @_;

   my $out = $self->_run_as_root( q(set_password), $username,
                                  NUL, q(*DISABLED*), TRUE );

   $self->_reset_mod_times;
   return $out;
}

sub get_primary_rid {
   my ($self, $username) = @_; my $user_ref = $self->_get_user_ref( $username );

   return $user_ref ? $user_ref->{pgid} : undef;
}

sub get_users_by_rid {
   my ($self, $rid) = @_; defined $rid or return ();

   my (undef, $rid2users) = $self->_load;

   return exists $rid2users->{ $rid } ? @{ $rid2users->{ $rid } } : ();
}

sub set_password {
   my ($self, $username, @rest) = @_;

   my $out = $self->_run_as_root( q(set_password), $username, NUL, @rest );

   $self->_reset_mod_times;
   return ($out, $username);
}

sub update {
   my ($self, $fields) = @_; my $tempfile = $self->_write_params( $fields );

   my $out = $self->_run_as_root( q(update_account), $tempfile->pathname );

   $self->_reset_mod_times;
   return ($out, $fields->{username});
}

sub user_report {
   my ($self, $args) = @_; my $cmd;

   $cmd  = $self->config->suid.' -c account_report '.$self->_debug_flag;
   $cmd .= ' -- "'.$args->{path}.'" '.($args->{type} ? $args->{type} : q(text));

   return $self->run_cmd( $cmd, { async => TRUE,
                                  debug => $args->{debug},
                                  err   => q(out),
                                  out   => $self->file->tempname } )->out;
}

sub validate_password {
   my ($self, $username, $password) = @_; my $temp = $self->file->tempfile;

   try        { $temp->print( $password ) }
   catch ($e) { $self->log->error( 'Path '.$temp->pathname." cannot write\n" );
                return FALSE }

   my $cmd = $self->config->suid." -nc authenticate -- '${username}' 'stdin'";

   try { $self->run_cmd( $cmd, { err => q(out), in => $temp->pathname } ) }
   catch ($e) { $self->log->warn( $e ); return FALSE }

   return TRUE;
}

# Private methods
sub _build_passwd_obj {
   return File::UnixAuth->new( builder     => $_[ 0 ],
                               path        => $_[ 0 ]->passwd_file,
                               source_name => q(passwd) );
}

sub _build_shadow_obj {
   my $self = shift; $self->shadow_file->exists or return Class::Null->new;

   return File::UnixAuth->new( builder     => $self,
                               path        => $self->shadow_file,
                               source_name => q(shadow) );
}

sub _debug_flag {
   return $_[ 0 ]->debug ? q(-D) : q(-n);
}

sub _load {
   my $self = shift; my $key = __PACKAGE__.q(::_load);

   $self->lock->set( k => $key );

   $self->_should_update or return $self->_cache_results( $key );

   try {
      # Empty the cache contents. Leave the mtime and dirty flags
      for (grep { not m{ \A _ }mx } keys %{ $self->cache }) {
         delete $self->cache->{ $_ };
      }

      my $cache       = $self->cache;
      my $passwd_data = $self->passwd_obj->load->{passwd};
      my $passwd_src  = $self->passwd_obj->source;
      my $map         = $self->_field_map;
      my $shadow_data;
      my $shadow_src;

      if ($self->shadow_file->exists) {
         $shadow_data = $self->shadow_obj->load->{shadow};
         $shadow_src  = $self->shadow_obj->source;
      }
      else { $shadow_data = {}; $shadow_src = Class::Null->new }

      for my $username (keys %{ $passwd_data }) {
         my $mcu  = $cache->{users}->{ $username } ||= {};
         my $user = $passwd_data->{ $username };

         for my $col ($passwd_src->columns) {
            my $v = defined $user->{ $col } ? $user->{ $col }
                                            : $passwd_src->defaults->{ $col };

            defined $v and $mcu->{ $map->{ $col } || $col } = $v;
         }

         $mcu->{username     } = $username;
         $mcu->{email_address} = $self->aliases->email_address( $username );
         $cache->{uid2name }->{ $mcu->{uid } }   = $username;
         $cache->{rid2users}->{ $mcu->{pgid} } ||= [];
         push @{ $cache->{rid2users}->{ $mcu->{pgid} } }, $username;
         $user = $shadow_data->{ $username } || {};

         for my $col ($shadow_src->columns) {
            my $v = defined $user->{ $col } ? $user->{ $col }
                                            : $passwd_src->defaults->{ $col };

            defined $v and $mcu->{ $map->{ $col } || $col } = $v;
         }

         $mcu->{active} = $mcu->{crypted_password} =~ m{ [*!] }mx
                        ? FALSE : TRUE;
      }
   }
   catch ($e) { $self->lock->reset( k => $key ); throw $e }

   return $self->_cache_results( $key );
}

sub _reset_mod_times {
   my $self = shift;

   $self->cache->{_ptime} = 0; $self->cache->{_stime} = 0;
   return;
}

sub _run_as_root {
   my ($self, $method, @args) = @_;

   my $cmd = [ $self->config->suid, $self->_debug_flag, '-c',
               $method, '--', map { "'${_}'" } @args ];
   my $out = $self->run_cmd( $cmd, { err => q(out) } )->out;

   $self->debug and $self->log->debug( $out );

   return $out;
}

sub _should_update {
   my $self  = shift;
   my $cache = $self->cache;
   my $mtime = $self->passwd_file->stat->{mtime};
   my $updt  = delete $cache->{_dirty} ? TRUE : FALSE;

   $updt or $updt = $mtime == ($cache->{_ptime} || 0) ? FALSE : TRUE;
   $cache->{_ptime} = $mtime;

   if ($self->shadow_file->exists) {
      $mtime = $self->shadow_file->stat->{mtime};
      $updt or $updt = $mtime == ($cache->{_stime} || 0) ? $updt : TRUE;
      $cache->{_stime} = $mtime;
   }

   return $updt;
}

sub _write_params {
   my ($self, $fields) = @_; my $path = $self->file->tempfile;

   $self->file->dataclass_schema->dump( { data => $fields, path => $path } );

   return $path;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Users::Unix - User data store for the Unix OS

=head1 Version

Describes v0.13.$Rev: 1 $

=head1 Synopsis

   use CatalystX::Usul::Users::Unix;

   my $class = CatalystX::Usul::Users::Unix;

   my $user_obj = $class->new( $attr );

=head1 Description

User storage model for the Unix operating system

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item field_map

A hash ref which maps the field names used by the user model onto the field
names used by the OS

=item get_features

A hash ref which details the features supported by the OS user data store

=item passwd_file

A path to a file coerced from an array ref which defaults to F</etc/passwd>

=item passwd_obj

An instance of L<File::UnixAuth>

=item passwd_type

The name of the hashing algorithm to use when creating new accounts. Defaults
to C<SHA-512>

=item role_class

Overrides the attribute in the parent class. This is the name of the class
that manages roles (groups). It defaults to I<CatalystX::Usul::Roles::Unix>

=item shadow_file

A path to a file coerced from an array ref which defaults to F</etc/shadow>

=item shadow_obj

An instance of L<File::UnixAuth>

=back

=head1 Subroutines/Methods

=head2 assert_user

Returns a domain model user object for the specified user or
throws an exception if the user does not exist

=head2 change_password

Calls the suid wrapper to change the users password

=head2 check_password

Calls the suid wrapper to check the users password

=head2 create

Calls the suid wrapper to create a new user account, populate the
home directory and create a mail alias for the users email address to
the new account

=head2 delete

Calls the suid wrapper to delete the users mail alias and then delete
the account

=head2 disable_account

Sets the password to C<*DISABLED*> disabling the account

=head2 get_features

Returns a hashref of features supported by this store. Can be checked using
L<supports|CatalystX::Usul::Model>

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

Calls the suid wrapper to set the users password to a given value

=head2 update

Calls the suid wrapper to update the user account information

=head2 user_report

Calls the suid wrapper to create a report about the user accounts
in this store

=head2 validate_password

Called by L<check_password|CatalystX::Usul::Users/check_password> in the
parent class. This method execute the external setuid root wrapper
to validate the password provided

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Users>

=item L<CatalystX::Usul::Moose>

=item L<CatalystX::Usul::Constraints>

=item L<File::UnixAuth>

=item L<TryCatch>

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
