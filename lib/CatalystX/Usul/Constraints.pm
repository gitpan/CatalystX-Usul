# @(#)$Ident: Constraints.pm 2013-06-23 17:24 pjf ;

package CatalystX::Usul::Constraints;

use strict;
use warnings;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.16.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Encode                      qw( find_encoding );
use File::DataClass::IO;
use Class::Load                 qw( load_first_existing_class );
use Class::Usul::Constants;
use MooseX::Types -declare => [ qw( BaseClass CharEncoding ClassName Directory
                                    File FileClass IPCClass Lock
                                    NullLoadingClass Path ) ];
use MooseX::Types::Moose        qw( ArrayRef CodeRef HashRef Object Str Undef ),
                 ClassName => { -as => 'MooseClassName' };
use Scalar::Util                qw( blessed );

class_type BaseClass, { class => 'Class::Usul'       };
class_type FileClass, { class => 'Class::Usul::File' };
class_type IPCClass,  { class => 'Class::Usul::IPC'  };

subtype CharEncoding, as Str,
   where   { find_encoding( $_ ) },
   message { "String ${_} is not a valid encoding" };

subtype Lock, as Object,
   where   { $_->isa( 'Class::Null' )
                or ($_->can( 'set' ) and $_->can( 'reset') ) },
   message {
      'Object '.(blessed $_ || $_ || 'undef').' is missing set or reset methods'
   };

subtype NullLoadingClass, as MooseClassName;

subtype Path, as Object,
   where   { $_->isa( 'File::DataClass::IO' ) },
   message {
      'Object '.(blessed $_ || $_).' is not of class File::DataClass::IO'
   };

subtype Directory, as Path,
   where   { $_->exists and $_->is_dir  },
   message { 'Path '.($_ ? $_.' is not a directory' : 'not specified') };

subtype File, as Path,
   where   { $_->exists and $_->is_file },
   message { 'Path '.($_ ? $_.' is not a file' : 'not specified') };

coerce  CharEncoding, from Undef, via { DEFAULT_ENCODING };

coerce  Directory,
   from ArrayRef, via { io( $_ ) },
   from CodeRef,  via { io( $_ ) },
   from HashRef,  via { io( $_ ) },
   from Str,      via { io( $_ ) },
   from Undef,    via { io( $_ ) };

coerce  File,
   from ArrayRef, via { io( $_ ) },
   from CodeRef,  via { io( $_ ) },
   from HashRef,  via { io( $_ ) },
   from Str,      via { io( $_ ) },
   from Undef,    via { io( $_ ) };

coerce  NullLoadingClass,
   from Str,      via { __load_if_exists( $_  ) },
   from Undef,    via { __load_if_exists( NUL ) };

coerce  Path,
   from ArrayRef, via { io( $_ ) },
   from CodeRef,  via { io( $_ ) },
   from HashRef,  via { io( $_ ) },
   from Str,      via { io( $_ ) },
   from Undef,    via { io( $_ ) };

sub __load_if_exists {
   my $name = shift; load_first_existing_class( $name, q(Class::Null) );
};

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Constraints - Defines Moose type constraints

=head1 Version

This document describes CatalystX::Usul::Constraints version v0.16.$Rev: 1 $

=head1 Synopsis

   use CatalystX::Usul::Constraints q(:all);

=head1 Description

Defines the following type constraints

=over 3

=item C<CharEncoding>

Subtype of C<Str> which has to be one of the list of encodings in the
C<ENCODINGS> constant

=item C<ConfigType>

Subtype of C<Object> can be coerced from a hash ref

=item C<LogType>

Subtype of C<Object> which has to implement all of the methods in the
C<LOG_LEVELS> constant

=back

=head1 Subroutines/Methods

None

=head1 Configuration and Environment

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul::Constants>

=item L<Class::Usul::Functions>

=item L<MooseX::Types>

=item L<MooseX::Types::Moose>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Author

Peter Flanigan, C<< <Support at RoxSoft.co.uk> >>

=head1 Acknowledgements

Larry Wall - For the Perl programming language

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

