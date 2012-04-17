# @(#)$Id: Entrance.pm 1181 2012-04-17 19:06:07Z pjf $

package CatalystX::Usul::Controller::Entrance;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.7.%d', q$Rev: 1181 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Controller);

use CatalystX::Usul::Constants;
use MRO::Compat;

__PACKAGE__->config( docs_uri         => q(/html/index.html),
                     register_class   => q(IdentityDBIC),
                     register_profile => q(users), );

__PACKAGE__->mk_accessors( qw(docs_uri register_class register_profile) );

sub begin : Private {
   return shift->next::method( @_ );
}

sub base : Chained(/) CaptureArgs(0) {
   # PathPart set in global configuration
   my ($self, $c) = @_;

   $self->can( q(persist_state) )
      and $self->init_uri_attrs( $c, $self->model_base_class );

   return;
}

sub common : Chained(base) PathPart('') CaptureArgs(0) {
   my ($self, $c) = @_; my $s = $c->stash; my $nav = $s->{nav_model};

   $nav->add_header; $nav->add_footer; $nav->add_sidebar_panel;

   return;
}

sub activate_account : Chained(register_base) Args(1) Public {
   my ($self, $c, $key) = @_; my $s = $c->stash;

   my $nav = $s->{nav_model}; $nav->clear_menus; $nav->add_menu_blank;

   $s->{register_model}->activate_account( $key );
   return;
}

sub auth : Chained(common) PathPart(authentication) CaptureArgs(0) {
   my ($self, $c) = @_;

   $self->can( q(persist_state) )
      and $c->stash->{user_params} = $self->get_uri_query_params( $c );

   return $self->set_identity_model( $c );
}

sub authentication : Chained(auth) PathPart('') Args HasActions Public {
   my ($self, $c, @args) = @_; return $c->stash->{user_model}->form( @args );
}

sub authentication_login : ActionFor(authentication.login) {
   my ($self, $c) = @_; my $s = $c->stash; $s->{user_model}->authenticate;

   $self->can( q(persist_state) )
      and $self->set_uri_query_params( $c, { realm => $s->{realm} } );

   $self->redirect_to_path( $c, $s->{wanted} );
   return TRUE;
}

sub change_password : Chained(auth) Args HasActions {
   my ($self, $c, @args) = @_; return $c->stash->{user_model}->form( @args );
}

sub change_password_set : ActionFor(change_password.set) {
   my ($self, $c) = @_; return $c->stash->{user_model}->change_password;
}

sub check_field : Chained(base) Args(0) HasActions NoToken Public {
   return shift->next::method( @_ );
}

sub doc_base : Chained(common) PathPart(documentation) CaptureArgs(0) {
   my ($self, $c) = @_;

   $c->stash( help_model => $c->model( $self->help_class ) );
   return;
}

sub documentation : Chained(doc_base) PathPart('') Args(0) {
   my ($self, $c) = @_;

   return $c->stash->{help_model}->documentation( $self->docs_uri );
}

sub footer : Chained(base) Args(0) NoToken Public {
   my ($self, $c) = @_; return $c->model( $self->help_class )->add_footer;
}

sub module_docs : Chained(doc_base) Args {
   my ($self, $c, @args) = @_;

   return $c->stash->{help_model}->module_docs( @args );
}

sub modules : Chained(doc_base) Args(0) {
   my ($self, $c) = @_; return $c->stash->{help_model}->module_list;
}

sub navigation_sidebar : Chained(base) Args NoToken Public {
   my ($self, $c) = @_; return $c->stash->{nav_model}->add_tree_panel;
}

sub reception_base : Chained(common) PathPart(reception) CaptureArgs(0) {
}

sub reception : Chained(reception_base) PathPart('') Args(0) Public {
}

sub redirect_to_default : Chained(base) PathPart('') Args(0) {
   my ($self, $c) = @_; return $self->redirect_to_path( $c, SEP.q(reception) );
}

sub register_base : Chained(common) PathPart('') CaptureArgs(0) {
   my ($self, $c) = @_; my $s = $c->stash;

   $s->{register}->{profile} = $self->register_profile;
   $s->{register_model} = $c->model( $self->register_class )->users;
   return;
}

sub register : Chained(register_base) Args(0) HasActions {
   my ($self, $c) = @_;

   return $c->stash->{register_model}->form( SEP.q(captcha) );
}

sub register_create : ActionFor(register.insert) {
   my ($self, $c) = @_; return $c->stash->{register_model}->register;
}

sub sitemap : Chained(common) Args(0) {
   my ($self, $c) = @_; return $c->stash->{nav_model}->sitemap;
}

sub tutorial : Chained(reception_base) Args {
   my ($self, $c, $n_cols) = @_; my $model = $c->model( $self->help_class );

   return $model->stash_para_col_class( q(n_columns), $n_cols );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Entrance - Common controller methods

=head1 Version

$Revision: 1181 $

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

Calls L<CatalystX::Usul::Controller/authenticate>

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

   bin/munchies_cli -n -c pod2html

=head2 footer

Adds some debug information to the footer div. Called via the async form
widget

=head2 module_docs

Displays the POD for the selected module

=head2 modules

Displays a table of modules used by the application and their version
numbers. It has clickable fields that display POD for the module and
it's source code

=head2 navigation_sidebar

Action for the Ajax call that puts a navigation tree in a sidebar panel

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
