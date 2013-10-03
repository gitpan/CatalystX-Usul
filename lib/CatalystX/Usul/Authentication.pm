# @(#)Ident: ;

package CatalystX::Usul::Authentication;

use strict;
use version; our $VERSION = qv( sprintf '0.13.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;

has 'config' => is => 'ro', isa => HashRef, default => sub { {} };

around 'BUILDARGS' => sub {
   my ($next, $self, $config, $app, $realm) = @_;

   return $self->$next( config => $config );
};

sub find_user {
   my ($self, $params, $c) = @_;

   my $user_model = $c->model( $self->config->{model_class} );

   return $user_model->find_user( $params->{ $self->config->{user_field} } );
}

sub for_session {
   my ($self, $c, $user) = @_; return $user ? $user->for_session : undef;
}

sub from_session {
   my ($self, $c, $user) = @_; $user and blessed $user and return $user;

   return $self->find_user( { $self->config->{user_field} => $user }, $c );
}

sub user_supports {
   return shift->config->{model_class}->supports( @_ );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Authentication - Use a Catalyst model as an authentication store

=head1 Version

Describes v0.13.$Rev: 1 $

=head1 Synopsis

   package MyApp;
   use Catalyst qw( ... Authentication ... );

   # The Catalyst::Authentication config below uses this module as an
   # authentication store for both realms

   <component name="Plugin::Authentication">
      <default_realm>R01-Localhost</default_realm>
      <realms>
         <R01-Localhost>
            <credential>
               <class>Password</class>
               <password_field>password</password_field>
               <password_type>self_check</password_type>
            </credential>
            <store>
               <class>+CatalystX::Usul::Authentication</class>
               <model_class>IdentityUnix</model_class>
               <user_field>username</user_field>
            </store>
         </R01-Localhost>
         <R02-Database>
            <credential>
               <class>Password</class>
               <password_field>password</password_field>
               <password_type>self_check</password_type>
            </credential>
            <store>
               <class>+CatalystX::Usul::Authentication</class>
               <model_class>IdentityDBIC</model_class>
               <user_field>username</user_field>
            </store>
         </R02-Database>
      </realms>
   </component>

=head1 Description

Implements the L<Catalyst::Authentication::Store> interface. Uses any
L<Catalyst::Model> that implements the methods; C<find_user>,
C<check_password>, C<for_session>, C<get>, C<get_object>, C<id>, and
C<supports>

=head1 Configuration and Environment

Defined the following attributes

=over 3

=item C<config>

The constructor stores a copy of the C<config> on itself

=back

=head1 Subroutines/Methods

=head2 find_user

Uses the L<model|Catalyst/model> method to obtain a copy of the
identity object. This identity object is instantiated by L<Catalyst> when
the application restarts. In the example config the C<R01-Localhost>
authentication realm uses C<MyApp::Model::UsersUnix> as an identity
class (the C<MyApp::Model::> prefix is automatically applied to the
store class value). The identity object's C<find_user> method returns
a user object. The config for the authentication store defines the
user field in the input parameters.

=head2 for_session

Exposes the C<for_session> method in the user class. This allows the
user class to remove attribute from the user object prior to
serialisation on the session store

=head2 from_session

Return the user object if it already exists otherwise create one by
calling our own L</find_user> method

=head2 user_supports

Expose the C<supports> class method in the user class. Allows the user
class to define which optional features it supports

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
