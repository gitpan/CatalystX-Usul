package CatalystX::Usul::Build;

# @(#)$Id: Build.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(Module::Build);
use CatalystX::Usul::Programs;
use CatalystX::Usul::Schema;
use Class::C3;
use Config;
use CPAN;
use English qw(-no_match_vars);
use File::Basename;
use File::Copy;
use File::Find;
use File::Path;
use File::Spec::Functions;
use XML::Simple;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

my $SEP = q(/);

my (@paths, $prefix);

sub ACTION_build {
   my $self     = shift;
   my $width    = 50;
   my $prog     = CatalystX::Usul::Programs->new
      ( { appclass => $self->module_name, arglist => q(a ask>a), n => 1 } );
   my $dir      = catdir(  $self->base_dir, q(var), q(etc) );
   my $cfg_path = catfile( $self->base_dir, q(build.xml) );
   my $cfg      = $self->get_config( $prog, $cfg_path );
   my $ask      = exists $prog->args->{a}
                  || ($cfg->{ask} && $cfg->{ask} eq q(yes)) ? 1 : 0;
   my ($phase, $res, $text, $value);

   chmod oct q(0644), $cfg_path;

   return if ($cfg->{built} && $cfg->{built} eq q(yes));

   if ($ask) {
      $text  = 'The application has two modes if installation. In normal ';
      $text .= 'mode it installs all components to a specifed path. In ';
      $text .= 'traditional mode modules are install to the site lib, ';
      $text .= 'executables to the site bin and the rest to a subdirectory ';
      $text .= 'of /var. Installation defaults to normal mode since it is ';
      $text .= 'easier to maintain';
      $prog->output( $text, { cl => 1, fill => 1, nl => 1 } );
      $text  = 'Enter the install mode';
      $cfg->{style} = $prog->get_line( $text, q(normal), 1, $width );
   }

   $cfg->{style} ||= q(normal);

   if ($cfg->{style} eq q(normal)) {
      if ($ask) {
         $text = 'Application name is automatically appended to the prefix';
         $prog->output( $text, { cl => 1, fill => 1, nl => 1 } );
         $text = 'Enter install path prefix';
         $cfg->{new_prefix} =
            $prog->get_line( $text, $self->notes( q(prefix) ), 1, $width );

         exit 1 unless (defined $cfg->{new_prefix});
      }

      $cfg->{new_prefix} ||= $self->notes( q(prefix) );
   }

   ($cfg->{ver}, $phase) = ($self->notes( q(applrel) ) =~ m{ v(.*)p(\d+) }mx);

   if ($ask) {
      $text  = 'Phase number determines at run time the purpose of the ';
      $text .= 'application instance, e.g. live(1), test(2), development(3)';
      $prog->output( $text, { cl => 1, fill => 1, nl => 1 } );
      $text  = 'Enter phase number';
      $cfg->{phase} = $prog->get_line( $text, $cfg->{phase}, 1, $width );

      exit 1 unless (defined $cfg->{phase});
   }

   $cfg->{phase} ||= $phase;

   unless ($cfg->{phase} =~ m{ \A \d+ \z }mx) {
      $prog->fatal( 'Bad phase value (not an integer) '.$cfg->{phase} );
   }

   if ($ask) {
      $text  = 'Use groupadd, useradd, and usermod to create the user ';
      $text .= $cfg->{owner}.' and the groups '.$cfg->{group};
      $text .= ' and '.$cfg->{admin_role};
      $prog->output( $text, { cl => 1, fill => 1, nl => 1 } );
      $text  = 'Create groups and user';

      exit 1 if (($res = $prog->yorn( $text, q(y), 1, $width )) == 2);

      $cfg->{create_ugrps} = $res == 1 ? q(no) : q(yes);
   }

   $cfg->{create_ugrps} ||= q(yes);

   if ($ask and $cfg->{create_ugrps} eq q(yes)) {
      $text  = 'Which user does the Apache web server run as? This user ';
      $text .= 'will be added to the application group so that it can ';
      $text .= 'access the application\'s files';
      $prog->output( $text, { cl => 1, fill => 1, nl => 1 } );
      $text  = 'Web server user';
      $cfg->{apache_user} =
         $prog->get_line( $text, $cfg->{apache_user}, 1, $width );

      exit 1 unless (defined $cfg->{apache_user});
   }

   if ($ask) {
      $text  = 'Enable wrapper which allows limited access to some root ';
      $text .= 'only functions like password checking and user management. ';
      $text .= 'Not necessary unless the Unix authentication store is used';
      $prog->output( $text, { cl => 1, fill => 1, nl => 1 } );
      $text  = 'Enable suid root';

      exit 1 if (($res = $prog->yorn( $text, q(n), 1, $width )) == 2);

      $cfg->{set_uid_root} = $res == 1 ? q(no) : q(yes);
   }

   $cfg->{set_uid_root} ||= q(no);

   if ($ask) {
      $text  = 'Schema creation requires a database, id and password';
      $prog->output( $text, { cl => 1, fill => 1, nl => 1 } );
      $text  = 'Create database schema';

      exit 1 if (($res = $prog->yorn( $text, q(y), 1, $width )) == 2);

      $cfg->{create_schema} = $res == 1 ? q(no) : q(yes);
   }

   $cfg->{create_schema} ||= q(no);

   if ($ask && $cfg->{create_schema} ne q(no)) {
      my $name    = $self->notes( q(dbname) );
      my $path    = catfile( $dir, $name.q(.xml) );
      my ($dbcfg) = $self->get_connect_info( $prog, $path );
      my $prompts = { name     => 'Enter db name',
                      driver   => 'Enter DBD driver',
                      host     => 'Enter db host',
                      port     => 'Enter db port',
                      user     => 'Enter db user',
                      password => 'Enter db password' };
      my $defs    = { name     => $name,
                      driver   => q(_field),
                      host     => q(localhost),
                      port     => q(_field),
                      user     => q(_field),
                      password => q() };

      for my $fld (qw(name driver host port user password)) {
         $value = $defs->{ $fld } eq q(_field) ?
                  $dbcfg->{credentials}->{ $name }->{ $fld } : $defs->{ $fld };
         $value = $prog->get_line( $prompts->{ $fld }, $value, 1, $width, 0,
                                   $fld eq q(password) ? 1 : 0 );

         exit 1 unless (defined $value);

         if ($fld eq q(password)) {
            my $args = { seed => $cfg->{secret} || $cfg->{prefix} };

            $path    = catfile( $dir, $cfg->{prefix}.q(.txt) );
            $args->{data} = $prog->io( $path )->all if (-f $path);
            $value   = CatalystX::Usul::Schema->encrypt( $args, $value );
            $value   = q(encrypt=).$value if ($value);
         }

         $cfg->{credentials}->{ $name }->{ $fld } = $value;
      }
   }

   if ($ask) {
      $text  = 'Execute additional configuration commands. These may take ';
      $text .= 'several minutes to complete';
      $prog->output( $text, { cl => 1, fill => 1, nl => 1 } );
      $text  = 'Run commands';
      exit 1 if (($res = $prog->yorn( $text, q(y), 1, $width )) == 2);

      $cfg->{run_cmd} = $res == 1 ? q(no) : q(yes);

      $text = 'Make this the default version';
      exit 1 if (($res = $prog->yorn( $text, q(y), 1, $width )) == 2);

      $cfg->{make_default} = $res == 1 ? q(no) : q(yes);

      $text = 'Restart web server';
      exit 1 if (($res = $prog->yorn( $text, q(y), 1, $width )) == 2);

      $cfg->{restart_apache} = $res == 1 ? q(no) : q(yes);

      $text = 'Ask questions in future';
      exit 1 if (($res = $prog->yorn( $text, q(n), 1, $width )) == 2);

      $cfg->{ask} = $res == 1 ? q(no) : q(yes);
   }

   $cfg->{built} = q(yes);

   eval { XMLout( $cfg,
                  NoAttr     => 1,
                  OutputFile => $cfg_path,
                  RootName   => q(config) ) };

   $prog->fatal( $EVAL_ERROR ) if ($EVAL_ERROR);
   $prog->anykey()             if ($ask);

   return $self->next::method();
}

sub ACTION_install {
   my $self = shift;
   my $prog = CatalystX::Usul::Programs->new
      ( { appclass => $self->module_name, n => 1 } );
   my $path = catfile( $self->base_dir, q(build.xml) );
   my $cfg  = $self->get_config( $prog, $path );
   my $pref = $cfg->{prefix};
   my ($base, $cmd, $from, $text);

   # Now change default config values and call parent method
   if ($cfg->{style} eq q(normal)) {
      unless (-d $cfg->{new_prefix}) {
         mkpath( $cfg->{new_prefix}, 0, oct q(02750) );
      }

      $prog->fatal( 'Does not exist/cannot create '.$cfg->{new_prefix} )
         unless (-d $cfg->{new_prefix});

      $base = catdir( $cfg->{new_prefix},
                      $prog->class2appdir( $self->module_name ),
                      q(v).$cfg->{ver}.q(p).$cfg->{phase} );
      $self->install_base( $base );
      $self->install_path( bin => catdir( $base, 'bin' ) );
      $self->install_path( lib => catdir( $base, 'lib' ) );
      $self->install_path( var => catdir( $base, 'var' ) );
   }
   else {
      $base = catdir( rootdir, q(var),
                      $prog->class2appdir( $self->module_name ),
                      q(v).$cfg->{ver}.q(p).$cfg->{phase} );
      $self->install_path( var => $base );
   }

   my $bind = $self->install_destination( 'bin' );
   my $libd = $self->install_destination( 'lib' );

   $prog->info( 'Base path '.$base );
   $self->next::method();

   # Create some directories that don't ship with the distro
   for my $dir (@{ $cfg->{create_dirs} }) {
      $dir  = catdir( $base, $dir ) unless ((substr $dir, 0, 1) eq $SEP);

      if (-d $dir) { $prog->info( 'Exists '.$dir ) }
      else {
         $prog->info( 'Creating '.$dir ); mkpath( $dir, 0, oct '0770' );
      }
   }

   # Create some empty log files
   for $path (@{ $cfg->{create_files} }) {
      $path = catdir( $base, $path ) unless ((substr $path, 0, 1) eq $SEP);

      if (! -f $path) {
         $prog->info( 'Creating '.$path ); $prog->io( $path )->touch;
      }
   }

   # Copy some files
   for my $ref (@{ $cfg->{copy_files} }) {
      $from = $ref->{from};
      $path = $ref->{to};
      $from = catdir( $base, $from ) unless ((substr $from, 0, 1) eq $SEP);
      $path = catdir( $base, $path ) unless ((substr $path, 0, 1) eq $SEP);

      if (-f $from && ! -f $path) {
         $prog->info( "Copying $from to $path" );
         copy( $from, $path );
         chmod oct q(0644), $path;
      }
   }

   # Link some files
   for my $ref (@{ $cfg->{link_files} }) {
      $from = $ref->{from};
      $path = $ref->{to};
      $from = catdir( $base, $from ) unless ((substr $from, 0, 1) eq $SEP);
      $path = catdir( $base, $path ) unless ((substr $path, 0, 1) eq $SEP);

      unlink $path if (-e $path && -l $path);

      if (-e $from) {
         if (! -e $path) {
            $prog->info( "Symlinking $from to $path" );
            symlink $from, $path;
         }
         else { $prog->info( "Already exists $path" ) }
      }
      else { $prog->info( "Does not exist $from" ) }
   }

   # Optionally create databases and edit credentials
   if ($cfg->{create_schema} ne q(no)) {
      my $dbname = $self->notes( q(dbname) );

      # Edit the XML config file that contains the database connection info
      if ($cfg->{credentials} && $cfg->{credentials}->{ $dbname }) {
         $path = catfile( $base, 'var', 'etc', $dbname.'.xml' );

         my ($dbcfg, $dtd) = $self->get_connect_info( $prog, $path );

         for my $fld (qw(driver host port user password)) {
            my $value = $cfg->{credentials}->{ $dbname }->{ $fld };
            $value  ||= $dbcfg->{credentials}->{ $dbname }->{ $fld };
            $dbcfg->{credentials}->{ $dbname }->{ $fld } = $value;
         }

         my $wtr = $prog->io( $path );
         my $xs  = XML::Simple->new( NoAttr => 1, RootName => q(config) );

         $wtr->println( $dtd ) if ($dtd);
         $wtr->append( $xs->xml_out( $dbcfg ) );
      }

      # Create the database if we can. Will do nothing if we can't
      $cmd = catfile( $bind, $pref.q(_schema) ).' -n -c create_database';
      $prog->info( $prog->run_cmd( $cmd )->out );

      # Call DBIx::Class::deploy to create the
      # schema and populate it with static data
      $prog->info( 'Deploying schema and populating database' );
      $cmd = catfile( $bind, $pref.q(_schema) ).' -n -c deploy_and_populate';
      $prog->info( $prog->run_cmd( $cmd )->out );
   }

   # Create the two groups used by this application
   if ($cfg->{create_ugrps} ne q(no)) {
      # Create the application group
      $cmd = q(/usr/sbin/groupadd);

      if (-x $cmd) {
         for my $grp ($cfg->{group}, $cfg->{admin_role}) {
            unless (getgrnam $grp ) {
               $prog->info( 'Creating group '.$grp );
               $prog->run_cmd( $cmd.q( ).$grp );
            }
         }
      }

      # Add the Apache user to the application group
      $cmd = q(/usr/sbin/usermod);

      if (-x $cmd and $cfg->{apache_user}) {
         $cmd .= ' -a -G'.$cfg->{group}.q( ).$cfg->{apache_user};
         $prog->run_cmd( $cmd );
      }

      # Create the user to own the files and support the application
      $cmd = q(/usr/sbin/useradd);

      if (-x $cmd and not getpwnam $cfg->{owner}) {
         $prog->info( 'Creating user '.$cfg->{owner} );
         ($text = ucfirst $self->module_name) =~ s{ :: }{ }gmx;
         $cmd .= ' -c "'.$text.' Support" -d ';
         $cmd .= dirname( $base ).' -g '.$cfg->{group}.' -G ';
         $cmd .= $cfg->{admin_role}.' -s ';
         $cmd .= $cfg->{shell}.q( ).$cfg->{owner};
         $prog->run_cmd( $cmd );
      }
   }

   # Now we have created everything and have an owner and group
   my $gid = getgrnam( $cfg->{group} ) || 0;
   my $uid = getpwnam( $cfg->{owner} ) || 0;

   $text  = 'Setting owner '.$cfg->{owner}.'('.$uid.') and group ';
   $text .= $cfg->{group}.'('.$gid.')';
   $prog->info( $text );

   # Set ownership
   chown $uid, $gid, dirname( $base );
   find( sub { chown $uid, $gid, $_ }, $base );
   chown $uid, $gid, $base;

   # Set permissions
   chmod oct q(02750), dirname( $base );
   find( sub { if    (-d $_)                { chmod oct q(02750), $_ }
               elsif ($_ =~ m{ $pref _ }mx) { chmod oct q(0750),  $_ }
               else                         { chmod oct q(0640),  $_ } },
         $base );

   # Make the shared directories group writable
   for my $dir (@{ $cfg->{create_dirs} }) {
      $dir = catdir( $base, $dir ) if ($dir !~ m{ \A [/] }xms );

      chmod oct q(02770), $dir if (-d $dir);
   }

   # Create the default version symlink
   unless ($cfg->{make_default} eq q(no)) {
      chdir dirname( $base );
      unlink q(default) if (-e q(default));
      symlink basename( $base ), q(default);
   }

   # Bump start the web server
   unless ($cfg->{restart_apache} eq q(no)) {
      if ($cfg->{apachectl} && -x $cfg->{apachectl}) {
         $prog->info( 'Running '.$cfg->{apachectl}.' restart' );
         $prog->run_cmd( $cfg->{apachectl}.' restart' );
      }
   }

   $cfg->{base} = $base; $cfg->{binsdir} = $bind;
   $cfg->{gid } = $gid;  $cfg->{libsdir} = $libd;
   $cfg->{prog} = $prog; $cfg->{uid    } = $uid;
   $self->{cfg} = $cfg;
   return;
}

sub ACTION_installdeps {
   my $self = shift;

   for my $depend (grep { $_ ne 'perl' } keys %{ $self->requires }) {
      CPAN::Shell->install( $depend );
   }

   return;
}

sub fcopy {
   my ($self, $src, $paths, $dest) = @_; my ($dir, $path);

   mkdir $dest, oct q(0750) unless (-d $dest);

   for $path (@{ $paths }) {
      ($dir = dirname( $path )) =~ s{ $src }{}xms;
      $dir  = catdir( $dest, $dir );
      mkpath( $dir ) unless (-d $dir);
      copy( $path, $dir );
   }

   return;
}

sub filter {
   (my $path = $File::Find::name) =~ s{ \A $prefix }{}mx;

   ## no critic
   push @paths, $path if ($path && -f $path && $path !~ $Bob::skip_pattern);
   ## critic

   return;
}

sub get_config {
   my ($self, $prog, $path) = @_;
   my $arrays = [ qw(copy_files create_dirs
                     create_files credentials link_files run_cmds) ];
   my $cfg    = eval { XMLin( $path, ForceArray => $arrays ) };

   $prog->fatal( $EVAL_ERROR ) if ($EVAL_ERROR);

   return $cfg;
}

sub get_connect_info {
   my ($self, $prog, $path) = @_;
   my $text   = $prog->io( $path )->all;
   my $dtd    = join "\n", grep {  m{ <! .+ > }mx } split m{ \n }mx, $text;
      $text   = join "\n", grep { !m{ <! .+ > }mx } split m{ \n }mx, $text;
   my $arrays = $self->_get_arrays_from_dtd( $dtd );
   my $cfg    = eval {
         XML::Simple->new( ForceArray => $arrays )->xml_in( $text );
      };

   $prog->fatal( $EVAL_ERROR ) if ($EVAL_ERROR);

   return ($cfg, $dtd);
}

sub process_files {
   my ($self, $src, $dest) = @_;

   $prefix = $self->base_dir(); @paths = ();

   if (-d $src) { find( { no_chdir => 1, wanted => \&filter }, $src ) }
   else { push @paths, $src if ($src && -f $src) }

   $self->fcopy( $src, \@paths, $dest );
   return;
}

sub replace {
   my ($self, $prog, $this, $that, $path) = @_;

   $prog->fatal( "Not found $path" ) unless (-s $path);

   my $wtr = $prog->io( $path )->atomic;

   for ($prog->io( $path )->getlines) {
      s{ $this }{$that}gmx; $wtr->print( $_ );
   }

   $wtr->close;
   return;
}

sub _get_arrays_from_dtd {
   my ($self, $dtd) = @_; my $arrays = [];

   for my $line (split m{ \n }mx, $dtd) {
      if ($line =~ m{ \A <!ELEMENT \s+ (\w+) \s+ \(
                         \s* ARRAY \s* \) \*? \s* > \z }imsx) {
         push @{ $arrays }, $1;
      }
   }

   return $arrays;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Build - M::B utility methods

=head1 Version

0.1.$Revision: 402 $

=head1 Synopsis

   use CatalystX::Usul::Build;
   use Class::C3;

   my $builder = q(CatalystX::Usul::Build);
   my $class   = $builder->subclass( class => 'Bob', code  => <<'EOB' );

   sub ACTION_install {
      my $self = shift;

      $self->next::method();

      # Your application specific post installation code goes here

      return;
   }
   EOB

=head1 Description

Subclasses L<Module::Build>. Ask questions during the build phase and stores
the answers for use during the install phase. The answers to the questions
determine where the application will be installed and which additional
actions will take place. Should be generic enough for any application

=head1 Subroutines/Methods

=head2 ACTION_build

When called by it's subclass this method prompts the user for
information about how this installation is to be performed. User
responses are saved to the F<build.xml> file

=head2 ACTION_install

When called from it's subclass this method performs the sequence of
actions required to install the application. Configuration options are
read from the file F<build.xml>

=head2 ACTION_installdeps

Iterates over the I<requires> attributes calling L<CPAN> each time to
install the dependent module

=head2 fcopy

Copies files from source to destination, creating the destination directories
as required

=head2 filter

Select only required files for processing. Uses the I<skip_pattern> defined
in the subclass which must be called I<Bob>

=head2 get_config

Reads the configuration information from the named XML file

=head2 get_connect_info

Reads database connection information from the named XML file

=head2 process_files

Handles the processing of files other than library modules and programs. It
calls L</filter> to select only those files that should be processed and
L</fcopy> to do the actual copying

=head2 replace

Substitute one string for another in a given file

=head1 Diagnostics

None

=head1 Configuration and Environment

Edits and stores information in the file F<build.xml>

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Programs>

=item L<CatalystX::Usul::Schema>

=item L<Module::Build>

=item L<XML::Simple>

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
