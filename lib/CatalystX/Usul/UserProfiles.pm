# @(#)$Id: UserProfiles.pm 838 2010-04-28 12:35:21Z pjf $

package CatalystX::Usul::UserProfiles;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 838 $ =~ /\d+/gmx );

use File::DataClass::Constants;
use Moose;

extends qw(File::DataClass::Schema);

has '+result_source_attributes' =>
   default          => sub { return {
      profile       => {
         attributes => [ qw(baseid desc homedir increment passwd
                            pattern permissions printer
                            prefix project roles server
                            shell) ],
         defaults   => { baseid => 100, increment => 1 },
         label_attr => q(desc), }, } };

sub create {
   return shift->resultset->create( $_[0] );
}

sub delete {
   return shift->resultset->delete( { name => $_[0] } );
}

sub find {
   return shift->resultset->find( { name => $_[0] } );
}

sub list {
   return shift->resultset->list( { name => $_[0] } );
}

sub resultset {
   shift->next::method( q(profile) );
}

sub source {
   shift->next::method( q(profile) );
}

sub update {
   return shift->resultset->update( $_[0] );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::UserProfiles - CRUD methods for user account profiles

=head1 Version

0.4.$Revision: 838 $

=head1 Synopsis

   use CatalystX::Usul::UserProfiles;

   $profile_obj = CatalystX::Usul::Model::UserProfiles->new( $app, $config ) );
   $profile_obj->shells( $shells_obj );
   $profile_obj->roles ( $roles_obj );

=head1 Description

These methods maintain the user account profiles used by the identity
class to create new user accounts. This class inherits from
L<CatalystX::Usul::Model::Config> which provides the necessary CRUD
methods. Data is stored in the F<identity.xml> file in the I<ctrldir>

Inherits from L<File::DataClass::Schema> and defines the I<profile>
result source

=head1 Subroutines/Methods

=head2 create

Calls the create methods on the resultset provided by calling the
L</resultset> method

=head2 delete

Calls the delete method on the resultset provided by calling the
L</resultset> method

=head2 find

Calls the find method on the resultset provided by calling the
L</resultset> method

=head2 list

Calls the list method on the resultset provided by calling the
L</resultset> method

=head2 resultset

Returns a L<File::DataClass::ResultSet> object. Calls the parent class
C<resultset> method passing in the hard coded result source name
which is I<profile>

=head2 source

Returns a L<File::DataClass::ResultSource> object. Calls the parent class
C<source> method passing in the hard coded result source name
which is I<profile>

=head2 update

Calls the update method on the resultset provided by calling the
L</resultset> method

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

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

Copyright (c) 2009 Peter Flanigan. All rights reserved

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
