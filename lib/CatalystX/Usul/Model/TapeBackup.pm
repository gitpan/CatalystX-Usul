# @(#)$Id: TapeBackup.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Model::TapeBackup;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions;
use CatalystX::Usul::TapeBackup;
use TryCatch;

__PACKAGE__->config( domain_class => q(CatalystX::Usul::TapeBackup),
                     fs_class     => q(FileSystem) );

__PACKAGE__->mk_accessors( qw(fs_class fs_model) );

sub build_per_context_instance {
   my ($self, $c, @rest) = @_; my $s = $c->stash;

   my $new   = $self->next::method( $c, @rest );
   my $attrs = { %{ $new->domain_attributes || {} } };

   $attrs->{debug       } ||= $s->{debug};
   $attrs->{default_tape} ||= $s->{os}->{default_tape}->{value};
   $attrs->{dump_cmd    } ||= $s->{os}->{dump_cmd}->{value};
   $attrs->{dump_dates  } ||= $s->{os}->{dump_dates}->{value};
   $attrs->{form        } ||= $s->{form}->{name};
   $attrs->{lang        } ||= $s->{lang};

   $new->domain_model( $new->domain_class->new( $c, $attrs ) );
   $new->fs_model    ( $c->model( $self->fs_class ) );

   return $new;
}

sub backup_form {
   my ($self, $paths) = @_; my ($fsystems, $tape_status);

   my $s       = $self->context->stash;
   my $form    = $s->{form}->{name};
   my $params  = $s->{device_params};
   my $fsystem = $paths ? (split SPC, $paths)[ 0 ] : NUL;

   # Retrieve data from model
   try {
      my $fs_obj = $self->fs_model->get_file_systems( $fsystem );

      $fsystems         = [ NUL, @{ $fs_obj->file_systems} ];
      $params->{volume} = $fs_obj->volume;
      $tape_status      = $self->domain_model->get_status( $params );
   }
   catch ($e) { return $self->add_error( $e ) }

   # Add fields to form
   $self->clear_form( { firstfld => $form.q(.format) } );
   $self->add_field ( { default  => $tape_status->{format},
                        id       => $form.q(.format),
                        labels   => $tape_status->{f_labels},
                        values   => [ NUL, @{ $tape_status->{formats} } ] } );

   if ($tape_status->{format} eq q(tar)) {
      $self->add_field( { default => $paths,
                          id      => $form.q(.pathsTar),
                          name    => q(paths) } );
   }
   else {
      $self->add_field( { default => $fsystem,
                          id      => $form.q(.pathsDump),
                          name    => q(paths),
                          values  => $fsystems } );

      $fsystem and is_member $fsystem, $fsystems
         or return $self->group_fields( { id => $form.q(.select) } );

      $self->add_field( { default => $tape_status->{dump_type},
                          id      => $form.q(.type),
                          values  => $tape_status->{dump_types} } );

      if ($tape_status->{dump_type} eq q(specific)) {
         $self->add_field( { default => $tape_status->{next_level},
                             id      => $form.q(.next_level),
                             values  => [ NUL, 0 .. 9 ] } );
      }
      else { $self->add_hidden( q(next_level), $tape_status->{next_level} ) }
   }

   $self->add_field( { default => $tape_status->{device},
                       id      => $form.q(.device),
                       values  => [ NUL, @{ $tape_status->{devices} } ] } );
   $self->add_field( { default => $tape_status->{operation},
                       id      => $form.q(.operation),
                       labels  => $tape_status->{o_labels},
                       values  => [ 1, 2 ] } );
   $self->add_field( { default => $params->{position} || 1,
                       id      => $form.q(.position),
                       labels  => $tape_status->{p_labels},
                       values  => [ 1, 2 ] } );

   $tape_status->{format} eq q(dump)
      and $self->add_field( { id => $form.q(.except_inodes) } );

   $self->group_fields( { id => $form.q(.select) } );

   if ($tape_status->{format} eq q(dump)) {
      my $text = $self->loc( $tape_status->{dump_msg},
                             $fsystem,
                             $tape_status->{last_dump },
                             $tape_status->{last_level},
                             $tape_status->{next_level} );

      $self->add_field( { pwidth => q(100%),
                          type   => q(note),
                          text   => $text } );
   }

   if ($tape_status->{position}) {
      my $text = $self->loc( $tape_status->{position}, $tape_status->{file_no});

      $self->add_field( { clear  => q(left),
                          pwidth => q(100%),
                          type   => q(note),
                          text   => $text } );
   }

   $self->group_fields( { id => $form.q(.status) } );

   # Add buttons to form
   if ($tape_status->{device}
       and $tape_status->{online} and not $tape_status->{working}) {
      $self->add_buttons( qw(Start Eject) );
   }

   return;
}

sub eject {
   my $self = shift; my $s = $self->context->stash;

   my $device = $self->domain_model->eject( $s->{device_params} );

   $self->add_result_msg( q(ejectTape), $device );
   return TRUE;
}

sub start {
   my ($self, $paths) = @_; my $s = $self->context->stash;

   my $run = $self->domain_model->start( $s->{device_params}, $paths );

   $self->add_result( $run->out );
   return TRUE;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::TapeBackup - Provides tape backup methods

=head1 Version

0.6.$Revision: 1165 $

=head1 Synopsis

   package MyApp;

   use Catalyst qw(ConfigComponents);

   # In the application configuration file
   <component name="Model::TapeBackup">
      <base_class>CatalystX::Usul::Model::TapeBackup</base_class>
   </component>

=head1 Description

Provides methods to perform tape backups using either C<dump> or C<tar>

=head1 Subroutines/Methods

=head2 build_per_context_instance

Creates a new instance of L<CatalystX::Usul::TapeBackup> and stores a
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
