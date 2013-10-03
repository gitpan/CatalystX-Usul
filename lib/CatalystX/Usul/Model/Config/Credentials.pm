# @(#)Ident: Credentials.pm 2013-09-19 22:42 pjf ;

package CatalystX::Usul::Model::Config::Credentials;

use strict;
use version; our $VERSION = qv( sprintf '0.13.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions;
use Class::Usul::Crypt::Util qw( decrypt_from_config
                                 encrypt_for_config get_cipher );
use TryCatch;

extends q(CatalystX::Usul::Model::Config);

has '+create_msg_key' => default => 'Credentials [_1]/[_2] created';

has '+delete_msg_key' => default => 'Credentials [_1]/[_2] deleted';

has '+keys_attr'      => default => 'credentials';

has '+update_msg_key' => default => 'Credentials [_1]/[_2] updated';

sub create_or_update {
   my ($self, $ns, $args) = @_; my $c = $self->context; my $v;

   if (defined ($v = $self->query_value( 'password' ))) {
      my $cipher = $self->query_value( 'cipher' );

      $c->req->params->{password}
         = encrypt_for_config( $self->usul->config, $v, $cipher );
   }

   $self->next::method( $ns, $args );
   return;
}

sub credentials_form {
   my ($self, $ns, $acct) = @_; my ($config_obj, $def);

   try        { $config_obj = $self->list( $ns, $acct ) }
   catch ($e) { return $self->add_error( $e ) }

   my $c        = $self->context;
   my $s        = $c->stash;
   my $form     = $s->{form}->{name};
   my $spaces   = [ sort keys %{ $s->{ $self->ns_key } } ];
   my $id       = $ns ? "${form}.credentials" : q(config.).$self->ns_key;
   my $creds    = $config_obj->list;
   my $fields   = $config_obj->result;
   my $usul_cfg = $self->usul->config;
   my $password = decrypt_from_config( $usul_cfg, $fields->password );
   my $cipher   = get_cipher( $fields->password );
   my $ciphers  = [ NUL, $self->get_cipher_list ];

   unshift @{ $creds  }, NUL, $s->{newtag};
   unshift @{ $spaces }, NUL, 'default';

   $self->clear_form(   { firstfld => $id } );
   $self->add_field(    { default  => $ns,
                          id       => 'config.'.$self->ns_key,
                          stepno   => 0,
                          values   => $spaces } );

   if ($ns) {
      $self->add_field( { default  => $acct,
                          id       => "${form}.credentials",
                          values   => $creds } );
   }

   $self->group_fields( { id       => "${form}.select" } );

   ($ns and $acct and is_member $acct, $creds) or return;

   if ($acct eq $s->{newtag}) {
      $self->add_buttons( qw(Insert) ); $def = NUL; $id = "${form}.nameNew";
   }
   else {
      $self->add_buttons( qw(Save Delete) ); $def = $acct; $id = "${form}.name";
   }

   $self->add_field(    { default => $def,
                          id      => $id,
                          name    => 'name' } );
   $self->add_field(    { default => $fields->driver,
                          id      => "${form}.driver" } );
   $self->add_field(    { default => $fields->host,
                          id      => "${form}.host" } );
   $self->add_field(    { default => $fields->port,
                          id      => "${form}.port" } );
   $self->add_field(    { default => $fields->user,
                          id      => "${form}.user" } );
   $self->add_field(    { default => $password,
                          id      => "${form}.password" } );
   $self->add_field(    { default => $cipher,
                          id      => "${form}.cipher",
                          values  => $ciphers } );
   $self->group_fields( { id      => "${form}.edit" } );
   return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Config::Credentials - Database connection definitions

=head1 Version

Describes v0.13.$Rev: 1 $

=head1 Synopsis

   # The constructor is called by Catalyst at startup

=head1 Description

Maintains database connection strings

Defines the language independent attributes; I<driver>, I<host>,
I<password>, I<port> and I<user> for the I<credentials> element.
Returns a L<CatalystX::Usul::Model::Config> object

=head1 Subroutines/Methods

=head2 new

Defined the C<ctrldir> attribute

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
