# @(#)$Id: Admin.pm 1319 2013-06-23 16:21:01Z pjf $

package CatalystX::Usul::Controller::Admin;

use strict;
use version; our $VERSION = qv( sprintf '0.8.%d', q$Rev: 1319 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use File::Spec::Functions qw(catfile);

BEGIN { extends q(CatalystX::Usul::Controller) }

with q(CatalystX::Usul::TraitFor::Controller::ModelHelper);
with q(CatalystX::Usul::TraitFor::Controller::PersistentState);
with q(Class::Usul::TraitFor::LoadingClasses);

has 'default_action'   => is => 'ro', isa => NonEmptySimpleStr,
   default             => q(reception);

has 'security_logfile' => is => 'ro', isa => NonEmptySimpleStr,
   default             => q(admin.log);

sub begin : Private {
   return shift->next::method( @_ );
}

sub base : Chained(/) CaptureArgs(0) { # PathPart set in global configuration
   $_[ 0 ]->init_uri_attrs( $_[ 1 ], $_[ 0 ]->config_class ); return;
}

sub build_subcontrollers {
   return shift->build_subcomponents( __PACKAGE__ );
}

sub check_field : Chained(base) Args(0) NoToken {
   return shift->check_field_wrapper( @_ );
}

sub common : Chained(base) PathPart('') CaptureArgs(0) {
   my ($self, $c) = @_; my $nav = $c->stash->{nav_model};

   $nav->add_footer;
   $nav->add_nav_header;
   $nav->add_sidebar_panel( { name => q(default)  } );
   $nav->add_sidebar_panel( { name => q(overview) } );
   $nav->load_status_msgs;
   return;
}

sub footer : Chained(base) Args(0) NoToken {
   return $_[ 1 ]->model( $_[ 0 ]->help_class )->form( q(select_language) );
}

sub logfile_menu : Chained(common) PathPart(logfiles) CaptureArgs(0) {
   $_[ 1 ]->stash( fs_model => $_[ 1 ]->model( $_[ 0 ]->fs_class ) ); return;
}

sub overview : Chained(base) Args(0) NoToken {
   # Respond to the ajax call for some info about the side bar accordion
   return $_[ 1 ]->model( $_[ 0 ]->help_class )->overview;
}

sub reception : Chained(common) Args(0) {
}

sub redirect_to_default : Chained(base) PathPart('') Args(0) {
   my ($self, $c) = @_; my $action = SEP.$self->default_action;

   return $self->redirect_to_path( $c, $action, $c->req->query_params );
}

sub version {
   return $VERSION;
}

sub view_security_log : Chained(logfile_menu) PathPart(security_log) Args(0) {
   my ($self, $c) = @_;

   my $path = catfile( $self->usul->config->logsdir, $self->security_logfile );

   return $c->stash->{fs_model}->view_file( q(logfile), $path );
}

sub view_logfile : Chained(logfile_menu) PathPart('') Args(0) {
   my ($self, $c) = @_; my $path = $c->config->{logfile};

   ($path and -f $path) or $path = $self->usul->config->logfile;

   return $c->stash->{fs_model}->view_file( q(logfile), $path );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin - Administration controller methods

=head1 Version

0.8.$Revision: 1319 $

=head1 Synopsis

   package YourApp::Controller::Admin;

   use CatalystX::Usul::Moose;

   BEGIN { extends q(CatalystX::Usul::Controller::Admin) }

   __PACKAGE__->build_subcontrollers;

=head1 Description

Controller actions that inherit from L<CatalystX::Usul::Controller>

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item C<default_action>

A non empty simple string which defaults to C<reception>. The default
action for this controller

=item C<security_logfile>

A non empty simple string which defaults to C<admin.log>. The name of
the logfile for the suid administration program

=back

=head1 Subroutines/Methods

=head2 base

A midpoint in the URI that does nothing except act as a placeholder
for the namespace which is C<admin>

=head2 begin

Exposes the method of the same name in the parent class which is
responsible for stuffing the stash with all of the non endpoint
specific data

=head2 build_subcontrollers

Exposes method of the same name in the role
L<Class::Usul::TraitFor::LoadingClasses> which defines some
sub-controllers at runtime

=head2 check_field

Forward Ajax requests for this controller to the generic base class method

=head2 common

A midpoint in the URI. A number of other actions are chained off this
one. It sets up the navigation menu and form keys

=head2 footer

Adds some debug information to the footer div. Called via the async form
widget

=head2 logfile_menu

Midpoint off which the log file viewing endpoints are chained

=head2 overview

Endpoint for the Ajax call that populates one of the panels on the
accordion widget

Generates some blurb for the Overview panel of the sidebar accordion widget

=head2 reception

Displays the splash screen for this controller explaining it's purpose

=head2 redirect_to_default

Redirects to the splash screen for this level

=head2 sessions

Displays the current user sessions stored in the session store

=head2 version

Return the version number of this module

=head2 view_security_log

Endpoint that displays the log file used by the suid root wrapper script

=head2 view_logfile

Endpoint that displays the application server log file

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Controller>

=item L<CatalystX::Usul::TraitFor::Controller::ModelHelper>

=item L<CatalystX::Usul::TraitFor::Controller::PersistentState>

=item L<CatalystX::Usul::Moose>

=item L<Class::Usul::TraitFor::LoadingClasses>

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
