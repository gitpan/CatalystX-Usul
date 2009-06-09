# @(#)$Id: Schema.pm 562 2009-06-09 16:11:18Z pjf $

package CatalystX::Usul::Model::Schema;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.2.%d', q$Rev: 562 $ =~ /\d+/gmx );
use parent qw(Catalyst::Model::DBIC::Schema
              CatalystX::Usul::Model
              CatalystX::Usul::Schema);

use Class::C3;

sub new {
   my ($self, $app, @rest) = @_;

   my $new   = $self->next::method( $app, @rest );
   my $model = CatalystX::Usul::Model->new( $app, @rest );

   $new->{ $_ } = $model->{ $_ } for (keys %{ $model });

   return $new;
}

sub connect_info {
   my ($self, $app, $db) = @_; my ($args, $dir, $info, $path);

   if ($db and $dir = $app->config->{ctrldir}) {
      $path = $self->catfile( $dir, $app->config->{prefix}.q(.txt) );
      $args = { seed => $app->config->{secret} || $app->config->{prefix} };
      $args->{data} = $self->io( $path )->all if (-f $path);
      $info = $self->next::method( $self->catfile( $dir, $db.q(.xml) ),
                                   $db, $args );
   }
   else { $app->log->error( "${self}: No database or directory\n" ) }

   return $info;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Schema - Base class for database models

=head1 Version

0.1.$Revision: 562 $

=head1 Synopsis

   package YourApp::Model::YourModel;

   use base qw(CatalystX::Usul::Model::Schema);

   __PACKAGE__->config
      ( connect_info => [],
        database     => q(library),
        schema_class => q(YourApp::Schema::YourSchema) );

   sub new {
      my ($class, $app, @rest) = @_;

      my $database = $rest[0]->{database} || $class->config->{database};

      $class->config( connect_info
                         => $class->connect_info( $app, $database ) );

      return $class->next::method( $app, @rest );
   }

=head1 Description

Aggregates the methods from the three classes it inherits from

=head1 Subroutines/Methods

=head2 new

Adds the attributes from L<CatalystX::Usul::Model> to the ones from
L<Catalyst::Model::DBIC::Schema>

=head2 connect_info

Calls parent method to obtain dsn, user and password information from
configuration file before instantiating the database classes

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Catalyst::Model::DBIC::Schema>

=item L<CatalystX::Usul::Model>

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
