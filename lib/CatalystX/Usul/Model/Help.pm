package CatalystX::Usul::Model::Help;

# @(#)$Id: Help.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Model);
use CatalystX::Usul::Table;
use Class::C3;
use File::Spec;
use Pod::Html;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

my $HASH = chr 35;
my $NUL  = q();
my $SEP  = q(/);
my $SPC  = q( );

__PACKAGE__->mk_accessors( qw(default_css libsdir name) );

sub new {
   my ($self, $app, @rest) = @_;

   my $new      = $self->next::method( $app, @rest );
   my $app_conf = $app->config || {};

   $new->default_css( $app_conf->{default_css} );
   $new->libsdir    ( $app_conf->{libsdir    } );
   $new->name       ( $app_conf->{name       } );

   return $new;
}

sub documentation {
   my ($self, $uri) = @_;

   $self->add_field( { path => $uri, subtype => q(html), type => q(file) } );
   return;
}

sub feedback_form {
   my ($self, @rest) = @_;
   my $s             = $self->context->stash;
   my $subject       = $self->query_value( q(subject) );
   my $form          = $s->{form}->{name};

   $subject ||= $self->loc( $form.q(.subject), $self->name, join $SEP, @rest );
   ($s->{html_subject} = $subject) =~ s{ \s+ }{&nbsp;}gmx;

   $self->clear_form(  { firstfld => $form.q(.body),
                         title    => $self->loc( $form.q(.title) ) } );
   $self->add_field(   { id       => $form.q(.body) } );
   $self->add_hidden(  q(subject), $subject );
   $self->add_buttons( qw(Send) );
   return;
}

sub feedback_send {
   my $self    = shift;
   my $s       = $self->context->stash;
   my $subject = $self->query_value( q(subject) ) || $self->name.' feedback';
   my $args    = { attributes  => { charset      => $s->{encoding},
                                    content_type => q(text/html) },
                   body        => $self->query_value( q(body) ) || $NUL,
                   from        => $s->{user}.q(@).$s->{host},
                   mailer      => $s->{mailer},
                   mailer_host => $s->{mailer_host},
                   subject     => $subject,
                   to          => $s->{feedback_email} };

   $self->add_result( $self->send_email( $args ) );
   return;
}

sub get_help {
   # Generate the context sensitive help from the POD in the code
   my ($self, @args) = @_; my $e;

   return unless ($args[ 0 ]);

   my $controller = ucfirst ((split m{ $HASH }mx, $args[ 0 ])[ 0 ]);
   my $title      = $self->loc( q(helpTitle), $controller );

   $self->clear_form( { title => $title } );

   my $src   = $self->catfile( $self->libsdir,
                               $self->catfile( split m{ :: }mx, $self->name ),
                               q(Controller),
                               $controller.q(.pm) );
   my $page  = eval { $self->retrieve( $src ) };

   if ($e = $self->catch) { $self->add_error( $e ) }
   else { $self->stash_content( $page, q(sdata) ) }

   $self->context->stash( is_popup => q(true) );
   return;
}

sub module_docs {
   my ($self, $module) = @_; my $s = $self->context->stash; my $e;

   $s->{menus}->[0]->{selected}  = 2;
   $s->{menus}->[2]->{href    } .= $SEP.$module;

   my $title = $self->loc( q(helpTitle), $module );

   $self->clear_form( { title => $title } );

   my $page  = eval { $self->retrieve( $self->find_source( $module ) ) };

   if ($e = $self->catch) { $self->add_error( $e ) }
   else { $self->stash_form( $page ) }

   return;
}

sub module_list {
   my $self = shift; my $s = $self->context->stash; my $name;

   # Otherwise lots from modules that don't set VERSION
   no warnings; ## no critic

   my $count = 0;
   my $table = CatalystX::Usul::Table->new
      ( align  => { help    => 'center',
                    name    => 'left',
                    source  => 'center',
                    version => 'right' },
        flds   => [ qw(source help name version) ],
        hclass => { help    => q(minimal),
                    name    => q(most),
                    source  => q(minimal),
                    version => q(some) },
        labels => { help    => q(&nbsp;),
                    name    => 'Module Name',
                    source  => q(&nbsp;),
                    version => 'Version' } );

   for my $path (sort keys %INC) {
      next if ($path =~ m{ \A [/] }mx);

      ($name = $path) =~ s{ [/] }{::}gmx; $name =~ s{ \.pm }{}gmx;

      my $href  = $self->uri_for( $SEP.q(module_docs), $s->{lang}, $name );
      my $vsap  = q(root).$SEP.q(view_source);
      my $sref  = $self->uri_for( $vsap, $s->{lang}, $name );
      my $flds  = {};

      $flds->{name   } = $name;
      $flds->{help   } = _make_icon( 'Doucumentation',
                                     $s->{assets}.'help.gif', $href );
      $flds->{source } = _make_icon( 'Source', $s->{assets}.'f.gif', $sref );
      $flds->{version} = eval { $name->VERSION() };

      push @{ $table->values }, $flds;
      $count++;
   }

   $table->count( $count );
   $self->add_field(    { data => $table, type => q(table) } );
   $self->group_fields( { id   => q(module_list_select), nitems => 1 } );
   return;
}

sub overview {
   my $self = shift;

   $self->add_field ( { name => q(overview), type => q(label) } );
   $self->stash_meta( { id   => q(overview) } );
   delete $self->context->stash->{token};
   return;
}

sub retrieve {
   my ($self, $src) = @_; my $s = $self->context->stash; my $line;

   no warnings; ## no critic

   my $body = 0; my $page = $NUL; my $tmp = $self->tempfile;

   pod2html( '--backlink='.$self->loc( q(Back to Top) ),
             '--cachedir='.$self->tempdir,
             '--css='.$self->catfile( $s->{assets}, $self->default_css ),
             '--infile='.$src,
             '--outfile='.$tmp->pathname,
             '--quiet',
             '--title='.$s->{title} );

   while (defined ($line = $tmp->getline) ) {
      $body  = 0     if ($line =~ m{ \</body }mx);
      $page .= $line if ($body);
      $body  = 1     if ($line =~ m{ \<body }mx);
   }

   return $page;
}

# Private subroutines

sub _make_icon {
   my ($alt, $src, $href) = @_;

   return { container => 0,
            fhelp     => $alt,
            href      => $href,
            imgclass  => q(normal),
            sep       => q(),
            text      => $src,
            type      => q(anchor),
            widget    => 1 };
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Help - Create HTML from POD

=head1 Version

0.1.$Revision: 402 $

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

=head2 new

Constructor sets attributes for: default CSS filename, libsdir, and
application name from the application config

=head2 documentation

   $self->model( q(Help) )->documentation( $uri );

Adds a file type field to the form. Displays as an I<iframe>
containing the HTML document referenced by C<$uri>

=head2 feedback_form

Adds the fields and button data to the stash for the user feedback form

=head2 feedback_send

Sends an email to the site administrators

=head2 get_help

Add the field to the stash that is the rendered HTML created by
calling L</retrieve>

=head2 module_docs

Extract the POD for a given module and renders it as HTML

=head2 module_list

Generates the data for a table that shows all the modules the application
is using. Links allow the source code and the POD to be viewed

=head2 overview

Generate the data for an XML response to a Javascript C<XMLHttpRequest()>

=head2 retrieve

Calls L<Pod::Html> to create the help text from the controller POD

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::Table>

=item L<Pod::Html>

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
