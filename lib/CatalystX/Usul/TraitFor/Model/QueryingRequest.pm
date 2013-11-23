# @(#)Ident: QueryingRequest.pm 2013-08-19 19:19 pjf ;

package CatalystX::Usul::TraitFor::Model::QueryingRequest;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.14.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Moose::Role;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions   qw(app_prefix throw);
use MooseX::AttributeShortcuts;
use MooseX::Types::LoadableClass qw(LoadableClass);
use MooseX::Types::Moose         qw(HashRef Object);
use TryCatch;

requires qw(context usul);

has 'query_attributes' => is => 'lazy', isa => HashRef, default => sub { {} };

has 'query_class'      => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default             => sub { 'CatalystX::Usul::QueryRequest' };

has 'query'            => is => 'lazy', isa => Object,
   handles             => [ qw(query_array query_value
                               query_hash  query_value_by_fields) ],
   init_arg            => undef;

has 'validator_class'  => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default             => sub { 'Data::Validation' };

sub check_field {
   return shift->_build_validator->check_field( @_ );
}

sub check_field_wrapper { # Process Ajax calls to validate form field values
   my $self = shift;
   my $id   = $self->query_value( q(id)  );
   my $val  = $self->query_value( q(val) );
   my $msg;

   $self->stash_meta( { id => "${id}_ajax", result => NUL } );

   try        { $self->check_field( $id, $val ) }
   catch ($e) {
      $self->stash_meta( { class_name => q(error) } );
      $self->stash_content( $msg = $self->loc( $e->error, $e->args ) );
      $self->context->stash->{debug} and $self->log->debug( $msg );
   }

   return;
}

sub check_form  {
   my ($self, $form) = @_; my $c = $self->context; my $s = $c->stash;

   my $prefix = ($s->{form}->{name} || app_prefix blessed $self).q(.);

   try        { $form = $self->_build_validator->check_form( $prefix, $form ) }
   catch ($e) {
      my $last = pop @{ $e->args }; $c->error( $e->args ); throw $last;
   }

   return $form;
}

sub deserialize_request { # Deserialize the request if necessary
   my $self = shift; my $c = $self->context; my $s = $c->stash;

   my $verb = $s->{verb}; my $view = $c->view( $s->{current_view } );

   my %methods = ( options => 1, post => 1, put => 1, );

   return $verb && $methods{ $verb } ? $view->deserialize( $s, $c->req ) : NUL;
}

# Private methods

sub _build_query {
   my $self = shift; my $encoding = $self->usul->config->encoding;

   my $attr = { encoding => $encoding, %{ $self->query_attributes },
                model    => $self, };

   return $self->query_class->new( $attr );
}

sub _build_validator {
   my $self = shift; my $s = $self->context->stash;

   my $attr = { exception   => EXCEPTION_CLASS,
                constraints => $s->{constraints} || {},
                fields      => $s->{fields     } || {},
                filters     => $s->{filters    } || {} };

   return $self->validator_class->new( $attr );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TraitFor::Model::QueryingRequest - Creates a query request object

=head1 Version

Describes v0.14.$Rev: 1 $

=head1 Synopsis

   package YourApp::Model::YourModel;

   extends q(CatalystX::Usul::Model);
   with    q(CatalystX::Usul::TraitFor::Model::QueryingRequest);

=head1 Description

Creates a L<CatalystX::Usul::QueryRequest> object and on demand a
L<Data::Validation> object

=head1 Configuration and Environment

Requires; C<context> and C<usul> attributes

Defines the following attributes

=over 3

=item query_attributes

Hash ref which defaults to C<< { encoding => $_[ 0 ]->encoding } >>

=item query_class

Defaults to L<CatalystX::Usul::QueryRequest>

=item query

An instance of L<CatalystX::Usul::QueryRequest>

=item validator_class

Loadable class which defaults to L<Data::Validation>

=back

=head1 Subroutines/Methods

=head2 check_field

   $self->check_field( $id, $val );

Expose L<Data::Validation/check_field>

=head2 check_field_wrapper

   $self->check_field_wrapper;

Extract parameters from the query and call L</check_field>. Stash the result

=head2 check_form

   $fields = $self->check_form( \%fields );

Expose L<Data::Validation/check_form>

=head2 deserialize_request

   $request_body = $model_obj->deserialze_request;

Call the deserialize method on the current view

=head2 _build_query

   $query_request_object = $self->_build_query;

Create in instance of L<CatalystX::Usul::QueryRequest>. Uses the current
request object so this is called to instantiate the C<query> attribute
at the end of C<build_per_context_instance>

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::QueryRequest>

=item L<Data::Validation>

=item L<Moose::Role>

=item L<TryCatch>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

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
