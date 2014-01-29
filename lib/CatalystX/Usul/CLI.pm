# @(#)$Ident: CLI.pm 2014-01-10 21:16 pjf ;

package CatalystX::Usul::CLI;

use strict;
use namespace::sweep;
use version; our $VERSION = qv( sprintf '0.17.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Moo;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw( bson64id bson64id_time emit io );
use CatalystX::Usul::FileSystem;
use CatalystX::Usul::ProjectDocs;
use CatalystX::Usul::TapeBackup;
use Class::Usul::Functions     uuid => { -prefix => 'my_' };
use Class::Usul::Options;
use Class::Usul::Time          qw( nap time2str );
use English                    qw( -no_match_vars );
use File::DataClass::Types     qw( Int Object Path );
use File::Find                 qw( find );
use File::Spec::Functions      qw( catdir catfile tmpdir );

extends q(Class::Usul::Programs);
with    q(Class::Usul::TraitFor::MetaData);
with    q(CatalystX::Usul::TraitFor::PostInstallConfig);

option 'delete_after' => is => 'ro', isa => Int, default => 35,
   documentation => 'Housekeeping deletes archive file after this many days';

has '_filesys'  => is => 'lazy', isa => Object, builder => sub {
   CatalystX::Usul::FileSystem->new( builder => $_[ 0 ] ) },
   reader       => 'filesys';

has '_intfdir'  => is => 'lazy', isa => Path,
   builder      => sub { [ $_[ 0 ]->config->vardir, 'transfer' ] },
   coerce       => Path->coercion, reader => 'intfdir';

has '_tape_dev' => is => 'lazy', isa => Object, builder => sub {
   CatalystX::Usul::TapeBackup->new( builder => $_[ 0 ] ), },
   reader       => 'tape_dev';

has '_rprtdir'  => is => 'lazy', isa => Path,
   builder      => sub { [ $_[ 0 ]->config->root, 'reports' ] },
   coerce       => Path->coercion, reader => 'rprtdir';

# Public methods
sub archive : method {
   my ($self, @args) = @_; defined $args[ 0 ] or @args = @{ $self->extra_argv };

   $self->info( $self->filesys->archive( @args ) );
   return OK;
}

sub bson64_id : method {
   my ($self, @args) = @_; defined $args[ 0 ] or @args = @{ $self->extra_argv };

   for (1 .. ($args[ 0 ] ? $args[ 0 ] : 1)) {
      my $id = bson64id(); $self->quiet ? emit $id : $self->output( $id );

      $args[ 1 ] and nap 0.07; $args[ 2 ] or next;

      my $time = time2str undef, bson64id_time( $id );

      $self->quiet ? emit $time : $self->output( $time );
   }

   return OK;
}

sub dump_meta : method {
   $_[ 0 ]->dumper( $_[ 0 ]->get_package_meta ); return OK;
}

sub house_keeping : method {
   my $self = shift;

   # This is a safety feature
   my $dir = tmpdir(); $dir and -d $dir and chdir $dir;

   # Delete old files from the application tmp directory
   $dir = $self->file->tempdir;
   $dir and -d $dir and $self->purge_tree( $dir, 0, 3 );

   # Delete old html reports from the web server's document area
   if ($dir = $self->rprtdir and -d $dir) {
      find( { no_chdir => 1, wanted => \&__match_dot_files }, $dir );
      $self->purge_tree( $dir, 0, $self->delete_after );
   }

   # Purge old feed files from the interface directory structure
   if ($dir = $self->intfdir and -d $dir) {
      $self->info( "Deleting old files from ${dir}" );
      find( { no_chdir => 1, wanted => \&__match_dot_files }, $dir );

      for my $entry (io( $dir )->all_dirs( 1 )) {
         my $delete_after = $self->delete_after;
         my $path         = catfile( $entry->pathname, '.house' );

         if (-f $path) {
            for (grep { m{ \A mtime= }imsx } io( $path )->chomp->getlines) {
               $delete_after = (split m{ = }mx, $_)[ 1 ];
               last;
            }
         }

         $self->info( "Path ${entry} mod time ${delete_after}" );
         $self->purge_tree( $entry->pathname, 0, $delete_after );
      }
   }

   $self->rotate_logs;
   return OK;
}

sub pod2html : method {
   my $self    = shift;
   my $cfg     = $self->config;
   my $libroot = $self->extra_argv->[ 0 ] || catdir( $cfg->appldir, 'lib' );
   my $htmldir = catdir( $self->extra_argv->[ 1 ] || $cfg->root, 'html' );
   my $css     = catfile( $cfg->ctrldir, 'podstyle.css' );
   my $meta    = $self->get_package_meta;

   $self->info( 'Creating HTML from POD for '.$meta->name.SPC.$meta->version );

   $libroot =~ m{ \s+ }mx and $libroot = [ split m{ \s+ }mx, $libroot ];

   CatalystX::Usul::ProjectDocs->new( cssfile => $css,
                                      desc    => $meta->abstract,
                                      lang    => LANG,
                                      libroot => $libroot,
                                      outroot => $htmldir,
                                      title   => $meta->name, )->gen;

   my ($uid, $gid) = $self->get_owner( $self->read_post_install_config );

   if (defined $uid and defined $gid and -d $htmldir) {
      $self->run_cmd( [ qw( chown -R ), "${uid}:${gid}", $htmldir ],
                      { err => 'null', expected_rv => 1 } );
      chown $uid, $gid, $htmldir;
   }

   return OK;
}

sub purge_tree : method {
   my ($self, @args) = @_; defined $args[ 0 ] or @args = @{ $self->extra_argv };

   $self->info( $self->filesys->purge_tree( @args ) );
   return OK;
}

sub rotate_logs : method {
   my ($self, @args) = @_; defined $args[ 0 ] or @args = @{ $self->extra_argv };

   $self->info( $self->filesys->rotate_logs( @args ) );
   return OK;
}

sub tape_backup : method {
   my ($self, @args) = @_; defined $args[ 0 ] or @args = @{ $self->extra_argv };

   $self->info( $self->tape_dev->process( $self->options, @args ) );
   return OK;
}

sub translate : method {
   my ($self, @args) = @_; defined $args[ 0 ] or @args = @{ $self->extra_argv };

   $self->options->{from} = io $args[ 0 ];
   $self->options->{to  } = my $path = io $args[ 1 ];
   $self->file->dataclass_schema->translate( $self->options );
   $self->info( "Path ${path} size ".$path->stat->{size}.' bytes' );
   return OK;
}

sub unarchive : method {
   my ($self, @args) = @_; defined $args[ 0 ] or @args = @{ $self->extra_argv };

   $self->info( $self->filesys->unarchive( @args ) );
   return OK;
}

sub uuid : method {
   my $self = shift; my $uuid = my_uuid;

   $self->quiet ? emit $uuid : $self->output( $uuid );
   return OK;
}

sub wait_for : method {
   my ($self, @args) = @_; defined $args[ 0 ] or @args = @{ $self->extra_argv };

   $self->info( $self->filesys->wait_for( $self->options, @args ) );
   return OK;
}

# Private subroutines
sub __match_dot_files {
   my $now = time;

   -f $_ and $_ =~ m{ \A \.\w+ }msx and utime $now, $now, $_;
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::CLI - Subroutines accessed from the command line

=head1 Version

Describes v0.17.$Rev: 1 $

=head1 Synopsis

   use CatalystX::Usul::CLI;

   exit CatalystX::Usul::CLI->new_with_options
      ( appclass => 'YourApp' )->run;

=head1 Description

Some generic methods that may be applied to multiple applications. They can
be called via the command line. See L<Class::Usul::Programs>

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item delete_after

Integer which defaults to I<35>. House keeping deletes archive file
after this many days

=back

=head1 Subroutines/Methods

=head2 archive

   $exit_code = $self->archive( @paths );

Calls L<archive|CatalystX::Usul::FileSystem/archive>. The remaining
non switch extra argument values from the command line will be used
as the list of paths to archive

=head2 bson64_id

   $exit_code = $self->bson64_id( $count );

Exposes L<bson64id|Class::Usul::Functions/bson64id>. Outputs C<$count>
(defaults to one) BSON64 ids

=head2 dump_meta

   $exit_code = $self->dump_meta;

Use L<Data::Printer> to dump the applications F<META.yml> file

=head2 house_keeping

   $exit_code = $self->house_keeping;

Deletes old files from the applications temporary file directory. Archives and
deletes old report files from the applications report directory. Archives and
deletes old data files from the applications data file interface directory
tree. Rotates the log files in the applications log file directory

=head2 pod2html

   $exit_code = $self->pod2html;

Uses L<CatalystX::Usul::ProjectDocs> to generate HTML documentation from
the applications POD. Non default code library directory is the first non
switch argument value on the command line followed by a non default
root directory for the HTML output

=head2 purge_tree

   $exit_code = $self->purge_tree( $directory, $archive_time, $delete_time );

Archive and subsequently delete files from the specified directory tree
once they have become sufficiently old. The C<$directory> is the first non
switch argument value on the command line

=head2 rotate_logs

   $exit_code = $self->rotate_logs( $directory, $copies, $extension );

Rotate the log files (with optional file extension if it is not
I<.log>) in the specified directory. Defaults to keeping the last five
files. The C<$directory> is the first non switch argument value on the
command line

=head2 tape_backup

   $exit_code = $self->tape_backup( @paths );

Calls the L<tape backup|CatalystX::Usul::TapeBackup/process>
method. Passes any key / value pairs from the command line options as
the first argument, followed by a list of paths from the extra non
switch arguments on the command line

=head2 translate

   $exit_code = $self->translate( @paths );

Uses L<File::DataClass> to translate from one file format to another

=head2 unarchive

   $exit_code = $self->unarchive( @paths );

Reverses the action of L</archive>

=head2 uuid

   $exit_code = $self->uuid

Outputs a UUID from the system

=head2 wait_for

   $exit_code = $self->wait_for( $key, $max_wait, $no_thrash );

Waits for a specified file for a specified time

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::TraitFor::PostInstallConfig>

=item L<CatalystX::Usul::Constants>

=item L<CatalystX::Usul::FileSystem>

=item L<CatalystX::Usul::ProjectDocs>

=item L<CatalystX::Usul::TapeBackup>

=item L<Class::Usul::Programs>

=item L<CatalystX::Usul::Moose>

=item L<CatalystX::Usul::Constraints>

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
