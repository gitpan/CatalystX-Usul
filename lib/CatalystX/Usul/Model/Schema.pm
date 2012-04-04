# @(#)$Id: Schema.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Model::Schema;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use parent qw(Catalyst::Model::DBIC::Schema
              CatalystX::Usul::Model
              CatalystX::Usul::Schema);

use MRO::Compat;
use Scalar::Util qw(blessed);

__PACKAGE__->config( conf_extn => q(.xml) );

sub COMPONENT {
   my ($class, $app, $config) = @_;

   my $comp = $class->next::method( $app, $config );
   my $usul = CatalystX::Usul::Model->COMPONENT( $app, $config );

   for (grep { not defined $comp->{ $_ } } keys %{ $usul }) {
      $comp->{ $_ } = $usul->{ $_ }; # Attribute mixin
   }

   return $comp;
}

sub ACCEPT_CONTEXT {
   # Prevents the ACCEPT_CONTEXT in C::M::DBIC::Schema from being called
   my ($self, $c, @rest) = @_;

   blessed $c or return $self->build_per_context_instance( $c, @rest );

   my $s   = $c->stash;
   my $key = q(__InstancePerContext_).(blessed $self ? refaddr $self : $self);

   return $s->{ $key } ||= $self->build_per_context_instance( $c, @rest );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Schema - Base class for database models

=head1 Version

0.6.$Revision: 1165 $

=head1 Synopsis

   package YourApp::Model::YourModel;

   use parent qw(CatalystX::Usul::Model::Schema);

   __PACKAGE__->config( database     => q(library),
                        schema_class => q(YourApp::Schema::YourSchema) );

   sub COMPONENT {
      my ($class, $app, $config) = @_;

      $config->{database    } ||= $class->config->{database};
      $config->{connect_info} ||=
         $class->get_connect_info( $app->config, $config->{database} );

      return $class->next::method( $app, $config );
   }

=head1 Description

Aggregates the methods from the three classes it inherits from

=head1 Subroutines/Methods

=head2 ACCEPT_CONTEXT

Copy of the one in L<CatalsytX::Usul::Model> which is much more useful
than the pointless one we are overridding in
L<Catalyst::Model::DBIC::Schema>

=head2 COMPONENT

Adds the attributes from L<CatalystX::Usul::Model> to the ones from
L<Catalyst::Model::DBIC::Schema>

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Catalyst::Model::DBIC::Schema>

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::Schema>

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
