# @(#)$Id: Users.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Users;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(exception throw);
use CatalystX::Usul::UserProfiles;
use Crypt::Eksblowfish::Bcrypt qw(bcrypt en_base64);
use File::MailAlias;
use MRO::Compat;
use Sys::Hostname;
use Scalar::Util qw(weaken);
use TryCatch;

my @BASE64 = ( q(a) .. q(z), q(A) .. q(Z), 0 .. 9, q(.), q(/) );
my %FIELDS =
   ( active           => 0,   auth_realm       => undef,
     crypted_password => NUL, email_address    => NUL,
     first_name       => NUL, homedir          => q(/tmp),
     home_phone       => NUL, last_name        => NUL,
     location         => NUL, pgid             => NUL,
     project          => NUL, pwafter          => 0,
     pwdisable        => 0,   pwlast           => undef,
     pwnext           => 0,   pwwarn           => 0,
     pwexpires        => 0,   shell            => q(/bin/false),
     uid              => NUL, username         => q(unknown),
     work_phone       => NUL, );

__PACKAGE__->mk_accessors( keys %FIELDS );

__PACKAGE__->mk_accessors( qw(aliases cache def_passwd field_defaults
                              host max_login_trys max_pass_hist
                              min_fullname_len passwd_type profiles
                              roles sessdir user_list user_pattern
                              userid_len) );

sub new {
   my ($self, $app, $attrs) = @_;

   $attrs->{cache           } ||= { dirty => TRUE };
   $attrs->{def_passwd      } ||= q(*DISABLED*);
   $attrs->{field_defaults  }   = \%FIELDS;
   $attrs->{host            } ||= hostname;
   $attrs->{max_login_trys  } ||= 3;
   $attrs->{max_pass_hist   } ||= 10;
   $attrs->{min_fullname_len} ||= 6;
   $attrs->{passwd_type     } ||= q(Blowfish);
   $attrs->{user_pattern    } ||= q(\A [a-zA-Z0-9]+);
   $attrs->{userid_len      } ||= 3;

   my $new = $self->next::method( $app, $attrs );
   my $ac  = $app->config || {};

   $new->aliases ( $new->_build_aliases ( $ac ) );
   $new->profiles( $new->_build_profiles( $ac ) );

   return $new;
}

# C::A::Store methods

sub check_password {
   my ($self, $password) = @_; my $username = $self->username;

   (not $username or $username eq q(unknown)) and return;

   my $udm = $self->{_domain} or return;

   return $udm->_validate_password( $username, $password );
}

sub find_user {
   my ($self, $user, $verbose) = @_;

   my $new = $self->get_user( $user, $verbose ); $new->roles( [] );

   $new->username ne q(unknown) and $self->supports( qw(roles) )
      and $new->roles( [ $self->roles->get_roles( $user, $new->pgid ) ] );

   $new->{_domain} = $self; weaken( $new->{_domain} );

   return $new;
}

sub for_session {
   my $self = shift;

   delete $self->{crypted_password}; delete $self->{_domain};

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

sub activate_account {
   my ($self, $key) = @_; return;
}

sub authenticate {
   my ($self, $test_for_expired, $user, $passwd) = @_;

   my $user_obj = $self->_assert_user( $user );

   $user_obj->active
      or throw error => 'User [_1] account inactive', args => [ $user ];

   $test_for_expired and $self->_has_password_expired( $user_obj )
      and throw error => 'User [_1] password expired', args => [ $user ];

   if ($passwd eq q(stdin)) {
      $passwd = <STDIN>; $passwd ||= NUL; chomp $passwd;
   }

   my $stored   = $user_obj->crypted_password || NUL;
   my $supplied = $self->_encrypt_password( $passwd, $stored );
   my $path     = $self->io( $self->catfile( $self->sessdir, $user ) );

   $self->lock->set( k => $path );

   if ($supplied eq $stored) {
      $path->is_file and $path->unlink;
      $self->lock->reset( k => $path );
      return $user_obj;
   }

   $self->_count_login_attempt( $user, $path );
   $self->lock->reset( k => $path );
   throw error => 'User [_1] incorrect password for class [_2]',
         args  => [ $user, ref $user_obj ];
   return;
}

sub change_password {
   my ($self, @rest) = @_; $self->update_password( FALSE, @rest ); return;
}

sub disable_account {
   my ($self, $user) = @_;

   $self->update_password( TRUE, $user, NUL, q(*DISABLED*), TRUE );
   return;
}

sub encrypt_password {
   my ($self, $force, $user, $old_pass, $new_pass, $encrypted) = @_;

   unless ($force) {
      my $user_obj = $self->authenticate( FALSE, $user, $old_pass );

      if ((my $days = $self->_can_change_password( $user_obj )) > 0) {
         my $msg = 'User [_1] cannot change password for [_2] days';

         throw error => $msg, args => [ $user, $days ];
      }
   }

   my $enc_pass;
   my @passwords = ();
   my $path      = $self->catfile( $self->sessdir, $user.q(_history) );
   my $io        = $self->io( $path )->chomp->lock;

   if ($encrypted) { $enc_pass = $new_pass }
   else {
      if (not $force and $io->is_file and my $line = $io->getline) {
         @passwords = split m{ , }mx, $line;

         for my $used_pass (@passwords) {
            $enc_pass = $self->_encrypt_password( $new_pass, $used_pass );
            $enc_pass eq $used_pass and throw 'Password used before';
         }
      }

      $enc_pass = $self->_encrypt_password( $new_pass );
   }

   unless ($force) {
      push @passwords, $enc_pass;
      shift @passwords while ($#passwords > $self->max_pass_hist);
      $io->close->println( join q(,), @passwords );
   }

   return $enc_pass;
}

sub get_new_user_id {
   my ($self, $first_name, $last_name, $prefix) = @_; my $lid;

   defined $prefix or $prefix = NUL;

   my $name = (lc $last_name).(lc $first_name);

   if ((length $name) < $self->min_fullname_len) {
      throw error => 'User name [_1] too short [_2] character min.',
            args  => [ $first_name.SPC.$last_name, $self->min_fullname_len ];
   }

   my $name_len = $self->userid_len;
   my $lastp    = length $name < $name_len ? length $name : $name_len;
   my @chars    = ();

   $chars[ $_ ] = $_ for (0 .. $lastp - 1);

   while ($chars[ $lastp - 1 ] < length $name) {
      my $i = 0; $lid = NUL;

      while ($i < $lastp) { $lid .= substr $name, $chars[ $i++ ], 1 }

      $self->is_user( $prefix.$lid ) or last;

      $i = $lastp - 1; $chars[ $i ] += 1;

      while ($i >= 0 and $chars[ $i ] >= length $name) {
         my $ripple = $i - 1; $chars[ $ripple ] += 1;

         while ($ripple < $lastp) {
            my $carry = $ripple + 1; $chars[ $carry ] = $chars[ $ripple++ ] +1;
         }

         $i--;
      }
   }

   if ($chars[ $lastp - 1 ] >= length $name) {
      throw error => 'User name [_1] no ids left',
            args  => [ $first_name.SPC.$last_name ];
   }

   $lid or throw error => 'User name [_1] no user id', args => [ $name ];

   return ($prefix || NUL).$lid;
}

sub get_primary_rid {
   return;
}

sub get_user {
   my ($self, $user) = @_;

   my $new = bless {}, ref $self || $self;

   $new->{ $_ } = $FIELDS{ $_ } for (keys %FIELDS);

   my $uref = $self->_get_user_ref( $user ) or return $new;
   my $map  = $self->get_field_map;

   $new->{ $_ } = $uref->{ $map->{ $_ } } for (keys %{ $map });

   return $new;
}

sub get_users_by_rid {
   return ();
}

sub is_user {
   my ($self, $user) = @_; return $self->_get_user_ref( $user ) ? TRUE : FALSE;
}

sub list {
   my ($self, $pattern) = @_; my (%found, @users); $pattern ||= q( .+ );

   push @users, map  {     $found{ $_ } = TRUE; $_ }
                grep { not $found{ $_ } and $_ =~ m{ $pattern }mx }
                sort keys %{ ($self->_load)[ 0 ] };

   return \@users;
}

sub make_email_address {
   my ($self, $user) = @_; $user or return NUL; my $alias;

   exists $self->aliases->aliases_map->{ $user }
      and $alias = $self->aliases->find( $user )
      and return $alias->recipients->[ 0 ];

   return $user.q(@).$self->aliases->mail_domain;
}

sub retrieve {
   my ($self, $pattern, $user) = @_;

   my $user_obj = $self->find_user( $user, TRUE );

   $user_obj->user_list( $self->list( $pattern || $self->user_pattern ) );

   return $user_obj;
}

sub set_password {
   my ($self, $user, @rest) = @_;

   $self->update_password( TRUE, $user, NUL, @rest );
   return;
}

# Private methods

sub _assert_user {
   my ($self, $user, $verbose) = @_; $user or throw 'User not specified';

   my $user_obj = $self->get_user( $user, $verbose );

   $user_obj->username eq q(unknown)
      and throw error => 'User [_1] unknown', args => [ $user ];

   return $user_obj;
}

sub _build_aliases {
   my ($self, $ac) = @_; $self->aliases and return;

   my $attrs = { ioc_obj => $self, path => $ac->{aliases_path} || NUL };

   return File::MailAlias->new( $attrs );
}

sub _build_profiles {
   my ($self, $ac) = @_; $self->profiles and return;

   my $attrs = { ioc_obj => $self, path => $ac->{profiles_path} || NUL };

   return CatalystX::Usul::UserProfiles->new( $attrs );
}

sub _cache_results {
   my ($self, $key) = @_; my $cache = { %{ $self->cache } };

   $self->lock->reset( k => $key );

   return ($cache->{users}, $cache->{rid2users}, $cache->{uid2name});
}

sub _can_change_password {
   my ($self, $user_obj) = @_; $user_obj->pwnext or return 0;

   my $now        = int time / 86_400;
   my $min_period = $user_obj->pwlast + $user_obj->pwnext;

   return $now >= $min_period ? 0 : $min_period - $now;
}

sub _count_login_attempt {
   my ($self, $user, $path) = @_;

   my $n_trys = $path->is_file ? $path->chomp->getline || 0 : 0;

   $path->println( ++$n_trys );
   (not $self->max_login_trys or $n_trys < $self->max_login_trys) and return;
   $path->is_file and $path->unlink;
   $self->lock->reset( k => $path );
   $self->disable_account( $user );
   throw error => 'User [_1] max login attempts [_2] exceeded',
         args  => [ $user, $self->max_login_trys ];
   return;
}

sub _encrypt_password {
   my ($self, $password, $salt) = @_;

   my $type = $salt && $salt =~ m{ \A \$ 1    \$ }msx ? q(MD5)
            : $salt && $salt =~ m{ \A \$ 2 a? \$ }msx ? q(Blowfish)
            : $salt && $salt =~ m{ \A \$ 5    \$ }msx ? q(SHA-256)
            : $salt && $salt =~ m{ \A \$ 6    \$ }msx ? q(SHA-512)
            : $salt                                   ? q(unix)
                                                      : $self->passwd_type;

   $salt ||= __get_salt_by_type( $type );

   return $type eq q(Blowfish) ? bcrypt( $password, $salt )
                               :  crypt  $password, $salt;
}

sub _get_user_ref {
   my ($self, $user) = @_; $user or return;

   my ($cache) = $self->_load; return $cache->{ $user };
}

sub _has_password_expired {
   my ($self, $user_obj) = @_;

   my $now     = int time / 86_400;
   my $expires = $user_obj->pwlast && $user_obj->pwafter
               ? $user_obj->pwlast +  $user_obj->pwafter : 0;

   return TRUE if (defined $user_obj->pwlast and $user_obj->pwlast == 0);
   return TRUE if ($expires and $now > $expires);
   return TRUE if ($user_obj->pwdisable and $now > $user_obj->pwdisable);
   return FALSE;
}

sub _load {
   return ({}, {}, {});
}

sub _validate_password {
   my ($self, $user, $password) = @_;

   try        { $self->authenticate( TRUE, $user, $password ) }
   catch ($e) { $self->debug and $self->log_debug( exception $e );
                return FALSE }

   return TRUE;
}

# Private subroutines

sub __get_salt_by_type {
   my $type = shift;

   $type eq q(MD5)      and return '$1$'.__get_salt_bytes( 8 );
   $type eq q(Blowfish) and
            return '$2a$08$'.(en_base64( __get_salt_bytes( 16 ) ));
   $type eq q(SHA-256)  and return '$5$'.__get_salt_bytes( 8 );
   $type eq q(SHA-512)  and return '$6$'.__get_salt_bytes( 8 );

   return __get_salt_bytes( 2 );
}

sub __get_salt_bytes ($) {
   return join NUL, map { $BASE64[ rand 64 ] } 1 .. $_[ 0 ];
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Users - User domain model

=head1 Version

0.6.$Revision: 1165 $

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

=head2 activate_account

Placeholder methods returns undef. May be overridden in a subclass

=head2 authenticate

Called by the L</check_password> method via the factory subclass. The
supplied password is encrypted and compared to the one in storage.
Failures are counted and when I<max_login_trys> are exceeded the
account is disabled. Errors can be thrown for; unknown user, inactive
account, expired password, maximum attempts exceeded and incorrect
password

=head2 change_password

Proxies a call to C<update_password> which must be implemented by
the subclass

=head2 check_password

This method is required by the L<Catalyst::Authentication::Store> API. It
calls the factory method in the subclass to check that the supplied
password is the correct one

=head2 disable_account

Calls C<update_password> in the subclass
to set the users encrypted password to I<*DISABLED> thereby preventing
the user from logging in

=head2 encrypt_password

   $enc_pass = $self->encrypt_password( $force, $user, $old, $new, $encrypted);

Encrypts the I<new> password and returns it. If the I<encrypted> flag
is true then I<new> is assumed to be already encrypted and is returned
unchanged. The I<old> password is used to authenticate the I<user> unless
the I<force> flag is true

=head2 find_user

This method is required by the L<Catalyst::Authentication::Store>
API. It returns a user object (obtained by calling L</get_user>)
even if the user is unknown. If the user is known a list of roles that
the user belongs to is also returned. Adds a weakened reference to
self so that L<Catalyst::Authentication> can call the
L</check_password> method

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

=head2 get_primary_rid

Placeholder methods returns undef. May be overridden in a subclass

=head2 get_object

This method is required by the L<Catalyst::Authentication::Store> API.
Returns the self referential object

=head2 get_user

Returns a user object for the given user id. If the user does not exist
then a user object with a name of I<unknown> is returned

=head2 get_users_by_rid

Placeholder methods returns an empty list. May be overridden in a subclass

=head2 id

This method is required by the L<Catalyst::Authentication::Store> API.
Returns the username of the user object

=head2 is_user

Returns true if the given user exists, false otherwise

=head2 list

Returns an array ref of all users

=head2 make_email_address

Takes a user if or an an attribute hash, returns a guess as to what the
users email address might be

=head2 retrieve

Returns a user object for the selected user and a list of usernames

=head2 set_password

Proxies a call to C<update_password> which must be implemented by
the subclass

=head2 _validate_password

Wraps a call to L</authenticate> in a try block so that a failure
to validate the password returns false rather than throwing an
exception

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul>

=item L<CatalystX::Usul::Constants>

=item L<CatalystX::Usul::UserProfiles>

=item L<Crypt::Eksblowfish::Bcrypt>

=item L<File::MailAlias>

=item L<Sys::Hostname>

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
