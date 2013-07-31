# @(#)$Id: View.pm 1320 2013-07-31 17:31:20Z pjf $

package CatalystX::Usul::View;

use strict;
use version; our $VERSION = qv( sprintf '0.8.%d', q$Rev: 1320 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions   qw(exception is_arrayref is_hashref throw);
use CatalystX::Usul::Constraints qw(Directory);
use Scalar::Util                 qw(weaken);
use Template;
use TryCatch;
use Encode;

extends q(Catalyst::View);
with    q(CatalystX::Usul::TraitFor::BuildingUsul);

has 'deserialize_attrs' => is => 'ro',   isa => HashRef, default => sub { {} };

has 'form_sources'      => is => 'ro',   isa => ArrayRef,
   default              => sub { [ qw(sdata hidden) ] };

has 'js_object'         => is => 'ro',   isa => NonEmptySimpleStr,
   default              => q(behaviour);

has 'serialize_attrs'   => is => 'ro',   isa => HashRef, default => sub { {} };

has 'template_dir'      => is => 'ro',   isa => Directory, coerce => TRUE;

has 'usul'              => is => 'lazy', isa => BaseClass,
   handles              => [ qw(debug encoding log) ];

has 'widget_class'      => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default              => sub { 'HTML::FormWidgets' };

sub bad_request {
   my ($self, $c, $verb, $msg, $status) = @_; $status ||= 400;

   $c->res->body( $msg );
   $c->res->content_type( q(text/plain) );
   $c->res->status( $status );
   return FALSE;
}

sub deserialize {
   my ($self, $s, $req, $process) = @_; my $body; $s->{leader} = blessed $self;

   if ($body = $req->body) {
      try        { return $process->( $self->deserialize_attrs, $body ) }
      catch ($e) { $self->log->error_message( $s, (exception $e) ) }
   }
   else {
      $self->debug
         and $self->log->debug_message( $s, 'Nothing to deserialize' );
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

sub loc { # Localize the key and substitute the placeholder args
   my ($self, $opts, $key, @args) = @_; my $car = $args[ 0 ];

   my $args = (is_hashref $car) ? { %{ $car } }
            : { params => (is_arrayref $car) ? $car : [ @args ] };

   $args->{domain_names} ||= [ DEFAULT_L10N_DOMAIN, $opts->{ns} ];
   $args->{locale      } ||= $opts->{language};

   return $self->usul->localize( $key, $args );
}

sub not_implemented {
   return shift->bad_request( @_, 404 );
}

sub prepare_data {
   my ($self, $c) = @_;

   my $data = $self->read_form_sources( $c ) || [];
   my $s    = $c->stash; $s->{EOT} = $s->{is_xml} ? q( />) : q(>);
   my $loc  = sub { return $self->loc( $s, @_ ) };
   my $tt   = Template->new( { VARIABLES => { loc => $loc }, } )
      or throw $Template::ERROR;

   for my $source (@{ $data }) {
      my $id = 0;

      for my $item (grep { $_->{content} } @{ $source->{items} }) {
         my $content = $item->{content};

         if (is_hashref $content and exists $content->{text}) {
            $item->{content}->{text}
               = __tt_process( $tt, $s, \$content->{text} );
         }
         else { $item->{content} = __tt_process( $tt, $s, \$content ) }

         $item->{id} //= $id; $id++;
      }

      $source->{count} = scalar @{ $source->{items} };
   }

   $data->[ 1 ] or return $data->[ 0 ];

   for my $source (map { $data->[ $_ ] } 1 .. $#{ $data }) {
      push @{ $data->[ 0 ]->{items} || [] }, @{ $source->{items} || [] };
   }

   $data->[ 0 ]->{count} = scalar @{ $data->[ 0 ]->{items} || [] };

   return $data->[ 0 ];
}

sub process {
   my ($self, $c) = @_; my $s = $c->stash; my $type = $s->{content_type};

   try {
      my $attr = { %{ $self->serialize_attrs }, content_type => $type };
      my $body = $self->serialize( $attr, $self->prepare_data( $c ) );

      if (my $enc = $self->encoding) { # Encode the body of the page
         $body = encode( $enc, $body ); $type .= "; charset=${enc}";
      }

      $c->res->body( $body );
      $c->res->content_type( $type );
      $c->res->header( Vary => q(Content-Type) );
   }
   catch ($e) {
      my $body = "Serializer ${type} failed\r\n***ERROR***\r\n";

      $self->bad_request( $c, $s->{verb}, $body.(exception $e) );
   }

   return TRUE;
}

sub read_form_sources {
   my ($self, $c) = @_; my $s = $c->stash;

   my $sources = $self->form_sources || []; my $data = [];

   for my $part (map { $s->{ $_ } } grep { $s->{ $_ } } @{ $sources }) {
      unless (is_arrayref $part and $part->[ 0 ]) { push @{ $data }, $part }
      else { push @{ $data }, $_ for (@{ $part }) }
   }

   return $data;
}

# Private methods

sub _build_widgets {
   my ($self, $c, $args) = @_; my $s = $c->stash;

   my $attr = { %{ $args || {} } };
   my @attr = ( qw(assets content_type fields hidden
                   language literal_js ns optional_js pwidth width) );

   $attr->{ $_         } = $s->{ $_ } for (@attr);
   $attr->{base        } = $c->req->base;
   $attr->{js_object   } = $self->js_object;
   $attr->{l10n        } = sub { $self->loc( @_ ) };
   $attr->{root        } = $c->config->{root};
   $attr->{template_dir} = $self->template_dir;

   $self->widget_class->build( $attr );
   return;
}

# Private subroutines

sub __tt_process {
   my ($tt, $s, $in) = @_; my $out;

   $tt->process( $in, $s, \$out ) or throw $tt->error;

   return $out;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::View - Base class for views

=head1 Version

0.8.$Revision: 1320 $

=head1 Synopsis

   package YourApp::View::HTML;

   use CatalystX::Usul::Moose;

   extends qw(CatalystX::Usul::View::HTML);


   package YourApp::View::JSON;

   use CatalystX::Usul::Moose;

   extends qw(CatalystX::Usul::View::JSON);

=head1 Description

Provide common methods for view component subclasses

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

=head2 loc

   $localized_text = $self->loc( $c->stash, $key, @options );

Localizes the message. Calls L<Class::Usul::L10N/localize>. Adds the
constant C<DEFAULT_L10N_DOMAINS> to the list of domain files that are
searched. Adds C<< $c->stash->language >> and C<< $c->stash->namespace >>
(search domain) to the arguments passed to C<localize>

=head2 not_implemented

Sets the response body to the provided error message and the response
status to 405

=head2 prepare_data

   $hash_ref = $self->prepare_data( $c );

Called by L</process> this method is responsible for
selecting those elements from the stash that are passed to
the serializer method

=head2 process

Serializes the response using L<XML::Simple> and encodes the body using
L<Encode> if required

=head2 read_form_sources

Returns an array ref widget references in the stash. Can be passed to
L</_build_widgets> or its output can be sent directly to the serializer

=head1 Private Methods

=head2 _build_widgets

Calls C<build> in L<HTML::FormWidgets> which transforms the widgets
definitions into fragments of HTML or XHTML as required

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Catalyst::View>

=item L<Class::Usul>

=item L<CatalystX::Usul::Moose>

=item L<Encode>

=item L<CatalystX::Usul::Constraints>

=item L<HTML::FormWidgets>

=item L<Template>

=item L<TryCatch>

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

Copyright (c) 2013 Peter Flanigan. All rights reserved

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
