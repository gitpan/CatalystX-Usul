# @(#)Ident: ;

package CatalystX::Usul::View::XML;

use strict;
use version; our $VERSION = qv( sprintf '0.16.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use XML::Simple;

extends q(CatalystX::Usul::View);

has 'content_types'     => is => 'ro', isa => HashRef, default => sub { {
   'text/x-xml'         => { build_widgets => 0 },
   'text/xml'           => { build_widgets => 1 }, } };
has 'deserialize_attrs' => is => 'ro', isa => HashRef, default => sub { {
   ForceArray           => 0 } };

around 'prepare_data' => sub {
   my ($next, $self, $c) = @_; my $data = $self->$next( $c );

   my $js = join "\n", @{ $c->stash->{literal_js} || [] };

   $js and $data->{script} ||= [] and push @{ $data->{script} }, $js;

   return $data;
};

around 'read_form_sources' => sub {
   my ($next, $self, $c) = @_; my $data = $self->$next( $c );

   $self->content_types->{ $c->stash->{content_type} }->{build_widgets}
      and $self->_build_widgets( $c, { data => $data, skip_groups => 1 } );

   return $data;
};

sub deserialize {
   my ($self, @rest) = @_;

   my $process = sub { return XML::Simple->new( %{ $_[0] } )->xml_in( $_[1] ) };

   return $self->next::method( @rest, $process );
}

sub serialize {
   my ($self, $attrs, $data) = @_; $attrs ||= {}; delete $attrs->{content_type};

   return XML::Simple->new( %{ $attrs } )->xml_out( $data );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::View::XML - Render XML response to an XMLHttpRequest

=head1 Version

Describes v0.16.$Rev: 1 $

=head1 Synopsis

   MyApp->config( "View::XML"    => {
                  parent_classes => qw(CatalystX::Usul::View::XML) } );

=head1 Description

The XML view is used to generate fragments of XML in response to
Javascript XMLHttpRequests from a client that has selected this as the
required content type

=head1 Subroutines/Methods

=head2 deserialize

Deserializes the supplied data

=head2 serialize

Returns the supplied data encoded as XML

=head1 Configuration and Environment

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Catalyst::View>

=item L<CatalystX::Usul::Moose>

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
