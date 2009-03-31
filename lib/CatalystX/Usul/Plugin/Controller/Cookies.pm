package CatalystX::Usul::Plugin::Controller::Cookies;

# @(#)$Id: Cookies.pm 380 2009-03-11 18:22:46Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 380 $ =~ /\d+/gmx );

my $NUL = q();

sub delete_cookie {
   # Delete a key/value pair from the browser state cookie
   my ($self, $c, $args) = @_; my ($cookie, $key, $name, $val);

   return unless ($name = $args->{name} and $key = $args->{key});

   my $tokens = $NUL;

   if ($cookie = $c->req->cookie( $name )) {
      for my $token (split m{ ; }mx, $cookie) {
         $token =~ s{ \s+ }{}gmx;

         if ($token =~ m{ \A $name = }mx) {
            $val = (split m{ = }mx, $token)[1];
            $val =~ s{ % ([0-9A-Fa-f]{2}) }{chr( hex( $1 ) )}egmx;

            for (split m{ \+ }mx, $val) {
               unless (m{ \A $key ~ }mx) {
                  $tokens .= q(+) if ($tokens);
                  $tokens .= $_;
               }
            }

            $c->res->cookies->{ $name } = { value => $tokens };
            return;
         }
      }
   }

   return;
}

sub get_cookie {
   # Extract the requested item from the browser cookie
   my ($self, $c, $args) = @_; my ($cookie, $key, $name, $val);

   return $NUL unless ($name = $args->{name} and $key = $args->{key});

   if ($cookie = $c->req->cookie( $name )) {
      for my $token (split m{ ; }mx, $cookie) {
         $token =~ s{ \s+ }{}gmsx;

         if ($token =~ m{ \A $name = }msx) {
            $val = (split m{ = }mx, $token)[1];
            $val =~ s{ % ([0-9A-Fa-f]{2}) }{chr(hex($1))}egmsx;

            for (split m{ \+ }mx, $val) {
               return (split m{ ~ }mx, $_)[1] if (m{ \A $key ~ }msx);
            }

            return $NUL;
         }
      }
   }

   return $NUL;
}

sub load_stash_with_browser_state {
   # Extract key/value pairs from the browser state cookie
   my ($self, $c) = @_;
   my $cfg        = $c->config;
   my $s          = $c->stash;
   my $args       = { name => $s->{cname}, key => q(debug) };
   my $debug      = $self->get_cookie( $c, $args );

   $s->{debug  }  = $debug && $debug eq q(true) ? 1 : 0;
   $args->{key }  = q(footer);

   my $state      = $self->get_cookie( $c, $args );

   $s->{fstate }  = $state && $state eq q(true) ? 1 : 0;
   $args->{key }  = q(pwidth);

   my $pwidth     = $self->get_cookie( $c, $args );

   $s->{pwidth }  = $pwidth if ($pwidth);
   $args->{key }  = q(sidebar);
   $s->{sbstate}  = $self->get_cookie( $c, $args ) ? 1 : 0;
   $args->{key }  = q(skin);

   my $skin       = $self->get_cookie( $c, $args );

   $s->{skin   }  = $skin   if ($skin
                                && -d $self->catdir( $cfg->{skindir}, $skin ));
   $args->{key }  = q(width);

   my $width      = $self->get_cookie( $c, $args );

   $s->{width  }  = $width  if ($width);
   return;
}

sub set_cookie {
   # Set a key/value pair in the browser state cookie
   my ($self, $c, $args) = @_; my ($cookie, $key, $name, $val);

   return unless ($name = $args->{name} and $key = $args->{key});

   my $found = 0; my $tokens = $NUL; my $value = $args->{value}; $key .= q(~);

   if ($cookie = $c->req->cookie( $name )) {
      for my $token (split m{ ; }mx, $cookie) {
         $token =~ s{ \s+ }{}gmx;

         if ($token =~ m{ \A $name = }mx) {
            $val = (split m{ = }mx, $token)[1];
            $val =~ s{ % ([0-9A-Fa-f]{2}) }{chr(hex($1))}egmx;

            for (split m{ \+ }mx, $val) {
               $tokens .= q(+) if ($tokens);

               if (m{ \A $key }mx) { $tokens .= $key.$value; $found = 1 }
               else { $tokens .= $_ }
            }

            unless ($found) {
               $tokens .= q(+) if ($tokens);
               $tokens .= $key.$value
            }

            $c->res->cookies->{ $name } = { value => $tokens };
            return;
         }
      }
   }

   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Cookies - Cookie multiplexing methods

=head1 Version

0.1.$Revision: 380 $

=head1 Synopsis

   package CatalystX::Usul;
   use parent qw(Catalyst::Component CatalystX::Usul::Base);

   package CatalystX::Usul::Controller;
   use parent qw(CatalystX::Usul
                 CatalystX::Usul::Cookies
                 CatalystX::Usul::ModelHelper
                 Catalyst::Controller);

   package YourApp::Controller::YourController;
   use parent qw(CatalystX::Usul::Controller);

=head1 Description

Allows for multiple key/value pairs to be stored in a single cookie

=head1 Subroutines/Methods

=head2 delete_cookie

Deletes the key/value pair from the named cookie

=head2 get_cookie

Get a key/value pair from the named cookie

=head2 load_stash_with_browser_state

Stash key/value pairs from the browser state cookie

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
