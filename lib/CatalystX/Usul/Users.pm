# @(#)$Id: Users.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::Users;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul);

use Class::C3;
use Crypt::PasswdMD5;
use Sys::Hostname;
use Scalar::Util qw(weaken);

my $NUL    = q();
my $SPC    = q( );
my @CSET   = ( q(.), q(/), 0 .. 9, q(A) .. q(Z), q(a) .. q(z) );
my %FIELDS =
   ( active           => 0,             auth_realm       => undef,
     crypted_password => $NUL,          email_address    => $NUL,
     first_name       => $NUL,          homedir          => q(/tmp),
     home_phone       => $NUL,          uid              => $NUL,
     last_name        => $NUL,          location         => $NUL,
     pgid             => $NUL,          project          => $NUL,
     pwafter          => 0,             pwdisable        => 0,
     pwlast           => 0,             pwnext           => 0,
     pwwarn           => 0,             pwexpires        => 0,
     shell            => q(/bin/false), username         => q(unknown),
     work_phone       => $NUL, );

__PACKAGE__->mk_accessors( keys %FIELDS );

__PACKAGE__->config( def_passwd       => q(*DISABLED*),
                     host             => hostname,
                     max_login_trys   => 3,
                     max_pass_hist    => 10,
                     min_fullname_len => 6,
                     sessdir          => q(hist),
                     user_pattern     => q(\A [a-zA-Z0-9]+),
                     userid_len       => 3, );

__PACKAGE__->mk_accessors( qw(alias_domain def_passwd field_defaults
                              host max_login_trys max_pass_hist
                              min_fullname_len profile_domain
                              role_domain roles sessdir user_list
                              user_pattern userid_len _cache
                              _rid2users _uid2name) );

sub new {
   my ($self, $app, $config) = @_;

   my $new      = $self->next::method( $app, $config );
   my $app_conf = $app->config || {};

   $new->field_defaults( \%FIELDS                              );
   $new->sessdir       ( $app_conf->{sessdir} || $new->sessdir );

   return $new;
}

# C::A::Store methods

sub check_password {
   my ($self, $password) = @_; my $username = $self->username; my $udm;

   return if (not $username or $username eq q(unknown));

   return unless ($udm = $self->{_domain});

   return $udm->validate_password( $username, $password );
}

sub find_user {
   my ($self, $user, $verbose) = @_;

   my $new = $self->get_user( $user, $verbose );

   if ($new->username ne q(unknown) && $self->supports( qw(roles) )) {
      $new->roles( [ $self->role_domain->get_roles( $user, $new->pgid ) ] );
   }
   else { $new->roles( [] ) }

   $new->{_domain} = $self; weaken( $new->{_domain} );

   return $new;
}

sub for_session {
   my $self = shift;

   delete $self->{crypted_password};
   delete $self->{_domain};
   return $self;
}

sub get {
   my ($self, $attr) = @_; return $self->can( $attr ) ? $self->$attr : undef;
}

sub get_object {
   my $self = shift; return $self;
}

sub id {
   my $self = shift; return $self->username;
}

# Object methods

sub authenticate {
   my ($self, $test_for_expired, $user, $passwd) = @_; my ($e, $n_trys, $res);

   $self->throw( 'No user specified' ) unless ($user);

   my $user_obj = $self->_assert_user_known( $user );

   unless ($user_obj->active) {
      $self->throw( error => 'User [_1] account inactive', args => [ $user ] );
   }

   if ($test_for_expired and $self->_has_password_expired( $user_obj )) {
      $self->throw( error => 'User [_1] password expired', args => [ $user ] );
   }

   if ($passwd eq q(stdin)) {
      $passwd = <STDIN>; $passwd ||= $NUL; chomp $passwd;
   }

   if ($user_obj->crypted_password =~ m{ \A \$ 1 \$ }msx) {
      $res = unix_md5_crypt( $passwd, $user_obj->crypted_password );
   }
   else { $res = crypt $passwd, $user_obj->crypted_password }

   my $path = $self->catfile( $self->sessdir, $user );

   $self->lock->set( k => $path );

   if ($res eq $user_obj->crypted_password) {
      unlink $path if (-f $path);
      $self->lock->reset( k => $path );
      return $user_obj;
   }

   if (-f $path) {
      $n_trys = eval { $self->io( $path )->chomp->getline };

      if ($e = $self->catch) {
         $self->lock->reset( k => $path ); $self->throw( $e );
      }

      $n_trys ||= 0; $n_trys++;
   }
   else { $n_trys = 1 }

   if ($self->max_login_trys and $n_trys >= $self->max_login_trys) {
      unlink $path if (-f $path);
      $self->lock->reset( k => $path );
      $self->disable_account( $user );
      $self->throw( error => 'User [_1] max login attempts [_2] exceeded',
                    args  => [ $user, $self->max_login_trys ] );
   }

   eval { $self->io( $path )->println( $n_trys ) };

   if ($e = $self->catch) {
      $self->lock->reset( k => $path ); $self->throw( $e );
   }

   $self->lock->reset( k => $path );
   $self->throw( error => 'User [_1] incorrect password', args => [ $user ] );
   return;
}

sub disable_account {
   my ($self, $user) = @_;

   $self->update_password( 1, $user, $NUL, q(*DISABLED*), 1 );
   return;
}

sub encrypt_password {
   my ($self, $force, $user, $old_pass, $new_pass, $encrypted) = @_;
   my ($enc_pass, @flds, $line, $res);

   unless ($force) {
      my $user_obj = $self->authenticate( 0, $user, $old_pass );

      if (($res = $self->_can_change_password( $user_obj )) > 0) {
         my $msg = 'User [_1] cannot change password for [_2] days';

         $self->throw( error => $msg, args => [ $user, $res ] );
      }
   }

   my $path = $self->catfile( $self->sessdir, $user.q(_history) );

   unless ($encrypted) {
      if (not $force
          and -f $path
          and $line = $self->io( $path )->chomp->lock->getline) {
         @flds = split m{ , }mx, $line;

         for my $i (0 .. $#flds - 1) {
            if ($self->passwd_type eq q(md5)) {
               $enc_pass = unix_md5_crypt( $new_pass, $flds[ $i ] );
            }
            else { $enc_pass = crypt $new_pass, $flds[ $i ] }

            $self->throw( 'Password used before' ) if ($enc_pass eq $flds[$i]);
         }
      }

      if ($self->passwd_type eq q(md5)) {
         $enc_pass  = unix_md5_crypt( $new_pass );
      }
      else {
         $enc_pass  = crypt $new_pass, join $NUL, @CSET[ rand 64, rand 64 ];
      }
   }
   else { $enc_pass = $new_pass }

   unless ($force) {
      push @flds, $enc_pass;

      while ($#flds > $self->max_pass_hist) { shift @flds }

      $self->io( $path )->lock->println( join q(,), @flds );
   }

   return $enc_pass;
}

sub get_new_user_id {
   my ($self, $first_name, $last_name, $prefix) = @_;
   my ($carry, @chars, $i, $lastp, $lid, $name_len, $ripple, @words);

   my $name = (lc $last_name).(lc $first_name);

   if ((length $name) < $self->min_fullname_len) {
      $self->throw( error => 'User name [_1] too short [_2] character min.',
                    args  => [ $first_name.$SPC.$last_name,
                               $self->min_fullname_len ] );
   }

   $name_len  = $self->userid_len;
   $prefix    = $NUL unless (defined $prefix);
   $lastp     = length $name < $name_len ? length $name : $name_len;
   @chars     = ();
   $chars[$_] = $_ for (0 .. $lastp - 1);

   while ($chars[ $lastp - 1 ] < length $name) {
      $lid = $NUL; $i = 0;

      while ($i < $lastp) { $lid .= substr $name, $chars[ $i++ ], 1 }

      last unless ($self->is_user( $prefix.$lid ));

      $i = $lastp - 1; $chars[ $i ] += 1;

      while ($i >= 0 && $chars[ $i ] >= length $name) {
         $ripple = $i - 1; $chars[ $ripple ] += 1;

         while ($ripple < $lastp) {
            $carry = $ripple + 1; $chars[ $carry ] = $chars[ $ripple++ ] + 1;
         }

         $i--;
      }
   }

   if ($chars[ $lastp - 1 ] >= length $name) {
      $self->throw( error => 'User name [_1] no ids left',
                    args  => [ $first_name.$SPC.$last_name ] );
   }

   unless ($lid) {
      $self->throw( error => 'User name [_1] no user id', args => [ $name ] );
   }

   return ($prefix || $NUL).$lid;
}

sub is_user {
   my ($self, $user) = @_;

   return unless ($user);

   my ($cache) = $self->_load;

   return exists $cache->{ $user } ? 1 : 0;
}

sub retrieve {
   my ($self, $pattern, $user) = @_;

   my $user_obj = $self->find_user( $user, 1 );

   $user_obj->user_list( $self->list( $pattern || $self->user_pattern ) );

   return $user_obj;
}

# Private methods

sub _assert_user_known {
   my ($self, $user, $verbose) = @_;

   my $user_obj = $self->get_user( $user, $verbose );

   if ($user_obj->username eq q(unknown)) {
      $self->throw( error => 'User [_1] unknown', args => [ $user ] );
   }

   return $user_obj;
}

sub _can_change_password {
   my ($self, $user_obj) = @_;

   return 0 unless ($user_obj->pwnext);

   my $now        = int time / 86_400;
   my $min_period = $user_obj->pwlast + $user_obj->pwnext;

   return $now >= $min_period ? 0 : $min_period - $now;
}

sub _has_password_expired {
   my ($self, $user_obj) = @_;
   my $now     = int time / 86_400;
   my $expires = $user_obj->pwlast && $user_obj->pwafter
               ? $user_obj->pwlast +  $user_obj->pwafter : 0;

   return 1 if (defined $user_obj->pwlast and $user_obj->pwlast == 0);
   return 1 if ($expires and $now > $expires);
   return 1 if ($user_obj->pwdisable and $now > $user_obj->pwdisable);
   return 0;
}

sub _load {
   return {};
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Users - User domain model

=head1 Version

0.1.$Revision: 562 $

=head1 Synopsis

   use CatalystX::Usul::Users;

=head1 Description

Implements the base class for user data stores. Each subclass
that inherits from this should implement the required list of methods

=head1 Subroutines/Methods

=head2 new

Constructor initialises these attributes

=over 3

=item field_defaults

A hashref of the user object attributes and their default values

=item sessdir

Path to the directory containing the user password history files and
the count of failed login attempts

=back

=head2 authenticate

Called by the L</check_password> method via the factory subclass. The
supplied password is encrypted and compared to the one in storage.
Failures are counted and when I<max_login_trys> are exceeded the
account is disabled. Errors can be thrown for; unknown user, inactive
account, expired password, maximum attempts exceeded and incorrect
password

=head2 check_password

This method is required by the L<Catalyst::Authentication::Store> API. It
calls the factory method in the subclass to check that the supplied
password is the correct one

=head2 disable_account

Calls L<update_password|CatalystX::Usul::Users::Unix/update_password>
to set the users encrypted password to I<*DISABLED> thereby preventing
the user from logging in

=head2 encrypt_password

   $enc_pass = $self->encrypt_password( $force, $user, $old, $new, $encrypted);

Encrypts the I<new> password and returns it. If the I<encrypted> flag
is true then I<new> is assumed to be already encrypted and is returned
unchanged. The I<old> password is used to authenticate the I<user> unless
the I<force> flag is true

=head2 find_user

This method is required by the L<Catalyst::Authentication::Store> API. It
returns a user object even if the user is unknown. If the user is known
a list of roles that the user belongs to is also returned

=head2 for_session

This method is required by the L<Catalyst::Authentication::Store> API.
Returns the self referential object

=head2 get

This method is required by the L<Catalyst::Authentication::Store> API.
Field accessor returns undef if the field does not exist, otherwise
returns the value of the required field

=head2 get_new_user_id

Implements the algorithm that derives the username from the users first
name and surname. The supplied prefix from the user profile is prepended
to the generated value. If the prefix contains unique domain information
then the generated username will be globally unique to the organisation

=head2 get_object

This method is required by the L<Catalyst::Authentication::Store> API.
Returns the self referential object

=head2 id

This method is required by the L<Catalyst::Authentication::Store> API.
Returns the username of the user object

=head2 is_user

Returns true if the given user exists, false otherwise

=head2 retrieve

Returns a user object for the selected user and a list of usernames

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Crypt::PasswdMD5>

=item L<Sys::Hostname>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Author

Peter Flanigan, C<< <Support at RoxSoft.co.uk> >>

=head1 Acknowledgements

Larry Wall - For the Perl programming language

=head1 License and Copyright

Copyright (c) 2009 Peter Flanigan. All rights reserved

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
