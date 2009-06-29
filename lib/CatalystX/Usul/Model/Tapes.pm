# @(#)$Id: Tapes.pm 576 2009-06-09 23:23:46Z pjf $

package CatalystX::Usul::Model::Tapes;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 576 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model);

use CatalystX::Usul::TapeDevice;

my $NUL = q();

__PACKAGE__->config( fields   => [ qw(device format next_level operation
                                      paths position type) ],
                     fs_class => q(FileSystem) );

__PACKAGE__->mk_accessors( qw(fields fs_class fs_model tape_device) );

sub build_per_context_instance {
   my ($self, $c, @rest) = @_; my $s = $c->stash; my $args;

   my $new = $self->next::method( $c, @rest );

   %{ $args } = map  { $_->[ 0 ] => $_->[ 1 ] }
                grep { $_->[ 1 ] }
                map  { [ $_, $new->query_value( $_ ) ] } @{ $self->fields };

   $args->{fields} = $self->fields;
   $args->{debug } = $s->{debug};
   $args->{form  } = $s->{form}->{name};
   $args->{lang  } = $s->{lang};

   $new->tape_device( CatalystX::Usul::TapeDevice->new( $c, $args ) );
   $new->fs_model(    $c->model( $self->fs_class ) );

   return $new;
}

sub backup_form {
   my ($self, $device, $format, $paths) = @_;

   my $fsystem = $paths ? (split q( ), $paths)[0] : $NUL;
   my $s       = $self->context->stash;
   my $form    = $s->{form}->{name};

   my ($e, $fsystems, $tape_status, $text); $s->{pwidth} -= 10;

   # Retrieve data from model
   eval {
      my $res = $self->fs_model->get_file_systems( $fsystem );

      $fsystems    = $res->file_systems; unshift @{ $fsystems }, $NUL;
      $tape_status = $self->tape_device->get_status( $res->volume );
   };

   return $self->add_error( $e ) if ($e = $self->catch);

   # Add fields to form
   $self->clear_form( { firstfld => $form.'.format' } ); my $nitems = 0;

   my $values = $tape_status->{formats}; unshift @{ $values }, $NUL;

   $self->add_field( { default => $format,
                       id      => $form.'.format',
                       labels  => $tape_status->{f_labels},
                       stepno  => 0,
                       values  => $values } ); $nitems++;

   if ($format eq q(tar)) {
      $self->add_field( { default => $paths,
                          id      => $form.'.pathsTar',
                          name    => 'paths',
                          stepno  => 0 } ); $nitems++;
   }
   else {
      $self->add_field( { default => $fsystem,
                          id      => $form.'.pathsDump',
                          name    => 'paths',
                          stepno  => 0,
                          values  => $fsystems } ); $nitems++;

      unless ($fsystem && $self->is_member( $fsystem, @{ $fsystems } )) {
         $self->group_fields( { id     => $form.'.select',
                                nitems => $nitems } );
         return;
      }

      $self->add_field( { default => $tape_status->{dump_type},
                          id      => $form.'.type',
                          stepno  => 0,
                          values  => $tape_status->{dump_types} } ); $nitems++;

      if ($tape_status->{dump_type} eq q(specific)) {
         $self->add_field( { default => $tape_status->{next_level},
                             id      => $form.'.next_level',
                             stepno  => 0,
                             values  => [ $NUL, 0 .. 9 ] } ); $nitems++;
      }
      else { $self->add_hidden( q(next_level), $tape_status->{next_level} ) }
   }

   $values = $tape_status->{devices}; unshift @{ $values }, $NUL;

   $self->add_field( { default => $device,
                       id      => $form.'.device',
                       stepno  => 0,
                       values  => $values } ); $nitems++;

   my $default = $self->query_value( q(operation) ) || 1;

   $self->add_field( { default => $default,
                       id      => $form.'.operation',
                       labels  => $tape_status->{o_labels},
                       stepno  => 0,
                       values  => [ 1, 2 ] } ); $nitems++;

   $self->add_field( { default => $self->query_value( q(position) ) || 1,
                       id      => $form.'.position',
                       labels  => $tape_status->{p_labels},
                       stepno  => 0,
                       values  => [ 1, 2 ] } ); $nitems++;

   $self->group_fields( { id => $form.'.select', nitems => $nitems } );
   $nitems = 0;

   if ($format && $format eq q(dump)) {
      $text = $self->loc( $tape_status->{dump_msg},
                          $fsystem,
                          $tape_status->{next_level},
                          $tape_status->{last_dump },
                          $tape_status->{last_level} );
      $self->add_field( { palign => q(left),
                          pwidth => q(100%),
                          type   => q(note),
                          text   => $text } );
      $nitems++;
   }

   if ($tape_status->{position}) {
      $text = $self->loc( $tape_status->{position}, $tape_status->{file_no} );
      $self->add_field( { palign => q(left),
                          pwidth => q(100%),
                          type   => q(note),
                          text   => $text } );
      $nitems++;
   }

   $self->group_fields( { id => $form.'.status', nitems => $nitems } );

   # Add buttons to form
   if ($device and $tape_status->{online} and not $tape_status->{working}) {
      $self->add_buttons( qw(Start Eject) );
   }

   return;
}

sub eject {
   my $self = shift;

   $self->add_result_msg( q(ejectTape), $self->tape_device->eject );
   return;
}

sub start {
   my $self = shift; $self->add_result( $self->tape_device->start ); return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Tapes - Provides tape backup methods

=head1 Version

0.3.$Revision: 576 $

=head1 Synopsis

   package MyApp;

   use Catalyst qw(ConfigComponents);

   # In the application configuration file
   <component name="Model::Tapes">
      <base_class>CatalystX::Usul::Model::Tapes</base_class>
   </component>

=head1 Description

Provides methods to perform tape backups using either C<dump> or C<tar>

=head1 Subroutines/Methods

=head2 build_per_context_instance

Creates a new instance of L<CatalystX::Usul::TapeDevice> and stores a
cloned copy of L<CatalystX::Usul::Model::FileSystem>

=head2 backup_form

Stuffs the stash with data to render the backup form

=head2 eject

Eject the tape

=head2 start

Start a backup

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

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
