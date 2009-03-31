package CatalystX::Usul::Model;

# @(#)$Id: Model.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul CatalystX::Usul::Utils);
use Class::C3;
use Data::Validation;
use Scalar::Util qw(blessed refaddr weaken);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

__PACKAGE__->config( screensaver => q(xdg-screensaver lock),
                     scrub_chars => q([\'\"/\\;:]) );

__PACKAGE__->mk_encoding_methods( qw(_get_req_array _get_req_value) );

__PACKAGE__->mk_accessors( qw(context screensaver scrubbing scrub_chars) );

sub new {
   my ($self, $app, @rest) = @_; my $class = ref $self || $self;

   $class->_setup_plugins( $app );

   my $new      = $self->next::method( $app, @rest );
   my $app_conf = $app->config || {};

   $new->scrubbing( $new->scrubbing || $app_conf->{scrubbing} || 0 );

   return $new;
}

sub ACCEPT_CONTEXT {
   my ($self, $c, @rest) = @_;

   return $self->build_per_context_instance( $c, @rest ) unless ref $c;

   my $key = blessed $self ? refaddr $self : $self;

   return $c->stash->{ "__InstancePerContext_${key}" }
             ||= $self->build_per_context_instance( $c, @rest );
}

sub build_per_context_instance {
   my ($self, $c, @rest) = @_;

   my $new = bless { %{ $self } }, ref $self;

   if (ref $c) { $new->{context} = $c; weaken( $new->{context} ) }

   return $new;
}

sub check_field {
   my ($self, @rest) = @_; my $s = $self->context->stash;

   my $config = { exception   => q(CatalystX::Usul::Exception),
                  constraints => $s->{constraints} || {},
                  fields      => $s->{fields}      || {},
                  filters     => $s->{filters}     || {} };
   my $dv     = Data::Validation->new( %{ $config } );

   return $dv->check_field( @rest );
}

sub check_form  {
   my ($self, @rest) = @_; my $s = $self->context->stash;

   my $config = { exception   => q(CatalystX::Usul::Exception),
                  constraints => $s->{constraints} || {},
                  fields      => $s->{fields}      || {},
                  filters     => $s->{filters}     || {} };
   my $dv     = Data::Validation->new( %{ $config } );
   my $form   = $s->{form}->{name} || $self->app_prefix( ref $self );

   return $dv->check_form( $form.q(.), @rest );
}

sub form {
   my ($self, @rest) = @_; my $s = $self->context->stash;

   my $method = $s->{form}->{name}.q(_form);

   return $self->$method( @rest );
}

*loc = \&localize;

sub localize {
   my ($self, @rest) = @_; my $s = $self->context->stash;

   $self->content_type( $s->{content_type} || q(text/html) );
   $self->messages(     $s->{messages    } || {} );

   return $self->next::method( @rest );
}

sub lock_display {
   # TODO: Move this to a plugin
   my ($self, $display) = @_;

   $self->run_cmd( $self->screensaver, { err => q(out) } );
   return;
}

sub query_array {
   return shift->_query_array_or_value( q(array), @_ );
}

sub query_value {
   return shift->_query_array_or_value( q(value), @_ );
}

sub scrub {
   my ($self, $value) = @_; my $pattern = $self->scrub_chars;

   $value =~ s{ $pattern }{}gmx;

   return $value;
}

sub uri_for {
   my ($self, @rest) = @_; return $self->next::method( $self->context, @rest );
}

# Private methods

sub _get_req_array {
   my ($self, $fld) = @_; $fld ||= q();

   my $value = $self->context->req->params->{ $fld };

   $value = defined $value ? $value : [];

   $value = [ $value ] unless (ref $value eq q(ARRAY));

   return $value;
}

sub _get_req_value {
   my ($self, $fld) = @_; $fld ||= q();

   my $value = $self->context->req->params->{ $fld };

   $value = $value->[ 0 ] if ($value && ref $value eq q(ARRAY));

   return $value;
}

sub _query_array_or_value {
   my ($self, $type, @rest) = @_;

   (my $enc   = lc ($self->encoding || q(guess))) =~ s{ [-] }{_}gmx;
   my $method = q(_get_req_).$type.q(_).$enc.q(_encoding);
   my $value  = $self->$method( @rest );

   if ($self->scrubbing) {
      unless ($type eq q(array)) { $value = $self->scrub( $value ) }
      else { @{ $value } = map { $self->scrub( $_ ) } @{ $value } }
   }

   return $value;
}

sub _setup_plugins {
   my ($self, $app) = @_;

   unless (__PACKAGE__->get_inherited( q(_m_plugins) )) {
      my $config  = { search_paths => [ qw(::Plugin::Model ::Plugin::M) ],
                      %{ $app->config->{ setup_plugins } || {} } };
      my $plugins = __PACKAGE__->setup_plugins( $config );

      __PACKAGE__->set_inherited( q(_m_plugins), $plugins );
   }

   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model - Application independent common model methods

=head1 Version

0.1.$Revision: 402 $

=head1 Synopsis

   package CatalystX::Usul;
   use parent qw(Catalyst::Component CatalystX::Usul::Base);

   package CatalystX::Usul::Model;
   use parent qw(CatalystX::Usul CatalystX::Usul::Utils);

   package YourApp::Model::YourModel;
   use parent qw(CatalystX::Usul::Model);

=head1 Description

Common core model methods

=head1 Subroutines/Methods

=head2 new

Defines the following accessors:

=over 3

=item screensaver

The external command to execute to lock the display. Defaults to one that
works with KDE as the window manager. Should move this to a plugin
because its silly

=item scrubbing

Boolean used by L</query_array> and L</query_value> to determine if input
value should be cleaned of potentially dangerous characters

=item scrub_chars

List of characters to scrub from input values. Defaults to '"/\;

=back

Loads model plugins including;

=over 3

=item L<CatalystX::Usul::Plugin::Model::StashHelper>

=back

=head2 ACCEPT_CONTEXT

Calls L</build_per_context_instance> for each new context

=head2 build_per_context_instance

Called by L</ACCEPT_CONTEXT>. Takes a copy of the Catalyst object so
that we don't have to pass C<$c> into L<CatalystX::Usul/get_action>,
L<CatalystX::Usul/localize> and L<CatalystX::Usul/uri_for>

=head2 check_field

   $self->check_field( $id, $val );

Expose L<Data::Validation/check_field>

=head2 check_form

   $self->check_form( \%fields );

Expose L<Data::Validation/check_form>

=head2 form

   $self->form( @rest );

Calls the form method to stuff the stash with the data for the
requested form. Uses the C<< $c->stash->{form}->{name} >> value to
construct the method name

=head2 loc

=head2 localize

   $local_text = $self->localize( $message, $args );

Localizes the message. Optionally calls C<markdown> on the text

=head2 lock_display

Locks the display by running the external screensaver command

=head2 query_array

Returns the requested parameter in a list context. Uses the
B<encoding> attribute to generate the method call to decode the input
values. The decode method is provided by
L<CatalystX::Usul::Encoding>. Will try to guess the encoding if one is
not provided

=head2 query_value

Returns the requested parameter in a scalar context. Uses B<encoding>
attribute to generate the method call to decode the input value. The
decode method is provided by L<CatalystX::Usul::Encoding>. Will try to
guess the encoding if one is not provided

=head2 scrub

   $value = $self->scrub( $value );

Removes the C<< $self->scrub_chars >> from the value

=head2 uri_for

   $uri = $self->uri_for( $action_path, @args );

Provide defaults for the L<Catalyst> C<uri_for> method. Search for the uri
with differing numbers of capture args

=head2 _get_req_array

   my $array_ref = $self->_get_req_array( $field );

Takes a request object that must implement a C<params> method which
returns a hash ref. The method returns the value for C<$field> from
that hash. This method will always return a array ref. This method is
wrapped by C<Catalystx::Usul::Encoding::mk_encoding_methods>
and as such is not called directly

=head2 _get_req_value

   my $value = $self->_get_req_value( $field );

Takes a request object that must implement a C<params> method which
returns a hash ref. The method returns the value for C<$field> from
that hash. This method will always return a scalar. This method is
wrapped by C<Catalystx::Usul::Encoding::mk_encoding_methods>
and as such is not called directly

=head1 Configuration and Environment

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul>

=item L<CatalystX::Usul::Utils>

=item L<Data::Validation>

=item L<Scalar::Util>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module.

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
