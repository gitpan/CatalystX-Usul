# @(#)Ident: ;

package CatalystX::Usul::Model::MailAliases;

use strict;
use version; our $VERSION = qv( sprintf '0.15.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions   qw(throw);
use CatalystX::Usul::Constraints qw(Path);
use TryCatch;

extends q(CatalystX::Usul::Model);
with    q(CatalystX::Usul::TraitFor::Model::StashHelper);
with    q(CatalystX::Usul::TraitFor::Model::QueryingRequest);

has '+domain_class' => default => q(File::MailAlias);

has 'aliases_path'  => is => 'lazy', isa => Path, coerce => TRUE,
   default          => sub { [ $_[ 0 ]->usul->config->ctrldir, 'aliases' ] };


has '_user_model'   => is => 'lazy', isa => Object,
   default          => sub { $_[ 0 ]->context->model( q(UsersUnix) ) },
   init_arg         => undef, reader => 'user_model';

sub build_per_context_instance {
   my ($self, $c, @rest) = @_; my $clone = $self->next::method( $c, @rest );

   my $attr = { path => $clone->aliases_path,
                %{ $clone->domain_attributes || {} }, builder => $clone->usul };

   $clone->domain_model( $self->domain_class->new( $attr ) );
   return $clone;
}

sub create_or_update {
   my $self = shift;
   my $name = $self->query_value( q(name) ) or throw 'Alias name not specified';

  (my $recipients = $self->query_value( q(recipients) )) =~ s{ \s+ }{ }gmsx;

   my $s      = $self->context->stash;
   my $fields = { name       => $name,
                  alias_name => $name,
                  comment    => $self->query_array( q(comment) ) || [],
                  owner      => $s->{user}->username,
                  recipients => [ split SPC, $recipients ] };
   my $is_new = $self->query_value( q(alias) ) eq $s->{newtag} ? TRUE : FALSE;
   my $key    = $is_new ? 'Alias [_1] created' : 'Alias [_1] updated';
   my $method = $is_new ? q(create) : q(update);
   my $out;

   ($name, $out) = $self->domain_model->$method( $self->check_form( $fields ) );
   $self->user_model->invalidate_cache;
   $self->add_result_msg( $key, $name );
   $self->add_result( $out );
   return $name;
}

sub delete {
   my $self  = shift;
   my $alias = $self->query_value( q(alias) )
      or throw 'Alias name not specified';
   my ($name, $out) = $self->domain_model->delete( { name => $alias } );

   $self->user_model->invalidate_cache;
   $self->add_result_msg( 'Alias [_1] deleted', $name );
   $self->add_result( $out );
   return;
}

sub mail_aliases_form {
   my ($self, $alias_name) = @_; my $mail_alias;

   # Retrieve data from model
   try        { $mail_alias = $self->domain_model->list( $alias_name ) }
   catch ($e) { return $self->add_error( $e ) }

   my $s       = $self->context->stash;
   my $form    = $s->{form}->{name}; $s->{pwidth} -= 20;
   my $is_new  = $alias_name eq $s->{newtag} ? TRUE : FALSE;
   my $aliases = [ NUL, $s->{newtag}, @{ $mail_alias->list } ];
   my $alias   = $mail_alias->result;

   # Add HTML elements items to form
   $self->clear_form( { firstfld  => "${form}.alias" } );
   $self->add_field(  { default   => $alias_name,
                        id        => "${form}.alias",
                        values    => $aliases } );

   if ($is_new) {
      $self->add_field( { id      => "${form}.alias_name",
                          name    => 'name' } );
      $self->add_buttons( qw(Insert) );
   }
   else {
      $self->add_hidden( 'name', $alias_name );
      $self->add_buttons( qw(Save Delete) );
   }

   if ($mail_alias->found and $alias->owner) {
      $s->{owner} = $alias->owner; $s->{created} = $alias->created;
      $self->add_field( { id      => "${form}.note" } );
   }

   $self->group_fields( { id      => "${form}.select" } );

   $alias_name or return;

   $self->add_field(    { default => $alias->comment || '-',
                          id      => "${form}.comment" } );
   $self->add_field(    { default => (join "\r", @{ $alias->recipients || [] }),
                          id      => "${form}.recipients" } );
   $self->group_fields( { id      => "${form}.edit" } );
   return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::MailAliases - Manipulate the mail aliases file

=head1 Version

Describes v0.15.$Rev: 1 $

=head1 Synopsis

   package YourApp;

   use Catalyst qw(ConfigComponents...);

   __PACKAGE__->config(
     'Model::MailAliases'  => {
        parent_classes     => q(CatalystX::Usul::Model::MailAliases),
        domain_attributes  => {
           root_update_cmd => q(path_to_suid_wrapper), }, }, );

=head1 Description

Management model file the system mail alias file

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item aliases_path

The path to the local copy of the mail alias file. Defaults to
F<aliases> in F<ctrldir>

=back

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

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::MailAliases>

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::TraitFor::Model::QueryingRequest>

=item L<CatalystX::Usul::TraitFor::Model::StashHelper>

=item L<CatalystX::Usul::Moose>

=item L<CatalystX::Usul::Constraints>

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

Copyright (c) 2014 Peter Flanigan. All rights reserved

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
