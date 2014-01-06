# @(#)Ident: ;

package CatalystX::Usul::Users::DBIC;

use strict;
use version; our $VERSION = qv( sprintf '0.15.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw( emit sub_name throw );
use CatalystX::Usul::Moose;
use Class::Usul::Time;
use TryCatch;

extends q(CatalystX::Usul::Users);

has 'dbic_role_model'       => is => 'ro', isa => Object, required => TRUE;

has 'dbic_user_model'       => is => 'ro', isa => Object, required => TRUE;

has 'dbic_user_roles_model' => is => 'ro', isa => Object, required => TRUE;

has 'get_features'          => is => 'ro', isa => HashRef,
   default                  => sub { { roles   => [ q(roles) ],
                                       session => TRUE, } };


has '_field_map' => is => 'ro', isa => HashRef,
   default       => sub { { password => q(crypted_password), id => q(uid), } };

# Interface methods
sub activate_account {
   my ($self, $file) = @_;

   my $username = $self->dequeue_activation_file( $file );

   $self->_execute( sub {
      my $user = $self->assert_user( $username ); $user->active( TRUE );

      $user->update; $self->_update_cache( $user ); return;
   } );

   return ('User [_1] account activated', $username);
}

sub assert_user {
   my $self     = shift;
   my $username = shift or throw 'User not specified';
   my $rs       = $self->dbic_user_model->search( { username => $username } );
   my $user     = $rs->first
      or throw error => 'User [_1] unknown', args => [ $username ];

   return $user;
}

sub create {
   my ($self, $fields) = @_;

   $self->_execute( sub {
      my $username = $fields->{username};
      my $p_name   = delete $fields->{profile};
      my $profile  = $self->profiles->find( $p_name );
      my $passwd   = $fields->{password}
                  || $profile->passwd || $self->def_passwd;
      my $src      = $self->dbic_user_model->result_source;
      my $cols;

      $passwd !~ m{ [*!] }msx
         and $fields->{password} = $self->_encrypt_password( $passwd );

      for ($src->columns) {
         defined $fields->{ $_ } and $cols->{ $_ } = $fields->{ $_ };
      }

      $self->dbic_user_model->create( $cols );

      $self->roles->is_member_of_role( $p_name, $username )
         or $self->roles->add_user_to_role( $p_name, $username );

      if ($profile->roles) {
         for my $role (split m{ , }mx, $profile->roles) {
            $self->roles->is_member_of_role( $role, $username )
               or $self->roles->add_user_to_role( $role, $username );
         }
      }

      $self->_update_cache( $self->assert_user( $username ) );
      return;
   } );

   return ('User [_1] account created', $fields->{username});
}

sub delete {
   my ($self, $username) = @_;

   $self->_execute( sub {
      $self->assert_user( $username )->delete;
      $self->_delete_user_from_cache( $username );
      return;
   } );

   return ('User [_1] account deleted', $username);
}

sub update {
   my ($self, $fields)  = @_;

   $self->_execute( sub {
      my $username = $fields->{username};
      my $user     = $self->assert_user( $username );
      my $src      = $self->dbic_user_model->result_source;

      for my $col ($src->columns) {
         defined $fields->{ $col } and $user->$col( $fields->{ $col } );
      }

      $user->update; $self->_update_cache( $user );
      return;
   } );

   return ('User [_1] account updated', $fields->{username});
}

sub update_password {
   my ($self, @rest) = @_; my ($force, $username) = @rest;

   $self->_execute( sub {
      my $user = $self->assert_user( $username );

      $user->password( $self->encrypt_password( @rest ) );
      $user->pwlast( $force ? 0 : int time / 86_400 );
      $user->update; $self->_update_cache( $user );
      return;
   } );

   return ('User [_1] password updated', $username);
}

sub user_report {
   my ($self, $args) = @_; my @lines = (); my (@flds, $line);

   my $fmt = $args && $args->{type} ? $args->{type} : q(text);

   for my $username (@{ $self->list }) {
      my $user_ref = $self->_get_user_ref( $username );
      my $passwd   = $user_ref->{crypted_password} || NUL;

      @flds = ( q(C) );
   TRY: {
      if ($passwd =~ m{ DISABLED }imsx) { $flds[ 0 ] = q(D); last TRY }
      if ($passwd =~ m{ EXPIRED }imsx)  { $flds[ 0 ] = q(E); last TRY }
      if ($passwd =~ m{ LEFT }imsx)     { $flds[ 0 ] = q(L); last TRY }
      if ($passwd =~ m{ NOLOGIN }imsx)  { $flds[ 0 ] = q(N); last TRY }
      if ($passwd =~ m{ [*!] }msx)      { $flds[ 0 ] = q(N); last TRY }
      } # TRY

      $flds[ 1 ] = $username;
      $flds[ 2 ] = $user_ref->{first_name}.q( ).$user_ref->{last_name};
      $flds[ 3 ] = $user_ref->{location};
      $flds[ 4 ] = $user_ref->{work_phone};
      $flds[ 5 ] = $user_ref->{project};
      $flds[ 6 ] = 'Never Logged In';

      unless ($fmt eq q(csv)) {
         $line = sprintf '%s %-8.8s %-20.20s %-10.10s %5.5s %-14.14s %-16.16s',
                         map { defined $_ ? $_ : q(~) } @flds[ 0 .. 6 ];
      }
      else { $line = join q(,), map { defined $_ ? $_ : NUL } @flds }

      push @lines, $line;
   }

   @lines = sort @lines; my $count = @lines;

   if ($fmt eq q(csv)) {
      unshift @lines, '#S,Login,Full Name,Location,Extn,Role,Last Login';
   }
   else {
      # Prepend header
      unshift @lines, q(_) x 80;
      $line  = 'S Login    Full Name            Location    ';
      $line .= 'Extn Role           Last Login';
      unshift @lines, $line;
      unshift @lines, 'Host: '.$self->host.' Printed: '.time2str;

      # Append footer
      push @lines, NUL, NUL;
      $line  = 'Status field key: C = Current, D = Disabled, ';
      $line .= 'E = Expired, L = Left, N = NOLOGIN';
      push @lines, $line;
      push @lines, '                  U = Unused';
      push @lines, "Total users $count";
   }

   unless ($fmt eq q(csv)) { emit @lines }
   else { $self->io( $args->{path} )->println( join "\n", @lines  ) }

   return 'Here ends the user report';
}

# Private methods
sub _delete_user_from_cache {
   return delete $_[ 0 ]->cache->{users}->{ $_[ 1 ] };
}

sub _execute {
   my ($self, $f) = @_; my $key = __PACKAGE__.q(::_execute); my $res;

   $self->debug and $self->log->debug( __PACKAGE__.q(::).(sub_name 1) );
   $self->lock->set( k => $key );

   try        { $res = $f->() }
   catch ($e) { $self->lock->reset( k => $key ); throw $e }

   $self->lock->reset( k => $key );
   return $res;
}

sub _load {
   my ($self, $wanted) = @_;

   my $key; $self->lock->set( k => $key = __PACKAGE__.q(::_load) );

   my $cache = $self->cache; my $users = $cache->{users} ||= {};

   if ($wanted) {
      exists $users->{ $wanted } and defined $users->{ $wanted }
         and return $self->_cache_results( $key );

      try { $self->_update_cache( $self->assert_user( $wanted ) ) } catch {}
   }
   elsif (delete $cache->{_dirty}) {
      $cache->{users} = {};

      try {
         my $rs = $self->dbic_user_model->search( undef, {
            columns => [ qw(username) ] } );

         for my $username (map { $_->username } $rs->all) {
            $cache->{users}->{ $username } = $users->{ $username };
         }
      }
      catch ($e) { $self->lock->reset( k => $key ); throw $e }
   }

   return $self->_cache_results( $key );
}

sub _update_cache {
   my ($self, $user) = @_;

   my $map = $self->_field_map;
   my $src = $self->dbic_user_model->result_source;
   my $mcu = $self->cache->{users}->{ $user->username } ||= {};

   for my $col ($src->columns) {
      $mcu->{ $map->{ $col } || $col } = $user->$col;
   }

   return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Users::DBIC - Database user storage

=head1 Version

Describes v0.15.$Rev: 1 $

=head1 Synopsis

   use CatalystX::Usul::Users::DBIC;

   my $class = CatalystX::Usul::Users::DBIC;

   my $user = $class->new( $attr );

=head1 Description

User storage model for relational databases. This model makes use of
L<DBIx::Class>. It inherits from L<CatalystX::Usul::Users> and
implements the required list of factory methods

=head1 Configuration and Environment

Defines the following list of attributes

=over 3

=item dbic_role_model

Required schema object which represents roles

=item dbic_user_model

Required schema object which represents users

=item dbic_user_roles_model

Required schema object which represents the user / roles join table

=item field_map

A hash ref which maps the field names used by the user model onto the field
names used by this data store

=item get_features

A hash ref which details the features supported by the DBIC user data store

=back

=head1 Subroutines/Methods

=head2 activate_account

Searches the user store for the supplied user name and if it exists sets
the active column to true

=head2 assert_user

Returns a DBIC user object for the specified user or throws an exception
if the user does not exist

=head2 change_password

Calls C<update_password> in L<CatalystX::Usul::Identity::Users> with
the authenticate flag set to I<false>, thereby forcing the user to
authenticate. Passes the supplied arguments through

=head2 check_password

Calls C<authenticate> in L<CatalystX::Usul::Identity::Users>. Returns I<true>
if the authentication succeeded, I<false> otherwise

=head2 create

Creates a new user object on the user model. Adds the user to the list of
roles appropriate to the user profile

=head2 delete

Deletes a user object from the user model

=head2 get_primary_rid

Returns I<undef> as primary role ids are not supported by this storage
backend

=head2 get_user

Returns a hash ref of fields for the request user

=head2 get_users_by_rid

Returns an empty list as primary role ids are not supported by this storage
backend

=head2 is_user

Returns I<true> if the supplied user exists, I<false> otherwise

=head2 list

Returns a list reference of users in the database

=head2 set_password

Calls C<update_password> in L<CatalystX::Usul::Identity::Users> with
the authenticate flag set to I<true>, which bypasses user
authentication. Passes the supplied arguments through

=head2 update

Updates columns on the user object for the supplied user

=head2 update_password

Updates the users password in the database

=head2 user_report

Generate a report from the data in the user database

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Users>

=item L<CatalystX::Usul::Moose>

=item L<Class::Usul::Time>

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
