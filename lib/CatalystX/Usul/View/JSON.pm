# @(#)$Id: JSON.pm 1012 2011-06-22 16:10:58Z pjf $

package CatalystX::Usul::View::JSON;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1012 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::View);

use MRO::Compat;
use JSON;

sub deserialize {
   my ($self, @rest) = @_;

   my $process = sub { return JSON->new->decode( $_[ 1 ] ) };

   return $self->next::method( @rest, $process );
}

sub serialize {
   my ($self, $attrs, $data) = @_;

   return JSON->new->allow_blessed->convert_blessed->encode( $data );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::View::JSON - Render JSON response to an XMLHttpRequest

=head1 Version

0.4.$Revision: 1012 $

=head1 Synopsis

   MyApp->config( "View::JSON"   => {
                     base_class => qw(CatalystX::Usul::View::JSON) } );

=head1 Description

The JSON view is used to generate JSON data blocks in response to
Javascript XMLHttpRequests from a client that has selected this as the
required content type

=head1 Subroutines/Methods

=head2 deserialize

Decodes the supplied data. Calls C<decode_json> to get the work done

=head2 serialize

Returns the supplied data encoded as JSON.  Calls C<decode_json> to
get the work done

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Catalyst::View>

=item L<JSON>

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
