package CatalystX::Usul::Controller::Admin::UserManager;

# @(#)$Id: UserManager.pm 406 2009-03-30 01:53:50Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Controller);

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 406 $ =~ /\d+/gmx );

__PACKAGE__->config( namespace => q(admin), realm_class => q(IdentityUnix) );

__PACKAGE__->mk_accessors( qw(realm_class) );

my $SEP = q(/);

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
   $model = $c->model( $class );

   # Stash the identity objects for the selected identity model
   $s->{alias_model  } = $model->aliases;
   $s->{profile_model} = $model->profiles;
   $s->{role_model   } = $model->roles;
   $s->{user_model   } = $model->users;
   return;
}

sub mail_aliases : Chained(user_base) PathPart(aliases) Args HasActions {
   my ($self, $c, $alias) = @_;

   $alias = $self->set_key( $c, q(alias), $alias );
   $c->stash->{alias_model}->form( $alias );
   return;
}

sub mail_aliases_create_or_update : ActionFor(mail_aliases.insert)
                                    ActionFor(mail_aliases.save) {
   my ($self, $c) = @_;

   my $alias = $c->stash->{alias_model}->create_or_update;

   $self->set_key( $c, q(alias), $alias );
   return 1;
}

sub mail_aliases_delete : ActionFor(mail_aliases.delete) {
   my ($self, $c) = @_;

   $c->stash->{alias_model}->delete( $self->get_key( $c, q(alias) ) );
   $self->set_key( $c, q(alias), $c->stash->{newtag} );
   return 1;
}

sub user_admin : Chained(user_base) PathPart('') Args(0) Public {
   my ($self, $c) = @_;

   return $self->redirect_to_path( $c, $SEP.q(user_manager) );
}

sub user_manager : Chained(user_base) PathPart(manager) Args HasActions {
   my ($self, $c, $realm, $user, $profile) = @_;

   $realm   = $self->set_key( $c, q(realm),   $realm   );
   $user    = $self->set_key( $c, q(user),    $user    );
   $profile = $self->set_key( $c, q(profile), $profile );
   $c->stash->{user_model}->form( $realm, $user, $profile );
   return;
}

sub user_manager_create_or_update : ActionFor(user_manager.insert)
                                    ActionFor(user_manager.save) {
   my ($self, $c) = @_;

   my $user = $c->stash->{user_model}->create_or_update;

   $self->set_key( $c, q(user), $user );
   return 1;
}

sub user_manager_delete : ActionFor(user_manager.delete) {
   my ($self, $c) = @_;

   $c->stash->{user_model}->delete;
   $self->set_key( $c, q(user), $c->stash->{newtag} );
   return 1;
}

sub user_manager_fill : ActionFor(user_manager.fill) {
   my ($self, $c) = @_; $c->stash->{user_model}->user_fill; return 1;
}

sub user_profiles : Chained(user_base) PathPart(profiles) Args HasActions {
   my ($self, $c, $profile) = @_;

   $profile = $self->set_key( $c, q(profile), $profile );
   $c->stash->{profile_model}->form( $profile );
   return;
}

sub user_profiles_create_or_update : ActionFor(user_profiles.insert)
                                     ActionFor(user_profiles.save) {
   my ($self, $c) = @_;

   my $profile = $c->stash->{profile_model}->create_or_update;

   $self->set_key( $c, q(profile), $profile );
   return 1;
}

sub user_profiles_delete : ActionFor(user_profiles.delete) {
   my ($self, $c) = @_; my $s = $c->stash;

   $s->{profile_model}->delete;
   $self->set_key( $c, q(profile), $s->{newtag} );
   return 1;
}

sub user_report : Chained(user_base) PathPart(report) Args HasActions {
   my ($self, $c, $report) = @_;

   my $realm = $self->get_key( $c, q(realm) );

   $report = $self->set_key( $c, q(userReport), $report );
   $c->stash->{user_model}->form( $realm, $report );
   return;
}

sub user_report_execute : ActionFor(user_report.execute) {
   my ($self, $c) = @_;

   $c->stash->{user_model}->user_report_execute( q(csv) );
   return 1;
}

sub user_report_list : ActionFor(user_report.list) {
   my ($self, $c) = @_; $self->set_key( $c, q(userReport), 0 ); return 1;
}

sub user_report_purge : ActionFor(user_report.purge) {
   my ($self, $c) = @_; $c->stash->{user_model}->purge; return 1;
}

sub user_security : Chained(user_base) PathPart(security) Args HasActions {
   my ($self, $c, $realm, $user) = @_;

   $realm = $self->set_key( $c, q(realm), $realm );
   $user  = $self->set_key( $c, q(user),  $user  );
   $c->stash->{user_model}->form( $realm, $user  );
   return;
}

sub user_security_set : ActionFor(user_security.set) {
   my ($self, $c) = @_;

   $c->stash->{user_model}->set_password( $self->get_key( $c, q(user) ) );
   return 1;
}

sub user_security_update : ActionFor(user_security.update) {
   my ($self, $c) = @_; my $s = $c->stash;

   my $args = { user => $self->get_key( $c, q(user) ) };

   if ($s->{role_model}->query_value( q(groups_n_added) )) {
      $args->{field} = q(groups_added);
      $s->{role_model}->add_roles_to_user( $args );
   }

   if ($s->{role_model}->query_value( q(groups_n_deleted) )) {
      $args->{field} = q(groups_deleted);
      $s->{role_model}->remove_roles_from_user( $args );
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

0.1.$Revision: 406 $

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
