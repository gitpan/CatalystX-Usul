package CatalystX::Usul::Controller;

# @(#)$Id: Controller.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul Catalyst::Controller);
use CatalystX::Usul::PersistentState;
use Class::C3;
use Config;
use HTTP::Headers::Util qw(split_header_words);
use List::Util qw(first);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

__PACKAGE__->mk_accessors( qw(namespace phase) );

my $HASH = chr 35;
my $NUL  = q();
my $SEP  = q(/);
my $SPC  = q( );
my $TTS  = q( ~ );

sub new {
   my ($self, $app, @rest) = @_; my $class = ref $self || $self;

   $class->_setup_plugins( $app );

   my $new = $class->next::method( $app, @rest );

   # Determine phase number from install path
   my $appldir = $new->basename( $app->config->{appldir} || $NUL ) || $NUL;
   my ($phase) = $appldir =~ m{ \A v \d+ \. \d+ p (\d+) \z }msx;

   $new->phase( $phase || 3 );
   # This replaces what would have happened in Catalyst::Controller->new
   $new->_application( $app );

   return $new;
}

sub accepted_content_types {
   # Taken from jshirley's Catalyst::Action::REST
   my ($self, $req) = @_; my ($accept_header, $qvalue, $type, %types);

   # First, we use the content type in the HTTP Request.  It wins all.
   if ($req->method eq q(GET) and $type = $req->content_type) {
      $types{ $type } = 3;
   }

   if ($req->method eq q(GET) and $type = $req->param( q(content-type) )) {
      $types{ $type } = 2;
   }

   # Third, we parse the Accept header, and see if the client takes a
   # format we understand.  This is taken from chansen's
   # Apache2::UploadProgress.
   if ($accept_header = $req->header( q(accept) )) {
      my $counter = 0;

      for my $pair (split_header_words( $accept_header )) {
         ($type, $qvalue) = @{ $pair }[ 0, 3 ];

         next if ($types{ $type });

         $qvalue = 1 - (++$counter / 1_000) unless (defined $qvalue);

         $types{ $type } = sprintf q(%.3f), $qvalue;
      }
   }

   return [ reverse sort { $types{ $a } <=> $types{ $b } } keys %types ];
}

sub auto {
   # Allow access to authorised users. Forward the unwanted elsewhere
   my ($self, $c) = @_; my ($closed, $rv, $rooms);

   # Browser dependant content
   return 0 unless ($self->user_agent_ok( $c ));

   my $cfg = $c->config; my $s = $c->stash;

   # Select the room to authenticate
   my $name = $c->action->name || q(unknown);

   # Redirects are open to anyone always
   return 1 if ($name =~ m{ \A redirect_to }mx);

   # Handle closing of the application by administrators
   my $path = $cfg->{app_closed} || $NUL; $path =~ s{ \A root / }{}mx;

   return 1 if ($c->action->reverse eq $path);

   $self->redirect_to_page( $c, q(app_closed) ) if ($s->{app_closed});

   # If the state attribute is > 1 then the room is closed
   if ($rooms = $s->{rooms} and exists $rooms->{ $name }) {
      $closed = exists $rooms->{ $name }->{state}
              ? $rooms->{ $name }->{state} : 0;
   }
   else { $closed = 0 }

   $self->redirect_to_page( $c, q(room_closed) ) if ($closed > 1);

   # Rooms with the Public attribute are open to anyone
   return 1 if (exists $c->action->attributes->{ q(Public) });

   # Must have an authentication page configured
   $path = $cfg->{authenticate};

   return $self->error_page( $c, q(eNoAuthenicatePage) ) unless ($path);

   my $model = $c->model( q(Navigation) );

   # Zero return value from access_check grants access to wanted room
   return 1 unless ($rv = $model->access_check( q(rooms), $name ));

   if ($rv == 1) {
      # Err on the side of caution and deny access if no access list is found
      return $self->error_page( $c, q(eNoACL), $c->action->reverse );
   }

   if ($rv == 2) {
      # Force the user to authenticate. Save the wanted room in session store
      $c->session->{wanted} = $c->action->reverse;
      $self->redirect_to_path( $c, $path );
   }

   # Access denied, user not authorised
   $self->redirect_to_page( $c, q(access_denied) ) if ($rv == 3);

   return 0;
}

sub begin {
   my ($self, $c, @rest) = @_; my $cfg;

   # No configuration game over. Implies we didn't parse homedir/appname.xml
   unless ($cfg = $c->config and $cfg->{default_action}) {
      $self->log_fatal( 'No config '.$cfg->{file} );
      return;
   }

   my $s = $c->stash; my $req = $c->req;

   # Stash the content type from the request. Default from config
   my $content_type = $self->preferred_content_type( $cfg, $req );

   $s->{content_type} = $self->content_type( $content_type );

   # Select the view from the content type
   $s->{current_view} = $cfg->{content_map}->{ $content_type };

   # Derive the verb from the request. View dependant
   $s->{verb} = $c->view( $s->{current_view } )->get_verb( $s, $req );

   # Deserialize the request if necessary
   $s->{data} = $self->deserialize( $c );

   # Set the language to sane supported value
   $s->{lang} = $self->get_language( $cfg, $req );

   # Cut down on the number of $c->config calls
   $s->{admin_role} = $cfg->{admin_role};

   # Read the config files from cache
   $self->load_stash_per_request( $c );

   # Debug output mimics system debug but turned on within the application
   if ($s->{debug} && !$c->debug) {
      $self->log_debug( $req->method.$SPC.$req->path );
   }

   my $namespace = $c->action->namespace || $NUL;
   my $name      = $c->action->name      || $NUL;
   my $uri       = $self->uri_for( $c, $namespace.$SEP.$name, $s->{lang} );
   my $mark      = join $HASH, split m{ $SEP }mx, $c->action;
   my $help      = q(root).$SEP.q(help);

   # Stuff some basic information into the stash
   $s->{application} = q(unknown) unless ($s->{application});
   $s->{assets     } = $c->uri_for( $SEP.$cfg->{skins}.$SEP.$s->{skin} ).$SEP;
   $s->{body       } = 1;
   $s->{class      } = $self->prefix;
   $s->{dhtml      } = 1;
   $s->{domain     } = $req->uri->host;
   $s->{encoding   } = $self->encoding;
   $s->{form       } = { action => $uri, name => $name };
   $s->{help_url   } = $self->uri_for( $c, $help, $s->{lang}, $mark );
   $s->{help_url   } =~ s{ %23 }{$HASH}mx;
   $s->{host_port  } = $req->uri->host_port;
   $s->{host       } = (split m{ \. }mx, ucfirst $s->{domain})[0];
   $s->{is_popup   } = q(false);
   $s->{is_xml     } = 1 if ($content_type =~ m{ xml }mx);
   $s->{nbsp       } = q(&nbsp;);
   $s->{port       } = $req->uri->port;
   $s->{page       } = 1;
   $s->{platform   } = $s->{host_port} unless ($s->{platform});
   $s->{page_title } = $s->{application}.$SPC.$s->{platform};
   $s->{root       } = $cfg->{root};
   $s->{sess_path  } = $SEP;
   $s->{skindir    } = $cfg->{skindir};
   $s->{static     } = $c->uri_for( $SEP.q(static) ).$SEP;
   $s->{title      } = $s->{application}.$SPC.(ucfirst $namespace);
   $s->{token      } = $cfg->{token};
   $s->{version    } = eval { $self->version };
   $s->{url        } = $self->uri_for( $c, $namespace, $s->{lang} ).$SEP;

   return;
}

sub deserialize {
   my ($self, $c) = @_; my $s = $c->stash;

   return unless ($s->{verb});

   my $should = (grep { $_ eq $s->{verb} } ( qw(options post put) )) ? 1 : 0;
   my $view   = $c->view( $s->{current_view } );

   return $should ? $view->deserialize( $s, $c->req ) : $NUL;
}

sub end {
   # Last controller method called by Catalyst
   my ($self, $c) = @_;

   $self->maybe::next::method( $c );
   $c->forward( q(render) );
   return;
}

sub error_page {
   # Display an error message
   my ($self, $c, @rest) = @_; my $s = $c->stash; my $e;

   my $msg = $self->loc( @rest ); my $model = $c->model( q(Base) );

   $s->{subHeading} = ucfirst $msg;
   $self->log_error( (ref $self).$SPC.$msg );
   $c->action->reverse( q(error_page) );

   eval { $model->clear_controls; $model->simple_page( q(error) ) };

   $c->res->body( $msg.$TTS.$e->as_string ) if ($e = $self->catch);

   $self->add_menu_back( $c ) if ($self->can( 'add_menu_back' ));

   # Must return false for auto
   return 0;
}

sub get_key {
   my ($self, $c, @rest) = @_;

   return CatalystX::Usul::PersistentState->get_key( $c, @rest );
}

sub get_language {
   # Select from; captured args, request headers, config default or hard coded
   my ($self, $cfg, $req) = @_;

   my @languages  = split $SPC, $cfg->{languages} || q(en);
   my $candidate  = lc substr $req->captures->[0] || $NUL, 0, 2;

   return $candidate if (__is_language( $candidate, \@languages ));

   my @candidates = map    { lc ((split m{ ; }mx, $_)[ 0 ]) }
                    split m{ , }mx,
                    $req->headers->{ 'accept-language' } || $NUL;
   my $lang       = first  { __is_language( $_, \@languages ) } @candidates;

   return $lang || $cfg->{language} || q(en);
}

sub load_keys {
   my ($self, $c) = @_;

   return CatalystX::Usul::PersistentState->load_keys( $c );
}

sub load_stash_from_user {
   # Set user identity from the session state. Session state will be retained
   # for ninety days. User lasts for max_sess_time or two hours
   my ($self, $c) = @_; my $s = $c->stash; my $now = time;

   $s->{elapsed}  = $now - (($c->session && $c->session->{elapsed}) || $now);
   $s->{expires}  = $s->{max_sess_time} || 7_200;
   $s->{user   }  = $NUL;

   if ($c->user) {
      if ($s->{elapsed} < $s->{expires}) {
         $c->session->{elapsed} = $now;
         $s->{user     } = $c->user->username;
         $s->{name     } = $c->user->first_name.$SPC.$c->user->last_name;
         $s->{firstName} = $c->user->first_name;
         $s->{lastName } = $c->user->last_name;
         $s->{roles    } = $c->user->roles;
      }
      else {
         my $msg = (ucfirst ref $self).': Session expired for user ';

         $self->log_info( $msg.$c->user->username );
         $c->session_expire_key( __user => 0 );
         $c->logout;
      }
   }

   unless ($s->{user}) {
      $s->{user     } = q(unknown);
      $s->{name     } = $NUL;
      $s->{firstName} = $NUL;
      $s->{lastName } = $NUL;
      $s->{roles    } = [];
   }

   # Anyone in the administrators role gets access to all levels and rooms
   $s->{is_administrator}
      = (first { $_ eq $s->{admin_role} } @{ $s->{roles} }) ? 1 : 0;

   return;
}

sub load_stash_per_request {
   # Read the XML config from the cached copy in the data model
   my ($self, $c) = @_; my $s = $c->stash; my ($e, $namespace);

   # Merge the hashes from each file in order. My phase allows for multiple
   # installations of the same version for different purposes
   my $files = [ 'os_'.$Config{osname}, 'phase'.$self->phase,
                 'default',             'default_'.$s->{lang} ];

   # Add a controller specific file to the list
   if ($namespace = $c->action->namespace) {
      push @{ $files }, $namespace, $namespace.q(_).$s->{lang};
   }

   my $config = eval { $c->model( q(Config) )->load_files( @{ $files } ) };

   if ($e = $self->catch) { $self->error_page( $c, $e->as_string ) }
   else {
      # Copy the config to the stash
      while (my ($key, $value) = each %{ $config }) {
         $s->{ $key } = $value;
      }

      $self->messages( $s->{messages} || {} );

      # Raise the "level" of the globals in the stash
      my $globals = delete $s->{globals};

      while (my ($key, $value) = each %{ $globals }) {
         $s->{ $key } = $value->{value};
      }
   }

   # Recover the user identity from the session store
   $self->load_stash_from_user( $c );

   # Recover attributes from cookies set by javascript in the browser
   $self->load_stash_with_browser_state( $c );

   return;
}

sub load_stash_with_browser_state {
   # Extract key/value pairs from the browser state cookie
   my ($self, $c) = @_; my $cfg = $c->config; my $s = $c->stash;

   $s->{cookiep}  = $self->app_prefix( $cfg->{name} );
   $s->{cname  }  = $s->{cookiep}.q(_state);

   # Set some defaults
   $s->{debug  }  = $c->debug;
   $s->{fstate }  = 1;
   $s->{pwidth }  = $s->{pwidth} || 40;
   $s->{sbstate}  = 0;
   $s->{skin   }  = $cfg->{default_skin};
   $s->{width  }  = 1024;

   # Call the plugin parent class method if it's loaded
   $self->maybe::next::method( $c );
   return;
}

sub preferred_content_type {
   my ($self, $cfg, $req) = @_; my $type;

   # Set the content type from the request header
   if ($cfg->{negotiate_content_type}) {
      $type = $self->accepted_content_types( $req )->[ 0 ];
   }

   # Default the content type if it's not already set
   $type = $cfg->{content_type} if (!$type || $type eq q(*/*));

   return $type;
}

sub redirect_to_page {
   # Redirects to a private action path via a config attribute
   my ($self, $c, $page, $error) = @_;

   my $path = $c->config->{ $page };

   $error ||= q(eNo).(join $NUL, map    { ucfirst $_ }
                                 split m{ _ }mx, $page).q(Page);

   return $self->error_page( $c, $error ) unless ($path);

   my $namespace = $c->action->namespace;
   my $name      = $c->action->name || q(unknown);

   $self->redirect_to_path( $c, $path, $namespace, $name );
   return;
}

sub redirect_to_path {
   # Does a response redirect and detach
   my ($self, $c, $path, @rest) = @_; my $s = $c->stash;

   $path ||= $c->config->{default_action}; delete $s->{token};
   $c->res->redirect( $self->uri_for( $c, $path, $s->{lang}, @rest ) );
   $c->detach(); # Never returns
   return;
}

sub set_key {
   my ($self, $c, @rest) = @_;

   return CatalystX::Usul::PersistentState->set_key( $c, @rest );
}

sub user_agent_ok {
   my ($self, $c) = @_; my $cfg = $c->config; my $s = $c->stash;

   my $ua = $c->req->headers->{ q(user-agent) } || $NUL;

   if (($cfg->{misery_page} or $cfg->{misery_skin}) and $ua =~ m{ msie }imsx) {
      unless ($cfg->{misery_skin}) {
         $c->res->redirect( $cfg->{misery_page} );
         $c->detach(); # Never returns
         return 0;
      }

      $s->{skin  } = $cfg->{misery_skin};
      $s->{assets} = $c->uri_for( $SEP.$cfg->{skins}.$SEP.$s->{skin} ).$SEP;
   }

   return 1;
}

# Private methods

sub _parse_HasActions_attr { ## no critic
   # Adding the HasActions attribute to a controller action causes our apps
   # action class handler to be called for each request
   my ($self, $c, $name, $value) = @_;

   return ( q(ActionClass), $c->config->{action_class} );
}

sub _setup_plugins {
   # Load the controller plugins
   my ($self, $app) = @_;

   unless (__PACKAGE__->get_inherited( q(_c_plugins) )) {
      my $config  = { search_paths => [ qw(::Plugin::Controller ::Plugin::C) ],
                      %{ $app->config->{ setup_plugins } || {} } };
      my $plugins = __PACKAGE__->setup_plugins( $config );

      # So we'll do this only once
      __PACKAGE__->set_inherited( q(_c_plugins), $plugins );
   }

   return;
}

# Private subroutines

sub __is_language {
   # Is this one if the languages the application supports
   my ($candidate, $languages) = @_;

   return (first { $_ eq $candidate } @{ $languages }) ? 1 : 0;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller - Application independent common controller methods

=head1 Version

0.1.$Revision: 402 $

=head1 Synopsis

   package CatalystX::Usul;
   use parent qw(Catalyst::Component CatalystX::Usul::Base);

   package CatalystX::Usul::Controller;
   use parent qw(CatalystX::Usul Catalyst::Controller);

   package YourApp::Controller::YourController;
   use parent qw(CatalystX::Usul::Controller);

=head1 Description

Provides methods common to all controllers. Implements the "big three"
L<Catalyst> API methods; B<begin>, B<auto> and B<end>

=head1 Subroutines/Methods

Private methods begin with an _ (underscore). Private subroutines begin
with __ (two underscores)

=head2 new

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

=head2 accepted_content_types

   $types = $self->accepted_content_types( $c->req );

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

=head2 auto

Control access to actions based on user roles and ACLs

This method will return true to allow the dispatcher to
forward to the requested action, or this method will redirect to
either the profile defined authentication action or one of the
predefined default actions

These actions are permanently on public access; about, access_denied,
captcha, room_closed, help, and view_source. Anonymous access is
granted to actions that have the I<Public> attribute set

Each action has a I<state> attribute which is stored in the action's
configuration file. Setting the actions I<state> attribute to a
value greater than 1 has the effect of closing the action to
access. Instead the request is redirected to the I<room_closed> action
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

If no ACL for a room can be determined the the request is redirected
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
the array returned by L</accepted_content_types>. The content type is
used to lookup the current view in the I<content_map>

Once the view has been selected it's deserialization method is called
as required

The requested language is obtained by calling L</get_language>

Once the language is known the stash is further populated by calling
L</load_stash_per_request>

=head2 deserialize

   $data = $self->deserialize( $c );

Calls C<deserialize> on the current view if the request is one of; options,
post, or put

=head2 end

Maybe calls the end method in one of the controller plugins if it
exists. Forwards to the C<render> method which has the action class
attribute set to 'RenderView'

=head2 error_page

   $self->error_page( $c, $error_message_key, @args );

Generic error page which displays the specified message. The error message is
localized by calling the L<loc|CatalystX::Usul/localize> method in the base
class

=head2 get_key

   my $value = $self->get_key( $c, $key_name );

Returns a value for a given key from stash which was populated by
L<load_keys|CatalystX::Usul::PersistentState/load_keys>

=head2 get_language

   $language = $self->get_language( $c->config, $c->req );

In order of precedence uses; the first capture argument, the
I<accept-language> headers from the request, the configuration default
and finally the hard coded default which is B<en> (English)

=head2 load_keys

   $self->load_keys( $c );

Recovers the key(s) for the current controller by calling
L<load_keys|CatalystX::Usul::PersistentState/load_keys>

=head2 load_stash_from_user

   $self->load_stash_from_user( $c );

Using this system sessions do not expire for three months. Instead the
user key is expired after a period of inactivity. This method recovers
information about the user and stores it on the stash. Everywhere else
the stashed information is used as required

=head2 load_stash_per_request

   $self->load_stash_per_request( $c );

Uses the config model to load the config data for the current
request. The data is split across six files; one for OS dependant
data, one for this phase (live, test, development etc.), default data
and language dependant default data, data for the current controller
and it's language dependant data. This information is cached by the
config model

Data in the I<globals> attribute is raised to the top level of the
stash and the I<globals> attribute deleted

=head2 load_stash_with_browser_state

   $self->load_stash_with_browser_state( $c );

Recover information stored in the browser state cookie. Uses the
L<CatalystX::Usul::Plugin::Controller::Cookies> module if it's loaded

=head2 preferred_content_type

   $content_type = $self->preferred_content_type( $c->config, $c->req );

Returns the first accepted content type if the I<negotiate_content_type>
config attribute is true. Defaults to the config attribute I<content_type>

=head2 redirect_to_page

   $self->redirect_to_page( $c, $page_name );

Takes a simple page name works out it's private path and then calls
L</redirect_to_path>

=head2 redirect_to_path

   $self->redirect_to_path( $c, $action_path, @args );

Sets redirect on the response object and then detaches. Defaults
to the I<default_action> config attribute if the action path is null

=head2 set_key

   $self->set_key( $c, $key_name, $value );

Sets a key/value pair in the in L<CatalystX::Usul::PersistentState>

=head2 user_agent_ok

   $bool = $self->user_agent_ok( $c );

Detects use of the misery browser. Sets the skin to
C<< $c->config->{misery_skin} >> if its defined. Otherwise redirects to
C<< $c->config->{misery_page} >> if that is defined. Otherwise serves
up a W3C validated page for Exploiter to render as garbage

=head2 _parse_HasActions_attr

Associates the B<HasActions> method attribute with the action class defined
in the I<action_class> configuration attribute

=head2 _setup_plugins

   $class->_setup_plugins( $app );

Load and instantiate any installed controller plugins. Called from the
constructor

=head2 __is_language

   $bool = __is_language( $candidate, \@languages );

Tests to see if the given language is supported by the current configuration

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Catalyst::Controller>

=item L<CatalystX::Usul>

=item L<CatalystX::Usul::ModelHelper>

=item L<CatalystX::Usul::PersistentState>

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
