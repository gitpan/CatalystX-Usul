# @(#)Ident: FileSystem.pm 2013-08-19 19:16 pjf ;

package CatalystX::Usul::Response::FileSystem;

use strict;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(merge_attributes);

has 'file_system'  => is => 'ro',   isa => SimpleStr | Undef;

has 'file_systems' => is => 'lazy', isa => ArrayRef;

has 'fs_type'      => is => 'ro',   isa => SimpleStr | Undef,
   default         => q(ext3);

has 'ipc'          => is => 'ro',   isa => Object, handles => [ qw(run_cmd) ],
   required        => TRUE;

has 'volume'       => is => 'lazy', isa => SimpleStr | Undef;


has '_volume_map'  => is => 'lazy', isa => HashRef, init_arg => undef,
   reader          => 'volume_map';

around 'BUILDARGS' => sub {
   my ($next, $self, @args) = @_; my $attr = $self->$next( @args );

   my $builder = delete $attr->{builder} or return $attr;

   merge_attributes $attr, $builder, {}, [ qw(fs_type ipc) ];

   return $attr;
};

# Private methods

sub _build_file_systems {
   return [ sort { lc $a cmp lc $b } keys %{ $_[ 0 ]->volume_map } ];
}

sub _build_volume {
   return $_[ 0 ]->file_system ? $_[ 0 ]->volume_map->{ $_[ 0 ]->file_system }
                               : undef;
}

sub _build__volume_map {
   my $self = shift; my $map = {};

   my $cmd  = [ q(mount), ($self->fs_type ? (q(-t), $self->fs_type) : ()) ];

   for my $line (split m{ [\n] }mx, $self->run_cmd( $cmd )->stdout) {
      my ($volume, $filesys) = $line =~ m{ \A (\S+) \s+ on \s+ (\S+) }msx;

      $volume and $filesys and $map->{ $filesys } = $volume;
   }

   return $map;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Response::FileSystem - Object wrapper for the file system

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   use CatalystX::Usul::Response::FileSystem;

   $file_system_object = CatalystX::Usul::Response::FileSystem->new;

=head1 Description

Object wrapper for the file system

=head1 Configuration and Environment

Defines the following list of attributes;

=over 3

=item C<file_system>

An optional string. The name of the wanted file system

=item C<file_systems>

An array ref containing the list of defined file systems of the specified
type

=item C<fs_type>

An optional string. The type of the file systems to list

=item C<ipc>

A required object. An instance of L<Class::Usul::IPC>

=item C<volume>

An optional string. The volume of the I<file_system> attribute

=back

=head1 Subroutines/Methods

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

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
