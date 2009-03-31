package CatalystX::Usul::Model::Identity::Users::DBIC;

# @(#)$Id: DBIC.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Model::Identity::Users);
use Crypt::PasswdMD5;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

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

__PACKAGE__->mk_accessors( qw(dbic_user_class passwd_type roles _dirty) );

sub build_per_context_instance {
   my ($self, $c, @rest) = @_; my $class;

   my $new = $self->next::method( $c, @rest );

   $class = $new->dbic_user_class;
   $new->user_model( $c->model( $class ) );

   $class = $new->roles_obj->dbic_role_class;
   $new->roles_obj->role_model( $c->model( $class ) );

   $class = $new->roles_obj->dbic_user_roles_class;
   $new->roles_obj->user_roles_model( $c->model( $class ) );

   return $new;
}

sub get_features {
   return \%FEATURES;
}

# Factory methods

sub f_activate_account {
   my ($self, $user) = @_; my ($rs, $user_obj);

   $rs = $self->user_model->search( { username => $user } );

   unless ($user_obj = $rs->first) {
      $self->throw( error => q(eUnknownUser), arg1 => $user );
   }

   $user_obj->active( 1 ); $user_obj->update; $self->_dirty( 1 );
   return;
}

sub f_change_password {
   my ($self, $user, $old, $new) = @_;

   $self->update_password( 0, $user, $old, $new );
   return;
}

sub f_check_password {
   my ($self, $user, $password) = @_; my $e;

   eval { $self->authenticate( 1, $user, $password ) };

   return 1 unless ($e = $self->catch);

   $self->log_debug( $e->as_string( 2 ) ) if ($self->debug);
   return 0;
}

sub f_create {
   my ($self, $fields) = @_;
   my ($cols, $e, $passwd, $pname, $profile, $role, $user);

   $pname   = delete $fields->{profile};
   $profile = $self->profiles_ref->find( $pname );
   $passwd  = $fields->{password} || $profile->passwd || $self->def_passwd;
   $user    = $fields->{username};

   $fields->{password} = unix_md5_crypt( $passwd ) if ($passwd !~ m{ \* }mx);

   $cols->{ $_ } = $fields->{ $_ } for (values %FIELD_MAP);

   eval { $self->user_model->create( $cols ) };

   $self->throw( $e ) if ($e = $self->catch);

   $self->_dirty( 1 );

   unless ($self->roles_obj->is_member_of_role( $pname, $user )) {
      $self->roles_obj->f_add_user_to_role( $pname, $user );
   }

   if ($profile->roles) {
      for $role (split m{ , }mx, $profile->roles) {
         unless ($self->roles_obj->is_member_of_role( $role, $user )) {
            $self->roles_obj->f_add_user_to_role( $role, $user );
         }
      }
   }

   return;
}

sub f_delete {
   my ($self, $user) = @_; my ($rs, $user_obj);

   $rs = $self->user_model->search( { username => $user } );

   unless ($user_obj = $rs->first) {
      $self->throw( error => q(eUnknownUser), arg1 => $user );
   }

   $user_obj->delete; $self->_dirty( 1 );
   return;
}

sub f_get_primary_rid {
   return;
}

sub f_get_user {
   my ($self, $user, $verbose) = @_; my ($cache) = $self->_load; my $user_ref;

   $user_ref->{ $_ } = $self->field_defaults->{ $_ } for (keys %FIELD_MAP);

   return $user_ref unless ($user && exists $cache->{ $user });

   for (keys %FIELD_MAP) {
      $user_ref->{ $_ } = $cache->{ $user }->{ $FIELD_MAP{ $_ } };
   }

   return $user_ref;
}

sub f_get_users_by_rid {
   return ();
}

sub f_is_user {
   my ($self, $user) = @_; my ($cache) = $self->_load;

   return $user && exists $cache->{ $user } ? 1 : 0;
}

sub f_list {
   my ($self, $pattern) = @_; my (%found, @users); my ($cache) = $self->_load;

   $pattern ||= q( .+ );

   for my $user (keys %{ $cache }) {
      if (!$found{ $user } && $user =~ m{ $pattern }mx) {
         push @users, $user; $found{ $user } = 1;
      }
   }

   return \@users;
}

sub f_set_password {
   my ($self, $user, $password, $encrypted) = @_;

   $self->update_password( 1, $user, q(), $password, $encrypted );
   return;
}

sub f_update {
   my ($self, $fields) = @_; my ($field, $rs, $src, $user, $user_obj);

   $user = $fields->{username};
   $rs   = $self->user_model->search( { username => $user } );
   $src  = $rs->result_source;

   unless ($user_obj = $rs->first) {
      $self->throw( error => q(eUnknownUser), arg1 => $user );
   }

   for $field (values %FIELD_MAP) {
      if ($src->has_column( $field ) && exists $fields->{ $field }) {
         $user_obj->$field( $fields->{ $field } );
      }
   }

   $user_obj->update; $self->_dirty( 1 );
   return;
}

sub f_update_password {
   my ($self, $user, $enc_pass, $force) = @_; my ($rs, $user_obj);

   $rs = $self->user_model->search( { username => $user } );

   unless ($user_obj = $rs->first) {
      $self->throw( error => q(eUnknownUser), arg1 => $user );
   }

   $user_obj->password( $enc_pass );
   $user_obj->pwlast( $force ? 0 : int time / 86_400 );
   $user_obj->update; $self->_dirty( 1 );
   return;
}

sub f_user_report {
   my ($self, $args) = @_;
   my ($fmt, @flds, $line, @lines, $passwd, $user, $user_ref);

   $fmt = $args && $args->{type} ? $args->{type} : q(text); @lines = ();

   for $user (@{ $self->retrieve->user_list }) {
      next unless ($user);

      $user_ref = $self->f_get_user( $user );
      $passwd   = $user_ref->{password} || q();
      @flds     = ( q(C) );
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

   @lines = sort @lines;

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
   }

   if ($fmt eq q(csv)) {
      $self->io( $args->{path} )->println( join "\n", @lines  );
   }
   else {
      print {*STDOUT} (join "\n", @lines)."\n"
         or $self->throw( q(eIOError) );
   }

   return;
}

# Private methods

sub _load {
   my $self = shift;
   my ($cache, $field, $rs, $src, $user, $user_col, $user_obj);

   $self->lock->set( k => __PACKAGE__ );

   unless ($self->_dirty) {
      $cache = { %{ $self->_cache } };
      $self->lock->reset( k => __PACKAGE__ );
      return ($cache);
   }

   $self->_cache( {} );
   $user_col = $FIELD_MAP{username};
   $rs       = $self->user_model->search();
   $src      = $rs->result_source;

   while (defined ($user_obj = $rs->next)) {
      $user = $user_obj->$user_col;

      for $field (values %FIELD_MAP) {
         if ($src->has_column( $field )) {
            $self->_cache->{ $user }->{ $field } = $user_obj->$field;
         }
      }
   }

   $cache = { %{ $self->_cache } }; $self->_dirty( 0 );
   $self->lock->reset( k => __PACKAGE__ );
   return ($cache);
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Identity::Users::DBIC - Database user storage

=head1 Version

0.1.$Revision: 402 $

=head1 Synopsis

   use CatalystX::Usul::Model::Identity::Users::DBIC;

   my $class = CatalystX::Usul::Model::Identity::Users::DBIC;

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

=head2 f_activate_account

Searches the user model for the supplies user name and if it exists sets
the active column to true

=head2 f_change_password

Calls C<update_password> in L<CatalystX::Usul::Identity::Users> with
the authenticate flag set to I<false>, thereby forcing the user to
authenticate. Passes the supplied arguments through

=head2 f_check_password

Calls C<authenticate> in L<CatalystX::Usul::Identity::Users>. Returns I<true>
if the authentication succeeded, I<false> otherwise

=head2 f_create

Creates a new user object on the user model. Adds the user to the list of
roles appropriate to the user profile

=head2 f_delete

Deletes a user object from the user model

=head2 f_get_primary_rid

Returns I<undef> as primary role ids are not supported by this storage
backend

=head2 f_get_user

Returns a hash ref of fields for the request user

=head2 f_get_users_by_rid

Returns an empty list as primary role ids are not supported by this storage
backend

=head2 f_is_user

Returns I<true> if the supplied user exists, I<false> otherwise

=head2 f_list

Returns a list reference of users in the database

=head2 f_set_password

Calls C<update_password> in L<CatalystX::Usul::Identity::Users> with
the authenticate flag set to I<true>, which bypasses user
authentication. Passes the supplied arguments through

=head2 f_update

Updates columns on the user object for the supplied user

=head2 f_update_password

Updates the users password in the database

=head2 f_user_report

Generate a report from the data in the user database

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
