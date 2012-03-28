# @(#)$Id: HTML.pm 1097 2012-01-28 23:31:29Z pjf $

package CatalystX::Usul::View::HTML;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1097 $ =~ /\d+/gmx );
use parent qw(Catalyst::View::TT CatalystX::Usul::View);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(exception is_member);
use Encode;
use English qw(-no_match_vars);
use File::Find;
use HTML::FillInForm;
use MRO::Compat;
use Template::Stash;
use TryCatch;

__PACKAGE__->config( CATALYST_VAR       => q(c),
                     COMPILE_EXT        => q(.ttc),
                     PRE_CHOMP          => 1,
                     TRIM               => 1,
                     default_css        => q(presentation),
                     default_jscript    => q(behaviour),
                     default_template   => q(layout),
                     font_extension     => q(.typeface.js),
                     fonts_dir          => q(fonts),
                     form_sources       =>
                        [ qw(append button footer header hidden
                             menus quick_links sdata sidebar) ],
                     lang_dir           => q(lang),
                     jscript_path       => q(static/jscript),
                     target             => q(top),
                     template_extension => q(.tt), );

__PACKAGE__->mk_accessors( qw(css_paths default_css default_jscript
                              default_template font_extension
                              fonts_dir fonts_jscript js_for_skin
                              jscript_dir jscript_path
                              lang_dep_jsprefixs lang_dep_jscript
                              lang_dir optional_js static_js target
                              template_extension templates) );

sub COMPONENT {
   my ($class, $app, @rest) = @_;

   my $new = $class->next::method( $app, @rest );

   $new->css_paths         ( {} );
   $new->fonts_jscript     ( {} );
   $new->js_for_skin       ( {} );
   $new->lang_dep_jscript  ( {} );
   $new->lang_dep_jsprefixs( [] ) unless ($new->lang_dep_jsprefixs);
   $new->optional_js       ( [] );
   $new->static_js         ( [] );
   $new->templates         ( {} );

   # Cache the CSS files with the colour- prefix from each available skin
   my $config     = $app->config;
   my $stylesheet = $config->{stylesheet};
   my $css_file   = $new->default_css.q(.css);
   my $js_file    = $new->default_jscript.q(.js);
   my $skin_dir   = $new->io( $config->{skindir} );

   for my $path ($skin_dir->all_dirs) {
      my $skin_name = $path->filename;
      my $css_path  = $skin_dir->catfile( $skin_name, $css_file );

      ($path->is_dir and $css_path->is_file) or next;

      my $css_paths = $new->css_paths->{ $skin_name } = [];
      my $skin_path = join SEP, NUL, $config->{skins}, $skin_name, NUL;

      @{ $css_paths } = map  { $skin_path.$_ }
                        grep { not m{ \A $stylesheet }mx }
                        grep { m{ \A colour- }mx }
                        map  { $new->basename( $_ ) }
                        glob $skin_dir->catfile( $skin_name, q(*.css) );

      $skin_dir->catfile( $skin_name, $stylesheet )->exists
         and unshift @{ $css_paths }, $skin_path.$stylesheet;

      $skin_dir->catfile( $skin_name, $js_file )->exists
         and $new->js_for_skin->{ $skin_name } = $skin_path.$js_file;
   }

   # Cache the JS files in the static JS directory
   for my $file ($new->_list_jscript( $new->jscript_dir )) {
      my ($order)   = $file =~ m{ \A (\d+) }mx;
      my $array_ref = $order && $order < 50
                    ? $new->static_js : $new->optional_js;

      push @{ $array_ref }, SEP.$new->jscript_path.SEP.$file;
   }

   # Cache the language dependant JS files
   my $dir = $new->catdir( $new->jscript_dir, $new->lang_dir );

   for my $file ($new->_list_jscript( $dir )) {
      $new->lang_dep_jscript->{ $file } = TRUE;
   }

   # Cache the font replacement JS files. Fugly
   my $suffix = $new->font_extension;
   my $wanted = sub {
      m{ \Q$suffix\E \z }mx and $new->fonts_jscript->{
         $new->basename( $_, $suffix ) } =
            $new->catfile( $new->basename( $new->dirname( $_ ) ),
                           $new->basename( $_ ) ) };

   $dir = $new->catdir( $new->jscript_dir, $new->fonts_dir );
   find( { no_chdir => TRUE, wanted => $wanted }, $dir );

   # Cache the per page custom templates
   $suffix = $new->template_extension;
   $wanted = sub { m{ $suffix \z }mx and $new->templates->{ $_ } = TRUE };
   find( { no_chdir => TRUE, wanted => $wanted }, $new->template_dir );

   return $new;
}

sub bad_request {
   my ($self, $c, $verb, $msg, $status) = @_;

   my $s = $c->stash; $verb ||= NUL; $msg ||= 'unknown'; $status ||= 400;

   # Add a stock phrase to the user visible reason for failure
   my $buttons = $s->{buttons} || {};
   my $button  = $buttons->{ $c->action->{name}.q(.).$verb } || {};
   my $err     = $button->{error} || NUL;

   $c->model( q(Base) )->add_result( $err ? $err."\n".(lcfirst $msg) : $msg );

   return $s->{override} = TRUE;
}

sub deserialize {
   # Do nothing
}

sub get_verb {
   my ($self, $c) = @_; my $s = $c->stash; my $req = $c->req; my $verb;

   if ($verb = lc $req->params->{_method}) {
      # To be sure we'll only do this once
      $s->{ '_method'   } = delete $req->params->{ '_method'   };
      $s->{ '_method.x' } = delete $req->params->{ '_method.x' };
      $s->{ '_method.y' } = delete $req->params->{ '_method.y' };
   }
   elsif (lc $req->method eq q(get)) { $verb = q(get) }

   return $verb;
}

sub process {
   my ($self, $c) = @_; my $s = $c->stash; my $enc = $s->{encoding};

   $self->_fix_stash    ( $c );
   $self->_build_widgets( $c, { data => $self->_read_form_sources( $c ) } );
   $self->_setup_css    ( $c );
   $self->_setup_jscript( $c );

   $enc and $s->{content_type} .= q(; charset=).$enc;

   # Do the template thing
   if ($self->next::method( $c )) { $s->{override} and $self->_fillform( $c ) }
   else { $c->res->body( $c->error() ) }

   # Encode the body of the page
   $enc and $c->res->body( encode( $enc, $c->res->body ) );

   $c->res->content_type( $s->{content_type} );
   $c->res->header( Vary => q(Content-Type) );
   return TRUE;
}

# Private methods

sub _fillform {
   my ($self, $c) = @_;

   $c->response->output
      ( HTML::FillInForm->new->fill
        ( scalarref => \$c->res->{body}, fdat => $c->req->parameters, ) );

   return;
}

sub _fix_stash {
   my ($self, $c) = @_; my $s = $c->stash;

   my $action = $c->action; my $extension = $self->template_extension;

   if ($action->name) {
      # Load a per page custom template if one is defined
      my $suffix = q(_).$s->{lang}.$extension;
      my @parts  = ( $action->namespace || q(root), $action->name );
      my $path   = $self->catfile( $self->template_dir, @parts );
      my $content;

      if (exists $self->templates->{ $path.$suffix }) {
         try        { $content = $self->io( $path.$suffix )->slurp }
         catch ($e) { $content = exception( $e )->as_string }
      }
      elsif (exists $self->templates->{ $path.$extension }) {
         try        { $content = $self->io( $path.$extension )->slurp }
         catch ($e) { $content = exception( $e )->as_string }
      }

      $content and unshift @{ $s->{sdata}->{items} },
         { class => $action->name, content => $content };
   }

   # Default the template if one is not already defined
   $s->{js_object}   = $self->js_object;
   $s->{skin     } ||= q(default);
   $s->{template } or $s->{template}
      = $self->catfile( $s->{skin}, $self->default_template.$extension );
   $s->{target   }   = $self->target
      and $c->res->headers->header( q(target) => $s->{target} );

   $Template::Stash::SCALAR_OPS->{loc} = sub { shift; $self->loc( $s, @_ ) };

   return;
}

sub _list_jscript {
   my ($self, $dir) = @_;

   return map { $self->basename( $_ ) } glob $self->catfile( $dir, q(*.js) );
}

sub _setup_css {
   my ($self, $c) = @_; my $s = $c->stash;

   my $rel = q(stylesheet); my $skin = $s->{skin}; $s->{css} = [];

   # Fixup the stashed CSS files as either primary or alternate
   for my $css (@{ $self->css_paths->{ $skin } }) {
      (my $title = $self->basename( $css, qw(.css) )) =~ s{ \A colour- }{}mx;

      push @{ $s->{css} }, { href  => $c->uri_for( $css ),
                             title => ucfirst $title,
                             rel   => $rel };
      $rel = q(alternate stylesheet);
   }

   return;
}

sub _setup_jscript {
   my ($self, $c) = @_; my $s = $c->stash; $s->{dhtml} or return;

   my $conf = $c->config; my $path;

   # Stash the static JS loaded by every page. Batch 0
   $s->{scripts} = [ map { [ 0, $c->uri_for( $_ ) ] }
                        @{ $self->static_js || [] } ];

   # Stash the optional JS. Batch 0
   push   @{ $s->{scripts} },
      map  { [ 0, $c->uri_for( $_ ) ] }
      grep { (my $x = $self->basename( $_ )) =~ s{ \A (\d+) }{}mx;
             is_member $x, $s->{optional_js} }
          @{ $self->optional_js || [] };

   # Stash the language dependent JS files. Batch 1
   push   @{ $s->{scripts} },
      map  { [ 1, $c->uri_for( $_ ) ] }
      map  { join SEP, SEP.$self->jscript_path, $self->lang_dir, $_ }
      grep { exists $self->lang_dep_jscript->{ $_ } }
      map  { $_.q(-).$s->{lang}.q(.js) }
      grep { is_member $_.q(.js), $s->{optional_js} }
          @{ $self->lang_dep_jsprefixs || [] };

   # Stash the font replacement JS files. Batch 1
   push   @{ $s->{scripts} },
      map  { [ 1, $c->uri_for( $_ ) ] }
      map  { join SEP, SEP.$self->jscript_path, $self->fonts_dir,
                       $self->fonts_jscript->{ $_ } }
      grep { $self->fonts_jscript->{ $_ } }
          @{ $s->{fonts} || [] };

   # Stash the "use case" JS for the selected skin. Batch 2
   exists $self->js_for_skin->{ $s->{skin} } and push @{ $s->{scripts} },
      [ 2, $c->uri_for( $self->js_for_skin->{ $s->{skin} }) ];

   # If true generate literal js to async download all the js files in batches
   $path = $conf->{async_js} and
      $s->{async_js} = $c->uri_for( join SEP, SEP.$self->jscript_path, $path );

   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::View::HTML - Render a page of HTML or XHTML

=head1 Version

0.4.$Revision: 1097 $

=head1 Synopsis

   use base qw(CatalystX::Usul::View::HTML);

=head1 Description

Generate a page of HTML or XHTML using Template Toolkit and the contents
of the stash

=head1 Subroutines/Methods

=head2 COMPONENT

Looks up and caches CSS, Javascript and template files rather than test for
their existence with each request

=head2 bad_request

Adds the provided error message to the result div after prepending a stock
phrase specific to the failed action

=head2 deserialize

Dummy method, does nothing in this view

=head2 get_verb

Returns the I<_method> parameter from the query which is used by the
action class to lookup the action to forward to. Called from the
C<begin> method once the current view has been determined from the
request content type

=head2 not_implemented

Proxy for L</bad_request>

=head2 process

Calls L</_fix_stash>, C<_build_widgets>, L</_setup_css> and L</_setup_jscript>
before calling L<Template::Toolkit> via the parent class. Will also
call L</_fillform> if the I<override> attribute was set in the stash
to indicate an error.  Encodes the response body using the currently
selected encoding

C<_build_widgets> in L<CatalystX::Usul::View> is passed those parts of
the stash that might contain widget definitions which it renders as
HTML or XHTML

=head1 Private Methods

=head2 _fillform

Uses L<HTML::FillInForm> to fill in the response body from the request
parameters

=head2 _fix_stash

Adds some extra entries to the stash

=over 3

=item template

Detects and loads a custom template if one has been created for this page

=item target

Sets the target for this page in the headers

=back

=head2 _setup_css

For the selected skin sets up the data for the main CSS link and the
alternate CSS links if any exist

=head2 _setup_jscript

For the selected skin adds it's Javascript file to the list files that
will be linked into the page

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
