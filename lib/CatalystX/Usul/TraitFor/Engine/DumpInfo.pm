# @(#)$Id: DumpInfo.pm 1305 2013-04-02 14:51:23Z pjf $

package CatalystX::Usul::TraitFor::Engine::DumpInfo;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.8.%d', q$Rev: 1305 $ =~ /\d+/gmx );

use Moose::Role;
use Data::Dumper;
use HTML::Entities;

requires q(finalize_error);

before 'finalize_error' => sub {
   my ($self, $c) = @_;

   my $config = $c->config->{Debug} || {};
   my $re     = $config->{skip_dump_elements} || q(_print_all_the_keys_);

   $Data::Dumper::Terse    = 1;
   $Data::Dumper::Indent   = 1;
   $Data::Dumper::Sortkeys = sub {
      return [ grep { not m{ $re }mx } sort keys %{ $_[ 0 ] } ];
   };

   return;
};

# Private methods

sub _dump_error_page_element {
   my ($self, $i, $element) = @_; my ($name, $val) = @{ $element };

   ref $val eq q(HASH) and exists $val->{'__MOP__'}
      and local $val->{'__MOP__'} = 'Stringified: '.$val->{'__MOP__'} ;

   return sprintf << "EOF", $name, encode_entities( Dumper( $val ) );
<h2><a href="#" onclick="toggleDump('dump_$i'); return false">%s</a></h2>
<div id="dump_$i" style="display: none;">
    <pre wrap="">%s</pre>
</div>
EOF
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TraitFor::Engine::DumpInfo - Prettier debug information dump

=head1 Version

0.8.$Revision: 1305 $

=head1 Synopsis

   package YourApp;

   use CatalystX::RoleApplicator;

   __PACKAGE__->apply_engine_class_roles
      ( qw(CatalystX::Usul::TraitFor::Engine::DumpInfo) );

   # Start the development server with

   bin/munchies_server -d -r -rd 1 -rr "\\.json\$|\\.pm\$" \
      --restart_directory lib

=head1 Description

Replaces the use of L<Data::Dump> with L<Data::Dumper> in the
dump info output

=head1 Subroutines/Methods

=head2 finalize_error

Uses a method modifier to execute this before L<Catalyst/finalize_error>. Sets
the packaged scoped variables in the L<Data::Dumper> api

=head2 _dump_error_page_element

Replaces the Catalyst method of the same name. Calls <Data::Dumper/Dumper>

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Data::Dumper>

=item L<HTML::Entites>

=item L<Moose::Role>

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
