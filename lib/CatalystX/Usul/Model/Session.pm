package CatalystX::Usul::Model::Session;

# @(#)$Id: Session.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Model);
use CatalystX::Usul::Table;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

sub list_sessions {
   my $self = shift; my $c = $self->context; my $s = $c->stash; my $e;

   my @sessions = eval { $c->list_sessions };

   return $self->add_error( $e ) if ($e = $self->catch);

   my $expires = $s->{max_sess_time} || 7_200; my $now = time; my @values = ();

   for my $session (@sessions) {
      my ($sid) = $session->{key} =~ m{ \A session: (.*) \z }mx; my $value;

      next unless ($sid and $value = $session->{value});

      my $last_updated = $value->{__updated} || 0;

      if (exists $value->{__user} && $now < $last_updated + $expires) {
         my $user_obj = eval { $value->{__user} };

         push @values,
            { address  => $value->{__address},
              created  => $self->stamp( $value->{__created} || 0 ),
              realm    => $value->{__user_realm},
              sid      => $sid,
              updated  => $self->stamp( $last_updated ),
              username => $user_obj ? $user_obj->username : q(unknown) };
      }
   }

   my $nitems = 0;

   if (my $count = scalar @values) {
      my $data    = CatalystX::Usul::Table->new
         ( count  => $count,
           flds   => [ qw(username realm sid address created updated) ],
           labels => { address => 'Address', created  => 'Created',
                       realm   => 'Realm',   sid      => 'Session Id',
                       updated => 'Updated', username => 'User' },
           values => [ sort { $a->{username} cmp $b->{username} } @values ] );

      $self->add_field( { data   => $data,
                          select => q(left), type => q(table) } );
      $nitems++;
      $self->add_buttons( qw(Delete) );
   }

   $self->group_fields( { nitems => $nitems,
                          text   => $self->loc( 'Catalyst Sessions' ) } );
   return;
}

sub list_TTY_sessions {
   my $self = shift; my $s = $self->context->stash; my $e;

   my $data = eval { $self->_list_TTY_sessions( $s->{user_model} ) };

   $self->add_error( $e ) if ($e = $self->catch);

   $self->add_field(    { data   => $data, type => q(table) } );
   $self->group_fields( { id     => $s->{form}->{name}.q(.heading),
                          nitems => 1 } );
   return;
}

# Private methods

sub _list_TTY_sessions {
   my ($self, $user_model) = @_;

   my $table = CatalystX::Usul::Table->new
      ( align  => { login     => 'left',       name   => 'left',
                    tty       => 'right',      idle   => 'right',
                    loginTime => 'right',      office => 'left',
                    extn      => 'right',      phone  => 'right',
                    id        => 'right',      whence => 'left' },
        flds   => [ qw(login name tty idle loginTime
                       office extn phone id whence) ],
        labels => { login     => 'Login',      name   => 'Name',
                    tty       => 'Line',       idle   => 'Idle',
                    loginTime => 'Login Time', office => 'Office',
                    extn      => 'Extn',       phone  => 'Home Phone',
                    id        => 'PID',        whence => 'Whence' } );
   my $res = $self->run_cmd( 'who -u' );

   for my $line (split m{ \n }mx, $res->out) {
      my @tmp            = split q( ), $line;
      my $user           = $user_model->find_user( $tmp[0] );
      my $flds           = {};
      $flds->{extn     } = $user->work_phone;
      $flds->{idle     } = $tmp[4] && $tmp[4] ne q(?) ? $tmp[4] : 'working';
      $flds->{login    } = $tmp[0];
      $flds->{loginTime} = $tmp[2].q( ).$tmp[3];
      $flds->{name     } = $user->first_name.q( ).$user->last_name;
      $flds->{office   } = $user->location;
      $flds->{phone    } = $user->home_phone;
      $flds->{id       } = $tmp[5];
      $flds->{tty      } = $tmp[1];
      $flds->{whence   } = $tmp[6];

      push @{ $table->values }, $flds;
   }

   return $table;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Session - Current session information

=head1 Version

0.1.$Revision: 402 $

=head1 Synopsis

   package YourApp;

   use Catalyst qw(ConfigComponents);

   $class->config
      ( 'Model::Session' => {
           base_class    => q(CatalystX::Usul::Model::Session) }, );

   sub list_sessions {
      # TODO: Move this method to the C::P::Session::Store::FastMmap
      return shift->_session_fastmmap_storage->get_keys( 2 );
   }

   package YourApp::Controller::YourController;

   sub sessions : Chained(common) Args(0) {
      my ($self, $c) = @_; my $s = $c->stash;

      $c->model( q(Session) )->list_sessions( $c );
      return;
   }

   sub ttys : Chained(common) Args(0) {
      my ($self, $c) = @_; my $s = $c->stash;

      $c->model( q(Session) )->list_TTY_sessions( $s );
      return;
   }

=head1 Description

Provides a utility method to display current session information

=head1 Subroutines/Methods

=head2 list_sessions

Stuffs the stash with table data for the current user sessions

=head2 list_TTY_sessions

Calls L</_list_TTY_sessions> to obtain a list of terminal
sessions. Stuffs the stash with the data needed by
L<HTML::FormWidgets> to display this information as a table

=head2 _list_TTY_sessions

Generates table data for current terminal sessions

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::Table>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

Only works with Catalyst::Session::FastMmap

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