# @(#)$Ident: Controller.pm 2013-11-21 23:33 pjf ;

package CatalystX::Usul::Controller;

use strict;
use version; our $VERSION = qv( sprintf '0.15.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Class::Null;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw( exception is_arrayref is_hashref throw );
use CatalystX::Usul::Moose;
use HTTP::Headers::Util        qw( split_header_words );
use List::Util                 qw( first );
use TryCatch;

extends q(Catalyst::Controller);
with    q(CatalystX::Usul::TraitFor::BuildingUsul);
with    q(CatalystX::Usul::TraitFor::Controller::Cookies);

has 'action_source'    => is => 'ro',   isa => NonEmptySimpleStr,
   default             => 'action';

has 'config_class'     => is => 'ro',   isa => NonEmptySimpleStr,
   default             => 'Config';

has 'fs_class'         => is => 'ro',   isa => NonEmptySimpleStr,
   default             => 'FileSystem';

has 'global_class'     => is => 'ro',   isa => NonEmptySimpleStr,
   default             => 'Config::Globals';

has 'help_class'       => is => 'ro',   isa => NonEmptySimpleStr,
   default             => 'Help';

has 'nav_class'        => is => 'ro',   isa => NonEmptySimpleStr,
   default             => 'Navigation';

has 'realm_class'      => is => 'ro',   isa => NonEmptySimpleStr,
   default             => 'UsersSimple';

has 'user_agent_class' => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default             => sub { 'Parse::HTTP::UserAgent' };

has 'usul'             => is => 'lazy', isa => BaseClass,
   handles             => [ qw( debug encoding log ) ];

sub auto { # Allow access to authorised users. Redirect the unwanted elsewhere
   my ($self, $c) = @_; my $s = $c->stash; my $name;

   # Select the action to authenticate
   $self->_stash_action_info( $c, $name = $c->action->name || q(unknown) );
   # Redirects are open to anyone always
   $name =~ m{ \A redirect_to }mx and return TRUE;
   # Browser dependant content
   $self->_is_user_agent_ok( $c ) or return FALSE;
   # Handle closing of the application by administrators
   __want_app_closed( $c ) and return TRUE;
   $s->{app_closed} and $self->_redirect_to_page( $c, q(app_closed) );
   # Administrators can close individual actions
   $self->_is_action_state_ok( $c )
      or $self->_redirect_to_page( $c, q(action_closed) );
   # Actions with the Public attribute are open to anyone
   exists $c->action->attributes->{Public} and return TRUE;

   # The begin method stashed the navigation model object
   my $rv = $s->{nav_model}->access_check( $self->action_source, $name );

   $rv == ACCESS_OK and return TRUE;

   if ($rv == ACCESS_NO_UGRPS) {
      # Err on the side of caution and deny access if no access list is found
      my $msg = 'Action [_1] has no user/group access list';

      return $self->error_page( $c, $msg, $c->action->reverse );
   }

   if ($rv == ACCESS_UNKNOWN_USER) {
      # Force the user to authenticate. Save wanted action in session store
      $s->{session}->{wanted} = $c->action->reverse;
      $self->_redirect_to_page( $c, q(authenticate),
                                { no_action_args => TRUE } );
   }

   # Access denied, user not authorised
   $rv == ACCESS_DENIED and $self->_redirect_to_page( $c, q(access_denied) );

   return FALSE;
}

sub begin {
   my ($self, $c) = @_; my $s = $c->stash; my $req = $c->req;

   my $cfg = $c->config; my $ns = $c->action->namespace || NUL;

   $c->stash( leader => blessed $self );
   # Redirect after successful model call from a post request
   $c->stash( redirect_after_execute => TRUE );
   # No configuration game over. Implies we didn't parse homedir/appname.json
   ($cfg and $cfg->{has_loaded}) or $self->_throw_up_and_die( $c, $s );
   # Stash the session to reduce $c->can session calls
   $c->stash( session => $c->can( 'session' ) ? $c->session : {} );
   # Stash the content type from the request. Default from config
   $c->stash( __get_preferred_content_type( $req, $cfg ) );
   # Select the view from the content type
   $c->stash( current_view => $cfg->{content_map}->{ $s->{content_type} } );
   # Derive the verb from the request. View dependant
   $c->stash( verb => $c->view( $s->{current_view } )->get_verb( $c ) );
   # Recover attributes from cookies set by Javascript in the browser
   $c->stash( $self->get_browser_state( $c, $cfg ) );
   # Debug output mimics system debug but turned on within the application
   $self->_set_debug_state( $c, $s, $req );
   # Set the language to sane supported value
   $c->stash( language => __get_language( $s, $req, $cfg ) );
   # Recover the user identity from the session store
   $c->stash( user => $self->_get_user_object( $c, $s, $cfg ) );
   # Load the per request config files from cache
   $c->model( $self->config_class )->load_per_request_config( $ns );
   # Stuff some basic information into the stash
   $c->stash( $self->_get_basic_info( $c, $s, $req, $cfg, $ns ) );
   # Generate and stash some common uris
   $c->stash( $self->_get_common_uris( $c, $s, $req, $cfg, $ns ) );
   return;
}

sub deny_access {
   # Auto has allowed access to the form. Can deny access to individual actions
   # Called from the action class for "POST" requests
   my ($self, $c, $action_path) = @_;

   my $sep     = SEP; $action_path =~ s{ \A $sep }{}mx;
   my (@parts) = split m{ $sep }mx, $action_path;
   my $name    = pop @parts;
   my $ns      = join SEP, @parts;
   my $action  = $c->get_action( $name, $ns );

   exists $action->attributes->{Public} and return ACCESS_OK;

   my $navm    = $c->stash->{nav_model};
   my $rv      = $navm->access_check( $self->action_source, $action->name );

   return $rv == ACCESS_NO_UGRPS ? ACCESS_OK : $rv;
}

sub end { # Last controller method called by Catalyst
   my ($self, $c) = @_; $c->error->[ 0 ] or return $c->forward( q(render) );

   my ($class, $e, $errors); my $s = $c->stash; $s->{leader} = blessed $self;

   for my $error (grep { defined } @{ $c->error }) {
      if ($e = $error and $class = blessed $e and $e->can( q(args) )) {
         if ($s->{debug}) {
            $e->can( q(class) ) and $class = $e->class
               and $s->{stacktrace} .= "${class}\n";
            $e->can( q(stacktrace) )
               and $s->{stacktrace} .= $e->stacktrace."\n";
         }
      }
      else { $e = exception $error }

      $errors .= $e->can( q(leader) ) ? $e->leader : NUL;
      $errors .= ucfirst $self->loc( $s, $e->error, $e->args )."\n";
      $self->log->error_message( $s, $e );
   }

   $c->clear_errors; $self->_error_page( $c, $errors );

   return $c->forward( q(render) );
}

sub error_page { # Log and display a localized error message
   my ($self, $c, $error, @args) = @_; my $s = $c->stash;

   my $args = (is_arrayref $args[ 0 ]) ? $args[ 0 ] : [ @args ];
   my $e    = exception 'error' => $error, 'args' => $args;

   $s->{leader} = blessed $self; $self->log->error_message( $s, $e );
   $self->_error_page( $c, $self->loc( $s, $e->error, $e->args ) );

   return FALSE; # Must return false for auto
}

sub get_browser_state {
   # Default key/value pairs overridden by the browser state cookie values
   my ($self, $c, $cfg) = @_;

   return ( footer  => { state => TRUE },
            sbstate => FALSE,
            skin    => $cfg->{default_skin}  || q(default),
            width   => $cfg->{default_width} || 1024, );
}

sub loc { # Localize the key and substitute the placeholder args
   my ($self, $opts, $key, @args) = @_; my $car = $args[ 0 ];

   my $args = (is_hashref $car) ? { %{ $car } }
            : { params => (is_arrayref $car) ? $car : [ @args ] };

   $args->{domain_names} ||= [ DEFAULT_L10N_DOMAIN, $opts->{ns} ];
   $args->{locale      } ||= $opts->{language};

   return $self->usul->localize( $key, $args );
}

sub redirect_to_path { # Does a response redirect and detach
   my ($self, $c, $path, @args) = @_; my $s = $c->stash;

   my $default_action = __get_default_action( $s ); my $sep = SEP;

   # Normalise the path. It must contain a SEP char
   defined $path          or $path  = $sep.$default_action;
   0 <= index $path, $sep or $path .= $sep.$default_action;

   # Extract the action attributes
   my (@parts) = split m{ $sep }mx, $path;
   # Default the method name if one was not provided
   my $name    = pop @parts; $name ||= $default_action;
   my $ns      = join $sep, @parts;

   # Default the namespace
   length $ns   or $ns = ($c->action && $c->action->namespace) || ROOT;
   $ns eq ROOT and $ns = $sep; # Expand the root symbol

   defined $args[ 0 ] or @args = ();
   $c->res->redirect( $c->uri_for_action( $ns.$sep.$name, @args ) );
   $c->detach(); # Never returns
   return;
}

# Private methods
sub _error_page { # Display a customised error page
   my ($self, $c, $error) = @_; my $action = $c->action; my $s = $c->stash;

   my $body = "<h1>500 Internal Server Error</h1><pre>${error}\n</pre>";

   $s->{error} = { class => q(banner), content => ucfirst $error, level => 4 };

   $c->res->status( 500 );

   if ($self->can( q(reset_nav_menu) )) {
      try {
         $s->{nav_model} ||= $c->model( $self->nav_class );

         $self->reset_nav_menu( $c, q(back) )->clear_form( { force => TRUE } );

         $action->namespace( NUL ); $action->name( q(error) );
         return;
      }
      catch ($e) { $body .= "<pre>${e}</pre>" }
   }

   $c->res->body( $body );
   return;
}

sub _get_basic_info {
   my ($self, $c, $s, $req, $cfg, $ns) = @_;

   my $req_host = $req->uri->host;
   my $app      = $s->{application} || q(unknown);
   my $hostname = (split m{ \. }mx, $req_host)[ 0 ];
   my $platform = $s->{platform} || $hostname;
   my $navm     = $c->model( $self->nav_class );

   # TODO: Add some sort of structure to the stash. Move all globals down
   return ( action_paths => $navm ? $navm->action_paths : {},
            application  => $app,
            class        => $self->usul->config->prefix,
            dhtml        => TRUE,
            domain       => __get_request_domain( $req_host ),
            fonts        => [ split SPC, $cfg->{fonts} || NUL ],
            hidden       => {},
            host         => $req_host,
            host_port    => $req->uri->host_port,
            hostname     => $hostname,
            is_popup     => q(false),
            is_xml       => $s->{content_type} =~ m{ xml }mx ? TRUE : FALSE,
            literal_js   => [],
            nav_model    => $navm,
            nbsp         => NBSP,
            ns           => $ns,
            optional_js  => [ split SPC, $cfg->{optional_js} || NUL ],
            port         => $req->uri->port,
            page         => TRUE,
            page_title   => "${app} ${platform}",
            platform     => $platform,
            pwidth       => $cfg->{pwidth} || 40,
            root         => $cfg->{root},
            skindir      => $cfg->{skindir},
            title        => $app.SPC.(ucfirst $ns),
            token        => $cfg->{token},
            version      => eval { $self->version } || NUL, );
}

sub _get_common_uris {
   my ($self, $c, $s, $req, $cfg, $ns) = @_;

   my $sep     =  SEP;
   my $hash    =  HASH_CHAR;
   my $name    =  $c->action->name || NUL;
   my $skin    =  $sep.$cfg->{skins}.$sep.$s->{skin};
   my $path    =  "${ns}${sep}".__get_default_action( $s );
   my $base    =  $c->uri_for_action( $path );
   my $default =  "${base}${sep}"; $default =~ s{ ($sep) $sep \z }{$1}mx;
   my $comp    =  q(::Controller::).(ucfirst $ns).$hash.(ucfirst $name);
   my $help    =  $c->uri_for_action( "${sep}help", $cfg->{name}.$comp );
      $help    =~ s{ %23 }{$hash}mx;
   my $uri     =  $c->uri_for_action( "${ns}${sep}${name}", $req->captures,
                                      @{ $req->args } );

   return ( assets        => $c->uri_for( $skin ).$sep,
            base_url      => $base,
            canonical_url => $uri,
            default_url   => $default,
            form          => { action => $uri, name => $name },
            help_url      => $help,
            static        => $c->uri_for( "${sep}static" ).$sep, );
}

sub _get_unexpired_user {
   # Set user identity from the session state. Session state will be retained
   # for ninety days. User lasts for max_sess_time or two hours
   my ($self, $c, $s) = @_; my $now = time; my ($class, $max, $user);

   $s->{elapsed} = $now - ($s->{session}->{__updated} || $now);

   if ($c->can( q(user) ) and $user = $c->user) {
      delete $user->{_users};

      if ($max = $user->max_sess_time and $s->{elapsed} > $max) {
         my $model = $c->model( $class = $self->realm_class )
            or throw error => 'Class [_1] has no user model',
                     args  => [ $class ];

         $model->logout( { no_redirect => TRUE,
                           message     => 'User [_1] session expired',
                           user        => $user, } );
         return;
      }
      else {
         $s->{elapsed} > $user->sess_updt_period
            and $c->session->{__updated} = $now;
      }
   }

   return $user;
}

sub _get_unknown_user {
   my ($self, $c) = @_; state $cache; $cache and return $cache; my $class;

   my $model = $c->model( $class = $self->realm_class )
      or throw error => 'Class [_1] has no user model', args => [ $class ];
   my $user  = $model->find_user( 'unknown' ); $user and delete $user->{_users};

   return $cache = $user;
}

sub _get_user_object {
   my ($self, $c, $s, $cfg) = @_; my $user;

   if ($user = $self->_get_unexpired_user( $c, $s )) {
      my $admin_role = $cfg->{admin_role};
      # Administrators get access to all controllers and actions
      $s->{is_administrator} = (first { $_ eq $admin_role } @{ $user->roles })
                             ? TRUE : FALSE;
   }
   else {
      $user = $self->_get_unknown_user( $c ); $s->{is_administrator} = FALSE;
   }

   return $user;
}

sub _is_action_state_ok {
   my ($self, $c) = @_; my $state = $c->stash->{action_state} // ACTION_OPEN;

   # If the state attribute is > 1 then the action is closed to access
   return $state > ACTION_HIDDEN ? FALSE : TRUE;
}

sub _is_user_agent_ok {
   my ($self, $c) = @_; my $cfg = $c->config; my $s = $c->stash;

   my $header = $c->req->headers->{ q(user-agent) } || 'Mozilla';
   my $ua     = $s->{user_agent}
              = $self->user_agent_class->new( $header, { extended => 0 } );

   $cfg->{misery_page} or $cfg->{misery_skin} or return TRUE;
   (not $ua->name or $ua->name ne EVIL_EMPIRE) and return TRUE;

   if ($cfg->{misery_skin}) {
      $s->{skin  } = $cfg->{misery_skin};
      $s->{assets} = $c->uri_for( SEP.$cfg->{skins}.SEP.$s->{skin} ).SEP;
      return TRUE;
   }

   $c->res->redirect( $cfg->{misery_page} ); $c->detach(); # Never returns
   return FALSE;
}

sub _parse_HasActions_attr { ## no critic
   # Adding the HasActions attribute to a controller action causes our apps
   # action class handler to be called for each request
   my ($self, $c, $name, $value) = @_;

   return ( q(ActionClass), $c->config->{action_class} );
}

sub _redirect_to_page { # Redirects to a private action via a config attribute
   my ($self, $c, $page, $opts) = @_; my ($name, $ns);

   my $path = $c->stash->{action_paths}->{ $page }
      or return $self->error_page( $c, 'Page [_1] unknown', $page );

   unless ($opts->{no_action_args}) {
      $ns = $c->action->namespace; $name = $c->action->name || q(unknown);
   }

   $self->redirect_to_path( $c, $path, $ns, $name );
   return;
}

sub _set_debug_state {
   my ($self, $c, $s, $req) = @_;

   my $debug = defined $s->{browser_debug} ? delete $s->{browser_debug}
                                           : $c->debug;

   $self->debug( $s->{debug} = $debug );
   $debug and not $c->debug
          and $self->log->info( $req->method.SPC.$req->path );
   return;
}

sub _stash_action_info {
   my ($self, $c, $name) = @_; my $s = $c->stash;

   my $action_info = $s->{ $self->action_source } || {}; my $cfg;
   # Lookup config information for this action
   if (exists $action_info->{ $name } and $cfg = $action_info->{ $name }) {
      exists $cfg->{state } and $s->{action_state} = $cfg->{state};
      exists $cfg->{pwidth} and $s->{pwidth} = $cfg->{pwidth};
      $s->{keywords   } = $self->loc
         ( $s, $name, { context => 'action.keywords', no_default => TRUE } );
      $s->{description} = $self->loc
         ( $s, $name, { context => 'action.tip',      no_default => TRUE } );
   }

   return;
}

sub _throw_up_and_die {
   my ($self, $c, $s) = @_; my $msg = 'No configuration file loaded';

   $c->stash( page => TRUE, content_type => DEFAULT_CONTENT_TYPE );
   $self->log->fatal( $s, $msg ); throw $msg;
   return; # Never reached
}

# Private functions
sub __accepted_content_types { # Taken from jshirley's Catalyst::Action::REST
   my $req = shift; my ($accept_header, $qvalue, $type, %types);

   # First, we use the content type in the HTTP Request.  It wins all.
   $req->method eq q(GET) and $type = $req->content_type
      and $types{ $type } = 3;

   $req->method eq q(GET) and $type = $req->param( q(content-type) )
      and $types{ $type } = 2;

   # Third, we parse the Accept header, and see if the client takes a
   # format we understand.  This is taken from chansen's
   # Apache2::UploadProgress.
   if ($accept_header = $req->header( q(accept) )) {
      my $counter = 0;

      for my $pair (split_header_words( $accept_header )) {
         ($type, $qvalue) = @{ $pair }[ 0, 3 ];
         $types{ $type } and next;
         defined $qvalue or $qvalue = 1 - (++$counter / 1_000);
         $types{ $type } = sprintf q(%.3f), $qvalue;
      }
   }

   return [ reverse sort { $types{ $a } <=> $types{ $b } } keys %types ];
}

sub __extract_version_from {
   my ($versioned_type, $cfg) = @_;

   my ($rest, $format) = split m{ [+] }mx, $versioned_type;
   my ($type, $ver)    = split m{ [-] }mx, $rest;

   $format and $type .= "+${format}"; $ver and $ver =~ s{ \A v }{}mx;

   return ( $type, $ver || $cfg->{api_version} || 1 );
}

sub __get_default_action {
   my $navm = $_[ 0 ]->{nav_model};

   return $navm ? $navm->default_action : 'about';
}

sub __get_language {
   # Select from; query parameters, domain host, cookie, session key,
   # request headers, config default or hard coded
   my ($s, $req, $cfg) = @_;

   my @languages  = split SPC, $cfg->{languages}   || LANG;
   my $candidate  = $req->query_parameters->{lang} || NUL;

   __is_language( $candidate, \@languages ) and return $candidate;

   $candidate     = $req->uri->host =~ m{ \A (\w{2}) \. }mx ? $1 : NUL;

   __is_language( $candidate, \@languages ) and return $candidate;

   $candidate     = $s->{language} || NUL;

   __is_language( $candidate, \@languages ) and return $candidate;

   $candidate     = $s->{session}->{language} || NUL;

   __is_language( $candidate, \@languages ) and return $candidate;

   my $lang       = first { __is_language( $_, \@languages ) }
                            __list_acceptable_languages( $req );

   return $lang || $cfg->{language} || LANG;
}

sub __get_preferred_content_type {
   my ($req, $cfg) = @_; my ($type, $ver);

   my $types = __accepted_content_types( $req );

   # Set the content type from the client request header
   $cfg->{negotiate_content_type} ne NEGOTIATION_OFF and $type = $types->[ 0 ];

   # Chrome cannot handle what it asks for
   # Adding the !ENTITY definitions for dagger etc breaks the DOM
   $type and $cfg->{negotiate_content_type} eq NEGOTIATION_IGNORE_XML
         and $type =~ m{ \A application .+? xml \z }mx
         and $type = $cfg->{content_type};

   # Default the content type if it's not already set
  ($type and $type ne '*/*') or $type = $cfg->{content_type};
  ($type, $ver) = __extract_version_from( $type, $cfg );

   return ( 'content_type', $type, 'api_version', $ver );
}

sub __get_request_domain {
   my @parts = split m{ [\.] }mx, $_[ 0 ]; shift @parts; my $domain;

   return ($domain = join q(.), @parts) ? q(.).$domain : NUL;
}

sub __is_language { # Is this one if the languages the application supports
   my ($candidate, $languages) = @_;

   return (first { $_ eq $candidate } @{ $languages }) ? TRUE : FALSE;
}

sub __list_acceptable_languages {
   return (map { (split m{ ; }mx, $_)[ 0 ] } split m{ , }mx,
           lc( $_[ 0 ]->headers->{ q(accept-language) } || NUL ));
}

sub __want_app_closed {
   my $c = shift; my $cfg = $c->config; my $root = ROOT; my $sep = SEP;

   my $navm = $c->stash->{nav_model};
   my $path = $navm->action_paths->{app_closed} || NUL;
      $path =~ s{ \A $root $sep }{}mx;

   return $c->action->reverse eq $path ? TRUE : FALSE;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller - Application independent common controller methods

=head1 Version

This document describes CatalystX::Usul::Controller version v0.15.$Rev: 1 $

=head1 Synopsis

   package YourApp::Controller::YourController;

   BEGIN { extents qw(CatalystX::Usul::Controller) }

=head1 Description

Provides methods common to all controllers. Implements the "big three"
L<Catalyst> API methods; C<begin>, C<auto> and C<end>

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item action_source

String which defaults to C<action>. A key in the stash where meta information
about actions is stored

=item config_class

String which defaults to C<Config>

=item fs_class

String which defaults to C<FileSystem>

=item global_class

String which defaults to C<Config::Globals>

=item help_class

String which defaults to C<Help>

=item model_base_class

String which defaults to C<Base>

=item nav_class

String which defaults to C<Navigation>

=item realm_class

String which defaults to C<UsersSimple>

=item usul

A L<Class::Usul> object

=back

Extends L<Catalyst::Controller>. Applies the controller roles including;

=over 3

=item L<CatalystX::Usul::TraitFor::BuildingUsul>

=item L<CatalystX::Usul::TraitFor::Controller::Cookies>

=item L<CatalystX::Usul::TraitFor::Controller::ModelHelper>

=item L<CatalystX::Usul::TraitFor::Controller::PersistentState>

=item L<CatalystX::Usul::TraitFor::Controller::TokenValidation>

=back

=head1 Subroutines/Methods

Private methods begin with an _ (underscore). Private subroutines begin
with __ (two underscores)

=head2 auto

Control access to actions based on user roles and ACLs

This method will return true to allow the dispatcher to
forward to the requested action, or this method will redirect to
either the profile defined authentication action or one of the
predefined default actions

These actions are permanently on public access; about, access_denied,
captcha, action_closed, help, and view_source. Anonymous access is
granted to actions that have the I<Public> attribute set

Each action has a I<state> attribute which is stored in the action's
configuration file. Setting the actions I<state> attribute to a
value greater than 1 has the effect of closing the action to
access. Instead the request is redirected to the I<action_closed> action
which is implemented by the root controller. The I<state> attribute is
set/unset by the I<access_control> action in the I<Admin> controller

The list of users/groups permitted to access an action (ACL) is stored in
the configuration file. If an ACL has not been created only
members of the support group will be allowed to access the action. ACLs
can contain both user ids and group names. Group names are prefixed
with an '@' character to distinguish them from user ids

The special ACL 'any' will allow any request to access the action. If
the action does not permit public access requests from unknown users
will be redirected to the authentication action which is defined in the
package configuration

Requests for access to an action for which there is no authorisation will
be redirected to the I<access_denied> action which is implemented in
the root controller

If no ACL for an action can be determined the the request is redirected
to the I<error_page> action

=head2 begin

This method stuffs the stash with most of data needed by
L<Template::Toolkit> to generate a 'blank' page. Begin methods in
controllers forward to here. They can alter the stash contents before
and after the call to this method

The file F<default.json> contains the meta data for each
controller. Each controller has two configuration files which contain
the controller specific data. One of the files is language independent
and contains elements that define form fields and form keys. The
language dependent file contains all the literal text strings used by
that controller

The content type is either set from the configuration or if
I<negotiate_content_type> is true it is set to the first element of
the array returned by L</__accepted_content_types>. The content type is
used to lookup the current view in the I<content_map>

Once the view has been selected it's deserialization method is called
as required

The requested language is obtained by calling L</__get_language>

Once the language is known the stash is further populated by calling
L</_stash_per_request_config>

=head2 deny_access

   $bool = $self->deny_access( $c );

Returns true if the user is denied access to the requested action

=head2 end

Calls
L<add_token|CatalystX::Usul::Plugin::Controller::TokenValidation/add_token>
if the current page should contain a token and the plugin has been
loaded. Traps and processes any errors. Forwards to the C<render>
method which has the action class attribute set to C<RenderView>

=head2 error_page

   $self->error_page( $c, $error_message_key, @args );

Generic error page which displays the specified message. The error message is
localized by calling the L<localize|CatalystX::Usul/loc> method in the base
class

=head2 get_browser_state

   $self->get_browser_state( $c, $c->config );

Recover information stored in the browser state cookie. Uses the
L<CatalystX::Usul::TraitFor::Controller::Cookies> module if it's loaded

=head2 loc

   $local_text = $self->loc( $c->stash, $key, @options );

Localizes the message. Calls L<Class::Usul::L10N/localize>. Adds the
constant C<DEFAULT_L10N_DOMAINS> to the list of domain files that are
searched. Adds C<< $c->stash->{language} >> and C<< $c->stash->{namespace} >>
(search domain) to the arguments passed to C<localize>

=head2 redirect_to_path

   $self->redirect_to_path( $c, $action_path, @args );

Sets redirect on the response object and then detaches. Defaults
to the I<default_action> config attribute if the action path is null

=head1 Private Methods

=head2 _get_user_object

   $c->stash->{user} = $self->_get_user_object( $c, $c->stash, $c->config );

Using this system, sessions do not expire for three months. Instead the
user key is expired after a period of inactivity. This method recovers
information about the user and stores it on the stash. Everywhere else
the stashed information is used as required

=head2 _is_user_agent_ok

   $bool = $self->_is_user_agent_ok( $c );

Detects use of the misery browser. Sets the skin to
C<< $c->config->{misery_skin} >> if its defined. Otherwise redirects to
C<< $c->config->{misery_page} >> if that is defined. Otherwise serves
up a W3C validated page for Exploiter to render as garbage

=head2 _parse_HasActions_attr

Associates the C<HasActions> method attribute with the action class defined
in the C<action_class> configuration attribute

=head2 _redirect_to_page

   $self->_redirect_to_page( $c, $page_name );

Takes a simple page name works out it's private path and then calls
L</redirect_to_path>

=head1 Private Subroutines

=head2 __accepted_content_types

   $types = __accepted_content_types( $c->req );

Taken from jshirley's L<Catalyst::Action::REST>

Returns an array reference of content types accepted by the
client

The list of types is created by looking at the following sources:

=over 3

=item Content-type header

If this exists and the request is a GET request, this will always be
the first type in the list

=item Content-type parameter

If the request is a GET request and there is a "content-type"
parameter in the query string, this will come before any types in the
Accept header

=item Accept header

This will be parsed and the types found will be ordered by the
relative quality specified for each type

=back

If a type appears in more than one of these places, it is ordered based on
where it is first found.

=head2 __get_language

   $language = __get_language( $c->stash, $c->req, $c->config );

In order of precedence uses; the first capture argument, the
I<accept-language> headers from the request, the configuration default
and finally the hard coded default which is B<en> (English)

=head2 __is_language

   $bool = __is_language( $candidate, \@languages );

Tests to see if the given language is supported by the current configuration

=head2 __preferred_content_type

   $content_type = __preferred_content_type( $c->req, $c->config );

Returns the first accepted content type if the I<negotiate_content_type>
config attribute is true. Defaults to the config attribute I<content_type>

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Catalyst::Controller>

=item L<Class::Usul>

=item L<CatalystX::Usul::Moose>

=item L<HTTP::Headers::Util>

=item L<Parse::HTTP::UserAgent>

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

Copyright (c) 2014 Pete Flanigan. All rights reserved

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
