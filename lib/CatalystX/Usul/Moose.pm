# @(#)$Ident: Moose.pm 2013-06-23 00:39 pjf ;

package CatalystX::Usul::Moose;

use strict;
use warnings;
use feature ();
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );
use namespace::autoclean ();

use CatalystX::Usul::Constraints ();
use Import::Into;
#use Method::Signatures::Simple ();
use Moose ();
#use Moose::Autobox ();
use Moose::Util::TypeConstraints ();
use MooseX::AttributeShortcuts ();
use MooseX::Types::Moose ();
use MooseX::Types::Common::String ();
use MooseX::Types::Common::Numeric ();
use MooseX::Types::LoadableClass ();
# MooseX::Types::Parameterizable broken 0.08 RT#75119
#use MooseX::Types::Varchar ();
use Scalar::Util qw(blessed);

sub import {
   my ($self, @args) = @_;

   my $class = blessed $self || $self;
   my $opts  = @args && ref $args[ 0 ] eq q(HASH) ? shift @args : {};

   $opts->{also} ||= [ 'Moose', 'Moose::Util::TypeConstraints', @args ];
   $opts->{into} ||= caller;

   return _do_import( $class, $opts );
}

# Private methods

sub _do_import {
   my ($class, $opts) = @_; my $target = $opts->{into};

   my ($import, $unimport, $init_meta) = Moose::Exporter->build_import_methods
      ( into => $target, also => $opts->{also} || [] );

   feature->import( qw(state switch) );
   $opts->{no_autoclean} or namespace::autoclean->import( -cleanee => $target );
   $class->$import( { into => $target } );
   CatalystX::Usul::Constraints->import( { into => $target }, q(:all) );
   MooseX::AttributeShortcuts->import::into( $target );
#   Method::Signatures::Simple->import( into => $target );
#   Moose::Autobox->import( into => $target );
   MooseX::Types::Moose->import( { into => $target },
      MooseX::Types::Moose->type_names );
   MooseX::Types::Common::String->import( { into => $target },
      MooseX::Types::Common::String->type_names );
   MooseX::Types::Common::Numeric->import( { into => $target },
      MooseX::Types::Common::Numeric->type_names );
   MooseX::Types::LoadableClass->import( { into => $target },
      qw(LoadableClass LoadableRole) );
#   MooseX::Types::Varchar->import( { into => $target }, 'Varchar' );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Moose - Moose, the way I like it.

=head1 Version

This documents version v0.9.$Rev: 0 $

=head1 Synopsis

   use CatalystX::Usul::Moose;

=head1 Description

Applies L<Moose>, L<Moose::Util::TypeConstraints>,
L<namespace::autoclean>, etc to the class using it.

=head1 Subroutines/Methods

=head2 import

Imports into the calling packages namespace the selected packages exports

=head1 Configuration and Environment

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<bareword::filehandles>

=item L<feature>

=item L<namespace::autoclean>

=item L<multidimensional>

=item L<strict>

=item L<warnings>

=item L<Class::Usul::Constraints>

=item L<Import::Into>

=item L<Moose>

=item L<Moose::Util::TypeConstraints>

=item L<MooseX::AttributeShortcuts>

=item L<MooseX::Types::Moose>

=item L<MooseX::Types::Common::String>

=item L<MooseX::Types::Common::Numeric>

=item L<MooseX::Types::LoadableClass>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

t0m - Pasted his version of this, so I nicked it and adapted

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
