# @(#)Ident: Help.pm 2013-11-21 23:41 pjf ;

package CatalystX::Usul::Model::Help;

use strict;
use version; our $VERSION = qv( sprintf '0.17.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw( distname find_source merge_attributes throw);
use CatalystX::Usul::Moose;
use Class::Usul::Time;
use Time::Elapsed              qw( elapsed );

extends q(CatalystX::Usul::Model);
with    q(CatalystX::Usul::TraitFor::Model::StashHelper);
with    q(CatalystX::Usul::TraitFor::Model::QueryingRequest);
with    q(CatalystX::Usul::TraitFor::Email);

has 'cpan_dist_uri' => is => 'ro', isa => NonEmptySimpleStr,
   default          => q(http://search.cpan.org/dist/);

has 'name'          => is => 'ro', isa => NonEmptySimpleStr,
   required         => TRUE;

sub COMPONENT {
   my ($class, $app, $attr) = @_;

   merge_attributes $attr, $app->config, {}, [ qw(name) ];

   return $class->next::method( $app, $attr );
}

sub about_form {
   my $self = shift; $self->_set_title( 'About' );

   $self->add_field ( { container_class => q(info_dialog),
                        id              => q(about_dialog),
                        name            => q(about),
                        type            => q(template) } );
   $self->stash_meta( { id              => q(about_dialog) } );
   return;
}

sub add_language_selector {
   my ($self, $prefix, $name) = @_; my $c = $self->context; my $s = $c->stash;

   my $cfg = $c->config; my @languages = split SPC, $cfg->{languages} || LANG;

   my ($classes, $labels) = ({}, {});

   for my $lang (@languages) {
      $classes->{ $lang } = "flag_${lang}";
       $labels->{ $lang } = $self->loc( "lang_${lang}" );
   }

   $self->add_field( { classes => $classes,
                       default => $s->{language},
                       id      => "${prefix}.${name}",
                       labels  => $labels,
                       values  => \@languages } );
   $self->add_field( { default => $self->query_value( q(val) ),
                       name    => q(referer),
                       type    => q(hidden) } );

   my $action = $c->uri_for_action( SEP.$name );

   $self->form_wrapper( { action => $action, name => $name } );
   return;
}

sub company_form {
   my $self = shift; $self->_set_title( 'Company Information' );

   $self->add_field ( { container_class => q(info_dialog),
                        id              => q(company_dialog),
                        name            => q(company),
                        type            => q(template) } );
   $self->stash_meta( { id              => q(company_dialog) } );
   return;
}

sub documentation_form {
   my ($self, $path) = @_; my $uri = $self->context->uri_for( $path );

   $self->add_field( { path => $uri, subtype => q(html), type => q(file) } );
   return;
}

sub feedback_form {
   my ($self, @args) = @_;
   my $nbsp          = NBSP;
   my $s             = $self->context->stash;
   my $subject       = $self->query_value( q(subject) );
   my $form          = $s->{form}->{name};

   $subject ||= $self->loc( "${form}.subject", $self->name, join SEP, @args );
   ($s->{html_subject} = $subject) =~ s{ \s+ }{$nbsp}gmx;

   $self->clear_form ( { firstfld => "${form}.body",
                         title    => $self->loc( "${form}.title" ) } );
   $self->add_field  ( { id       => "${form}.body" } );
   $self->add_hidden ( q(subject), $subject );
   $self->add_buttons( qw(Send) );
   return;
}

sub feedback_send {
   my $self    = shift;
   my $s       = $self->context->stash;
   my $subject = $self->query_value( q(subject) ) || $self->name.' feedback';
   my $post    = { attributes      => {
                      charset      => $self->encoding,
                      content_type => q(text/html) },
                   body            => $self->query_value( q(body) ) || NUL,
                   from            => $s->{user}->email_address,
                   mailer          => $s->{mailer},
                   mailer_host     => $s->{mailer_host},
                   subject         => $subject,
                   to              => $s->{feedback_email} };

   $self->add_result_msg( 'Email sent to [_1]', $self->send_email( $post ) );
   return TRUE;
}

sub footer_form {
   my ($self, $selector_name) = @_; my $prefix = q(footer);

   defined $selector_name or throw 'Selector name undefined';
   $self->add_language_selector( $prefix, $selector_name );
   $self->context->stash->{debug} and $self->stash_debug_info( $prefix );
   $self->add_field ( {
      container => FALSE, id => $prefix, type => q(template), } );
   $self->stash_meta( { id => "${prefix}.data" } );
   return;
}

sub help_form {
   my ($self, $module) = @_; $module ||= $self->name;

   my $c       = $self->context;
   my $src     = find_source $module
      or return $self->add_error( 'Module [_1] not found', $module );
   my $docs_ap = $c->stash->{action_paths}->{module_docs};
   my $url     = $c->uri_for_action( $docs_ap, '%s' );
   my $title   = $self->_set_title( 'Help for', $module );

   $self->clear_form( { title => $c->stash->{title} } );
   $self->add_field ( { src   => $src,
                        title => $title,
                        type  => q(POD),
                        url   => $url, } );
   return;
}

sub modules_form {
   my $self = shift; my $c = $self->context; my $s = $c->stash;

   my $aps  = $s->{action_paths}; my $docs_ap = $aps->{module_docs};

   my $view_source_ap = $aps->{view_source};

   no warnings; ## no critic

   my @rows = (); my $count = 0;

   for my $path (sort keys %INC) {
      $path =~ m{ \A [/] }mx and next;

     (my $name  = $path) =~ s{ [/] }{::}gmx; $name =~ s{ \.pm }{}gmx;
      my $c_uri = $self->cpan_dist_uri.(distname $name);
      my $h_uri = $c->uri_for_action( $docs_ap, $name );
      my $s_uri = $c->uri_for_action( $view_source_ap, $name );
      my $flds  = {};

      $flds->{name   } = $name;
      $flds->{cpan   } = __make_icon( 'CPAN',           q(link_icon), $c_uri );
      $flds->{help   } = __make_icon( 'Doucumentation', q(help_icon), $h_uri );
      $flds->{source } = __make_icon( 'View Source',    q(file_icon), $s_uri );
      $flds->{version} = eval { $name->VERSION() };

      push @rows, $flds; $count++;
   }

   my $table = $self->_get_module_table( \@rows, $count );

   $self->add_field( { data => $table, number_rows => TRUE, type => q(table) });
   $self->group_fields( { id => q(module_list.select) } );
   return;
}

sub overview {
   my $self = shift;

   $self->add_field ( { id => q(overview) } );
   $self->stash_meta( { id => q(overview) } );
   return;
}

sub stash_debug_info {
   my ($self, $prefix) = @_; my $c = $self->context; my $s = $c->stash;

   my $cfg = $c->config; my $data = $s->{user}->username.q(@).$s->{host};

   $s->{tip_title} = $self->loc( 'Debug Info' );
   $self->_add_template_data( $prefix, $data, q(yourIdentity) );

   # Useful numbers and such
   $cfg->{version} and $self->_add_template_data( $prefix, $cfg->{version},
                                                  q(moduleVersion) );

   defined $s->{version} and $self->_add_template_data( $prefix, $s->{version},
                                                        q(levelVersion) );

   $self->_add_template_data( $prefix, time2str(), q(pageGenerated) );

   $s->{elapsed} and $self->_add_template_data( $prefix,
                                                elapsed( $s->{elapsed} ),
                                                q(elapsedTime) );

   $self->_add_template_data( $prefix, $s->{user_agent}->name, 'User agent' );
   $data = $s->{user_agent}->version;
   $self->_add_template_data( $prefix, $data, 'User agent version' );
   return;
}

# Private methods

sub _add_template_data {
   my ($self, $id, $data, $alt) = @_; my $s = $self->context->stash;

   my $key = q(template_data);
   my $tip = ($s->{tip_title} || DOTS).TTS.$self->loc( $alt || 'None' );

   push @{ $s->{ $key }->{ $id } ||= [] }, { text => $data, tip => $tip };
   return;
}

sub _get_module_table {
   my ($self, $values, $count) = @_;

   return $self->table_class->new
      ( class    => { cpan    => q(icons),
                      help    => q(icons),
                      name    => q(data_value),
                      source  => q(icons),
                      version => q(data_value), },
        count    => $count,
        fields   => [ qw(source help cpan name version) ],
        hclass   => { cpan    => q(minimal),
                      help    => q(minimal),
                      name    => q(most),
                      source  => q(minimal),
                      version => q(some) },
        labels   => { cpan    => 'CPAN',
                      help    => 'Help',
                      name    => 'Module Name',
                      source  => 'Source',
                      version => 'Version' },
        typelist => { version => q(numeric), },
        values   => $values );
}

sub _set_title {
   my ($self, $text, $module) = @_;

   $text = $self->loc( $text ); $module ||= NUL;

   my $s = $self->context->stash; my $title = "${text} ${module}";

   $s->{page_title}      = $s->{application}.SPC.$s->{platform}.q( - ).$title;
   $s->{title}           = $self->loc( '[_1] Help', $s->{application} );
   $s->{header}->{title} = $title;

   return $title;
}

# Private subroutines

sub __make_icon {
   return { class     => q(icon),
            container => FALSE,
            href      => $_[ 2 ],
            imgclass  => $_[ 1 ],
            sep       => NUL,
            target    => q(documentation),
            text      => NUL,
            tip       => $_[ 0 ],
            type      => q(anchor),
            widget    => TRUE };
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Help - Provides data for help pages

=head1 Version

Describes v0.17.$Rev: 1 $

=head1 Synopsis

   package YourApp;

   use Catalyst qw(ConfigComponents...);

   __PACKAGE__->config(
     'Model::Help'     => {
        parent_classes => q(CatalystX::Usul::Model::Help) }, );

=head1 Description

Provides context sensitive help. Help text comes from running
L<Pod::Html> on the controller source

=head1 Configuration and Environment

Defined the following list of attributes

=over 3

=item cpan_dist_uri

A non empty simple string which defaults to I<http://search.cpan.org/dist/>.
The uri prefix for a distributions online documentation

=item name

A required non empty simple string. The name of the application

=back

=head1 Subroutines/Methods

=head2 COMPONENT

Constructor sets attributes for the application name from the
application config

=head2 about_form

   $self->about_form;

Provides information about the application. Content is implemented in a
template

=head2 add_language_selector

   $self->add_language_selector( $prefix, $name );

Adds a form containing a popup menu that allows the user to select from
the list of supported languages. Called from L</add_footer>

=head2 company_form

   $self->company_form;

Provides information about the company. Content is implemented in a
template

=head2 documentation_form

   $self->documentation_form( $uri );

Adds a file type field to the form. Displays as an I<iframe>
containing the HTML document referenced by C<$uri>

=head2 feedback_form

   $self->feedback_form( @args );

Adds the fields and button data to the stash for the user feedback form

=head2 feedback_send

   $self->feedback_send;

Sends an email to the site administrators

=head2 footer_form

   $self->footer_form;

Calls L</stash_debug_info> and L</add_language_selector>

=head2 help_form

   $self->help_form( $module );

Extract the POD for a given controller and renders it as HTML

=head2 modules_form

   $self->modules_form;

Generates the data for a table that shows all the modules the application
is using. Links allow the source code and the POD to be viewed

=head2 overview

   $self->overview;

Generate the data for an XML response to a Javascript C<XMLHttpRequest()>

=head2 stash_debug_info

   $self->stash_debug_info( $prefix );

Stashes some useful information if debug is turned on

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::TraitFor::Model::StashHelper>

=item L<CatalystX::Usul::TraitFor::Model::QueryingRequest>

=item L<CatalystX::Usul::TraitFor::Email>

=item L<CatalystX::Usul::Moose>

=item L<Class::Usul::Time>

=item L<Time::Elapsed>

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
