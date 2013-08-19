# @(#)Ident: ;

package CatalystX::Usul::InflateSymbols;

use strict;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use Class::Usul;
use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(is_hashref);

has 'app_class' => is => 'ro',   isa => NonEmptySimpleStr, required => TRUE;

around 'BUILDARGS' => sub {
   my ($next, $self, @args) = @_; my $car = $args[ 0 ];

   $car and @args < 2 and not is_hashref $car
      and return $self->$next( { app_class => $car } );

   return $self->$next( @args );
};

sub inflate {
   my ($self, $symbol, $relpath) = @_; my $usul = $self->_usul; my $inflated;

   $usul->config->can( $symbol ) and $inflated = $usul->config->$symbol;

   (defined $inflated and defined $relpath) or return $inflated;

   return $usul->config->canonicalise( $inflated, $relpath );
}

# Private methods

sub _usul {
   my $self = shift; my $app_class = $self->app_class; my $usul;

   $app_class->can( q(usul) ) and defined ($usul = $app_class->usul)
      and return $usul;

   $usul = Class::Usul->new_from_class( $app_class );

   $app_class->mk_classdata( q(usul), $usul );

   return $usul;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::InflateSymbols - Return paths to installation directories

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   package MyApp;

   use Catalyst qw(InflateMore ConfigLoader ...);

   MyApp->config->{Plugin::InflateMore} = 'CatalystX::Usul::InflateSymbols';

=head1 Description

The intention here is to demonstrate how to use
L<Catalyst::Plugin::InflateMore> to inflate symbolic references in configuration
data

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item app_class

The classname of the application whose configuration data symbols are being
inflated

=back

=head1 Subroutines/Methods

=head2 inflate

   $inflated = $self->inflate( $symbol, $relpath );

Inflates the symbol. If C<$relpath> is provided returns the untainted
canonical path of the concatenated inflated symbol value and the
C<$relpath>

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul>

=item L<CatalystX::Usul::Moose>

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
