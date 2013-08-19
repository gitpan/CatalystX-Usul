# @(#)Ident: ;

package CatalystX::Usul::Model::Config::Keys;

use strict;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;

extends q(CatalystX::Usul::Model::Config);

has '+create_msg_key' => default => 'Keys [_1]/[_2] created';

has '+delete_msg_key' => default => 'Keys [_1]/[_2] deleted';

has '+fields'         => default => sub { [ qw(vals) ] };

has '+keys_attr'      => default => q(keys);

has '+table_data'     => default => sub { {
   vals               => {
      classes         => { order => 'ifield numeric' },
      fields          => [ qw(name key order) ],
      labels          => { name => 'Key',  key => 'Default', order => 'Order' },
      typelist        => { order => 'numeric' },
      sizes           => { name => 16,     key => 16,        order => 2 }, },}};

has '+typelist'       => default => sub { { vals => q(table) } };

has '+update_msg_key' => default => 'Keys [_1]/[_2] updated';

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Keys - Class definition for keys configuration element

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   # Instantiated by Catalyst when the application starts

=head1 Description

Defines the attributes for the <keys> element in the configuration
files

Defines one language independent attribute; C<vals>

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
