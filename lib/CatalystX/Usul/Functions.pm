# @(#)Ident: ;

package CatalystX::Usul::Functions;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.14.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Class::Usul::Functions ();
use Sub::Exporter;

my @_my_functions;

BEGIN {
   @_my_functions = ( qw(dos2unix) );
}

sub import {
   my ($class, @wanted_functions) = @_; my $into = caller; my @self = ();

   my $class_usul = {}; $class_usul->{ $_ } = 1 for (@wanted_functions);

   for (@_my_functions) { delete $class_usul->{ $_ } and push @self, $_ }

   my $import = Sub::Exporter::build_exporter( {
      exports => [ @_my_functions ], groups => { default => [], },
   } );

   Class::Usul::Functions->import( { into => $into }, keys %{ $class_usul } );
   __PACKAGE__->$import( { into => $into }, @self );
   return;
}

sub dos2unix (;$){
   my $y = shift; defined $y or $y = q();

   $y =~ s{ [\r][\n] }{\n}gmsx; return $y;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Functions - Exports general purpose functions

=head1 Version

Describes v0.14.$Rev: 1 $

=head1 Synopsis

   use CatalystX::Usul::Functions qw(abs_path throw);

=head1 Description

Exports functions. Some are defined locally the rest are taken from
L<Class::Usul::Functions>

=head1 Subroutines/Methods

=head2 import

Make the requested functions available in the callers namespace

=head2 dos2unix

   $unix_text = dos2unix $dos_text;

Replaces evil line termination characters with the proper one

=head1 Configuration and Environment

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul::Functions>

=item L<Sub::Exporter>

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
