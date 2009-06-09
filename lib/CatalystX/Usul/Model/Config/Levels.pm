# @(#)$Id: Levels.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::Model::Config::Levels;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model::Config);

use Class::C3;

__PACKAGE__->config
   ( create_msg_key    => 'Namespace [_2] created',
     delete_msg_key    => 'Namespace [_2] deleted',
     file              => q(default),
     keys_attr         => q(level),
     schema_attributes => {
        attributes     => [ qw(acl state text tip) ],
        defaults       => { acl => [ q(any) ], state => 0, text => q() },
        element        => q(levels),
        lang_dep       => { qw(text 1 tip 1) }, },
     update_msg_key    => 'Namespace [_2] updated', );

__PACKAGE__->mk_accessors( qw(file) );

sub delete {
   my ($self, $args) = @_;

   $self->next::method( $args );
   delete $self->context->stash->{levels}->{ $args->{name} };
   return;
}

sub get_list {
   my ($self, $name) = @_; return $self->next::method( $self->file, $name );
}

sub set_state {
   my ($self, $args) = @_; my ($msg_args, $state);

   $state = $self->query_value( q(state) );
   $args->{fields} = { state => $state };
   $self->update( $args );
   $msg_args = [ $args->{name}, $state ? q(closed) : q(open) ];
   $self->add_result_msg( q(setLevelState), $msg_args );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Levels - Class definition for the levels configuration element

=head1 Version

0.1.$Revision: 562 $

=head1 Synopsis

   # Instantiated by Catalyst when the application starts

=head1 Description

Defines the <levels> configuration element

Defines three language independent attributes: I<acl>, I<name> and  I<state>

Defines two language dependent attributes: I<text> and  I<tip>

=head1 Subroutines/Methods

=head2 delete

Deletes the specified I<levels> element from the configuration

=head2 get_list

Returns an object that contains a list of the defined levels and the fields
of the specified level

=head2 set_state

Toggles the I<state> attribute which has the effect of opening (false) or
closing (true) the level to the application

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
