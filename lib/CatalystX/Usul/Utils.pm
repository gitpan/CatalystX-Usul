package CatalystX::Usul::Utils;

# @(#)$Id: Usul.pm 32 2008-03-20 13:56:43Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Base);
use CatalystX::Usul::Response;
use English qw(-no_match_vars);
use Email::Send;
use Email::MIME;
use Email::MIME::Creator;
use IO::Handle;
use IO::Select;
use IPC::Open3;
use MIME::Types;
use POSIX qw(:signal_h :errno_h :sys_wait_h);
use Proc::ProcessTable;
use Template;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 32 $ =~ /\d+/gmx );

my ($ERROR, $WAITEDPID);

sub child_list {
   my ($self, $pid, $ref) = @_; my ($child, $p, $t); my @pids = ();

   unless (defined $ref) {
      $t = Proc::ProcessTable->new(); $ref = {};

      for $p (@{ $t->table }) { $ref->{ $p->pid } = $p->ppid }
   }

   if (exists $ref->{ $pid }) {
      for $child (grep { $ref->{ $_ } == $pid } keys %{ $ref }) {
         push @pids, $self->child_list( $child, $ref ); # Recurse
      }

      push @pids, $pid;
   }

   return @pids;
}

sub cleaner {
   $ERROR = 1; $WAITEDPID = wait; $SIG{PIPE} = \&cleaner; return;
}

sub handler {
   # Is the candidate value in the list
   my $pid    = waitpid -1, WNOHANG();

   $WAITEDPID = $pid if ($pid != -1 && WIFEXITED( $CHILD_ERROR ));

   $SIG{CHLD} = \&handler; # in case of unreliable signals
   return;
}

sub popen {
   my ($self, $cmd, @input) = @_; my ($e, $pid, @ready);

   my $err = IO::Handle->new();
   my $rdr = IO::Handle->new();
   my $wtr = IO::Handle->new();
   my $res = CatalystX::Usul::Response->new();

   eval {
      $ERROR = 0; $SIG{CHLD} = \&handler; $SIG{PIPE} = \&cleaner;
      $pid   = open3( $wtr, $rdr, $err, $cmd );

      if (defined $input[0]) {
         for my $line (@input) {
            print {$wtr} $line or $self->throw( q(eWritePipe) );
         }
      }

      $wtr->close;
   };

   if ($e = $self->catch) { $err->close; $rdr->close; $self->throw( $e ) }

   if ($ERROR) {
      $e = do { local $RS = undef; <$err> }; $err->close; $rdr->close;
      $self->throw( $e );
   }

   my $selector = IO::Select->new(); $selector->add( $err, $rdr );

   while (@ready = $selector->can_read) {
      for my $fh (@ready) {
         if (fileno $fh == fileno $err) {
            $e = do { local $RS = undef; <$err> };
         }
         else { $res->out( do { local $RS = undef; <$rdr> } ) }

         $selector->remove( $fh ) if (eof $fh);
      }
   }

   waitpid $pid, 0;

   $self->throw( $e ) if ($e);

   return $res;
}

sub process_exists {
   my ($self, @rest) = @_;
   my $args     = $self->arg_list( @rest );
   my $pid_file = $args->{file};
   my $pid      = $args->{pid};

   if ($pid_file && -f $pid_file) {
      $pid = $self->io( $pid_file )->chomp->lock->getline;
   }

   return 0 if (not $pid or $pid !~ m{ \d+ }mx);
   return 1 if (CORE::kill 0, $pid);
   return 0;
}

sub run_cmd {
   my ($self, $cmd, $args) = @_;
   my ($e, $err, $out, $pid, $prog, $res, $rv, $text);

   $self->throw( q(eNoCommand) ) unless ($cmd);
   $prog = $self->basename( (split q( ), $cmd)[0] );

   $args                ||= {};
   $args->{debug      } ||= $self->debug;
   $args->{expected_rv} ||= 0;
   $args->{tempdir    } ||= $self->tempdir;
   # Three different semi-random file names in the temp directory
   $args->{err_ref    } ||= $self->tempfile( $args->{tempdir} );
   $args->{out_ref    } ||= $self->tempfile( $args->{tempdir} );
   $args->{pid_ref    } ||= $self->tempfile( $args->{tempdir} );

   if ($args->{async} && !$args->{out}) {
      $args->{out} = $args->{out_ref}->pathname; $args->{err} = q(out);
   }

   $out = $args->{out} ? $args->{out} : $args->{out_ref}->pathname;

   if ($args->{err}) { $err = $args->{err} eq q(out) ? $out : $args->{err} }
   else { $err = $args->{err_ref}->pathname }

   $cmd .= ' 1>'.$out if ($out ne q(stdout));
   $cmd .= $err eq $out ? ' 2>&1' : ($err ne q(stderr) ? ' 2>'.$err : q());
   $cmd .= ' & echo $! 1>'.$args->{pid_ref}->pathname if ($args->{async});

   $self->log_debug( "Run cmd $cmd" ) if ($args->{debug});

   $rv = eval { local $SIG{CHLD} = \&handler; system $cmd; };

   if ($e = $self->catch) { $e->rv( -1 ); $self->throw( $e ) }

   if ($rv == -1) {
      $self->throw( error => q(eFailedToStart),
                    arg1  => $prog, arg2 => $ERRNO, rv => -1 );
   }

   $res = CatalystX::Usul::Response->new();
   $res->sig( $rv & 127 ); $res->core( $rv & 128 ); $rv = $rv >> 8;

   if ($args->{async}) {
      if ($rv != 0) {
         $self->throw( error => q(eFailedToStart), arg1 => $prog, rv => $rv );
      }

      $pid = $self->io( $args->{pid_ref}->pathname )->chomp->getline
          || q(pid unknown);
      $res->out( 'Started '.$prog.'('.$pid.') in the background' );
      return $res;
   }

   if ($out ne q(stdout) and -f $out and $text = $self->io( $out )->slurp) {
      $res->stdout( $text );
      $res->out( join "\n", map    { $self->strip_leader( $_ ) }
                            grep   { !m{ (?: Started | Finished ) }msx }
                            split m{ [\n] }msx, $text );
   }

   if ($err ne q(stderr)) {
      if ($err ne $out) {
         if (-f $err and $text = $self->io( $err )->slurp) {
            $res->stderr( $text ); chomp $text;
         }
         else { $text = q() }

         $text .= ' code '.$rv if ($args->{debug});
      }
      else { $res->stderr( $res->stdout ); $text = $res->out; chomp $text }
   }

   $self->throw( error => $text, rv => $rv ) if ($rv > $args->{expected_rv});

   return $res;
}

sub send_email {
   my ($self, $args) = @_; my $email;

   $self->throw( q(eNoArgs) ) unless ($args);

   $email->{attributes} =  $args->{attributes} || {};
   $email->{header    } =
      [ From            => $args->{from      } || q(unknown),
        To              => $args->{to        } || q(postmaster),
        Subject         => $args->{subject   } || q(No subject) ];

   unless ($email->{body} = $args->{body}) {
      $self->throw( q(eNoBodyFound) ) unless ($args->{template});

      my ($text, $tmplt);

      if ($tmplt = Template->new( $self )) {
         if ($tmplt->process( $args->{template}, $args->{stash}, \$text )) {
            $email->{body} = $text;
         }
         else { $self->throw( $tmplt->error() ) }
      }
      else { $self->throw( $Template::ERROR ) }
   }

   if (exists $args->{attachments}) {
      my $types = MIME::Types->new( only_complete => 1 );
      my $part  = Email::MIME->create( attributes => $email->{attributes},
                                       body       => delete $email->{body} );
      $email->{parts} = [ $part ];

      while (my ($attachment, $path) = each %{ $args->{attachments} }) {
         my $body  = $self->io( $path )->lock->all;
         my $file  = $self->basename( $path );
         my $mime  = $types->mimeTypeOf( $file );
         my $attrs = { content_type => $mime->type,
                       encoding     => $mime->encoding,
                       filename     => $file,
                       name         => $attachment };
         $part     = Email::MIME->create( attributes => $attrs,
                                          body       => $body );
         push @{ $email->{parts} }, $part;
      }
   }

   my $sender = Email::Send->new( {
      mailer      => $args->{mailer} || q(SMTP),
      mailer_args => [ Host => $args->{mailer_host} || q(localhost) ],
   } );

   return $sender->send( Email::MIME->create( %{ $email } ) );
}

sub signal_process {
   my ($self, @rest) = @_; my $args = $self->arg_list( @rest );
   my ($io, $mpid, $pid, $pids, $pid_file, @pids, $sig);

   $sig      = $args->{sig } || q(TERM);
   $pids     = $args->{pids} || [];
   $pid_file = $args->{file};

   push @{ $pids }, $args->{pid} if ($args->{pid});

   if ($pid_file and -f $pid_file) {
      push @{ $pids }, $self->io( $pid_file )->chomp->lock->getlines;

      unlink $pid_file if ($sig eq q(TERM));
   }

   unless (defined $pids->[0] && $pids->[0] =~ m{ \d+ }mx) {
      $self->throw( q(eBadPid) );
   }

   for $mpid (@{ $pids }) {
      if (exists $args->{flag} && $args->{flag} =~ m{ one }imx) {
         CORE::kill $sig, $mpid;
         next;
      }

      @pids = reverse $self->child_list( $mpid );

      for $pid (@pids) { CORE::kill $sig, $pid }

      next unless ($args->{force});

      sleep 3; @pids = reverse $self->child_list( $mpid );

      for $pid (@pids) { CORE::kill q(KILL), $pid }
   }

   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Utils - Base class utility methods for models and programs

=head1 Version

0.1.$Revision: 32 $

=head1 Synopsis

   package CatalystX::Usul::Model;

   use parent qw(CatalystX::Usul CatalystX::Usul::Utils);

   package YourApp::Model::YourModel;

   use parent qw(CatalystX::Usul::Model);

=head1 Description

Provides utility methods to the model and program base classes

=head1 Subroutines/Methods

=head2 child_list

   @pids = $self->child_list( $pid );

Called with a process id for an argument this method returns a list of child
process ids

=head2 cleaner

This interrupt handler traps the pipe signal

=head2 handler

This interrupt handler traps the child signal

=head2 popen

   $response = $self->popen( $cmd, @input );

Uses L<IPC::Open3> to fork a command and pipe the lines of input into
it. Returns a C<CatalystX::Usul::Response> object. The response
object's C<out> method returns the B<STDOUT> from the command. Throws
in the event of an error

=head2 process_exists

   $bool = $self->process_exists( file => $path, pid => $pid );

Tests for the existence of the specified process. Either specify a
path to a file containing the process id or specify the id directly

=head2 run_cmd

   $response = $self->run_cmd( $cmd, $args );

Runs the given command by calling C<system>. The keys of the C<$args> hash are:

=over 3

=item async

If I<async> is true then the command is run in the background

=item debug

Debug status. Defaults to C<< $self->debug >>

=item err

Passing I<< err => q(out) >> mixes the normal and error output
together

=item log

Logging object. Defaults to C<< $self->log >>

=item tempdir

Directory used to store the lock file and lock table if the C<fcntl> backend
is used. Defaults to C<< $self->tempdir >>

=back

Returns a L<CatalystX::Usul::Response> object or throws an
error. The response object has the following methods:

=over 3

=item B<core>

Returns true if the command generated a core dump

=item B<err>

Contains a cleaned up version of the command's B<STDERR>

=item B<out>

Contains a cleaned up version of the command's B<STDOUT>

=item B<rv>

The return value of the command

=item B<sig>

If the command died as the result of receiving a signal return the
signal number

=item B<stderr>

Contains the command's B<STDERR>

=item B<stdout>

Contains the command's B<STDOUT>

=back

=head2 send_email

   $result = $self->send_email( $args );

Sends emails. The C<$args> hash ref uses these keys:

=over 3

=item attachments

A hash ref whose key/value pairs are the attachment name and path
name. Encoding and content type are derived from the file name
extension

=item attributes

A hash ref that is applied to email when it is created. Typical keys are;
I<content_type> and I<charset>

=item body

Text for the body of the email message

=item from

Email address of the sender

=item mailer

Which mailer should be used to send the email. Defaults to I<SMTP>

=item mailer_host

Which host should send the email. Defaults to I<localhost>

=item stash

Hash ref used by the template rendering to supply values for variable
replacement

=item subject

Subject string

=item template

If it exists then the template is rendered and used as the body contents

=item to

Email address of the recipient

=back

=head2 signal_process

   $self->signal_process( [{] param => value, ... [}] );

This is called by processes running as root to send signals to
selected processes. The passed parameters can be either a list of key
value pairs or a hash ref. Either a single B<pid>, or an array ref
B<pids>, or B<file> must be passwd. The B<file> parameter should be a
path to a file containing pids one per line. The B<sig> defaults to
I<TERM>. If the B<flag> parameter is set to I<one> then the given signal
will be sent once to each selected process. Otherwise each process and
all of it's children will be sent the signal. If the B<force>
parameter is set to true the after a grace period each process and
it's children are sent signal I<KILL>

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Base>

=item L<CatalystX::Usul::Response>

=item L<Email::Send>

=item L<Email::MIME>

=item L<Email::MIME::Creator>

=item L<IPC::Open3>

=item L<IPC::SysV>

=item L<MIME::Types>

=item L<POSIX>

=item L<Proc::ProcessTable>

=item L<Template>

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
