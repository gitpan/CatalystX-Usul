# @(#)$Ident: HTML.pm 2013-08-19 19:06 pjf ;

package CatalystX::Usul::View::HTML;

use strict;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions   qw(exception is_member);
use Catalyst::View::TT;
use Encode;
use English                      qw(-no_match_vars);
use File::Basename               qw(basename dirname);
use CatalystX::Usul::Constraints qw(Directory);
use File::DataClass::IO;
use File::Find;
use File::Spec::Functions        qw(catdir catfile);
use HTML::FillInForm;
use TryCatch;

extends q(CatalystX::Usul::View);

__PACKAGE__->config( CATALYST_VAR => q(c),
                     COMPILE_EXT  => q(.ttc),
                     PRE_CHOMP    => 1,
                     TRIM         => 1, );

has 'css_paths'          => is => 'ro',   isa => HashRef, default => sub { {} };

has 'default_css'        => is => 'ro',   isa => NonEmptySimpleStr,
   default               => q(presentation);

has 'default_jscript'    => is => 'ro',   isa => NonEmptySimpleStr,
   default               => q(behaviour);

has 'default_template'   => is => 'ro',   isa => NonEmptySimpleStr,
   default               => q(layout);

has 'font_extension'     => is => 'ro',   isa => NonEmptySimpleStr,
   default               => q(.typeface.js);

has 'fonts_dir'          => is => 'ro',   isa => NonEmptySimpleStr,
   default               => q(fonts);

has 'fonts_jscript'      => is => 'ro',   isa => HashRef, default => sub { {} };

has '+form_sources'      => default => sub {
   [ qw(append button footer header hidden menus quick_links sdata sidebar) ] };

has 'js_for_skin'        => is => 'ro',   isa => HashRef, default => sub { {} };

has 'jscript_dir'        => is => 'ro',   isa => Directory, coerce => TRUE,
   required              => TRUE;

has 'jscript_path'       => is => 'ro',   isa => NonEmptySimpleStr,
   default               => q(static/jscript);

has 'lang_dep_jsprefixs' => is => 'ro',   isa => ArrayRef,
   default               => sub { [] };

has 'lang_dep_jscript'   => is => 'ro',   isa => HashRef, default => sub { {} };

has 'lang_dir'           => is => 'ro',   isa => NonEmptySimpleStr,
   default               => q(lang);

has 'optional_js'        => is => 'ro',   isa => ArrayRef,
   default               => sub { [] };

has 'static_js'          => is => 'ro',   isa => ArrayRef,
   default               => sub { [] };

has 'target'             => is => 'ro',   isa => NonEmptySimpleStr,
   default               => q(top);

has 'template_extension' => is => 'ro',   isa => NonEmptySimpleStr,
   default               => q(.tt);

has 'templates'          => is => 'ro',   isa => HashRef, default => sub { {} };

has 'view_tt'            => is => 'lazy', isa => Object;

sub COMPONENT {
   my ($class, $app, @rest) = @_;

   my $self       = $class->next::method( $app, @rest );
   my $ac         = $app->config;
   my $stylesheet = $ac->{stylesheet};
   my $css_file   = $self->default_css.q(.css);
   my $js_file    = $self->default_jscript.q(.js);
   my $skin_dir   = io( $ac->{skindir} );

   # Cache the CSS files with the colour- prefix from each available skin
   for my $path ($skin_dir->all_dirs) {
      my $skin_name = $path->filename;
      my $css_path  = $skin_dir->catfile( $skin_name, $css_file );

      ($path->is_dir and $css_path->is_file) or next;

      my $css_paths = $self->css_paths->{ $skin_name } = [];
      my $skin_path = join SEP, NUL, $ac->{skins}, $skin_name, NUL;

      @{ $css_paths } = map  { $skin_path.$_ }
                        grep { not m{ \A $stylesheet }mx }
                        grep { m{ \A colour- }mx }
                        map  { basename( $_ ) }
                        glob $skin_dir->catfile( $skin_name, q(*.css) );

      $skin_dir->catfile( $skin_name, $stylesheet )->exists
         and unshift @{ $css_paths }, $skin_path.$stylesheet;

      $skin_dir->catfile( $skin_name, $js_file )->exists
         and $self->js_for_skin->{ $skin_name } = $skin_path.$js_file;
   }

   # Cache the JS files in the static JS directory
   for my $file (__list_jscript( $self->jscript_dir )) {
      my ($order)   = $file =~ m{ \A (\d+) }mx;
      my $array_ref = $order && $order < 50
                    ? $self->static_js : $self->optional_js;

      push @{ $array_ref }, SEP.$self->jscript_path.SEP.$file;
   }

   # Cache the language dependant JS files
   my $dir = catdir( $self->jscript_dir, $self->lang_dir );

   for my $file (__list_jscript( $dir )) {
      $self->lang_dep_jscript->{ $file } = TRUE;
   }

   # Cache the font replacement JS files. Fugly
   my $suffix = $self->font_extension;
   my $wanted = sub {
      m{ \Q$suffix\E \z }mx
         and $self->fonts_jscript->{ basename( $_, $suffix ) }
            = catfile( basename( dirname( $_ ) ), basename( $_ ) ) };

   $dir = catdir( $self->jscript_dir, $self->fonts_dir );
   -d $dir and find( { no_chdir => TRUE, wanted => $wanted }, $dir );

   # Cache the per page custom templates
   $suffix = $self->template_extension;
   $wanted = sub { m{ $suffix \z }mx and $self->templates->{ $_ } = TRUE };
   find( { no_chdir => TRUE, wanted => $wanted }, $self->template_dir );

   return $self;
}

sub bad_request {
   my ($self, $c, $verb, $msg, $status) = @_;

   my $s = $c->stash; $verb ||= NUL; $msg ||= 'unknown'; $status ||= 400;

   # Add a stock phrase to the user visible reason for failure
   my $buttons = $s->{buttons} || {};
   my $button  = $buttons->{ $c->action->{name}.q(.).$verb } || {};
   my $err     = $button->{error} || NUL;

   $c->model( q(Config) )->add_result( $err ? $err."\n".(lcfirst $msg) : $msg );

   return $s->{override} = TRUE;
}

sub deserialize {
   # Do nothing
}

sub get_verb {
   my ($self, $c) = @_; my $s = $c->stash; my $req = $c->req; my $verb;

   if ($verb = lc( $req->params->{_method} || NUL)) {
      # To be sure we'll only do this once
      $s->{ '_method'   } = delete $req->params->{ '_method'   };
      $s->{ '_method.x' } = delete $req->params->{ '_method.x' };
      $s->{ '_method.y' } = delete $req->params->{ '_method.y' };
   }
   elsif (lc $req->method eq q(get)) { $verb = q(get) }

   return $verb;
}

sub process {
   my ($self, $c) = @_; my $s = $c->stash; my $enc = $self->encoding;

   $self->_fix_stash    ( $c );
   $self->_build_widgets( $c, { data => $self->read_form_sources( $c ) } );
   $self->_setup_css    ( $c );
   $self->_setup_jscript( $c );

   $enc and $s->{content_type} .= "; charset=${enc}";

   if ($self->view_tt->process( $c )) { # Do the template thing
      $s->{override} and $self->_fillform( $c );
   }
   else { $c->res->body( $c->error() ) }

   # Encode the body of the page
   $enc and $c->res->body( encode( $enc, $c->res->body ) );

   $c->res->content_type( $s->{content_type} );
   $c->res->header( Vary => q(Content-Type) );
   return TRUE;
}

# Private methods

sub _build_view_tt {
   my $self = shift; my $class = 'Catalyst::View::TT';

   $class->meta->add_method( loc => sub {
      my (undef, $c, @rest) = @_; $self->loc( $c->stash, @rest ) } );

   my $attr = { %{ $self } }; $attr->{expose_methods} ||= [];

   push @{ $attr->{expose_methods} }, q(loc);

   return $class->new( $self->app_class, $attr );
}

sub _fillform {
   my ($self, $c) = @_;

   $c->response->output
      ( HTML::FillInForm->new->fill
        ( scalarref => \$c->res->{body}, fdat => $c->req->parameters, ) );

   return;
}

sub _fix_stash {
   my ($self, $c) = @_; my $s = $c->stash;

   my $action = $c->action; my $extn = $self->template_extension;

   if ($action->name) {
      # Load a per page custom template if one is defined
      my $suffix = q(_).($s->{language} || LANG).$extn;
      my @parts  = ( $action->namespace || q(root), $action->name );
      my $path   = catfile( $self->template_dir, @parts );
      my $content;

      if (exists $self->templates->{ $path.$suffix }) {
         try        { $content = io( $path.$suffix )->slurp }
         catch ($e) { $content = exception( $e )->as_string }
      }
      elsif (exists $self->templates->{ $path.$extn }) {
         try        { $content = io( $path.$extn )->slurp }
         catch ($e) { $content = exception( $e )->as_string }
      }

      $content and unshift @{ $s->{sdata}->{items} },
         { class => $action->name, content => $content };
   }

   # Default the template if one is not already defined
   $s->{js_object}   = $self->js_object;
   $s->{skin     } ||= q(default);
   $s->{target   }   = $self->target
      and $c->res->headers->header( q(target) => $s->{target} );
   $s->{template } ||= catfile( $s->{skin}, $self->default_template.$extn );

   return;
}

sub _setup_css {
   my ($self, $c) = @_; my $s = $c->stash;

   my $rel = q(stylesheet); my $skin = $s->{skin}; $s->{css} = [];

   # Fixup the stashed CSS files as either primary or alternate
   for my $css (@{ $self->css_paths->{ $skin } }) {
      (my $title = basename( $css, qw(.css) )) =~ s{ \A colour- }{}mx;

      push @{ $s->{css} }, { href  => $c->uri_for( $css ),
                             title => ucfirst $title,
                             rel   => $rel };
      $rel = q(alternate stylesheet);
   }

   return;
}

sub _setup_jscript {
   my ($self, $c) = @_; my $s = $c->stash; $s->{dhtml} or return;

   my $lang_dir = $self->lang_dir; my $js_path = $self->jscript_path;

   # Stash the static JS loaded by every page. Batch 0
   $s->{scripts} = [ map { [ 0, $c->uri_for( $_ ) ] }
                        @{ $self->static_js || [] } ];

   # Stash the optional JS. Batch 0
   push   @{ $s->{scripts} },
      map  { [ 0, $c->uri_for( $_ ) ] }
      grep { (my $x = basename( $_ )) =~ s{ \A (\d+) }{}mx;
             is_member $x, $s->{optional_js} }
          @{ $self->optional_js || [] };

   # Stash the language dependent JS files. Batch 1
   push   @{ $s->{scripts} },
      map  { [ 1, $c->uri_for( join SEP, NUL, $js_path, $lang_dir, $_ ) ] }
      grep { exists $self->lang_dep_jscript->{ $_ } }
      map  { $_.q(-).$s->{language}.q(.js) }
      grep { is_member $_.q(.js), $s->{optional_js} }
          @{ $self->lang_dep_jsprefixs || [] };

   # Stash the font replacement JS files. Batch 1
   push   @{ $s->{scripts} },
      map  { [ 1, $c->uri_for( $_ ) ] }
      map  { join SEP, NUL, $js_path, $self->fonts_dir,
             $self->fonts_jscript->{ $_ } }
      grep { $self->fonts_jscript->{ $_ } }
          @{ $s->{fonts} || [] };

   # Stash the "use case" JS for the selected skin. Batch 2
   exists $self->js_for_skin->{ $s->{skin} } and push @{ $s->{scripts} },
      [ 2, $c->uri_for( $self->js_for_skin->{ $s->{skin} } ) ];

   # If true generate literal js to async download all the js files in batches
   my $path; $path = $c->config->{async_js} and
      $s->{async_js} = $c->uri_for( join SEP, NUL, $js_path, $path );

   return;
}

# Private functions

sub __list_jscript {
   return map { basename( $_ ) } glob catfile( $_[ 0 ], q(*.js) );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::View::HTML - Render a page of HTML or XHTML

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   use CatalystX::Usul::Moose;

   extends qw(CatalystX::Usul::View);

=head1 Description

Generate a page of HTML or XHTML using Template Toolkit and the contents
of the stash

=head1 Configuration and Environment

Defines the following list of attributes

=over 3

=item css_paths

Defaults to an empty hash ref. Populated by L</COMPONENT>

=item default_css

Basename of the file containing the CSS for the generated
page. Defaults to C<presentation>

=item default_jscript

Basename of the file containing the Javascript used to modify the
default behaviour of the browser. Defaults to C<behaviour>

=item default_template

Basename of the L<Template::Toolkit> file used to generate the
page. Defaults to C<layout>

=item font_extension

String appended to font names to create a font filename. Defaults to
F<.typeface.js>

=item fonts_dir

Name of the directory that contains the JavaScript font replacement
files. Defaults to C<fonts>

=item fonts_jscript

Defaults to an empty hash ref. Populated by L</COMPONENT> it maps font names
to the pathnames

=item form_sources

An array ref the overrides the list in the parent class. Contains the stash
keys that are searched for widget definitions

=item js_for_skin

Defaults to an empty hash ref. Populated by L</COMPONENT> it maps skin names
onto paths for the behaviour class library

=item jscript_dir

A required directory that contains all of the JavaScript class
libraries (except for the one in the skin directory)

=item jscript_path

A partial path used to construct uris to the JavaScript class
libraries. Defaults to F<static/jscript>

=item lang_dep_jsprefixs

Defaults to an empty array ref. Populated in the component
configuration it lists the additional directories to search for
language dependent JavaScript files

=item lang_dep_jscript

Defaults to an empty hash ref. Populated by L</COMPONENT> it maps the
language dependent JavaScript filenames to pathnames

=item lang_dir

A string which defaults to C<lang>. It is the name of the directory that
contains the language dependent JavaScript files

=item optional_js

Defaults to an empty array ref. Populated by L</COMPONENT> it lists JavaScript
class library files which can be optionally included on a page

=item static_js

Defaults to an empty array ref. Populated by L</COMPONENT> it lists JavaScript
class library files which will be included on every page

=item target

A string which defaults to C<top>. The HTML window target

=item template_extension

String which defaults to F<.tt>. The extension applied to
L<Template::Toolkit> files

=item templates

Defaults to an empty hash ref. Populated by L</COMPONENT> it caches the
per page custom templates

=item view_tt

An instance of L<Catalyst::View::TT>

=back

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

=head1 Dependencies

=over 3

=item L<Catalyst::View::TT>

=item L<CatalystX::Usul::View>

=item L<CatalystX::Usul::Moose>

=item L<Encode>

=item L<CatalystX::Usul::Constraints>

=item L<File::DataClass::IO>

=item L<HTML::FillInForm>

=item L<TryCatch>

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
