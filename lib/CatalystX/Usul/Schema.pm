# @(#)$Id: Schema.pm 1181 2012-04-17 19:06:07Z pjf $

package CatalystX::Usul::Schema;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.7.%d', q$Rev: 1181 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Base CatalystX::Usul::File);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(create_token throw);
use Crypt::CBC;
use English qw(-no_match_vars);
use MIME::Base64;
use Sys::Hostname;

my $CLEANER         = '.*^\s*use\s+Acme::Bleach\s*;\r*\n';
my %DB_ADMIN_IDS    = ( mysql  => q(root),
                        pg     => q(postgres), );
my $KEY             = " \t" x 8;
my $DATA            = do { local $RS = undef; <DATA> };
my %UNICODE_OPTIONS = ( mysql  => { mysql_enable_utf8 => TRUE },
                        pg     => { pg_enable_utf8    => TRUE },
                        sqlite => { sqlite_unicode    => TRUE }, );

__PACKAGE__->mk_accessors( qw(attrs database driver dsn host password
                              preversion rdbms schema_version unlink user) );

# Class methods

sub get_connect_info {
   my ($self, $app_cfg, $db) = @_; $app_cfg ||= {};

   $db or throw error => 'Class [_1] no database name',
                args  => [ ref $self || $self ];

   my $schema  = $self->file_dataclass_schema;
   my $ctlfile = $self->_get_control_file( $app_cfg, $db );
   my $data    = $self->_load_credentials( $schema, $ctlfile, $db );
   my $creds   = $data->{credentials}->{ $db };
   my $dsn     = q(dbi:).$creds->{driver}.q(:database=).$db;
      $dsn    .= q(;host=).$creds->{host}.q(;port=).$creds->{port};
   my $uopt    = $creds->{unicode_option}
              || $UNICODE_OPTIONS{ lc $creds->{driver} } || {};
   my $attr    = { AutoCommit => defined $creds->{auto_commit}
                               ? $creds->{auto_commit} : TRUE,
                   PrintError => defined $creds->{print_error}
                               ? $creds->{print_error} : FALSE,
                   RaiseError => defined $creds->{raise_error}
                               ? $creds->{raise_error} : TRUE,
                   %{ $uopt }, };

   $creds->{password} = $self->_decrypt_from_cfg( $app_cfg, $creds->{password});

   return [ $dsn, $creds->{user}, $creds->{password}, $attr ];
}

# Public interface object methods

sub schema_init {
   my ($self, $cfg, $vars) = @_; my $dbs; $vars ||= {};

   $self->rdbms( [ @{ $cfg->{rdbms} } ] );

   if ($dbs = $vars->{rdbms}) {
      push @{ $self->rdbms }, ref $dbs eq ARRAY ? @{ $dbs } : $dbs;
   }

   $self->database      ( $vars->{database  } || $cfg->{database      } );
   $self->preversion    ( $vars->{preversion} || $cfg->{preversion    } );
   $self->schema_version( $vars->{version   } || $cfg->{schema_version} );
   $self->unlink        ( $vars->{unlink    } || $cfg->{unlink        } );

   my $info = $self->get_connect_info( $cfg, $self->database );

   $self->dsn     ( $vars->{dsn}      || $info->[ 0 ]                );
   $self->user    ( $vars->{user    } || $info->[ 1 ]                );
   $self->password( $vars->{password} || $info->[ 2 ]                );
   $self->attrs   ( { add_drop_table => TRUE, no_comments => TRUE,
                 %{ $vars->{dbattrs } || $info->[ 3 ] }, }           );
   $self->host    ( (split q(=), (split q(;), $self->dsn)[ 1 ])[ 1 ] );
   $self->driver  ( (split q(:), $self->dsn)[ 1 ]                    );
   return;
}

sub create_database : method {
   my $self = shift; my $cmd;

   my $host = $self->host; my $database = $self->database;
   my $user = $self->user; my $password = $self->password;

   my $admin_creds = $self->_get_db_admin_creds( 'create database' );

   if (lc $self->driver eq q(mysql)) {
      $self->info( "Creating MySQL database ${database}" );
      $cmd  = "create user '${user}'".'@';
      $cmd .= "'${host}' identified by '${password}';";
      $self->_run_db_cmd( $admin_creds, $cmd );
      $cmd  = "create database if not exists ${database} default character ";
      $cmd .= "set utf8 collate utf8_unicode_ci;";
      $self->_run_db_cmd( $admin_creds, $cmd );
      $cmd  = "grant all privileges on ${database}.* to '${user}'".'@';
      $cmd .= "'${host}' with grant option;";
      $self->_run_db_cmd( $admin_creds, $cmd );
      return OK;
   }

   if (lc $self->driver eq q(pg)) {
      $self->info( "Creating PostgreSQL database ${database}" );
      $cmd = "create role ${user} login password '${password}';";
      $self->_run_db_cmd( $admin_creds, $cmd );
      $cmd = "create database ${database} owner ${user} encoding 'UTF8';";
      $self->_run_db_cmd( $admin_creds, $cmd );
      return OK;
   }

   return FAILED;
}

sub create_ddl {
   my ($self, $dbh, $dir) = @_; my $version = $self->schema_version;

   if ($self->unlink) {
      for my $db (@{ $self->rdbms }) {
         my $path = $self->io( $dbh->ddl_filename( $db, $version, $dir ) );

         $path->is_file and $path->unlink;
      }
   }

   $dbh->storage->create_ddl_dir( $dbh,
                                  $self->rdbms,
                                  $version,
                                  $dir,
                                  $self->preversion,
                                  $self->attrs );
   return;
}

sub create_schema : method {
   # Create databases and edit credentials
   my $self    = shift;
   my $cfg     = $self->config;
   my $picfg   = $self->read_post_install_config;
   my $text    = 'Schema creation requires a database, id and password. ';
      $text   .= 'For Postgres the driver is Pg and the port 5432';
   my $default = defined $picfg->{create_schema}
               ? $picfg->{create_schema} : TRUE;

   $self->output( $text, $cfg->{paragraph} );

   my $choice  = $self->yorn( 'Create database schema', $default, TRUE, 0 );

   $picfg->{create_schema} = $choice or return OK;

   # Edit the config file that contains the database connection info
   $self->_edit_credentials( $picfg );

   # Create the database if we can. Will do nothing if we can't
   $self->create_database;

   # Call DBIx::Class::deploy to create schema and populate it with static data
   $self->deploy_and_populate;
   return OK;
}

sub decrypt {
   my ($self, $seed, $encoded) = @_; $encoded or return;

   my $cipher = Crypt::CBC->new( -cipher => q(Twofish),
                                 -key    => $self->_keygen( $seed ) );

   return $cipher->decrypt( decode_base64( $encoded ) );
}

sub deploy_and_populate {
   my ($self, $dbh, $dir, $schema) = @_; my $res; $dbh or return;

   $self->info( "Deploying schema ${schema} and populating" );
   $dbh->storage->ensure_connected; $dbh->deploy( $self->attrs, $dir );

   $schema =~ s{ :: }{-}gmx;

   my $re = qr{ \A $schema [-] \d+ [-] (.*) \.xml \z }mx;
   my $io = $self->io( $dir )->filter( sub { $_->filename =~ $re } );

   for my $path ($io->all_files) {
      my ($class) = $path->filename =~ $re;

      if ($class) { $self->output( "Populating ${class}" ) }
      else        { $self->fatal ( 'No class in [_1]', $path->filename ) }

      my $hash = $self->file_dataclass_schema->load( $path );
      my $flds = [ split SPC, $hash->{fields} ];
      my @rows = map { [ map    { s{ \A [\'\"] }{}mx; s{ [\'\"] \z }{}mx; $_ }
                         split m{ , \s* }mx, $_ ] } @{ $hash->{rows} };

      @{ $res->{ $class } } = $dbh->populate( $class, [ $flds, @rows ] );
   }

   return;
}

sub drop_database : method {
   my $self = shift; my $database = $self->database; my $cmd;

   my $host = $self->host; my $user = $self->user;

   my $admin_creds = $self->_get_db_admin_creds( 'drop database' );

   $self->info( "Droping database ${database}" );

   if (lc $self->driver eq q(mysql)) {
      $cmd = "drop database if exists ${database};";
      $self->_run_db_cmd( $admin_creds, $cmd );
      $cmd = "drop user '${user}'".'@'."'${host}';";
      $self->_run_db_cmd( $admin_creds, $cmd, { expected_rv => 1 } );
      return OK;
   }

   if (lc $self->driver eq q(pg)) {
      $self->_run_db_cmd( $admin_creds, "drop database ${database};" );
      $self->_run_db_cmd( $admin_creds, "drop user ${user};" );
      return OK;
   }

   return FAILED;
}

sub encrypt {
   my ($self, $seed, $plain) = @_; $plain or return;

   my $cipher = Crypt::CBC->new( -cipher => q(Twofish),
                                 -key    => $self->_keygen( $seed ) );

   return encode_base64( $cipher->encrypt( $plain ), NUL );
}

# Private methods

sub _decrypt_from_cfg {
   my ($self, $cfg, $password) = @_;

   return $password =~ m{ \A encrypt= (.+) \z }mx
        ? $self->decrypt( $self->_get_crypt_args( $cfg ), $1 ) : $password;
}

sub _edit_credentials {
   my ($self, $picfg) = @_; my $cfg = $self->config;

   my $db      = $picfg->{database_name} or throw 'No database name';
   my $schema  = $self->file_dataclass_schema( $picfg->{config_attrs} );
   my $ctlfile = $self->_get_control_file( $cfg, $db );
   my $data    = $self->_load_credentials( $schema, $ctlfile, $db );
   my $creds   = $data->{credentials}->{ $db };
   my $prompts = { name     => 'Enter db name',
                   driver   => 'Enter DBD driver',
                   host     => 'Enter db host',
                   port     => 'Enter db port',
                   user     => 'Enter db user',
                   password => 'Enter db password' };
   my $defs    = { name     => $db,
                   driver   => q(_field),
                   host     => q(localhost),
                   port     => q(_field),
                   user     => q(_field),
                   password => NUL };
   my $value;

   for my $fld (qw(name driver host port user password)) {
      $value =  $defs->{ $fld } eq q(_field)
             ? $creds->{ $fld } : $defs->{ $fld };
      $value = $self->get_line( $prompts->{ $fld }, $value, TRUE, 0, FALSE,
                                $fld eq q(password) ? TRUE : FALSE );
      $fld eq q(password) and $value = $self->_encrypt_for_cfg( $cfg, $value );
      $creds->{ $fld } = $value || NUL;
   }

   $schema->dump( { data => $data, path => $ctlfile } );

   # To reload the connect info
   $self->schema_init( $cfg, $self->vars );
   return;
}

sub _encrypt_for_cfg {
   my ($self, $cfg, $value) = @_; $value or return;

   $value = $self->encrypt( $self->_get_crypt_args( $cfg ), $value );

   return $value ? q(encrypt=).$value : undef;
}

sub _get_control_file {
   my ($self, $app_cfg, $db) = @_;

   exists $app_cfg->{ctlfile} and return $app_cfg->{ctlfile};

   my $extn = $app_cfg->{conf_extn} || $self->config->{conf_extn};

   defined $extn or throw 'Config extension not defined';

   return $self->catfile( $app_cfg->{ctrldir}, $db.$extn );
}

sub _get_crypt_args {
   my ($self, $app_cfg) = @_;

   my $dir  = $app_cfg->{ctrldir} || $app_cfg->{tempdir};
   my $path = $self->catfile( $dir, $app_cfg->{prefix}.q(.txt) );
   my $args = { seed => $app_cfg->{secret} || $app_cfg->{prefix} };

   -f $path and $args->{data} = $self->io( $path )->all;

   return $args;
}

sub _get_db_admin_creds {
   my ($self, $reason) = @_; my $cfg = $self->config;

   my $attrs  = { password => NUL, user => NUL, };
   my $text   = 'Need the database administrators id and password to perform ';
      $text  .= "a ${reason} operation";

   $self->output( $text, $cfg->{paragraph} );

   my $prompt = 'Database administrator id';
   my $user   = $DB_ADMIN_IDS{ lc $self->driver } || NUL;

   $attrs->{user    } = $self->get_line( $prompt, $user, TRUE, 0 );
   $prompt    = 'Database administrator password';
   $attrs->{password} = $self->get_line( $prompt, NUL, TRUE, 0, FALSE, TRUE );
   return $attrs;
}

sub _keygen {
   my ($self, $args) = @_;

   ($args and ref $args eq HASH) or $args = { seed => $args || NUL };

   (my $salt = __inflate( $args->{data} || $DATA )) =~ s{ $CLEANER }{}msx;

   my $material = ( eval $salt ).$args->{seed}; ## no critic

   return substr create_token( $material ), 0, 32;
}

sub _load_credentials {
   my ($self, $schema, $ctlfile, $db) = @_;

   my $data = $schema->load( $ctlfile ); my $creds = $data->{credentials};

   ($creds and exists $creds->{ $db })
      or throw error => 'Path [_1] database [_2] no credentials',
               args  => [ $ctlfile, $db ];

   return $data;
}

sub _run_db_cmd {
   my ($self, $admin_creds, $cmd, $opts) = @_; $admin_creds ||= {};

   my $drvr = lc $self->driver;
   my $host = $self->host || q(localhost);
   my $user = $admin_creds->{user} || $DB_ADMIN_IDS{ $drvr };
   my $pass = $admin_creds->{password} or return 'No database admin password';

   $cmd = "echo \"${cmd}\" | ";

   if ($drvr eq q(mysql) ) {
      $cmd .= "mysql -A -h ${host} -u ${user} -p${pass} mysql";
   }
   elsif ($drvr eq q(pg)) {
      $cmd .= "PGPASSWORD=${pass} psql -q -w -h ${host} -U ${user}";
   }

   $self->run_cmd( $cmd, { debug => $self->debug, err => q(stderr),
                           out   => q(stdout), %{ $opts || {} } } );
   return;
}

# Private subroutines

sub __inflate {
   local $_ = pop; s{ \A $KEY|[^ \t] }{}gmx; tr{ \t}{01}; return pack 'b*', $_;
}

1;

=pod

=head1 Name

CatalystX::Usul::Schema - Support for database schemas

=head1 Version

0.7.$Revision: 1181 $

=head1 Synopsis

   package CatalystX::Usul::Model::Schema;

   use parent qw(Catalyst::Model::DBIC::Schema
                 CatalystX::Usul::Model
                 CatalystX::Usul::Schema);

   package YourApp::Model::YourModel;

   use parent qw(CatalystX::Usul::Model::Schema);

   __PACKAGE__->config( database     => q(library),
                        schema_class => q(YourApp::Schema::YourSchema) );

   sub COMPONENT {
      my ($class, $app, $config) = @_;

      $config->{database    } ||= $class->config->{database};
      $config->{connect_info} ||=
         $class->get_connect_info( $app, $config->{database} );

      return $class->next::method( $app, $config );
   }

=head1 Description

Provides utility methods to classes inheriting from
L<DBIx::Class::Schema>

The encryption/decryption methods only B<obscure> the database password from
casual viewing, they do not in any way B<secure> it

=head1 Configuration and Environment

The XML data looks like this:

  <credentials>
    <name>database_we_want_to_connect_to</name>
    <driver>mysql</driver>
    <host>localhost</host>
    <password>encrypt=0QqX325DLs18I8T/wU4/ZQQ=</password>
    <port>3306</port>
    <print_error>0</print_error>
    <raise_error>1</raise_error>
    <user>root</user>
  </credentials>

=head1 Subroutines/Methods

=head2 schema_init

Called from the constructor of C<YourApp::Schema> this method initialiases
the attributes used by the other methods

=head2 create_database

Creates a database. Understands how to do this for different RDBMSs,
e.g. MySQL and PostgreSQL

=head2 create_ddl

Dump the database schema definition

=head2 create_schema

Creates a database then deploys and populates the schema

=head2 decrypt

   my $plain = $self->decrypt( $seed, $encoded );

Decodes and decrypts the C<$encoded> argument and returns the plain
text result. See the L</encrypt> method

=head2 deploy_and_populate

Create database tables and populate them with initial data. Called as
part of the application install

=head2 drop_database

Drops the database that is selected by the call to L</get_connect_info>

=head2 get_connect_info

   my $db_info_arr = $self->get_connect_info( $config, $database );

Returns an array ref containing the information needed to make a
connection to a database; DSN, user id, password, and options hash
ref. The data is read from the XML file in the config
I<ctrldir>. Multiple sets of data can be stored in the same file,
keyed by the C<$database> argument. The password is decrypted if
required. The password decrpytion can be seeded from a text file
in the I<ctrldir>

=head2 encrypt

   my $encrypted = $self->encrypt( $seed, $plain );

Encrypts the plain text passed in the C<$plain> argument and returns
it Base64 encoded. L<Crypt::Twofish_PP> is used to do the encryption. The
C<$seed> argument is passed to the L</_keygen> method

=head1 Private Methods

=head2 _edit_credentials

   $self->_edit_credentials( $config );

Writes the database login information stored in the C<$config> to the
application config file in the F<var/etc> directory. Called from
L</create_schema>

=head2 _encrypt_for_cfg

   $encrypted_value = $self->_encrypt_for_conf( $config, $plain )

Returns the encrypted value of the plain value prefixed appropriately
for storage in a config file. Called from L</_edit_credentials>

=head2 _keygen

Generates the key used by the L</encrypt> and L</decrypt> methods. Calls
L</_inflate> to create the salt. Note that the salt is C<eval>'d in string
context

=head1 Private Subroutines

=head2 __inflate

Lifted from L<Acme::Bleach> this recovers the default salt for the key
generator

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Base>

=item L<CatalystX::Usul::File>

=item L<Crypt::CBC>

=item L<Crypt::Twofish>

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

Copyright (c) 2011 Peter Flanigan. All rights reserved

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

__DATA__
			  	   
  		 	 	 
 		 	 			
  	   			
 	     	 
		 				 	
	 		  			
   	 			 
 			 		 	
    		 	 
		 		 	 	
  		  			
 	  			  
	   	 		 
	  	 		 	
 	  		 	 
			  	  
