package CatalystX::Usul::Action;

# @(#)$Id: Action.pm 435 2009-04-07 19:54:06Z pjf $

use strict;
use warnings;
use parent qw(Catalyst::Action);
use Class::C3;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 435 $ =~ /\d+/gmx );

my $BRK = q(: );
my $SEP = q(/);

sub execute {
   # Action class for controllers that have buttons
   my ($self, @rest) = @_; my ($action_path, $res, $text, $verb);

   my ($controller, $c) = @rest; my $s = $c->stash;

   unless (defined $s->{verb} and $verb = $s->{verb} and $verb ne q(get)) {
      return $self->next::method( @rest );
   }

   return $self->_return_options( $c ) if ($verb eq q(options));

   my @args = ($controller, $c, $verb);

   # Search for the action whose ActionFor attribute matches this verb
   unless ($action_path = $self->_get_action_path( @args )) {
      return $self->_not_implemented( @args )
         ? $self->next::method( @rest ) : undef;
   }

   # Test the validity of the request token if we are using it
   if ($controller->can( q(validate_token) ) && __should_validate( $c )) {
      unless ($controller->validate_token( $c )) {
         return $self->_invalid_token( @args )
            ? $self->next::method( @rest ) : undef;
      }

      $controller->remove_token( $c );
   }

   if ($c->forward( $action_path )) {
      # The action completed successfully. Log any result message
      if ($res = $s->{result} and $res->{items}->[ 0 ]) {
         my $leader = $action_path; $leader =~ s{ \A $SEP }{}mx;

         for my $line (map { chomp; ucfirst $_ }
                       map { $_->{content} } @{ $res->{items} }) {
            $controller->log_info( (ucfirst $leader).$BRK.$line );
         }
      }

      return $self->next::method( @rest );
   }

   # Handle the error
   return $self->_error( @args, $action_path )
      ? $self->next::method( @rest ) : undef;
}

# Private methods

sub _bad_request {
   my ($self, @rest) = @_; my ($controller, $c, $verb) = @rest;

   my $view = $c->view( $c->{current_view} ); my $msg = __loc( @rest );

   $controller->log_error( (ucfirst $self->reverse).$BRK.(ucfirst $msg) );

   return $view->bad_request( $c, $msg, $controller, $verb );
}

sub _error {
   my ($self, @rest) = @_; my ($e, $nm);

   my (undef, $c) = @rest; my $s = $c->stash;

   # The stash override parameter triggers a call to FillInForm
   # in the HTML view which will preserve the contents of the form
   $s->{override} = 1;

   # The action failed capture the error and log it
   $c->error( [] )            unless ($c->error);
   $c->error( [ $c->error ] ) unless (ref $c->error eq q(ARRAY));

   if ($c->error->[ 0 ]) {
      for $e (@{ $c->error }) {
         if (ref $e eq q(CatalystX::Usul::Exception)) {
            $nm = $self->_bad_request( @rest,
                                       $e->as_string( $s->{debug} ? 2 : 1 ),
                                       [ $e->arg1, $e->arg2 ] );
         }
         else { $nm = $self->_bad_request( @rest, $e ) }
      }
   }
   else { # An unknown error occurred
      $nm = $self->_bad_request( @rest, q(eUnknownForward) );
   }

   $c->clear_errors;
   return $nm;
}

sub _get_action_path {
   my ($self, $controller, $c, $verb) = @_; my $attrs;

   my $namespace = $c->action->namespace;
   my $id        = $c->action->name.q(.).$verb;

   for my $container ($c->dispatcher->get_containers( $namespace )) {
      for my $action (values %{ $container->actions }) {
         next unless ($attrs = $action->attributes->{ q(ActionFor) });

         return $SEP.$action->reverse for (grep { $_ eq $id } @{ $attrs });
      }
   }

   return;
}

sub _get_allowed_methods {
   my ($self, $c) = @_; my @allowed = ( q(get options) ); my $attrs;

   my $namespace = $c->action->namespace;
   my $pattern   = $c->action->name.q(.);

   for my $container ($c->dispatcher->get_containers( $namespace )) {
      for my $action (values %{ $container->actions }) {
         next unless ($attrs = $action->attributes->{ q(ActionFor) });

         for (grep { m{ \A $pattern }mx } @{ $attrs }) {
            push @allowed, $1 if (m{ \A $pattern (.+) \z }mx);
         }
      }
   }

   return \@allowed;
}

sub _invalid_token {
   my ($self, @rest) = @_;

   return $self->_bad_request( @rest, $self->reverse, q(eBadToken) );
}

sub _not_implemented {
   my ($self, @rest) = @_; my ($controller, $c, $verb) = @rest;

   my $msg  = __loc( @rest, $self->reverse, q(eNotImplemented) );
   my $view = $c->view( $c->{current_view} );

   $controller->log_error( (ucfirst $self->reverse).$BRK.(ucfirst $msg) );
   $c->res->header( 'Allow' => $self->_get_allowed_methods( $c ) );

   return $view->not_implemented( $c, $msg, $controller, $verb );
}

sub _return_options {
   my ($self, $c) = @_;

   $c->res->content_type( q(text/plain) );
   $c->res->header( 'Allow' => $self->_get_allowed_methods( $c ) );
   $c->res->status( 200 );
   return;
}

# Private subroutines

sub __loc {
   my ($controller, $c, $verb, $action_path, $key, $args) = @_;

   unless ($args) {
      if ($action_path) { $args = [ $action_path, $verb ] }
      else { $args = [ $verb ] }
   }

   my $s = $c->stash;

   $controller->content_type( $s->{content_type} );
   $controller->messages( $s->{messages} );

   return $controller->loc( $key, $args );
}

sub __should_validate {
   my $c = shift; my $method = lc $c->req->method;

   my %will_validate = ( qw(delete 1 post 1 put 1) );

   return $c->config->{token} && $will_validate{ $method };
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Action - A generic action class

=head1 Version

0.1.$Revision: 435 $

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

Copyright (c) 2008 Peter Flanigan. All rights reserved

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
