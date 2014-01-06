# @(#)Ident: ;

package CatalystX::Usul::FileSystem;

use strict;
use version; our $VERSION = qv( sprintf '0.15.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions   qw(arg_list throw);
use Class::Usul::File;
use Class::Usul::IPC;
use Class::Usul::Time;
use Fcntl                        qw(:mode);
use File::Basename               qw(basename dirname);
use File::Copy;
use CatalystX::Usul::Constraints qw(Path);
use File::Find;
use File::Spec::Functions        qw(catfile);

has 'compress_logs'  => is => 'ro',   isa => Bool, default => TRUE;

has 'config_path'    => is => 'lazy', isa => Path, coerce => TRUE,
   default           => sub { [ $_[ 0 ]->config->ctrldir, q(misc.json) ] };

has 'ctldata'        => is => 'lazy', isa => HashRef;

has 'fcopy_format'   => is => 'ro',   isa => NonEmptySimpleStr,
   default           => q(%{file}.%{copy});

has 'fs_type'        => is => 'ro',   isa => NonEmptySimpleStr,
   default           => 'ext3';

has 'fuser'          => is => 'ro',   isa => SimpleStr, default => NUL;

has 'postfix'        => is => 'ro',   isa => SimpleStr, default => 'A_';

has 'response_class' => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default           => sub { 'CatalystX::Usul::Response::FileSystem' };

has 'table_class'    => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default           => sub { 'Class::Usul::Response::Table' };

has 'usul'           => is => 'ro',   isa => BaseClass,
   handles           => [ qw(config debug lock log) ], init_arg => 'builder',
   required          => TRUE, weak_ref => TRUE;


has '_file' => is => 'lazy', isa => FileClass,
   default  => sub { Class::Usul::File->new( builder => $_[ 0 ]->usul ) },
   handles  => [ qw(io) ], init_arg => undef, reader => 'file';

has '_ipc'  => is => 'lazy', isa => IPCClass,
   default  => sub { Class::Usul::IPC->new( builder => $_[ 0 ]->usul ) },
   handles  => [ qw(run_cmd) ], init_arg => undef, reader => 'ipc';

around 'BUILDARGS' => sub {
   my ($next, $self, @args) = @_; my $attr = $self->$next( @args );

   my $builder = $attr->{builder} or return $attr;

   if ($builder->can( q(os) )) {
      my $os = $builder->os;

      defined $os->{fs_type} and $attr->{fs_type} //= $os->{fs_type}->{value};
      defined $os->{fuser  } and $attr->{fuser  } //= $os->{fuser  }->{value};
   }

   return $attr;
};

sub archive { # Prepend $self->postfix to file
   my ($self, @paths) = @_; my $out = NUL;

   $paths[ 0 ] or throw 'Archive file path not specified';

   for my $path (@paths) {
      -e $path or throw error => 'Path [_1] does not exist',
                        args  => [ $path ], out => $out;

      my $to = catfile( dirname( $path ), $self->postfix.basename( $path ) );

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

   return $self->run_cmd( [ $self->fuser, $path ] )->stdout ? TRUE : FALSE;
}

sub file_systems {
   return $_[ 0 ]->response_class->new( builder     => $_[ 0 ],
                                        file_system => $_[ 1 ] );
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

   my $io    = $self->io( $args->{dir} );
   my $match = $args->{pattern};
      $match and $io->filter( sub { $_->filename =~ $match } );
   my @paths = $io->all;
   my @rows  = ();
   my $count = 0;

   for my $path (@paths) {
      push @rows, $self->_directory_fields( $path, $args ); $count++;
   }

   return $self->_new_results_table( \@rows, $count );
}

sub purge_tree {
   my ($self, $dir, $atime, $dtime) = @_; my ($archive, $delete, $out);

   $archive = defined $atime && $atime == 0 ? FALSE : TRUE;
   $atime   = defined $atime ?  $atime : 7;
   $delete  = defined $dtime && $dtime == 0 ? FALSE : TRUE;
   $dtime   = defined $dtime ?  $dtime : 2 * $atime;

      $dir or throw 'Directory path not specified';
   -d $dir or throw error => 'Directory [_1] not found', args => [ $dir ];

   $archive and $out .= $self->_find_and_archive( $dir, $atime );

   $delete and $out .= $self->_find_and_delete( $dir, $dtime );

   return $out;
}

sub rotate {
   my ($self, $path, $copies) = @_; my $moves = []; my $copy_no = $copies - 1;

   -e $path or throw error => 'Path [_1] does not exist', args => [ $path ];

   while ($copy_no > 0) {
      my $from = $self->_get_file_copy_path( $path, $copy_no - 1 );
      my $to   = $self->_get_file_copy_path( $path, $copy_no     );

      -e $from        and push @{ $moves }, [ $copy_no, $from, $to ];
      -e "${from}.gz" and push @{ $moves }, [ $copy_no, "${from}.gz",
                                                        "${to}.gz" ];
      $copy_no--;
   }

   push @{ $moves }, [ 0, $path, $self->_get_file_copy_path( $path, 0 ) ];

   for my $move (@{ $moves }) {
      my $from = $move->[ 1 ]; my $to = $move->[ 2 ];

      move( $from, $to ) or throw error => 'Cannot move from [_1] to [_2]',
                                  args  => [ $from, $to ];

      $self->compress_logs and $move->[ 0 ] > 0 and $to !~ m{ \.gz \z }msx
         and $self->run_cmd( [ qw(gzip -f), $to ] );
   }

   return;
}

sub rotate_log {
   my ($self, @rest) = @_; my $args = arg_list @rest;

   my $path = $args->{logfile} or return;
   my $pid  = $args->{pidfile}
            ? $self->io( $args->{pidfile} )->chomp->lock->getline
            : $args->{pid};

   $self->rotate( $path, $args->{copies} || 1 );

   unless ($args->{notouch}) {
      $self->io( $path )->perms( $args->{mode} )->touch;
      defined $args->{owner} and defined $args->{group}
         and chown $args->{owner}, $args->{group}, $path;
   }

   defined $args->{sig} and defined $pid and CORE::kill $args->{sig}, $pid;

   return "Rotated ${path}\n";
}

sub rotate_logs {
   my ($self, $copies, $extn, $dir) = @_; my $out = NUL;

   $copies //= 7; $extn //= q(.log); $dir //= $self->config->logsdir;

   my $io = $self->io( $dir ); my $fcopy = $self->_get_file_copy_regex;

   my $match   = qr{ \Q$extn\E \z }msx;
   my $nomatch = qr{ $fcopy \Q$extn\E (\.gz)? \z }msx;

   $io->filter( sub { $_->filename =~ $match and $_->filename !~ $nomatch } );

   for ($io->all) {
      $out .= $self->rotate_log( copies  => $copies,
                                 logfile => $_, mode => 0640 );
   }

   return $out;
}

sub unarchive {
   my ($self, @paths) = @_; my $out = NUL;

   $paths[ 0 ] or throw 'Archive file path not specified';

   for my $path (@paths) {
      if (-e $path) { $out .= "Already exists ${path}\n"; next }

      my $from = catfile( dirname( $path ), $self->postfix.basename( $path ) );

      -e $from or throw error => 'Path [_1] does not exist',
                        args  => [ $from ], out => $out;

      move( $from, $path ) or throw error => 'Cannot move from [_1] to [_2]',
                                    args  => [ $from, $path ], out => $out;
      $out .= "Unarchived ${path}\n";
   }

   return $out;
}

sub wait_for {
   my ($self, $opts, $key, $max_wait, $no_thrash) = @_;

   $key or throw 'Hash key not specified';

   my $data  = $self->ctldata->{wait_for}->{ $key }
      or throw error => 'Key [_1] has no data', args => [ $key ];
   my $path  = $data->{path} || NUL;
   my ($rep) = $path =~ m{ % (\w+) % }msx;

   if ($rep) {
      $rep = $opts->{ $rep } || NUL; $path =~ s{ % (\w+) % }{ $rep }gmsx;
   }

   $path or throw error => 'Key [_1] path not specified',
                  args  => [ $key ], rv => 2;

   $max_wait  ||= $data->{max_wait} || 60;
   $no_thrash ||= $self->config->no_thrash;
   $no_thrash   < $self->config->no_thrash
      and $no_thrash = $self->config->no_thrash;

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

sub _build_ctldata {
   return $_[ 0 ]->file->data_load( paths => [ $_[ 0 ]->config_path ] );
}

sub _directory_fields {
   my ($self, $path, $args) = @_;

   my $file = $path->basename; my $fields = $path->stat;

   my $href = ($args->{action} || NUL).(defined $args->{make_key}
                                        ? SEP.$args->{make_key}( $file )
                                        : '?file='.$file);

   $fields->{name    } = $file;
   $fields->{modestr } = $self->get_perms( $fields->{mode} );
   $fields->{icon    } = __make_icon( $args->{assets}, $href );
   $fields->{user    } = getpwuid $fields->{uid} || $fields->{uid};
   $fields->{group   } = getgrgid $fields->{gid} || $fields->{gid};
   $fields->{accessed} = time2str( undef, $fields->{atime} );
   $fields->{modified} = time2str( undef, $fields->{mtime} );

   return $fields;
}

sub _find_and_archive {
   my ($self, $dir, $atime) = @_; my $postfix = $self->postfix;

   my $out = "Archiving in ${dir} files more than ${atime} days old\n";

   my @paths = (); $atime = time - ($atime * 86_400);

   my $match_arc_files = sub {
      -f $_ and $_ !~ m{ \A $postfix }mx and (stat _)[ 9 ] < $atime
         and push @paths, $_;
      return;
   };

   find( { no_chdir => TRUE, wanted => $match_arc_files }, $dir );

   if ($paths[ 0 ]) { $out .= $self->archive( $_ ) for (@paths) }
   else { $out .= "Path ${dir} nothing to archive\n" }

   return $out;
}

sub _find_and_delete {
   my ($self, $dir, $dtime) = @_;

   my $out = "Deleting in ${dir} files more than ${dtime} days old\n";

   my @paths = (); $dtime = time - ($dtime * 86_400);

   my $match_old_files = sub {
      -f $_ and (stat _)[ 9 ] < $dtime and push @paths, $_; return;
   };

   find( { no_chdir => TRUE, wanted => $match_old_files }, $dir );

   if ($paths[ 0 ]) {
      for my $path (@paths) {
         unlink $path or throw error => 'Path [_1] cannot delete',
                               args  => [ $path ], out => $out;
         $out .= "Deleted ${path}\n";
      }
   }
   else { $out .= "Path ${dir} nothing to delete\n" }

   return $out;
}

sub _get_file_copy_path {
   my ($self, $path, $copy_no) = @_;

   my $dir  = dirname( $path );
   my $file = basename( $path );
   my $extn = NUL; $file =~ m{ (\.[^\.]+ (\.gz)?) \z }msx and $extn = $1;
   my $base = $file; $extn and $base =~ s{ \Q$extn\E \z }{}msx;
   my $name = $self->fcopy_format;

   $name =~ s{ %\{file\} }{$base}msx; $name =~ s{ %\{copy\} }{$copy_no}msx;

   return $dir ? catfile( $dir, $name.$extn ) : $name.$extn;
}

sub _get_file_copy_regex {
   my $self = shift; my $regex = $self->fcopy_format;

   $regex =~ s{ \. }{\\.}gmsx; $regex =~ s{ %\{file\} }{(.+)}msx;

   $regex =~ s{ %\{copy\} }{\\d+}msx; return $regex;
}

sub _new_results_table {
   my ($self, $rows, $count) = @_; my $class = {}; my $hclass = {};

   my @fields = ( qw(icon name modestr nlink user group size accessed
                     modified) );

   for (@fields) {
      $class->{ $_ } = q(data_value); $hclass->{ $_ } = q(minimal);
   }

   $class->{icon} = q(row_select); $class->{modestr} = q(mono);
   $hclass->{name} = q(some);

   return $self->table_class->new
      ( class    => $class,
        count    => $count,
        fields   => \@fields,
        hclass   => $hclass,
        labels   => { accessed => q(Last Accessed),
                      group    => q(Group),
                      icon     => '&#160;',
                      nlink    => q(Links),
                      modestr  => q(Mode),
                      modified => q(Last Modified),
                      name     => q(File Name),
                      size     => q(Size),
                      user     => q(User) },
        typelist => { accessed => q(date),    modified => q(date),
                      nlink    => q(numeric), size     => q(numeric) },
        values   => $rows, );
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

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::FileSystem - File system related methods

=head1 Version

Describes v0.15.$Rev: 1 $

=head1 Synopsis

   use Class::Usul;
   use CatalystX::Usul::FileSystem;

   my $usul    = Class::Usul->new( config => {} );
   my $filesys = CatalystX::Usul::FileSystem->new( builder => $usul );
   my $table   = $filesys->list_subdirectory( { dir => 'path_to_directory' } );

=head1 Description

This model provides methods for manipulating files and directories

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item C<compress_logs>

Boolean defaults to true. Causes the L</rotate_logs> methods to compress
logs files after the first copy

=item C<config_path>

A path to a file containing control data. Defaults to the F<misc> file
in the C<ctrldir> directory

=item C<ctldata>

Hash ref of control data loaded from file referenced by C<config_path>
attribute

=item C<fcopy_format>

A non empty simple string which defaults to C<%{file}.%{copy}>. Used
by L</rotate_logs> to insert the copy number into the file name. The
C<%{file}> symbol is replaced by the file name and the C<%{copy}>
symbol is replaced by the copy number. Literal text remains unaffected

=item C<fs_type>

String which defaults to C<ext3>. The default filesystem type

=item C<fuser>

String which defaults to the value returned by the usul config
object. The path to the external C<fuser> command

=item C<postfix>

String which defaults to C<A_>. Prepended to filename when archived

=back

=head1 Subroutines/Methods

=head2 archive

   $output_messages = $self->archive( @paths );

Archives a files by prepending the C<$self->postfix>, which
defaults to C<A_>

=head2 file_in_use

   $bool = $self->file_in_use( $path );

Uses the system C<fuser> command if it is available to determine if a file
is in use

=head2 file_systems

   $filesystem_responce_object = $self->file_systems( $filesysem );

Parses the output from the system C<mount> command to produce a list of
file systems. Includes details of the specified filesystem

=head2 get_perms

   $permission_string = $self->get_perms( $mode );

Returns the C<-rw-rw-r--> style permission string for a given octal mode

=head2 list_subdirectory

   $table_object = $self->list_subdirectory( $director_path );

Generates the table data for a directory listing. The data is used by
the C<table> subclass of L<HTML::FormWidgets>

=head2 purge_tree

   $output_messages = $self->purge_tree( $dir, $atime, $dtime );

Archive old files and delete even older ones from a given directory

=head2 rotate

   $self->rotate( $logfile, $copies );

Issues a sequence a C<move> commands to rename C<file> to C<file.0>,
C<file.0> to C<file.1>, C<file.1> to C<file.2> and so on. If the attribute
C<compress_logs> is true, then copies after the first one are compressed

=head2 rotate_log

   $message = $self->rotate_log( logfile => $logfile_path, copies => $copies );

Calls L</rotate>. Will also C<touch> a new logfile into existence and
optionally signal a process

=head2 rotate_logs

   $output_messages = $self->rotate_logs( $copies, $extension, $directory );

Calls L</rotate_log> on all of the F<.log> files in the given
directory, which defaults to the logs directory. Defaults to keeping seven
copies. Run this daily from C<cron>

=head2 unarchive

   $output_messages = $self->unarchive( @paths );

Reverse out the effect of calling L</archive>

=head2 wait_for

   $output_messages = $self->wait_for( $opts, $key, $max_wait, $no_thrash );

Wait for a given file to exist. Polls at given intervals file a configurable
period before throwing a time out error if the file does not show up

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Response::FileSystem>

=item L<Class::Usul::File>

=item L<Class::Usul::IPC>

=item L<CatalystX::Usul::Moose>

=item L<Class::Usul::Response::Table>

=item L<Class::Usul::Time>

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
