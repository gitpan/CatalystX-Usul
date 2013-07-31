# @(#)$Id: FileSystem.pm 1319 2013-06-23 16:21:01Z pjf $

package CatalystX::Usul::Model::FileSystem;

use strict;
use version; our $VERSION = qv( sprintf '0.8.%d', q$Rev: 1319 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Functions qw(find_source);

extends q(CatalystX::Usul::Model);
with    q(CatalystX::Usul::TraitFor::Model::StashHelper);

has '+domain_class' => default => q(CatalystX::Usul::FileSystem);

sub build_per_context_instance {
   my ($self, $c, @args) = @_; my $clone = $self->next::method( $c, @args );

   my $attr = { %{ $clone->domain_attributes || {} }, builder => $self->usul, };

   my $os_deps = $c->stash->{os};

   defined $os_deps->{fs_type}
          and $attr->{fs_type} ||= $os_deps->{fs_type}->{value};
   defined $os_deps->{fuser  }
          and $attr->{fuser  } ||= $os_deps->{fuser  }->{value};

   $clone->domain_model( $self->domain_class->new( $attr ) );

   return $clone;
}

sub get_file_systems {
   return shift->domain_model->file_systems( @_ );
}

sub list_subdirectory {
   return shift->domain_model->list_subdirectory( @_ );
}

sub view_file {
   my ($self, $subtype, $id) = @_; $id or return;

   my $path = $subtype eq q(source) ? find_source $id : $id;

   $self->add_field(  { path    => $path,
                        subtype => $subtype, type => q(file) } );
   $self->add_append( { class   => q(heading),
                        text    => $self->loc( 'Viewing [_1]', $path ),
                        type    => q(label) } );
   return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::FileSystem - File system related methods

=head1 Version

0.8.$Revision: 1319 $

=head1 Synopsis

   package YourApp;

   use Catalyst qw(ConfigComponents...);

   __PACKAGE__->config(
     'Model::FileSystem' => {
        parent_classes   => q(CatalystX::Usul::Model::FileSystem) }, );

=head1 Description

This model provides methods for manipulating files and directories

=head1 Configuration and Environment

Defines no attributes

=head1 Subroutines/Methods

=head2 build_per_context_instance

Creates an instance of L<CatalystX::Usul::Filesystem>

=head2 get_file_systems

   $self->get_file_systems( $args );

Returns the file systems on the local host

=head2 list_subdirectory

   $self->list_subdirectory( $directory );

Returns the contents of the selected directory as a
L<Class::Usul::Response::Table> object

=head2 view_file

   $self->view_file( $subtype, $id );

Stash the data used by L<HTML::FormWidgets> to view a file of a given type

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::FileSystem>

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::TraitFor::Model::StashHelper>

=item L<CatalystX::Usul::Moose>

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
