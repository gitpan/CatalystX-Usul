# @(#)Ident: ;

package CatalystX::Usul::Controller::Admin::Config;

use strict;
use version; our $VERSION = qv( sprintf '0.15.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;

BEGIN { extends q(CatalystX::Usul::Controller) }

with q(CatalystX::Usul::TraitFor::Controller::PersistentState);

__PACKAGE__->config( namespace => q(admin), );

has 'button_class'     => is => 'ro', isa => NonEmptySimpleStr,
   default             => q(Config::Buttons);

has 'credential_class' => is => 'ro', isa => NonEmptySimpleStr,
   default             => q(Config::Credentials);

has 'field_class'      => is => 'ro', isa => NonEmptySimpleStr,
   default             => q(Config::Fields);

has 'key_class'        => is => 'ro', isa => NonEmptySimpleStr,
   default             => q(Config::Keys);

has 'message_class'    => is => 'ro', isa => NonEmptySimpleStr,
   default             => q(Config::Messages);

has 'template_class'   => is => 'ro', isa => NonEmptySimpleStr,
   default             => q(Templates);

sub config_base : Chained(common) PathPart(configuration) CaptureArgs(0) {
}

sub configuration : Chained(config_base) PathPart('') Args(0) Public {
   my ($self, $c) = @_; return $self->redirect_to_path( $c, SEP.q(globals) );
}

sub buttons_delete : ActionFor(buttons_view.delete) {
   my ($self, $c, $ns) = @_; my $s = $c->stash;

   $c->model( $self->button_class )->delete( $ns );
   $self->set_uri_args( $c, $ns, $s->{newtag} );
   return TRUE;
}

sub buttons_save : ActionFor(buttons_view.save)
                   ActionFor(buttons_view.insert) {
   my ($self, $c, $ns) = @_; my $s = $c->stash;

   my $name = $c->model( $self->button_class )->create_or_update( $ns );

   $self->set_uri_args( $c, $ns, $name );
   return TRUE;
}

sub buttons_view : Chained(config_base) PathPart(buttons) Args HasActions {
   my ($self, $c, @args) = @_;

   return $c->model( $self->button_class )->config_form( @args );
}

sub credentials : Chained(config_base) Args HasActions {
   my ($self, $c, @args) = @_;

   return $c->model( $self->credential_class )->form( @args );
}

sub credentials_delete : ActionFor(credentials.delete) {
   my ($self, $c, $ns) = @_; my $s = $c->stash;

   $c->model( $self->credential_class )->delete( $ns );
   $self->set_uri_args( $c, $ns, $s->{newtag} );
   return TRUE;
}

sub credentials_save : ActionFor(credentials.save)
                       ActionFor(credentials.insert) {
   my ($self, $c, $ns) = @_; my $s = $c->stash;

   my $name = $c->model( $self->credential_class )->create_or_update( $ns );

   $self->set_uri_args( $c, $ns, $name );
   return TRUE;
}

sub fields_delete : ActionFor(fields_view.delete) {
   my ($self, $c, $ns) = @_; my $s = $c->stash;

   $c->model( $self->field_class )->delete( $ns );
   $self->set_uri_args( $c, $ns, $s->{newtag} );
   return TRUE;
}

sub fields_save : ActionFor(fields_view.save) ActionFor(fields_view.insert) {
   my ($self, $c, $ns) = @_; my $s = $c->stash;

   my $name = $c->model( $self->field_class )->create_or_update( $ns );

   $self->set_uri_args( $c, $ns, $name );
   return TRUE;
}

sub fields_view : Chained(config_base) PathPart(fields) Args HasActions {
   my ($self, $c, @args) = @_;

   return $c->model( $self->field_class )->config_form( @args );
}

sub globals : Chained(config_base) PathPart(globals) Args(0) HasActions {
   my ($self, $c) = @_; return $c->model( $self->global_class )->form;
}

sub globals_save : ActionFor(globals.save) {
   my ($self, $c) = @_; return $c->model( $self->global_class )->save;
}

sub keys_delete : ActionFor(keys_view.delete) {
   my ($self, $c, $ns) = @_; my $s = $c->stash;

   $c->model( $self->key_class )->delete( $ns );
   $self->set_uri_args( $c, $ns, $s->{newtag} );
   return TRUE;
}

sub keys_save : ActionFor(keys_view.save) ActionFor(keys_view.insert) {
   my ($self, $c, $ns) = @_; my $s = $c->stash;

   my $name = $c->model( $self->key_class )->create_or_update( $ns );

   $self->set_uri_args( $c, $ns, $name );
   return TRUE;
}

sub keys_view : Chained(config_base) PathPart(keys) Args HasActions {
   my ($self, $c, @args) = @_;

   return $c->model( $self->key_class )->config_form( @args );
}

sub messages_delete : ActionFor(messages_view.delete) {
   my ($self, $c, $ns) = @_; my $s = $c->stash;

   $c->model( $self->message_class )->delete( $ns );
   $self->set_uri_args( $c, $ns, $s->{newtag} );
   return TRUE;
}

sub messages_save : ActionFor(messages_view.save)
                    ActionFor(messages_view.insert) {
   my ($self, $c, $ns) = @_; my $s = $c->stash;

   my $name = $c->model( $self->message_class )->create_or_update( $ns );

   $self->set_uri_args( $c, $ns, $name );
   return TRUE;
}

sub messages_view : Chained(config_base) PathPart(messages) Args HasActions {
   my ($self, $c, @args) = @_;

   return $c->model( $self->message_class )->config_form( @args );
}

sub templates_delete : ActionFor(templates_view.delete) {
   my ($self, $c, $ns) = @_; my $s = $c->stash;

   $c->model( $self->template_class )->delete( $ns );
   $self->set_uri_args( $c, $ns, $s->{newtag} );
   return TRUE;
}

sub templates_save : ActionFor(templates_view.save)
                     ActionFor(templates_view.insert) {
   my ($self, $c, $ns) = @_; my $s = $c->stash;

   my $name = $c->model( $self->template_class )->create_or_update( $ns );

   $self->set_uri_args( $c, $ns, $name );
   return TRUE;
}

sub templates_view : Chained(config_base) PathPart(templates) Args HasActions {
   my ($self, $c, @args) = @_;

   return $c->model( $self->template_class )->form( @args );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin::Config - Editor for config files

=head1 Version

Describes v0.15.$Rev: 1 $

=head1 Synopsis

   package YourApp::Controller::Admin;

   use CatalystX::Usul::Moose;

   BEGIN { extends q(CatalystX::Usul::Controller::Admin) }

   __PACKAGE__->build_subcontrollers;

=head1 Description

CRUD methods for the configuration files

=head1 Configuration and Environment

Defines the following list of attributes

=over 3

=item C<button_class>

A non empty simple string which defaults to C<Config::Buttons>. The model
class for button widgets

=item C<credential_class>

A non empty simple string which defaults to C<Config::Credentials>. The
model class for database login credentials

=item C<field_class>

A non empty simple string which defaults to C<Config::Fields>. The model
class for input field widgets

=item C<key_class>

A non empty simple string which defaults to C<Config::Keys>. The model
class for form keys

=item C<message_class>

A non empty simple string which defaults to C<Config::Messages>. The model
class for GNU Gettext messages

=item C<template_class>

A non empty simple string which defaults to C<Templates>. The model
class for L<Toolkit::Template> templates

=back

=head1 Subroutines/Methods

=head2 config_base

Stash some parameters used by all the other actions which chain off this one

=head2 configuration

Redirects to default configuration page

=head2 buttons_delete

Called in response to the I<Delete> button on the L</buttons_view>
page being pressed, this method deletes the currently selected button
definition

=head2 buttons_save

Called in response to the I<Insert> or I<Save> buttons on the
L</buttons_view> page being pressed, this method either updates the
currently selected button definition or inserts a new one

=head2 buttons_view

Displays the button definition form. Button definitions define the help,
prompt and error text associated with a form submission image button

=head2 credentials

Displays the credential definition form. Credentials contain the data used
to connect to a database

=head2 credentials_delete

Called in response to the I<Delete> button on the L</credentials>
page being pressed, this method deletes the currently selected credential
definition

=head2 credentials_save

Called in response to the I<Insert> or I<Save> buttons on the
L</credential> page being pressed, this method either updates the
currently selected credentials or inserts a new one

=head2 fields_delete

Called in response to the I<Delete> button on the L</fields_view>
page being pressed, this method deletes the currently selected fields
definition

=head2 fields_save

Called in response to the I<Insert> or I<Save> buttons on the
L</fields_view> page being pressed, this method either updates the
currently selected fields definition or inserts a new one

=head2 fields_view

Displays the fields definition form. Field definitions define the
attributes passed to the L<HTML::FormWidgets> class that is used by
the view to create user interface widgets

=head2 globals

Displays the globals attributes form. Global attributes are loaded
into the "top level" of the stash

=head2 globals_save

Called in response to the I<Save> buttons on the L</globals> page
being pressed

=head2 keys_delete

Called in response to the I<Delete> button on the L</keys_view>
page being pressed, this method deletes the currently selected keys
definition

=head2 keys_save

Called in response to the I<Insert> or I<Save> buttons on the
L</keys_view> page being pressed, this method either updates the
currently selected keys definition or inserts a new one

=head2 keys_view

Displays the keys definition form. Keys definitions define the
attributes that L<CatalystX::Usul::PersistentState> uses

=head2 messages_delete

Called in response to the I<Delete> button on the L</messages_view>
page being pressed, this method deletes the currently selected message
definition

=head2 messages_save

Called in response to the I<Insert> or I<Save> buttons on the
L</messages_view> page being pressed, this method either updates the
currently selected message definition or inserts a new one

=head2 messages_view

Displays the message definition form. Messages are language dependent
and are used to L<localize|CatalystX::Usul::Controller/loc> output

=head2 templates_delete

Called in response to the I<Delete> button on the L</templates_view>
page being pressed, this method deletes the currently selected template
file

=head2 templates_save

Called in response to the I<Insert> or I<Save> buttons on the
L</templates_view> page being pressed, this method either updates the
currently selected template or creates a new one

=head2 templates_view

Displays the template form. Templates define the contents
of a page

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Controller>

=item L<CatalystX::Usul::TraitFor::Controller::PersistentState>

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

Copyright (c) 2014 Peter Flanigan. All rights reserved

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
