# @(#)$Id: Build.pm 1092 2011-12-16 20:38:17Z pjf $

package CatalystX::Usul::Build;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1092 $ =~ /\d+/gmx );
use parent qw(Module::Build);
use lib;

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(class2appdir say);
use CatalystX::Usul::Programs;
use CatalystX::Usul::Time;
use Config;
use TryCatch;
use File::Spec;
use MRO::Compat;
use Pod::Select;
use Perl::Version;
use Module::CoreList;
use Module::Metadata;
use Pod::Eventual::Simple;
use English         qw(-no_match_vars);
use File::Copy      qw(copy);
use File::Find      qw(find);
use IO::Interactive qw(is_interactive);
use Scalar::Util    qw(blessed);

if ($ENV{AUTOMATED_TESTING}) {
   # Some CPAN testers set these. Breaks dependencies
   $ENV{PERL_TEST_CRITIC} = FALSE; $ENV{PERL_TEST_POD} = FALSE;
   $ENV{TEST_CRITIC     } = FALSE; $ENV{TEST_POD     } = FALSE;
}

my %CONFIG =
   ( actions       => [ qw(create_dirs create_files copy_files link_files
                           edit_files) ],
     arrays        => [ qw(actions arrays attrs copy_files create_dirs
                           create_files credentials link_files
                           post_install_cmds) ],
     attrs         => [ qw(path_prefix ver phase
                           install post_install built) ],
     changes_file  => q(Changes),
     change_token  => q({{ $NEXT }}),
     cpan_authors  => q(http://search.cpan.org/CPAN/authors/id),
     cpan_dists    => q(http://search.cpan.org/dist),
     config_attrs  => { storage_attributes => { root_name => q(config) } },
     config_file   => [ qw(var etc build.xml) ],
     create_ugrps  => TRUE,
     edit_files    => TRUE,
     install       => TRUE,
     line_format   => q(%-9s %s),
     local_lib     => q(local),
     manifest_file => q(MANIFEST),
     paragraph     => { cl => TRUE, fill => TRUE, nl => TRUE },
     path_prefix   => [ NUL, qw(opt) ],
     phase         => 1,
     pwidth        => 50,
     time_format   => q(%Y-%m-%d %T %Z), );

# Around these M::B actions

sub ACTION_distmeta {
   my $self = shift;

   try {
      # Optionally create a README.pod file
      $self->notes->{create_readme_pod} and podselect( {
         -output => q(README.pod) }, $self->dist_version_from );

      $self->_update_changelog( $self->_get_config, $self->_dist_version );
      $self->next::method();
   }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

sub ACTION_install {
   my $self = shift;

   try {
      my $cfg = $self->_ask_questions( $self->_get_config );

      $self->_set_install_paths( $cfg );
      $cfg->{install} and $self->next::method();

      # Call each of the defined installation actions
      $self->$_( $cfg ) for (grep { $cfg->{ $_ } } @{ $self->actions });

      $self->_log_info( 'Installation complete' );
      $self->_post_install( $cfg );
   }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

# New M::B actions

sub ACTION_change_version {
   my $self = shift;

   try {
      $self->depends_on( q(manifest) );
      $self->depends_on( q(release)  );
      $self->_change_version( $self->_get_config );
   }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

sub ACTION_install_local_cpanm {
   my $self = shift;

   try {
      $self->depends_on( q(install_local_lib) );
      $self->_install_local_cpanm( $self->_get_local_config );
   }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

sub ACTION_install_local_deps {
   my $self = shift;

   try {
      my $cfg = $self->_get_local_config;

      $ENV{DEVEL_COVER_NO_COVERAGE} = TRUE;     # Devel::Cover
      $ENV{SITEPREFIX} = $cfg->{perlbrew_root}; # XML::DTD

      $self->depends_on( q(install_local_cpanm) );
      $self->_install_local_deps( $cfg );
   }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

sub ACTION_install_local_lib {
   my $self = shift;

   try {
      my $cfg = $self->_get_local_config;

      $self->_install_local_lib( $cfg );
      $self->_import_local_env ( $cfg );
   }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

sub ACTION_install_local_perl {
   my $self = shift;

   try {
      $self->depends_on( q(install_local_perlbrew) );
      $self->_install_local_perl( $self->_get_local_config );
   }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

sub ACTION_install_local_perlbrew {
   my $self = shift;

   try {
      $self->depends_on( q(install_local_lib) );
      $self->_install_local_perlbrew( $self->_get_local_config );
   }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

sub ACTION_local_archive {
   my $self = shift;

   try {
      my $dir = $self->_get_config->{local_lib};

      $self->make_tarball( $dir, $self->_get_archive_names( $dir )->[ 0 ] );
   }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

sub ACTION_prereq_diff {
   my $self = shift;

   try        { $self->_prereq_diff( $self->_get_config ) }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

sub ACTION_release {
   my $self = shift;

   try {
      $self->depends_on( q(distmeta) );
      $self->_commit_release( 'release '.$self->_dist_version ) }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

sub ACTION_restore_local_archive {
   my $self = shift;

   try {
      my $dir = $self->_get_config->{local_lib};

      $self->_extract_tarball( $self->_get_archive_names( $dir ) );
   }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

sub ACTION_standalone {
   my $self = shift;

   try {
      $self->depends_on( q(install_local_deps) );
      $self->depends_on( q(manifest) );
      $self->depends_on( q(dist) );
   }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

sub ACTION_uninstall {
   my $self = shift;

   try {
      my $cfg = $self->_get_config;

      $self->_set_install_paths( $cfg );
      $self->_uninstall( $cfg );
   }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

sub ACTION_upload {
   # Upload the distribution to CPAN
   my $self = shift;

   try {
      $self->depends_on( q(release) );
      $self->depends_on( q(dist) );
      $self->_cpan_upload;
   }
   catch ($e) { $self->cli->fatal( $e ) }

   return;
}

# Public object methods

sub actions {
   # Accessor/mutator for the list of defined actions
   my ($self, $actions) = @_;

   defined $actions and $self->{_actions} = $actions;
   defined $self->{_actions} or $self->{_actions} = $CONFIG{actions};

   return $self->{_actions};
}

sub cli {
   # Self initialising accessor for the command line interface object
   my $self = shift;

   return $self->{cli} ||= CatalystX::Usul::Programs->new
      ( { appclass => $self->module_name, n => TRUE } );
}

sub config_attributes {
   # Accessor/mutator for the list of defined config attributes
   my ($self, $attrs) = @_;

   defined $attrs and $self->{_attributes} = $attrs;
   defined $self->{_attributes} or $self->{_attributes} = $CONFIG{attrs};

   return $self->{_attributes};
}

sub dispatch {
   # Now we can have M::B plugins
   my $self = shift; $self->_setup_plugins; return $self->next::method( @_ );
}

sub dist_description {
   # More meta data. Requires patching M::B::PodParser
   return shift->_pod_parse( q(description) );
}

sub make_tarball {
   # I want my tarballs in the parent of the project directory
   my ($self, $dir, $archive) = @_; $archive ||= $dir;

   return $self->next::method( $dir, $self->_archive_file( $archive ) );
}

sub patch_file {
   # Will apply a patch to a file only once
   my ($self, $path, $patch) = @_; my $cli = $self->cli;

   (not $path->is_file or -f $path.q(.orig)) and return;

   $self->_log_info( "Patching ${path}" ); $path->copy( $path.q(.orig) );

   my $cmd = [ qw(patch -p0), $path->pathname, $patch->pathname ];

   $self->_log_info( $cli->run_cmd( $cmd, { err => q(out) } )->out );
   return;
}

sub process_files {
   # Find and copy files and directories from source tree to destination tree
   my ($self, $src, $dest) = @_; $src or return; $dest ||= q(blib);

   if    (-f $src) { $self->_copy_file( $src, $dest ) }
   elsif (-d _) {
      my $prefix = $self->base_dir;

      find( { no_chdir => TRUE, wanted => sub {
         (my $path = $File::Find::name) =~ s{ \A $prefix }{}mx;
         return $self->_copy_file( $path, $dest );
      }, }, $src );
   }

   return;
}

sub process_local_files {
   # Will copy the local lib into the blib
   my $self = shift; return $self->process_files( q(local) );
}

sub public_repository {
   # Accessor for the public VCS repository information
   my $class = shift; my $repo = $class->repository or return;

   return $repo !~ m{ \A file: }mx ? $repo : undef;
}

sub repository {
   # Accessor for the VCS repository
   my $vcs = shift->_vcs or return; return $vcs->repository;
}

sub skip_pattern {
   # Accessor/mutator for the regular expression of paths not to process
   my ($self, $re) = @_;

   defined $re and $self->{_skip_pattern} = $re;

   return $self->{_skip_pattern};
}

# Questions

sub q_built {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $prefix = $cfg->{path_prefix} or $cli->throw( 'No path_prefix' );

   $cfg->{base} = $cli->catdir( $prefix, class2appdir $self->module_name,
                                q(v).$cfg->{ver}.q(p).$cfg->{phase} );
   return TRUE;
}

sub q_install {
   my ($self, $cfg) = @_; my $cli = $self->cli; my $text;

   my $install = $cfg->{install} || TRUE;

   $text  = 'Running Module::Build install may require superuser privilege ';
   $text .= 'to create directories. Depends on the path prefix';

   $cli->output( $text, $cfg->{paragraph} );

   return $cli->yorn( 'Run Module::Build install', $install, TRUE, 0 );
}

sub q_path_prefix {
   my ($self, $cfg) = @_; my $cli = $self->cli; my $text;

   my $prefix = $cli->catdir( @{ $cfg->{path_prefix} || [] } ) || NUL;

   $text  = 'Where in the filesystem should the application install to. ';
   $text .= 'Application name is automatically appended to the prefix';

   $cli->output( $text, $cfg->{paragraph} );

   return $cli->get_line( 'Enter install path prefix', $prefix, TRUE, 0 );
}

sub q_phase {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $phase = $cfg->{phase} || PHASE; my $text;

   $text  = 'Phase number determines at run time the purpose of the ';
   $text .= 'application instance, e.g. live(1), test(2), development(3)';
   $cli->output( $text, $cfg->{paragraph} );
   $phase = $cli->get_line( 'Enter phase number', $phase, TRUE, 0 );
   $phase =~ m{ \A \d+ \z }mx
      or $cli->throw( "Phase value $phase bad (not an integer)" );

   return $phase;
}

sub q_post_install {
   my ($self, $cfg) = @_; my $cli = $self->cli; my $text;

   my $run = defined $cfg->{post_install} ? $cfg->{post_install} : TRUE;

   $text  = 'Execute post installation commands. These may take ';
   $text .= 'several minutes to complete';
   $cli->output( $text, $cfg->{paragraph} );

   return $cli->yorn( 'Post install commands', $run, TRUE, 0 );
}

sub q_ver {
   my $self = shift; (my $ver = $self->dist_version) =~ s{ \A v }{}mx;

   my ($major, $minor) = split m{ \. }mx, $ver;

   return $major.q(.).$minor;
}

# Actions

sub copy_files {
   # Copy some files without overwriting
   my ($self, $cfg) = @_; my $cli = $self->cli;

   for my $pair (@{ $cfg->{copy_files} }) {
      my $from = $cli->abs_path( $self->base_dir, $pair->{from} );
      my $to   = $cli->abs_path( $self->_get_dest_base( $cfg ), $pair->{to} );

      ($from->is_file and not -e $to->pathname) or next;
      $self->_log_info( "Copying ${from} to ${to}" );
      $from->copy( $to )->chmod( 0640 );
   }

   return;
}

sub create_dirs {
   # Create some directories that don't ship with the distro
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $base = $self->_get_dest_base( $cfg );

   for my $io (map { $cli->abs_path( $base, $_ ) } @{ $cfg->{create_dirs} }) {
      if ($io->is_dir) { $self->_log_info( "Directory ${io} exists" ) }
      else { $self->_log_info( "Creating ${io}" ); $io->mkpath( oct q(02750) ) }
   }

   return;
}

sub create_files {
   # Create some empty log files
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $base = $self->_get_dest_base( $cfg );

   for my $io (map { $cli->abs_path( $base, $_ ) } @{ $cfg->{create_files} }){
      unless ($io->is_file) { $self->_log_info( "Creating ${io}" ); $io->touch }
   }

   return;
}

sub edit_files {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   # Fix hard coded path in suid program
   my $io   = $cli->io( [ $self->install_destination( q(bin) ),
                          $cli->prefix.q(_admin) ] );
   my $that = qr( \A use \s+ lib \s+ .* \z )msx;
   my $this = 'use lib q('.$cli->catdir( $cfg->{base}, q(lib) ).");\n";

   $io->is_file and $io->substitute( $that, $this )->chmod( 0555 );

   # Pointer to the application directory in /etc/default/<app dirname>
   $io   = $cli->io( [ NUL, qw(etc default),
                       class2appdir $self->module_name ] );
   $that = qr( \A APPLDIR= .* \z )msx;
   $this = q(APPLDIR=).$cfg->{base}."\n";

   $io->is_file and $io->substitute( $that, $this )->chmod( 0644 );
   return;
}

sub link_files {
   # Link some files
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $base = $self->_get_dest_base( $cfg ); my $msg;

   for my $link (@{ $cfg->{link_files} }) {
      try        { $msg = $self->symlink( $base, $link->{from}, $link->{to} ) }
      catch ($e) { $msg = NUL.$e }

      $self->_log_info( $msg );
   }

   return;
}

# Private methods

sub _archive_dir {
   return File::Spec->updir;
}

sub _archive_file {
   return $_[ 0 ]->cli->catfile( $_[ 0 ]->_archive_dir, $_[ 1 ] );
}

sub _ask_questions {
   my ($self, $cfg) = @_; $cfg->{built} and return $cfg;

   my $cli = $self->cli; $cli->pwidth( $cfg->{pwidth} );

   # Update the config by looping through the questions
   for my $attr (@{ $self->config_attributes }) {
      my $method = q(q_).$attr; $cfg->{ $attr } = $self->$method( $cfg );
   }

   $cli->anykey;

   # Save the updated config for the post install commands to use
   my $args = { data => $cfg, path => $self->_get_config_path( $cfg ) };

   $self->cli->file_dataclass_schema( $cfg->{config_attrs} )->dump( $args );

   return $cfg;
}

sub _change_version {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $comp = $cli->get_line( 'Enter major/minor 0 or 1',  1, TRUE, 0 );
   my $bump = $cli->get_line( 'Enter increment/decrement', 0, TRUE, 0 )
           or return;
   my $ver  = $self->_dist_version or return;
   my $from = __tag_from_version( $ver );

   $ver->component( $comp, $ver->component( $comp ) + $bump );
   $comp == 0 and $ver->component( 1, 0 );
   $self->_update_version( $from, __tag_from_version( $ver ) );
   $self->_create_tag_release( $from );
   $self->_update_changelog( $cfg, $ver = $self->_dist_version );
   $self->_commit_release( 'first '.__tag_from_version( $ver ) );
   $self->_rebuild_build;
   return;
}

sub _commit_release {
   my ($self, $msg) = @_; my $cli = $self->cli;

   my $vcs = $self->_vcs or return;

   $vcs->commit( ucfirst $msg ) and say "Committed ${msg}";
   $vcs->error and say @{ $vcs->error };
   return;
}

sub _consolidate {
   my ($self, $used) = @_; my (%dists, %result);

   $self->cli->ensure_class_loaded( q(CPAN) );

   for my $used_key (keys %{ $used }) {
      my ($curr_dist, $module, $prev_dist); my $try_module = $used_key;

      while ($curr_dist = __dist_from_module( $try_module )
             and (not $prev_dist
                  or  $curr_dist->base_id eq $prev_dist->base_id)) {
         $module = $try_module;
         $prev_dist or $prev_dist = $curr_dist;
         $try_module =~ m{ :: }mx or last;
         $try_module =~ s{ :: [^:]+ \z }{}mx;
      }

      unless ($module) {
         $result{ $used_key } = $used->{ $used_key }; next;
      }

      exists $dists{ $module } and next;
      $dists{ $module } = $self->_version_from_module( $module );
   }

   $result{ $_ } = $dists{ $_ } for (keys %dists);

   return \%result;
}

sub _copy_file {
   my ($self, $src, $dest) = @_; my $cli = $self->cli;

   my $pattern = $self->skip_pattern;

   ($src and -f $src and (not $pattern or $src !~ $pattern)) or return;

   # Rebase the directory path
   my $dir = $cli->catdir( $dest, $cli->dirname( $src ) );

   # Ensure target directory exists
   -d $dir or $cli->io( $dir )->mkpath( oct q(02750) );

   copy( $src, $dir );
   return;
}

sub _cpan_upload {
   my $self = shift; my $cli  = $self->cli; my $args = $self->_read_pauserc;

   $args->{subdir} = lc $self->dist_name;
   exists $args->{dry_run} or $args->{dry_run}
      = $cli->yorn( 'Really upload to CPAN', FALSE, TRUE, 0 );
   $cli->ensure_class_loaded( q(CPAN::Uploader) );
   CPAN::Uploader->upload_file( $self->dist_dir.q(.tar.gz), $args );
   return;
}

sub _create_tag_release {
   my ($self, $tag) = @_; my $cli = $self->cli; my $vcs = $self->_vcs or return;

   say "Creating tagged release v${tag}";

   $vcs->tag( $tag ); $vcs->error and say @{ $vcs->error };
   return;
}

sub _dependencies {
   my ($self, $paths) = @_; my $used = {};

   for my $path (@{ $paths }) {
      my $lines = __read_non_pod_lines( $path );

      for my $line (split m{ \n }mx, $lines) {
         my $modules = __parse_depends_line( $line ); $modules->[ 0 ] or next;

         for (@{ $modules }) {
            __looks_like_version( $_ ) and $used->{perl} = $_ and next;

            not exists $used->{ $_ }
               and $used->{ $_ } = $self->_version_from_module( $_ );
         }
      }
   }

   return $used;
}

sub _dist_version {
   my $self = shift;
   my $info = Module::Metadata->new_from_file( $self->dist_version_from );

   return Perl::Version->new( $info->version );
}

sub _draw_line {
    my ($self, $count) = @_; return say q(-) x ($count || 60);
}

sub _extract_tarball {
   my ($self, $archives) = @_; my $cli = $self->cli;

   for my $file (map { $self->_archive_file( $_.q(.tar.gz) ) } @{ $archives }) {
      unless (-f $file) { $cli->info( "Archive ${file} not found\n" ) }
      else {
         $cli->run_cmd( [ qw(tar -xzf), $file ] );
         $cli->info   ( "Extracted ${file}\n"   );
         return;
      }
   }

   return;
}

sub _filter_dependents {
   my ($self, $cfg, $used) = @_;

   my $perl_version = $used->{perl} || $cfg->{min_perl_ver};
   my $core_modules = $Module::CoreList::version{ $perl_version };
   my $provides     = $self->cli->get_meta->provides;

   return $self->_consolidate( { map   { $_ => $used->{ $_ }              }
                                 grep  { not exists $core_modules->{ $_ } }
                                 grep  { not exists $provides->{ $_ }     }
                                 keys %{ $used } } );
}

sub _filter_build_requires_paths {
   return [ grep { m{ \.t \z }mx } @{ $_[ 1 ] } ];
}

sub _filter_configure_requires_paths {
   return [ grep { $_ eq q(Build.PL) } @{ $_[ 1 ] } ];
}

sub _filter_requires_paths {
   return [ grep { not m{ \.t \z }mx and $_ ne q(Build.PL) } @{ $_[ 1 ] } ];
}

sub _get_archive_names {
   my ($self, $original_dir) = @_;

   my $name     = $self->dist_name;
   my $arch     = $Config{myarchname};
   my @archives = ( join q(-), $name, $original_dir,
                    $self->args->{ARGV}->[ 0 ] || $self->_dist_version, $arch );
   my $pattern  = "${name} - ${original_dir} - (.+) - ${arch}";
   my $latest   = ( map  { $_->[ 1 ] }               # Returning filename
                    sort { $a->[ 0 ] <=> $b->[ 0 ] } # By version object
                    map  { __to_version_and_filename( $pattern, $_ ) }
                    $self->cli->io    ( $self->_archive_dir      )
                              ->filter( sub { m{ $pattern }msx } )
                              ->all_files )[ -1 ];

   $latest and push @archives, $latest;
   return \@archives;
}

sub _get_config {
   my ($self, $passed_cfg) = @_; $passed_cfg ||= {};

   exists $self->{_config_cache} and return $self->{_config_cache};

   my $cfg  = { %CONFIG, %{ $passed_cfg }, %{ $self->notes } };
   my $path = $self->_get_config_path( $cfg );

   if (-f $path) {
      my $attrs = { storage_attributes => { force_array => $cfg->{arrays} } };

      $cfg = $self->cli->file_dataclass_schema( $attrs )->load( $path );
   }

   return $self->{_config_cache} = $cfg;
}

sub _get_config_path {
   my ($self, $cfg) = @_;

   return $self->cli->catfile( $self->base_dir, $self->blib,
                               @{ $cfg->{config_file} } );
}

sub _get_dest_base {
   my ($self, $cfg) = @_;

   return $self->destdir ? $self->cli->catdir( $self->destdir, $cfg->{base} )
                         : $cfg->{base};
}

sub _get_local_config {
   my $self = shift; my $cli = $self->cli;

   $self->{_local_config_cache} and return $self->{_local_config_cache};

  (my $perl_ver = $PERL_VERSION) =~ s{ \A v }{perl-}mx;

   my $argv = $self->args->{ARGV}; my $cfg = $self->_get_config;

   $cfg->{perl_ver     } = $argv->[ 0 ] || $perl_ver;
   $cfg->{appldir      } = $argv->[ 1 ] || $cli->config->{appldir};
   $cfg->{perlbrew_root} = $cli->catdir ( $cfg->{appldir}, $cfg->{local_lib} );
   $cfg->{local_etc    } = $cli->catdir ( $cfg->{perlbrew_root}, q(etc) );
   $cfg->{local_libperl} = $cli->catdir ( $cfg->{perlbrew_root}, qw(lib perl5));
   $cfg->{perlbrew_bin } = $cli->catdir ( $cfg->{perlbrew_root}, q(bin) );
   $cfg->{perlbrew_cmnd} = $cli->catfile( $cfg->{perlbrew_bin }, q(perlbrew) );
   $cfg->{local_lib_uri} = join SEP, $cfg->{cpan_authors}, $cfg->{ll_author},
                                     $cfg->{ll_ver_dir}.q(.tar.gz);

   return $self->{_local_config_cache} ||= $cfg;
}

sub _import_local_env {
   my ($self, $cfg) = @_;

   lib->import( $cfg->{local_libperl} );

   require local::lib; local::lib->import( $cfg->{perlbrew_root} );

   return;
}

sub _install_local_cpanm {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $cmd  = q(curl -s -L http://cpanmin.us | perl - App::cpanminus -L );
   my $path = $cli->catfile( $cfg->{perlbrew_bin}, q(cpanm) );

   -f $path and return;

   $self->_log_info( 'Installing local copy of App::cpanminus...' );
   $cli->run_cmd( $cmd.$cfg->{perlbrew_root} );
   not -f $path and $cli->throw( "Failed to install App::cpanminus to $path" );
   return;
}

sub _install_local_deps {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $local_lib = $cfg->{perlbrew_root} or $cli->throw( 'Local lib not set' );

   $self->_log_info( "Installing dependencies to ${local_lib}..." );

   my $cmd = [ qw(cpanm -L), $local_lib, qw(--installdeps .) ];

   $cli->run_cmd( $cmd, { err => q(stderr), out => q(stdout) } );

   my $ref; $ref = $self->can( q(hook_local_deps) ) and $self->$ref( $cfg );

   return;
}

sub _install_local_lib {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $dir = $cfg->{ll_ver_dir}; -d $cfg->{local_lib} and return;

   chdir $cfg->{appldir};
   $self->_log_info( 'Installing local::lib to '.$cfg->{perlbrew_root} );
   $cli->run_cmd( q(curl -s -L ).$cfg->{local_lib_uri}.q( | tar -xzf -) );

   (-d $dir and chdir $dir) or $cli->throw( "Directory ${dir} cannot access" );

   my $cmd = q(perl Makefile.PL --bootstrap=).$cfg->{perlbrew_root};

   $cli->run_cmd( $cmd.q( --no-manpages) );
   $cli->run_cmd( q(make test) );
   $cli->run_cmd( q(make install) );

   chdir $cfg->{appldir}; $cli->io( $cfg->{ll_ver_dir} )->rmtree;
   return;
}

sub _install_local_perl {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   unless (__perlbrew_mirror_is_set( $cli, $cfg )) {
      my $cmd = "echo 'm\n".$cfg->{perl_mirror}."' | perlbrew mirror";

      $self->_log_info( 'Setting perlbrew mirror' );
      __run_perlbrew( $cli, $cfg, $cmd );
   }

   unless (__perl_version_is_installed( $cli, $cfg )) {
      $self->_log_info( 'Installing '.$cfg->{perl_ver}.'...' );
      __run_perlbrew( $cli, $cfg, q(perlbrew install ).$cfg->{perl_ver} );
   }

   __run_perlbrew( $cli, $cfg, q(perlbrew switch ).$cfg->{perl_ver} );
   return;
}

sub _install_local_perlbrew {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   -f $cfg->{perlbrew_cmnd} and return;

   $self->_log_info( 'Installing local perlbrew...' );
   $cli->run_cmd ( q(cpanm -L ).$cfg->{perlbrew_root}.q( App::perlbrew) );
   __run_perlbrew( $cli, $cfg, q(perlbrew init) );
   $cli->io      ( [ $cfg->{local_etc}, q(kshrc) ] )
       ->print   ( __local_kshrc_content( $cfg ) );

   my $ref; $ref = $self->can( q(hook_local_perlbrew) ) and $self->$ref( $cfg );

   return;
}

sub _log_info {
   return shift->log_info( map { chomp; "${_}\n" } @{ [ @_ ] } );
}

sub _post_install {
   my ($self, $cfg) = @_;

   $cfg->{post_install} and $self->_run_bin_cmd( $cfg, q(post_install) )
      and $self->_log_info( 'Post install complete' );

   return;
}

sub _prereq_diff {
   my ($self, $cfg) = @_;

   my $field   = $self->args->{ARGV}->[ 0 ] || q(requires);
   my $filter  = q(_filter_).$field.q(_paths);
   my $prereqs = $self->prereq_data->{ $field };
   my $depends = $self->_dependencies( $self->$filter( $self->_source_paths ) );
   my $used    = $self->_filter_dependents( $cfg, $depends );

   $self->_say_diffs( __compare_prereqs_with_used( $field, $prereqs, $used ) );
   return;
}

sub _read_pauserc {
   my $self    = shift;
   my $cli     = $self->cli;
   my $pauserc = $cli->catfile( $ENV{HOME} || File::Spec->curdir, q(.pause) );
   my $args    = {};

   for ($cli->io( $pauserc )->chomp->getlines) {
      next unless ($_ and $_ !~ m{ \A \s* \# }mx);
      my ($k, $v) = m{ \A \s* (\w+) \s+ (.+) \z }mx;
      exists $args->{ $k } and $cli->throw( "Multiple enties for ${k}" );
      $args->{ $k } = $v;
   }

   return $args;
}

sub _rebuild_build {
   my $self = shift; my $cmd = [ $EXECUTABLE_NAME, q(Build.PL) ];

   $self->cli->run_cmd( $cmd, { err => q(out) } );
   return;
}

sub _run_bin_cmd {
   my ($self, $cfg, $key) = @_; my $cli = $self->cli; my $cmd;

   $cfg and ref $cfg eq HASH and $key and $cmd = $cfg->{ $key.q(_cmd) }
         or $cli->throw( "Command ${key} not found" );

   my ($prog, @args) = split SPC, $cmd;
   my $bind = $self->install_destination( q(bin) );
   my $path = $cli->abs_path( $bind, $prog );

   -f $path or $cli->throw( "Path ${path} not found" );

   $cmd = join SPC, $path, @args;
   $self->_log_info( "Running ${cmd}" );
   $cli->run_cmd( $cmd, { err => q(stderr), out => q(stdout) } );

   my $ref; $ref = $self->can( q(hook_).$key ) and $self->$ref( $cfg );

   return TRUE;
}

sub _say_diffs {
   my ($self, $diffs) = @_; my $cli = $self->cli; $self->_draw_line;

   for my $table (sort keys %{ $diffs }) {
      say $table; $self->_draw_line;

      for (sort keys %{ $diffs->{ $table } }) {
         say "'$_' => '".$diffs->{ $table }->{ $_ }."',";
      }

      $self->_draw_line;
   }

   return;
}

sub _set_install_paths {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   $cfg->{base} or $cli->throw( 'Config base path not set' );

   $self->_log_info( 'Base path '.$cfg->{base} );
   $self->install_base( $cfg->{base} );
   $self->install_path( bin   => $cli->catdir( $cfg->{base}, q(bin)   ) );
   $self->install_path( lib   => $cli->catdir( $cfg->{base}, q(lib)   ) );
   $self->install_path( var   => $cli->catdir( $cfg->{base}, q(var)   ) );
   $self->install_path( local => $cli->catdir( $cfg->{base}, q(local) ) );
   return;
}

sub _setup_plugins {
   # Load CX::U::Plugin::Build::* plugins. Can haz plugins for M::B!
   my $self = shift; my $cli = $self->cli;

   exists $self->{_plugins} and return $self->{_plugins};

   my $config = { child_class  => blessed $self,
                  search_paths => [ q(::Plugin::Build) ],
                  %{ $cli->config->{ setup_plugins } || {} } };

   return $self->{_plugins} = $cli->setup_plugins( $config );
}

sub _source_paths {
   my $self = shift; my $cli = $self->cli;

   return [ grep { m{ (?: \.pm | \.t | \.pl ) \z }imx
                   || $cli->io( $_ )->getline
                         =~ m{ \A \#! (?: .* ) perl (?: \s | \z ) }mx }
            map  { s{ \s+ }{ }gmx; (split SPC, $_)[ 0 ] }
            $cli->io( $CONFIG{manifest_file} )->chomp->getlines ];
}

sub _uninstall {
   my ($self, $cfg) = @_;

   $self->_run_bin_cmd( $cfg, q(uninstall) )
      and $self->_log_info( 'Uninstall complete' );

   return;
}

sub _update_changelog {
   my ($self, $cfg, $ver) = @_;

   my $cli  = $self->cli;
   my $io   = $cli->io( $cfg->{changes_file} );
   my $tok  = $cfg->{change_token};
   my $time = time2str( $cfg->{time_format} || NUL );
   my $line = sprintf $cfg->{line_format}, $ver->normal, $time;
   my $tag  = q(v).__tag_from_version( $ver );
   my $text = $io->all;

   if (   $text =~ m{ ^   \Q$tag\E }mx)    {
          $text =~ s{ ^ ( \Q$tag\E .* ) $ }{$line}mx   }
   else { $text =~ s{   ( \Q$tok\E    )   }{$1\n\n$line}mx }

   say 'Updating '.$cfg->{changes_file};
   $io->close->print( $text );
   return;
}

sub _update_version {
   my ($self, $from, $to) = @_;

   my $cli   = $self->cli;
   my $prog  = $EXECUTABLE_NAME;
   my $cmd   = "'s{ \Q${from}\E \\.%d    }{${to}.%d}gmx;";
      $cmd  .= " s{ \Q${from}\E \\.\$Rev }{${to}.\$Rev}gmx'";
      $cmd   = [ q(xargs), q(-i), $prog, q(-pi), q(-e), $cmd, q({}) ];
   my $paths = [ map { "$_\n" } @{ $self->_source_paths } ];

   $cli->popen( $cmd, { err => q(out), in => $paths } );
   return;
}

sub _vcs {
   my $self = shift; my $class = __PACKAGE__.q(::VCS); my $vcs;

   my $dir  = ref $self ? $self->cli->config->{appldir} : File::Spec->curdir;

   ref $self and $vcs = $self->{_vcs} and return $vcs;

   $vcs = $class->new( $dir ); ref $self and $self->{_vcs} = $vcs;

   return $vcs;
}

sub _version_from_module {
   my ($self, $module) = @_; my $version;

   eval "no warnings; require ${module}; \$version = ${module}->VERSION;";

   return $self->cli->catch || ! $version ? undef : $version;
}

# Private subroutines

sub __compare_prereqs_with_used {
   my ($field, $prereqs, $used) = @_;

   my $result     = {};
   my $add_key    = "Would add these to the ${field} in Build.PL";
   my $remove_key = "Would remove these from the ${field} in Build.PL";
   my $update_key = "Would update these in the ${field} in Build.PL";

   for (grep { defined $used->{ $_ } } keys %{ $used }) {
      if (exists $prereqs->{ $_ }) {
         my $oldver = version->new( $prereqs->{ $_ } );
         my $newver = version->new( $used->{ $_ }    );

         if ($newver != $oldver) {
            $result->{ $update_key }->{ $_ }
               = $prereqs->{ $_ }.q( => ).$used->{ $_ };
         }
      }
      else { $result->{ $add_key }->{ $_ } = $used->{ $_ } }
   }

   for (keys %{ $prereqs }) {
      exists $used->{ $_ }
         or $result->{ $remove_key }->{ $_ } = $prereqs->{ $_ };
   }

   return $result;
}

sub __dist_from_module {
   my $module = CPAN::Shell->expand( q(Module), $_[ 0 ] );

   return $module ? $module->distribution : undef;
}

sub __local_kshrc_content {
   my $cfg = shift; my $content;

   $content  = '#!/usr/bin/env ksh'."\n";
   $content .= q(export LOCAL_LIB=).$cfg->{local_libperl}."\n";
   $content .= q(export PERLBREW_ROOT=).$cfg->{perlbrew_root}."\n";
   $content .= q(export PERLBREW_PERL=).$cfg->{perl_ver}."\n";
   $content .= q(export PERLBREW_BIN=).$cfg->{perlbrew_bin}."\n";
   $content .= q(export PERLBREW_CMND=).$cfg->{perlbrew_cmnd}."\n";
   $content .= <<'RC';

perlbrew_set_path() {
   alias -d perl 1>/dev/null
   path_without_perlbrew=$(perl -e \
      'print join ":", grep   { index $_, $ENV{PERLBREW_ROOT} }
                       split m{ : }mx, $ENV{PATH};')
   export PATH=${PERLBREW_BIN}:${path_without_perlbrew}
}

perlbrew() {
   local rc ; export SHELL ; short_option=""

   if [ $(echo ${1} | cut -c1) = '-' ]; then
      short_option=${1} ; shift
   fi

   case "${1}" in
   (use)
      if [ -z "${2}" ]; then
         print "Using ${PERLBREW_PERL} version"
      elif [ -x ${PERLBREW_ROOT}/perls/${2}/bin/perl -o ${2} = system ]; then
         unset PERLBREW_PERL
         eval $(${PERLBREW_CMND} ${short_option} env ${2})
         perlbrew_set_path
      else
         print "${2} is not installed" >&2 ; rc=1
      fi
      ;;

   (switch)
      ${PERLBREW_CMND} ${short_option} ${*} ; rc=${?}
      test -n "$2" && perlbrew_set_path
      ;;

   (off)
      unset PERLBREW_PERL
      ${PERLBREW_CMND} ${short_option} off
      perlbrew_set_path
      ;;

   (*)
      ${PERLBREW_CMND} ${short_option} ${*} ; rc=${?}
      ;;
   esac
   alias -t -r
   return ${rc:-0}
}

eval $(perl -I${LOCAL_LIB} -Mlocal::lib=${PERLBREW_ROOT})

perlbrew_set_path

RC

   return $content;
}

sub __looks_like_version {
    my $ver = shift;

    return defined $ver && $ver =~ m{ \A v? \d+ (?: \.[\d_]+ )? \z }mx;
}

sub __parse_depends_line {
   my $line = shift; my $modules = [];

   for my $stmt (grep   { length }
                 map    { s{ \A \s+ }{}mx; s{ \s+ \z }{}mx; $_ }
                 split m{ ; }mx, $line) {
      if ($stmt =~ m{ \A (?: use | require ) \s+ }mx) {
         my (undef, $module, $rest) = split m{ \s+ }mx, $stmt, 3;

         # Skip common pragma and things that don't look like module names
         $module =~ m{ \A (?: lib | strict | warnings ) \z }mx and next;
         $module =~ m{ [^\.:\w] }mx and next;

         push @{ $modules }, $module eq q(base) || $module eq q(parent)
                          ? ($module, __parse_list( $rest )) : $module;
      }
      elsif ($stmt =~ m{ \A (?: with | extends ) \s+ (.+) }mx) {
         push @{ $modules }, __parse_list( $1 );
      }
   }

   return $modules;
}

sub __parse_list {
   my $string = shift;

   $string =~ s{ \A q w* [\(/] \s* }{}mx;
   $string =~ s{ \s* [\)/] \z }{}mx;
   $string =~ s{ [\'\"] }{}gmx;
   $string =~ s{ , }{ }gmx;

   return grep { length && !m{ [^\.:\w] }mx } split m{ \s+ }mx, $string;
}

sub __perl_version_is_installed {
   my ($cli, $cfg) = @_; my $perl_ver = $cfg->{perl_ver};

   my $installed = __run_perlbrew( $cli, $cfg, q(perlbrew list) )->out;

   return (grep { m{ $perl_ver }mx } split "\n", $installed)[0] ? TRUE : FALSE;
}

sub __perlbrew_mirror_is_set {
   my ($cli, $cfg) = @_;

   return -f $cli->catfile( $cfg->{perlbrew_root}, q(Conf.pm) );
}

sub __read_non_pod_lines {
   my $path = shift; my $p = Pod::Eventual::Simple->read_file( $path );

   return join "\n", map  { $_->{content} }
                     grep { $_->{type} eq q(nonpod) } @{ $p };
}

sub __run_perlbrew {
   my ($cli, $cfg, $cmd) = @_;

   my $path_sep = $Config::Config{path_sep};
   my $path     = join     $path_sep,
                  grep   { index $_, $cfg->{perlbrew_root} }
                  split m{ $path_sep }mx, $ENV{PATH};

   $ENV{PATH         } = $cfg->{perlbrew_bin }.$path_sep.$path;
   $ENV{PERLBREW_ROOT} = $cfg->{perlbrew_root};
   $ENV{PERLBREW_PERL} = $cfg->{perl_ver     };

   return $cli->run_cmd( $cmd );
}

sub __tag_from_version {
   my $ver = shift; return $ver->component( 0 ).q(.).$ver->component( 1 );
}

sub __to_version_and_filename {
   my ($pattern, $io) = @_;

  (my $file  = $io->filename) =~ s{ [.]tar[.]gz \z }{}msx;
   my ($ver) = $file =~ m{ $pattern }msx;

   return [ qv( $ver ), $file ];
}

# Response classes

package # Hide from indexer
   CatalystX::Usul::Build::VCS;

use parent qw(CatalystX::Usul::Base CatalystX::Usul::File);

use CatalystX::Usul::Constants;
use IPC::Cmd qw(can_run);

__PACKAGE__->mk_accessors( qw(type vcs) );

sub new {
   my ($self, $project_dir) = @_;

   my $new = bless {}, ref $self || $self;

   if (-d $new->catfile( $project_dir, q(.git) )) {
      can_run( q(git) ) or return; # Be nice to CPAN testing

      require Git::Class::Worktree;

      $new->vcs( Git::Class::Worktree->new( path => $project_dir ) );
      $new->type( q(git) );
      return;
   }

   if (-d $new->catfile( $project_dir, q(.svn) )) {
      can_run( q(svn) ) or return; # Be nice to CPAN testing

      require SVN::Class;

      $new->vcs( SVN::Class::svn_dir( $project_dir ) );
      $new->type( q(svn) );
   }

   return $new;
}

sub commit {
   my ($self, $msg) = @_; $self->vcs or return;

   $self->type eq q(git)
      and return $self->vcs->commit( { all => TRUE, message => $msg } );

   return $self->vcs->commit( $msg );
}

sub error {
   my $self = shift; return $self->vcs ? $self->vcs->error : 'No VCS';
}

sub repository {
   my $self = shift; $self->vcs or return;

   my $info = $self->vcs->info or return;

   return $info->root;
}

sub tag {
   my ($self, $tag) = @_; my $vtag = q(v).$tag;

   $self->vcs or return;
   $self->type eq q(git) and return $self->vcs->tag( { tag => $vtag } );

   my $repo = $self->repository or return;
   my $from = $repo.SEP.q(trunk);
   my $to   = $repo.SEP.q(tags).SEP.$vtag;
   my $msg  = "Tagging $vtag";

   return $self->vcs->svn_run( q(copy), [ q(-m), $msg ], "$from $to" );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Build - M::B subclass

=head1 Version

This document describes CatalystX::Usul::Build version 0.4.$Revision: 1092 $

=head1 Synopsis

   use CatalystX::Usul::Build;
   use MRO::Compat;

   my $builder = q(CatalystX::Usul::Build);
   my $class   = $builder->subclass( class => 'Bob', code  => <<'EOB' );

   sub ACTION_instal { # Spelling mistake intentional
      my $self = shift;

      $self->next::method();

      # Your application specific post installation code goes here

      return;
   }
   EOB

=head1 Description

Subclasses L<Module::Build>. Ask questions during the install
phase. The answers to the questions determine where the application
will be installed and which additional actions will take place. Should
be generic enough for any web application

=head1 ACTIONS

=head2 ACTION_build

Prompts the user for information about how this installation is to be
performed. User responses are saved to the F<build.xml> file. The
L</config_attributes> method returns the list of questions to ask

=head2 ACTION_change_version

=head2 _change_version

Changes the C<$VERSION> strings in all of the projects files

=head2 ACTION_distmeta

=head2 distmeta

Updates license file and changelog

=head2 ACTION_install

=head2 install

Optionally calls the C<ACTION_install> method in L<Module::Build>

Next it performs the additional sequence of actions required to install the
application. The L</actions> method returns the list of additional steps
required

=head2 ACTION_install_local_cpanm

Install a copy of L<App::cpanminus> to the local lib

=head2 ACTION_install_local_deps

Install the applications dependencies to the local lib

=head2 ACTION_install_local_lib

Bootstrap a copy of L<local::lib> into the project directory

=head2 ACTION_install_local_perl

Install a version of Perl using L<perlbrew> to the local lib

=head2 ACTION_install_local_perlbrew

Install a copy of L<perlbrew> to the local lib

=head2 ACTION_local_archive

=head2 _local_archive

Create a tarball (in the parent of the project directory, the one with
F<Build.PL> in it). Contains the local lib built by the
L</_install_local_deps> action

=head2 ACTION_prereq_diff

=head2 _prereq_diff

Generates a report of dependencies used by the module. It is presented
as three lists; a list of modules that you might want to add to the
target list in C<Build.PL>, a list of modules you might want to
remove from C<Build.PL>, and a list modules whose versions should be
updated in C<Build.PL>. The target list defaults to I<requires> and
can be changed to I<build_requires> or I<configure_requires> on the
command line

=head2 ACTION_release

=head2 release

Commits the current working copy as the next release

=head2 ACTION_restore_local_archive

=head2 _restore_local_archive

Unpack the tarball created by L</_local_archive>

=head2 ACTION_standalone

Create a local lib directory, populate it with dependencies and then include
it in the application distribution

=head2 ACTION_uninstall

Removes the HTTP server deployment links. Deletes the database. Deletes
the owner id and the two groups that were created when the application
was installed. Does not delete the application files and directories

=head2 ACTION_upload

=head2 upload

Upload distribution to CPAN

=head1 Subroutines/Methods

=head2 actions

   $current_list_of_actions = $builder->actions( $new_list_of_actions );

This accessor/mutator method defaults to the list defined in the
C<$CONFIG{actions}> package variable

=head2 cli

   $cli = $builder->cli;

Returns an instance of L<CatalystX::Usul::Programs>, the command line
interface object

=head2 config_attributes

   $current_list_of_attrs = $builder->config_attributes( $new_list_of_attrs );

This accessor/mutator method defaults to the list defined in the
C<$CONFIG{attrs}> package variable

=head2 dispatch

   $builder->dispatch( @_ );

Intercept the call to parent method and call L</_setup_plugins> first

=head2 dist_description

   $builder->dist_description;

Returns the description section from the POD in the main application class

=head2 make_tarball

   $builder->make_tarball( $dir, $archive );

Prepends C<updir> to the file name and calls
L<make_tarball|Module::Build::Base/make_tarball>. The C<$archive>
defaults to C<$dir>

=head2 patch_file

   $builder->patch_file( $path, $patch );

Apply a patch to the specified file

=head2 process_files

   $builder->process_files( $source, $destination );

Handles the processing of files other than library modules and
programs.  Uses the I<Bob::skip_pattern> defined in the subclass to
select only those files that should be processed.  Copies files from
source to destination, creating the destination directories as
required. Source can be a single file or a directory. The destination
is optional and defaults to B<blib>

=head2 process_local_files

   $builder->process_local_files();

Causes the local lib to be copied to blib during the build process

=head2 public_repository

Return the URI of the VCS repository for this project. Return undef
if we are not using svn or the repository is a local file path

=head2 repository

Returns the URI of the VCS repository for this project

=head2 skip_pattern

   $regexp = $builder->skip_pattern( $new_regexp );

Accessor/mutator method. Used by L</_copy_file> to skip processing files
that match this pattern. Set to false to not have a skip list

=head1 Questions

All question methods are passed C<$config> and return the new value
for one of it's attributes

=head2 q_built

Always returns true. This dummy question is used to trigger the suppression
of any further questions once the build phase is complete

=head2 q_install

Should we execute the Module::Build install method. Answer no if the
distribution tarball was unpacked into the directory where the
application is going to be executed from, e.g. one's home directory
for non-root installations

=head2 q_path_prefix

Prompt for the installation prefix. The application name and version
directory are automatically appended. All of the application will be
installed to this path. The default is F</opt>

=head2 q_phase

The phase number represents the reason for the installation. It is
encoded into the name of the application home directory. At runtime
the application will load some configuration data that is dependent
upon this value

=head2 q_post_install

Prompt for permission to execute the post installation commands

=head2 q_ver

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

=head2 edit_files

Edit the path that points to the application install directory in
F</etc/default/{app-name}>. Edit the same path in the F<{prefix}_admin>
program which runs setuid root. Hence taint mode is on and it cannot aquire
the path

=head2 link_files

Creates some symbolic links

=head1 Private Methods

=head2 _ask_questions

   $config = $builder->_ask_questions( $config );

Called from the L</ACTION_install> method. Writes the C<$config> hash
to file for later use by the post install commands

=head2 _commit_release

   $builder->_commit_release( 'Release message for VCS log' );

Commits the release to the VCS

=head2 _copy_file

   $builder->_copy_file( $source, $destination );

Called by L</process_files>. Copies the C<$source> file to the
C<$destination> directory

=head2 _cpan_upload

   $builder->_cpan_upload;

Called by L</ACTION_upload>. Uses L<CPAN::Uploader> (which it loads on
demand) to do the lifting. Reads from the users F<.pause> in their
C<$ENV{HOME}> directory

=head2 _get_config

   $config = $builder->_get_config( $config_hash_ref );

Will merge the L<Module::Build> C<notes> hash with the passed config
hash ref and the C<%CONFIG> hash in. Caches the result

=head2 _log_info

   $builder->_log_info( @list_of_messages );

Add newlines to the messages before calling parent method

=head2 _set_base_path

   $base = $builder->_set_base_path( $config );

Sets the L<Module::Build> I<install_base> attribute to the base
directory for this installation.  Returns that path. Also sets;
F<bin>, F<lib>, and F<var> directory paths as appropriate. Called from
the L</ACTION_install> method

=head2 _setup_plugins

   $builder->_setup_plugins

Loads any plugins it finds in the C<CX::U::Plugin::Build> namespace.
The C<$builder->config> I<setup_plugins> attribute is passed to
L<setup_plugins|CatalystX::Usul/setup_plugins>

=head2 _update_changelog

   $builder->_update_changelog( $config, $version );

Update the version number and date/time stamp in the F<Changes> file

=head1 Diagnostics

None

=head1 Configuration and Environment

Stores config information in the file F<var/etc/cli.xml>

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Programs>

=item L<Module::Build>

=item L<SVN::Class>

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
