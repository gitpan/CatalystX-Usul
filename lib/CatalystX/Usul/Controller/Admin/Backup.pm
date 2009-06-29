# @(#)$Id: Backup.pm 584 2009-06-12 15:25:11Z pjf $

package CatalystX::Usul::Controller::Admin::Backup;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 584 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Controller);

__PACKAGE__->config( device_class => q(Tapes),
                     fs_class     => q(FileSystem),
                     logfile      => q(cli.log),
                     namespace    => q(admin) );

__PACKAGE__->mk_accessors( qw(device_class fs_class logfile) );

sub backup_base : Chained(common) CaptureArgs(0) {
   my ($self, $c) = @_;
   my $s          = $c->stash;
   my $model      = $s->{device_model} = $c->model( $self->device_class );
   my $ref        = $s->{os} || {};

   for (grep { $model->can( $_ ) } keys %{ $ref }) {
      $model->$_( $ref->{ $_ }->{value} );
   }

   return;
}

sub backup : Chained(backup_base) PathPart('') Args HasActions {
   my ($self, $c, $device, $format, $paths) = @_;

   $device = $self->set_key( $c, q(device), $device );
   $format = $self->set_key( $c, q(format), $format );
   $paths  = $self->set_key( $c, q(paths),  $paths  );
   $c->stash->{device_model}->form( $device, $format, $paths );
   return;
}

sub backup_eject : ActionFor(backup.eject) {
   my ($self, $c) = @_; $c->stash->{device_model}->eject; return 1;
}

sub backup_logfile : Chained(backup_base) PathPart(logfile) Args(0) {
   my ($self, $c) = @_;

   my $path = $self->catfile( $c->config->{logsdir}, $self->logfile );

   $c->model( $self->fs_class )->view_file( q(logfile), $path );
   return;
}

sub backup_start : ActionFor(backup.start) {
   my ($self, $c) = @_; $c->stash->{device_model}->start; return 1;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin::Backup - Tape device backups

=head1 Version

0.3.$Revision: 584 $

=head1 Synopsis

   package MyApp::Controller::Admin;

   use base qw(CatalystX::Usul::Controller::Admin);

   __PACKAGE__->build_subcontrollers;

=head1 Description

Perform dumps and tars to selected tape device

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
