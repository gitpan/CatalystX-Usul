# @(#)$Id: FileSystem.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Model::FileSystem;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model);

use CatalystX::Usul::FileSystem;
use MRO::Compat;

sub build_per_context_instance {
   my ($self, $c, @rest) = @_; my $s = $c->stash;

   my $new   = $self->next::method( $c, @rest );
   my $attrs = { %{ $new->domain_attributes || {} } };

   $attrs->{debug  } ||= $s->{debug};
   $attrs->{lang   } ||= $s->{lang};
   $attrs->{fs_type} ||= $s->{os}->{fs_type}->{value};
   $attrs->{fuser  } ||= $s->{os}->{fuser  }->{value};
   $attrs->{logsdir} ||= $c->config->{logsdir};

   $new->domain_model( CatalystX::Usul::FileSystem->new( $c, $attrs ) );

   return $new;
}

sub get_file_systems {
   return shift->domain_model->get_file_systems( @_ );
}

sub list_subdirectory {
   return shift->domain_model->list_subdirectory( @_ );
}

sub view_file {
   my ($self, $subtype, $id) = @_; $id or return;

   my $path = $subtype eq q(source) ? $self->find_source( $id ) : $id;

   $self->add_field(  { path    => $path,
                        subtype => $subtype, type => q(file) } );
   $self->add_append( { class   => q(heading),
                        text    => $self->loc( 'Viewing [_1]', $path ),
                        type    => q(label) } );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::FileSystem - File system related methods

=head1 Version

0.6.$Revision: 1165 $

=head1 Synopsis

   package MyApp::Model::FileSystem;

   use base qw(CatalystX::Usul::Model::FileSystem);

   1;

   package MyApp::Controller::Foo;

   sub bar {
      my ($self, $c) = @_;

      $c->model( q(FileSystem) )->list_subdirectory( { dir => q(/path) } );
      return;
   }

=head1 Description

This model provides methods for manipulating files and directories

=head1 Subroutines/Methods

=head2 build_per_context_instance

Creates an instance of L<CatalystX::Usul::Filesystem>

=head2 get_file_systems

Returns the file systems on the local host

=head2 list_subdirectory

Returns the contents of the selected directory as a L<CatalystX::Usul::Table>
object

=head2 view_file

Stash the data used by L<HTML::FormWidgets> to view a file of a given type

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::FileSystem>

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
