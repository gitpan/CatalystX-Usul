# @(#)Ident: ;

package CatalystX::Usul::Model::Config;

use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use Class::Usul::File;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Constraints qw( Directory Path );
use CatalystX::Usul::Functions   qw( dos2unix escape_TT is_arrayref is_hashref
                                     throw unescape_TT );
use CatalystX::Usul::Moose;
use TryCatch;
use Config;

extends q(CatalystX::Usul::Model);
with    q(CatalystX::Usul::TraitFor::Model::StashHelper);
with    q(CatalystX::Usul::TraitFor::Model::QueryingRequest);

has 'classes'        => is => 'ro',   isa => HashRef, default => sub { {} };

has 'create_msg_key' => is => 'ro',   isa => SimpleStr, default => NUL;

has 'ctrldir'        => is => 'lazy', isa => Directory, coerce => TRUE,
   default           => sub { $_[ 0 ]->usul->config->ctrldir };

has 'default_ns'     => is => 'ro',   isa => NonEmptySimpleStr,
   default           => q(default);

has 'delete_msg_key' => is => 'ro',   isa => SimpleStr, default => NUL;

has '+domain_attributes' => default => sub { {
   encoding          => $_[ 0 ]->encoding, storage_class => q(Any) } };

has '+domain_class'  => default => q(CatalystX::Usul::Config);

has 'extension'      => is => 'lazy', isa => SimpleStr,
   default           => sub { $_[ 0 ]->usul->config->extension };

has 'fields'         => is => 'ro',   isa => ArrayRef[Str],
   default           => sub { [] };

has 'keys_attr'      => is => 'ro',   isa => SimpleStr, default => NUL;

has 'ns_key'         => is => 'ro',   isa => NonEmptySimpleStr,
   default           => q(namespace);

has 'phase'          => is => 'lazy', isa => PositiveOrZeroInt,
   default           => sub { $_[ 0 ]->usul->config->phase };

has 'prompts'        => is => 'ro',   isa => HashRef, default => sub { {} };

has 'table_data'     => is => 'ro',   isa => HashRef, default => sub { {} };

has 'typelist'       => is => 'ro',   isa => HashRef, default => sub { {} };

has 'update_msg_key' => is => 'ro',   isa => SimpleStr, default => NUL;


has '_config_paths'  => is => 'lazy', isa => ArrayRef[Path], init_arg => undef;

has '_file' => is => 'lazy', isa => FileClass,
   default  => sub { Class::Usul::File->new( builder => $_[ 0 ]->usul ) },
   handles  => [ qw(io) ], init_arg => undef, reader => 'file';

sub build_per_context_instance {
   my ($self, $c, @args) = @_; my $clone = $self->next::method( $c, @args );

   my $attr = { %{ $clone->domain_attributes } };

   $attr->{builder  } ||= $clone->usul;
   $attr->{lang     } ||= $c->stash->{language};
   $attr->{localedir} ||= $clone->usul->config->localedir;
   $attr->{storage_attributes}->{encoding} ||= $clone->encoding;
   $clone->domain_model( $clone->domain_class->new( $attr ) );
   return $clone;
}

sub config_form {
   my ($self, $ns, $name) = @_; my ($selected, $named_obj);

   my $s = $self->context->stash; my $newtag = $s->{newtag};

   $ns ||= $self->default_ns; $name ||= $newtag;

   try        { $selected = $self->list( $ns, $name ) }
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

   if ($selected) {
      $self->add_field( {
         default => $name,
         id      => q(config.attr),
         labels  => $selected->labels,
         name    => $self->keys_attr,
         values  => [ NUL, $newtag, @{ $selected->list } ] } );
      $named_obj =  $selected->result;
   }

   if ($name eq $newtag) { $self->add_field( { id => q(config.name) } ) }
   else { $self->add_hidden( q(name), $name ) }

   $self->group_fields( { id => "${form}.select" } );

   $named_obj or return; my @attrs = @{ $self->fields };

   scalar @attrs or @attrs = @{ $self->_source->attributes };

   $self->_add_field( $form, $_, $named_obj->$_ ) for (@attrs);

   $self->group_fields( { id => "${form}.edit" } );
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
   return $_[ 0 ]->_resultset( $_[ 1 ] )->find( { name => $_[ 2 ] } );
}

sub list {
   return $_[ 0 ]->_resultset( $_[ 1 ] )->list( { name => $_[ 2 ] || NUL } );
}

sub load {
   my ($self, @files) = @_;

   return $self->domain_model->load( map { $self->_get_path( $_ ) } @files );
}

sub load_per_request_config {
   # Read the config from the cached copy in the domain model
   my ($self, $ns) = @_; my $c = $self->context;

   my @paths = @{ $self->_config_paths };

   # Add a controller specific file to the list
   $ns and push @paths, $self->_get_path( $ns );
   # Copy the config to the stash
   $c->stash( %{ $self->domain_model->load( @paths ) } );

   # TODO: Raise the "level" of the globals in the stash. Stop doing this
   my $globals = delete $c->stash->{globals} || {};

   $c->stash( map { $_ => $globals->{ $_ }->{value} } keys %{ $globals } );

   return;
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
   return $_[ 0 ]->_resultset( $_[ 1 ] )->search( $_[ 2 ] );
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

   $name = $self->_resultset( $ns )->update( $args )
      and $self->add_result_msg( $self->update_msg_key, [ $ns, $name ] );

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
   my ($self, $form, $attr, $value) = @_; state $clear;

   my $params = { id => "${form}.${attr}", stepno => -1 };
   my $type   = $params->{type} = $self->_get_widget_type( $attr );
   my $field  = (lc $attr); $field =~ s{ _ }{ }gmx;
   my $prompt = defined $self->prompts->{ $attr }
              ? $self->prompts->{ $attr } : q(defTextPrompt);

   $clear and $params->{clear} = $clear;
   $params->{prompt} = $self->loc( $prompt, $field );
   $self->classes and exists $self->classes->{ $attr }
      and $params->{class} = $self->classes->{ $attr };

   if ($type eq q(table)) {
      $params->{data   } = $self->_get_table_object( $attr, $value );
   }
   elsif ($type eq q(freelist) or $type eq q(popupmenu)) {
      $params->{values } = [ map { escape_TT $_ } @{ $value } ];
   }
   else {
      $params->{default} = (is_arrayref $value)
                         ? join "\n", map { escape_TT $_ } @{ $value }
                         : escape_TT $value;
   }

   $self->add_field( $params );
   $clear = q(left);
   return;
}

sub _build__config_paths {
   my $self  = shift; my $phase = $self->phase;

   my @files = ( q(os_).$Config{osname}, "phase${phase}", q(default), );

   return [ grep { $_->exists } map { $self->_get_path( $_ ) } @files ];
}

sub _get_field_type {
   my ($self, $attr) = @_; my $def = $self->_source->defaults || {};

   my $type = exists $def->{ $attr }
            ? ref    $def->{ $attr } || q(SCALAR) : q(SCALAR);

   $type eq ARRAY and $self->_get_widget_type( $attr ) eq q(table)
      and $type = HASH;

   return $type;
}

sub _get_path {
   my ($self, $name) = @_; $name or throw 'Config file name not specified';

   return $self->io( [ $self->ctrldir, $name.$self->extension ] );
}

sub _get_table_object {
   my ($self, $attr, $values) = @_;

   my $table = { %{ $self->table_data->{ $attr } } };

   if (is_arrayref $values) {
      push @{ $table->{values} }, map { { text => escape_TT $_ } } @{ $values };
   }
   elsif (is_hashref $values) {
      for my $key (sort keys %{ $values }) {
         my $ref = { name => $key }; my $value = $values->{ $key };

         for (grep { $_ ne q(name) } @{ $table->{fields} }) {
            $ref->{ $_ } = escape_TT $value->{ $_ };
         }

         push @{ $table->{values} }, $ref;
      }
   }

   $table->{count} = @{ $table->{values} || [] };

   return $self->table_class->new( $table );
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

   my $form  = $self->context->stash->{form}->{name};
   my @attrs = @{ $self->fields };

   scalar @attrs or @attrs = @{ $self->_source->attributes };

   for my $attr (@attrs) {
      my $type = $self->_get_field_type( $attr );

      if ($type eq HASH) {
         my $fields = $self->table_data->{ $attr }->{fields} || [];

         $args->{ $attr } = $self->query_hash( $attr, $fields );
      }
      elsif ($type eq ARRAY) {
         my @attr_list = grep { defined && length }
                          map { __filter_value( $_ ) }
                             @{ $self->query_array( $attr ) };

         $args->{ $attr } = @attr_list > 0 ? [ @attr_list ] : undef;
      }
      else {
         my $qv = $args->{ $attr } || $self->query_value( $attr );

         $args->{ $attr } = __filter_value( $qv );
      }
   }

   return $args;
}

sub _resultset {
   my ($self, $ns) = @_;

   my $dm = $self->domain_model; $dm->path( $self->_get_path( $ns ) );

   my $rs = $dm->resultset( $self->keys_attr ) or throw 'No resultset object';

   return $rs;
}

sub _source {
   my $self = shift; my $dm = $self->domain_model;

   my $src  = $dm->source( $self->keys_attr ) or throw 'No source object';

   return $src;
}

# Private functions

sub __filter_value {
   my $y = unescape_TT dos2unix( $_[ 0 ] ); return length $y ? $y : undef;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config - Read and write configuration files

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   package YourApp;

   use Catalyst qw(ConfigComponents...);

   __PACKAGE__->config(
     'Model::Config'   => {
        parent_classes => q(CatalystX::Usul::Model::Config) }, );

=head1 Description

Provides CRUD methods for read and write configuration files. For each
schema a subclass is defined that inherits from this class

=head1 Configuration and Environment

Defines the following list of attributes;

=over 3

=item C<classes>

A hash ref which defaults to an empty ref. Keyed by field name its values are
CSS class names which are applied to the field's input element

=item C<create_msg_key>

A simple string which defaults to C<NUL>. The message that is added to the
result div when a new configuration element is created

=item C<ctrldir>

Defaults to C<< $self->usul->config->ctrldir >> the location of the
configuration files

=item C<default_ns>

A non empty simple string which defaults to C<default>. The default
namespace

=item C<delete_msg_key>

A simple string which defaults to C<NUL>. The message that is added to the
result div when a configuration element is deleted

=item C<domain_attributes>

Overrides the base class default with C<{ storage_class => q(Any) }>. Passed
to the domain class each time an instance is created

=item C<domain_class>

Overrides the base class default with C<CatalystX::Usul::Config>. The
classname of the domain model

=item C<extension>

Defaults to C<< $self->usul->config->extension >> the default filename
extension for configuration files

=item C<fields>

An array ref of strings which defaults to the empty list. If empty the
domain models source attributes are used instead. It is the list of
fields used on the form for the configuration element

=item C<keys_attr>

A simple string which defaults to C<NUL>. The attribute name that is used
as the key for the configuration element

=item C<ns_key>

A non empty simple string which defaults to C<namespace>. A stash key whose
stashed value is a list of controller namespaces

=item C<phase>

Defaults to C<< $self->usul->config->phase >> the type number for this
installation

=item C<prompts>

A hash ref of prompts used to override the default one on a per field basis.
Keyed by attribute name

=item C<table_class>

A loadable class which defaults to C<Class::Usul::Response::Table>. The
class of the table object passed to L<HTML::FormWidgets> when the
configuration element contains a table

=item C<table_data>

A hash ref which defaults to an empty hash. The data for a table object

=item C<typelist>

A hash ref which defaults to an empty hash. The list of type for each
field

=item C<update_msg_key>

A simple string which defaults to C<NUL>. The message that is added to the
result div when a configuration element is updated

=back

=head1 Subroutines/Methods

=head2 build_per_context_instance

Creates a new C<domain_class> object and makes a copy of the request
object

=head2 config_form

   $self->config_form( $namespace, $config_element_name );

Creates the form to edit a configuration element

=head2 create

   $config_element_name = $self->create( $namespace, $args );

Creates a new element. The C<$args> hash requires these keys; C<file>
the name of the file to edit, C<name> the name of the element to edit
and C<fields> is a hash containing the attributes of the new
element

=head2 create_or_update

   $config_element_name = $self->create_or_update( $namespace, $args );

Creates a new element if one does not exist or updates the existing one
if it does exist

=head2 delete

   $self->delete( $args );

Deletes an element

=head2 find

   $config_object = $self->find( $namspace, $name );

Returns the requested configuration element if it exists

=head2 list

   $selected_list_and_named_element = $self->list( $namespace, $name );

Retrieves the named element and a list of elements

=head2 load

   $config = $self->load( @{ $files } );

Loads the required configuration files. Returns a hash ref

=head2 load_per_request_config

   $self->load_per_request_config;

Loads the config data for the current request. The data is split
across six files; one for OS dependant data, one for this phase (live,
test, development etc.), default data and language dependant default
data, data for the current controller and it's language dependant
data. This information is cached

Data in the C<globals> attribute is raised to the top level of the
stash and the C<globals> attribute deleted

=head2 push_attribute

   $count = $self->push_attribute( $namespace, $args );

Add new items to an attribute list. The C<$args> hash requires these
keys; C<file> the name of the file to edit, C<name> the name of the
element to edit, C<list> the attribute of the named element containing
the list of existing items, C<req> the request object and C<field> the
field on the request object containing the list of new items

=head2 search

   @elements = $self->search( $args );

Searches the given file for elements matching the given criteria. Returns an
array of element objects

=head2 splice_attribute

   $count = $self->splice_attribute( $namespace, $args );

Removes items from an attribute list

=head2 update

   $config_element_name = $self->update( $namespace, $args );

Updates the named element

=head2 update_list

   $bool = $self->update_list( $namespace, $args );

Will push/splice attributes to/from the selected list

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::TraitFor::Model::StashHelper>

=item L<CatalystX::Usul::TraitFor::Model::QueryingRequest>

=item L<CatalystX::Usul::Moose>

=item L<Class::Usul::File>

=item L<Class::Usul::Response::Table>

=item L<Config>

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
