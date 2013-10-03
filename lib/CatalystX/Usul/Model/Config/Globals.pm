# @(#)Ident: ;

package CatalystX::Usul::Model::Config::Globals;

use strict;
use version; our $VERSION = qv( sprintf '0.13.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(throw);
use TryCatch;

extends q(CatalystX::Usul::Model::Config);

has '+create_msg_key' => default => 'Global attribute [_2] created in [_1]';

has '+delete_msg_key' => default => 'Global attribute [_2] deleted from [_1]';

has 'filename'        => is => 'ro', isa => Str, default => q(default);

has '+keys_attr'      => default => q(globals);

has '+update_msg_key' => default => 'Global attribute [_2] updated in [_1]';

sub globals_form {
   my $self = shift; my $s = $self->context->stash; my @elements;

   my $form   = $s->{form}->{name}; $s->{pwidth} -= 10;

   try        { @elements = $self->search( $self->filename ) }
   catch ($e) { return $self->add_error( $e ) }

   $self->clear_form( { firstfld => "${form}.newParam" } );
   $self->add_field ( { id       => "${form}.newParam", stepno => 0 } );

   for my $element (sort { $a->name cmp $b->name } @elements) {
      my $text = $element->name; $text =~ s{ _ }{ }gmx;

      $self->add_field( { clear   => q(left),
                          default => $element->value,
                          name    => $element->name,
                          prompt  => $self->loc( q(defTextPrompt), $text ),
                          stepno  => -1,
                          width   => 40 } );
   }

   $self->group_fields( { id => "${form}.edit" } );
   $self->add_buttons ( qw(Save Delete) );
   return;
}

sub save {
   my $self = shift; my ($element, $p, $updated, $v);

   if ($p = lc $self->query_value( q(newParam) )) {
      if ($self->find( $self->filename, $p )) {
         throw error => 'Attribute [_1] already exists', args => [ $p ];
      }

      $self->create( $self->filename, { name => $p, value => q() } );
   }
   else {
      for $element ($self->search( $self->filename )) {
         if (defined ($v = $self->query_value( $element->name ))
             and (($v and not defined $element->value)
                  or (defined $element->value and $element->value ne $v))) {
            $element->value( $v ); $element->update;
            $self->add_result_msg( $self->update_msg_key,
                                   $self->filename, $element->name );
            $updated = TRUE;
         }
      }

      $updated or throw 'Nothing updated';
   }

   return TRUE;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Globals - Class definition for global configuration variables

=head1 Version

Describes v0.13.$Rev: 1 $

=head1 Synopsis

   # The constructor is called by Catalyst at startup

=head1 Description

Defines the attributes of the global definitions in the configuration files

Defines one attribute; I<value>

=head1 Subroutines/Methods

=head2 globals_form

Stuffs the stash with the data to display the global editing form

=head2 save

Updates the global configuration variables

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
