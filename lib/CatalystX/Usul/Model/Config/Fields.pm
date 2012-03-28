# @(#)$Id: Fields.pm 1076 2011-10-30 02:03:52Z pjf $

package CatalystX::Usul::Model::Config::Fields;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1076 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model::Config);

__PACKAGE__->config
   ( classes        => { fhelp => q(ifield autosize),
                         tip   => q(ifield autosize), },
     create_msg_key => 'Field [_1]/[_2] created',
     delete_msg_key => 'Field [_1]/[_2] deleted',
     keys_attr      => q(fields),
     typelist       => { fhelp => q(textarea), tip => q(textarea) },
     update_msg_key => 'Field [_1]/[_2] updated', );

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Fields - Class definition for fields

=head1 Version

0.4.$Revision: 1076 $

=head1 Synopsis

   # The constructor is called by Catalyst at startup

=head1 Description

Defines the attributes of the <field> elements in the configuration files

There are twenty one language independent attributes to the I<fields>
element; I<type>, I<clear>, I<width>, I<maxlength>, I<required>,
I<validate>, I<onchange>, I<height>, I<pclass>, I<align>,
I<checked>, I<class>, I<max_integer>, I<min_integer>,
I<min_password_length>, I<onkeypress>, I<pwidth>, I<sep>
and I<subtype>

There are six language dependent attributes to the I<fields>
element; I<atitle>, I<ctitle>, I<fhelp>, I<prompt>, I<text> and I<tip>

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
