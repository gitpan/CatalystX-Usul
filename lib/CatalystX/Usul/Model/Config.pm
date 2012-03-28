# @(#)$Id: Config.pm 1097 2012-01-28 23:31:29Z pjf $

package CatalystX::Usul::Model::Config;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1097 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions
    qw(escape_TT is_arrayref is_hashref merge_attributes throw unescape_TT);
use CatalystX::Usul::Config;
use CatalystX::Usul::Table;
use MRO::Compat;
use Scalar::Util qw(blessed);
use TryCatch;

__PACKAGE__->config( ctrldir      => NUL,
                     default_ns   => q(default),
                     domain_class => q(CatalystX::Usul::Config),
                     ns_key       => q(namespace),
                     localedir    => NUL, );

__PACKAGE__->mk_accessors( qw(classes create_msg_key ctrldir default_ns
                              delete_msg_key fields keys_attr localedir
                              ns_key table_data typelist update_msg_key) );

sub COMPONENT {
   my ($class, $app, $attrs) = @_; my $ac = $app->config;

   merge_attributes $attrs, $ac, $class->config, [ qw(ctrldir localedir) ];

   return $class->next::method( $app, $attrs );
}

sub build_per_context_instance {
   my ($self, $c, @rest) = @_;

   my $new   = $self->next::method( $c, @rest );
   my $attrs = { %{ $new->domain_attributes || {} },
                 ioc_obj   => $new,
                 lang      => $c->stash->{lang},
                 localedir => $self->localedir, };

   $new->domain_model( $new->domain_class->new( $attrs ) );

   return $new;
}

sub config_form {
   my ($self, $ns, $name) = @_; my $s = $self->context->stash; my $labels = {};

   my $newtag = $s->{newtag}; my $names = [ NUL, $newtag ]; my $result;

   $ns ||= $self->default_ns; $name ||= $newtag;

   try {
      my $config_obj = $self->list( $ns, $name );

      push @{ $names }, @{ $config_obj->list };
      $labels = $config_obj->labels; $result = $config_obj->result;
   }
   catch ($e) { $self->add_error( $e ) }

   my $first_fld = $name eq $newtag ? q(config.name) : q(config.attr);
   my $form      = $s->{form}->{name}; $s->{key_attr} = $self->keys_attr;
   my $spaces    = [ NUL, $self->default_ns,
                     sort keys %{ $s->{ $self->ns_key } } ];

   $self->clear_form ( { firstfld => $first_fld } );
   $self->add_buttons( $name eq $newtag ? q(Insert) : qw(Save Delete) );
   $self->add_field  ( { default  => $ns,
                         id       => q(config.).$self->ns_key,
                         values   => $spaces } );
   $self->add_field  ( { default  => $name,
                         id       => q(config.attr),
                         labels   => $labels,
                         name     => $s->{key_attr},
                         values   => $names } );

   if ($name eq $newtag) { $self->add_field( { id => q(config.name) } ) }
   else { $self->add_hidden( q(name), $name ) }

   $self->group_fields( { id => $form.q(.select) } );

   $result or return; my $clear = NUL;

   for my $attr (@{ $self->fields || $self->_source->attributes }) {
      $self->_add_field( $form, $clear, $attr, $result->$attr );
      $clear = q(left);
   }

   $self->group_fields( { id => $form.q(.edit) } );
   return;
}

sub create {
   my ($self, $ns, $args) = @_;

   my $name = $self->_resultset( $ns )->create( $args );

   $self->add_result_msg( $self->create_msg_key, [ $ns, $name ] );

   return $name;
}

sub create_or_update {
   my ($self, $ns, $args) = @_; $args ||= {};

   my $key    = $self->keys_attr;
   my $s      = $self->context->stash;
   my $val    = $self->query_value( $key ) || NUL;
   my $method = ! $val || $val eq $s->{newtag} ? q(create) : q(update);
   my $name   = $method eq q(create) ? $self->query_value( q(name) ) : $val;

   $args->{name} ||= $name;
   $args = $self->check_form( $self->_query_form( $args ) );

   return $self->$method( $ns, $args );
}

sub delete {
   my ($self, $ns, $name) = @_;

   my $args = { name => $name || $self->query_value( $self->keys_attr ) };

   $name = $self->_resultset( $ns )->delete( $args );
   $self->add_result_msg( $self->delete_msg_key, [ $ns, $name ] );
   return;
}

sub find {
   my ($self, $ns, $name) = @_;

   return $self->_resultset( $ns )->find( { name => $name } );
}

sub list {
   my ($self, $ns, $name) = @_;

   return $self->_resultset( $ns )->list( { name => $name || NUL } );
}

sub load {
   my ($self, @files) = @_;

   return $self->domain_model->load( map { $self->_get_path( $_ ) } @files );
}

sub push_attribute {
   my ($self, $ns, $args) = @_; my $count = 0;

   my $added    = $self->_resultset( $ns )->push( $args ) || [];

   not ($count  = @{ $added }) and return 0;

   my $msg_args = [ $ns.q( / ).$args->{name}, (join q(, ), @{ $added }) ];

   $self->add_result_msg( $args->{msgs}->{added}, $msg_args );

   return $count;
}

sub search {
   my ($self, $ns, $where) = @_;

   return $self->_resultset( $ns )->search( $where );
}

sub splice_attribute {
   my ($self, $ns, $args) = @_; my $count;

   my $removed  = $self->_resultset( $ns )->splice( $args ) || [];

   not ($count  = @{ $removed }) and return 0;

   my $msg_args = [ $ns.q( / ).$args->{name}, (join q(, ), @{ $removed }) ];

   $self->add_result_msg( $args->{msgs}->{deleted}, $msg_args );

   return $count;
}

sub update {
   my ($self, $ns, $args) = @_; my $name;

   if ($name = $self->_resultset( $ns )->update( $args ) ) {
      $self->add_result_msg( $self->update_msg_key, [ $ns, $name ] );
   }

   return $name;
}

sub update_list {
   my ($self, $ns, $args) = @_; my $count = 0;

   return $self->update_group_membership( {
      add_method    => sub { $self->push_attribute( $ns, @_ ) },
      delete_method => sub { $self->splice_attribute( $ns, @_ ) },
      field         => $args->{field},
      method_args   => {
         name       => $args->{name},
         list       => $args->{list},
         msgs       => $args->{msgs} },
   } );
}

# Private methods

sub _add_field {
   my ($self, $form, $clear, $attr, $value) = @_;

   my $def_prompt = $self->loc( q(defTextPrompt) );
   my $prompt     = $def_prompt.(lc $attr); $prompt =~ s{ _ }{ }gmx;
   my $params     = { clear => $clear, id => $form.q(.).$attr, stepno => -1 };
   my $type       = $params->{type} = $self->_get_widget_type( $attr );

   $params->{prompt} = $prompt;

   $self->classes and exists $self->classes->{ $attr }
      and $params->{class} = $self->classes->{ $attr };

   if ($type eq q(table)) {
       $params->{data} = $self->_get_table_data( $attr, $value );
   }
   elsif ($type eq q(freelist) or $type eq q(popupmenu)) {
      $params->{values} = [ map { escape_TT $_ } @{ $value } ];
   }
   else {
      $params->{default} = (is_arrayref $value)
                         ? join "\n", map { escape_TT $_ } @{ $value }
                         : escape_TT $value;
   }

   $self->add_field( $params );
   return;
}

sub _get_field_type {
   my ($self, $attr) = @_; my $def = $self->_source->defaults || {};

   return exists $def->{ $attr } ? ref $def->{ $attr } || q(SCALAR) : q(SCALAR);
}

sub _get_path {
   my ($self, $name) = @_; my $s = $self->context->stash;

   $s->{leader} = blessed $self; $name or throw 'File name not specified';

   my $extn = $self->domain_model->storage->extn || NUL;

   return $self->io( [ $self->ctrldir, $name.$extn ] );
}

sub _get_table_data {
   my ($self, $attr, $values) = @_;

   my $data = CatalystX::Usul::Table->new( $self->table_data->{ $attr } );

   if (is_arrayref $values) {
      push @{ $data->{values} }, map { { text => escape_TT $_ } } @{ $values };
   }
   elsif (is_hashref $values) {
      for my $key (sort keys %{ $values }) {
         my $ref = { name => $key }; my $value = $values->{ $key };

         for (grep { $_ ne q(name) } @{ $data->{flds} }) {
            $ref->{ $_ } = escape_TT $value->{ $_ };
         }

         push @{ $data->{values} }, $ref;
      }
   }

   $data->{count} = @{ $data->{values} };

   return $data;
}

sub _get_widget_type {
   my ($self, $attr) = @_; my $list = $self->typelist || {};

   my $type = $list->{ $attr } || q(textfield);
   my $map  = { date  => q(textfield),
                money => q(textfield), numeric => q(textfield) };

   return exists $map->{ $type } ? $map->{ $type } : $type;
}

sub _query_form {
   my ($self, $args) = @_; $args ||= {};

   my $form = $self->context->stash->{form}->{name};

   for my $attr (@{ $self->fields || $self->_source->attributes }) {
      my $type = $self->_get_field_type( $attr );

      if ($type eq HASH) { $args->{ $attr } = $self->_query_hash( $attr ) }
      elsif ($type eq ARRAY) {
         my @attr_list = grep { length }
                          map { unescape_TT __dos2unix( $_ ) }
                             @{ $self->query_array( $attr ) };

         $args->{ $attr } = @attr_list > 0 ? [ @attr_list ] : undef;
      }
      else {
         my $qv = $args->{ $attr } || $self->query_value( $attr );
            $qv = unescape_TT __dos2unix( $qv );

         $args->{ $attr } = length $qv ? $qv : undef;
      }
   }

   return $args;
}

sub _query_hash {
   my ($self, $attr) = @_;

   my $nrows  = $self->query_value( "_${attr}_nrows" ) || 0;
   my $fields = $self->table_data->{ $attr }->{flds};
   my $ncols  = @{ $fields };
   my $result = $ncols > 1 ? {} : [];
   my $r_no   = 0;

   while ($r_no < $nrows) {
      my $c_no = 0; my $prefix = "${attr}_${r_no}_";

      if (my $key = $self->query_value( $prefix.$c_no )) {
         if ($ncols > 1) {
            for my $field (@{ $fields }) {
               if ($c_no > 0) {
                  my $qv = $self->query_value( $prefix.$c_no );
                     $qv = unescape_TT __dos2unix( $qv );

                  $result->{ $key }->{ $field } = length $qv ? $qv : undef;
               }

               $c_no++;
            }
         }
         else { push @{ $result }, unescape_TT __dos2unix( $key ) }
      }

      $r_no++;
   }

   return $result;
}

sub _resultset {
   my ($self, $ns) = @_;

   my $dm = $self->domain_model; $dm->path( $self->_get_path( $ns ) );

   return $dm->resultset( $self->keys_attr ) or throw 'No resultset object';
}

sub _source {
   my $self = shift; my $dm = $self->domain_model;

   return $dm->source( $self->keys_attr ) or throw 'No source object';
}

# Private functions

sub __dos2unix {
   (my $y = shift || NUL) =~ s{ [\r][\n] }{\n}gmsx; return $y;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config - Read and write configuration files

=head1 Version

0.4.$Revision: 1097 $

=head1 Synopsis

   use base qw(CatalystX::Usul::Model::Config);

=head1 Description

Provides CRUD methods for read and write configuration files. For each
schema a subclass is defined that inherits from this class

=head1 Subroutines/Methods

=head2 COMPONENT

The constructor sets up the C<ctrldir> attribute which acts as a default
directory if one is not supplied in the file name

=head2 build_per_context_instance

Creates a new L<CatalystX::Usul::File> object and takes a copy of the
stashed language

=head2 config_form

   $c->model( q(Config::*) )->config_form;

Creates the form to edit an element

=head2 create

Creates a new element. The C<$args> hash requires these keys; I<file>
the name of the file to edit, I<name> the name of the element to edit
and I<fields> is a hash containing the attributes of the new
element. Missing attributes are defaulted from the I<defaults>
attribute of the L<CatalystX::Usul::File::Schema> object

=head2 create_or_update

   $c->model( q(Config::*) )->create_or_update( $args );

Creates a new element if one does not exist or updates the existing one
if it does exist

=head2 delete

   $c->model( q(Config::*) )->delete( $args );

Deletes an element

=head2 find

   $c->model( q(Config::*) )->find( $ns, $name );

=head2 list

   $c->model( q(Config::*) )->list( $ns, $name );

Retrieves the named element and a list of elements

=head2 load

   $config = $c->model( q(Config) )->load( @{ $files } );

Loads the required configuration files. Returns a hash ref

=head2 push_attribute

   $c->model( q(Config::*) )->push_attribute( $args );

Add new items to an attribute list. The C<$args> hash requires these
keys; I<file> the name of the file to edit, I<name> the name of the
element to edit, I<list> the attribute of the named element containing
the list of existing items, I<req> the request object and I<field> the
field on the request object containing the list of new items

=head2 search

   @elements = $c->model( q(Config::*) )->search( $args );

Searches the given file for elements matching the given criteria. Returns an
array of L<element|CatalystX::Usul::File::Element> objects

=head2 splice_attribute

   $c->model( q(Config::*) )->splice_attribute( $args );

Removes items from an attribute list

=head2 update

Updates the named element

=head2 update_list

   $bool = $c->model( q(Config::*) )->update_list( $namespace, $args );

Calls
L<update_group_membership|CatalystX::Usul::Plugin::Model::StashHelper/update_group_membership>
which will push/splice attributes to/from the selected list

=head2 _resultset

Return a L<File::DataClass::ResultSet> for the supplied file

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::File::ResultSource>

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::Table>

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
