# @(#)$Id: Base.pm 1095 2012-01-11 16:27:56Z pjf $

package CatalystX::Usul::Base;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1095 $ =~ /\d+/gmx );
use parent qw(Class::Accessor::Grouped);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Exception;
use CatalystX::Usul::Functions qw(data_dumper throw);
use Class::MOP;
use Scalar::Util qw(blessed);
use TryCatch;

sub dumper {
   my $self = shift; return data_dumper( @_ ); # Damm handy for development
}

sub ensure_class_loaded {
   my ($self, $class, $opts) = @_; $opts ||= {};

   my $package_defined = sub { Class::MOP::is_class_loaded( $class ) };

   not $opts->{ignore_loaded} and $package_defined->() and return TRUE;

   try { Class::MOP::load_class( $class ) } catch ($e) { throw $e }

   $package_defined->()
      or throw error => 'Class [_1] loaded but package undefined',
               args  => [ $class ];

   return TRUE;
}

sub exception_class {
   return EXCEPTION_CLASS;
}

sub mk_accessors {
   return shift->mk_group_accessors( q(simple), @_ );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Base - Base class utility methods

=head1 Version

0.4.$Revision: 1095 $

=head1 Synopsis

   package YourBaseClass;

   use parent qw(CatalystX::Usul::Base);

   __PACKAGE__->mk_accessors( qw(list of accessor names) );

=head1 Description

Provides dynamic class loading method and exposes the exception handling
methods in L<CatalystX::Usul::Exception>. Also provides accessor/mutator
creation method which it inherits from L<Class::Accessor::Grouped>

=head1 Subroutines/Methods

=head2 dumper

   $self->udump( $object );

Calls L<dumper|CatalystX::Usul::Functions/dumper> for dumping objects
for inspection

=head2 ensure_class_loaded

   $self->ensure_class_loaded( $some_class );

Require the requested class, throw an error if it doesn't load

=head2 exception_class

   $self->exception_class;

Return the exception class used to throw errors. Wraps the constant
C<EXCEPTION_CLASS> in a method so we can use it for inversion of control

=head2 mk_accessors

   $self->mk_accessors( @fieldspec );

Create accessors methods like L<Class::Accessor::Fast> but using
L<Class::Accessor::Grouped>

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Constants>

=item L<CatalystX::Usul::Exception>

=item L<Class::Accessor::Grouped>

=item L<Class::MOP>

=item L<TryCatch>

=back

=head1 Incompatibilities

None known

=head1 Bugs and Limitations

There are no known bugs in this module.  Please report problems to the
address below.  Patches are welcome

=head1 Author

Peter Flanigan, C<< <Support at RoxSoft.co.uk> >>

=head1 License and Copyright

Copyright (c) 2011 Peter Flanigan. All rights reserved

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
