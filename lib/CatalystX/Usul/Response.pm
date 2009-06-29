# @(#)$Id: Response.pm 576 2009-06-09 23:23:46Z pjf $

package CatalystX::Usul::Response;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 576 $ =~ /\d+/gmx );
use parent qw(Class::Accessor::Fast);

__PACKAGE__->mk_accessors( qw(core out sig stderr stdout) );

sub new {
   my $self = shift;

   return bless { core   => 0,   out    => q(), sig => undef,
                  stderr => q(), stdout => q() }, ref $self || $self;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Response - Response class for running external programs

=head1 Version

0.3.$Revision: 576 $

=head1 Synopsis

   use CatalystX::Usul::Response;

   my $result = CatalystX::Usul::Response->new();

=head1 Description

Response class returned by L<CatalystX::Usul::Utils/run_cmd> and
L<CatalystX::Usul::Utils/popen>

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

=item L<Class::Accessor::Fast>

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
