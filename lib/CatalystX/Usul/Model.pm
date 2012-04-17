# @(#)$Id: Model.pm 1181 2012-04-17 19:06:07Z pjf $

package CatalystX::Usul::Model;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.7.%d', q$Rev: 1181 $ =~ /\d+/gmx );
use parent qw(Catalyst::Model CatalystX::Usul CatalystX::Usul::Encoding);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(app_prefix is_arrayref throw);
use Data::Validation;
use MRO::Compat;
use Scalar::Util qw(blessed refaddr weaken);
use TryCatch;

__PACKAGE__->config( scrubbing => FALSE, scrub_chars => q([\'\"/\:]) );

__PACKAGE__->mk_accessors( qw(context domain_attributes domain_class
                              domain_model scrubbing scrub_chars) );

__PACKAGE__->mk_encoding_methods( qw(_get_req_array _get_req_value) );

sub COMPONENT {
   my ($class, $app, $config) = @_; $class->_setup_plugins( $app );

   my $comp = $class->next::method( $app, $config );
   my $usul = CatalystX::Usul->new( $app, {} );

   for (grep { not defined $comp->{ $_ } } keys %{ $usul }) {
      $comp->{ $_ } = $usul->{ $_ }; # Attribute mixin
   }

   return $comp;
}

sub ACCEPT_CONTEXT {
   my ($self, $c, @rest) = @_;

   blessed $c or return $self->build_per_context_instance( $c, @rest );

   my $s   = $c->stash;
   my $key = q(__InstancePerContext_).(blessed $self ? refaddr $self : $self);

   return $s->{ $key } ||= $self->build_per_context_instance( $c, @rest );
}

sub build_per_context_instance {
   my ($self, $c, @rest) = @_;

   my $attrs = { ref $self ? %{ $self } : () }; # Clone self
   my $new   = bless $attrs, blessed $self || $self;

   if (blessed $c) { $new->{context} = $c; weaken( $new->{context} ) }

   return $new;
}

sub check_field {
   my ($self, $id, $value) = @_;

   return $self->_validator->check_field( $id, $value );
}

sub check_form  {
   my ($self, $form) = @_; my $c = $self->context; my $s = $c->stash;

   my $prefix = ($s->{form}->{name} || app_prefix blessed $self).q(.);

   try        { $form = $self->_validator->check_form( $prefix, $form ) }
   catch ($e) {
      my $last = pop @{ $e->args }; $c->error( $e->args ); throw $last;
   }

   return $form;
}

sub form {
   my ($self, @rest) = @_; my $s = $self->context->stash;

   my $method = $s->{form}->{name}.q(_form);

   return $self->$method( @rest );
}

sub loc {
   my ($self, @rest) = @_;

   return $self->next::method( $self->context->stash, @rest );
}

sub query_array {
   my ($self, @rest) = @_; return $self->_query_by_type( q(array), @rest );
}

sub query_value {
   my ($self, @rest) = @_; return $self->_query_by_type( q(value), @rest );
}

sub query_value_by_fields {
   my ($self, @fields) = @_;

   return { map  { $_->[ 0 ] => $_->[ 1 ]           }
            grep { defined $_->[ 1 ]                }
            map  { [ $_, $self->query_value( $_ ) ] } @fields };
}

sub scrub {
   my ($self, $value) = @_; defined $value or return;

   my $pattern = $self->scrub_chars; $value =~ s{ $pattern }{}gmx;

   return $value;
}

# Private methods

sub _get_req_array {
   my ($self, $attr) = @_;

   my $value = $self->context->req->params->{ $attr || NUL };

   $value = defined $value ? $value : [];

   is_arrayref $value or $value = [ $value ];

   return $value;
}

sub _get_req_value {
   my ($self, $attr) = @_;

   my $value = $self->context->req->params->{ $attr || NUL };

   is_arrayref $value and $value = $value->[ 0 ];

   return $value;
}

sub _query_by_type {
   my ($self, $type, @rest) = @_;

   (my $enc   = lc ($self->encoding || q(guess))) =~ s{ [-] }{_}gmx;
   my $method = q(_get_req_).$type.q(_).$enc.q(_encoding);
   my $value  = $self->$method( @rest );

   $self->scrubbing or return $value;

   unless ($type eq q(array)) { $value = $self->scrub( $value ) }
   else { @{ $value } = map { $self->scrub( $_ ) } @{ $value } }

   return $value;
}

sub _setup_plugins {
   my ($self, $app) = @_; my $plugins;

   $plugins = __PACKAGE__->get_inherited( q(_m_plugins) ) and return $plugins;

   my $config = { search_paths => [ q(::Plugin::Model) ],
               %{ $app->config->{ setup_plugins } || {} } };

   $plugins = __PACKAGE__->setup_plugins( $config );

   return __PACKAGE__->set_inherited( q(_m_plugins), $plugins );
}

sub _validator {
   my $self  = shift;
   my $s     = $self->context->stash;
   my $attrs = { exception   => EXCEPTION_CLASS,
                 constraints => $s->{constraints} || {},
                 fields      => $s->{fields     } || {},
                 filters     => $s->{filters    } || {} };

   return Data::Validation->new( $attrs );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model - Interface model base class

=head1 Version

0.7.$Revision: 1181 $

=head1 Synopsis

   package CatalystX::Usul;
   use parent qw(CatalystX::Usul::Base CatalystX::Usul::File);

   package CatalystX::Usul::Model;
   use parent qw(Catalyst::Model CatalystX::Usul CatalystX::Usul::IPC);

   package YourApp::Model::YourModel;
   use parent qw(CatalystX::Usul::Model);

=head1 Description

Common core interface model methods

=head1 Subroutines/Methods

=head2 COMPONENT

Defines the following accessors:

=over 3

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
that we don't have to pass C<< $c->stash >> into L<CatalystX::Usul/loc>

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

   $local_text = $self->loc( $key, $args );

Localizes the message. Calls L<CatalystX::Usul/loc>

=head2 query_array

   $array_ref = $self->query_array( $attr );

Returns the requested parameter in a list context. Uses the
B<encoding> attribute to generate the method call to decode the input
values. The decode method is provided by
L<CatalystX::Usul::Encoding>. Will try to guess the encoding if one is
not provided

=head2 query_value

   $scalar_value = $self->query_value( $attr );

Returns the requested parameter in a scalar context. Uses B<encoding>
attribute to generate the method call to decode the input value. The
decode method is provided by L<CatalystX::Usul::Encoding>. Will try to
guess the encoding if one is not provided

=head2 query_value_by_fields

   $hash_ref = $self->query_value_by_fields( @fields );

Returns a hash_ref of fields and their values if the values are
defined by the request. Calls L</query_value> for each of supplied
fields

=head2 scrub

   $value = $self->scrub( $value );

Removes the C<< $self->scrub_chars >> from the value

=head2 _get_req_array

   my $array_ref = $self->_get_req_array( $attr );

Takes a request object that must implement a C<params> method which
returns a hash ref. The method returns the value for C<$attr> from
that hash. This method will always return a array ref. This method is
wrapped by L<Catalystx::Usul::Encoding/mk_encoding_methods>
and as such is not called directly

=head2 _get_req_value

   my $value = $self->_get_req_value( $attr );

Takes a request object that must implement a C<params> method which
returns a hash ref. The method returns the value for C<$attr> from
that hash. This method will always return a scalar. This method is
wrapped by L<Catalystx::Usul::Encoding/mk_encoding_methods>
and as such is not called directly

=head1 Configuration and Environment

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Catalyst::Model>

=item L<CatalystX::Usul>

=item L<CatalystX::Usul::Encoding>

=item L<CatalystX::Usul::IPC>

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

Copyright (c) 2008-2009 Peter Flanigan. All rights reserved

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
