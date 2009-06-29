# @(#)$Id: HTML.pm 576 2009-06-09 23:23:46Z pjf $

package CatalystX::Usul::View::HTML;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 576 $ =~ /\d+/gmx );
use parent qw(Catalyst::View::TT CatalystX::Usul::View);

use Class::C3;
use Encode;
use English qw(-no_match_vars);
use File::Find;
use Template::Stash;

my $NUL = q();
my $SEP = q(/);

__PACKAGE__->config( CATALYST_VAR       => q(c),
                     COMPILE_EXT        => q(.ttc),
                     PRE_CHOMP          => 1,
                     TRIM               => 1,
                     css                => q(presentation),
                     default_template   => q(layout),
                     form_sources       =>
                        [ qw(append bbar footer header hidden
                             menus quick_links sdata) ],
                     jscript            => q(behaviour),
                     jscript_path       => q(static/jscript),
                     target             => q(top),
                     template_extension => q(.tt), );

__PACKAGE__->mk_accessors( qw(css css_files default_template jscript
                              jscript_dir jscript_path
                              lang_dep_jsprefixs lang_dep_jscript
                              static_jscript target template_extension
                              templates) );

sub new {
   my ($self, $app, @rest) = @_; my $path;

   my $new = $self->next::method( $app, @rest );

   $new->css_files         ( {} );
   $new->lang_dep_jscript  ( {} );
   $new->lang_dep_jsprefixs( [] ) unless ($new->lang_dep_jsprefixs);
   $new->static_jscript    ( [] );
   $new->templates         ( {} );

   # Cache the CSS files with the colour- prefix from each available skin
   my $io = $new->io( $app->config->{skindir} );

   while ($path = $io->next) {
      if (-d $path->pathname
          and -f $self->catfile( $path->pathname, $new->css.q(.css) )) {
         @{ $new->css_files->{ $path->filename } }
            = grep { m{ \A colour- }mx }
              map  { $new->basename( $_ ) }
              glob $self->catfile( $path->pathname, q(*.css) );
      }
   }

   $io->close;

   # Cache the JS files in the static JS directory
   for $path (glob $self->catfile( $new->jscript_dir, q(*.js) )) {
      $path = $SEP.$new->jscript_path.$SEP.$new->basename( $path );
      push @{ $new->static_jscript }, $path;
   }

   # Cache the language dependant JS files
   for $path (glob $self->catfile( $self->catdir( $new->jscript_dir,
                                                  q(lang) ), q(*.js))) {
      $new->lang_dep_jscript->{ $new->basename( $path ) } = 1;
   }

   # Cache the per page custom templates
   my $extension = $new->template_extension;

   find( { no_chdir => 1,
           wanted   =>
              sub { $new->templates->{ $_ } = 1 if (m{ $extension \z }mx) } },
         $new->dynamic_templates );

   return $new;
}

sub bad_request {
   my ($self, $c, $verb, $msg) = @_; my $s = $c->stash;

   # Add a stock phrase to the user visible reason for failure
   my $button = $s->{buttons}->{ $c->action->{name}.q(.).$verb } || {};

   $msg = $button->{error}."\n".(lcfirst $msg) if ($button->{error});

   $c->model( q(Base) )->add_result( $msg );
   $s->{override} = 1;
   return 1;
}

sub deserialize {
   # Do nothing
}

sub fix_stash {
   my ($self, $c) = @_; my $s = $c->stash; my $e;
   my $extension  = $self->template_extension;

   if ($c->action->reverse) {
      # Load a per page custom template if one is defined
      my $path = $self->catfile( $self->dynamic_templates,
                                 split m{ $SEP }mx,
                                 $c->action->reverse ).$extension;

      if (exists $self->templates->{ $path }) {
         my $content = eval { $self->io( $path )->slurp };
         $content = $e->as_string if ($e = $self->catch);
         push @{ $s->{sdata}->{items} }, { content => $content };
      }
   }

   # Default the template if one is not already defined
   unless ($s->{template}) {
      $s->{template}
         = $self->catfile( $s->{skin}, $self->default_template.$extension );
   }

   if ($s->{target} = $self->target) {
      $c->res->headers->header( q(target) => $s->{target} );
   }

   $s->{content_type} .= q(; charset=).$s->{encoding} if ($s->{encoding});

   my $name = $c->action->name; my ($cfg, $text);

   if (exists $s->{rooms}->{ $name } and $cfg = $s->{rooms}->{ $name }) {
       $s->{description} = $text if ($text = $cfg->{tip     });
       $s->{keywords   } = $text if ($text = $cfg->{keywords});
   }

   $Template::Stash::SCALAR_OPS->{loc} = sub {
      my (undef, $msg, @rest) = @_; return $self->loc( $c, $msg, @rest );
   };

   return;
}

sub get_css {
   my ($self, $c) = @_;
   my @csss       = ();
   my $s          = $c->stash;
   my $skin       = $s->{skin};
   my $conf       = $c->config;
   my $skin_path  = $SEP.$conf->{skins}.$SEP.$skin.$SEP;
   my $path       = $self->catfile( $conf->{skindir},
                                    $skin, $conf->{default_css} );
   my $title;

   # TODO: Cache these to avoid the -f on each get request
   # Primary CSS file
   push @csss, $skin_path.$conf->{default_css} if (-f $path);

   # Add list of alternate CSS files
   for my $css (@{ $self->css_files->{ $skin } }) {
      $path = $skin_path.$css;
      push @csss, $path unless ($self->is_member( $path, @csss ));
   }

   my $rel = q(stylesheet); $s->{css} = [];

   # Fixup the stashed CSS files as either primary or alternate
   for my $css (@csss) {
      ($title = $self->basename( $css, qw(.css) )) =~ s{ \A colour- }{}mx;
      push @{ $s->{css} }, { href  => $c->uri_for( $css ),
                             rel   => $rel,
                             title => ucfirst $title };
      $rel = q(alternate stylesheet);
   }

   return;
}

sub get_jscript {
   my ($self, $c) = @_; my $s = $c->stash; my $conf = $c->config; my $path;

   # Stash the static JS loaded by every page
   @{ $s->{scripts} } = map { $c->uri_for( $_ ) } @{ $self->static_jscript };

   # Stash the language dependent JS files
   for my $file (map { $_.q(-).$s->{lang}.q(.js) }
                 @{ $self->lang_dep_jsprefixs }) {
      if (exists $self->lang_dep_jscript->{ $file }) {
         $path = join $SEP, $SEP.$self->jscript_path, q(lang), $file;
         push @{ $s->{scripts} }, $c->uri_for( $path );
      }
   }

   # Cache the "use case" JS for the selected skin
   $path = $self->catfile( $conf->{root}, $conf->{skins},
                           $s->{skin}, $self->jscript.q(.js) );

   # TODO: Cache this to avoid -f on each get request
   if (-f $path) {
      $path = join $SEP, $SEP.$conf->{skins}, $s->{skin}, $self->jscript.'.js';
      push @{ $s->{scripts} }, $c->uri_for( $path );
   }

   # Set the onload event handler
   $s->{onload} .= "behaviour.state.setState('".($s->{firstfld} || $NUL)."')";
   return;
}

sub get_verb {
   my ($self, $s, $req) = @_; my $verb = lc $req->param( q(_method) );

   if ($verb) {
      # To be sure we'll only do this once
      $s->{ '_method'   } = delete $req->params->{ '_method'   };
      $s->{ '_method.x' } = delete $req->params->{ '_method.x' };
      $s->{ '_method.y' } = delete $req->params->{ '_method.y' };
   }

   return $verb;
}

sub not_implemented {
   my ($self, @rest) = @_; return $self->bad_request( @rest );
}

sub process {
   my ($self, $c) = @_; my $s = $c->stash; my $enc;

   $self->fix_stash    ( $c                      );
   $self->build_widgets( $c, $self->form_sources );
   $self->get_css      ( $c                      );
   $self->get_jscript  ( $c                      ) if ($s->{dhtml});

   # Do the template thing
   if ($self->next::method( $c )) { $c->fillform() if ($s->{override}) }
   else { $c->res->body( $c->error() ) }

   # Encode the body of the page
   $c->res->body( encode( $enc, $c->res->body ) ) if ($enc = $s->{encoding});
   $c->res->content_type( $s->{content_type} );
   $c->res->header( Vary => q(Content-Type) );
   return 1;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::View::HTML - Render a page of HTML or XHTML

=head1 Version

0.3.$Revision: 576 $

=head1 Synopsis

   use base qw(CatalystX::Usul::View::HTML);

=head1 Description

Generate a page of HTML or XHTML using Template Toolkit and the contents
of the stash

=head1 Subroutines/Methods

=head2 new

Looks up and caches CSS, Javascript and template files rather than test for
their existence with each request

=head2 bad_request

Adds the provided error message to the result div after prepending a stock
phrase specific to the failed action

=head2 deserialize

Dummy method, does nothing in this view

=head2 fix_stash

Adds some extra entries to the stash

=over 3

=item template

Detects and loads a custom template if one has been created for this page

=item target

Sets the target for this page in the headers

=back

=head2 get_css

For the selected skin sets up the data for the main CSS link and the
alternate CSS links if any exist

=head2 get_jscript

For the selected skin adds it's Javascript file to the list files that
will be linked into the page

=head2 get_verb

Returns the I<_method> parameter from the query which is used by the
action class to lookup the action to forward to. Called from the
C<begin> method once the current view has been determined from the
request content type

=head2 not_implemented

Proxy for L</bad_request>

=head2 process

Calls L</fix_stash>, C<build_widgets>, L</get_css> and L</get_jscript>
before calling L<Template::Toolkit> via the parent class. Will also
call C<FillInForm> if the I<override> attribute was set in the stash
to indicate an error.  Encodes the response body using the currently
selected encoding

C<build_widgets> in L<CatalystX::Usul::View> is passed those parts of
the stash that might contain widget definitions which it renders as
HTML or XHTML

=head1 Diagnostics

None

=head1 Configuration and Environment

=over 3

=item css

Basename of the file containing the CSS for the generated
page. Defaults to B<presentation>

=item jscript

Basename of the file containing the Javascript used to modify the
default behaviour of the browser. Defaults to B<behaviour>

=item default_template

Basename of the TT file used to generate the page. Defaults to B<layout>

=item template_extension

Templage file extension. Defaults to B<tt>

=back

=head1 Dependencies

=over 3

=item L<Catalyst::View::TT>

=item L<CatalystX::Usul::View>

=item L<Encode>

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
