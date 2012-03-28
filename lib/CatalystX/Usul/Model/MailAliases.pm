# @(#)$Id: MailAliases.pm 1139 2012-03-28 23:49:18Z pjf $

package CatalystX::Usul::Model::MailAliases;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1139 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(throw);
use File::MailAlias;
use MRO::Compat;
use TryCatch;

__PACKAGE__->mk_accessors( qw(user_model) );

sub build_per_context_instance {
   my ($self, $c, @rest) = @_;

   my $new   = $self->next::method( $c, @rest );
   my $attrs = { %{ $new->domain_attributes || {} } };

   $attrs->{ioc_obj} = $new;
   $attrs->{path   } = $c->config->{aliases_path};

   $new->domain_model( File::MailAlias->new( $attrs ) );
   $new->user_model  ( $c->model( q(UsersUnix) ) );

   return $new;
}

sub create_or_update {
   my $self = shift;
   my $name = $self->query_value( q(name) )
      or throw 'Alias name not specified';

  (my $recipients = $self->query_value( q(recipients) )) =~ s{ \s+ }{ }gmsx;

   my $s      = $self->context->stash;
   my $fields = { name       => $name,
                  alias_name => $name,
                  comment    => $self->query_array( q(comment) ) || [],
                  owner      => $s->{user},
                  recipients => [ split SPC, $recipients ] };
   my $alias  = $self->query_value( q(alias) ) || NUL;
   my $key    = $alias eq $s->{newtag}
              ? 'Alias [_1] created' : 'Alias [_1] updated';
   my $method = $alias eq $s->{newtag} ? q(create) : q(update);
   my $out;

   ($name, $out) = $self->domain_model->$method( $self->check_form( $fields ) );
   $self->add_result_msg( $key, $name );
   $self->add_result( $out );
   $self->user_model->domain_model->cache->{dirty} = TRUE;
   return $name;
}

sub delete {
   my $self  = shift;
   my $alias = $self->query_value( q(alias) )
      or throw 'Alias name not specified';
   my ($name, $out) = $self->domain_model->delete( { name => $alias } );

   $self->add_result_msg( 'Alias [_1] deleted', $name );
   $self->add_result( $out );
   $self->user_model->domain_model->cache->{dirty} = TRUE;
   return;
}

sub mail_aliases_form {
   my ($self, $alias) = @_; my $data;

   # Retrieve data from model
   try        { $data = $self->domain_model->list( $alias ) }
   catch ($e) { return $self->add_error( $e ) }

   my $s       = $self->context->stash;
   my $form    = $s->{form}->{name}; $s->{pwidth} -= 20;
   my $aliases = [ NUL, $s->{newtag}, @{ $data->list } ];
   my $element = $data->result;

   # Add HTML elements items to form
   $self->clear_form( { firstfld => $form.'.alias' } );
   $self->add_field(  { default  => $alias,
                        id       => $form.'.alias',
                        values   => $aliases } );

   if ($data->found and $element->owner) {
      $s->{owner  } = $element->owner;
      $s->{created} = $element->created;
      $self->add_field( { id => $form.'.note' } );
   }

   $self->group_fields( { id => $form.'.select' } ); $alias or return;

   $self->add_field(    { ajaxid  => $form.'.alias_name',
                          default => $alias ne $s->{newtag} ? $alias : NUL,
                          name    => 'name' } );
   $self->add_field(    { default => $element->comment || '-',
                          id      => $form.'.comment' } );
   $self->add_field(    { default =>
                             (join "\r", @{ $element->recipients || [] } ),
                          id      => $form.'.recipients' } );
   $self->group_fields( { id      => $form.'.edit' } );

   # Add buttons to form
   if ($alias eq $s->{newtag}) { $self->add_buttons( qw(Insert) ) }
   else { $self->add_buttons( qw(Save Delete) ) }

   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::MailAliases - Manipulate the mail aliases file

=head1 Version

0.5.$Revision: 1139 $

=head1 Synopsis

   use CatalystX::Usul::Model::MailAliases;

   $alias_obj = CatalystX::Usul::Model::MailAliases->new( $app, $config );

=head1 Description

Management model file the system mail alias file

=head1 Subroutines/Methods

=head2 build_per_context_instance

Creates a new instance of L<CatalystX::Usul::MailAliases>

=head2 create_or_update

   $alias_obj->create_or_update;

Creates a new mail alias or updates an existing one. Request object fields
are:

=over 3

=item alias_name

The name of the alias to be created or updated

=item comment

The comment associated with this alias

=item owner

The logged in user name from the system

=item recipients

List of recipients

=back

Checks the fields passed to it from the web form and calls C<create>
or C</update> on the domain model as appropriate

=head2 delete

   $alias_obj->delete;

Deletes the specified mail alias

=head2 mail_aliases_form

   $alias_obj->aliases_form( $alias );

Stuffs the stash with the data used to render the web form used to display,
create and update mail aliases

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::MailAliases>

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
