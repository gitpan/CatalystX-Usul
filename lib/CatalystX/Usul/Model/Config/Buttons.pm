# @(#)$Id: Buttons.pm 1139 2012-03-28 23:49:18Z pjf $

package CatalystX::Usul::Model::Config::Buttons;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1139 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model::Config);

__PACKAGE__->config
   ( classes        => { help => q(ifield autosize) },
     create_msg_key => 'Button [_1]/[_2] created',
     delete_msg_key => 'Button [_1]/[_2] deleted',
     keys_attr      => q(buttons),
     typelist       => { help => q(textarea) },
     update_msg_key => 'Button [_1]/[_2] updated', );

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Buttons - Class definition for buttons

=head1 Version

0.5.$Revision: 1139 $

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
