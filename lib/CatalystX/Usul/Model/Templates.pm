# @(#)$Id: Templates.pm 1083 2011-11-26 22:17:41Z pjf $

package CatalystX::Usul::Model::Templates;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 1083 $ =~ /\d+/gmx );
use parent q(CatalystX::Usul::Model);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(escape_TT unescape_TT throw);
use TryCatch;

__PACKAGE__->config( blank_ns     => q(none),
                     escape_chars => [ qw({ }) ],
                     extension    => q(.tt),
                     ns_key       => q(namespace),
                     root_ns      => q(root), );

__PACKAGE__->mk_accessors( qw(blank_ns ns_key escape_chars
                              extension root_ns) );

sub create_or_update {
   my ($self, $ns) = @_;

   my $extn    = $self->extension;
   my $newtag  = $self->context->stash->{newtag};
   my $name    = $self->query_value( q(template) );
   my $content = unescape_TT $self->query_value( q(content) );
   my $message = 'Template [_1] / [_2] updated';

   if ($name eq $newtag) {
      $name    = $self->query_value( q(name) );
      $name and $name !~ m{ $extn \z }mx and $name .= $extn;
      $message = 'Template [_1] / [_2] created';
   }

   $name or throw 'Template name not specified';
   $self->io( [ $self->_get_dir_for( $ns ), $name ] )->print( $content );
   $self->add_result_msg( $message, [ $ns, $name ] );
   return $name;
}

sub delete {
   my ($self, $ns) = @_;

   my $name = $self->query_value( q(template) )
      or throw 'Template name not specified';

   $self->io( [ $self->_get_dir_for( $ns ), $name ] )->unlink;
   $self->add_result_msg( 'Template [_1] / [_2] deleted', [ $ns, $name ] );
   return;
}

sub templates_view_form {
   my ($self, $ns, $name) = @_; my $s = $self->context->stash; my $data = {};

   my $newtag = $s->{newtag}; $ns ||= q(default); $name ||= $newtag;

   try        { $data = $self->_get_template_data( $ns, $name ) }
   catch ($e) { $self->add_error( $e ) }

   my $form     = $s->{form}->{name};
   my $firstfld = $form.($name eq $newtag ? q(.name) : q(.template));
   my $spaces   = [ NUL, $self->blank_ns, $self->root_ns,
                    sort keys %{ $s->{ $self->ns_key } } ];
   my $list     = [ NUL, $newtag, @{ $data->{list} || [] } ];

   $self->clear_form  ( { firstfld => $firstfld } );
   $self->add_field   ( { default  => $ns,
                          id       => $form.q(.namespace),
                          values   => $spaces, } );
   $self->add_field   ( { default  => $name,
                          id       => $form.q(.template),
                          values   => $list, } );

   if ($name ne $newtag) { $self->add_hidden( q(name), $name ) }
   else { $self->add_field( { id => $form.q(.name) } ) }

   $self->group_fields( { id       => $form.q(.select) } );
   $self->add_field   ( { default  => $data->{template} || NUL,
                          id       => $form.q(.content), } );
   $self->group_fields( { id       => $form.q(.edit) } );

   if ($name eq $newtag) { $self->add_buttons( qw(Insert) ) }
   else { $self->add_buttons( qw(Save Delete) ) }

   return;
}

# Private methods

sub _get_dir_for {
   my ($self, $ns) = @_; $ns eq $self->blank_ns and $ns = NUL;

   my $sep = SEP; my $templates = $self->context->config->{template_dir};

   return $self->catdir( $templates, split m{ $sep }mx, $ns );
}

sub _get_template_data {
   my ($self, $ns, $name) = @_;

   my $extn  = $self->extension;
   my $dir   = $self->_get_dir_for( $ns );
   my $io    = $self->io( [ $dir, $name ] );
   my $tt    = $io->is_file ? $io->all : NUL;
   my $fs    = $self->context->model( q(FileSystem) );
   my $args  = { dir => $dir, pattern => qr{ \Q$extn\E \z }mx };
   my $table = $fs->list_subdirectory( $args );

   return { list     => [ map { $_->{name} } @{ $table->values } ],
            template => escape_TT $tt, $self->escape_chars };
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Templates - Edit page templates

=head1 Version

0.1.$Revision: 1083 $

=head1 Synopsis

=head1 Description

CRUD methods for TT files

=head1 Configuration and Environment

=head1 Subroutines/Methods

=head2 create_or_update

   $name = $c->model( q(Templates) )->create_or_update( $namespace );

Transforms C<$namespace> into the path to the template directory. Gets the
template from the form. Writes the form content to the selected template
file and returns the template name

=head2 delete

   $c->model( q(Templates) )->delete( $namespace );

Deletes the template specified by the form parameter and the selected
namespace

=head2 _get_template_data

   $hashref = $c->model( q(Templates) )->_get_template_data( $namespace, $name );

Returns a hashref containing a list of template names and the content of
the selected template

=head2 templates_view_form

   $c->model( q(Templates) )->templates_view_form( $namespace, $name );

Calls L</_get_template_data> and stash the data used to build the
template editing form

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::Functions>

=item L<TryCatch>

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

Copyright (c) 2010 Peter Flanigan. All rights reserved

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
