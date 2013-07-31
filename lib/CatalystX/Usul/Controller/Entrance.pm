# @(#)$Id: Entrance.pm 1319 2013-06-23 16:21:01Z pjf $

package CatalystX::Usul::Controller::Entrance;

use version; our $VERSION = qv( sprintf '0.8.%d', q$Rev: 1319 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Moose;

BEGIN { extends q(CatalystX::Usul::Controller) }

with q(CatalystX::Usul::TraitFor::Controller::ModelHelper);
with q(CatalystX::Usul::TraitFor::Controller::PersistentState);

has 'default_action'   => is => 'ro', isa => NonEmptySimpleStr,
   default             => q(reception);

has 'docs_uri'         => is => 'ro', isa => NonEmptySimpleStr,
   default             => q(/html/index.html);

has 'register_class'   => is => 'ro', isa => NonEmptySimpleStr,
   default             => q(UsersDBIC);

has 'register_profile' => is => 'ro', isa => NonEmptySimpleStr,
   default             => q(users);

sub begin : Private {
   return shift->next::method( @_ );
}

sub base : Chained(/) CaptureArgs(0) { # PathPart set in global configuration
   return $_[ 0 ]->init_uri_attrs( $_[ 1 ], $_[ 0 ]->config_class );
}

sub common : Chained(base) PathPart('') CaptureArgs(0) {
   my $nav = $_[ 1 ]->stash->{nav_model};

   $nav->add_footer; $nav->add_nav_header; $nav->add_navigation_sidebar;
   $nav->load_status_msgs;
   return;
}

sub activate_account : Chained(register_base) Args(1) Public {
   my ($self, $c, @args) = @_; my $s = $c->stash; my $nav = $s->{nav_model};

   $nav->clear_menus; $nav->add_menu_blank; $s->{register_model}->form( @args );
   return;
}

sub auth : Chained(common) PathPart(authentication) CaptureArgs(0) {
   $_[ 1 ]->stash( user_params => $_[ 0 ]->get_uri_query_params( $_[ 1 ] ) );
   $_[ 0 ]->stash_identity_model( $_[ 1 ] );
   return;
}

sub authentication : Chained(auth) PathPart('') Args HasActions Public {
   my ($self, $c, @args) = @_; return $c->stash->{user_model}->form( @args );
}

sub authentication_login : ActionFor(authentication.login) {
   my ($self, $c) = @_; my $s = $c->stash;

   $s->{user_model}->authenticate;
   $self->set_uri_query_params( $c, { realm => $s->{realm} } );
   $self->redirect_to_path( $c, $s->{wanted}, @{ $s->{redirect_params} } );
   return TRUE;
}

sub change_password : Chained(auth) Args HasActions {
   my ($self, $c, @args) = @_; return $c->stash->{user_model}->form( @args );
}

sub change_password_set : ActionFor(change_password.set) {
   my ($self, $c) = @_; my $s = $c->stash;

   $s->{user_model}->change_password;
   $self->redirect_to_path( $c, $s->{wanted}, @{ $s->{redirect_params} } );
   return TRUE;
}

sub check_field : Chained(base) Args(0) NoToken Public {
   return shift->check_field_wrapper( @_ );
}

sub doc_base : Chained(common) PathPart(documentation) CaptureArgs(0) {
   return $_[ 1 ]->stash( help_model => $_[ 1 ]->model( $_[ 0 ]->help_class ) );
}

sub documentation : Chained(doc_base) PathPart('') Args(0) {
   return $_[ 1 ]->stash->{help_model}->form( $_[ 0 ]->docs_uri );
}

sub footer : Chained(base) Args(0) NoToken Public {
   return $_[ 1 ]->model( $_[ 0 ]->help_class )->form( q(select_language) );
}

sub module_docs : Chained(doc_base) Args {
   my ($self, $c, @args) = @_;

   return $self->set_popup( $c, q(close) )->help_form( @args );
}

sub modules : Chained(doc_base) Args(0) {
   return $_[ 1 ]->stash->{help_model}->form;
}

sub navigation_sidebar : Chained(base) Args NoToken Public {
   return $_[ 1 ]->stash->{nav_model}->form;
}

sub reception_base : Chained(common) PathPart(reception) CaptureArgs(0) {
}

sub reception : Chained(reception_base) PathPart('') Args(0) Public {
}

sub redirect_to_default : Chained(base) PathPart('') Args(0) {
   my ($self, $c) = @_; my $action_path = SEP.$self->default_action;

   return $self->redirect_to_path( $c, $action_path, $c->req->query_params );
}

sub register_base : Chained(common) PathPart('') CaptureArgs(0) {
   my ($self, $c) = @_; my $s = $c->stash;

   $s->{register}->{profile} = $self->register_profile;
   $s->{register_model} = $c->model( $self->register_class );
   return;
}

sub register : Chained(register_base) Args(0) HasActions {
   return $_[ 1 ]->stash->{register_model}->form;
}

sub register_create : ActionFor(register.insert) {
   return $_[ 1 ]->stash->{register_model}->register;
}

sub sitemap : Chained(common) Args(0) {
   return $_[ 1 ]->stash->{nav_model}->form;
}

sub tutorial : Chained(reception_base) Args {
   my ($self, $c, $n_cols) = @_; my $model = $c->model( $self->help_class );

   return $model->stash_para_col_class( q(n_columns), $n_cols );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Entrance - Common controller methods

=head1 Version

0.8.$Revision: 1319 $

=head1 Synopsis

   package YourApp::Controller::Entrance;

   use CatalystX::Usul::Moose;

   BEGIN { extends q(CatalystX::Usul::Controller::Entrance) }

=head1 Description

Provides controller methods that are common to multiple applications. The
methods include welcome pages, authentication, sitemap, documentation, and
user registration

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item C<default_action>

A non empty simple string which defaults to C<reception>. The default
action for this controller

=item C<docs_uri>

A non empty simple string which defaults to C</html/index.html>. Relative path
to the applications documentation

=item C<register_class>

A non empty simple string which defaults to C<UsersDBIC>. Name of the model
class used to perform user registrations

=item C<register_profile>

A non empty simple string which defaults to C<users>. The name of the
user profile used when creating a registered user

=back

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

Intermediate subroutine maps to the reception path part. Both reception landing
page and the tutorial chain to this controller

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

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Controller>

=item L<CatalystX::Usul::TraitFor::Controller::ModelHelper>

=item L<CatalystX::Usul::TraitFor::Controller::PersistentState>

=item L<CatalystX::Usul::Moose>

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
