# @(#)Ident: ConnectInfo.pm 2013-12-01 01:30 pjf ;

package CatalystX::Usul::TraitFor::ConnectInfo;

use 5.010001;
use strict;
use namespace::sweep;
use version;  our $VERSION = qv( sprintf '0.15.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use Class::Usul::Crypt::Util qw( decrypt_from_config );
use Class::Usul::File;
use Class::Usul::Functions   qw( merge_attributes throw );
use File::Spec::Functions    qw( catfile );
use Scalar::Util             qw( blessed );
use Moo::Role;

requires qw( config ); # As a class method

sub dump_config_data {
   my ($self, $config, $db, $cfg_data) = @_;

   my $params = $self->_merge_attributes( $config );

   return __dump_config_data( $params, $db, $cfg_data );
}

sub extract_creds_from {
   my ($self, $config, $db, $cfg_data) = @_;

   my $params = $self->_merge_attributes( $config );

   return __extract_creds_from( $params, $db, $cfg_data );
}

sub get_connect_info {
   my ($self, $app, $params) = @_; my $attr = $self->_connect_config_attr;

   state $cache //= {}; $app //= $self; $params //= {};

   merge_attributes $params, $app->config, $self->config, $attr;

   my $class    = blessed $self || $self; $params->{class} = $class;
   my $db       = $params->{database}
      or throw error => 'Class [_1] no database name', args => [ $class ];
   my $key      = __get_connect_info_cache_key( $params, $db );

   defined $cache->{ $key } and return $cache->{ $key };

   my $cfg_data = $self->load_config_data( $params, $db );
   my $creds    = $self->extract_creds_from( $params, $db, $cfg_data );
   my $dsn      = 'dbi:'.$creds->{driver}.':database='.$db
                  .';host='.$creds->{host}.';port='.$creds->{port};
   my $password = decrypt_from_config( $params, $creds->{password} );
   my $opts     = __get_connect_options( $creds );

   return $cache->{ $key } = [ $dsn, $creds->{user}, $password, $opts ];
}

sub load_config_data {
   return __load_config_data( $_[ 0 ]->_merge_attributes( $_[ 1 ] ), $_[ 2 ] );
}

# Private methods
sub _connect_config_attr {
   return [ qw( class ctlfile ctrldir database dataclass_attr extension
                prefix read_secure salt seed seed_file subspace tempdir ) ];
}

sub _merge_attributes {
   my ($self, $config) = @_;

   my $attr = $self->_connect_config_attr; my $class = blessed $self || $self;

   return merge_attributes { class => $class }, $config, {}, $attr;
}

# Private functions
sub __dump_config_data {
   my ($params, $db, $cfg_data) = @_;

   my $ctlfile = __get_credentials_file( $params, $db );
   my $schema  = __get_dataclass_schema( $params->{dataclass_attr} );

   return $schema->dump( { data => $cfg_data, path => $ctlfile } );
}

sub __extract_creds_from {
   my ($params, $db, $cfg_data) = @_;

   my $key = __get_connect_info_cache_key( $params, $db );

   ($cfg_data->{credentials} and defined $cfg_data->{credentials}->{ $key })
      or throw error => 'Path [_1] database [_2] no credentials',
               args  => [ __get_credentials_file( $params, $db ), $key ];

   return $cfg_data->{credentials}->{ $key };
}

sub __get_connect_info_cache_key {
   my ($params, $db) = @_;

   return $params->{subspace} ? "${db}.".$params->{subspace} : $db;
}

sub __get_connect_options {
   my $creds = shift;
   my $uopt  = $creds->{unicode_option}
            || __unicode_options()->{ lc $creds->{driver} } || {};

   return { AutoCommit =>  $creds->{auto_commit  } // TRUE,
            PrintError =>  $creds->{print_error  } // FALSE,
            RaiseError =>  $creds->{raise_error  } // TRUE,
            %{ $uopt }, %{ $creds->{database_attr} || {} }, };
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

   my $schema = __get_dataclass_schema( $params->{dataclass_attr} );

   return $schema->load( __get_credentials_file( $params, $db ) );
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

v0.10.$Rev: 1 $

=head1 Synopsis

   package YourApp::Model::YourModel;

   use CatalystX::Usul::Moose;

   extends q(CatalystX::Usul::Model::Schema);

   __PACKAGE__->config( database     => 'your_database_name',
                        schema_class => 'YourApp::Schema::YourSchema' );

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
    <password>{Twofish2}0QqX325DLs18I8T/wU4/ZQQ=</password>
    <port>3306</port>
    <print_error>0</print_error>
    <raise_error>1</raise_error>
    <user>root</user>
  </credentials>

=head1 Subroutines/Methods

=head2 dump_config_data

   $dumped_data = $self->dump_config_data( $app_config, $db, $cfg_data );

Call the L<dump method|File::DataClass::Schema/dump> to write the
configuration file back to disk

=head2 extract_creds_from

   $creds = $self->extract_creds_from( $app_config, $db, $cfg_data );

Returns the credential info for the specified database and (optional)
subspace. The subspace attribute of C<$app_config> is appended
to the database name to create a unique cache key

=head2 get_connect_info

   $db_info_arr = $self->get_connect_info( $app_config, $db );

Returns an array ref containing the information needed to make a
connection to a database; DSN, user id, password, and options hash
ref. The data is read from the configuration file in the config
C<ctrldir>. Multiple sets of data can be stored in the same file,
keyed by the C<$db> argument. The password is decrypted if
required

=head2 load_config_data

   $cfg_data = $self->load_config_data( $app_config, $db );

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
