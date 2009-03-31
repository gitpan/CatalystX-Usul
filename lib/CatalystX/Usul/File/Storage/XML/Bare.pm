package CatalystX::Usul::File::Storage::XML::Bare;

# @(#)$Id: Bare.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::File::Storage::XML);
use XML::Bare;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

__PACKAGE__->config( root_name => q(config) );

__PACKAGE__->mk_accessors( qw(root_name) );

my $PADDING = q(  );

# Private methods

sub _read_file {
   my ($self, $path) = @_;

   my $method = sub {
      my $data;
      $data = $self->_dtd_parse( $path->all );
      $data = XML::Bare->new( text => $data )->parse() || {};
      $data = $data->{ $self->root_name } || {};
      $self->_read_filter( $self->_arrays || {}, $data );
      return $data;
   };

   return $self->_read_file_with_locking( $path, $method );
}

sub _write_file {
   my ($self, $path, $data) = @_;

   unless (-f $path->pathname) {
      $self->throw( error => q(eNotFound), arg1 => $path->pathname );
   }

   my $method = sub {
      my $wtr = shift;
      $wtr->println( @{ $self->_dtd } ) if ($self->_dtd->[ 0 ]);
      $wtr->print(  $self->_write_filter( 0, $self->root_name, $data ) );
      return $data;
   };

   return $self->_write_file_with_locking( $path, $method );
}

# Private methods

sub _read_filter {
   # Turn the structure returned by XML::Bare into one returned by XML::Simple
   my ($self, $arrays, $data) = @_; my ($hash, $value);

   if (ref $data eq q(ARRAY)) {
      for my $key (0 .. $#{ $data }) {
         if (ref $data->[ $key ] eq q(HASH)
             && defined ($value = $data->[ $key ]->{value})
             && $value !~ m{ \A [\n\s]+ \z }mx) {
            # Coerce arrays from single scalars. Array list given by the DTD
            if ($arrays->{ $key }) { $data->[ $key ] = [ $value ] }
            else { $data->[ $key ] = $value }

            next;
         }

         $self->_read_filter( $arrays, $data->[ $key ] ); # Recurse
      }
   }
   elsif (ref $data eq q(HASH)) {
      for my $key (keys %{ $data }) {
         if (ref $data->{ $key } eq q(HASH)
             && defined ($value = $data->{ $key }->{value})
             && $value !~ m{ \A [\n\s]+ \z }mx) {
            # Coerce arrays from single scalars. Array list given by the DTD
            if ($arrays->{ $key }) { $data->{ $key } = [ $value ] }
            else { $data->{ $key } = $value }

            next;
         }

         $self->_read_filter( $arrays, $data->{ $key } ); # Recurse

         # Turn arrays of hashes with a name attribute into hash keyed by name
         if (ref $data->{ $key } eq q(ARRAY)
             && ($value = $data->{ $key }->[ 0 ])
             && ref $value eq q(HASH)
             && exists $value->{name}) {
            $hash = {};

            for my $ref (@{ $data->{ $key } }) {
               my $name = delete $ref->{name}; $hash->{ $name } = $ref;
            }

            $data->{ $key } = $hash;
         }
      }

      delete $data->{_pos} if (exists $data->{_pos});

      if (exists $data->{value} && $data->{value} =~ m{ \A [\n\s]+ \z }mx) {
         delete $data->{value};
      }
   }

   return;
}

sub _write_filter {
   my ($self, $level, $element, $data) = @_; my $xml = q();

   my $padding = $PADDING x $level;

   if (ref $data eq q(ARRAY)) {
      for (sort @{ $data }) {
         $xml .= $padding.q(<).$element.q(>).$_.q(</).$element.q(>)."\n";
      }
   }
   elsif (ref $data eq q(HASH)) {
      $padding = $PADDING x ($level + 1);

      for my $key (sort keys %{ $data }) {
         my $value = $data->{ $key };

         if (ref $value eq q(HASH)) {
            for (sort keys %{ $value }) {
               $xml .= $padding.q(<).$key.q(>)."\n";
               $xml .= $padding.$PADDING.q(<name>).$_.q(</name>)."\n";
               $xml .= $self->_write_filter( $level + 1, q(), $value->{ $_ } );
               $xml .= $padding.q(</).$key.q(>)."\n";
            }
         }
         else { $xml .= $self->_write_filter( $level + 1, $key, $value ) }
      }
   }
   elsif ($element) {
      $xml .= $padding.q(<).$element.q(>).$data.q(</).$element.q(>)."\n";
   }

   if ($level == 0 && $element) {
      $xml = q(<).$element.q(>)."\n".$xml.q(</).$element.q(>)."\n";
   }

   return $xml;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::File::Storage::XML::Bare - Read/write XML data storage model

=head1 Version

0.1.$Revision: 402 $

=head1 Synopsis

   package CatalystX::Usul::File::Storage;

   use parent qw(CatalystX::Usul);

   __PACKAGE__->config( class => q(XML::Bare) );

   sub new {
      my ($self, $app, $attrs) = @_; $attrs ||= {};

      my $class = $attrs->{class} || $self->config->{class};

      if (q(+) eq substr $class, 0, 1) { $class = substr $class, 1 }
      else { $class = __PACKAGE__.q(::).$class }

      $self->ensure_class_loaded( $class );

      return $class->new( $app, $attrs );
   }

=head1 Description

Uses L<XML::Bare> to read and write XML files

=head1 Subroutines/Methods

=head2 _read_file

Defines the closure that reads the file, parses the DTD, parses the
file using L<XML::Bare> and filters the resulting hash so that it is
compatible with L<XML::Simple>. Calls
L<read file with locking|CatalystX::Usul::File::Storage::XML/_read_file_with_locking>
in the base class

=head2 _read_filter

Processes the hash read by L</_read_file> altering it's structure so that
is is compatible with L<XML::Simple>

=head2 _write_file

Defines the closure that writes the DTD and data to file. Filters the data
so that it is readable by L<XML::Bare>

=head2 _write_filter

Reverses the changes made by L</_read_filter>

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::File::Storage::XML>

=item L<XML::Bare>

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
