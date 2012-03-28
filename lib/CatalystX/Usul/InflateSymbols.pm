# @(#)$Id: InflateSymbols.pm 1072 2011-10-29 18:51:11Z pjf $

package CatalystX::Usul::InflateSymbols;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1072 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Base CatalystX::Usul::File);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(class2appdir home2appl untaint_path);
use Config;

require Cwd;

my @METHODS = qw(appldir binsdir phase);

__PACKAGE__->mk_accessors( qw(_config) );

sub new {
   my ($self, $app) = @_;

   my $conf = ref $app ? $app->{config} : $app->config;

   return bless { _config => $conf }, ref $self || $self;
}

sub appldir {
   my $self = shift; my $conf = $self->_config; my $dir;

   if (not $conf->{appldir} or $conf->{appldir} =~ m{ __APPLDIR__ }msx) {
      $dir = $self->dirname( $Config{sitelibexp} );
      $dir = $conf->{home} =~ m{ \A $dir }msx
           ? $self->catdir( NUL, qw(var www), class2appdir $conf->{name},
                            q(default) )
           : home2appl $conf->{home};
      $conf->{appldir} = Cwd::abs_path( $dir );
   }

   return $conf->{appldir};
}

sub binsdir {
   my $self = shift; my $conf = $self->_config; my $dir;

   if (not $conf->{binsdir} or $conf->{binsdir} =~ m{ __BINSDIR__ }msx) {
      $dir = $self->dirname( $Config{sitelibexp} );
      $dir = $conf->{home} =~ m{ \A $dir }msx
           ? $Config{scriptdir}
           : $self->catdir( home2appl $conf->{home}, q(bin) );
      $conf->{binsdir} = Cwd::abs_path( $dir );
   }

   return $conf->{binsdir};
}

sub inflate_symbols {
   my ($self, $symbols) = @_; my $conf = $self->_config; $symbols or return;

   for my $k (keys %{ $symbols }) {
      my $v = defined $conf->{ $k } ? $conf->{ $k }
            : ref $symbols->{ $k }  ? $self->_expand( $symbols->{ $k } )
                                    : $symbols->{ $k };

   TRY: {
      $v =~ m{ __appldir\( (.*) \)__ }msx
         and $v = $self->catdir( $conf->{appldir}, $1 ) and last TRY;

      $v =~ m{ __binsdir\( (.*) \)__ }msx
         and $v = $self->catdir( $conf->{binsdir}, $1 ) and last TRY;

      $v =~ m{ __path_to\( (.*) \)__ }msx
         and $v = $self->catdir( $conf->{home}, $1 );
      } # TRY

      $v and $v = untaint_path( $v ) and -e $v and $v = Cwd::abs_path( $v );

      $conf->{ $k } = $v;
   }

   return;
}

sub phase {
   my $self = shift; my $conf = $self->_config; my $dir;

   if (not $conf->{phase} or $conf->{phase} =~ m{ __PHASE__ }msx) {
      my $dir     = $self->basename( $self->appldir );
      my ($phase) = $dir =~ m{ \A v \d+ [.] \d+ p (\d+) \z }msx;

      $conf->{phase} = defined $phase ? $phase : PHASE;
   }

   return $conf->{phase};
}

sub visit_all {
   my $self = shift; $self->$_() for (@METHODS); return;
}

# Private methods

sub _expand {
   my ($self, $args) = @_;

   return '__appldir('.$self->catdir( @{ $args } ).')__';
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::InflateSymbols - Return paths to installation directories

=head1 Version

0.4.$Revision: 1072 $

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

=head2 inflate_symbols

Takes a hash ref of config key and values. Inflates and untaints (as
file paths) the values

=head2 phase

Return the phase number derived from the L</appldir>

=head2 visit_all

Calls each of the other object methods thereby inflating each value

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul>

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
