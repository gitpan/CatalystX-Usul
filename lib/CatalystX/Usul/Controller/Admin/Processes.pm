# @(#)$Id: Processes.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Controller::Admin::Processes;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Controller);

__PACKAGE__->config( namespace     => q(admin),
                     process_class => q(Process) );

__PACKAGE__->mk_accessors( qw(process_class) );

sub proc_table : Chained(common) Args HasActions {
   my ($self, $c, @args) = @_;

   $c->stash->{process_params} = $self->get_uri_query_params( $c );

   return $c->model( $self->process_class )->form( @args );
}

sub proc_table_signal : ActionFor(proc_table.abort)
                        ActionFor(proc_table.kill)
                        ActionFor(proc_table.terminate) {
   my ($self, $c) = @_;

   return $c->model( $self->process_class )->signal_process;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin::Processes - Process table manipulation

=head1 Version

0.6.$Revision: 1165 $

=head1 Synopsis

   package MyApp::Controller::Admin;

   use base qw(CatalystX::Usul::Controller::Admin);

   __PACKAGE__->build_subcontrollers;

=head1 Description

Displays the process table and send signals to selected processes

=head1 Subroutines/Methods

=head2 proc_table

Display the process table. Processes can be filtered by user, by a
pattern match, or by file system. Signals can be optionally propagated
to the processes children

=head2 proc_table_signal

Send the selected processes the specified signal, one of; SIGTERM,
SIGKILL, or SIGABORT

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
