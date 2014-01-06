# @(#)Ident: ;

package CatalystX::Usul::Constants;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.15.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Class::Usul::Constants ();
use Sub::Exporter;

my @CONSTANTS;

BEGIN {
   @CONSTANTS = qw( ACCESS_OK ACCESS_NO_UGRPS ACCESS_UNKNOWN_USER
                    ACCESS_DENIED ACTION_OPEN ACTION_HIDDEN
                    ACTION_CLOSED DEFAULT_ACTION DEFAULT_CONTENT_TYPE DOTS
                    EVIL_EMPIRE GT HASH_CHAR LSB MAX_SESSION_TIME NBSP
                    NEGOTIATION_IGNORE_XML NEGOTIATION_OFF
                    NEGOTIATION_ON ROOT RSB TTS );
}

sub import {
   my ($class, @wanted) = @_; my $into = caller;

   my $import = Sub::Exporter::build_exporter( {
      exports => [ @CONSTANTS ], groups => { default => [ @CONSTANTS ], },
   } );

   # TODO: Split wanted in two lists and add to import calls
   Class::Usul::Constants->import( { into => $into } );
   __PACKAGE__->$import( { into => $into } );
   return;
}

sub ACCESS_OK              () { 0         }
sub ACCESS_NO_UGRPS        () { 1         }
sub ACCESS_UNKNOWN_USER    () { 2         }
sub ACCESS_DENIED          () { 3         }
sub ACTION_OPEN            () { 0         }
sub ACTION_HIDDEN          () { 1         }
sub ACTION_CLOSED          () { 2         }
sub DEFAULT_ACTION         () { q(redirect_to_default) }
sub DEFAULT_CONTENT_TYPE   () { q(text/html) }
sub DOTS                   () { chr 8230  }
sub EVIL_EMPIRE            () { q(MSIE)   }
sub GT                     () { q(&gt;)   }
sub HASH_CHAR              () { chr 35    }
sub LSB                    () { q([)      }
sub MAX_SESSION_TIME       () { 7_200     }
sub NBSP                   () { q(&#160;) }
sub NEGOTIATION_IGNORE_XML () { 2         }
sub NEGOTIATION_OFF        () { 0         }
sub NEGOTIATION_ON         () { 1         }
sub ROOT                   () { q(root)   }
sub RSB                    () { q(])      }
sub TTS                    () { q( ~ )    }

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Constants - Definitions of constant values

=head1 Version

Describes v0.15.$Rev: 1 $

=head1 Synopsis

   use CatalystX::Usul::Constants;

   my $bool = TRUE; my $slash = SEP;

=head1 Description

Exports a list of subroutines each of which returns a constants value

=head1 Subroutines/Methods

=head2 ACCESS_OK

Access to an action has been granted

=head2 ACCESS_NO_UGRPS

No list of users/groups for selected action

=head2 ACCESS_UNKNOWN_USER

The current user is unknown and anonymous access is not allowed

=head2 ACCESS_DENIED

Access to the selected action for this user is denied

=head2 ACTION_OPEN

Then action is available

=head2 ACTION_HIDDEN

The action is available but does not appear in the navigation menus

=head2 ACTION_CLOSED

The action is not available

=head2 ARRAY

String ARRAY

=head2 ASSERT

Returns a coderef which defaults to a subroutine that does
nothing. Can be set via a call to to the I<Assert> inherited attribute
mutator, i.e.

   CatalystX::Usul::Constants->set_inherited( q(Assert), q(YourSubRef) );

=head2 BRK

Separate leader (: ) from message

=head2 CODE

String CODE

=head2 DEFAULT_ACTION

All controllers should implement this method as a redirect

=head2 DEFAULT_CONTENT_TYPE

Returns I<text/html>

=head2 DEFAULT_L10N_DOMAIN

Name of the GNU Gettext Portable Object file that contains common message
strings

=head2 DIGEST_ALGORITHMS

List of L<Digest> algorithms to search for. Used by
L<create_token|CatalystX::Usul::Functions/create_token>

=head2 DOTS

Multiple dots ....

=head2 EVIL

The devil's spawn. Value returned by C<$OSNAME> on the unmentionable platform

=head2 EVIL_EMPIRE

What L<HTTP::DetectUserAgent> returns if someone is using the wrong client

=head2 FAILED

Non zero exit code indicating program failure

=head2 FALSE

Digit 0

=head2 GT

HTML entity for the greater than character C<< > >>

=head2 HASH

String HASH

=head2 HASH_CHAR

Hash character

=head2 LANG

Default language code

=head2 LBRACE

Left curly brace

=head2 LOCALIZE

The character sequence that introduces a localization substitution
parameter

=head2 LSB

Left square bracket character

=head2 MAX_SESSION_TIME

The default length of time before a session expires through non use (in
seconds). Two hours

=head2 NBSP

Unicode for a non breaking space

=head2 NEGOTIATION_IGNORE_XML

Content negotiation state

=head2 NEGOTIATION_OFF

Content negotiation state

=head2 NEGOTIATION_ON

Content negotiation state

=head2 NUL

Empty string

=head2 OK

Returns good program exit code, zero

=head2 PHASE

The default phase number used to select installation specific config

=head2 ROOT

Root namespace symbol

=head2 RSB

Right square bracket character

=head2 SEP

Slash (/) character

=head2 SPC

Space character

=head2 TRUE

Digit 1

=head2 TTS

Help tips title separator string

=head2 UNTAINT_IDENTIFIER

Regular expression used to untaint identifier strings

=head2 UNTAINT_PATH_REGEX

Regular expression used to untaint path strings

=head2 UUID_PATH

An array ref. which is passed to C<catfile> and is a path to the F<proc>
filesystems random generator

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Class::Usul::Constants>

=item L<Sub::Exporter>

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

Copyright (c) 2014 Peter Flanigan. All rights reserved

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
