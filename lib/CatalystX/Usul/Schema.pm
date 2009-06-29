# @(#)$Id: Schema.pm 580 2009-06-11 16:44:10Z pjf $

package CatalystX::Usul::Schema;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 580 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul);

use Crypt::CBC;
use English qw(-no_match_vars);
use MIME::Base64;
use Sys::Hostname;
use XML::Simple;

my $CLEANER = '.*^\s*use\s+Acme::Bleach\s*;\r*\n';
my $KEY     = " \t" x 8;
my $NUL     = q();
my $DATA    = do { local $RS = undef; <DATA> };

__PACKAGE__->mk_accessors( qw(attrs databases) );

sub connect_info {
   my ($self, $path, $db, $seed) = @_; my ($attr, $cfg, $dsn);

   if ($cfg = $self->_read_config( $path )->{ $db }) {
      $dsn  = 'dbi:'.$cfg->{driver}.':database='.$db.';host=';
      $dsn .= $cfg->{host}.';port='.$cfg->{port};
      $attr = { AutoCommit => 1,
                PrintError => $cfg->{print_error} || 0,
                RaiseError => $cfg->{raise_error} || 1 };

      if ($cfg->{password} =~ m{ \A encrypt= (.+) \z }mx) {
         $cfg->{password} = $self->decrypt( $seed, $1 );
      }

      return [ $dsn, $cfg->{user}, $cfg->{password}, $attr ];
   }

   return [ $NUL, $NUL, $NUL, {} ];
}

sub create_ddl {
   my ($self, $dbh, $version, $dir, $unlink) = @_;

   if ($unlink) {
      for my $db (@{ $self->databases }) {
         my $path = $dbh->ddl_filename( $db, $version, $dir );

         unlink $path if (-f $path);
      }
   }

   $dbh->storage->create_ddl_dir( $dbh,
                                  $self->databases,
                                  $version,
                                  $dir,
                                  $self->attrs );
   return 0;
}

sub decrypt {
   my ($self, $seed, $encoded) = @_;

   return unless ($encoded);

   my $cipher = Crypt::CBC->new( -cipher => q(Twofish),
                                 -key    => $self->keygen( $seed ) );

   return $cipher->decrypt( decode_base64( $encoded ) );
}

sub deploy_and_populate {
   my ($self, $dbh, $dir, $schema) = @_;
   my ($cfg, $class, $flds, $hndl, $path, @paths, $re, $res, @rows, $xs);

   $dbh->storage->ensure_connected;
   $dbh->deploy( $self->attrs, $dir );

   $schema =~ s{ :: }{-}gmx;
   $re     = '\A '.$schema.' [-] \d+ [-] (.*) \.xml \z';
   $xs     = XML::Simple->new( ForceArray => [ qw(rows) ] );
   $hndl   = $self->io( $dir );

   while ($path = $hndl->next) {
      push @paths, $path if ($path->filename =~ m{ $re }mx);
   }

   $hndl->close;

   for $path (sort { $a->filename cmp $b->filename } @paths) {
      ($class) = $path->filename =~ m{ $re }mx;
      $self->fatal( 'No class in [_1]', $path->filename ) unless ($class);
      $self->output( "Populating $class" );
      $cfg  = $xs->xml_in( $path->pathname );
      $flds = [ split q( ), $cfg->{fields} ];
      @rows = map { [ map { my $row = $_;
                            $row =~ s{ \A [\'\"] }{}mx;
                            $row =~ s{ [\'\"] \z }{}mx; $row }
                      split m{ , \s* }mx, $_ ] } @{ $cfg->{rows} };
      @{ $res->{ $class } } = $dbh->populate( $class, [ $flds, @rows ] );
   }

   return 0;
}

sub encrypt {
   my ($self, $seed, $plain) = @_;

   return unless ($plain);

   my $cipher = Crypt::CBC->new( -cipher => q(Twofish),
                                 -key    => $self->keygen( $seed ) );

   return encode_base64( $cipher->encrypt( $plain ), $NUL );
}

sub keygen {
   my ($self, $args) = @_;

   $args = { seed => $args || $NUL } unless ($args && ref $args eq q(HASH));

   (my $salt = _inflate( $args->{data} || $DATA )) =~ s{ $CLEANER }{}msx;

   ## no critic
   return substr $self->create_token( ( eval $salt ).$args->{seed} ), 0, 32;
   ## critic
}

# Private methods

sub _inflate {
   local $_ = pop; s{ \A $KEY|[^ \t] }{}gmx; tr{ \t}{01}; return pack 'b*', $_;
}

sub _read_config {
   my ($self, $path) = @_;

   my $xs   = XML::Simple->new();
   my $text = join $NUL,
              grep { !m{ <! .+ > }mx } $self->io( $path )->lock->getlines;
   my $cfg  = $xs->xml_in( $text, ForceArray => [ q(credentials) ] ) || {};

   return $cfg->{credentials} ? $cfg->{credentials} : {};
}

1;

=pod

=head1 Name

CatalystX::Usul::Schema - Support for database schemas

=head1 Version

0.3.$Revision: 580 $

=head1 Synopsis

   package CatalystX::Usul::Model::Schema;

   use parent qw(Catalyst::Model::DBIC::Schema
                 CatalystX::Usul::Model
                 CatalystX::Usul::Schema);

   package YourApp::Model::YourModel;

   use base qw(CatalystX::Usul::Model::Schema);

   __PACKAGE__->config( connect_info => [], schema_class => undef );

   sub new {
      my ($self, $app, @rest) = @_;

      $self->config( connect_info =>
                      $self->connect_info( $app, $rest[0]->{database} ) );
      $self->config( schema_class => $rest[0]->{schema_class} );

      return $self->next::method( $app, @rest );
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

=head2 connect_info

   my $info_arr = $self->connect_info( $path, $database, $seed );

Returns an array ref containing the information needed to make a
connection to a database; DSN, user id, password, and options hash
ref. The data is read from the XML file C<$path>. Multiple sets of
data can be stored in the same file, keyed by the C<$database>
argument. The password is decrypted if required. The C<$seed> argument
is an application dependant constant string that is used to perturb
the key generator

=head2 create_ddl

Dump the database schema definition

=head2 decrypt

   my $plain = $self->decrypt( $seed, $encoded );

Decodes and decrypts the C<$encoded> argument and returns the plain
text result. See the C<encrypt> method

=head2 deploy_and_populate

Create database tables and populate them with initial data. Called as
part of the application install

=head2 encrypt

   my $encrypted = $self->encrypt( $seed, $plain );

Encrypts the plain text passed in the C<$plain> argument and returns
it Base64 encoded. L<Crypt::Twofish_PP> is used to do the encryption. The
C<$seed> argument is passed to the C<keygen> method

=head2 keygen

Generates the key used by the C<encrypt> and C<decrypt> methods. Calls
C<_inflate> to create the salt. Note that the salt is C<eval>'d in string
context

=head2 _inflate

Lifted from L<Acme::Bleach> this recovers the default salt for the key
generator

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul>

=item L<Crypt::CBC>

=item L<Crypt::Twofish>

=item L<XML::Simple>

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

__DATA__
 	 	 	 	 	 	 	 			   	  	
    	  		
		 	  	 	
 			 		  
			  	  	
		 				 	
   	   		
 	  	 		 
 			 		 	
			 	    
  			 	 	
  		  	  
			   		 
		 	 		  
   	 	   
 	 		    
 	 	    	
 	 			 		
  			 	 	
  		     
 	  	    
 	 		   	
	 	 		 		
 	 	  		 
 	 			   
	 			   	
    	   	
	 		 	 	 
 		 	    
		 		   	
	    	 		
 		 			  
	 		     
	 	    		
	  	     
		 	 	  	
	 	 			  
	   			 	
     	 		
 				 		 
		  			  
 	 			  	
		 		 	  
  		 	 		
 		 	 	  
		  			 	
  			  	 
  	 		 	 
 	 		 	 	
		  	   	
		 	     
	 	  			 
 		 	 	  
		   	 		
	     			
 			 			 
	 	 			 	
  	 		   
	  		    
  	    	 
 	   	  	
 	 	 	   
	 	     	
   		  	 
					 	 	
 	 	 	 		
  	 	 	 	
   	  	  
	 	 					
 	 	  	  
	   	   	
 	  	 	  
 			 	  	
		  	  	 
 		 	 			
  	  	 		
     	 	 
   
