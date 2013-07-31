# @(#)$Id: Unix.pm 1319 2013-06-23 16:21:01Z pjf $

package CatalystX::Usul::Roles::Unix;

use strict;
use version; our $VERSION = qv( sprintf '0.8.%d', q$Rev: 1319 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions   qw(throw);
use CatalystX::Usul::Constraints qw(File);
use File::UnixAuth;
use TryCatch;

extends q(CatalystX::Usul::Roles);

has 'baseid'     => is => 'ro',   isa => PositiveInt, default => 1000;

has 'group_obj'  => is => 'lazy', isa => Object, init_arg => undef;

has 'group_path' => is => 'ro',   isa => File, coerce => TRUE,
   default       => sub { [ NUL, qw(etc group) ] };

has 'inc'        => is => 'ro',   isa => PositiveInt, default => 1;

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
   return "Role update ${cmd} ${fld} complete";
}

# Private methods

sub _build_group_obj {
   return File::UnixAuth->new( builder     => $_[ 0 ],
                               path        => $_[ 0 ]->group_path,
                               source_name => q(group) );
}

sub _get_new_gid {
   my $self = shift; my $base_id = $self->baseid; my ($cache) = $self->_load;

   my $inc  = $self->inc; my $new_id = $base_id;

   for my $gid (sort { $a <=> $b }
                map  { $cache->{ $_ }->{id} } keys %{ $cache }) {
      if ($gid >= $base_id) { $gid > $new_id and last; $new_id = $gid + $inc }
   }

   return $new_id;
}

sub _load {
   my $self  = shift; my $key = __PACKAGE__.q(::_load);

   $self->lock->set( k => $key );

   my $cache = $self->cache;
   my $mtime = $self->group_path->stat->{mtime};
   my $updt  = delete $cache->{_dirty} ? TRUE : FALSE;

   $updt or $updt = $mtime == ($cache->{_mtime} || 0) ? FALSE : TRUE;

   $updt or return $self->_cache_results( $key ); $cache->{_mtime} = $mtime;

   delete $cache->{ $_ } for (grep { not m{ \A _ }mx } keys %{ $cache });

   try {
      my $data = $self->group_obj->load->{group};

      for my $group (keys %{ $data }) {
         my $group_data = $data->{ $group };
         my $gid        = $group_data->{gid};
         my $users      = $group_data->{members};

         unless (exists $cache->{id2name}->{ $gid }) {
            $cache->{id2name}->{ $gid   } = $group;
            $cache->{roles  }->{ $group } = {
               id     => $gid,
               passwd => $group_data->{password},
               users  => [] };
         }

         push @{ $cache->{roles}->{ $group }->{users} }, @{ $users };
         push @{ $cache->{user2role}->{ $_ } }, $group for (@{ $users });
      }
   }
   catch ($e) { $self->lock->reset( k => $key ); throw $e }

   return $self->_cache_results( $key );
}

sub _run_as_root {
   my ($self, $method, @args) = @_; my $suid = $self->config->suid;

   my $cmd = [ $suid, $self->debug_flag, q(-c), $method, q(--), @args ];
   my $out = $self->run_cmd( $cmd, { err => q(out) } )->out;

   $self->debug and $self->log->debug( $out );

   return $out;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Roles::Unix - Group management for the Unix OS

=head1 Version

0.8.$Revision: 1319 $

=head1 Synopsis

   use CatalystX::Usul::Roles::Unix;

   my $class = CatalystX::Usul::Roles::Unix;

   my $role_obj = $class->new( $attr );

=head1 Description

Methods to manipulate the group file which defaults to
F</etc/group>. This class implements the methods required by it's
base class L<CatalystX::Usul::Roles>

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item C<baseid>

A positive integer which defaults to I<1000>. New id must will be greater
than or equal to this value

=item C<group_obj>

A lazily constructed object which cannot be passed in the constructor. It
is an instance of L<File::UnixAuth>

=item C<group_path>

A file which is coerced from the default array ref
C< [ NUL, qw(etc group) ] >

=item C<inc>

A positive integer which defaults to I<1>. The gap to leave between new
group ids

=back

=head1 Subroutines/Methods

=head2 add_user_to_role

   $out = $role_obj->add_user_to_role( $groupname, $username );

Calls the suid root wrapper to add the specified user to the specified
group. Returns the output from running the command

=head2 create

   $out = $role_obj->create( $groupname );

Calls the suid root wrapper to create a new group

=head2 delete

   $out = $role_obj->delete( $groupname );

Calls the suid root wrapper to delete an existing group

=head2 remove_user_from_role

   $out = $role_obj->remove_user_to_role( $groupname, $username );

Calls the suid root wrapper to remove the given user from the
specified group

=head2 roles_update

   $out = $role_obj->roles_update( $cmd, $field, $username, $groupname );

Called from the suid root wrapper this is the method that updates the
group file. The C<$cmd> is either I<add> or I<delete>. The C<$field> is
either I<user> or I<group>

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Roles>

=item L<CatalystX::Usul::Moose>

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
