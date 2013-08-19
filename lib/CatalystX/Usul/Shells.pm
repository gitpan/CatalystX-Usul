# @(#)Ident: ;

package CatalystX::Usul::Shells;

use strict;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Constraints qw(File);
use File::Spec::Functions        qw(catfile);

has 'default' => is => 'ro', isa => File, coerce => TRUE,
   lazy       => TRUE,   builder => '_build_default';

has 'path'    => is => 'ro', isa => File, coerce => TRUE,
   default    => sub { [ NUL, qw(etc shells) ] };

has 'shells'  => is => 'ro', isa => ArrayRef, builder => '_build_shells',
   lazy       => TRUE;

sub _build_default {
   my $file = $ENV{SHELL}; -f $file and return $file;

   $file = catfile( NUL, qw(bin ksh) ); -f $file and return $file;

   $file = catfile( NUL, qw(bin bash) ); -f $file and return $file;

   return catfile( NUL, qw(bin sh) );
}

sub _build_shells {
   my $self = shift;

   return [ catfile( NUL, qw(bin false) ),
            sort grep { $_ and '#' ne substr $_, 0, 1 and not m{ false }mx }
            $self->path->chomp->getlines ]
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Shells - Access the available shells list

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   use CatalystX::Usul::Shells

   $shells_object  = CatalystX::Usul::Shells->new( $attrs );

=head1 Description

Provides access to the operating systems list of available shells. Used by
the user object for account creation

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item default

File path which defaults to the first available from; the
environment variable I<SHELL>, F</bin/ksh>, F</bin/bash>, or F</bin/sh>

=item path

File path which defaults to F</etc/shells>

=item shells

Array ref of shells defined in F</etc/shells>, sorted with F</bin/false>
return first

=back

=head1 Subroutines/Methods

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Moose>

=item L<CatalystX::Usul::Constraints>

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
