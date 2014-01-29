# @(#)Ident: QueryRequest.pm 2013-08-19 19:21 pjf ;

package CatalystX::Usul::QueryRequest;

use strict;
use version; our $VERSION = qv( sprintf '0.17.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(dos2unix is_arrayref is_coderef is_hashref
                                  unescape_TT);
use Encode;
use Encode::Guess;

has 'encoding'  => is => 'ro', isa => CharEncoding, required => TRUE;

has 'encodings' => is => 'ro', isa => ArrayRef[CharEncoding],
   default      => sub { [ ENCODINGS ] };

has 'model'     => is => 'ro', isa => Object, required => TRUE,
   weak_ref     => TRUE;

has 'scrubber'  => is => 'ro', isa => NonEmptyStr | CodeRef,
   default      => q([\'\"/\:]);

sub BUILD {
   my $self = shift; my $meta = __PACKAGE__->meta; $meta->make_mutable;

   for my $enc (grep { not m{ guess }mx } @{ $self->encodings }) {
      my $method = __method_name( $enc );

      $meta->has_method( $method ) or $meta->add_method( $method => sub {
         my ($self, $req_method, @rest) = @_;

         return $self->_decode_data( $enc, $self->$req_method( @rest ) );
      } );
   }

   for my $req_method (qw(_get_req_array _get_req_value)) {
      for my $enc_method (map { __method_name( $_ ) } @{ $self->encodings }) {
         my $method = $req_method.$enc_method;

         $meta->has_method( $method ) or $meta->add_method( $method => sub {
            return shift->$enc_method( $req_method, @_ );
         } );
      }
   }

   $meta->make_immutable;
   return;
}

sub query_array {
   my ($self, $attr) = @_;

   my $nrows = $self->query_value( "_${attr}_nrows" )
      or return $self->_query_by_type( q(array), $attr );

   my $r_no = 0; my @selected = ();

   while ($r_no < $nrows) {
      my $v = __filter_value( $self->query_value( "${attr}.select${r_no}" ) );

      $v and push @selected, $v; $r_no++;
   }

   return \@selected;
}

sub query_hash {
   my ($self, $attr, $fields) = @_;

   my $nrows = $self->query_value( "_${attr}_nrows" ) || 0;

   my $ncols = @{ $fields }; my $result = $ncols > 1 ? {} : []; my $r_no = 0;

   # TODO: Editable field line of table not being picked up as a new row
   while ($r_no < $nrows) {
      my $c_no = 0; my $prefix = "${attr}_${r_no}_";

      if (my $key = $self->query_value( $prefix.$c_no )) {
         if ($ncols > 1) {
            for my $field (@{ $fields }) {
               if ($c_no > 0) {
                  my $qv = $self->query_value( $prefix.$c_no );

                  $result->{ $key }->{ $field } = __filter_value( $qv );
               }

               $c_no++;
            }
         }
         else { push @{ $result }, __filter_value( $key ) }
      }

      $r_no++;
   }

   return $result;
}

sub query_value {
   return shift->_query_by_type( q(value), @_ );
}

sub query_value_by_fields {
   my ($self, @fields) = @_;

   return { map  { $_->[ 0 ] => $_->[ 1 ]           }
            grep { defined $_->[ 1 ]                }
            map  { [ $_, $self->query_value( $_ ) ] } @fields };
}

# Private methods

sub _decode_data {
   my ($self, $enc_name, $data) = @_; my $enc;

   return                       unless (defined $data                    );
   return $data                 if     (is_hashref $data                 );
   return $data                 unless ($enc = find_encoding( $enc_name ));
   return $enc->decode( $data ) unless (is_arrayref $data                );

   return [ map { $enc->decode( $_ ) } @{ $data } ];
}

sub _get_req_array {
   my ($self, $attr) = @_; my $c = $self->model->context;

   my $value = $c->req->params->{ $attr || NUL };

   $value = defined $value ? $value : [];

   is_arrayref $value or $value = [ $value ];

   return $value;
}

sub _get_req_value {
   my ($self, $attr) = @_; my $c = $self->model->context;

   my $value = $c->req->params->{ $attr || NUL };

   is_arrayref $value and $value = $value->[ 0 ];

   return $value;
}

sub _guess_encoding {
   my ($self, $req_method, @rest) = @_; my $data;

   defined ($data = $self->$req_method( @rest )) or return;

   my $all = (is_arrayref $data) ? join SPC, @{ $data } : $data;
   my $enc = guess_encoding( $all, grep { not m{ guess }mx }
                             @{ $self->encodings } );

   return $enc && ref $enc ? $self->_decode_data( $enc->name, $data ) : $data;
}

sub _query_by_type {
   my ($self, $type, @rest) = @_;

   my $method = "_get_req_${type}".__method_name( $self->encoding || q(guess) );
   my $value  = $self->$method( @rest );

   $self->model->context->stash->{query_scrubbing} or return $value;

   if ($type ne q(array)) { $value = $self->_scrub( $value ) }
   else { @{ $value } = map { $self->_scrub( $_ ) } @{ $value } }

   return $value;
}

sub _scrub {
   my ($self, $value) = @_; defined $value or return;

   my $scrubber = $self->scrubber;

   is_coderef $scrubber and return $scrubber->( $value );

   $value =~ s{ $scrubber }{}gmx; return $value;
}

# Private functions

sub __filter_value {
   my $y = unescape_TT dos2unix( $_[ 0 ] ); return length $y ? $y : undef;
}

sub __method_name {
   (my $enc = lc shift) =~ s{ [-] }{_}gmx; return "_${enc}_encoding";
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::QueryRequest - Create request query methods for different encodings

=head1 Version

Describes v0.17.$Rev: 1 $

=head1 Synopsis

   use  qw(CatalystX::Usul::QueryRequest);

=head1 Description

Creates a pair of methods (one for scalar values and one for array refs) for
each of the encodings specified in the I<encodings> attribute

=head1 Configuration and Environment

Defines the following accessors:

=over 3

=item encoding

An encoding type which is required

=item encodings

Array ref which defaults  to C<< [ qw(ascii iso-8859-1 UTF-8 guess) ] >>

=item request

A weakened request object reference. This is a writable attribute

=item scrubbing

Boolean used by L</query_array> and L</query_value> to determine if input
value should be cleaned of potentially dangerous characters

=item scrubber

List of characters to scrub from input values. Defaults to '"/\;. Can also
be a coderef in which case it is called with the input value and it's
return value is used

=back

=head1 Subroutines/Methods

=head2 BUILD

Create the request query methods

=head2 query_array

   $array_ref = $self->query_array( $attr );

Uses the I<encoding> attribute to generate the method call to decode
the input values. Will try to guess the encoding if one is not
provided

If the form attribute I<_${attr}_nrows> is not defined then this
method returns an array ref of the the form attributes. If the
I<_${attr}_nrows> is defined then this method returns an array ref of
selected values from the select checkbox column of the table widget

=head2 query_hash

   $hash_ref = $self->query_hash( $attr, \@fields );

Returns a hash ref of data extracted from the table embeded in a form

=head2 query_value

   $scalar_value = $self->query_value( $attr );

Returns the requested parameter in a scalar context. Uses I<encoding>
attribute to generate the method call to decode the input value. Will
try to guess the encoding if one is not provided

=head2 query_value_by_fields

   $hash_ref = $self->query_value_by_fields( @fields );

Returns a hash_ref of fields and their values if the values are
defined by the request. Calls L</query_value> for each of supplied
fields

=head2 _decode_data

   $array_ref = $self->_decode_data( $encoding, $array_ref );
   $value     = $self->_decode_data( $encoding, $value     );

Decodes the data passed using the given encoding name. Can handle both
scalars and array refs but not hashes

=head2 _get_req_array

   $array_ref = $self->_get_req_array( $attr );

Uses the I<request> attribute that must implement a C<params> method which
returns a hash ref. The method returns the value for C<$attr> from
that hash. This method will always return a array ref

=head2 _get_req_value

   $value = $self->_get_req_value( $attr );

Uses the I<request> attribute that must implement a C<params> method which
returns a hash ref. The method returns the value for C<$attr> from
that hash. This method will always return a scalar

=head2 _guess_encoding

   $value = $self->_guess_encoding( $req_method, $attr );

If you really don't know what the source encoding is then this method
will use L<Encode::Guess> to determine the encoding. If successful
calls L</_decode_data> to get the job done

=head2 _scrub

   $value = $self->_scrub( $value );

Removes the C<< $self->scrubbing >> from the value

=head2 __method_name

   $name = __method_name( $encoding );

Takes an encoding name and converts it to a private method name

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Moose>

=item L<Encode>

=item L<Encode::Guess>

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
