package CatalystX::Usul::Model::Navigation;

# @(#)$Id: Navigation.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Model);
use CatalystX::Usul::Table;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

my $DOTS = chr 8230;
my $GT   = q(&gt;);
my $NUL  = q();
my $SEP  = q(/);
my $TTS  = q( ~ );

__PACKAGE__->config( _quick_link_cache => {} );

__PACKAGE__->mk_accessors( qw(_quick_link_cache) );

sub access_check {
   # Return non zero to prevent access to requested endpoint
   # The return code indicates the reason
   my ($self, @args) = @_; my $s = $self->context->stash; my %roles;

   # Administrators are always allowed access
   return 0 if ($s->{is_administrator});

   # Get the list of allowed users and groups from the stash
   my $endp    = exists $s->{ $args[0] }->{ $args[1] }
               ? $s->{ $args[0] }->{ $args[1] } : {};
   my $allowed = [ @{ $endp->{acl} || [] } ];

   # Cannot obtain a list of users/groups for this endpoint
   return 1 unless ($allowed->[0]);

   for my $ugrp (@{ $allowed }) {
      # Public access or granted access to the user specifically
      return 0 if ($ugrp eq q(any) || $ugrp eq $s->{user});

      # Anon. access is now denied
      return 2 if ($s->{user} eq q(unknown));

      if (q(@) eq substr $ugrp, 0, 1) { # This is a group not a user
         unless (exists $roles{_seeded}) { # Create a hash lookup
            %roles = map { $_ => 1 } @{ $s->{roles} }, q(_seeded);
         }

         # User is in a role that has access to the endpoint
         return 0 if (exists $roles{ substr $ugrp, 1 });
      }
   }

   # We don't like your kind around here...
   return 3;
}

sub access_control_form {
   my ($self, $level, $room) = @_;
   my ($acl, $e, $grp, @grps, $model, $nitems, $ref, $user, $users, @ugrps);

   my $s         = $self->context->stash;
   my $level_tag = q(..Level..);
   my $form      = $s->{form}->{name};
   my $states    = { 0 => q(open), 1 => q(hidden), 2 => q(closed) };
   my $noun      = !$level || $room eq $level_tag ? q(level) : q(room);

   $s->{info  }  = $noun eq q(level) ? $level : $room;
   $s->{noun  }  = $noun;
   $s->{pwidth} -= 10;

   my $res = eval { $s->{level_model}->get_list( $level ) };

   return $self->add_error( $e ) if ($e = $self->catch);

   my $levels = $res->list; unshift @{ $levels }, $NUL, q(default);

   $acl = $res->element->acl if ($noun eq q(level));

   $res = eval { $s->{room_model}->get_list( $level, $room ) };

   return $self->add_error( $e ) if ($e = $self->catch);

   my $rooms = $res->list; unshift @{ $rooms }, $NUL, $level_tag;
   my $state = $res->element->state || 0;

   $acl = $res->element->acl if ($noun eq q(room));

   for $model (@{ $s->{auth_models} }) {
      $users = eval { $model->users->retrieve( q([^\?]+), $NUL )->user_list };

      return $self->add_error( $e ) if ($e = $self->catch);

      for $user (@{ $users }) {
         push @ugrps, $user unless ($self->is_member( $user, @{ $acl } ));
      }

      @grps  = eval { $model->roles->get_roles( q(all) ) };

      return $self->add_error( $e ) if ($e = $self->catch);

      for $grp (@grps) {
         unless ($self->is_member( q(@).$grp, @{ $acl } )) {
            push @ugrps, q(@).$grp;
         }
      }
   }

   @ugrps = sort @ugrps;

   unshift @ugrps, q(any) unless ($self->is_member( q(any), @{ $acl } ));

   # Build the form
   $self->clear_form( { firstfld => $form.q(.room) } ); $nitems = 0;
   $self->add_field(  { default  => $level,
                        id       => q(config.level),
                        stepno   => 0,
                        values   => $levels } ); $nitems++;

   if ($level && $level ne $s->{newtag}) {
      $self->add_field( { default => $room,
                          id      => $form.q(.room),
                          stepno  => 0,
                          values  => $rooms } ); $nitems++;
   }

   $self->group_fields( { id => $form.q(.select), nitems => $nitems } );

   return if     (!$level || $level eq $s->{newtag});
   return unless ( $room  && $self->is_member( $room, @{ $rooms } ));

   $self->add_field(    { default => $state,
                          id      => $form.q(.state),
                          labels  => $states,
                          stepno  => 0,
                          values  => [ 0, 1, 2 ] } );
   $self->group_fields( { id      => $form.q(.state), nitems => 1 } );
   $self->add_field(    { all     => \@ugrps,
                          current => $acl,
                          id      => $form.q(.user_groups),
                          stepno  => 0 } );
   $self->group_fields( { id      => $form.q(.add_remove), nitems => 1 } );
   $self->add_buttons(  qw(Set Update) );
   return;
}

sub add_main_menu {
   my $self = shift;

   my ($class, $content, $first, $i, $is_link, $is_ref, $item, $level, $menu);
   my ($namespace, $path, $query, $room, $r_ord, @r_parts, $s_ord);
   my (@s_parts, $selected, $text, $tip);

   my $name    = q(menus);
   my $c       = $self->context;
   my $req     = $c->req;
   my $s       = $c->stash;
   my $menus   = $s->{ $name } = [];
   my $myname  = $c->action->name;
   my $myspace = $c->action->namespace;
   my $base    = $self->uri_for( $myspace, $s->{lang} ) || $NUL;
   my $title   = $self->loc( q(navigationTitle) );

   $self->push_menu_item( $name, 0, {
      class     => q(menuTitleFade),
      container => 0,
      href      => $base,
      text      => ucfirst $myspace,
      tip       => $NUL,
      type      => q(anchor),
      widget    => 1 }, { namespace => $myspace } );

   unless ($selected = $s->{form}->{action}) { $selected = $myname }
   else { $selected =~ s{ \A $base $SEP }{}mx }

   $s->{menusSep} = $GT;
   $s->{menuPath} = $myname ? $selected : $NUL; # Used by releases model
   $s_ord    = () = $selected =~ m{ $SEP }gmx;
   @s_parts  = split m{ $SEP }mx, $selected;

   # TODO: This seem to work better than blindly preserving the query. Need to
   # work out condition for retaining query
   #$query    = q(?);
   #for (keys %{ $req->query_parameters }) {
   #   $query .= q(&) if ($query !~ m{ \? \z }msx);
   #   $query .= $_.q(=).($req->query_parameters->{ $_ } || $NUL);
   #}
   #$query = $NUL if ($query eq q(?));
   $query = $NUL;

   while (($namespace, $level) = each %{ $s->{levels} }) {
      next unless ($level and not $level->{state});
      next unless ($self->allowed( q(levels), $namespace ));

      if ($namespace eq $myspace) {
         # This is the currently selected controller on the navigation tool
         $content         = $menus->[0]->{items}->[0]->{content};
         $content->{text} = $level->{text} || ucfirst $namespace;
         $content->{tip } = $title.$TTS.($level->{tip} || $NUL);
      }
      else {
         # Just another registered controller
         $self->push_menu_item( $name, 0, {
            class     => q(menuLinkFade),
            container => 0,
            href      => $self->uri_for( $namespace, $s->{lang} ),
            text      => $level->{text} || ucfirst $namespace,
            tip       => $title.$TTS.($level->{tip} || $NUL),
            type      => q(anchor),
            widget    => 1 }, { namespace => $namespace } );
      }
   }

   while (($name, $room) = each %{ $s->{rooms} }) {
      next unless ($room and not $room->{state});
      next unless ($self->allowed( q(rooms), $name ));

      if ($path = $self->uri_for( $myspace.$SEP.$name, $s->{lang} )) {
         $path =~ s{ \A $base $SEP }{}mx;
      }
      else { $path = $name };

      $text    = $room->{text} || ucfirst $name;
      $tip     = $room->{tip } || $NUL;
      $r_ord   = () = $path =~ m{ $SEP }gmx;
      $is_ref  = 0;
      $is_link = 0;

   TRY: {
      if ($path eq $selected) {
         $menus->[0]->{selected} = $s_ord + 1;
         $is_ref = 1;
         last TRY;
      }

      if ($r_ord < $s_ord) {
         if ($path.$SEP eq (substr $selected, 0, length $path).$SEP) {
            $is_ref = 1;
            last TRY;
         }

         if ($r_ord == 0) { $is_link = 1; last TRY }

         @r_parts = split m{ $SEP }mx, $path;
         $is_link = 1;

         for $i (0 .. $r_ord - 1) {
            $is_link = 0 if ($r_parts[ $i ] ne $s_parts[ $i ]);
         }

         last TRY;
      }

      if ($r_ord > $s_ord) {
         if ($r_ord == $s_ord + 1
             && (substr $path, 0, length $selected) eq $selected) {
            $is_ref = 1;
         }

         last TRY;
      }

      if ($r_ord == 0) { $is_link = 1; last TRY }

      @r_parts = split m{ $SEP }mx, $path;
      $is_link = 1;

      for $i (0 .. $r_ord - 1) {
         $is_link = 0 if ($r_parts[ $i ] ne $s_parts[ $i ]);
      }
      }  # TRY

      if (($is_ref || $is_link) && !defined $menus->[ $r_ord + 1 ]) {
         $menus->[ $r_ord + 1 ] = { items => [] };
      }

      if ($menu = $menus->[ $r_ord + 1 ]) {
         $class = $is_ref && $r_ord == $s_ord ? q(menuSelectedFade)
                : $is_ref                     ? q(menuTitleFade)
                                              : q(menuLinkFade);
         $item  = { namespace => $myspace,
                    content   => { class     => $class,
                                   container => 0,
                                   href      => $base.$SEP.$path.$query,
                                   text      => $text,
                                   tip       => $title.$TTS.$tip,
                                   type      => q(anchor),
                                   widget    => 1 } };

         if ($is_ref) {
            if ($menu->{items}->[ 0 ]) {
               $menu->{items}->[ 0 ]->{content}->{class} = q(menuLinkFade);
            }

            unshift @{ $menu->{items} }, $item;
         }
         elsif ($is_link) { push @{ $menu->{items} }, $item }
      }
   }

   for $menu (@{ $menus }) {
      if ($menu->{items}->[0]) {
         $first = shift @{ $menu->{items} };

         @{ $menu->{items} } =
            sort { lc $a->{content}->{text} cmp lc $b->{content}->{text} }
            @{ $menu->{items} };

         unshift @{ $menu->{items} }, $first;
      }
   }

   return;
}

sub add_menu_back {
   # Add a browser back link to the navigation menu
   my ($self, $args, $name, $ord) = @_;

   my $title   = $self->loc( q(navigationTitle) );
   my $tip     = $self->loc( 'Go back to the previous page' );
   my $content = { class     => q(menuTitleFade),
                   container => 0,
                   href      => '#top',
                   onclick   => 'window.history.back()',
                   text      => $self->loc( 'Back' ),
                   tip       => $title.$TTS.$tip,
                   type      => q(anchor),
                   widget    => 1 };

   $self->push_menu_item( $name || q(menus), $ord || 0, $content );
   return;
}

sub add_menu_blank {
   # Stash some padding to fill the gap where the nav. menu was
   my ($self, $args, $name, $ord) = @_;

   my $content = { class     => q(menuTitleFade),
                   container => 0,
                   href      => '#top',
                   text      => q(&nbsp;) x 30,
                   type      => q(anchor),
                   widget    => 1 };

   $self->push_menu_item( $name || q(menus), $ord || 0, $content );
   return;
}

sub add_menu_close {
   # Add a close window link to the navigation menu
   my ($self, $args, $name, $ord) = @_; $args ||= {};

   my $title   = $self->loc( q(navigationTitle) );
   my $onclick = $args->{onclick} || 'window.close()';
   my $tip     = $self->loc( $args->{tip} || 'Close this window' );
   my $content = { class     => q(menuTitleFade),
                   container => 0,
                   href      => '#top',
                   onclick   => $onclick,
                   text      => $self->loc( 'Close' ),
                   tip       => $title.$TTS.$tip,
                   type      => q(anchor),
                   widget    => 1 };

   $self->push_menu_item( $name || q(menus), $ord || 0, $content );
   return;
}

sub add_quick_links {
   my $self = shift; my $c = $self->context; my $s = $c->stash; my $links;

   if ($links = $self->_quick_link_cache->{ $s->{lang} }) {
      $s->{quick_links} = { items => $links };
      return;
   }
   else { $links = [] }

   my $model = $c->model( q(Config::Rooms) );
   my $title = $self->loc( q(navigationTitle) );

   for my $ns (keys %{ $s->{levels} }) {
      my @elements = $model->search( $ns, { quick_link => { '>' => 0 } } );

      for my $element (@elements) {
         my $name = $element->name;
         my $href = $self->uri_for( $ns.$SEP.$name, $s->{lang} );
         my $tip  = $title.$TTS.($element->tip || $NUL);

         push @{ $links }, {
            content => { class     => q(headerFade),
                         container => 0,
                         href      => $href,
                         name      => $name,
                         sort_by   => $element->quick_link,
                         text      => $element->text || $name,
                         tip       => $tip,
                         type      => q(anchor),
                         widget    => 1 } };
      }
   }

   @{ $links } = sort { $a->{content}->{sort_by}
                        <=> $b->{content}->{sort_by} } @{ $links };
   $self->_quick_link_cache->{ $s->{lang} } = $links;
   $s->{quick_links} = { items => $links };
   return;
}

sub add_tools_menu {
   my $self    = shift; my ($alt, $jscript, $text);
   my $menu    = 0;
   my $item    = 0;
   my $name    = q(tools);
   my $c       = $self->context;
   my $s       = $c->stash;
   my $tools   = $s->{ $name } = [];
   my $default = $c->config->{default_skin};
   my $title   = $self->loc( q(displayOptionsTip) );

   $self->push_menu_item( $name, $menu, {
      class     => $name.q(TitleFade),
      container => 0,
      fhelp     => 'Tools',
      href      => '#top',
      id        => $name.$menu.q(item).$item,
      imgclass  => $name,
      sep       => $NUL,
      text      => $s->{assets}.'tools.gif',
      tip       => $DOTS.$TTS.$title,
      type      => q(anchor),
      widget    => 1 } ); $item++;

   if ($s->{is_administrator}) {
      # Runtime debug option
      $jscript = "behaviour.state.toggleSwapText('${name}0item${item}', ";

      if ($s->{debug}) {
         $text     = $self->loc( q(debugOffText) );
         $alt      = $self->loc( q(debugOnText) );
         $jscript .= "'debug', '$text', '$alt')";
      }
      else {
         $text     = $self->loc( q(debugOnText) );
         $alt      = $self->loc( q(debugOffText) );
         $jscript .= "'debug', '$alt', '$text')";
      }

      $self->push_menu_item( $name, $menu, {
         class     => $name.q(LinkFade),
         container => 0,
         href      => '#top',
         id        => $name.$menu.q(item).$item,
         onclick   => $jscript,
         text      => $text,
         tip       => $title.$TTS.$self->loc( q(debugToggleTip) ),
         type      => q(anchor),
         widget    => 1 } ); $item++;
   }

   # Toggle footer visibility
   $jscript = "behaviour.state.toggleSwapText('${name}0item${item}', ";

   if ($s->{fstate}) {
      $text     = $self->loc( q(footerOffText) );
      $alt      = $self->loc( q(footerOnText) );
      $jscript .= "'footer', '$text', '$alt')";
   }
   else {
      $text     = $self->loc( q(footerOnText) );
      $alt      = $self->loc( q(footerOffText) );
      $jscript .= "'footer', '$alt', '$text')";
   }

   $self->push_menu_item( $name, $menu, {
      class     => $name.q(LinkFade),
      container => 0,
      href      => '#top',
      id        => $name.$menu.q(item).$item,
      onclick   => $jscript,
      text      => $text,
      tip       => $title.$TTS.$self->loc( q(footerToggleTip) ),
      type      => q(anchor),
      widget    => 1 } ); $item++;

   # Select the default skin
   $jscript     = "behaviour.submit.refresh('skin', '${default}')";

   $self->push_menu_item( $name, $menu, {
      class     => $name.q(LinkFade),
      container => 0,
      href      => '#top',
      id        => $name.$menu.q(item).$item,
      onclick   => $jscript,
      text      => $self->loc( q(changeSkinDefaultText) ),
      tip       => $title.$TTS.$self->loc( q(changeSkinDefaultTip) ),
      type      => q(anchor),
      widget    => 1 } ); $item++;

   # Select alternate skins
   for my $skin (map { $self->basename($_) }
              glob $self->catfile( $s->{skindir}, q{*})) {
      next if ($skin eq $default);

      $jscript = "behaviour.submit.refresh('skin', '${skin}')";
      $self->push_menu_item( $name, $menu, {
         class     => $name.q(LinkFade),
         container => 0,
         href      => '#top',
         id        => $name.$menu.q(item).$item,
         onclick   => $jscript,
         text      => (ucfirst $skin).$self->loc( q(changeSkinAltText) ),
         tip       => $title.$TTS.$self->loc( q(changeSkinAltTip) ),
         type      => q(anchor),
         widget    => 1 } ); $item++;
   }

   $menu++; $item = 0;

   # Help options
   $title = $self->loc( q(helpOptionTip) );
   $self->push_menu_item( $name, $menu, {
      class     => $name.q(TitleFade),
      container => 0,
      fhelp     => 'Help',
      href      => '#top',
      id        => $name.$menu.q(item).$item,
      imgclass  => $name,
      sep       => $NUL,
      text      => $s->{assets}.'help.gif',
      tip       => $DOTS.$TTS.$title,
      type      => q(anchor),
      widget    => 1 } ); $item++;

   # Context senitive help page generated from pod in the controller
   $self->push_menu_item( $name, $menu, {
      class     => $name.q(LinkFade),
      container => 0,
      href      => '#top',
      id        => $name.$menu.q(item).$item,
      onclick   => $self->open_window( key  => q(help),
                                       href => $s->{help_url} ),
      text      => $self->loc( q(contextHelpText) ),
      tip       => $title.$TTS.$self->loc( q(contextHelpTip) ),
      type      => q(anchor),
      widget    => 1 } ); $item++;

   # Display window with copyright and distribution information
   $text = $self->uri_for( q(root).$SEP.q(about), $s->{lang} );
   $self->push_menu_item( $name, $menu, {
      class     => $name.q(LinkFade),
      container => 0,
      href      => '#top',
      id        => $name.$menu.q(item).$item,
      onclick   => $self->open_window( href => $text, key => q(about) ),
      text      => $self->loc( q(aboutOptionText) ),
      tip       => $title.$TTS.$self->loc( q(aboutOptionTip) ),
      type      => q(anchor),
      widget    => 1 } ); $item++;

   # Send feedback email to site administrators
   if ($s->{user} ne q(unknown)) {
      $text = $self->uri_for( q(root).$SEP.q(feedback), $s->{lang},
                              $c->action->namespace, $c->action->name );
      $self->push_menu_item( $name, $menu, {
         class     => $name.q(LinkFade),
         container => 0,
         href      => '#top',
         id        => $name.$menu.q(item).$item,
         onclick   => $self->open_window( height => 670,
                                          href   => $text,
                                          key    => q(feedback),
                                          width  => 850 ),
         text      => $self->loc( q(feedbackOptionText) ),
         tip       => $title.$TTS.$self->loc( q(feedbackOptionTip) ),
         type      => q(anchor),
         widget    => 1 } ); $item++;
   }

   $menu++; $item = 0;

   # Logout option drops current identity
   $self->push_menu_item( $name, $menu, {
      class     => $name.q(TitleFade),
      container => 0,
      fhelp     => 'Exit',
      href      => '#top',
      id        => $name.$menu.q(item).$item,
      onclick   => "behaviour.window.wayOut('".$c->req->base."')",
      imgclass  => $name,
      sep       => $NUL,
      text      => $s->{assets}.'exit.gif',
      tip       => $DOTS.$TTS.$self->loc( q(exitTip) ),
      type      => q(anchor),
      widget    => 1 } ); $item++;

   $menu++; $item = 0;

   if ($s->{is_administrator}) {
      my $url   = $self->uri_for( q(root).$SEP.q(lock_display), $s->{lang} );
      my $data  = q(display=:0);
      $self->push_menu_item( $name, $menu, {
         class     => $name.q(TitleFade),
         container => 0,
         fhelp     => 'Lock',
         href      => '#top',
         id        => $name.$menu.q(item).$item,
         imgclass  => $name,
         onclick   => "behaviour.server.postData( '${url}', '${data}' )",
         sep       => $NUL,
         text      => $s->{assets}.'lock.png',
         tip       => $DOTS.$TTS.$self->loc( 'Lock the current display' ),
         type      => q(anchor),
         widget    => 1 } ); $item++;
   }

   $s->{toolsSep} = $NUL;
   return;
}

sub allowed {
   # Negate the logic of the access_check method
   my ($self, @rest) = @_; return !$self->access_check( @rest );
}

sub push_menu_item {
   # Add a link to the navigation menu
   my ($self, $menu, $ord, $ref, $opts) = @_; my $s = $self->context->stash;

   $s->{ $menu } ||= []; $ord ||= 0; $ref = $ref ? { content => $ref } : {};

   if ($opts) { $ref->{ $_ } = $opts->{ $_ } for (keys %{ $opts }) }

   push @{ $s->{ $menu }->[ $ord ]->{items} }, $ref;
   return;
}

sub retrieve {
   my $self   = shift;
   my $c      = $self->context;
   my $lastc  = 0;
   my $n_cols = 0;
   my $s      = $c->stash;
   my $levels = $s->{levels};
   my $model  = $c->model( q(Config::Rooms) );
   my $title  = $self->loc( q(navigationTitle) );
   my $new    = CatalystX::Usul::Table->new
      ( align  => { level => q(left)  }, flds   => [ q(level) ],
        labels => { level => 'Level' },  values => [] );
   my ($c_no, $element, $fld, $path, $room);

   for my $level (sort { __level_cmp( $levels, $a, $b ) } keys %{ $levels }) {
      my $first = 1;
      my $flds  = {};
      my %rooms = ();
      my $base  = $self->uri_for( $level, $s->{lang} ) || $NUL;

      $flds->{room } = $NUL;
      $flds->{level} = { class     => q(linkFade),
                         container => 0,
                         href      => $base,
                         text      => $levels->{ $level }->{text},
                         tip       => $title.$TTS.$levels->{ $level }->{tip},
                         type      => q(anchor),
                         widget    => 1 };
      push @{ $new->values }, $flds;

      for $element ($model->search( $level )) {
         $room = $element->name;

         if ($path = $self->uri_for( $level.$SEP.$room, $s->{lang} )) {
            $path =~ s{ \A $base $SEP }{}mx;
         }
         else { $path = $room };

         $rooms{ $path } = $element;
      }

      for $path (sort keys %rooms) {
         $element        = $rooms{ $path };
         $room           = $element->name;
         $c_no           = () = $path =~ m{ $SEP }gmx;
         $n_cols         = $c_no if ($c_no > $n_cols);
         $fld            = q(room).$c_no;
         $flds           = {};
         $flds->{level}  = $NUL;
         $flds->{ $fld } = { class     => q(linkFade),
                             container => 0,
                             href      => $base.$SEP.$path,
                             text      => $element->text || $room,
                             tip       => $title.$TTS.($element->tip || $NUL),
                             type      => q(anchor),
                             widget    => 1 };

         if ($first || $c_no > $lastc) {
            $first = 0; $lastc = $c_no;
            $new->values->[ $#{ $new->values } ]->{ $fld } = $flds->{ $fld };
         }
         else {
            $lastc = $c_no;

            while ($c_no > 0) {
               $fld = q(room).--$c_no; $flds->{ $fld } = $NUL;
            }

            push @{ $new->values }, $flds;
         }
      }
   }

   for $c_no (0 .. $n_cols) {
      $fld = q(room).$c_no;
      push @{ $new->flds }, $fld;
      $new->labels->{ $fld } = 'Rooms';
      $new->align->{ $fld }  = q(left);
   }

   return $new;
}

sub room_manager_form {
   my ($self, $level, $room) = @_;
   my ($def, $e, $id, $is_new, $flds, $levels, $nitems, $ref, $rooms);

   my $s         = $self->context->stash;
   my $level_tag = q(..Level..);
   my $form      = $s->{form}->{name};
   my $new_tag   = $s->{newtag};
   my $noun      = !$level || $level eq $new_tag || $room eq $level_tag
                 ? q(level) : q(room);
   my $step      = 1;

   $s->{info}    = $noun eq q(level) ? $level : $room;
   $s->{noun}    = $noun;
   $s->{pwidth} -= 10;

   my $res = eval { $s->{level_model}->get_list( $level ) };

   return $self->add_error( $e ) if ($e = $self->catch);

   $levels = $res->list; unshift @{ $levels }, $NUL, $new_tag, q(default);
   $flds   = $res->element;

   if ($level and $level ne $new_tag) {
      $res = eval { $s->{room_model}->get_list( $level, $room ) };

      return $self->add_error( $e ) if ($e = $self->catch);

      $rooms  = $res->list; unshift @{ $rooms }, $NUL, $level_tag, $new_tag;
      $flds   = $res->element if ($room ne $level_tag);
   }

   $flds->acl( [ $NUL ] ) unless (defined $flds->acl);

   $self->clear_form( { firstfld => $form.'.level' } ); $nitems = 0;
   $self->add_hidden( q(acl), $flds->acl );
   $self->add_field(  { default => $level,
                        id      => $form.'.level',
                        stepno  => 0,
                        values  => $levels } ); $nitems++;

   if ($level and $level ne $new_tag) {
      $self->add_field( { default => $room,
                          id      => $form.'.room',
                          stepno  => 0,
                          values  => $rooms } ); $nitems++;
   }

   $self->group_fields( { id => $form.'.select', nitems => $nitems } );
   $nitems = 0;

   return unless ($level && $self->is_member( $level, @{ $levels } ));
   return unless ($level eq $new_tag
                  || ($room && ($room eq $level_tag
                                || $self->is_member( $room, @{ $rooms } ))));

   $is_new = $level eq $new_tag || $room eq $new_tag;
   $def    = $is_new ? $NUL : ($room eq $level_tag ? $level : $room);
   $self->add_field(    { ajaxid  => $form.'.name',
                          default => $def,
                          stepno  => $step++ } ); $nitems++;
   $self->add_field(    { ajaxid  => $form.'.text',
                          default => $flds->text,
                          stepno  => $step++ } ); $nitems++;
   $self->add_field(    { ajaxid  => $form.'.tip',
                          default => $flds->tip,
                          stepno  => $step++ } ); $nitems++;

   if ($noun eq q(room)) {
      $self->add_field( { id      => $form.q(.keywords),
                          default => $flds->keywords,
                          stepno  => $step++ } ); $nitems++;
   }

   $self->group_fields( { id => $form.'.edit', nitems => $nitems } );

   # Add form buttons
   if ($level eq $new_tag || $room eq $new_tag) {
      $self->add_buttons( qw(Insert) );
   }
   else { $self->add_buttons( qw(Save Delete) ) }

   return;
}

sub sitemap {
   my $self = shift; my $e;

   my $data = eval { $self->retrieve };

   return $self->add_error( $e ) if ($e = $self->catch);

   $self->clear_form( { heading => $self->loc( q(sitemapHeading) ) } );
   $self->add_field(  { data    => $data, type => q(table) } );
   return;
}

# Private subroutines

sub __level_cmp {
   my ($ref, $arg1, $arg2) = @_;

   $arg1 = $ref->{ $arg1 }->{text} || $arg1;
   $arg2 = $ref->{ $arg2 }->{text} || $arg2;
   return $arg1 cmp $arg2;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Navigation - Navigation links and access control

=head1 Version

0.1.$Revision: 402 $

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

This method is called from C</add_main_menu> (via the C</allowed>
method which negates the result) to determine which levels the current
user has access to. It is also called by B</auto> to determine if
access to the requested endpoint is permitted

It could also be used from an application controller method to allow
the display logic to display content based on the users identity

=head2 access_control_form

   $c->model( q(Navigation) )->form( $level, $room );

Stuffs the stash with the data for the form that controls access to
levels and rooms

=head2 add_main_menu

   $c->model( q(Navigation) )->add_main_menu;

Adds data to the stash to generate the main navigation menu. The menu uses
a Cone Trees layout which has been flattened to produce a visual trail
of breadcrumbs effect, i.e. Home > Reception > Tutorial

=head2 add_menu_back

   $c->model( q(Navigation) )->add_menu_back( $args, $menu, $ord );

Adds a history back link to the main navigation menu

=head2 add_menu_blank

   $c->model( q(Navigation) )->add_menu_blank( $args, $menu, $ord );

Adds some filler to the main navigation menu

=head2 add_menu_close

   $c->model( q(Navigation) )->add_menu_close( $args, $menu, $ord );

Adds a window close link to the main navigation menu

=head2 add_quick_links

   $c->model( q(Navigation) )->add_quick_links;

Stashes the data used to display "quick" navigation links. These
usually appear in the header and allow single click access to any
endpoint. They are identified in the configuration by adding a
I<quick_link> attribute to the I<rooms> element. The I<quick_link>
attribute value is an integer which determines the display order

=head2 add_tools_menu

   $c->model( q(Navigation) )->add_tools_menu;

Adds the stash data for the tools menu. This contains a selection of
utility options including: toggle runtime debugging, toggle footer,
skin switching, context sensitive help, about popup, email feedback
and logout option

=head2 allowed

   $bool = $c->model( q(Navigation) )->allowed( @args );

Negates the result returned by L</access_check>. Called from
L</add_main_menu> to determine if a page is accessible to a user. If
the user does not have access then do not display a link to it

=head2 push_menu_item

   $c->model( q(Navigation) )->push_menu_item( $name, $order, $ref );

Pushes an anchor widget C<$ref> onto a menu structure

=head2 retrieve

   $data = $c->model( q(Navigation) )->retrieve;

Called by L</sitemap> this method generates the table data used by
L<HTML::FormWidgets>

=head2 room_manager_form

   $c->model( q(Navigation) )->room_manager( $level, $room );

Allows for editing of the level and room definition elements in the
configuration files

=head2 sitemap

   $c->model( q(Navigation) )->sitemap;

Displays a table of all the pages on the site

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
