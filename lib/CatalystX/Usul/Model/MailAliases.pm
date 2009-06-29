# @(#)$Id: MailAliases.pm 576 2009-06-09 23:23:46Z pjf $

package CatalystX::Usul::Model::MailAliases;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 576 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model);

use CatalystX::Usul::MailAliases;
use Class::C3;

my $NUL = q();

__PACKAGE__->mk_accessors( qw(domain_attributes domain_model) );

sub build_per_context_instance {
   my ($self, $c, @rest) = @_;

   my $new   = $self->next::method( $c, @rest );
   my $attrs = $new->domain_attributes || {};

   $new->domain_model( CatalystX::Usul::MailAliases->new( $c, $attrs ) );

   return $new;
}

sub create_or_update {
   my $self = shift; my ($alias, $flds, $name, $recipients);

   my $s = $self->context->stash;

   unless ($name = $self->query_value( q(name) )) {
      $self->throw( 'No alias name specified' );
   }

   ($recipients = $self->query_value( q(recipients) )) =~ s{ \s+ }{ }gmsx;
   $flds  = { alias_name => $name,
              comment    => $self->query_value( q(comment) ),
              owner      => $s->{user},
              recipients => [ split q( ), $recipients ] };
   $flds  = $self->check_form( $flds );
   $alias = $self->query_value( q(alias) ) || $NUL;

   if ($alias eq $s->{newtag}) {
      $self->add_result( $self->domain_model->create( $flds ) );
   }
   else { $self->add_result( $self->domain_model->update( $flds ) ) }

   return $name;
}

sub delete {
   my $self = shift; my $alias = $self->query_value( q(alias) );

   $self->throw( 'No alias name specified' ) unless ($alias);

   $self->add_result( $self->domain_model->delete( $alias ) );
   return;
}

sub mail_aliases_form {
   my ($self, $alias) = @_;

   # Retrieve data from model
   my $data    = eval { $self->domain_model->retrieve( $alias ) }; my $e;

   return $self->add_error( $e ) if ($e = $self->catch);

   my $s       = $self->context->stash; $s->{pwidth} -= 10;
   my $aliases = $data->aliases; unshift @{ $aliases }, $NUL, $s->{newtag};
   my $form    = $s->{form}->{name};
   my $nitems  = 0;
   my $step    = 1;

   # Add HTML elements items to form
   $self->clear_form( { firstfld => $form.'.alias' } );
   $self->add_field(  { default  => $alias,
                        id       => $form.'.alias',
                        values   => $aliases } ); $nitems++;

   if ($data->owner) {
      $s->{owner} = $data->owner; $s->{created} = $data->created;
      $self->add_field( { id => $form.'.note' } ); $nitems++;
   }

   $self->group_fields( { id => $form.'.select', nitems => $nitems } );

   return unless ($alias);

   my $default = $alias ne $s->{newtag} ? $alias : $NUL;

   $self->add_field(    { ajaxid  => $form.'.alias_name',
                          default => $default,
                          name    => 'name',
                          stepno  => $step++ } ); $nitems = 1;
   $self->add_field(    { default => $data->comment,
                          id      => $form.'.comment',
                          stepno  => $step++ } ); $nitems++;
   $self->add_field(    { default => (join "\r", @{ $data->recipients }),
                          id      => $form.'.recipients',
                          stepno  => $step++ } ); $nitems++;
   $self->group_fields( { id      => $form.'.edit', nitems => $nitems } );

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

0.3.$Revision: 576 $

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
