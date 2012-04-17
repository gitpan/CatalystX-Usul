# @(#)$Id: Help.pm 1181 2012-04-17 19:06:07Z pjf $

package CatalystX::Usul::Model::Help;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.7.%d', q$Rev: 1181 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model CatalystX::Usul::Email);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(distname merge_attributes);
use CatalystX::Usul::Table;
use CatalystX::Usul::Time;
use Time::Elapsed qw(elapsed);
use MRO::Compat;

__PACKAGE__->config( cpan_dist_uri => q(http://search.cpan.org/dist/),
                     default_css   => NUL,
                     name          => NUL, );

__PACKAGE__->mk_accessors( qw(cpan_dist_uri default_css name) );

sub COMPONENT {
   my ($class, $app, $attrs) = @_; my $ac = $app->config;

   merge_attributes $attrs, $ac, $class->config, [ qw(default_css name) ];

   return $class->next::method( $app, $attrs );
}

sub about_form {
   my $self = shift; my $s = $self->context->stash;

   $s->{title} = $s->{header}->{title} = $self->loc( 'About' );
   return;
}

sub add_debug_info {
   my ($self, $prefix) = @_; my $c = $self->context; my $s = $c->stash;

   my $cfg = $c->config; my $data = $s->{user}.q(@).$s->{host_port};

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
}

sub add_footer {
   my $self = shift; my $s = $self->context->stash; my $prefix = q(footer);

   $self->add_select_language( $prefix );
   $s->{debug} and $self->add_debug_info( $prefix );
   $self->add_field ( {
      container => FALSE, name => $prefix, type => q(template), } );
   $self->stash_meta( { id => $prefix.q(.data) } );
   return;
}

sub add_select_language {
   my ($self, $prefix) = @_; my $c = $self->context; my $s = $c->stash;

   my $cfg = $c->config; my @languages = split SPC, $cfg->{languages} || LANG;

   my ($classes, $labels) = ({}, {}); my $name = q(select_language);

   for my $lang (@languages) {
      $classes->{ $lang } = q(flag_).$lang;
      $labels->{ $lang } = $self->loc( q(lang_).$lang );
   }

   $self->add_field( { classes => $classes,
                       default => $s->{lang},
                       id      => $prefix.q(.).$name,
                       labels  => $labels,
                       values  => \@languages } );
   $self->add_field( { default => $self->query_value( q(val) ),
                       name    => q(referer),
                       type    => q(hidden) } );

   my $action = $c->uri_for_action( SEP.$name );

   $self->form_wrapper( { action => $action, name => $name } );
   return;
}

sub documentation {
   my ($self, $path) = @_; my $uri = $self->context->uri_for( $path );

   $self->add_field( { path => $uri, subtype => q(html), type => q(file) } );
   return;
}

sub feedback_form {
   my ($self, @rest) = @_;
   my $nbsp          = NBSP;
   my $s             = $self->context->stash;
   my $subject       = $self->query_value( q(subject) );
   my $form          = $s->{form}->{name};

   $subject ||= $self->loc( $form.q(.subject), $self->name, join SEP, @rest );
   ($s->{html_subject} = $subject) =~ s{ \s+ }{$nbsp}gmx;

   $self->clear_form ( { firstfld => $form.q(.body),
                         title    => $self->loc( $form.q(.title) ) } );
   $self->add_field  ( { id       => $form.q(.body) } );
   $self->add_hidden ( q(subject), $subject );
   $self->add_buttons( qw(Send) );
   return;
}

sub feedback_send {
   my $self    = shift;
   my $s       = $self->context->stash;
   my $subject = $self->query_value( q(subject) ) || $self->name.' feedback';
   my $post    = { attributes  => { charset      => $s->{encoding},
                                    content_type => q(text/html) },
                   body        => $self->query_value( q(body) ) || NUL,
                   from        => $s->{user_email},
                   mailer      => $s->{mailer},
                   mailer_host => $s->{mailer_host},
                   subject     => $subject,
                   to          => $s->{feedback_email} };

   $self->add_result( $self->send_email( $post ) );
   return TRUE;
}

sub module_docs {
   my ($self, $module, $name) = @_; my $c = $self->context; my $s = $c->stash;

   $module ||= $self->name; $name ||= $module;

   my $src   = $self->find_source( $module )
      or return $self->add_error_msg( 'Module [_1] not found', $module );
   my $url   = $c->uri_for_action( $c->config->{module_docs}, '%s' );
   my $help  = $self->loc( 'Help' );
   my $title = $name.SPC.$help;
   my $nav   = $s->{nav_model};

   $nav->clear_controls; $nav->add_menu_close;

   $s->{title     } = $s->{application}.SPC.$help;
   $s->{page_title} = $title.q( - ).$s->{application}.SPC.$s->{platform};

   $self->clear_form( { title => $s->{title} } );
   $self->add_field ( { src   => $src,
                        title => $title,
                        type  => q(POD),
                        url   => $url, } );
   return;
}

sub module_list {
   my $self = shift; my $c = $self->context; my $s = $c->stash; my $name;

   # TODO: Switch to using Module::Versions
   # Otherwise lots from modules that don't set VERSION
   no warnings; ## no critic

   my $count = 0;
   my $docs  = $c->action->namespace.SEP.q(module_docs);
   my $table = __get_module_table();

   for my $path (sort keys %INC) {
      $path =~ m{ \A [/] }mx and next;

      ($name = $path) =~ s{ [/] }{::}gmx; $name =~ s{ \.pm }{}gmx;

      my $c_uri = $self->cpan_dist_uri.(distname $name);
      my $h_uri = $c->uri_for_action( $docs, $name );
      my $s_uri = $c->uri_for_action( SEP.q(view_source), $name );
      my $flds  = {};

      $flds->{name   } = $name;
      $flds->{cpan   } = __make_icon( 'CPAN',           q(link_icon), $c_uri );
      $flds->{help   } = __make_icon( 'Doucumentation', q(help_icon), $h_uri );
      $flds->{source } = __make_icon( 'View Source',    q(file_icon), $s_uri );
      $flds->{version} = eval { $name->VERSION() };

      push @{ $table->values }, $flds; $count++;
   }

   $table->count( $count );
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

# Private methods

sub _add_template_data {
   my ($self, $name, $data, $alt) = @_; my $s = $self->context->stash;

   my $key = "template_data_${name}";
   my $tip = ($s->{tip_title} || DOTS).TTS.$self->loc( $alt || 'None' );

   $s->{ $key } ||= []; push @{ $s->{ $key } }, { text => $data, tip => $tip };
   return;
}

# Private subroutines

sub __get_module_table {
   return CatalystX::Usul::Table->new
      ( class    => { cpan    => q(icons),
                      help    => q(icons),
                      name    => q(data_value),
                      source  => q(icons),
                      version => q(data_value), },
        flds     => [ qw(source help cpan name version) ],
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
        typelist => { version => q(numeric), } );
}

sub __make_icon {
   my ($alt, $imgclass, $href) = @_;

   return { class     => q(icon),
            container => FALSE,
            href      => $href,
            imgclass  => $imgclass,
            sep       => NUL,
            target    => q(documentation),
            text      => NUL,
            tip       => $alt,
            type      => q(anchor),
            widget    => TRUE };
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Help - Provides data for help pages

=head1 Version

0.7.$Revision: 1181 $

=head1 Synopsis

   package MyApp::Model::Help;

   use base qw(CatalystX::Usul::Model::Help);

   1;

   package MyApp::Controller::Foo;

   sub bar {
      my ($self, $c) = @_;

      $c->model( q(Help) )->get_help( $c->stash, q(Foo) );
   }

=head1 Description

Provides context sensitive help. Help text comes from running
L<Pod::Html> on the controller source

=head1 Subroutines/Methods

=head2 COMPONENT

Constructor sets attributes for: default CSS filename and the
application name from the application config

=head2 about_form

Provides information about the application. Content is implemented in a
template

=head2 add_debug_info

Adds some useful information to the footer if debug is turned on

=head2 add_footer

Calls L</add_debug_info> and L</add_select_language>

=head2 add_select_language

Adds a form containing a popup menu that allows the user to select from
the list of supported languages. Called from L</add_footer>

=head2 documentation

   $self->model( q(Help) )->documentation( $uri );

Adds a file type field to the form. Displays as an I<iframe>
containing the HTML document referenced by C<$uri>

=head2 feedback_form

Adds the fields and button data to the stash for the user feedback form

=head2 feedback_send

Sends an email to the site administrators

=head2 get_help

Add a field of type I<POD>

=head2 module_docs

Extract the POD for a given module and renders it as HTML

=head2 module_list

Generates the data for a table that shows all the modules the application
is using. Links allow the source code and the POD to be viewed

=head2 overview

Generate the data for an XML response to a Javascript C<XMLHttpRequest()>

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::Table>

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
