# @(#)$Id: Cookies.pm 1139 2012-03-28 23:49:18Z pjf $

package CatalystX::Usul::Plugin::Controller::Cookies;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1139 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;

sub delete_cookie {
   # Delete a key/value pair from the browser state cookie
   my ($self, $c, $args) = @_;

   my $name   = $args->{name} or return;
   my $key    = $args->{key } or return;
   my $cookie = $c->req->cookie( $name ) or return;
   my $pairs  = NUL;

   for (__get_pairs_for( $cookie, $name )) {
      m{ \A $key ~ }mx and next; $pairs and $pairs .= q(+); $pairs .= $_;
   }

   $c->res->cookies->{ $name } = { value => $pairs };
   return;
}

sub get_browser_state {
   # Extract key/value pairs from the browser state cookie
   my ($self, $c, $name) = @_; my $cfg = $c->config; my $res = {};

   my $args  = { name => $name, key => q(debug) };
   my $debug = $self->get_cookie( $c, $args );

   $res->{debug  } = $debug && $debug eq q(true) ? TRUE : FALSE;
   $args->{key   } = q(footer);
   $res->{fstate } = $self->get_cookie( $c, $args ) eq q(true) ? TRUE : FALSE;
   $args->{key   } = q(language);
   $res->{lang   } = $self->get_cookie( $c, $args );
   $args->{key   } = q(sidebar);
   $res->{sbstate} = $self->get_cookie( $c, $args ) ? TRUE : FALSE;
   $args->{key   } = q(skin);

   my $skin; $skin = $self->get_cookie( $c, $args )
      and -d $self->catdir( $cfg->{skindir}, $skin )
      and $res->{skin} = $skin;

   $args->{key} = q(width);

   my $width; $width = $self->get_cookie( $c, $args )
      and $res->{width} = $width;

   return $res;
}

sub get_cookie {
   # Extract the requested item from the browser cookie
   my ($self, $c, $args) = @_;

   my $name   = $args->{name} or return NUL;
   my $key    = $args->{key } or return NUL;
   my $cookie = $c->req->cookie( $name ) or return NUL;

   for (__get_pairs_for( $cookie, $name )) {
      m{ \A $key ~ }msx and return (split m{ ~ }mx, $_)[1];
   }

   return NUL;
}

sub set_cookie {
   # Set a key/value pair in the browser state cookie
   my ($self, $c, $args) = @_;

   my $value  = $args->{value};
   my $name   = $args->{name } or return;
   my $key    = $args->{key  } or return; $key .= q(~);
   my $cookie = $c->req->cookie( $name ) || NUL;
   my $found  = FALSE;
   my $pairs  = NUL;

   for (__get_pairs_for( $cookie, $name )) {
      $pairs and $pairs .= q(+);

      if (m{ \A $key }mx) { $pairs .= $key.$value; $found = TRUE }
      else { $pairs .= $_ }
   }

   unless ($found) { $pairs and $pairs .= q(+); $pairs .= $key.$value }

   $c->res->cookies->{ $name } = { value => $pairs };
   return;
}

# Private functions

sub __get_pairs_for {
   my ($cookie, $name) = @_;

   my $pairs = (grep   { m{ \A $name = }msx }
                map    { s{ \s+ }{}gmx; $_  }
                split m{ ; }mx, $cookie || NUL)[0] or return NUL;
   my $v     = (split m{ = }mx, $pairs)[1] || NUL;
      $v     =~ s{ % ([0-9A-Fa-f]{2}) }{chr(hex($1))}egmsx;

   return split m{ \+ }mx, $v;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Plugin::Controller::Cookies - Cookie multiplexing methods

=head1 Version

0.5.$Revision: 1139 $

=head1 Synopsis

   package CatalystX::Usul;
   use parent qw(CatalystX::Usul::Base CatalystX::Usul::File);

   package CatalystX::Usul::Controller;
   use parent qw(Catalyst::Controller CatalystX::Usul);

   package YourApp::Controller::YourController;
   use parent qw(CatalystX::Usul::Controller);

=head1 Description

Allows for multiple key/value pairs to be stored in a single cookie

=head1 Subroutines/Methods

=head2 delete_cookie

Deletes the key/value pair from the named cookie

=head2 get_browser_state

Stash key/value pairs from the browser state cookie

=head2 get_cookie

Get a key/value pair from the named cookie

=head2 set_cookie

Sets a key/value pair in the named cookie

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

None

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
