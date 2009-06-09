# @(#)$Id: Programs.pm 566 2009-06-09 19:34:27Z pjf $

package CatalystX::Usul::Programs;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 566 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul CatalystX::Usul::Utils);

use CatalystX::Usul::InflateSymbols;
use Class::C3;
use Class::Null;
use Config;
use Cwd qw(abs_path);
use English qw(-no_match_vars);
use File::Spec;
use Getopt::Mixed qw(nextOption);
use IO::Interactive qw(is_interactive);
use IPC::SRLock;
use Log::Handler;
use Pod::Man;
use Pod::Usage;
use Sys::Hostname;
use Term::ReadKey;
use Text::Autoformat;
use XML::Simple;
use YAML::Syck;

my $BRK    = q(: );
my $NO     = q(n);
my $NUL    = q();
my $PREFIX = q(/opt);
my $QUIT   = q(q);
my $SPC    = q( );
my $YES    = q(y);

sub new {
   my ($self, @rest) = @_;

   autoflush STDOUT 1; autoflush STDERR 1;

   my $strap = $self->_bootstrap( $self->arg_list( @rest ) );
   my $new   = $strap->next::method( $strap, {} );

   Getopt::Mixed::init( $new->arglist );

   $new->_load_args_ref();

   Getopt::Mixed::cleanup();

   $new->_set_attr       ( q(c), q(method)        );
   $new->_set_attr       ( q(L), q(language)      );
   $new->_set_attr       ( q(S), q(silent)        );
   $new->debug           ( $new->get_debug_option );
   $new->lock->debug     ( $new->debug            );
   $new->lock->log       ( $new->log              );
   $new->_load_messages  ( $new->language         );
   $new->_load_os_depends(                        );
   $new->_load_vars_ref  (                        );

   return $new;
}

sub add_leader {
   my ($self, $text, $args) = @_; my ($leader, $res);

   $res    = $NUL; $text = $NUL.$text; chomp $text;
   $text   = $self->loc( $self, $text, @{ $args->{args} || [] } );
   $text ||= '[no message]';
   $leader = exists $args->{noLead} || exists $args->{no_lead}
           ? $NUL : (ucfirst $self->name).$BRK;

   if ($args->{fill}) {
      $text = autoformat $text, { right => 79 - length $leader };
   }

   $res = join "\n", map { (m{ \A $leader }mx ? $NUL : $leader).$_ }
                     split  m{ \n }mx, $text;

   return $res;
}

sub anykey {
   my ($self, $prompt) = @_;

   $prompt = 'Press any key to continue...' unless ($prompt);

   return $self->prompt( -p => $prompt, -e => $NUL, -1 );
}

sub config {
   return shift;
}

sub dispatch {
   my $self = shift; my ($e, $method, $parms, $rv, $text);

   $self->usage(1) if     (exists $self->args->{h});
   $self->usage(2) if     (exists $self->args->{H});
   $self->usage(0) unless ($method = $self->method);

   umask $self->mode;

   $parms = exists $self->parms->{ $method } ? $self->parms->{ $method } : [];
   $text  = 'Started by '.$self->logname.' Version '.$self->version.$SPC;
   $text .= 'Pid '.(abs $PID);
   $self->output( $text );

   if ($self->can( $method )) {
      $rv = eval { $self->$method( @{ $parms } ) };

      if ($e = $self->catch) {
         my $class = ref $e;

         if ($class and $class eq $self->exception_class) {
            $self->output( $e->out ) if ( $e->out );
            $self->error ( $e->as_string( $self->debug ? 2 : 1 ),
                           { args => $e->args } );
            $rv = $e->rv || -1 unless (defined $rv);
         }
         else { $self->error( $e ); $rv = -1 }
      }
      else {
         unless (defined $rv) {
            if ($EVAL_ERROR) { $self->error( $EVAL_ERROR ) }
            else { $self->error( "Undefined error in $method" ) }

            $rv = -1;
         }
      }
   }
   else {
      $self->error( "Cannot call method $method from class ".(ref $self) );
      $rv = -1;
   }

   if (defined $rv && $rv == 0) { $self->output( 'Finished' ) }
   else { $self->output( "Terminated code $rv" ) }

   $self->delete_tmp_files;
   return $rv;
}

sub error {
   my ($self, $text, $args) = @_;

   $text = $self->add_leader( $text, $args );

   $self->log_error( $_ ) for (split m{ \n }mx, $text);

   print {*STDERR} $text."\n"
      or $self->throw( error => 'IO error [_1]', args =>[ $ERRNO ] );

   return;
}

sub fatal {
   my ($self, $text, $args) = @_; my ($file, $line);

   (undef, $file, $line) = caller 0;
   $text  = $self->add_leader( $text, $args );
   $text .= ' at '.abs_path( $file ).' line '.$line;

   $self->log_alert( $_ ) for (split m{ \n }mx, $text);

   print {*STDERR} $text."\n"
      or $self->throw( error => 'IO error [_1]', args =>[ $ERRNO ] );
   exit 1;
}

sub get_debug_option {
   my $self = shift; my $args = $self->args || {};

   return 1 if (exists $args->{D});

   return 0 if (exists $args->{n} || exists $args->{h} || exists $args->{H});

   return 0 unless (is_interactive());

   return $self->yorn( 'Do you want debugging turned on', 0, 1 );
}

sub get_line {
   # General text input routine.
   my ($self, $question, $default, $quit, $width, $newline, $pword) = @_;
   my ($advice, $left_x, $left_prompt, $right_prompt, $prompt);
   my ($result, $right_x, $total);

   if ($quit) { $advice = "($QUIT to quit) " }
   else { $advice = $NUL; $quit = 0 }

   $right_prompt = $advice.($default ? q([).$default.q(]) : $NUL);

   if (defined $width) {
      $total       = $width || $self->pwidth || 40;
      $right_x     = length $right_prompt;
      $left_x      = $total - $right_x;
      $left_prompt = sprintf '%-*s', $left_x, $question;
   }
   else { $left_prompt = $question }

   $default ||= $NUL;
   $prompt    = $left_prompt.$SPC.$right_prompt.$BRK;
   $prompt   .= "\n" if ($newline);

   if ($pword) {
      $result = $self->prompt( -d => $default, -e => q(*), -p => $prompt );
   }
   else { $result = $self->prompt( -d => $default, -p => $prompt ) }

   exit 1 if ($quit and defined $result and lc $result eq $QUIT);

   return $NUL.$result;
}

sub get_meta {
   my ($self, $path) = @_;

   unless ($path and -f $path) {
      $path = $self->catfile( $self->appldir, 'META.yml' );
   }

   my @fields   = ( qw(abstract author name version) );
   my %attrs    = map { $_ => $NUL } @fields;
   my $meta_obj = bless \%attrs, ref $self || $self;

   __PACKAGE__->mk_accessors( @fields );

   return $meta_obj unless (-f $path);

   my $data = LoadFile( $path );

   for (@fields) {
      my $val = ref $data->{ $_ } eq q(ARRAY)
              ? $data->{ $_ }->[ 0 ] : $data->{ $_ };
      $meta_obj->$_( $val );
   }

   return $meta_obj;
}

sub info {
   my ($self, $text, $args) = @_;

   $text = $self->add_leader( $text, $args );

   $self->log_info( $_ ) for (split m{ \n }mx, $text);

   $self->say( $text ) unless ($self->silent);

   return;
}

sub output {
   my ($self, $text, $args) = @_;

   return if ($self->silent);

   $self->say if ($args and $args->{cl});

   $self->say( $self->add_leader( $text, $args ) );

   $self->say if ($args and $args->{nl});

   return;
}

sub prompt {
   my ($self, @data) = @_;
   my ($cntl, %cntl, $default, $echo, $input, $len, $newlines);
   my ($next, $onechar, $prompt);

   my $IN = \*STDIN; my $OUT = \*STDOUT;

   for (my $i = 0; $i < @data; $i++) {
      if    ($data[ $i ] eq q(-1)) { $onechar = 1 }
      elsif ($data[ $i ] eq q(-d)) { $default = $data[ $i + 1 ]; $i++ }
      elsif ($data[ $i ] eq q(-e)) { $echo    = $data[ $i + 1 ]; $i++ }
      elsif ($data[ $i ] eq q(-p)) { $prompt  = $data[ $i + 1 ]; $i++ }
   }

   unless (is_interactive()) {
      return $default if ($ENV{PERL_MM_USE_DEFAULT});
      return getc $IN if ($onechar);
      return scalar <$IN>;
   }

   ($cntl, %cntl)  = $self->_get_control_chars( $IN );
   local $SIG{INT} = sub { $self->_restore_mode( $IN ); exit };
   print {$OUT} $prompt
      or $self->throw( error => 'IO error [_1]', args =>[ $ERRNO ] );
   $input = $NUL;
   $self->_raw_mode( $IN );

   while (1) {
      if (defined ($next = getc $IN)) {
         if ($next eq $cntl{INTERRUPT}) {
            $self->_restore_mode( $IN );
            exit;
         }
         elsif ($next eq $cntl{ERASE}) {
            if ($len = length $input) {
               $input = substr $input, 0, $len - 1;
               print {$OUT} "\b \b"
                  or $self->throw( error => 'IO error [_1]', args =>[$ERRNO] );
            }

            next;
         }
         elsif ($next eq $cntl{EOF}) {
            $self->_restore_mode( $IN );
            close $IN
               or $self->throw( error => 'IO error [_1]', args =>[ $ERRNO ] );
            return $input;
         }
         elsif ($next !~ m{ $cntl }mx) {
            $input .= $next;

            if ($next eq "\n") {
               if ($input eq "\n" and $default) {
                  print {$OUT} ('['.(defined $echo
                                     ? $echo x length $default
                                     : $default).']')."\n"
                     or $self->throw( error => 'IO error [_1]',
                                      args  =>[ $ERRNO ] );
                  $self->_restore_mode( $IN );

                  return $onechar ? substr $default, 0, 1 : $default;
               }

               $newlines .= "\n";
            }
            else {
               print {$OUT} (defined $echo ? $echo : $next)
                  or $self->throw( error => 'IO error [_1]', args =>[$ERRNO] );
            }
         }
         else { $input .= $next }
      }

      if ($onechar or not defined $next or $input =~ m{ \Q$RS\E \z }mx) {
         chomp $input; $self->_restore_mode( $IN );

         if (defined $newlines) {
            print {$OUT} $newlines
               or $self->throw( error => 'IO error [_1]', args =>[ $ERRNO ] );
         }

         return $onechar ? substr $input, 0, 1 : $input;
      }
   }

   return;
}

sub stash {
   my $self = shift; return $self;
}

sub usage {
   my ($self, $verbose) = @_; my ($cmd, $name, $parser, $tempfile);

   if ($verbose < 2) {
      pod2usage( { -input   => $self->pathname,
                   -message => $SPC, -verbose => $verbose } );
      exit 0; # Never reached
   }

   $name   = $self->basename( $self->script, qw(.pl) );
   $parser = Pod::Man->new( center  => $self->doc_title,
                            name    => $name,
                            release => 'Version '.$main::VERSION,
                            section => q(3m) );
   $tempfile = $self->tempfile;
   $parser->parse_from_file( $self->pathname, $tempfile->pathname );
   $cmd = 'cat '.$tempfile->pathname.' | nroff -man';
   system $cmd;
   exit 0;
}

sub warning {
   my ($self, $text, $args) = @_;

   $text = $self->add_leader( $text, $args );

   $self->log_warning( $_ ) for (split m{ \n }mx, $text);

   $self->say( $text ) unless ($self->silent);

   return;
}

sub yorn {
   # General yes or no input routine
   my ($self, $question, $default, $quit, $width, $newline) = @_;
   my ($advice, $left_x, $left_prompt, $right_prompt, $prompt);
   my ($result, $right_x, $total);

   $quit         = $quit    ? $QUIT : q();
   $default      = $default ? $YES  : $NO;
   $advice       = $quit    ? "($YES/$NO, $quit) " : "($YES/$NO) ";
   $right_prompt = $advice.q([).$default.q(]);
   $left_prompt  = $question;

   if (defined $width) {
      $total        = $width || $self->pwidth || 40;
      $right_x      = length $right_prompt;
      $left_x       = $total - $right_x;
      $left_prompt  = sprintf '%-*s', $left_x, $question;
   }

   $prompt  = $left_prompt.$SPC.$right_prompt.$BRK;

   $prompt .= "\n" if (defined $newline && $newline == 1);

   while ($result = $self->prompt( -d => $default, -p => $prompt )) {
      exit   1 unless (defined $result);
      exit   1 if     ($quit and $result =~ m{ \A (?: $quit | [\e] ) }imx);
      return 1 if     ($result =~ m{ \A $YES }imx);
      return 0 if     ($result =~ m{ \A $NO  }imx);
   }

   return;
}

# Private methods

sub _bootstrap {
   my ($proto, $args) = @_; my $e;

   Class::C3::initialize();

   my $self           = bless {}, ref $proto || $proto;
   $self->{arglist }  = q(c=s D H h L=s n o=s S );
   $self->{arglist } .= $args->{arglist} if ($args->{arglist});
   $self->{args    }  = $args->{n      } ? { n => 1 } : {};
   $self->{silent  }  = $args->{silent } ? 1 : 0;

   $self->{script  }  = $self->basename( $args->{script} || $PROGRAM_NAME );
   my $base           = $self->basename( lc $self->{script}, qw(.pl .pm));
   $self->{prefix  }  = $args->{prefix  } || (split m{ _ }mx, $base)[0];
   $self->{appclass}  = $args->{appclass} || $self->{prefix};
   $self->{home    }  = $self->_get_homedir( $self->{appclass}, $args );

   # Now we know where the config file should be we can try parsing it
   my $file = $self->app_prefix( $self->{appclass} );
   my $path = $self->catfile( $self->{home}, $file.q(.xml) );
   my $cfg  = {};

   if (-f $path) {
      $cfg = eval { XML::Simple->new( SuppressEmpty => 1 )->xml_in( $path ) };

      $self->throw( $e ) if ($e = $self->catch);
   }

   my $inflator        = CatalystX::Usul::InflateSymbols->new( $self );
   $self->{appldir   } = $inflator->appldir;
   $self->{binsdir   } = $inflator->binsdir;
   $self->{libsdir   } = $inflator->libsdir;
   $self->{debug     } = $cfg->{debug};
   my $dir             = '__appldir('.$self->catdir( q(var), q(etc) ).')__';
   $self->{ctrldir   } = $self->_inflate( $cfg->{ctrldir    } || $dir );
   $dir                = '__appldir('.$self->catdir( q(var), q(db) ).')__';
   $self->{dbasedir  } = $self->_inflate( $cfg->{dbasedir   } || $dir );
   $self->{doc_title } = $cfg->{doc_title}                    || $NUL;
   $self->{encoding  } = $cfg->{encoding}                     || q(UTF-8);
   $self->{hostname  } = hostname;
   $self->{language  } = $NUL;
   $self->{lock      } = $cfg->{lock};
   $self->{log       } = undef;
   $self->{log_level } = $cfg->{log_level}                    || 6;
   $self->{logname   } = $ENV{USER}                           || $ENV{LOGNAME};
   $dir                = '__appldir(logs)__';
   $self->{logsdir   } = $self->_inflate( $cfg->{logsdir}     || $dir );
   $self->{messages  } = {};
   $self->{method    } = $NUL;
   $self->{mode      } = oct ($cfg->{mode}                    || q(027) );
   $self->{name      }
      = (split m{ _ }mx, $self->basename( $self->{script}, qw(.pl .pm) ))[1]
         || $self->basename( $self->{script}, qw(.pl .pm) );
   $self->{no_thrash } = $cfg->{no_thrash}                    || 3;
   $self->{os        } = {};
   $self->{owner     } = $self->{prefix}                      || q(root);
   $self->{parms     } = {};
   $self->{pwidth    } = 60;
   $dir                = '__appldir('.$self->catdir( q(var), q(root) ).')__';
   $self->{root      } = $self->_inflate( $cfg->{root      }  || $dir );
   $dir                = '__appldir('.$self->catdir( q(var), q(run) ).')__';
   $self->{rundir    } = $self->_inflate( $cfg->{rundir    }  || $dir );
   $path               = '__appldir('.$self->catdir( q(var), q(tmp),
                                                     q(config_cache) ).')__';
   $self->{share_file} = $self->_inflate( $cfg->{share_file}  || $path );
   $self->{secret    } = $cfg->{secret}                     || $self->{prefix};
   $self->{shell     } = $cfg->{shell}                        || q(/bin/pdksh);
   $self->{ssh_id    } = $NUL;
   $path               = '__binsdir('.($self->{prefix}).'_suid)__';
   $self->{suid      } = $self->_inflate( $cfg->{suid      }  || $path );
   $dir                = '__appldir('.$self->catdir( q(var), q(tmp) ).')__';
   $dir                = $self->_inflate( $cfg->{tempdir   }  || $dir );
   $self->{tempdir   } = -d $dir ? $dir : File::Spec->tmpdir;
   ($self->{tempdir} ) = $self->{tempdir} =~ m{ \A ([[:print:]]+) \z }msx;
   $dir                = '__appldir(var)__';
   $self->{vardir    } = $self->_inflate( $cfg->{vardir    }  || $dir );
   $self->{vars      } = {};
   $self->{version   } = $VERSION;

   $self->{logsdir   } = $self->{tempdir} unless (-d $self->{logsdir});

   $self->{ctlfile   } = $self->catfile( $self->{ctrldir},
                                         $self->{name}.q(.xml) );
   $self->{logfile   } = $self->catfile( $self->{logsdir},
                                         $self->{name}.q(.log) );
   ($self->{logfile} ) = $self->{logfile} =~ m{ \A ([[:print:]]+) \z }msx;
   $self->{pathname  } = $self->catfile( $self->{binsdir}, $self->{script} );
   $self->{verdir    } = $self->basename( $self->{appldir} ) || $NUL;

   $self->{log       } = $self->_new_log_object;

   if ($self->{verdir} =~ m{ \A v (\d+) \. (\d+) p (\d+) \z }msx) {
      $self->{major  } = $1;
      $self->{minor  } = $2;
      $self->{phase  } = $3;
   }
   else {
      $self->{major  } = $cfg->{major} || 0;
      $self->{minor  } = $cfg->{minor} || 1;
      $self->{phase  } = $cfg->{phase} || 3;
      $self->{verdir } = undef;
   }

   __PACKAGE__->mk_accessors( keys %{ $self } );

   return $self;
}

sub _get_control_chars {
   my ($self, $handle) = @_; my %cntl = GetControlChars $handle;

   return ((join q(|), values %cntl), %cntl);
}

sub _get_homedir {
   my ($self, $class, $args) = @_;
   my ($app_prefix, $dir_path, $path, $prefix, $well_known);

   $path = $ENV{ $args->{evar} || $self->env_prefix( $class ).q(_HOME) };

   return $path if ($path && -d $path);

   $app_prefix = $self->app_prefix( $class );
   $path       = $self->catfile( File::Spec->rootdir,
                                 q(etc), q(default), $app_prefix );
   $well_known = $args->{install} || $path;
   $path       = undef;

   if (-f $well_known) {
      for (grep { !m{ \A \# }mx } $self->io( $well_known )->chomp->getlines) {
         $path = $_; last;
      }
   }

   return $path if ($path && -d $path);

   $path     = $self->catdir( $PREFIX, $self->class2appdir( $class ) );
   $prefix   = $args->{prefix} || $path;
   $dir_path = $self->catdir( split m{ :: }mx, $class );
   $path     = $self->catdir( $prefix, q(default), q(lib), $dir_path );

   return $path if (-d $path);

   for (@INC) {
      $path = $self->catfile( $_, $dir_path, $app_prefix.q(.xml) );

      return abs_path( $self->dirname( $path ) ) if (-f $path);
   }

   return File::Spec->tmpdir;
}

sub _inflate {
   my ($self, $val) = @_;

   return unless (defined $val);

TRY: {
   if ($val =~ m{ __binsdir\((.*)\)__  }mx) {
      $val = $self->catdir( $self->{binsdir}, $1 ); last TRY;
   }

   if ($val =~ m{ __libsdir\((.*)\)__  }mx) {
      $val = $self->catdir( $self->{libsdir}, $1 ); last TRY;
   }

   if ($val =~ m{ __appldir\((.*)\)__ }mx) {
      $val = $self->catdir( $self->{appldir}, $1 ); last TRY;
   }

   if ($val =~ m{ __path_to\((.*)\)__  }mx) {
      $val = $self->catdir( $self->{home}, $1 );
   }
   } # TRY

   $val = abs_path( $val ) if (-e $val);

   return $val;
}

sub _load_args_ref {
   my $self = shift; my $args = $self->args; my ($opt, $val);

   while (($opt, $val) = nextOption()) {
      if ($args->{ $opt }) {
         if (ref $args->{ $opt } eq q(ARRAY)) {
            push @{ $args->{ $opt } }, $val;
         }
         else { $args->{ $opt } = [ $args->{ $opt }, $val ] }
      }
      else { $args->{ $opt } = $val }
   }

   return;
}

sub _load_messages {
   my ($self, $lang) = @_; my ($cfg, $path, $text);

   return unless ($lang);

   $path   = $self->catfile( $self->ctrldir, q(default_).$lang.q(.xml) );
   ($path) = $path =~ m{ \A ([[:print:]]+) \z }msx; # Untaint

   if ($path && -f $path) {
      $text = $self->io( $path )->lock->all;
      $text = join "\n", grep { !m{ <! .+ > }mx } split  m{ \n }mx, $text;
      $cfg  = eval {
         XML::Simple->new( ForceArray => [ q(messages) ] )->xml_in( $text );
      };
      $self->error   ( $EVAL_ERROR      ) if ($EVAL_ERROR);
      $self->messages( $cfg->{messages} ) if ($cfg && $cfg->{messages});
   }

   return;
}

sub _load_os_depends {
   my $self = shift; my ($cfg, $path, $text);

   $path   = $self->catfile( $self->ctrldir, q(os_).$Config{osname}.q(.xml) );
   ($path) = $path =~ m{ \A ([[:print:]]+) \z }msx; # Untaint

   if ($path && -f $path) {
      $text = $self->io( $path )->lock->all;
      $text = join "\n", grep { !m{ <! .+ > }mx } split  m{ \n }mx, $text;
      $cfg  = eval {
         XML::Simple->new( ForceArray => [ q(os) ] )->xml_in( $text );
      };
      $self->error( $EVAL_ERROR ) if ($EVAL_ERROR);
      $self->os   ( $cfg->{os}  ) if ($cfg && $cfg->{os});
   }

   return;
}

sub _load_vars_ref {
   my $self = shift; my $args = $self->args; my $vars = $self->vars;

   return unless (exists $args->{o});

   for my $opt (ref $args->{o} eq q(ARRAY) ? @{ $args->{o} } : ($args->{o})) {
      my ($var, $val) = split m{ [=] }mx, $opt;

      if ($vars->{ $var }) {
         if (ref $vars->{ $var } eq q(ARRAY)) {
            push @{ $vars->{ $var } }, $val;
         }
         else { $vars->{ $var } = [ $vars->{ $var }, $val ] }
      }
      else { $vars->{ $var } = $val }
   }

   return;
}

sub _new_log_object {
   my $self = shift;

   return Class::Null->new() unless (-d $self->{logsdir});

   return Log::Handler->new( filename => $self->{logfile},
                             maxlevel => $self->{debug}
                                         ? 7 : $self->{log_level},
                             mode     => q(append) );
}

sub _raw_mode {
   my ($self, $handle) = @_; ReadMode q(raw), $handle; return;
}

sub _restore_mode {
   my ($self, $handle) = @_; ReadMode q(restore), $handle; return;
}

sub _set_attr {
   my ($self, $opt, $attr) = @_; my ($untainted, $val);

   if (exists $self->args->{ $opt }) {
      if ($self->arglist =~ m{ $opt =s }mx) {
         if ($val = $self->args->{ $opt }) {
            ($untainted) = $val =~ m{ \A ([[:print:]]+) \z }msx;
            $self->$attr( $untainted );
         }
      }
      else { $self->$attr( 1 ) }
   }

   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Programs - Provide support for command line programs

=head1 Version

0.1.$Revision: 566 $

=head1 Synopsis

   # In YourClass.pm
   use base qw(CatalystX::Usul::Programs);

   # In yourProg.pl
   use base qw(YourClass);

   exit YourClass->new( appclass => 'MyApplication' )->dispatch;

=head1 Description

This base class provides methods common to command line programs. The
constructor can initialise a multi-lingual message catalog if required

=head1 Subroutines/Methods

=head2 new

   $obj = CatalystX::Usul::Programs->new({ ... })

Return a new program object. The optional argument is a hash ref which
may contain these attributes:

=head3 applclass

The name of the application to which the program using this class
belongs. It is used to find the application installation directory
which will contain the configuration XML file

=head3 arglist

Additional L<Getopts::Mixed> command line initialisation arguments are
appended to the default list shown below:

=over 3

=item c method

The method in the subclass to dispatch to

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

=item S

Suppresses the usual started/finished information messages

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

=head3 silent

Boolean which if true suppresses the usual started/finished
information messages. Defaults to false

=head2 add_leader

   $leader = $obj->add_leader( $text, $args );

Prepend C<< $obj->name >> to each line of C<$text>. If
C<< $args->{no_lead} >> exists then do nothing. Return C<$text> with
leader prepended

=head2 anykey

   $key = $obj->anykey( $prompt );

Prompt string defaults to 'Press any key to continue...'. Calls and
returns L<prompt|/prompt>. Requires the user to press any key on the
keyboard (that generates a character response)

=head2 config

   $obj = $obj->config();

Return a reference to self

=head2 dispatch

   $rv = $obj->dispatch;

Call the method specified by the C<-c> option on the command
line. Returns the exit code

=head2 error

   $obj->error( $text, $args );

Calls L<CatalystX::Usul::localize|CatalystX::Usul/localize> with
the passed args. Logs the result at the error level, then adds the
program leader and prints the result to I<STDERR>

=head2 fatal

   $obj->fatal( $text, $args );

Calls L<CatalystX::Usul::localize|CatalystX::Usul/localize> with
the passed args. Logs the result at the alert level, then adds the
program leader and prints the result to I<STDERR>. Exits with a return
code of one

=head2 get_debug_option

   $obj->get_debug_option();

If it is an interactive session prompts the user to turn debugging
on. Returns true if debug is on. Also offers the option to quit

=head2 get_line

   $line = $obj->get_line( $question, $default, $quit, $width, $newline );

Prompts the user to enter a single line response to C<$question> which
is printed to I<STDOUT> with a program leader. If C<$quit> is true
then the options to quit is included in the prompt. If the C<$width>
argument is defined then the string is formatted to the specified
width which is C<$width> or C<< $obj->pwdith >> or 40. If C<$newline>
is true a newline character is appended to the prompt so that the user
get a full line of input

=head2 get_meta

   $res_obj = $obj->get_meta( $dir );

Extracts; I<name>, I<version>, I<author> and I<abstract> from the
F<META.yml> file.  Optionally look in C<$dir> for the file instead of
C<< $obj->appldir >>. Returns a response object with accessors
defined

=head2 info

   $obj->info( $text, $args );

Calls L<CatalystX::Usul::localize|CatalystX::Usul/localize> with
the passed args. Logs the result at the info level, then adds the
program leader and prints the result to I<STDOUT>

=head2 output

   $obj->output( $text, $args );

Calls L<CatalystX::Usul::localize|CatalystX::Usul/localize> with
the passed args. Adds the program leader and prints the result to
I<STDOUT>

=head2 prompt

   $line = $obj->prompt( 'key' => 'value', ... );

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

=head2 stash

Return C<$self>

=head2 usage

   $obj->usage( $verbosity );

Print out usage information from POD. The C<$verbosity> is; 0, 1 or 2

=head2 warning

   $obj->warning( $text, $args );

Calls L<CatalystX::Usul::localize|CatalystX::Usul/localize> with
the passed args. Logs the result at the warning level, then adds the
program leader and prints the result to I<STDOUT>

=head2 yorn

   $obj->yorn( $question, $default, $quit, $width );

Prompt the user to respond to a yes or no question. The C<$question>
is printed to I<STDOUT> with a program leader. The C<$default>
argument is C<0|1>. If C<$quit> is true then the option to quit is
included in the prompt. If the C<$width> argument is defined then the
string is formatted to the specified width which is C<$width> or
C<< $obj->pwdith >> or 40

=head2 _bootstrap

Initialise the contents of the self referential hash

=head2 _get_control_chars

   ($cntrl, %cntrl) = $obj->_get_control_chars( $handle );

Returns a string of pipe separated control characters and a hash of
symbolic names and values

=head2 _get_homedir

   $path = $obj->_get_homedir( 'myApplication' );

Search through subdirectories of @INC looking for the file
myApplication.xml. Uses the location of this file to return the path to
the installation directory

=head2 _inflate

   $tempdir = $obj->inflate( '__appldir(var/tmp)__' );

Inflates symbolic pathnames with their actual runtime values

=head2 _load_messages

=head2 _load_os_depends

=head2 _load_vars_ref

=head2 _new_log_object

=head2 _set_attr

Sets the specified attribute from the command line option

=head2 _raw_mode

   $obj->_raw_mode( $handle );

Puts the terminal in raw input mode

=head2 _restore_mode

   $obj->_restore_mode( $handle );

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

=item L<IPC::SRLock>

=item L<Log::Handler>

=item L<Term::ReadKey>

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
