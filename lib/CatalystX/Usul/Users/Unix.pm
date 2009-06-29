# @(#)$Id: Unix.pm 577 2009-06-10 00:15:54Z pjf $

package CatalystX::Usul::Users::Unix;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 577 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Users CatalystX::Usul::Utils);

use CatalystX::Usul::MailAliases;
use Class::C3;
use English qw(-no_match_vars);
use File::Copy;
use Lingua::EN::NameParse;
use Unix::PasswdFile;

my $NUL       = q();
my %FEATURES  = ( fields  => { homedir => 1, shells => 1 },
                  roles   => [ q(roles) ],
                  session => 1, );
my %FIELD_MAP =
   ( active           => q(active),        crypted_password => q(password),
     email_address    => q(email_address), first_name       => q(first_name),
     homedir          => q(homedir),       home_phone       => q(home_phone),
     uid              => q(id),            last_name        => q(last_name),
     location         => q(location),      pgid             => q(pgid),
     project          => q(project),       shell            => q(shell),
     username         => q(username),      work_phone       => q(work_phone),
   );

__PACKAGE__->config( base_id     => 100,
                     def_perms   => oct q(0755),
                     common_home => q(/home/common),
                     passwd_file => q(/etc/passwd),
                     mail_domain => q(localhost),
                     shadow_file => q(/etc/shadow),
                     uid_inc     => 1,
                     _ptime      => 0,
                     _stime      => 0 );

__PACKAGE__->mk_accessors( qw(base_id binsdir
                              common_home def_perms passwd_file
                              passwd_type ppath profdir mail_domain
                              shadow_file spath uid_inc _ptime _stime) );

sub new {
   my ($self, $app, $config) = @_;

   my $new     = $self->next::method( $app, $config );
   my $profdir = $self->catdir( $app->config->{ctrldir}, q(profiles) );

   $new->binsdir( $new->config->{binsdir}                           );
   $new->ppath  ( $new->_get_passwd_file( $new->passwd_file )       );
   $new->profdir( $new->config->{profdir} || $profdir               );
   $new->spath  ( $new->_get_shadow_file( $new->shadow_file )       );

   return $new;
}

# Interface methods

sub activate_account {
   my ($self, $key) = @_;

   $self->throw( 'Activation not supported' );
   return;
}

sub change_password {
   my ($self, $user, $old, $new) = @_; my $cmd;

   # TODO: Write to temp file to hide command line
   $cmd  = $self->suid.' -n -c update_password -- '.$user.' "';
   $cmd .= $old.'" "'.$new.'" ';
   $self->run_cmd( $cmd );
   return;
}

sub create {
   my ($self, $flds) = @_; my ($cmd, $e, $tempfile, $user);

   $tempfile = $self->tempfile;

   eval { XMLout( $flds,
                  NoAttr        => 1,
                  SuppressEmpty => 1,
                  OutputFile    => $tempfile->pathname,
                  RootName      => q(config) ) };

   $self->throw( $e ) if ($e = $self->catch);

   $cmd  = $self->suid.' -n -c create_account -- '.$tempfile->pathname;
   $self->run_cmd( $cmd, { err => q(out) } );
   $user = $flds->{username};

   if ($self->is_user( $user ) and $flds->{populate}) {
      $cmd  = $self->suid.' -n -c populate_account -- '.$tempfile->pathname;
      $self->run_cmd( $cmd, { err => q(out) } );
   }

   # Add entry to the mail aliases file
   if ($self->is_user( $user ) and $flds->{email_address}) {
      $self->aliase_domain->create( $flds );
   }

   return;
}

sub delete {
   my ($self, $user) = @_; my $e;

   eval { $self->alias_domain->delete( $user ) };

   my $cmd = $self->suid.' -n -c delete_account -- '.$user;
   $self->run_cmd( $cmd, { err => q(out) } );
   return;
}

sub get_features {
   return \%FEATURES;
}

sub get_primary_rid {
   my ($self, $user) = @_;

   return unless ($user);

   my ($cache) = $self->_load;

   return exists $cache->{ $user } ? $cache->{ $user }->{pgid} : undef;
}

sub get_user {
   my ($self, $user, $verbose) = @_; my ($cache) = $self->_load; my $new;

   $new->{ $_ } = $self->field_defaults->{ $_ } for (keys %FIELD_MAP);

   bless $new, ref $self || $self;

   return $new unless ($user && exists $cache->{ $user });

   for (keys %FIELD_MAP) {
      if ($verbose and $_ eq q(project)) {
         my $val = $self->_get_project( $cache->{ $user }->{homedir} );

         $cache->{ $user }->{project} = $val if (defined $val);
      }

      $new->{ $_ } = $cache->{ $user }->{ $FIELD_MAP{ $_ } };
   }

   return $new;
}

sub get_users_by_rid {
   my ($self, $rid) = @_;

   return () unless (defined $rid);

   my (undef, $rid2users) = $self->_load;

   return exists $rid2users->{ $rid } ? @{ $rid2users->{ $rid } } : ();
}

sub list {
   my ($self, $pattern) = @_; my (%found, @users); my ($cache) = $self->_load;

   $pattern ||= q( .+ );

   for (sort keys %{ $cache }) {
      if (not $found{ $_ } and $_ =~ m{ $pattern }mx) {
         push @users , $_; $found{ $_ } = 1;
      }
   }

   return \@users;
}

sub set_password {
   my ($self, $user, $passwd, $flag) = @_; my $cmd;

   $cmd  = $self->suid.' -n -c set_password -- '.$user;
   $cmd .= ' "" "'.$passwd.'" '.$flag;
   $self->run_cmd( $cmd );
   return;
}

sub update {
   my ($self, $flds) = @_; my ($cmd, $e, $tempfile);

   $tempfile = $self->tempfile;

   eval { XMLout( $flds,
                  NoAttr        => 1,
                  SuppressEmpty => 1,
                  OutputFile    => $tempfile->pathname,
                  RootName      => q(config) ) };

   $self->throw( $e ) if ($e = $self->catch);

   $cmd  = $self->suid.' -n -c update_account -- '.$tempfile->pathname;
   $self->run_cmd( $cmd, { err => q(out) } );
   return;
}

sub update_password {
   my ($self, @rest) = @_; my ($force, $user) = @rest; my $passwd_obj;

   $self->throw( 'No user specified' ) unless ($user);

   my ($cache) = $self->_load; my $mcu = $cache->{ $user };

   unless ($mcu) {
      $self->throw( error => 'User [_1] unknown', args => [ $user ] );
   }

   $mcu->{password} = $self->encrypt_password( @rest );

   if ($self->spath && -f $self->spath) {
      $mcu->{pwlast} = $force ? 0 : int time / 86_400;
      $self->_update_shadow( q(update), $user );
      return;
   }

   $self->lock->set( k => $self->ppath );
   $passwd_obj = $self->_get_passwd_obj;
   $passwd_obj->user( $user,
                      $mcu->{password},
                      $mcu->{id      },
                      $mcu->{pgid    },
                      $self->_get_gecos( $mcu ),
                      $mcu->{homedir },
                      $mcu->{shell   } );
   $passwd_obj->commit( backup => '.bak' );
   $self->lock->reset( k => $self->ppath );
   return;
}

sub user_report {
   my ($self, $args) = @_; my $cmd;

   $cmd  = $self->suid.' -c account_report ';
   $cmd .= $args->{debug} ? '-D ' : '-n ';
   $cmd .= '-- "'.$args->{path}.'" '.($args->{type} ? $args->{type} : q(text));

   return $self->run_cmd( $cmd, { async => 1,
                                  debug => $args->{debug},
                                  err   => q(out),
                                  out   => $self->tempname } )->out;
}

sub validate_password {
   my ($self, $user, $password) = @_; my ($cmd, $e);
   my $temp = $self->tempfile;

   eval { $temp->print( $password ) };

   if ($e = $self->catch) {
      $self->log_error( 'Cannot write '.$temp->pathname."\n" );
      return 0;
   }

   $cmd  = $self->suid.' -n -c authenticate -- "'.$user.'" "stdin" 0<';
   $cmd .= $temp->pathname;

   eval { $self->run_cmd( $cmd, { err => q(out) } ) };

   return 1 unless ($e = $self->catch);

   $self->log_debug( $e->as_string( 2 ) ) if ($self->debug);

   return 0;
}

# Private methods

sub _get_gecos {
   my ($self, $params) = @_;

   my $gecos = $params->{first_name}.q( ).$params->{last_name};

   if ($params->{location} || $params->{work_phone} || $params->{home_phone}) {
      $gecos .= q(,).($params->{location  } || q(?));
      $gecos .= q(,).($params->{work_phone} || q(?));
      $gecos .= q(,).($params->{home_phone} || q(?));
   }

   return $gecos;
}

sub _get_passwd_file {
   my ($self, $path) = @_; $path ||= $self->passwd_file;

   if ($path =~ m{ \A ([[:print:]]+) \z }mx) { $path = $1  } # now untainted

   $self->throw( 'No file path specified' ) unless ($path);

   unless (-f $path) {
      $self->throw( error => 'File [_1] not found', args => [ $path ] );
   }

   return $path;
}

sub _get_passwd_obj {
   my $self       = shift;
   my $mode       = $EFFECTIVE_USER_ID == 0 ? q(rw) : q(r);
   my $passwd_obj = Unix::PasswdFile->new( $self->ppath,
                                           locking => q(none),
                                           mode    => $mode );

   $self->throw( 'Cannot create password file object' ) unless ($passwd_obj);

   return $passwd_obj;
}

sub _get_project {
   my ($self, $home) = @_;

   return unless ($home);

   my $path = $self->catfile( $home, '.project' );

   return $NUL unless (-s $path);

   return $self->io( $path )->chomp->lock->getline;
}

sub _get_shadow_file {
   my ($self, $path) = @_; $path ||= $self->shadow_file;

   if ($path =~ m{ \A ([[:print:]]+) \z }mx) { $path = $1  } # now untainted

   $self->throw( 'No file path specified' ) unless ($path);

   unless (-f $path) {
      $self->throw( error => 'File [_1] not found', args => [ $path ] );
   }

   return $path;
}

sub _load {
   my $self = shift;
   my ($cache, $e, $email, $file, @flds, $fullname, $home, $io, $line, $locn);
   my ($mcu, $mtime, %names, $passwd_obj, $rid2users, $uid2name);
   my ($updt, $user, $work);

   $self->lock->set( k => $self->ppath );
   $mtime = $self->status_for( $self->ppath )->{mtime};
   $updt  = $mtime == $self->_ptime ? 0 : 1;
   $self->_ptime( $mtime );

   if ($self->spath && -r $self->spath) {
      $mtime = $self->status_for( $self->spath )->{mtime};
      $updt  = $mtime == $self->_stime ? $updt : 1;
      $self->_stime( $mtime );
   }

   unless ($updt) {
      $cache     = { %{ $self->_cache     } };
      $rid2users = { %{ $self->_rid2users } };
      $uid2name  = { %{ $self->_uid2name  } };
      $self->lock->reset( k => $self->ppath );
      return ($cache, $rid2users, $uid2name);
   }

   $self->_cache( {} ); $self->_rid2users( {} ); $self->_uid2name( {} );
   $passwd_obj = $self->_get_passwd_obj;

   my %args = ( auto_clean => 1, force_case => 1, lc_prefix => 1 );
   my $name_parse_ref = Lingua::EN::NameParse->new( %args );

   for $user ($passwd_obj->users) {
      @flds = $passwd_obj->user( $user );
      ($fullname, $locn, $work, $home) = split m{ , }mx, $flds[3], 4;

      if ($fullname && !$name_parse_ref->parse( $fullname )) {
         %names = $name_parse_ref->components;
      }
      else { %names = ( given_name_1 => $user, surname_1 => q(), ) }

      # TODO: Should pull this from aliases_model keyed by $user
      $email  = $names{given_name_1} || $user;
      $email .= $names{surname_1} ? q(.).$names{surname_1} : q();
      $email .= q(@).$self->mail_domain;

      $mcu = $self->_cache->{ $user } = {};
      $mcu->{email_address} = $email;
      $mcu->{first_name   } = $names{given_name_1} || $user;
      $mcu->{homedir      } = $flds[4] || $NUL;
      $mcu->{home_phone   } = $home    || $NUL;
      $mcu->{id           } = defined $flds[1] ? $flds[1] : -1;
      $mcu->{last_name    } = $names{surname_1};
      $mcu->{location     } = $locn    || $NUL;
      $mcu->{password     } = $flds[0] || $NUL;
      $mcu->{pgid         } = defined $flds[2] ? $flds[2] : -1;
      $mcu->{project      } = $NUL;
      $mcu->{pwafter      } = 99_999;
      $mcu->{pwdisable    } = 0;
      $mcu->{pwlast       } = 13_267;
      $mcu->{pwnext       } = 0;
      $mcu->{pwwarn       } = 7;
      $mcu->{pwexpires    } = 0;
      $mcu->{shell        } = $flds[5] || $NUL;
      $mcu->{username     } = $user;
      $mcu->{work_phone   } = $work    || $NUL;
      $mcu->{active       } = $mcu->{password} =~ m{ [*!] }mx ? 0 : 1;

      $self->passwd_type( q(md5) ) if ($mcu->{password} =~ m{ \A \$ 1 \$ }msx);

      push @{ $self->_rid2users->{ $mcu->{pgid} } }, $user;
      $self->_uid2name->{ $mcu->{id} } = $user;
   }

   unless ($self->spath && -r $self->spath){
      $cache     = { %{ $self->_cache     } };
      $rid2users = { %{ $self->_rid2users } };
      $uid2name  = { %{ $self->_uid2name  } };
      $self->lock->reset( k => $self->ppath );
      return ($cache, $rid2users, $uid2name);
   }

   $file = eval { $self->io( $self->spath )->slurp };

   if ($e = $self->catch) {
      $self->log->error( 'Cannot read '.$self->spath );
      $cache     = { %{ $self->_cache     } };
      $rid2users = { %{ $self->_rid2users } };
      $uid2name  = { %{ $self->_uid2name  } };
      $self->lock->reset( k => $self->ppath );
      return ($cache, $rid2users, $uid2name);
   }

   for $line (split m{ \n }mx, $file) {
      @flds             = split m{ : }mx, $line;
      $mcu              = $self->_cache->{ $flds[0] };
      $mcu->{password } = $flds[1] || q(*);
      $mcu->{pwlast   } = defined $flds[2] ? $flds[2] : 13_267;
      $mcu->{pwnext   } = defined $flds[3] ? $flds[3] : 0;
      $mcu->{pwafter  } = defined $flds[4] ? $flds[4] : 99_999;
      $mcu->{pwwarn   } = defined $flds[5] ? $flds[5] : 7;
      $mcu->{pwexpires} = defined $flds[6] ? $flds[6] : 0;
      $mcu->{pwdisable} = defined $flds[7] ? $flds[7] : 0;
      $mcu->{active   } = $mcu->{password} =~ m{ [*!] }mx ? 0 : 1;

      $self->passwd_type( q(md5) ) if ($mcu->{password} =~ m{ \A \$ 1 \$ }msx);
   }

   $cache     = { %{ $self->_cache     } };
   $rid2users = { %{ $self->_rid2users } };
   $uid2name  = { %{ $self->_uid2name  } };
   $self->lock->reset( k => $self->ppath );
   return ($cache, $rid2users, $uid2name);
}

sub _update_shadow {
   my ($self, $cmd, $user) = @_; my ($cache, $e, $file, $io, $line, $mcu);

   ($cache) = $self->_load; $mcu = $cache->{ $user };
   $self->lock->set( k => $self->spath );

   eval {
      copy( $self->spath, $self->spath.'.bak' ) if (-s $self->spath);
      $file = $self->io( $self->spath )->slurp;
      $io   = $self->io( $self->spath.'.tmp' )->perms( oct q(0600) );

      for $line (split m{ \n }mx, $file) {
         if ($line =~ m{ \A $user : }mx) {
            next if ($cmd eq 'delete');

            $line  = $user.q(:).$mcu->{password}.q(:).$mcu->{pwlast}.q(:);
            $line .= $mcu->{pwnext}.q(:).$mcu->{pwafter}.q(:);
            $line .= $mcu->{pwwarn}.q(:).$mcu->{pwexpires}.q(:);
            $line .= $mcu->{pwdisable};
         }

         $io->println( $line );
      }

      $io->close;
      move( $self->spath.'.tmp', $self->spath) if (-s $self->spath.'.tmp');
   };

   if ($e = $self->catch) {
      $self->lock->reset( k => $self->spath ); $self->throw( $e );
   }

   $self->lock->reset( k => $self->spath );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Users::Unix - User data store for the Unix OS

=head1 Version

0.3.$Revision: 577 $

=head1 Synopsis

   use CatalystX::Usul::Users::Unix;

   my $class = CatalystX::Usul::Users::Unix;

   my $user_obj = $class->new( $app, $config );

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

Updates the users password only if the new one has not been used
before or there is an administrative override. Updates the
F<shadow> file file if it is used, or the F<passwd> file otherwise

=head2 user_report

Calls the setuserid wrapper to create a report about the user accounts
in this store

=head2 validate_password

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

=item L<Lingua::EN::NameParse>

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
