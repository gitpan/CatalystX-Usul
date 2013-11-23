# @(#)Ident: ;

package CatalystX::Usul::Controller::Admin::UserManager;

use strict;
use version; our $VERSION = qv( sprintf '0.14.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Moose;
use CatalystX::Usul::Constants;

BEGIN { extends q(CatalystX::Usul::Controller) }

with q(CatalystX::Usul::TraitFor::Controller::ModelHelper);
with q(CatalystX::Usul::TraitFor::Controller::PersistentState);

__PACKAGE__->config( namespace => q(admin), );

has 'alias_class'   => is => 'ro', isa => Str, default => q(MailAliases);

has 'profile_class' => is => 'ro', isa => Str, default => q(UserProfiles);

sub user_base : Chained(common) PathPart(users) CaptureArgs(0) {
   # Stash the identity model for the selected realm
   my ($self, $c) = @_;

   $c->stash->{user_params} = $self->get_uri_query_params( $c );

   return $self->stash_identity_model( $c );
}

sub mail_aliases : Chained(user_base) PathPart(aliases) Args HasActions {
   my ($self, $c, $alias) = @_;

   return $c->model( $self->alias_class )->form( $alias );
}

sub mail_aliases_create_or_update : ActionFor(mail_aliases.insert)
                                    ActionFor(mail_aliases.save) {
   my ($self, $c) = @_;

   $self->set_uri_args( $c, $c->model( $self->alias_class )->create_or_update );
   return TRUE;
}

sub mail_aliases_delete : ActionFor(mail_aliases.delete) {
   my ($self, $c) = @_; $c->model( $self->alias_class )->delete;

   $self->set_uri_args( $c, $c->stash->{newtag} );
   return TRUE;
}

sub user_admin : Chained(user_base) PathPart('') Args(0) Public {
   my ($self, $c) = @_;

   return $self->redirect_to_path( $c, SEP.q(user_manager) );
}

sub user_manager : Chained(user_base) PathPart(manager) Args HasActions {
   my ($self, $c, $user) = @_; return $c->stash->{user_model}->form( $user );
}

sub user_manager_create_or_update : ActionFor(user_manager.insert)
                                    ActionFor(user_manager.save) {
   my ($self, $c) = @_;

   $self->set_uri_args( $c, $c->stash->{user_model}->create_or_update );
   return TRUE;
}

sub user_manager_delete : ActionFor(user_manager.delete) {
   my ($self, $c) = @_; my $s = $c->stash; $s->{user_model}->delete;

   $self->set_uri_args( $c, $s->{newtag} );
   return TRUE;
}

sub user_manager_fill : ActionFor(user_manager.fill) {
   my ($self, $c) = @_; return $c->stash->{user_model}->user_fill;
}

sub user_profiles : Chained(user_base) PathPart(profiles) Args HasActions {
   my ($self, $c, $profile) = @_;

   return $c->model( $self->profile_class )->form( $profile );
}

sub user_profiles_create_or_update : ActionFor(user_profiles.insert)
                                     ActionFor(user_profiles.save) {
   my ($self, $c) = @_; my $model = $c->model( $self->profile_class );

   $self->set_uri_args( $c, $model->create_or_update );
   return TRUE;
}

sub user_profiles_delete : ActionFor(user_profiles.delete) {
   my ($self, $c) = @_; $c->model( $self->profile_class )->delete;

   $self->set_uri_args( $c, $c->stash->{newtag} );
   return TRUE;
}

sub user_report : Chained(user_base) PathPart(report) Args HasActions {
   my ($self, $c, $report) = @_;

   return $c->stash->{user_model}->form( $report );
}

sub user_report_execute : ActionFor(user_report.execute) {
   my ($self, $c) = @_; return $c->stash->{user_model}->user_report( q(csv) );
}

sub user_report_list : ActionFor(user_report.list) {
   my ($self, $c) = @_; $self->set_uri_args( $c, NUL ); return TRUE;
}

sub user_report_purge : ActionFor(user_report.purge) {
   my ($self, $c) = @_; return $c->stash->{user_model}->purge;
}

sub user_security : Chained(user_base) PathPart(security) Args HasActions {
   my ($self, $c, $user) = @_; return $c->stash->{user_model}->form( $user );
}

sub user_security_set : ActionFor(user_security.set) {
   my ($self, $c) = @_; return $c->stash->{user_model}->set_password;
}

sub user_security_update : ActionFor(user_security.update) {
   my ($self, $c) = @_; return $c->stash->{role_model}->update_roles;
}

sub user_sessions : Chained(user_base) PathPart(sessions) Args(0) HasActions {
   my ($self, $c) = @_; my $model = $c->model( q(Session) );

   $model->list_sessions; $model->list_TTY_sessions;
   return;
}

sub user_sessions_delete : ActionFor(user_sessions.delete) {
   my ($self, $c) = @_; return $c->model( q(Session) )->delete_sessions;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Controller::Admin::UserManager - User account management

=head1 Version

Describes v0.14.$Rev: 1 $

=head1 Synopsis

   package YourApp::Controller::Admin;

   use CatalystX::Usul::Moose;

   BEGIN { extends q(CatalystX::Usul::Controller::Admin) }

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

=head2 user_sessions_delete

Delete the selected user sessions

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Controller>

=item L<CatalystX::Usul::TraitFor::Controller::ModelHelper>

=item L<CatalystX::Usul::TraitFor::Controller::PersistentState>

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
