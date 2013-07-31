# @(#)$Id: Cookies.pm 1319 2013-06-23 16:21:01Z pjf $

package CatalystX::Usul::TraitFor::Controller::Cookies;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.8.%d', q$Rev: 1319 $ =~ /\d+/gmx );

use Moose::Role;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(app_prefix);
use File::Spec::Functions      qw(catdir);

requires q(get_browser_state);

around 'get_browser_state' => sub {
   # Extract key/value pairs from the browser state cookie
   my ($next, $self, $c, $cfg) = @_; my $stash = { $self->$next( $c, $cfg ) };

   my $name = __get_state_cookie_name( $c ); my $cookie = {};

   for (split m{ \+ }mx, __get_cookie( $c, $name )) {
      my ($key, $value) = split m{ ~ }mx, $_;
      $key and $cookie->{ $key } = $value;
   }

   $cookie->{debug} and $stash->{browser_debug}
      = $cookie->{debug} eq q(true) ? TRUE : FALSE;

   $cookie->{footer} and $stash->{footer}->{state}
      = $cookie->{footer} eq q(true) ? TRUE : FALSE;

   $cookie->{language} and $stash->{language} = $cookie->{language};

   $cookie->{sidebar} and $stash->{sbstate} = $cookie->{sidebar} ? TRUE : FALSE;

   $cookie->{skin} and -d catdir( $cfg->{skindir}, $cookie->{skin} )
      and $stash->{skin} = $cookie->{skin};

   $cookie->{width} and $stash->{width} = $cookie->{width};

   $stash->{cookie_path} = $cfg->{cookie_path} || SEP;

   return %{ $stash };
};

sub delete_cookie {
   # Delete a key/value pair from the browser state cookie
   my ($self, $c, $args) = @_; my $s = $c->stash;

   my $name   = $args->{name} or return;
   my $key    = $args->{key } or return;
   my $cookie = __get_cookie( $c, $name ) or return;
   my $found  = FALSE;
   my $pairs  = NUL;

   for (split m{ \+ }mx, $cookie) {
      m{ \A $key ~ }mx and $found = TRUE and next;
      $pairs and $pairs .= q(+); $pairs .= $_;
   }

   $c->res->cookies->{ $name } = { domain => $s->{domain}, value => $pairs };
   return $found;
}

sub delete_state_cookie {
   my ($self, $c, $k) = @_; my $name = __get_state_cookie_name( $c );

   return $self->delete_cookie( $c, { name => $name, key => $k } );
}

sub get_cookie {
   # Extract the requested item from the browser cookie
   my ($self, $c, $args) = @_;

   my $name   = $args->{name} or return;
   my $key    = $args->{key } or return;
   my $cookie = __get_cookie( $c, $name ) or return;

   for (split m{ \+ }mx, $cookie) {
      m{ \A $key ~ }msx and return (split m{ ~ }mx, $_)[ 1 ];
   }

   return;
}

sub get_state_cookie {
   my ($self, $c, $k) = @_; my $name = __get_state_cookie_name( $c );

   return $self->get_cookie( $c, { name => $name, key => $k } );
}

sub set_cookie {
   # Set a key/value pair in the browser state cookie
   my ($self, $c, $args) = @_; my $s = $c->stash;

   my $value  = $args->{value};
   my $name   = $args->{name } or return;
   my $key    = $args->{key  } or return;
   my $cookie = __get_cookie( $c, $name );
   my $found  = FALSE;
   my $pairs  = NUL;

   for (split m{ \+ }mx, $cookie) {
      $pairs and $pairs .= q(+);

      if (m{ \A $key ~ }mx) { $pairs .= "${key}~${value}"; $found = TRUE }
      else { $pairs .= $_ }
   }

   unless ($found) { $pairs and $pairs .= q(+); $pairs .= "${key}~${value}" }

   $c->res->cookies->{ $name } = { domain => $s->{domain}, value => $pairs };

   return $value;
}

sub set_state_cookie {
   my ($self, $c, $k, $v) = @_; my $name = __get_state_cookie_name( $c );

   return $self->set_cookie( $c, { name => $name, key => $k, value => $v } );
}

# Private functions

sub __get_cookie {
   my ($c, $name) = @_;

   exists $c->res->cookies->{ $name }
      and return $c->res->cookies->{ $name }->{value};

   my $cookie_obj = $c->req->cookie( $name ) or return NUL;

   return $cookie_obj->value || NUL;
}

sub __get_state_cookie_name {
   my $c = shift; my $s = $c->stash;

   my $prefix = $s->{cookie_prefix} ||= app_prefix $c->config->{name} || NUL;

   return "${prefix}_state";
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TraitFor::Controller::Cookies - Cookie multiplexing methods

=head1 Version

0.8.$Revision: 1319 $

=head1 Synopsis

   package YourApp::Controller::YourController;

   use CatalystX::Usul::Moose;

   BEGIN { extends q(CatalystX::Usul::Controller) }

   sub foo {
      my ($self, $c) = @_;

      $cookie_value = $self->get_state_cookie( $c, $cookie_key );
   }

=head1 Description

Allows for multiple key/value pairs to be stored in a single cookie

=head1 Configuration and Environment

Requires C<get_browser_state>

=head1 Subroutines/Methods

=head2 delete_cookie

   $bool = $self->delete_cookie( $c, { name => $cookie_name, key => $k } );

Deletes the key / value pair from the named cookie

=head2 delete_state_cookie

   $bool = $self->set_state_cookie( $c, $cookie_key );

Deletes the key / value pair from the state cookie and
returns true if the pair was deleted, false otherwise

=head2 get_browser_state

Modifies the base controller method. Stash key/value pairs from the
browser state cookie

=head2 get_cookie

   $value = $self->get_cookie( $c, { name => $cookie_name, key => $k } );

Get a key/value pair from the named cookie

=head2 get_state_cookie

   $cookie_value = $self->set_state_cookie( $c, $cookie_key );

Returns the value from the state cookie for the specified key

=head2 set_cookie

   $value = $self->set_cookie( $c, { name => $name, key => $k, value => $v } );

Sets a key / value pair in the named cookie

=head2 set_state_cookie

   $cookie_value = $self->set_state_cookie( $c, $cookie_key, $cookie_value );

Sets the key / value pair on the state cookie. Returns the value

=head1 Diagnostics

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

Copyright (c) 2013 Pete Flanigan. All rights reserved

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
