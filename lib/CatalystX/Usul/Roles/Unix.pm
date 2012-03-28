# @(#)$Id: Unix.pm 1139 2012-03-28 23:49:18Z pjf $

package CatalystX::Usul::Roles::Unix;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1139 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Roles CatalystX::Usul::IPC);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(throw untaint_path);
use File::UnixAuth;
use TryCatch;

__PACKAGE__->mk_accessors( qw(backup_extn baseid group_obj group_path
                              inc _mtime) );

sub new {
   my ($class, $app, $attrs) = @_;

   $attrs->{backup_extn} ||= q(.bak);
   $attrs->{baseid     } ||= 1000;
   $attrs->{group_path } ||= q(/etc/group);
   $attrs->{inc        } ||= 1;
   $attrs->{_mtime     }   = 0;

   my $new = $class->next::method( $app, $attrs );

   $new->group_path( $new->_build_group_path );
   $new->group_obj ( $new->_build_group_obj  );

   return $new;
}

# Factory methods

sub add_user_to_role {
   my ($self, @rest) = @_;

   return $self->_run_as_root( qw(roles_update add user), @rest );
}

sub create {
   my ($self, @rest) = @_;

   return $self->_run_as_root( qw(roles_update add group), @rest );
}

sub delete {
   my ($self, @rest) = @_;

   return $self->_run_as_root( qw(roles_update delete group), @rest );
}

sub remove_user_from_role {
   my ($self, @rest) = @_;

   return $self->_run_as_root( qw(roles_update delete user), @rest );
}

# Called from suid as root

sub roles_update {
   my ($self, $cmd, $fld, $grp, $user) = @_;

   ($cmd and ($cmd eq q(add) or $cmd eq q(delete)))
      or throw error => 'Command [_1] unknown', args => [ $cmd || NUL ];

   ($fld and ($fld eq q(group) or $fld eq q(user)))
      or throw error => 'Field [_1] unknown', args => [ $fld || NUL ];

   ($user or ($fld and $fld eq q(group))) or throw 'User not specified';

   unless (($cmd and $cmd eq q(add) and $fld and $fld eq q(group))
           or $self->is_role( $grp )) {
      throw error => 'Role [_1] unknown', args => [ $grp || NUL ];
   }

   my $key = __PACKAGE__.q(::_execute); $self->lock->set( k => $key );

   try {
      my $rs = $self->group_obj->resultset;

      if ($cmd eq q(add)) {
         if ($fld eq q(group)) {
            $rs->create( { name => $grp, gid => $self->_get_new_gid } );
         }
         else {
            my $grp_obj = $rs->find( { name => $grp } )
               or throw error => 'Group [_1] unknown', args => [ $grp ];

            $grp_obj->add_user_to_group( $user );
         }
      }
      elsif ($cmd eq q(delete)) {
         if ($fld eq q(group)) { $rs->delete( { name => $grp } ) }
         else {
            my $grp_obj = $rs->find( { name => $grp } )
               or throw error => 'Group [_1] unknown', args => [ $grp ];

            $grp_obj->remove_user_from_group( $user );
         }
      }
   }
   catch ($e) { $self->lock->reset( k => $key ); throw $e }

   $self->lock->reset( k => $key );
   return "Role update $cmd $fld complete";
}

# Private methods

sub _build_group_obj {
   my $self  = shift;

   return File::UnixAuth->new( ioc_obj     => $self, path => $self->group_path,
                               source_name => q(group) );
}

sub _build_group_path {
   my $self = shift; my $path = untaint_path $self->group_path;

   $path or throw 'Group file path not specified';
   -f $path or throw error => 'File [_1] not found', args => [ $path ];

   return $path;
}

sub _get_new_gid {
   my $self    = shift;
   my $base_id = $self->baseid;
   my ($cache) = $self->_load;
   my $inc     = $self->inc;
   my $new_id  = $base_id;

   for my $gid (sort { $a <=> $b }
                map  { $cache->{ $_ }->{id} } keys %{ $cache }) {
      if ($gid >= $base_id) { $gid > $new_id and last; $new_id = $gid + $inc }
   }

   return $new_id;
}

sub _load {
   my $self = shift; my $key = __PACKAGE__.q(::_load);

   $self->lock->set( k => $key );

   my $mtime = $self->status_for( $self->group_path )->{mtime};
   my $updt  = $mtime == $self->_mtime ? FALSE : TRUE;

   $self->_mtime( $mtime );

   $updt or return $self->_cache_results( $key );

   delete $self->cache->{ $_ } for (keys %{ $self->cache });

   try {
      my $data = $self->group_obj->load->{group};

      for my $group (keys %{ $data }) {
         my $group_data = $data->{ $group };
         my $gid        = $group_data->{gid};
         my $users      = $group_data->{members};

         unless (exists $self->cache->{id2name}->{ $gid }) {
            $self->cache->{id2name}->{ $gid    } = $group;
            $self->cache->{roles  }->{ $group  } = {
               id     => $gid,
               passwd => $group_data->{password},
               users  => [] };
         }

         push @{ $self->cache->{roles}->{ $group }->{users} }, @{ $users };
         push @{ $self->cache->{user2role}->{ $_ } }, $group for (@{ $users });
      }
   }
   catch ($e) { $self->lock->reset( k => $key ); throw $e }

   return $self->_cache_results( $key );
}

sub _run_as_root {
   my ($self, $method, @args) = @_;

   my $cmd = [ $self->suid, ($self->debug ? q(-D) : q(-n)), q(-c),
               $method, q(--), @args ];
   my $out = $self->run_cmd( $cmd, { err => q(out) } )->out;

   $self->debug and $self->log->debug( $out );

   return $out;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Roles::Unix - Group management for the Unix OS

=head1 Version

0.5.$Revision: 1139 $

=head1 Synopsis

   use CatalystX::Usul::Roles::Unix;

   my $class = CatalystX::Usul::Roles::Unix;

   my $role_obj = $class->new( $attrs, $app );

=head1 Description

Methods to manipulate the group file which defaults to
I</etc/group>. This class implements the methods required by it's
base class

=head1 Subroutines/Methods

=head2 new

Constructor

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