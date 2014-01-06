# @(#)Ident: ;

package CatalystX::Usul::Model::Session;

use strict;
use version; our $VERSION = qv( sprintf '0.15.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use Class::Usul::Time;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(squeeze throw);
use TryCatch;

extends q(CatalystX::Usul::Model);
with    q(CatalystX::Usul::TraitFor::Model::StashHelper);
with    q(CatalystX::Usul::TraitFor::Model::QueryingRequest);

has 'ipc_class'   => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default        => sub { 'Class::Usul::IPC' };


has '_ipc' => is => 'lazy', isa => IPCClass,
   default => sub { $_[ 0 ]->ipc_class->new( builder => $_[ 0 ]->usul ) },
   handles => [ qw(run_cmd) ], init_arg => undef, reader => 'ipc';

sub delete_session {
   my ($self, $sid) = @_; my $c = $self->context;

   $c->delete_session_data( "${_}:${sid}" ) for qw(session expires flash);
   $c->delete_session_id( $sid );
   return;
}

sub delete_sessions {
   my $self = shift; my $selected = $self->query_array( 'sessions' );

   $selected->[ 0 ] or throw 'Nothing selected';

   for my $sid (@{ $selected } ) {
      $self->delete_session( $sid );
      $self->add_result_msg( 'Session [_1] deleted', $sid );
   }

   return TRUE;
}

sub list_sessions {
   my $self = shift; my $s = $self->context->stash; my $sessions;

   try        { $sessions = $self->_get_session_table }
   catch ($e) { return $self->add_error( $e ) }

   if ($sessions->count) {
      $self->add_field   ( { data   => $sessions,   id    => q(sessions),
                             select => q(right), sortable => TRUE,
                             type   => q(table) } );
      $self->group_fields( { id     => $s->{form}->{name}.q(.sessions) } );
      $self->add_buttons ( qw(Delete) );
   }

   return;
}

sub list_TTY_sessions {
   my $self = shift; my $s = $self->context->stash; my $sessions;

   try        { $sessions = $self->_get_tty_session_table( $s->{user_model} ) }
   catch ($e) { return $self->add_error( $e ) }

   if ($sessions->count) {
      $self->add_field( { data => $sessions, id => q(ttys), type => q(table) });
      $self->group_fields( { id => $s->{form}->{name}.q(.tty_sessions) } );
   }

   return;
}

# Private methods

sub _get_session_table {
   my $self = shift; my $rows = $self->_get_session_table_rows;

   return $self->table_class->new
         ( count    => scalar @{ $rows },
           fields   => [ qw(username realm id address created updated) ],
           labels   => { address => 'Address',    created  => 'Created',
                         id      => 'Session Id', realm    => 'Realm',
                         updated => 'Updated',    username => 'User',  },
           typelist => { address => q(ipaddr),    created  => q(date),
                         id      => q(hex),       updated  => q(date), },
           values   => $rows );
}

sub _get_session_table_rows {
   my $self = shift; my $c = $self->context; my $now = time; my @rows = ();

   for my $session ($c->list_sessions) {
      my ($sid) = $session->{key} =~ m{ \A session: (.*) \z }mx;

      my $value; ($sid and $value = $session->{value}) or next;

      my $updated  = $value->{__updated} || 0;
      my $elapsed  = $now - ($updated || $now);
      my $user_obj = exists $value->{__user} ? eval {$value->{__user}} : undef;
      my $max_sess = $user_obj ? $user_obj->max_sess_time : MAX_SESSION_TIME;
      my $status   = $elapsed > $max_sess  ? q(expired) : q(valid);
      my $select   = $status eq q(expired) ? q(checked) : undef;
      my $realm    = $value->{__user_realm};

      push @rows, { _meta    => { updated => $status, select => $select, },
                    address  => $value->{__address},
                    created  => time2str( undef, $value->{__created} || 0 ),
                    id       => $sid,
                    realm    => $realm,
                    updated  => time2str( undef, $updated ),
                    username => __make_user_link( $c, $user_obj, $realm, ), };
   }

   return [ sort { $a->{username}->{text} cmp $b->{username}->{text} } @rows ];
}

sub _get_tty_session_table {
   my ($self, @args) = @_;

   my $rows = $self->_get_tty_session_table_rows( @args );

   return $self->table_class->new
      ( count    => scalar @{ $rows },
        fields   => [ qw(login name tty idle loginTime
                         office extn phone id whence) ],
        id       => q(ttys),
        labels   => { login     => 'Login',      name      => 'Name',
                      tty       => 'Line',       idle      => 'Idle',
                      loginTime => 'Login Time', office    => 'Office',
                      extn      => 'Extn',       phone     => 'Home Phone',
                      id        => 'PID',        whence    => 'Whence' },
        typelist => { extn      => 'numeric',    id        => 'numeric',
                      idle      => 'time',       loginTime => 'date',
                      phone     => 'numeric', },
        values   => $rows, );
}

sub _get_tty_session_table_rows {
   my ($self, $user_model) = @_;

   my $res = $self->run_cmd( [ qw(who -u) ] ); my @rows = ();

   for my $line (split m{ \n }mx, $res->out) {
      my @tmp  = split SPC, squeeze $line;
      my $user = $user_model->find_user( $tmp[ 0 ] );
      my $flds = {};

      $flds->{extn     } = $user->work_phone;
      $flds->{idle     } = $tmp[ 4 ] && $tmp[ 4 ] ne q(?) ? $tmp[4] : 'working';
      $flds->{login    } = $tmp[ 0 ];
      $flds->{loginTime} = $tmp[ 2 ].SPC.$tmp[ 3 ];
      $flds->{name     } = $user->fullname;
      $flds->{office   } = $user->location;
      $flds->{phone    } = $user->home_phone;
      $flds->{id       } = $tmp[ 5 ];
      $flds->{tty      } = $tmp[ 1 ];
      $flds->{whence   } = $tmp[ 6 ];

      push @rows, $flds;
   }

   return \@rows;
}

# Private functions

sub __make_user_link {
   my ($c, $user_obj, $realm) = @_;

   my $action   = $c->action->namespace.SEP.q(user_manager);
   my $username = $user_obj ? $user_obj->username : q(unknown);
   my $options  = { realm => $realm };

   return { container => FALSE,
            href      => $c->uri_for_action( $action, $username, $options ),
            text      => $username,
            type      => q(anchor),
            widget    => TRUE, };
}

__PACKAGE__->meta->make_immutable;

1;


__END__

=pod

=head1 Name

CatalystX::Usul::Model::Session - Current session information

=head1 Version

Describes v0.15.$Rev: 1 $

=head1 Synopsis

   package YourApp;

   use Moose;
   use Catalyst qw(ConfigComponents...);

   with qw(CatalystX::Usul::TraitFor::ListSessions);

   $class->config
      ( 'Model::Session' => {
           base_class    => q(CatalystX::Usul::Model::Session) }, );

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

=head1 Configuration and Environment

Defines the following list of attributes;

=over 3

=item ipc_class

A loadable class which defaults to I<Class::Usul::IPC>

=item table_class

A loadable class which defaults to I<Class::Usul::Response::Table>
These table objects are stashed and rendered later by
L<HTML::FormWidgets::Table>

=back

=head1 Subroutines/Methods

=head2 build_per_context_instance

Returns a clone of the model instance. Instantiates query object

=head2 delete_session

   $self->delete_session( $c, $sid );

Deletes the specified session

=head2 delete_sessions

   $bool = $self->delete_sessions;

Delete the selected sessions. Returns true

=head2 list_sessions

   $self->list_sessions;

Stuffs the stash with table data for the current user sessions

=head2 list_TTY_sessions

   $self->list_TTY_sessions;

Calls L</_list_TTY_sessions> to obtain a list of terminal
sessions. Stuffs the stash with the data needed by
L<HTML::FormWidgets> to display this information as a table

=head2 _get_tty_session_table

   $table_object = $self->_get_tty_session_table( $user_model );

Generates table data for current terminal sessions

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::TraitFor::Model::QueryingRequest>

=item L<CatalystX::Usul::TraitFor::Model::StashHelper>

=item L<CatalystX::Usul::Moose>

=item L<Class::Usul::Response::Table>

=item L<Class::Usul::Time>

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
