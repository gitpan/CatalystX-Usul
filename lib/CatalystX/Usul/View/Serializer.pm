# @(#)$Id: Serializer.pm 1062 2011-10-23 01:23:45Z pjf $

package CatalystX::Usul::View::Serializer;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1062 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::View);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(throw);
use Data::Serializer;
use MRO::Compat;
use Safe;

my $LB = chr 123;

__PACKAGE__->config
   ( content_types => {
      'application/x-storable'   => { serializer => q(Storable)           },
      'application/x-freezethaw' => { serializer => q(FreezeThaw)         },
      'text/x-config-general'    => { serializer => q(Config::General)    },
      'text/x-data-dumper'       => { serializer => q(Data::Dumper)       },
      'text/x-php-serialization' => { serializer => q(PHP::Serialization) },
   } );

sub deserialize {
   my ($self, @rest) = @_; my ($s, $req) = @rest; my $process;

   $self->deserialize_attrs( $self->content_types->{ $s->{content_type} } );

   $process = sub {
      if ( $_[ 0 ]->{serializer} eq q(Data::Dumper) ) {
         my $code = $LB eq substr $_[ 1 ], 0, 1 ? q(+).$_[ 1 ] : $_[ 1 ];
         my $compartment = Safe->new;

         $compartment->permit_only( qw(anonhash anonlist const
                                       leaveeval lineseq list null
                                       padany pushmark refgen undef) );

         return $compartment->reval( $code );
      }

      return Data::Serializer->new( %{ $_[ 0 ] } )->deserialize( $_[ 1 ] );
   };

   return $self->next::method( @rest, $process );
}

sub serialize {
   my ($self, $attrs, $data) = @_; $attrs ||= {};

   my $type = $attrs->{content_type} || NUL;

   $attrs = $self->content_types->{ $type }
      or throw "Unsupported content type ${type}";

   return Data::Serializer->new( %{ $attrs } )->serialize( $data );
}

# Private methods

sub _unsupported_media_type {
   my ($self, $c, $body) = @_;

   $c->res->body( $body );
   $c->res->content_type( q(text/plain) );
   $c->res->status( 415 );
   return TRUE;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::View::Serializer - Serialize response to an XMLHttpRequest

=head1 Version

0.4.$Revision: 1062 $

=head1 Synopsis

   MyApp->config( "View::JSON"   => {
                     base_class => qw(CatalystX::Usul::View::JSON) } );

=head1 Description

The Serializer view is used to generate serialized data blocks in response to
Javascript XMLHttpRequests from a client that has selected this as the
required content type

=head1 Subroutines/Methods

=head2 deserialize

Deserializes the supplied data

=head2 serialize

Returns the supplied data serialized in the required format

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
