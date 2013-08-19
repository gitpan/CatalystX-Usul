# @(#)Ident: ;

package CatalystX::Usul::Model::Imager;

use strict;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions   qw(create_token is_member
                                    merge_attributes throw);
use Class::Usul::File;
use File::Basename               qw(basename);
use CatalystX::Usul::Constraints qw(Directory Path);
use File::Spec::Functions        qw(catdir catfile);
use Imager;
use MIME::Types;

extends qw(CatalystX::Usul::Model);

has 'cache_depth' => is => 'ro', isa => PositiveInt, default => 2;

has 'cache_root'  => is => 'ro', isa => Path, coerce => TRUE,
   required       => TRUE;

has 'methods'     => is => 'ro', isa => ArrayRef[NonEmptySimpleStr],
   default        => sub { [ qw(scale scaleX scaleY crop
                                flip rotate convert map) ] };

has 'root'        => is => 'ro', isa => Directory, coerce => TRUE,
   required       => TRUE;

has 'types'       => is => 'ro', isa => Object,
   default        => sub { MIME::Types->new( only_complete => 1 ) };

has '_file' => is => 'lazy', isa => FileClass,
   default  => sub { Class::Usul::File->new( builder => $_[ 0 ]->usul ) },
   handles  => [ qw(io status_for) ], init_arg => undef, reader => 'file';

sub COMPONENT {
   my ($class, $app, $attr) = @_;

   my $ac = $app->config || {}; my $cc = $class->config || {};

   $cc->{cache_root} ||= catdir( $ac->{tempdir}, q(imager_cache) );

   merge_attributes $attr, $cc, $ac, [ qw(cache_root root) ];

   return $class->next::method( $app, $attr );
}

sub transform {
   my ($self, $args, $query) = @_;

   $args->[ 0 ] or throw 'Method not specified'; $query ||= {};

   my $methods = shift @{ $args }; my @methods = split m{ \+ }mx, $methods;

   for my $method (@methods) {
      is_member $method, @{ $self->methods }
         or throw error => 'Imager method [_1] unknown', args => [ $method ];
   }

   $args->[ 0 ] or throw 'File path not specified';

   my $stat  = delete $query->{stat};
   my $force = delete $query->{force};
   my $path  = catfile( @{ $args } );
   my $key   = __make_key( $methods, $path, $query );

   $path = catfile( $self->root, $path );

   -f $path or throw error => 'Path [_1] not found', args => [ $path ];

   my $mtime = $stat ? $self->status_for( $path )->{mtime} : undef;
   my $type  = $self->types->mimeTypeOf( basename( $path ) )->type;
   my $data;

   if ($force or not $data = $self->_cache( $mtime, $key )) {
      $data = __get_image( \@methods, $path, $query );
      $self->_cache( undef, $key, $data );
   }

   return ($data, $type, $mtime);
}

# Private methods

sub _bucket {
   my ($self, $key, $depth) = @_; $depth ||= $self->cache_depth;

   my $file = create_token $key;

   return catfile( $self->cache_root,
                   (map { substr $file, 0, $_ + 1 } (0 .. $depth - 1)), $file );
}

sub _cache {
   my ($self, $mtime, $key, $data) = @_; $key or return;

   my $path = $self->_bucket( $key );

   if ($data) { $self->io( $path )->assert->lock->print( $data ) }
   elsif (-f $path) {
      if (not $mtime or $mtime <= $self->status_for( $path )->{mtime}) {
         $data = $self->io( $path )->lock->all;
      }
   }

   return $data;
}

# Private functions

sub __get_image {
   my ($methods, $path, $query) = @_;

   my $img  = Imager->new; my ($data, $transformed);

   $img->read( file => $path ) or throw $img->errstr;

   my $type = $img->tags( name => q(i_format) );

   for my $method (@{ $methods }) {
      $transformed = $img->$method( %{ $query } ) and $img = $transformed;
   }

   $img->write( data => \$data, type => $type ) or throw $img->errstr;
   return $data;
}

sub __make_key {
   my ($methods, $path, $query) = @_;

   return $methods.q(/).$path.q(?).(join  q(&),
                                    map   { $_.q(=).$query->{ $_ } }
                                    keys %{ $query });
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Imager - Manipulate images

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   package YourApp;

   use Catalyst qw(ConfigComponents...);

   __PACKAGE__->config(
     'Model::Imager'   => {
        parent_classes => q(CatalystX::Usul::Model::Imager),
        scale          => { scalefactor => 0.5 } }, );

   # For a thumbnail image
   # http://localhost:3000/imager/scale/static/images/catalyst_logo.png?scalefactor=0.5

=head1 Description

Transform any image under the document root using the L<Imager> module

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item cache_depth

A positive integer which defaults to C<2>. The number of intermediate
directory levels beneath the C<cache_root>

=item cache_root

A required path which points to the root of the image cache

=item methods

An array ref of non empty simple strings which are the list of methods
that can be applied to the image. Defaults to
C<scale scaleX scaleY crop flip rotate convert map>

=item root

A required directory. The document root for serving static content

=item types

An instance of L<MIME::Types>

=back

=head1 Subroutines/Methods

=head2 COMPONENT

Sets attributes for the document root and the cache root

=head2 transform

   ($data, $type, $mtime) = $self->transform( $args, $query );

Creates an L<Imager> object for the supplied path under the document
root. Transforms the object using the supplied method and parameters.
Returns the rendered image data, the mime type and the modification
time of the image file

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::Moose>

=item L<Class::Usul::File>

=item L<Imager>

=item L<MIME::Types>

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
