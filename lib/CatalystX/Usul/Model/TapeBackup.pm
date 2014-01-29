# @(#)Ident: ;

package CatalystX::Usul::Model::TapeBackup;

use strict;
use version; our $VERSION = qv( sprintf '0.17.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions;
use TryCatch;

extends q(CatalystX::Usul::Model);
with    q(CatalystX::Usul::TraitFor::Model::StashHelper);

has '+domain_class' => default => q(CatalystX::Usul::TapeBackup);

has '_fs_model'     => is => 'lazy', isa => Object,
   default          => sub { $_[ 0 ]->context->model( q(FileSystem) ) },
   init_arg         => undef, reader => 'fs_model';

sub build_per_context_instance {
   my ($self, $c, @rest) = @_; my $clone = $self->next::method( $c, @rest );

   my $s       = $c->stash;
   my $os_deps = $s->{os_deps};
   my $attr    = { %{ $clone->domain_attributes },
                   builder  => $clone->usul,
                   form     => $s->{form}->{name},
                   language => $s->{language}, };

   defined $os_deps->{default_tape}
          and $attr->{default_tape} ||= $os_deps->{default_tape}->{value};
   defined $os_deps->{dump_cmd    }
          and $attr->{dump_cmd    } ||= $os_deps->{dump_cmd    }->{value};
   defined $os_deps->{dump_dates  }
          and $attr->{dump_dates  } ||= $os_deps->{dump_dates  }->{value};

   $clone->domain_model( $clone->domain_class->new( $attr ) );

   return $clone;
}

sub backup_form {
   my ($self, $paths) = @_; my ($fsystems, $tape_status);

   my $s       = $self->context->stash;
   my $form    = $s->{form}->{name};
   my $params  = $s->{device_params};
   my $fsystem = $paths ? (split SPC, $paths)[ 0 ] : NUL;

   try { # Retrieve data from the domain model
      my $filesys = $self->fs_model->get_file_systems( $fsystem );

      $fsystems         = [ NUL, @{ $filesys->file_systems } ];
      $params->{volume} = $filesys->volume;
      $tape_status      = $self->domain_model->get_status( $params );
   }
   catch ($e) { return $self->add_error( $e ) }

   # Add fields to form
   $self->clear_form( { firstfld => "${form}.format" } );
   $self->add_field ( { default  => $tape_status->{format},
                        id       => "${form}.format",
                        labels   => $tape_status->{f_labels},
                        values   => [ NUL, @{ $tape_status->{formats} } ] } );

   if ($tape_status->{format} eq q(tar)) {
      $self->add_field( { default => $paths,
                          id      => "${form}.pathsTar",
                          name    => q(paths) } );
   }
   else {
      $self->add_field( { default => $fsystem,
                          id      => "${form}.pathsDump",
                          name    => q(paths),
                          values  => $fsystems } );

      $fsystem and is_member $fsystem, $fsystems
         or return $self->group_fields( { id => "${form}.select" } );

      $self->add_field( { default => $tape_status->{dump_type},
                          id      => "${form}.type",
                          values  => $tape_status->{dump_types} } );

      if ($tape_status->{dump_type} eq q(specific)) {
         $self->add_field( { default => $tape_status->{next_level},
                             id      => "${form}.next_level",
                             values  => [ NUL, 0 .. 9 ] } );
      }
      else { $self->add_hidden( q(next_level), $tape_status->{next_level} ) }
   }

   $self->add_field( { default => $tape_status->{device},
                       id      => "${form}.device",
                       values  => [ NUL, @{ $tape_status->{devices} } ] } );
   $self->add_field( { default => $tape_status->{operation},
                       id      => "${form}.operation",
                       labels  => $tape_status->{o_labels},
                       values  => [ 1, 2 ] } );
   $self->add_field( { default => $params->{position} || 1,
                       id      => "${form}.position",
                       labels  => $tape_status->{p_labels},
                       values  => [ 1, 2 ] } );

   $tape_status->{format} eq q(dump)
      and $self->add_field( { id => "${form}.except_inodes" } );

   $self->group_fields( { id => "${form}.select" } );

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

   $self->group_fields( { id => "${form}.status" } );

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

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::TapeBackup - Provides tape backup methods

=head1 Version

Describes v0.17.$Rev: 1 $

=head1 Synopsis

   package YourApp;

   use Catalyst qw(ConfigComponents...);

   __PACKAGE__->config( 'Model::TapeBackup' => {
      parent_classes => 'CatalystX::Usul::Model::TapeBackup' } );

=head1 Description

Provides methods to perform tape backups using either C<dump> or C<tar>

=head1 Configuration and Environment

Defines the following list of attributes

=over 3

=item domain_class

Overrides the default domain class. Sets it to I<CatalystX::Usul::TapeBackup>

=back

=head1 Subroutines/Methods

=head2 build_per_context_instance

Creates a new instance of the I<domain_class>

=head2 backup_form

   $self->backup_form( $paths );

Stuffs the stash with data to render the backup form

=head2 eject

   $bool = $self->eject;

Eject the tape

=head2 start

   $bool = $self->start( $paths );

Start a backup

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::TraitFor::Model::StashHelper>

=item L<CatalystX::Usul::Moose>

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
