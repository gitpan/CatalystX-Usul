# @(#)$Id: Imager.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::Model::Imager;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model);

use Imager;
use MIME::Types;

my @METHODS = qw(scale scaleX scaleY crop flip rotate convert map);

__PACKAGE__->config( cache_depth => 2,
                     types       => MIME::Types->new( only_complete => 1 ) );

__PACKAGE__->mk_accessors( qw(cache_depth cache_root doc_root types) );

sub new {
   my ($self, $app, @rest) = @_;

   my $new = $self->next::method( $app, @rest );

   $new->cache_root( $new->catdir( $new->tempdir, q(imager_cache) ) );
   $new->doc_root  ( $app->config->{root}                           );

   return $new;
}

sub transform {
   my ($self, $args, $query) = @_; my $data; $query ||= {};

   $self->throw( 'No method specified' ) unless ($args->[ 0 ]);

   my $methods = shift @{ $args }; my @methods = split m{ \+ }mx, $methods;

   for my $method (@methods) {
      unless ($self->is_member( $method, @METHODS )) {
         $self->throw( error => 'Method [_1] unknown', args => [ $method ] );
      }
   }

   $self->throw( 'No file path specified' ) unless ($args->[ 0 ]);

   my $stat  = delete $query->{stat};
   my $force = delete $query->{force};
   my $path  = $self->catfile( @{ $args } );
   my $key   = $self->_make_key( $methods, $path, $query );

   $path = $self->catfile( $self->doc_root, $path );

   unless (-f $path) {
      $self->throw( error => 'File [_1] not found', args => [ $path ] );
   }

   my $mtime = $stat ? $self->status_for( $path )->{mtime} : undef;
   my $type  = $self->types->mimeTypeOf( $self->basename( $path ) )->type;

   if ($force or not $data = $self->_cache( $mtime, $key )) {
      $data = $self->_get_image( \@methods, $path, $query );
      $self->_cache( undef, $key, $data );
   }

   return ($data, $type, $mtime);
}

# Private methods

sub _bucket {
   my ($self, $key, $depth) = @_; $depth ||= $self->cache_depth;

   my $file = $self->create_token( $key );

   return $self->catfile( $self->cache_root,
                          (map { substr $file, 0, $_ + 1 } (0 .. $depth - 1)),
                          $file );
}

sub _cache {
   my ($self, $mtime, $key, $data) = @_; my $e;

   return unless ($key);

   my $path = $self->_bucket( $key );

   if ($data) { $self->io( $path )->assert->lock->print( $data ) }
   elsif (-f $path) {
      if (!$mtime || $mtime <= $self->status_for( $path )->{mtime}) {
         $data = $self->io( $path )->lock->all;
      }
   }

   return $data;
}

sub _get_image {
   my ($self, $methods, $path, $query) = @_; my $data;

   my $img  = Imager->new;

   $self->throw( $img->errstr ) unless ($img->read( file => $path ));

   my $type = $img->tags( name => q(i_format) );

   for my $method (@{ $methods }) { $img = $img->$method( %{ $query } ) }

   unless ($img->write( data => \$data, type => $type )) {
      $self->throw( $img->errstr );
   }

   return $data;
}

sub _make_key {
   my ($self, $methods, $path, $query) = @_;

   return $methods.q(/).$path.q(?).(join  q(&),
                                    map   { $_.q(=).$query->{ $_ } }
                                    keys %{ $query });
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Imager - Manipulate images

=head1 Version

0.1.$Revision: 562 $

=head1 Synopsis

   my $model = $c->model( q(Imager) );

   my ($data, $type, $mtime) = eval {
      $model->transform( [ @args ], $c->req->query_parameters );
   };

   # For a thumbnail image
   # http://localhost:3000/en/imager/scale/static/images/catalyst_logo.png?scalefactor=0.5

=head1 Description

Transform any image under the document root using the L<Imager> module

=head1 Subroutines/Methods

=head2 new

Sets attributes for the document root and the cache root

=head2 transform

Creates an L<Imager> object for the supplied path under the document
root. Transforms the object using the supplied method and parameters.
Returns the rendered image data, the mime type and the modification
time of the image file

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

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
