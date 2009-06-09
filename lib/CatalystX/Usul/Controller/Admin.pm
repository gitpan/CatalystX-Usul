# @(#)$Id: Admin.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::Controller::Admin;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Controller);

use Class::C3;

my $SEP = q(/);

__PACKAGE__->config( security_logfile => q(suid.log), );

__PACKAGE__->mk_accessors( qw(security_logfile) );

sub base : Chained(lang) CaptureArgs(0) {
   # PathPart set in global configuration
}

sub begin : Private {
   return shift->next::method( @_ );
}

sub build_subcontrollers {
   return shift->build_subcomponents( __PACKAGE__ );
}

sub check_field : Chained(base) Args(0) HasActions {
   return shift->next::method( @_ );
}

sub common : Chained(base) PathPart('') CaptureArgs(0) {
   my ($self, $c) = @_;

   $self->next::method( $c ); $self->load_keys( $c );
   $self->add_sidebar_panel( $c, { name => q(default)  } );
   $self->add_sidebar_panel( $c, { name => q(overview) } );
   return;
}

sub lang : Chained(/) PathPart('') CaptureArgs(1) {
   # Capture the language selection from the requested url
}

sub logfile_menu : Chained(common) CaptureArgs(0) {
}

sub overview : Chained(base) Args(0) {
   return shift->next::method( @_ );
}

sub reception : Chained(common) Args(0) {
   my ($self, $c) = @_;

   $c->model( q(Base) )->simple_page( q(reception) );
   return;
}

sub redirect_to_default : Chained(base) PathPart('') Args {
   my ($self, $c) = @_;

   return $self->redirect_to_path( $c, $SEP.q(reception) );
}

sub version {
   return $VERSION;
}

sub view_security_log : Chained(logfile_menu) Args(0) {
   my ($self, $c) = @_;
   my $path = $self->catfile( $c->config->{logsdir}, $self->security_logfile );

   $c->model( q(FileSystem) )->view_file( q(logfile), $path );
   return;
}

sub view_logfile : Chained(logfile_menu) PathPart('') Args(0) {
   my ($self, $c) = @_; my $path = $c->config->{logfile};

   $c->model( q(FileSystem) )->view_file( q(logfile), $path );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin - Administration controller methods

=head1 Version

$Revision: 562 $

=head1 Synopsis

   package MyApp::Controller::Admin;

   use base qw(CatalystX::Usul::Controller::Admin);

   __PACKAGE__->build_subcontrollers;

=head1 Description

Controller actions that inherit from L<CatalystX::Usul::Controller>

=head1 Subroutines/Methods

=head2 base

A midpoint in the URI that does nothing except act as a placeholder
for the namespace which is I<admin>

=head2 begin

Exposes the method of the same name in the parent class which is
responsible for stuffing the stash with all of the non endpoint
specific data

=head2 build_subcontrollers

Exposes method of the same name in the base class which defines some
subcontrollers at runtime

=head2 check_field

Forward Ajax requests for this controller to the generic base class method

=head2 common

A midpoint in the URI. A number of other actions are chained off this
one. It sets up the navigation menu and form keys

=head2 lang

Capture the required language. The actual work is done in the
L</begin> method

=head2 logfile_menu

Midpoint off which the log file viewing endpoints are chained

=head2 overview

Endpoint for the Ajax call that populates one of the panels on the
accordion widget

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
