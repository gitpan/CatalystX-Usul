package CatalystX::Usul::Model::Config::Keys;

# @(#)$Id: Keys.pm 401 2009-03-27 00:17:37Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Model::Config);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 401 $ =~ /\d+/gmx );

__PACKAGE__->config
   ( create_msg_key    => q(keysCreated),
     delete_msg_key    => q(keysDeleted),
     keys_attr         => q(key),
     schema_attributes => {
        attributes     => [ qw(vals) ],
        defaults       => { vals => {} },
        element        => q(keys),
        lang_dep       => q(), },
     table_data        => { vals => { align  => { name => q(left),
                                                  key  => q(left) },
                                      flds   => [ qw(name key) ],
                                      labels => { name => q(Key),
                                                  key  => q(Default) },
                                      sizes  => { name => 16,
                                                  key  => 32 } } },
     typelist          => {},
     update_msg_key    => q(keysUpdated), );

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Keys - Class definition for keys configuration element

=head1 Version

0.1.$Revision: 401 $

=head1 Synopsis

   # Instantiated by Catalyst when the application starts

=head1 Description

Defines the attributes for the <keys> element in the configuration
files

Defines one language independent attribute; I<vals>

=head1 Subroutines/Methods

None

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model::Config>

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
