# @(#)$Id: Build.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::Build;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(Module::Build);

use CatalystX::Usul::Programs;
use CatalystX::Usul::Schema;
use Class::C3;
use Config;
use CPAN        ();
use English     qw(-no_match_vars);
use File::Copy  qw(copy move);
use File::Find  qw(find);
use File::Path  qw(make_path);
use SVN::Class  ();
use XML::Simple ();

if ($ENV{AUTOMATED_TESTING}) {
   # Some CPAN testers set these. Breaks dependencies
   $ENV{PERL_TEST_CRITIC} = 0; $ENV{PERL_TEST_POD} = 0;
   $ENV{TEST_CRITIC     } = 0; $ENV{TEST_POD     } = 0;
}

my $ACTIONS  = [ qw(create_dirs create_files copy_files link_files
                    create_schema create_ugrps set_owner
                    set_permissions make_default restart_apache) ];
my $ARRAYS   = [ qw(copy_files create_dirs
                    create_files credentials link_files run_cmds) ];
my $ATTRS    = [ qw(style new_prefix ver phase create_ugrps
                    apache_user setuid_root create_schema credentials
                    run_cmd make_default restart_apache built ask) ];
my $CFG_FILE = q(build.xml);

# Around these M::B actions

sub ACTION_build {
   my $self     = shift;
   my $cli      = $self->cli;
   my $cfg_path = $cli->catfile( $self->base_dir, $CFG_FILE );
   my $cfg      = $self->_get_config( $cfg_path );
   my $ask      = $cfg->{ask} = exists $cli->args->{a} || $cfg->{ask};

   return $self->next::method() if ($cfg->{built});

   chmod oct q(0640), $cfg_path; $cli->pwidth( $cfg->{pwidth} );

   # Update the config by looping through the questions
   for my $attr (@{ $self->config_attributes }) {
      my $method = q(get_).$attr;

      $cfg->{ $attr } = $self->$method( $cfg );
   }

   # Save the updated config for the install action to use
   $self->_set_config( $cfg_path, $cfg );

   $cli->anykey() if ($ask);

   return $self->next::method();
}

sub ACTION_install {
   my $self     = shift;
   my $cli      = $self->cli;
   my $cfg_path = $cli->catfile( $self->base_dir, $CFG_FILE );
   my $cfg      = $self->_get_config( $cfg_path );
   my $base     = $cfg->{base} = $self->_set_base( $cfg );

   $cli->info( "Base path $base" );
   $self->next::method();

   # Call each of the defined actions
   $self->$_( $cfg ) for (grep { $cfg->{ $_ } } @{ $self->actions });

   return $cfg;
}

# New M::B action

sub ACTION_installdeps {
   # Install all the dependent modules
   my $self = shift;

   for my $depend (grep { $_ ne q(perl) } keys %{ $self->requires }) {
      CPAN::Shell->install( $depend );
   }

   return;
}

# Public object methods

sub actions {
   # Accessor/mutator for the list of defined actions
   my ($self, $actions) = @_;

   $self->{_actions} = $actions if     (defined $actions);
   $self->{_actions} = $ACTIONS unless (defined $self->{_actions});

   return $self->{_actions};
}

sub cli {
   # Self initialising accessor for the command line interface object
   my $self = shift;

   unless ($self->{_command_line_interface}) {
      $self->{_command_line_interface} = CatalystX::Usul::Programs->new
         ( { appclass => $self->module_name, arglist => q(a ask>a), n => 1 } );
   }

   return $self->{_command_line_interface};
}

sub config_attributes {
   # Accessor/mutator for the list of defined config attributes
   my ($self, $attrs) = @_;

   $self->{_attributes} = $attrs if     (defined $attrs);
   $self->{_attributes} = $ATTRS unless (defined $self->{_attributes});

   return $self->{_attributes};
}

sub post_install {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $gid  = $cfg->{gid}; my $uid = $cfg->{uid};

   my $bind = $self->install_destination( q(bin) );

   $cli->info( 'The following commands may take a *long* time to complete' );

   for my $cmd (@{ $cfg->{run_cmds} || [] }) {
      my $prog = (split q( ), $cmd)[0];

      $cmd = $cli->catdir( $bind, $cmd ) if (!$cli->io( $prog )->is_absolute);
      $cmd =~ s{ \[% \s+ uid \s+ %\] }{$uid}gmx;
      $cmd =~ s{ \[% \s+ gid \s+ %\] }{$gid}gmx;

      if ($cfg->{run_cmd}) {
         $cli->info( "Running $cmd" );
         $cli->info( $cli->run_cmd( $cmd )->out );
      }
      else {
         # Don't run custom commands, print them out instead
         $cli->info( "Would run $cmd" );
      }
   }

   return;
}

sub process_files {
   # Find and copy files and directories from source tree to destination tree
   my ($self, $src, $dest) = @_;

   return unless ($src); $dest ||= q(blib);

   if    (-f $src) { $self->_copy_file( $src, $dest ) }
   elsif (-d $src) {
      my $prefix = $self->base_dir;

      find( { no_chdir => 1, wanted => sub {
         (my $path = $File::Find::name) =~ s{ \A $prefix }{}mx;
         return $self->_copy_file( $path, $dest );
      }, }, $src );
   }

   return;
}

sub replace {
   # Edit a file and replace one string with another
   my ($self, $this, $that, $path) = @_; my $cli = $self->cli;

   $cli->fatal( "Not found $path" ) unless (-s $path);

   my $wtr = $cli->io( $path )->atomic;

   for ($cli->io( $path )->getlines) {
      s{ $this }{$that}gmx; $wtr->print( $_ );
   }

   $wtr->close;
   return;
}

sub repository {
   # Accessor for the SVN repository information
   my $class = shift;
   my $file  = SVN::Class->svn_file( q(.svn) );

   return unless ($file);

   my $info = $file->info;

   return $info ? $info->root : undef;
}

sub skip_pattern {
   # Accessor/mutator for the regular expression of paths not to process
   my ($self, $re) = @_;

   $self->{_skip_pattern} = $re if (defined $re);

   return $self->{_skip_pattern};
}

# Questions

sub get_apache_user {
   my ($self, $cfg) = @_; my $user = $cfg->{apache_user};

   if ($cfg->{ask} and $cfg->{create_ugrps}) {
      my $cli = $self->cli; my $text;

      $text  = 'Which user does the Apache web server run as? This user ';
      $text .= 'will be added to the application group so that it can ';
      $text .= 'access the application\'s files';
      $cli->output( $text, { cl => 1, fill => 1, nl => 1 } );
      $user  = $cli->get_line( 'Web server user', $user, 1, 0 );
   }

   return $user;
}

sub get_ask {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   return $cli->yorn( 'Ask questions in future', 0, 1, 0 );
}

sub get_built {
   return 1;
}

sub get_create_schema {
   my ($self, $cfg) = @_; my $create = $cfg->{create_schema};

   if ($cfg->{ask}) {
      my $cli = $self->cli; my $text;

      $text   = 'Schema creation requires a database, id and password';
      $cli->output( $text, { cl => 1, fill => 1, nl => 1 } );
      $create = $cli->yorn( 'Create database schema', $create, 1, 0 );
   }

   return $create;
}

sub get_create_ugrps {
   my ($self, $cfg) = @_; my $create = $cfg->{create_ugrps};

   if ($cfg->{ask}) {
      my $cli = $self->cli; my $text;

      $text   = 'Use groupadd, useradd, and usermod to create the user ';
      $text  .= $cfg->{owner}.' and the groups '.$cfg->{group};
      $text  .= ' and '.$cfg->{admin_role};
      $cli->output( $text, { cl => 1, fill => 1, nl => 1 } );
      $create = $cli->yorn( 'Create groups and user', $create, 1, 0 );
   }

   return $create;
}

sub get_credentials {
   my ($self, $cfg) = @_; my $credentials = $cfg->{credentials};

   if ($cfg->{ask} && $cfg->{create_schema}) {
      my $cli     = $self->cli;
      my $dir     = $cli->catdir ( $self->base_dir, qw(var etc) );
      my $name    = $self->notes ( q(dbname) );
      my $path    = $cli->catfile( $dir, $name.q(.xml) );
      my ($dbcfg) = $self->_get_connect_info( $path );
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
      my $value;

      for my $fld (qw(name driver host port user password)) {
         $value = $defs->{ $fld } eq q(_field) ?
                  $dbcfg->{credentials}->{ $name }->{ $fld } : $defs->{ $fld };
         $value = $cli->get_line( $prompts->{ $fld }, $value, 1, 0, 0,
                                   $fld eq q(password) ? 1 : 0 );

         if ($fld eq q(password)) {
            my $args = { seed => $cfg->{secret} || $cfg->{prefix} };

            $path    = $cli->catfile( $dir, $cfg->{prefix}.q(.txt) );
            $args->{data} = $cli->io( $path )->all if (-f $path);
            $value   = CatalystX::Usul::Schema->encrypt( $args, $value );
            $value   = q(encrypt=).$value if ($value);
         }

         $credentials->{ $name }->{ $fld } = $value;
      }
   }

   return $credentials;
}

sub get_make_default {
   my ($self, $cfg) = @_; my $make_default = $cfg->{make_default};

   if ($cfg->{ask}) {
      my $text = 'Make this the default version';

      $make_default = $self->cli->yorn( $text, $make_default, 1, 0 );
   }

   return $make_default;
}

sub get_new_prefix {
   my ($self, $cfg) = @_; my $style = $cfg->{style};

   my $prefix = $self->notes( q(prefix) );

   if ($cfg->{ask} and $style eq q(normal)) {
      my $cli = $self->cli; my $text;

      $text   = 'Application name is automatically appended to the prefix';
      $cli->output( $text, { cl => 1, fill => 1, nl => 1 } );
      $prefix = $cli->get_line( 'Enter install path prefix', $prefix, 1, 0 );
   }

   return $prefix;
}

sub get_phase {
   my ($self, $cfg) = @_; my $phase = $cfg->{phase};

   my $cli = $self->cli; my $text;

   unless ($phase) {
      ($phase) = ($self->notes( q(applrel) ) =~ m{ \A v .* p (\d+) \z }mx);
   }

   if ($cfg->{ask}) {
      $text  = 'Phase number determines at run time the purpose of the ';
      $text .= 'application instance, e.g. live(1), test(2), development(3)';
      $cli->output( $text, { cl => 1, fill => 1, nl => 1 } );
      $phase = $cli->get_line( 'Enter phase number', $phase, 1, 0 );
   }

   unless ($phase =~ m{ \A \d+ \z }mx) {
      $cli->fatal( "Bad phase value (not an integer) $phase" );
   }

   return $phase;
}

sub get_restart_apache {
   my ($self, $cfg) = @_; my $restart = $cfg->{restart_apache};

   if ($cfg->{ask}) {
      $restart = $self->cli->yorn( 'Restart web server', $restart, 1, 0 );
   }

   return $restart;
}

sub get_run_cmd {
   my ($self, $cfg) = @_; my $run_cmd = $cfg->{run_cmd};

   if ($cfg->{ask}) {
      my $cli = $self->cli; my $text;

      $text    = 'Execute post installation commands. These may take ';
      $text   .= 'several minutes to complete';
      $cli->output( $text, { cl => 1, fill => 1, nl => 1 } );
      $run_cmd = $cli->yorn( 'Post install commands', $run_cmd, 1, 0 );
   }

   return $run_cmd;
}

sub get_setuid_root {
   my ($self, $cfg) = @_; my $setuid = $cfg->{setuid_root};

   if ($cfg->{ask}) {
      my $cli = $self->cli; my $text;

      $text   = 'Enable wrapper which allows limited access to some root ';
      $text  .= 'only functions like password checking and user management. ';
      $text  .= 'Not necessary unless the Unix authentication store is used';
      $cli->output( $text, { cl => 1, fill => 1, nl => 1 } );
      $setuid = $cli->yorn( 'Enable suid root', $setuid, 1, 0 );
   }

   return $setuid;
}

sub get_style {
   my ($self, $cfg) = @_; my $style = $cfg->{style};

   return $style unless ($cfg->{ask});

   my $cli = $self->cli; my $text;

   $text  = 'The application has two modes if installation. In normal ';
   $text .= 'mode it installs all components to a specifed path. In ';
   $text .= 'perl mode modules are install to the site lib, ';
   $text .= 'executables to the site bin and the rest to a subdirectory ';
   $text .= 'of /var. Installation defaults to normal mode since it is ';
   $text .= 'easier to maintain';
   $cli->output( $text, { cl => 1, fill => 1, nl => 1 } );

   return $cli->get_line( 'Enter the install mode', $style, 1, 0 );
}

sub get_ver {
   my $self = shift;

   my ($version) = ($self->notes( q(applrel) ) =~ m{ \A v(.*)p(\d+) \z }mx);

   return $version;
}

# Actions

sub copy_files {
   # Copy some files
   my ($self, $cfg) = @_; my $cli = $self->cli; my $base = $cfg->{base};

   for my $ref (@{ $cfg->{copy_files} }) {
      my $from = $self->_abs_path( $base, $ref->{from} );
      my $path = $self->_abs_path( $base, $ref->{to  } );

      if (-f $from && ! -f $path) {
         $cli->info( "Copying $from to $path" );
         copy( $from, $path );
         chmod oct q(0644), $path;
      }
   }

   return;
}

sub create_dirs {
   # Create some directories that don't ship with the distro
   my ($self, $cfg) = @_; my $cli = $self->cli; my $base = $cfg->{base};

   for my $dir (map { $self->_abs_path( $base, $_ ) }
                @{ $cfg->{create_dirs} }) {
      if (-d $dir) { $cli->info( "Exists $dir" ) }
      else {
         $cli->info( "Creating $dir" );
         make_path( $dir, { mode => oct q(02750) } );
      }
   }

   return;
}

sub create_files {
   # Create some empty log files
   my ($self, $cfg) = @_; my $cli = $self->cli; my $base = $cfg->{base};

   for my $path (map { $self->_abs_path( $base, $_ ) }
                 @{ $cfg->{create_files} }) {
      if (! -f $path) {
         $cli->info( "Creating $path" ); $cli->io( $path )->touch;
      }
   }

   return;
}

sub create_schema {
   # Create databases and edit credentials
   my ($self, $cfg) = @_; my $cli = $self->cli;

   # Edit the XML config file that contains the database connection info
   $self->_edit_credentials( $cfg, $self->notes( q(dbname) ) );

   my $bind = $self->install_destination( q(bin) );
   my $cmd  = $cli->catfile( $bind, $cfg->{prefix}.q(_schema) );

   # Create the database if we can. Will do nothing if we can't
   $cli->info( $cli->run_cmd( $cmd.q( -n -c create_database) )->out );

   # Call DBIx::Class::deploy to create the
   # schema and populate it with static data
   $cli->info( 'Deploying schema and populating database' );
   $cli->info( $cli->run_cmd( $cmd.q( -n -c deploy_and_populate) )->out );
   return;
}

sub create_ugrps {
   # Create the two groups used by this application
   my ($self, $cfg) = @_; my $cli = $self->cli; my $base = $cfg->{base};

   my $cmd = q(/usr/sbin/groupadd); my $text;

   if (-x $cmd) {
      # Create the application group
      for my $grp ($cfg->{group}, $cfg->{admin_role}) {
         unless (getgrnam $grp ) {
            $cli->info( "Creating group $grp" );
            $cli->run_cmd( $cmd.q( ).$grp );
         }
      }
   }

   $cmd = q(/usr/sbin/usermod);

   if (-x $cmd and $cfg->{apache_user}) {
      # Add the Apache user to the application group
      $cmd .= ' -a -G'.$cfg->{group}.q( ).$cfg->{apache_user};
      $cli->run_cmd( $cmd );
   }

   $cmd = q(/usr/sbin/useradd);

   if (-x $cmd and not getpwnam $cfg->{owner}) {
      # Create the user to own the files and support the application
      $cli->info( 'Creating user '.$cfg->{owner} );
      ($text = ucfirst $self->module_name) =~ s{ :: }{ }gmx;
      $cmd .= ' -c "'.$text.' Support" -d ';
      $cmd .= $cli->dirname( $base ).' -g '.$cfg->{group}.' -G ';
      $cmd .= $cfg->{admin_role}.' -s ';
      $cmd .= $cfg->{shell}.q( ).$cfg->{owner};
      $cli->run_cmd( $cmd );
   }

   return;
}

sub link_files {
   # Link some files
   my ($self, $cfg) = @_; my $cli = $self->cli; my $base = $cfg->{base};

   for my $ref (@{ $cfg->{link_files} }) {
      my $from = $self->_abs_path( $base, $ref->{from} );
      my $path = $self->_abs_path( $base, $ref->{to  } );

      if (-e $from) {
         unlink $path if (-e $path && -l $path);

         if (! -e $path) {
            $cli->info( "Symlinking $from to $path" );
            symlink $from, $path;
         }
         else { $cli->info( "Already exists $path" ) }
      }
      else { $cli->info( "Does not exist $from" ) }
   }

   return;
}

sub make_default {
   # Create the default version symlink
   my ($self, $cfg) = @_; my $cli = $self->cli; my $base = $cfg->{base};

   chdir $cli->dirname( $base );
   unlink q(default) if (-e q(default));
   symlink $cli->basename( $base ), q(default);
   return;
}

sub restart_apache {
   # Bump start the web server
   my ($self, $cfg) = @_; my $cli = $self->cli; my $base = $cfg->{base};

   if ($cfg->{apachectl} && -x $cfg->{apachectl}) {
      $cli->info( 'Running '.$cfg->{apachectl}.' restart' );
      $cli->run_cmd( $cfg->{apachectl}.' restart' );
   }

   return;
}

sub set_owner {
   # Now we have created everything and have an owner and group
   my ($self, $cfg) = @_; my $cli = $self->cli; my $base = $cfg->{base};

   my $gid = $cfg->{gid} = getgrnam( $cfg->{group} ) || 0;
   my $uid = $cfg->{uid} = getpwnam( $cfg->{owner} ) || 0;
   my $text;

   $text  = 'Setting owner '.$cfg->{owner}."($uid) and group ";
   $text .= $cfg->{group}."($gid)";
   $cli->info( $text );

   # Set ownership
   chown $uid, $gid, $cli->dirname( $base );
   find( sub { chown $uid, $gid, $_ }, $base );
   chown $uid, $gid, $base;
   return;
}

sub set_permissions {
   # Set permissions
   my ($self, $cfg) = @_; my $cli = $self->cli; my $base = $cfg->{base};

   my $pref = $cfg->{prefix};

   chmod oct q(02750), $cli->dirname( $base );

   find( sub { if    (-d $_)                { chmod oct q(02750), $_ }
               elsif ($_ =~ m{ $pref _ }mx) { chmod oct q(0750),  $_ }
               else                         { chmod oct q(0640),  $_ } },
         $base );

   if ($cfg->{create_dirs}) {
      # Make the shared directories group writable
      for my $dir (map { $self->_abs_path( $base, $_ ) }
                   @{ $cfg->{create_dirs} }) {
         chmod oct q(02770), $dir if (-d $dir);
      }
   }

   return;
}

# Private methods

sub _abs_path {
   my ($self, $base, $path) = @_; my $cli = $self->cli;

   unless ($cli->io( $path )->is_absolute) {
      $path = $cli->catfile( $base, $path );
   }

   return $path;
}

sub _copy_file {
   my ($self, $src, $dest) = @_;

   my $cli = $self->cli; my $pattern = $self->skip_pattern;

   return unless ($src && -f $src && (!$pattern || $src !~ $pattern));

   # Rebase the directory path
   my $dir = $cli->catdir( $dest, $cli->dirname( $src ) );

   # Ensure target directory exists
   make_path( $dir, { mode => oct q(02750) }  ) unless (-d $dir);

   copy( $src, $dir );
   return;
}

sub _edit_credentials {
   my ($self, $cfg, $dbname) = @_;

   my $cli = $self->cli; my $base = $cfg->{base};

   if ($cfg->{credentials} && $cfg->{credentials}->{ $dbname }) {
      my $path          = $cli->catfile( $base, qw(var etc), $dbname.q(.xml) );
      my ($dbcfg, $dtd) = $self->_get_connect_info( $path );

      for my $fld (qw(driver host port user password)) {
         my $value = $cfg->{credentials}->{ $dbname }->{ $fld };

         $value  ||= $dbcfg->{credentials}->{ $dbname }->{ $fld };
         $dbcfg->{credentials}->{ $dbname }->{ $fld } = $value;
      }

      eval {
         my $wtr = $cli->io( $path );
         my $xs  = XML::Simple->new( NoAttr => 1, RootName => q(config) );

         $wtr->println( $dtd ) if ($dtd);
         $wtr->append ( $xs->xml_out( $dbcfg ) );
      };

      $cli->fatal( $EVAL_ERROR ) if ($EVAL_ERROR);
   }

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

sub _get_config {
   my ($self, $path) = @_; my $cli = $self->cli;

   $cli->fatal( "Not found $path" ) unless (-f $path);

   my $cfg = eval {
      XML::Simple->new( ForceArray => $ARRAYS )->xml_in( $path );
   };

   $cli->fatal( $EVAL_ERROR ) if ($EVAL_ERROR);

   return $cfg;
}

sub _get_connect_info {
   my ($self, $path) = @_;

   my $cli    = $self->cli;
   my $text   = $cli->io( $path )->all;
   my $dtd    = join "\n", grep {  m{ <! .+ > }mx } split m{ \n }mx, $text;
      $text   = join "\n", grep { !m{ <! .+ > }mx } split m{ \n }mx, $text;
   my $arrays = $self->_get_arrays_from_dtd( $dtd );
   my $info   = eval {
      XML::Simple->new( ForceArray => $arrays )->xml_in( $text );
   };

   $cli->fatal( $EVAL_ERROR ) if ($EVAL_ERROR);

   return ($info, $dtd);
}

sub _set_base {
   my ($self, $cfg) = @_; my $cli = $self->cli; my $base;

   if ($cfg->{style} and $cfg->{style} eq q(perl)) {
      $base = $cli->catdir( q(), q(var),
                            $cli->class2appdir( $self->module_name ),
                            q(v).$cfg->{ver}.q(p).$cfg->{phase} );
      $self->install_path( var => $base );
   }
   else {
      unless (-d $cfg->{new_prefix}) {
         make_path( $cfg->{new_prefix}, { mode => oct q(02750) } );
      }

      $cli->fatal( 'Does not exist/cannot create '.$cfg->{new_prefix} )
         unless (-d $cfg->{new_prefix});

      $base = $cli->catdir( $cfg->{new_prefix},
                            $cli->class2appdir( $self->module_name ),
                            q(v).$cfg->{ver}.q(p).$cfg->{phase} );
      $self->install_base( $base );
      $self->install_path( bin => $cli->catdir( $base, 'bin' ) );
      $self->install_path( lib => $cli->catdir( $base, 'lib' ) );
      $self->install_path( var => $cli->catdir( $base, 'var' ) );
   }

   return $base;
}

sub _set_config {
   my ($self, $path, $cfg) = @_; my $cli = $self->cli;

   $cli->fatal( 'No config path'   ) unless (defined $path);
   $cli->fatal( 'No config to set' ) unless (defined $cfg);

   eval {
      XML::Simple->new( NoAttr     => 1,
                        OutputFile => $path,
                        RootName   => q(config) )->xml_out( $cfg );
   };

   $cli->fatal( $EVAL_ERROR ) if ($EVAL_ERROR);

   return $cfg;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Build - M::B utility methods

=head1 Version

0.1.$Revision: 562 $

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
actions will take place. Should be generic enough for any web application

=head1 Subroutines/Methods

=head2 ACTION_build

When called by it's subclass this method prompts the user for
information about how this installation is to be performed. User
responses are saved to the F<build.xml> file. The L</config_attributes>
method returns the list of questions to ask

=head2 ACTION_install

When called from it's subclass this method performs the sequence of
actions required to install the application. Configuration options are
read from the file F<build.xml>. The L</actions> method returns the
list of steps required to install the application

=head2 ACTION_installdeps

Iterates over the I<requires> attributes calling L<CPAN> each time to
install the dependent module

=head2 actions

   $current_list_of_actions = $builder->actions( $new_list_of_actions );

This accessor/mutator method defaults to the list defined in the C<$ACTIONS>
package variable

=head2 cli

   $cli = $builder->cli;

Returns an instance of L<CatalystX::Usul::Programs>, the command line
interface object

=head2 config_attributes

   $current_list_of_attrs = $builder->config_attributes( $new_list_of_attrs );

This accessor/mutator method defaults to the list defined in the C<$ATTRS>
package variable

=head2 post_install

   $builder->post_install( $config );

Executes the custom post installation commands

=head2 process_files

   $builder->process_files( $source, $destination );

Handles the processing of files other than library modules and
programs.  Uses the I<Bob::skip_pattern> defined in the subclass to
select only those files that should be processed.  Copies files from
source to destination, creating the destination directories as
required. Source can be a single file or a directory. The destination
is optional and defaults to B<blib>

=head2 replace

   $builder->replace( $this, $that, $path );

Substitutes C<$this> string for C<$that> string in the file F<$path>

=head2 repository

Return the URI of the SVN repository for this project

=head2 skip_pattern

   $regexp = $builder->skip_pattern( $new_regexp );

Accessor/mutator method. Used by L</_copy_file> to skip processing files
that match this pattern. Set to false to not have a skip list

=head1 Questions

All question methods are passed C<$config> and return the new value
for one of it's attributes

=head2 get_apache_user

Prompts for the userid of the web server process owner. This user will
be added to the group that owns the application files and directories.
This will allow the web server processes to read and write these files

=head2 get_ask

Ask if questions should be asked in future runs of the build process

=head2 get_built

Always returns true. This dummy question is used to trigger the suppression
of any further questions once the build phase is complete

=head2 get_create_schema

Should a database schema be created? If yes then the database connection
information must be entered. The database must be available at install
time

=head2 get_create_ugrps

Create the application user and group that owns the files and directories
in the application

=head2 get_credentials

Get the database connection information

=head2 get_make_default

When installed should this installation become the default for this
host? Causes the symbolic link (that hides the version directory from
the C<PATH> environment variable) to be deleted and recreated pointing
to this installation

=head2 get_new_prefix

If the installation style is B<normal>, then prompt for the installation
prefix. This default to F</opt>. The application name and version
directory are automatically appended

=head2 get_phase

The phase number represents the reason for the installation. It is
encoded into the name of the application home directory. At runtime
the application will load some configuration data that is dependent
upon this value

=head2 get_restart_apache

When the application is mostly installed, should the web server be
restarted?

=head2 get_run_cmd

Run the post installation commands? These may take a long time to complete

=head2 get_setuid_root

Enable the C<setuid> root wrapper?

=head2 get_style

Which installation layout? Either B<perl> or B<normal>

=over 3

=item B<normal>

Modules, programs, and the F<var> directory tree are installed to a
user selectable path. Defaults to F<< /opt/<appname> >>

=item B<perl>

Will install modules and programs in their usual L<Config> locations. The
F<var> directory tree will be install to F<< /var/<appname> >>

=back

=head2 get_ver

Dummy question returns the version part of the installation directory

=head1 Actions

All action methods are passed C<$config>

=head2 copy_files

Copies files as defined in the C<< $config->{copy_files} >> attribute.
Each item in this list is a hash ref containing I<from> and I<to> keys

=head2 create_dirs

Create the directory paths specified in the list
C<< $config->{create_dirs} >> if they do not exist

=head2 create_files

Create the files specified in the list
C<< $config->{create_files} >> if they do not exist

=head2 create_schema

Creates a database then deploys and populates the schema

=head2 create_ugrps

Creates the user and group to own the application files

=head2 link_files

Creates some symbolic links

=head2 make_default

Makes this installation the default for this server

=head2 restart_apache

Restarts the web server

=head2 set_owner

Set the ownership of the installed files and directories

=head2 set_permissions

Set the permissions on the installed files and directories

=head1 Private Methods

=head2 _abs_path

   $absolute_path = $builder->_abs_path( $base, $path );

Prepends F<$base> to F<$path> unless F<$path> is an absolute path

=head2 _copy_file

   $builder->_copy_file( $source, $destination );

Called by L</process_files>. Copies the C<$source> file to the
C<$destination> directory

=head2 _edit_credentials

   $builder->_edit_credentials( $config, $dbname );

Writes the database login information stored in the C<$config> to the
application config file in the F<var/etc> directory. Called from
L</create_schema>

=head2 _get_arrays_from_dtd

   $list_of_arrays = $builder->_get_arrays_from_dtd( $dtd );

Parses the C<$dtd> data and returns the list of element names which are
interpolated into arrays. Called from L</_get_connect_info>

=head2 _get_config

   $config = $builder->_get_config( $path );

Reads the configuration information from F<$path> using L<XML::Simple>.
The package variable C<$ARRAYS> is passed to L<XML::Simple> as the
I<ForceArray> attribute. Called by L</ACTION_build> and L<ACTION_install>

=head2 _get_connect_info

   ($info, $dtd) = $builder->_get_connect_info( $path );

Reads database connection information from F<$path> using L<XML::Simple>.
The I<ForceArray> attribute passed to L<XML::Simple> is obtained by parsing
the DTD elements in the file. Called by the L</get_credentials> question
and L<_edit_credentials>

=head2 _set_base

   $base = $builder->_set_base( $config );

Uses the C<< $config->{style} >> attribute to set the L<Module::Build>
I<install_base> attribute to the base directory for this installation.
Returns that path. Also sets; F<bin>, F<lib>, and F<var> directory paths
as appropriate. Called from L<ACTION_install>

=head2 _set_config

   $config = $builder->_set_config( $path, $config );

Writes the C<$config> hash to the F<$path> file for later use by
the install action. Called from L<ACTION_build>

=head1 Diagnostics

None

=head1 Configuration and Environment

Edits and stores config information in the file F<build.xml>

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Programs>

=item L<CatalystX::Usul::Schema>

=item L<Module::Build>

=item L<SVN::Class>

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
