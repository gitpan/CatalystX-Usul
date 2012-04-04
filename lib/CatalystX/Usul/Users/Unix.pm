# @(#)$Id: Unix.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Users::Unix;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Users CatalystX::Usul::IPC);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(exception throw untaint_path);
use English qw(-no_match_vars);
use File::UnixAuth;
use MRO::Compat;
use TryCatch;

my %FEATURES  = ( fields  => { homedir => TRUE, shells => TRUE },
                  roles   => [ q(roles) ],
                  session => TRUE, );
my %FIELD_MAP =
   ( active           => q(active),        crypted_password => q(password),
     email_address    => q(email_address), first_name       => q(first_name),
     homedir          => q(homedir),       home_phone       => q(home_phone),
     last_name        => q(last_name),     location         => q(location),
     pgid             => q(pgid),          project          => q(project),
     shell            => q(shell),         uid              => q(id),
     username         => q(username),      work_phone       => q(work_phone),
   );

__PACKAGE__->mk_accessors( qw(binsdir common_home def_perms
                              passwd_file passwd_obj ppath
                              profdir shadow_file shadow_obj spath
                              _ptime _stime) );

sub new {
   my ($class, $app, $attrs) = @_; my $ac = $app->config || {};

   $attrs->{binsdir    } ||= $ac->{binsdir};
   $attrs->{common_home} ||= $class->catdir( NUL, qw(home common) );
   $attrs->{def_perms  } ||= oct q(0755);
   $attrs->{passwd_file} ||= $class->catdir( NUL, qw(etc passwd) );
   $attrs->{passwd_type} ||= q(SHA-512);
   $attrs->{profdir    } ||= $class->catdir( $ac->{ctrldir}, q(profiles) );
   $attrs->{shadow_file} ||= $class->catdir( NUL, qw(etc shadow) );
   $attrs->{_ptime     }   = 0;
   $attrs->{_stime     }   = 0;

   my $new = $class->next::method( $app, $attrs );

   $new->ppath( $new->_build_ppath( $new->passwd_file ) );
   $new->spath( $new->_build_spath( $new->shadow_file ) );

   $new->passwd_obj( $new->_build_passwd_obj );
   $new->shadow_obj( $new->_build_shadow_obj );

   return $new;
}

# Interface methods

sub assert_user {
   my ($self, @rest) = @_; return $self->_assert_user( @rest );
}

sub change_password {
   my ($self, @rest) = @_;

   # TODO: Write to temp file to hide command line
   my $out = $self->_run_as_root( q(update_password), @rest );

   $self->_reset_mod_times;
   return $out;
}

sub create {
   my ($self, $fields) = @_; $fields ||= {}; my ($out, $tmp);

   my $tempfile = $self->tempfile; my $user = $fields->{username};

   $self->_write_params( $tempfile->pathname, $fields );
   $out = $self->_run_as_root( q(create_account), $tempfile->pathname );
   $self->_reset_mod_times;

   if ($self->is_user( $user ) and $fields->{populate}) {
      $out .= "\n";
      $out .= $self->_run_as_root( q(populate_account), $tempfile->pathname );
   }

   # Add entry to the mail aliases file
   if ($self->is_user( $user ) and $fields->{email_address}) {
      $out .= "\n";
      (undef, $tmp) = $self->aliases->create( { %{ $fields }, name => $user } );
      $out .= $tmp;
   }

   return $out;
}

sub delete {
   my ($self, $user) = @_;

   try        { $self->aliases->delete( { name => $user } ) }
   catch ($e) { $self->log_error( exception $e ) }

   my $out = $self->_run_as_root( q(delete_account), $user );

   $self->_reset_mod_times;
   return $out;
}

sub disable_account {
   my ($self, $user) = @_;

   my $out = $self->_run_as_root( q(set_password), $user,
                                  NUL, q(*DISABLED*), TRUE );

   $self->_reset_mod_times;
   return $out;
}

sub get_features {
   return \%FEATURES;
}

sub get_field_map {
   return \%FIELD_MAP;
}

sub get_primary_rid {
   my ($self, $user) = @_; my $mcu = $self->_get_user_ref( $user );

   return $mcu ? $mcu->{pgid} : undef;
}

sub get_user {
   my ($self, $user, $verbose) = @_;

   my $new = bless { common_home => $self->common_home }, ref $self || $self;
   my $map = $self->get_field_map;

   $new->{ $_ } = $self->field_defaults->{ $_ } for (keys %{ $map });

   my $mcu = $self->_get_user_ref( $user ) or return $new;

   for (keys %{ $map }) {
      $verbose and $map->{ $_ } eq q(project)
         and $mcu->{project} = $self->_get_project( $mcu->{homedir} );
      $new->{ $_ } = $mcu->{ $map->{ $_ } };
   }

   return $new;
}

sub get_users_by_rid {
   my ($self, $rid) = @_; defined $rid or return ();

   my (undef, $rid2users) = $self->_load;

   return exists $rid2users->{ $rid } ? @{ $rid2users->{ $rid } } : ();
}

sub set_password {
   my ($self, $user, @rest) = @_;

   my $out = $self->_run_as_root( q(set_password), $user, NUL, @rest );

   $self->_reset_mod_times;
   return $out;
}

sub update {
   my ($self, $fields) = @_; my $tempfile = $self->tempfile;

   $self->_write_params( $tempfile->pathname, $fields );

   my $out = $self->_run_as_root( q(update_account), $tempfile->pathname );

   $self->_reset_mod_times;
   return $out;
}

sub user_report {
   my ($self, $args) = @_; my $cmd;

   $cmd  = $self->suid.' -c account_report';
   $cmd .= $args->{debug} ? ' -D' : ' -n';
   $cmd .= ' -- "'.$args->{path}.'" '.($args->{type} ? $args->{type} : q(text));

   return $self->run_cmd( $cmd, { async => TRUE,
                                  debug => $args->{debug},
                                  err   => q(out),
                                  out   => $self->tempname } )->out;
}

# Private methods

sub _build_passwd_obj {
   my $self = shift;

   $self->ppath or throw 'Passwd file path not specified';

   return File::UnixAuth->new( ioc_obj     => $self, path => $self->ppath,
                               source_name => q(passwd) );
}

sub _build_ppath {
   my ($self, $path) = @_;

   $path = untaint_path( $path || $self->passwd_file );
   $path or throw 'File path not specified';
   -f $path or throw error => 'File [_1] not found', args => [ $path ];

   return $path;
}

sub _build_shadow_obj {
   my $self = shift; $self->spath or return Class::Null->new;

   return File::UnixAuth->new( ioc_obj     => $self, path => $self->spath,
                               source_name => q(shadow) );
}

sub _build_spath {
   my ($self, $path) = @_;

   $path = untaint_path( $path || $self->shadow_file );
   $path or throw 'Shadow file path not specified';

   return -f $path ? $path : undef;
}

sub _get_project {
   my ($self, $home) = @_; $home or return;

   my $path = $self->io( $self->catfile( $home, q(.project) ) );

   return NUL unless ($path->is_file and not $path->empty);

   return $path->chomp->lock->getline;
}

sub _load {
   my $self = shift; my $key = __PACKAGE__.q(::_load);

   $self->lock->set( k => $key );

   $self->_should_update or return $self->_cache_results( $key );

   try {
      # Empty the cache contents
      delete $self->cache->{ $_ } for (keys %{ $self->cache });

      my $source = $self->passwd_obj->source;
      my $data   = $self->passwd_obj->load->{passwd};

      for my $user (keys %{ $data }) {
         my $mcu = $self->cache->{users}->{ $user } = $data->{ $user };

         $mcu->{username     } = $user;
         $mcu->{email_address} = $self->make_email_address( $user );
         $self->cache->{rid2users}->{ $mcu->{pgid} } ||= [];
         push @{ $self->cache->{rid2users}->{ $mcu->{pgid} } }, $user;
         $self->cache->{uid2name}->{ $mcu->{id} } = $user;
      }

      $source = $self->shadow_obj->source;
      $data   = $self->spath && -r $self->spath
              ? $self->shadow_obj->load->{shadow} : {};

      for my $user (keys %{ $self->cache->{users} }) {
         my $user_data = $data->{ $user };
         my $mcu       = $self->cache->{users}->{ $user };

         for (@{ $source->attributes }) {
            $mcu->{ $_ } = defined $user_data && defined $user_data->{ $_ }
                         ? $user_data->{ $_ } : $source->defaults->{ $_ };
         }

         $mcu->{active  } = $mcu->{password} =~ m{ [*!] }mx ? FALSE : TRUE;
      }
   }
   catch ($e) { $self->lock->reset( k => $key ); throw $e }

   return $self->_cache_results( $key );
}

sub _reset_mod_times {
   my $self = shift; $self->_ptime( 0 ); $self->_stime( 0 ); return;
}

sub _run_as_root {
   my ($self, $method, @args) = @_;

   my $cmd = [ $self->suid, ($self->debug ? q(-D) : q(-n)), q(-c),
               $method, q(--), map { "'".$_."'" } @args ];
   my $out = $self->run_cmd( $cmd, { err => q(out) } )->out;

   $self->debug and $self->log->debug( $out );

   return $out;
}

sub _should_update {
   my $self  = shift;
   my $mtime = $self->status_for( $self->ppath )->{mtime};
   my $should_update = $mtime == $self->_ptime ? FALSE : TRUE;

   $self->_ptime( $mtime );

   if ($self->spath and -r $self->spath) {
      $mtime = $self->status_for( $self->spath )->{mtime};
      $should_update = $mtime == $self->_stime ? $should_update : TRUE;
      $self->_stime( $mtime );
   }

   return $self->cache->{dirty} ? TRUE : $should_update;
}

sub _validate_password {
   my ($self, $user, $password) = @_; my $temp = $self->tempfile;

   try        { $temp->print( $password ) }
   catch ($e) { $self->log_error( 'Path '.$temp->pathname." cannot write\n" );
                return FALSE }

   my $cmd = $self->suid.' -n -c authenticate -- "'.$user.'" "stdin"';

   try { $self->run_cmd( $cmd, { err => q(out), in => $temp->pathname } ) }
   catch ($e) { $self->debug and $self->log_debug( $e ); return FALSE }

   return TRUE;
}

sub _write_params {
   my ($self, $path, $fields) = @_;

   $self->file_dataclass_schema->dump( { data => $fields, path => $path } );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Users::Unix - User data store for the Unix OS

=head1 Version

0.6.$Revision: 1165 $

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

=head2 activate_account

Activation is not currently supported by this store

=head2 assert_user

Returns a domain model user object for the specified user or
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

=head2 disable_account

Sets the password to C<*DISABLED*> disabling the account

=head2 get_features

Returns a hashref of features supported by this store. Can be checked using
L<supports|CatalystX::Usul::Model>

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

=head2 user_report

Calls the setuserid wrapper to create a report about the user accounts
in this store

=head2 _validate_password

Called by L<check_password|CatalystX::Usul::Users/check_password> in the
parent class. This method execute the external setuid root wrapper
to validate the password provided

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
