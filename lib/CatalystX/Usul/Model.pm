# @(#)$Ident: Model.pm 2013-08-19 19:06 pjf ;

package CatalystX::Usul::Model;

use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw( is_arrayref is_hashref throw );
use CatalystX::Usul::Moose;
use Scalar::Util               qw( refaddr );

extends q(Catalyst::Model);
with    q(CatalystX::Usul::TraitFor::BuildingUsul);

has 'context'           => is => 'rwp',  isa => Object, weak_ref => TRUE;

has 'domain_attributes' => is => 'lazy', isa => HashRef,
   default              => sub { { encoding => $_[ 0 ]->encoding } };

has 'domain_class'      => is => 'lazy', isa => NullLoadingClass,
   coerce               => TRUE, default => sub {};

has 'domain_model'      => is => 'rw',   isa => Object;

has 'encoding'          => is => 'lazy', isa => CharEncoding, coerce => TRUE,
   default              => sub { $_[ 0 ]->usul->config->encoding };

has 'table_class'       => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default              => sub { 'Class::Usul::Response::Table' };

has 'usul'              => is => 'lazy', isa => BaseClass,
   handles              => [ qw(debug lock log) ];

sub ACCEPT_CONTEXT {
   my ($self, $c, @args) = @_;

   blessed $c or return $self->build_per_context_instance( $c, @args );

   my $s   = $c->stash;
   my $key = q(__InstancePerContext_).(blessed $self ? refaddr $self : $self);

   return $s->{ $key } ||= $self->build_per_context_instance( $c, @args );
}

sub build_per_context_instance {
   my ($self, $c) = @_;

   my $class = blessed $self or throw 'Not a class method';
   my $clone = bless { %{ $self } }, $class; # Clone self

   blessed $c and $clone->_set_context( $c );

   return $clone;
}

sub loc {
   my ($self, $key, @args) = @_; my $car = $args[ 0 ];

   my $args = (is_hashref $car) ? { %{ $car } }
            : { params => (is_arrayref $car) ? $car : [ @args ] };
   my $s    = $self->context->stash;

   $args->{domain_names} ||= [ DEFAULT_L10N_DOMAIN, $s->{ns} ];
   $args->{locale      } ||= $s->{language};

   return $self->usul->localize( $key, $args );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model - Interface model base class

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   package YourApp::Model::YourModel;

   use CatalystX::Usul::Moose;

   extends qw(CatalystX::Usul::Model);

=head1 Description

Common core interface model methods

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item context

A weakened copy of the L<Catalyst> object

=item domain_attributes

Hash ref which defaults to I<< {} >>

=item domain_class

A loadable class which defaults to I<Class::Null>

=item domain_model

The domain model object

=item encoding

The IO encoding used by the domain model. Defaults to
L<Class::Usul::Config/encoding>

=item table_class

A loadable class which defaults to L<Class::Usul::Response::Table>. Contains
a table of links used to display the site map

=item usul

A reference to the L<Class::Usul> object stored on the application by
L<CatalystX::Usul::TraitFor::CreatingUsul>

=back

=head1 Subroutines/Methods

=head2 ACCEPT_CONTEXT

Calls L</build_per_context_instance> for each new context

=head2 build_per_context_instance

Called by L</ACCEPT_CONTEXT>. Takes a copy of the L<Catalyst> object as
C<< $self->context >>

=head2 loc

   $localized_text = $self->loc( $key, @options );

Localizes the message. Calls L<Class::Usul::L10N/localize>. Adds the
constant C<DEFAULT_L10N_DOMAINS> to the list of domain files that are
searched. Adds C<< $self->context->stash->language >> and
C<< $self->context->stash->namespace >> (search domain) to the
arguments passed to C<localize>

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Catalyst::Model>

=item L<CatalystX::Usul>

=item L<CatalystX::Usul::TraitFor::BuildingUsul>

=item L<Class::Usul>

=item L<CatalystX::Usul::Moose>

=item L<Scalar::Util>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module.

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
