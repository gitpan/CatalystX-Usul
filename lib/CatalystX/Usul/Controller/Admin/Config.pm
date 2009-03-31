package CatalystX::Usul::Controller::Admin::Config;

# @(#)$Id: Config.pm 406 2009-03-30 01:53:50Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Controller);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 406 $ =~ /\d+/gmx );

__PACKAGE__->config( namespace => q(admin) );

sub config_base : Chained(common) PathPart(configuration) CaptureArgs(0) {
   my ($self, $c) = @_; my $model = $c->model( q(Base) );

   $c->stash->{model_args} = { file => $self->get_key( $c, q(level) ),
                               name => $model->query_value( q(name)  ) };
   return;
}

sub buttons_delete : ActionFor(buttons_view.delete) {
   my ($self, $c) = @_;

   my $s     = $c->stash;
   my $args  = $s->{model_args};
   my $model = $c->model( q(Config::Buttons) );
   my $attr  = $model->keys_attr;

   $args->{name} = $self->get_key( $c, $attr );
   $model->delete( $args );
   $self->set_key( $c, $attr, $s->{newtag} );
   return 1;
}

sub buttons_save : ActionFor(buttons_view.save)
                   ActionFor(buttons_view.insert) {
   my ($self, $c) = @_;

   my $model = $c->model( q(Config::Buttons) );
   my $name  = $model->create_or_update( $c->stash->{model_args} );

   $self->set_key( $c, $model->keys_attr, $name );
   return 1;
}

sub buttons_view : Chained(config_base) PathPart(buttons) Args HasActions {
   my ($self, $c, $namespace, $name) = @_;

   my $model  = $c->model( q(Config::Buttons) );

   $namespace = $self->set_key( $c, q(level), $namespace );
   $name      = $self->set_key( $c, $model->keys_attr, $name );
   $model->config_form( $namespace, $name );
   return;
}

sub credentials : Chained(config_base) Args HasActions {
   my ($self, $c, $namespace, $name) = @_;

   my $model  = $c->model( q(Config::Credentials) );

   $namespace = $self->set_key( $c, q(level), $namespace );
   $name      = $self->set_key( $c, $model->keys_attr, $name );
   $model->form( $namespace, $name );
   return;
}

sub credentials_delete : ActionFor(credentials.delete) {
   my ($self, $c) = @_;

   my $s     = $c->stash;
   my $args  = $s->{model_args};
   my $model = $c->model( q(Config::Credentials) );
   my $attr  = $model->keys_attr;

   $args->{name} = $self->get_key( $c, $attr );
   $model->delete( $args );
   $self->set_key( $c, $attr, $s->{newtag} );
   return 1;
}

sub credentials_save : ActionFor(credentials.save)
                       ActionFor(credentials.insert) {
   my ($self, $c) = @_;

   my $model = $c->model( q(Config::Credentials) );
   my $name  = $model->create_or_update( $c->stash->{model_args} );

   $self->set_key( $c, $model->keys_attr, $name );
   return 1;
}

sub fields_delete : ActionFor(fields_view.delete) {
   my ($self, $c) = @_;

   my $s     = $c->stash;
   my $args  = $s->{model_args};
   my $model = $c->model( q(Config::Fields) );
   my $attr  = $model->keys_attr;

   $args->{name} = $self->get_key( $c, $attr );
   $model->delete( $args );
   $self->set_key( $c, $attr, $s->{newtag} );
   return 1;
}

sub fields_save : ActionFor(fields_view.save) ActionFor(fields_view.insert) {
   my ($self, $c) = @_;

   my $model = $c->model( q(Config::Fields) );
   my $name  = $model->create_or_update( $c->stash->{model_args} );

   $self->set_key( $c, $model->keys_attr, $name );
   return 1;
}

sub fields_view : Chained(config_base) PathPart(fields) Args HasActions {
   my ($self, $c, $namespace, $name) = @_;

   my $model  = $c->model( q(Config::Fields) );

   $namespace = $self->set_key( $c, q(level), $namespace );
   $name      = $self->set_key( $c, $model->keys_attr, $name );
   $model->config_form( $namespace, $name );
   return;
}

sub globals : Chained(config_base) PathPart('') Args(0) HasActions {
   my ($self, $c) = @_; $c->model( q(Config::Globals) )->form; return;
}

sub globals_save : ActionFor(globals.save) {
   my ($self, $c) = @_; $c->model( q(Config::Globals) )->save; return 1;
}

sub keys_delete : ActionFor(keys_view.delete) {
   my ($self, $c) = @_;

   my $s     = $c->stash;
   my $args  = $s->{model_args};
   my $model = $c->model( q(Config::Keys) );
   my $attr  = $model->keys_attr;

   $args->{name} = $self->get_key( $c, $attr );
   $model->delete( $args );
   $self->set_key( $c, $attr, $s->{newtag} );
   return 1;
}

sub keys_save : ActionFor(keys_view.save) ActionFor(keys_view.insert) {
   my ($self, $c) = @_;

   my $model = $c->model( q(Config::Keys) );
   my $name  = $model->create_or_update( $c->stash->{model_args} );

   $self->set_key( $c, $model->keys_attr, $name );
   return 1;
}

sub keys_view : Chained(config_base) PathPart(keys) Args HasActions {
   my ($self, $c, $namespace, $name) = @_;

   my $model  = $c->model( q(Config::Keys) );

   $namespace = $self->set_key( $c, q(level), $namespace );
   $name      = $self->set_key( $c, $model->keys_attr, $name );
   $model->config_form( $namespace, $name );
   return;
}

sub messages_delete : ActionFor(messages_view.delete) {
   my ($self, $c) = @_;

   my $s     = $c->stash;
   my $args  = $s->{model_args};
   my $model = $c->model( q(Config::Messages) );
   my $attr  = $model->keys_attr;

   $args->{name} = $self->get_key( $c, $attr );
   $model->delete( $args );
   $self->set_key( $c, $attr, $s->{newtag} );
   return 1;
}

sub messages_save : ActionFor(messages_view.save)
                    ActionFor(messages_view.insert) {
   my ($self, $c) = @_;

   my $model = $c->model( q(Config::Messages) );
   my $name  = $model->create_or_update( $c->stash->{model_args} );

   $self->set_key( $c, $model->keys_attr, $name );
   return 1;
}

sub messages_view : Chained(config_base) PathPart(messages) Args HasActions {
   my ($self, $c, $namespace, $name) = @_;

   my $model  = $c->model( q(Config::Messages) );

   $namespace = $self->set_key( $c, q(level), $namespace );
   $name      = $self->set_key( $c, $model->keys_attr, $name );
   $model->config_form( $namespace, $name );
   return;
}

sub pages_delete : ActionFor(pages_view.delete) {
   my ($self, $c) = @_;

   my $s     = $c->stash;
   my $args  = $s->{model_args};
   my $model = $c->model( q(Config::Pages) );
   my $attr  = $model->keys_attr;

   $args->{name} = $self->get_key( $c, $attr );
   $model->delete( $args );
   $self->set_key( $c, $attr, $s->{newtag} );
   return 1;
}

sub pages_save : ActionFor(pages_view.save) ActionFor(pages_view.insert) {
   my ($self, $c) = @_;

   my $model = $c->model( q(Config::Pages) );
   my $name  = $model->create_or_update( $c->stash->{model_args} );

   $self->set_key( $c, $model->keys_attr, $name );
   return 1;
}

sub pages_view : Chained(config_base) PathPart(pages) Args HasActions {
   my ($self, $c, $namespace, $name) = @_;

   my $model  = $c->model( q(Config::Pages) );

   $namespace = $self->set_key( $c, q(level), $namespace );
   $name      = $self->set_key( $c, $model->keys_attr, $name );
   $model->config_form( $namespace, $name );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin::Config - Editor for config files

=head1 Version

0.1.$Revision: 406 $

=head1 Synopsis

   package MyApp::Controller::Admin;

   use base qw(CatalystX::Usul::Controller::Admin);

   __PACKAGE__->build_subcontrollers;

=head1 Description

CRUD methods for the configuration files

=head1 Subroutines/Methods

=head2 config_base

Stash some parameters used by all the other actions which chain off this one

=head2 buttons_delete

Called in response to the I<Delete> button on the L</buttons_view>
page being pressed, this method deletes the currently selected button
definition

=head2 buttons_save

Called in response to the I<Insert> or I<Save> buttons on the
L</buttons_view> page being pressed, this method either updates the
currently selected button definition or inserts a new one

=head2 buttons_view

Displays the button defintion form. Button defintions define the help,
prompt and error text associated with a form submission image button

=head2 credentials

Displays the credential defintion form. Credentials contain the data used
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

Displays the fields defintion form. Field defintions define the
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

Displays the keys defintion form. Keys defintions define the
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
and are used to L<localize|CatalystX::Usul/localize> output

=head2 pages_delete

Called in response to the I<Delete> button on the L</pages_view>
page being pressed, this method deletes the currently selected page
definition

=head2 pages_save

Called in response to the I<Insert> or I<Save> buttons on the
L</pages_view> page being pressed, this method either updates the
currently selected page definition or inserts a new one

=head2 pages_view

Displays the page definition form. Page definitions define the contents
of a L<simple page|CatalystX::Usul::Plugin::Model::StashHelper/simple_page>

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Controller>

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
