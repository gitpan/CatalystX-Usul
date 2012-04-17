# @(#)$Id: CLI.pm 1181 2012-04-17 19:06:07Z pjf $

package CatalystX::Usul::CLI;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.7.%d', q$Rev: 1181 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Programs);

use CatalystX::Usul::Constants;
use CatalystX::Usul::FileSystem;
use CatalystX::Usul::Functions qw(arg_list say);
use CatalystX::Usul::ProjectDocs;
use CatalystX::Usul::TapeBackup;
use CatalystX::Usul::Time;
use English qw(-no_match_vars);
use File::DataClass::Schema;
use File::Find qw(find);
use File::Spec;
use MRO::Compat;

__PACKAGE__->mk_accessors( qw(intfdir rprtdir) );

my %CONFIG = ( delete_after => 35,
               file_class   => q(CatalystX::Usul::FileSystem),
               tape_class   => q(CatalystX::Usul::TapeBackup), );

sub new {
   my ($self, @rest) = @_;

   my $attrs = { config => \%CONFIG, %{ arg_list @rest } };
   my $new   = $self->next::method( $attrs );

   $new->intfdir( $new->catfile( $new->config->{vardir}, q(transfer) ) );
   $new->rprtdir( $new->catfile( $new->config->{root  }, q(reports)  ) );
   $new->version( $VERSION );

   return $new;
}

sub archive : method {
   my ($self, @rest) = @_; defined $rest[ 0 ] or @rest = @ARGV;

   $self->output( $self->_fs_obj->archive( @rest ) );
   return OK;
}

sub dump_meta : method {
   $_[ 0 ]->dumper( $_[ 0 ]->get_meta ); return OK;
}

sub house_keeping : method {
   my $self = shift;

   # This is a safety feature
   my $dir = File::Spec->tmpdir; $dir and -d $dir and chdir $dir;

   # Delete old files from the application tmp directory
   $dir = $self->tempdir; $dir and -d $dir and $self->purge_tree( $dir, 0, 3 );

   # Delete old html reports from the web server's document area
   if ($dir = $self->rprtdir and -d $dir) {
      find( { no_chdir => 1, wanted => \&__match_dot_files }, $dir );
      $self->purge_tree( $dir, 0, $self->config->{delete_after} );
   }

   # Purge old feed files from the interface directory structure
   if ($dir = $self->intfdir and -d $dir) {
      $self->info( "Deleting old files from ${dir}" );
      find( { no_chdir => 1, wanted => \&__match_dot_files }, $dir );

      for my $entry ($self->io( $dir )->all_dirs( 1 )) {
         my $delete_after = $self->config->{delete_after};
         my $path         = $self->catfile( $entry->pathname, q(.house) );

         if (-f $path) {
            for (grep { m{ \A mtime= }imsx }
                 $self->io( $path )->chomp->getlines) {
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

sub lock_list : method {
   my $self = shift; my $line;

   for my $ref (@{ $self->lock->list || [] }) {
      $line  = $ref->{key}.q(,).$ref->{pid}.q(,);
      $line .= time2str( '%Y-%m-%d %H:%M:%S', $ref->{stime} ).q(,);
      $line .= $ref->{timeout};
      say $line;
   }

   return OK;
}

sub lock_reset : method {
   $_[ 0 ]->lock->reset( %{ $_[ 0 ]->args } ); return OK;
}

sub lock_set : method {
   $_[ 0 ]->lock->set( %{ $_[ 0 ]->args } ); return OK;
}

sub pod2html : method {
   my $self    = shift;
   my $cfg     = $self->config;
   my $libroot = $ARGV[ 0 ] || $self->catdir( $cfg->{appldir}, q(lib) );
   my $htmldir = $self->catdir( $ARGV[ 1 ] || $cfg->{root}, q(html) );
   my $meta    = $self->get_meta;

   $self->info( 'Creating HTML from POD for '.$meta->name.SPC.$meta->version );

   $libroot =~ m{ \s+ }mx and $libroot = [ split m{ \s+ }mx, $libroot ];

   CatalystX::Usul::ProjectDocs->new( outroot => $htmldir,
                                      libroot => $libroot,
                                      title   => $meta->name,
                                      desc    => $meta->abstract,
                                      lang    => LANG, )->gen;

   my ($uid, $gid) = $self->get_owner( $self->read_post_install_config );

   if (defined $uid and defined $gid and -d $htmldir) {
      $self->run_cmd( [ qw(chown -R), $uid.q(:).$gid, $htmldir ] );
      chown $uid, $gid, $htmldir;
   }

   return OK;
}

sub purge_tree : method {
   my ($self, @rest) = @_; defined $rest[ 0 ] or @rest = @ARGV;

   $self->info( $self->_fs_obj->purge_tree( @rest ) );
   return OK;
}

sub rotate_logs : method {
   my ($self, @rest) = @_; defined $rest[ 0 ] or @rest = @ARGV;

   $self->info( $self->_fs_obj->rotate_logs( @rest ) );
   return OK;
}

sub tape_backup : method {
   my ($self, @rest) = @_; defined $rest[ 0 ] or @rest = @ARGV; my $args = {};

   $args->{debug       } = $self->{debug};
   $args->{default_tape} = $self->{os   }->{default_tape}->{value};
   $args->{lang        } = $self->{lang };

   my $tape_obj = $self->config->{tape_class}->new( $self, $args );

   $self->info( $tape_obj->process( $self->vars, @rest ) );
   return OK;
}

sub translate : method {
   my ($self, @rest) = @_; defined $rest[ 0 ] or @rest = @ARGV; my $path;

   my $file_obj = File::DataClass::Schema->new( { ioc_obj => $self } );

   $self->vars->{from} = $self->io( $rest[ 0 ] );
   $self->vars->{to  } = $path = $self->io( $rest[ 1 ] );
   $file_obj->translate( $self->vars );
   $self->info( "Path ${path} size ".$path->stat->{size}.' bytes' );
   return OK;
}

sub unarchive : method {
   my ($self, @rest) = @_; defined $rest[ 0 ] or @rest = @ARGV;

   $self->output( $self->_fs_obj->unarchive( @rest ) );
   return OK;
}

sub wait_for : method {
   my ($self, @rest) = @_; defined $rest[ 0 ] or @rest = @ARGV;

   my $cfg    = $self->config;
   my $path   = [ $cfg->{ctrldir}, q(misc).$cfg->{conf_extn} ];
   my $data   = $self->file_dataclass_schema->load( $path );
   my $fs_obj = $self->_fs_obj( {
      ctldata => $data, fuser => $self->os->{fuser}->{value} } );

   $self->info( $fs_obj->wait_for( $self->vars, @rest ) );
   return OK;
}

# Private _methods

sub _fs_obj {
   return $_[ 0 ]->config->{file_class}->new( $_[ 1 ], $_[ 0 ] );
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

0.7.$Revision: 1181 $

=head1 Synopsis

   package YourApp;

   use parent q(CatalystX::Usu::CLI);

=head1 Description

=head1 Subroutines/Methods

=head2 new

=head2 archive

=head2 dump_meta

=head2 house_keeping

=head2 lock_list

=head2 lock_reset

=head2 lock_set

=head2 pod2html

=head2 purge_tree

=head2 rotate_logs

=head2 tape_backup

=head2 translate

=head2 unarchive

=head2 wait_for

=head1 Private Methods

=head2 _fs_obj

=head1 Private Subroutines

=head2 __match_dot_files

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Programs>

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
