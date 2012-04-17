# @(#)$Id: UserProfiles.pm 1181 2012-04-17 19:06:07Z pjf $

package CatalystX::Usul::Model::UserProfiles;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.7.%d', q$Rev: 1181 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(is_member throw);
use CatalystX::Usul::UserProfiles;
use CatalystX::Usul::Shells;
use MRO::Compat;
use Scalar::Util qw(weaken);
use TryCatch;

__PACKAGE__->config( domain_class      => q(CatalystX::Usul::UserProfiles),
                     role_class        => q(RolesUnix),
                     shells_attributes => {},
                     shells_class      => q(CatalystX::Usul::Shells),
                     source_name       => q(profile) );

__PACKAGE__->mk_accessors( qw(role_class role_model shells_attributes
                              shells_class shells_domain source_name) );

sub build_per_context_instance {
   my ($self, $c, @rest) = @_;

   my $new   = $self->next::method( $c, @rest );
   my $attrs = { %{ $new->domain_attributes || {} }, ioc_obj => $new };

   $attrs->{path} ||= $c->config->{profiles_path};
   $new->domain_model( $new->domain_class->new( $attrs ) );
   $new->role_model  ( $c->model( $new->role_class ) );
   weaken( $new->{role_model} );
   $attrs = { %{ $new->shells_attributes || {} } };
   $new->shells_domain( $self->shells_class->new( $c, $attrs ) );

   return $new;
}

sub create_or_update {
   my $self    = shift;
   my $name    = $self->query_value( q(name) ) or throw 'Profile not specified';
   my @fields  = @{ $self->domain_model->source->attributes };
   my $fields  = $self->query_value_by_fields( @fields );
   my $newtag  = $self->context->stash->{newtag};
   my $method  = $self->query_value( $self->source_name ) eq $newtag
               ? q(create) : q(update);
   my $msg     = $method eq q(create)
               ? 'Profile [_1] created' : 'Profile [_1] updated';

   $fields->{name} = $name;
   $self->domain_model->$method( $self->check_form( $fields ) );
   $self->add_result_msg( $msg, [ $name ] );
   return $name;
}

sub delete {
   my $self = shift;
   my $name = $self->query_value( $self->source_name )
      or throw 'Profile not specified';

   $self->domain_model->delete( $name );
   $self->add_result_msg( 'Profile [_1] deleted', [ $name ] );
   return;
}

sub find {
   my ($self, $name) = @_; return $self->domain_model->find( $name );
}

sub list {
   my ($self, $name) = @_; return $self->domain_model->list( $name );
}

sub user_profiles_form {
   my ($self, $profile) = @_; my $s = $self->context->stash; $profile ||= NUL;

   my ($def_shell, $profile_list, $profile_obj);
   my ($profiles, $roles, $shells, $shells_obj);

   # Retrieve data from model
   try {
      $profile_list = $self->list( $profile );
      $profile_obj  = $profile_list->result;
      $profiles     = [ NUL, $s->{newtag}, @{ $profile_list->list } ];
      $roles        = [ NUL, grep { not is_member $_, $profiles }
                             $self->role_model->get_roles( q(all) ) ];
      $shells_obj   = $self->shells_domain->retrieve;
      $def_shell    = $shells_obj->default;
      $shells       = $shells_obj->shells;
   }
   catch ($e) { return $self->add_error( $e ) }

   my $form      = $s->{form}->{name};
   my $moniker   = $self->source_name;
   my $name      = $self->query_value( q(name) ) || NUL;
   my $first_fld = $profile eq $s->{newtag} && !$name ? $form.'.name'
                 :                              $name ? $form.'.desc'
                 :                                      $form.'.'.$moniker;

   # Add fields to form
   $self->clear_form( { firstfld => $first_fld } );
   $self->add_field ( { default  => $profile,
                        id       => $form.'.'.$moniker,
                        labels   => $profile_list->labels,
                        values   => $profiles } );

   if ($profile) {
      if ($profile eq $s->{newtag}) {
         $self->add_field( { default => $name,
                             id      => $form.'.name',
                             values  => $roles } );
      }
      else {
         $self->add_field ( { id => $form.'.group_name' } );
         $self->add_hidden( 'name', $profile );
         $s->{profile} = $profile;
      }

   }

   $self->group_fields( { id      => $form.'.select' } );

   (not $profile or (not $name and $profile eq $s->{newtag})) and return;

   $self->add_field   ( { default => $profile_obj->desc,
                          ajaxid  => $form.'.desc' } );
   $self->add_field   ( { default => $profile_obj->passwd,
                          id      => $form.'.passwd' } );
   $self->add_field   ( { default => $profile_obj->baseid,
                          id      => $form.'.baseid' } );
   $self->add_field   ( { default => $profile_obj->increment,
                          id      => $form.'.increment' } );
   $self->add_field   ( { default => $profile_obj->homedir,
                          id      => $form.'.homedir' } );
   $self->add_field   ( { default => $profile_obj->permissions,
                          id      => $form.'.permissions' } );
   $self->add_field   ( { default => $profile_obj->shell || $def_shell,
                          id      => $form.'.shell',
                          values  => $shells } );
   $self->add_field   ( { default => $profile_obj->roles,
                          id      => $form.'.roles' } );
   $self->add_field   ( { default => $profile_obj->printer,
                          id      => $form.'.printer' } );
   $self->add_field   ( { default => $profile_obj->server,
                          id      => $form.'.server' } );
   $self->add_field   ( { default => $profile_obj->prefix,
                          id      => $form.'.prefix' } );
   $self->add_field   ( { default => $profile_obj->pattern,
                          id      => $form.'.pattern' } );
   $self->add_field   ( { default => $profile_obj->project,
                          id      => $form.'.project' } );
   $self->group_fields( { id      => $form.'.edit' } );

   # Add buttons to form
   if ($profile eq $s->{newtag}) { $self->add_buttons( qw(Insert) ) }
   else { $self->add_buttons( qw(Save Delete) ) }

   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::UserProfiles - CRUD methods for user account profiles

=head1 Version

0.7.$Revision: 1181 $

=head1 Synopsis

   use CatalystX::Usul::Model::UserProfiles;

   $profile_obj = CatalystX::Usul::Model::UserProfiles->new( $app, $config ) );
   $profile_obj->shells( $shells_obj );
   $profile_obj->roles ( $roles_obj );

=head1 Description

These methods maintain the user account profiles used by the identity
class to create new user accounts. This class inherits from
L<CatalystX::Usul::Model::Config> which provides the necessary CRUD
methods. Data is stored in the F<identity.xml> file in the I<ctrldir>

=head1 Subroutines/Methods

=head2 build_per_context_instance

Creates an instance if the domain model, caches copies of the role model
and the shells model

=head2 create_or_update

   $profile_obj->create_or_update;

Creates a new user account profile or updates an existing one. Field
data is extracted from the request object. The result
message is written to C<$stash>

=head2 delete

   $profile_obj->delete;

Delete the selected user account profile. The name of the profile to delete
is extracted from the request object. The result message
is written to C<$stash>

=head2 find

   $config_element_obj = $profile_obj->find( $wanted );

Returns a L<File::DataClass::Result> object for the wanted
profile

=head2 list

   $config_list_obj = $profile_obj->list( $wanted );

Returns a L<File::DataClass::List> object whose I<list>
attribute is an array ref of account profile names. If a profile name
is given it also returns a L<File::DataClass::Result> object
for that profile

=head2 user_profiles_form

   $profile_obj->profile_form( $profile );

Stuffs the stash with the data to generate the profile editing form

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model::Config>

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
