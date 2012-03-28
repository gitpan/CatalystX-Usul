# @(#)$Id: XML.pm 1093 2011-12-30 00:24:43Z pjf $

package CatalystX::Usul::View::XML;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1093 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::View);

use XML::Simple;
use MRO::Compat;

__PACKAGE__->config
   ( content_types     => {
      'text/x-xml'     => { build_widgets => 0 },
      'text/xml'       => { build_widgets => 1 }, },
     deserialize_attrs => { ForceArray    => 0 }, );


sub deserialize {
   my ($self, @rest) = @_;

   my $process = sub { return XML::Simple->new( %{ $_[0] } )->xml_in( $_[1] ) };

   return $self->next::method( @rest, $process );
}

sub serialize {
   my ($self, $attrs, $data) = @_; $attrs ||= {}; delete $attrs->{content_type};

   return XML::Simple->new( %{ $attrs } )->xml_out( $data );
}

# Private Methods

sub _read_form_sources {
   my ($self, $c) = @_; my $data = $self->next::method( $c );

   $self->content_types->{ $c->stash->{content_type} }->{build_widgets}
      and $self->_build_widgets( $c, { data => $data, skip_groups => 1 } );

   return $data;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::View::XML - Render XML response to an XMLHttpRequest

=head1 Version

0.4.$Revision: 1093 $

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
