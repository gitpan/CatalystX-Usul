# @(#)$Id: Encoding.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::Encoding;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );

use Encode;
use Encode::Guess;

our $ENCODINGS = [ qw(ascii iso-8859-1 UTF-8 guess) ];
our $LEVELS    = [ qw(alert debug error fatal info warn) ];

sub mk_encoding_methods {
   my ($self, @fields) = @_; my $class = ref $self || $self;

   no strict q(refs); ## no critic

   for my $enc (grep { !m{ guess }mx } @{ $ENCODINGS }) {
      my $accessor = __PACKAGE__.q(::)._method_name( $enc );

      unless (defined &{ "$accessor" }) {
         *{ "$accessor" } = sub {
            my ($self, $field, $caller, @rest) = @_;

            return $self->_decode_data( $enc, $caller->$field( @rest ) );
         };
      }
   }

   foreach my $field (@fields) {
      foreach my $method (map { _method_name( $_ ) } @{ $ENCODINGS }) {
         my $accessor = $class.q(::).$field.$method;

         unless (defined &{ "$accessor" }) {
            *{ "$accessor" }
               = sub { return __PACKAGE__->$method( $field, @_ ) };
         }
      }
   }

   return;
}

sub mk_log_methods {
   my $self = shift; my $class = ref $self || $self;

   no strict q(refs); ## no critic

   for my $level (@{ $LEVELS }) {
      my $accessor = $class.q(::log_).$level;

      unless (defined &{ "$accessor" }) {
         *{ "$accessor" } = sub {
            my ($self, $text) = @_;
            return unless ($text);
            $text = encode( $self->encoding, $text ) if ($self->encoding);
            $self->log->$level( $text."\n" );
            return;
         };
      }
   }

   return;
}

# Private class methods

sub _decode_data {
   my ($self, $enc_name, $data) = @_; my $enc;

   return                       unless (defined $data                    );
   return $data                 if     (ref $data eq q(HASH)             );
   return $data                 unless ($enc = find_encoding( $enc_name ));
   return $enc->decode( $data ) unless (ref $data eq q(ARRAY)            );

   return [ map { $enc->decode( $_ ) } @{ $data } ];
}

sub _guess_encoding {
   my ($self, $field, $caller, @rest) = @_; my $data;

   return unless (defined ($data = $caller->$field( @rest )) );

   my $all = ref $data eq q(ARRAY) ? join q( ), @{ $data } : $data;
   my $enc = guess_encoding( $all, grep { !m{ guess }mx } @{ $ENCODINGS } );

   return $enc && ref $enc ? $self->_decode_data( $enc->name, $data ) : $data;
}

sub _method_name {
   (my $enc = lc shift) =~ s{ [-] }{_}gmx; return q(_).$enc.q(_encoding)
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Encoding - Create additional methods for different encodings

=head1 Version

$Revision: 562 $

=head1 Synopsis

   use base qw(CatalystX::Usul::Encoding);

   __PACKAGE__->mk_encoding_methods( qw(get_req_array get_req_value) );

   sub get_req_array {
      my ($self, $req, $field) = @_; my $value = $req->params->{ $field };

      $value = defined $value ? $value : [];

      return ref $value eq q(ARRAY) ? $value : [ $value ];
   }

   sub get_req_value {
      my ($self, $req, $field) = @_; my $value = $req->params->{ $field };

      return $value && ref $value eq q(ARRAY) ? $value->[0] : $value;
   }

   # The standard calls are
   $array = $self->get_req_array( $c->req, $field );
   $value = $self->get_req_value( $c->req, $field );

   # but now we can call these methods also
   $array = $self->get_req_array_ascii_encoding(      $c->req, $field );
   $array = $self->get_req_array_iso_8859_1_encoding( $c->req, $field );
   $array = $self->get_req_array_utf_8_encoding(      $c->req, $field );
   $array = $self->get_req_array_guess_encoding(      $c->req, $field );
   $value = $self->get_req_value_ascii_encoding(      $c->req, $field );
   $value = $self->get_req_value_iso_8859_1_encoding( $c->req, $field );
   $value = $self->get_req_value_utf_8_encoding(      $c->req, $field );
   $value = $self->get_req_value_guess_encoding(      $c->req, $field );

   __PACKAGE__->mk_log_methods();

   # Can now call the following
   $self->log_debug( $text );
   $self->log_info(  $text );
   $self->log_warn(  $text );
   $self->log_error( $text );
   $self->log_fatal( $text );

=head1 Description

For each input method defined in your class C<mk_encoding_methods>
defines additional methods; C<my_input_method_utf_8_encoding> and
C<my_input_method_guess_encoding> for example

=head1 Subroutines/Methods

=head2 mk_encoding_methods

Takes a list of method names in the calling package. For each of these
a set of new methods are defined in the calling package. The method
set is defined by the list of values in the C<$ENCODINGS> package
variable. Each of these newly defined methods calls C<_decode_data>
with a different encoding name

=head2 mk_log_methods

Creates a set of methods defined by the C<$LEVELS> package
variable. The method expects C<< $self->log >> and C<< $self->encoding >>
to be set.  It encodes the output string prior calling the log
method at the given level

=head2 _decode_data

Decodes the data passed using the given encoding name. Can handle both
scalars and array refs but not hashes

=head2 _guess_encoding

If you really don't know what the source encoding is then this method
will use L<Encode::Guess> to determine the encoding. If successful
calls C<_decode_data> to get the job done

=head2 _method_name

Takes an encoding name and converts it to a private method name

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

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
