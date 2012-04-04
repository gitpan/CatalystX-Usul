# @(#)$Id: Credentials.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Model::Config::Credentials;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model::Config);

use CatalystX::Usul::Functions;
use CatalystX::Usul::Schema;
use MRO::Compat;
use TryCatch;

__PACKAGE__->config
   ( create_msg_key         => 'Credentials [_1]/[_2] created',
     delete_msg_key         => 'Credentials [_1]/[_2] deleted',
     keys_attr              => q(credentials),
     typelist               => {},
     schema_class           => q(CatalystX::Usul::Schema),
     update_msg_key         => 'Credentials [_1]/[_2] updated' );

__PACKAGE__->mk_accessors( qw(schema_class) );

sub create_or_update {
   my ($self, $ns, $args) = @_; my $req = $self->context->req; my $v;

   if (defined ($v = $self->query_value( q(password) ))) {
      $v = $self->schema_class->encrypt( $self->_seed, $v );
      $req->params->{password} = q(encrypt=).$v;
   }

   $self->next::method( $ns, $args );
   return;
}

sub credentials_form {
   my ($self, $ns, $acct) = @_; my ($config_obj, $def, $id);

   try        { $config_obj = $self->list( $ns, $acct ) }
   catch ($e) { return $self->add_error( $e ) }

   my $creds  = $config_obj->list;
   my $fields = $config_obj->result;
   my $s      = $self->context->stash;
   my $form   = $s->{form}->{name};
   my $spaces = [ sort keys %{ $s->{ $self->ns_key } } ];

   unshift @{ $creds  }, q(), $s->{newtag};
   unshift @{ $spaces }, q(), q(default);

   if ($fields->password and $fields->password =~ m{ \A encrypt= (.+) \z }mx) {
      $fields->password( $self->schema_class->decrypt( $self->_seed, $1 ) );
   }

   $self->clear_form(   { firstfld => $form.q(.credentials) } );
   $self->add_field(    { default  => $ns,
                          id       => q(config.).$self->ns_key,
                          stepno   => 0,
                          values   => $spaces } );

   if ($ns) {
      $self->add_field( { default  => $acct,
                          id       => $form.q(.credentials),
                          values   => $creds } );
   }

   $self->group_fields( { id       => $form.q(.select) } );

   ($ns and $acct and is_member $acct, $creds) or return;

   if ($acct eq $s->{newtag}) {
      $self->add_buttons( qw(Insert) ); $def = q(); $id = $form.'.nameNew';
   }
   else {
      $self->add_buttons( qw(Save Delete) ); $def = $acct; $id = $form.'.name';
   }

   $self->add_field(    { ajaxid  => $form.'.name',
                          default => $def,
                          id      => $id,
                          name    => q(name) } );
   $self->add_field(    { ajaxid  => $form.'.driver',
                          default => $fields->driver } );
   $self->add_field(    { ajaxid  => $form.'.host',
                          default => $fields->host } );
   $self->add_field(    { ajaxid  => $form.'.port',
                          default => $fields->port } );
   $self->add_field(    { ajaxid  => $form.'.user',
                          default => $fields->user } );
   $self->add_field(    { default => $fields->password,
                          id      => $form.'.password' } );
   $self->group_fields( { id      => $form.'.edit' } );
   return;
}

# Private methods

sub _seed {
   my $self = shift; my ($args, $path);

   $path = $self->catfile( $self->ctrldir, $self->prefix.q(.txt) );
   $args = { seed => $self->secret };
   $args->{data} = $self->io( $path )->all if (-f $path);
   return $args;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Credentials - Database connection definitions

=head1 Version

0.6.$Revision: 1165 $

=head1 Synopsis

   # The constructor is called by Catalyst at startup

=head1 Description

Maintains database connection strings

Defines the language independent attributes; I<driver>, I<host>,
I<password>, I<port> and I<user> for the I<credentials> element.
Returns a L<CatalystX::Usul::Model::Config> object

=head1 Subroutines/Methods

=head2 new

Defined the I<ctrldir> attribute

=head2 create_or_update

   $c->model( q(Config::Credentials) )->create_or_update( $stash, $args );

Encrypts the C<< $args->{req}->params->{password} >> attribute by calling
C<encrypt> in L<CatalystX::Usul::Schema>. Then calls method of same
name in L<CatalystX::Usul::Model::Config>

=head2 credentials_form

   $c->model( q(Config::Credentials) )->credentials_form( $stash );

Stuffs the stash with the data to build the credentials maintenance form

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model::Config>

=item L<CatalystX::Usul::Schema>

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
