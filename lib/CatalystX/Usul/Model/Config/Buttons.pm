# @(#)Ident: ;

package CatalystX::Usul::Model::Config::Buttons;

use strict;
use version; our $VERSION = qv( sprintf '0.15.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;

extends q(CatalystX::Usul::Model::Config);

has '+classes'        => default => sub { { help => q(ifield autosize) } };

has '+create_msg_key' => default => 'Button [_1]/[_2] created';

has '+delete_msg_key' => default => 'Button [_1]/[_2] deleted';

has '+keys_attr'      => default => q(buttons);

has '+typelist'       => default => sub { { help => q(textarea) } };

has '+update_msg_key' => default => 'Button [_1]/[_2] updated';

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Buttons - Class definition for buttons

=head1 Version

Describes v0.15.$Rev: 1 $

=head1 Synopsis

   # The constructor is called by Catalyst at startup

=head1 Description

Defines the attributes of the <button> element in the configuration files

There are three language dependent attributes to the I<buttons>
element; I<error>, I<help> and I<prompt>

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
