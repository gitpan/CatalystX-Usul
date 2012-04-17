# @(#)$Id: Log.pm 1181 2012-04-17 19:06:07Z pjf $

package CatalystX::Usul::Log;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.7.%d', q$Rev: 1181 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use Encode;

# requires qw(encoding log);

our $LEVELS = [ qw(alert debug error fatal info warn) ];

sub mk_log_methods {
   my $self = shift; my $class = ref $self || $self;

   no strict q(refs); ## no critic

   for my $level (@{ $LEVELS }) {
      my $method = q(log_).$level; my $accessor = $class.q(::).$method;

      defined &{ "${accessor}" } and next;

      *{ "${accessor}" } = sub {
         my ($self, $text) = @_; $text or return; chomp $text;
         $self->encoding and $text = encode( $self->encoding, $text );
         $self->log->$level( $text."\n" );
         return;
      };

      *{ "${accessor}_message" } = sub {
         my ($self, @rest) = @_;
         $self->$method( __mk_log_message( @rest ) );
         return;
      };

   }

   return;
}

# Private functions

sub __mk_log_message {
   my ($message, $args) = @_; $args ||= {};

   $message ||= NUL; $message = NUL.$message; chomp $message;

   my $text  = (ucfirst $args->{leader} || NUL).LSB.($args->{user} || NUL);
      $text .= RSB.SPC.(ucfirst $message || 'no message');

   return $text;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Log - Create logging methods for different encodings

=head1 Version

$Revision: 1181 $

=head1 Synopsis

   use parent qw(CatalystX::Usul::Log);

   __PACKAGE__->mk_log_methods();

   # Can now call the following
   $self->log_debug( $text );
   $self->log_info(  $text );
   $self->log_warn(  $text );
   $self->log_error( $text );
   $self->log_fatal( $text );

=head1 Description

Defines a class methods which will create logging methods that encode thier
output using the required encoding

=head1 Subroutines/Methods

=head2 mk_log_methods

Creates a set of methods defined by the C<$LEVELS> package
variable. The method expects C<< $self->log >> and C<< $self->encoding >>
to be set.  It encodes the output string prior calling the log
method at the given level

=head2 mk_log_message

   $self->mk_log_message( $args, $message );

Returns a message formatted for logging

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Encode>

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
