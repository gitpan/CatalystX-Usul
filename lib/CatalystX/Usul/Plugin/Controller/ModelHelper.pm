# @(#)$Id: ModelHelper.pm 1166 2012-04-03 12:37:30Z pjf $

package CatalystX::Usul::Plugin::Controller::ModelHelper;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1166 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;

sub add_header {
   my ($self, $c) = @_; my $model = $c->stash->{nav_model} or return;

   return $model->add_header;
}

sub check_field {
   # Process Ajax calls to validate form field values
   my ($self, $c) = @_;

   return $c->model( $self->model_base_class )->check_field_wrapper;
}

sub close_footer {
   # Prevent the footer div from displaying
   my ($self, $c) = @_; my $s = $c->stash;

   if ($s->{footer}->{state}) {
      $self->can( q(set_cookies) )
         and $self->set_cookie( $c, { name  => $s->{cookie_prefix}.q(_state),
                                      key   => q(footer),
                                      value => q(false) } );
      $s->{footer}->{state} = FALSE;
   }

   return;
}

sub close_sidebar {
   # Prevent the side bar div from displaying
   my ($self, $c) = @_; my $s = $c->stash;

   if ($s->{sbstate}) {
      $self->can( q(delete_cookie) )
         and $self->delete_cookie( $c, { name => $s->{cookie_prefix}.q(_state),
                                         key  => q(sidebar) } );
      $s->{sbstate} = FALSE;
   }

   return;
}

sub default {
   # Award the luser a 404
   my ($self, $c) = @_; my $action = $c->action; $c->res->redirect and return;

   $c->stash->{request_path} = $c->req->path;

   $self->add_header( $c ); $self->reset_nav_menu( $c, q(back) );

   $action->namespace( NUL ); $action->name( q(default) );

   $c->res->status( 404 );
   return;
}

sub help {
   # Generate the context sensitive help from the POD in the code
   my ($self, $c, $name) = @_; $name = ucfirst ($name || q(root));

   $self->add_header( $c ); $c->stash( is_popup => q(true) );

   my $module = $c->config->{name}.q(::Controller::).$name;

   $c->model( $self->help_class )->module_docs( $module, $name );
   return;
}

sub open_footer {
   # Force the footer into the open state
   my ($self, $c) = @_; my $s = $c->stash;

   unless ($s->{footer}->{state}) {
      $self->can( q(set_cookie) )
         and $self->set_cookie( $c, { name  => $s->{cookie_prefix}.q(_state),
                                      key   => q(footer),
                                      value => q(true) } );
      $s->{footer}->{state} = TRUE;
   }

   return;
}

sub open_sidebar {
   # Force the side bar into an open state
   my ($self, $c) = @_; my $s = $c->stash;

   not $s->{sbstate} and $self->can( q(set_cookie) )
      and $self->set_cookie( $c, { name  => $s->{cookie_prefix}.q(_state),
                                   key   => q(sidebar),
                                   value => q(pushedpin_icon) } );
   return;
}

sub reset_nav_menu {
   my ($self, $c, $key, $args) = @_; $key ||= NUL;

   my $nav = $c->stash->{nav_model}; $nav->clear_controls;

   if    ($key eq q(back) ) { $nav->add_menu_back ( $args ) }
   elsif ($key eq q(blank)) { $nav->add_menu_blank( $args ) }
   elsif ($key eq q(close)) { $nav->add_menu_close( $args ) }

   return $nav;
}

sub select_sidebar_panel {
   my ($self, $c, $pno) = @_;

   $self->can( q(set_cookie) ) and $self->set_cookie( $c, {
      name  => $c->stash->{cookie_prefix}.q(_state),
      key   => q(sidebarPanel),
      value => $pno } );
   return;
}

sub set_popup {
   my ($self, $c, @rest) = @_;

   $self->add_header( $c ); $self->reset_nav_menu( $c, @rest );
   $c->stash( is_popup => q(true) );
   return;
}

sub set_identity_model {
   my ($self, $c) = @_; my $model_name;

   my $model = $c->model( $self->realm_class );
   my $realm = $self->get_uri_query_params( $c )->{realm}
            || $model->default_realm;

   ($model_name, $realm)
          = $model->get_identity_model_name( $self->realm_class, $realm );
   $model = $c->model( $model_name );

   $c->stash( role_model => $model->roles,
              user_model => $model->users,
              user_realm => $realm );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Plugin::Controller::ModelHelper - Convenience methods for common model calls

=head1 Version

0.6.$Revision: 1166 $

=head1 Synopsis

   package CatalystX::Usul;
   use parent qw(CatalystX::Usul::Base CatalystX::Usul::File);

   package CatalystX::Usul::Controller;
   use parent qw(Catalyst::Controller CatalystX::Usul);

   package YourApp::Controller::YourController;
   use parent qw(CatalystX::Usul::Controller);

=head1 Description

Many convenience methods for common model calls

=head1 Subroutines/Methods

=head2 add_header

Calls method of the same name on the navigation model

=head2 check_field

Creates an XML response to and Ajax call which validates a data value
for a given form field. Calls L<CatalystX::Usul::Model/check_field>

=head2 close_footer

Forces the footer to not be displayed when the page is rendered

=head2 close_sidebar

Forces the sidebar to not be displayed when the page is rendered

=head2 default

Generates a simple page not found page. No longer called as unknown
pages cause a redirect to the controllers default page

=head2 help

Generates a context sensitive help page by calling
L<get_help|CatalystX::Usul::Model::Help>

=head2 open_footer

Sets the key/value pair in the browser state cookie that will cause
the footer to appear in the generated page

=head2 open_sidebar

Sets the key/value pair in the browser state cookie that will cause
the sidebar to appear in the generated page

=head2 query_array

Exposes the method of the same name in the base model class

=head2 query_value

Exposes the method of the same name in the base model class

=head2 reset_nav_menu

   $model_obj = $self->reset_nav_menu( $c, $key );

Calls L<add_header|CatalystX::Usul::Model::Navigation/add_header> and
L<clear_controls|CatalystX::Usul::Model::Navigation/clear_controls> on
the stashed C<nav_model>.  Optionally calls an C<add_menu_*> method on
the stashed C<nav_model> if C<$key> is one of; I<back>, I<blank>, or
C<close>. Returns the stashed C<nav_model> object

=head2 select_sidebar_panel

Set the cookie that controls which sidebar panel is visible

=head2 set_identity_model

Stashes currently selected realm name. Determines and stashes the current
user and roles models based on the current realm

=head2 set_popup

Sets the popup flag to stop the browser from caching the window size in
the browser state cookie. Clears the main navigation menu and adds a
close window link

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul>

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
