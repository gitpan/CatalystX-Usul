# @(#)Ident: Users.pm 2013-08-19 19:16 pjf ;

package CatalystX::Usul::Response::Users;

use strict;
use version; our $VERSION = qv( sprintf '0.14.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions   qw( trim );
use CatalystX::Usul::Constraints qw( Path );
use File::Spec;

has 'auth_realm'       => is => 'rw',   isa => SimpleStr | Undef;

has 'roles'            => is => 'rw',   isa => ArrayRef, default => sub { [] };


has 'active'           => is => 'ro',   isa => Bool, default => FALSE;

has 'crypted_password' => is => 'ro',   isa => SimpleStr, default => NUL;

has 'email_address'    => is => 'ro',   isa => SimpleStr, default => NUL;

has 'first_name'       => is => 'ro',   isa => SimpleStr, default => q(Dave);

has 'fullname'         => is => 'lazy', isa => NonEmptySimpleStr,
   default             => sub { $_[ 0 ]->first_name.SPC.$_[ 0 ]->last_name };

has 'homedir'          => is => 'lazy', isa => Path, coerce => TRUE,
   default             => sub { File::Spec->tmpdir };

has 'home_phone'       => is => 'ro',   isa => SimpleStr, default => NUL;

has 'last_name'        => is => 'ro',   isa => SimpleStr, default => NUL;

has 'location'         => is => 'ro',   isa => SimpleStr, default => NUL;

has 'max_sess_time'    => is => 'ro',   isa => PositiveInt,
   default             => MAX_SESSION_TIME;

has 'pgid'             => is => 'ro',   isa => PositiveOrZeroInt | Undef;

has 'project'          => is => 'ro',   isa => SimpleStr, default => NUL;

has 'pwlast'           => is => 'ro',   isa => PositiveOrZeroInt | Undef,
   documentation       => 'Date of last password change';

has 'pwnext'           => is => 'ro',   isa => PositiveOrZeroInt | Undef,
   documentation       => 'Minimum password age';

has 'pwafter'          => is => 'ro',   isa => PositiveOrZeroInt | Undef,
   documentation       => 'Maximum password age';

has 'pwwarn'           => is => 'ro',   isa => PositiveOrZeroInt | Undef,
   documentation       => 'Password warning period';

has 'pwexpires'        => is => 'ro',   isa => PositiveOrZeroInt | Undef,
   documentation       => 'Password inactivity period';

has 'pwdisable'        => is => 'ro',   isa => PositiveOrZeroInt | Undef,
   documentation       => 'Account expiration date';

has 'sess_updt_period' => is => 'ro',   isa => PositiveInt, default => 300;

has 'shell'            => is => 'lazy', isa => Path, coerce => TRUE,
   default             => sub { [ NUL, qw(bin false) ] };

has 'uid'              => is => 'ro',   isa => PositiveOrZeroInt | Undef;

has 'username'         => is => 'ro',   isa => NonEmptySimpleStr,
   default             => q(unknown);

has 'work_phone'       => is => 'ro',   isa => SimpleStr, default => NUL;


has '_users' => is => 'ro', isa => Object,
   handles   => [ qw(find_user supports validate_password) ],
   init_arg  => 'builder', required => TRUE, weak_ref => TRUE;

around 'BUILDARGS' => sub {
   my ($next, $self, @args) = @_; my $attr = $self->$next( @args );

   my $builder   = $attr->{builder} or return $attr;
   my $user_data = delete $attr->{user_data} || {};
   my $verbose   = delete $attr->{verbose  } || FALSE;

   for (grep { defined $user_data->{ $_ } } $self->_attribute_list) {
      $attr->{ $_ } = $user_data->{ $_ };
   }

   $verbose
      and $attr->{project} ||= __get_project( $builder, $attr->{homedir} );

   return $attr;
};

# C::A::Store methods
sub check_password {
   my ($self, $password) = @_; my $username = $self->username;

   (not $username or $username eq q(unknown)) and return;

   return $self->validate_password( $username, $password );
}

sub for_session {
   my $self = shift;

   delete $self->{crypted_password}; delete $self->{_users};
   $self->{homedir} .= NUL; $self->{shell} .= NUL;

   return $self;
}

sub get {
   my ($self, $attr) = @_; return $self->can( $attr ) ? $self->$attr : undef;
}

sub get_object {
   return $_[ 0 ];
}

sub id {
   return $_[ 0 ]->username;
}

# Public methods
around 'active' => sub {
   my ($next, $self) = @_;
   my $now           = int time / 86_400;
   my $expires       = $self->_get_password_expiry_date;

   $expires and $self->pwexpires and $now > $expires + $self->pwexpires
      and return FALSE;

   $self->pwdisable and $now > $self->pwdisable and return FALSE;

   return $self->$next();
};

sub has_password_expired {
   my $self    = shift;
   my $now     = int time / 86_400;
   my $expires = $self->_get_password_expiry_date;

   defined $self->pwlast and $self->pwlast == 0 and return TRUE;

   $expires and $now > $expires and return TRUE;

   return FALSE;
}

sub should_warn_of_expiry {
   my $self    = shift;
   my $now     = int time / 86_400;
   my $expires = $self->_get_password_expiry_date;

   $expires and $self->pwwarn and $now > $expires - $self->pwwarn
      and $self->active and return TRUE;

   return FALSE;
}

sub when_can_change_password {
   my $self = shift;

   ($self->pwlast and $self->pwnext) or return 0;

   my $now        = int time / 86_400;
   my $min_period = $self->pwlast + $self->pwnext;

   return $now >= $min_period ? 0 : $min_period - $now;
}

# Private methods
sub _attribute_list {
   return ( grep { $_ ne 'meta' and '_' ne substr $_, 0, 1 }
            __PACKAGE__->meta->get_attribute_list );
}

sub _get_password_expiry_date {
   my $self = shift;

   return $self->pwlast && $self->pwafter ? $self->pwlast + $self->pwafter : 0;
}

# Private functions
sub __get_project {
   my ($builder, $home) = @_; $home or return NUL;

   my $path = $builder->io( [ $home, q(.project) ] );

   ($path->is_file and not $path->empty) or return NUL;

   return trim $path->chomp->lock->getline;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Response::Users - The actual user object

=head1 Version

Describes v0.14.$Rev: 1 $

=head1 Synopsis

   use CatalystX::Usul::Response::Users;

   $user_object = CatalystX::Usul::Response::Users->new( \%params );

=head1 Description

The actual user object

=head1 Configuration and Environment

Defines a long list of attributes

=head1 Subroutines/Methods

=head2 Catalyst Authentication Store Methods

=head3 check_password

   $bool = $self->check_password( $password );

This method is required by the L<Catalyst::Authentication::Store> API. It
calls the factory method in the subclass to check that the supplied
password is the correct one

=head3 for_session

   $self_for_session = $self->for_session;

This method is required by the L<Catalyst::Authentication::Store> API.
Returns the self referential object with some attribute values removed
from the hash

=head3 get

   $attribute_value = $self->get( $attribute_name );

This method is required by the L<Catalyst::Authentication::Store> API.
Field accessor returns undef if the field does not exist, otherwise
returns the value of the required field

=head3 get_object

   $self = $self->get_object;

This method is required by the L<Catalyst::Authentication::Store> API.
Returns the self referential object

=head3 id

   $username = $self->id;

This method is required by the L<Catalyst::Authentication::Store> API.
Returns the username of the user object

=head2 Public Object Methods

=head3 active

   $bool = $self->active;

Returns true if the account is active. Can be inactive because of active
field in the user account data being set to false, or the account can
be inactive due to password expiration

=head3 has_password_expired

   $bool = $self->has_password_expired;

Returns true if this user object's password has expired. For the expiry
period the password on the account can still be changed

=head3 should_warn_of_expiry

   $bool = $self->should_warn_of_expiry;

Returns true if the accounts password is about to expire

=head3 when_can_change_password

   $days = $self->when_can_change_password;

Returns the number of days before the password can be changed. Returns 0
if the password can be changed now

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Moose>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

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
