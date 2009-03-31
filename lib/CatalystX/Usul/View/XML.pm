package CatalystX::Usul::View::XML;

# @(#)$Id: XML.pm 334 2008-12-20 02:50:09Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::View);
use Class::C3;
use XML::Simple;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 334 $ =~ /\d+/gmx );

__PACKAGE__->config( deserialize_attrs => { ForceArray => 0 } );

sub deserialize {
   my ($self, @rest) = @_; my $process;

   $process = sub { return XML::Simple->new( %{ $_[0] } )->xml_in( $_[1] ); };

   return $self->next::method( @rest, $process );
}

sub serialize {
   my ($self, $attrs, $data) = @_;

   return XML::Simple->new( %{ $attrs } )->xml_out( $data );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::View::XML - Render XML response to an XMLHttpRequest

=head1 Version

0.1.$Revision: 334 $

=head1 Synopsis

   MyApp->config( "View::XML"   => {
                     base_class => qw(CatalystX::Usul::View::XML) } );

=head1 Description

The XML view is used to generate fragments of XML in response to
Javascript XMLHttpRequests from a client that has selected this as the
required content type

=head1 Subroutines/Methods

=head2 deserialize

Deserializes the supplied data

=head2 serialize

Returns the supplied data encoded as XML

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Catalyst::View>

=item L<XML::Simple>

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
