# @(#)$Id: Entrance.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::Controller::Entrance;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Controller);

use Class::C3;

my $SEP = q(/);

__PACKAGE__->config( docs_uri       => q(/html/index.html),
                     realm_class    => q(IdentityUnix),
                     register_class => q(IdentityDBIC), );

__PACKAGE__->mk_accessors( qw(docs_uri realm_class register_class) );

sub activate_account : Chained(register_base) Args(1) Public {
   my ($self, $c, $key) = @_; my $model = $c->model( q(Navigation) );

   $model->clear_menus;
   $model->add_menu_blank;
   $c->stash->{register_model}->activate_account( $key );
   return;
}

sub auth : Chained(common) PathPart(authentication) CaptureArgs(0) {
   my ($self, $c) = @_; my ($msg, $user_class);

   my $s     = $c->stash;
   my $model = $c->model( $self->realm_class );
   my $realm = $self->get_key( $c, q(realm) ) || $model->default_realm;

   unless ($realm && ($user_class = $model->auth_realms->{ $realm })) {
      $user_class = $self->realm_class;
      $msg        = 'Defaulting user class [_1]';
      $self->log_warning( $self->loc( $c, $msg, $user_class ) );
   }

   $s->{user_model} = $c->model( $user_class )->users;
   return;
}

sub authentication : Chained(auth) PathPart('') Args HasActions {
   my ($self, $c, $id) = @_; $c->stash->{user_model}->form( $id ); return;
}

sub authentication_login : ActionFor(authentication.login) {
   my ($self, $c, $no_redirect) = @_; my ($msg, $user_ref, $wanted);

   my $s     = $c->stash;
   my $model = $c->model( q(Base) );

   $model->scrubbing( 1 );

   my $realm = $model->query_value( q(realm)  );
   my $user  = $model->query_value( q(user)   );
   my $pass  = $model->query_value( q(passwd) );

   if ($user && $pass) {
      my $userinfo = { username => $user, password => $pass };
      my @realms   = $realm ? ( $realm ) : sort keys %{ $c->auth_realms };

      for $realm (@realms) {
         next if     ($realm eq q(default));
         next unless ($user_ref = $c->find_user( $userinfo, $realm )
                      and $user_ref->username eq $user);

         if ($c->authenticate( $userinfo, $realm )) {
            $c->session->{elapsed} = time;
            $msg = "User [_1] logged in to realm [_2]";
            $self->log_info( $self->loc( $c, $msg, $user, $realm ) );

            return 1 if ($no_redirect);

            if ($wanted = $c->session->{wanted}) {
               $c->session->{wanted} = q();
               $self->redirect_to_path( $c, $wanted );
               return 1;
            }

            $self->redirect_to_path( $c, $c->config->{default_action} );
            return 1;
         }
      }

      $c->logout;
      $s->{override} = 1;
      $s->{user    } = q(unknown);
      $c->session_expire_key( __user => 0 );
      $msg = 'The login id ([_1]) and password were not recognised';
      $self->throw( error => $msg, args => [ $user ] );
   }

   $s->{user} = q(unknown);
   $self->throw( 'Id and/or password not set' );
   return;
}

sub base : Chained(lang) CaptureArgs(0) {
   # PathPart set in global configuration
}

sub begin : Private {
   return shift->next::method( @_ );
}

sub change_password : Chained(auth) Args HasActions {
   my ($self, $c, $realm, $id) = @_;

   $realm = $self->set_key( $c, q(realm), $realm );
   $c->stash->{user_model}->form( $realm, $id );
   return;
}

sub change_password_set : ActionFor(change_password.set) {
   my ($self, $c) = @_; $c->stash->{user_model}->change_password; return 1;
}

sub check_field : Chained(base) Args(0) HasActions Public {
   return shift->next::method( @_ );
}

sub common : Chained(base) PathPart('') CaptureArgs(0) {
   my ($self, $c) = @_;

   $self->next::method( $c );
   $self->load_keys( $c );
   return;
}

sub doc_base : Chained(common) PathPart(documentation) CaptureArgs(0) {
}

sub documentation : Chained(doc_base) PathPart('') Args(0) {
   my ($self, $c) = @_;

   $c->model( q(Help) )->documentation( $c->uri_for( $self->docs_uri ) );
   return;
}

sub lang : Chained(/) PathPart('') CaptureArgs(1) {
   # Capture the language selection from the requested url
}

sub module_docs : Chained(doc_base) Args {
   my ($self, $c, $module) = @_;

   $c->model( q(Help) )->module_docs( $module || ref $self );
   return;
}

sub modules : Chained(doc_base) Args(0) {
   my ($self, $c) = @_; $c->model( q(Help) )->module_list; return;
}

sub reception_base : Chained(common) PathPart(reception) CaptureArgs(0) {
}

sub reception : Chained(reception_base) PathPart('') Args(0) HasActions {
   my ($self, $c) = @_;

   $c->model( q(Base) )->simple_page( q(reception) );
   return;
}

sub redirect_to_default : Chained(base) PathPart('') Args {
   my ($self, $c) = @_;

   return $self->redirect_to_path( $c, $SEP.q(reception) );
}

sub register_base : Chained(common) PathPart('') CaptureArgs(0) {
   my ($self, $c) = @_; my $s = $c->stash;

   $s->{register_model} = $c->model( $self->register_class )->users;

   return;
}

sub register : Chained(register_base) Args(0) HasActions {
   my ($self, $c) = @_; $c->stash->{register_model}->form; return;
}

sub register_create : ActionFor(register.insert) {
   my ($self, $c) = @_; my $s = $c->stash;

   my $value = $s->{register_model}->query_value( q(security) );

   unless ($c->validate_captcha( $value )) {
      $self->throw( error => 'Security code [_1] incorrect',
                    args  => [ $value ] );
   }

   $s->{register}->{profile} = q(users);
   $s->{register_model}->register;
   return 1;
}

sub sitemap : Chained(common) Args(0) {
   my ($self, $c) = @_; $c->model( q(Navigation) )->sitemap; return;
}

sub tutorial : Chained(reception_base) Args {
   my ($self, $c, $n_cols) = @_;

   $c->model( q(Base) )->simple_page( q(tutorial), $n_cols );
   $c->model( $self->realm_class )->users->authentication_reminder;
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Entrance - Common controller methods

=head1 Version

$Revision: 562 $

=head1 Synopsis

   package MyApp::Controller::Entrance;

   use base qw(CatalystX::Usul::Controller::Entrance);

=head1 Description

Provides controller methods that are common to multiple applications. The
methods include welcome pages, authentication, sitemap and documentation

=head1 Subroutines/Methods

=head2 activate_account

Activates newly created accounts

=head2 auth

Intermediate controller maps to the authentication path part. Three other
controllers chain to this one so as to appear in the right place in the
navigation menu

=head2 authentication

Identify yourself to the system. You will need a login id and password
to prove your identity to the system

=head2 authentication_login

Authenticate the user. If another controller was wanted and the user
was forced to authenticate first, redirect the session to the
originally requested controller. This was stored in a cookie by the
auto method prior to redirecting to the authentication controller
which forwarded to here

=head2 base

A midpoint in the URI that does nothing except act as a placeholder
for the namespace which is I<entrance>

=head2 begin

Exposes the method of the same name in the parent class which is
responsible for stuffing the stash with all of the non endpoint
specific data

=head2 change_password

Change your password. Passwords will be checked for conformance with
local rules

=head2 change_password_set

This private method invokes the data model to update a user password

=head2 check_field

Action to enable Ajax field checking. Calls method of same name in
parent class

=head2 common

A midpoint in the URI. A number of other actions are chained off this
one. It sets up the navigation menu and form keys

=head2 doc_base

Another midpoint, this one is used by documentation endpoints

=head2 documentation

Links to the HTML documentation index generated from POD. It can be
regenerated with the command

   bin/munchies_misc -n -c pod2html

=head2 lang

Capture the required language. The actual work is done in the
L</begin> method

=head2 module_docs

Displays the POD for the selected module

=head2 modules

Displays a table of modules used by the application and their version
numbers. It has clickable fields that display POD for the module and
it's source code

=head2 reception_base

Intermediate subroutine maps to the reception path part. Both receptionView
and the tutorial chain to this controller

=head2 reception

Display the splash page for the application

=head2 redirect_to_default

Redirects client to this controllers default page

=head2 register_base

Midpoint that stashes a copy of the register model for use by the site
registration actions

=head2 register

User self registration page

=head2 register_create

Private method calls the data model to create a new user account

=head2 sitemap

Displays links to all the rooms on this site

=head2 tutorial

Guides you through the elements common to all rooms on this site

=head1 Diagnostics

Debug can be turned on/off from the tools menu

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Controller>

=back

=head1 Incompatibilities

None known

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
