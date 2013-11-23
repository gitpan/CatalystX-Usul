# @(#)Ident: ;

package CatalystX::Usul::Model::UserProfiles;

use strict;
use version; our $VERSION = qv( sprintf '0.14.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(is_member throw);
use TryCatch;

extends q(CatalystX::Usul::Model);
with    q(CatalystX::Usul::TraitFor::Model::StashHelper);
with    q(CatalystX::Usul::TraitFor::Model::QueryingRequest);

has '+domain_class'     => default => q(CatalystX::Usul::UserProfiles);

has 'role_model_class'  => is => 'ro',   isa => NonEmptySimpleStr,
   default              => q(RolesUnix);

has 'shells_attributes' => is => 'ro',   isa => HashRef, default => sub { {} };

has 'shells_class'      => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default              => sub { 'CatalystX::Usul::Shells' };


has '_role_model'       => is => 'lazy', isa => Object, init_arg => undef,
   reader               => 'role_model', weak_ref => TRUE;

has '_shells_domain'    => is => 'lazy', isa => Object, init_arg => undef,
   reader               => 'shells_domain';

sub build_per_context_instance {
   my ($self, $c, @rest) = @_; my $clone = $self->next::method( $c, @rest );

   my $attr = { %{ $clone->domain_attributes }, builder => $clone->usul, };

   $attr->{storage_attributes}->{encoding} ||= $clone->encoding;
   $clone->domain_model( $clone->domain_class->new( $attr ) );
   return $clone;
}

sub create_or_update {
   my $self   = shift;
   my $dm     = $self->domain_model;
   my $fields = $self->query_value_by_fields( @{ $dm->source->attributes } );
   my $name   = $fields->{name} = $self->query_value( q(name) );
   my $s      = $self->context->stash;
   my $method = $self->query_value( $dm->source_name ) eq $s->{newtag}
              ? q(create) : q(update);
   my $msg    = $method eq q(create)
              ? 'Profile [_1] created' : 'Profile [_1] updated';

   $name or throw 'Profile not specified';
   $self->domain_model->$method( $self->check_form( $fields ) );
   $self->add_result_msg( $msg, [ $name ] );
   return $name;
}

sub delete {
   my $self = shift;
   my $dm   = $self->domain_model;
   my $name = $self->query_value( $dm->source_name )
      or throw 'Profile not specified';

   $dm->delete( $name );
   $self->add_result_msg( 'Profile [_1] deleted', [ $name ] );
   return;
}

sub find {
   return shift->domain_model->find( @_ );
}

sub list {
   return shift->domain_model->list( @_ );
}

sub user_profiles_form {
   my ($self, $profile) = @_; my $c = $self->context; my $s = $c->stash;

   my ($def_shell, $profile_list, $profile_obj, $profiles, $roles, $shells);

   try { # Retrieve data from the domain model
      $profile    ||= NUL;
      $profile_list = $self->list( $profile );
      $profile_obj  = $profile_list->result;
      $profiles     = [ NUL, $s->{newtag}, @{ $profile_list->list } ];
      $roles        = [ NUL, grep { not is_member $_, $profiles }
                             $self->role_model->get_roles( q(all) ) ];
      $def_shell    = $self->shells_domain->default;
      $shells       = $self->shells_domain->shells;
   }
   catch ($e) { return $self->add_error( $e ) }

   my $form        = $s->{form}->{name};
   my $common_home = $c->config->{common_home};
   my $moniker     = $self->domain_model->source_name;
   my $name        = $self->query_value( q(name) ) || NUL;
   my $first_fld   = $profile eq $s->{newtag} && !$name ? "${form}.name"
                   :                              $name ? "${form}.desc"
                   :                                      "${form}.${moniker}";

   # Add fields to form
   $self->clear_form( { firstfld => $first_fld } );
   $self->add_field ( { default  => $profile,
                        id       => "${form}.${moniker}",
                        labels   => $profile_list->labels,
                        values   => $profiles } );

   if ($profile) {
      if ($profile eq $s->{newtag}) {
         $self->add_field( { default => $name,
                             id      => "${form}.name",
                             values  => $roles } );
      }
      else {
         $self->add_field ( { id => "${form}.group_name" } );
         $self->add_hidden( 'name', $profile );
         $s->{profile} = $profile;
      }

   }

   $self->group_fields( { id      => "${form}.select" } );

   (not $profile or (not $name and $profile eq $s->{newtag})) and return;

   $self->add_field   ( { default => $profile_obj->desc,
                          id      => "${form}.desc" } );
   $self->add_field   ( { default => $profile_obj->passwd,
                          id      => "${form}.passwd" } );
   $self->add_field   ( { default => $profile_obj->baseid,
                          id      => "${form}.baseid" } );
   $self->add_field   ( { default => $profile_obj->increment,
                          id      => "${form}.increment" } );
   $self->add_field   ( { default => $profile_obj->homedir,
                          id      => "${form}.homedir" } );
   $self->add_field   ( { default => $profile_obj->permissions,
                          id      => "${form}.permissions" } );
   $self->add_field   ( { default => $profile_obj->shell || $def_shell,
                          id      => "${form}.shell",
                          values  => $shells } );
   $self->add_field   ( { default => $profile_obj->roles,
                          id      => "${form}.roles" } );
   $self->add_field   ( { default => $profile_obj->printer,
                          id      => "${form}.printer" } );
   $self->add_field   ( { default => $profile_obj->server,
                          id      => "${form}.server" } );
   $self->add_field   ( { default => $profile_obj->prefix,
                          id      => "${form}.prefix" } );
   $self->add_field   ( { default => $profile_obj->pattern,
                          id      => "${form}.pattern" } );
   $self->add_field   ( { default => $profile_obj->project,
                          id      => "${form}.project" } );
   $self->add_field   ( { default => $profile_obj->common_home || $common_home,
                          id      => "${form}.common_home" } );
   $self->group_fields( { id      => "${form}.edit" } );

   # Add buttons to form
   if ($profile eq $s->{newtag}) { $self->add_buttons( qw(Insert) ) }
   else { $self->add_buttons( qw(Save Delete) ) }

   return;
}

# Private methods

sub _build__role_model {
   return $_[ 0 ]->context->model( $_[ 0 ]->role_model_class );
}

sub _build__shells_domain {
   return $_[ 0 ]->shells_class->new( $_[ 0 ]->shells_attributes );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::UserProfiles - CRUD methods for user account profiles

=head1 Version

Describes v0.14.$Rev: 1 $

=head1 Synopsis

   package YourApp;

   use Catalyst qw(ConfigComponents...);

   __PACKAGE__->config( 'Model::UserProfiles' => {
      parent_classes => 'CatalystX::Usul::Model::UserProfiles' } );


=head1 Description

These methods maintain the user account profiles used by the identity
class to create new user accounts. This class inherits from
L<CatalystX::Usul::Model>. Data is stored in the F<user_profiles.json> file
in the C<ctrldir>

=head1 Configuration and Environment

Defines the following list of attributes

=over 3

=item domain_class

Overrides the default value in the base class with
C<CatalystX::Usul::UserProfiles>

=item role_model_class

A string which defaults to C<RolesUnix>

=item shells_attributes

A hash ref used to construct the shells domain object

=item shells_class

A loadable class which defaults to C<CatalystX::Usul::Shells>

=back

=head1 Subroutines/Methods

=head2 build_per_context_instance

   $clone = $self->build_per_context_instance( $c, @rest );

Clones an instance if the domain model, caches copies of the role model
and the shells model on the clone

=head2 create_or_update

   $profile_name = $self->create_or_update;

Creates a new user account profile or updates an existing one. Field
data is extracted from the request object. The result message is
written to the stash

=head2 delete

   $self->delete;

Delete the selected user account profile. The name of the profile to
delete is extracted from the request object. The result message is
written to the stash

=head2 find

   $profile_obj = $self->find( $profile_name );

Returns a L<File::DataClass::Result> object for the wanted
profile

=head2 list

   $profile_list_obj = $self->list( $profile_name );

Returns a L<File::DataClass::List> object whose C<list>
attribute is an array ref of account profile names. If a profile name
is given it also returns a L<File::DataClass::Result> object
for that profile

=head2 user_profiles_form

   $self->user_profiles_form( $profile_name );

Stuffs the stash with the data to generate the profile editing form

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::TraitFor::Model::QueryingRequest>

=item L<CatalystX::Usul::TraitFor::Model::StashHelper>

=item L<CatalystX::Usul::Moose>

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
