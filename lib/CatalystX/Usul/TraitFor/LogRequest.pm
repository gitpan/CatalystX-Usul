# @(#)Ident: ;

package CatalystX::Usul::TraitFor::LogRequest;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.13.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Moose::Role;

requires qw(config debug log);

sub log_request_parameters {
   # Print stars instead of values for some debug attributes
   my ($self, %all_params) = @_; $self->debug or return;

   my $config       = $self->config->{Debug} || {};
   my $re           = $config->{skip_dump_parameters} || q();
   my $column_width = Catalyst::Utils::term_width() - 44;

   for my $type (qw(query body)) {
      my $params = $all_params{ $type }; keys %{ $params } or next;

      my $t = Text::SimpleTable->new( [ 35, 'Parameter' ],
                                      [ $column_width, 'Value' ] );

      for my $key (sort keys %{ $params }) {
         my $param = exists $params->{ $key } ? $params->{ $key } : q();
         my $value = ref $param eq q(ARRAY)
                   ? (join q(, ), @{ $param }) : $param;

         $re and $key =~ m{ \A $re \z }mx and $value = q(*) x length $value;
         $t->row( $key, $value );
      }

      $self->log->debug( (ucfirst $type)." Parameters are:\n".$t->draw );
   }

   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TraitFor::LogRequest - Log request parameters with filtering

=head1 Version

Describes v0.13.$Rev: 1 $

=head1 Synopsis

   package YourApp;

   use CatalystX::Usul::Moose;

   with qw(CatalystX::Usul::TraitFor::LogRequest);

=head1 Description

Log request parameters, displaying values for selected keys as stars

=head1 Configuration and Environment

Requires I<config>, I<debug>, and I<log> attributes

=head1 Subroutines/Methods

=head2 log_request_parameters

Overrides the Catalyst method to suppress the printing of passwords in
the debug output. The configuration options C<Debug> attribute
C<skip_dump_parameters> should be set to a regex that matches the keys
to suppress

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Moose::Role>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

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
