# @(#)Ident: ;

package CatalystX::Usul::Model::Config::Messages;

use strict;
use version; our $VERSION = qv( sprintf '0.13.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;

extends q(CatalystX::Usul::Model::Config);

has '+classes'        => default => sub { {
   translator_comment => q(ifield autosize), } };

has '+create_msg_key' => default => 'Message [_1]/[_2] created';

has '+delete_msg_key' => default => 'Message [_1]/[_2] deleted';

has '+domain_attributes' => default => sub { {
   storage_class      => q(+File::Gettext::Storage::PO) } };

has '+domain_class'   => default => q(File::Gettext);

has '+fields'         => default => sub {
   [ qw(msgctxt msgstr msgid_plural translator_comment
        extracted_comment reference flags previous) ] };

has '+keys_attr'      => default => q(msgid);

has '+table_data'     => default => sub { {
   msgstr             => {
      classes         => { text => q(ifield autosize) },
      fields          => [ qw(text) ],
      labels          => { text => 'Text' },
      typelist        => { text => q(textarea) }, }, } };

has '+typelist'       => default => sub { {
   extracted_comment  => q(label),
   flags              => q(label),
   msgstr             => q(table),
   previous           => q(label),
   reference          => q(label),
   translator_comment => q(textarea), } };

has '+update_msg_key' => default => 'Message [_1]/[_2] updated';

after 'create_or_update' => sub {
   $_[ 0 ]->usul->l10n->invalidate_cache;
};

after 'delete' => sub {
   $_[ 0 ]->usul->l10n->invalidate_cache;
};

# Private methods

sub _resultset {
   my ($self, $ns) = @_; my $s = $self->context->stash;

   my $dm = $self->domain_model; $dm->set_path( $s->{language}, $ns );

   return $dm->resultset;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Messages - Class definition for the messages configuration element

=head1 Version

Describes v0.13.$Rev: 1 $

=head1 Synopsis

   package YourApp;

   use Catalyst qw(ConfigComponents...);

   __PACKAGE__->config(
     'Model::Config::Messages' => {
        parent_classes => q(CatalystX::Usul::Model::Config::Messages) }, );

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

Copyright (c) 2013 Peter Flanigan. All rights reserved

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
