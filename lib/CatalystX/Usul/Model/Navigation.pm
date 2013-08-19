# @(#)Ident: ;

package CatalystX::Usul::Model::Navigation;

use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw( is_member merge_attributes throw );
use CatalystX::Usul::Moose;
use English                    qw( -no_match_vars );
use File::DataClass::IO;
use TryCatch;

extends q(CatalystX::Usul::Model);
with    q(CatalystX::Usul::TraitFor::Model::StashHelper);
with    q(CatalystX::Usul::TraitFor::Model::NavigationLinks);

has 'action_class'        => is => 'ro',   isa => NonEmptySimpleStr,
   default                => q(Config::Rooms);

has 'action_paths'        => is => 'ro',   isa => HashRef,
   default                => sub { {} };

has 'action_source'       => is => 'ro',   isa => NonEmptySimpleStr,
   default                => q(action);

has 'default_action'      => is => 'ro',   isa => NonEmptySimpleStr,
   default                => DEFAULT_ACTION;

has 'menu_link_class'     => is => 'ro',   isa => NonEmptySimpleStr,
   default                => q(menu_link fade);

has 'menu_selected_class' => is => 'ro',   isa => NonEmptySimpleStr,
   default                => q(menu_selected fade);

has 'menu_title_class'    => is => 'ro',   isa => NonEmptySimpleStr,
   default                => q(menu_title fade);

has 'namespace_source'    => is => 'ro',   isa => NonEmptySimpleStr,
   default                => q(namespace);

has 'namespace_tag'       => is => 'ro',   isa => NonEmptySimpleStr,
   default                => q(..Level..);

has 'skins'               => is => 'ro',   isa => ArrayRef, required => TRUE;

has 'user_level_access'   => is => 'ro',   isa => Bool, default => FALSE;


has '_nav_link_cache'   => is => 'ro', isa => HashRef, default => sub { {} };

has '_quick_link_cache' => is => 'ro', isa => HashRef, default => sub { {} };

sub COMPONENT {
   my ($class, $app, $attr) = @_;

   my $ac = $app->config || {}; my $cc = $class->config || {};

   $cc->{skins} = [ map { $_->filename } io( $ac->{skindir} )->all_dirs ];

   merge_attributes $attr, $cc, $ac, [ qw(default_action skins) ];

   return $class->next::method( $app, $attr );
}

sub access_check {
   # Return non zero to prevent access to requested endpoint
   # The return code indicates the reason
   my ($self, $source, $key) = @_; my $s = $self->context->stash;

   # Administrators are always allowed access
   $s->{is_administrator} and return ACCESS_OK;

   # Get the list of allowed users and groups from the stash
   my $action   = exists $s->{ $source }->{ $key }
                ? $s->{ $source }->{ $key } : {};
   my @allowed  = @{ $action->{acl} || [] };
   my $roles    = $s->{user_role_lookup} ||= {};
   my $username = $s->{user}->username;

   # Cannot obtain a list of users/groups for this endpoint
   $allowed[ 0 ] or return ACCESS_NO_UGRPS;

   for my $ugrp (@allowed) {
      # Public access or granted access to the user specifically
      ($ugrp eq q(any) or $ugrp eq $username) and return ACCESS_OK;
      # Anon. access is now denied
      $username eq q(unknown) and return ACCESS_UNKNOWN_USER;

      (q(@) eq substr $ugrp, 0, 1) or next; # Is this a group or a user?

      unless (exists $roles->{_seeded}) { # Create a hash lookup
         $roles = $s->{user_role_lookup}
                = { map { $_ => undef } @{ $s->{user}->roles }, q(_seeded) };
      }
      # User is in a group that has access to the endpoint
      exists $roles->{ substr $ugrp, 1 } and return ACCESS_OK;
   }

   # We don't like your kind around here...
   return ACCESS_DENIED;
}

sub access_control_form {
   my ($self, $ns, $name) = @_; my $s = $self->context->stash; my $access = {};

   my $new_tag = $s->{newtag}; $ns ||= q(default); $name ||= $new_tag;

   try        { $access = $self->_get_access_data( $ns, $name ) }
   catch ($e) { return $self->add_error( $e ) }

   my $form = $s->{form}->{name}; my $id = $form.q(.).$self->action_source;

   # Build the form
   $self->clear_form  ( { firstfld => $id } );
   $self->add_field   ( { default  => $ns,
                          id       => q(config.).$self->namespace_source,
                          values   => $access->{nspaces} } );
   $ns and $ns ne $new_tag and
      $self->add_field( { default  => $name,
                          id       => $id,
                          values   => $access->{actions} } );
   $self->group_fields( { id       => "${form}.select" } );

   ($ns and $ns ne $new_tag and $name
        and is_member $name, $access->{actions}) or return;

   my $labels = { ACTION_OPEN()    => $self->loc( 'open'   ),
                  ACTION_HIDDEN()  => $self->loc( 'hidden' ),
                  ACTION_CLOSED()  => $self->loc( 'closed' ), };

   $self->add_field   ( { default  => $access->{state},
                          id       => "${form}.state",
                          labels   => $labels,
                          values   => [ ACTION_OPEN,
                                        ACTION_HIDDEN,
                                        ACTION_CLOSED, ], } );
   $self->group_fields( { id       => "${form}.state" } );
   $self->add_field   ( { all      => $access->{ugrps},
                          current  => $access->{acl},
                          id       => "${form}.user_groups" } );
   $self->group_fields( { id       => "${form}.add_remove" } );
   $self->add_buttons ( qw(Set Update) );
   return;
}

sub add_menu_back { # Add a browser back link to the navigation menu
   my ($self, $args) = @_; my $stack = []; $args ||= {};

   $self->_push_menu_link( $stack, 0, $self->get_history_back_link( $args ) );

   my $widget = { data => $stack, id => q(menu), type => q(menu) };

   $self->add_field( $widget, qw(menus clear_menus) );
   return;
}

sub add_menu_blank { # Some padding to fill the gap where the nav. menu was
   my $self = shift; my $stack = [];

   $self->_push_menu_link( $stack, 0, $self->get_blank_link );

   my $widget = { data => $stack, id => q(menu), type => q(menu) };

   $self->add_field( $widget, qw(menus clear_menus) );
   return;
}

sub add_menu_close { # Add a close window link to the navigation menu
   my ($self, $args) = @_; my $stack = []; $args ||= {};

   $self->_push_menu_link( $stack, 0, $self->get_close_link( $args ) );

   my $widget = { data => $stack, id => q(menu), type => q(menu) };

   $self->add_field( $widget, qw(menus clear_menus) );
   return;
}

sub add_nav_header {
   my $self = shift; my $s = $self->context->stash;

   my $company_link = $self->get_company_link( { name => q(header) } );

   $self->add_field( $self->get_logo_link, qw(header clear_header) );
   $self->add_field( $company_link, qw(header) );

   $self->add_nav_menu; $self->add_utils_menu; $self->add_quick_links;

   $self->stash_meta( { title => $s->{title} }, q(header) );
   return;
}

sub add_nav_menu { # Generate a cone forest
   my $self  = shift;
   my $c     = $self->context;
   my $s     = $c->stash;
   my $ns    = $c->action->namespace;
   my $name  = $c->action->name;
   my $key   = $s->{language}.$SUBSEP.$ns.$SUBSEP.$name;
   my $cache = $self->_nav_link_cache->{ $key } ||= $self->_get_nav_links;
   my $first = TRUE;
   my $links = [];

   for my $menu (@{ $cache }) {
      my $copy = { %{ $menu } };

      $copy->{items} = [ grep { $self->_is_visible( $first, $_ ) }
                         @{ $menu->{items} } ];
      push @{ $links }, $copy; $first = FALSE;
   }

   my $title  =  $links->[ 0 ]->{items}->[ 0 ]->{content}->{text} || NUL;
   my $widget =  { data   => $links, id   => q(menu), select => TRUE,
                   spacer => GT,     type => q(menu) };

   $s->{title} =  $s->{application}.SPC.$title;

   $self->add_field( $widget, qw(menus clear_menus) );
   return;
}

sub add_navigation_sidebar {
   return $_[ 0 ]->add_sidebar_panel( {
      heading     => $_[ 0 ]->_localized_nav_title,
      on_complete => 'function() { this.rebuild() }',
      name        => q(navigation_sidebar), } );
}

sub add_quick_links {
   my $self  = shift;
   my $s     = $self->context->stash;
   my $links = $self->_quick_link_cache->{ $s->{language} }
           ||= $self->_get_quick_links;
   my @items = ( map { { q(content) => $_ } } @{ $links } );

   $s->{quick_links} = { items => \@items };
   return;
}

sub add_utils_menu {
   my $self = shift; my $c = $self->context;

   my $menu_no = 0; my $name = q(tools); my @stack = ();

   $self->_add_tools_menu( $name, \@stack, $menu_no++ );
   $self->_add_help_menu ( $name, \@stack, $menu_no++ );

   my $args = { item => 0, menu => $menu_no, name => $name, title => DOTS };

   # Logout option drops current identity
   $c->stash->{user}->username ne q(unknown)
      and $self->_push_menu_link( \@stack, $menu_no,
                                  $self->get_logout_link( $args ) );
   $args->{item} += 1;

   my $widget = { data   => \@stack, id => $name,
                  select => FALSE, type => q(menu) };

   $self->add_field( $widget, qw(menus clear_menus) );
   return;
}

sub allowed { # Negate the logic of the access_check method
   my ($self, @args) = @_; return not $self->access_check( @args );
}

sub app_closed_form {
   my $self = shift; my $form = $self->context->stash->{form}->{name};

   $self->add_field  ( { id => "${form}.user"   } );
   $self->add_field  ( { id => "${form}.passwd" } );
   $self->add_hidden ( $form, 0 );
   $self->add_buttons( q(Login) );
   return;
}

sub load_status_msgs {
   my $self = shift; my $c = $self->context; my $s = $c->stash;

   $c->load_status_msgs;
   $s->{error_msg } and $self->add_error ( delete $s->{error_msg } );
   $s->{status_msg} and $self->add_result( delete $s->{status_msg} );
   return;
}

sub navigation_sidebar_form {
   my $self = shift; my $name = $self->context->action->name;

   $self->add_field ( { container => FALSE,
                        data      => $self->_get_tree_panel_data,
                        id        => "tree_panel_data_${name}",
                        type      => q(tree) } );
   $self->stash_meta( { id => $name } );
   return;
}

sub room_manager_form {
   my ($self, $ns, $name) = @_; my $s = $self->context->stash; my $actions = {};

   my $new_tag = $s->{newtag}; $ns ||= $new_tag; $name ||= $new_tag;

   try        { $actions = $self->_get_action_data( $ns, $name ) }
   catch ($e) { return $self->add_error( $e ) }

   my $form = $s->{form}->{name}; my $ns_tag = $self->namespace_tag;

   $self->clear_form  ( { firstfld => $form.q(.).$self->namespace_source } );
   $self->add_hidden  ( q(acl), $actions->{fields}->acl );
   $self->add_field   ( { default  => $ns,
                          id       => $form.q(.).$self->namespace_source,
                          values   => $actions->{nspaces} } );
   $ns and $ns ne $new_tag and
      $self->add_field( { default  => $name,
                          id       => $form.q(.).$self->action_source,
                          values   => $actions->{actions} } );
   $self->group_fields( { id       => "${form}.select" } );

   ($ns   and is_member $ns,   $actions->{nspaces}) or return;
   ($name and is_member $name, $actions->{actions}) or return;

   my $nspace = ($ns eq $new_tag) || ($ns eq q(default)) ? NUL : $ns;
   my $action = $name eq $ns_tag  || $name eq $new_tag
              ? $self->default_action : $name;
   my $uri    = eval { $self->context->uri_for_action( $nspace.SEP.$action ) };

   $self->add_field( { id => "${form}.uri", text => $uri || NUL } );

   if ($actions->{is_new}) {
      $self->add_field( { default => $actions->{name},
                          id      => "${form}.name" } );
      $self->add_buttons( qw(Insert) )
   }
   else {
      $self->add_hidden( q(name), $actions->{name} );
      $self->add_buttons( qw(Save Delete) )
   }

   $self->add_field( { default => $actions->{fields}->text,
                       id      => "${form}.text" } );
   $self->add_field( { default => $actions->{fields}->tip,
                       id      => "${form}.tip" } );

   if ($s->{noun} eq q(action)) {
      $self->add_field( { id      => "${form}.keywords",
                          default => $actions->{fields}->keywords   } );
      $self->add_field( { id      => "${form}.quick_link",
                          default => $actions->{fields}->quick_link } );
      $self->add_field( { id      => "${form}.pwidth",
                          default => $actions->{fields}->pwidth     } );
   }

   $self->group_fields( { id => "${form}.edit" } );
   return;
}

sub select_this {
   my ($self, $item_no, $menu_no, $widget) = @_; my $s = $self->context->stash;

   my $stack = $s->{menus}->{items}->[ $item_no ]->{content}->{data};

   $stack->[ 0 ]->{selected} = $menu_no; $widget or return;

   $widget->{class    } ||= $self->menu_selected_class;
   $widget->{container} ||= FALSE;
   $widget->{type     } ||= q(anchor);
   $widget->{widget   } ||= TRUE;
   $self->_unshift_menu_item( $stack, $menu_no, $widget );
   return;
}

sub sitemap_form {
   my $self = shift; my $s = $self->context->stash; my $sitemap;

   try        { $sitemap = $self->_get_sitemap_data }
   catch ($e) { return $self->add_error( $e ) }

   $self->clear_form( {
      heading      => $self->loc( q(sitemap_heading) ),
      sub_heading  => { class   => q(banner),
                        content => $self->loc( q(sitemap_subheading) ),
                        level   => 2, }, } );
   $self->add_field ( { data => $sitemap, id => $s->{form}->{name} } );
   return;
}

# Private methods

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
   my ($self, $opts, $name, $action_info) = @_;

   my $c = $self->context; my $sep = SEP; my $base = $opts->{base};

   # TODO: This is flawed. Wont work with capture args
   # I think we should be using $opts->{myspace}.$sep.$name
   my $path = eval { $c->uri_for_action( $opts->{myspace}.$sep.$name ) };

   if ($path) { $path =~ s{ \A $base $sep }{}mx } else { $path = $name }

   my ($is_first, $is_link, $menu_no) = __link_flags( $opts, $path );

   ($is_first or $is_link) and not defined $opts->{menus}->[ $menu_no ]
      and $opts->{menus}->[ $menu_no ] = { items => [] };

   my $menu  = $opts->{menus}->[ $menu_no ] or return;
   my $class = $is_first
            && $menu_no == $opts->{s_len} ? $self->menu_selected_class
             : $is_first                  ? $self->menu_title_class
                                          : $self->menu_link_class;
   my $text  = $action_info->{text} || ucfirst $name;
   my $tip   = $action_info->{tip } || NUL;
   my $item  = { action    => $name,
                 namespace => $opts->{myspace},
                 content   => { class     => $class,
                                container => FALSE,
                                href      => $base.$sep.$path.$opts->{query},
                                text      => $text,
                                tip       => $opts->{title}.TTS.$tip,
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

sub _add_help_menu {
   my ($self, $name, $stack, $menu_no) = @_; my $c = $self->context;

   my $title = $self->loc( q(helpOptionTip) );
   my $args  = { item => 0, menu => $menu_no, name => $name, title => $title };
   my $link  = $self->get_help_menu_link( $args ); # Help options

   $self->_push_menu_link( $stack, $menu_no, $link ); $args->{item} += 1;
   # Context senitive help page generated from pod in the controller
   $link = $self->get_context_help_link( $args );
   $self->_push_menu_link( $stack, $menu_no, $link ); $args->{item} += 1;
   # Display window with copyright and distribution information
   $link = $self->get_about_menu_link( $args );
   $self->_push_menu_link( $stack, $menu_no, $link ); $args->{item} += 1;

   $c->stash->{user}->username eq q(unknown) and return;

   # Send feedback email to site administrators
   $link = $self->get_feedback_menu_link( $args );
   $self->_push_menu_link( $stack, $menu_no, $link ); $args->{item} += 1;
   return;
}

sub _add_namespace_link {
   my ($self, $opts, $ns, $ns_info) = @_; $ns_info ||= {};

   my $c    = $self->context;
   my $text = $ns_info->{text} || ucfirst $ns;
   my $tip  = $opts->{title}.TTS.($ns_info->{tip} || NUL);

   if ($ns eq $opts->{myspace}) {
      # This is the currently selected controller on the navigation tool
      my $content = $opts->{menus}->[ 0 ]->{items}->[ 0 ]->{content};

      $content->{text} = $text; $content->{tip} = $tip;
   }
   else {
      # Just another registered controller
      $self->_push_menu_link( $opts->{menus}, 0, {
         class => $self->menu_link_class,
         href  => $c->uri_for_action( $ns.SEP.$self->default_action ),
         text  => $text,
         tip   => $tip }, { namespace => $ns } );
   }

   return;
}

sub _add_tools_menu {
   my ($self, $name, $stack, $menu_no) = @_; my $c = $self->context;

   my $title = $self->loc( q(displayOptionsTip) );
   my $args  = { item => 0, menu => $menu_no, name => $name, title => $title };
   my $link  = $self->get_tools_menu_link( $args );

   $self->_push_menu_link( $stack, $menu_no, $link ); $args->{item} += 1;
   # Toggle footer visibility
   $link = $self->get_footer_toggle_link( $args );
   $self->_push_menu_link( $stack, $menu_no, $link ); $args->{item} += 1;

   if ($c->stash->{is_administrator}) { # Runtime debug option
      $link = $self->get_debug_toggle_link( $args );
      $self->_push_menu_link( $stack, $menu_no, $link ); $args->{item} += 1;
   }

   my $default = $self->context->config->{default_skin};

   # Select the default skin
   $link = $self->get_default_skin_link( $args, $default );
   $self->_push_menu_link( $stack, $menu_no, $link ); $args->{item} += 1;

   # Select alternate skins
   for my $skin (grep { $_ ne $default } @{ $self->skins }) {
      $link = $self->get_alternate_skin_link( $args, $skin );
      $self->_push_menu_link( $stack, $menu_no, $link ); $args->{item} += 1;
   }

   return;
}

sub _get_access_data {
   my ($self, $ns, $name) = @_; my $s = $self->context->stash; my $access = {};

   my $ns_tag = $self->namespace_tag;
   my $noun   = ! $ns || $name eq $ns_tag ? q(controller) : q(action);

   $s->{info} = $noun eq q(controller) ? $ns : $name; $s->{noun} = $noun;

   my $rs     = $s->{namespace_model}->list
      ( ! $ns || $ns eq $s->{newtag} ? q(default) : $ns);

   $access->{nspaces} = [ NUL, q(default), @{ $rs->list } ];
   $noun eq q(controller) and $access->{acl} = $rs->result->acl;

   if ($ns and $ns ne $s->{newtag}) {
      $rs                = $s->{name_model}->list( $ns, $name );
      $access->{actions} = [ NUL, $ns_tag, @{ $rs->list } ];
      $access->{state  } = $rs->result->state || ACTION_OPEN;

      $noun eq q(action) and $access->{acl} = $rs->result->acl;
   }
   else {
      $access->{acl    } = [];
      $access->{actions} = [ NUL, $ns_tag ];
      $access->{state  } = ACTION_OPEN;
   }

   my @tmp = ();

   for my $model (@{ $s->{auth_models} }) {
      for my $group ($model->domain_model->roles->get_roles( q(all) )) {
         is_member q(@).$group, $access->{acl} or push @tmp, q(@).$group;
      }

      $self->user_level_access or next;

      for my $user (@{ $model->list }) {
         is_member $user, $access->{acl} or push @tmp, $user;
      }
   }

   my %tmp = (); my @ugrps = ();

   for (@tmp) { unless ($tmp{ $_ }) { push @ugrps, $_; $tmp{ $_ } = TRUE } }

   @ugrps = sort @ugrps;

   is_member q(any), $access->{acl} or unshift @ugrps, q(any);

   $access->{ugrps} = \@ugrps;
   return $access;
}

sub _get_action_data {
   my ($self, $ns, $name) = @_; my $s = $self->context->stash; my $actions = {};

   my $new_tag = $s->{newtag};
   my $ns_tag  = $self->namespace_tag;
   my $noun    = ! $ns || $ns eq $new_tag || $name eq $ns_tag
               ? q(controller) : q(action);
   my $is_new  = ($ns && $ns eq $new_tag) || ($name && $name eq $new_tag);

   $s->{info}  = $noun eq q(controller) ? $ns : $name; $s->{noun} = $noun;

   my $res     = $s->{namespace_model}->list( $ns );

   $actions->{nspaces} = [ NUL, $new_tag, q(default), @{ $res->list } ];
   $actions->{fields } = $res->result;

   if ($ns and $ns ne $new_tag) {
      $res = $s->{name_model}->list( $ns, $name );

      $actions->{actions} = [ NUL, $ns_tag, $new_tag, @{ $res->list } ];
      $name ne $ns_tag and $actions->{fields} = $res->result;
   }

   defined $actions->{fields}->acl or $actions->{fields}->acl( [ NUL ] );

   $actions->{name  } = $is_new ? NUL : ($noun eq q(controller) ? $ns : $name);
   $actions->{is_new} = $is_new;
   return $actions;
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

sub _get_nav_links {
   my $self     =  shift;
   my $links    =  [];
   my $sep      =  SEP;
   my $c        =  $self->context;
   my $s        =  $c->stash;
   my $myspace  =  $c->action->namespace;
   my $myname   =  $c->action->name;
   my $base     =  $s->{base_url};
   my $selected =  $c->uri_for_action( $myspace.$sep.$myname,
                                       [ map { '*' } @{ $c->req->captures } ] );
      $selected =~ s{ \A $base $sep }{}msx; $selected =~ s{ $sep \* }{}gmsx;
   my @s_list   =  __split_on_sep( $selected );
   my $opts     =  { base     => $base,
                     menus    => $links,
                     myspace  => $myspace,
                     query    => NUL,
                     s_len    => scalar @s_list,
                     s_list   => \@s_list,
                     selected => $selected,
                     title    => $self->_localized_nav_title };

   $self->_push_menu_link( $links, 0, {
      class => $self->menu_title_class,
      href  => $base,
      text  => ucfirst $myspace,
      tip   => NUL }, { namespace => $myspace } );

   while (my ($ns, $ns_info) = each %{ $s->{ $self->namespace_source } }) {
      $self->_add_namespace_link( $opts, $ns, $ns_info );
   }

   while (my ($action, $action_info) = each %{ $s->{ $self->action_source } }) {
      $action_info and $self->_add_action_link( $opts, $action, $action_info );
   }

   return $self->_sort_links( $links );
}

sub _get_quick_links {
   my $self  = shift; my $c = $self->context; my $stack = [];

   my $model = $c->model( $self->action_class );
   my $title = $self->_localized_nav_title;

   for my $ns (keys %{ $c->stash->{ $self->namespace_source } }) {
      for my $result ($model->search( $ns, { quick_link => { '>' => 0 } } )) {
         my $name = $result->name;

         push @{ $stack }, { class      => q(header_link fade),
                             container  => FALSE,
                             href       => $c->uri_for_action( $ns.SEP.$name ),
                             id         => "quick_link_${name}",
                             quick_link => $result->quick_link,
                             text       => $result->text || ucfirst $name,
                             tip        => $title.TTS.($result->tip || NUL),
                             type       => q(anchor),
                             widget     => TRUE };
      }
   }

   return [ sort { $a->{quick_link} <=> $b->{quick_link} } @{ $stack } ];
}

sub _get_sitemap_data {
   my $self    = shift; my $c = $self->context;

   my $title   = $self->loc( 'Select Tab' ); my $key = $self->namespace_source;

   my $nspaces = $c->stash->{ $key }; my $sitemap = []; my $index = 0;

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
         id        => "${ns}_map",
         type      => q(table),
         widget    => TRUE };

      $sitemap->[ $index++ ] = { clicker => $clicker, section => $section };
   }

   return $sitemap;
}

sub _get_sitemap_table {
   my ($self, $ns) = @_; my $c = $self->context; my $s = $c->stash;

   my $base    = $c->uri_for_action( $ns.SEP.$self->default_action ) || NUL;
   my $c_no    = 0; my $first  = TRUE; my $field = NUL; my $fields = {};
   my $lastc   = 0; my $n_cols = 0;    my $sep = SEP; my $rows = [];
   my $title   = $self->_localized_nav_title;
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
   push @{ $rows }, $fields;

   for my $uri_path (sort keys %actions) {
      my $action_info = $actions{ $uri_path };
      my $name        = $action_info->name;

      $self->_action_allowed( $action_info ) or next;

      $c_no                 = () = $uri_path =~ m{ $sep }gmx;
      $n_cols               = $c_no if ($c_no > $n_cols);
      $field                = "action_${c_no}";
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
         $rows->[ -1 ]->{ $field } = $fields->{ $field };
      }
      else {
         $lastc = $c_no;

         while ($c_no > 0) {
            $field = q(action_).--$c_no; $fields->{ $field } = NUL;
         }

         push @{ $rows }, $fields;
      }
   }

   my @fields = ( q(controller) );
   my $labels = { controller => $self->loc( 'Controller' ) };
   my $width  = (int 100 / (2 + $n_cols)).q(%);
   my $widths = { controller => $width };

   for $field (map { "action_${_}" } 0 .. $n_cols) {
      push @fields, $field;
      $labels->{ $field } = $self->loc( 'Actions' );
      $widths->{ $field } = $width;
   }

   return $self->table_class->new( fields => \@fields, labels => $labels,
                                   values => $rows,    widths => $widths );
}

sub _get_tree_panel_data {
   my $self = shift; my $c = $self->context; my $s = $c->stash; my $sep = SEP;

   my $key  = $self->namespace_source; my $nspaces = $s->{ $key };

   my $root = $self->loc( 'Site Map' ); my $tree = { $root => {} };

   for my $ns (sort { __cmp_text( $nspaces, $a, $b ) } keys %{ $nspaces }) {
      my $ns_info = $nspaces->{ $ns };

      ($ns_info->{state} or not $self->allowed( $key, $ns )) and next;

      my $base = $c->uri_for_action( $ns.$sep.$self->default_action ) || NUL;
      my %action_info = $self->_get_action_info( $base, $ns );

      $tree->{ $root }->{ $ns } = {
         _text => $ns_info->{text} || ucfirst $ns,
         _tip  => $ns_info->{tip } || NUL,
         _url  => $base,
      };

      for my $uri_path (sort keys %action_info) {
         my $action_info = $action_info{ $uri_path };
         my $cursor      = $tree->{ $root }->{ $ns };

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

   return $tree;
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

sub _localized_nav_title {
   return $_[ 0 ]->loc( 'Navigation' );
}

sub _push_menu_link { # Add a link to the navigation menu
   my ($self, $stack, $menu_no, $content, $opts) = @_;

   $stack or throw 'No menu arrayref'; $menu_no ||= 0;

   $content ||= {}; $content->{container} = FALSE;

   $content->{type} = q(anchor); $content->{widget} = TRUE;

   my $item = { content => $content };

   if ($opts) { $item->{ $_ } = $opts->{ $_ } for (keys %{ $opts }) }

   push @{ $stack->[ $menu_no ]->{items} }, $item;
   return;
}

sub _sort_links {
   my ($self, $stack) = @_; my $count = 0;

   my $selected = $stack->[ 0 ]->{selected} || 0;

   for my $menu (@{ $stack }) {
      my $items = $menu->{items} or next; my $first;

      if ($count++ <= $selected) { $first = shift @{ $items } }
      else { $items->[ 0 ]->{content}->{class} = $self->menu_link_class }

      @{ $items } =
         sort { lc $a->{content}->{text} cmp lc $b->{content}->{text} }
         @{ $items };

      if ($first) { unshift @{ $items }, $first }
      else { $items->[ 0 ]->{content}->{class} = $self->menu_title_class }
   }

   return $stack;
}

sub _unshift_menu_item {
   my ($self, $stack, $menu_no, $content, $opts) = @_;

   $stack or throw 'No menu arrayref'; $menu_no ||= 0;

   my $item = $content ? { content => $content } : {};

   if ($opts) { $item->{ $_ } = $opts->{ $_ } for (keys %{ $opts }) }

   my $items = $stack->[ $menu_no ]->{items};

   $items->[ 0 ] and $items->[ 0 ]->{content}->{class} = $self->menu_link_class;

   unshift @{ $items }, $item;
   return;
}

# Private functions

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

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Navigation - Navigation links and access control

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   package YourApp;

   use Catalyst qw(ConfigComponents...);

   __PACKAGE__->config(
     'Model::Navigation' => {
        parent_classes   => q(CatalystX::Usul::Model::Navigation) }, );

=head1 Description

Provides methods for creating navigation links and access control

=head1 Configuration and Environment

Defines the following list of attributes

=over 3

=item action_class

A non empty simple string which defaults to I<Config::Rooms>, the name
of the model used to manage defined actions

=item action_source

A non empty simple string which defaults to I<action>, the stash key
where action definitions are stored

=item default_action

A non empty simple string which defaults to I<redirect_to_default>. Each
controller implements this action. It redirects to the controllers default
action

=item menu_link_class

A non empty simple string which defaults to I<menu_link fade>. The classes
on the markup for a navigation link

=item menu_selected_class

A non empty simple string which defaults to I<menu_selected fade>. The
classes on the markup for the selected navigation link

=item menu_title_class

A non empty simple string which defaults to I<menu_title fade>. The
classes on the markup of the not selected navigation links

=item namespace_source

A non empty simple string which defaults to I<namespace>. The stash key
where the namespace/controller definitions are stored

=item namespace_tag

A non empty simple string which defaults to I<..Level..>. A popup menu
selection option used to selected namespace/controller operations

=item skins

A required  array ref. A list of the available skins/themes

=item user_level_access

A boolean which defaults to false. It true then access to actions can be
set for individual users, not just groups of users. Slows things down a
lot

=back

=head1 Subroutines/Methods

=head2 COMPONENT

   $navigation_model_object = $self->COMPONENT( $app, $attributes );

Called by Catalyst when the application starts it sets the default action
from global config and sets up the list of available skins

=head2 access_check

   $state = $self->access_check( $source, $key );

Expects to be passed a key to search in
the stash (C<$source>) and a controller or action to search for
(C<$key>). It returns 0 if the ACL on the requested controller/action
permits access to the current user. It returns 1 if no ACL was
found. It returns 2 if the current user is unknown and the
controller/action's ACL did not contain the value I<any> which would permit
anonymous access. It returns 3 if the current user is explicitly
denied access to the selected controller/action

This method is called from L</add_nav_menu> (via the L</allowed>
method which negates the result) to determine which controllers the current
user has access to. It is also called by C<auto> to determine if
access to the requested action is permitted

It could also be used from an application controller method to allow
the display logic to display content based on the users identity

=head2 access_control_form

   $self->form( $namespace, $name );

Stuffs the stash with the data for the form that controls access to
controllers and actions

=head2 add_menu_back

   $self->add_menu_back( { tip => $title_text } );

Adds a history back link to the main navigation menu

=head2 add_menu_blank

   $self->add_menu_blank;

Adds some filler to the main navigation menu

=head2 add_menu_close

   $self->add_menu_close( $args );

Adds a window close link to the main navigation menu

=head2 add_nav_header

   $self->add_nav_header;

Calls parent method. Adds main and tools menu data. Adds quick link data

Calls L</add_nav_menu>. This is the main navigation menu

Calls L</add_utils_menu>

Calls L<add_quick_links>. Quick links appear in the header and are
selected from the I<rooms> config items if the I<quick_link> element
is set. It's numeric value determines the sort order of the links

=head2 add_nav_menu

   $self->add_nav_menu;

Returns the data used to generate the main navigation menu. The menu uses
a Cone Trees layout which has been flattened to produce a visual trail
of breadcrumbs effect, i.e. Home > Reception > Tutorial

=head2 add_navigation_sidebar

   $panel_number = $self->add_navigation_sidebar;

Adds a sidebar panel containing a tree widget that represents all the
action available in the application (another sitemap)

=head2 add_quick_links

   $links = $self->add_quick_links;

Returns the data used to display "quick" navigation links. Caches data
on first use. These usually appear in the header and allow single
click access to any endpoint. They are identified in the configuration
by adding a I<quick_link> attribute to the I<rooms> element. The
I<quick_link> attribute value is an integer which determines the
display order

=head2 add_utils_menu

   $self->add_utils_menu;

Returns the stash data for the utilities menu. This contains a selection of
utility options including: toggle runtime debugging, toggle footer,
skin switching, context sensitive help, about popup, email feedback
and logout option. Calls L</_add_help_menu> and L</_add_tools_menu>

=head2 allowed

   $state = $self->allowed( $source, $key );

Negates the result returned by L</access_check>. Called from
L</add_nav_menu> to determine if a page is accessible to a user. If
the user does not have access then do not display a link to it

=head2 app_closed_form

   $self->app_closed_form;

Allows administrators to authenticate and reopen the application

=head2 load_status_msgs

   $self->load_status_msgs;

Calls L<Catalyst::Plugin::StatusMessage> to load the stash with the status
and error messages from the previous request (oops there goes HTTP's
statelessness). Stuffs the messages back into the stash so that they appear
in the results div

=head2 navigation_sidebar_form

   $self->navigation_sidebar_form;

Calls L</_get_tree_panel_data> and creates a tree widget using the
data. Implements the navigation sidebar

=head2 room_manager_form

   $self->room_manager_form( $namespace, $name );

Allows for editing of the controller and action definition elements in the
configuration files

=head2 select_this

   $self->select_this( $menu_no, $order, $widget );

Make the widget the selected menu item

=head2 sitemap_form

   $self->sitemap_form;

Displays a table of all the pages on the site

=head1 Private Methods

=head2 _add_help_menu

   $self->_add_help_menu( $name, $stack, $menu_no );

Stashes the data for the help menu options

=head2 _add_tools_menu

   $self->_add_tools_menu( $name, $stack, $menu_no );

Utility menu options

=head2 _get_tree_panel_data

   $data = $self->_get_tree_panel_data;

Called by L</sitemap> this method generates the table data used by
L<HTML::FormWidgets>'s C<Tree> subclass

=head2 _get_sitemap_data

   $data = $self->_get_sitemap_data;

Called by L</sitemap> this method generates an array of hash refs used by
L<HTML::FormWidgets>'s C<TabSwapper> subclass

=head2 _get_sitemap_table

   $data = $self->_get_sitemap_table( $ns );

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

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::TraitFor::Model::StashHelper>

=item L<CatalystX::Usul::Moose>

=item L<Class::Usul::Response::Table>

=item L<File::DataClass::IO>

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
