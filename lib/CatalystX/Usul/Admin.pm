# @(#)$Id: Admin.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Admin;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Programs);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(arg_list class2appdir throw untaint_path);
use Class::Null;
use MRO::Compat;
use File::MailAlias;
use File::Find      qw(find);
use List::Util      qw(first);
use English         qw(-no_match_vars);
use IO::Interactive qw(is_interactive);
use Scalar::Util    qw(weaken);
use TryCatch;

use CatalystX::Usul::Model::UserProfiles;
use CatalystX::Usul::Roles::Unix;
use CatalystX::Usul::Users::UnixAdmin;

__PACKAGE__->mk_accessors( qw(secsdir) );

my %CONFIG =
   ( group_add_cmd   => q(groupadd),
     group_del_cmd   => q(delgroup),
     parms           => { update_password => [ FALSE ] },
     profile_class   => q(CatalystX::Usul::UserProfiles),
     public_methods  => [ qw(authenticate change_password list_methods) ],
     role_class      => q(CatalystX::Usul::Roles::Unix),
     sites_available => [ NUL, qw(etc apache2 sites-available) ],
     sites_enabled   => [ NUL, qw(etc apache2 sites-enabled) ],
     server_options  => [ { plack    => q(Plack/Starman) },
                          { mod_perl => q(Apache/mod_perl) },
                          { none     => q(None) }, ],
     user_add_cmd    => q(useradd),
     user_class      => q(CatalystX::Usul::Users::UnixAdmin),
     user_del_cmd    => q(deluser),
     user_mod_cmd    => q(usermod), );

sub new {
   my ($self, @rest) = @_;

   my $attrs = { config => \%CONFIG, %{ arg_list @rest } };
   my $new   = $self->next::method( $attrs );

   $new->parms  ( { %{ $new->config->{parms} }, %{ $new->parms } }  );
   $new->secsdir( $new->catdir( $new->config->{vardir}, q(secure) ) );
   $new->version( $VERSION );

   return $new;
}

sub is_authorised {
   my $self = shift; my $wanted = $self->method or return FALSE;

   first { $wanted eq $_ } @{ $self->config->{public_methods} } and return TRUE;

   my $user = $self->logname or return FALSE;

   first { __find_method( $wanted, $_ ) } $self->_list_auth_sub_files( $user )
      or return FALSE;
   q(user_) eq substr $wanted, 0, 5 or return TRUE;
   $self->parms->{set_user} = [ substr $wanted, 5 ];
   $self->method( q(set_user) );
   return TRUE;
}

sub is_setuid {
   my $self = shift; return (stat $self->pathname)[ 2 ] & oct q(04000);
}

sub account_report : method {
   my $self = shift;

   $self->info( $self->users->user_report( @ARGV ), { no_lead => TRUE } );
   return OK;
}

sub authenticate : method {
   my $self = shift;

   try        { $self->users->authenticate( TRUE, @ARGV ) }
   catch ($e) { $self->error( $e->error, { args => $e->args } ); return FAILED }

   return OK;
}

sub create_account : method {
   my $self = shift;

   $self->info( $self->users->create_account( @ARGV ) );
   return OK;
}

sub create_ugrps : method {
   # Create the two groups and one users used by this application
   my $self = shift; my ($cmd, $text);

   my $cfg     = $self->config;
   my $picfg   = $self->read_post_install_config;
   my $user    = $picfg->{process_owner} || $picfg->{owner};
   my $groups  = [ $picfg->{group}, $picfg->{admin_role} ];
   my $default = $picfg->{create_ugrps};

   $text  = 'Use groupadd, useradd, and usermod to create the user ';
   $text .= $picfg->{owner}.' and the groups '.$picfg->{group}.' and ';
   $text .= $picfg->{admin_role};
   $self->output( $text, $cfg->{paragraph} );

   my $choice  = $self->yorn( 'Create groups and user', $default, TRUE, 0 );

   $picfg->{create_ugrps} = $choice or return OK;

   $text  = 'Which user does the HTTP server run as? This user ';
   $text .= 'will be added to the application group so that it can ';
   $text .= 'access the application\'s files';
   $self->output( $text, $cfg->{paragraph} );

   $user  = $self->get_line( 'HTTP server user', $user, TRUE, 0 );

   # Create the application and support groups
   $self->_create_app_groups( $cfg->{group_add_cmd}, $groups );

   # Create the user to own the files and support the application
   $self->_create_app_user( $cfg->{user_add_cmd}, $picfg );

   # Add the process owner user to the application group
   $self->_add_user_to_group( $cfg->{user_mod_cmd}, $user, $picfg->{group} );

   ($picfg->{uid}, $picfg->{gid}) = $self->get_owner( $picfg );

   return OK;
}

sub deploy_server : method {
   # Redispatch to server specific method
   my $self          = shift;
   my $picfg         = $self->read_post_install_config;
   my $server_opts   = $self->config->{server_options};
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

   my $method = q(_deploy_).$deploy_server.q(_server);

   my $ref; $ref = $self->can( $method ) and return $self->$ref();

   return OK;
}

sub delete_account : method {
   my $self = shift;

   $self->info( $self->users->delete_account( @ARGV ) );
   return OK;
}

sub init_suid : method {
   my $self = shift; my $cfg = $self->config;

   my $picfg = $self->read_post_install_config; my $text;

   $text  = 'Enable wrapper which allows limited access to some root ';
   $text .= 'only functions like password checking and user management. ';
   $text .= 'Necessary if the OS authentication store is used';
   $self->output( $text, $cfg->{paragraph} );

   $self->yorn( 'Enable suid root', $picfg->{init_suid}, TRUE, 0 ) or return OK;

   my $secd = $self->secsdir; my $path = $self->suid;

   my ($uid, $gid) = $self->get_owner( $picfg );

   $text  = 'Restricting permissions on '.$self->basename( $secd );
   $text .= " and ".$self->basename( $path );

   $self->info( $text );
   # Restrict access for these files to root only
   chown 0, $gid, $secd; chmod oct q(02700), $secd;

   for ($self->io( $secd )->filter( sub { m{ \.sub \z }mx } )->all_files) {
      chown 0, $gid, "$_"; chmod oct q(600), "$_";
   }

   chown 0, $gid, $path; chmod oct q(04750), $path;

   return OK;
}

sub make_default : method {
   # Create the default version symlink
   my $self   = shift;
   my $picfg  = $self->read_post_install_config;
   my $text   = 'Make this the default version';

   $self->yorn( $text, $picfg->{make_default}, TRUE, 0 ) or return OK;

   my $verdir = $self->_unlink_default_link;

   $self->info   ( $self->symlink( NUL, $verdir,    q(default) ) );
   $self->run_cmd( [ qw(chown -h), $picfg->{owner}, q(default) ] );
   return OK;
}

sub populate_account : method {
   my $self = shift;

   $self->info( $self->users->populate_account( @ARGV ) );
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

   $self->_write_post_install_config( $picfg );
   return OK;
}

sub restart_server : method {
   # Bump start the web server
   my $self    = shift;
   my $picfg   = $self->read_post_install_config;
   my $default = $picfg->{restart_server};

   $self->yorn( 'Restart HTTP server', $default, TRUE, 0 ) or return OK;

   my $cmd     = $picfg->{restart_server_cmd};
      $cmd     = $self->get_line
      ( 'HTTP server restart command', $cmd, TRUE, 0, TRUE );
   my $prog    = (split SPC, $cmd)[ 0 ];

   ($prog and -x $prog) or return FAILED;

   $self->info( "Server restart, running $cmd" );
   $self->run_cmd( $cmd );
   return OK;
}

sub roles {
   return shift->_identity->[ 1 ];
}

sub roles_update : method {
   my $self = shift;

   $self->output( $self->roles->roles_update( @ARGV ) );
   return OK;
}

sub set_owner : method {
   # Now we have created everything and have an owner and group
   my $self = shift; my $picfg = $self->read_post_install_config;

   my $base        = $self->config->{appldir};
   my ($uid, $gid) = $self->get_owner( $picfg );
   my $text        = 'Setting owner '.$picfg->{owner}."($uid) and group ";
      $text       .= $picfg->{group}."($gid)";

   $self->info( $text );
   chown $uid, $gid, $self->dirname( $base );
   find( sub { chown $uid, $gid, $_ }, $base );
   chown $uid, $gid, $base;
   return OK;
}

sub set_password : method {
   return shift->update_password( TRUE );
}

sub set_permissions : method {
   # Set permissions
   my $self = shift; my $picfg = $self->read_post_install_config;

   my $base = $self->config->{appldir}; my $pref = $self->prefix;

   $self->info( "Setting permissions on ${base}" );
   chmod oct q(02750), $self->dirname( $base );

   find( sub { if    (-d $_)                { chmod oct q(02750), $_ }
               elsif ($_ =~ m{ $pref _ }mx) { chmod oct q(0750),  $_ }
               elsif ($_ =~ m{ \.sh \z }mx) { chmod oct q(0750),  $_ }
               else                         { chmod oct q(0640),  $_ } },
         $base );

   # Make the shared directories group writable
   for my $dir (grep { $_->is_dir }
                map  { $self->abs_path( $base, $_ ) }
                    @{ $picfg->{create_dirs} }) {
      $dir->chmod( 02770 );
   }

   return OK;
}

sub set_user : method {
   my ($self, $user) = @_; my $logname = $self->logname; my $logger;

   is_interactive() or throw 'Not interactive';
   $logger = $self->os->{logger}->{value} or throw 'Logger not specified';
   -x $logger or throw error => 'Cannot execute [_1]', args => [ $logger ];

   $logname =~ m{ \A ([\w.]+) \z }msx and $logname = $1;

   my $msg  = "Admin suid from ${logname} to ${user}";
   my $cmd  = [ $logger,  qw(-t suid -p auth.info -i), "${msg}" ];

   $self->run_cmd( $cmd );

   my $path = $self->catfile( $self->config->{binsdir},
                              $self->prefix.q(_suenv) );

   $cmd = $ARGV[ 1 ] || NUL;

   if ($ARGV[ 0 ] and $ARGV[ 0 ] eq q(-)) {
      # Old style full login, ENV unset, HOME set for new user
      $cmd = "su - ${user}";
   }
   elsif ($ARGV[ 0 ] and $ARGV[ 0 ] eq q(+)) {
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

   $self->vars->{pids} = \@ARGV;
   $self->signal_process_as_root( %{ $self->vars } );
   return OK;
}

sub tape_backup : method {
   my $self = shift; my ($cmd, $res, $text);

   $self->info( 'Starting tape backup on '.$self->vars->{device} );
   $cmd  = $self->catfile( $self->config->{binsdir}, $self->prefix.q(_cli) );
   $cmd .= SPC.$self->debug_flag;
   $cmd .= ' -c tape_backup -L '.$self->language;
   $cmd .= ' -o '.$_.'="'.$self->vars->{ $_ }.'"' for (keys %{ $self->vars });
   $cmd .= ' -- '.(join q( ), map { '"'.$_.'"' } @ARGV);

   $self->output( $self->run_cmd( $cmd )->out );
   return OK;
}

sub uninstall : method {
   my $self   = shift;
   my $cfg    = $self->config;
   my $appdir = class2appdir $cfg->{class};
   my $picfg  = $self->read_post_install_config;

   if ($picfg->{deploy_server} eq q(plack)) {
      $self->run_cmd( [ q(invoke-rc.d), $appdir, q(stop)   ],
                      { expected_rv => 100 } );
      $self->io     ( [ NUL, qw(etc init.d), $appdir       ] )->unlink;
      $self->run_cmd( [ q(update-rc.d), $appdir, q(remove) ] );
   }
   elsif ($picfg->{deploy_server} eq q(mod_perl)) {
      my $link = sprintf '%-3.3d-%s', $cfg->{phase}, $appdir;

      $self->io( [ @{ $cfg->{sites_enabled  } }, $link      ] )->unlink;
      $self->io( [ @{ $cfg->{sites_available} }, $appdir    ] )->unlink;
      $self->run_cmd( [ q(invoke-rc.d), $appdir, q(restart) ] );
   }

   my $io  = $self->io( [ NUL, qw(etc default), $appdir ] );

   $io->exists and $io->unlink;

   my $cmd = $self->catfile( $cfg->{binsdir}, $self->prefix.q(_schema) );

   $self->run_cmd( [ $cmd, $self->debug_flag, qw(-c drop_database) ],
                   { err => q(stderr), out => q(stdout) } );
   $self->run_cmd( $self->interpolate_cmd( $cfg->{user_del_cmd },
                                           $picfg->{owner} ) );
   $self->run_cmd( $self->interpolate_cmd( $cfg->{group_del_cmd},
                                           $picfg->{group} ) );
   $self->run_cmd( $self->interpolate_cmd( $cfg->{group_del_cmd},
                                           $picfg->{admin_role} ) );

   $self->_unlink_default_link;
   return OK;
}

sub untaint_self {
   my $self = shift; my $cmd = $self->pathname;

   $cmd .= SPC.$self->debug_flag;
   $cmd .= ' -e -c "'.$self->method.'"';
   $cmd .= ' -L '.$self->language if ($self->language);
   $cmd .= ' -q'                  if ($self->quiet);
   $cmd .= ' -o '.$_.'="'.$self->vars->{ $_ }.'"' for (keys %{ $self->vars });
   $cmd .= ' -- '.(join q( ), map { "'".$_."'" } @ARGV);
   $cmd  = untaint_path $cmd;

   $self->debug and $self->log_debug( $cmd );
   return $cmd;
}

sub update_account : method {
   my $self = shift;

   $self->info( $self->users->update_account( @ARGV ) );
   return OK;
}

sub update_mail_aliases : method {
   my $self = shift;

   $self->output( File::MailAlias->new( @ARGV )->update_as_root );
   return OK;
}

sub update_password : method {
   my $self = shift;

   $self->output( $self->users->update_password( shift, @ARGV ) );
   return OK;
}

sub update_progs : method {
   my $self    = shift;
   my $cfg     = $self->config;
   my $path    = $self->io( [ $cfg->{ctrldir}, q(default).$cfg->{conf_extn} ] );
   my $globals = $self->file_dataclass_schema->load( $path )->{globals}
      or throw 'No global config from ${path}';
   my $global  = $globals->{ssh_id} or throw 'No SSH identity from ${path}';
   my $ssh_id  = $global->{value} or throw 'No SSH identity value from ${path}';
   my $from    = $ARGV[ 0 ] or throw 'Copy from file path not specified';
   my $to      = $ARGV[ 1 ] or throw 'Copy to file path not specified';
   my $cmd     = 'su '.$self->owner." -c 'scp -i ${ssh_id} ${from} ${to}'";

   $self->info( $self->run_cmd( $cmd )->out );
   return OK;
}

sub users {
   return shift->_identity->[ 0 ];
}

# Private methods

sub _add_user_to_group {
   my ($self, $cmd, $user, $group) = @_; ($cmd and $user and $group) or return;

   $self->info   ( "Adding process owner (${user}) to group (${group})" );
   $self->run_cmd( $self->interpolate_cmd( $cmd, $group, $user ) );
   return;
}

sub _call_post_install_method {
   my ($self, $cfg, $key, @args) = @_;

   if ($key eq q(admin)) {
      if ($cfg->{post_install}) {
         my $ref; $ref = $self->can( $args[ 0 ] ) and $self->$ref();
      }
      else { $self->info( 'Would call '.$args[ 0 ] ) }
   }
   else {
      my $prog    = $self->prefix.q(_).$key;
      my $cmd     = [ $prog, $self->debug_flag, q(-c), $args[ 0 ] ];
      my $cmd_str = join SPC, @{ $cmd };

      if ($cfg->{post_install}) {
         $self->info( "Running ${cmd_str}" );
         $cmd->[ 0 ] = $self->abs_path( $self->config->{binsdir}, $cmd->[ 0 ] );
         $self->run_cmd( $cmd, { err => q(stderr), out => q(stdout) } );
      }
      else { $self->info( "Would run ${cmd_str}" ) }
   }

   return;
}

sub _create_app_groups {
   my ($self, $cmd, $groups) = @_; ($cmd and $groups) or return;

   for my $grp (grep { not getgrnam $_ } @{ $groups }) {
      $self->info( "Creating group ${grp}" );
      $self->run_cmd( $self->interpolate_cmd( $cmd, $grp ) );
   }

   return;
}

sub _create_app_user {
   my ($self, $cmd, $picfg) = @_;

   ($cmd and $picfg) or return; getpwnam $picfg->{owner} and return;

   my $cfg = $self->config; (my $text = ucfirst $cfg->{class}) =~ s{ :: }{ }gmx;

   $picfg->{gecos  } = "$text Support";
   $picfg->{homedir} = $self->dirname( $cfg->{appldir} );

   $self->info   ( 'Creating user '.$picfg->{owner} );
   $self->run_cmd( $self->interpolate_cmd( $cmd, $picfg ) );
   return;
}

sub _deploy_mod_perl_server {
   my $self = shift;
   my $cfg  = $self->config;
   my $base = $cfg->{appldir};
   my $file = class2appdir $cfg->{class};
   my $from = [ qw(var etc mod_perl.conf) ];
   my $to   = [ @{ $cfg->{sites_available} }, $file ];
   my $link = sprintf '%-3.3d-%s', $cfg->{phase}, $file;

   $self->info( $self->symlink( $base, $from, $to ) );

   $from = [ @{ $cfg->{sites_available} }, $file ];
   $to   = [ @{ $cfg->{sites_enabled  } }, $link ];
   $self->info( $self->symlink( $base, $from, $to ) );

   $from = [ NUL, qw(etc apache2 mods-available expires.load) ];
   $to   = [ NUL, qw(etc apache2 mods-enabled   expires.load) ];
   $self->info( $self->symlink( $base, $from, $to ) );
   return OK;
}

sub _deploy_plack_server {
   my $self = shift; my $file = class2appdir $self->config->{class};

   $self->abs_path( $self->config->{appldir}, [ qw(var etc psgi.sh) ] )
        ->copy    ( [ NUL, qw(etc init.d), $file ] )
        ->chmod   ( 0755 );
   $self->run_cmd ( [ q(update-rc.d), $file, qw(defaults 98 02) ] );
   return OK;
}

sub _identity {
   my $self  = shift;

   exists $self->{_identity_cache} and return $self->{_identity_cache};

   my $roles = $self->config->{role_class}->new( $self, {} );
   my $users = $self->config->{user_class}->new( $self, {} );
   my $attrs = { path => $self->config->{profiles_path} };

   $users->profiles( $self->config->{profile_class}->new( $self, $attrs ) );
   $users->roles   ( $roles ); weaken( $users->{roles} );
   $roles->users   ( $users ); weaken( $roles->{users} );

   return $self->{_identity_cache} = [ $users, $roles ];
}

sub _interpolate_useradd_cmd {
   my ($self, $cmd, $cfg) = @_;

   return [ $cmd, q(-c), $cfg->{gecos}, q(-d), $cfg->{homedir},
                  q(-g), $cfg->{group}, q(-G), $cfg->{admin_role},
                  q(-s), $cfg->{shell}, $cfg->{owner} ];
}

sub _interpolate_usermod_cmd {
   my ($self, $cmd, $group, $user) = @_;

   return [ $cmd, qw(-a -G), $group, $user ];
}

sub _list_auth_sub_files {
   my ($self, $user) = @_;

   return grep { $_->is_file }
          map  { $self->io( [ $self->secsdir, $_.q(.sub) ] ) }
                 $self->roles->get_roles( $user );
}

sub _unlink_default_link {
   my $self   = shift;
   my $base   = $self->config->{appldir};
   my $verdir = $self->basename( $base );

   chdir $self->dirname( $base ); -e q(default) and unlink q(default);

   return $verdir;
}

sub _write_post_install_config {
   my ($self, $picfg) = @_;

   my $cfg  = $self->config;
   my $path = $self->catfile( $cfg->{ctrldir}, $cfg->{pi_config_file} );
   my $args = { data => $picfg, path => $path };

   $self->file_dataclass_schema( $cfg->{pi_config_attrs} )->dump( $args );
   return;
}

# Private subroutines

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

0.6.$Revision: 1165 $

=head1 Synopsis

   # Setuid root program wrapper
   use CatalystX::Usul::Admin;
   use English qw(-no_match_vars);

   my $prog = CatalystX::Usul::Admin->new( appclass => q(App::Munchies),
                                           arglist  => q(e) );

   $EFFECTIVE_USER_ID  = 0; $REAL_USER_ID  = 0;
   $EFFECTIVE_GROUP_ID = 0; $REAL_GROUP_ID = 0;

   unless ($prog->is_authorised) {
      my $text = 'Permission denied to '.$prog->method.' for '.$prog->logname;

      $prog->error( $text );
      exit 1;
   }

   exit $prog->run;

=head1 Description

Methods called from the setuid root program wrapper

=head1 Subroutines/Methods

=head2 new

Constructor

=head2 is_authorised

Is the user authorised to call the method

=head2 is_setuid

Is the program running suid

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

=head2 init_suid

Enable the C<setuid> root wrapper?

=head2 make_default

When installed should this installation become the default for this
host? Causes the symbolic link (that hides the version directory from
the C<PATH> environment variable) to be deleted and recreated pointing
to this installation

=head2 post_install

Runs the post installation methods as defined in the
L<post installtion config|/read_post_install_config>

=head2 populate_account

Calls the L<populate account|CatalystX::Usul::Users::UnixAdmin/populate_account>
method on the user model

=head2 restart_server

Restarts the web server

=head2 roles

Returns the identity roles object

=head2 roles_update

Calls the L<roles update|CatalystX::Usul::Roles::Unix/roles_update>
method on the user model

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

=head2 update_mail_aliases

=head2 update_password

=head2 update_progs

=head2 users

=head1 Private Methods

=head2 _deploy_mod_perl_server

Creates the symlinks necessary to deploy the Apache/mod_perl server

=head2 _deploy_plack_server

Create the symlink necessary to deploy the Plack server

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
