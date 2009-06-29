# @(#)$Id: UserManager.pm 576 2009-06-09 23:23:46Z pjf $

package CatalystX::Usul::Controller::Admin::UserManager;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.3.%d', q$Rev: 576 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Controller);

my $SEP = q(/);

__PACKAGE__->config( namespace => q(admin), realm_class => q(IdentityUnix) );

__PACKAGE__->mk_accessors( qw(realm_class) );

sub user_base : Chained(common) PathPart(users) CaptureArgs(0) {
   my ($self, $c) = @_; my $s = $c->stash;

   # Select the identity model used for finding our realm
   my $model = $c->model( $self->realm_class );

   # Select the realm from the session store
   my $realm = $self->get_key( $c, q(realm) );

   unless ($self->is_member( $realm, keys %{ $model->auth_realms } )) {
      # Select the default realm if there isn't one in the session store
      $realm = $model->default_realm;
   }

   # Store the selected realm on the session store
   $self->set_key( $c, q(realm), $realm );

   # Get the identity class associated with the selected realm
   my $class = $realm ? $model->auth_realms->{ $realm } : $self->realm_class;

   # Get the identity model for the selected identity class
   $s->{identity_model} = $c->model( $class );
   return;
}

sub mail_aliases : Chained(user_base) PathPart(aliases) Args HasActions {
   my ($self, $c, $alias) = @_; my $model = $c->stash->{identity_model};

   $model->aliases->form( $self->set_key( $c, q(alias), $alias ) );
   return;
}

sub mail_aliases_create_or_update : ActionFor(mail_aliases.insert)
                                    ActionFor(mail_aliases.save) {
   my ($self, $c) = @_; my $model = $c->stash->{identity_model};

   $self->set_key( $c, q(alias), $model->aliases->create_or_update );
   return 1;
}

sub mail_aliases_delete : ActionFor(mail_aliases.delete) {
   my ($self, $c) = @_; my $s = $c->stash; my $model = $s->{identity_model};

   $model->aliases->delete; $self->set_key( $c, q(alias), $s->{newtag} );
   return 1;
}

sub user_admin : Chained(user_base) PathPart('') Args(0) Public {
   my ($self, $c) = @_;

   return $self->redirect_to_path( $c, $SEP.q(user_manager) );
}

sub user_manager : Chained(user_base) PathPart(manager) Args HasActions {
   my ($self, $c, $realm, $user, $profile) = @_;

   my $model = $c->stash->{identity_model};

   $realm   = $self->set_key( $c, q(realm),   $realm   );
   $user    = $self->set_key( $c, q(user),    $user    );
   $profile = $self->set_key( $c, q(profile), $profile );

   $model->users->form( $realm, $user, $profile );
   return;
}

sub user_manager_create_or_update : ActionFor(user_manager.insert)
                                    ActionFor(user_manager.save) {
   my ($self, $c) = @_; my $model = $c->stash->{identity_model};

   $self->set_key( $c, q(user), $model->users->create_or_update );
   return 1;
}

sub user_manager_delete : ActionFor(user_manager.delete) {
   my ($self, $c) = @_; my $s = $c->stash; my $model = $s->{identity_model};

   $model->users->delete; $self->set_key( $c, q(user), $s->{newtag} );
   return 1;
}

sub user_manager_fill : ActionFor(user_manager.fill) {
   my ($self, $c) = @_; my $model = $c->stash->{identity_model};

   $model->users->user_fill;
   return 1;
}

sub user_profiles : Chained(user_base) PathPart(profiles) Args HasActions {
   my ($self, $c, $profile) = @_; my $model = $c->stash->{identity_model};

   $model->profiles->form( $self->set_key( $c, q(profile), $profile ) );
   return;
}

sub user_profiles_create_or_update : ActionFor(user_profiles.insert)
                                     ActionFor(user_profiles.save) {
   my ($self, $c) = @_; my $model = $c->stash->{identity_model};

   $self->set_key( $c, q(profile), $model->profiles->create_or_update );
   return 1;
}

sub user_profiles_delete : ActionFor(user_profiles.delete) {
   my ($self, $c) = @_; my $s = $c->stash; my $model = $s->{identity_model};

   $model->profiles->delete; $self->set_key( $c, q(profile), $s->{newtag} );
   return 1;
}

sub user_report : Chained(user_base) PathPart(report) Args HasActions {
   my ($self, $c, $report) = @_; my $model = $c->stash->{identity_model};

   $report = $self->set_key( $c, q(userReport), $report );
   $model->users->form( $self->get_key( $c, q(realm) ), $report );
   return;
}

sub user_report_execute : ActionFor(user_report.execute) {
   my ($self, $c) = @_; my $model = $c->stash->{identity_model};

   $model->users->user_report( q(csv) );
   return 1;
}

sub user_report_list : ActionFor(user_report.list) {
   my ($self, $c) = @_; $self->set_key( $c, q(userReport), 0 ); return 1;
}

sub user_report_purge : ActionFor(user_report.purge) {
   my ($self, $c) = @_; my $model = $c->stash->{identity_model};

   $model->users->purge;
   return 1;
}

sub user_security : Chained(user_base) PathPart(security) Args HasActions {
   my ($self, $c, $realm, $user) = @_; my $model = $c->stash->{identity_model};

   $realm = $self->set_key( $c, q(realm), $realm );
   $user  = $self->set_key( $c, q(user),  $user  );
   $model->users->form( $realm, $user  );
   return;
}

sub user_security_set : ActionFor(user_security.set) {
   my ($self, $c) = @_; my $model = $c->stash->{identity_model};

   $model->users->set_password( $self->get_key( $c, q(user) ) );
   return 1;
}

sub user_security_update : ActionFor(user_security.update) {
   my ($self, $c) = @_; my $s = $c->stash; my $model = $s->{identity_model};

   my $args = { user => $self->get_key( $c, q(user) ) };

   if ($model->roles->query_value( q(groups_n_added) )) {
      $args->{field} = q(groups_added);
      $model->roles->add_roles_to_user( $args );
   }

   if ($model->roles->query_value( q(groups_n_deleted) )) {
      $args->{field} = q(groups_deleted);
      $model->roles->remove_roles_from_user( $args );
   }

   return 1;
}

sub user_sessions : Chained(user_base) PathPart(sessions) Args(0) HasActions {
   my ($self, $c) = @_; my $model = $c->model( q(Session) );

   $model->list_sessions; $model->list_TTY_sessions;
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin::UserManager - User account management

=head1 Version

0.3.$Revision: 576 $

=head1 Synopsis

   package MyApp::Controller::Admin;

   use base qw(CatalystX::Usul::Controller::Admin);

   __PACKAGE__->build_subcontrollers;

=head1 Description

Create and maintain user accounts across multiple user data stores

=head1 Subroutines/Methods

=head2 user_base

All the user actions are chained on this one. It determines the current
authentication realm and which storage model that uses. Stashes the model
references for later use

=head2 mail_aliases

Calls the mail alias model to stash the data used to create the
mail aliases form

=head2 mail_aliases_create_or_update

Action that calls the model to create a new mail alias or update an
existing one. Called in response to pressing the I<insert> or I<save>
button on the L</mail_aliases> form

=head2 mail_aliases_delete

Calls the model to delete an existing mail alias. Called in response
to pressing the I<delete> button on the L</mail_aliases> form

=head2 user_admin

Chained on L</user_base> with a null path part this action redirects to
L</user_manager>

=head2 user_manager

Calls the user model to stash the data used to create the user account
management form

=head2 user_manager_create_or_update

This action calls the user model to create a new user account or update
an existing one. Called in response to pressing the I<create> or I<save>
button on the L</user_manager> form

=head2 user_manager_delete

Calls the user model to delete the selected user account. Called in
response to pressing the I<delete> button on the L</user_manager> form

=head2 user_manager_fill

Called in response to pressing the I<fill> button on the L</user_manager>
form this action calls the user model to automatically fill in some of the
fields on the form

=head2 user_profiles

Calls the profiles model to stash the data used to create the user profiles
form. User profiles provide a number of static parameters used in the
creation of a user account

=head2 user_profiles_create_or_update

This action calls the profiles model to create a new profile or update
an existing one. It is called in response to pressing the I<create> or
I<save> buttons on the L<user_profiles> form

=head2 user_profiles_delete

Calls the C<delete> method on the user profiles model in response to
pressing the I<delete> button on the L</user_profiles> form

=head2 user_report

Calls the user model to stash the data used to create either the
available user reports list or to view a specific report. The report id
can be passed as the first captured argument after L<Catalyst> context

=head2 user_report_execute

Called in response to pressing the I<execute> button on the L</user_report>
form this action calls the user model to generate a report on the available
user accounts

=head2 user_report_list

Switches back to the report list after viewing a specific report

=head2 user_report_purge

One or more accounts can be selected from viewing a specific user
account report. This action is called in response to pressing the
I<purge> button on that report and will call the user model to delete
all the selected accounts

=head2 user_security

Calls the security form on the user model to stash the form data. This
form allows administrators to add/remove users to/from roles and to
change a users password

=head2 user_security_set

Updates the selected users password

=head2 user_security_update

Updates the selected users list of roles (groups)

=head2 user_sessions

Display two tables. The list of current sessions stored in the session
store and the list of current TTY sessions

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Controller>

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
