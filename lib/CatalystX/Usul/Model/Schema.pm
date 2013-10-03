# @(#)Ident: ;

package CatalystX::Usul::Model::Schema;

use strict;
use version; our $VERSION = qv( sprintf '0.13.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use Scalar::Util qw(refaddr);

extends qw(Catalyst::Model::DBIC::Schema CatalystX::Usul::Model);
with    q(CatalystX::Usul::TraitFor::Model::QueryingRequest);
with    q(CatalystX::Usul::TraitFor::Model::StashHelper);
with    q(CatalystX::Usul::TraitFor::ConnectInfo);

around 'BUILDARGS' => sub {
   my ($next, $self, $app, @rest) = @_; my $attr = $self->$next( $app, @rest );

   my $model = CatalystX::Usul::Model->new( $app, $attr );

   for (grep { not exists $attr->{ $_ } } keys %{ $model }) {
      $attr->{ $_ } = $model->{ $_ }; # Attribute mixin
   }

   return $attr;
};

sub ACCEPT_CONTEXT {
   # Prevents the ACCEPT_CONTEXT in C::M::DBIC::Schema from being called
   my ($self, $c, @rest) = @_;

   blessed $c or return $self->build_per_context_instance( $c, @rest );

   my $s   = $c->stash;
   my $key = q(__InstancePerContext_).(blessed $self ? refaddr $self : $self);

   return $s->{ $key } ||= $self->build_per_context_instance( $c, @rest );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Schema - Base class for database models

=head1 Version

Describes v0.13.$Rev: 1 $

=head1 Synopsis

   package YourApp::Model::YourModel;

   use CatalystX::Usul::Moose;

   extends q(CatalystX::Usul::Model::Schema);

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

Aggregates the methods from the two classes it inherits from

=head1 Configuration and Environment

=head2 BUILDARGS

Adds the attributes from L<CatalystX::Usul::Model> to the ones from
L<Catalyst::Model::DBIC::Schema>

=head1 Subroutines/Methods

=head2 ACCEPT_CONTEXT

Copy of the one in L<CatalsytX::Usul::Model> which is much more useful
than the pointless one we are overriding in
L<Catalyst::Model::DBIC::Schema>

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Catalyst::Model::DBIC::Schema>

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::TraitFor::ConnectInfo>

=item L<CatalystX::Usul::TraitFor::Model::QueryingRequest>

=item L<CatalystX::Usul::TraitFor::Model::StashHelper>

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
