# @(#)Ident: ;

package CatalystX::Usul::ProjectDocs;

use strict;
use version; our $VERSION = qv( sprintf '0.16.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use Class::Null;
use CatalystX::Usul::Constants;
use English qw(-no_match_vars);
use File::Copy;
use Text::Tabs;

has 'docs_class' => is => 'lazy', isa => ClassName;

has '_args'      => is => 'ro',   isa => HashRef, default => sub { {} };

around 'BUILDARGS' => sub {
   my ($next, $self, @args) = @_; return { _args => $self->$next( @args ) };
};

sub gen {
   my $self = shift; my $css = delete $self->_args->{cssfile};

   $self->docs_class->new( %{ $self->_args } )->gen;

   $css and -f $css and copy( $css, $self->_args->{outroot} );

   return;
}

# Private methods

sub _build_docs_class {
   eval {
      require PPI;
      require PPI::HTML;
      require Pod::ProjectDocs;

      my $highlight = PPI::HTML->new( line_numbers => 1 );

      no warnings q(redefine); ## no critic

      *Pod::ProjectDocs::Parser::PerlPod::highlighten = sub {
         my ($self, $type, $text) = @_; $tabstop = 3; # Text::Tabs

         $text = expand( $text );

         return $highlight->html( PPI::Document->new( \$text ) );
      };
   };

   $EVAL_ERROR or return q(Pod::ProjectDocs); $EVAL_ERROR = undef;

   eval {
      require Pod::ProjectDocs;
      require Syntax::Highlight::Perl;

      my $shp    = Syntax::Highlight::Perl->new;
      my %scheme =
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

      $shp->set_format( \%scheme );
      $shp->define_substitution( q(<) => q(&lt;),
                                 q(>) => q(&gt;),
                                 q(&) => q(&amp;) );

      no warnings q(redefine); ## no critic

      *Pod::ProjectDocs::Parser::PerlPod::highlighten = sub {
         my ($self, $type, $text) = @_; $tabstop = 3; # Text::Tabs

         return $shp->format_string( expand( $text ) );
      };
   };

   $EVAL_ERROR or return q(Pod::ProjectDocs); $EVAL_ERROR = undef;

   eval {
      require Pod::ProjectDocs;
   };

   return $EVAL_ERROR ? q(Class::Null) : q(Pod::ProjectDocs);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::ProjectDocs - Generates CPAN like pod pages

=head1 Version

Describes v0.16.$Rev: 1 $

=head1 Synopsis

   use CatalystX::Usul::ProjectDocs;

   my $pd = CatalystX::Usul::ProjectDocs->new( cssfile => $css,
                                               desc    => $meta->abstract,
                                               lang    => q(en),
                                               libroot => $libroot,
                                               outroot => $htmldir,
                                               title   => $meta->name, );

   $pd->gen();

=head1 Description

Inherits from L<Pod::ProjectDocs> but replaces
L<Syntax::Highlight::Universal> with L<Syntax::Highlight::Perl> if
it is available

=head1 Subroutines/Methods

=head2 gen

Proxy for L<gen|Pod::ProjectDocs/gen>. If the C<css> file exists copies this
over the one created by L<Pod::ProjectDocs>

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Pod::ProjectDocs>

=item L<PPI>

=item L<PPI::HTML>

=item L<Syntax::Highlight::Perl>

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

Copyright (c) 2010 Peter Flanigan. All rights reserved

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
