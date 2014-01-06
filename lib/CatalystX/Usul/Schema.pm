# @(#)Ident: Schema.pm 2014-01-06 12:41 pjf ;

package CatalystX::Usul::Schema;

use strict;
use namespace::sweep;
use version;  our $VERSION = qv( sprintf '0.15.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Moo;
use CatalystX::Usul::Constants;
use Class::Usul::Crypt::Util qw( encrypt_for_config );
use Class::Usul::Functions   qw( distname ensure_class_loaded );
use Class::Usul::Options;
use Class::Usul::Types       qw( ArrayRef Bool HashRef NonEmptySimpleStr Str );

extends q(Class::Usul::Programs);
with    q(CatalystX::Usul::TraitFor::ConnectInfo);

# Public attributes
option 'attrs'          => is => 'ro',   isa => HashRef,
   documentation        => 'Default database connection attributes',
   default              => sub { { add_drop_table => TRUE,
                                   no_comments    => TRUE, } },
   init_arg             => 'dbattrs';

option 'database'       => is => 'ro',   isa => NonEmptySimpleStr,
   documentation        => 'The database to connect to',
   required             => TRUE;

option 'db_admin_ids'   => is => 'ro',   isa => HashRef,
   documentation        => 'The admin user ids for each RDBMS',
   default              => sub { { mysql => 'root', pg => 'postgres', } };

option 'preversion'     => is => 'ro',   isa => Str, default => NUL,
   documentation        => 'Previous schema version';

option 'rdbms'          => is => 'ro',   isa => ArrayRef,
   documentation        => 'List of RDBMSs',
   default              => sub { [ qw( MySQL PostgreSQL ) ] };

option 'schema_classes' => is => 'lazy', isa => HashRef, default => sub { {} },
   documentation        => 'The database schema classes';

option 'schema_version' => is => 'ro',   isa => NonEmptySimpleStr,
   documentation        => 'Current schema version',
   default              => '0.1';

option 'unlink'         => is => 'ro',   isa => Bool, default => FALSE,
   documentation        => 'If true remove DDL file before creating new ones';

option 'yes'            => is => 'ro',   isa => Bool, default => FALSE,
   documentation        => 'When true flips the defaults for yes/no questions',
   short                => 'y';

has 'paragraph'         => is => 'ro',   isa => HashRef,
   default              => sub { { cl => TRUE, fill => TRUE, nl => TRUE } };

# Private attributes
has '_connect_info' => is => 'lazy', isa => ArrayRef, init_arg => undef,
   reader           => 'connect_info';

# Public methods
sub create_database : method {
   my $self = shift; my $cmd;

   my $host = $self->host; my $database = $self->database;
   my $user = $self->user; my $password = $self->password;

   my $admin_creds = $self->_get_db_admin_creds( 'create database' );

   if (lc $self->driver eq 'mysql') {
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

   if (lc $self->driver eq 'pg') {
      $self->info( "Creating PostgreSQL database ${database}" );
      $cmd  = "create role ${user} login password '${password}';";
      $self->_run_db_cmd( $admin_creds, $cmd );
      $cmd  = "create database ${database} owner ${user} encoding 'UTF8';";
      $self->_run_db_cmd( $admin_creds, $cmd );
      return OK;
   }

   $self->warning( 'Create database failed: Unknown driver '.$self->driver );
   return FAILED;
}

sub create_ddl : method {
   my $self = shift; $self->output( 'Creating DDL for '.$self->dsn );

   for my $schema_class (values %{ $self->schema_classes }) {
      ensure_class_loaded( $schema_class );
      $self->_create_ddl( $schema_class, $self->config->dbasedir );
   }

   return OK;
}

sub create_schema : method { # Create databases and edit credentials
   my $self    = shift;
   my $text    = 'Schema creation requires a database, id and password. ';
      $text   .= 'For Postgres the driver is Pg and the port 5432';
   my $default = $self->yes;

   $self->output( $text, $self->paragraph );

   $self->yorn( 'Create database schema', $default, TRUE, 0 ) or return OK;

   # Edit the config file that contains the database connection info
   $self->edit_credentials;
   # Create the database if we can. Will do nothing if we can't
   $self->create_database and return OK;
   # Call DBIx::Class::deploy to create schema and populate it with static data
   $self->deploy_and_populate;
   return OK;
}

sub dbattrs {
   my $self = shift; my $attrs = $self->connect_info->[ 3 ];

   $attrs->{ $_ } = $self->attrs->{ $_ } for (keys %{ $self->attrs });

   return $attrs;
}

sub deploy_and_populate : method {
   my $self = shift; $self->output( 'Deploy and populate for '.$self->dsn );

   for my $schema_class (values %{ $self->schema_classes }) {
      ensure_class_loaded( $schema_class );
      $self->_deploy_and_populate( $schema_class, $self->config->dbasedir );
   }

   return OK;
}

sub driver {
   return (split m{ [:] }mx, $_[ 0 ]->dsn)[ 1 ];
}

sub drop_database : method {
   my $self = shift; my $database = $self->database; my $cmd;

   my $host = $self->host; my $user = $self->user;

   my $admin_creds = $self->_get_db_admin_creds( 'drop database' );

   $self->info( "Droping database ${database}" );

   if (lc $self->driver eq 'mysql') {
      $cmd = "drop database if exists ${database};";
      $self->_run_db_cmd( $admin_creds, $cmd );
      $cmd = "drop user '${user}'".'@'."'${host}';";
      $self->_run_db_cmd( $admin_creds, $cmd, { expected_rv => 1 } );
      return OK;
   }

   if (lc $self->driver eq 'pg') {
      $self->_run_db_cmd( $admin_creds, "drop database ${database};" );
      $self->_run_db_cmd( $admin_creds, "drop user ${user};" );
      return OK;
   }

   $self->error( "Failed to drop database ${database}" );
   return FAILED;
}

sub dsn {
   return $_[ 0 ]->connect_info->[ 0 ];
}

sub edit_credentials : method {
   my $self      = shift;
   my $self_cfg  = $self->config;
   my $db        = $self->database;
   my $bootstrap = $self->options->{bootstrap};
   my $cfg_data  = $bootstrap ? {} : $self->load_config_data( $self_cfg, $db );
   my $creds     = $bootstrap ? {}
                 : $self->extract_creds_from( $self_cfg, $db, $cfg_data );
   my $prompts   = { name     => 'Enter db name',
                     driver   => 'Enter DBD driver',
                     host     => 'Enter db host',
                     port     => 'Enter db port',
                     user     => 'Enter db user',
                     password => 'Enter db password' };
   my $defaults  = { name     => $db,
                     driver   => '_field',
                     host     => 'localhost',
                     port     => '_field',
                     user     => '_field',
                     password => NUL };

   for my $field (qw( name driver host port user password )) {
      my $value = $defaults->{ $field } ne '_field' ? $defaults->{ $field }
                :                                        $creds->{ $field };

      $value = $self->get_line( $prompts->{ $field }, $value, TRUE, 0, FALSE,
                                $field eq 'password' ? TRUE : FALSE );

      $field eq 'password' and $value
         = encrypt_for_config( $self_cfg, $value, $creds->{password} );

      $creds->{ $field } = $value || NUL;
   }

   $cfg_data->{credentials}->{ $creds->{name} } = $creds;
   $self->dump_config_data( $self_cfg, $creds->{name}, $cfg_data );
   return OK;
}

sub host {
   return (split m{ [=] }mx, (split m{ [;] }mx, $_[ 0 ]->dsn)[ 1 ])[ 1 ];
}

sub password {
   return $_[ 0 ]->connect_info->[ 2 ];
}

sub user {
   return $_[ 0 ]->connect_info->[ 1 ];
}

# Private methods
sub _build__connect_info {
   my $self = shift;

   return $self->get_connect_info( $self, { database => $self->database } );
}

sub _create_ddl {
   my ($self, $schema_class, $dir) = @_;

   my $schema  = $schema_class->connect( $self->dsn, $self->user,
                                         $self->password, $self->dbattrs );
   my $version = $self->schema_version;

   if ($self->unlink) {
      for my $rdb (@{ $self->rdbms }) {
         my $path = $self->io( $schema->ddl_filename( $rdb, $version, $dir ) );

         $path->is_file and $path->unlink;
      }
   }

   $schema->create_ddl_dir( $self->rdbms, $version, $dir,
                            $self->preversion, $self->dbattrs );
   return;
}

sub _deploy_and_populate {
   my ($self, $schema_class, $dir) = @_; my $res;

   my $schema = $schema_class->connect( $self->dsn, $self->user,
                                        $self->password, $self->dbattrs );

   $self->info( "Deploying schema ${schema_class} and populating" );
   $schema->storage->ensure_connected; $schema->deploy( $self->dbattrs, $dir );

   my $dist = distname $schema_class;
   my $extn = $self->config->extension;
   my $re   = qr{ \A $dist [-] \d+ [-] (.*) \Q$extn\E \z }mx;
   my $io   = $self->io( $dir )->filter( sub { $_->filename =~ $re } );

   for my $path ($io->all_files) {
      my ($class) = $path->filename =~ $re;

      if ($class) { $self->output( "Populating ${class}" ) }
      else        { $self->fatal ( 'No class in [_1]', $path->filename ) }

      my $hash = $self->file->dataclass_schema->load( $path );
      my $flds = [ split SPC, $hash->{fields} ];
      # TODO: Use Data::Record
      my @rows = map { [ map    { s{ \A [\'\"] }{}mx; s{ [\'\"] \z }{}mx; $_ }
                         split m{ , \s* }mx, $_ ] } @{ $hash->{rows} };

      @{ $res->{ $class } } = $schema->populate( $class, [ $flds, @rows ] );
   }

   return;
}

sub _get_db_admin_creds {
   my ($self, $reason) = @_;

   my $attrs  = { password => NUL, user => NUL, };
   my $text   = 'Need the database administrators id and password to perform ';
      $text  .= "a ${reason} operation";

   $self->output( $text, $self->paragraph );

   my $prompt = 'Database administrator id';
   my $user   = $self->db_admin_ids->{ lc $self->driver } || NUL;

   $attrs->{user    } = $self->get_line( $prompt, $user, TRUE, 0 );
   $prompt    = 'Database administrator password';
   $attrs->{password} = $self->get_line( $prompt, NUL, TRUE, 0, FALSE, TRUE );
   return $attrs;
}

sub _run_db_cmd {
   my ($self, $admin_creds, $cmd, $opts) = @_; $admin_creds ||= {};

   my $drvr = lc $self->driver;
   my $host = $self->host || 'localhost';
   my $user = $admin_creds->{user} || $self->db_admin_ids->{ $drvr };
   my $pass = $admin_creds->{password}
      or $self->fatal( 'No database admin password' );

   $cmd = "echo \"${cmd}\" | ";

   if ($drvr eq 'mysql' ) {
      $cmd .= "mysql -A -h ${host} -u ${user} -p${pass} mysql";
   }
   elsif ($drvr eq 'pg') {
      $cmd .= "PGPASSWORD=${pass} psql -q -w -h ${host} -U ${user}";
   }

   $self->run_cmd( $cmd, { debug => $self->debug,
                           out   => 'stdout', %{ $opts || {} } } );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Schema - Support for database schemas

=head1 Version

Describes v0.15.$Rev: 1 $

=head1 Synopsis

   package YourApp::Schema;

   use CatalystX::Usul::Moose;
   use Class::Usul::Functions qw(arg_list);
   use YourApp::Schema::Authentication;
   use YourApp::Schema::Catalog;

   extends qw(CatalystX::Usul::Schema);

   my %ATTRS  = ( database          => 'library',
                  schema_classes    => {
                     authentication => 'YourApp::Schema::Authentication',
                     catalog        => 'YourApp::Schema::Catalog', }, );

   sub new_with_options {
      my ($self, @rest) = @_; my $attrs = arg_list @rest;

      return $self->next::method( %ATTRS, %{ $attrs } );
   }

=head1 Description

Methods used to install and uninstall database applications

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item C<attrs>

Hash ref which defaults to
C<< { add_drop_table => TRUE, no_comments => TRUE, } >>. It has an
initialisation argument of C<dbattrs>

=item C<database>

String which is required

=item C<db_admin_ids>

Hash ref which defaults to C<< { mysql => 'root', pg => 'postgres', } >>

=item C<paragraph>

Hash ref which defaults to C<< { cl => TRUE, fill => TRUE, nl => TRUE } >>

=item C<preversion>

String which defaults to null

=item C<rdbms>

Array ref which defaults  to C<< [ qw(MySQL PostgreSQL) ] >>

=item C<schema_classes>

Hash ref which defaults to C<< {} >>

=item C<schema_version>

String which defaults to C<0.1>

=item C<unlink>

Boolean which defaults to false

=item C<yes>

Boolean which defaults to false. When true flips the defaults for
yes/no questions

=back

=head1 Subroutines/Methods

=head2 create_database - Creates a database

   $self->create_database;

Understands how to do this for different RDBMSs, e.g. MySQL and PostgreSQL

=head2 create_ddl - Dump the database schema definition

   $self->create_ddl;

Creates the DDL for multiple RDBMs

=head2 create_schema - Creates a database then deploys and populates the schema

   $self->create_schema;

Calls L<create_database> followed by L<deploy_and_populate>

=head2 dbattrs

   $self->dbattrs;

Merges the C<attrs> attribute with the database attributes returned by the
L<get_connect_info|CatalystX::Usul::TraitFor::ConnectInfo/get_connect_info>
method

=head2 deploy_and_populate - Create tables and populates them with initial data

   $self->deploy_and_populate;

Called as part of the application install

=head2 driver

   $self->driver;

The database driver string, derived from the L</dsn> method

=head2 drop_database - Drops a database

   $self->drop_database;

The database is selected by the C<database> attribute

=head2 dsn

   $self->dsn;

Returns the DSN from the call to
L<get_connect_info|CatalystX::Usul::TraitFor::ConnectInfo/get_connect_info>

=head2 edit_credentials - Edits the database login information

   $self->edit_credentials;

Encrypts the database connection password before storage

=head2 host

   $self->host;

Returns the hostname of the database server derived from the call to
L</dsn>

=head2 password

   $self->password;

The unencrypted password used to connect to the database

=head2 user

   $self->user;

The user id used to connect to the database

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::TraitFor::ConnectInfo>

=item L<CatalystX::Usul::TraitFor::PostInstallConfig>

=item L<CatalystX::Usul::Moose>

=item L<Class::Usul::Programs>

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
