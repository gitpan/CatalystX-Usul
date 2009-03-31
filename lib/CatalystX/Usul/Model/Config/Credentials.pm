package CatalystX::Usul::Model::Config::Credentials;

# @(#)$Id: Credentials.pm 401 2009-03-27 00:17:37Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Model::Config);
use CatalystX::Usul::Schema;
use Class::C3;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 401 $ =~ /\d+/gmx );

__PACKAGE__->config
   ( create_msg_key    => q(createdCredentials),
     delete_msg_key    => q(deletedCredentials),
     keys_attr         => q(acct),
     schema_attributes => {
        attributes     => [ qw(driver host password port user) ],
        defaults       => {},
        element        => q(credentials),
        lang_dep       => undef, },
     typelist          => {},
     update_msg_key    => q(updatedCredentials) );

__PACKAGE__->mk_accessors( qw(ctrldir) );

sub new {
   my ($self, $app, @rest) = @_;

   my $new = $self->next::method( $app, @rest );

   $new->ctrldir( $app->config->{ctrldir} || q() );
   return $new;
}

sub create_or_update {
   my ($self, $args) = @_; my $req = $self->context->req; my $val;

   if (defined ($val = $self->query_value( q(password) ))) {
      $val = CatalystX::Usul::Schema->encrypt( $self->_seed, $val );
      $req->params->{password} = q(encrypt=).$val;
   }

   $self->next::method( $args );
   return;
}

sub credentials_form {
   my ($self, $level, $acct) = @_; my ($def, $e, $id);

   my $data   = eval { $self->get_list( $level, $acct ) };

   return $self->add_error( $e ) if ($e = $self->catch);

   my $s      = $self->context->stash; $s->{pwidth} -= 10;
   my $creds  = $data->list; unshift @{ $creds }, q(), $s->{newtag};
   my $levels = [ sort keys %{ $s->{levels} } ];
   my $form   = $s->{form}->{name};
   my $fields = $data->element;
   my $nitems = 0;
   my $stepno = 1;

   unshift @{ $levels }, q(), q(default);

   if ($fields->password and $fields->password =~ m{ \A encrypt= (.+) \z }mx) {
      my $schema_class = q(CatalystX::Usul::Schema);

      $fields->password( $schema_class->decrypt( $self->_seed, $1 ) );
   }

   $self->clear_form(   { firstfld => $form.q(.acct) } );
   $self->add_field(    { default  => $level,
                          id       => q(config.level),
                          stepno   => 0,
                          values   => $levels } ); $nitems++;

   if ($level) {
      $self->add_field( { default  => $acct,
                          id       => $form.q(.acct),
                          stepno   => 0,
                          values   => $creds } ); $nitems++;
   }

   $self->group_fields( { id       => $form.q(.select),
                          nitems   => $nitems } ); $nitems = 0;

   return unless ($level and $acct and $self->is_member( $acct, @{ $creds } ));

   if ($acct eq $s->{newtag}) {
      $self->add_buttons( qw(Insert) ); $def = q(); $id = $form.'.nameNew';
   }
   else {
      $self->add_buttons( qw(Save Delete) ); $def = $acct; $id = $form.'.name';
   }

   $self->add_field(    { ajaxid  => $form.'.name',
                          default => $def,
                          id      => $id,
                          name    => q(name),
                          stepno  => $stepno++ } ); $nitems++;
   $self->add_field(    { ajaxid  => $form.'.driver',
                          default => $fields->driver,
                          stepno  => $stepno++ } ); $nitems++;
   $self->add_field(    { ajaxid  => $form.'.host',
                          default => $fields->host,
                          stepno  => $stepno++ } ); $nitems++;
   $self->add_field(    { ajaxid  => $form.'.port',
                          default => $fields->port,
                          stepno  => $stepno++ } ); $nitems++;
   $self->add_field(    { ajaxid  => $form.'.user',
                          default => $fields->user,
                          stepno  => $stepno++ } ); $nitems++;
   $self->add_field(    { default => $fields->password,
                          id      => $form.'.password',
                          stepno  => $stepno++ } ); $nitems++;
   $self->group_fields( { id      => $form.'.edit', nitems => $nitems } );
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

0.1.$Revision: 401 $

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
