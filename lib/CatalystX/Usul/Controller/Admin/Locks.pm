# @(#)Ident: ;

package CatalystX::Usul::Controller::Admin::Locks;

use strict;
use version; our $VERSION = qv( sprintf '0.16.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(throw);

BEGIN { extends q(CatalystX::Usul::Controller) }

__PACKAGE__->config( namespace => q(admin) );

sub lock_table : Chained(common) Args(0) HasActions {
   my ($self, $c) = @_;

   my $model = $c->model( $self->config_class );
   my $lockt = $model->lock->get_table;

   $model->add_field( { data => $lockt, select => q(left), type => q(table) } );
   $model->group_fields( { id => q(lock_table.select) } );
   $lockt->{count} > 0 and $model->add_buttons( qw(Delete) );
   return;
}

sub lock_table_delete : ActionFor(lock_table.delete) {
   my ($self, $c) = @_; my $s = $c->stash;

   my $model    = $c->model( $self->config_class );
   my $selected = $model->query_array( 'table' );

   $selected->[ 0 ] or throw 'Nothing selected';

   for my $key (@{ $selected } ) {
      $model->lock->reset( k => $key )
         and $self->log->info
            ( 'User '.$s->{user}->username." deleted lock ${key}" );
   }

   return TRUE;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin::Locks - Manipulate the lock table

=head1 Version

Describes v0.16.$Rev: 1 $

=head1 Synopsis

   package YourApp::Controller::Admin;

   use CatalystX::Usul::Moose;

   BEGIN { extends q(CatalystX::Usul::Controller::Admin) }

   __PACKAGE__->build_subcontrollers;

=head1 Description

Displays the lock table and allows individual locks to be selected and
deleted

=head1 Subroutines/Methods

=head2 lock_table

Display the lock table

=head2 lock_table_delete

Deletes the selected locks

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Controller>

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
