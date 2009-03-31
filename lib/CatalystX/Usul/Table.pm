package CatalystX::Usul::Table;

# @(#)$Id: Table.pm 403 2009-03-28 04:09:04Z pjf $

use strict;
use warnings;
use parent qw(Class::Accessor::Fast);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 403 $ =~ /\d+/gmx );

__PACKAGE__->mk_accessors( qw(align class count flds hclass labels
                              sizes typelist values wrap) );

sub new {
   my ($self, @rest) = @_;

   my $args = $rest[0] && ref $rest[0] eq q(HASH) ? $rest[0] : { @rest };
   my $new  = bless { align  => {}, class    => undef,
                      count  => 0,  flds     => [],
                      hclass => {}, labels   => {},
                      sizes  => {}, typelist => {},
                      values => [], wrap     => {} }, ref $self || $self;

   for (grep { exists $new->{ $_ } } keys %{ $args }) {
      $new->$_( $args->{ $_ } );
   }

   return $new;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Table - Data structure for the table widget

=head1 Version

0.1.$Revision: 403 $

=head1 Synopsis

=head1 Description

Response class for the table widget in L<HTML::FormWidgets>

=head1 Subroutines/Methods

=head2 new

Create and return a new instance of this class

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Class::Accessor::Fast>

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
