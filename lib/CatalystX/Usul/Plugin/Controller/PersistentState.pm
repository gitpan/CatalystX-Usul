# @(#)$Id: PersistentState.pm 1181 2012-04-17 19:06:07Z pjf $

package CatalystX::Usul::Plugin::Controller::PersistentState;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.7.%d', q$Rev: 1181 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;

sub get_uri_args {
   my ($self, $c) = @_;
   my $cache      = $self->_uri_attrs_cache  ( $c );
   my $model      = $self->_uri_attrs_model  ( $c );
   my $session    = $self->_uri_attrs_session( $c );
   my @args       = ();

   for my $pair (@{ $cache->{args} || [] }) {
      my ($cfg_key) = keys %{ $pair }; my $v;

      unless ($v = $cache->{values}->{ $cfg_key } ) {
         unless (defined ($v = $model->query_value( $cfg_key ))) {
            unless (defined ($v = $session->{ $cfg_key }) and length $v) {
               $v = $self->_uri_attrs_inflate( $c, $pair->{ $cfg_key } );
            }
         }

         $cache->{values}->{ $cfg_key } = $session->{ $cfg_key } = $v;
      }

      push @args, $v;
   }

   $self->debug and defined $args[0]
      and $self->log_debug( 'URI attrs '.__uri_attrs_stringify( @args ) );
   return @args;
}

sub get_uri_query_params {
   my ($self, $c) = @_;
   my $cache      = $self->_uri_attrs_cache  ( $c );
   my $model      = $self->_uri_attrs_model  ( $c );
   my $session    = $self->_uri_attrs_session( $c );
   my $params     = {};

   for my $cfg_key (keys %{ $cache->{params} || {} }) {
      my $v = $cache->{values}->{ $cfg_key };

      if ($v) { $params->{ $cfg_key } = $v; next }

      unless (defined ($v = $model->query_value( $cfg_key ))) {
         unless (defined ($v = $session->{ $cfg_key }) and length $v) {
            $v = $self->_uri_attrs_inflate( $c, $cache->{params}->{ $cfg_key });
         }
      }

      $params->{ $cfg_key } = $cache->{values}->{ $cfg_key }
         = $session->{ $cfg_key } = $v;
   }

   return $params;
}

sub init_uri_attrs {
   my ($self, $c, $model_class) = @_;

   $self->_uri_attrs_model_class( $c, $model_class );

   my $s         = $c->stash;
   my $conf_key  = $self->_uri_attrs_config_key;
   my $conf_keys = $s->{ $conf_key }->{ $s->{form}->{name} } or return;
   my $cache     = $self->_uri_attrs_cache( $c );

   while (my ($key, $conf) = each %{ $conf_keys->{vals} }) {
      if (defined $conf->{order}) {
         $cache->{args}->[ $conf->{order} ] = { $key => $conf->{key} };
      }
      else { $cache->{params}->{ $key } = $conf->{key} }
   }

   return;
}

sub persist_state {
   # When the plugin is loaded $self->can( q(persist_state) )
}

sub set_uri_args {
   my ($self, $c, @args) = @_;

   $self->get_uri_args( $c );

   my $cache   = $self->_uri_attrs_cache( $c );
   my $session = $self->_uri_attrs_session( $c );
   my $count   = 0;

   for my $pair (@{ $cache->{args} || [] }) {
      my ($cfg_key) = keys %{ $pair };

      defined $args[ $count ]
         and $cache->{values}->{ $cfg_key }
                = $session->{ $cfg_key } = $args[ $count ];
      $count++;
   }

   return;
}

sub set_uri_attrs_or_redirect {
   my ($self, $c, @args) = @_;

   if (defined $args[ 0 ]) {
      $self->set_uri_args( $c, @args );
      $self->set_uri_query_params( $c, $c->req->query_params );
      return;
   }

   my $action = $c->action->reverse; @args = $self->get_uri_args( $c );

   ($action and $args[ 0 ]) or return;

   my $params = $self->get_uri_query_params( $c );
   my $uri    = $c->uri_for_action( $action, @args, $params );

   $c->res->redirect( $uri );
   $c->detach(); # Never returns
   return;
}

sub set_uri_query_params {
   my ($self, $c, $params) = @_;

   $self->get_uri_query_params( $c );

   my $cache   = $self->_uri_attrs_cache( $c );
   my $session = $self->_uri_attrs_session( $c );

   for my $cfg_key (keys %{ $cache->{params} || {} }) {
      defined $params->{ $cfg_key }
         and $cache->{values}->{ $cfg_key }
                = $session->{ $cfg_key } = $params->{ $cfg_key };
   }

   return;
}

# Private methods

sub _uri_attrs_cache {
   my ($self, $c) = @_; my $s = $c->stash;

   return $s->{ $self->_uri_attrs_stash_key }->{ $s->{form}->{name} } ||= {};
}

sub _uri_attrs_config_key {
   return q(keys);
}

sub _uri_attrs_inflate {
   my ($self, $c, $v) = @_; my $s = $c->stash;

   if (defined $v and $v =~ m{ \[% \s+ (.*) \s+ %\] }msx) {
      $v = undef;

      for my $part (split m{ \. }mx, $1) {
         $v = defined $v ? $v->{ $part } : $s->{ $part };
      }
   }

   return $v;
}

sub _uri_attrs_model {
   my ($self, $c) = @_; return $c->model( $self->_uri_attrs_model_class( $c ) );
}

sub _uri_attrs_model_class {
   my ($self, $c, $class) = @_; my $s = $c->stash; $class ||= q(Base);

   return $s->{ $self->_uri_attrs_stash_key }->{_model_class} ||= $class;
}

sub _uri_attrs_session {
   my ($self, $c) = @_;

   return $c->session->{ $c->action->namespace || q(root) } ||= {};
}

sub _uri_attrs_stash_key {
   return q(uri_attrs_cache);
}

# Private subroutines

sub __uri_attrs_stringify {
   return join SPC, map { "'".(defined $_ ? $_ : 'undef')."'" } @_;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Plugin::Controller::PersistentState - Set/Get state information on/from the session store

=head1 Version

0.7.$Revision: 1181 $

=head1 Synopsis

   use CatalystX::Usul::PersistentState;

=head1 Description

Uses the session store to provide state information that is persistent across
requests

=head1 Subroutines/Methods

=head2 get_uri_args

   my @args = $self->get_uri_args( $c );

=head2 get_uri_query_params

=head2 init_uri_attrs

=head2 persist_state

When the plugin is loaded C<$self->can( q(persist_state) )>

=head2 set_uri_args

   $self->set_uri_args( $c, @args );

=head2 set_uri_attrs_or_redirect;

=head2 set_uri_query_params

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Constants>

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

Copyright (c) 2008-2010 Peter Flanigan. All rights reserved

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
