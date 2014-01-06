# @(#)Ident: ;

package CatalystX::Usul::TraitFor::Controller::ModelHelper;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.15.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Moose::Role;
use CatalystX::Usul::Constants;

sub check_field_wrapper { # Process Ajax calls to validate form field values
   return $_[ 1 ]->model( $_[ 0 ]->config_class )->check_field_wrapper;
}

sub close_footer { # Prevent the footer div from displaying
   my ($self, $c) = @_; my $footer = $c->stash->{footer};

   $footer->{state} or return FALSE; $footer->{state} = FALSE;

   return defined $self->set_state_cookie( $c, q(footer), q(false) )
        ? TRUE : FALSE;
}

sub close_sidebar { # Prevent the side bar div from displaying
   my ($self, $c) = @_; my $s = $c->stash;

   $s->{sbstate} or return FALSE; $s->{sbstate} = FALSE;

   return $self->delete_state_cookie( $c, q(sidebar) );
}

sub default { # Award the luser a 404
   my ($self, $c) = @_; my $action = $c->action;

   $c->res->redirect and return;
   $c->stash->{request_path} = $c->req->path;
   $self->reset_nav_menu( $c, q(back) );
   $action->namespace( NUL ); $action->name( q(default) );
   $c->res->status( 404 );
   return;
}

sub open_footer { # Force the footer into the open state
   my ($self, $c) = @_; my $footer = $c->stash->{footer};

   $footer->{state} and return FALSE; $footer->{state} = TRUE;

   return defined $self->set_state_cookie( $c, q(footer), q(true) )
        ? TRUE : FALSE;
}

sub open_sidebar { # Force the side bar into an open state
   my ($self, $c) = @_; my $s = $c->stash;

   $s->{sbstate} and return FALSE; $s->{sbstate} = TRUE;

   return defined $self->set_state_cookie( $c, q(sidebar), q(pushedpin_icon) )
        ? TRUE : FALSE;
}

sub reset_nav_menu {
   my ($self, $c, $key, $args) = @_; my $nav = $c->stash->{nav_model};

   $key ||= NUL; $nav->add_nav_header; $nav->clear_controls;

   if    ($key eq q(back) ) { $nav->add_menu_back ( $args ) }
   elsif ($key eq q(blank)) { $nav->add_menu_blank( $args ) }
   elsif ($key eq q(close)) { $nav->add_menu_close( $args ) }

   return $nav;
}

sub select_sidebar_panel {
   return $_[ 0 ]->set_state_cookie( $_[ 1 ], q(sidebarPanel), $_[ 2 ] );
}

sub set_popup {
   my ($self, $c, @args) = @_;

   $c->stash( is_popup => q(true) ); $self->reset_nav_menu( $c, @args );

   return $c->model( $self->help_class );
}

sub stash_identity_model {
   my ($self, $c) = @_; my $model_name;

   my $model      = $c->model( $self->realm_class );
   my $realm      = $self->get_uri_query_params( $c )->{realm};
   my ($user_class, $user_realm)
      = $model->get_user_model_class( $self->realm_class, $realm );
   my $user_model = $c->model( $user_class );

   $c->stash( role_model => $c->model( $user_model->role_model_class ),
              user_model => $user_model,
              user_realm => $user_realm );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TraitFor::Controller::ModelHelper - Convenience methods for common model calls

=head1 Version

Describes v0.15.$Rev: 1 $

=head1 Synopsis

   package YourApp::Controller::YourController;

   use CatalystX::Usul::Moose;

   extends q(CatalystX::Usul::Controller);
   with    q(CatalystX::Usul::TraitFor::Controller::ModelHelper);

=head1 Description

Many convenience methods for common model calls

=head1 Subroutines/Methods

=head2 check_field_wrapper

   $self->check_field_wrapper( $c );

Creates an XML response to and Ajax call which validates a data value
for a given form field. Calls
L<CatalystX::Usul::TraitFor::Controller::ModelHelper/check_field_wrapper>

=head2 close_footer

   $bool = $self->close_footer( $c );

Forces the footer to not be displayed when the page is rendered

=head2 close_sidebar

   $bool = $self->close_sidebar( $c );

Forces the sidebar to not be displayed when the page is rendered

=head2 default

   $self->default( $c );

Generates a simple page not found page. No longer called as unknown
pages cause a redirect to the controllers default page

=head2 open_footer

   $bool = $self->open_footer( $c );

Sets the key/value pair in the browser state cookie that will cause
the footer to appear in the generated page

=head2 open_sidebar

   $bool = $self->open_sidebar( $c );

Sets the key/value pair in the browser state cookie that will cause
the sidebar to appear in the generated page

=head2 reset_nav_menu

   $nav_model_obj = $self->reset_nav_menu( $c, $key, \%params );

Calls L<add_header|CatalystX::Usul::Model::Navigation/add_header> and
L<clear_controls|CatalystX::Usul::Model::Navigation/clear_controls> on
the stashed C<nav_model>.  Optionally calls an C<add_menu_*> method on
the stashed C<nav_model> if C<$key> is one of; I<back>, I<blank>, or
C<close>. Returns the stashed C<nav_model> object

=head2 select_sidebar_panel

   $panel_number = $self->select_sidebar_panel( $c, $panel_number );

Set the cookie that controls which sidebar panel is visible

=head2 set_popup

   $help_model = $self->set_popup( $c, $key, \%params );

Sets the popup flag to stop the browser from caching the window size in
the browser state cookie. Clears the main navigation menu and adds a
I<$key> window link. Calls L</reset_nav_menu>. Returns the help model
object

=head2 stash_identity_model

   $self->stash_identity_model( $c );

Stashes currently selected realm name. Determines and stashes the current
user and roles models based on the current realm

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Moose::Role>

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
