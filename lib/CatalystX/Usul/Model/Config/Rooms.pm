package CatalystX::Usul::Model::Config::Rooms;

# @(#)$Id: Rooms.pm 406 2009-03-30 01:53:50Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Model::Config);
use Class::C3;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 406 $ =~ /\d+/gmx );

__PACKAGE__->config
   ( create_msg_key    => q(createdRoom),
     delete_msg_key    => q(deletedRoom),
     keys_attr         => q(room),
     schema_attributes => {
        attributes     => [ qw(acl keywords quick_link state text tip) ],
        defaults       => { acl => [ q(any) ], state => 0, text => q() },
        element        => q(rooms),
        lang_dep       => { qw(keywords 1 text 1 tip 1) } },
     update_msg_key    => q(updatedRoom), );

__PACKAGE__->mk_accessors( qw(rooms) );

sub delete {
   my ($self, $args) = @_; my $s = $self->context->stash;

   $self->next::method( $args );
   delete $s->{levels}->{ $args->{file} }->{ $args->{name} };
   return;
}

sub set_state {
   my ($self, $args) = @_; my ($msg_args, $state);

   my %states = ( 0 => q(open), 1 => q(hidden), 2 => q(closed) );

   $state = $self->query_value( q(state) ) || 0;
   $args->{fields} = { state => $state };
   $self->update( $args );
   $self->clear_result;
   $msg_args = [ $args->{file}.q( / ).$args->{name}, $states{ $state } ];
   $self->add_result_msg( q(setRoomState), $msg_args );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Rooms - Class definition for the room configuration element

=head1 Version

0.1.$Revision: 406 $

=head1 Synopsis

   # Instantiated by Catalyst when the application starts

=head1 Description

Defines the attributes for the <rooms> configuration element

Defines three language independent attributes: I<acl>, I<name> and  I<state>

Defines two language dependent attributes: I<text> and  I<tip>

=head1 Subroutines/Methods

=head2 delete

Deletes the specified I<rooms> element from the configuration

=head2 get_list

Returns an object that contains a list of the defined rooms and the fields
of the specified room

=head2 set_state

Toggles the I<state> attribute which has the effect of opening (false) or
closing (true) the room to the application

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
