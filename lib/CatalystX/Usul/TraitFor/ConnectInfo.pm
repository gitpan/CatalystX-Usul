# @(#)Ident: ConnectInfo.pm 2013-08-19 19:34 pjf ;

package CatalystX::Usul::TraitFor::ConnectInfo;

use 5.010001;
use namespace::sweep;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw( merge_attributes throw );
use Class::Usul::Crypt         qw( cipher_list );
use Class::Usul::Crypt::Util   qw( decrypt_from_config encrypt_for_config );
use Class::Usul::File;
use File::Spec::Functions      qw( catfile );
use Moo::Role;
use Scalar::Util               qw( blessed );

requires qw( config ); # As a class method

sub decrypt_from_cfg {
   my $self = shift; return decrypt_from_config( @_ );
}

sub dump_cfg_data {
   my ($self, $config, $db, $cfg_data) = @_;

   my $params = __merge_attributes( blessed $self || $self, $config );

   return __dump_config_data( $params, $db, $cfg_data );
}

sub encrypt_for_cfg {
   my $self = shift; return encrypt_for_config( @_ );
}

sub extract_creds_from_cfg {
   my ($self, $config, $db, $cfg_data) = @_;

   my $params = __merge_attributes( blessed $self || $self, $config );

   return __extract_creds_from_cfg( $params, $db, $cfg_data );
}

sub get_connect_info {
   my ($self, $app, $params) = @_; state $cache //= {}; $params ||= {};

   merge_attributes $params, $app->config, $self->config, __get_config_attr();

   my $class    = blessed $self || $self; $params->{class} = $class;
   my $db       = $params->{database}
      or throw error => 'Class [_1] no database name', args => [ $class ];
   my $key      = __get_connect_info_cache_key( $params, $db );

   defined $cache->{ $key } and return $cache->{ $key };

   my $cfg_data = __load_config_data( $params, $db );
   my $creds    = __extract_creds_from_cfg( $params, $db, $cfg_data );
   my $dsn      = q(dbi:).$creds->{driver}.q(:database=).$db;
      $dsn     .= q(;host=).$creds->{host}.q(;port=).$creds->{port};
   my $password = decrypt_from_config( $params, $creds->{password} );
   my $opts     = __get_connect_options( $creds );

   return $cache->{ $key } = [ $dsn, $creds->{user}, $password, $opts ];
}

sub get_cipher_list {
   return cipher_list;
}

sub load_cfg_data {
   my ($self, $config, $db) = @_;

   my $params = __merge_attributes( blessed $self || $self, $config );

   return __load_config_data( $params, $db );
}

# Private functions
sub __dump_config_data {
   my ($params, $db, $cfg_data) = @_;

   my $ctlfile = __get_credentials_file( $params, $db );
   my $schema  = __get_dataclass_schema( $params->{dataclass_attr} );

   return $schema->dump( { data => $cfg_data, path => $ctlfile } );
}

sub __extract_creds_from_cfg {
   my ($params, $db, $cfg_data) = @_;

   my $key = __get_connect_info_cache_key( $params, $db );

   ($cfg_data->{credentials} and defined $cfg_data->{credentials}->{ $key })
      or throw error => 'Path [_1] database [_2] no credentials',
               args  => [ __get_credentials_file( $params, $db ), $key ];

   return $cfg_data->{credentials}->{ $key };
}

sub __get_config_attr {
   return [ qw(class ctlfile ctrldir database dataclass_attr extension subspace
               ctrldir prefix read_secure salt seed suid tempdir) ];
}

sub __get_connect_info_cache_key {
   my ($params, $db) = @_;

   return $params->{subspace} ? $db.q(.).$params->{subspace} : $db;
}

sub __get_connect_options {
   my $creds = shift;
   my $uopt  = $creds->{unicode_option}
            || __unicode_options()->{ lc $creds->{driver} } || {};

   return { AutoCommit => $creds->{auto_commit} // TRUE,
            PrintError => $creds->{print_error} // FALSE,
            RaiseError => $creds->{raise_error} // TRUE,
            %{ $uopt }, %{ $creds->{database_attributes} || {} }, };
}

sub __get_credentials_file {
   my ($params, $db) = @_; my $ctlfile = $params->{ctlfile};

   defined $ctlfile and -f $ctlfile and return $ctlfile;

   my $dir = $params->{ctrldir}; my $extn = $params->{extension} || CONFIG_EXTN;

      $dir or throw error => 'Control directory not specified';
   -d $dir or throw error => 'Directory [_1] not found', args => [ $dir ];
       $db or throw error => 'Class [_1] no database name',
                    args  => [ $params->{class} ];

   return catfile( $dir, $db.$extn );
}

sub __get_dataclass_schema {
   return Class::Usul::File->dataclass_schema( @_ );
}

sub __load_config_data {
   my ($params, $db) = @_;

   my $ctlfile = __get_credentials_file( $params, $db );
   my $schema  = __get_dataclass_schema( $params->{dataclass_attr} );

   return $schema->load( $ctlfile );
}

sub __merge_attributes {
   my ($class, $config) = @_; my $params = {};

   merge_attributes $params, $config, { class => $class }, __get_config_attr();

   return $params;
}

sub __unicode_options {
   return { mysql  => { mysql_enable_utf8 => TRUE },
            pg     => { pg_enable_utf8    => TRUE },
            sqlite => { sqlite_unicode    => TRUE }, };
}

1;

=pod

=head1 Name

CatalystX::Usul::TraitFor::ConnectInfo - Provides the DBIC connect info array ref

=head1 Version

0.1.$Rev: 0 $

=head1 Synopsis

   package YourApp::Model::YourModel;

   use CatalystX::Usul::Moose;

   extends qw(CatalystX::Usul::Model::Schema);

   __PACKAGE__->config( database     => q(your_database_name),
                        schema_class => q(YourApp::Schema::YourSchema) );

   sub COMPONENT {
      my ($class, $app, $cfg) = @_;

      $cfg->{connect_info} ||= $class->get_connect_info( $app, $cfg );

      return $class->next::method( $app, $cfg );
   }

=head1 Description

Provides the DBIC connect info array ref

=head1 Configuration and Environment

The XML data looks like this:

  <credentials>
    <name>database_we_want_to_connect_to.optional_subspace</name>
    <driver>mysql</driver>
    <host>localhost</host>
    <password>{Twofish}0QqX325DLs18I8T/wU4/ZQQ=</password>
    <port>3306</port>
    <print_error>0</print_error>
    <raise_error>1</raise_error>
    <user>root</user>
  </credentials>

=head1 Subroutines/Methods

=head2 decrypt_from_cfg

   $plain_text = $self->decrypt_from_cfg( $app_config, $password );

Strips the C<{Twofish2}> prefix and then decrypts the password

=head2 dump_cfg_data

   $dumped_data = $self->dump_cfg_data( $app_config, $db, $cfg_data );

Call the L<dump method|File::DataClass::Schema/dump> to write the
configuration file back to disk

=head2 encrypt_for_cfg

   $encrypted_value = $self->encrypt_for_cfg( $app_config, $plain_text );

Returns the encrypted value of the plain value prefixed with C<{Twofish2}>
for storage in a configuration file

=head2 extract_creds_from_cfg

   $creds = $self->extract_creds_from_cfg( $app_config, $db, $cfg_data );

Returns the credential info for the specified database and (optional)
subspace. The subspace attribute of C<$app_config> is appended
to the database name to create a unique cache key

=head2 get_cipher_list

   @list_of_ciphers = $self->get_cipher_list;

Returns the list of ciphers supported by L<Crypt::CBC>. These may not
all be installed

=head2 get_connect_info

   $db_info_arr = $self->get_connect_info( $app_config, $db );

Returns an array ref containing the information needed to make a
connection to a database; DSN, user id, password, and options hash
ref. The data is read from the configuration file in the config
C<ctrldir>. Multiple sets of data can be stored in the same file,
keyed by the C<$db> argument. The password is decrypted if
required

=head2 load_cfg_data

   $cfg_data = $self->load_cfg_data( $app_config, $db );

Returns a hash ref of configuration file data. The path to the file
can be specified in C<< $app_config->{ctlfile} >> or it will default
to the C<$db.$extension> file in the C<< $app_config->{ctrldir} >>
directory.  The C<$extension> is either C<< $app_config->{extension} >>
or C<< $self->config->{extension} >> or the default extension given
by the C<CONFIG_EXTN> constant

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Moose::Role>

=item L<Class::Usul::Crypt>

=item L<Class::Usul::Crypt::Util>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

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
