# @(#)$Id: Config.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::Model::Config;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model);

use CatalystX::Usul::File;
use CatalystX::Usul::Table;
use Class::C3;

my $NUL = q();
my $SPC = q( );

__PACKAGE__->config( default_level => q(default) );

__PACKAGE__->mk_accessors( qw(create_msg_key ctrldir default_level
                              delete_msg_key domain_model keys_attr lang
                              schema_attributes table_data typelist
                              update_msg_key) );

sub new {
   my ($self, $app, @rest) = @_;

   my $new = $self->next::method( $app, @rest );

   $new->ctrldir( $new->ctrldir || $app->config->{ctrldir} || $NUL );

   return $new;
}

sub build_per_context_instance {
   my ($self, $c, @rest) = @_;

   my $new   = $self->next::method( $c, @rest);
   my $attrs = { schema_attributes => $new->schema_attributes };

   $new->domain_model( CatalystX::Usul::File->new( $c, $attrs ) );
   $new->lang        ( $c->stash->{lang} || q(en) );

   return $new;
}

sub add_to_attribute_list {
   my ($self, $args) = @_;

   $args->{path } = $self->_get_path( $args->{file} );
   $args->{items} = $self->query_array( $args->{field} );

   $args->{lang } = $self->lang if ($self->lang);

   my $added    = $self->domain_model->add_to_attribute_list( $args );
   my $aname    = $args->{file}.q( / ).$args->{name};
   my $msg_args = [ $aname, (join q(, ), @{ $added }) ];

   $self->add_result_msg( $args->{msg}, $msg_args );
   return;
}

sub config_form {
   my ($self, $level, $name) = @_; my $e;

   my $s = $self->context->stash; my $newtag = $s->{newtag};

   $level ||= $self->default_level; $name ||= $newtag;

   my $config_ref = eval {
      my $args = { file => $level, lang => $self->lang,
                   name => $name,  path => $self->_get_path( $level ) };

      $self->domain_model->get_list( $args );
   };

   return $self->add_error( $e ) if ($e = $self->catch);

   my $list       = $config_ref->list; unshift @{ $list }, $NUL, $newtag;
   my $first_fld  = $name eq $newtag ? q(config.name) : q(config.attr);
   my $levels     = [ $self->default_level, sort keys %{ $s->{levels} } ];
   my $schema     = $self->domain_model->result_source->schema;
   my $attr       = $s->{key_attr} = $self->keys_attr;
   my $def_prompt = $self->loc( q(defTextPrompt) );
   my $form       = $s->{form}->{name};
   my $step       = 1;

   $s->{pwidth}  -= 10;
   $self->clear_form(   { firstfld => $first_fld } ); my $nitems = 0;
   $self->add_field(    { default  => $level,
                          id       => q(config.level),
                          stepno   => 0,
                          values   => $levels } ); $nitems++;
   $self->add_field(    { default  => $name,
                          id       => q(config.attr),
                          name     => $attr,
                          stepno   => 0,
                          values   => $list } ); $nitems++;

   if ($name eq $newtag) {
      $self->add_field( { id       => q(config.name),
                          stepno   => 0 } ); $nitems++;
   }
   else { $self->add_hidden( q(name), $name ) }

   $self->group_fields( { id       => $form.q(.select),
                          nitems   => $nitems } ); $nitems = 0;

   if ($name eq $newtag) { $self->add_buttons( q(Insert) ) }
   else { $self->add_buttons( qw(Save Delete) ) }

   for my $attr (@{ $schema->attributes }) {
      my $field = $config_ref->element->$attr;
      my $clear = $nitems > 0 ? q(left) : $NUL;

      if (ref $schema->defaults->{ $attr } eq q(HASH)) {
         my $data = CatalystX::Usul::Table->new
            ( $self->table_data->{ $attr } );
         my $count = $data->{count} = 0;

         $data->{values} = [];

         if (ref $field eq q(HASH)) {
            for my $key (sort keys %{ $field }) {
               my $ref = { name => $key }; my $value = $field->{ $key };

               for (grep { $_ ne q(name) } @{ $data->{flds} }) {
                  $ref->{ $_ } = $self->escape_TT( $value->{ $_ } );
               }

               push @{ $data->{values} }, $ref;
               $count++;
            }
         }

         $data->{count} = $count;
         $self->add_field( { clear   => $clear,
                             data    => $data,
                             id      => $form.q(.).$attr,
                             stepno  => $step++ } ); $nitems++;
      }
      else {
         my $default = $self->escape_TT( $field );
         my $prompt  = lc $attr; $prompt =~ s{ _ }{ }gmx;
         my $type    = $self->typelist->{ $attr } || q(textfield);
         my $width   = $type eq q(textarea) ? 38 : 40;

         $self->add_field( { clear   => $clear,
                             default => $default,
                             id      => $form.q(.).$attr,
                             prompt  => $def_prompt.$prompt,
                             stepno  => $step++,
                             type    => $type,
                             width   => $width } ); $nitems++;
      }
   }

   $self->group_fields( { id => $form.q(.edit), nitems => $nitems } );

   return;
}

sub create {
   my ($self, $args) = @_;

   $args->{path  } = $self->_get_path( $args->{file} );
   $args->{fields} = $self->check_form( $args->{fields} || {} );

   $args->{lang  } = $self->lang  if ($self->lang);

   my $name = $self->domain_model->create( $args );

   $self->add_result_msg( $self->create_msg_key, [ $args->{file}, $name ] );
   return $name;
}

sub create_or_update {
   my ($self, $args) = @_; my ($type, $val);

   my $schema = $self->domain_model->result_source->schema;

   for my $attr (@{ $schema->attributes }) {
      if ($type = $schema->defaults->{ $attr } and ref $type eq q(HASH)) {
         my $key    = $self->table_data->{ $attr }->{flds}->[0];
         my $nrows  = $self->query_value( $attr.q(_nrows) );
         my $count  = undef;
         my $suffix = $NUL;

         while (!$count || $count <= $nrows) {
            if ($val = $self->query_value( $attr.q(_).$key.$suffix )) {
               for my $field (@{ $self->table_data->{ $attr }->{flds} }) {
                  next if ($field eq $key);

                  my $qv = $self->query_value( $attr.q(_).$field.$suffix );

                  if (defined $qv) {
                     $args->{fields}->{ $attr }->{ $val }->{ $field }
                        = $self->unescape_TT( $qv );
                  }
               }
            }

            $count  = defined $count ? $count + 1 : 0;
            $suffix = $count;
         }
      }
      elsif ($type and ref $type eq q(ARRAY)) {
         $args->{fields}->{ $attr } = [ map { $self->unescape_TT( $_ ) }
                                           @{ $self->query_array( $attr ) } ];
      }
      elsif (defined ($val = $self->query_value( $attr ))) {
         $args->{fields}->{ $attr } = $self->unescape_TT( $val );
      }
   }

   my $query_key = $self->query_value( $self->keys_attr ) || $NUL;
   my $newtag    = $self->context->stash->{newtag};

   return $self->create( $args ) if ($query_key eq $newtag);

   return $self->update( $args );
}

sub delete {
   my ($self, $args) = @_;

   $args->{path} = $self->_get_path( $args->{file} );

   $args->{lang} = $self->lang if ($self->lang);

   my $name = $self->domain_model->delete( $args );

   $self->add_result_msg( $self->delete_msg_key, [ $args->{file}, $name ] );
   return;
}

sub find {
   my ($self, $file, $name) = @_;

   my $args = { file => $file,
                name => $name,
                path => $self->_get_path( $file ) };

   $args->{lang} = $self->lang if ($self->lang);

   return $self->domain_model->find( $args );
}

sub get_list {
   my ($self, $file, $name) = @_;

   my $args = { file => $file,
                name => $name || $NUL,
                path => $self->_get_path( $file ) };

   $args->{lang} = $self->lang if ($self->lang);

   return $self->domain_model->get_list( $args );
}

sub load_files {
   my ($self, @files) = @_;

   my @paths = map { $self->_get_path( $_ ) } @files;

   return $self->domain_model->load_files( @paths );
}

sub remove_from_attribute_list {
   my ($self, $args) = @_;

   $args->{path } = $self->_get_path( $args->{file} );
   $args->{items} = $self->query_array( $args->{field} );

   $args->{lang } = $self->lang if ($self->lang);

   my $removed  = $self->domain_model->remove_from_attribute_list( $args );
   my $aname    = $args->{file}.q( / ).$args->{name};
   my $msg_args = [ $aname, (join q(, ), @{ $removed }) ];

   $self->add_result_msg( $args->{msg}, $msg_args );
   return;
}

sub search {
   my ($self, $file, $criterion) = @_;

   my $args = { criterion => $criterion,
                path      => $self->_get_path( $file ) };

   $args->{lang} = $self->lang if ($self->lang);

   return $self->domain_model->search( $args );
}

sub update {
   my ($self, $args) = @_;

   $args->{path  } = $self->_get_path( $args->{file} );
   $args->{fields} = $self->check_form( $args->{fields} || {} );

   $args->{lang  } = $self->lang if ($self->lang);

   my $name = $self->domain_model->update( $args );

   $self->add_result_msg( $self->update_msg_key, [ $args->{file}, $name ] );
   return $name;
}

# Private methods

sub _get_path {
   my ($self, $path, $args) = @_; $args ||= {};

   $self->throw( 'No file path specified' ) unless ($path);

   return $path if (ref $path);

   return $self->io( $path ) if (-f $path);

   $path = $self->catfile( $self->ctrldir, $path.q(.xml) );

   # TODO: Test for a permission error rather than returning undef
   return $self->io( $path ) if (-f $path or $args->{ignore_error});

   my $msg = $self->loc( 'File [_1] not found', $path );

   $self->log_info( (ref $self).$SPC.$msg );

   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config - Read and write configuration files

=head1 Version

0.1.$Revision: 562 $

=head1 Synopsis

   use base qw(CatalystX::Usul::Model::Config);

=head1 Description

Provides CRUD methods for read and write configuration files. For each
schema a subclass is defined that inherits from this class

=head1 Subroutines/Methods

=head2 new

The constructor sets up the C<ctrldir> attribute which acts as a default
directory if one is not supplied in the file name

=head2 build_per_context_instance

Creates a new L<CatalystX::Usul::File> object and takes a copy of the
stashed language

=head2 config_form

   $c->model( q(Config::*) )->config_form;

Creates the form to edit an element

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

=head2 create_or_update

   $c->model( q(Config::*) )->create_or_update( $args );

Creates a new element if one does not exist or updates the existing one
if it does exist

=head2 delete

   $c->model( q(Config::*) )->delete( $args );

Deletes an element

=head2 find

   $c->model( q(Config::*) )->find( $file, $name );

=head2 get_list

   $c->model( q(Config::*) )->get_list( $file, $name );

Retrieves the named element and a list of elements

=head2 load_files

   $config = eval { $c->model( q(Config) )->load_files( @{ $files } ) };

Loads the required configuration files. Returns a hash ref

=head2 remove_from_attribute_list

   $c->model( q(Config::*) )->remove_from_attribute_list( $args );

Removes items from an attribute list

=head2 search

   @elements = $c->model( q(Config::*) )->search( $args );

Searches the given file for elements matching the given criteria. Returns an
array of L<element|CatalystX::Usul::File::Element> objects

=head2 update

   $c->model( q(Config::*) )->update( $args );

Updates the named element

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
