# @(#)$Id: View.pm 576 2009-06-09 23:23:46Z pjf $

package CatalystX::Usul::View;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 576 $ =~ /\d+/gmx );
use parent qw(Catalyst::View CatalystX::Usul);

use Encode;
use HTML::FormWidgets;

__PACKAGE__->config( form_sources    => [ qw(sdata hidden) ],
                     serialize_attrs => {} );

__PACKAGE__->mk_accessors( qw(content_types deserialize_attrs
                              dynamic_templates form_sources
                              serialize_attrs) );

sub bad_request {
   my ($self, $c, $verb, $msg) = @_;

   $c->res->body( $msg );
   $c->res->content_type( q(text/plain) );
   $c->res->status( 400 );
   return 0;
}

sub build_widgets {
   my ($self, $c, $sources, $config) = @_; my $s = $c->stash; my $data = [];

   $sources ||= []; $config ||= {};

   for my $part (map { $s->{ $_ } } grep { $s->{ $_ } } @{ $sources }) {
      if (ref $part eq q(ARRAY) and $part->[ 0 ]) {
         push @{ $data }, $_ for (@{ $part });
      }
      else { push @{ $data }, $part }
   }

   $config->{assets      } = $s->{assets};
   $config->{base        } = $c->req->base;
   $config->{content_type} = $s->{content_type};
   $config->{fields      } = $s->{fields} || {};
   $config->{form        } = $s->{form};
   $config->{hide        } = $s->{hidden}->{items};
   $config->{messages    } = $s->{messages};
   $config->{pwidth      } = $s->{pwidth};
   $config->{root        } = $c->config->{root};
   $config->{static      } = $s->{static};
   $config->{swidth      } = $s->{width} if ($s->{width});
   $config->{templatedir } = $self->dynamic_templates;
   $config->{url         } = $c->req->path;

   HTML::FormWidgets->build( $config, $data );
   return $data;
}

sub deserialize {
   my ($self, $s, $req, $process) = @_; my ($body, $data, $e);

   if ($body = $req->body) {
      $data = eval { $process->( $self->deserialize_attrs || {}, $body ) };

      if ($e = $self->catch) {
         $self->log_error( $e->as_string );
         return;
      }
   }
   else { $self->log_debug( 'Nothing to deserialize' ) if ($self->debug) }

   return $data;
}

sub get_verb {
   my ($self, $s, $req) = @_; my $verb = lc $req->method;

   if ($verb eq q(post)) {
      $verb = delete $req->params->{_method} if ($req->param( q(_method) ));
   }

   return $verb;
}

sub not_implemented {
   my ($self, $c, $verb, $msg) = @_;

   $c->res->body( $msg );
   $c->res->content_type( q(text/plain) );
   $c->res->status( 405 );
   return 0;
}

sub prepare_data {
   my ($self, $c) = @_; my $s = $c->stash; my $form;

   my $srcs = $self->form_sources;
   my $data = $self->build_widgets( $c, $srcs, { skip_groups => 1 } );

   if ($data and $form = $data->[ 0 ]) {
      if ($form->{items}->[ 0 ] and $form->{items}->[ 0 ]->{content}) {
         my %s = map { $_ => $s->{ $_ } } keys %{ $s };

         $form->{items}->[ 0 ]->{content}
            =~ s{ \[% \s+ (.+) \s+ %\] }{$s{ $1 }}gmx;
      }

      shift @{ $data };
   }
   else { $form = { items => [] } }


   if ($data and $data->[ 0 ]) {
      push @{ $form->{items} }, @{ $_->{items} || [] } for (@{ $data });
   }

   $form->{count} = scalar @{ $form->{items} };

   for my $id (0 .. $form->{count}) {
      my $item = $form->{items}->[ $id ];

      $item->{id} = $id unless (defined $item->{id});
   }

   return $form;
}

sub process {
   my ($self, $c) = @_; my ($attrs, $body, $e, $enc, $types);

   my $s = $c->stash; my $type = $s->{content_type};

   if ($types = $self->content_types) {
      if ($type) {
         if (exists $types->{ $type }) { $attrs = $types->{ $type } }
         else { $body = $self->loc( $c, 'Content type [_1] unknown', $type ) }
      }
      else { $body = $self->loc( $c, 'Content type not specified' ) }

      return $self->_unsupported_media_type( $c, $body."\r\n" ) if ($body);
   }
   else { $attrs = $self->serialize_attrs }

   $body = eval { $self->serialize( $attrs, $self->prepare_data( $c ) ) };

   if ($e = $self->catch) {
      $body  = $self->loc( $c, 'Serializer [_1] failed', $type );
      $body .= "\r\n***ERROR***\r\n".$e->as_string;
      $self->bad_request( $c, $body );
      return 1;
   }

   if ($enc = $s->{encoding}) { # Encode the body of the page
      $body = encode( $enc, $body ); $type .= q(; charset=).$enc;
   }

   $c->res->header( Vary => q(Content-Type) );
   $c->res->content_type( $type );
   $c->res->body( $body );
   return 1;
}

# Private methods

sub _unsupported_media_type {
   my ($self, $c, $body) = @_;

   $c->res->body( $body );
   $c->res->content_type( q(text/plain) );
   $c->res->status( 415 );
   return 1;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::View - Base class for views

=head1 Version

0.3.$Revision: 576 $

=head1 Synopsis

   package CatalystX::Usul::View;
   use parent qw(Catalyst::View CatalystX::Usul::Base);

   package CatalystX::Usul::View::HTML;
   use parent qw(CatalystX::Usul::View);

   package YourApp::View::HTML;
   use parent qw(CatalystX::Usul::View::HTML);

   package YourApp::View::JSON;
   use parent qw(CatalystX::Usul::View::JSON);

=head1 Description

Provide common methods for subclasses

=head1 Subroutines/Methods

=head2 bad_request

Sets the response body to the provided error message and the response
status to 400

=head2 build_widgets

Calls C<build> in L<HTML::FormWidgets> which transforms the widgets
definitions into fragments of HTML or XHTML as required

=head2 deserialize

Calls the deserialization method selected by the subclass on
the request body

=head2 get_verb

Returns the lower case request method name. Allows for the
implementation of a "RESTful" API. The client may post and set the
I<_method> request parameter to I<delete> or I<put> if it does not
support those methods directly. It may also set the the I<_method> to
an arbitrary value

The verb is used by the action class to lookup the action to forward
to. Called from the C<begin> method once the current view has been
determined from the request content type

=head2 not_implemented

Sets the response body to the provided error message and the response
status to 405

=head2 prepare_data

Called by L</process> this method is responsible for
selecting those elements from the stash that are passed to
the C</build_widgets> method

=head2 process

Serializes the response using L<XML::Simple> and encodes the body using
L<Encode> if required

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Catalyst::View>

=item L<CatalystX::Usul::Base>

=item L<Encode>

=item L<HTML::FormWidgets>

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
