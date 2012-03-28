# @(#)$Id: Response.pm 730 2009-10-28 02:13:42Z pjf $

package CatalystX::Usul::IPC::Response;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 730 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Base);

__PACKAGE__->mk_accessors( qw(core out pid rv sig stderr stdout) );

sub new {
   my $self = shift;

   return bless { core   => 0,   out    => q(),   pid    => undef,
                  rv     => 0,   sig    => undef, stderr => q(),
                  stdout => q() }, ref $self || $self;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::IPC::Response - Response class for running external programs

=head1 Version

0.4.$Revision: 730 $

=head1 Synopsis

   use CatalystX::Usul::IPC::Response;

   my $result = CatalystX::Usul::IPC::Response->new();

=head1 Description

Response class returned by L<CatalystX::Usul::IPC/run_cmd> and
L<CatalystX::Usul::IPC/popen>

=head1 Configuration and Environment

This class defined these attributes:

=over 3

=item core

True if external commands core dumped

=item out

Processed output from the command

=item sig

Signal that caused the program to terminate

=item stderr

The standard error output from the command

=item stdout

The standard output from the command

=back

=head1 Subroutines/Methods

=head2 new

Basic constructor

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Base>

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

Copyright (c) 2009 Peter Flanigan. All rights reserved

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
