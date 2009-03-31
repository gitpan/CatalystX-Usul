package CatalystX::Usul::Model::Identity::Suid;

# @(#)$Id: Suid.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Model::Identity::Users::Unix);
use Crypt::PasswdMD5;
use English qw(-no_match_vars);
use File::Copy;
use File::Path;
use XML::Simple;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

my @CSET = ( q(.), q(/), 0 .. 9, q(A) .. q(Z), q(a) .. q(z) );
my $NUL  = q();
my $SPC  = q( );

# Called from Suid.pm

sub create_account {
   my ($self, $path) = @_;
   my ($base_id, $e, $gecos, $gid, $home, $inc, $line, $params, $passwd);
   my ($passwd_obj, $pname, $profile, $role, $shell, $uid, $user);

   $params = $self->_read_params( $path );
   $user   = $params->{username};

   if ($self->is_user( $user )) {
      $self->throw( error => q(eUserExists), arg1 => $user );
   }

   $self->throw( q(eNoProfile) ) unless ($pname = $params->{profile});

   unless ($gid = $self->roles_obj->get_rid( $pname )) {
      $self->throw( q(eNoPrimaryGroup) );
   }

   $profile = $self->profiles_ref->find( $pname );
   $base_id = $profile->baseid    || $self->base_id;
   $inc     = $profile->increment || $self->uid_inc;

   unless ($uid = $self->_get_new_uid( $base_id, $inc )) {
      $self->throw( q(eNoNewUID) );
   }

   $passwd = $params->{password} || $profile->passwd || $self->def_passwd;

   if ($passwd !~ m{ \* }mx) {
      if ($self->passwd_type eq q(md5)) { $passwd = unix_md5_crypt( $passwd ) }
      else { $passwd = crypt $passwd, join $NUL, @CSET[ rand 64, rand 64 ] }
   }

   if ($self->spath) {
      # TODO: Default values should be in the profile
      if ($passwd =~ m{ \* }mx) { $line  = $user.q(:).$passwd.q(:::::::) }
      else { $line  = $user.q(:).$passwd.q(:0:7:40::90::) }

      $self->lock->set( k => $self->spath );
      copy( $self->spath, $self->spath.'.bak' ) if (-s $self->spath);

      eval { $self->io( $self->spath )->appendln( $line ) };

      if ($e = $self->catch) {
         $self->lock->reset( k => $self->spath ); $self->throw( $e );
      }

      $self->lock->reset( k => $self->spath );
      $passwd = q(x);
   }

   $gecos      = $self->_get_gecos( $params );
   $home       = $profile->homedir;
   $home       = $home ne $self->common_home
               ? $self->catdir( $home, $user ) : $home;
   $home       = $params->{homedir} || $home;
   $shell      = $params->{shell  } || $profile->shell;
   $passwd_obj = $self->_get_passwd_obj;
   $self->lock->set( k => $self->ppath );
   $passwd_obj->user( $user, $passwd, $uid, $gid, $gecos, $home, $shell );
   $passwd_obj->commit( backup => '.bak' );
   $self->lock->reset( k => $self->ppath );

   # Add entries to the group file
   if ($profile->roles) {
      for $role (split m{ , }mx, $profile->roles) {
         unless ($self->roles_obj->is_member_of_role( $role, $user )) {
            $self->roles_obj->f_add_user_to_role( $role, $user );
         }
      }
   }

   return 'Account created '.$user;
}

sub delete_account {
   my ($self, $user) = @_;
   my ($home_dir, $passwd_obj, $role, @roles, $user_ref);

   $self->throw( q(eNoUser) ) unless ($user);

   $user_ref = $self->f_get_user( $user );

   if ($user_ref->{username} eq q(unknown)) {
      $self->throw( error => q(eUnknownUser), arg1 => $user );
   }

   if ($home_dir = $user_ref->{homedir} and -d $home_dir) {
      rmtree( $home_dir, {} );
   }

   @roles = $self->roles_obj->get_roles( $user ); shift @roles;

   for $role (@roles) {
      $self->roles_obj->f_remove_user_from_role( $role, $user );
   }

   $passwd_obj = $self->_get_passwd_obj;
   $self->lock->set( k => $self->ppath );
   $passwd_obj->delete( $user );
   $passwd_obj->commit( backup => '.bak' );
   $self->lock->reset( k => $self->ppath );
   $self->_update_shadow( q(delete), $user );
   return 'Account deleted '.$user;
}

sub populate_account {
   my ($self, $path) = @_;
   my ($e, $home, $gid, $group, $mode, $params, $pat, $profile);
   my ($s_flds, $uid, $user, $user_ref);

   $params   = $self->_read_params( $path );
   $user     = $params->{username};
   $user_ref = $self->f_get_user( $user );

   if ($user_ref->{username} eq q(unknown)) {
      $self->throw( error => q(eUnknownUser), arg1 => $user );
   }

   unless ($home = $user_ref->{homedir}) {
      $self->throw( error => q(eNoHomeDir), arg1 => $user );
   }

   $pat = $self->common_home;

   return if ($home =~ m{ \A $pat }mx);

   $uid = $user_ref->{uid}; $gid = $user_ref->{pgid};

   unless ($group = $self->roles_obj->get_name( $gid )) {
      $gid ||= q(NULL);
      $self->throw( error => q(eInvalidPrimaryGroup),
                    arg1  => $gid, arg2 => $user );
   }

   $profile = $self->profiles_ref->find( $params->{profile} );
   $mode    = $profile->permissions
            ? oct $profile->permissions : oct $self->def_perms;
   $self->lock->set( k => $home );

   eval {
      mkdir $home unless (-d $home);

      unless (-d $home) {
         $self->throw( error => q(eCannotCreate), arg1 => $home );
      }

      $s_flds = $self->io( $home )->stat;

      chown $uid, $gid, $home if ($s_flds->{uid} <=> $uid
                                  or $s_flds->{gid} <=> $gid);

      chmod $mode, $home;
      $path = $self->catfile( $self->profdir, $group.'.profile' );

      if (-f $path) {
         $self->_backup( 'file', $self->catfile( $home, '.profile' ),
                         $path, $uid, $gid, q(0644) );
      }

      $path = $self->catfile( $self->profdir, 'kshrc' );

      if (-f $path) {
         $self->_backup( 'file', $self->catfile( $home, '.kshrc' ),
                         $path, $uid, $gid, q(0644) );
      }

      $path = $self->catfile( $self->profdir, 'logout' );

      if (-f $path) {
         $self->_backup( 'file', $self->catfile( $home, '.logout' ),
                         $path, $uid, $gid, q(0755) );
      }

      $path = $self->catfile( $self->profdir, 'Xdefaults' );

      if (-f $path) {
         $self->_backup( 'file', $self->catfile( $home, '.Xdefaults' ),
                         $path, $uid, $gid, q(0644) );
      }

      $path = $self->catfile( $self->profdir, 'exrc' );

      if (-f $path) {
         $self->_backup( 'file', $self->catfile( $home, '.exrc' ),
                         $path, $uid, $gid, q(0644) );
      }

      $path = $self->catfile( $self->profdir, 'emacs' );

      if (-f $path) {
         $self->_backup( 'file', $self->catfile( $home, '.emacs' ),
                         $path, $uid, $gid, q(0644) );
      }

      if ($params->{project}) {
         $self->_backup( 'text', $self->catfile( $home, '.project' ),
                         $params->{project}."\n", $uid, $gid, q(0644) );
      }
   };

   if ($e = $self->catch) {
      $self->lock->reset( k => $home ); $self->throw( $e );
   }

   $self->lock->reset( k => $home );
   return 'Account populated '.$home;
}

sub update_account {
   my ($self, $path) = @_;
   my ($e, $gecos, $gid, $home, $params, $passwd, $passwd_obj);
   my ($shell, $uid, $user, $user_ref);

   $params   = $self->_read_params( $path );
   $user     = $params->{username};
   $user_ref = $self->f_get_user( $user, 1 );

   if ($user_ref->{username} eq q(unknown)) {
      $self->throw( error => q(eUnknownUser), arg1 => $user );
   }

   $passwd   = $self->spath && -f $self->spath ? q(x) : $user_ref->{password};
   $uid      = $user_ref->{uid};
   $gid      = $user_ref->{pgid};
   $gecos    = $self->_get_gecos( $params );
   $home     = $params->{homedir};
   $shell    = $params->{shell};

   $passwd_obj = $self->_get_passwd_obj;
   $self->lock->set( k => $self->ppath );
   $passwd_obj->user( $user, $passwd, $uid, $gid, $gecos, $home, $shell );
   $passwd_obj->commit( backup => '.bak' );
   $self->lock->reset( k => $self->ppath );

   # TODO: Save project text
   return 'Account updated '.$user;
}

sub user_report {
   my ($self, $path, $fmt) = @_;
   my (@flds, $line, %lastl, @lines, $out, $passwd, $res);
   my ($sdate, $trunc, $type, $user, $user_ref);

   $fmt  = q(text) unless ($fmt); %lastl = (); @lines = (); $sdate = $NUL;
   $path = q(-)    unless ($path);
   $res  = $self->_list_previous;

   for $line (split m{ \n }mx, $res->out) {
      $line =~ s{ \s+ }{ }gmx; @flds = split $SPC, $line;

      if ($line =~ m{ \A wtmp \s+ begins }mx) {
         shift @flds; shift @flds; $sdate = join $SPC, @flds;
      }
      else {
         if (length $line > 0) {
            $line = $flds[2].$SPC.$flds[3].$SPC.$flds[4].$SPC.$flds[5];
            $lastl{ $flds[0] } = $line unless (exists $lastl{ $flds[0] });
         }
      }
   }

   for $user (@{ $self->retrieve->user_list }) {
      @flds     = ();
      $user_ref = $self->f_get_user( $user, 1 );
      $passwd   = $user_ref->{crypted_password};
   TRY: {
      if ($passwd =~ m{ DISABLED }imx) { $flds[0] = 'D'; last TRY }
      if ($passwd =~ m{ EXPIRED }imx)  { $flds[0] = 'E'; last TRY }
      if ($passwd =~ m{ LEFT }imx)     { $flds[0] = 'L'; last TRY }
      if ($passwd =~ m{ NOLOGIN }imx)  { $flds[0] = 'N'; last TRY }
      if ($passwd =~ m{ \A x \z }imx)  { $flds[0] = 'C'; last TRY }
      if ($passwd =~ m{ \* }mx)        { $flds[0] = 'D'; last TRY }
      if ($passwd =~ m{ \! }mx)        { $flds[0] = 'D'; last TRY }

      $flds[0] = q(C);
   } # TRY
      $flds[1] = $user;
      $flds[2] = $user_ref->{first_name}.$SPC.$user_ref->{last_name};
      $flds[3] = $user_ref->{location};
      $flds[4] = $fmt ne q(csv)
               ? substr $user_ref->{work_phone}, -5, 5
               : $user_ref->{work_phone};
      $flds[5] = $user_ref->{project};
      $trunc   = substr $user, 0, 8;
      $flds[6] = exists $lastl{ $trunc }
               ? $lastl{ $trunc } : 'Never Logged In';
      $flds[6] = $user_ref->{homedir} && -d $user_ref->{homedir}
               ? $flds[6] : 'No Home Dir.';

      if ($fmt ne q(csv)) {
         $line = sprintf '%s %-8.8s %-20.20s %-10.10s %5.5s %-14.14s %-16.16s',
                         map { defined $_ ? $_ : q(~) } @flds[ 0 .. 6 ];
      }
      else { $line = join q(,), map { defined $_ ? $_ : $NUL } @flds }

      push @lines, $line;
   }

   @lines = sort @lines;

   if ($fmt eq 'csv') {
      unshift @lines, '#S,Login,Full Name,Location,Extn,Role,Last Login';
   }
   else {
      # Prepend header
      unshift @lines, q(_) x 80;
      $line  = 'S Login    Full Name            Location    ';
      $line .= 'Extn Role           Last Login';
      unshift @lines, $line;
      $line  = 'Host: '.$self->host.' History Begins: '.$sdate;
      $line .= ' Printed: '.$self->stamp;
      unshift @lines, $line;

      # Append footer
      push @lines, $NUL, $NUL;
      $line  = 'Status field key: C = Current, D = Disabled, ';
      $line .= 'E = Expired, L = Left, N = NOLOGIN';
      push @lines, $line, '                  U = Unused';
   }

   if ($path eq q(-)) { $out = (join "\n", @lines)."\n" }
   else {
      $self->io( $path )->println( join "\n", @lines  );
      $out = 'Wrote '.($#lines+1).' lines to '.$path;
   }

   return $out;
}

# Private methods

sub _backup {
   my ($self, $type, $path, $src, $uid, $gid, $mode) = @_;
   my ($cmd, $cnt);

   $mode = oct $mode; $cnt = 1;

   if (-e $path and $type ne q(link)) {
      while (-e $path.'.OLD-'.$cnt) { $cnt++ }

      $self->throw( $ERRNO ) unless (move( $path, $path.'.OLD-'.$cnt ));
   }

 TRY: {
   if ($type eq q(dir)) {
      $self->throw( $ERRNO ) unless (mkdir $path);

      chown $uid, $gid, $path; chmod $mode, $path;
      last TRY;
   }

   if ($type eq q(file)) {
      $self->throw( error => q(eNotFound), arg1 => $src ) unless (-r $src);
      $self->throw( $ERRNO ) unless (copy( $src, $path ));

      chown $uid, $gid, $path; chmod $mode, $path;
      last TRY;
   }

   if ($type eq q(link)) {
      $self->throw( 'not found '.$src ) unless (-e $src);

      unlink $path if (-e $path);

      $self->throw( $ERRNO ) unless (symlink $src, $path);

      $cmd = 'chown -h '.$uid.q(:).$gid.$SPC.$path; system $cmd;
      last TRY;
   }

   if ($type eq q(text)) {
      $self->io( $path )->lock->print( $src );
      chown $uid, $gid, $path; chmod $mode, $path;
      last TRY;
   }
   } # Try

   return;
}

sub _get_new_uid {
   my ($self, $base_id, $inc) = @_; my ($cache, $new_id, $uid, @uids);

   ($cache) = $self->_load;
   $base_id = 100 unless ($base_id);
   $inc     = 1   unless ($inc);
   $new_id  = $base_id;
   @uids    = ();

   for (keys %{ $cache }) { push @uids, $cache->{ $_ }->{id} }

   for $uid (sort { $a <=> $b } @uids) {
      if ($uid >= $base_id) { last if ($uid > $new_id); $new_id = $uid + $inc }
   }

   return $new_id;
}

sub _list_previous {
   my $self = shift; return $self->popen( q(last) );
}

sub _read_params {
   my ($self, $path) = @_; my ($e, $params, $user);

   $params = eval { XMLin( $path, SuppressEmpty => undef ) };

   $self->throw( $e ) if ($e = $self->catch);

   $self->throw( q(eNoUser) ) unless ($user = $params->{username});

   if ($user =~ m{ [ :] }mx) {
      $self->throw( error => q(eInvalidUser), arg1 => $user );
   }

   return $params;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Identity::Suid - Set uid root methods for account manipulation

=head1 Version

0.1.$Revision: 402 $

=head1 Synopsis

   # In a module executing setuid root
   use base qw(CatalystX::Usul::Programs);
   use CatalystX::Usul::Model::Identity;

   __PACKAGE__->mk_accessors( qw(identity) );

   sub new {
      my ($class, @rest) = @_;
      my $config   = { role_class => q(Roles::Unix), user_class => q(Suid) };
      my $id_class = q(CatalystX::Usul::Model::Identity);

      $self->{identity} = $id_class->new( $self, $config );
      return $self;
   }

   sub create_account {
      my $self = shift;

      $self->output( $self->users->create_account( @ARGV ) );
      return 0;
   }

=head1 Description

The public methods are called from a program running setuid root. The
methods enable the management of OS accounts

=head1 Subroutines/Methods

=head2 create_account

   $self->create_account( $path );

Creates an OS account. The given path is an XML file containing the
account parameters. Account profiles are obtained from the
C<< $self->profiles_ref >> object. New entries are added to the I<passwd>
file, the I<shadow> file (if it is being used) and the I<group> file

=head2 delete_account

   $self->delete_account( $user ):

Deletes an OS account. The accounts home directory is removed, the users
entries in the I<group> file are removed as are the entries in the
I<passwd> and I<shadow> files

=head2 populate_account

   $self->create_account( $path );

Creates the new users home directory and populates it with some "dot"
files if templates for such exist in the C<< $self->profdir >>
directory. Does not create a directory if the users homedir matches
C<< $self->common_home >>. Account parameters are read from the XML file
given by C<$path>

=head2 update_account

   $self->update_account( $path );

Account parameters are read from the XML file given by C<$path>. Updates
entries in the I<passwd> file

=head2 user_report

   $self->user_report( $path, $format );

Creates a report of user accounts. Outputs to C<$path> or I<STDOUT> if
C<$path> is I<->. Format is either I<text> or I<csv>

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model::Identity::Users::Unix>

=item L<Crypt::PasswdMD5>

=item L<XML::Simple>

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
