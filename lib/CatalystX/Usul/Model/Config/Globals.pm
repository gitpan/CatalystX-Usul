# @(#)$Id: Globals.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::Model::Config::Globals;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model::Config);

__PACKAGE__->config( create_msg_key    => q(Globals [_2] created),
                     delete_msg_key    => q(Globals [_2] deleted),
                     file              => q(default),
                     keys_attr         => q(),
                     schema_attributes => {
                        attributes     => [ qw(value) ],
                        defaults       => {},
                        element        => q(globals),
                        lang_dep       => {}, },
                     typelist          => {},
                     update_msg_key    => q(Globals [_2] updated), );

__PACKAGE__->mk_accessors( qw(file) );

sub globals_form {
   my $self = shift; my $s = $self->context->stash;
   my ($clear, $e, $element, @elements, $form, $nitems, $prompt, $step, $text);

   $step     = 1;
   $form     = $s->{form}->{name};
   $prompt   = $self->loc( q(defTextPrompt) );
   @elements = eval { $self->search( $self->file ) };

   return $self->add_error( $e ) if ($e = $self->catch);

   $s->{pwidth} -= 10;
   $self->clear_form( { firstfld => $form.'.newParam' } ); $nitems = 0;
   $self->add_field(  { id       => $form.'.newParam',
                        stepno   => $step++ } ); $nitems++;

   for $element (sort { $a->name cmp $b->name } @elements) {
      $clear = $nitems > 0 ? q(left) : q();
      $text  = $element->name; $text =~ s{ _ }{ }gmx; $text = $prompt.$text;
      $self->add_field( { clear    => $clear,
                          default  => $element->value,
                          name     => $element->name,
                          prompt   => $text,
                          stepno   => $step++,
                          width    => 40 } ); $nitems++;
   }

   $self->group_fields( { id => $form.'.edit', nitems => $nitems } );
   $self->add_buttons(  qw(Save Delete) );
   return;
}

sub save {
   my $self = shift; my ($element, $p, $updated, $val);

   if ($p = $self->query_value( q(newParam) )) {
      if ($self->find( $self->file, lc $p )) {
         $self->throw( error => 'Attribute [_1] already exists',
                       args  => [ lc $p ] );
      }

      $self->create( { file   => $self->file,
                       fields => { value => q() }, name => lc $p } );
   }
   else {
      for $element ($self->search( $self->file )) {
         if (defined ($val = $self->query_value( $element->name ))
             && (($val && !defined $element->value)
                 || (defined $element->value && $element->value ne $val))) {
            $element->value( $val );
            $element->update;
            $self->add_result_msg( $self->update_msg_key, $element->name );
            $updated = 1;
         }
      }

      $self->throw( 'Nothing updated' ) unless ($updated);
   }

   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Globals - Class definition for global configuration variables

=head1 Version

0.1.$Revision: 562 $

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
