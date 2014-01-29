# @(#)Ident: ;

package CatalystX::Usul::Controller::Admin::Backup;

use strict;
use version; our $VERSION = qv( sprintf '0.17.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use File::Spec::Functions qw(catfile);

BEGIN { extends q(CatalystX::Usul::Controller) }

with q(CatalystX::Usul::TraitFor::Controller::PersistentState);

__PACKAGE__->config( namespace => q(admin) );

has 'device_class' => is => 'ro', isa => Str, default => q(TapeBackup);

has 'logfile'      => is => 'ro', isa => Str, default => q(cli.log);

sub backup_base : Chained(common) PathPart(backup) CaptureArgs(0) {
   my ($self, $c) = @_; my $s = $c->stash;

   $s->{device_model } = $c->model( $self->device_class );
   $s->{device_params} = $self->get_uri_query_params( $c );
   return;
}

sub backup : Chained(backup_base) PathPart('') Args HasActions {
   my ($self, $c, $paths) = @_;

   return $c->stash->{device_model}->form( $paths );
}

sub backup_eject : ActionFor(backup.eject) {
   my ($self, $c) = @_; return $c->stash->{device_model}->eject;
}

sub backup_logfile : Chained(backup_base) PathPart(logfile) Args(0) {
   my ($self, $c) = @_;

   my $path = catfile( $self->usul->config->logsdir, $self->logfile );

   return $c->model( $self->fs_class )->view_file( q(logfile), $path );
}

sub backup_start : ActionFor(backup.start) {
   my ($self, $c, $paths) = @_;

   return $c->stash->{device_model}->start( $paths );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin::Backup - Tape device backups

=head1 Version

Describes v0.17.$Rev: 1 $

=head1 Synopsis

   package YourApp::Controller::Admin;

   use CatalystX::Usul::Moose;

   BEGIN { extends q(CatalystX::Usul::Controller::Admin) }

   __PACKAGE__->build_subcontrollers;

=head1 Description

Perform dumps and tars to selected tape device

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item C<device_class>

A string which defaults to C<TapeBackup>. The name of the interface
model class

=item C<logfile>

A string which defaults to F<cli.log>. The name of the command line interface
log file

=back

=head1 Subroutines/Methods

=head2 backup_base

Set OS specific options on the tape device model

=head2 backup

Display the tape backup selection form

=head2 backup_eject

Eject the tape from the selected drive

=head2 backup_logfile

View the backup logfile

=head2 backup_start

Start a backup on the selected drive

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
