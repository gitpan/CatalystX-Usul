# @(#)$Id: FileSystem.pm 1097 2012-01-28 23:31:29Z pjf $

package CatalystX::Usul::FileSystem;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1097 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul CatalystX::Usul::IPC);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(arg_list throw);
use CatalystX::Usul::Table;
use CatalystX::Usul::Time;
use Fcntl qw(:mode);
use File::Copy;
use File::Find;
use MRO::Compat;

__PACKAGE__->mk_accessors( qw(ctldata file_systems fs_type fuser
                              logsdir postfix volume) );

sub new {
   my ($self, $app, $attrs) = @_;

   $attrs->{postfix} ||= q(A_);

   return $self->next::method( $app, $attrs );
}

sub archive {
   # Prepend $self->postfix to file
   my ($self, @paths) = @_; my $out = NUL;

   $paths[ 0 ] or throw 'Archive file path not specified';

   for my $path (@paths) {
      -e $path or throw error => 'Path [_1] does not exist',
                        args  => [ $path ], out => $out;

      my $to = $self->catfile( $self->dirname( $path ),
                               $self->postfix.$self->basename( $path ) );

      if (-e $to) { $out .= "Already exists ${to}\n"; next }

      move( $path, $to ) or throw error => 'Cannot move from [_1] to [_2]',
                                  args  => [ $path, $to ], out => $out;
      $out .= "Archived ${path}\n";
   }

   return $out;
}

sub file_in_use {
   my ($self, $path) = @_;

   ($self->fuser and -x $self->fuser and $path and -e $path) or return FALSE;

   return $self->run_cmd( $self->fuser.SPC.$path )->stdout ? TRUE : FALSE;
}

sub get_file_systems {
   my ($self, $wanted) = @_;

   my $class = ref $self || $self;
   my $new   = bless { file_systems => [], volume => undef }, $class;
   my $cmd   = q(mount ).($self->fs_type ? q(-t ).$self->fs_type : NUL);

   for my $line (split m{ [\n] }mx, $self->run_cmd( $cmd )->stdout) {
      my ($volume, $filesys) = $line =~ m{ \A (\S+) \s+ on \s+ (\S+) }msx;

      if ($volume and $filesys) {
         push @{ $new->file_systems }, $filesys;
         $wanted and $filesys eq $wanted and $new->volume( $volume );
      }
   }

   @{ $new->file_systems } = sort { lc $a cmp lc $b } @{ $new->file_systems };
   return $new;
}

sub get_perms {
   my ($self, $mode) = @_; my $perms;

   $perms  = S_ISREG($mode)  ? q(-) : q(?);
   $perms  = S_ISDIR($mode)  ? q(d) : $perms;
   $perms  = S_ISLNK($mode)  ? q(l) : $perms;
   $perms  = S_ISBLK($mode)  ? q(b) : $perms;
   $perms  = S_ISCHR($mode)  ? q(c) : $perms;
   $perms  = S_ISFIFO($mode) ? q(p) : $perms;
   $perms  = S_ISSOCK($mode) ? q(s) : $perms;
   $perms .= ($mode & S_IRUSR) ? q(r) : q(-);
   $perms .= ($mode & S_IWUSR) ? q(w) : q(-);
   $perms .= ( ($mode & S_ISUID) && !($mode & S_IXUSR)) ? q(S) : NUL;
   $perms .= ( ($mode & S_ISUID) &&  ($mode & S_IXUSR)) ? q(s) : NUL;
   $perms .= (!($mode & S_ISUID) &&  ($mode & S_IXUSR)) ? q(x) : NUL;
   $perms .= (!($mode & S_ISUID) && !($mode & S_IXUSR)) ? q(-) : NUL;
   $perms .= ($mode & S_IRGRP) ? q(r) : q(-);
   $perms .= ($mode & S_IWGRP) ? q(w) : q(-);
   $perms .= ( ($mode & S_ISGID) && !($mode & S_IXGRP)) ? q(S) : NUL;
   $perms .= ( ($mode & S_ISGID) &&  ($mode & S_IXGRP)) ? q(s) : NUL;
   $perms .= (!($mode & S_ISGID) &&  ($mode & S_IXGRP)) ? q(x) : NUL;
   $perms .= (!($mode & S_ISGID) && !($mode & S_IXGRP)) ? q(-) : NUL;
   $perms .= ($mode & S_IROTH) ? q(r) : q(-);
   $perms .= ($mode & S_IWOTH) ? q(w) : q(-);
   $perms .= ( ($mode & S_ISVTX) && !($mode & S_IXOTH)) ? q(T) : NUL;
   $perms .= ( ($mode & S_ISVTX) &&  ($mode & S_IXOTH)) ? q(t) : NUL;
   $perms .= (!($mode & S_ISVTX) &&  ($mode & S_IXOTH)) ? q(x) : NUL;
   $perms .= (!($mode & S_ISVTX) && !($mode & S_IXOTH)) ? q(-) : NUL;
   return $perms;
}

sub list_subdirectory {
   my ($self, $args) = @_;

   my $count = 0;
   my $table = __new_results_table();
   my $io    = $self->io( $args->{dir} );
   my $match = $args->{pattern};
      $match and $io->filter( sub { $_->filename =~ $match } );
   my @paths = $io->all; $paths[ 0 ] or return $table;

   for my $path (@paths) {
      push @{ $table->values }, $self->_directory_fields( $path, $args );
      $count++;
   }

   $table->count( $count );
   return $table;
}

sub purge_tree {
   my ($self, $dir, $atime, $dtime) = @_; my $postfix = $self->postfix;

   my ($archive, $delete, $out, @paths);

   $archive = defined $atime && $atime == 0 ? FALSE : TRUE;
   $atime   = defined $atime ?  $atime : 7;
   $delete  = defined $dtime && $dtime == 0 ? FALSE : TRUE;
   $dtime   = defined $dtime ?  $dtime : 2 * $atime;

      $dir or throw 'Directory path not specified';
   -d $dir or throw error => 'Directory [_1] not found', args => [ $dir ];

   if ($archive) {
      $out   = "Archiving in $dir files more than $atime days old\n";
      $atime = time - ($atime * 86_400);
      @paths = ();

      my $match_arc_files = sub {
         if (-f $_ and $_ !~ m{ \A $postfix }mx and (stat _)[ 9 ] < $atime) {
            push @paths, $_;
         }

         return;
      };

      find( { no_chdir => TRUE, wanted => $match_arc_files }, $dir );

      if ($paths[ 0 ]) { $out .= $self->archive( $_ ) for (@paths) }
      else { $out .= "Path $dir nothing to archive\n" }
   }

   if ($delete) {
      $out  .= "Deleting in $dir files more than $dtime days old\n";
      $dtime = time - ($dtime * 86_400);
      @paths = ();

      my $match_old_files = sub {
         push @paths, $_ if (-f $_ and (stat _)[ 9 ] < $dtime); return;
      };

      find( { no_chdir => TRUE, wanted => $match_old_files }, $dir );

      if ($paths[ 0 ]) {
         for my $path (@paths) {
            unlink $path or throw error => 'Path [_1] cannot delete',
                                  args  => [ $path ], out => $out;
            $out .= "Deleted $path\n";
         }
      }
      else { $out .= "Path $dir nothing to delete\n" }
   }

   return $out;
}

sub rotate {
   my ($self, $logfile, $copies) = @_; my $copy_no = $copies;

   while ($copy_no > 0) {
      my $path = $logfile.q(.).($copy_no - 1);

      -e $path and move( $path, $logfile.q(.).$copy_no );

      $copy_no--;
   }

   -e $logfile and move( $logfile, $logfile.q(.0) );
   return;
}

sub rotate_log {
   my ($self, @rest) = @_;

   my $args = arg_list @rest;
   my $path = $args->{logfile} or return;
   my $pid  = $args->{pidfile}
            ? $self->io( $args->{pidfile} )->chomp->lock->getline
            : $args->{pid};

   $self->rotate( $path, $args->{copies} || 0 );

   unless ($args->{notouch}) {
      $self->io( $path )->perms( $args->{mode} )->touch;
      defined $args->{owner} and defined $args->{group}
         and chown $args->{owner}, $args->{group}, $path;
   }

   defined $args->{sig} and defined $pid and CORE::kill $args->{sig}, $pid;

   return "Rotated $path\n";
}

sub rotate_logs {
   my ($self, $dir, $copies, $extn) = @_;

   $dir ||= $self->logsdir; $copies ||= 5; $extn ||= q(.log);

   my $io = $self->io( $dir ); my $out = NUL;

   $io->filter( sub { $_->filename =~ m{ \Q $extn \E \z }msx } );

   $out .= $self->rotate_log( logfile => $_, copies => $copies ) for ($io->all);

   return $out;
}

sub unarchive {
   my ($self, @paths) = @_; my $out = NUL;

   $paths[ 0 ] or throw 'Archive file path not specified';

   for my $path (@paths) {
      if (-e $path) { $out .= "Already exists ${path}\n"; next }

      my $from = $self->catfile( $self->dirname( $path ),
                                 $self->postfix.$self->basename( $path ) );

      -e $from or throw error => 'Path [_1] does not exist',
                        args  => [ $from ], out => $out;

      move( $from, $path ) or throw error => 'Cannot move from [_1] to [_2]',
                                    args  => [ $from, $path ], out => $out;
      $out .= "Unarchived ${path}\n";
   }

   return $out;
}

sub wait_for {
   my ($self, $vars, $key, $max_wait, $no_thrash) = @_;

   $key or throw 'Hash key not specified';

   my $cfg   = $self->config;
   my $data  = $self->ctldata->{wait_for}->{ $key }
      or throw error => 'Key [_1] has no data', args => [ $key ];
   my $path  = $data->{path} || NUL;
   my ($rep) = $path =~ m{ % (\w+) % }msx;

   if ($rep) {
      $rep = $vars->{ $rep } || NUL; $path =~ s{ % (\w+) % }{ $rep }gmsx;
   }

   $path or throw error => 'Key [_1] path not specified',
                  args  => [ $key ], rv => 2;

   $max_wait  ||= $data->{max_wait} || $cfg->{max_wait} || 60;
   $no_thrash ||= $cfg->{no_thrash} || 3;

   my $out   = "Waiting on ${path} for ${max_wait} minutes\n";

   my $start = time; my $elapsed = 0; $max_wait *= 60;

   while (not -f $path or $self->file_in_use( $path )) {
      ($elapsed = time - $start) and $elapsed > $max_wait
         and throw error => 'Path [_1] wait for timed out',
                   args  => [ $path ], out => $out, rv => 3;
      sleep $no_thrash;
   }

   return $out."Path ${path} found after ${elapsed} seconds\n";
}

# Private methods

sub _directory_fields {
   my ($self, $path, $args) = @_;

   my $file = $path->basename;
   my $flds = $path->stat;
   my $mode = $self->get_perms( $flds->{mode} );
   my $href = ($args->{action} || NUL).(defined $args->{make_key}
                                        ? SEP.$args->{make_key}( $file )
                                        : '?file='.$file);

   $flds->{name    } = $file;
   $flds->{modestr } = $mode;
   $flds->{icon    } = __make_icon( $args->{assets}, $href );
   $flds->{user    } = getpwuid $flds->{uid} || $flds->{uid};
   $flds->{group   } = getgrgid $flds->{gid} || $flds->{gid};
   $flds->{accessed} = time2str( undef, $flds->{atime} );
   $flds->{modified} = time2str( undef, $flds->{mtime} );

   return $flds;
}

# Private subroutines

sub __make_icon {
   my ($assets, $href) = @_;

   return { class     => q(content),
            container => FALSE,
            href      => $href,
            imgclass  => q(file_icon),
            sep       => NUL,
            text      => NUL,
            tip       => 'View File',
            type      => q(anchor),
            widget    => TRUE };
}

sub __new_results_table {
   my $table = CatalystX::Usul::Table->new
      ( class    => {},
        flds     => [ qw(icon name modestr nlink user
                         group size accessed modified) ],
        hclass   => {},
        labels   => { accessed => q(Last Accessed),
                      group    => q(Group),
                      icon     => '&#160;',
                      nlink    => q(Links),
                      modestr  => q(Mode),
                      modified => q(Last Modified),
                      name     => q(File Name),
                      size     => q(Size),
                      user     => q(User) },
        typelist => { nlink    => q(numeric),
                      size     => q(numeric) }, );

   for (@{ $table->flds }) {
      $table->class->{ $_ } = q(data_value);
      $table->hclass->{ $_ } = q(minimal);
   }

   $table->class->{icon   } = q(row_select);
   $table->class->{modestr} = q(mono);
   $table->hclass->{name} = q(some);
   return $table;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::FileSystem - File system related methods

=head1 Version

0.4.$Revision: 1097 $

=head1 Synopsis

   package CatalystX::Usul::Model::FileSystem;

   use CatalystX::Usul::FileSystem;

   1;

   package YourApp::Model::FileSystem;

   use base qw(CatalystX::Usul::Model::FileSystem);

   1;

   package YourApp::Controller::Foo;

   sub bar {
      my ($self, $c) = @_;

      $c->model( q(FileSystem) )->list_subdirectory( { dir => q(/path) } );
      return;
   }

=head1 Description

This model provides methods for manipulating files and directories

=head1 Subroutines/Methods

=head2 new

Constructor defines I<logsdir>; the location of the applications log
files and I<no_thrash>; the length of time to wait between test for
the existence of a file to avoid a spin loop

=head2 archive

Archives a file by prepending the C<$self->postfix>, which
defaults to I<A_>

=head2 file_in_use

Uses the system C<fuser> command if it is available to determine if a file
is in use

=head2 get_file_systems

Parses the output from the system C<mount> command to produce a list of
file systems

=head2 get_perms

Returns the C<-rw-rw-r--> style permission string for a given octal mode

=head2 list_subdirectory

Generates the table data for a directory listing. The data is used by
the I<table> subclass of L<HTML::FormWidgets>

=head2 purge_tree

Archive old files and delete even older ones from a given directory

=head2 rotate

Issues a sequence a C<move> commands to rename I<file> to I<file.0>,
I<file.0> to I<file.1>, I<file.1> to I<file.2> and so on

=head2 rotate_log

Calls L</rotate>. Will also C<touch> a new logfile into existence and
optionally signal a process

=head2 rotate_logs

Calls L</rotate_log> on all of the I<.log> files in the given
directory, which defaults to the logs directory

=head2 unarchive

Reverse out the effect of calling L</archive>

=head2 wait_for

Wait for a given file to exist. Polls at given intervals file a configurable
period before throwing a time out error if the file does not show up

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul>

=item L<CatalystX::Usul::Constants>

=item L<CatalystX::Usul::Table>

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

Copyright (c) 2011 Peter Flanigan. All rights reserved

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
