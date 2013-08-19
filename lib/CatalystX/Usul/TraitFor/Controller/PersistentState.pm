# @(#)Ident: ;

package CatalystX::Usul::TraitFor::Controller::PersistentState;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use Moose::Role;
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

   $self->debug and defined $args[ 0 ]
      and $self->log->debug( 'URI attrs '.__uri_attrs_stringify( @args ) );
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
   my $conf_keys = $s->{ $conf_key }->{ $s->{form}->{name} || NUL } or return;
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
   # When the role is applied $self->can( q(persist_state) )
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
   my ($self, $c, @args) = @_; my $sep = SEP;

   # Workaround a bug in $c->req. Cannot handle / as an argument
   $c->req->_path =~ m{ $sep $sep \z }mx and $args[ 0 ] = $sep;

   if (defined $args[ 0 ]) {
      $self->set_uri_args( $c, @args );
      $self->set_uri_query_params( $c, $c->req->query_params );
      return;
   }

   my $action = $c->action->reverse; @args = $self->get_uri_args( $c );

   ($action and $args[ 0 ]) or return;

   my $params = { %{ $self->get_uri_query_params( $c ) },
                  %{ $c->req->query_params             } };
   my $uri    = $c->uri_for_action( $action, grep { defined } @args, $params );
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
         $v = defined $v ? $v->{ $part } : $s->{ $part }; defined $v or return;
      }
   }

   return $v;
}

sub _uri_attrs_model {
   my ($self, $c) = @_; return $c->model( $self->_uri_attrs_model_class( $c ) );
}

sub _uri_attrs_model_class {
   my ($self, $c, $class) = @_; my $s = $c->stash; $class ||= q(Config);

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

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   package YourApp::Controller::YourController;

   use CatalystX::Usul::Moose;

   extends q(CatalystX::Controller);
   with    q(CatalystX::Usul::TraitFor::Controller::PersistentState);

=head1 Description

Uses the session store to provide uri arguments and parameters that are
persistent across requests

=head1 Subroutines/Methods

=head2 get_uri_args

   @args = $self->get_uri_args( $c );

Each action can define a list of named arguments in config. This method
returns a list of values, one for each defined argument. Values are
searched for in the following locations; the uri attribute cache, the
request object, the session and finally the configuration default

=head2 get_uri_query_params

   $params = $self->get_uri_query_params( $c );

Each action can define a list of key / value parameter pairs in config. This
method return a hash ref of parameters. Values are searched for in the same
locations as L</get_uri_args>

=head2 init_uri_attrs

   $self->init_uri_attrs( $c, $model_class );

This needs to be called early in chained controller methods. It
initialises the attribute cache used by the other method calls

=head2 persist_state

When the role is applied C<$self->can( q(persist_state) )> is true

=head2 set_uri_args

   $self->set_uri_args( $c, @args );

Saves the supplied list of arguments to the session and the cache

=head2 set_uri_attrs_or_redirect

   $self->set_uri_attrs_or_redirect( $c, @args );

If at least one defined argument is passed then this method calls
L</set_uri_args> and L</set_uri_query_params> and the returns. If no
defined arguments are passed it calls L</get_uri_args> and
L</get_uri_query_params>. This method then creates a uri using these values
and redirects to it

=head2 set_uri_query_params

   $self->set_uri_query_params( $c, \%params );

Saves the supplied parameter hash to the session and the cache

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<Moose::Role>

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
