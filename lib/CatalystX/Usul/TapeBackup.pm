# @(#)Ident: TapeBackup.pm 2013-08-27 17:42 pjf ;

package CatalystX::Usul::TapeBackup;

use strict;
use version; our $VERSION = qv( sprintf '0.14.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions   qw(throw);
use Class::Usul::File;
use Class::Usul::IPC;
use Class::Usul::Time            qw(str2time time2str);
use English                      qw(-no_match_vars);
use CatalystX::Usul::Constraints qw(Directory Lock Path);
use File::Spec::Functions        qw(catdir catfile rootdir);
use TryCatch;

has 'dev_dir'      => is => 'lazy', isa => Directory, coerce => TRUE,
   default         => sub { [ NUL, q(dev) ] };

has 'default_tape' => is => 'ro',   isa => NonEmptySimpleStr, default => 'st0';

has 'dump_cmd'     => is => 'ro',   isa => NonEmptySimpleStr,
   default         => sub { catfile( NUL, qw(sbin dump) ).q( -aqu -b 128) };

has 'dump_dates'   => is => 'lazy', isa => Path, coerce => TRUE,
   default         => sub { [ NUL, qw(etc dumpdates) ] };

has 'form'         => is => 'ro',   isa => NonEmptySimpleStr,
   default         => 'backup';

has 'level_map'    => is => 'ro',   isa => HashRef, init_arg => undef,
   default         => sub { { 0 => 1, 1 => 3, 2 => 5, 3 => 2, 4 => 7,
                              5 => 4, 6 => 9, 7 => 6, 8 => 9, 9 => 8 } };

has 'locale'       => is => 'ro',   isa => NonEmptySimpleStr,
   default         => sub { $_[ 0 ]->config->locale };

has 'max_wait'     => is => 'ro',   isa => PositiveInt, default => 43_200;

has 'mt_cmd'       => is => 'ro',   isa => NonEmptySimpleStr,
   default         => 'mt -f';

has 'no_rew_pref'  => is => 'ro',   isa => SimpleStr, default => 'n';

has 'no_rew_suff'  => is => 'ro',   isa => SimpleStr, default => NUL;

has 'pattern'      => is => 'ro',   isa => NonEmptySimpleStr,
   default         => 'st[0-9]+';

has 'static_data'  => is => 'lazy', isa => HashRef, init_arg => undef;

has 'tar_cmd'      => is => 'ro',   isa => NonEmptySimpleStr,
   default         => 'tar -c -b 256';


has '_file' => is => 'lazy', isa => FileClass,
   default  => sub { Class::Usul::File->new( builder => $_[ 0 ]->usul ) },
   handles  => [ qw(io) ], init_arg => undef, reader => 'file';

has '_ipc'  => is => 'lazy', isa => IPCClass,
   default  => sub { Class::Usul::IPC->new( builder => $_[ 0 ]->usul ) },
   handles  => [ qw(run_cmd) ], init_arg => undef, reader => 'ipc';

has '_usul' => is => 'ro',   isa => BaseClass,
   handles  => [ qw(config debug lock log) ], init_arg => 'builder',
   reader   => 'usul', required => TRUE, weak_ref => TRUE;

sub eject {
   my ($self, $args) = @_;

   my $path = $self->_dev_path( $args->{device} );
   my $cmd  = $self->mt_cmd.SPC.$path.q( eject);

   $self->run_cmd( $cmd, { async => 1, debug => $self->debug } );
   return $args->{device};
}

sub get_status {
   my ($self, $args) = @_; my $stat = $self->static_data;

   $stat->{device    } = $args->{device    } || $self->default_tape;
   $stat->{dump_type } = $args->{type      } || q(daily);
   $stat->{format    } = $args->{format    } || q(dump);
   $stat->{operation } = $args->{operation } || 1;
   $stat->{next_level} = $args->{next_level} || 0;

   my $volume = $args->{volume};
   my $form   = $self->form;
   my $pat    = $self->pattern;
   my $io     = $self->io( $self->dev_dir )->filter( sub {
      return (-c $_->pathname) && ($_->filename =~ m{ \A $pat \z }mx) } );

   for my $device (map { $_->filename } $io->all_files) {
      push @{ $stat->{devices} }, $device;

      $device eq $stat->{device} or next; $stat->{working} = FALSE;

      for my $lock (@{ $self->lock->list }) {
         if ($lock->{key} =~ m{ $device }mx) { $stat->{working} = TRUE; last }
      }

      if ($stat->{working}) {
         $stat->{position} = "${form}.tapeInProgress"; next;
      }

      $self->_read_device_position( $stat, $device );
   }

   ($stat->{format} eq q(dump) and $volume) or return $stat;

   ($stat->{last_dump}, $stat->{last_level}) = $self->_get_last( $volume );

   my $type  = $stat->{dump_type};
   my $level = { complete => 0,
                 weekly   => 1,
                 daily    => $self->level_map->{ $stat->{last_level} } || 0,
                 specific => $stat->{next_level} }->{ $type };

   $stat->{next_level} = $level;
   $level == 0 and $type ne q(specific) and $type = q(complete);
   $level == 1 and $type ne q(specific) and $type = q(weekly);
   $stat->{dump_type } = $type;
   $stat->{dump_msg  } = $stat->{last_dump} ? "${form}.dumpedBefore"
                                            : "${form}.neverDumped";
   return $stat;
}

sub process {
   my ($self, $args, @paths) = @_; my $msg;

   my $dev = $args->{position} == 2
           ? $self->_dev_path( $args->{device} )
           : $self->_dev_path( $self->_no_rewind( $args->{device} ) );

   -c $dev or throw error => 'Path [_1] not a character device',
                    args  => [ $dev ];

   defined $paths[ 0 ] or $paths[ 0 ] = rootdir;

   $self->lock->set( k => $dev, t => $self->max_wait );

   try        { $msg = $self->_process( $dev, $args, \@paths ) }
   catch ($e) { $self->lock->reset( k => $dev ); throw $e }

   $self->lock->reset( k => $dev );
   return $msg;
}

sub start {
   my ($self, $args, $paths) = @_; my $cmd;

   $paths or throw 'No file path specified';
   $cmd  = $self->config->suid.q( -c tape_backup ).$self->debug_flag;
   $cmd .= q( -L ).$self->locale;

   while (my ($k, $v) = each %{ $args }) {
      $cmd .= q( -o ).$k.'="'.$v.'"';
   }

   $cmd .= q( -- ).$paths;

   return $self->run_cmd( $cmd, { async => 1,
                                  debug => $self->debug,
                                  err   => q(out),
                                  out   => $self->file->tempname } );
}

# Private methods

sub _build_static_data {
   my $sd = {};

   $sd->{devices   } = [];
   $sd->{dump_msg  } = NUL;
   $sd->{dump_types} = [ qw(complete weekly daily specific) ];
   $sd->{f_labels  } = { dump => 'Filesystem Dump', tar => 'Tape Archive' };
   $sd->{file_no   } = 0;
   $sd->{formats   } = [ qw(dump tar) ];
   $sd->{last_dump } = NUL;
   $sd->{last_level} = 0;
   $sd->{o_labels  } = { 1 => 'Status', 2 => 'Rewind' };
   $sd->{online    } = FALSE;
   $sd->{p_labels  } = { 1 => 'EOD (norewind)', 2 => 'BOT (rewind)' };
   $sd->{position  } = NUL;
   $sd->{working   } = FALSE;
   return $sd;
}

sub _dev_path {
   my ($self, $device) = @_; return catfile( $self->dev_dir, $device );
}

sub _get_last {
   my ($self, $volume) = @_; my ($dstr, $level); my $lastd = 0;

   $volume or throw 'No disk volume specified';

   -f $self->dump_dates or return (NUL, 0);

   for my $line ($self->io( $self->dump_dates )->chomp->getlines) {
      $line !~ m{ \A $volume \s+ (\d+) \s+ (.*) }mx and next;

      my $date = str2time( $2 );

      if ($date > $lastd) { $level = $1; $dstr = $2; $lastd = $date }
   }

   return defined $level ? ($dstr, $level) : (NUL, 0);
}

sub _no_rewind {
   return $_[ 0 ]->no_rew_pref . $_[ 1 ] . $_[ 0 ]->no_rew_suff;
}

sub _process {
   my ($self, $dev, $args, $paths);

   my $cmd = $self->mt_cmd.SPC.$dev; my $text;

   if ($args->{operation} == 2) {
      $text = "Rewinding ${dev}\n"; $cmd .= q( rewind);
   }
   else { $text = "Appending to ${dev}\n"; $cmd .= q( status) }

   $self->run_cmd( $cmd, { err => q(out) } );

   for my $path (@{ $paths }) {
      $text .= "Dumping ${path} ".time2str()."\n";

      if ($args->{format} eq q(dump)) {
         $cmd  = $self->dump_cmd.($self->debug ? q( -v) : NUL);
         $cmd .= q( -).$args->{level};

         $args->{except_inodes} and $cmd .= q( -e )
            .(join q(,), split SPC, $args->{except_inodes});
      }
      else { $cmd = $self->tar_cmd }

      $cmd  .= q( -f ).$dev.SPC.$path;
      $text .= $self->run_cmd( $cmd, { err => q(out) } )->stdout;
   }

   return $text;
}

sub _read_device_position {
   my ($self, $stat, $device) = @_; my $posn;

   my $form = $self->form;
   my $path = $self->_dev_path( $self->_no_rewind( $device ) );
   my $cmd  = $self->mt_cmd.SPC.$path.q( status);
   my $out  = eval { $self->run_cmd( $cmd, { err => q(out) } )->out } || NUL;

   for my $line (split m{ \n }mx, $out) {
      $stat->{online } = TRUE if ($line =~ m{ ONLINE }mx ||
                                  $line =~ m{ resource \s+ busy }mx);
      $stat->{file_no} = $1   if ($line =~ m{ \A File \s+ number= (\d+) }mx);
      $posn = 1               if ($line =~ m{ BOT }mx);
      $posn = 2               if ($line =~ m{ EOF }mx);
      $posn = 3               if ($line =~ m{ resource \s+ busy }mx);
   }

   if ($stat->{online}) {
      if    ($posn == 3) { $stat->{position} = "${form}.tapeBusy" }
      elsif ($posn == 2) { $stat->{position} = "${form}.tapeEOF" }
      elsif ($posn == 1) { $stat->{position} = "${form}.tapeBOT" }
      else               { $stat->{position} = "${form}.tapeUnknown" }
   }
   else { $stat->{position} = "${form}.tapeNotOnline" }

   return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TapeBackup - Provides tape device methods

=head1 Version

Describes v0.14.$Rev: 1 $

=head1 Synopsis

   use CatalystX::Usul::TapeBackup;
   use Class::Usul;

   my $attr     = { builder  => Class::Usul->new, };

   my $tape_obj = CatalystX::Usul::TapeBackup->new( $attr );

   my $status_hash_ref = $tape_obj->get_status( {} );

   my $ipc_response_obj = $tape_obj->start( $args, $paths );

   my $tape_device = $tape_obj->eject( { device => $tape_device } );

=head1 Description

Provides methods to perform tape backups using either C<dump> or C<tar>

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item dev_dir

Directory path which defaults to F</dev>

=item default_tape

String which defaults to C<st0>

=item dump_cmd

String which defaults to C</sbin/dump -aqu -b 128>

=item dump_dates

Path which defaults to F</etc/dumpdates>

=item form

String which defaults to C<backup>

=item locale

String which defaults to C<en_GB>

=item max_wait

Integer which defaults to C<43_200>

=item mt_cmd

String which defaults to C<mt -f>

=item no_rew_pref

String which defaults to C<n>

=item no_rew_suff

String which defaults to null

=item pattern

String which defaults to C<st[0-9]+>

=item tar_cmd

String which defaults to C<tar -c -b 256>

=back

=head1 Subroutines/Methods

=head2 eject

   $tape_device = $self->eject( { device => $tape_device } );

Ejects the tape in the selected drive

=head2 get_status

   $status_hash_ref = $self->get_status( $args );

Returns a hash ref of information about the selected tape device

=head2 process

   $display_message = $self->process( $options, $paths );

Called from a command line wrapper this method executes the actual C<dump>
or C<tar> command

=head2 start

   $ipc_response_obj = $self->start( $args, $paths );

Calls the external command line wrapper which performs the
backup. Runs the command asynchronously so that it can return
immediately to the action that called it

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul::File>

=item L<Class::Usul::IPC>

=item L<CatalystX::Usul::Moose>

=item L<Class::Usul::Time>

=item L<CatalystX::Usul::Constraints>

=item L<TryCatch>

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

Copyright (c) 2013 Peter Flanigan. All rights reserved

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
