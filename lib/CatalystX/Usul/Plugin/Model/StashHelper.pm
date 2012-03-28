# @(#)$Id: StashHelper.pm 1139 2012-03-28 23:49:18Z pjf $

package CatalystX::Usul::Plugin::Model::StashHelper;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1139 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(exception is_arrayref is_hashref throw);
use Class::Null;
use Data::Pageset;
use Scalar::Util  qw(blessed);
use TryCatch;

# Core stash helper methods

sub stash_content {
   # Push/unshift the content onto the item list for the given stash id
   my ($self, $content, $id, $clear, $stack_dirn) = @_;

   $content or return; $id ||= q(sdata); $clear ||= q(clear_form);

   my $s = $self->context->stash;

   unless (defined $s->{ $id }) { try { $self->$clear() } catch {} }

   my $count = @{ $s->{ $id }->{items} || [] };
   my $item  = { content => $content, id => $id.$count };

   if ($stack_dirn) { unshift @{ $s->{ $id }->{items} }, $item }
   else { push @{ $s->{ $id }->{items} }, $item }

   $s->{ $id }->{count} = $count + 1;
   return;
}

sub stash_meta {
   # Set attribute value pairs for the given stash id
   my ($self, $content, $id, $clear) = @_;

   $content or return; $id ||= q(sdata); $clear ||= q(clear_form);

   my $s = $self->context->stash;

   unless (defined $s->{ $id }) { try { $self->$clear() } catch {} }

   while (my ($attr, $value) = each %{ $content }) {
      $attr eq q(items) or $s->{ $id }->{ $attr } = $value;
   }

   return;
}

# Stash content methods

sub add_field {
   # Add a field widget definition to the inner frame div
   my ($self, $content, @rest) = @_; is_hashref $content or return;

   my $s = $self->context->stash; $content->{widget} = TRUE;

   # TODO: yuck yuck yuck
   # If error then resultDisp is too wide coz content haz no padding
   if (exists $content->{subtype} and $content->{subtype} eq q(html)) {
      $s->{content}->{class} = q(subtype_html);
   }
   elsif (not exists $s->{content}->{class}) {
      $s->{content}->{class} = q(subtype_normal);
   }

   return $self->stash_content( $content, @rest );
}

sub add_result {
   # Add some content the the result div
   my ($self, $content) = @_; my $s = $self->context->stash;

   $content or return; chomp $content;

   $s->{result} and $s->{result}->{items}->[ 0 ]
      and $s->{result}->{items}->[ -1 ]->{content} .= "\n";

   return $self->stash_content( $content, qw(result clear_result) );
}

sub form_wrapper {
   # Wrap a group of form fields with a form element
   my ($self, $args) = @_; my $s = $self->context->stash;

   my $nitems = __get_field_count( $s->{sdata}, $args->{nitems} ) or return;
   my $attrs  = { action  => $args->{action},
                  enctype => q(application/x-www-form-urlencoded),
                  method  => q(post), name => $args->{name} };

   return $self->stash_content( { attrs  => $attrs, form => TRUE,
                                  nitems => $nitems } );
}

sub group_fields {
   # Enclose a group of form fields in a field set definition
   my ($self, $args) = @_; my $s = $self->context->stash;

   my $nitems = __get_field_count( $s->{sdata}, $args->{nitems} ) or return;
   my $class  = exists $args->{class} ? $args->{class} : undef;
   my $text   = $args->{text} || $self->loc( $args->{id} || q(duh) );

   return $self->stash_content( { frame_class  => $class,  group => TRUE,
                                  nitems       => $nitems, text  => $text } );
}

# Add field helper methods

sub add_append {
   # Add a widget definition to the append div
   my ($self, $content) = @_;

   return $self->add_field( $content, qw(append clear_append) );
}

sub add_button {
   # Add a button widget definition to the button bar div
   my ($self, $args) = @_; is_hashref $args or return;

   my $s       = $self->context->stash;
   my $label   = $args->{label}  || 'Unknown';
   my $id      = $s->{form}->{name}.q(.).(lc $label);
   my $button  = $s->{buttons}->{ $id } || {};
   my $help    = $args->{help  } || $button->{help  };
   my $prompt  = $args->{prompt} || $button->{prompt};
   my $class   = $args->{class } || $button->{class } || NUL;
   my $type    = $args->{type  } || $button->{type  } || q(image);
   my $content = { id => $id.q(_button), type => q(button), };
   my $file;

   if ($type eq q(vertical)) {
      $content->{class } = $class || q(vertical markup_button submit);
      $content->{config} = { args    => "[ '${label}' ]",
                             method  => "'submitForm'" };
      $content->{src   } = { content => uc $label };
   }
   else { $class and $content->{class} = $class; $content->{name} = $label }

   if ($type eq q(image) and $file = $self->_get_image_file( $s, $label )) {
      $content->{alt} = $label; $content->{src} = $s->{assets}.$file;
   }

   $help   and $content->{tip   } = ($args->{title} || DOTS).TTS.$help;
   $prompt and $content->{config} = { args   => "[ '${label}', '${prompt}' ]",
                                      method => "'confirmSubmit'" };

   return $self->add_field( $content, qw(button clear_buttons) );
}

sub add_buttons {
   my ($self, @labels) = @_; my $title = $self->loc( 'Action' );

   for my $label (@labels) {
      $self->add_button( { label => $label, title => $title } );
   }

   return;
}

sub add_chooser {
   my ($self, $args) = @_;

   my $s      = $self->context->stash;
   my $attr   = $args->{attr     } or return;
   my $field  = $args->{field    } or return;
   my $form   = $args->{form     } or return;
   my $method = $args->{method   } or return;
   my $val    = $args->{value    };
   my $w_fld  = $args->{where_fld};
   my $param  = {};

   $s->{is_popup} = q(true); # Stop JS from caching window size
   $s->{header  }->{title} = $self->loc( 'Select Item' );
   $w_fld and $param->{ $w_fld } = $args->{where_val};
   $param->{ $field } = { like => $val ? $val : q(%) };

   my @items  = $self->$method( $param );

   $items[ 0 ]
      or return $self->add_field( { text => $self->loc( 'Nothing selected' ),
                                    type => q(label) } );

   my $class = ($args->{class} || q(anchor_button fade)).q( submit);
   my $count = 0;

   for my $item (@items) {
      my $text = $item->$attr();

      $self->add_field( {
         class       => $class,
         config      => { args   => "[ '${form}', '${field}', '${text}' ]",
                          method => q("returnValue") },
         frame_class => $args->{frame_class} || q(chooser),
         href        => '#top',
         id          => $field.q(_).$attr.$count++,
         text        => $text,
         tip         => $self->loc( 'Click to select' ),
         type        => q(anchor) } );
   }

   return;
}

sub add_error {
   # Handle error thrown by a call to the model
   my ($self, $e) = @_; my $s = $self->context->stash; my $class = blessed $e;

   ($class and $e->isa( EXCEPTION_CLASS )) or $e = exception $e;
   $s->{stacktrace} = $s->{debug} ? (blessed $e)."\n".$e->stacktrace : NUL;

   return $self->_log_and_stash_error( $e );
}

sub add_error_msg {
   my ($self, $error, @rest) = @_;

   my $key  = (split m{ [\n] }mx, $error)[ 0 ];
   my $args = (is_arrayref $rest[ 0 ]) ? $rest[ 0 ] : [ @rest ];
   my $e    = exception 'error' => $key, 'args' => $args;

   return $self->_log_and_stash_error( $e );
}

sub add_footer {
   my $self = shift; my $s = $self->context->stash;

   $self->add_field( $self->_hash_for_footer_line,  qw(footer clear_footer) );
   $self->add_field( $self->_hash_for_async_footer, qw(footer) );

   return $self->stash_meta( { state => $s->{fstate} }, qw(footer) );
}

sub add_header {
   my $self = shift; my $s = $self->context->stash;

   $self->add_field( $self->_hash_for_logo_link,    qw(header clear_header) );
   $self->add_field( $self->_hash_for_company_link, qw(header) );

   return $self->stash_meta( { title => $s->{title} }, qw(header) );
}

sub add_hidden {
   # Add a hidden input field to the form
   my ($self, $name, $values) = @_;

   ($name and defined $values) or return;

   is_arrayref $values or $values = [ $values ];

   for my $value (@{ $values }) {
      my $content = { default => $value, name => $name, type => q(hidden) };

      $self->add_field( $content, qw(hidden clear_hidden) );
   }

   return;
}

sub add_result_msg {
   my ($self, @rest) = @_; return $self->add_result( $self->loc( @rest ) );
}

sub add_search_hit {
   return; # You want to override in your subclass
}

sub add_search_links {
   my ($self, $page_info, $attrs) = @_; my ($args, $key, $name, $page);

   $attrs ||= {};

   my $s            = $self->context->stash;
   my $hits_per     = $attrs->{hits_per};
   my $href         = $attrs->{href};
   my $anchor_class = $attrs->{anchor_class} || q(search fade);
   my $clear        = TRUE;

   for $page (qw(first_page previous_page pages_in_set next_page last_page)) {
      if ($page eq q(pages_in_set)) {
         for (@{ $page_info->pages_in_set }) {
            if ($_ == $page_info->current_page) {
               $args = { container       => FALSE,
                         text            => q(&hellip;),
                         type            => q(label) };
            }
            else {
               $args = { class           => $anchor_class,
                         container_class => q(label_text),
                         href            => $href.$hits_per.SEP.$_,
                         name            => q(page).$_,
                         pwidth          => 0,
                         text            => $_,
                         type            => q(anchor) };
            }

            $self->add_field( $args );
         }
      }
      elsif ($key = $page_info->$page) {
         $name = (split m{ _ }mx, $page)[ 0 ];
         $args = { class           => $anchor_class,
                   container_class => q(label_text),
                   href            => $href.$hits_per.SEP.$key,
                   name            => $name,
                   pwidth          => 0,
                   text            => $self->loc( $page.q(_anchor) ),
                   type            => q(anchor) };

         if ($clear) {
            $args->{frame_class } = q(clearLeft);
            $args->{prompt      } = $self->loc( q(page_prompt) );
            $args->{stepno      } = 0;
         }

         $self->add_field( $args );
         $clear = FALSE;
      }
   }

   return;
}

sub add_sidebar_panel {
   # Add an Ajax call to the sidebar accordion widget
   my ($self, $args) = @_; my ($content, $count);

   my $name    = $args->{name};
   my $s       = $self->context->stash;
   my $sidebar = $s->{sidebar} || {};

   unless ($count = $sidebar->{count} || 0) {
      $self->_clear_by_id( q(sidebar) );
      $s->{sidebar}->{tip} = $self->loc( q(sidebarTip) );
   }

   if ($name eq q(default)) {
      $content        =  {
         class        => q(accordion_content heading),
         container_id => q(glassPanel),
         header       => {
            class     => q(accordion_header),
            id        => $name.q(Header),
            text      => $self->loc( q(sidebarBlankHeader) ) },
         id           => $name,
         panel        => {
            class     => q(accordion_panel),
            id        => q(panel).$count.q(Content) },
         text         => $self->loc( q(sidebarBlankContent) ),
         type         => q(sidebarPanel) };
   }
   else {
      my $action = $name.($args->{action} ? SEP.$args->{action} : NUL);

      $content        =  {
         config       => {
            action    => '"'.$action.'"',
            name      => '"'.$name.'"' },
         container_id => $name.q(Panel),
         header       => {
            class     => q(accordion_header),
            id        => $name.q(Header),
            text      => $args->{heading} || ucfirst $name },
         id           => $name,
         panel        => {
            class     => q(accordion_panel),
            id        => q(panel).$count.q(Content) },
         text         => SPC,
         type         => q(sidebarPanel) };
   }

   $args->{on_complete}
      and $content->{config}->{onComplete} = $args->{on_complete};
   $args->{value} and $content->{config}->{value} = '"'.$args->{value}.'"';
   $self->add_field( $content, qw(sidebar clear_sidebar), $args->{unshift} );

   return $args->{unshift} ? 0 : $s->{sidebar}->{count} - 1;
}

sub search_for {
   throw 'Method search_for not overridden in subclass'; return;
}

sub search_page {
   my ($self, $args) = @_; my ($hits, @hits);

   my $field    = $args->{search_field};
   my $query    = $args->{query       };
   my $hits_per = $args->{hits_per    };
   my $offset   = $args->{offset      };
   my $heading  = $self->loc( $args->{key}, $query );
   my $s        = $self->context->stash;
   my $form     = $s->{form}->{name};
   my $href     = $s->{form}->{action}.SEP.$query.SEP;

   try { $hits = $self->search_for( { hits_per     => $hits_per,
                                      page         => $offset,
                                      query        => $query,
                                      search_field => $field } );
   }
   catch ($e) { return $self->add_error( $e ) }

   my $page_info = Data::Pageset->new( {
      current_page     => $offset + 1,
      entries_per_page => $hits_per,
      mode             => q(slide),
      total_entries    => $hits->total_hits } );
   my $link_num    = 1 + $hits_per * $offset;
   my $sub_heading = $self->loc( q(search_results),
                                 $offset + 1,
                                 $page_info->last_page,
                                 scalar @{ $hits->list || [] },
                                 $hits->total_hits || 0 );

   $self->clear_form( { class       => q(narrow left),
                        heading     => { class   => q(narrow left),
                                         content => $heading, },
                        sub_heading => { class   => q(narrow left),
                                         content => $sub_heading,
                                         level   => 4 } } );

   $self->add_search_links( $page_info, { href     => $href,
                                          hits_per => $hits_per } );

   try {
      for my $hit (@{ $hits->list || [] }) {
         $self->add_search_hit( $hit, $link_num++, $field );
      }
   }
   catch ($e) { return $self->add_error( $e ) }

   $self->add_search_links( $page_info, { href     => $href,
                                          hits_per => $hits_per } );
   return;
}

# Supporting cast

sub check_field_wrapper {
   # Process Ajax calls to validate form field values
   my $self = shift;
   my $id   = $self->query_value( q(id)  );
   my $val  = $self->query_value( q(val) );
   my $msg;

   $self->stash_meta( { id => $id.q(_ajax), result => NUL } );

   try        { $self->check_field( $id, $val ) }
   catch ($e) {
      $self->stash_meta( { class_name => q(error) } );
      $self->stash_content( $msg = $self->loc( $e->error, $id, $val ) );
      $self->context->stash->{debug} and $self->log_debug( $msg );
   }

   return;
}

sub clear_controls {
   # Clear contents of multiple divs
   my $self = shift;

   $self->clear_footer;
   $self->clear_menus;
   $self->clear_quick_links;
   $self->clear_sidebar;
   return;
}

sub get_para_col_class {
   my ($self, $columns) = @_; $columns ||= 1;

   my @col_names  = ( qw(zero one two three four five six seven eight nine ten
                         eleven twelve thirteen fourteen fifteen) );
   my $col_class  = $columns > 1 ? $col_names[ $columns ].' multi' : 'one';
      $col_class .= 'Column';

   return $col_class;
}

sub stash_para_col_class {
   my ($self, $key, $n_cols) = @_; my $s = $self->context->stash;

   return $s->{ $key } = $self->get_para_col_class( $n_cols || 2 );
}

sub update_group_membership {
   my ($self, $args) = @_; my $count = 0;

   my $method_args = $args->{method_args};

   $method_args->{items} = $self->query_array( $args->{field}.q(_added) );

   defined $method_args->{items}->[ 0 ]
      and $count += $args->{add_method}->( $method_args );

   $method_args->{items} = $self->query_array( $args->{field}.q(_deleted) );

   defined $method_args->{items}->[ 0 ]
      and $count += $args->{delete_method}->( $method_args );

   $count < 1 and throw 'Updated nothing';

   return TRUE;
}

# Clear content methods. Called by the stash content methods on first use

sub clear_append {
   my ($self, $args) = @_; return $self->_clear_by_id( q(append), $args );
}

sub clear_buttons {
   my ($self, $args) = @_; return $self->_clear_by_id( q(button), $args );
}

sub clear_footer {
   my ($self, $args) = @_; return $self->_clear_by_id( q(footer), $args );
}

sub clear_form {
   # Clear the stash of all form content
   my ($self, $args) = @_; my $s = $self->context->stash; my $id = q(sdata);

   exists $s->{ $id } and not $args->{force} and return;

   $self->_clear_by_id( $id, $args );

   exists $args->{title}
      and $s->{title} = $s->{header}->{title} = $args->{title};

   $s->{firstfld} = $args->{firstfld} || NUL;
   return;
}

sub clear_header {
   my $self = shift; return $self->_clear_by_id( q(header) );
}

sub clear_hidden {
   my ($self, $args) = @_; return $self->_clear_by_id( q(hidden), $args );
}

sub clear_menus {
   my $self = shift; return $self->_clear_by_id( q(menus) );
}

sub clear_quick_links {
   my $self = shift; return $self->_clear_by_id( q(quick_links) );
}

sub clear_result {
   my ($self, $args) = @_;

   $self->_clear_by_id( q(result), $args );
   $self->context->stash->{result}->{text} = $self->loc( 'Results' );
   return;
}

sub clear_sidebar {
   my $self = shift; $self->context->stash( sidebar => FALSE ); return;
}

# Private methods

sub _clear_by_id {
   my ($self, $id, $args) = @_; $id or return; $args ||= {};

   my $sid     = $self->context->stash->{ $id } ||= {};
   my $heading = $args->{heading}
               ? ( (is_hashref $args->{heading})
               ? $args->{heading}
               : { class => q(banner), content => $args->{heading} } )
               : FALSE;

   $heading                    and $sid->{heading    } = $heading;
   exists $args->{class      } and $sid->{class      } = $args->{class      };
   exists $args->{sub_heading} and $sid->{sub_heading} = $args->{sub_heading};

   $sid->{count} = 0;
   $sid->{items} = [];
   $sid->{mark } = -1;
   return;
}

{  my %cache;

   sub _get_image_file {
      my ($self, $s, $prefix) = @_;

      my $dir = $self->catdir( $s->{skindir}, $s->{skin} );

      0 > index $prefix, SPC or $prefix =~ s{ \s+ }{_}gmx;

      for my $file (map { $prefix.$_ } qw(.png .gif)) {
         my $path = $self->catfile( $dir, $file );

         not exists $cache{ $path } and $cache{ $path } = -f $path;

         $cache{ $path } and return $file;
      }

      return;
   }
}

sub _hash_for_async_footer {
   my $self = shift; my $c = $self->context; my $s = $c->stash;

   my $id       = q(footer.data);
   my $action   = $c->action->reverse;
   my $function = 'function() { this.rebuild() }';
   my $args     = "[ 'footer', '${id}', '${action}', ${function} ]";

   return { config           => [ {
               'tools0item1' => {
                  args       => $args,
                  method     => "'request'" } }, {
               'footer.data' => {
                  args       => $args,
                  event      => "'load'",
                  method     => "'requestIfVisible'" } }, ],
            id               => $id,
            text             => $s->{nbsp},
            type             => q(async) };
}

sub _hash_for_company_link {
   my $self = shift; my $c = $self->context; my $s = $c->stash;

   my $href = $c->uri_for_action( SEP.q(company) );

   return { class           => q(header_link fade windows),
            config          => {
               args         => "[ '${href}', { name: 'company' } ]",
               method       => "'openWindow'" },
            container_id    => q(headerSubTitle),
            container_class => q(none),
            href            => '#top',
            id              => q(company_link),
            sep             => NUL,
            text            => $s->{company},
            tip             => DOTS.TTS.$self->loc( q(aboutCompanyTip) ),
            type            => q(anchor) };
}

sub _hash_for_footer_line {
   # Cut on the dotted line toggle the footer visibilty
   my $self = shift;
   my $id   = q(tools0item1);
   my $text = $self->loc( q(footerOffText) );
   my $alt  = $self->loc( q(footerOnText) );

   return { class     => q(cut_here),
            config    => {
               args   => "[ '${id}', 'footer', '${text}', '${alt}' ]",
               method => "'toggleSwapText'" },
            href      => '#top',
            id        => q(footer_line),
            imgclass  => q(scissors_icon),
            text      => NUL,
            tip       => DOTS.TTS.$self->loc( q(footerToggleTip) ),
            type      => q(rule) };
}

sub _hash_for_logo_link {
   my $self = shift;
   my $s    = $self->context->stash;
   my $href = $s->{server_home} || q(http://).$s->{domain};

   return { class        => q(logo),
            container_id => q(companyLogo),
            fhelp        => q(Company Logo),
            hint_title   => $href,
            href         => $href,
            imgclass     => q(logo),
            sep          => NUL,
            text         => $s->{assets}.($s->{logo} || q(logo.png)),
            tip          => $self->loc( q(logoTip) ),
            type         => q(anchor) };
}

sub _log_and_stash_error {
   my ($self, $e) = @_; my $s = $self->context->stash;

   $s->{leader} = blessed $self; $self->log_error_message( $e, $s );

   return $self->add_result( $self->loc( $e->error, $e->args ) );
}

# Private functions

sub __get_field_count {
   my ($sid, $nitems) = @_; $nitems ||= $sid->{count} - $sid->{mark} - 1;

   (not $nitems or $nitems <= 0) and return FALSE; $sid->{mark} = $sid->{count};

   return $nitems;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Plugin::Model::StashHelper - Convenience methods for stuffing the stash

=head1 Version

0.5.$Revision: 1139 $

=head1 Synopsis

   package CatalystX::Usul;
   use parent qw(CatalystX::Usul::Base CatalystX::Usul::File);

   package CatalystX::Usul::Model;
   use parent qw(Catalyst::Model CatalystX::Usul);

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
as image buttons on the I<button> div

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

Adds data for a horizontal rule to separate the footer from the rest of the
content

=head2 add_header

Stuffs the stash with the data for the page header

=head2 add_hidden

Adds a I<hidden> field to the form

=head2 add_result

Adds the result of forwarding to an an action. This is the I<result>
div in the template

=head2 add_result_msg

Localises the message text and calls L</add_result>

=head2 add_search_hit

Placeholder should have been implemented in the class that applies
this role

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

=head2 clear_header

Clears the header data from the form

=head2 clear_hidden

Clears the hidden fields from the form

=head2 clear_menus

Clears the stash of the main navigation and tools menu data

=head2 clear_quick_links

Clears the stash of the quick links navigation data

=head2 clear_result

Clears the stash of messages from the output of actions

=head2 clear_sidebar

Clears the stash of the data used by the sidebar accordion widget

=head2 form_wrapper

Stashes the data used by L<HTML::FormWidgets> to throw I<form> around
a group of fields

=head2 get_para_col_class

   $column_class = $model_obj->get_para_col_class( $n_columns );

Converts an integer number into a string representation

=head2 group_fields

Stashes the data used by L<HTML::FormWidgets> to throw a I<fieldset> around
a group of fields

=head2 search_for

Placeholder returns an instance of L<Class::Null>. Should have been
implemented in the interface model subclass

=head2 search_page

Create a L<KinoSearch> results page

=head2 stash_content

Pushes the content (usually a widget definition) onto the specified stack.
Defaults the I<sdata> stack

=head2 stash_meta

Adds some meta data to the response for an Ajax call

=head2 stash_para_col_class

   $column_class = $model_obj->stash_para_col_class( $key, $n_columns );

Calls and returns the value from L</get_para_col_class>. Also stashes the
value in the C<$key> attribute

=head2 update_group_membership

   $bool = $model_obj->update_group_membership( $args );

Adds/removes lists of attributes from groups

=head2 _hash_for_logo_link

Returns a content hash ref that renders as a clickable image anchor. The
link returns to the web servers default page

=head2 _hash_for_footer_line

Adds a horizontal rule to separate the footer. Called by L</add_footer>

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
