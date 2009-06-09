# @(#)$Id: Usul.pm 571 2009-06-09 19:41:36Z pjf $

package CatalystX::Usul;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 571 $ =~ /\d+/gmx );
use parent qw(Catalyst::Component CatalystX::Usul::Base);

use Class::C3;
use Class::Null;
use File::Spec;
use IPC::SRLock;
use Module::Pluggable::Object;
use Text::Markdown qw(markdown);

__PACKAGE__->mk_accessors( qw(debug encoding lock log prefix
                              redirect_to secret suid tabstop tempdir) );

my $LSB = q([);
my $NUL = q();
my $SEP = q(/);
my $SPC = q( );

sub new {
   my ($self, $app, @rest) = @_; $app ||= Class::Null->new;

   my $app_conf = $app->config || {};
   my $new      = $self->next::method( $app, @rest );
   my $prefix   = (split m{ _ }mx, ($app_conf->{suid} || $NUL))[0];

   $new->debug      ( $app->debug              || 0                      );
   $new->encoding   ( $app_conf->{encoding}    || q(UTF-8)               );
   $new->log        ( $app->log                || Class::Null->new       );
   $new->prefix     ( $app_conf->{prefix}      || $prefix                );
   $new->redirect_to( $app_conf->{redirect_to} || q(redirect_to_default) );
   $new->secret     ( $app_conf->{secret}      || $new->prefix           );
   $new->suid       ( $app_conf->{suid}        || $NUL                   );
   $new->tabstop    ( $app_conf->{tabstop}     || 3                      );
   $new->tempdir    ( $app_conf->{tempdir}     || File::Spec->tmpdir     );
   $new->lock       ( $new->_lock_obj( $app_conf->{lock} )               );

   return $new;
}

sub build_subcomponents {
   # Voodo by mst. Finds and loads component subclasses
   my ($self, $base_class) = @_; my $my_class = ref $self || $self; my $dir;

   ($dir = $self->find_source( $base_class )) =~ s{ \.pm \z }{}mx;

   for my $path (glob $self->catfile( $dir, q(*.pm) )) {
      my $subcomponent = $self->basename( $path, q(.pm) );
      my $component    = join q(::), $my_class,   $subcomponent;
      my $base         = join q(::), $base_class, $subcomponent;

      $self->load_component( $component, $base );
   }

   return;
}

sub get_action {
   my ($self, $c, $path) = @_; my $action;

   # Normalise the path. It must contain a SEP char
   $path ||= $SEP;
   $path  .= $SEP if ((index $path, $SEP) < 0);

   # Extract the action attributes
   my ($namespace, $name) = split $SEP, $path;

   # Default the namespace and expand the root symbol
   $namespace ||= ($c->action && $c->action->namespace) || $SEP;
   $namespace   = $SEP if ($namespace eq q(root));

   # Default the name if one was not provided
   $name ||= $self->redirect_to;

   # Return the action for this namespace/name pair
   return $action if ($action = $c->get_action( $name, $namespace ));

   my $error = 'No action for [_1]/[_2]';

   $self->log_warn( $self->loc( $c, $error, $namespace, $name ) );
   return;
}

*loc = \&localize;

sub localize {
   my ($self, $c, $key, @rest) = @_; my $s = $c->stash; my @args = ();

   return unless $key;

   $key = q().$key; # Force stringification. I hate Return::Value

   # Lookup the message using the supplied key
   my $messages = $s->{messages} || {};
   my $message  = $messages->{ $key };
   my $text;

   if ($message and $text = $message->{text}) {
      # Optionally call markdown if required
      if ($message->{markdown}) {
         # TODO: Cache copies of this on demand
         my $content_type = $s->{content_type} || q(text/html);
         my $suffix       = $content_type eq q(text/html) ? q(>) : q( />);

         $text = markdown( $text, { empty_element_suffix => $suffix,
                                    tab_width            => $self->tabstop } );
      }
   }
   else { $text = $key } # Default the message text to the key

   if ($rest[ 0 ]) {
      @args = ref $rest[ 0 ] eq q(ARRAY) ? @{ $rest[ 0 ] } : @rest;
   }

   # Expand positional parameters of the form [_<n>]
   if ((index $text, $LSB) >= 0) {
      push @args, map { $NUL } 0 .. 10;
      $text =~ s{ \[ _ (\d+) \] }{$args[ $1 - 1 ]}gmx;
   }

   return $text;
}

sub setup_plugins {
   # Searches for and then load plugins in the search path
   my ($class, $config) = @_;

   my $exclude = delete $config->{ exclude_pattern } || q(\A \z);
   my @paths   = @{ delete $config->{ search_paths } || [] };
   my $finder  = Module::Pluggable::Object->new
      ( search_path => [ map { m{ \A :: }mx ? __PACKAGE__.$_ : $_ } @paths ],
        %{ $config } );
   my @plugins = grep { !m{ $exclude }mx }
                 sort { length $a <=> length $b } $finder->plugins;

   $class->load_component( $class, @plugins );

   return \@plugins;
}

sub uri_for {
   # Code lifted from contextual_uri_for_action
   my ($self, $c, $action_path, @rest) = @_;
   my ($action, @captures, $chained_action, $error, $uri);

   # Get the action for the given action path
   return unless ($action = $self->get_action( $c, $action_path ));

   my $attrs = $action->attributes;

   if (not $attrs->{Chained} or $attrs->{CaptureArgs}) {
      $error = 'Not a chained endpoint [_1]';
      $self->log_warn( $self->loc( $c, $error, $action->reverse ) );
      return;
   }

   my $chained_path = $attrs->{Chained}->[ 0 ]; my @chain = ();

   # Pull out all actions for the chain
   while ($chained_path ne $SEP) {
      $chained_action = $self->_get_chained_action( $c, $chained_path );
      unshift @chain, $chained_action;
      $chained_path = $chained_action->attributes->{Chained}->[ 0 ];
   }

   my $params = scalar @rest && ref $rest[ -1 ] eq q(HASH) ? pop @rest : $NUL;
   my @args   = @rest;

   # Now start from the root of the chain, populate captures
   for my $num_caps (map { $_->attributes->{CaptureArgs}->[ 0 ] } @chain) {
      if ($num_caps > scalar @args) {
         $error = 'Insufficient args for [_1]';
         $self->log_warn( $self->loc( $c, $error, $action->reverse ) );
         return;
      }

      push @captures, splice @args, 0, $num_caps;
   }

   my $first_arg = $captures[ 0 ] || $args[ 0 ] || $NUL;

   push @args, $params if ($params);

   unless ($uri = $c->uri_for( $action, \@captures, @args )) {
      $self->log_warn( $self->loc( $c, 'No uri for [_1]', $action->reverse ) );
      return;
   }

   return $uri unless ($uri =~ m{ $SEP $SEP $first_arg \z }mx);

   # Fix up result in this edge case
   $uri =~ s{ $SEP $SEP $first_arg \z }{$SEP$first_arg}mx;
   return bless \$uri, ref $c->req->base;
}

# Private methods

sub _get_chained_action {
   # Returns the action for a given chained midpoint
   my ($self, $c, $path) = @_; my $chained_action;

   if ($Catalyst::VERSION < 5.8) {
      for my $d_type (@{ $c->dispatcher->dispatch_types }) {
         last if ($chained_action = $d_type->{actions}->{ $path });
      }
   }
   else {
      my $d_type = $c->dispatcher->dispatch_type( q(Chained) );

      $chained_action = $d_type->{actions}->{ $path } if ($d_type);
   }

   return $chained_action if ($chained_action);

   my $error = 'Unable to find action in chain [_1]';

   $self->throw( $self->loc( $c, $error, $path ) );
   return;
}

sub _lock_obj {
   my ($self, $args) = @_; my $lock;

   # There is only one lock object
   return $lock if ($lock = __PACKAGE__->get_inherited( q(lock) ));

   $args            ||= {};
   $args->{debug  } ||= $self->debug;
   $args->{log    } ||= $self->log;
   $args->{tempdir} ||= $self->tempdir;

   return __PACKAGE__->set_inherited( q(lock), IPC::SRLock->new( $args ) );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul - A base class for Catalyst MVC components

=head1 Version

0.1.$Revision: 571 $

=head1 Synopsis

   use base qw(CatalystX::Usul);

=head1 Description

These modules provide a set of base classes for a Catalyst web
application. Features include:

=over 3

=item Targeted at intranet applications

The identity model supports multiple backend authentication stores
including the underlying operating system accounts

=item Thin controllers

Most controllers make a single call to the model and so comprise of
only a few lines of code. The model stashes data used by the view to
render the page

=item No further view programing required

A single L<Template::Toolkit> template is used to render all pages as
either HTML or XHTML. The template forms one component of the "skin",
the other components are: a Javascript file containing the use cases
for the Javascript libraries, a primary CSS file with support for
alternative CSS files, and a set of image files

Designers can create new skins with different layout, presentation and
behaviour for the whole application. They can do this for the example
application, L<App::Munchies>, whilst the programmers write the "real"
application in parallel with the designers work

=item Agile development methodology

These base classes are used by an example application,
L<App::Munchies>, which can be deployed to staging and production
servers at the beginning of the project. Setting up the example
application allows issues regarding the software technology to be
resolved whilst the "real" application is being written. The example
application can be deleted leaving these base classes for the "real"
application to use

=back

=head1 Configuration and Environment

Catalyst will set the C<$config> argument passed to the constructor to
the section of the configuration appropriate for the component being
initialised

=head1 Subroutines/Methods

This module provides methods common to C<CatalystX::Usul::Controller>
and C<CatalystX::Usul::Model> which both inherit from this class. This
means that you should probably inherit from one of them instead

=head2 new

   $self = CatalystX::Usul->new( $app, $config );

This class inherits from L<Catalyst::Component> and
L<CatalystX::Usul::Base>. The Catalyst application context is C<$app>
and C<$config> is a hash ref whose contents are copied to the created
object. Defines the following attributes:

=over 3

=item debug

The application context debug is used to set this. Defaults to false

=item encoding

The config supplies the encoding for the C<query_array>,
C<query_value> and log methods. Defaults to I<UTF-8>

=item lock

An L<IPC::SRLock> object which is used to single thread the application
where required. This is a singleton object

=item log

The application context log. Defaults to a L<Class::Null> object

=item prefix

The prefix applied to executable programs in the I<bin>
directory. This is extracted from the I<suid> key in the config hash

=item secret

This applications secret key as set by the administrators in the
configuration. It is used to perturb the encryption methods. Defaults to
the I<prefix> attribute value

=item suid

Supplied by the config hash, it is the name of the setuid root
program in the I<bin> directory. Defaults to the null string

=item tabstop

Supplied by the config hash, it is the number of spaces to expand the tab
character to in the call to L<markdown|Text::Markdown/markdown> made by
L</localize>. Defaults to 3

=item tempdir

Supplied by the config hash, it is the location of any temporary files
created by the application. Defaults to the L<File::Spec> tempdir

=back

=head2 build_subcomponents

   __PACKAGE__->build_subcomponents( $base_class );

Class method that allows us to define components that inherit from the base
class at runtime

=head2 get_action

   $action = $self->get_action( $c, $action_path );

Provide defaults for the L<get_action|Catalyst/get_action>
method. Return the action object if one exists, otherwise log a warning
and return undef

=head2 loc

=head2 localize

   $local_text = $self->localize( $c, $message, @args );

Localizes the message. Optionally calls C<Text::Markdown> on the text

=head2 setup_plugins

   @plugins = $self->setup_plugins( $class, $config_ref );

Load the given list of plugins and have the supplies class inherit from them.
Returns an array ref of available plugins

=head2 uri_for

   $uri = $self->uri_for( $c, $action_path, @args );

Turns the action path into an action object by calling L</get_action>.
Calculates the number of capture args by introspecting the dispatcher
splits them of from passed args and then calls
L<uri_for|Catalyst/uri_for>

=head2 _get_chained_action

   $action = $self->_get_chained_action( $c, $action_path );

Returns the action object for the given chained midpoint action path. Called
by L</uri_for>. Irons out the differences between Catalyst versions

=head2 _lock_obj

   $self->_lock_obj( $args );

Provides defaults for and returns a new L<IPC::SRLock> object. The keys of
the C<$args> hash are:

=over 3

=item debug

Debug status. Defaults to C<< $usul_obj->debug >>

=item log

Logging object. Defaults to C<< $usul_obj->log >>

=item tempdir

Directory used to store the lock file and lock table if the C<fcntl> backend
is used. Defaults to C<< $usul_obj->tempdir >>

=back

=head1 Diagnostics

Setting the I<debug> attribute to true causes messages to be logged at the
debug level

=head1 Dependencies

=over 3

=item L<Catalyst::Component>

=item L<CatalystX::Usul::Base>

=item L<Class::Null>

=item L<IPC::SRLock>

=item L<Module::Pluggable::Object>

=item L<Text::Markdown>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Author

Peter Flanigan, C<< <Support at RoxSoft.co.uk> >>

=head1 Acknowledgements

Larry Wall - For the Perl programming language

=head1 License and Copyright

Copyright (c) 2009 Peter Flanigan. All rights reserved

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
