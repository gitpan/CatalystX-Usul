# @(#)Ident: ;

package CatalystX::Usul::TraitFor::ListSessions;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.13.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Moose::Role;

sub list_sessions {
   return shift->_session_fastmmap_storage->get_keys( 2 );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TraitFor::ListSessions - List Catalyst sessions

=head1 Version

Describes v0.13.$Rev: 1 $

=head1 Synopsis

   package YourApp;

   use Moose;

   with qw(CatalystX::Usul::TraitFor::ListSessions);

=head1 Description

A L<role|Moose::Role> which lists
L<Catalyst::Plugin::Session::Store::FastMmap> sessions

=head1 Configuration and Environment

None

=head1 Subroutines/Methods

=head2 list_sessions

Lists the users session data stored in
L<Catalyst::Plugin::Session::Store::FastMmap>

This method should be implemented for each of the C::P::S::Store::* backends

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Catalyst::Plugin::Session::Store::FastMmap>

=item L<Moose::Role>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

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
