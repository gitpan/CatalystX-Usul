# @(#)$Id: Controller.pm 1166 2012-04-03 12:37:30Z pjf $

package CatalystX::Usul::Controller;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1166 $ =~ /\d+/gmx );
use parent qw(Catalyst::Controller CatalystX::Usul);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions
   qw(app_prefix arg_list exception is_arrayref throw);
use HTTP::DetectUserAgent;
use HTTP::Headers::Util qw(split_header_words);
use List::Util qw(first);
use MRO::Compat;
use Scalar::Util qw(blessed);
use TryCatch;

__PACKAGE__->config( action_source    => q(action),
                     config_class     => q(Config),
                     fs_class         => q(FileSystem),
                     global_class     => q(Config::Globals),
                     help_class       => q(Help),
                     model_base_class => q(Base),
                     nav_class        => q(Navigation),
                     realm_class      => q(IdentitySimple), );

__PACKAGE__->mk_accessors( qw(action_source config_class fs_class
                              global_class help_class model_base_class
                              nav_class realm_class) );

sub COMPONENT {
   my ($class, $app, $config) = @_; __setup_plugins( $app );

   my $new  = $class->next::method( $app, $config );
   my $usul = CatalystX::Usul->new( $app, {} );

   for (grep { not defined $new->{ $_ } } keys %{ $usul }) {
      $new->{ $_ } = $usul->{ $_ };
   }

   return $new;
}

sub auto {
   # Allow access to authorised users. Redirect the unwanted elsewhere
   my ($self, $c) = @_; my $s = $c->stash;

   # Select the action to authenticate
   my $name = $c->action->name || q(unknown);

   # Redirects are open to anyone always
   $name =~ m{ \A redirect_to }mx and return TRUE;
   # Browser dependant content
   $self->user_agent_ok( $c ) or return FALSE;
   # Handle closing of the application by administrators
   __want_app_closed( $c ) and return TRUE;
   $s->{app_closed} and $self->redirect_to_page( $c, q(app_closed) );
   # Administrators can close individual actions
   $self->_action_state_ok( $c, $name )
      or $self->redirect_to_page( $c, q(action_closed) );
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
      $c->can( q(session) ) and $c->session->{wanted} = $c->action->reverse;
      $self->redirect_to_page( $c, q(authenticate), { no_action_args => TRUE });
   }

   # Access denied, user not authorised
   $rv == ACCESS_DENIED and $self->redirect_to_page( $c, q(access_denied) );

   return FALSE;
}

sub begin {
   my ($self, $c, @rest) = @_; my $req = $c->req; my $s = $c->stash; my $cfg;

   # No configuration game over. Implies we didn't parse homedir/appname.xml
   unless ($cfg = $c->config and $cfg->{has_loaded}) {
      $s->{leader} = blessed $self;
      $self->log_fatal_message( 'No configuration file loaded', $s );
      return;
   }

   # Stash the content type from the request. Default from config
   $s->{content_type} = __preferred_content_type( $c );
   # Select the view from the content type
   $s->{current_view} = $cfg->{content_map}->{ $s->{content_type} };
   # Derive the verb from the request. View dependant
   $s->{verb} = $c->view( $s->{current_view } )->get_verb( $c );
   # Deserialize the request if necessary
   $s->{data} = __deserialize( $c );
   # Recover the user identity from the session store
   $self->_stash_user_attributes( $c );
   # Recover attributes from cookies set by Javascript in the browser
   $self->_stash_browser_state( $c );
   # Set the language to sane supported value
   $s->{lang} = __get_language( $c );
   # Debug output mimics system debug but turned on within the application
   $s->{debug} and not $c->debug
               and $self->log_debug( $req->method.SPC.$req->path );
   # Load the config files from cache
   my $model; $model = $c->model( $self->config_class )
      and $model->load_per_request_config;

   my $ns   = $c->action->namespace || NUL;
   my $name = $c->action->name      || NUL;
   my $navm = $c->model( $self->nav_class );

   # Stuff some basic information into the stash
   $s->{application} = q(unknown) unless ($s->{application});
   $s->{class      } = $self->prefix;
   $s->{dhtml      } = TRUE;
   $s->{domain     } = $req->uri->host;
   $s->{encoding   } = $self->encoding;
   $s->{fonts      } = [ split SPC, $cfg->{fonts} || NUL ];
   $s->{hidden     } = {};
   $s->{host_port  } = $req->uri->host_port;
   $s->{host       } = (split m{ \. }mx, ucfirst $s->{domain})[ 0 ];
   $s->{is_popup   } = q(false);
   $s->{is_xml     } = TRUE if ($s->{content_type} =~ m{ xml }mx);
   $s->{literal_js } = [];
   $s->{nav_model  } = $navm;
   $s->{nbsp       } = NBSP;
   $s->{ns         } = $ns;
   $s->{optional_js} = [ split SPC, $cfg->{optional_js} || NUL ];
   $s->{port       } = $req->uri->port;
   $s->{page       } = TRUE;
   $s->{platform   } = $s->{host_port} unless ($s->{platform});
   $s->{page_title } = $s->{application}.SPC.$s->{platform};
   $s->{pwidth     } = $cfg->{pwidth} || 40;
   $s->{root       } = $cfg->{root};
   $s->{skindir    } = $cfg->{skindir};
   $s->{title      } = $s->{application}.SPC.(ucfirst $ns);
   $s->{token      } = $cfg->{token};
   $s->{version    } = eval { $self->version };

   # Generate and stash some uris
   my $sep  = SEP;
   my $hash = HASH_CHAR;
   my $mark = $ns.$hash.(ucfirst $name);
   my $skin = $sep.$cfg->{skins}.$sep.$s->{skin};
   my $path = $ns.$sep.($navm ? $navm->default_action : q(about));
   my $uri  = $c->uri_for_action( $ns.$sep.$name, $c->req->captures );

   $s->{assets     } = $c->uri_for( $skin ).$sep;
   $s->{form       } = { action => $uri, name => $name };
   $s->{help_url   } = $c->uri_for_action( $sep.q(help), $mark );
   $s->{help_url   } =~ s{ %23 }{$hash}mx;
   $s->{static     } = $c->uri_for( $sep.q(static) ).$sep;
   $s->{default_url} = $c->uri_for_action( $path ).$sep;
   $s->{default_url} =~ s{ ($sep) $sep \z }{$1}mx;
   return;
}

sub deny_access {
   # Auto has allowed access to the form. Can deny access to individual actions
   my ($self, $c, $action_path) = @_;

   my $sep     = SEP; $action_path =~ s{ \A $sep }{}mx;
   my (@parts) = split m{ $sep }mx, $action_path;
   my $name    = pop @parts;
   my $ns      = join SEP, @parts;
   my $action  = $c->get_action( $name, $ns );

   exists $action->attributes->{Public} and return ACCESS_OK;

   my $model   = $c->stash->{nav_model};
   my $rv      = $model->access_check( $self->action_source, $action->name );

   return $rv == ACCESS_NO_UGRPS ? ACCESS_OK : $rv;
}

sub end {
   # Last controller method called by Catalyst
   my ($self, $c) = @_; my $s = $c->stash;

   $self->can( q(add_token) ) and $self->add_token( $c );
   $c->error->[ 0 ] or return $c->forward( q(render) );

   my ($class, $e, $errors); $s->{leader} = blessed $self;

   for my $error (grep { defined } @{ $c->error }) {
      if ($e = $error and $class = blessed $e and $e->can( q(stacktrace) )) {
         $s->{debug} and $s->{stacktrace} .= $class."\n".$e->stacktrace."\n";
      }
      else { $e = exception $error }

      $self->log_error_message( $e, $s );
      $errors .= ucfirst $self->loc( $s, $e->error, $e->args )."\n";
   }

   $self->_error_page( $c, $errors ); $c->clear_errors;

   return $c->forward( q(render) );
}

sub error_page {
   # Log and display a localized error message
   my ($self, $c, $error, @rest) = @_; my $s = $c->stash;

   my $args = (is_arrayref $rest[ 0 ]) ? $rest[ 0 ] : [ @rest ];
   my $e    = exception 'error' => $error, 'args' => $args;

   $s->{leader} = blessed $self;
   $self->log_error_message( $e, $s );
   $self->_error_page( $c, $self->loc( $s, $e->error, $e->args ) );

   return FALSE; # Must return false for auto
}

sub redirect_to_page {
   # Redirects to a private action path via a config attribute
   my ($self, $c, $page, $opts) = @_; my ($name, $ns);

   my $path = $c->config->{ $page }
      or return $self->error_page( $c, 'Page [_1] unknown', $page );

   unless ($opts->{no_action_args}) {
      $ns = $c->action->namespace; $name = $c->action->name || q(unknown);
   }

   $self->redirect_to_path( $c, $path, $ns, $name );
   return;
}

sub redirect_to_path {
   # Does a response redirect and detach
   my ($self, $c, $path, @rest) = @_; my $s = $c->stash; my $sep = SEP;

   my $navm           = $s->{nav_model};
   my $default_action = $navm ? $navm->default_action : q(about);

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

   defined $rest[ 0 ] or @rest = ();
   $self->can( q(do_not_add_token) ) and $self->do_not_add_token( $c );
   $c->res->redirect( $c->uri_for_action( $ns.$sep.$name, @rest ) );
   $c->detach(); # Never returns
   return;
}

sub user_agent_ok {
   my ($self, $c) = @_; my $cfg = $c->config; my $s = $c->stash;

   $cfg->{misery_page} or $cfg->{misery_skin} or return TRUE;

   my $header = $c->req->headers->{ q(user-agent) } || NUL;
   my $ua     = $s->{user_agent} = HTTP::DetectUserAgent->new( $header );

   (not $ua->vendor or $ua->vendor ne EVIL_EMPIRE) and return TRUE;

   if ($cfg->{misery_skin}) {
      $s->{skin  } = $cfg->{misery_skin};
      $s->{assets} = $c->uri_for( SEP.$cfg->{skins}.SEP.$s->{skin} ).SEP;
      return TRUE;
   }

   $c->res->redirect( $cfg->{misery_page} ); $c->detach(); # Never returns
   return FALSE;
}

# Private methods

sub _action_state_ok {
   my ($self, $c, $name) = @_; my $s = $c->stash; my $state = ACTION_OPEN;

   my $action_info = $s->{ $self->action_source } || {}; my $cfg;

   # Lookup config information for this action
   if (exists $action_info->{ $name } and $cfg = $action_info->{ $name }) {
      exists $cfg->{state } and $state = $cfg->{state};
      exists $cfg->{pwidth} and $s->{pwidth} = $cfg->{pwidth};
      $s->{keywords   } = $self->loc( $s, $name.q(.keywords),
                                      { no_default => TRUE } );
      $s->{description} = $self->loc( $s, $name.q(.tip),
                                      { no_default => TRUE } );
   }

   # If the state attribute is > 1 then the action is closed to access
   return $state > ACTION_HIDDEN ? FALSE : TRUE;
}

sub _error_page {
   # Display a customised error page
   my ($self, $c, $error) = @_; my $action = $c->action; my $s = $c->stash;

   $s->{error} = { class => q(banner), content => ucfirst $error, level => 4 };

   try {
      $self->add_header( $c );

      $self->reset_nav_menu( $c, q(back) )->clear_form( { force => TRUE } );

      $action->namespace( NUL ); $action->name( q(error) );
   }
   catch ($e) { $c->res->body( q(<pre>).$error."\n".$e.q(</pre>) ) }

   return;
}

sub _parse_HasActions_attr { ## no critic
   # Adding the HasActions attribute to a controller action causes our apps
   # action class handler to be called for each request
   my ($self, $c, $name, $value) = @_;

   return ( q(ActionClass), $c->config->{action_class} );
}

sub _stash_browser_state {
   # Extract key/value pairs from the browser state cookie
   my ($self, $c) = @_; my $cfg = $c->config; my $s = $c->stash;

   $s->{cookie_path  } = $cfg->{cookie_path} || SEP;
   $s->{cookie_prefix} = app_prefix $cfg->{name};

   # Call the controller plugin if it's loaded
   my $default_state = { fstate  => TRUE,
                         sbstate => TRUE,
                         skin    => $cfg->{default_skin}  || q(default),
                         width   => $cfg->{default_width} || 1024, };
   my $cookie_name   = $s->{cookie_prefix}.q(_state);
   my $browser_state = $self->can( q(get_browser_state) )
                     ? $self->get_browser_state( $c, $cookie_name ) : {};
   my $debug         = $s->{is_administrator}
                     ? $browser_state->{debug} : $c->debug;

   $c->stash( %{ $default_state }, %{ $browser_state } );
   $c->stash( debug => $debug );
   return;
}

sub _stash_user_attributes {
   # Set user identity from the session state. Session state will be retained
   # for ninety days. User lasts for max_sess_time or two hours
   my ($self, $c) = @_; my $s = $c->stash; my $now = time; my $user;

   my $admin_role = $c->config->{admin_role};
   my $session    = $c->can( q(session) ) ? $c->session : {};

   $s->{elapsed}  = $now - ($session->{last_visit} || $now);
   $s->{expires}  = $s->{max_sess_time} || 7_200;
   $s->{user   }  = NUL;

   if ($c->can( 'user' ) and $user = $c->user) {
      if ($s->{elapsed} < $s->{expires}) {
         $session->{last_visit} = $now;
         $s->{user      } = $user->username;
         $s->{user_email} = $user->email_address;
         $s->{firstName } = $user->first_name || NUL;
         $s->{lastName  } = $user->last_name || NUL;
         $s->{roles     } = $user->roles;
         $s->{name      } = $s->{firstName}.SPC.$s->{lastName};
      }
      else {
         my $msg = 'User [_1] session expired';

         $self->log_info( $self->loc( $s, $msg, $user->username ) );
         $c->can( q(session) ) and $c->session_expire_key( __user => FALSE );
         $c->logout;
      }
   }

   unless ($s->{user}) {
      $s->{user      } = q(unknown);
      $s->{user_email} = NUL;
      $s->{name      } = NUL;
      $s->{firstName } = q(Dave);
      $s->{lastName  } = NUL;
      $s->{roles     } = [];
   }

   # Administrators get access to all controllers and actions
   $s->{is_administrator}
      = (first { $_ eq $admin_role } @{ $s->{roles} }) ? TRUE : FALSE;

   return;
}

# Private subroutines

sub __accepted_content_types {
   # Taken from jshirley's Catalyst::Action::REST
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

sub __deserialize {
   my $c       = shift;
   my $s       = $c->stash;
   my $verb    = $s->{verb} or return;
   my $view    = $c->view( $s->{current_view } );
   my %methods = ( options => 1, post => 1, put => 1, );

   return $methods{ $verb } ? $view->deserialize( $s, $c->req ) : NUL;
}

sub __get_language {
   # Select from; query parameters, domain host, cookie, session key,
   # request headers, config default or hard coded
   my $c          = shift;
   my $req        = $c->req;
   my $cfg        = $c->config;
   my $session    = $c->can( q(session) ) ? $c->session : {};
   my @languages  = split SPC, $cfg->{languages}   || LANG;
   my $candidate  = $req->query_parameters->{lang} || NUL;

   __is_language( $candidate, \@languages ) and return $candidate;

   $candidate     = $req->uri->host =~ m{ \A (\w{2}) \. }mx ? $1 : NUL;

   __is_language( $candidate, \@languages ) and return $candidate;

   $candidate     = $c->stash->{lang} ||  NUL;

   __is_language( $candidate, \@languages ) and return $candidate;

   $candidate     = $session->{language} || NUL;

   __is_language( $candidate, \@languages ) and return $candidate;

   my $lang       = first { __is_language( $_, \@languages ) }
                            __list_acceptable_languages( $req );

   return $lang || $cfg->{language} || LANG;
}

sub __is_language {
   # Is this one if the languages the application supports
   my ($candidate, $languages) = @_;

   return (first { $_ eq $candidate } @{ $languages }) ? TRUE : FALSE;
}

sub __list_acceptable_languages {
   my $req = shift;

   return (map    { (split m{ ; }mx, $_)[ 0 ] }
           split m{ , }mx, lc( $req->headers->{ q(accept-language) } || NUL ));
}

sub __preferred_content_type {
   my $c = shift; my $cfg = $c->config; my $type;

   my $types = __accepted_content_types( $c->req );

   # Set the content type from the client request header
   $cfg->{negotiate_content_type} ne NEGOTIATION_OFF and $type = $types->[ 0 ];

   # Chrome cannot handle what it asks for
   # Adding the !ENTITY definitions for dagger etc breaks the DOM
   if ($type and $cfg->{negotiate_content_type} eq NEGOTIATION_IGNORE_XML) {
      ($type eq q(application/xml) or $type eq q(application/xhtml+xml))
         and $type = $cfg->{content_type};
   }

   # Default the content type if it's not already set
   (not $type or $type eq q(*/*)) and $type = $cfg->{content_type};

   return $type;
}

sub __setup_plugins {
   # Load the controller plugins
   my $app  = shift; my $plugins;

   $plugins = __PACKAGE__->get_inherited( q(_c_plugins) ) and return $plugins;

   my $cfg  = { search_paths => [ q(::Plugin::Controller) ],
                %{ $app->config->{ setup_plugins } || {} } };

   $plugins = __PACKAGE__->setup_plugins( $cfg );

   return __PACKAGE__->set_inherited( q(_c_plugins), $plugins );
}

sub __want_app_closed {
   my $c = shift; my $cfg = $c->config; my $root = ROOT; my $sep = SEP;

   my $path = $cfg->{app_closed} || NUL; $path =~ s{ \A $root $sep }{}mx;

   return $c->action->reverse eq $path ? TRUE : FALSE;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller - Application independent common controller methods

=head1 Version

This document describes CatalystX::Usul::Controller version 0.6.$Rev: 1166 $

=head1 Synopsis

   package CatalystX::Usul;
   use parent qw(CatalystX::Usul::Base CatalystX::Usul::Encoding);

   package CatalystX::Usul::Controller;
   use parent qw(Catalyst::Controller CatalystX::Usul);

   package YourApp::Controller::YourController;
   use parent qw(CatalystX::Usul::Controller);

=head1 Description

Provides methods common to all controllers. Implements the "big three"
L<Catalyst> API methods; B<begin>, B<auto> and B<end>

=head1 Subroutines/Methods

Private methods begin with an _ (underscore). Private subroutines begin
with __ (two underscores)

=head2 COMPONENT

The constructor stores a copy of the application instance for future
reference. It does this to remain compatible with L<Catalyst::Controller>
whose constructor is no longer called

Extracts the phase number from the configuration's I<appldir>
attribute.  The phase number is used to select one of a set of
configuration files

Loads the controller plugins including;

=over 3

=item L<CatalystX::Usul::Plugin::Controller::Cookies>

=item L<CatalystX::Usul::Plugin::Controller::ModelHelper>

=item L<CatalystX::Usul::Plugin::Controller::TokenValidation>

=back

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

This method stuffs the stash with most of data needed by TT to
generate a 'blank' page. Begin methods in controllers forward to
here. They can alter the stash contents before and after the call to
this method

The file F<default.xml> contains the meta data for each
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
method which has the action class attribute set to 'RenderView'

=head2 error_page

   $self->error_page( $c, $error_message_key, @args );

Generic error page which displays the specified message. The error message is
localized by calling the L<localize|CatalystX::Usul/loc> method in the base
class

=head2 redirect_to_page

   $self->redirect_to_page( $c, $page_name );

Takes a simple page name works out it's private path and then calls
L</redirect_to_path>

=head2 redirect_to_path

   $self->redirect_to_path( $c, $action_path, @args );

Sets redirect on the response object and then detaches. Defaults
to the I<default_action> config attribute if the action path is null

=head2 user_agent_ok

   $bool = $self->user_agent_ok( $c );

Detects use of the misery browser. Sets the skin to
C<< $c->config->{misery_skin} >> if its defined. Otherwise redirects to
C<< $c->config->{misery_page} >> if that is defined. Otherwise serves
up a W3C validated page for Exploiter to render as garbage

=head1 Private Methods

=head2 _stash_browser_state

   $self->_stash_browser_state( $c );

Recover information stored in the browser state cookie. Uses the
L<CatalystX::Usul::Plugin::Controller::Cookies> module if it's loaded

=head2 _stash_user_attributes

   $self->_stash_user_attributes( $c );

Using this system sessions do not expire for three months. Instead the
user key is expired after a period of inactivity. This method recovers
information about the user and stores it on the stash. Everywhere else
the stashed information is used as required

=head2 _parse_HasActions_attr

Associates the B<HasActions> method attribute with the action class defined
in the I<action_class> configuration attribute

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

=head2 __deserialize

   $data = __deserialize( $c, $verb );

Calls C<deserialize> on the current view if the request is one of; options,
post, or put

=head2 __get_language

   $language = __get_language( $c );

In order of precedence uses; the first capture argument, the
I<accept-language> headers from the request, the configuration default
and finally the hard coded default which is B<en> (English)

=head2 __is_language

   $bool = __is_language( $candidate, \@languages );

Tests to see if the given language is supported by the current configuration

=head2 __preferred_content_type

   $content_type = __preferred_content_type( $c->config, $c->req );

Returns the first accepted content type if the I<negotiate_content_type>
config attribute is true. Defaults to the config attribute I<content_type>

=head2 __setup_plugins

   __setup_plugins( $app );

Load and instantiate any installed controller plugins. Called from the
constructor

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Catalyst::Controller>

=item L<CatalystX::Usul>

=item L<CatalystX::Usul::ModelHelper>

=item L<HTTP::DetectUserAgent>

=item L<HTTP::Headers::Util>

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

Copyright (c) 2008 Pete Flanigan. All rights reserved

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
