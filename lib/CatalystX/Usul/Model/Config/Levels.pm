# @(#)$Id: Levels.pm 891 2010-09-30 01:47:24Z pjf $

package CatalystX::Usul::Model::Config::Levels;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 891 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model::Config);

use MRO::Compat;

__PACKAGE__->config
   ( create_msg_key => 'Namespace [_1] created',
     delete_msg_key => 'Namespace [_1] deleted',
     file           => q(default),
     keys_attr      => q(namespace),
     update_msg_key => 'Namespace [_1] updated', );

__PACKAGE__->mk_accessors( qw(file) );

sub create_or_update {
   my ($self, $ns, $name) = @_;

   return $self->next::method( $ns, { name => $name } );
}

sub delete {
   my ($self, $ns, $name) = @_; my $s = $self->context->stash;

   $self->next::method( $ns, $name );
   delete $s->{ $self->keys_attr }->{ $name };
   return;
}

sub list {
   my ($self, $name) = @_; return $self->next::method( $self->file, $name );
}

sub set_state {
   my ($self, $ns, $name) = @_;

   my $state  = $self->query_value( q(state) ) || 0;

   $self->update( $ns, { name => $name, state => $state } );
   $self->clear_result;

   my $user   = $self->context->stash->{user};
   my $msg    = 'Namespace [_1] state set to [_2] by [_3]';
   my %states = ( 0 => q(open), 1 => q(hidden), 2 => q(closed) );

   $self->add_result_msg( $msg, $name, $states{ $state }, $user );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Levels - Class definition for the namespace configuration element

=head1 Version

0.4.$Revision: 891 $

=head1 Synopsis

   # Instantiated by Catalyst when the application starts

=head1 Description

Defines the <namespace> configuration element

Defines three language independent attributes: I<acl>, I<name> and  I<state>

Defines two language dependent attributes: I<text> and  I<tip>

=head1 Subroutines/Methods

=head2 create_or_update

Creates or updates the specified I<namespace> element

=head2 delete

Deletes the specified I<namespace> element from the configuration

=head2 list

Returns an object that contains a list of the defined namespaces and the fields
of the specified namespace

=head2 set_state

Toggles the I<state> attribute which has the effect of opening (false) or
closing (true) the namespace to the application

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
