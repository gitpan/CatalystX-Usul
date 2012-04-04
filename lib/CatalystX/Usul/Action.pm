# @(#)$Id: Action.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Action;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );
use parent qw(Catalyst::Action);

use MRO::Compat;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(exception);
use Scalar::Util qw(blessed);

sub execute {
   # Action class for controller methods with the HasActions attribute
   my ($self, @rest) = @_; my ($res, $verb);

   my @args = my ($controller, $c) = splice @rest, 0, 2;

   my $s = $c->stash; my $persistant = $controller->can( q(persist_state) );

   # Must have a verb in order to search for an action to forward to
   unless ($verb = $s->{verb} and $verb ne q(get)) {
      if ($persistant) {
         if ($verb) { $controller->set_uri_attrs_or_redirect( $c, @rest ) }
         else { @rest = $controller->get_uri_args( $c ) }
      }

      return $self->next::method( @args, @rest );
   }

   $verb eq q(options) and return $self->_set_options_response( $c );

   # Use the persistant URI args if available
   $persistant and @rest = $controller->get_uri_args( $c );

   # Search for the action whose ActionFor attribute matches this verb
   my $action_path = $self->_get_action_path( @args, $verb )
      or return $self->_not_implemented( @args, [ $verb, $self->reverse ] )
              ? $self->next::method( @args, @rest ) : undef;

   # Test the validity of the request token if we are using it
   if ($controller->can( q(validate_token) ) and __should_validate( $c )) {
      $controller->validate_token( $c )
         or return $self->_invalid_token( @args, [ $verb, $action_path ] )
                 ? $self->next::method( @args, @rest ) : undef;
      $controller->remove_token( $c );
   }

   # Authorize the users access to the action
   if ($controller->can( q(deny_access) )
       and $controller->deny_access( $c, $action_path )) {
      return $self->_access_denied( @args, [ $verb, $action_path ] )
           ? $self->next::method( @args, @rest ) : undef;
   }

   # Forward to the selected action
   $c->forward( $action_path, [ @rest ] )
      or return $self->_error( @args, [ $verb, $action_path ] )
              ? $self->next::method( @args, @rest ) : undef;

   # The action completed successfully. Log any result message
   if ($res = $s->{result} and $res->{items}->[ 0 ]) {
      $self->_log_info( @args, $action_path, $res );
   }

   # The action may have changed the URI args
   $persistant and @rest = $controller->get_uri_args( $c );

   return $self->next::method( @args, @rest );
}

# Private methods

sub _access_denied {
   my ($self, $controller, $c, $args) = @_;

   return $self->_bad_request
      ( $controller, $c, 'Action [_2] method [_1] access denied', $args );
}

sub _bad_request {
   my ($self, $controller, $c, $e, $args) = @_;

   my $s = $c->stash; my $verb = $args->[ 0 ];

   unless (blessed $e and $e->isa( EXCEPTION_CLASS )) {
      $e = exception 'error' => $e, 'args' => $args;
   }

   $controller->log_error_message( $e, $s );

   my $msg = $controller->loc( $s, $e->error, $e->args );

   return $c->view( $c->{current_view} )->bad_request( $c, $verb, $msg );
}

sub _error {
   my ($self, $controller, $c, $args) = @_; my $s = $c->stash; my $nm;

   # The stash override parameter triggers a call to FillInForm
   # in the HTML view which will preserve the contents of the form
   $s->{override} = TRUE;
   $c->error or $c->error( [] );
   ref $c->error eq ARRAY or $c->error( [ $c->error ] );

   if ($c->error->[ 0 ]) {
      for my $e (@{ $c->error }) {
         my $class = blessed $e || NUL;

         if ($class and $e->isa( $controller->exception_class )) {
            $s->{debug} and $s->{stacktrace} .= $class."\n".$e->stacktrace."\n";
         }

         $nm = $self->_bad_request( $controller, $c, $e, $args );
      }
   }
   else {
      $nm = $self->_bad_request
         ( $controller, $c, 'Action [_2] method [_1] unknown error', $args );
   }

   $c->clear_errors;
   return $nm;
}

sub _get_action_path {
   my ($self, $controller, $c, $verb) = @_;

   my $s  = $c->stash;
   my $ns = $c->action->namespace;
   my $id = $c->action->name.q(.).$verb;

   for my $container ($c->dispatcher->get_containers( $ns )) {
      for my $action (values %{ $container->actions }) {
         my $attrs = $action->attributes->{ q(ActionFor) } or next;

         for (grep { $_ eq $id } @{ $attrs }) {
            $s->{leader} = $action->reverse; return SEP.$action->reverse;
         }
      }
   }

   $s->{leader} = $self->reverse;
   return;
}

sub _get_allowed_methods {
   my ($self, $c) = @_;

   my @allowed = ( qw(get options) );
   my $ns      = $c->action->namespace;
   my $pattern = $c->action->name.q(.);

   for my $container ($c->dispatcher->get_containers( $ns )) {
      for my $action (values %{ $container->actions }) {
         my $attrs = $action->attributes->{ q(ActionFor) } or next;

         for (@{ $attrs }) {
            m{ \A $pattern (.+) \z }mx and push @allowed, $1;
         }
      }
   }

   return \@allowed;
}

sub _invalid_token {
   my ($self, $controller, $c, $args) = @_; $c->stash( override => TRUE );

   return $self->_bad_request
      ( $controller, $c, 'Action [_2] invalid token', $args );
}

sub _log_info {
   my ($self, $controller, $c, $leader, $res) = @_; my $s = $c->stash;

   my $sep = SEP; $leader =~ s{ \A $sep }{}mx; $s->{leader} = $leader;

   for my $line (map { $_->{content} } @{ $res->{items} }) {
      $controller->log_info_message( $line, $s );
   }

   return;
}

sub _not_implemented {
   my ($self, $controller, $c, $args) = @_; my $verb = $args->[ 0 ];

   $c->res->header( q(Allow) => $self->_get_allowed_methods( $c ) );

   my $s   = $c->stash; $s->{leader} = $self->reverse;
   my $key = 'Action [_2] method [_1] not implemented';
   my $e   = exception 'error' => $key, 'args' => $args;

   $controller->log_error_message( $e, $s );

   my $msg = $controller->loc( $s, $e->error, $e->args );

   return $c->view( $c->{current_view} )->not_implemented( $c, $verb, $msg );
}

sub _set_options_response {
   my ($self, $c) = @_;

   $c->res->content_type( q(text/plain) );
   $c->res->header( 'Allow' => $self->_get_allowed_methods( $c ) );
   $c->res->status( 200 );
   return;
}

# Private subroutines

sub __should_validate {
   my $c = shift; my $method = lc $c->req->method;

   my %will_validate = ( qw(delete 1 post 1 put 1) );

   return $c->stash->{token} && $will_validate{ $method };
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Action - A generic action class

=head1 Version

0.6.$Revision: 1165 $

=head1 Synopsis

   use base qw(CatalystX::Usul::Controller);

   sub some_method : Chained('/') PathPart('') Args(0) HasActions {
      my ($self, $c) = @_;

      $c->model( q(some_model) )->add_buttons( $c, qw(Save Delete) );

      return;
   }

   sub delete_action : ActionFor('some_method.delete') {
   }

   sub save_action : ActionFor('some_method.save') {
   }

=head1 Description

The C<_parse_HasActions_attr> method in the base controller class causes
L<Catalyst> to chain this execute method when a form is posted to an end
point the sets the HasActions attribute

Actions should define one or more I<ActionFor> attributes whose
argument takes the form; method name dot lower case button name, where
the button name was also passed to
L<add_buttons|CatalystX::Usul::Plugin::Model::StashHelper/add_buttons>

=head1 Subroutines/Methods

=head2 execute

The verb is obtained from the request object via the stash.  Verbs can
be set the I<_method> parameter which is removed to prevent this from
executing more than once. If we're using it, check to see if the form
token is valid and remove it from the form. Recover the button to
subroutine map for this action by introspection and forward to that
method. Log an error if one occurred and add it's text to the result
block. In the event that an error occurred, set the I<override>
attribute in the stash which causes the HTML view to call
L<Catalyst::Plugin::FillInForm> to preserve the form's state

=head1 Diagnostics

Errors are logged to C<< $controller->log_error >>

=head1 Configuration and Environment

Expects C<< $c->stash->{buttons} >> to be a hash that
contains display text for errors, prompts and tips

=head1 Dependencies

=over 3

=item L<Catalyst::Action>

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

Copyright (c) 2011 Peter Flanigan. All rights reserved

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE

=cut

# Local Variables:
# mode: perl
# tab-width: 3
# End:
