package CatalystX::Usul::Process;

# @(#)$Id: Process.pm 403 2009-03-28 04:09:04Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul CatalystX::Usul::Utils);
use CatalystX::Usul::Table;
use Proc::ProcessTable;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 403 $ =~ /\d+/gmx );

sub get_table {
   my ($self, $ptype, $user, $fsystem, $ref) = @_;
   my ($cmd, $count, $f, $has, $new, $out, $p, $pat, $pid, $t);

   $count = 0;
   $pat   = $ref->{pattern}->[ $ptype ];
   $t     = Proc::ProcessTable->new( cache_ttys => 1 );
   $new   = CatalystX::Usul::Table->new
      ( align  => { uid   => 'left',   pid   => 'right',
                    ppid  => 'right',  start => 'right',
                    tty   => 'right',  time  => 'right',
                    size  => 'right',  state => 'left',
                    cmd   => 'left' },
        flds   => [ qw(uid pid ppid start time size state tty cmd) ],
        labels => { uid   => 'User',   pid   => 'PID',
                    ppid  => 'PPID',   start => 'Start Time',
                    tty   => 'TTY',    time  => 'Time',
                    size  => 'Size',   state => 'State',
                    cmd   => 'Command' },
        wrap   => { cmd => 1 }, );

   $ref = {}; for $p (@{ $t->table }) { $ref->{ $p->pid } = $p }

   $has = {}; for $f ($t->fields) { $has->{ $f } = 1 }

   $new->values( [] );

   if ($ptype == 3 && $fsystem) {
      $cmd  = 'df -k '.$fsystem.' | awk ';
      $cmd .= ' \'{ if ($2 && $NF != "on") { print $NF } }\' | xargs -i ';
      $cmd .= 'fuser {} 2>/dev/null | sed -e \'s/[^0-9 ]//g\' | ';
      $cmd .= 'tr -s " " | tr " " "\n" | grep -v ^$ | sort -n | uniq';

      if ($out = $self->run_cmd( $cmd )->out) {
         for $pid (split m{ \n }mx, $out) {
            if ($p = $ref->{ $pid }) {
               push @{ $new->values }, $self->_set_fields( $has, $p );
               $count++;
            }
         }
      }
   }
   else {
      for $p (values %{ $ref }) {
         if (($ptype == 1 && (!$user || $user eq q(All) ||
                              $user eq getpwuid $p->uid)) ||
             ($ptype == 2 && (!$pat  || $p->cmndline =~ m{ $pat }msx))) {
            push @{ $new->values }, $self->_set_fields( $has, $p );
            $count++;
         }
      }
   }

   @{ $new->values } = sort { _pscomp( $a, $b ) } @{ $new->values };
   $new->count( $count );
   return $new;
}

sub signal_process {
   my ($self, $flag, $sig, $pids) = @_; my ($cmd, $opts);

   $opts  = '-o sig='.$sig.q( ) if ($sig);
   $opts .= '-o flag=one'       if ($flag);
   $cmd   = $self->suid.' -n -c signal_process '.$opts.' -- ';
   $cmd  .= join q( ), @{ $pids };

   return $self->run_cmd( $cmd )->out;
}

# Private methods

sub _pscomp {
   my ($arg1, $arg2) = @_; my $result;

   $result = $arg1->{uid} cmp $arg2->{uid};
   $result = $arg1->{pid} <=> $arg2->{pid} if ($result == 0);

   return $result;
}

sub _set_fields {
   my ($self, $has, $p) = @_;

   my $flds       = {};
   $flds->{id   } = $has->{pid   } ? $p->pid                      : q();
   $flds->{pid  } = $has->{pid   } ? $p->pid                      : q();
   $flds->{ppid } = $has->{ppid  } ? $p->ppid                     : q();
   $flds->{start} = $has->{start }
                  ? $self->time2str( '%d/%m %H:%M', $p->start )   : q();
   $flds->{state} = $has->{state } ? $p->state                    : q();
   $flds->{tty  } = $has->{ttydev} ? $p->ttydev                   : q();
   $flds->{time } = $has->{time  } ? int $p->time / 1_000_000     : q();
   $flds->{uid  } = $has->{uid   } ? getpwuid $p->uid             : q();

   if ($has->{ttydev} && $p->ttydev) {
      $flds->{tty} = $p->ttydev;
   }
   elsif ($has->{ttynum} && $p->ttynum) {
      $flds->{tty} = $p->ttynum;
   }
   else { $flds->{tty} = q() }

   if ($has->{rss} && $p->rss) {
      $flds->{size} = int $p->rss/1_024;
   }
   elsif ($has->{size} && $p->size) {
      $flds->{size} = int $p->size/1_024;
   }
   else { $flds->{size} = q() }

   if ($has->{exec} && $p->exec) {
      $flds->{cmd} = substr $p->exec, 0, 64;
   }
   elsif ($has->{cmndline} && $p->cmndline) {
      $flds->{cmd} = substr $p->cmndline, 0, 64;
   }
   elsif ($has->{fname} && $p->fname) {
      $flds->{cmd} = substr $p->fname, 0, 64;
   }
   else { $flds->{cmd} = q() }

   return $flds;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Process - View and signal processes

=head1 Version

0.1.$Revision: 403 $

=head1 Synopsis

   use CatalystX::Usul::Process;

   $process_model = CatalystX::Usul::Process->new( $c );

=head1 Description

Displays the process table and allows signals to be sent to selected
processes

=head1 Subroutines/Methods

=head2 get_table

Generates the process table data used by the L<HTML::FormWidget> table
subclass. Called by L<CatalystX::Usul::Model::Process/proc_table>

=head2 signal_process

Send a signal the the selected processes

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul>

=item L<CatalystX::Usul::Table>

=item L<CatalystX::Usul::Utils>

=item L<Proc::ProcessTable>

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
