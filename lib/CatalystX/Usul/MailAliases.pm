package CatalystX::Usul::MailAliases;

# @(#)$Id: MailAliases.pm 372 2009-03-05 17:39:15Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul CatalystX::Usul::Utils);
use Class::C3;
use English qw(-no_match_vars);
use File::Copy;
use Text::Wrap;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 372 $ =~ /\d+/gmx );

my $NUL = q();

__PACKAGE__->config( aliases_file => q(/etc/mail/aliases),
                     new_aliases  => q(newaliases),
                     commit       => 0, );

__PACKAGE__->mk_accessors( qw(aliases aliases_file file new_aliases
                              comment commit created found owner prog
                              recipients suid) );

sub new {
   my ($self, $app, @rest) = @_;

   my $new      = $self->next::method( $app, @rest );
   my $app_conf = $app->config || {};
   my $prog     = lc $app_conf->{prefix}.q(_misc);
   my $aliases  = $self->catfile( $app_conf->{ctrldir}, q(aliases) );

   $new->file( $new->file || $aliases );
   $new->prog( $new->prog || $self->catfile( $app_conf->{binsdir}, $prog ) );

   return $new;
}

sub create {
   my ($self, $flds) = @_; my ($cmd, $name, $res);

   $self->throw( q(eNoAliasName) ) unless ($name = $flds->{alias_name});

   $res = $self->retrieve( $name );

   $self->throw( error => q(eAliasExists), arg1 => $name ) if ($res->found);

   $cmd  = $self->suid.' -n -c aliases_update -- '.$name.' "';
   $cmd .= (join q(,), @{ $flds->{recipients} }).'" ';
   $cmd .= $flds->{owner}.' "'.$flds->{comment}.'" ';

   return $self->run_cmd( $cmd, { err => q(out) } )->out;
}

sub delete {
   my ($self, $name) = @_; my $res = $self->retrieve( $name );

   unless ($res->found) {
      $self->throw( error => q(eUnknownAlias), arg1 => $name );
   }

   my $cmd = $self->suid.' -n -c aliases_update -- '.$name;

   return $self->run_cmd( $cmd, { err => q(out) } )->out;
}

sub retrieve {
   my ($self, $name) = @_; my ($alias, $recipients);

   my $new = $self->_init();
   my $buf = $self->_read_file;

   $self->lock->reset( k => $self->file );

   my ($comment, $created, $owner) = ($NUL, $NUL, $NUL);

   for my $line (@{ $buf }) {
      if ($line && $line !~ m{ \A \# }mx
          && $line =~ m{ \A (([^:]+) : \s+) (.*) }mx) {
         $alias = $2; $recipients = $3;
         push @{ $new->aliases }, $alias;

         if ($name && $name eq $alias) {
            $new->found(   1 );
            $new->owner(   $owner );
            $new->created( $created );
            $new->comment( $comment );
            $recipients =~ s{ \s+ }{}gmx;
            $recipients =~ s{ , \z }{}mx;
            $new->recipients( [ split m{ , }mx, $recipients ] );
         }
      }
      elsif ($line && $line !~ m{ \A \# }mx
             && $alias && $name && $name eq $alias) {
         $line =~ s{ \s+ }{ }gmx;
         $line =~ s{ , \z }{}mx;
         push @{ $new->recipients }, split m{ , }mx, $line;
      }
      else { $alias = $NUL; $comment = $NUL }

      if ($line && $line =~ m{ \A \# }mx) {
         $line =~ s{ \A \# \s* }{}mx;

         if ($line =~ m{ \A Created \s+ by \s+ ([^ ]+) \s+ (.*) }mx) {
            $owner = $1; $created = $2;
         }
         else { $comment = $line }
      }
   }

   @{ $new->aliases } = sort { lc $a cmp lc $b } @{ $new->aliases };
   return $new;
}

sub update {
   my ($self, $flds) = @_; my ($cmd, $name, $res);

   $self->throw( q(eNoAliasName) ) unless ($name = $flds->{alias_name});

   $res = $self->retrieve( $name );

   unless ($res->found) {
      $self->throw( error => q(eUnknownAlias), arg1 => $name );
   }

   $cmd  = $self->suid.' -n -c aliases_update -- '.$name.' "';
   $cmd .= (join q(,), @{ $flds->{recipients} }).'" "" "';
   $cmd .= $flds->{comment}.'" ';

   return $self->run_cmd( $cmd, { err => q(out) } )->out;
}

sub update_file {
   my ($self, $alias, $recipients, $owner, $comment) = @_;
   my (@buf, $cmd, $created, $found, $func, $in_region);
   my ($key, $line, @lines, $pad, $res, $tempfile);

   $self->throw( q(eNoAlias) ) unless ($alias);

   $tempfile = $self->tempfile;
   ($key = $alias) =~ tr{ }{.};
   ($created, $found, $in_region) = ( $NUL, 0, 0 );

   for $line (@{ $self->_read_file }) {
      push @buf, $line;

      if ($line =~ m{ \A $key : }mx) {
         $line = $buf[0] && $buf[0] =~ m{ Created \s+ by }mx
               ? shift @buf : $NUL;

         if ($line && $line =~ m{ Created \s+ by \s+ ([^ ]+) \s+ (.*) }mx) {
            $owner = $1; $created = $2;
         }

         $comment  ||= $buf[0] ? shift @buf : $NUL;
         $in_region  = 1; $found = 1;
      }
      elsif (!$line) {
         $tempfile->println( @buf ) unless ($in_region);

         $in_region = 0; @buf = ();
      }
   }

   $tempfile->println( @buf ) if ($buf[0] && !$in_region);

   $func = $recipients ? q(update) : q(delete);

   if ($func eq q(update)) {
## no critic
      local $Text::Wrap::columns  = 80;
      local $Text::Wrap::unexpand = 0;
## critic

      if ($created) { $line = 'Created by '.$owner.q( ).$created }
      else { $line = 'Created by '.$owner.q( ).$self->stamp }

      $tempfile->println( wrap( '# ', '# ', $line ) );
      $tempfile->println( wrap( '# ', '# ', ($comment || q(-)) ) );
      $line = $recipients;
      $line =~ s{ \015 }{,}gmsx;
      $line =~ tr{ \n}{}d;
      $line =~ tr{,}{}s;
      $line =~ s{ , }{, }gmsx;
      $line = $key.q(: ).$line;
      $pad  = q( ) x ((length $key) + 2);
      $tempfile->println( wrap( $NUL, $pad, $line ), $NUL );
      $found = 1;
   }

   unless ($found) {
      $self->lock->reset( k => $self->file );
      $self->throw( error => q(eUnknownAlias), arg1 => $alias );
   }

   $tempfile->io_handle->flush;

   unless (copy( $tempfile->pathname, $self->file )) {
      $self->lock->reset( k => $self->file );
      $self->throw( error => $ERRNO );
   }

   $self->lock->reset( k => $self->file ); $tempfile->close;

   if ($self->new_aliases && -x $self->new_aliases) {
      unless (copy( $self->file, $self->aliases_file )) {
         $self->throw( error => $ERRNO );
      }

      $self->run_cmd( $self->new_aliases, { err => q(out) } );
   }

   if ($self->commit) {
      $cmd = $self->prog.' -n -c release -- commit '.$self->file;
      $self->run_cmd( $cmd, { err => q(out) } );
   }

   $func = $func eq q(delete)
         ? q(deleted) : $created
         ? q(updated) : q(created);
   return 'Mail alias '.$alias.q( ).$func;
}

# Private methods

sub _init {
   my $self = shift;

   return bless { aliases    => [],
                  comment    => $NUL,
                  created    => $NUL,
                  found      => 0,
                  owner      => $NUL,
                  recipients => [] }, ref $self;
}

sub _read_file {
   my $self = shift; my ($e, $buf, $line);

   unless (-s $self->file) {
      $self->throw( error => q(eNotFound), arg1 => $self->file );
   }

   $self->lock->set( k => $self->file );

   $buf = eval { [ $self->io( $self->file )->chomp->getlines ] };

   if ($e = $self->catch) {
      $self->lock->reset( k => $self->file ); $self->throw( $e );
   }

   return $buf;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::MailAliases - Manipulate the mail aliases file

=head1 Version

0.1.$Revision: 372 $

=head1 Synopsis

   use CatalystX::Usul::MailAliases;

   $alias_obj = CatalystX::Usul::MailAliases->new( $app, $config );

=head1 Description

Management model file the system mail alias file

=head1 Subroutines/Methods

=head2 new

Sets these attributes:

=over 3

=item aliases_file

The real mail alias file. Defaults to F</etc/mail/aliases>

=item commit

Boolean indicating whether source code control tracking is being
used. Defaults to I<false>

=item file

Path to the copy of the I<aliases> file that this module works on. Defaults
to I<aliases> in the I<ctrldir>

=item prog

Path to the I<appname>_misc program which is optionally used to
commit changes to the local copy of the aliases file to a source
code control repository

=item new_aliases

Path to the C<newaliases> program that is used to update the MTA
when changes are made

=item suid

Path to the C<suid> root wrapper program that is called to enable update
access to the real mail alias file

=back

=head2 create

   $alias_obj->create( $fields );

Create a new mail alias. Passes the fields to the C<suid> root
wrapper on the command line. The wrapper calls the L</update_file> method
to get the job done. Adds the text from the wrapper call to the results
section on the stash

=head2 delete

   $alias_obj->delete( $name );

Deletes the named mail alias. Calls L</update_file> via the C<suid>
wrapper. Adds the text from the wrapper call to the results section on
the stash

=head2 retrieve

   $response_obj = $alias_obj->retrieve( $name );

Returns an object containing a list of alias names and the fields pertaining
to the requested alias if it exists

=head2 update

   $alias_obj->update( $fields );

Update an existing mail alias. Calls L</update_file> via the C<suid> wrapper

=head2 update_file

   $alias_obj->update_file( $alias, $recipients, $owner, $comment );

Called from the C<suid> root wrapper this method updates the local copy
of the alias file as required and then copies the changed file to the
real system alias file. It will also run the C<newaliases> program and
commit the changes to a source code control system if one is being used

=head2 _init

Initialises these attributes in the object returned by L</retrieve>

=over 3

=item aliases

List of alias names

=item comment

Creation comment associated with the selected alias

=item created

Date the selected alias was created

=item found

Boolean indicating whether the selected alias was found in the alias file

=item owner

Who created the selected alias

=item recipients

List of recipients for the selected owner

=back

=head2 _read_file

Reads the local copy of the mail alias file with locking

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<Text::Wrap>

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
