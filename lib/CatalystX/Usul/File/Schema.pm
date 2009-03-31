package CatalystX::Usul::File::Schema;

# @(#)$Id: Schema.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul);
use CatalystX::Usul::File::ResultSet;
use CatalystX::Usul::File::Storage;
use Class::C3;
use Scalar::Util qw(weaken);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

__PACKAGE__->config
   ( attributes           => [],
     defaults             => {},
     element              => q(unknown),
     resultset_attributes => {},
     resultset_class      => q(CatalystX::Usul::File::ResultSet),
     storage_class        => q(CatalystX::Usul::File::Storage), );

__PACKAGE__->mk_accessors( qw(attributes defaults element label_attr
                              lang_dep resultset_attributes
                              resultset_class source storage
                              storage_class) );

sub new {
   my ($self, $app, $attrs) = @_;

   my $new = $self->next::method( $app, $attrs );

   $attrs  = { %{ $attrs->{storage_attributes} || {} }, schema => $new };
   $new->storage( $new->storage_class->new( $app, $attrs ) );

   weaken( $new->storage->{schema} );
   return $new;
}

sub resultset {
   my $self  = shift;
   my $attrs = { %{ $self->resultset_attributes }, schema => $self };
   my $rs    = $self->resultset_class->new( $attrs );

   weaken( $rs->{schema} );
   return $rs;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::File::Schema - Base class for schema definitions

=head1 Version

0.1.$Revision: 402 $

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

=head2 resultset

Creates a new instance of the result set class which defaults to
L<CatalystX::Usul::File::ResultSet>

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
