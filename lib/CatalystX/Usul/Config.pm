# @(#)$Id: Config.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Config;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );

use Moose;
use File::DataClass::Constants;

extends qw(File::DataClass::Schema::WithLanguage);

has '+result_source_attributes' =>
   default          => sub { {
      action        => {
         attributes => [ qw(acl keywords pwidth quick_link state text tip) ],
         defaults   => { acl => [ q(any) ], state => 0, text => NUL },
         lang_dep   => { qw(keywords 1 text 1 tip 1) },
      },
      buttons       => {
         attributes => [ qw(help prompt error type) ],
         defaults   => { help => NUL, type => q(image) },
         lang_dep   => { qw(error 1 help 1 prompt 1) },
      },
      credentials   => {
         attributes => [ qw(driver host password port user) ],
         defaults   => {},
      },
      fields        => {
         attributes => [ qw(type prompt clear width maxlength tip
                            required validate container container_class
                            stepno onchange height pclass
                            atitle align checked class
                            ctitle edit fhelp max_integer min_integer
                            min_password_length onkeypress
                            pwidth select sep subtype table_class text) ],
         defaults   => { prompt => NUL, stepno => -1 },
         lang_dep   => { qw(atitle 1 ctitle 1 fhelp 1
                            prompt 1 text   1 tip   1) },
      },
      globals       => {
         attributes => [ qw(value) ],
         defaults   => {},
      },
      keys          => {
         attributes => [ qw(vals) ],
         defaults   => { vals => {} },
      },
      namespace     => {
         attributes => [ qw(acl state text tip) ],
         defaults   => { acl => [ q(any) ], state => 0, text => NUL },
         lang_dep   => { qw(text 1 tip 1) },
      },
   } };

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Config - Schema defintions for config files

=head1 Version

0.6.$Revision: 1165 $

=head1 Synopsis

   use CatalystX::Usul::Config;

   $config_obj = CatalystX::Usul::Config->new( $attrs );

=head1 Description

Inherits from L<File::DataClass::Schema> and defines the schema for the
configuration files

=head1 Subroutines/Methods

=head2 resultset

   my $rs = $config_obj->resultset( $source_name, $lang );

Returns a L<File::DataClass::ResultSet> object. The C<$source_name> is
a key to the schema's result source attributes hash (these define the
schemas for the different configuration files). The C<$lang> argument
is the two character language code used to select locale specific
configuration files

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<File::DataClass::Schema>

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

Copyright (c) 2011 Peter Flanigan. All rights reserved

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
