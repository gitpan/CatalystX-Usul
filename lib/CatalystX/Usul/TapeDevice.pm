# @(#)$Id: TapeDevice.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::TapeDevice;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul CatalystX::Usul::Utils);

use English qw(-no_match_vars);

my $NUL = q();

__PACKAGE__->config( dev_dir     => '/dev',
                     device      => 'st0',
                     dump_cmd    => '/sbin/dump -aqu -b 128',
                     dump_dates  => '/etc/dumpdates',
                     fields      => [],
                     'format'    => q(dump),
                     lang        => q(en),
                     level       => 0,
                     level_map   => { 0 => 1, 1 => 3, 2 => 5, 3 => 2, 4 => 7,
                                      5 => 4, 6 => 9, 7 => 6, 8 => 9, 9 => 8 },
                     max_wait    => 43_200,
                     mt_cmd      => 'mt -f',
                     next_level  => 0,
                     no_rew_pref => 'n',
                     no_rew_suff => $NUL,
                     operation   => 1,
                     pattern     => 'st[0-9]+',
                     position    => 1,
                     stash       => {},
                     tar_cmd     => 'tar -c -b 256',
                     type        => $NUL );

__PACKAGE__->mk_accessors( qw( dev_dir device dump_cmd
                               dump_dates fields form format lang
                               level level_map max_wait mt_cmd
                               next_level no_rew_pref no_rew_suff
                               operation paths pattern position
                               tar_cmd type) );

sub eject {
   my $self = shift;
   my $path = $self->_get_dev_path( $self->device );
   my $cmd  = $self->mt_cmd.q( ).$path.q( eject);

   $self->run_cmd( $cmd, { async => 1, debug => $self->debug } );

   return $self->device;
}

sub get_status {
   my ($self, $volume) = @_; my $s = {}; my ($cmd, $path, $posn, $ref);

   $s->{devices   } = [];
   $s->{dump_type } = $self->type;
   $s->{dump_types} = [ qw(complete weekly daily specific) ];
   $s->{file_no   } = 0;
   $s->{f_labels  } = { dump => 'Filesystem Dump', tar => 'Tape Archive' };
   $s->{formats   } = [ qw(dump tar) ];
   $s->{last_dump } = $NUL;
   $s->{dump_msg  } = $NUL;
   $s->{last_level} = 0;
   $s->{next_level} = $self->next_level;
   $s->{o_labels  } = { 1 => 'Status', 2 => 'Rewind' };
   $s->{online    } = 0;
   $s->{p_labels  } = { 1 => 'EOD (norewind)', 2 => 'BOT (rewind)' };
   $s->{position  } = $NUL;
   $s->{working   } = $NUL;

   my $form   = $self->form;
   my $device = $self->device;
   my $pat    = $self->pattern;
   my $io     = $self->io( $self->dev_dir );

   while ($path = $io->next) {
      my $file = $path->filename;

      next unless (-c $path->pathname && $file =~ m{ \A $pat \z }mx);

      push @{ $s->{devices} }, $file;

      next unless ($file eq $device);

      $s->{working} = 0;

      for $ref (@{ $self->lock->list }) {
         if ($ref->{key} =~ m{ $device }mx) { $s->{working} = 1; last }
      }

      unless ($s->{working}) {
         $cmd  = $self->mt_cmd.q( );
         $cmd .= $self->_get_dev_path( $self->_get_no_rewind( $device ) );
         $cmd .= q( status);

         my $res = $self->run_cmd( $cmd, { err => q(out) } );

         for my $line (split m{ \n }mx, $res->out) {
            $s->{online } = 1  if ($line =~ m{ ONLINE }mx ||
                                   $line =~ m{ resource \s+ busy }mx);
            $s->{file_no} = $1 if ($line =~ m{ \A File \s+ number= (\d+) }mx);
            $posn = 1          if ($line =~ m{ BOT }mx);
            $posn = 2          if ($line =~ m{ EOF }mx);
            $posn = 3          if ($line =~ m{ resource \s+ busy }mx);
         }

         if ($s->{online}) {
            if    ($posn == 3) { $s->{position} = $form.'.tapeBusy' }
            elsif ($posn == 2) { $s->{position} = $form.'.tapeEOF' }
            elsif ($posn == 1) { $s->{position} = $form.'.tapeBOT' }
            else               { $s->{position} = $form.'.tapeUnknown' }
         }
         else { $s->{position} = $form.'.tapeNotOnline' }
      }
      else { $s->{position} = $form.'.tapeInProgress' }
   }

   $io->close;

   if ($self->format eq q(dump)) {
      my $type = $self->type || q(daily);

      ($s->{last_dump}, $s->{last_level}) = $self->_get_last( $volume );
      $ref     = { complete  => 0,
                   weekly    => 1,
                   daily     => $self->level_map->{ $s->{last_level} } || 0,
                   specific  => $self->next_level };
      $s->{next_level} = $ref->{ $type };
      $type    = q(complete) if ($ref->{ $type } == 0 && $type ne q(specific));
      $type    = q(weekly)   if ($ref->{ $type } == 1 && $type ne q(specific));
      $s->{dump_type}  = $type;

      if ($s->{last_dump}) { $s->{dump_msg} = $form.'.dumpedBefore' }
      else { $s->{dump_msg} = $form.'.neverDumped' }
   }

   return $s;
}

sub process {
   my ($self, @paths) = @_; my ($cmd, $dev, @lines, $path, $res, $text);

   $paths[0] = q(/) unless (defined $paths[0]);

   if ($self->position == 2) { $dev = $self->_get_dev_path( $self->device ) }
   else {
      $dev = $self->_get_dev_path( $self->_get_no_rewind( $self->device ) );
   }

   unless (-c $dev) {
      $self->throw( error => 'Not a character device [_1]', args => [ $dev ] );
   }

   $self->lock->set( k => $dev, t => $self->max_wait );

   if ($self->operation == 2) {
      $text = "Rewinding $dev\n";
      $cmd  = $self->mt_cmd.q( ).$dev.q( rewind);
   }
   else {
      $text = "Appending to $dev\n";
      $cmd  = $self->mt_cmd.q( ).$dev.q( status);
   }

   $res = $self->run_cmd( $cmd, { err => q(out) } );

   for $path (@paths) {
      $text .= "Dumping $path ".$self->stamp."\n";

      if ($self->format eq q(dump)) {
         $cmd  = $self->dump_cmd.($self->debug ? q( -v) : $NUL);
         $cmd .= q( -).$self->level;
      }
      else { $cmd = $self->tar_cmd }

      $cmd  .= q( -f ).$dev.q( ).$path;
      $res   = $self->run_cmd( $cmd, { err => q(out) } );
      $text .= $res->stdout;
   }

   $self->lock->reset( k => $dev );
   return $text;
}

sub start {
   my $self = shift; my ($cmd, $value);

   $self->throw( 'No file path specified' ) unless ($self->paths);

   $cmd  = $self->suid.' -c tape_backup'.($self->debug ? ' -D' : ' -n');
   $cmd .= ' -L '.$self->lang;

   for my $field (@{ $self->fields }) {
      $cmd .= " -o ${field}=\"${value}\"" if ($value = $self->$field());
   }

   $cmd .= ' -- '.$self->paths;

   return $self->run_cmd( $cmd, { async => 1,
                                  debug => $self->debug,
                                  err   => q(out),
                                  out   => $self->tempname } )->out;
}

# Private methods

sub _get_dev_path {
   my ($self, $device) = @_; return $self->catfile( $self->dev_dir, $device );
}

sub _get_last {
   my ($self, $volume) = @_; my ($dstr, $level); my $lastd = 0;

   $self->throw( 'No disk volume specified' ) unless ($volume);

   return ($NUL, 0) unless (-f $self->dump_dates);

   for my $line ($self->io( $self->dump_dates )->chomp->getlines) {
      if ($line =~ m{ \A $volume \s+ (\d+) \s+ (.*) }mx) {
         my $date = $self->str2time( $2 );

         if ($date > $lastd) { $level = $1; $dstr = $2; $lastd = $date }
      }
   }

   return defined $level ? ($dstr, $level) : ($NUL, 0);
}

sub _get_no_rewind {
   return $_[0]->no_rew_pref . $_[1] . $_[0]->no_rew_suff;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TapeDevice - Provides tape device methods

=head1 Version

0.1.$Revision: 562 $

=head1 Synopsis

   use CatalystX::Usul::TapeDevice;

=head1 Description

Provides methods to perform tape backups using either C<dump> or C<tar>

=head1 Subroutines/Methods

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

=item L<CatalystX::Usul::Utils>

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
