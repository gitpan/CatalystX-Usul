# @(#)$Id: UserProfiles.pm 1319 2013-06-23 16:21:01Z pjf $

package CatalystX::Usul::UserProfiles;

use strict;
use version; our $VERSION = qv( sprintf '0.8.%d', q$Rev: 1319 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Functions qw(arg_list);
use File::DataClass::Constants;
use File::Spec::Functions      qw(catdir catfile);

extends qw(File::DataClass::Schema);

has '+result_source_attributes' =>
   default          => sub { return {
      profile       => {
         attributes => [ qw(baseid common_home desc homedir increment passwd
                            pattern permissions printer
                            prefix project roles server
                            shell) ],
         defaults   => { baseid      => 100,
                         common_home => catdir( NUL, qw(home common) ),
                         increment   => 1 },
         label_attr => q(desc), }, } };

has 'source_name' => is => 'ro', isa => 'Str', default => q(profile);

around 'BUILDARGS' => sub {
   my ($next, $self, @args) = @_; my $attr = arg_list @args;

   my $filename = delete $attr->{filename} || q(user_profiles.json);

   if (my $builder = $attr->{builder}) {
      not defined $attr->{path}
         and $attr->{path} = catfile( $builder->config->ctrldir, $filename )
            and $attr->{storage_class} = q(Any);
   }

   return $self->$next( $attr );
};

sub create {
   return $_[ 0 ]->resultset->create( $_[ 1 ] );
}

sub delete {
   return $_[ 0 ]->resultset->delete( { name => $_[ 1 ] } );
}

sub find {
   return $_[ 0 ]->resultset->find( { name => $_[ 1 ] } );
}

sub list {
   return $_[ 0 ]->resultset->list( { name => $_[ 1 ] } );
}

sub resultset {
   return $_[ 0 ]->next::method( $_[ 0 ]->source_name );
}

sub source {
   return $_[ 0 ]->next::method( $_[ 0 ]->source_name );
}

sub update {
   return $_[ 0 ]->resultset->update( $_[ 1 ] );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::UserProfiles - CRUD methods for user account profiles

=head1 Version

0.8.$Revision: 1319 $

=head1 Synopsis

   use CatalystX::Usul::UserProfiles;

   $profile_obj = CatalystX::Usul::Model::UserProfiles->new( $config ) );

   $profile_obj->find( $profile );

=head1 Description

These methods maintain the user account profiles used by the user
class to create new user accounts. This class inherits from
L<File::DataClass::Schema> which provides the necessary CRUD
methods. Data is stored in the F<user_profiles.json> file in the C<ctrldir>

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item C<+result_source_attributes>

Defines the result source attributes for the schema class

=item C<source_name>

A string which defaults to C<profile>

=back

=head1 Subroutines/Methods

=head2 create

   $self->create( $hash_ref_of_fields_and_values );

Creates a new profile. Calls the create method on the resultset
provided by calling the L</resultset> method

=head2 delete

   $self->delete( $profile );

Deletes the named profile. Calls the delete method on the resultset
provided by calling the L</resultset> method

=head2 find

   $profile_obj = $self->find( $profile );

Finds and returns a profile object. Calls the find method on the
resultset provided by calling the L</resultset> method

=head2 list

   $list_obj = $self->list( $profile );

Calls the list method on the resultset provided by calling the
L</resultset> method. The list object has a C<result> attribute which
is the return value from L</find> and a list of defined profiles

=head2 resultset

   $resultset = $self->resultset;

Returns a L<File::DataClass::ResultSet> object. Calls the parent class
C<resultset> method passing in the hard coded result source name
which is C<profile>

=head2 source

   $source = $self->source;

Returns a L<File::DataClass::ResultSource> object. Calls the parent class
C<source> method passing in the hard coded result source name
which is C<profile>

=head2 update

   $self->update( $hash_ref_of_fields_and_values );

Updates an existing profile. Calls the update method on the resultset
provided by calling the L</resultset> method

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Moose>

=item L<File::DataClass::Constants>

=item L<File::DataClass::Schema>

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
