# @(#)$Id: UserProfiles.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::Model::UserProfiles;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model::Config);

use CatalystX::Usul::Shells;
use Class::C3;

__PACKAGE__->config
   ( create_msg_key    => q(createdProfile),
     delete_msg_key    => q(deletedProfile),
     file              => q(identity),
     keys_attr         => q(profile),
     schema_attributes => {
        attributes     => [ qw(baseid desc homedir increment passwd pattern
                               permissions printer prefix project
                               roles server shell) ],
        defaults       => {},
        element        => q(userProfiles),
        label_attr     => q(desc),
        lang_dep       => undef, },
     update_msg_key    => q(updatedProfile), );

__PACKAGE__->mk_accessors( qw(file roles shells shells_attributes) );

sub new {
   my ($self, $app, $config) = @_;

   my $new   = $self->next::method( $app, $config );
   my $attrs = $new->shells_attributes || {};

   $new->shells( CatalystX::Usul::Shells->new( $app, $attrs ) );

   return $new;
}

sub create_or_update {
   my $self = shift; my $s = $self->context->stash;

   my ($msg, $name); my $fields = {};

   unless ($name = $self->query_value( q(name) )) {
      $self->throw( 'No profile name specified');
   }

   for (@{ $self->domain_model->result_source->schema->attributes }) {
      $fields->{ $_ } = $self->query_value( $_ );
   }

   $fields = $self->check_form( $fields );
   $self->lang( undef );

   if ($self->query_value( q(profile) ) eq $s->{newtag}) { # Insert new
      return $self->create( { file => $self->file,
                              name => $name, fields => $fields } );
   }

   # Update existing
   return $self->update( { file => $self->file,
                           name => $name, fields => $fields } );
}

sub delete {
   my $self = shift; my $name;

   unless ($name = $self->query_value( q(profile) )) {
      $self->throw( 'No profile name specified' );
   }

   $self->lang( undef );

   return $self->next::method( { file => $self->file, name => $name } );
}

sub find {
   my ($self, $name) = @_;

   return unless ($name);

   $self->lang( undef );

   return $self->next::method( $self->file, $name );
}

sub get_list {
   my ($self, $name) = @_;

   $self->lang( undef );

   return $self->next::method( $self->file, $name );
}

sub user_profiles_form {
   my ($self, $profile) = @_;
   my ($def_shell, $e, $profile_list, $profile_obj);
   my ($profiles, $roles, $shells, $shells_obj);

   $self->lang( undef ); $profile ||= q();

   # Retrieve data from model
   eval {
      $profile_list = $self->get_list( $profile );
      $profile_obj  = $profile_list->element;
      $profiles     = $profile_list->list;
      @{ $roles }   = grep { !$self->is_member( $_, @{ $profiles } ) }
                              $self->roles->get_roles( q(all) );
      $shells_obj   = $self->shells->retrieve;
      $def_shell    = $shells_obj->default;
      $shells       = $shells_obj->shells;
   };

   return $self->add_error( $e ) if ($e = $self->catch);

   my $s         = $self->context->stash; $s->{pwidth} -= 10;
   my $name      = $self->query_value( q(name) ) || q();
   my $form      = $s->{form}->{name};
   my $first_fld = $profile eq $s->{newtag} && !$name ? $form.'.name'
                 : $name                              ? $form.'.desc'
                                                      : $form.'.profile';
   my $nitems    = 0;
   my $step      = 1;

   unshift @{ $profiles }, q(), $s->{newtag};
   unshift @{ $roles    }, q();

   # Add fields to form
   $self->clear_form( { firstfld => $first_fld } );
   $self->add_field(  { default  => $profile,
                        id       => $form.'.profile',
                        labels   => $profile_list->labels,
                        stepno   => 0,
                        values   => $profiles } ); $nitems++;

   if ($profile) {
      if ($profile eq $s->{newtag}) {
         $self->add_field(  { default => $name,
                              id      => $form.'.name',
                              stepno  => 0,
                              values  => $roles } );
      }
      else {
         $s->{profile} = $profile;
         $self->add_hidden( 'name', $profile );
         $self->add_field(  { id => $form.'.group_name', stepno => 0 } );
      }

      $nitems++;
   }

   $self->group_fields( { id => $form.'.select', nitems => $nitems } );
   $nitems = 0;

   return if (!$profile || (!$name && $profile eq $s->{newtag}));

   $self->add_field(    { default => $profile_obj->desc,
                          ajaxid  => $form.'.desc',
                          stepno  => $step++ } ); $nitems++;
   $self->add_field(    { default => $profile_obj->passwd,
                          id      => $form.'.passwd',
                          stepno  => $step++ } ); $nitems++;
   $self->add_field(    { default => $profile_obj->baseid,
                          id      => $form.'.baseid',
                          stepno  => $step++ } ); $nitems++;
   $self->add_field(    { default => $profile_obj->increment,
                          id      => $form.'.increment',
                          stepno  => $step++ } ); $nitems++;
   $self->add_field(    { default => $profile_obj->homedir,
                          id      => $form.'.homedir',
                          stepno  => $step++ } ); $nitems++;
   $self->add_field(    { default => $profile_obj->permissions,
                          id      => $form.'.permissions',
                          stepno  => $step++ } ); $nitems++;
   $self->add_field(    { default => $profile_obj->shell || $def_shell,
                          id      => $form.'.shell',
                          stepno  => $step++,
                          values  => $shells } ); $nitems++;
   $self->add_field(    { default => $profile_obj->roles,
                          id      => $form.'.roles',
                          stepno  => $step++ } ); $nitems++;
   $self->add_field(    { default => $profile_obj->printer,
                          id      => $form.'.printer',
                          stepno  => $step++ } ); $nitems++;
   $self->add_field(    { default => $profile_obj->server,
                          id      => $form.'.server',
                          stepno  => $step++ } ); $nitems++;
   $self->add_field(    { default => $profile_obj->prefix,
                          id      => $form.'.prefix',
                          stepno  => $step++ } ); $nitems++;
   $self->add_field(    { default => $profile_obj->pattern,
                          id      => $form.'.pattern',
                          stepno  => $step++ } ); $nitems++;
   $self->add_field(    { default => $profile_obj->project,
                          id      => $form.'.project',
                          stepno  => $step++ } ); $nitems++;
   $self->group_fields( { id      => $form.'.edit', nitems => $nitems } );

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

0.1.$Revision: 562 $

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

=head2 new

Creates an instance of L<CatalystX::Usul::Shells>

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

Returns a L<CatalystX::Usul::File::Element> object for the wanted
profile

=head2 get_list

   $config_list_obj = $profile_obj->get_list( $wanted );

Returns a L<CatalystX::Usul::File::List> object whose I<list>
attribute is an array ref of account profile names. If a profile name
is given it also returns a L<CatalystX::Usul::File::Element> object
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
