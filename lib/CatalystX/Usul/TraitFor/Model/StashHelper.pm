# @(#)Ident: StashHelper.pm 2013-08-19 19:34 pjf ;

package CatalystX::Usul::TraitFor::Model::StashHelper;

use 5.010001;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw( assert exception is_arrayref is_hashref
                                   sub_name throw );
use Data::Pageset;
use File::Spec::Functions      qw( catdir catfile );
use Moose::Role;
use TryCatch;

# Core stash helper methods
sub stash_content {
   # Push/unshift the content onto the item list for the given stash id
   my ($self, $content, $id, $clear, $stack_dirn) = @_;

   $content or return; $id ||= q(sdata); $clear ||= q(clear_form);

   my $s = $self->context->stash;

   unless (defined $s->{ $id }) { try { $self->$clear() } catch {} }

   my $count = @{ $s->{ $id }->{items} || [] };
   my $item  = { content => $content, id => "${id}${count}" };

   if ($stack_dirn) { unshift @{ $s->{ $id }->{items} }, $item }
   else { push @{ $s->{ $id }->{items} }, $item }

   $s->{ $id }->{count} = $count + 1;
   return;
}

sub stash_meta { # Set attribute value pairs for the given stash id
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
sub add_field { # Add an HTML::FormWidgets field to the content div
   my ($self, $content, @args) = @_;

   my $s = $self->context->stash; $content->{widget} = TRUE;

   # TODO: yuck yuck yuck
   # If error then resultDisp is too wide coz content haz no padding
   if (exists $content->{subtype} and $content->{subtype} eq q(html)) {
      $s->{content}->{class} = q(subtype_html);
   }
   elsif (not exists $s->{content}->{class}) {
      $s->{content}->{class} = q(subtype_normal);
   }

   return $self->stash_content( $content, @args );
}

sub add_result { # Add some content the the result div
   my ($self, $content) = @_; $content or return;

   my $s = $self->context->stash; chomp $content;

   $s->{result} and $s->{result}->{items}->[ 0 ]
      and $s->{result}->{items}->[ -1 ]->{content} .= "\n";

   return $self->stash_content( $content, qw(result clear_result) );
}

sub form_wrapper { # Wrap a group of form fields with a form element
   my ($self, $args) = @_; my $s = $self->context->stash;

   my $nitems = __get_field_count( $s->{sdata}, $args->{nitems} ) or return;
   my $attrs  = { action  => $args->{action},
                  enctype => q(application/x-www-form-urlencoded),
                  method  => q(post), name => $args->{name} };

   return $self->stash_content( { attrs  => $attrs, form => TRUE,
                                  nitems => $nitems } );
}

sub group_fields { # Enclose a group of form fields in a field set definition
   my ($self, $args) = @_; my $s = $self->context->stash;

   my $nitems = __get_field_count( $s->{sdata}, $args->{nitems} ) or return;
   my $class  = exists $args->{class} ? $args->{class} : undef;
   my $text   = $args->{text} || $self->loc( $args->{id} || 'duh' );

   return $self->stash_content( { frame_class => $class,  group => TRUE,
                                  nitems      => $nitems, text  => $text } );
}

# Add field helper methods
sub add_append { # Add a widget definition to the append div
   my ($self, $content) = @_;

   return $self->add_field( $content, qw(append clear_append) );
}

sub add_button { # Add a button widget definition to the button bar div
   my ($self, $args) = @_;

   my $s       = $self->context->stash;
   my $label   = $args->{label}  || $self->loc( 'Unknown' );
   my $id      = $s->{form}->{name}.q(.).(lc $label);
   my $button  = $s->{buttons}->{ $id } || {};
   my $help    = $args->{help  } || $button->{help  };
   my $prompt  = $args->{prompt} || $button->{prompt};
   my $class   = $args->{class } || $button->{class } || NUL;
   my $type    = $args->{type  } || $button->{type  } || q(image);
   my $content = { id => "${id}_button", type => q(button), };
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
   my ($self, @args) = @_; my $title = $self->loc( 'Action' );

   for my $label (@args) {
      $self->add_button( { label => $label, title => $title } );
   }

   return;
}

sub add_chooser {
   my ($self, $args) = @_;

   my $field = __get_or_throw( $args, q(field) );
   my $form  = __get_or_throw( $args, q(form)  );
   my $id    = __get_or_throw( $args, q(id)    );
   my $show  = "function() { this.window.dialogs[ '${field}' ].show() }";

   $self->add_field ( { class         => q(hidden live_grid),
                        config        => {
                           event      => $args->{event } || "'load'",
                           fieldValue => "'".($args->{val} || NUL)."'",
                           gridToggle => $args->{toggle} ? 'true' : 'false',
                           onComplete => $show, },
                        container     => FALSE,
                        href          => '#top',
                        id            => "${form}_${field}",
                        subtype       => q(display),
                        type          => q(chooser) } );
   $self->stash_meta( { id            => $id, } );
   return;
}

sub add_chooser_grid_rows {
   my ($self, $args) = @_;

   my $cb_method = __get_or_throw( $args, q(method) );
   my $field     = __get_or_throw( $args, q(field)  );
   my $form      = __get_or_throw( $args, q(form)   );
   my $id        = __get_or_throw( $args, q(id)     );
   my $page      = $args->{page     } || 0;
   my $page_size = $args->{page_size} || 10;
   my $start     = $page * $page_size;
   my $count     = 0;

   for my $value (@{ $args->{values} || [] }) {
      my $link_num = $start + $count;
      my $item     = $self->$cb_method( $args, $value, $link_num );
      my $rv       = (delete $item->{value}) || $item->{text};

      $item->{class    } ||= 'chooser_grid fade submit';
      $item->{config   }   = { args   => "[ '${form}', '${field}', '${rv}' ]",
                               method => "'returnValue'", };
      $item->{container}   = FALSE;
      $item->{id       }   = "${id}_link${link_num}";
      $item->{type     }   = q(anchor);
      $item->{widget   }   = TRUE;

      $self->add_field( {
         class   => q(grid),
         classes => { item     => q(grid_cell),
                      item_num => q(grid_cell lineNumber first) },
         fields  => [ qw(item_num item) ],
         type    => q(tableRow),
         values  => { item => $item, item_num => $link_num + 1, }, } );
      ++$count;
   }

   $self->stash_meta( { id => "${id}${start}", offset => $start, } );
   return;
}

sub add_chooser_grid_table {
   my ($self, $args) = @_;

   my $field  = __get_or_throw( $args, q(field) );
   my $form   = __get_or_throw( $args, q(form)  );
   my $total  = __get_or_throw( $args, q(total) );
   my $value  = $args->{field_value} ||= NUL;
   my $psize  = $args->{page_size  } ||= 10;
   my $id     = "${form}_${field}";
   my @values = ();
   my $count  = 0;

   while ($count < $total && $count < $psize) {
      push @values, { item => DOTS, item_num => ++$count, };
   }

   my $grid   = $self->_new_chooser_grid_table( $args, \@values );

   $self->add_field ( { class           => q(grid_subheader),
                        container_class => q(grid_header),
                        id              => "${id}_header",
                        href            => '#top',
                        text            => $self->loc( 'Loading' ).DOTS,
                        type            => q(anchor), } );
   $self->add_field ( { container       => TRUE,
                        container_class => q(grid_container),
                        data            => $grid,
                        hclass          => NUL,
                        id              => "${id}_grid",
                        table_class     => q(grid),
                        type            => q(table), } );
   $self->stash_meta( { field_value     => $value,
                        id              => $id,
                        totalcount      => $total, } );
   return;
}

sub add_error {
   my ($self, $e, @args) = @_; my $s = $self->context->stash; my $class;

   unless ($class = blessed $e and $e->can( q(args) )) {
      my $err  = (split m{ [\n] }mx, NUL.$e)[ 0 ];
      my $args = (is_arrayref $args[ 0 ]) ? $args[ 0 ] : [ @args ];

      $e = exception error => $err || 'Unspecified error added', args => $args;
   }

   if ($s->{debug}) {
      $e->can( q(leader) ) and $s->{stacktrace} .= $e->leader;
      $class and $s->{stacktrace} .= "${class}\n";
      $e->can( q(stacktrace) ) and $s->{stacktrace} .= $e->stacktrace."\n";
   }

   $s->{leader} = blessed $self; $self->log->error_message( $s, $e );

   return $self->add_result_msg( $e->error, $e->args );
}

sub add_footer {
   my $self = shift;

   $self->add_field( $self->_hash_for_footer_line,  qw(footer clear_footer) );
   $self->add_field( $self->_hash_for_async_footer, qw(footer) );
   return;
}

sub add_hidden { # Add a hidden input field to the form
   my ($self, $name, $values) = @_; ($name and defined $values) or return;

   is_arrayref $values or $values = [ $values ];

   for my $value (@{ $values }) {
      my $content = { default => $value, name => $name, type => q(hidden) };

      $self->add_field( $content, qw(hidden clear_hidden) );
   }

   return;
}

sub add_result_msg {
   my ($self, @args) = @_;

   is_arrayref $args[ 0 ] or return $self->add_result( $self->loc( @args ) );

   $self->add_result( $self->loc( @{ $_ } ) ) for (@{ $args[ 0 ] });

   return;
}

sub add_search_hit { # You want to override this in your subclass
   throw 'Method add_search_hit not overridden in subclass';
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
                         text            => $self->loc( $_ ),
                         type            => q(anchor) };
            }

            $self->add_field( $args );
         }
      }
      elsif ($key = $page_info->$page) {
         $clear and
            $self->add_field( { frame_class => q(clearLeft),
                                stepno      => 0,
                                text        => $self->loc( q(page_prompt) ),
                                type        => q(label) } );
         $name = (split m{ _ }mx, $page)[ 0 ];
         $self->add_field( { class           => $anchor_class,
                             container_class => q(label_text),
                             href            => $href.$hits_per.SEP.$key,
                             name            => $name,
                             pwidth          => 0,
                             text            => $self->loc( "${page}_anchor" ),
                             type            => q(anchor) } );

         $clear = FALSE;
      }
   }

   return;
}

sub add_sidebar_panel { # Add an Ajax call to the sidebar accordion widget
   my ($self, $args) = @_; my $count;

   my $name    = __get_or_throw( $args, q(name) );
   my $s       = $self->context->stash;
   my $sidebar = $s->{sidebar} || {};

   unless ($count = $sidebar->{count} || 0) {
      $self->_clear_by_id( q(sidebar) );
      $s->{sidebar}->{tip} = $self->loc( q(sidebarTip) );
   }

   my $content = $self->_get_sidebar_panel_hash( $args, $name, $count );

   $args->{on_complete}
      and $content->{config}->{onComplete} = $args->{on_complete};
   $args->{value} and $content->{config}->{value} = '"'.$args->{value}.'"';
   $self->add_field( $content, qw(sidebar clear_sidebar), $args->{unshift} );

   return $args->{unshift} ? 0 : $s->{sidebar}->{count} - 1;
}

sub search_for { # You want to override this in your subclass
   throw 'Method search_for not overridden in subclass';
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

   try {
      $hits = $self->search_for( { hits_per     => $hits_per,
                                   page         => $offset,
                                   query        => $query,
                                   search_field => $field } );

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

      for my $hit (@{ $hits->list || [] }) {
         $self->add_search_hit( $hit, $link_num++, $field );
      }

      $self->add_search_links( $page_info, { href     => $href,
                                             hits_per => $hits_per } );
   }
   catch ($e) { $self->add_error( $e ) }

   return;
}

# Supporting cast
sub clear_controls { # Clear contents of multiple divs
   my $self = shift;

   $self->clear_footer;
   $self->clear_menus;
   $self->clear_quick_links;
   $self->clear_sidebar;
   return;
}

sub form {
   my ($self, @args) = @_;

   my $method = $self->context->stash->{form}->{name}.q(_form);

   return $self->$method( @args );
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
   my ($self, $key, $n_cols) = @_; my $c = $self->context;

   return $c->stash( $key => $self->get_para_col_class( $n_cols || 2 ) );
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
   return $_[ 0 ]->_clear_by_id( q(append), $_[ 1 ] );
}

sub clear_buttons {
   return $_[ 0 ]->_clear_by_id( q(button), $_[ 1 ] );
}

sub clear_footer {
   return $_[ 0 ]->_clear_by_id( q(footer), $_[ 1 ] );
}

sub clear_form { # Clear the stash of all form content
   my ($self, $args) = @_; my $s = $self->context->stash; my $id = q(sdata);

   exists $s->{ $id } and not $args->{force} and return;

   $self->_clear_by_id( $id, $args );

   exists $args->{title}
      and $s->{title} = $s->{header}->{title} = $args->{title};

   $s->{firstfld} = $args->{firstfld} || NUL;
   return;
}

sub clear_header {
   return $_[ 0 ]->_clear_by_id( q(header), $_[ 1 ] );
}

sub clear_hidden {
   return $_[ 0 ]->_clear_by_id( q(hidden), $_[ 1 ] );
}

sub clear_menus {
   return $_[ 0 ]->_clear_by_id( q(menus) );
}

sub clear_quick_links {
   return $_[ 0 ]->_clear_by_id( q(quick_links) );
}

sub clear_result {
   my ($self, $args) = @_; $self->_clear_by_id( q(result), $args );

   $self->context->stash->{result}->{text} = $self->loc( 'Results' );
   return;
}

sub clear_sidebar {
   $_[ 0 ]->context->stash( sidebar => FALSE ); return;
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

sub _get_image_file {
   my ($self, $args, $filename) = @_; $filename or throw 'No image filename';

   state %cache; my $dir = catdir( $args->{skindir}, $args->{skin} );

   0 > index $filename, SPC or $filename =~ s{ \s+ }{_}gmx;

   for my $file (map { "${filename}${_}" } qw(.png .gif)) {
      my $path = catfile( $dir, $file );

      defined $cache{ $path } or $cache{ $path } = -f $path;

      $cache{ $path } and return $file;
   }

   return;
}

sub _get_sidebar_panel_hash {
   my ($self, $args, $name, $count) = @_;

   $name eq q(default) and return {
      class        => q(accordion_content heading),
      container_id => q(glassPanel),
      header       => {
         class     => q(accordion_header),
         id        => "${name}Header",
         text      => $self->loc( q(sidebarBlankHeader) ) },
      id           => $name,
      panel        => {
         class     => q(accordion_panel),
         id        => "panel${count}Content" },
      text         => $self->loc( q(sidebarBlankContent) ),
      type         => q(sidebarPanel) };

   my $action = $name.($args->{action} ? SEP.$args->{action} : NUL);

   return { config       => {
               action    => "'${action}'",
               name      => "'${name}'" },
            container_id => "${name}Panel",
            header       => {
               class     => q(accordion_header),
               id        => "${name}Header",
               text      => $self->loc( $args->{heading} || ucfirst $name ) },
            id           => $name,
            panel        => {
               class     => q(accordion_panel),
               id        => "panel${count}Content" },
            text         => SPC, # Heisenbug last spotted here
            type         => q(sidebarPanel) };
}

sub _hash_for_async_footer {
   my $self = shift; my $c = $self->context; my $s = $c->stash;

   my $id       = q(footer.data);
   my $action   = $c->action->reverse;
   my $function = 'function() { this.rebuild() }';
   my $args     = "[ 'footer', '${id}', '${action}', ${function} ]";

   return { class            => q(footer_item_panel server),
            config           => [ {
               'tools0item1' => {
                  method     => "'request'", args => $args, } }, {
               'footer.data' => {
                  event      => "'load'",
                  method     => "'requestIfVisible'", args => $args, } }, ],
            id               => $id,
            text             => NBSP,
            type             => q(async) };
}

sub _hash_for_footer_line { # Cut on the dotted line toggle the footer visibilty
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

sub _new_chooser_grid_table {
   my ($self, $args, $values) = @_;

   return $self->table_class->new( {
      class    => { item     => q(grid_cell),
                    item_num => q(grid_cell lineNumber first), },
      count    => scalar @{ $values },
      fields   => [ qw(item_num item) ],
      hclass   => { item     => q(grid_header most),
                    item_num => q(grid_header minimal first), },
      labels   => { item     => $self->loc( $args->{label} || 'Select Item' ),
                    item_num => HASH_CHAR, },
      typelist => { item_num => q(numeric), },
      values   => $values,
   } );
}

# Private functions
sub __get_field_count {
   my ($sid, $nitems) = @_; $nitems ||= $sid->{count} - $sid->{mark} - 1;

   (not $nitems or $nitems <= 0) and return FALSE; $sid->{mark} = $sid->{count};

   return $nitems;
}

sub __get_or_throw {
   my ($args, $attr) = @_;

   defined $args->{ $attr }
      or throw error => 'Method [_1] called, attribute [_2] missing',
               args  => [ sub_name( 1 ), $attr ];

   return $args->{ $attr };
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TraitFor::Model::StashHelper - Convenience methods for stuffing the stash

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   package CatalystX::Usul::Model;

   use CatalystX::Usul::Moose;

   extends q(Catalyst::Model);
   with    q(CatalystX::Usul::TraitFor::Model::StashHelper);

=head1 Description

Many convenience methods for stuffing/resetting the stash. The form
widget definitions will be replaced later by the form building method
which is called from the HTML view

=head1 Subroutines/Methods

=head2 add_append

   $self->add_append( $content );

Stuff some content into the stash so that it will appear in the C<append>
div in the template. The content is a hash ref which will be
interpreted as a widget definition by the form builder which is
invoked by the HTML view. Multiple calls push the content onto a stack
which is rendered in the order in which items were added

=head2 add_button

   $self->add_button( $args_hash_ref );

Add a button definition to the stash. The template will render these
as image buttons on the C<button> div

=head2 add_buttons

   $self->add_buttons( @button_labels );

Loop around L</add_button>

=head2 add_chooser

   $self->add_chooser( $args_hash_ref );

Generates the data for the popup chooser window which allows a data value to
be selected from a list produced by some query. It is intended as a
replacement for a popup menu widget where the list of values would be
prohibitively long

=head2 add_chooser_grid_rows

   $self->add_chooser_grid_rows( $args_hash_ref );

=head2 add_chooser_grid_table

   $self->add_chooser_grid_table( $args_hash_ref );

=head2 add_error

   $self->add_error( $error );

Stringifies the passed error object, localises the text, logs it as an error
and calls L</add_result> to display it at the top of the C<sdata> div

=head2 add_field

   $self->add_field( $content, $id, $clear, $stack_dirn );

Create a widget definition for a form field. Sets C<< $content->{widget> >>
to true and calls L</stash_content>

=head2 add_footer

   $self->add_footer;

Adds data for a horizontal rule to separate the footer from the rest of the
content. Add data to asynchronously load the footer data

=head2 add_hidden

   $self->add_header( $name, $values );

Adds one or more C<hidden> fields to the form. The C<$values> argument
can be either a scalar or an array ref

=head2 add_result

   $self->add_result( $content );

Adds the result of forwarding to an an action. This is the C<result>
div in the template

=head2 add_result_msg

   $self->add_result_msg( $message, $args );

Localises the message text and calls L</add_result>. If C<$message> is
an array ref then messages are localised and L</add_result> called for
each array ref in the list

=head2 add_search_hit

   $self->add_search_hit( $hit, $link_num, $field );

Placeholder should have been implemented in the class that applies
this role. It should add the link to the page of search results

=head2 add_search_links

   $self->add_search_links( $page_info, $attrs );

Adds the sequence of links used in search page results; first page, previous
page, list of pages around the current one, next page, and last page

=head2 add_sidebar_panel

   $count = $self->add_sidebar_panel( \%args );

Stuffs the stash with the data necessary to create a panel in the
accordion widget on the sidebar. Returns the number of the newly created
panel

=head2 clear_append

   $self->clear_append( \%args );

Clears the stash of the widget data used by the region appended to the
main data store. Calls L</_clear_by_id> with an C<id> of C<append>

=head2 clear_buttons

   $self->clear_buttons( \%args );

Clears button data from the stash. Calls L</_clear_by_id> with an
C<id> of C<buttons>

=head2 clear_controls

   $self->clear_controls;

Groups the methods that clear the stash of data not used in a minority
of pages.  Calls; L</clear_footer>, L</clear_menus>,
L</clear_quick_links>, and L</clear_sidebar>

=head2 clear_footer

   $self->clear_footer( \%args );

Clears all footer data. Called by L</add_footer>. Calls
L</_clear_by_id> with an C<id> of C<footer>

=head2 clear_form

   $self->clear_form( \%args );

Initialises the C<sdata> stack contents. Called by C</stash_content>
on first use. Calls L</_clear_by_id>. The args hash may contain;
C<force> which clears the stack even if it contains data, C<title>
which is used to set C<< $c->stash->{title} >> and
C<< $c->stash->{header}->{title} >>, and C<firstfld> which is used to set
C<< $c->stash->{firstfld} >>

=head2 clear_header

   $self->clear_header( \%args );

Clears all header data. Called by L</add_header>. Calls
L</_clear_by_id> with an C<id> of C<header>

=head2 clear_hidden

   $self->clear_header( \%args );

Clears all hidden data. Called by L</add_hidden>. Calls
L</_clear_by_id> with an C<id> of C<hidden>

=head2 clear_menus

   $self->clear_menus;

Clears the stash of the main navigation and tools menu data. Calls
L</_clear_by_id> with an C<id> of C<menus>

=head2 clear_quick_links

   $self->clear_quick_links;

Clears the stash of the quick links navigation data. Calls
L</_clear_by_id> with an C<id> of C<quick_links>

=head2 clear_result

   $self->clear_result( \%args );

Clears the stash of messages from the output of actions. Calls
L</_clear_by_id> with an C<id> of C<result>. Stash the localised phrase
for the legend on the fieldset

=head2 clear_sidebar

   $self->clear_sidebar;

Clears the stash of the data used by the sidebar accordion widget

=head2 form

   $self->form( @args );

Calls the form method to stuff the stash with the data for the
requested form. Uses the C<< $c->stash->{form}->{name} >> value to
construct the method name

=head2 form_wrapper

   $self->form_wrapper( \%args );

Stashes the data used by L<HTML::FormWidgets> to throw C<form> around
a group of fields

=head2 get_para_col_class

   $column_class = $model_obj->get_para_col_class( $n_columns );

Converts an integer number into a string representation

=head2 group_fields

   $self->group_field( \%args );

Stashes the data used by L<HTML::FormWidgets> to throw a C<fieldset> around
a group of fields

=head2 search_for

   $hits_object = $self->search_for( \%args );

Placeholder returns an instance of L<Class::Null>. Should have been
implemented in the interface model subclass

=head2 search_page

   $self->search_page( \%args );

Create a results page containing the previous and next links from
L<Data::Pageset> and the list links from calling L</search_for>

=head2 stash_content

   $self->stash_content( $content, $id, $clear, $stack_dirn );

Pushes the content (usually a widget definition) onto the specified
stack.  Defaults C<$id> to C<sdata> (the stash key of the content
stack) and C<$clear> to L</clear_form>. The clear method is called to
instantiate the stack on first use. A unique id is added to the stack
item and a count of the number of stack items is incremented. The optional
stack direction if true unshifts the item onto the stack as opposed to
the default which pushes the item onto the stack

=head2 stash_meta

   $self->stash_meta( $content, $id, $clear );

Adds some meta data to the response for an Ajax call

=head2 stash_para_col_class

   $column_class = $model_obj->stash_para_col_class( $key, $n_columns );

Calls and returns the value from L</get_para_col_class>. Also stashes the
value in the C<$key> attribute

=head2 update_group_membership

   $bool = $model_obj->update_group_membership( \%args );

Adds/removes lists of attributes from groups

=head1 Private Methods

=head2 _clear_by_id

   $self->_clear_by_id( $stack_id, $args );

Clears the specified stack of any items that have been added to it

=head2 _hash_for_footer_line

   $self->_hash_for_footer_line;

Adds a horizontal rule to separate the footer. Called by L</add_footer>

=head1 Configuration and Environment

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Data::Pageset>

=item L<Moose::Role>

=item L<TryCatch>

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
