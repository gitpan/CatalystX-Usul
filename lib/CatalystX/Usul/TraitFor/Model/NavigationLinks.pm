# @(#)Ident: NavigationLinks.pm 2013-08-19 19:18 pjf ;

package CatalystX::Usul::TraitFor::Model::NavigationLinks;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.16.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Moose::Role;
use Moose::Util::TypeConstraints;
use CatalystX::Usul::Constants;

requires qw(context loc);

enum 'LinkType', [ qw(modal tab window) ];

has 'about_action'    => is => 'ro', isa => 'Str', default => SEP.q(about);

has 'company_action'  => is => 'ro', isa => 'Str', default => SEP.q(company);

has 'feedback_action' => is => 'ro', isa => 'Str', default => SEP.q(feedback);

has 'logout_action'   => is => 'ro', isa => 'Str', default => SEP.q(logout);

has 'link_type'       => is => 'ro', isa => 'LinkType', default => q(tab);

sub get_about_menu_link {
   my ($self, $args) = @_; my $c = $self->context; my $s = $c->stash;

   my $class = $args->{name}.q(_link fade);
   my $field = $s->{fields}->{ 'about_link' } || {};
   my $href  = $c->uri_for_action( $self->about_action );
   my $id    = __get_link_id( $args );
   my $text  = $self->loc( q(aboutOptionText) );
   my $tip   = $args->{title}.TTS.$self->loc( q(aboutOptionTip) );
   my $type  = $field->{type} // $self->link_type;

   $type eq q(tab) and return { class  => $class, href => $href,  id  => $id,
                                target => 'help', text => $text, tip => $tip };

   my $method = $type eq q(modal) ? "'modalDialog'" : "'openWindow'";
   my $jsargs = "[ '${href}', { name: 'about', title: '${text}' } ]";

   return { class  => "${class} windows",
            config => { method => $method, args => $jsargs, },
            href   => '#top', id => $id, text => $text, tip => $tip, };
}

sub get_alternate_skin_link {
   my ($self, $args, $skin) = @_;

   return { class  => $args->{name}.q(_link fade submit),
            config => { method => "'refresh'", args => "[ 'skin', '${skin}' ]"},
            href   => '#top',
            id     => __get_link_id( $args ),
            text   => (ucfirst $skin).SPC.$self->loc( q(changeSkinAltText) ),
            tip    => $args->{title}.TTS.$self->loc( q(changeSkinAltTip) ) };
}

sub get_blank_link {
   my $self = shift; my $text = NBSP x 100;

   return { class => $self->menu_title_class, href => '#top', text => $text };
}

sub get_close_link {
   my ($self, $args) = @_;

   my $field = $args->{field} || NUL;
   my $form  = $args->{form } || NUL;
   my $value = $args->{value} || NUL;
   my $tip   = $self->loc( $args->{tip} || 'Close this window' );
   my $title = $args->{title} ? $self->loc( $args->{title} )
                              : $self->_localized_nav_title;

   return { class  => $self->menu_title_class.q( submit),
            config => { args   => "[ '${form}', '${field}', '${value}' ]",
                        method => "'returnValue'" },
            href   => '#top',
            id     => q(close_window),
            text   => $self->loc( $args->{text } || 'Close' ),
            tip    => $title.TTS.$tip };
}

sub get_company_link {
   my ($self, $args) = @_; my $c = $self->context; my $s = $c->stash;

   my $id    = q(company_link);
   my $class = $args->{name}.q(_link fade);
   my $field = $s->{fields}->{ $id } || {};
   my $hash  = { container_id    => $args->{name}.q(SubTitle),
                 container_class => $args->{name}.q(_subtitle),
                 id              => $id,
                 text            => $s->{company},
                 tip             => DOTS.TTS.$self->loc( q(aboutCompanyTip) ),
                 type            => q(anchor), };
   my $href  = $c->uri_for_action( $self->company_action );
   my $title = $self->loc( 'Company Information' );
   my $type  = $field->{type} // $self->link_type;

   $type eq q(tab) and return
      { %{ $hash }, class => $class, href => $href, target => 'help', };

   my $method = $type eq q(modal) ? "'modalDialog'" : "'openWindow'";
   my $jsargs = "[ '${href}', { name: 'company', title: '${title}' } ]";

   return { %{ $hash },
            class  => "${class} windows",
            config => { method => $method, args => $jsargs, },
            href   => '#top', sep => NUL, };
}

sub get_context_help_link {
   my ($self, $args) = @_; my $c = $self->context; my $s = $c->stash;

   my $class = $args->{name}.q(_link fade);
   my $field = $s->{fields}->{ 'help_link' } || {};
   my $href  = $c->stash->{help_url};
   my $id    = __get_link_id( $args );
   my $text  = $self->loc( q(contextHelpText) );
   my $tip   = $args->{title}.TTS.$self->loc( q(contextHelpTip) );
   my $type  = $field->{type} // $self->link_type;

   $type eq q(tab) and return
      { class  => $class, href => $href, id   => $id,
        target => 'help', text => $text, tip  => $tip };

   my $method = $type eq q(modal) ? "'modalDialog'" : "'openWindow'";

   return { class  => "${class} windows",
            config => { method => $method,
                        args   => "[ '${href}', { name: 'help' } ]", },
            href   => '#top', id   => $id,   text => $text, tip => $tip };
}

sub get_debug_toggle_link {
   my ($self, $args) = @_; my $s = $self->context->stash;

   my $id   = __get_link_id( $args );
   my $text = $self->loc( q(debugOffText) );
   my $alt  = $self->loc( q(debugOnText) );

   return { class     => $args->{name}.q(_link fade togglers),
            config    => {
               method => "'toggleSwapText'",
               args   => "[ '${id}', 'debug', '${text}', '${alt}' ]", },
            href      => '#top',
            id        => $id,
            text      => $s->{debug} ? $text : $alt,
            tip       => $args->{title}.TTS.$self->loc( q(debugToggleTip) ) };
}

sub get_default_skin_link {
   my ($self, $args, $skin) = @_;

   my $tip = $args->{title}.TTS.$self->loc( q(changeSkinDefaultTip) );

   return { class  => $args->{name}.q(_link fade submit),
            config => { method => "'refresh'",
                        args   => "[ 'skin', '${skin}' ]", },
            href   => '#top',
            id     => __get_link_id( $args ),
            text   => $self->loc( q(changeSkinDefaultText) ),
            tip    => $tip };
}

sub get_feedback_menu_link {
   my ($self, $args) = @_; my $c = $self->context; my $s = $c->stash;

   my $class  = $args->{name}.q(_link fade);
   my $field  = $s->{fields}->{ 'feedback_link' } || {};
   my $href   = $c->uri_for_action
      ( $self->feedback_action, $c->action->namespace, $c->action->name );
   my $id     = __get_link_id( $args );
   my $opts   = "{ height: 670, name: 'feedback', width: 850 }";
   my $text   = $self->loc( q(feedbackOptionText) );
   my $tip    = $args->{title}.TTS.$self->loc( q(feedbackOptionTip) );
   my $type   = $field->{type} // $self->link_type;

   $type eq q(tab) and return
      { class  => $class, href => $href, id   => $id,
        target => 'help', text => $text, tip  => $tip };

   my $method = $type eq q(modal) ? "'modalDialog'" : "'openWindow'";

   return { class  => "${class} windows",
            config => { method => $method, args => "[ '${href}', ${opts} ]", },
            href   => '#top', id => $id, text => $text, tip => $tip };
}

sub get_footer_toggle_link {
   my ($self, $args) = @_; my $s = $self->context->stash;

   my $id   = __get_link_id( $args );
   my $text = $self->loc( q(footerOffText) );
   my $alt  = $self->loc( q(footerOnText) );

   return { class     => $args->{name}.q(_link fade server togglers),
            config    => {
               method => "'toggleSwapText'",
               args   => "[ '${id}', 'footer', '${text}', '${alt}' ]", },
            href      => '#top',
            id        => $id,
            text      => $s->{footer}->{state} ? $text : $alt,
            tip       => $args->{title}.TTS.$self->loc( q(footerToggleTip) ) };
}

sub get_help_menu_link {
   my ($self, $args) = @_;

   return { class    => $args->{name}.q(_title fade),
            href     => '#top',
            id       => __get_link_id( $args ),
            imgclass => q(help_icon),
            sep      => NUL,
            text     => NUL,
            tip      => DOTS.TTS.$args->{title} };
}

sub get_history_back_link {
   my ($self, $args) = @_;

   my $tip = $self->loc( $args->{tip} || 'Go back to the previous page' );

   return { class  => $self->menu_title_class.q( submit),
            config => { args => "[]", method => "'historyBack'" },
            href   => '#top',
            id     => q(history_back),
            text   => $self->loc( 'Back' ),
            tip    => $self->_localized_nav_title.TTS.$tip };
}

sub get_logo_link {
   my $self = shift; my $s = $self->context->stash;

   my $href = $s->{server_home} || q(http://).$s->{host};

   return { class           => q(logo),
            container_id    => q(companyLogo),
            container_class => q(company_logo),
            fhelp           => q(Company Logo),
            hint_title      => $href,
            href            => $href,
            imgclass        => q(logo),
            sep             => NUL,
            text            => $s->{assets}.($s->{logo} || q(logo.png)),
            tip             => $self->loc( q(logoTip) ),
            type            => q(anchor) };
}

sub get_logout_link {
   my ($self, $args) = @_; my $c = $self->context;

   my $href = $c->uri_for_action( $self->logout_action );

   return { class    => $args->{name}.q(_title fade windows),
            config   => { args   => "[ '${href}' ]", method => "'location'" },
            href     => '#top',
            id       => __get_link_id( $args ),
            imgclass => q(exit_icon),
            sep      => NUL,
            text     => NUL,
            tip      => $args->{title}.TTS.$self->loc( q(exitTip) ) };
}

sub get_tools_menu_link {
   my ($self, $args) = @_;

   return { class    => $args->{name}.q(_title fade),
            href     => '#top',
            id       => __get_link_id( $args ),
            imgclass => q(tools_icon),
            sep      => NUL,
            text     => NUL,
            tip      => DOTS.TTS.$args->{title} };
}

# Private functions

sub __get_link_id {
   return $_[ 0 ]->{name}.$_[ 0 ]->{menu}.q(item).$_[ 0 ]->{item};
}

no Moose::Role;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TraitFor::Model::NavigationLinks - Provides navigation links

=head1 Version

Describes v0.16.$Rev: 1 $

=head1 Synopsis

   package YourApp::Model::Navigation;

   use CatalystX::Usul::Moose;

   with q(CatalystX::Usul::TraitFor::Model::NavigationLinks);

=head1 Description

Each of the methods in this class returns a hash ref. that is used to
instantiate an anchor link in the L<HTML::FormWidgets> class

=head1 Configuration and Environment

Defines the following attributes:

=over 3

=item C<about_action>

A string which defaults to C</about>. The action in the root controller
that displays the application "about" information

=item C<company_action>

A string which defaults to C</company>. The action in the root controller
that displays the information about the company

=item C<feedback_action>

A string which defaults to C</feedback>. The action in the root controller
that displays the application feedback email form

=item C<logout_action>

A string which defaults to C</logout>. The action in the root controller
that logs the user out of the application

=item C<link_type>

One of; C<modal>, C<tab>, or C<window>. Which type of link should be
created if the links C<< $c->stash->{fields}->{ link_id } >> attribute
does not specify. A value of C<modal> uses JavaScript to create a model dialog.
A value of C<tab> opens a new tab in browser. A value of C<window> creates a
new browser window. Defaults to C<tab>.

=back

=head1 Subroutines/Methods

=head2 get_about_menu_link

   $anchor_hash_ref = $self->get_about_menu_link;

The link to the "about the application" page

=head2 get_alternate_skin_link

   $anchor_hash_ref = $self->get_alternate_skin_link;

The link to select a different skin (theme)

=head2 get_blank_link

   $anchor_hash_ref = $self->get_blank_link;

A blank link the goes nowhere

=head2 get_close_link

   $anchor_hash_ref = $self->get_close_link;

A link that will close the current tab / window

=head2 get_company_link

   $anchor_hash_ref = $self->get_company_link;

A link the displays information about the company

=head2 get_context_help_link

   $anchor_hash_ref = $self->get_context_help_link;

A link the displays the context sensitive help page

=head2 get_debug_toggle_link

   $anchor_hash_ref = $self->get_debug_toggle_link;

A link to toggle the runtime debugging state

=head2 get_default_skin_link

   $anchor_hash_ref = $self->get_default_skin_link;

A link to select the default skin (theme)

=head2 get_feedback_menu_link

   $anchor_hash_ref = $self->get_feedback_menu_link;

A link to display the application feedback email form

=head2 get_footer_toggle_link

   $anchor_hash_ref = $self->get_footer_toggle_link;

A link that toggles the footer region on / off

=head2 get_help_menu_link

   $anchor_hash_ref = $self->get_help_menu_link;

A link to display the help menu

=head2 get_history_back_link

   $anchor_hash_ref = $self->get_history_back_link;

A link to go back in the browser history

=head2 get_logo_link

   $anchor_hash_ref = $self->get_logo_link;

Returns a content hash ref that renders as a clickable image anchor. The
link returns to the web servers default page

=head2 get_logout_link

   $anchor_hash_ref = $self->get_logout_link;

A link to log the user out of the application

=head2 get_tools_menu_link

   $anchor_hash_ref = $self->get_tools_menu_link;

A link to display the tools menu

=head1 Diagnostics

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

=head1 Acknowledgements

Larry Wall - For the Perl programming language

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
