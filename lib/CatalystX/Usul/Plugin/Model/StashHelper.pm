package CatalystX::Usul::Plugin::Model::StashHelper;

# @(#)$Id: StashHelper.pm 406 2009-03-30 01:53:50Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul);
use Data::Pageset;
use Lingua::Flags;
use Time::Elapsed qw(elapsed);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 406 $ =~ /\d+/gmx );

my $DOTS = chr 8230;
my $NUL  = q();
my $SEP  = q(/);
my $SPC  = q( );
my $TTS  = q( ~ );

# Core stash helper methods

sub stash_content {
   # Push the content onto the item list for the given stash id
   my ($self, $content, $id, $clear) = @_;

   return unless ($content and $id);

   my $s = $self->context->stash;

   eval { $self->$clear() } if ($clear and not defined $s->{ $id });

   my $ref = { content => $content, id => $id };

   if (ref $content eq q(HASH) and $content->{class}) {
      $ref->{class} = $content->{class};
   }

   push @{ $s->{ $id }->{items} }, $ref;
   $s->{ $id }->{count} = @{ $s->{ $id }->{items} };
   return;
}

sub stash_meta {
   # Set attribute value pairs for the given stash id
   my ($self, $data, $id, $clear) = @_;

   $id ||= q(sdata); $clear ||= q(clear_form);

   my $s = $self->context->stash;

   eval { $self->$clear() } unless (defined $s->{ $id });

   while (my ($attr, $value) = each %{ $data }) {
      $s->{ $id }->{ $attr } = $value unless ($attr eq q(items));
   }

   return;
}

# Stash content methods

sub add_append {
   # Add a widget definition to the append div
   my ($self, $content) = @_;

   return unless ($content and ref $content eq q(HASH));

   $content->{widget} = 1;

   $self->stash_content( $content, q(append), q(clear_append) );
   return;
}

sub add_button {
   # Add a button widget definition to the button bar div
   my ($self, $args) = @_; my $s = $self->context->stash; my $content;

   return unless ($args and ref $args eq q(HASH));

   my $label   = $args->{label  } || q(Unknown);
   my $button  = $s->{buttons}->{ $s->{form}->{name}.q(.).(lc $label) };
   my $help    = $args->{help   } || $button ? $button->{help  } : $NUL;
   my $prompt  = $args->{prompt } || $button ? $button->{prompt} : $NUL;
   my $onclick = $args->{onclick} || $prompt
               ? "return window.confirm( '${prompt}' )" : $NUL;
   my $type    = $args->{type   } || q(image);

   $label      = (split $SPC, $label.q( X))[0];

   my $file    = $label.q(.png);
   my $path    = $self->catfile( $s->{skindir}, $s->{skin}, $file );

   unless (-f $path) {
      $file = $label.q(.gif);
      $path = $self->catfile( $s->{skindir}, $s->{skin}, $file );
   }

   if ($type eq q(image) and -f $path) {
      $content = { alt => $label, src => $s->{assets}.$file };
   }

   $content->{class  } = $args->{class} || q(button);
   $content->{name   } = $label;
   $content->{onclick} = $onclick if ($onclick);
   $content->{tip    } = ($args->{title} || $DOTS).$TTS.$help if ($help);
   $content->{type   } = q(button);
   $content->{widget } = 1;

   $self->stash_content( $content, q(bbar), q(clear_buttons) );
   return;
}

sub add_footer {
   my $self = shift;
   my $c    = $self->context;
   my $cfg  = $c->config;
   my $req  = $c->req;
   my $s    = $c->stash;
   my ($content, $text);

   $self->stash_content( $self->_footer_line, q(footer), q(clear_footer) );

   $content = { text    => $s->{user}.q(@).$s->{host_port},
                tip     => $self->loc( q(yourIdentity) ),
                tiptype => q(plain),
                type    => q(label),
                widget  => 1 };
   $self->stash_content( $content, q(footer) );

   if ($s->{debug}) {
      # Useful numbers and such
      if ($cfg->{version}) {
         $content = { text    => q(&nbsp;).$cfg->{version},
                      tip     => $self->loc( q(moduleVersion) ),
                      tiptype => q(plain),
                      type    => q(label),
                      widget  => 1 };
         $self->stash_content( $content, q(footer) );
      }

      if (defined $s->{version}) {
         $content = { text    => q(&nbsp;).$s->{version},
                      tip     => $self->loc( q(levelVersion) ),
                      tiptype => q(plain),
                      type    => q(label),
                      widget  => 1 };
         $self->stash_content( $content, q(footer) );
      }

      ($text = $self->stamp) =~ tr?/:?..?;
      $content = { text    => $text,
                   tip     => $self->loc( q(pageGenerated) ),
                   tiptype => q(plain),
                   type    => q(label),
                   widget  => 1 };
      $self->stash_content( $content, q(footer) );

      if ($s->{elapsed}) {
         $content = { text    => q(&nbsp;).elapsed( $s->{elapsed} ),
                      tip     => $self->loc( q(elapsedTime) ),
                      tiptype => q(plain),
                      type    => q(label),
                      widget  => 1 };
         $self->stash_content( $content, q(footer) );
      }

      # TODO: Replace this with a language selector
      my %lang2country_map = ( 'de' => q(DE), 'en' => q(GB) );
      my $country          = $lang2country_map{ $s->{lang} };
      my $flag             = as_html_img( $country );

      $flag =~ s{ \s* / > }{>}mx if ($s->{content_type} eq q(text/html));

      $content = { text => $flag, type => q(label), widget => 1 };
      $self->stash_content( $content, q(footer) );
   }

   return;
}

sub add_header {
   my $self = shift; my $s = $self->context->stash;

   $self->stash_content( $self->_logo_link,        q(header) );
   $self->stash_content( $self->_company_link,     q(header) );
   $self->stash_meta   ( { title => $s->{title} }, q(header) );
   return;
}

sub add_hidden {
   # Add a hidden input field to the form
   my ($self, $name, $values) = @_;

   return unless ($name && defined $values);

   $values = [ $values ] unless (ref $values eq q(ARRAY));

   for my $value (@{ $values }) {
      my $content = { default => $value,    name   => $name,
                      type    => q(hidden), widget => 1 };

      $self->stash_content( $content, q(hidden), q(clear_hidden) );
   }

   return;
}

sub add_result {
   # Add some content the the result div
   my ($self, $content) = @_;

   return unless ($content); chomp $content;

   my $s = $self->context->stash;

   if ($s->{result} and $s->{result}->{items}->[ 0 ]) {
      $s->{result}->{items}->[-1]->{content} .= "\n";
   }

   $self->stash_content( $content, q(result), q(clear_result) );
   return;
}

sub add_sidebar_panel {
   # Add an Ajax call to the side bar accordion widget
   my ($self, $args) = @_; my ($content, $count, $jscript);

   my $s = $self->context->stash;

   unless ($count = $s->{sidebar}->{count} || 0) {
      $self->_clear_by_id( q(sidebar) );
      $s->{sidebar}->{tip} = $self->loc( q(sidebarTip) );
   }

   if ($args->{name} eq q(default)) {
      $content = {
         content      => { class => q(sidebarContent),
                           id    => q(default),
                           text  => $self->loc( q(sidebarBlankContent) ) },
         contentClass => q(sidebarPanel),
         contentId    => q(panel).$count.q(Content),
         header       => { content => $self->loc( q(sidebarBlankHeader)) },
         headerClass  => q(sidebarHeader sidebarHeaderFirst),
         headerId     => q(glassHeader),
         panelId      => q(glassPanel) };
   }
   else {
      $jscript  = "behaviour.loadMore.request('".$args->{name}."', '";
      $jscript .= $args->{name}."', '".($args->{value} || $NUL)."')";

      $args->{heading} = ucfirst $args->{name} unless ($args->{heading});

      $content = {
         content      => { class => q(sidebarContent),
                           id    => $args->{name},
                           text  => q(&nbsp;) },
         contentClass => q(sidebarPanel),
         contentId    => q(panel).$count.q(Content),
         header       => { onclick => $jscript,
                           content => $args->{heading} },
         headerClass  => q(sidebarHeader),
         headerId     => $args->{name}.q(Header),
         panelId      => $args->{name}.q(Panel) };
   }

   $self->stash_content( $content, q(sidebar), q(clear_sidebar) );
   return $s->{sidebar}->{count} - 1;
}

sub stash_form {
   my ($self, $content) = @_;

   $self->stash_content( $content, q(sdata), q(clear_form) );
   return;
}

# Clear content methods. Called by the stash content methods on first use

sub clear_append {
   my ($self, $args) = @_; $self->_clear_by_id( q(append), $args ); return;
}

sub clear_buttons {
   my ($self, $args) = @_; $self->_clear_by_id( q(bbar), $args ); return;
}

sub clear_footer {
   my ($self, $args) = @_; $self->_clear_by_id( q(footer), $args ); return;
}

sub clear_form {
   # Clear the stash of all form content
   my ($self, $args) = @_; my $s = $self->context->stash; my $id = q(sdata);

   return if (exists $s->{ $id });

   $self->_clear_by_id( $id, $args );

   if (exists $args->{title}) {
      $s->{title} = $args->{title}; $s->{header}->{title} = $args->{title};
   }

   $s->{firstfld} = $args->{firstfld} || $NUL;
   return;
}

sub clear_hidden {
   my ($self, $args) = @_; $self->_clear_by_id( q(hidden), $args ); return;
}

sub clear_menu {
   my $self = shift; $self->context->stash( menus => [] ); return;
}

sub clear_quick_links {
   my $self = shift; $self->_clear_by_id( q(quick_links) ); return;
}

sub clear_result {
   my ($self, $args) = @_; my $s = $self->context->stash;

   $self->_clear_by_id( q(result), $args );
   $s->{result}->{class} = q(centre);
   $s->{result}->{text } = 'Results';
   return;
}

sub clear_sidebar {
   my $self = shift; $self->context->stash( sidebar => 0 ); return;
}

sub clear_tools {
   my $self = shift; $self->context->stash( tools => 0 ); return;
}

# Curried stash content methods

sub add_buttons {
   my ($self, @buttons) = @_; my $title = $self->loc( q(buttonTitle) );

   for (0 .. $#buttons) {
      $self->add_button( { label => $buttons[ $_ ], title => $title } );
   }

   return;
}

sub add_chooser {
   my ($self, $args) = @_; my ($item, @items, $jscript, $param, $tip);

   my $s      = $self->context->stash;
   my $attr   = $args->{attr};
   my $fld    = $args->{field};
   my $form   = $args->{form};
   my $method = $args->{method};
   my $val    = $args->{value};
   my $w_fld  = $args->{where_fld};
   my $w_val  = $args->{where_val};

   delete $s->{token};
   $s->{logo    } = $NUL;
   $s->{is_popup} = q(true); # Stop JS from caching window size
   $s->{title   } = ucfirst $args->{title};
   $s->{header  } = { subtitle => $NUL, title => $s->{title} };

   $param->{ $w_fld } = $w_val if ($w_fld);
   $param->{ $fld   } = { like => $val ? $val : q(%) };
   @items             = $self->$method( $param );

   unless ($items[0]) {
      $self->add_field( { text => 'Nothing selected', type => q(label) } );
      return;
   }

   for $item (@items) {
      $jscript  = "behaviour.submit.returnValue('";
      $jscript .= "${form}', '${fld}', '".$item->$attr()."') ";
      $self->add_field( { class   => $args->{class},
                          clear   => q(left),
                          href    => '#top',
                          onclick => $jscript,
                          text    => $item->$attr(),
                          tip     => 'Click to select',
                          type    => q(anchor) } );
   }

   return;
}

sub add_error {
   # Handle $self->catch error thrown by a call to the model
   my ($self, $e, $verbosity, $offset) = @_;

   unless (defined $verbosity) {
      ($verbosity, $offset) = (($self->context->stash->{debug} ? 3 : 2), 1);
   }

   my $estr = $e->as_string( $verbosity, $offset );
   my $text = $self->loc( $estr, $e->arg1, $e->arg2 );

   $self->log_error( (ref $self).$SPC.(split m{ \n }mx, $text)[0] );
   $self->add_result( $text );
   return;
}

sub add_error_msg {
   my ($self, $key, $args) = @_;

   my $msg = $self->loc( $key, $args );
   my $e   = CatalystX::Usul::Exception->new( error => $msg );

   $self->add_error( $e );
   return;
}

sub add_field {
   # Add a field widget definition to the inner frame div
   my ($self, $content) = @_; my $s = $self->context->stash;

   return unless ($content and ref $content eq q(HASH));

   if (exists $content->{subtype} && $content->{subtype} eq q(html)) {
      $s->{content}->{style} = q(overflow: hidden; padding: 0px;);
   }

   $content->{widget} = 1;
   $self->stash_form( $content );
   return;
}

sub add_result_msg {
   my ($self, @rest) = @_; $self->add_result( $self->loc( @rest ) ); return;
}

sub add_search_links {
   my ($self, $page_info, $attrs) = @_; my ($key, $name, $page, $ref);

   $attrs ||= {};

   my $s            = $self->context->stash;
   my $clear        = 'left';
   my $expr         = $attrs->{expression};
   my $hits_per     = $attrs->{hits_per};
   my $href         = $s->{form}->{action}.$SEP.$expr.$SEP;
   my $anchor_class = $attrs->{anchor_class} || q(searchFade smaller);

   for $page (qw(first_page previous_page pages_in_set next_page last_page)) {
      if ($page eq q(pages_in_set)) {
         for (@{ $page_info->pages_in_set }) {
            if ($_ == $page_info->current_page) {
               $ref = { container => 1,
                        text      => q(&hellip;), type => q(label) };
            }
            else {
               $ref = { class  => $anchor_class,
                        href   => $href.$hits_per.$SEP.$_,
                        name   => q(page).$_,
                        pwidth => 0,
                        text   => $_,
                        type   => q(anchor) };
            }

            $self->add_field( $ref );
         }
      }
      elsif ($key = $page_info->$page) {
         $name = (split m{ _ }mx, $page)[0];
         $ref  = { class  => $anchor_class,
                   href   => $href.$hits_per.$SEP.$key,
                   name   => $name,
                   pwidth => 0,
                   text   => $self->loc( $page.q(_anchor) ),
                   type   => q(anchor) };

         if ($clear) {
            $ref->{clear}  = $clear;
            $ref->{prompt} = $self->loc( q(page_prompt) );
         }

         $self->add_field( $ref );
         $clear = $NUL;
      }
   }

   return;
}

sub group_fields {
   # Enclose a group of form fields in a field set definition
   my ($self, $args) = @_; my ($content, $text);

   my $nitems = $args->{nitems} || $args->{nItems};

   return if (!$nitems || $nitems <= 0);

   $text    = $args->{id  } ?  $self->loc( $args->{id} ) : q(duh);
   $text    = $args->{text} || $text;
   $content = { nitems => $nitems, text => $text, group => 1 };

   $self->stash_form( $content );
   return;
}

sub search_page {
   my ($self, $args) = @_; my ($e, $hit, @hits, $link_num, $page_info, $text);

   my $cnt      = 0;
   my $expr     = $args->{expression};
   my $excerpts = $args->{excerpts};
   my $hits_per = $args->{hits_per};
   my $key      = $args->{key};
   my $model    = $args->{data_model};
   my $offset   = $args->{offset};
   my $s        = $self->context->stash;
   my $form     = $s->{form}->{name};
   my $ref      = eval { $model->search_for( $expr, $hits_per, $offset ) };

   return $self->add_error( $e ) if ($e = $self->catch);

   while ($hit = $ref->fetch_hit_hashref) { push @hits, $hit; $cnt++ }

   $ref        = { current_page     => $offset + 1,
                   entries_per_page => $hits_per,
                   mode             => q(slide),
                   total_entries    => $ref->total_hits };
   $page_info  = Data::Pageset->new( $ref );
   $link_num   = 1 + $hits_per * $offset;
   $text       = $self->loc( $key, $expr );
   $self->add_field( { id => $form.q(.).$key, text => $text } );
   $text       = $self->loc( q(search_results), $offset +1,
                             $page_info->last_page,
                             $cnt, $ref->{total_entries} );
   $self->add_field( { id => $form.q(.search_results), text => $text } );
   $self->add_search_links( $page_info, { expression => $expr,
                                          hits_per   => $hits_per } );

   for $hit (@hits) {
      $self->add_field( { href   => $s->{url}.$hit->{url},
                          id     => $form.q(.title),
                          stepno => $link_num++,
                          text   => $hit->{title} } );
      $self->add_field( { id     => $form.q(.excerpt),
                          text   => $hit->{excerpts}->{ $excerpts } } );
      $self->add_field( { id     => $form.q(.score),
                          pwidth => 0,
                          text   => sprintf '%0.3f', $hit->{score} } );
      $self->add_field( { id     => $form.q(.file),
                          pwidth => 0,
                          text   => $hit->{file} } );
      $self->add_field( { id     => $form.q(.key),
                          pwidth => 0,
                          text   => $hit->{key} } );
   }

   $self->add_search_links( $page_info, { expression => $expr,
                                          hits_per   => $hits_per } );
   return;
}

sub simple_page {
   # Knock up a page of simple content from the XML config files
   my ($self, $name) = @_; my ($page, $ref, $subh, $text);

   my $s = $self->context->stash;

   unless ($name and $page = $s->{pages}->{ $name }) {
      $self->add_error_msg( q(eNoPage), [ $name ] );
      return;
   }

   unless (exists $s->{sdata}) {
      delete $s->{token}; # Do not need a CSRF token on a simple page
      $self->clear_form
         ( { heading    => $page->{heading} || $s->{title},
             subHeading => { content => $page->{subHeading} || q(&nbsp;) },
             title      => $page->{title} || $s->{title} } );
   }

   my $columns = $page->{columns}; my $data = { values => [] }; my $idx = 0;
   my $para    = $page->{vals}->{ q(para).$idx };

   while ($text = $para->{text}) {
      my $drop = $para->{dropcap} || 0; my $mark = $para->{markdown} || 0;
      $ref  = { class => q(), text => { dropcap => $drop, markdown => $mark,
                                        text    => $text, type => q(label) } };

      if ($subh = $page->{vals}->{ q(subHeading).$idx }->{text}) {
         $ref->{heading} = { text => $subh, type => q(label) };
      }

      push @{ $data->{values} }, $ref;
      $para = $page->{vals}->{ q(para).++$idx };
   }

   $self->add_field( { class        => $page->{class},
                       column_class => $columns > 1 ? q(paraColumn) : $NUL,
                       columns      => $columns,
                       container    => 0,
                       data         => $data,
                       hclass       => q(subheading),
                       type         => q(paragraphs) } );
   return 1;
}

# Stash meta methods

sub check_field_wrapper {
   # Process Ajax calls to validate form field values
   my $self = shift;
   my $s    = $self->context->stash;
   my $id   = $self->query_value( q(id) );
   my $val  = $self->query_value( q(val) );
   my $e;

   delete $s->{token};
   $self->stash_meta( { id => $id.q(_checkField), result => q(hidden) } );

   eval { $self->check_field( $id, $val ) };

   return unless ($e = $self->catch);

   if ($s->{debug}) {
      $self->log_debug( $self->loc( $e->as_string( 1 ), $id, $val ) );
   }

   $self->stash_meta( { result => q(error) } );
   return;
}

# Supporting cast

sub clear_controls {
   # Clear contents of multiple divs
   my $self = shift;

   $self->clear_footer;
   $self->clear_menu;
   $self->clear_quick_links;
   $self->clear_sidebar;
   $self->clear_tools;
   return;
}

sub open_window {
   my ($self, @rest) = @_; my ($jscript, $text);

   my $args = $self->arg_list( @rest );

   return unless ($args->{key} and $args->{href});

   $text     = 'dependent=no, width='.($args->{width} || 800);
   $text    .= ', height='.($args->{height} || 600).', resizable=yes, ';
   $text    .= 'screenX=0, screenY=0, titlebar=no, scrollbars=yes';
   $jscript  = "behaviour.window.openWindow('".$args->{href}."', '";
   $jscript .= $args->{key}."', '${text}')";
   return $jscript;
}

# Private methods

sub _clear_by_id {
   my ($self, $id, $args) = @_;

   return unless ($id);

   my $s = $self->context->stash; $s->{ $id } ||= {}; $args ||= {};

   $s->{ $id }->{count     } = 0;
   $s->{ $id }->{heading   } = $args->{heading} || $NUL;
   $s->{ $id }->{items     } = [];
   $s->{ $id }->{subHeading} = $args->{subHeading}
      if (exists $args->{subHeading});

   return;
}

sub _company_link {
   my $self    = shift;
   my $s       = $self->context->stash;
   my $href    = $self->uri_for( q(root).$SEP.q(company), $s->{lang} );
   my $tip     = $DOTS.$TTS.$self->loc( q(aboutCompanyTip) );
   my $content =
      { class           => q(headerFade),
        container_class => $s->{class},
        container_id    => q(headerSubTitle),
        href            => '#top',
        onclick         => $self->open_window( key  => q(company),
                                               href => $href ),
        sep             => q(),
        text            => $s->{company},
        tip             => $tip,
        type            => q(anchor),
        widget          => 1 };

   return $content;
}

sub _footer_line {
   my $self = shift; my ($content, $item, $jscript, $tip);

   my $s = $self->context->stash;

   # Cut on the dotted line toggle the footer visibilty
   $item     = 1 + ($s->{is_administrator} ? 1 : 0);
   $jscript  = "behaviour.state.toggleSwapText('tools0item${item}";
   $jscript .= "', 'footer', '".$self->loc( q(footerOffText) )."', '";
   $jscript .= $self->loc( q(footerOnText) )."')";
   $tip      = $self->loc( q(footerToggleTip) );
   $content  = { alt      => 'Close Footer',
                 class    => q(footer),
                 href     => '#top',
                 imgclass => q(footer),
                 onclick  => $jscript,
                 text     => $s->{assets}.'footerCut.gif',
                 tip      => $tip,
                 type     => q(rule),
                 widget   => 1 };

   return $content;
}

sub _logo_link {
   my $self    = shift;
   my $s       = $self->context->stash;
   my $href    = $s->{server_home} || 'http://'.$s->{domain};
   my $content =
      { class           => q(logo),
        container_class => $s->{class},
        container_id    => q(companyLogo),
        fhelp           => q(Company Logo),
        hint_title      => $href,
        href            => $href,
        imgclass        => q(logo),
        sep             => $NUL,
        text            => $s->{assets}.($s->{logo} || q(logo.png)),
        tip             => $self->loc( q(logoTip) ),
        type            => q(anchor),
        widget          => 1 };

   return $content;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Plugin::Model::StashHelper - Convenience methods for stuffing the stash

=head1 Version

0.1.$Revision: 406 $

=head1 Synopsis

   package CatalystX::Usul;
   use parent qw(Catalyst::Component CatalystX::Usul::Base);

   package CatalystX::Usul::Model;
   use parent qw(CatalystX::Usul CatalystX::Usul::StashHelper);

   package YourApp::Model::YourModel;
   use parent qw(CatalystX::Usul::Model);

=head1 Description

Many convenience methods for stuffing/resetting the stash. The form
widget definitions will be replaced later by the form building method
which is called from the HTML view

=head1 Subroutines/Methods

=head2 add_append

Stuff some content into the stash so that it will appear in the I<append>
div in the template. The content is a hash ref which will be
interpreted as a widget definition by the form builder which is
invoked by the HTML view. Multiple calls push the content onto a stack
which is rendered in the order in which it was stacked

=head2 add_button

Add a button definition to the stash. The template will render these
as image buttons on the I<bbar> div

=head2 add_buttons

Loop around L</add_button>

=head2 add_chooser

Generates the data for the popup chooser window which allows a data value to
be selected from a list produced by some query. It is intended as a
replacement for a popup menu widget where the list of values would be
prohibitively long

=head2 add_error

Stringifies the passed error object, localises the text, logs it as an error
and calls L</add_result> to display it at the top of the I<sdata> div

=head2 add_error_msg

Localises the message text, creates a new error object and calls
L</add_error>

=head2 add_field

Create a widget definition for a form field

=head2 add_footer

Adds some useful debugging info to the footer

=head2 add_header

Stuffs the stash with the data for the page header

=head2 add_hidden

Adds a I<hidden> field to the form

=head2 add_result

Adds the result of forwarding to an an action. This is the I<result>
div in the template

=head2 add_result_msg

Localises the message text and calls L</add_result>

=head2 add_search_links

Adds the sequence of links used in search page results; first page, previous
page, list of pages around the current one, next page, and last page

=head2 add_sidebar_panel

Stuffs the stash with the data necessary to create a panel in the
accordion widget on the sidebar

=head2 check_field_wrapper

   $model->check_field_wrapper;

Extract parameters from the query and call C<check_field>. Stash the result

=head2 clear_append

Clears the stash of the widget data used by the region appended to the
main data store

=head2 clear_buttons

Clears button data from the stash

=head2 clear_controls

Groups the methods that clear the stash of data not used in a minority of pages

=head2 clear_footer

Clears all footer data. Called by L</add_footer>

=head2 clear_form

Initialises the I<sdata> div contents. Called by C</stash_content> on
first use

=head2 clear_hidden

Clears the hidden fields from the form

=head2 clear_menu

Clears the stash of the main navigation menu data

=head2 clear_quick_links

Clears the stash of the quick links navigation data

=head2 clear_result

Clears the stash of messages from the output of actions

=head2 clear_sidebar

Clears the stash of the data used by the sidebar accordion widget

=head2 clear_tools

Clears the stash of the data used to create the tools menu

=head2 _footer_line

Adds a horizontal rule to separate the footer. Called by L</add_footer>

=head2 group_fields

Stashes the data used by L<HTML::FormWidgets> to throw I<fieldset> around
a group of fields

=head2 _logo_link

Returns a content hash ref that renders as a clickable image anchor. The
link returns to the web servers default page

=head2 open_window

Returns the Javascript fragment that will open a new window in the web
browser

=head2 search_page

Create a L<KinoSearch> results page

=head2 simple_page

Creates a "simple" page from information stored in the configuration files

=head2 stash_content

Pushes the content (usually a widget definition) onto the specified stack

=head2 stash_form

Calls L</stash_content> specifying the I<sdata> stack

=head2 stash_meta

Adds some meta data to the response for an Ajax call

=head1 Configuration and Environment

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul>

=item L<Data::Pageset>

=item L<Lingua::Flags>

=item L<Time::Elapsed>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module.

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
