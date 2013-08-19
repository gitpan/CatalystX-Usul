# @(#)$Ident: Admin.pm 2013-08-19 19:05 pjf ;

package CatalystX::Usul::Admin;

use namespace::sweep;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw( class2appdir logname emit throw
                                   untaint_cmdline untaint_identifier );
use Class::Null;
use English                    qw( -no_match_vars );
use File::DataClass::Types     qw( ArrayRef Bool Directory HashRef
                                   LoadableClass Object Path );
use File::Find                 qw( find );
use File::Basename             qw( basename dirname );
use File::Spec::Functions      qw( catfile );
use IO::Interactive            qw( is_interactive );
use List::Util                 qw( first );
use Moo;
use MooX::Options;
use TryCatch;

extends q(Class::Usul::Programs);
with    q(CatalystX::Usul::TraitFor::PostInstallConfig);

# Public attributes
option 'exec_setuid' => is => 'ro', isa => Bool, default => FALSE,
   documentation     => 'True when executing setuid', short => 'e';

with    q(Class::Usul::TraitFor::UntaintedGetopts);

# Private attributes
has '_commands'        => is => 'ro',   isa => HashRef,
   default             => sub { { group_add_cmd => q(groupadd),
                                  group_del_cmd => q(delgroup),
                                  user_add_cmd  => q(useradd),
                                  user_del_cmd  => q(deluser),
                                  user_mod_cmd  => q(usermod), } },
   reader              => 'commands';

has '_paragraph'       => is => 'ro',   isa => HashRef,
   default             => sub { { cl => TRUE, fill => TRUE, nl => TRUE } },
   reader              => 'paragraph';

has '_public_methods'  => is => 'ro',   isa => ArrayRef,
   default             => sub { [ qw(authenticate dump_user list_methods) ] },
   reader              => 'public_methods';

has '_secsdir'         => is => 'lazy', isa => Directory,
   default             => sub { [ $_[ 0 ]->config->vardir, q(secure) ] },
   coerce              => Directory->coercion, reader => 'secsdir';

has '_sites_available' => is => 'lazy', isa => Path, coerce => Path->coercion,
   default             => sub { [ NUL, qw(etc apache2 sites-available) ] },
   reader              => 'sites_available';

has '_sites_enabled'   => is => 'lazy', isa => Path, coerce => Path->coercion,
   default             => sub { [ NUL, qw(etc apache2 sites-enabled) ] },
   reader              => 'site_enabled';

has '_server_options'  => is => 'ro',   isa => ArrayRef,
   default             => sub { [ { plack    => q(Plack/Starman)   },
                                  { mod_perl => q(Apache/mod_perl) },
                                  { none     => q(None)            }, ] },
   reader              => 'server_options';

has '_user_class'      => is => 'lazy', isa => LoadableClass,
   default             => 'CatalystX::Usul::Users::UnixAdmin',
   reader              => 'user_class';

has '_users'           => is => 'lazy', isa => Object,
   default             => sub { $_[ 0 ]->user_class->new( builder => $_[ 0 ] )},
   reader              => 'users';

# Construction
around 'BUILDARGS' => sub {
   my ($next, $self, @args) = @_; my $attr = $self->$next( @args );

   $attr->{mode  } = oct q(027);
   $attr->{params}->{update_password} ||= [ FALSE ];

   return $attr;
};

around 'new_with_options' => sub {
   my ($next, $self, @args) = @_; $ENV{ENV} = NUL; # For taint mode

   my $new = $self->$next( @args ); $new->method or $self->_exit_usage( 0 );

   $REAL_USER_ID != 0 and $ENV{USER} = $ENV{LOGNAME} = getpwuid $REAL_USER_ID;

   $EFFECTIVE_USER_ID  = 0; $REAL_USER_ID  = 0;
   $EFFECTIVE_GROUP_ID = 0; $REAL_GROUP_ID = 0;

   return $new;
};

around 'run' => sub {
   my ($next, $self, @args) = @_; my $method = $self->method || 'unknown';

   # Running as root not suid root during install
   if ($self->_is_setuid and not $self->_is_authorised) {
      $self->error( "Access denied to ${method} for ".logname );
      exit FAILED;
   }

   if (q(user_) eq substr $method, 0, 5) {
      $self->params->{set_user} = [ substr $method, 5 ];
      $self->method( q(set_user) );
   }

   return $self->$next( @args );
};

# Public methods
sub account_report : method {
   my $self = shift; my @argv = @{ $self->extra_argv };

   $self->info( $self->users->user_report( @argv ), { no_lead => TRUE } );
   return OK;
}

sub authenticate : method {
   my $self = shift;

   try {
      my $user = $self->users->authenticate( @{ $self->extra_argv } );

      $user->has_password_expired
         and throw error => 'User [_1] password expired',
                   args  => [ $user->username ], class => 'PasswordExpired';
   }
   catch ($e) { $self->error( $e->error, { args => $e->args } ); return FAILED }

   return OK;
}

sub create_account : method {
   my $self = shift;

   $self->info( $self->users->create_account( @{ $self->extra_argv } ) );
   return OK;
}

sub create_ugrps : method {
   # Create the two groups and one users used by this application
   my $self = shift; my ($cmd, $text);

   my $picfg   = $self->read_post_install_config;
   my $user    = $picfg->{process_owner} || $picfg->{owner};
   my $groups  = [ $picfg->{group}, $picfg->{admin_role} ];
   my $default = $picfg->{create_ugrps};

   $text  = 'Use groupadd, useradd, and usermod to create the user ';
   $text .= $picfg->{owner}.' and the groups '.$picfg->{group}.' and ';
   $text .= $picfg->{admin_role};
   $self->output( $text, $self->paragraph );

   my $choice  = $self->yorn( 'Create groups and user', $default, TRUE, 0 );

   $picfg->{create_ugrps} = $choice or return OK;

   $text  = 'Which user does the HTTP server run as? This user ';
   $text .= 'will be added to the application group so that it can ';
   $text .= 'access the application\'s files';
   $self->output( $text, $self->paragraph );

   $user  = $self->get_line( 'HTTP server user', $user, TRUE, 0 );

   # Create the application and support groups
   $self->_create_app_groups( $self->commands->{group_add_cmd}, $groups );
   # Create the user to own the files and support the application
   $self->_create_app_user( $self->commands->{user_add_cmd}, $picfg );
   # Add the process owner user to the application group
   $self->_add_user_to_group( $self->commands->{user_mod_cmd},
                              $user, $picfg->{group} );

   return OK;
}

sub deploy_server : method { # Redispatch to server specific method
   my $self          = shift;
   my $picfg         = $self->read_post_install_config;
   my $server_opts   = $self->server_options;
   my $deploy_server = $picfg->{deploy_server}
                     ? $picfg->{deploy_server}
                     : (keys %{ $server_opts->[ 0 ] })[ 0 ];

   my $prompt  = 'Choose server startup option from this list:';
   my $count   = 1;
   my $default = ( map  { $_->[ 0 ] }
                   grep { $_->[ 1 ] eq $deploy_server }
                   map  { [ $count++, $_ ] }
                   map  { (keys   %{ $_ })[ 0 ] } @{ $server_opts } )[ 0 ];
   my $options = [ map  { (values %{ $_ })[ 0 ] } @{ $server_opts } ];
   my $option  = $self->get_option( $prompt, $default, TRUE, 0, $options );

   ($option < 0 ) and return OK;

   $picfg->{deploy_server} = $deploy_server
      = (keys %{ $server_opts->[ $option ] })[ 0 ];

   $deploy_server eq q(none) and return OK;

   $self->info( "Deploying server ${deploy_server}" );

   my $method = "_deploy_${deploy_server}_server";

   my $ref; $ref = $self->can( $method ) and return $self->$ref();

   return OK;
}

sub delete_account : method {
   my $self = shift;

   $self->info( $self->users->delete_account( @{ $self->extra_argv } ) );
   return OK;
}

sub dump_user : method {
   my $self = shift; my $user = shift @{ $self->extra_argv } // logname;

   $self->dumper( $self->users->find_user( $user, TRUE ) );
   return OK;
}

sub init_suid : method {
   my $self = shift; my $picfg = $self->read_post_install_config; my $text;

   $text  = 'Enable wrapper which allows limited access to some root ';
   $text .= 'only functions like password checking and user management. ';
   $text .= 'Necessary if the OS authentication store is used';
   $self->output( $text, $self->paragraph );

   $self->yorn( 'Enable suid root', $picfg->{init_suid}, TRUE, 0 ) or return OK;

   my $secd = $self->secsdir; my $path = $self->config->suid;

   my ($uid, $gid) = $self->get_owner( $picfg );

   $text  = 'Restricting permissions on '.basename( $secd );
   $text .= ' and '.basename( $path );
   $self->info( $text );
   # Restrict access for these files to root only
   chown 0, $gid, $secd; chmod oct q(02700), $secd;

   for ($self->io( $secd )->filter( sub { m{ \.sub \z }mx } )->all_files) {
      chown 0, $gid, "$_"; chmod oct q(600), "$_";
   }

   chown 0, $gid, $path; chmod oct q(04750), $path;
   return OK;
}

sub make_default : method { # Create the default version symlink
   my $self = shift; my $picfg = $self->read_post_install_config;

   my $text = 'Make this the default version';

   $self->yorn( $text, $picfg->{make_default}, TRUE, 0 ) or return OK;

   my $verdir = $self->_unlink_default_link;

   $self->info   ( $self->file->symlink( NUL, $verdir, q(default) ) );
   $self->run_cmd( [ qw(chown -h), $picfg->{owner}, q(default) ] );
   return OK;
}

sub populate_account : method {
   my $self = shift;

   $self->info( $self->users->populate_account( @{ $self->extra_argv } ) );
   return OK;
}

sub post_install : method {
   my $self = shift; my $picfg = $self->read_post_install_config;

   if ($picfg->{post_install}) {
      $self->info( 'Running post install' );
      $self->info( 'The following commands may take a *long* time to complete');
   }
   else { $self->info( 'Not running post install' ) }

   for my $ref (@{ $picfg->{post_install_methods} || [] }) {
      my $key = (keys %{ $ref })[ 0 ]; my $val = (values %{ $ref })[ 0 ];

      $self->_call_post_install_method( $picfg, $key, $val );
   }

   $self->write_post_install_config( $picfg );
   return OK;
}

sub read_secure : method {
   my $self    = shift;
   my $file    = $self->extra_argv->[ 0 ] or return FAILED;
   my $path    = $self->secsdir->catfile( basename( $file ) );
   my $msg     = "Admin reading secure file ${file} for ".logname;

   $self->_logger( $msg, q(auth.info), q(read_secure) );
   emit $path->getlines;
   return OK;
}

sub restart_server : method { # Bump start the web server
   my $self    = shift;
   my $picfg   = $self->read_post_install_config;
   my $default = $picfg->{restart_server};

   $self->yorn( 'Restart HTTP server', $default, TRUE, 0 ) or return OK;

   my $cmd     = $picfg->{restart_server_cmd};
      $cmd     = $self->get_line
      ( 'HTTP server restart command', $cmd, TRUE, 0, TRUE );
   my $prog    = (split SPC, $cmd)[ 0 ];

   ($prog and -x $prog) or return FAILED;

   $self->info( "Server restart, running ${cmd}" );
   $self->run_cmd( $cmd );
   return OK;
}

sub roles {
   return $_[ 0 ]->users->roles;
}

sub roles_update : method {
   my $self = shift;

   $self->output( $self->roles->roles_update( @{ $self->extra_argv } ) );
   return OK;
}

sub set_owner : method {
   # Now we have created everything and have an owner and group
   my $self = shift; my $picfg = $self->read_post_install_config;

   my $base        = $self->config->appldir;
   my ($uid, $gid) = $self->get_owner( $picfg );
   my $text        = 'Setting owner '.$picfg->{owner}."(${uid}) and group ";
      $text       .= $picfg->{group}."(${gid})";

   $self->info( $text );
   chown $uid, $gid, dirname( $base );
   find( sub { chown $uid, $gid, $_ }, $base );
   chown $uid, $gid, $base;
   return OK;
}

sub set_password : method {
   return $_[ 0 ]->update_password( TRUE );
}

sub set_permissions : method { # Set permissions on all files in the app
   my $self = shift; my $picfg = $self->read_post_install_config;

   my $base = $self->config->appldir; my $pref = $self->config->prefix;

   $self->info( "Setting permissions on ${base}" );
   chmod oct q(02750), dirname( $base );

   find( sub { if    (-d $_)                { chmod oct q(02750), $_ }
               elsif ($_ =~ m{ $pref _ }mx) { chmod oct q(0750),  $_ }
               elsif ($_ =~ m{ \.sh \z }mx) { chmod oct q(0750),  $_ }
               else                         { chmod oct q(0640),  $_ } },
         $base );

   # Make the shared directories group writable
   for my $dir (grep { $_->is_dir }
                map  { $self->file->absolute( $base, $_ ) }
                    @{ $picfg->{create_dirs} }) {
      $dir->chmod( 02770 );
   }

   return OK;
}

sub set_user : method {
   my ($self, $user) = @_; my $logname = logname;

   $user or throw "No user supplied - ${logname}";
   is_interactive() or throw "Not interactive - ${logname}";

   my $msg  = "Admin suid from ${logname} to ${user}";

   $self->_logger( $msg, q(auth.info), q(suid) );

   my $cfg  = $self->config;
   my $path = catfile( $cfg->binsdir, $cfg->prefix.q(_suenv) );
   my @argv = @{ $self->extra_argv };
   my $cmd  = $argv[ 1 ] || NUL;

   if ($argv[ 0 ] and $argv[ 0 ] eq q(-)) {
      # Old style full login, ENV unset, HOME set for new user
      $cmd = "su - ${user}";
   }
   elsif ($argv[ 0 ] and $argv[ 0 ] eq q(+)) {
      # Keep ENV as now, set HOME for new user
      $cmd = "su ${user} -c '. ${path} ${cmd}'";
   }
   else {
      # HOME from old user,  ENV set from old user
      $cmd = "su ${user} -c 'HOME=".$ENV{HOME}." . ${path} ${cmd}'";
   }

   exec $cmd or throw error => 'Exec failed [_1]', args => [ $ERRNO ];
   return; # Never reached
}

sub signal_process : method {
   my $self = shift;

   $self->ipc->signal_process_as_root( %{ $self->options },
                                       pids => $self->extra_argv );
   return OK;
}

sub tape_backup : method {
   my $self = shift; my $cfg = $self->config; my ($cmd, $res, $text);

   $self->info( 'Starting tape backup on '.$self->options->{device} );
   $cmd  = catfile( $cfg->binsdir, $cfg->prefix.q(_cli) );
   $cmd .= SPC.$self->debug_flag.' -c tape_backup -L '.$self->language;

   for (keys %{ $self->options }) {
      $cmd .= ' -o '.$_.'="'.$self->options->{ $_ }.'"';
   }

   $cmd .= ' -- '.(join q( ), map { '"'.$_.'"' } @{ $self->extra_argv });

   $self->output( $self->run_cmd( $cmd )->out );
   return OK;
}

sub uninstall : method {
   my $self   = shift;
   my $cfg    = $self->config;
   my $appdir = class2appdir $cfg->appclass;
   my $picfg  = $self->read_post_install_config;

   $self->yorn( $self->add_leader( 'Are you sure?' ), FALSE, TRUE )
      or return OK;

   if ($picfg->{deploy_server} eq q(plack)) {
      $self->run_cmd( [ q(invoke-rc.d), $appdir, q(stop)   ],
                      { expected_rv => 100 } );
      $self->io     ( [ NUL, qw(etc init.d), $appdir       ] )->unlink;
      $self->run_cmd( [ q(update-rc.d), $appdir, q(remove) ] );
   }
   elsif ($picfg->{deploy_server} eq q(mod_perl)) {
      my $link = sprintf '%-3.3d-%s', $cfg->phase, $appdir;

      $self->io( [ @{ $self->sites_enabled   }, $link   ] )->unlink;
      $self->io( [ @{ $self->sites_available }, $appdir ] )->unlink;
      $self->run_cmd( [ q(invoke-rc.d), $appdir, q(restart) ] );
   }

   my $io  = $self->io( [ NUL, qw(etc default), $appdir ] );

   $io->exists and $io->unlink;

   my $cmd = catfile( $cfg->binsdir, $cfg->prefix.q(_schema) );

   $self->run_cmd( [ $cmd, $self->debug_flag, qw(-c drop_database) ],
                   { err => q(stderr), out => q(stdout) } );
   $self->run_cmd( $self->interpolate_cmd( $self->commands->{user_del_cmd},
                                           $picfg->{owner} ) );
   $self->run_cmd( $self->interpolate_cmd( $self->commands->{group_del_cmd},
                                           $picfg->{group} ) );
   $self->run_cmd( $self->interpolate_cmd( $self->commands->{group_del_cmd},
                                           $picfg->{admin_role} ) );

   $self->_unlink_default_link;
   return OK;
}

sub untaint_self {
   my $self = shift; my $cmd = $self->config->pathname;

   $cmd .= SPC.$self->debug_flag.' -e -c "'.$self->method.'"';
   $cmd .= ' -L '.$self->language if ($self->language);
   $cmd .= ' -q'                  if ($self->quiet);

   for (keys %{ $self->options }) {
      $cmd .= ' -o '.$_.'="'.$self->options->{ $_ }.'"';
   }

   $cmd .= ' -- '.(join SPC, map { "'".$_."'" } @{ $self->extra_argv });
   $cmd  = untaint_cmdline $cmd;

   $self->debug and $self->log->debug( $cmd );
   return $cmd;
}

sub update_account : method {
   my $self = shift; my @argv = @{ $self->extra_argv };

   $self->info( $self->users->update_account( @argv ) );
   return OK;
}

sub update_mail_aliases : method {
   my $self = shift; my @argv = @{ $self->extra_argv };

   $self->output( $self->users->alias_class->new( @argv )->update_as_root );
   return OK;
}

sub update_password : method {
   my ($self, $flag) = @_; my @argv = @{ $self->extra_argv };

   $self->output( $self->users->update_password( $flag, @argv ) );
   return OK;
}

sub update_progs : method {
   my $self    = shift;
   my $cfg     = $self->config;
   my $path    = $self->io( [ $cfg->ctrldir, q(default).$cfg->extension ] );
   my $globals = $self->file->dataclass_schema->load( $path )->{globals}
      or throw "No global config from ${path}";
   my $global  = $globals->{ssh_id} or throw "No SSH identity from ${path}";
   my $ssh_id  = $global->{value} or throw "No SSH identity value from ${path}";
   my $from    = $self->extra_argv->[ 0 ]
      or throw 'Copy from file path not specified';
   my $to      = $self->extra_argv->[ 1 ]
      or throw 'Copy to file path not specified';
   my $cmd     = 'su '.$cfg->owner." -c 'scp -i ${ssh_id} ${from} ${to}'";

   $self->info( $self->run_cmd( $cmd )->out );
   return OK;
}

# Private methods
sub _add_user_to_group {
   my ($self, $cmd, $user, $group) = @_; ($cmd and $user and $group) or return;

   $self->info   ( "Adding process owner (${user}) to group (${group})" );
   $self->run_cmd( $self->interpolate_cmd( $cmd, $group, $user ) );
   return;
}

sub _call_post_install_method {
   my ($self, $picfg, $key, @args) = @_;

   if ($key eq q(admin)) {
      if ($picfg->{post_install}) {
         my $ref; $ref = $self->can( $args[ 0 ] ) and $self->$ref();
      }
      else { $self->info( 'Would call '.$args[ 0 ] ) }
   }
   else {
      my $prog    = $self->config->prefix.q(_).$key;
      my $cmd     = [ $prog, $self->debug_flag, q(-c), $args[ 0 ] ];
      my $cmd_str = join SPC, @{ $cmd };

      if ($picfg->{post_install}) {
         $self->info( "Running ${cmd_str}" );
         $cmd->[ 0 ] = $self->file->absolute( $self->config->binsdir,
                                              $cmd->[ 0 ] );
         $self->run_cmd( $cmd, { debug => $self->debug, out => q(stdout) } );
      }
      else { $self->info( "Would run ${cmd_str}" ) }
   }

   return;
}

sub _create_app_groups {
   my ($self, $cmd, $groups) = @_; ($cmd and $groups) or return;

   for my $grp (grep { not getgrnam $_ } @{ $groups }) {
      $self->info   ( "Creating group ${grp}" );
      $self->run_cmd( $self->interpolate_cmd( $cmd, $grp ) );
   }

   return;
}

sub _create_app_user {
   my ($self, $cmd, $picfg) = @_;

   ($cmd and $picfg) or return; getpwnam $picfg->{owner} and return;

   my $cfg  = $self->config;
  (my $text = ucfirst $cfg->appclass) =~ s{ :: }{ }gmx;

   $picfg->{gecos  } = "${text} Support";
   $picfg->{homedir} = dirname( $cfg->appldir );

   $self->info   ( 'Creating user '.$picfg->{owner} );
   $self->run_cmd( $self->interpolate_cmd( $cmd, $picfg ) );
   return;
}

sub _deploy_mod_perl_server {
   my $self = shift;
   my $cfg  = $self->config;
   my $base = $cfg->appldir;
   my $file = class2appdir $cfg->appclass;
   my $from = [ qw(var etc mod_perl.conf) ];
   my $to   = [ @{ $self->sites_available }, $file ];
   my $link = sprintf '%-3.3d-%s', $cfg->phase, $file;

   $self->info( $self->file->symlink( $base, $from, $to ) );

   $from = [ @{ $self->sites_available }, $file ];
   $to   = [ @{ $self->sites_enabled   }, $link ];
   $self->info( $self->file->symlink( $base, $from, $to ) );

   $from = [ NUL, qw(etc apache2 mods-available expires.load) ];
   $to   = [ NUL, qw(etc apache2 mods-enabled   expires.load) ];
   $self->info( $self->file->symlink( $base, $from, $to ) );
   return OK;
}

sub _deploy_plack_server {
   my $self = shift;
   my $cfg  = $self->config;
   my $file = class2appdir $cfg->appclass;
   my $path = $self->io( [ NUL, qw(etc default) ] );

   $path->exists or $path->mkpath( 0755 );

   $self->file->absolute( $cfg->appldir, [ qw(var etc etc_default) ] )
              ->copy    ( [ NUL, qw(etc default), $file ] )
              ->chmod   ( 0644 );

   $self->file->absolute( $cfg->appldir, [ qw(var etc psgi.sh) ] )
              ->copy    ( [ NUL, qw(etc init.d), $file ] )
              ->chmod   ( 0755 );

   $self->run_cmd ( [ q(update-rc.d), $file, qw(defaults 98 02) ] );
   return OK;
}

sub _interpolate_useradd_cmd {
   my ($self, $cmd, $cfg) = @_;

   return [ $cmd, q(-c), $cfg->{gecos}, q(-d), $cfg->{homedir},
                  q(-g), $cfg->{group}, q(-G), $cfg->{admin_role},
                  q(-s), $cfg->{shell}, $cfg->{owner} ];
}

sub _interpolate_usermod_cmd {
   return [ $_[ 1 ], qw(-a -G), $_[ 2 ], $_[ 3 ] ];
}

sub _is_authorised {
   my $self = shift; my $wanted = $self->method or return FALSE;

   first { $wanted eq $_ } @{ $self->public_methods } and return TRUE;

   my $user = logname or return FALSE;

   first { __find_method( $wanted, $_ ) } $self->_list_auth_sub_files( $user )
      and return TRUE;

   return FALSE;
}

sub _is_setuid {
   return $_[ 0 ]->config->pathname->stat->{mode} & oct q(04000);
}

sub _list_auth_sub_files {
   return grep { $_->is_file }
          map  { $_[ 0 ]->io( [ $_[ 0 ]->secsdir, $_.q(.sub) ] ) }
                 $_[ 0 ]->roles->get_roles( $_[ 1 ] );
}

sub _logger {
   my ($self, $msg, $priority, $tag) = @_; my $logger;

   $logger = $self->os->{logger}->{value} or throw 'Logger not specified';
   -x $logger or throw error => 'Cannot execute [_1]', args => [ $logger ];

   $self->run_cmd( [ $logger, q(-i), q(-p), $priority, q(-t), $tag, "${msg}" ]);
   return;
}

sub _unlink_default_link {
   my $base = $_[ 0 ]->config->appldir;

   chdir dirname( $base ); -e q(default) and unlink q(default);

   return basename( $base );
}

# Private functions
sub __find_method {
   my ($wanted, $io) = @_; my $hash = HASH_CHAR;

   return first { $_ eq $wanted }
          map   { (split m{ \s+ $hash }mx, $_.SPC.$hash)[ 0 ] }
          grep  { length } $io->chomp->getlines;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Admin - Subroutines that run as the super user

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   # Setuid root program wrapper
   use CatalystX::Usul::Admin;

   $ENV{PATH} = q(/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin);

   my $app = CatalystX::Usul::Admin->new_with_options
      ( appclass => 'YourApp' );

   $app->exec_setuid or exec $app->untaint_self or die "Exec failed\n";

   exit $app->run;

=head1 Description

Methods called from the setuid root program wrapper

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item C<commands>

Hash ref of OS commands

=item C<exec_setuid>

A boolean which defaults to false. Becomes true after the program has
re-executed itself

=item C<paragraph>

Hash ref of options that makes output appear in separate paragraphs

=item C<public_methods>

List of methods that do not require authorization

=item C<server_options>

Array ref of deployment options

=back

=head1 Subroutines/Methods

=head2 BUILDARGS

Customize the constructor

=head2 account_report

Calls the L<report|CatalystX::Usul::Users::Unix/user_report>
method on the user model

=head2 authenticate

Calls the L<authenticate|CatalystX::Usul::Users/authenticate>
method on the user model

=head2 create_account

Calls the L<create account|CatalystX::Usul::Users::UnixAdmin/create_account>
method on the user model

=head2 create_ugrps

Creates the user and group to own the application files

=head2 deploy_server

Redispatches the call to one of the server specific methods

=head2 delete_account

Calls the L<delete account|CatalystX::Usul::Users::UnixAdmin/delete_account>
method on the user model

=head2 dump_user

Retrieves data for the specified user and dumps it using L<Data::Printer>

=head2 init_suid

Enable the C<setuid> root wrapper?

=head2 make_default

When installed should this installation become the default for this
host? Causes the symbolic link (that hides the version directory from
the C<PATH> environment variable) to be deleted and recreated pointing
to this installation

=head2 post_install

Runs the post installation methods as defined in the
L<post installation config|/read_post_install_config>

=head2 populate_account

Calls the L<populate account|CatalystX::Usul::Users::UnixAdmin/populate_account>
method on the user model

=head2 read_secure

Reads a key file from the secure directory and prints it to STDOUT

=head2 restart_server

Restarts the web server

=head2 roles

Returns the identity roles object

=head2 roles_update

Calls the L<roles update|CatalystX::Usul::Roles::Unix/roles_update>
method on the user model

=head2 run

Modifies the parent method to reject unauthorized calls

=head2 set_owner

Set the ownership of the installed files and directories

=head2 set_password

Calls L</update_password> with a true parameter

=head2 set_permissions

Set the permissions on the installed files and directories

=head2 set_user

Execs an interactive shell as another user

=head2 signal_process

Calls the L<signal process as root|CatalystX::Usul::IPC/signal_process_as_root>
method in the L<CatalystX::Usul::IPC> class

=head2 tape_backup

Runs the L<tape backup|CatalystX::Usul::CLI/tape_backup>
command in the C<appname_cli> program

=head2 uninstall

Will uninstall the application

=head2 untaint_self

Returns an untainted reconstruction of our own invoking command line

=head2 update_account

Calls C<update_account> in the user model to change attributes of the
user account

=head2 update_mail_aliases

Updates a mail alias via L<File::MailAlias>

=head2 update_password

Changes a users password by calling C<update_password> on the user model

=head2 update_progs

Uses C<scp> to copy program files from the specified remote server

=head1 Private Methods

=head2 _deploy_mod_perl_server

Creates the symlinks necessary to deploy the Apache/mod_perl server

=head2 _deploy_plack_server

Create the symlink necessary to deploy the Plack server

=head2 _is_authorised

Is the user authorised to call the method

=head2 _is_setuid

Is the program running suid

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::TraitFor::PostInstallConfig>

=item L<Class::Null>

=item L<Class::Usul::Programs>

=item L<CatalystX::Usul::Moose>

=item L<CatalystX::Usul::Constraints>

=item L<IO::Interactive>

=item L<TryCatch>

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

Copyright (c) 2013 Peter Flanigan. All rights reserved

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
