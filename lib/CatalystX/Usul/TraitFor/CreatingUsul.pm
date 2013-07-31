# @(#)$Id: CreatingUsul.pm 1319 2013-06-23 16:21:01Z pjf $

package CatalystX::Usul::TraitFor::CreatingUsul;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.8.%d', q$Rev: 1319 $ =~ /\d+/gmx );

use Moose::Role;
use Class::Usul;

requires q(setup_components);

before 'setup_components' => sub {
   my $class = shift;
   my $body  = $class->log->can( q(_body) ) ? $class->log->_body : undef;

   $class->log( $class->_get_usul->log ); $class->_recycle_old( $body );
   return;
};

# Private methods

sub _get_usul {
   my $app_class = shift; my $usul;

   $app_class->can( q(usul) ) and defined ($usul = $app_class->usul)
      and return $usul;

   $usul = Class::Usul->new_from_class( $app_class );

   $app_class->mk_classdata( q(usul), $usul );

   return $usul;
}

sub _recycle_old {
   my ($class, $body) = @_; my $buf = q(); $body or return;

   for (split m{ [\n] }mx, $body) {
      if (m{ \A \[debug\] \s+ }mx) {
         $buf and $class->log->debug( $buf ); $buf = q();
         s{ \A \[debug\] \s+ }{}mx;
      }

      $buf .= "${_}\n";
   }

   $buf and $class->log->debug( $buf );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TraitFor::CreatingUsul - Create an instance if Class::Usul

=head1 Version

0.8.$Revision: 1319 $

=head1 Synopsis

   package YourApp;

   use CatalystX::Usul::Moose;

   with qw(CatalystX::Usul::TraitFor::CreatingUsul);

=head1 Description

Creates an instance of L<Class::Usul> just before
L<setup components|Catalyst/setup_components> is called

=head1 Configuration and Environment

Requires the method C<setup_components>

=head1 Subroutines/Methods

=head2 _build_usul

Creates an instance of L<Class::Usul> which is stored as class data on
the I<usul> attribute of the application class. References to this
object are shared amongst the applications components by
L<CatalystX::Usul::TraitFor::BuildingUsul>

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul>

=item L<Moose::Role>

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
