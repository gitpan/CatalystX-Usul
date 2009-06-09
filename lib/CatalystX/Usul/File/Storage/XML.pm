# @(#)$Id: XML.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::File::Storage::XML;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul);

use Class::C3;
use Hash::Merge qw(merge);
use List::Util qw(max);

__PACKAGE__->config( extn => q(.xml), lang => q(), path => q(), _dtd => [] );

__PACKAGE__->mk_accessors( qw(extn lang path schema _arrays _dtd) );

my $cache = {};

sub delete {
   my ($self, $element_obj) = @_;

   return $self->_delete( $element_obj, $self->_validate_params );
}

sub insert {
   my ($self, $element_obj) = @_;

   my ($path, $element) = $self->_validate_params;

   $path->touch;

   # TODO: Add _arrays attributes from schema definition
   if ($self->_is_array( $element ) && !$self->_is_in_dtd( $element )) {
      push @{ $self->_dtd }, '<!ELEMENT '.$element.' (ARRAY)*>';
   }

   return $self->_write( 0, $element_obj, $path, $element );
}

sub load_files {
   my ($self, @paths) = @_; return $self->_load_files( @paths );
}

sub select {
   my $self = shift;
   my ($path, $element) = $self->_validate_params;
   my @paths = ( $path );

   push @paths, $self->_make_lang_path( $path ) if ($self->lang);

   my $data = $self->_load_files( @paths );

   return exists $data->{ $element } ? $data->{ $element } : {};
}

sub update {
   my ($self, $element_obj) = @_;

   return $self->_write( 1, $element_obj, $self->_validate_params );
}

# Private methods

sub _delete {
   my ($self, $element_obj, $path, $element) = @_;

   my $name    = delete $element_obj->{name};
   my ($data)  = $self->_read_file( $path );
   my $updated = 0;

   if (exists $data->{ $element } && exists $data->{ $element }->{ $name }) {
      delete $data->{ $element }->{ $name }; $updated = 1;
      $self->_write_file( $path, $data );
   }

   if ($self->lang) {
      my $lang_path = $self->_make_lang_path( $path );
      ($data) = $self->_read_file( $lang_path );

      if (exists $data->{ $element }
          && exists $data->{ $element }->{ $name }) {
         delete $data->{ $element }->{ $name }; $updated = 1;
         $self->_write_file( $lang_path, $data );
      }
   }

   unless ($updated) {
      $self->throw( error => 'File [_1] element [_2] not updated',
                    args  => [ $path, $name ] );
   }

   return $updated;
}

sub _delete_cache {
   my ($self, $key) = @_; delete $cache->{ $key }; return;
}

sub _dtd_parse {
   my ($self, $data) = @_;

   $self->_dtd_parse_reset;

   return unless ($data);

   while ($data =~ s{ ( <! [^<>]+ > ) }{}msx) {
      push @{ $self->_dtd }, $1; $self->_dtd_parse_line( $1 );
   }

   return $data;
}

sub _dtd_parse_line {
   my ($self, $data) = @_;

   if ($data =~ m{ \A <!ELEMENT \s+ (\w+) \s+ \(
                      \s* ARRAY \s* \) \*? \s* > \z }imsx) {
      $self->_arrays->{ $1 } = 1;
   }

   return;
}

sub _dtd_parse_reset {
   my $self = shift; $self->_arrays( {} ); $self->_dtd( [] ); return;
}

sub _is_array {
   my ($self, $element) = @_;

   return 0;
}

sub _is_in_dtd {
   my ($self, $candidate) = @_; my %elements;

   my $pattern = '<!ELEMENT \s+ (\w+) \s+ \( \s* ARRAY \s* \) \*? \s* >';

   $elements{ $_ } = 1 for (grep { m{ \A $pattern \z }msx } @{ $self->_dtd });

   return exists $elements{ $candidate };
}

sub _load_files {
   my ($self, @paths) = @_; my ($cached, $data, $key, $mtime, $path);

   return {} unless ($paths[0]);

   my $newest = 0; my $ref = {};

   for $path (@paths) {
      my $pathname = $path->pathname;

      $key .= $key ? q(~).$pathname : $pathname;

      if ($cached = $cache->{ $pathname }) { $mtime = $cached->{mtime} }
      else { $mtime = $path->stat->{mtime} || 0 }

      $newest = $mtime if ($mtime > $newest);
   }

   $cached = $cache->{ $key };

   if (not $cached or $cached->{mtime} < $newest) {
      for $path (@paths) {
         ($data) = $self->_read_file( $path );

         next unless ($data);

         for (keys %{ $data }) {
            $ref->{ $_ } = exists $ref->{ $_ }
                         ? merge( $ref->{ $_ }, $data->{ $_ } )
                         : $data->{ $_ };
         }
      }

      $self->_set_cache( $key, $ref, $newest );
   }
   else { $ref = $cached->{data} }

   return $ref;
}

sub _make_lang_path {
   my ($self, $path) = @_;

   my $pathname = $path->pathname; my $extn = $self->extn;

   return $pathname.q(_).$self->lang unless ($pathname =~ m{ $extn \z }mx);

   my $file = $self->basename( $pathname, $extn ).q(_).$self->lang.$extn;

   return $self->io( $self->catfile( $self->dirname( $pathname ), $file ) );
}

sub _merge_attr {
   my ($self, $from, $to_ref) = @_;

   my $updated = 0; my $to = ${ $to_ref };

   if ($to && ref $to eq q(ARRAY)) {
      $updated = $self->_merge_attr_arrays( $from, $to );
   }
   elsif ($to && ref $to eq q(HASH)) {
      $updated = $self->_merge_attr_hashes( $from, $to );
   }
   elsif ((!$to && defined $from) || ($to && $to ne $from)) {
      $updated = 1; ${ $to_ref } = $from;
   }

   return $updated;
}

sub _merge_attr_arrays {
   my ($self, $from, $to) = @_; my $updated = 0;

   for (0 .. $#{ $to }) {
      if ($from->[ $_ ]) {
         my $res = $self->_merge_attr( $from->[ $_ ], \$to->[ $_ ] );
         $updated ||= $res;
      }
      elsif ($to->[ $_ ]) {
         $updated = 1; splice @{ $to }, $_;
         last;
      }
   }

   if (@{ $from } > @{ $to }) {
      $updated = 1; push @{ $to }, (splice @{ $from }, $#{ $to } + 1);
   }

   return $updated;
}

sub _merge_attr_hashes {
   my ($self, $from, $to) = @_; my $updated = 0;

   for (keys %{ $to }) {
      if ($from->{ $_ }) {
         my $res = $self->_merge_attr( $from->{ $_ }, \$to->{ $_ } ) ;
         $updated ||= $res;
      }
      elsif ($to->{ $_ }) {
         $updated = 1; delete $to->{ $_ };
      }
   }

   if (keys %{ $from } > keys %{ $to }) {
      for (keys %{ $from }) {
         if ($from->{ $_ } && !exists $to->{ $_ }) {
            $updated = 1; $to->{ $_ } = $from->{ $_ };
         }
      }
   }

   return $updated;
}

sub _merge_attrs {
   my ($self, $overwrite, $condition, $src, $dest) = @_;

   my $updated = 0; ${ $dest } ||= {};

   for my $attr (grep  { not m{ \A _ }mx
                         and $_ ne q(name)
                         and $condition->( $_ ) }
                 keys %{ $src }) {
      if (defined $src->{ $attr }) {
         my $res = $self->_merge_attr
            ( $src->{ $attr }, \${ $dest }->{ $attr } );
         $updated ||= $res;
      }
      elsif (${ $dest }->{ $attr }) {
         $updated = 1; delete ${ $dest }->{ $attr };
      }
   }

   ${ $dest }->{name} = $src->{name} if ($updated);

   return $updated;
}

sub _read_file {
   my ($self, $path) = @_;

   $self->throw( error => 'Method _read_file not overridden in [_1]',
                 args  => [ ref $self ] );
   return;
}

sub _read_file_with_locking {
   my ($self, $path, $coderef) = @_; my ($data, $e);

   my $pathname = $path->pathname;

   $self->lock->set( k => $pathname );

   my $res   = $cache->{ $pathname };
   my $mtime = $path->stat->{mtime};

   if (not $res or $res->{mtime} < $mtime) {
      $data = eval { $coderef->() };

      if ($e = $self->catch) {
         $self->lock->reset( k => $pathname ); $self->throw( $e );
      }

      $self->_set_cache( $pathname, $data, $mtime );

      $self->log_debug( "Reread config $pathname" ) if ($self->debug);
   }
   else {
      $data = $res->{data}; $self->_dtd( $res->{dtd} );

      $self->log_debug( "Cached config $pathname" ) if ($self->debug);
   }

   $self->lock->reset( k => $pathname );

   return ($data, $mtime);
}

sub _set_cache {
   my ($self, $key, $data, $mtime) = @_;

   $cache->{ $key } = { data => $data, dtd => $self->_dtd, mtime => $mtime };
   return;
}

sub _validate_params {
   my $self = shift; my ($elem, $path, $schema);

   $self->throw( 'No schema specified'    ) unless ($schema = $self->schema);
   $self->throw( 'No file path specified' ) unless ($path = $self->path);
   $self->throw( 'No element specified'   ) unless ($elem = $schema->element);

   return ($path, $elem);
}

sub _write {
   my ($self, $overwrite, $element_obj, $path, $element) = @_;

   my $schema    = $self->schema;
   my $condition = sub { !$schema->lang_dep || !$schema->lang_dep->{ $_[0] } };
   my $updated   = $self->_write_on_condition( $overwrite, $element_obj,
                                               $path, $element, $condition );

   if ($self->lang) {
      my $lpath  = $self->_make_lang_path( $path );
      $condition = sub { $schema->lang_dep && $schema->lang_dep->{ $_[0] } };
      my $res    = $self->_write_on_condition( $overwrite, $element_obj,
                                               $lpath, $element, $condition );
      $updated ||= $res;
   }

   $self->throw( 'Nothing updated' ) if ($overwrite and not $updated);

   return $updated;
}

sub _write_file {
   my ($self, $path, $data) = @_;

   $self->throw( error => 'Method _write_file not overridden in [_1]',
                 args  => [ ref $self ] );
   return;
}

sub _write_file_with_locking {
   my ($self, $path, $coderef) = @_; my $e;

   my $pathname = $path->pathname;

   $self->lock->set( k => $pathname );

   my $wtr  = $path->perms( oct q(0664) )->atomic;
   my $data = eval { $coderef->( $wtr ) };

   if ($e = $self->catch) {
      $wtr->delete; $self->lock->reset( k => $pathname );
      $self->throw( $e );
   }

   $wtr->close;
   $self->_delete_cache( $pathname );
   $self->lock->reset( k => $pathname );
   return;
}

sub _write_on_condition {
   my ($self, $overwrite, $element_obj, $path, $element, $condition) = @_;

   my $name    = $element_obj->name;
   my ($data)  = $self->_read_file( $path );

   if (!$overwrite && exists $data->{ $element }->{ $name }) {
      $self->throw( error => 'File [_1] element [_2] already exists',
                    args  => [ $path->pathname, $name ] );
   }

   my $row_ref = \$data->{ $element }->{ $name };
   my $updated = $self->_merge_attrs( $overwrite, $condition,
                                      $element_obj, $row_ref );

   $self->_write_file( $path, $data ) if ($updated);

   return $updated;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::File::Storage::XML - Read/write XML data storage model

=head1 Version

0.1.$Revision: 562 $

=head1 Synopsis

This is an abstract base class. See one of the subclasses for a
concrete example

=head1 Description

Implements the basic storage methods for reading and writing XML files

=head1 Subroutines/Methods

=head2 delete

   $bool = $self->delete( $element_obj );

Deletes the specified element object returning true if successful. Throws
an error otherwise

=head2 insert

   $bool = $self->insert( $element_obj );

Inserts the specified element object returning true if successful. Throws
an error otherwise

=head2 load_files

   $hash_ref = $self->load_files( @paths );

Loads each of the specified files merging the resultant hash ref which
it returns. Paths are instances of L<CatalystX::Usul::File::IO>

=head2 select

   $hash_ref = $self->select;

Returns a hash ref containing all the elements of the type specified in the
schema

=head2 update

   $bool = $self->update( $element_obj );

Updates the specified element object returning true if successful. Throws
an error otherwise

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul>

=item L<Hash::Merge>

=item L<List::Util>

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
