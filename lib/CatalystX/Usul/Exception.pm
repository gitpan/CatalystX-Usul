package CatalystX::Usul::Exception;

# @(#)$Id: Exception.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use Exception::Class
   ( 'CatalystX::Usul::Exception::Class'
        => { fields => [qw(arg1 arg2 out rv)] } );
use base       qw(CatalystX::Usul::Exception::Class);
use English    qw(-no_match_vars);
use List::Util qw(first);
use Carp;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

my $NUL = q();

our $IGNORE = [ __PACKAGE__ ];

sub catch {
   my ($self, @rest) = @_; my $e;

   return $e if ($e = $self->caught( @rest ));

   return $self->new( arg1           => $NUL,
                      arg2           => $NUL,
                      ignore_package => $IGNORE,
                      out            => $NUL,
                      rv             => 1,
                      show_trace     => 0,
                      error          => $EVAL_ERROR ) if ($EVAL_ERROR);

   return;
}

sub as_string {
   my ($self, $verbosity, $offset) = @_; my ($frame, $l_no, %seen);

   $verbosity ||= 1; $offset ||= 1;

   my $text = $NUL.$self->message; # I hate Return::Value

   return $text if ($verbosity < 2 and not $self->show_trace);

   my $i = $verbosity > 2 ? 0 : $offset; $frame = undef;

   while (defined ($frame = $self->trace->frame( $i++ ))) {
      my $line = "\n".$frame->package.' line '.$frame->line;

      if ($verbosity > 2) { $text .= $line; next }

      last if (($l_no = $seen{ $frame->package }) && $l_no == $frame->line);

      $seen{ $frame->package } = $frame->line;
   }

   return $text;
}

sub throw {
   my ($self, @rest) = @_;

   croak $rest[ 0 ] if ($rest[ 0 ] and ref $rest[ 0 ]);

   my @args = @rest == 1 ? ( error => $rest[0] ) : @rest;

   croak $self->new( arg1           => $NUL,
                     arg2           => $NUL,
                     ignore_package => $IGNORE,
                     out            => $NUL,
                     rv             => 1,
                     show_trace     => 0,
                     @args );
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Exception - Exception base class

=head1 Version

0.1.$Revision: 402 $

=head1 Synopsis

   use base qw(CatalystX::Usul);

   sub some_method {
      my $self = shift; my $e;

      eval { this_will_fail }

      $self->throw( $e ) if ($e = $self->catch);
   }

=head1 Description

Implements try (by way of an eval), throw, and catch error
semantics. Inherits from L<Exception::Class>

=head1 Subroutines/Methods

=head2 catch

Catches and returns a thrown exception or generates a new exception if
I<EVAL_ERROR> has been set

=head2 as_string

   warn $e->as_string( $verbosity, $offset );

Serialise the exception to a string. The passed parameters; I<verbosity>
and I<offset> determine how much output is returned.

The I<verbosity> parameter can be:

=over 3

=item 1

The default value. Only show a stack trace if C<< $self->show_trace >> is true

=item 2

Always show the stack trace and start at frame I<offset> which
defaults to 1. The stack trace stops when the first duplicate output
line is detected

=item 3

Always shows the complete stack trace starting at frame 0

=back

=head2 throw

Create (or re-throw) an exception to be caught by the catch above. If
the passed parameter is a reference it is re-thrown. If a single scalar
is passed it is taken to be an error message code, a new exception is
created with all other parameters taking their default values. If more
than one parameter is passed the it is treated as a list and used to
instantiate the new exception. The 'error' parameter must be provided
in this case

=head1 Diagnostics

None

=head1 Configuration and Environment

The C<$IGNORE> package variable is list of methods whose presence
should be suppressed in the stack trace output

=head1 Dependencies

=over 3

=item L<Exception::Class>

=item L<List::Util>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

The default ignore package list should be configurable

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Author

Peter Flanigan C<< <Support at RoxSoft.co.uk> >>

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