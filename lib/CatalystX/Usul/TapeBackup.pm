# @(#)$Id: TapeBackup.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::TapeBackup;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul CatalystX::Usul::IPC);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(arg_list throw);
use CatalystX::Usul::Time qw(str2time time2str);
use English qw(-no_match_vars);
use File::Spec::Functions qw(catdir catfile rootdir);
use TryCatch;

__PACKAGE__->mk_accessors( qw(dev_dir default_tape dump_cmd dump_dates
                              form lang level_map max_wait mt_cmd
                              no_rew_pref no_rew_suff pattern tar_cmd) );

sub new {
   my ($self, $app, @rest) = @_; my $attrs = arg_list @rest;

   $attrs->{dev_dir     } ||= catdir( NUL, q(dev) );
   $attrs->{default_tape} ||= q(st0);
   $attrs->{dump_cmd    } ||= catfile( NUL, qw(sbin dump) ).q( -aqu -b 128);
   $attrs->{dump_dates  } ||= catfile( NUL, qw(etc dumpdates) );
   $attrs->{form        } ||= q(backup);
   $attrs->{lang        } ||= LANG;
   $attrs->{level_map   }   = { 0 => 1, 1 => 3, 2 => 5, 3 => 2, 4 => 7,
                                5 => 4, 6 => 9, 7 => 6, 8 => 9, 9 => 8 };
   $attrs->{max_wait    } ||= 43_200;
   $attrs->{mt_cmd      } ||= q(mt -f);
   $attrs->{no_rew_pref } ||= q(n);
   $attrs->{no_rew_suff } ||= NUL;
   $attrs->{pattern     } ||= q(st[0-9]+);
   $attrs->{tar_cmd     } ||= q(tar -c -b 256);

   return $self->next::method( $app, $attrs );
}

sub eject {
   my ($self, $args) = @_;

   my $path = $self->_dev_path( $args->{device} );
   my $cmd  = $self->mt_cmd.SPC.$path.q( eject);

   $self->run_cmd( $cmd, { async => 1, debug => $self->debug } );
   return $args->{device};
}

sub get_status {
   my ($self, $args) = @_; my $s = __get_static_data_hash();

   $s->{device    } = $args->{device    } || $self->default_tape;
   $s->{dump_type } = $args->{type      } || q(daily);
   $s->{format    } = $args->{format    } || q(dump);
   $s->{operation } = $args->{operation } || 1;
   $s->{next_level} = $args->{next_level} || 0;

   my $volume = $args->{volume};
   my $form   = $self->form;
   my $pat    = $self->pattern;
   my $io     = $self->io( $self->dev_dir )->filter( sub {
      return (-c $_->pathname) && ($_->filename =~ m{ \A $pat \z }mx) } );

   for my $device (map { $_->filename } $io->all_files) {
      push @{ $s->{devices} }, $device;

      $device eq $s->{device} or next; $s->{working} = FALSE;

      for my $lock (@{ $self->lock->list }) {
         if ($lock->{key} =~ m{ $device }mx) { $s->{working} = TRUE; last }
      }

      if ($s->{working}) { $s->{position} = $form.'.tapeInProgress'; next }

      $self->_stash_device_position( $s, $device );
   }

   ($s->{format} eq q(dump) and $volume) or return $s;

   ($s->{last_dump}, $s->{last_level}) = $self->_get_last( $volume );

   my $type  = $s->{dump_type};
   my $level = { complete => 0,
                 weekly   => 1,
                 daily    => $self->level_map->{ $s->{last_level} } || 0,
                 specific => $s->{next_level} }->{ $type };

   $s->{next_level} = $level;
   $level == 0 and $type ne q(specific) and $type = q(complete);
   $level == 1 and $type ne q(specific) and $type = q(weekly);
   $s->{dump_type } = $type;
   $s->{dump_msg  } = $form.($s->{last_dump} ? '.dumpedBefore'
                                             : '.neverDumped');
   return $s;
}

sub process {
   my ($self, $args, @paths) = @_; my $msg;

   my $dev = $args->{position} == 2
           ? $self->_dev_path( $args->{device} )
           : $self->_dev_path( $self->_no_rewind( $args->{device} ) );

   -c $dev
      or throw error => 'Path [_1] not a character device', args => [ $dev ];

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
   $cmd  = $self->suid.q( -c tape_backup).($self->debug ? q( -D) : q( -n));
   $cmd .= q( -L ).$self->lang;

   while (my ($k, $v) = each %{ $args }) {
      $cmd .= q( -o ).$k.'="'.$v.'"';
   }

   $cmd .= q( -- ).$paths;

   return $self->run_cmd( $cmd, { async => 1,
                                  debug => $self->debug,
                                  err   => q(out),
                                  out   => $self->tempname } );
}

# Private methods

sub _dev_path {
   my ($self, $device) = @_; return $self->catfile( $self->dev_dir, $device );
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

sub _stash_device_position {
   my ($self, $s, $device) = @_; my $posn;

   my $form = $self->form;
   my $path = $self->_dev_path( $self->_no_rewind( $device ) );
   my $cmd  = $self->mt_cmd.SPC.$path.q( status);
   my $out  = eval { $self->run_cmd( $cmd, { err => q(out) } )->out } || NUL;

   for my $line (split m{ \n }mx, $out) {
      $s->{online } = TRUE if ($line =~ m{ ONLINE }mx ||
                               $line =~ m{ resource \s+ busy }mx);
      $s->{file_no} = $1   if ($line =~ m{ \A File \s+ number= (\d+)}mx);
      $posn = 1            if ($line =~ m{ BOT }mx);
      $posn = 2            if ($line =~ m{ EOF }mx);
      $posn = 3            if ($line =~ m{ resource \s+ busy }mx);
   }

   if ($s->{online}) {
      if    ($posn == 3) { $s->{position} = $form.'.tapeBusy' }
      elsif ($posn == 2) { $s->{position} = $form.'.tapeEOF' }
      elsif ($posn == 1) { $s->{position} = $form.'.tapeBOT' }
      else               { $s->{position} = $form.'.tapeUnknown' }
   }
   else { $s->{position} = $form.'.tapeNotOnline' }

   return;
}

# Private subroutines

sub __get_static_data_hash {
   my $s = {};

   $s->{devices   } = [];
   $s->{dump_msg  } = NUL;
   $s->{dump_types} = [ qw(complete weekly daily specific) ];
   $s->{f_labels  } = { dump => 'Filesystem Dump', tar => 'Tape Archive' };
   $s->{file_no   } = 0;
   $s->{formats   } = [ qw(dump tar) ];
   $s->{last_dump } = NUL;
   $s->{last_level} = 0;
   $s->{o_labels  } = { 1 => 'Status', 2 => 'Rewind' };
   $s->{online    } = FALSE;
   $s->{p_labels  } = { 1 => 'EOD (norewind)', 2 => 'BOT (rewind)' };
   $s->{position  } = NUL;
   $s->{working   } = FALSE;
   return $s;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TapeBackup - Provides tape device methods

=head1 Version

0.6.$Revision: 1165 $

=head1 Synopsis

   use CatalystX::Usul::TapeBackup;

=head1 Description

Provides methods to perform tape backups using either C<dump> or C<tar>

=head1 Subroutines/Methods

=head2 new

Constructor

=head2 eject

Ejects the tape in the selected drive

=head2 get_status

For the given filesystem volume, looks up all the data used by the
C<backup_view> method

=head2 process

Called from a command line wrapper this method executes the actual C<dump>
or C<tar> command

=head2 start

Calls the external command line wrapper which performs the
backup. Runs the command asynchronously so that it can return
immediately to the action that called it

=head2 _get_last

For the given filesystem volume this method stashes values for
I<last_dump> and I<last_level> which it parses from the data in the
file pointed to by the I<dump_dates> attribute (defaults to
F</etc/dumpdates>). Called by the L</retrieve> method

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul>

=item L<CatalystX::Usul::Constants>

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
