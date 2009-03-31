package CatalystX::Usul::InflateSymbols;

# @(#)$Id: InflateSymbols.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Base);
use Config;
use Cwd qw(abs_path);
use File::Spec;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

__PACKAGE__->mk_accessors( qw(_application) );

sub new {
   my ($proto, $app) = @_;

   return bless { _application => $app }, ref $proto || $proto;
}

sub appldir {
   my $self = shift; my $conf = $self->_application->config; my $dir;

   if (!$conf->{appldir} || $conf->{appldir} =~ m{ __APPLDIR__ }mx) {
   TRY: {
      $dir = $ENV{ $self->env_prefix( $conf->{name} ).q(_APPL) };

      last TRY if ($dir and -d $dir);

      $dir = $self->dirname( $Config{sitelibexp} );

      if ($conf->{home} =~ m{ \A $dir }mx) {
         $dir = $self->catdir( File::Spec->rootdir,
                               'var', $conf->{prefix}, 'default' );
         last TRY if ($dir and -d $dir);
      }

      $dir = $self->home2appl( $conf->{home} );
   } # TRY
      $conf->{appldir} = abs_path( $dir );
   }

   return $conf->{appldir};
}

sub binsdir {
   my $self = shift; my $conf = $self->_application->config; my $dir;

   if (!$conf->{binsdir} || $conf->{binsdir} =~ m{ __BINSDIR__ }mx) {
      $dir = $self->dirname( $Config{sitelibexp} );

      if ($conf->{home} =~ m{ \A $dir }mx) { $dir = $Config{scriptdir} }
      else { $dir = $self->catdir( $self->home2appl( $conf->{home} ), 'bin' ) }

      $conf->{binsdir} = abs_path( $dir );
   }

   return $conf->{binsdir};
}

sub libsdir {
   my $self = shift; my $conf = $self->_application->config; my $dir;

   if (!$conf->{libsdir} || $conf->{libsdir} =~ m{ __LIBSDIR__ }mx) {
      $dir = $self->dirname( $Config{sitelibexp} );

      if ($conf->{home} =~ m{ \A $dir }mx) { $dir = $Config{sitelibexp} }
      else { $dir = $self->catdir( $self->home2appl( $conf->{home} ), 'lib' ) }

      $conf->{libsdir} = abs_path( $dir );
   }

   return $conf->{libsdir};
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::InflateSymbols - Return paths to installation directories

=head1 Version

0.1.$Revision: 402 $

=head1 Synopsis

   package MyApp;

   use Catalyst qw(InflateMore ConfigLoader ...);

   MyApp->config->{InflateMore} = 'MyApp::Config';

   package MyApp::Config;

   use base qw(CatalystX::Usul::InflateSymbols);

=head1 Description

The intention here is to demonstrate how to use
L<Catalyst::Plugin::InflateMore>. It is unlikely that anyone will find
this module useful unless your share my view on application
layout. Instead write your own class that implements the methods for
the configuration file symbols of your choice.

My applications are divided into three parts by the installer. Since
the installer supports multiple layouts these methods will return
paths to each of those components. These methods are called from
L<Catalyst::Plugin::InflateMore>.

=head1 Subroutines/Methods

=head2 new

The constructor stores a copy of the application object

=head2 appldir

Return absolute path to the directory which defines the phase number

=head2 binsdir

Return absolute path to the directory containing the programs

=head2 libsdir

Return absolute path to the directory containing the modules

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Base>

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
