# @(#)$Id: File.pm 1139 2012-03-28 23:49:18Z pjf $

package CatalystX::Usul::File;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1139 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(create_token is_arrayref throw);
use English qw(-no_match_vars);
use File::DataClass::IO ();
use File::DataClass::Schema;
use File::Spec;
use Scalar::Util qw(blessed);

# requires qw(tempdir);

sub abs_path {
   my ($self, $base, $path) = @_; $base ||= NUL; $path or return NUL;

   is_arrayref $base and $base = File::Spec->catdir( $base );

   return $self->io( $path )->absolute( $base );
}

sub basename {
   my ($self, $path, @suffixes) = @_;

   return $self->io( $path )->basename( @suffixes );
}

sub catdir {
   my ($self, @rest) = @_; return File::Spec->catdir( @rest );
}

sub catfile {
   my ($self, @rest) = @_; return File::Spec->catfile( @rest );
}

sub classdir {
   return File::Spec->catdir( split m{ :: }mx, $_[ 1 ] );
}

sub classfile {
   return File::Spec->catfile( split m{ :: }mx, $_[ 1 ].q(.pm) );
}

sub delete_tmp_files {
   return $_[ 0 ]->io( $_[ 1 ] || $_[ 0 ]->tempdir )->delete_tmp_files;
}

sub dirname {
   return $_[ 0 ]->io( $_[ 1 ] )->dirname;
}

sub file_dataclass_schema {
   my ($self, $attrs) = @_; $attrs = { %{ $attrs || {} } };

   blessed $self and $attrs->{ioc_obj} = $self;

   delete $attrs->{cache} or $attrs->{cache_class} = q(none);
   delete $attrs->{lock } or $attrs->{lock_class } = q(none);

   return File::DataClass::Schema->new( $attrs );
}

sub find_source {
   my ($self, $class) = @_; my $file = $self->classfile( $class );

   for (@INC) {
      my $path = File::Spec->catfile( $_, $file ); -f $path and return $path;
   }

   return;
}

sub io {
   my ($self, @rest) = @_; my $io = File::DataClass::IO->new( @rest );

   $io->exception_class( EXCEPTION_CLASS ); return $io;
}

sub status_for {
   return $_[ 0 ]->io( $_[ 1 ] )->stat;
}

sub symlink {
   my ($self, $base, $from, $to) = @_;

   $from or throw 'Symlink path from undefined';
   $from = $self->abs_path( $base, $from );
   $from->exists or
      throw error => 'Path [_1] does not exist', args => [ $from->pathname ];
   $to or throw 'Symlink path to undefined';
   $to   = $self->io( $to ); -l $to->pathname and $to->unlink;
   $to->exists and
      throw error => 'Path [_1] already exists', args => [ $to->pathname ];
   CORE::symlink $from->pathname, $to->pathname or throw $ERRNO;
   return "Symlinked ${from} to ${to}";
}

sub tempfile {
   return $_[ 0 ]->io( $_[ 1 ] || $_[ 0 ]->tempdir )->tempfile;
}

sub tempname {
   my ($self, $dir) = @_; my $path;

   while (not $path or -f $path) {
      my $file = sprintf '%6.6d%s', $PID, (substr create_token, 0, 4);

      $path = File::Spec->catfile( $dir || $self->tempdir, $file );
   }

   return $path;
}

sub uuid {
   return $_[ 0 ]->io( $_[ 1 ] || UUID_PATH )->lock->chomp->getline;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::File - File and directory IO base class

=head1 Version

0.5.$Revision: 1139 $

=head1 Synopsis

   package MyBaseClass;

   use base qw(CatalystX::Usul::File);

=head1 Description

Provides file and directory methods to the application base class

=head1 Subroutines/Methods

=head2 abs_path

   $absolute_path = $self->_abs_path( $base, $path );

Prepends F<$base> to F<$path> unless F<$path> is an absolute path

=head2 basename

   $basename = $self->basename( $path, @suffixes );

Returns the L<base name|File::Basename/basename> of the passed path

=head2 catdir

   $dir_path = $self->catdir( $part1, $part2 );

Expose L<File::Spec/catdir>

=head2 catfile

   $file_path = $self->catfile( $dir_path, $file_name );

Expose L<File::Spec/catfile>

=head2 classdir

   $dir_path = $self->classdir( __PACKAGE__ );

Returns the path (directory) of a given class. Like L</classfile> but
without the I<.pm> extenstion

=head2 classfile

   $file_path = $self->classfile( __PACKAGE__ );

Returns the path (file name plus extension) of a given class. Uses
L<File::Spec> for portability, e.g. C<App::Munchies> becomes
C<App/Munchies.pm>

=head2 delete_tmp_files

   $self->delete_tmp_files( $dir );

Delete this processes temporary files. Files are in the C<$dir> directory
which defaults to C<< $self->tempdir >>

=head2 dirname

   $dirname = $self->dirname( $path );

Returns the L<directory name|File::Basename/dirname> of the passed path

=head2 file_dataclass_schema

   $f_dc_schema_obj = $self->file_dataclass_schema( $attrs );

Returns a L<File::DataClass::Schema> object. Object uses our
C<exception_class>, no caching and no locking

=head2 find_source

   $path = $self->find_source( $module_name );

Find the source code for the given module

=head2 io

   $io_obj = $self->io( $pathname );

Expose the methods in L<File::DataClass::IO>

=head2 status_for

   $stat_ref = $self->status_for( $path );

Return a hash for the given path containing it's inode status information

=head2 symlink

   $out_ref = $self->symlink( $base, $from, $to );

Creates a symlink. If either C<$from> or C<$to> is a relative path then
C<$base> is prepended to make it absolute. Returns a message indicating
success or throws an exception on failure

=head2 tempfile

   $tempfile_obj = $self->tempfile( $dir );

Returns a L<File::Temp> object in the C<$dir> directory
which defaults to C<< $self->tempdir >>. File is automatically deleted
if the C<$tempfile_obj> reference goes out of scope

=head2 tempname

   $pathname = $self->tempname( $dir );

Returns the pathname of a temporary file in the given directory which
defaults to C<< $self->tempdir >>. The file will be deleted by
L</delete_tmp_files> if it is called otherwise it will persist

=head2 uuid

   $uuid = $self->uuid;

Return the contents of F</proc/sys/kernel/random/uuid>

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Constants>

=item L<Digest>

=item L<File::DataClass::IO>

=item L<File::Temp>

=back

=head1 Incompatibilities

The C</uuid> method with only work on a OS with a F</proc> filesystem

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
