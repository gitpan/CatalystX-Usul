# @(#)$Id: Root.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::Controller::Root;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Controller);

use Class::C3;

my $SEP = q(/);

sub about : Chained(lang) Args(0) Public {
   # Display license and authorship information
   my ($self, $c) = @_;

   my $model = $c->model( q(Base) );

   $model->add_header;
   $model->simple_page( q(about) );
   $self->set_popup( $c );
   return;
}

sub access_denied : Chained(lang) Args Public {
   # The auto method has decided not to allow access to the requested room
   my ($self, $c, $ns, $name) = @_; my $s = $c->stash; my $msg;

   unless ($s->{denied_level} = $ns and $s->{denied_room} = $name) {
      $msg = 'No action namespace and/or name specified';

      return $self->error_page( $c, $msg );
   }

   my $model = $c->model( q(Navigation) );

   $model->add_header;
   $model->clear_controls;
   $model->add_menu_back;
   $model->simple_page( q(cracker) );
   $msg = 'Access denied to [_1] for [_2]';
   $self->log_warn( $self->loc( $c, $msg, $ns.$SEP.$name, $s->{user} ) );
   $c->res->status( 403 );
   return 0;
}

sub app_closed : Chained(lang) Args HasActions {
   # Application has been closed by the administrators
   my ($self, $c) = @_;
   my $s          = $c->stash;
   my $form       = $s->{form}->{name};
   my $model      = $c->model( q(Navigation) );

   $model->add_header;
   $model->clear_controls;
   $model->add_menu_blank;
   $model->simple_page( $form );
   $model->add_field  ( { id => $form.q(.user)   } );
   $model->add_field  ( { id => $form.q(.passwd) } );
   $model->add_hidden ( $form, 0 );
   $model->add_buttons( q(Login) );

   $s->{token} = $c->config->{token};
   return 0;
}

sub app_reopen : ActionFor(app_closed.login) {
   # Open the application to users
   my ($self, $c) = @_; my $cfg = $c->config;

   unless ($c->forward( $SEP.$cfg->{authenticate}.q(_login), [ 1 ] )) {
      return 0;
   }

   if ($self->is_member( $cfg->{admin_role}, @{ $c->user->roles } )) {
      $c->model( q(Config::Globals) )->save;
   }

   $self->redirect_to_path( $c, $cfg->{default_action} );
   return 1;
}

sub auto : Private {
   return shift->next::method( @_ );
}

sub begin : Private {
   return shift->next::method( @_ );
}

sub captcha : Chained(lang) Args(0) Public {
   # Dynamically generate a jpeg image displaying a random number
   my ($self, $c) = @_; delete $c->stash->{token}; return $c->create_captcha();
}

sub company : Chained(lang) Args(0) Public {
   # And now a short message from our sponsor
   my ($self, $c) = @_;

   my $model = $c->model( q(Base) );

   $model->add_header;
   $model->simple_page( q(company) );
   $self->set_popup( $c );
   return;
}

sub end : Private {
   return shift->next::method( @_ );
}

sub feedback : Chained(lang) Args HasActions {
   # Form to send an email to the site administrators
   my ($self, $c, @rest) = @_;

   $c->model( q(Help) )->form( @rest );
   $self->set_popup( $c );
   return;
}

sub feedback_send : ActionFor(feedback.send) {
   # Send an email to the site administrators
   my ($self, $c) = @_; $c->model( q(Help) )->feedback_send; return 1;
}

sub help : Chained(lang) Args Public {
   return shift->next::method( @_ );
}

sub imager : Chained(lang) Args Public {
   my ($self, $c, @args) = @_; my $e;

   my $model = $c->model( q(Imager) ); delete $c->stash->{token};

   my ($data, $type, $mtime) = eval {
      $model->transform( [ @args ], $c->req->query_parameters );
   };

   if ($e = $self->catch) {
      return $self->error_page( $c, $e->as_string, @{ $e->args } );
   }

   return $self->error_page( $c, 'No body data specified' ) unless ($data);

   $c->res->body( $data );
   $c->res->content_type( $type );
   $c->res->headers->last_modified( $mtime ) if ($mtime);
# TODO: Work out what to do with expires header
#    $c->res->headers->expires( time() );
   return;
}

sub lang : Chained(/) PathPart('') CaptureArgs(1) {
   # Capture the language selection from the requested url
}

sub lock_display : Chained(lang) Args(0) {
   # TODO: Move this to a plugin
   my ($self, $c) = @_; my $model = $c->model( q(Base) );

   $model->lock_display( $model->query_value( q(display) ) );
   $c->res->status( 204 );
   $c->detach;
   return;
}

sub quit : Chained(/) Args(0) Public {
   my ($self, $c) = @_; my $s = $c->stash;

   exit 0 if ($ENV{ $self->env_prefix( $c->config->{name} ).q(_QUIT_OK) });

   $self->log_warn( $self->loc( $c, 'Quit attempted by [_1]', $s->{user} ) );

   return $self->redirect_to_path( $c );
}

sub redirect_to_default : Chained(/) PathPart('') Args {
   my ($self, $c) = @_; return $self->redirect_to_path( $c );
}

sub render : ActionClass(RenderView) {
}

sub room_closed : Chained(lang) Args Public {
   # Requested page exists but is temporarily unavailable
   my ($self, $c, $ns, $name) = @_; my $s = $c->stash; my $e;

   unless ($s->{closed_level} = $ns and $s->{closed_room} = $name) {
      my $msg = 'No action namespace and/or name specified';

      return $self->error_page( $c, $msg );
   }

   my $model = $c->model( q(Navigation) );

   $model->add_header;
   $model->clear_controls;
   $model->add_menu_back;
   $model->simple_page( q(closed) );
   $self->log_warn( $self->loc( $c, 'Action [_1]/[_2] closed', $ns, $name ) );
   return;
}

sub version {
   return $VERSION;
}

sub view_source : Chained(lang) Args Public {
   # Display the source code with syntax highlighting
   my ($self, $c, $module) = @_; my $e;

   return $self->error_page( $c, 'No module specified' ) unless ($module);

   eval {
      my $model = $c->model( q(Navigation) );

      $self->common( $c );
      $model->clear_controls;
      $model->add_menu_back;
      $c->model( q(FileSystem) )->view_file( q(source), $module );
   };

   $self->error_page( $c, $e->as_string ) if ($e = $self->catch);

   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Root - Root Controller for the application

=head1 Version

0.1$Revision: 562 $

=head1 Synopsis

   package MyApp::Controller::Root;

   use base qw(CatalystX::Usul::Controller::Root);

=head1 Description

Exposes some generic endpoints implemented in the base class

=head1 Subroutines/Methods

=head2 about

Display a simple popop window containing the copyright and license information

=head2 access_denied

The auto method redirects unauthorised users to this endpoint

=head2 app_closed

Display an information screen explaining that the application has been
closed by the administrators. An administrator must authenticate to
reopen the application

=head2 app_reopen

Action to reopen the application. Does this by setting the global
configuration attribute to false

=head2 auto

Calls method of same name in parent class

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

Calls method of same name in parent class

=head2 imager

Generates transformations of any image under the document root. Calls
L<transform|CatalystX::Usul::Model::Iamger/transform> and sets the
response object directly

=head2 lang

Capture the required language. The actual work is done in the
L</begin> method

=head2 lock_display

Locks the display. Silly but I couldn't resist

=head2 quit

Called when collecting profile data using L<Devel::NYTProf> to stop
the server. The environment variable I<MYAPP_QUIT_OK> must be set to
true for this to work, so don't do that on a production server

=head2 redirect_to_default

Redirects to default controller. Matches any uri not matched by another action

=head2 render

Use the renderview action class

=head2 room_closed

The requested endpoint exists but has been deactivated by the
administrators.  The page is generated by the
L<simple page|CatalystX::Usul::Plugin::Model::StashHelper/simple_page> method
in the base class

=head2 version

Return the version number of this controller

=head2 view_source

View the source code for the current controller. Calls the
C<view_file> method in the L<CatalystX::Usul::Model::FileSystem> model
to display some source code with syntax highlighting

=head1 Diagnostics

Debug can be turned on/off from the tools menu

=head1 Configuration and Environment

Package variables contain the list of publicly accessible rooms

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Controller>

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
