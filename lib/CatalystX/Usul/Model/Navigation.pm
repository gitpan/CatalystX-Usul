# @(#)$Id: Navigation.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Model::Navigation;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(is_member merge_attributes);
use CatalystX::Usul::Table;
use English qw(-no_match_vars);
use TryCatch;

__PACKAGE__->config( action_class        => q(Config::Rooms),
                     action_source       => q(action),
                     default_action      => DEFAULT_ACTION,
                     menu_link_class     => q(menu_link fade),
                     menu_selected_class => q(menu_selected fade),
                     menu_title_class    => q(menu_title fade),
                     namespace_source    => q(namespace),
                     namespace_tag       => q(..Level..),
                     user_level_access   => FALSE,
                     _nav_link_cache     => {},
                     _quick_link_cache   => {} );

__PACKAGE__->mk_accessors( qw(action_class action_source default_action
                              menu_link_class menu_selected_class
                              menu_title_class namespace_source
                              namespace_tag skins user_level_access
                              _nav_link_cache _quick_link_cache) );

sub COMPONENT {
   my ($class, $app, $attrs) = @_; my $ac = $app->config;

   merge_attributes $attrs, $ac, $class->config, [ qw(default_action) ];

   my $new = $class->next::method( $app, $attrs );

   $new->skins( [ map { $_->filename } $new->io( $ac->{skindir} )->all_dirs ] );

   return $new;
}

sub access_check {
   # Return non zero to prevent access to requested endpoint
   # The return code indicates the reason
   my ($self, $source, $key) = @_; my $s = $self->context->stash; my %roles;

   # Administrators are always allowed access
   $s->{is_administrator} and return ACCESS_OK;

   # Get the list of allowed users and groups from the stash
   my $action  = exists $s->{ $source }->{ $key }
               ? $s->{ $source }->{ $key } : {};
   my @allowed = @{ $action->{acl} || [] };

   # Cannot obtain a list of users/groups for this endpoint
   $allowed[ 0 ] or return ACCESS_NO_UGRPS;

   for my $ugrp (@allowed) {
      # Public access or granted access to the user specifically
      ($ugrp eq q(any) or $ugrp eq $s->{user}) and return ACCESS_OK;

      # Anon. access is now denied
      $s->{user} eq q(unknown) and return ACCESS_UNKNOWN_USER;

      if (q(@) eq substr $ugrp, 0, 1) { # This is a group not a user
         unless (exists $roles{_seeded}) { # Create a hash lookup
            %roles = map { $_ => TRUE } @{ $s->{roles} }, q(_seeded);
         }

         # User is in a role that has access to the endpoint
         exists $roles{ substr $ugrp, 1 } and return ACCESS_OK;
      }
   }

   # We don't like your kind around here...
   return ACCESS_DENIED;
}

sub access_control_form {
   my ($self, $ns, $name) = @_; my $s = $self->context->stash; my $data = {};

   my $new_tag = $s->{newtag}; $ns ||= q(default); $name ||= $new_tag;

   try        { $data = $self->_get_access_data( $ns, $name ) }
   catch ($e) { return $self->add_error( $e ) }

   my $form = $s->{form}->{name};

   # Build the form
   $self->clear_form  ( { firstfld => $form.q(.).$self->action_source } );
   $self->add_field   ( { default  => $ns,
                          id       => q(config.).$self->namespace_source,
                          values   => $data->{nspaces} } );
   $ns and $ns ne $new_tag and
      $self->add_field( { default  => $name,
                          id       => $form.q(.).$self->action_source,
                          values   => $data->{actions} } );
   $self->group_fields( { id       => $form.q(.select) } );

   ($ns and $ns ne $new_tag and $name
        and is_member $name, $data->{actions}) or return;

   my $labels = { ACTION_OPEN()    => $self->loc( 'open'   ),
                  ACTION_HIDDEN()  => $self->loc( 'hidden' ),
                  ACTION_CLOSED()  => $self->loc( 'closed' ), };

   $self->add_field   ( { default  => $data->{state},
                          id       => $form.q(.state),
                          labels   => $labels,
                          values   => [ ACTION_OPEN,
                                        ACTION_HIDDEN,
                                        ACTION_CLOSED, ], } );
   $self->group_fields( { id       => $form.q(.state) } );
   $self->add_field   ( { all      => $data->{ugrps},
                          current  => $data->{acl},
                          id       => $form.q(.user_groups) } );
   $self->group_fields( { id       => $form.q(.add_remove) } );
   $self->add_buttons ( qw(Set Update) );
   return;
}

sub add_header {
   my $self = shift; my $s = $self->context->stash;

   $self->maybe::next::method();

   $self->add_nav_menu; $self->add_utils_menu; $self->add_quick_links;

   $self->stash_meta( { title => $s->{title} }, q(header) );
   return;
}

sub add_help_menu {
   my ($self, $name, $stack, $menu) = @_;

   my $c = $self->context; my $s = $c->stash;

   my $title = $self->loc( q(helpOptionTip) ); my $item = 0;

   # Help options
   $self->_push_menu_link( $stack, $menu, {
      class    => $name.q(_title fade),
      href     => '#top',
      id       => $name.$menu.q(item).$item++,
      imgclass => 'help_icon',
      sep      => NUL,
      text     => NUL,
      tip      => DOTS.TTS.$title } );

   # Context senitive help page generated from pod in the controller
   $self->_push_menu_link( $stack, $menu, {
      class    => $name.q(_link fade windows),
      config   => { args   => "[ '".$s->{help_url}."', { name: 'help' } ]",
                    method => "'openWindow'" },
      href     => '#top',
      id       => $name.$menu.q(item).$item++,
      text     => $self->loc( q(contextHelpText) ),
      tip      => $title.TTS.$self->loc( q(contextHelpTip) ) } );

   # Display window with copyright and distribution information
   my $href    = $c->uri_for_action( SEP.q(about) );

   $self->_push_menu_link( $stack, $menu, {
      class    => $name.q(_link fade windows),
      config   => { args   => "[ '${href}', { name: 'about' } ]",
                    method => "'openWindow'" },
      href     => '#top',
      id       => $name.$menu.q(item).$item++,
      text     => $self->loc( q(aboutOptionText) ),
      tip      => $title.TTS.$self->loc( q(aboutOptionTip) ) } );

   # Send feedback email to site administrators
   $s->{user} eq q(unknown) and return;

   my $opts    = "{ height: 670, name: 'feedback', width: 850 }";

   $href       = $c->uri_for_action
      ( SEP.q(feedback), $c->action->namespace, $c->action->name );

   $self->_push_menu_link( $stack, $menu, {
      class    => $name.q(_link fade windows),
      config   => { args   => "[ '${href}', ${opts} ]",
                    method => "'openWindow'" },
      href     => '#top',
      id       => $name.$menu.q(item).$item++,
      text     => $self->loc( q(feedbackOptionText) ),
      tip      => $title.TTS.$self->loc( q(feedbackOptionTip) ) } );
   return;
}

sub add_menu_back {
   # Add a browser back link to the navigation menu
   my ($self, $args) = @_; $args ||= {};

   my $tip   = $self->loc( $args->{tip} || 'Go back to the previous page' );
   my $menu  = [];

   $self->_push_menu_link( $menu, 0, {
      class  => $self->menu_title_class.q( submit),
      config => { args => "[]", method => "'historyBack'" },
      href   => '#top',
      id     => q(history_back),
      text   => $self->loc( 'Back' ),
      tip    => $self->loc( 'Navigation' ).TTS.$tip } );

   my $content = { data => $menu, id => q(menu), type => q(menu) };

   $self->add_field( $content, qw(menus clear_menus) );
   return;
}

sub add_menu_blank {
   # Stash some padding to fill the gap where the nav. menu was
   my ($self, $args) = @_; $args ||= {}; my $menu = [];

   $self->_push_menu_link( $menu, 0, { class => $self->menu_title_class,
                                       href  => '#top',
                                       text  => NBSP x 30 } );

   my $content = { data => $menu, id => q(menu), type => q(menu) };

   $self->add_field( $content, qw(menus menus_clear) );
   return;
}

sub add_menu_close {
   # Add a close window link to the navigation menu
   my ($self, $args) = @_; $args ||= {};

   my $field = $args->{field} || NUL;
   my $form  = $args->{form } || NUL;
   my $value = $args->{value} || NUL;
   my $tip   = $self->loc( $args->{tip} || 'Close this window' );
   my $menu  = [];

   $self->_push_menu_link( $menu, 0, {
      class  => $self->menu_title_class.q( submit),
      config => { args   => "[ '${form}', '${field}', '${value}' ]",
                  method => "'returnValue'" },
      href   => '#top',
      id     => q(close_window),
      text   => $self->loc( $args->{text } || 'Close' ),
      tip    => $self->loc( $args->{title} || 'Navigation' ).TTS.$tip } );

   my $content = { data => $menu, id => q(menu), type => q(menu) };

   $self->add_field( $content, qw(menus clear_menus) );
   return;
}

sub add_nav_menu {
   # Generate a cone forest
   my $self     =  shift;
   my $sep      =  SEP;
   my $c        =  $self->context;
   my $s        =  $c->stash;
   my $ns       =  $c->action->namespace;
   my $base     =  $c->uri_for_action( $ns.$sep.$self->default_action );
   my $selected =  $s->{form}->{action} || $c->action->name || NUL;
      $selected =~ s{ \A $base $sep }{}msx;
   my $links    =  $self->_get_my_nav_links( $base, $ns, $selected );
   my $title    =  $links->[ 0 ]->{items}->[ 0 ]->{content}->{text};

   $s->{title}  =  $s->{application}.SPC.$title;
   $self->add_field( { data   => $links, id     => q(menu),
                       select => TRUE,   spacer => GT,
                       type   => q(menu) }, qw(menus clear_menus) );
   return;
}

sub add_quick_links {
   my $self  = shift;
   my $s     = $self->context->stash;
   my $links = $self->_quick_link_cache->{ $s->{lang} }
           ||= $self->_get_quick_links;
   my @items = ( map { { q(content) => $_ } } @{ $links } );

   $s->{quick_links} = { items => \@items };
   return;
}

sub add_sidebar_panel {
   my $self = shift;

   return $self->next::method( {
      heading     => $self->loc( 'Navigation' ),
      on_complete => 'function() { this.rebuild() }',
      name        => q(navigation_sidebar), } );
}

sub add_tools_menu {
   my ($self, $name, $stack, $menu) = @_; my $s = $self->context->stash;

   my $title = $self->loc( q(displayOptionsTip) ); my $item = 0;

   $self->_push_menu_link( $stack, $menu, {
      class    => $name.q(_title fade),
      href     => '#top',
      id       => $name.$menu.q(item).$item++,
      imgclass => q(tools_icon),
      sep      => NUL,
      text     => NUL,
      tip      => DOTS.TTS.$title } );

   # Toggle footer visibility
   my $id   = $name.$menu.q(item).$item++;
   my $text = $self->loc( q(footerOffText) );
   my $alt  = $self->loc( q(footerOnText) );

   $self->_push_menu_link( $stack, $menu, {
      class     => $name.q(_link fade server togglers),
      config    => {
         args   => "[ '${id}', 'footer', '${text}', '${alt}' ]",
         method => "'toggleSwapText'" },
      href      => '#top',
      id        => $id,
      text      => $s->{fstate} ? $text : $alt,
      tip       => $title.TTS.$self->loc( q(footerToggleTip) ) } );

   if ($s->{is_administrator}) {
      # Runtime debug option
      $id   = $name.$menu.q(item).$item++;
      $text = $self->loc( q(debugOffText) );
      $alt  = $self->loc( q(debugOnText) );

      $self->_push_menu_link( $stack, $menu, {
         class     => $name.q(_link fade togglers),
         config    => {
            args   => "[ '${id}', 'debug', '${text}', '${alt}' ]",
            method => "'toggleSwapText'" },
         href      => '#top',
         id        => $id,
         text      => $s->{debug} ? $text : $alt,
         tip       => $title.TTS.$self->loc( q(debugToggleTip) ) } );
   }

   # Select the default skin
   my $default = $self->context->config->{default_skin};

   $self->_push_menu_link( $stack, $menu, {
      class  => $name.q(_link fade submit),
      config => { args => "[ 'skin', '${default}' ]", method => "'refresh'" },
      href   => '#top',
      id     => $name.$menu.q(item).$item++,
      text   => $self->loc( q(changeSkinDefaultText) ),
      tip    => $title.TTS.$self->loc( q(changeSkinDefaultTip) ) } );

   # Select alternate skins
   for my $skin (grep { $_ ne $default } @{ $self->skins }) {
      $self->_push_menu_link( $stack, $menu, {
         class  => $name.q(_link fade submit),
         config => { args => "[ 'skin', '${skin}' ]", method => "'refresh'" },
         href   => '#top',
         id     => $name.$menu.q(item).$item++,
         text   => (ucfirst $skin).SPC.$self->loc( q(changeSkinAltText) ),
         tip    => $title.TTS.$self->loc( q(changeSkinAltTip) ) } );
   }

   return;
}

sub add_tree_panel {
   my $self = shift; my $name = $self->context->action->name;

   $self->add_field ( { container => FALSE,
                        data      => $self->_get_tree_panel_data,
                        id        => $name.q(_data),
                        type      => q(tree) } );
   $self->stash_meta( { id => $name } );
   return;
}

sub add_utils_menu {
   my $self = shift; my $c = $self->context;

   my $item = 0; my $menu = 0; my $name = q(tools); my @stack = ();

   $self->add_tools_menu( $name, \@stack, $menu++ );
   $self->add_help_menu ( $name, \@stack, $menu++ );

   # Logout option drops current identity
   unless ($self->context->stash->{user} eq q(unknown)) {
      $self->_push_menu_link( \@stack, $menu, {
         class    => $name.q(_title fade windows),
         config   => { args   => "[ '".$c->req->base."' ]",
                       method => "'wayOut'" },
         href     => '#top',
         id       => $name.$menu.q(item).$item++,
         imgclass => q(exit_icon),
         sep      => NUL,
         text     => NUL,
         tip      => DOTS.TTS.$self->loc( q(exitTip) ) } );
   }

   my $content = { data   => \@stack, id   => q(tools),
                   select => FALSE,   type => q(menu) };

   $self->add_field( $content, qw(menus clear_menus) );
   return;
}

sub allowed {
   # Negate the logic of the access_check method
   my ($self, @rest) = @_; return not $self->access_check( @rest );
}

sub app_closed_form {
   my $self = shift; my $form = $self->context->stash->{form}->{name};

   $self->add_field  ( { id => $form.q(.user)   } );
   $self->add_field  ( { id => $form.q(.passwd) } );
   $self->add_hidden ( $form, 0 );
   $self->add_buttons( q(Login) );
   return;
}

sub room_manager_form {
   my ($self, $ns, $name) = @_; my $s = $self->context->stash; my $data = {};

   my $new_tag = $s->{newtag}; $ns ||= $new_tag; $name ||= $new_tag;

   try        { $data = $self->_get_action_data( $ns, $name ) }
   catch ($e) { return $self->add_error( $e ) }

   my $form = $s->{form}->{name}; my $ns_tag = $self->namespace_tag;

   $self->clear_form  ( { firstfld => $form.q(.).$self->namespace_source } );
   $self->add_hidden  ( q(acl), $data->{fields}->acl );
   $self->add_field   ( { default  => $ns,
                          id       => $form.q(.).$self->namespace_source,
                          values   => $data->{nspaces} } );
   $ns and $ns ne $new_tag and
      $self->add_field( { default  => $name,
                          id       => $form.q(.).$self->action_source,
                          values   => $data->{actions} } );
   $self->group_fields( { id       => $form.q(.select) } );

   ($ns and is_member $ns, $data->{nspaces}) or return;
   ($ns eq $new_tag
    or ($name and ($name eq $ns_tag
                   or is_member $name, $data->{actions}))) or return;

   my $nspace = ($ns eq $new_tag) || ($ns eq q(default)) ? NUL : $ns;
   my $action = $name eq $ns_tag  || $name eq $new_tag
              ? $self->default_action : $name;
   my $uri    = eval { $self->context->uri_for_action( $nspace.SEP.$action ) };

   $self->add_field( { id => $form.q(.uri), text => $uri || NUL } );

   if ($data->{is_new}) {
      $self->add_field( { ajaxid => $form.'.name', default => $data->{name} } );
      $self->add_buttons( qw(Insert) )
   }
   else {
      $self->add_hidden( q(name), $data->{name} );
      $self->add_buttons( qw(Save Delete) )
   }

   $self->add_field( { ajaxid  => $form.'.text',
                       default => $data->{fields}->text } );
   $self->add_field( { ajaxid  => $form.'.tip',
                       default => $data->{fields}->tip  } );

   if ($s->{noun} eq q(action)) {
      $self->add_field( { id      => $form.q(.keywords),
                          default => $data->{fields}->keywords   } );
      $self->add_field( { id      => $form.q(.quick_link),
                          default => $data->{fields}->quick_link } );
      $self->add_field( { id      => $form.q(.pwidth),
                          default => $data->{fields}->pwidth     } );
   }

   $self->group_fields( { id => $form.q(.edit) } );
   return;
}

sub select_this {
   my ($self, $mitem, $ord, $widget) = @_; my $s = $self->context->stash;

   my $menu = $s->{menus}->{items}->[ $mitem ]->{content}->{data};

   $menu->[ 0 ]->{selected} = $ord; $widget or return;

   $widget->{class    } ||= $self->menu_selected_class;
   $widget->{container} ||= FALSE;
   $widget->{type     } ||= q(anchor);
   $widget->{widget   } ||= TRUE;
   $self->_unshift_menu_item( $menu, $ord, $widget );
   return;
}

sub sitemap {
   my $self = shift; my $s = $self->context->stash; my $data;

   try        { $data = $self->_get_sitemap_data }
   catch ($e) { return $self->add_error( $e ) }

   $self->clear_form( {
      heading      => $self->loc( q(sitemap_heading) ),
      sub_heading  => { class   => q(banner),
                        content => $self->loc( q(sitemap_subheading) ),
                        level   => 2, }, } );
   $self->add_field ( { data => $data, id => $s->{form}->{name} } );
   return;
}

# Private methods;

sub _action_allowed {
   my ($self, $action_info) = @_;

   ($action_info and not $action_info->state) or return FALSE;

   my $name = $action_info->name; my $s = $self->context->stash;

   $s->{_temp_action}->{ $name } = $action_info;

   $self->allowed( q(_temp_action), $name ) or return FALSE;

   delete $s->{_temp_action};
   return TRUE;
}

sub _add_action_link {
   my ($self, $args, $name, $action_info) = @_;

   my $c = $self->context; my $sep = SEP; my $base = $args->{base};

   my $path = eval { $c->uri_for_action( $args->{myspace}.$sep.$name ) };

   if ($path) { $path =~ s{ \A $base $sep }{}mx }
   else { $path = $name }

   my ($is_first, $is_link, $path_len) = __link_flags( $args, $path );

   ($is_first or $is_link) and not defined $args->{menus}->[ $path_len ]
      and $args->{menus}->[ $path_len ] = { items => [] };

   my $menu  = $args->{menus}->[ $path_len ] or return;
   my $class = $is_first
            && $path_len == $args->{s_len} ? $self->menu_selected_class
             : $is_first                   ? $self->menu_title_class
                                           : $self->menu_link_class;
   my $text  = $action_info->{text} || ucfirst $name;
   my $tip   = $action_info->{tip } || NUL;
   my $item  = { action    => $name,
                 namespace => $args->{myspace},
                 content   => { class     => $class,
                                container => FALSE,
                                href      => $base.$sep.$path.$args->{query},
                                text      => $text,
                                tip       => $args->{title}.TTS.$tip,
                                type      => q(anchor),
                                widget    => TRUE } };

   if ($is_first) {
      $menu->{items}->[ 0 ] and
         $menu->{items}->[ 0 ]->{content}->{class} = $self->menu_link_class;
      unshift @{ $menu->{items} }, $item;
   }
   elsif ($is_link) { push @{ $menu->{items} }, $item }

   return;
}

sub _add_namespace_link {
   my ($self, $args, $ns, $ns_info) = @_; $ns_info ||= {};

   my $c    = $self->context;
   my $text = $ns_info->{text} || ucfirst $ns;
   my $tip  = $args->{title}.TTS.($ns_info->{tip} || NUL);

   if ($ns eq $args->{myspace}) {
      # This is the currently selected controller on the navigation tool
      my $content = $args->{menus}->[ 0 ]->{items}->[ 0 ]->{content};

      $content->{text} = $text; $content->{tip} = $tip;
   }
   else {
      # Just another registered controller
      $self->_push_menu_link( $args->{menus}, 0, {
         class => $self->menu_link_class,
         href  => $c->uri_for_action( $ns.SEP.$self->default_action ),
         text  => $text,
         tip   => $tip }, { namespace => $ns } );
   }

   return;
}

sub _get_access_data {
   my ($self, $ns, $name) = @_; my $s = $self->context->stash; my $data = {};

   my $ns_tag = $self->namespace_tag;
   my $noun   = ! $ns || $name eq $ns_tag ? q(controller) : q(action);

   $s->{info} = $noun eq q(controller) ? $ns : $name; $s->{noun} = $noun;

   my $rs     = $s->{namespace_model}->list
      ( ! $ns || $ns eq $s->{newtag} ? q(default) : $ns);

   $data->{nspaces} = [ NUL, q(default), @{ $rs->list} ];
   $noun eq q(controller) and $data->{acl} = $rs->result->acl;

   if ($ns and $ns ne $s->{newtag}) {
      $rs              = $s->{name_model}->list( $ns, $name );
      $data->{actions} = [ NUL, $ns_tag, @{ $rs->list } ];
      $data->{state  } = $rs->result->state || ACTION_OPEN;

      $noun eq q(action) and $data->{acl} = $rs->result->acl;
   }
   else {
      $data->{acl    } = [];
      $data->{actions} = [ NUL, $ns_tag ];
      $data->{state  } = ACTION_OPEN;
   }

   my @ugrps = ();

   for my $model (@{ $s->{auth_models} }) {
      for my $grp ($model->roles->get_roles( q(all) )) {
         is_member q(@).$grp, $data->{acl} or push @ugrps, q(@).$grp;
      }

      $self->user_level_access or next;

      my $users = $model->users->retrieve( q([^\?]+), NUL )->user_list;

      for my $user (@{ $users }) {
         is_member $user, $data->{acl} or push @ugrps, $user;
      }
   }

   @ugrps = sort @ugrps;

   is_member q(any), $data->{acl} or unshift @ugrps, q(any);

   $data->{ugrps} = \@ugrps;
   return $data;
}

sub _get_action_data {
   my ($self, $ns, $name) = @_; my $s = $self->context->stash; my $data = {};

   my $new_tag = $s->{newtag};
   my $ns_tag  = $self->namespace_tag;
   my $noun    = ! $ns || $ns eq $new_tag || $name eq $ns_tag
               ? q(controller) : q(action);
   my $is_new  = ($ns && $ns eq $new_tag) || ($name && $name eq $new_tag);

   $s->{info}  = $noun eq q(controller) ? $ns : $name; $s->{noun} = $noun;

   my $res     = $s->{namespace_model}->list( $ns );

   $data->{nspaces} = [ NUL, $new_tag, q(default), @{ $res->list } ];
   $data->{fields } = $res->result;

   if ($ns and $ns ne $new_tag) {
      $res = $s->{name_model}->list( $ns, $name );

      $data->{actions} = [ NUL, $ns_tag, $new_tag, @{ $res->list } ];
      $name ne $ns_tag and $data->{fields} = $res->result;
   }

   defined $data->{fields}->acl or $data->{fields}->acl( [ NUL ] );

   $data->{name  } = $is_new ? NUL : ($noun eq q(controller) ? $ns : $name);
   $data->{is_new} = $is_new;
   return $data;
}

sub _get_action_info {
   my ($self, $base, $ns) = @_; my $c = $self->context; my $s = $c->stash;

   my $model = $c->model( $self->action_class );

   my %action_info = (); my $sep = SEP;

   for my $action_info ($model->search( $ns )) {
      my $name = $action_info->name; my $uri;

      $uri = $c->uri_for_action( $ns.$sep.$name )
         and $uri =~ s{ \A $base $sep }{}mx;

      $action_info{ $uri || $name } = $action_info;
   }

   return %action_info;
}

sub _get_my_nav_links {
   my ($self, $base, $ns, $selected) = @_;

   my $s     = $self->context->stash;
   my $key   = $s->{lang}.$SUBSEP.$ns.$SUBSEP.$selected;
   my $cache = $self->_nav_link_cache->{ $key }
           ||= $self->_get_nav_links( $base, $ns, $selected );
   my $first = TRUE;
   my $links = [];

   for my $menu (@{ $cache }) {
      my $copy          = { %{ $menu } };
         $copy->{items} = [ grep { $self->_is_visible( $first, $_ ) }
                                @{ $menu->{items} } ];

      push @{ $links }, $copy; $first = FALSE;
   }

   return $links;
}

sub _get_nav_links {
   my ($self, $base, $myspace, $selected) = @_;

   my $links  = [];
   my $s      = $self->context->stash;
   my @s_list = __split_on_sep( $selected );
   my $args   = { base     => $base,
                  menus    => $links,
                  myspace  => $myspace,
                  query    => NUL,
                  s_len    => scalar @s_list,
                  s_list   => \@s_list,
                  selected => $selected,
                  title    => $self->loc( 'Navigation' ) };

   $self->_push_menu_link( $links, 0, {
      class => $self->menu_title_class,
      href  => $base,
      text  => ucfirst $myspace,
      tip   => NUL }, { namespace => $myspace } );

   while (my ($ns, $ns_info) = each %{ $s->{ $self->namespace_source } }) {
      $self->_add_namespace_link( $args, $ns, $ns_info );
   }

   while (my ($action, $action_info) = each %{ $s->{ $self->action_source } }) {
      $action_info and $self->_add_action_link( $args, $action, $action_info );
   }

   return $self->_sort_links( $links );
}

sub _get_quick_links {
   my $self  = shift; my $c = $self->context; my $links = [];

   my $model = $c->model( $self->action_class );
   my $title = $self->loc( 'Navigation' );

   for my $ns (keys %{ $c->stash->{ $self->namespace_source } }) {
      for my $result ($model->search( $ns, { quick_link => { '>' => 0 } } )) {
         my $name = $result->name;

         push @{ $links }, { class     => q(header_link fade),
                             container => FALSE,
                             href      => $c->uri_for_action( $ns.SEP.$name ),
                             id        => $name.q(_quick_link),
                             sort_by   => $result->quick_link,
                             text      => $result->text || ucfirst $name,
                             tip       => $title.TTS.($result->tip || NUL),
                             type      => q(anchor),
                             widget    => TRUE };
      }
   }

   return [ sort { $a->{sort_by} <=> $b->{sort_by} } @{ $links } ];
}

sub _get_sitemap_data {
   my $self    = shift; my $c = $self->context;

   my $title   = $self->loc( 'Select Tab' ); my $key = $self->namespace_source;

   my $nspaces = $c->stash->{ $key }; my $data = []; my $index = 0;

   for my $ns (sort { __cmp_text( $nspaces, $a, $b ) } keys %{ $nspaces }) {
      my $ns_info  = $nspaces->{ $ns };

      ($ns_info->{state} or not $self->allowed( $key, $ns )) and next;

      my $clicker  = {
         class     => q(tabs fade),
         container => FALSE,
         href      => '#top',
         text      => $ns_info->{text} || ucfirst $ns,
         tip       => $title.TTS.($ns_info->{tip} || NUL),
         type      => q(anchor),
         widget    => TRUE };
      my $section  = {
         data      => $self->_get_sitemap_table( $ns ),
         id        => $ns.q(_map),
         type      => q(table),
         widget    => TRUE };

      $data->[ $index++ ] = { clicker => $clicker, section => $section };
   }

   return $data;
}

sub _get_sitemap_table {
   my ($self, $ns) = @_; my $c = $self->context; my $s = $c->stash;

   my $base    = $c->uri_for_action( $ns.SEP.$self->default_action ) || NUL;
   my $c_no    = 0; my $first  = TRUE; my $field = NUL; my $fields = {};
   my $lastc   = 0; my $n_cols = 0;    my $sep = SEP;
   my $table   = CatalystX::Usul::Table->new
      ( flds   => [ q(controller) ], labels => { controller => 'Controller' } );
   my $title   = $self->loc( 'Navigation' );
   my $ns_info = $s->{ $self->namespace_source }->{ $ns };
   my %actions = $self->_get_action_info( $base, $ns );

   $fields->{controller} = {
      class     => q(navigation fade),
      container => FALSE,
      href      => $base,
      text      => $ns_info->{text} || ucfirst $ns,
      tip       => $title.TTS.($ns_info->{tip} || NUL),
      type      => q(anchor),
      widget    => TRUE };
   push @{ $table->values }, $fields;

   for my $uri_path (sort keys %actions) {
      my $action_info = $actions{ $uri_path };
      my $name        = $action_info->name;

      $self->_action_allowed( $action_info ) or next;

      $c_no                 = () = $uri_path =~ m{ $sep }gmx;
      $n_cols               = $c_no if ($c_no > $n_cols);
      $field                = q(action_).$c_no;
      $fields               = {};
      $fields->{controller} = NUL;
      $fields->{ $field   } = {
         class     => q(navigation fade),
         container => FALSE,
         href      => $base.SEP.$uri_path,
         text      => $action_info->text || ucfirst $name,
         tip       => $title.TTS.($action_info->tip || NUL),
         type      => q(anchor),
         widget    => TRUE };

      if ($first || $c_no > $lastc) {
         $first = FALSE; $lastc = $c_no;
         $table->values->[-1]->{ $field } = $fields->{ $field };
      }
      else {
         $lastc = $c_no;

         while ($c_no > 0) {
            $field = q(action_).--$c_no; $fields->{ $field } = NUL;
         }

         push @{ $table->values }, $fields;
      }
   }

   my $width = $table->widths->{controller} = (int 100 / (2 + $n_cols)).q(%);

   for $field (map { q(action_).$_ } 0 .. $n_cols) {
      push @{ $table->flds }, $field;
      $table->labels->{ $field } = 'Actions';
      $table->widths->{ $field } = $width;
   }

   return $table;
}

sub _get_tree_panel_data {
   my $self = shift; my $c = $self->context; my $s = $c->stash;

   my $key  = $self->namespace_source; my $nspaces = $s->{ $key };

   my $root = q(Site Map); my $data = { $root => {} }; my $sep = SEP;

   for my $ns (sort { __cmp_text( $nspaces, $a, $b ) } keys %{ $nspaces }) {
      my $ns_info = $nspaces->{ $ns };

      ($ns_info->{state} or not $self->allowed( $key, $ns )) and next;

      my $base = $c->uri_for_action( $ns.$sep.$self->default_action ) || NUL;
      my %action_info = $self->_get_action_info( $base, $ns );

      $data->{ $root }->{ $ns } = {
         _text => $ns_info->{text} || ucfirst $ns,
         _tip  => $ns_info->{tip } || NUL,
         _url  => $base,
      };

      for my $uri_path (sort keys %action_info) {
         my $action_info = $action_info{ $uri_path };
         my $cursor      = $data->{ $root }->{ $ns };

         $self->_action_allowed( $action_info ) or next;

         for my $ent (__split_on_sep( $uri_path )) {
            exists $cursor->{ $ent } or $cursor->{ $ent } = {};

            $cursor = $cursor->{ $ent };
         }

         my $name = $action_info->name;

         $cursor->{_text} = $action_info->text || ucfirst $name;
         $cursor->{_tip } = $action_info->tip  || NUL;
         $cursor->{_url } = $base.$sep.$uri_path;
      }
   }

   return $data;
}

sub _is_in_open_state {
   my ($self, $source, $key) = @_; my $s = $self->context->stash;

   my $action = exists $s->{ $source } && exists $s->{ $source }->{ $key }
              ? $s->{ $source }->{ $key } : {};

   return ($action->{state} || ACTION_OPEN) == ACTION_OPEN ? TRUE : FALSE;
}

sub _is_visible {
   my ($self, $flag, $item) = @_;

   my $source = $flag ? $self->namespace_source : $self->action_source;
   my $key    = $flag ? $item->{namespace}      : $item->{action};

   return $self->_is_in_open_state( $source, $key || NUL )
       && $self->allowed( $source, $key || NUL );
}

sub _push_menu_link {
   # Add a link to the navigation menu
   my ($self, $menu, $ord, $ref, $opts) = @_;

   $menu ||= []; $ord ||= 0; $ref ||= {};

   $ref->{container} = FALSE; $ref->{type} = q(anchor); $ref->{widget} = TRUE;

   $ref = { content => $ref };

   if ($opts) { $ref->{ $_ } = $opts->{ $_ } for (keys %{ $opts }) }

   push @{ $menu->[ $ord ]->{items} }, $ref;
   return;
}

sub _sort_links {
   my ($self, $links) = @_; my $count = 0;

   my $selected = $links->[ 0 ]->{selected} || 0;

   for my $menu (@{ $links }) {
      my $items = $menu->{items} or next; my $first;

      if ($count++ <= $selected) { $first = shift @{ $items } }
      else { $items->[ 0 ]->{content}->{class} = $self->menu_link_class }

      @{ $items } =
         sort { lc $a->{content}->{text} cmp lc $b->{content}->{text} }
         @{ $items };

      if ($first) { unshift @{ $items }, $first }
      else { $items->[ 0 ]->{content}->{class} = $self->menu_title_class }
   }

   return $links;
}

sub _unshift_menu_item {
   my ($self, $menu, $ord, $args, $opts) = @_;

   $menu ||= []; $ord ||= 0; $args = $args ? { content => $args } : {};

   if ($opts) { $args->{ $_ } = $opts->{ $_ } for (keys %{ $opts }) }

   my $items = $menu->[ $ord ]->{items};

   $items->[0] and $items->[0]->{content}->{class} = $self->menu_link_class;

   unshift @{ $items }, $args;
   return;
}

# Private subroutines

sub __cmp_text {
   return ($_[ 0 ]->{ $_[ 1 ] }->{text} || $_[ 1 ])
      cmp ($_[ 0 ]->{ $_[ 2 ] }->{text} || $_[ 2 ]);
}

sub __link_flags {
   my ($args, $path) = @_;

   my $p_list   = [ __split_on_sep( $path ) ];
   my $p_len    = scalar @{ $p_list };
   my $selected = $args->{selected};
   my $s_len    = $args->{s_len};

   if ($path eq $selected) {
      $args->{menus}->[ 0 ]->{selected} = $s_len; # Side effect
      return (TRUE, FALSE, $p_len);
   }

   if ($p_len > $s_len) {
      $p_len == $s_len + 1
         and $selected eq substr $path, 0, length $selected
         and return (TRUE, FALSE, $p_len);

      return (FALSE, FALSE, $p_len);
   }

   $p_len < $s_len and $path eq substr $selected, 0, length $path
      and return (TRUE, FALSE, $p_len);

   return (FALSE, __match_paths( $args->{s_list}, $p_len, $p_list ), $p_len);
}

sub __match_paths {
   my ($s_list, $p_len, $p_list) = @_; $p_len == 1 and return TRUE;

   for my $i (0 .. $p_len - 2) {
      $p_list->[ $i ] ne $s_list->[ $i ] and return FALSE;
   }

   return TRUE;
}

sub __split_on_sep {
   my $sep = SEP; return split m{ $sep }mx, $_[ 0 ] || NUL;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Navigation - Navigation links and access control

=head1 Version

0.6.$Revision: 1165 $

=head1 Synopsis

   package MyApp;

   use Catalyst qw(ConfigComponents);

   # In the application configuration file
   <component name="Model::Navigation">
      <base_class>CatalystX::Usul::Model::Navigation</base_class>
   </component>

=head1 Description

Provides methods for creating navigation links and access control

=head1 Subroutines/Methods

=head2 COMPONENT

Called by Catalyst when the application starts it sets the default action
from global config and sets up the list of available skins

=head2 access_check

   $state = $c->model( q(Navigation) )->access_check( @args );

Expects to be passed the stash (C<< $c->stash >>), a key to search in
the stash (C<$args[0]>) and a level or room to search for
(C<$args[1]>). It returns 0 if the ACL on the requested level/room
permits access to the current user. It returns 1 if no ACL was
found. It returns 2 if the current user is unknown and the
level/room's ACL did not contain the value I<any> which would permit
anonymous access. It returns 3 if the current user is explicitly
denied access to the selected level/room

This method is called from C</add_nav_menu> (via the C</allowed>
method which negates the result) to determine which levels the current
user has access to. It is also called by B</auto> to determine if
access to the requested endpoint is permitted

It could also be used from an application controller method to allow
the display logic to display content based on the users identity

=head2 access_control_form

   $c->model( q(Navigation) )->form( $namespace, $name );

Stuffs the stash with the data for the form that controls access to
levels and rooms

=head2 add_header

   $c->model( q(Navigation) )->add_header;

Calls parent method. Adds main and tools menu data. Adds quick link data

Calls L</add_nav_menu>. This is the main navigation menu

Calls L</add_utils_menu>

Calls L<add_quick_links>. Quick links appear in the header and are
selected from the I<rooms> config items if the I<quick_link> element
is set. It's numeric value determines the sort order of the links

=head2 add_help_menu

Help menu options

=head2 add_footer

Adds some useful debugging info to the footer

=head2 add_menu_back

   $c->model( q(Navigation) )->add_menu_back( $args );

Adds a history back link to the main navigation menu

=head2 add_menu_blank

   $c->model( q(Navigation) )->add_menu_blank( $args );

Adds some filler to the main navigation menu

=head2 add_menu_close

   $c->model( q(Navigation) )->add_menu_close( $args );

Adds a window close link to the main navigation menu

=head2 add_nav_menu

   $c->model( q(Navigation) )->add_nav_menu;

Returns the data used to generate the main navigation menu. The menu uses
a Cone Trees layout which has been flattened to produce a visual trail
of breadcrumbs effect, i.e. Home > Reception > Tutorial

=head2 add_quick_links

   $links = $c->model( q(Navigation) )->add_quick_links;

Returns the data used to display "quick" navigation links. Caches data
on first use. These usually appear in the header and allow single
click access to any endpoint. They are identified in the configuration
by adding a I<quick_link> attribute to the I<rooms> element. The
I<quick_link> attribute value is an integer which determines the
display order

=head2 add_sidebar_panel

Adds a sidebar panel containing a tree widget that represents all the
action available in the application (another sitemap)

=head2 add_tools_menu

Utility menu options

=head2 add_tree_panel

   $c->model( q(Navigation) )->add_tree_panel;

Calls L</_get_tree_panel_data> and creates a tree widget using the data. Implements
the navigation sidebar

=head2 add_utils_menu

   $c->model( q(Navigation) )->add_utils_menu;

Returns the stash data for the utilities menu. This contains a selection of
utility options including: toggle runtime debugging, toggle footer,
skin switching, context sensitive help, about popup, email feedback
and logout option. Calls L</add_help_menu> and L</add_tools_menu>

=head2 allowed

   $bool = $c->model( q(Navigation) )->allowed( @args );

Negates the result returned by L</access_check>. Called from
L</add_nav_menu> to determine if a page is accessible to a user. If
the user does not have access then do not display a link to it

=head2 app_closed_form

   $c->model( q(Navigation) )->app_closed_form;

Allows administrators to authenticate and reopen the application

=head2 room_manager_form

   $c->model( q(Navigation) )->room_manager_form( $namespace, $name );

Allows for editing of the level and room definition elements in the
configuration files

=head2 select_this

   $c->model( q(Navigation) )->select_this( $menu_num, $order, $widget );

Make the widget the selected menu item

=head2 sitemap

   $c->model( q(Navigation) )->sitemap;

Displays a table of all the pages on the site

=head2 _get_tree_panel_data

   $data = $c->model( q(Navigation) )->_get_tree_panel_data;

Called by L</sitemap> this method generates the table data used by
L<HTML::FormWidgets>'s C<Tree> subclass

=head2 _get_sitemap_data

   $data = $c->model( q(Navigation) )->_get_sitemap_data;

Called by L</sitemap> this method generates an array of hash refs used by
L<HTML::FormWidgets>'s C<TabSwapper> subclass

=head2 _get_sitemap_table

   $data = $c->model( q(Navigation) )->_get_sitemap_table( $ns );

Called by L</_get_sitemap_data> this method generates the table
data used by L<HTML::FormWidgets>'s C<Table> subclass

=head2 _push_menu_link

   $self->_push_menu_link( $name, $order, $ref );

Pushes an anchor widget C<$ref> onto a menu structure

=head2 _unshift_menu_item

   $self->_unshift_menu_item( $name, $order, $widget );

Unshift an anchor widget onto a menu structure

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::Table>

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

Copyright (c) 2011 Peter Flanigan. All rights reserved

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
