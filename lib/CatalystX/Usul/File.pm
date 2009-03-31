package CatalystX::Usul::File;

# @(#)$Id: File.pm 407 2009-03-30 09:34:16Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul);
use CatalystX::Usul::File::ResultSource;
use Class::C3;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 407 $ =~ /\d+/gmx );

__PACKAGE__->config
   ( result_source_class => q(CatalystX::Usul::File::ResultSource),
     schema_attributes   => {} );

__PACKAGE__->mk_accessors( qw(result_source result_source_class
                              schema_attributes ) );

sub new {
   my ($self, $app, @rest) = @_;

   my $new   = $self->next::method( $app, @rest );
   my $attrs = { schema_attributes => $new->schema_attributes };

   $new->result_source( $new->result_source_class->new( $app, $attrs ) );

   return $new;
}

sub add_to_attribute_list {
   my ($self, $args) = @_; my ($added, $attrs, $list);

   my ($rs, $name) = $self->_validate_params( $args );

   $self->throw( q(eNoListName) ) unless ($list = $args->{list});

   my $items = $args->{items};

   $self->throw( q(eNoListItems) ) unless ($items->[0]);

   $self->_txn_do( $args->{path}, sub {
      ($attrs, $added) = $rs->push_attribute( $name, $list, $items );
      $rs->find_and_update( $name, $attrs );
   } );

   return $added;
}

sub create {
   my ($self, $args) = @_;

   my ($rs, $name) = $self->_validate_params( $args );

   $args->{fields}->{name} = $name;

   $self->_txn_do( $args->{path}, sub {
      $rs->create( $args->{fields} )->insert;
   } );

   return $name;
}

sub delete {
   my ($self, $args) = @_;

   my ($rs, $name) = $self->_validate_params( $args );

   $self->_txn_do( $args->{path}, sub {
      my $element = $rs->find( $name );
      $self->throw( error => q(eNoRecord), arg1 => $name ) unless ($element);
      $element->delete;
   } );

   return $name;
}

sub find {
   my ($self, $args) = @_;

   my ($rs, $name) = $self->_validate_params( $args );

   return $self->_txn_do( $args->{path}, sub { $rs->find( $name ) } );
}

sub get_list {
   my ($self, $args) = @_; my $path;

   $self->throw( q(eNoPath) ) unless ($path = $args->{path});

   my $rs = $self->result_source->resultset( $path, $args->{lang} );

   return $self->_txn_do( $args->{path},
                          sub { $rs->get_list( $args->{name} ) } );
}

sub load_files {
   my ($self, @paths) = @_;

   my $rs = $self->result_source->resultset;

   return $rs->storage->load_files( @paths ) || {};
}

sub remove_from_attribute_list {
   my ($self, $args) = @_; my ($attrs, $list, $removed);

   my ($rs, $name) = $self->_validate_params( $args );

   $self->throw( q(eNoListName) ) unless ($list = $args->{list});

   my $items = $args->{items};

   $self->throw( q(eNoListItems) ) unless ($items->[0]);

   $self->_txn_do( $args->{path}, sub {
      ($attrs, $removed) = $rs->splice_attribute( $name, $list, $items );
      $rs->find_and_update( $name, $attrs );
   } );

   return $removed;
}

sub search {
   my ($self, $args) = @_; my ($lang, $path);

   $self->throw( q(eNoPath)     ) unless ($path = $args->{path});
   $self->throw( q(eNoLanguage) ) unless ($lang = $args->{lang});

   my $rs = $self->result_source->resultset( $path, $lang );

   return $self->_txn_do( $path, sub { $rs->search( $args->{criterion} ) } );
}

sub update {
   my ($self, $args) = @_;

   my ($rs, $name) = $self->_validate_params( $args );

   $self->_txn_do( $args->{path}, sub {
      $rs->find_and_update( $name, $args->{fields} );
   } );

   return $name;
}

# Private methods

sub _txn_do {
   my ($self, $path, $code_ref) = @_; my ($e, $res);

   my $key = q(txn:).$path->pathname;

   $self->lock->set( k => $key );

   if (wantarray) { @{ $res } = eval { $code_ref->() } }
   else { $res = eval { $code_ref->() } }

   if ($e = $self->catch) {
      $self->lock->reset( k => $key ); $self->throw( $e );
   }

   $self->lock->reset( k => $key );

   return wantarray ? @{ $res } : $res;
}

sub _validate_params {
   my ($self, $args) = @_; my ($name, $path, $rs);

   $self->throw( q(eNoPath) ) unless ($path = $args->{path});
   $self->throw( q(eNoName) ) unless ($name = $args->{name});

   $rs = $self->result_source->resultset( $path, $args->{lang} );

   return ($rs, $name);
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::File - Read and write configuration files

=head1 Version

0.1.$Revision: 407 $

=head1 Synopsis

   use CatalystX::Usul::File;

=head1 Description

Provides CRUD methods for read and write configuration files. For each
schema a subclass is defined that inherits from this class

=head1 Subroutines/Methods

=head2 new

Creates a new result source

=head2 add_to_attribute_list

   $c->model( q(Config::*) )->add_to_attribute_list( $args );

Add new items to an attribute list. The C<$args> hash requires these
keys; I<file> the name of the file to edit, I<name> the name of the
element to edit, I<list> the attribute of the named element containing
the list of existing items, I<req> the request object and I<field> the
field on the request object containing the list of new items

=head2 create

   $c->model( q(Config::*) )->create( $args );

Creates a new element. The C<$args> hash requires these keys; I<file>
the name of the file to edit, I<name> the name of the element to edit
and I<fields> is a hash containing the attributes of the new
element. Missing attributes are defaulted from the I<defaults>
attribute of the L<CatalystX::Usul::File::Schema> object

=head2 delete

   $c->model( q(Config::*) )->delete( $args );

Deletes an element

=head2 find

   $c->model( q(Config::*) )->find( $args );

=head2 get_list

   $c->model( q(Config::*) )->get_list( $args );

Retrieves the named element and a list of elements

=head2 load_files

=head2 remove_from_attribute_list

   $c->model( q(Config::*) )->remove_from_attribute_list( $args );

Removes items from an attribute list

=head2 search

   $c->model( q(Config::*) )->search( $args );

Search for elements that match the supplied criteria

=head2 update

   $c->model( q(Config::*) )->update( $args );

Updates the named element

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Usul>

=item L<CatalystX::Usul::File::ResultSource>

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
