# @(#)$Ident: LoadingClasses.pm 2014-01-09 16:37 pjf ;

package CatalystX::Usul::TraitFor::LoadingClasses;

use strict;
use namespace::sweep;
use version; our $VERSION = qv( sprintf '0.17.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Class::Usul::Constants;
use Class::Usul::Functions  qw( ensure_class_loaded find_source throw );
use File::Basename          qw( basename );
use File::Spec::Functions   qw( catfile );
use Module::Pluggable::Object;
use Scalar::Util            qw( blessed );
use Unexpected::Functions   qw( Unspecified );
use Moo::Role;

sub build_subcomponents { # Voodo by mst. Finds and loads component subclasses
   my ($self, $base_class) = @_; my $my_class = blessed $self || $self;

   $base_class or throw class => Unspecified, args => [ 'Base class' ];

  (my $dir = find_source $base_class) =~ s{ [.]pm \z }{}msx;

   for my $path (glob catfile( $dir, '*.pm' )) {
      my $subcomponent = basename( $path, '.pm' );
      my $component    = join '::', $my_class,   $subcomponent;
      my $base         = join '::', $base_class, $subcomponent;

      $self->load_component( $component, $base );
   }

   return;
}

sub load_component {
   my ($self, $child, @parents) = @_;

   $child or throw class => Unspecified, args => [ 'Child class' ];

   ## no critic
   for my $parent (reverse @parents) {
      ensure_class_loaded $parent;
      {  no strict 'refs';

         $child eq $parent or $child->isa( $parent )
            or unshift @{ "${child}::ISA" }, $parent;
      }
   }

   exists $Class::C3::MRO{ $child } or eval "package $child; import Class::C3;";
   ## critic
   return;
}

sub setup_plugins {
   # Searches for and then load plugins in the search path
   my ($self, $config) = @_; $config ||= {};

   my $class   = $config->{child_class} || blessed $self || $self;
   my $prefix  = delete $config->{class_prefix   } || 'Class::Usul';
   my $exclude = delete $config->{exclude_pattern} || '\A \z';
   my @paths   = @{ delete $config->{search_paths} || [] };
   my $finder  = Module::Pluggable::Object->new
      ( search_path => [ map { m{ \A :: }mx ? "${prefix}${_}" : $_ } @paths ],
        %{ $config } );
   my @plugins = grep { not m{ $exclude }mx }
                 sort { length $a <=> length $b } $finder->plugins;

   $self->load_component( $class, @plugins );

   return \@plugins;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TraitFor::LoadingClasses - Load classes at runtime

=head1 Version

This documents version v0.17.$Rev: 1 $ of
L<CatalystX::Usul::TraitFor::LoadingClasses>

=head1 Synopsis

   use Moo;

   with q(CatalystX::Usul::TraitFor::LoadingClasses);

=head1 Description

A L<Moo::Role> which load classes at runtime

=head1 Subroutines/Methods

=head2 build_subcomponents

   __PACKAGE__->build_subcomponents( $base_class );

Class method that allows us to define components that inherit from the base
class at runtime

=head2 load_component

   $self->load_component( $child, @parents );

Ensures that each component is loaded then fixes @ISA for the child so that
it inherits from the parents

=head2 setup_plugins

   @plugins = $self->setup_plugins( $class, $config_ref );

Load the given list of plugins and have the supplied class inherit from them.
Returns an array ref of available plugins

=head1 Configuration and Environment

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul::Constants>

=item L<Class::Usul::Functions>

=item L<Module::Pluggable::Object>

=item L<Moo::Role>

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

Copyright (c) 2014 Peter Flanigan. All rights reserved

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
