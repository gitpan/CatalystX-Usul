# @(#)$Id: Messages.pm 591 2009-06-13 13:34:41Z pjf $

package CatalystX::Usul::Model::Config::Messages;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 591 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model::Config);

__PACKAGE__->config( create_msg_key    => q(Message [_1]/[_2] created),
                     delete_msg_key    => q(Message [_1]/[_2] deleted),
                     keys_attr         => q(message),
                     schema_attributes => {
                        attributes        => [ qw(markdown text) ],
                        defaults          => { markdown => 0, text => q() },
                        element           => q(messages),
                        lang_dep          => { markdown => 1, text => 1 }, },
                     typelist          => { text => q(textarea) },
                     update_msg_key    => q(Message [_1]/[_2] updated), );

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Messages - Class definition for the messages configuration element

=head1 Version

0.3.$Revision: 591 $

=head1 Synopsis

   # Instatiated by Catalyst when the application starts

=head1 Description

Defines the attributes of the I<messages> configuration element

Defines two language dependent attributes: I<markdown> and I<text>

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
