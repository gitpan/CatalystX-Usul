# @(#)$Id: Templates.pm 1320 2013-07-31 17:31:20Z pjf $

package CatalystX::Usul::Model::Templates;

use strict;
use version; our $VERSION = qv( sprintf '0.8.%d', q$Rev: 1320 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(escape_TT unescape_TT throw);
use Class::Usul::File;
use File::Spec::Functions      qw(catdir);
use TryCatch;

extends q(CatalystX::Usul::Model);
with    q(CatalystX::Usul::TraitFor::Model::StashHelper);
with    q(CatalystX::Usul::TraitFor::Model::QueryingRequest);

has 'blank_ns'     => is => 'ro', isa => NonEmptySimpleStr, default => 'none';

has 'escape_chars' => is => 'ro', isa => ArrayRef[NonEmptySimpleStr],
   default         => sub { [ qw({ }) ] };

has 'extension'    => is => 'ro', isa => NonEmptySimpleStr, default => '.tt';

has 'ns_key'       => is => 'ro', isa => NonEmptySimpleStr,
   default         => 'namespace';

has 'root_ns'      => is => 'ro', isa => NonEmptySimpleStr, default => 'root';

has '_file' => is => 'lazy', isa => FileClass,
   default  => sub { Class::Usul::File->new( builder => $_[ 0 ]->usul ) },
   handles  => [ qw(io) ], init_arg => undef, reader => 'file';

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

   return catdir( $templates, split m{ $sep }mx, $ns );
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

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Templates - Edit page templates

=head1 Version

0.1.$Revision: 1320 $

=head1 Synopsis

   package YourApp;

   use Catalyst qw(ConfigComponents...);

   __PACKAGE__->config( 'Model::Templates' => {
      parent_classes => 'CatalystX::Usul::Model::Templates' } );

=head1 Description

CRUD methods for L<Template::Toolkit> files

=head1 Configuration and Environment

Defines the following list of attributes

=over 3

=item blank_ns

A non-empty simple string which defaults to C<none>. A marker to indicate
an application wide template. One that does not belong to a specific
namespace

=item escape_chars

An array ref of non-empty simple strings. Pair of fencepost characters
used to replace C<[> and C<]> when escaping L<Template::Toolkit> templates

=item extension

A non-empty simple string which defaults to F<.tt>

=item ns_key

A non-empty simple string which defaults to C<namespace>

=item root_ns

A non-empty simple string which defaults to C<root>

=back

=head1 Subroutines/Methods

=head2 build_per_context_instance

Instantiates the query object. Returns a clone of the model object

=head2 create_or_update

   $name = $self->create_or_update( $namespace );

Transforms C<$namespace> into the path to the template directory. Gets the
template from the form. Writes the form content to the selected template
file and returns the template name

=head2 delete

   $c->self->delete( $namespace );

Deletes the template specified by the form parameter and the selected
namespace

=head2 _get_template_data

   $hashref = $self->_get_template_data( $namespace, $name );

Returns a hashref containing a list of template names and the content of
the selected template

=head2 templates_view_form

   $self->templates_view_form( $namespace, $name );

Calls L</_get_template_data> and stash the data used to build the
template editing form

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::TraitFor::Model::QueryingRequest>

=item L<CatalystX::Usul::TraitFor::Model::StashHelper>

=item L<Class::Usul::File>

=item L<CatalystX::Usul::Moose>

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
