# @(#)$Id: Schema.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::File::Schema;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul);

use CatalystX::Usul::File::Storage;
use Class::C3;
use Scalar::Util qw(weaken);

__PACKAGE__->config
   ( attributes    => [],
     defaults      => {},
     element       => q(unknown),
     storage_class => q(CatalystX::Usul::File::Storage), );

__PACKAGE__->mk_accessors( qw(attributes defaults element label_attr
                              lang_dep source storage storage_class) );

sub new {
   my ($self, $app, $attrs) = @_;

   my $new = $self->next::method( $app, $attrs );

   weaken( $new->{source} );

   $attrs  = { %{ $attrs->{storage_attributes} || {} }, schema => $new };
   $new->storage( $new->storage_class->new( $app, $attrs ) );

   return $new;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::File::Schema - Base class for schema definitions

=head1 Version

0.1.$Revision: 562 $

=head1 Synopsis

   package CatalystX::Usul::File::ResultSource;

   use parent qw(CatalystX::Usul);
   use CatalystX::Usul::File::Schema;
   use Class::C3;
   use Scalar::Util qw(weaken);

   __PACKAGE__->config( schema_class => q(CatalystX::Usul::File::Schema) );

   __PACKAGE__->mk_accessors( qw(schema schema_class) );

   sub new {
      my ($self, $app, $attrs)  = @_;

      my $new = $self->next::method( $app, $attrs );

      $attrs  = { %{ $attrs->{schema_attributes} || {} }, source => $new };

      $new->schema( $new->schema_class->new( $app, $attrs ) );

      weaken( $new->schema->{source} );
      return $new;
   }

=head1 Description

This is the base class for schema definitions. Each element in a data file
requires a schema definition to define it's attributes that should
inherit from this

=head1 Subroutines/Methods

=head2 new

Creates a new instance of the storage class which defaults to
L<CatalystX::Usul::File::Storage>

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul>

=item L<CatalystX::Usul::File::ResultSet>

=item L<CatalystX::Usul::File::Storage>

=item L<Scalar::Util>

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
