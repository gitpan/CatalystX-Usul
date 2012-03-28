# @(#)$Id: Shells.pm 1139 2012-03-28 23:49:18Z pjf $

package CatalystX::Usul::Shells;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1139 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul);

__PACKAGE__->mk_accessors( qw(default path shells) );

sub new {
   my ($class, $app, $attrs) = @_;

   $attrs->{default} ||= q(/bin/ksh);
   $attrs->{path   } ||= q(/etc/shells);

   return $class->next::method( $app, $attrs );
}

sub retrieve {
   my $self = shift;
   my $new  = bless { default => $self->default }, ref $self || $self;

   $new->shells
      ( [ q(/bin/false),
          sort grep { $_ and '#' ne substr $_, 0, 1 and not m{ false }mx }
          $self->io( $self->path )->chomp->getlines ] );

   return $new;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Shells - Access the available shells list

=head1 Version

0.5.$Revision: 1139 $

=head1 Synopsis

   use CatalystX::Usul::Shells

   $model  = CatalystX::Usul::Shells->new( $attrs, $app );
   $shells = $model->retrieve;

=head1 Description

=head1 Subroutines/Methods

=head2 new

Constructor

=head2 retrieve

Returns the list of available shells by reading the contents of
F</etc/shells>. Adds I</bin/false> if it is not present

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
