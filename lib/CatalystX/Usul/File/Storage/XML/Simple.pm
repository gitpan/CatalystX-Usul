package CatalystX::Usul::File::Storage::XML::Simple;

# @(#)$Id: Simple.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::File::Storage::XML);
use XML::Simple;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

# Private methods

sub _read_file {
   my ($self, $path) = @_;

   my $method = sub {
      my $data   = $self->_dtd_parse( $path->all );
      my $arrays = [ keys %{ $self->_arrays } ];
      my $xs     = XML::Simple->new( SuppressEmpty => 1 );
      return $xs->xml_in( $data, ForceArray => $arrays );
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
      my $xs  = XML::Simple->new( NoAttr   => 1, SuppressEmpty => 1,
                                  RootName => q(config) );
      $wtr->println( @{ $self->_dtd }      ) if ($self->_dtd->[ 0 ]);
      $wtr->append(  $xs->xml_out( $data ) );
      return $data;
   };

   return $self->_write_file_with_locking( $path, $method );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::File::Storage::XML::Simple - Read/write XML data storage model

=head1 Version

0.1.$Revision: 402 $

=head1 Synopsis

   package CatalystX::Usul::File::Storage;

   use parent qw(CatalystX::Usul);

   __PACKAGE__->config( class => q(XML::Simple) );

   sub new {
      my ($self, $app, $attrs) = @_; $attrs ||= {};

      my $class = $attrs->{class} || $self->config->{class};

      if (q(+) eq substr $class, 0, 1) { $class = substr $class, 1 }
      else { $class = __PACKAGE__.q(::).$class }

      $self->ensure_class_loaded( $class );

      return $class->new( $app, $attrs );
   }

=head1 Description

Uses L<XML::Simple> to read and write XML files

=head1 Subroutines/Methods

=head2 _read_file

Defines the closure that reads the file, parses the DTD, parses the
file using L<XML::Simple>. Calls
L<read file with locking|CatalystX::Usul::File::Storage::XML/_read_file_with_locking>
in the base class

=head2 _write_file

Defines the closure that writes the DTD and data to file

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::File::Storage::XML>

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