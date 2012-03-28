# @(#)$Id: DBIC.pm 1139 2012-03-28 23:49:18Z pjf $

package CatalystX::Usul::Users::DBIC;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1139 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Users);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(say sub_name throw);
use CatalystX::Usul::Time;
use MRO::Compat;
use TryCatch;

my %FEATURES  = ( roles => [ q(roles) ], session => TRUE, );
my %FIELD_MAP =
   ( active        => q(active),        crypted_password => q(password),
     email_address => q(email_address), first_name       => q(first_name),
     home_phone    => q(home_phone),    last_name        => q(last_name),
     location      => q(location),      project          => q(project),
     uid           => q(id),            username         => q(username),
     work_phone    => q(work_phone), );

__PACKAGE__->mk_accessors( qw(dbic_user_class dbic_user_model) );

sub new {
   my ($class, $app, $attrs) = @_;

   my $new = $class->next::method( $app, $attrs );

   $new->dbic_user_model( $app->model( $new->dbic_user_class ) );

   return $new;
}

# Interface methods

sub activate_account {
   my ($self, $user) = @_;

   return $self->_execute( sub {
      my $user_obj = $self->assert_user( $user );

      $user_obj->active( TRUE ); $user_obj->update;
   } );
}

sub assert_user {
   my $self     = shift;
   my $user     = shift or throw 'User not specified';
   my $rs       = $self->dbic_user_model->search( { username => $user } );
   my $user_obj = $rs->first
      or throw error => 'User [_1] unknown', args => [ $user ];

   return $user_obj;
}

sub create {
   my ($self, $fields) = @_;

   return $self->_execute( sub {
      my $user    = $fields->{username};
      my $pname   = delete $fields->{profile};
      my $profile = $self->profiles->find( $pname );
      my $passwd  = $fields->{password}
                 || $profile->passwd || $self->def_passwd;

      $passwd !~ m{ [*!] }msx
         and $fields->{password} = $self->_encrypt_password( $passwd );

      my $cols; $cols->{ $_ } = $fields->{ $_ } for (values %FIELD_MAP);

      $self->dbic_user_model->create( $cols );

      $self->roles->is_member_of_role( $pname, $user )
         or $self->roles->add_user_to_role( $pname, $user );

      if ($profile->roles) {
         for my $role (split m{ , }mx, $profile->roles) {
            $self->roles->is_member_of_role( $role, $user )
               or $self->roles->add_user_to_role( $role, $user );
         }
      }
   } );
}

sub delete {
   my ($self, $user) = @_;

   return $self->_execute( sub { $self->assert_user( $user )->delete } );
}

sub get_features {
   return \%FEATURES;
}

sub get_field_map {
   return \%FIELD_MAP;
}

sub update {
   my ($self, $fields)  = @_;

   return $self->_execute( sub {
      my $user     = $fields->{username};
      my $user_obj = $self->assert_user( $user );
      my $src      = $self->dbic_user_model->result_source;

      for my $field (values %FIELD_MAP) {
         $src->has_column( $field ) and exists $fields->{ $field }
            and $user_obj->$field( $fields->{ $field } );
      }

      $user_obj->update;
   } );
}

sub update_password {
   my ($self, @rest) = @_;

   return $self->_execute( sub {
      my ($force, $user) = @rest; my $user_obj = $self->assert_user( $user );

      $user_obj->password( $self->encrypt_password( @rest ) );
      $user_obj->pwlast( $force ? 0 : int time / 86_400 );
      $user_obj->update;
   } );
}

sub user_report {
   my ($self, $args) = @_; my @lines = (); my (@flds, $line);

   my $fmt = $args && $args->{type} ? $args->{type} : q(text);

   for my $user (@{ $self->retrieve->user_list }) {
      my $user_ref = $self->get_user( $user );
      my $passwd   = $user_ref->{password} || NUL;

      @flds = ( q(C) );
   TRY: {
      if ($passwd =~ m{ DISABLED }imsx) { $flds[ 0 ] = q(D); last TRY }
      if ($passwd =~ m{ EXPIRED }imsx)  { $flds[ 0 ] = q(E); last TRY }
      if ($passwd =~ m{ LEFT }imsx)     { $flds[ 0 ] = q(L); last TRY }
      if ($passwd =~ m{ NOLOGIN }imsx)  { $flds[ 0 ] = q(N); last TRY }
      if ($passwd =~ m{ [*!] }msx)      { $flds[ 0 ] = q(N); last TRY }
      } # TRY

      $flds[ 1 ] = $user;
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

   unless ($fmt eq q(csv)) { say @lines }
   else { $self->io( $args->{path} )->println( join "\n", @lines  ) }

   return;
}

# Private methods

sub _execute {
   my ($self, $f) = @_; my $key = __PACKAGE__.q(::_execute); my $res;

   $self->debug and $self->log_debug( __PACKAGE__.q(::).(sub_name 1) );
   $self->lock->set( k => $key );
   $self->cache->{dirty} = TRUE;

   try        { $res = $f->() }
   catch ($e) { $self->lock->reset( k => $key ); throw $e }

   $self->cache->{dirty} = TRUE;
   $self->lock->reset( k => $key );
   return $res;
}

sub _load {
   my $self = shift; my $key = __PACKAGE__.q(::_load); my $user_obj;

   $self->lock->set( k => $key );

   $self->cache->{dirty} or return $self->_cache_results( $key );

   my @keys = keys %{ $self->cache }; delete $self->cache->{ $_ } for (@keys);

   try {
      my $user_col = $FIELD_MAP{username};
      my $rs       = $self->dbic_user_model->search;
      my $src      = $rs->result_source;

      while (defined ($user_obj = $rs->next)) {
         my $user = $user_obj->$user_col;

         for my $field (values %FIELD_MAP) {
            $src->has_column( $field )
               and $self->cache->{users}->{ $user }->{ $field }
                      = $user_obj->$field;
         }
      }

      $self->cache->{dirty} = FALSE;
   }
   catch ($e) { $self->lock->reset( k => $key ); throw $e }

   return $self->_cache_results( $key );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Users::DBIC - Database user storage

=head1 Version

0.5.$Revision: 1139 $

=head1 Synopsis

   use CatalystX::Usul::Users::DBIC;

   my $class = CatalystX::Usul::Users::DBIC;

   my $user_obj = $class->new( $attrs, $app );

=head1 Description

User storage model for relational databases. This model makes use of
L<DBIx::Class>. It inherits from
L<CatalystX::Usul::Model::Identity::Users> and implements the required
list of factory methods

=head1 Subroutines/Methods

=head2 new

Constructor

=head2 activate_account

Searches the user model for the supplies user name and if it exists sets
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

=head2 get_features

Returns a hashref of features supported by this store. Can be checked using
the C<supports> method implemented in C<CatalystX::Usul::Model>

=head2 get_field_map

Returns a reference to the package scoped variable C<%FIELD_MAP>

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

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model::Identity::Users>

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
