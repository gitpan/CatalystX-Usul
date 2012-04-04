# @(#)$Id: Locks.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Controller::Admin::Locks;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Controller);

use CatalystX::Usul::Functions qw(throw);

__PACKAGE__->config( namespace => q(admin) );

sub lock_table : Chained(common) Args(0) HasActions {
   my ($self, $c) = @_;

   my $model = $c->model( $self->model_base_class );
   my $data  = $self->lock->get_table;

   $model->add_field( { data => $data, select => q(left), type => q(table) } );
   $model->group_fields( { id => q(lock_table.select) } );
   $data->{count} > 0 and $model->add_buttons( qw(Delete) );
   return;
}

sub lock_table_delete : ActionFor(lock_table.delete) {
   my ($self, $c) = @_; my ($key, $nrows, $r_no, $text);

   my $s = $c->stash; my $model = $c->model( $self->model_base_class );

   $nrows = $model->query_value( q(_table_nrows) ) or throw 'Lock table empty';

   for $r_no (0 .. $nrows) {
      if ($key = $model->query_value( q(table_select).$r_no )) {
         $self->lock->reset( k => $key )
            and $self->log_info( 'User '.$s->{user}.' deleted lock '.$key );
      }
   }

   return 1;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin::Locks - Manipulate the lock table

=head1 Version

0.6.$Revision: 1165 $

=head1 Synopsis

   package MyApp::Controller::Admin;

   use base qw(CatalystX::Usul::Controller::Admin);

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
