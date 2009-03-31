package CatalystX::Usul::Plugin::Controller::ModelHelper;

# @(#)$Id: ModelHelper.pm 403 2009-03-28 04:09:04Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 403 $ =~ /\d+/gmx );

my $SEP = q(/);

sub add_menu_back {
   # Add a browser back link to the navigation menu
   my ($self, $c) = @_; my $e;

   eval { $c->model( q(Navigation) )->add_menu_back };

   $self->error_page( $c, $e->as_string ) if ($e = $self->catch);

   return;
}

sub add_menu_blank {
   # Stash some padding to fill the gap where the nav. menu was
   my ($self, $c) = @_; my $e;

   eval { $c->model( q(Navigation) )->add_menu_blank };

   $self->error_page( $c, $e->as_string ) if ($e = $self->catch);

   return;
}

sub add_menu_close {
   # Add a close window link to the navigation menu
   my ($self, $c) = @_; my $e;

   eval { $c->model( q(Navigation) )->add_menu_close };

   $self->error_page( $c, $e->as_string ) if ($e = $self->catch);

   return;
}

sub add_sidebar_panel {
   # Add an Ajax call to the side bar accordion widget
   my ($self, $c, @rest) = @_; my $e;

   my $pno = eval { $c->model( q(Base) )->add_sidebar_panel( @rest ) };

   $self->error_page( $c, $e->as_string ) if ($e = $self->catch);

   return $pno;
}

sub check_field {
   # Process Ajax calls to validate form field values
   my ($self, $c) = @_; $c->model( q(Base) )->check_field_wrapper; return;
}

sub close_footer {
   # Prevent the footer div from displaying
   my ($self, $c) = @_; my $s = $c->stash;

   if ($s->{fstate}) {
      if ($self->can( q(set_cookies) )) {
         $self->set_cookie( $c, { name => $s->{cname},
                                  key  => q(footer), value => q(false) } );
      }

      $s->{fstate} = 0;
   }

   return;
}

sub close_sidebar {
   # Prevent the side bar div from displaying
   my ($self, $c) = @_; my $s = $c->stash;

   if ($s->{sbstate}) {
      if ($self->can( q(delete_cookie) )) {
         $self->delete_cookie( $c, { name => $s->{cname},
                                     key  => q(sidebar) } );
      }

      $s->{sbstate} = 0;
   }

   return;
}

sub common {
   # Most controllers will want to add these things to the stash
   my ($self, $c, $base_model, $nav_model) = @_; my $e;

   $base_model ||= $c->model( q(Base) );
   $nav_model  ||= $c->model( q(Navigation) );

   eval {
      $base_model->add_header;
      $base_model->add_footer;
      $nav_model->add_quick_links;
      $nav_model->add_main_menu;
      $nav_model->add_tools_menu;
   };

   if ($e = $self->catch) {
      $self->error_page( $c, $e->as_string );
      $c->detach; # Never returns
   }

   return;
}

sub default {
   # Award the luser a 404
   my ($self, $c) = @_; my $s = $c->stash; my $e;

   return if ($c->res->redirect);

   my $model = $c->model( q(Base) );

   eval { $model->clear_controls; $model->simple_page( q(default) ) };

   $self->error_page( $c, $e->as_string ) if ($e = $self->catch);

   $self->add_menu_back( $c );
   $s->{request_path} = $c->req->path;
   $c->action->reverse( q(default) );
   $c->res->status( 404 );
   return;
}

sub help {
   # Generate the context sensitive help from the POD in the code
   my ($self, $c, @args) = @_; my $e;

   eval { $c->model( q(Help) )->get_help( @args ) };

   $self->error_page( $c, $e->as_string ) if ($e = $self->catch);

   $self->set_popup( $c );
   return;
}

sub open_footer {
   # Force the footer into the open state
   my ($self, $c) = @_; my $s = $c->stash;

   if (not $s->{fstate} and $self->can( q(set_cookie) )) {
      $self->set_cookie( $c, { name => $s->{cname},
                               key  => q(footer), value => q(true) } );
   }

   return;
}

sub open_sidebar {
   # Force the side bar into an open state
   my ($self, $c) = @_; my $s = $c->stash;

   if (not $s->{sbstate} and $self->can( q(set_cookie) )) {
      $self->set_cookie( $c, { key   => q(sidebar), name => $s->{cname},
                               value => $s->{assets}.q(pushedpin.gif) } );
   }

   return;
}

sub overview {
   # Respond to the ajax call for some info about the side bar accordion
   my ($self, $c) = @_; my $e;

   eval { $c->model( q(Help) )->overview };

   $self->error_page( $c, $e->as_string ) if ($e = $self->catch);

   return;
}

sub select_sidebar_panel {
   my ($self, $c, $pno) = @_;

   if ($self->can( q(set_cookie) )) {
      $self->set_cookie( $c, { name  => $c->stash->{cname},
                               key   => q(sidebarPanel), value => $pno } );
   }

   return;
}

sub set_popup {
   my ($self, $c) = @_; my $e;

   eval { $c->model( q(Base) )->clear_controls };

   $self->error_page( $c, $e->as_string ) if ($e = $self->catch);

   $c->stash( is_popup => q(true) );
   $self->add_menu_close( $c );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::ModelHelper - Convenience methods for common model calls

=head1 Version

0.1.$Revision: 403 $

=head1 Synopsis

   package CatalystX::Usul;
   use parent qw(Catalyst::Component CatalystX::Usul::Base);

   package CatalystX::Usul::Controller;
   use parent qw(CatalystX::Usul
                 CatalystX::Usul::ModelHelper
                 Catalyst::Controller);

   package YourApp::Controller::YourController;
   use parent qw(CatalystX::Usul::Controller);

=head1 Description

Many convenience methods for common model calls

=head1 Subroutines/Methods

=head2 add_menu_back

Added a link to the main navigation menu that goes back to the previous page
Calls L<add_meun_item|CatalystX::Usul::Model::Navigation>

=head2 add_menu_blank

Adds some whitespace to the navigation menu so that the background does
not show through

=head2 add_menu_close

Adds a link that will close the current window to the main navigation menu.
Calls L<add_meun_item|CatalystX::Usul::Model::Navigation>

=head2 add_result

Add a message to the results div

=head2 add_sidebar_panel

Calls method of the same name in the base model class to stuff the
stash with the data necessary to create a panel in the accordion
widget on the sidebar

=head2 check_field

Creates an XML response to and Ajax call which validates a data value
for a given form field. Calls L<CatalystX::Usul::Model/check_field>

=head2 close_footer

Forces the footer to not be displayed when the page is rendered

=head2 close_sidebar

Forces the sidebar to not be displayed when the page is rendered

=head2 common

Sets stash values for the navigation menus, tools menus, the footer,
quick links and recovers the keys for the current form
from the session store

Calls L<add_header|CatalystX::Usul::Model>

Calls L<add_footer|CatalystX::Usul::Model>

Calls L<add_main_menu|CatalystX::Usul::Model::Navigation>.  This is
the main navigation menu

Calls L<add_quick_links|CatalystX::Usul::Model::Navigation>. Quick
links appear in the header and are selected from the I<rooms> config
items if the I<quick_link> element is set. It's numeric value
determines the sort order of the links

Calls L<add_tools_menu|CatalystX::Usul::Model::Navigation>

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

=head2 overview

Generates some blurb for the Overview panel of the sidebar accordion widget

=head2 query_array

Exposes the method of the same name in the base model class

=head2 query_value

Exposes the method of the same name in the base model class

=head2 select_sidebar_panel

Set the cookie that controls which sidebar panel is visible

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
