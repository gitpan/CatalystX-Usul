# @(#)$Id: Messages.pm 1139 2012-03-28 23:49:18Z pjf $

package CatalystX::Usul::Model::Config::Messages;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1139 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model::Config);

use File::Gettext;

__PACKAGE__->config
   ( classes        => { translator_comment => q(ifield autosize), },
     create_msg_key => 'Message [_1]/[_2] created',
     delete_msg_key => 'Message [_1]/[_2] deleted',
     domain_class   => q(File::Gettext),
     fields         => [ qw(msgctxt msgstr msgid_plural translator_comment
                            extracted_comment reference flags previous) ],
     keys_attr      => q(msgid),
     table_data     => {
        msgstr      => {
           classes  => { text => q(ifield autosize) },
           flds     => [ qw(text) ],
           labels   => { text => 'Text' },
           typelist => { text => q(textarea) }, }, },
     typelist       => { extracted_comment  => q(label),
                         flags              => q(label),
                         msgstr             => q(table),
                         previous           => q(label),
                         reference          => q(label),
                         translator_comment => q(textarea), },
     update_msg_key => 'Message [_1]/[_2] updated', );

# Private methods

sub _resultset {
   my ($self, $ns) = @_; my $s = $self->context->stash;

   my $dm = $self->domain_model; $dm->set_path( $s->{lang}, $ns );

   return $dm->resultset;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Messages - Class definition for the messages configuration element

=head1 Version

0.5.$Revision: 1139 $

=head1 Synopsis

   # Instatiated by Catalyst when the application starts

=head1 Description

Defines the attributes of the I<messages> configuration element

Defines language dependent attribute: I<text>

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
