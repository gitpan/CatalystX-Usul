# @(#)Ident: ;

package CatalystX::Usul::Model::Config::Rooms;

use strict;
use version; our $VERSION = qv( sprintf '0.15.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;

extends q(CatalystX::Usul::Model::Config);

has '+create_msg_key' => default => 'Action [_1] / [_2] created';

has '+delete_msg_key' => default => 'Action [_1] / [_2] deleted';

has '+keys_attr'      => default => q(action);

has '+update_msg_key' => default => 'Action [_1] / [_2] updated';

sub create_or_update {
   my ($self, $ns, $name) = @_;

   return $self->next::method( $ns, { name => $name } );
}

sub delete {
   my ($self, $ns, $name) = @_; my $s = $self->context->stash;

   $self->next::method( $ns, $name );
   delete $s->{levels}->{ $ns }->{ $name };
   return;
}

sub set_state {
   my ($self, $ns, $name) = @_;

   my $state  = $self->query_value( q(state) ) || 0;

   $self->update( $ns, { name => $name, state => $state } );
   $self->clear_result;

   my $user   = $self->context->stash->{user}->username;
   my $msg    = 'Action [_1] / [_2] state set to [_3] by [_4]';
   my %states = ( 0 => q(open), 1 => q(hidden), 2 => q(closed) );

   $self->add_result_msg( $msg, $ns, $name, $states{ $state }, $user );
   return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Rooms - Class definition for the action configuration element

=head1 Version

Describes v0.15.$Rev: 1 $

=head1 Synopsis

   package YourApp;

   use Catalyst qw(ConfigComponents...);

   __PACKAGE__->config(
     'Model::Config::Rooms' => {
        parent_classes      => q(CatalystX::Usul::Model::Config::Rooms) }, );

=head1 Description

Defines the attributes for the <action> configuration element

Defines three language independent attributes: C<acl>, C<name> and  C<state>

Defines two language dependent attributes: C<text> and  C<tip>

=head1 Subroutines/Methods

=head2 create_or_update

Creates or updates the specified C<action> element

=head2 delete

Deletes the specified C<action> element from the configuration

=head2 set_state

Toggles the C<state> attribute which has the effect of opening (false) or
closing (true) the action to the application

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

Copyright (c) 2014 Peter Flanigan. All rights reserved

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
