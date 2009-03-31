package CatalystX::Usul::FileSystem;

# @(#)$Id: FileSystem.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul CatalystX::Usul::Utils);
use CatalystX::Usul::Table;
use Class::C3;
use Fcntl qw(:mode);
use File::Copy;
use File::Find;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

__PACKAGE__->config( no_thrash => 3, postfix => q(A_), );

__PACKAGE__->mk_accessors( qw(ctldata file_systems fs_type fuser
                              logsdir no_thrash postfix volume) );

my $NUL = q();

sub new {
   my ($self, $app, @rest) = @_;

   my $new      = $self->next::method( $app, @rest );
   my $app_conf = $app->config || {};

   $new->logsdir  ( $app_conf->{logsdir}                      );
   $new->no_thrash( $app_conf->{no_thrash} || $new->no_thrash );

   return $new;
}

sub archive {
   # Prepend $self->postfix to file
   my ($self, @paths) = @_; my $out = $NUL;

   $self->throw( q(eNoPath) ) unless ($paths[0]);

   for my $path (@paths) {
      unless (-e $path) {
         $self->throw( error => q(eNotFound), arg1 => $path, out => $out );
      }

      my $to = $self->catfile( $self->dirname( $path ),
                               $self->postfix.$self->basename( $path ) );

      if (-e $to) { $out .= "Already exists $to\n"; next }

      if (move( $path, $to )) { $out .= "Archived $path\n" }
      else {
         $self->throw( error => q(eCannotMove), arg1 => $path, out => $out );
      }
   }

   return $out;
}

sub file_in_use {
   my ($self, $path) = @_;

   return 0 unless ($self->fuser && -x $self->fuser && $path && -e $path);

   my $res = $self->run_cmd( $self->fuser.q( ).$path );

   return $res->stdout ? 1 : 0;
}

sub get_file_systems {
   my ($self, $wanted) = @_;

   my $new = bless { file_systems => [], volume => undef }, ref $self || $self;
   my $cmd = 'mount '.($self->fs_type ? '-t '.$self->fs_type : $NUL);

   for my $line (split m{ [\n] }mx, $self->run_cmd( $cmd )->stdout) {
      my ($volume, $filesys) = $line =~ m{ \A (\S+) \s+ on \s+ (\S+) }msx;

      if ($volume && $filesys) {
         push @{ $new->file_systems }, $filesys;
         $new->volume( $volume ) if ($wanted && $filesys eq $wanted);
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
   $perms .= ( ($mode & S_ISUID) && !($mode & S_IXUSR)) ? q(S) : $NUL;
   $perms .= ( ($mode & S_ISUID) &&  ($mode & S_IXUSR)) ? q(s) : $NUL;
   $perms .= (!($mode & S_ISUID) &&  ($mode & S_IXUSR)) ? q(x) : $NUL;
   $perms .= (!($mode & S_ISUID) && !($mode & S_IXUSR)) ? q(-) : $NUL;
   $perms .= ($mode & S_IRGRP) ? q(r) : q(-);
   $perms .= ($mode & S_IWGRP) ? q(w) : q(-);
   $perms .= ( ($mode & S_ISGID) && !($mode & S_IXGRP)) ? q(S) : $NUL;
   $perms .= ( ($mode & S_ISGID) &&  ($mode & S_IXGRP)) ? q(s) : $NUL;
   $perms .= (!($mode & S_ISGID) &&  ($mode & S_IXGRP)) ? q(x) : $NUL;
   $perms .= (!($mode & S_ISGID) && !($mode & S_IXGRP)) ? q(-) : $NUL;
   $perms .= ($mode & S_IROTH) ? q(r) : q(-);
   $perms .= ($mode & S_IWOTH) ? q(w) : q(-);
   $perms .= ( ($mode & S_ISVTX) && !($mode & S_IXOTH)) ? q(T) : $NUL;
   $perms .= ( ($mode & S_ISVTX) &&  ($mode & S_IXOTH)) ? q(t) : $NUL;
   $perms .= (!($mode & S_ISVTX) &&  ($mode & S_IXOTH)) ? q(x) : $NUL;
   $perms .= (!($mode & S_ISVTX) && !($mode & S_IXOTH)) ? q(-) : $NUL;
   return $perms;
}

sub list_subdirectory {
   my ($self, $args) = @_; my ($file, $flds, $href, $mode, $path);

   my $count   = 0;
   my @paths   = ();
   my $pat     = $args->{pattern};
   my $io      = $self->io( $args->{dir} );
   my $new     = CatalystX::Usul::Table->new
      ( align  => { icon     => q(center),
                    nlink    => q(right),
                    size     => q(right) },
        class  => {},
        flds   => [ qw(icon name modestr nlink user
                       group size accessed modified) ],
        hclass => {},
        labels => { accessed => q(Last Accessed),
                    group    => q(Group),
                    icon     => q(&nbsp;),
                    nlink    => q(Links),
                    modestr  => q(Mode),
                    modified => q(Last Modified),
                    name     => q(File Name),
                    size     => q(Size),
                    user     => q(User) }, );

   for (@{ $new->flds }) {
      $new->class->{ $_ } = q(small); $new->hclass->{ $_ } = q(minimal);
   }

   $new->class->{modestr} = q(mono); $new->hclass->{name} = q(some);

   while ($path = $io->next) {
      if (!$pat || ($path->filename =~ m{ $pat }msx)) {
         push @paths, $path->pathname;
      }
   }

   $io->close;

   return $new unless ($paths[0]);

   for $path (sort { lc $a cmp lc $b } @paths) {
      $file = $self->basename( $path );
      $flds = $self->status_for( $path );
      $mode = $self->get_perms( $flds->{mode} );
      $href = $args->{action}.(defined $args->{make_key}
                               ? q(/).$args->{make_key}( $file )
                               : '?file='.$file);

      $flds->{name    } = $file;
      $flds->{modestr } = $mode;
      $flds->{icon    } = _make_icon( $args->{assets}, $href );
      $flds->{user    } = getpwuid $flds->{uid} || $flds->{uid};
      $flds->{group   } = getgrgid $flds->{gid} || $flds->{gid};
      $flds->{accessed} = $self->stamp( $flds->{atime} );
      $flds->{modified} = $self->stamp( $flds->{mtime} );

      push @{ $new->values }, $flds;
      $count++;
   }

   $new->count( $count );
   return $new;
}

sub purge_tree {
   my ($self, $dir, $atime, $dtime) = @_; my $postfix = $self->postfix;

   my ($archive, $delete, $out, $path, @paths, $ref, $to);

   $archive = defined $atime && $atime == 0 ? 0 : 1;
   $atime   = defined $atime ? $atime : 7;
   $delete  = defined $dtime && $dtime == 0 ? 0 : 1;
   $dtime   = defined $dtime ? $dtime : 2 * $atime;

   $self->throw( q(eNoPath) ) unless ($dir);
   $self->throw( error => q(eNotFound), arg1 => $dir ) unless (-d $dir);

   if ($archive) {
      $out    = 'Archiving files more than '.$atime.' days old in '.$dir."\n";
      $atime  = time - ($atime * 86_400);
      @paths  = ();

      my $match_arc_files = sub {
         if (-f $_ && $_ !~ m{ \A $postfix }mx && (stat _)[9] < $atime) {
            push @paths, $_;
         }

         return;
      };

      find( { no_chdir => 1, wanted => $match_arc_files }, $dir );

      if ($paths[0]) {
         for $path (@paths) { $out .= $self->archive( $path ) }
      }
      else { $out .= 'Nothing to archive in '.$dir."\n" }
   }

   if ($delete) {
      $out  .= 'Deleting files more than '.$dtime.' days old in '.$dir."\n";
      $dtime = time - ($dtime * 86_400);
      @paths = ();

      my $match_old_files = sub {
         push @paths, $_ if (-f $_ && (stat _)[9] < $dtime); return;
      };

      find( { no_chdir => 1, wanted => $match_old_files }, $dir );

      if ($paths[0]) {
         for $path (@paths) {
            if (unlink $path) { $out .= 'Deleted '.$path."\n" }
            else {
               $self->throw( error => q(eCannotDelete),
                           arg1  => $path,
                           out   => $out );
            }
         }
      }
      else { $out .= 'Nothing to delete in '.$dir."\n"  }
   }

   return $out;
}

sub rotate {
   my ($self, @rest) = @_; my $args = $self->arg_list( @rest );
   my ($copy_no, $logfile, $ncopies, $next_no, $pid);

   $ncopies = $args->{ncopies} || 0;

   $pid = $args->{file}
        ? $self->io( $args->{file} )->chomp->lock->getline : $args->{pid};

   for $logfile (@{ $args->{logfiles} }) {
      $copy_no = $ncopies;

      while ($copy_no > 0) {
         $next_no = $copy_no - 1;

         move( $logfile.q(.).$next_no, $logfile.q(.).$copy_no )
            if (-e $logfile.q(.).$next_no);

         $copy_no = $next_no;
      }

      move( $logfile, $logfile.q(.).0 );

      unless ($args->{notouch}) {
         $self->io( $logfile )->perms( $args->{mode} )->touch;
         chown $args->{owner}, $args->{group}, $logfile
            if (defined $args->{owner} && defined $args->{group});
      }

      CORE::kill $args->{sig}, $pid if (defined $args->{sig} && defined $pid);
   }

   return 0;
}

sub rotate_logs {
   my ($self, $dir, $copies) = @_; my (%files, $io, $logfile, $out, $path);

   $out = $NUL; %files = (); $copies ||= 5; $dir ||= $self->logsdir;

   $io = $self->io( $dir );

   while ($path = $io->next) {
      if ($path->filename =~ m{ \.log \z }xms) {
         $logfile = $self->basename( $path->filename, '.log' );
         $files{ $logfile } = 1;
      }
   }

   $io->close;

   for $logfile (sort { uc $a cmp uc $b } keys %files) {
      $path = $self->catfile( $dir, $logfile ).'.log';
      $out .= 'Rotating '.$path."\n";
      $self->rotate( logfiles => [ $path ], ncopies => $copies );
   }

   return $out;
}

sub unarchive {
   # TODO: Implement this
}

sub wait_for {
   my ($self, $vars, $key, $max_wait, $no_thrash) = @_;
   my ($elapsed, $out, $path, $ref, $rep, $start);

   $self->throw( q(eNoKey) ) unless ($key);

   unless ($ref = $self->ctldata->{wait_for}->{ $key }) {
      $self->throw( error => q(eNoData), arg1 => $key );
   }

   $path  = $ref && $ref->{path} ? $ref->{path} : $NUL;
   ($rep) = $path =~ m{ % (\w+) % }msx;

   if ($rep) {
      $rep = $vars->{ $rep } || $NUL; $path =~ s{ % (\w+) % }{ $rep }gmsx;
   }

   $self->throw( error => q(eNoPath), arg1 => $key, rv => 2 ) unless ($path);

   $max_wait  = 60 unless ($max_wait);
   $out       = "Waiting for $path for $max_wait minutes\n";
   $max_wait *= 60;
   $no_thrash = $no_thrash && $no_thrash > $self->no_thrash
              ? $no_thrash : $self->no_thrash;
   $start     = time;
   $elapsed   = 0;

   while (!-f $path || $self->file_in_use( $path )) {
      $elapsed = time - $start;

      if ($elapsed > $max_wait) {
         $self->throw( error => q(eTimeOut), arg1  => $path,
                       out   => $out,        rv    => 3 );
      }

      sleep $no_thrash;
   }

   $out .= "Found $path after $elapsed seconds\n";
   return $out;
}

# Private subroutines

sub _make_icon {
   my ($assets, $href) = @_;

   return { container => 0,
            fhelp     => 'File',
            href      => $href,
            imgclass  => q(normal),
            sep       => q(),
            text      => $assets.q(f.gif),
            type      => q(anchor),
            widget    => 1 };
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::FileSystem - File system related methods

=head1 Version

0.1.$Revision: 402 $

=head1 Synopsis

   package CatalystX::Usul::Model::FileSystem;

   use CatalystX::Usul::FileSystem;

   1;

   package MyApp::Model::FileSystem;

   use base qw(CatalystX::Usul::Model::FileSystem);

   1;

   package MyApp::Controller::Foo;

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
I<file.0> to I<file.1>, I<file.1> to I<file.2> and so on. Will also
C<touch> a new logfile into existence and optionally signal a process

=head2 rotate_logs

Calls L</rotate> on all of the I<.log> files in the given directory, which
defaults to the logs directory

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

=item L<CatalystX::Usul::Table>

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
