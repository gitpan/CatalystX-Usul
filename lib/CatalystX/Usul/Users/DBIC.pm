# @(#)$Id: DBIC.pm 619 2009-06-30 11:54:42Z pjf $

package CatalystX::Usul::Users::DBIC;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 619 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Users);

use Crypt::PasswdMD5;

my $NUL       = q();
my %FEATURES  = ( roles => [ q(roles) ], session => 1, );
my %FIELD_MAP =
   ( active        => q(active),        crypted_password => q(password),
     email_address => q(email_address), first_name       => q(first_name),
     home_phone    => q(home_phone),    last_name        => q(last_name),
     location      => q(location),      project          => q(project),
     uid           => q(id),            username         => q(username),
     work_phone    => q(work_phone), );

__PACKAGE__->config( passwd_type => q(md5), _dirty => 1, );

__PACKAGE__->mk_accessors( qw(dbic_user_class dbic_user_model
                              passwd_type _dirty) );

# Interface methods

sub activate_account {
   my ($self, $user) = @_;

   my ($user_obj) = $self->_assert_user_known_with_src( $user );

   $user_obj->active( 1 ); $user_obj->update;
   $self->_set_dirty;
   return;
}

sub change_password {
   my ($self, $user, $old, $new) = @_;

   $self->update_password( 0, $user, $old, $new );
   return;
}

sub create {
   my ($self, $fields) = @_;
   my ($cols, $e, $passwd, $pname, $profile, $role, $user);

   $pname   = delete $fields->{profile};
   $profile = $self->profile_domain->find( $pname );
   $passwd  = $fields->{password} || $profile->passwd || $self->def_passwd;
   $user    = $fields->{username};

   $fields->{password} = unix_md5_crypt( $passwd ) if ($passwd !~ m{ \* }mx);

   $cols->{ $_ } = $fields->{ $_ } for (values %FIELD_MAP);

   eval { $self->dbic_user_model->create( $cols ) };

   $self->throw( $e ) if ($e = $self->catch);

   $self->_set_dirty;

   unless ($self->role_domain->is_member_of_role( $pname, $user )) {
      $self->role_domain->add_user_to_role( $pname, $user );
   }

   if ($profile->roles) {
      for $role (split m{ , }mx, $profile->roles) {
         unless ($self->role_domain->is_member_of_role( $role, $user )) {
            $self->role_domain->add_user_to_role( $role, $user );
         }
      }
   }

   return;
}

sub delete {
   my ($self, $user) = @_;

   my ($user_obj) = $self->_assert_user_known_with_src( $user );

   $user_obj->delete;
   $self->_set_dirty;
   return;
}

sub get_features {
   return \%FEATURES;
}

sub get_primary_rid {
   return;
}

sub get_user {
   my ($self, $user, $verbose) = @_; my ($cache) = $self->_load; my $new;

   $new->{ $_ } = $self->field_defaults->{ $_ } for (keys %FIELD_MAP);

   bless $new, ref $self || $self;

   return $new unless ($user && exists $cache->{ $user });

   for (keys %FIELD_MAP) {
      $new->{ $_ } = $cache->{ $user }->{ $FIELD_MAP{ $_ } };
   }

   return $new;
}

sub get_users_by_rid {
   return ();
}

sub list {
   my ($self, $pattern) = @_; $pattern ||= q( .+ );

   my ($cache) = $self->_load; my (%found, @users);

   for my $user (keys %{ $cache }) {
      if (not $found{ $user } and $user =~ m{ $pattern }mx) {
         push @users, $user; $found{ $user } = 1;
      }
   }

   return \@users;
}

sub set_password {
   my ($self, $user, $password, $encrypted) = @_;

   $self->update_password( 1, $user, q(), $password, $encrypted );
   return;
}

sub update {
   my ($self, $fields)  = @_; my $user = $fields->{username};

   my ($user_obj, $src) = $self->_assert_user_known_with_src( $user );

   for my $field (values %FIELD_MAP) {
      if ($src->has_column( $field ) && exists $fields->{ $field }) {
         $user_obj->$field( $fields->{ $field } );
      }
   }

   $user_obj->update; $self->_set_dirty;
   return;
}

sub update_password {
   my ($self, @rest) = @_; my ($force, $user) = @rest;

   $self->throw( 'No user specified' ) unless ($user);

   my ($user_obj) = $self->_assert_user_known_with_src( $user );

   $user_obj->password( $self->encrypt_password( @rest ) );
   $user_obj->pwlast( $force ? 0 : int time / 86_400 );
   $user_obj->update; $self->_set_dirty;
   return;
}

sub user_report {
   my ($self, $args) = @_; my @lines = (); my (@flds, $line);

   my $fmt = $args && $args->{type} ? $args->{type} : q(text);

   for my $user (@{ $self->retrieve->user_list }) {
      my $user_ref = $self->get_user( $user );
      my $passwd   = $user_ref->{password} || q();

      @flds = ( q(C) );
   TRY: {
      if ($passwd =~ m{ DISABLED }imx) { $flds[0] = q(D); last TRY }
      if ($passwd =~ m{ EXPIRED }imx)  { $flds[0] = q(E); last TRY }
      if ($passwd =~ m{ LEFT }imx)     { $flds[0] = q(L); last TRY }
      if ($passwd =~ m{ NOLOGIN }imx)  { $flds[0] = q(N); last TRY }
      if ($passwd =~ m{ x }imx)        { $flds[0] = q(C); last TRY }
      if ($passwd =~ m{ \* }mx)        { $flds[0] = q(D); last TRY }
      if ($passwd =~ m{ \! }mx)        { $flds[0] = q(D); last TRY }
      } # TRY

      $flds[1] = $user;
      $flds[2] = $user_ref->{first_name}.q( ).$user_ref->{last_name};
      $flds[3] = $user_ref->{location};
      $flds[4] = $user_ref->{work_phone};
      $flds[5] = $user_ref->{project};
      $flds[6] = 'Never Logged In';

      unless ($fmt eq q(csv)) {
         $line = sprintf '%s %-8.8s %-20.20s %-10.10s %5.5s %-14.14s %-16.16s',
                         map { defined $_ ? $_ : q(~) } @flds[ 0 .. 6 ];
      }
      else { $line = join q(,), map { defined $_ ? $_ : q() } @flds }

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
      unshift @lines, 'Host: '.$self->host.' Printed: '.$self->stamp;

      # Append footer
      push @lines, q(), q();
      $line  = 'Status field key: C = Current, D = Disabled, ';
      $line .= 'E = Expired, L = Left, N = NOLOGIN';
      push @lines, $line;
      push @lines, '                  U = Unused';
      push @lines, "Total users $count";
   }

   unless ($fmt eq q(csv)) { $self->say( @lines ) }
   else { $self->io( $args->{path} )->println( join "\n", @lines  ) }

   return;
}

sub validate_password {
   my ($self, $user, $password) = @_; my $e;

   eval { $self->authenticate( 1, $user, $password ) };

   return 1 unless ($e = $self->catch);

   $self->log_debug( $e->as_string( 2 ) ) if ($self->debug);
   return 0;
}

# Private methods

sub _assert_user_known_with_src {
   my ($self, $user) = @_; my $user_obj;

   my $rs = $self->dbic_user_model->search( { username => $user } );

   unless ($user_obj = $rs->first) {
      $self->throw( error => 'User [_1] unknown', args => [ $user ] );
   }

   return ($user_obj, $rs->result_source);
}

sub _load {
   my $self = shift; my ($cache, $field, $user, $user_obj);

   $self->lock->set( k => __PACKAGE__ );

   unless ($self->_dirty) {
      $cache = { %{ $self->_cache } };
      $self->lock->reset( k => __PACKAGE__ );
      return ($cache);
   }

   $self->_cache( {} );

   eval {
      my $user_col = $FIELD_MAP{username};
      my $rs       = $self->dbic_user_model->search();
      my $src      = $rs->result_source;

      while (defined ($user_obj = $rs->next)) {
         $user = $user_obj->$user_col;

         for $field (values %FIELD_MAP) {
            if ($src->has_column( $field )) {
               $self->_cache->{ $user }->{ $field } = $user_obj->$field;
            }
         }
      }
   };

   my $e = $self->catch;

   $cache = { %{ $self->_cache } }; $self->_dirty( 0 );
   $self->lock->reset( k => __PACKAGE__ );

   $self->throw( $e ) if ($e);

   return ($cache);
}

sub _set_dirty {
   my $self = shift;

   $self->lock->set( k => __PACKAGE__ );
   $self->_dirty( 1 );
   $self->lock->reset( k => __PACKAGE__ );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Users::DBIC - Database user storage

=head1 Version

0.3.$Revision: 619 $

=head1 Synopsis

   use CatalystX::Usul::Users::DBIC;

   my $class = CatalystX::Usul::Users::DBIC;

   my $user_obj = $class->new( $app, $config );

=head1 Description

User storage model for relational databases. This model makes use of
L<DBIx::Class>. It inherits from
L<CatalystX::Usul::Model::Identity::Users> and implements the required
list of factory methods

=head1 Subroutines/Methods

=head2 build_per_context_instance

Make copies of DBIC model references available only after the application
setup is complete

=head2 get_features

Returns a hashref of features supported by this store. Can be checked using
the C<supports> method implemented in C<CatalystX::Usul::Model>

=head2 activate_account

Searches the user model for the supplies user name and if it exists sets
the active column to true

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

=head2 validate_password

Called by L<check_password|CatalystX::Usul::Users/check_password> in
the parent class. This method calls
L<authenticate|CatalystX::Usul::Users/authenticate> in the parent
class

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model::Identity::Users>

=item L<Crypt::PasswdMD5>

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
