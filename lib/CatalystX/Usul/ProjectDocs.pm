package CatalystX::Usul::ProjectDocs;

# @(#)$Id: ProjectDocs.pm 403 2009-03-28 04:09:04Z pjf $

use strict;
use warnings;
use parent qw(Pod::ProjectDocs);
use Text::Tabs;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 403 $ =~ /\d+/gmx );

my %SCHEME =
   ( Variable_Scalar   => [ '<font color="#CC6600">', '</font>' ],
     Variable_Array    => [ '<font color="#FFCC00">', '</font>' ],
     Variable_Hash     => [ '<font color="#990099">', '</font>' ],
     Variable_Typeglob => [ '<font color="#000000">', '</font>' ],
     Subroutine        => [ '<font color="#339933">', '</font>' ],
     Quote             => [ '<font color="#000000">', '</font>' ],
     String            => [ '<font color="#3399FF">', '</font>' ],
     Comment_Normal    => [ '<font color="#ff0000"><i>', '</i></font>' ],
     Comment_POD       => [ '<font color="#ff9999">', '</font>' ],
     Bareword          => [ '<font color="#000000">', '</font>' ],
     Package           => [ '<font color="#000000">', '</font>' ],
     Number            => [ '<font color="#003333">', '</font>' ],
     Operator          => [ '<font color="#999999">', '</font>' ],
     Symbol            => [ '<font color="#000000">', '</font>' ],
     Keyword           => [ '<font color="#0000ff"><b>', '</b></font>' ],
     Builtin_Operator  => [ '<font color="#000000">', '</font>' ],
     Builtin_Function  => [ '<font color="#000000">', '</font>' ],
     Character         => [ '<font color="#3399FF"><b>', '</b></font>' ],
     Directive         => [ '<font color="#000000"><i><b>',
                           '</b></i></font>' ],
     Label             => [ '<font color="#000000">', '</font>' ],
     Line              => [ '<font color="#000000">', '</font>' ], );

BEGIN {
    our $HIGHLIGHTER;
    eval {
        require Syntax::Highlight::Perl;
        $HIGHLIGHTER = Syntax::Highlight::Perl->new;
    };
    no warnings q(redefine); ## no critic
    *Pod::ProjectDocs::Parser::highlighten = $HIGHLIGHTER ? sub {
       my ($self, $type, $text) = @_;

       $tabstop = 3;
       $HIGHLIGHTER->set_format( \%SCHEME );
       $HIGHLIGHTER->define_substitution( q(<) => q(&lt;),
                                          q(>) => q(&gt;),
                                          q(&) => q(&amp;) );

       return $HIGHLIGHTER->format_string( expand( $text ) );
    } : sub { return $_[2] };
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::ProjectDocs - Generates CPAN like pod pages

=head1 Version

0.1.$Revision: 403 $

=head1 Synopsis

   use CatalystX::Usul::ProjectDocs;

   my $pd = CatalystX::Usul::ProjectDocs->new( outroot => $htmldir,
                                               libroot => $libroot,
                                               title   => $meta->name,
                                               desc    => $meta->abstract,
                                               lang    => q(en), );

   $pd->gen();

=head1 Description

Inherits from L<Pod::ProjectDocs> but replaces
L<Syntax::Highlight::Universal> with L<Syntax::Highlight::Perl>

=head1 Subroutines/Methods

None

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Pod::ProjectDocs>

=item L<Text::Tabs>

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