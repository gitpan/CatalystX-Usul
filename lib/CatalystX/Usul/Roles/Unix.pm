# @(#)$Id: Unix.pm 576 2009-06-09 23:23:46Z pjf $

package CatalystX::Usul::Roles::Unix;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 576 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Roles CatalystX::Usul::Utils);

use Unix::GroupFile;

__PACKAGE__->config( backup_extn => q(.bak),
                     baseid      => 100,
                     group_file  => q(/etc/group),
                     inc         => 1,
                     _mtime      => 0 );

__PACKAGE__->mk_accessors( qw(backup_extn baseid group_file inc _mtime) );

# Factory methods

sub add_user_to_role {
   my ($self, $role, $user) = @_; my $cmd;

   $cmd  = $self->suid.' -n -c roles_update -- add user "';
   $cmd .= $user.'" "'.$role.'" ';
   $self->run_cmd( $cmd, { err => q(out) } );
   return;
}

sub create {
   my ($self, $role) = @_; my $cmd;

   $cmd = $self->suid.' -n -c roles_update -- add group "" "'.$role.'" ';
   $self->run_cmd( $cmd, { err => q(out) } );
   return;
}

sub delete {
   my ($self, $role) = @_; my $cmd;

   $cmd = $self->suid.' -n -c roles_update -- delete group "" "'.$role.'" ';
   $self->run_cmd( $cmd, { err => q(out) } );
   return;
}

sub remove_user_from_role {
   my ($self, $role, $user) = @_; my $cmd;

   $cmd  = $self->suid.' -n -c roles_update -- delete user "';
   $cmd .= $user.'" "'.$role.'" ';
   $self->run_cmd( $cmd, { err => q(out) } );
   return;
}

# Called from suid as root

sub roles_update {
   my ($self, $cmd, $fld, $user, $grp) = @_;

   unless ($cmd && ($cmd eq q(add) || $cmd eq q(delete))) {
      $self->throw( error => 'Command [_1] unknown', args => [ $cmd || q() ] );
   }

   unless ($fld && ($fld eq q(group) || $fld eq q(user))) {
      $self->throw( error => 'Field [_1] unknown', args => [ $fld || q() ] );
   }

   unless ($user || ($fld && $fld eq q(group))) {
      $self->throw( 'No user specified' );
   }

   unless (($cmd && $cmd eq q(add) && $fld && $fld eq q(group))
           || $self->is_role( $grp )) {
      $self->throw( error => 'Role [_1] unknown', args => [ $grp || q() ] );
   }

   my $path = $self->_get_group_file;
   $self->lock->set( k => $path );
   my $group_obj = $self->_get_group_obj( $path, q(rw) );

   if ($cmd eq q(add)) {
      if ($fld eq q(group)) {
         $group_obj->group( $grp, q(*), $self->_get_new_gid);
      }
      else { $group_obj->add_user( $grp, $user ) }
   }
   elsif ($cmd eq q(delete)) {
      if ($fld eq q(group)) { $group_obj->delete( $grp ) }
      else { $group_obj->remove_user( $grp, $user ) }
   }

   $group_obj->commit( backup => $self->backup_extn );
   $self->lock->reset( k => $path );
   return "Role update $cmd $fld complete";
}

# Private methods

sub _get_group_file {
   my ($self, $path) = @_; $path ||= $self->group_file;

   if ($path =~ m{ \A ([[:print:]]+) \z }mx) { $path = $1  } # now untainted

   unless ($path && -f $path) {
      $self->throw( error => 'File [_1] not found', args => [ $path ] );
   }

   return $path;
}

sub _get_group_obj {
   my ($self, $path, $mode) = @_;

   my $group_obj = Unix::GroupFile->new
      ( $path, locking => q(none), mode => $mode );

   unless ($group_obj) {
      $self->lock->reset( k => $path );
      $self->throw( 'Cannot create group file object' );
   }

   return $group_obj;
}

sub _get_new_gid {
   my $self = shift; my ($base_id, $gid, @gids, $inc, $new_id);

   $base_id = $self->baseid; $inc = $self->inc; $new_id = $base_id; @gids = ();

   push @gids, $self->_cache->{ $_ }->{id} for (keys %{ $self->_cache });

   for $gid (sort { $a <=> $b } @gids) {
      if ($gid >= $base_id) { last if ($gid > $new_id); $new_id = $gid + $inc }
   }

   return $new_id;
}

sub _load {
   my $self = shift;
   my ($cache, $gid, $group, $group_obj, $id2name, $mtime);
   my ($path, $updt, $user2role, $users);

   $path  = $self->_get_group_file;
   $self->lock->set( k => $path );
   $mtime = $self->status_for( $path )->{mtime};
   $updt  = $mtime == $self->_mtime ? 0 : 1;
   $self->_mtime( $mtime );

   unless ($updt) {
      $cache     = { %{ $self->_cache     } };
      $id2name   = { %{ $self->_id2name   } };
      $user2role = { %{ $self->_user2role } };
      $self->lock->reset( k => $path );
      return ($cache, $id2name, $user2role);
   }

   $self->_cache( {} ); $self->_id2name( {} ); $self->_user2role( {} );
   $group_obj = $self->_get_group_obj( $path, q(r) );

   for $group ($group_obj->groups) {
      next unless ($gid = $group_obj->gid( $group ));
      next if     (exists $self->_id2name->{ $gid });

      $self->_id2name->{ $gid } = $group;
      $users = [ $group_obj->members( $group ) ];
      $self->_cache->{ $group } = { id     => $gid,
                                    passwd => $group_obj->passwd( $group ),
                                    users  => $users };

      push @{ $self->_user2role->{ $_ } }, $group for (@{ $users });
   }

   $cache     = { %{ $self->_cache     } };
   $id2name   = { %{ $self->_id2name   } };
   $user2role = { %{ $self->_user2role } };
   $self->lock->reset( k => $path );
   return ($cache, $id2name, $user2role);
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Roles::Unix - Group management for the Unix OS

=head1 Version

0.3.$Revision: 576 $

=head1 Synopsis

   use CatalystX::Usul::Roles::Unix;

   my $class = CatalystX::Usul::Roles::Unix;

   my $role_obj = $class->new( $app, $config );

=head1 Description

Methods to manipulate the group file which defaults to
I</etc/group>. This class implements the methods required by it's
base class

=head1 Subroutines/Methods

=head2 add_user_to_role

   $role_obj->add_user_to_role( $group, $user );

Calls the suid root wrapper to add the specified user to the specified
group

=head2 create

   $role_obj->create( $group );

Calls the suid root wrapper to create a new group

=head2 delete

   $role_obj->delete( $group );

Calls the suid root wrapper to delete an existing group

=head2 remove_user_from_role

   $role_obj->remove_user_to_role( $group, $user );

Calls the suid root wrapper to remove the given user from the
specified group

=head2 roles_update

   $role_obj->roles_update( $cmd, $field, $user, $group );

Called from the suid root wrapper this is the method that updates the
group file. The C<$cmd> is either I<add> or I<delete>. The C<$field> is
either I<user> or I<group>

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Roles>

=item L<Unix::GroupFile>

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
