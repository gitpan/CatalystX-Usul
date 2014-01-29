# @(#)Ident: ;

package CatalystX::Usul::Action;

use strict;
use version; our $VERSION = qv( sprintf '0.17.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(exception is_arrayref is_hashref);

extends q(Catalyst::Action);

sub execute { # For controller methods with the HasActions attribute
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

   # This sets the args passed to the action from the uri
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

   # Either redirect or allow the request to proceed as if it were a get
   $s->{redirect_after_execute} and return $self->_redirect( @args, @rest );

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

   $controller->log->error_message( $s, $e );

   my $msg = $controller->loc( $s, $e->error, $e->args );

   return $c->view( $c->{current_view} )->bad_request( $c, $verb, $msg );
}

sub _error {
   my ($self, $controller, $c, $args) = @_; my $s = $c->stash; my $nm;

   # The stash override parameter triggers a call to FillInForm
   # in the HTML view which will preserve the contents of the form
   $s->{override} = TRUE; $c->error or $c->error( [] );

   is_arrayref $c->error or $c->error( [ $c->error ] );

   if ($c->error->[ 0 ]) {
      for my $e (@{ $c->error }) {
         my $class = blessed $e || NUL;

         if ($class and $e->isa( EXCEPTION_CLASS )) {
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

   my $s  = $c->stash; my $ns = $c->action->namespace;

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
   my ($self, $c) = @_; my @allowed = ( qw(get options) );

   my $ns = $c->action->namespace; my $pattern = $c->action->name.q(.);

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
      $controller->log->info_message( $s, $line );
   }

   return;
}

sub _not_implemented {
   my ($self, $controller, $c, $args) = @_; my $verb = $args->[ 0 ];

   $c->res->header( q(Allow) => $self->_get_allowed_methods( $c ) );

   my $s   = $c->stash; $s->{leader} = $self->reverse;
   my $key = 'Action [_2] method [_1] not implemented';
   my $e   = exception 'error' => $key, 'args' => $args;

   $controller->log->error_message( $s, $e );

   my $msg = $controller->loc( $s, $e->error, $e->args );

   return $c->view( $c->{current_view} )->not_implemented( $c, $verb, $msg );
}

sub _redirect {
   my ($self, $controller, $c, @rest) = @_;

   my $res    = $c->stash->{result};
   my $msg    = $res ? join NUL, map { $_->{content} } @{ $res->{items} || [] }
                     : undef;
   my $path   = $c->action->namespace.SEP.$c->action->name;
   my $params = ($rest[ 0 ] && is_hashref $rest[ -1 ]) ? pop @rest : {};

   $msg and $params->{mid} = $c->set_status_msg( $msg );

   $controller->redirect_to_path( $c, $path, @rest, $params );
   return;
}

sub _set_options_response {
   my ($self, $c) = @_; my $res = $c->res;

   $res->content_type( q(text/plain) );
   $res->header( 'Allow' => $self->_get_allowed_methods( $c ) );
   $res->status( 200 );
   return;
}

# Private subroutines

sub __should_validate {
   my $c = shift; my $method = lc $c->req->method;

   my %will_validate = ( qw(delete 1 post 1 put 1) );

   return $c->stash->{token} && $will_validate{ $method };
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Action - A generic action class

=head1 Version

Describes v0.17.$Rev: 1 $

=head1 Synopsis

   package YourApp::Controller::YourController;

   BEGIN { extends q(CatalystX::Usul::Controller) }

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
point the sets the C<HasActions> attribute

Actions should define one or more C<ActionFor> attributes whose
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
L<HTML::FillInForm> to preserve the form's state

=head1 Configuration and Environment

None

=head1 Diagnostics

Errors are logged to C<< $controller->log->error >>

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

Copyright (c) 2014 Peter Flanigan. All rights reserved

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
