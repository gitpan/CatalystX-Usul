# @(#)Ident: PostInstallConfig.pm 2013-08-19 19:17 pjf ;

package CatalystX::Usul::TraitFor::PostInstallConfig;

use namespace::sweep;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use Class::Usul::File;
use File::DataClass::Types  qw( NonEmptySimpleStr Path );
use Moo::Role;
use TryCatch;

requires qw( config );

has '_pic_file_name' => is => 'ro',   isa => NonEmptySimpleStr,
   default           => 'build.json', init_arg => 'pic_file_name',
   reader            => 'pic_file_name';

has '_pic_file_path' => is => 'lazy', isa => Path, coerce => Path->coercion,
   init_arg          => 'pic_file_path', reader => 'pic_file_path';

sub get_owner {
   my ($self, $pi_cfg) = @_; $pi_cfg ||= {};

   return ($self->options->{uid} || getpwnam( $pi_cfg->{owner} ) || 0,
           $self->options->{gid} || getgrnam( $pi_cfg->{group} ) || 0);
}

sub maybe_read_post_install_config {
   try { return $_[ 0 ]->read_post_install_config } catch {} return {};
}

{  my $cache;

   sub read_post_install_config {
      defined $cache and return $cache; my $paths = [ $_[ 0 ]->pic_file_path ];

      return $cache = Class::Usul::File->data_load( paths => $paths );
   }

   sub write_post_install_config {
      Class::Usul::File->data_dump
         ( path => $_[ 0 ]->pic_file_path, data => $cache = $_[ 1 ], );
      return;
   }
}

# Private methods
sub _build__pic_file_path {
   return [ $_[ 0 ]->config->ctrldir, $_[ 0 ]->pic_file_name ];
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Traitfor::PostInstallConfig - Reads and writes the post installation configuration file

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   use CatalystX::Usul::Moose;

   with q(CatalystX::Usul::Traitfor::PostInstallConfig);

=head1 Description

Reads and writes the post installation configuration file

=head1 Configuration and Environment

Requires the I<config> attribute. Defines the following list of attributes;

=over 3

=item pic_file_name

Name of the post installation configuration file. Defaults to
F<build.json>

=item pic_file_path

Path to the post installation configuration file. Defaults to
F<var/etc/build.json>

=back

=head1 Subroutines/Methods

=head2 get_owner

   ($uid, $gid) = $self->get_owner( $picfg_hash_ref );

Returns the application owner and group ids

=head2 maybe_read_post_install_config

   $hash_ref = $self->maybe_read_post_install_config;

Like L</read_post_install_config> but returns an empty hash ref if the file
does not exist

=head2 read_post_install_config

   $picfg_hash_ref = $self->read_post_install_config;

Returns a hash ref of the post installation config which was written to
the control directory during the installation process

=head2 write_post_install_config

   $self->write_post_install_config( $data );

Writes the hash ref of post install configuration information to a file
in the control directory

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul::File>

=item L<Moose::Role>

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
