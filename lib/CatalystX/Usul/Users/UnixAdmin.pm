# @(#)Ident: UnixAdmin.pm 2014-01-10 21:27 pjf ;

package CatalystX::Usul::Users::UnixAdmin;

use strict;
use version; our $VERSION = qv( sprintf '0.17.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Constraints qw( Path );
use CatalystX::Usul::Functions   qw( io throw untaint_path );
use CatalystX::Usul::Moose;
use Class::Usul::Time;
use English                      qw( -no_match_vars );
use File::Copy;
use File::Path                   qw( remove_tree );
use File::Spec::Functions        qw( catdir catfile );
use TryCatch;

extends q(CatalystX::Usul::Users::Unix);

has 'def_perms' => is => 'ro',   isa => Num, default => oct q(0755);

has 'profdir'   => is => 'lazy', isa => Path, coerce => TRUE;

# Called from suid wrapper program

sub create_account {
   my ($self, $param_path) = @_;

   my $params  = $self->_read_params( $param_path );
   my $user    = $params->{username};

   $self->is_user( $user )
      and throw error => 'User [_1] already exists', args => [ $user ];

   my $pname   = $params->{profile}
      or throw 'User profile not specified';
   my $gid     = $self->roles->get_rid( $pname )
      or throw 'Primary group not specified';
   my $profile = $self->profiles->find( $pname );
   my $uid     = $self->_get_new_uid( $profile->baseid, $profile->increment )
      or throw 'New uid not available';
   my $passwd  = $params->{password} || $profile->passwd || $self->def_passwd;

   $passwd !~ m{ [*!] }msx and $passwd = $self->_encrypt_password( $passwd );

   if ($self->spath) {
      my $fields = { name => $user, password => $passwd };

      $self->_update_shadow( q(create), $fields ); $passwd = q(x);
   }

   my $fields  = { name       => $user,
                   password   => $passwd,
                   id         => $uid,
                   pgid       => $gid,
                   first_name => $params->{first_name} || NUL,
                   last_name  => $params->{last_name } || NUL,
                   location   => $params->{location  } || NUL,
                   work_phone => $params->{work_phone} || NUL,
                   home_phone => $params->{home_phone} || NUL,
                   homedir    => $self->_get_homedir( $profile, $params ),
                   shell      => $params->{shell} || $profile->shell };

   $self->_update_passwd( q(create), $fields );

   # Add entries to the group file
   if ($profile->roles) {
      for my $role (split m{ , }mx, $profile->roles) {
         $self->roles->is_member_of_role( $role, $user )
            or $self->roles->add_user_to_role( $role, $user );
      }
   }

   return 'User [_1] account created';
}

sub delete_account {
   my ($self, $user) = @_; my $home_dir;

   my $user_obj = $self->assert_user( $user );

   $home_dir = $user_obj->homedir and -d $home_dir
      and remove_tree( $home_dir, {} );

   my @roles = $self->roles->get_roles( $user ); shift @roles;

   $self->roles->remove_user_from_role( $_, $user ) for (@roles);

   $self->_update_shadow( q(delete), { name => $user } ) if ($self->spath);
   $self->_update_passwd( q(delete), { name => $user } );
   return 'User [_1] account deleted';
}

sub populate_account {
   my ($self, $path) = @_;

   my $params   = $self->_read_params( $path );
   my $user     = $params->{username};
   my $user_obj = $self->assert_user( $user );
   my $home     = $user_obj->homedir
      or throw error => 'User [_1] no home directory', args => [ $user ];
   my $profile  = $self->profiles->find( $params->{profile} );
   my $pat      = $profile->common_home || q(dont_match_this);

   $home =~ m{ \A $pat }mx and return;

   my $uid      = $user_obj->uid;
   my $gid      = $user_obj->pgid;
   my $group    = $self->roles->get_name( $gid )
      or throw error => 'User [_1] invalid primary group [_2]',
               args  => [ $user, $gid || q(NULL) ];
   my $mode     = $profile->permissions
                ? oct $profile->permissions : oct $self->def_perms;

   try {
      $self->lock->set( k => $home );

      -d $home or mkdir $home;
      -d $home or throw error => 'Path [_1] cannot create', args => [ $home ];

      my $s_flds = io( $home )->stat;

      chown $uid, $gid, $home if ($s_flds->{uid} <=> $uid
                                  or $s_flds->{gid} <=> $gid);

      chmod $mode, $home;
      $path = catfile( $self->profdir, $group.'.profile' );

      if (-f $path) {
         $self->_backup( 'file', catfile( $home, '.profile' ),
                         $path, $uid, $gid, q(0644) );
      }

      $path = catfile( $self->profdir, 'kshrc' );

      if (-f $path) {
         $self->_backup( 'file', catfile( $home, '.kshrc' ),
                         $path, $uid, $gid, q(0644) );
      }

      $path = catfile( $self->profdir, 'logout' );

      if (-f $path) {
         $self->_backup( 'file', catfile( $home, '.logout' ),
                         $path, $uid, $gid, q(0755) );
      }

      $path = catfile( $self->profdir, 'Xdefaults' );

      if (-f $path) {
         $self->_backup( 'file', catfile( $home, '.Xdefaults' ),
                         $path, $uid, $gid, q(0644) );
      }

      $path = catfile( $self->profdir, 'exrc' );

      if (-f $path) {
         $self->_backup( 'file', catfile( $home, '.exrc' ),
                         $path, $uid, $gid, q(0644) );
      }

      $path = catfile( $self->profdir, 'emacs' );

      if (-f $path) {
         $self->_backup( 'file', catfile( $home, '.emacs' ),
                         $path, $uid, $gid, q(0644) );
      }

      if ($params->{project}) {
         $self->_backup( 'text', catfile( $home, '.project' ),
                         $params->{project}."\n", $uid, $gid, q(0644) );
      }

      $self->lock->reset( k => $home );
   }
   catch ($e) { $self->lock->reset( k => $home ); throw $e }

   return "Home directory ${home} populated";
}

sub update_account {
   my ($self, $path) = @_;

   my $params   = $self->_read_params( $path );
   my $user     = $params->{username};
   my $user_obj = $self->assert_user( $user, TRUE );
   my $passwd   = $self->spath && -f $self->spath ? q(x) : $user_obj->password;
   my $fields   = { name       => $user,
                    password   => $passwd,
                    id         => $user_obj->uid,
                    pgid       => $user_obj->pgid,
                    first_name => $params->{first_name} || NUL,
                    last_name  => $params->{last_name } || NUL,
                    location   => $params->{location  } || NUL,
                    work_phone => $params->{work_phone} || NUL,
                    home_phone => $params->{home_phone} || NUL,
                    homedir    => $params->{homedir   } || NUL,
                    shell      => $params->{shell     } || NUL };

   $self->_update_passwd( q(update), $fields );

   if ($params->{homedir} and -d $params->{homedir}) {
      my $io = io [ $params->{homedir}, q(.project) ];

      if ($params->{project}) {
         $io->println( $params->{project} )->chmod( 0644 );
         chown $user_obj->uid, $user_obj->pgid, $io->pathname;
      }
      else { $io->unlink }
   }

   return 'User [_1] account updated';
}

sub update_password {
   my ($self, @rest) = @_; my ($force, $user) = @rest;

   $user or throw 'User not specified';

   my $mcu = $self->_get_user_ref( $user )
      or throw error => 'User [_1] unknown', args => [ $user ];

   $mcu->{password} = $self->encrypt_password( @rest );

   if ($self->spath) {
      $mcu->{pwlast} = $force ? 0 : int time / 86_400;
      $self->_update_shadow( q(update), { %{ $mcu }, name => $user } );
   }
   else {
      $self->_update_passwd( q(update), { %{ $mcu }, name => $user } );
   }

   return 'User [_1] password updated';
}

sub user_report {
   my ($self, $path, $fmt) = @_; my (@flds, $line, $out);

   $path ||= q(-); $fmt ||= q(text);

   my %lastl = ();
   my @lines = ();
   my $sdate = NUL;
   my $res   = $self->_list_previous;

   for $line (split m{ \n }mx, $res->out) {
      $line =~ s{ \s+ }{ }gmx; @flds = split SPC, $line;

      if ($line =~ m{ \A wtmp \s+ begins }mx) {
         shift @flds; shift @flds; $sdate = join SPC, @flds;
      }
      else {
         if (length $line > 0) {
            $line = $flds[2].SPC.$flds[3].SPC.$flds[4].SPC.$flds[5];
            $lastl{ $flds[0] } = $line unless (exists $lastl{ $flds[0] });
         }
      }
   }

   for my $user (@{ $self->list }) {
      my $user_obj = $self->get_user( $user, TRUE );
      my $passwd   = $user_obj->crypted_password;
      my $trunc    = substr $user, 0, 8;

      @flds = ( q(C) );
   TRY: {
      if ($passwd =~ m{ DISABLED }imsx) { $flds[ 0 ] = q(D); last TRY }
      if ($passwd =~ m{ EXPIRED }imsx)  { $flds[ 0 ] = q(E); last TRY }
      if ($passwd =~ m{ LEFT }imsx)     { $flds[ 0 ] = q(L); last TRY }
      if ($passwd =~ m{ NOLOGIN }imsx)  { $flds[ 0 ] = q(N); last TRY }
      if ($passwd =~ m{ [*!] }msx)      { $flds[ 0 ] = q(N); last TRY }
      } # TRY

      $flds[ 1 ]  = $user;
      $flds[ 2 ]  = $user_obj->first_name.SPC.$user_obj->last_name;
      $flds[ 3 ]  = $user_obj->location;
      $flds[ 4 ]  = $fmt ne q(csv)
                  ? substr $user_obj->work_phone, -5, 5
                  : $user_obj->work_phone;
      $flds[ 5 ]  = $user_obj->project;
      $flds[ 6 ]  = exists $lastl{ $trunc }
                  ? $lastl{ $trunc } : 'Never Logged In';
      $flds[ 6 ]  = $user_obj->homedir && -d $user_obj->homedir
                  ? $flds[6] : 'No Home Dir.';

      if ($fmt ne q(csv)) {
         $line = sprintf '%s %-8.8s %-20.20s %-10.10s %5.5s %-14.14s %-16.16s',
                         map { defined $_ ? $_ : q(~) } @flds[ 0 .. 6 ];
      }
      else { $line = join q(,), map { defined $_ ? $_ : NUL } @flds }

      push @lines, $line;
   }

   @lines = sort @lines; my $count = @lines;

   if ($fmt eq 'csv') {
      unshift @lines, '#S,Login,Full Name,Location,Extn,Role,Last Login';
   }
   else {
      # Prepend header
      unshift @lines, q(_) x 80;
      $line  = 'S Login    Full Name            Location    ';
      $line .= 'Extn Role           Last Login';
      unshift @lines, $line;
      $line  = 'Host: '.$self->config->host.' History Begins: '.$sdate;
      $line .= ' Printed: '.time2str();
      unshift @lines, $line;

      # Append footer
      push @lines, NUL, NUL;
      $line  = 'Status field key: C = Current, D = Disabled, ';
      $line .= 'E = Expired, L = Left, N = NOLOGIN';
      push @lines, $line, '                  U = Unused';
      push @lines, "Total users ${count}";
   }

   if ($path eq q(-)) { $out = (join "\n", @lines)."\n" }
   else {
      io( $path )->perms( oct q(0640) )->println( join "\n", @lines  );
      $out = "Report ${path} contains ${count} users";
   }

   return $out;
}

# Private methods

sub _backup {
   my ($self, $type, $path, $src, $uid, $gid, $mode) = @_;

   $mode = oct $mode.NUL; my $cnt = 1;

   if (-e $path and $type ne q(link)) {
      $cnt++ while (-e "${path}.OLD-${cnt}");

      move( $path, "${path}.OLD-${cnt}" ) or throw $ERRNO;
   }

 TRY: {
   if ($type eq q(dir)) {
      mkdir $path or throw $ERRNO;
      chown $uid, $gid, $path;
      chmod $mode, $path;
      last TRY;
   }

   if ($type eq q(file)) {
      -r $src or throw error => 'File [_1] not found', args => [ $src ];
      copy( $src, $path ) or throw $ERRNO;
      chown $uid, $gid, $path;
      chmod $mode, $path;
      last TRY;
   }

   if ($type eq q(link)) {
      CORE::symlink( $src, $path );
      $self->run_cmd( [ qw(chown -h), $uid.q(:).$gid, $path ] );
      last TRY;
   }

   if ($type eq q(text)) {
      io( $path )->lock->print( $src );
      chown $uid, $gid, $path;
      chmod $mode, $path;
      last TRY;
   }
   } # Try

   return;
}

sub _build_profdir {
   return untaint_path catdir( $_[ 0 ]->config->ctrldir, q(profiles) );
}

sub _get_homedir {
   my ($self, $profile, $params) = @_;

   my $home = $profile->homedir;
      $home = $home ne $profile->common_home
            ? catdir( $home, $params->{username} ) : $home;
      $home = $params->{homedir} || $home;

   return $home;
}

sub _get_new_uid {
   my ($self, $base_id, $inc) = @_; $base_id ||= 100; $inc ||= 1;

   my ($cached_users) = $self->_load; my $new_id = $base_id; my @uids = ();

   push @uids, $cached_users->{ $_ }->{uid} for (keys %{ $cached_users });

   for my $uid (sort { $a <=> $b } @uids) {
      if ($uid >= $base_id) { last if ($uid > $new_id); $new_id = $uid + $inc }
   }

   return $new_id;
}

sub _list_previous {
   my $self = shift; return $self->ipc->popen( q(last) );
}

sub _read_params {
   my ($self, $path) = @_;

   my $params = $self->file->dataclass_schema->load( $path );
   my $user   = $params->{username} or throw 'User not specified';

   $user =~ m{ [ :] }mx and throw error => 'User [_1] invalid name',
                                  args  => [ $user ];

   return $params;
}

sub _update_passwd {
   my ($self, $method, $args) = @_;

   $self->passwd_obj->resultset->$method( $args );
   return;
}

sub _update_shadow {
   my ($self, $method, $args) = @_;

   $self->shadow_obj->resultset->$method( $args );
   return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Users::UnixAdmin - Set uid root methods for account manipulation

=head1 Version

Describes v0.17.$Rev: 1 $

=head1 Synopsis

   use CatalystX::Usul::Users::UnixAdmin;

=head1 Description

The public methods are called from a program running setuid root. The
methods enable the management of OS accounts

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item C<def_perms>

The default permissions applied to new home directories, C<0755>

=item C<profdir>

A path coerced from an array ref that contains the files used to provision
a new account

=back

=head1 Subroutines/Methods

=head2 create_account

   $self->create_account( $path );

Creates an OS account. The given path is an XML file containing the
account parameters. Account profiles are obtained from the
C<< $self->profile_domain >> object. New entries are added to the C<passwd>
file, the C<shadow> file (if it is being used) and the C<group> file

=head2 delete_account

   $self->delete_account( $user ):

Deletes an OS account. The accounts home directory is removed, the users
entries in the C<group> file are removed as are the entries in the
C<passwd> and C<shadow> files

=head2 populate_account

   $self->create_account( $path );

Creates the new users home directory and populates it with some "dot"
files if templates for such exist in the C<< $self->profdir >>
directory. Does not create a directory if the users home directory matches
C<< $profile->common_home >>. Account parameters are read from the XML file
given by C<$path>

=head2 update_account

   $self->update_account( $path );

Account parameters are read from the XML file given by C<$path>. Updates
entries in the C<passwd> file

=head2 update_password

   $self->update_password( $force, $user, $old_pw, $new_pw, $encrypted );

Updates the users password only if the new one has not been used
before or there is an administrative override. Updates the
F<shadow> file file if it is used, or the F<passwd> file otherwise

=head2 user_report

   $self->user_report( $path, $format );

Creates a report of user accounts. Outputs to C<$path> or C<STDOUT> if
C<$path> is C<->. Format is either C<text> or C<csv>

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Users::Unix>

=item L<CatalystX::Usul::Moose>

=item L<Class::Usul::Time>

=item L<CatalystX::Usul::Constraints>

=item L<File::Path>

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
