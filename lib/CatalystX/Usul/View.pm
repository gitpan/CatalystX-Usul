# @(#)$Id: View.pm 1097 2012-01-28 23:31:29Z pjf $

package CatalystX::Usul::View;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1097 $ =~ /\d+/gmx );
use parent qw(Catalyst::View CatalystX::Usul);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(exception is_arrayref is_hashref throw);
use Encode;
use HTML::FormWidgets;
use Scalar::Util qw(blessed);
use Template;
use TryCatch;

__PACKAGE__->config( form_sources    => [ qw(sdata hidden) ],
                     js_object       => q(behaviour),
                     serialize_attrs => {} );

__PACKAGE__->mk_accessors( qw(content_types deserialize_attrs
                              form_sources js_object serialize_attrs
                              template_dir) );

sub COMPONENT {
   my ($class, $app, @rest) = @_;

   my $new  = $class->next::method( $app, @rest );
   my $usul = CatalystX::Usul->new( $app, {} );

   for (grep { not defined $new->{ $_ } } keys %{ $usul }) {
      $new->{ $_ } = $usul->{ $_ };
   }

   return $new;
}

sub bad_request {
   my ($self, $c, $verb, $msg, $status) = @_; $status ||= 400;

   $c->res->body( $msg );
   $c->res->content_type( q(text/plain) );
   $c->res->status( $status );
   return FALSE;
}

sub deserialize {
   my ($self, $s, $req, $process) = @_;

   my $body = $req->body; $s->{leader} = blessed $self;

   if ($body) {
      try        { return $process->( $self->deserialize_attrs || {}, $body ) }
      catch ($e) { $self->log_error_message( (exception $e), $s ) }
   }
   else {
      $self->debug and $self->log_debug_message( 'Nothing to deserialize', $s );
   }

   return;
}

sub get_verb {
   my ($self, $c) = @_; my $req = $c->req; my $verb = lc $req->method;

   if ($verb eq q(post)) {
      $req->param( q(_method) ) and $verb = delete $req->params->{_method};
   }

   return $verb;
}

sub not_implemented {
   my ($self, @rest) = @_; return $self->bad_request( @rest, 405 );
}

sub process {
   my ($self, $c) = @_; my $s = $c->stash;

   my $attrs = $self->serialize_attrs || {}; my $body;

   my $type  = $attrs->{content_type} = $s->{content_type};

   try        { $body  = $self->serialize( $attrs, $self->_prepare_data( $c )) }
   catch ($e) { $body  = "Serializer ${type} failed\r\n***ERROR***\r\n";
                $self->bad_request( $c, $body.(exception $e) ); return TRUE }

   if (my $enc = $s->{encoding}) { # Encode the body of the page
      $body = encode( $enc, $body ); $type .= q(; charset=).$enc;
   }

   $c->res->header( Vary => q(Content-Type) );
   $c->res->content_type( $type );
   $c->res->body( $body );
   return TRUE;
}

# Private methods

sub _build_widgets {
   my ($self, $c, $args) = @_; my $s = $c->stash;

   my $attrs = { %{ $args || {} } };
   my @attrs = ( qw(assets content_type fields hidden
                    literal_js optional_js pwidth width) );

   $attrs->{ $_         } = $s->{ $_ } for (@attrs);
   $attrs->{base        } = $c->req->base;
   $attrs->{js_object   } = $self->js_object;
   $attrs->{l10n        } = sub { $self->loc( $s, @_ ) };
   $attrs->{root        } = $c->config->{root};
   $attrs->{template_dir} = $self->template_dir;

   HTML::FormWidgets->build( $attrs );
   return;
}

sub _prepare_data {
   my ($self, $c) = @_; my $s = $c->stash;

   $s->{EOT} = $s->{is_xml} ? q( />) : q(>);

   my $tt   = Template->new( {} ) or throw $Template::ERROR;
   my $data = $self->_read_form_sources( $c ) || [];

   for my $source (@{ $data }) {
      my $id = 0;

      for my $item (grep { $_->{content} } @{ $source->{items} }) {
         my $content = $item->{content};

         if (is_hashref $content and exists $content->{text}) {
            $item->{content}->{text}
               = __tt_process( $tt, $s, \$content->{text} );
         }
         else { $item->{content} = __tt_process( $tt, $s, \$content ) }

         defined $item->{id} or $item->{id} = $id; $id++;
      }

      $source->{count} = scalar @{ $source->{items} };
   }

   $data->[ 1 ] or return $data->[ 0 ];

   for my $source (map { $data->[ $_ ] } 1 .. $#{ $data }) {
      push @{ $data->[ 0 ]->{items} || [] }, @{ $source->{items} || [] };
   }

   return $data->[ 0 ];
}

sub _read_form_sources {
   my ($self, $c) = @_; my $s = $c->stash;

   my $sources = $self->form_sources || []; my $data = [];

   for my $part (map { $s->{ $_ } } grep { $s->{ $_ } } @{ $sources }) {
      unless (is_arrayref $part and $part->[ 0 ]) { push @{ $data }, $part }
      else { push @{ $data }, $_ for (@{ $part }) }
   }

   return $data;
}

# Private subroutines

sub __tt_process {
   my ($tt, $s, $in) = @_; my $out;

   $tt->process( $in, $s, \$out ) or throw $tt->error;

   return $out;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::View - Base class for views

=head1 Version

0.4.$Revision: 1097 $

=head1 Synopsis

   package CatalystX::Usul::View;
   use parent qw(Catalyst::View CatalystX::Usul);

   package CatalystX::Usul::View::HTML;
   use parent qw(CatalystX::Usul::View);

   package YourApp::View::HTML;
   use parent qw(CatalystX::Usul::View::HTML);

   package YourApp::View::JSON;
   use parent qw(CatalystX::Usul::View::JSON);

=head1 Description

Provide common methods for subclasses

=head1 Subroutines/Methods

=head2 COMPONENT

The constructor stores a copy of the application instance for future
reference. It does this to remain compatible with L<Catalyst::Controller>
whose constructor is no longer called

=head2 bad_request

Sets the response body to the provided error message and the response
status to 400

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

=head2 process

Serializes the response using L<XML::Simple> and encodes the body using
L<Encode> if required

=head1 Private Methods

=head2 _build_widgets

Calls C<build> in L<HTML::FormWidgets> which transforms the widgets
definitions into fragments of HTML or XHTML as required

=head2 _prepare_data

Called by L</process> this method is responsible for
selecting those elements from the stash that are passed to
the serializer method

=head2 _read_form_sources

Returns an array ref widget references in the stash. Can be passed to
L</_build_widgets> or its output can be sent directly to the serializer

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Catalyst::View>

=item L<CatalystX::Usul>

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
