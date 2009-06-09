# @(#)$Id: Storage.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::File::Storage;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul);

use Scalar::Util qw(weaken);

__PACKAGE__->config( class => q(XML::Simple) );

sub new {
   my ($self, $app, $attrs) = @_; $attrs ||= {};

   my $class = $attrs->{class} || $self->config->{class};

   if (q(+) eq substr $class, 0, 1) { $class = substr $class, 1 }
   else { $class = __PACKAGE__.q(::).$class }

   $self->ensure_class_loaded( $class );

   my $new = $class->new( $app, $attrs );

   weaken( $new->{schema} );
   return $new;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::File::Storage - Factory subclass loader

=head1 Version

0.1.$Revision: 562 $

=head1 Synopsis

   package CatalystX::Usul::File::Schema;

   use parent qw(CatalystX::Usul);
   use CatalystX::Usul::File::Storage;
   use Class::C3;
   use Scalar::Util qw(weaken);

   __PACKAGE__->config( storage_class => q(CatalystX::Usul::File::Storage) );

   __PACKAGE__->mk_accessors( qw(storage storage_class) );

   sub new {
      my ($self, $app, $attrs) = @_;

      my $new = $self->next::method( $app, $attrs );

      $attrs  = { %{ $attrs->{storage_attributes} || {} }, schema => $new };
      $new->storage( $new->storage_class->new( $app, $attrs ) );

      weaken( $new->storage->{schema} );
      return $new;
   }

=head1 Description

Loads and instantiates a factory subclass

=head1 Subroutines/Methods

=head2 new

Loads the subclass specified by the I<class> package attribute and
returns an instance of it

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul>

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
