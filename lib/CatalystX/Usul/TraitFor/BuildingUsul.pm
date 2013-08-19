# @(#)Ident: ;

package CatalystX::Usul::TraitFor::BuildingUsul;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use Moose::Role;

requires q(COMPONENT);

around 'COMPONENT' => sub {
   my ($next, $self, @args) = @_; my $app_class = blessed $self || $self;

   my $comp = $self->$next( @args ); $comp->{_application} ||= $app_class;

   return $comp;
};

sub app_class {
   return $_[ 0 ]->{_application};
}

sub _build_usul {
   return $_[ 0 ]->app_class->usul;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TraitFor::BuildingUsul - Caches the app_class for later use

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   use CatalystX::Usul::Moose;

   with qw(CatalystX::Usul::TraitFor::BuildingUsul);

   my $usul_object = $self->_build_usul;

=head1 Description

Caches the application's class for later use when building components

=head1 Configuration and Environment

Requires the C<COMPONENT> method

=head1 Subroutines/Methods

=head2 app_class

Returns the caches value for the application's class

=head2 _build_usul

Returns a reference to the L<Class::Usul> object created by the plugin
L<Catalyst::Plugin::InflateMore>

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Moose::Role>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Acknowledgements

L<Catalyst::Model::DBIC::Schema> - From which the app_class code was robbed

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
