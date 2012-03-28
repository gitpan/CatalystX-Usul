# @(#)$Id: Programs.pm 1127 2012-03-22 20:01:35Z pjf $

package CatalystX::Usul::Programs;

use strict;
use warnings;
use attributes ();
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1127 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul CatalystX::Usul::IPC);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(app_prefix class2appdir elapsed
    env_prefix exception is_arrayref is_member say split_on__ throw
    untaint_identifier untaint_path);
use CatalystX::Usul::InflateSymbols;
use Class::Inspector;
use Class::Null;
use Config;
use English         qw(-no_match_vars);
use File::HomeDir;
use File::Spec;
use Getopt::Mixed   qw(nextOption);
use IO::Interactive qw(is_interactive);
use List::Util      qw(first);
use Log::Handler;
use MRO::Compat;
use Pod::Man;
use Pod::Select ();
use Pod::Usage;
use Scalar::Util    qw(blessed);
use Sys::Hostname;
use Term::ReadKey;
use Text::Autoformat;
use TryCatch;

require Cwd;

my %CONFIG =
   ( conf_extn       => q(.xml),
     default_dirs    => { vardir       => [ qw(var)                ],
                          ctrldir      => [ qw(var etc)            ],
                          dbasedir     => [ qw(var db)             ],
                          localedir    => [ qw(var locale)         ],
                          logsdir      => [ qw(var logs)           ],
                          root         => [ qw(var root)           ],
                          rprtdir      => [ qw(var root reports)   ],
                          rundir       => [ qw(var run)            ],
                          skindir      => [ qw(var root skins)     ],
                          tempdir      => [ qw(var tmp)            ],
                          template_dir => [ qw(var root templates) ], },
     doc_title       => 'User Contributed Documentation',
     extensions      => [ qw(.pl .pm .t) ],
     log_extn        => q(.log),
     man_page_cmd    => [ qw(nroff -man) ],
     no_char         => q(n),
     paragraph       => { cl => TRUE, fill => TRUE, nl => TRUE },
     path_prefix     => [ NUL, qw(opt) ],
     pi_arrays       => [ qw(actions arrays attrs copy_files create_dirs
                             create_files credentials link_files
                             post_install_cmds wait_for) ],
     pi_config_attrs => { storage_attributes => { root_name => q(config) } },
     pi_config_file  => q(build.xml),
     quit            => q(q),
     shell           => [ NUL, qw(bin ksh) ],
     well_known      => [ NUL, qw(etc default) ],
     width           => 80,
     yes_char        => q(y), );

sub new {
   my ($self, @rest) = @_; my $class = blessed $self || $self;

   my $attrs = BUILDARGS( q(_arg_list), $class, @rest );

   $class->mk_accessors( keys %{ $attrs } );

   my $new = $class->next::method( {}, $attrs ); BUILD( $new );

   return $new;
}

sub BUILDARGS {
   my ($next, $class, @rest) = @_; my $args = $class->$next( @rest );

   autoflush STDOUT TRUE; autoflush STDERR TRUE;

   my $attrs = { config => { %{ $args->{config} || {} } } };

   $attrs->{arglist}  = q(c=s D H h L=s n o=s q );
   $attrs->{arglist} .= $args->{arglist } if ($args->{arglist});
   $attrs->{args   }  = exists $args->{n} ? { n => TRUE } : {};
   $attrs->{quiet  }  = exists $args->{quiet} ? TRUE : FALSE;
   $attrs->{script }  = $class->basename( $args->{script} || $PROGRAM_NAME );
   $attrs->{program}  = $class->basename( lc $attrs->{script},
                                          @{ $CONFIG{extensions} } );

   $class->_load_config    ( $attrs, $args );
   $class->_inflate_symbols( $attrs ); # Expand pathnames
   $class->_set_defaults   ( $attrs );

   return $attrs;
}

sub BUILD {
   my $self = shift;

   Getopt::Mixed::init( $self->arglist );

   $self->_copy_args_ref; $self->_copy_vars_ref;

   Getopt::Mixed::cleanup();

   $self->_set_attr( q(c), q(method)   );
   $self->_set_attr( q(L), q(language) );
   $self->_set_attr( q(q), q(quiet)    );

   $self->build_attributes( [ qw(debug log lock l10n os) ], TRUE );

   return;
}

sub add_leader {
   my ($self, $text, $args) = @_; $args ||= {};

   $text = $self->loc( $text || '[no message]', $args->{args} || [] );

   my $leader = exists $args->{no_lead} || exists $args->{noLead}
              ? NUL : (ucfirst $self->name).BRK;

   if ($args->{fill}) {
      my $width = $args->{width} || $self->config->{width};

      $text = autoformat $text, { right => $width - 1 - length $leader };
   }

   return join "\n", map { (m{ \A $leader }mx ? NUL : $leader).$_ }
                     split  m{ \n }mx, $text;
}

sub anykey {
   my ($self, $prompt) = @_; $prompt ||= 'Press any key to continue...';

   return $self->prompt( -p => $prompt, -e => NUL, -1 => TRUE );
}

sub can_call {
   my ($self, $method) = @_;

   return (is_member $method, __list_methods_of( $self )) ? TRUE : FALSE;
}

sub debug_flag {
   my $self = shift; return $self->debug ? q(-D) : q(-n);
}

sub dump_self : method {
   $_[ 0 ]->dumper( $_[ 0 ] ); return OK;
}

sub error {
   my ($self, $err, $args) = @_;

   $self->log_error( $_ ) for (split m{ \n }mx, $err.NUL);

   $self->_print_fh( \*STDERR, $self->add_leader( $err, $args )."\n" );
   return;
}

sub fatal {
   my ($self, $err, $args) = @_; my (undef, $file, $line) = caller 0;

   my $posn = ' at '.Cwd::abs_path( $file )." line ${line}";

   $err ||= 'unknown';

   $self->log_alert( $_ ) for (split m{ \n }mx, $err.$posn);

   $self->_print_fh( \*STDERR, $self->add_leader( $err, $args ).$posn."\n" );

   $err and blessed $err
        and $err->can( q(stacktrace) )
        and $self->_print_fh( \*STDERR, $err->stacktrace."\n" );

   exit FAILED;
}

sub get_line {
   # General text input routine.
   my ($self, $question, $default, $quit, $width, $multiline, $noecho) = @_;

   $question ||= 'Enter your answer';
   $default    = defined $default ? $default : NUL;

   my $quit_char    = $self->config->{quit};
   my $max_width    = $width || $self->pwidth || 60;
   my $advice       = $quit ? "(${quit_char} to quit)" : NUL;
   my $right_prompt = $advice.($multiline ? NUL : SPC.q([).$default.q(]));
   my $left_prompt  = $question;

   if (defined $width) {
      my $left_x = $max_width - (length $right_prompt);

      $left_prompt = sprintf '%-*s', $left_x, $question;
   }

   my $prompt  = $left_prompt.SPC.$right_prompt;

   if ($multiline) {
      $right_prompt = q([).$default.q(]).BRK;

      my $left_x = 3 + $max_width - (length $right_prompt);

      $prompt .= "\n".(SPC x ($left_x > 0 ? $left_x : 0)).$right_prompt;
   }
   else { $prompt .= BRK }

   my $result  = $noecho
               ? $self->prompt( -d => $default, -p => $prompt, -e => q(*) )
               : $self->prompt( -d => $default, -p => $prompt );

   $quit and defined $result and lc $result eq $quit_char and exit FAILED;

   return NUL.$result;
}

sub get_meta {
   my ($self, $path) = @_; my $meta_class = __PACKAGE__.q(::Meta);

   my @paths = ( $self->catfile( $self->config->{appldir}, q(META.yml) ),
                 $self->catfile( $self->config->{ctrldir}, q(META.yml) ),
                 q(META.yml) );

   $path and unshift @paths, $path;

   for (grep { -f $_ } @paths) {
      my $data = $self->{_meta_cache}->{ $_ } ||= $meta_class->load_file( $_ );

      $data->name and return $data;
   }

   throw 'No META.yml file';
   return; # Never reached
}

sub get_option {
   my ($self, $question, $default, $quit, $width, $options) = @_;

   $question ||= 'Select one option from the following list:';

   $self->output( $question, { cl => TRUE } ); my $count = 1;

   my $text = join "\n", map { $count++.q( - ).$_ } @{ $options };

   $self->output( $text, { cl => TRUE, nl => TRUE } );

   my $opt = $self->get_line( 'Select option', $default, $quit, $width );

   $opt !~ m{ \A \d+ \z }mx and $opt = defined $default ? $default : 0;

   return $opt - 1;
}

sub get_owner {
   my ($self, $pi_cfg) = @_; $pi_cfg ||= {};

   return ($self->vars->{uid} || getpwnam( $pi_cfg->{owner} ) || 0,
           $self->vars->{gid} || getgrnam( $pi_cfg->{group} ) || 0);
}

sub info {
   my ($self, $err, $args) = @_;

   $self->log_info( $_ ) for (split m{ [\n] }mx, $err);

   $self->quiet or say $self->add_leader( $err, $args );
   return;
}

sub interpolate_cmd {
   my ($self, $cmd, @args) = @_;

   my $ref = $self->can( q(_interpolate_).$cmd.q(_cmd) )
          or return [ $cmd, @args ];

   return $self->$ref( $cmd, @args );
}

sub list_methods : method {
   say __list_methods_of( shift ); return OK;
}

sub loc {
   my ($self, @rest) = @_;

   my $params = { lang => $self->language, ns => $self->name };

   return $self->next::method( $params, @rest );
}

sub output {
   my ($self, $text, $args) = @_;

   $self->quiet and return;
   $args and $args->{cl} and say;
   say $self->add_leader( $text, $args );
   $args and $args->{nl} and say;
   return;
}

sub prompt {
   my ($self, @rest) = @_; my ($len, $newlines, $next, $text);

   my $IN      = \*STDIN;
   my $OUT     = \*STDOUT;
   my $args    = $self->_map_prompt_args( $self->_arg_list( @rest ));
   my $default = $args->{default};
   my $echo    = $args->{echo   };
   my $onechar = $args->{onechar};
   my $input   = NUL;

   unless (is_interactive()) {
      $ENV{PERL_MM_USE_DEFAULT} and return $default;
      $onechar and return getc $IN;
      return scalar <$IN>;
   }

   my ($cntl, %cntl) = $self->_get_control_chars( $IN );
   local $SIG{INT}   = sub { $self->_restore_mode( $IN ); exit FAILED };

   $self->_print_fh( $OUT, $args->{prompt} );
   $self->_raw_mode( $IN );

   while (TRUE) {
      if (defined ($next = getc $IN)) {
         if ($next eq $cntl{INTERRUPT}) {
            $self->_restore_mode( $IN ); exit FAILED;
         }
         elsif ($next eq $cntl{ERASE}) {
            if ($len = length $input) {
               $input = substr $input, 0, $len - 1;
               $self->_print_fh( $OUT, "\b \b" );
            }

            next;
         }
         elsif ($next eq $cntl{EOF}) {
            $self->_restore_mode( $IN );
            close $IN
               or throw error => 'IO error [_1]', args =>[ $ERRNO ];
            return $input;
         }
         elsif ($next !~ m{ $cntl }mx) {
            $input .= $next;

            if ($next eq "\n") {
               if ($input eq "\n" and defined $default) {
                  $text = defined $echo ? $echo x length $default : $default;
                  $self->_print_fh( $OUT, "[${text}]\n" );
                  $self->_restore_mode( $IN );

                  return $onechar ? substr $default, 0, 1 : $default;
               }

               $newlines .= "\n";
            }
            else { $self->_print_fh( $OUT, defined $echo ? $echo : $next ) }
         }
         else { $input .= $next }
      }

      if ($onechar or not defined $next or $input =~ m{ \Q$RS\E \z }mx) {
         chomp $input; $self->_restore_mode( $IN );
         defined $newlines and $self->_print_fh( $OUT, $newlines );
         return $onechar ? substr $input, 0, 1 : $input;
      }
   }

   return;
}

{  my $_cache;

   sub read_post_install_config {
      my $self  = shift; defined $_cache and return $_cache;

      my $cfg   = $self->config;
      my $attrs = {
         storage_attributes => { force_array => $cfg->{pi_arrays} } };
      my $path  = $self->catfile( $cfg->{ctrldir}, $cfg->{pi_config_file} );

      return $_cache = $self->file_dataclass_schema( $attrs )->load( $path );
   }
}

sub run {
   my $self = shift; my ($parms, $rv, $text);

   exists $self->args->{h} and $self->usage( 1 ); # Usage never returns
   exists $self->args->{H} and $self->usage( 2 );

   my $method = $self->method || $self->usage( 0 ); umask $self->mode;

   $parms = exists $self->parms->{ $method } ? $self->parms->{ $method } : [];
   $text  = 'Started by '.$self->logname.' Version '.$self->version.SPC;
   $text .= 'Pid '.(abs $PID);
   $self->output( $text );

   if ($self->can( $method ) and $self->can_call( $method )) {
      try {
         defined ($rv = $self->$method( @{ $parms } ))
            or throw error => "Method [_1] return value undefined",
                     args  => [ $method ];
      }
      catch ($error) {
         my $e = exception $error;

         $e->out and $self->output( $e->out );
         $self->error( $e->error, { args => $e->args } );
         $self->debug and $self->_print_fh( \*STDERR, $e->stacktrace."\n" );
         $rv = $e->rv || -1;
      }

      not defined $rv and $rv = -1
         and $self->error( "Method ${method} error uncaught/rv undefined" );
   }
   else {
      $self->error( "Method ${method} not defined in class ".(blessed $self) );
      $rv = -1;
   }

   if (defined $rv and not $rv) {
      $self->output( 'Finished in '.elapsed.' seconds' );
   }
   elsif (defined $rv) { $self->output( "Terminated code ${rv}" ) }
   else { $self->output( 'Terminated with undefined rv' ); $rv = FAILED }

   $self->delete_tmp_files;
   return $rv;
}

sub usage {
   my ($self, $verbose) = @_; my $method = $ARGV[ 0 ];

   $method and $self->can_call( $method ) and exit $self->_usage_for( $method );

   $verbose > 1 and exit $self->_man_page_from( $self );

   pod2usage( { -input   => $self->pathname, -message => SPC,
                -verbose => $verbose } );
   exit OK; # Never reached
}

sub warning {
   my ($self, $err, $args) = @_;

   $self->log_warn( $_ ) for (split m{ \n }mx, $err);

   $self->quiet or say $self->add_leader( $err, $args );
   return;
}

sub yorn {
   # General yes or no input routine
   my ($self, $question, $default, $quit, $width, $newline) = @_;

   my $cfg  = $self->config; my $result;

   my $noc  = $cfg->{no_char}; my $yesc = $cfg->{yes_char};

   $default = $default ? $yesc : $noc; $quit = $quit ? $cfg->{quit} : NUL;

   my $advice   = $quit ? "(${yesc}/${noc}, ${quit}) " : "(${yesc}/${noc}) ";
   my $r_prompt = $advice.q([).$default.q(]);
   my $l_prompt = $question;

   if (defined $width) {
      my $max_width = $width || $self->pwidth || 40;
      my $right_x   = length $r_prompt;
      my $left_x    = $max_width - $right_x;

      $l_prompt  = sprintf '%-*s', $left_x, $question;
   }

   my $prompt = $l_prompt.SPC.$r_prompt.BRK;

   $newline and $prompt .= "\n";

   while (defined ($result = $self->prompt( -d => $default, -p => $prompt ))) {
      $quit and $result =~ m{ \A (?: $quit | [\e] ) }imx and exit FAILED;
      $result =~ m{ \A $noc  }imx and return FALSE;
      $result =~ m{ \A $yesc }imx and return TRUE;
   }

   exit FAILED;
}

# Private methods

sub _assert_directory {
   my ($self, $path) = @_; $path or return;

   $path = Cwd::abs_path( untaint_path $path ) or return;

   return -d $path ? $path : undef;
}

sub _build_debug {
   my $self = shift; my $args = $self->args || {};

   exists $args->{D}   and return TRUE;
   __dont_ask( $args ) and return FALSE;
   is_interactive()    or  return FALSE;

   return $self->yorn( 'Do you want debugging turned on', FALSE, TRUE );
}

sub _build_log {
   my $self = shift; $self->logfile or return Class::Null->new;

   my $dir = $self->dirname( $self->logfile );

   -d $dir or return Class::Null->new;

   return Log::Handler->new
      ( file      => {
         filename => $self->logfile,
         maxlevel => $self->debug ? 7 : $self->config->{log_level} || 6,
         mode     => q(append), } );
}

sub _build_os {
   my $self = shift;
   my $file = q(os_).$Config{osname}.$self->config->{conf_extn};
   my $path = $self->catfile( $self->config->{ctrldir}, $file );

   ($path = untaint_path( $path ) and -f $path) or return;

   return $self->file_dataclass_schema->load( $path )->{ q(os) } || {};
}

sub _copy_args_ref {
   my $self = shift; my $args = $self->args; my ($k, $v);

   while (($k, $v) = nextOption()) {
      if ($args->{ $k }) {
         if (is_arrayref $args->{ $k }) { push @{ $args->{ $k } }, $v }
         else { $args->{ $k } = [ $args->{ $k }, $v ] }
      }
      else { $args->{ $k } = $v }
   }

   return;
}

sub _copy_vars_ref {
   my $self = shift; my $args = $self->args; my $vars = $self->vars;

   exists $args->{o} or return; my $opts = $args->{o};

   for my $opt ((is_arrayref $opts) ? @{ $opts } : ( $opts )) {
      my ($k, $v) = split m{ [=] }mx, $opt;

      if ($vars->{ $k }) {
         if (is_arrayref $vars->{ $k }) { push @{ $vars->{ $k } }, $v }
         else { $vars->{ $k } = [ $vars->{ $k }, $v ] }
      }
      else { $vars->{ $k } = $v }
   }

   return;
}

sub _get_control_chars {
   my ($self, $handle) = @_; my %cntl = GetControlChars $handle;

   return ((join q(|), values %cntl), %cntl);
}

sub _get_homedir {
   my ($self, $class, $path) = @_; my $cfg = \%CONFIG;

   # 0. Pass the directory in
   $path = $self->_assert_directory( $path ) and return $path;

   # 1. Environment variable
   $path = $ENV{ (env_prefix $class).q(_HOME) };
   $path = $self->_assert_directory( $path ) and return $path;

   # 2a. Users home directory - application directory
   my $appdir   = class2appdir $class;
   my $classdir = $self->classdir( $class );

   $path = $self->catdir( File::HomeDir->my_home, $appdir );
   $path = $self->catdir( $path, qw(default lib), $classdir );
   $path = $self->_assert_directory( $path ) and return $path;

   # 2b. Users home directory - dotfile
   $path = $self->catdir( File::HomeDir->my_home, q(.).$appdir );
   $path = $self->catdir( $path, q(lib), $classdir );
   $path = $self->_assert_directory( $path ) and return $path;

   # 3. Well known path
   my $well_known = $self->catfile( @{ $cfg->{well_known} }, $appdir );

   $path = $self->_read_appldir_from( $well_known );
   $path and $path = $self->catdir( $path, q(lib), $classdir );
   $path = $self->_assert_directory( $path ) and return $path;

   # 4. Default install prefix
   $path = $self->catdir( @{ $cfg->{path_prefix} }, $appdir );
   $path = $self->catdir( $path, qw(default lib), $classdir );
   $path = $self->_assert_directory( $path ) and return $path;

   # 5. Config file found in @INC
   my $file = app_prefix $class;

   for my $dir (map { $self->catdir( Cwd::abs_path( $_ ), $classdir ) } @INC) {
      $path = untaint_path $self->catfile( $dir, $file.$cfg->{conf_extn} );

      -f $path and return $self->dirname( $path );
   }

   # 6. Default to /tmp
   return untaint_path( File::Spec->tmpdir );
}

sub _inflate_symbols {
   my ($self, $attr) = @_; my $cfg = $attr->{config};

   my $inflator = CatalystX::Usul::InflateSymbols->new( $attr );

   $inflator->visit_all; $inflator->inflate_symbols( $cfg->{default_dirs} );

   my $dir = -d $cfg->{tempdir} ? $cfg->{tempdir} : File::Spec->tmpdir;

      $cfg->{tempdir} = untaint_path $dir;
   -d $cfg->{logsdir} or $cfg->{logsdir} = $cfg->{tempdir};

   my $paths = {
      aliases_path  => $self->catfile( $cfg->{ctrldir}, q(aliases) ),
      profiles_path => $self->catfile( $cfg->{ctrldir}, q(user_profiles),
                                       $cfg->{conf_extn} ),
      suid          => $self->catfile( $cfg->{binsdir},
                                       $cfg->{prefix}.q(_admin) ),
   };

   $inflator->inflate_symbols( $paths );
   return;
}

sub _load_config {
   my ($self, $attr, $args) = @_;

   my $prefix = $args->{prefix  } || split_on__ $attr->{program};
   my $class  = $args->{appclass} || ucfirst $prefix;
   my $home   = $self->_get_homedir( $class, $args->{homedir} );
   my $path   = $self->catfile( $home, (app_prefix $class).$CONFIG{conf_extn} );
   my $loaded = {};

   # Now we know where the config file should be we can try parsing it
   -f $path and $loaded = $self->file_dataclass_schema->load( $path );

   my $cfg = $attr->{config} = { %CONFIG, %{ $attr->{config} }, %{ $loaded } };

   $cfg->{prefix} ||= $prefix; $cfg->{class} ||= $class; $cfg->{home} ||= $home;

   return;
}

sub _man_page_from {
   my ($self, $src) = @_; my $cmd = $self->config->{man_page_cmd} || [];

   my $parser   = Pod::Man->new( center  => $self->config->{doc_title} || NUL,
                                 name    => $self->script,
                                 release => 'Version '.$self->version,
                                 section => q(3m) );
   my $tempfile = $self->tempfile;

   $parser->parse_from_file( $src->pathname, $tempfile->pathname );
   say $self->run_cmd( [ @{ $cmd }, $tempfile->pathname ] )->out;
   return OK;
}

sub _map_prompt_args {
   my ($self, $args) = @_;

   my %map = ( qw(-1 onechar -d default -e echo -p prompt) );

   for (keys %{ $args }) {
      exists $map{ $_ } and $args->{ $map{ $_ } } = delete $args->{ $_ };
   }

   return $args;
}

sub _print_fh {
   my ($self, $handle, $text) = @_; $text ||= NUL;

   print {$handle} $text or throw error => 'IO error [_1]', args => [ $ERRNO ];
   return;
}

sub _raw_mode {
   my ($self, $handle) = @_; ReadMode q(raw), $handle; return;
}

sub _read_appldir_from {
   my ($self, $path) = @_;

   return -f $path ? first { length }
                     map   { (split q(=), $_)[ 1 ] }
                     grep  { m{ \A APPLDIR= }mx }
                     $self->io( $path )->chomp->getlines
                   : undef;
}

sub _restore_mode {
   my ($self, $handle) = @_; ReadMode q(restore), $handle; return;
}

sub _set_attr {
   my ($self, $opt, $attr) = @_; exists $self->args->{ $opt } or return;

   if ($self->arglist =~ m{ $opt =s }mx) {
      my $v; $v = $self->args->{ $opt } and $self->$attr( untaint_path $v );
   }
   else { $self->$attr( TRUE ) }

   return;
}

sub _set_defaults {
   my ($class, $attr) = @_;

   my $conf = $attr->{config}; my $prog = delete $attr->{program};

   $attr->{hostname} = hostname;
   $attr->{l10n    } = {};
   $attr->{language} = NUL;
   $attr->{lock    } = {};
   $attr->{method  } = NUL;
   $attr->{os      } = {};
   $attr->{parms   } = {};
   $attr->{vars    } = {};
   $attr->{version } = $VERSION;

   $attr->{debug   } = $conf->{debug}        || FALSE;
   $attr->{logname } = $ENV{USER}            || $ENV{LOGNAME};
   $attr->{mode    } = oct ($conf->{mode}    || q(027) );
   $attr->{name    } = (split_on__ $prog, 1) || $prog;
   $attr->{owner   } = $conf->{owner}        || $conf->{prefix} || q(root);
   $attr->{pwidth  } = $conf->{pwidth}       || 60;
   $attr->{shell   } = $class->catfile( $conf->{shell} );

   my $file = $attr->{name}.$conf->{conf_extn};

   $attr->{ctlfile } = untaint_path $class->catfile( $conf->{ctrldir}, $file );

   $file = $attr->{name}.$conf->{log_extn};

   $attr->{logfile } = untaint_path $class->catfile( $conf->{logsdir}, $file );
   $attr->{pathname} = $class->catfile( $conf->{binsdir}, $attr->{script} );

   return;
}

sub _usage_for {
   my ($self, $method) = @_; my @classes = (blessed $self);

   $method = untaint_identifier $method;

   while (my $class = shift @classes) {
      no strict q(refs);

      if (defined &{ "${class}::${method}" }) {
         my $selector = Pod::Select->new(); $selector->select( q(/).$method );
         my $source   = $self->find_source( $class );
         my $tempfile = $self->tempfile;

         $selector->parse_from_file( $source, $tempfile->pathname );
         return $self->_man_page_from( $tempfile );
      }

      push @classes, $_ for (@{ "${class}::ISA" });
   }

   return FAILED;
}

# Private subroutines

sub __dont_ask {
   return exists $_[ 0 ]->{n} || exists $_[ 0 ]->{h} || exists $_[ 0 ]->{H}
        ? TRUE : FALSE;
}

sub __list_methods_of {
   my $arg = shift; my $class = blessed $arg || $arg;

   return map  { s{ \A .+ :: }{}msx; $_ }
          grep { my $x = $_;
                 grep { $_ eq q(method) } attributes::get( \&{ $x } ) }
              @{ Class::Inspector->methods( $class, 'full', 'public' ) };
}

# Response classes

package # Hide from indexer
   CatalystX::Usul::Programs::Meta;

use parent qw(CatalystX::Usul::Base);

use YAML::Syck;

__PACKAGE__->mk_accessors( qw(abstract author license name
                              provides version) );

sub load_file {
   my ($self, $path) = @_; my $class = ref $self || $self; my $data;

   $path and -f $path and $data = LoadFile( $path );

   return bless $data || {}, $class;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Programs - Provide support for command line programs

=head1 Version

This document describes CatalystX::Usul::Programs version 0.4.$Revision: 1127 $

=head1 Synopsis

   # In YourClass.pm
   use base qw(CatalystX::Usul::Programs);

   # In yourProg.pl
   use YourClass;

   exit YourClass->new( appclass => 'YourApplicationClass' )->run;

=head1 Description

This base class provides methods common to command line programs. The
constructor can initialise a multi-lingual message catalog if required

=head1 Subroutines/Methods

=head2 new

   $self = CatalystX::Usul::Programs->new({ ... })

Return a new program object. The optional argument is a hash ref which
may contain these attributes:

=head3 appclass

The name of the application to which the program using this class
belongs. It is used to find the application installation directory
which will contain the configuration file

=head3 arglist

Additional L<Getopts::Mixed> command line initialisation arguments are
appended to the default list shown below:

=over 3

=item c method

The method in the subclass to call

=item D

Turn debugging on

=item H

Print long help text extracted from this POD

=item h

Print short help text extracted from this POD

=item L language

Print error messages in the selected language. If no language is
supplied print the error code and attributes

=item n

Do not prompt to turn debugging on

=item o key=value

The method that is dispatched to can access the key/value pairs
from the C<< $self->vars >> hash ref

=item q

Quiet. Suppresses the usual started/finished information messages

=back

=head3 debug

Boolean which if true causes program debug output to be
generated. Defaults to false

=head3 evar

Environment variable containing the path to a file which contains
the application installation directory. Defaults to the environment
variable <uppercase application name>_HOME

=head3 install

The path to a file which contains the application installation
directory.

=head3 n

Boolean which if true will stop the constructor from prompting the
user to turn debugging on. Defaults to false

=head3 prefix

Defaults to /opt/<application name>

=head3 script

The name of the program. Defaults to the value returned by L<caller>

=head3 quiet

Boolean which if true suppresses the usual started/finished
information messages. Defaults to false

=head2 BUILDARGS

Initialise the contents of the hash used to instantiate the object. It
is a private method, so do not call it

=head2 BUILD

Called by the constructor to complete the object instantiation

=head2 add_leader

   $leader = $self->add_leader( $text, $args );

Prepend C<< $self->name >> to each line of C<$text>. If
C<< $args->{no_lead} >> exists then do nothing. Return C<$text> with
leader prepended

=head2 anykey

   $key = $self->anykey( $prompt );

Prompt string defaults to 'Press any key to continue...'. Calls and
returns L<prompt|/prompt>. Requires the user to press any key on the
keyboard (that generates a character response)

=head2 can_call

   $bool = $self->can_call( $method );

Returns true if C<$self> has a method given by C<$method> that has defined
the I<method> method attribute

=head2 debug_flag

Returns the command line debug flag to match the current debug state

=head2 dump_self

   $self->dump_self;

Dumps out the self referential object using L<Data::Dumper>

=head2 error

   $self->error( $text, $args );

Calls L</loc> with the passed args. Logs the result at the error
level, then adds the program leader and prints the result to I<STDERR>

=head2 fatal

   $self->fatal( $text, $args );

Calls L</loc> with the passed args. Logs the result at the alert
level, then adds the program leader and prints the result to
I<STDERR>. Exits with a return code of one

=head2 get_line

   $line = $self->get_line( $question, $default, $quit, $width, $newline );

Prompts the user to enter a single line response to C<$question> which
is printed to I<STDOUT> with a program leader. If C<$quit> is true
then the options to quit is included in the prompt. If the C<$width>
argument is defined then the string is formatted to the specified
width which is C<$width> or C<< $self->pwdith >> or 40. If C<$newline>
is true a newline character is appended to the prompt so that the user
get a full line of input

=head2 get_meta

   $res_obj = $self->get_meta( $dir );

Extracts; I<name>, I<version>, I<author> and I<abstract> from the
F<META.yml> file.  Optionally look in C<$dir> for the file instead of
C<< $self->appldir >>. Returns a response object with accessors
defined

=head2 get_option

   $option = $self->get_line( $question, $default, $quit, $width, $options );

Prompts the user to select one from the list of options

=head2 get_owner

   ($uid, $gid) = $self->get_owner( $post_install_config_hash_ref );

Returns the numeric user and group ids of the application owner

=head2 info

   $self->info( $text, $args );

Calls L</loc> with the passed args. Logs the result at the info level,
then adds the program leader and prints the result to I<STDOUT>

=head2 interpolate_cmd

   $self->interpolate_cmd( $cmd, @args );

Flattens C<@args> and returns an array ref of all the passed parameters. If
C<_interpolate_${cmd}_cmd> exists it is called instead and is expected to
create the returned array ref

=head2 list_methods

   $self->list_methods

Prints a list of methods that can be called through this program

=head2 loc

   $local_text = $self->loc( $key, $args );

Localizes the message. Calls L<CatalystX::Usul/loc>

=head2 output

   $self->output( $text, $args );

Calls L</loc> with the passed args. Adds the program leader and prints
the result to I<STDOUT>

=head2 prompt

   $line = $self->prompt( 'key' => 'value', ... );

This was taken from L<IO::Prompt> which has an obscure bug in it. Much
simplified the following keys are supported

=over 3

=item -1

Return the first character typed

=item -d

Default response

=item -e

The character to echo in place of the one typed

=item -p

Prompt string

=back

=head2 read_post_install_config

   $picfg_hash_ref = $self->read_post_install_config;

Returns a hash ref of the post installation config which was written to
the control directory during the installation process

=head2 run

   $rv = $self->run;

Call the method specified by the C<-c> option on the command
line if it exists and L</can_call> returns true. Returns the exit code

=head2 usage

   $self->usage( $verbosity );

Print out usage information from POD. The C<$verbosity> is; 0, 1 or 2

=head2 warning

   $self->warning( $text, $args );

Calls L</loc> with the passed args. Logs the result at the warn level,
then adds the program leader and prints the result to I<STDOUT>

=head2 yorn

   $self->yorn( $question, $default, $quit, $width );

Prompt the user to respond to a yes or no question. The C<$question>
is printed to I<STDOUT> with a program leader. The C<$default>
argument is C<0|1>. If C<$quit> is true then the option to quit is
included in the prompt. If the C<$width> argument is defined then the
string is formatted to the specified width which is C<$width> or
C<< $self->pwdith >> or 40

=head2 _assert_directory

=head2 _build_debug

   $self->_build_debug();

If it is an interactive session prompts the user to turn debugging
on. Returns true if debug is on. Also offers the option to quit

=head2 _build_log

=head2 _get_control_chars

   ($cntrl, %cntrl) = $self->_get_control_chars( $handle );

Returns a string of pipe separated control characters and a hash of
symbolic names and values

=head2 _get_homedir

   $path = $self->_get_homedir( 'myApplication' );

Search through subdirectories of @INC looking for the file
myApplication.xml. Uses the location of this file to return the path to
the installation directory

=head2 _inflate

   $tempdir = $self->inflate( '__appldir(var/tmp)__' );

Inflates symbolic pathnames with their actual runtime values

=head2 _load_os_depends

=head2 _load_vars_ref

=head2 _set_attr

Sets the specified attribute from the command line option

=head2 _raw_mode

   $self->_raw_mode( $handle );

Puts the terminal in raw input mode

=head2 _restore_mode

   $self->_restore_mode( $handle );

Restores line input mode to the terminal

=head1 Configuration and Environment

None

=head1 Diagnostics

Turning debug on produces some more output

=head1 Dependencies

=over 3

=item L<CatalystX::Usul>

=item L<CatalystX::Usul::InflateSymbols>

=item L<Class::Null>

=item L<Getopt::Mixed>

=item L<IO::Interactive>

=item L<Log::Handler>

=item L<Term::ReadKey>

=item L<Text::Autoformat>

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
