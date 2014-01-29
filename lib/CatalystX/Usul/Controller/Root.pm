# @(#)Ident: Root.pm 2013-10-19 17:49 pjf ;

package CatalystX::Usul::Controller::Root;

use strict;
use version; our $VERSION = qv( sprintf '0.17.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw( env_prefix is_member throw );
use CatalystX::Usul::Moose;

BEGIN { extends q(CatalystX::Usul::Controller) }

with q(CatalystX::Usul::TraitFor::Controller::ModelHelper);
with q(CatalystX::Usul::TraitFor::Controller::PersistentState);
with q(CatalystX::Usul::TraitFor::Controller::TokenValidation);

has 'default_namespace' => is => 'ro', isa => SimpleStr, required => TRUE;

has 'imager_class'      => is => 'ro', isa => NonEmptySimpleStr,
   default              => q(Imager);


has '_profiler_no_start'  => is => 'lazy', isa => Bool, default => sub {
   ($ENV{NYTPROF} || NUL) =~ m{ start\=no }mx ? TRUE : FALSE },
   init_arg               => undef;

has '_trigger_profiler'   => is => 'lazy', isa => Bool,
   default                => sub {
      $_[ 0 ]->_profiler_no_start and DB::enable_profile(); TRUE },
   init_arg               => undef, reader => 'trigger_profiler';

sub auto : Private {
   return shift->next::method( @_ );
}

sub begin : Private {
   return shift->next::method( @_ );
}

sub end : Private {
   return shift->next::method( @_ );
}

sub render : ActionClass(RenderView) {
   $_[ 0 ]->trigger_profiler; return;
}

sub about : Chained(/) Args(0) NoToken Public {
   # Display license and authorship information
   return $_[ 0 ]->set_popup( $_[ 1 ], q(close) )->form;
}

sub access_denied : Chained(/) Args Public {
   # The auto method has decided not to allow access to the requested room
   my ($self, $c, $ns, $name) = @_; my $s = $c->stash;

   unless ($s->{denied_namespace} = $ns and $s->{denied_action} = $name) {
      my $msg  = 'Access was denied to an unspecified action. ';
         $msg .= 'Namespace and/or action name not specified';

      return $self->error_page( $c, $msg );
   }

   $self->reset_nav_menu( $c, q(back) ); $c->action->name( q(cracker) );

   my $msg = 'Access denied to [_1] for [_2]'; my $action = $ns.SEP.$name;

   $self->log->warn( $self->loc( $s, $msg, $action, $s->{user}->username ) );
   $c->res->status( 403 );
   return FALSE;
}

sub action_closed : Chained(/) Args Public {
   # Requested page exists but is temporarily unavailable
   my ($self, $c, $ns, $name) = @_; my $s = $c->stash;

   unless ($s->{closed_namespace} = $ns and $s->{closed_action} = $name) {
      my $msg  = 'Unspecified action is closed. ';
         $msg .= 'Namespace and/or action name not specified';

      return $self->error_page( $c, $msg );
   }

   $self->reset_nav_menu( $c, q(back) );

   my $msg = $self->loc( $s, 'Action [_1]/[_2] closed', $ns, $name );

   $self->log->warn_message( $s, $msg ); $c->res->status( 423 );
   return;
}

sub app_closed : Chained(/) Args HasActions {
   # Application has been closed by the administrators
   my ($self, $c, @args) = @_;

   return $self->reset_nav_menu( $c, q(blank) )->form( @args );
}

sub app_reopen : ActionFor(app_closed.login) {
   # Open the application to users
   my ($self, $c) = @_; my $s = $c->stash; my $cfg = $c->config;

   $self->stash_identity_model( $c ); $s->{user_model}->authenticate;

   $self->set_uri_query_params( $c, { realm => $s->{realm} } );

   if (is_member $cfg->{admin_role}, $c->user->roles) {
      $c->model( $self->global_class )->save;
      $self->redirect_to_path( $c, $s->{wanted} );
   }

   return TRUE;
}

sub base : Chained(/) PathPart('') CaptureArgs(0) {
   my ($self, $c) = @_;

   $self->init_uri_attrs( $c, $self->config_class );
   $c->stash->{nav_model}->load_status_msgs;
   return;
}

sub captcha : Chained(/) Args(0) NoToken Public {
   # Dynamically generate a jpeg image displaying a random number
   return $_[ 1 ]->model( $_[ 0 ]->realm_class )->create_captcha;
}

sub company : Chained(/) Args(0) NoToken Public {
   # And now a short message from our sponsor
   return $_[ 0 ]->set_popup( $_[ 1 ], q(close) )->form;
}

sub feedback : Chained(base) Args HasActions {
   # Form to send an email to the site administrators
   my ($self, $c, @args) = @_;

   return $self->set_popup( $c, q(close) )->form( @args );
}

sub feedback_send : ActionFor(feedback.send) {
   # Send an email to the site administrators
   return $_[ 1 ]->model( $_[ 0 ]->help_class )->feedback_send;
}

sub help : Chained(/) Args Public {
   # Generate the context sensitive help from the POD in the code
   my ($self, $c, @args) = @_;

   return $self->set_popup( $c, q(close) )->form( @args );
}

sub imager : Chained(/) Args NoToken Public {
   my ($self, $c, @args) = @_; my $model = $c->model( $self->imager_class );

   my ($image, $type, $mtime)
      = $model->transform( [ @args ], $c->req->query_parameters );

   $image or return $self->error_page( $c, 'No image data generated' );

   $c->res->body( $image );
   $c->res->content_type( $type );
   $mtime and $c->res->headers->last_modified( $mtime );
   # TODO: Work out what to do with expires header
   # $c->res->headers->expires( time() );
   return;
}

sub logout : Chained(/) Args(0) Public {
   my ($self, $c) = @_; my $s = $c->stash; my $ns = $self->default_namespace;

   $c->model( $self->realm_class )->logout( { user => $s->{user} } );

   return $self->redirect_to_path( $c, $ns, @{ $s->{redirect_params} } );
}

sub quit : Chained(/) Args(0) Public {
   my ($self, $c) = @_; my $s = $c->stash; my $cfg = $c->config;

   $ENV{ (env_prefix $cfg->{name}).q(_QUIT_OK) } and exit 0;

   $self->log->warn( $self->loc( $s, 'User [_1 ] attempted to quit',
                                 $s->{user}->username ) );

   return $self->redirect_to_path( $c, $self->default_namespace );
}

sub redirect_to_default : Chained(/) PathPart('') Args {
   return $_[ 0 ]->redirect_to_path( $_[ 1 ], $_[ 0 ]->default_namespace );
}

sub select_language : Chained(/) Args(0) Public {
   my ($self, $c) = @_; my $params = $c->req->params;

   $c->session( language => $params->{select_language} );

   return $self->redirect_to_path( $c, $params->{referer} );
}

sub version {
   return $VERSION;
}

sub view_source : Chained(/) Args Public {
   # Display the source code with syntax highlighting
   my ($self, $c, $module) = @_;

   $module or return $self->error_page( $c, 'Module not specified' );

   $self->reset_nav_menu( $c, q(close) );

   return $c->model( $self->fs_class )->view_file( q(source), $module );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Root - Root Controller for the application

=head1 Version

Describes v0.17.$Rev: 1 $

=head1 Synopsis

   package YourApp::Controller::Root;

   use CatalystX::Usul::Moose;

   BEGIN { extends q(CatalystX::Usul::Controller::Root) }

=head1 Description

Exposes some generic endpoints implemented in the base class

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item C<default_namespace>

A simple string which is required. The default namespace

=item C<imager_class>

A non empty simple string which defaults to C<Imager>

=back

=head1 Subroutines/Methods

=head2 about

Display a simple popup window containing the copyright and license information

=head2 access_denied

The auto method redirects unauthorised users to this endpoint

=head2 action_closed

The requested endpoint exists but has been deactivated by the
administrators

=head2 app_closed

Display an information screen explaining that the application has been
closed by the administrators. An administrator must authenticate to
reopen the application

=head2 app_reopen

Action to reopen the application. Does this by setting the global
configuration attribute to false

=head2 auto

Calls method of same name in parent class

=head2 base

Initializes the persistent URI attributes and loads the status messages

=head2 begin

Calls method of same name in parent class to stuff the stash with data
used by all pages

=head2 captcha

Dynamically generates a JPEG image used on the self registration
screen to defeat bots.

=head2 company

Some text about the company whose application this is.

=head2 end

Attempt to render a view

=head2 feedback

Display a popup window that lets the user send an email to the site
administrators

=head2 feedback_send

This private method is the action for the feedback controller

=head2 help

Generates a context sensitive help page by calling
L<help_form|CatalystX::Usul::Model::Help>

=head2 imager

Generates transformations of any image under the document root. Calls
L<transform|CatalystX::Usul::Model::Iamger/transform> and sets the
response object directly

=head2 logout

Expires the user object in the session store

=head2 quit

Called when collecting profile data using L<Devel::NYTProf> to stop
the server. The environment variable I<MYAPP_QUIT_OK> must be set to
true for this to work, so don't do that on a production server

=head2 redirect_to_default

Redirects to default controller. Matches any uri not matched by another action

=head2 render

Call the C<RenderView> action class

=head2 select_language

Handles the post request to select the language used. Stores the requested
language in the session and the redirects back to the original uri

=head2 version

Return the version number of this controller

=head2 view_source

View the source code for the current controller. Calls the
C<view_file> method in the L<CatalystX::Usul::Model::FileSystem> model
to display some source code with syntax highlighting

=head1 Diagnostics

Debug can be turned on/off from the tools menu

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Controller>

=item L<CatalystX::Usul::TraitFor::Controller::ModelHelper>

=item L<CatalystX::Usul::TraitFor::Controller::PersistentState>

=item L<CatalystX::Usul::Moose>

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

Copyright (c) 2014 Peter Flanigan. All rights reserved

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
