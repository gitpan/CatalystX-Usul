# @(#)Ident: Email.pm 2013-11-21 23:24 pjf ;

package CatalystX::Usul::TraitFor::Email;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.16.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Moose::Role;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw( ensure_class_loaded is_hashref throw );
use Email::MIME;
use Encode;
use File::Basename             qw( basename );
use File::DataClass::IO;
use MIME::Types;
use Template;

requires qw( loc );

sub send_email {
   my ($self, $args) = @_;

              $args or throw 'Email parameters not specified';
   is_hashref $args or throw 'Email parameters not a hash ref';

   $args->{email} = $self->_create_email( $args );

   return $self->_transport_email( $args );
}

# Private methods

sub _add_attachments {
   my ($self, $args, $email) = @_; $args ||= {}; $email ||= {};

   my $types = MIME::Types->new( only_complete => TRUE );
   my $part  = Email::MIME->create( attributes => $email->{attributes},
                                    body       => delete $email->{body} );

   $email->{parts} = [ $part ];

   while (my ($attachment, $path) = each %{ $args->{attachments} }) {
      my $body  = io( $path )->lock->all;
      my $file  = basename( $path );
      my $mime  = $types->mimeTypeOf( $file );
      my $attrs = { content_type => $mime->type,
                    encoding     => $mime->encoding,
                    filename     => $file,
                    name         => $attachment };

      $part = Email::MIME->create( attributes => $attrs, body => $body );
      push @{ $email->{parts} }, $part;
   }

   return;
}

sub _create_email {
   my ($self, $args) = @_; $args ||= {};

   my $email    = { attributes => $args->{attributes} || {} };
   my $from     = $args->{from} or throw 'No email from attribute';
   my $to       = $args->{to  } or throw 'No email to attribute';
   my $subject  = encode( 'MIME-Header', $args->{subject} || 'No subject' );
   my $encoding = $email->{attributes}->{charset};

   $email->{header} = [ From => $from, To => $to, Subject => $subject ];
   $email->{body  } = $self->_get_email_body( $args );

   $encoding and $email->{body} = encode( $encoding, $email->{body} );

   exists $args->{attachments} and $self->_add_attachments( $args, $email );

   return Email::MIME->create( %{ $email } );
}

sub _get_email_body {
   my ($self, $args) = @_; $args ||= {}; my $text;

   exists $args->{body} and defined $args->{body} and return $args->{body};

   $args->{template} or throw 'Message body not specified';

   my $conf  = $args->{template_attrs} || {};

   $conf->{VARIABLES}->{loc} = sub { return $self->loc( @_ ) };

   my $tmplt = Template->new( $conf ) or throw $Template::ERROR;

   $tmplt->process( $args->{template}, $args->{stash}, \$text )
      or throw $tmplt->error();

   delete $conf->{VARIABLES}->{loc};
   return $text;
}

sub _transport_email {
   my ($self, $args) = @_; $args ||= {};

   $args->{email} or throw 'No email object specified';

   my $class = $args->{mailer} || 'SMTP';

   substr $class, 0, 1 eq '+' or $class = "Email::Sender::Transport::${class}";

   ensure_class_loaded( $class );

   my $mailer_args = { %{ $args->{mailer_args} || {} } };

   exists $args->{mailer_host} and $mailer_args->{host} = $args->{mailer_host};

   my $mailer    = $class->new( $mailer_args );
   my $send_args = { from => $args->{from}, to => $args->{to} };
   my $result    = $mailer->send( $args->{email}, $send_args );

   $result->can( 'failure' ) and throw $result->message;
   return $args->{to};
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TraitFor::Email - Role for sending emails

=head1 Version

Describes v0.16.$Rev: 1 $

=head1 Synopsis

   package YourApp::Model::YourModel;

   use CatalystX::Usul::Moose;

   extends qw(CatalystX::Usul::Model);
   with    qw(CatalystX::Usul::TraitFor::Email);

   sub your_method {
      my $self = shift; $recipient = $self->send_email( $args ); return;
   }

=head1 Description

Provides utility methods to the model and program base classes

=head1 Configuration and Environment

Requires the C<loc> method

=head1 Subroutines/Methods

=head2 send_email

   $recipient = $self->send_email( $args );

Sends emails. Returns the recipient address, throws on error. The
C<$args> hash ref uses these keys:

=over 3

=item attachments

A hash ref whose key/value pairs are the attachment name and path
name. Encoding and content type are derived from the file name
extension

=item attributes

A hash ref that is applied to email when it is created. Typical keys are;
I<content_type> and I<charset>

=item body

Text for the body of the email message

=item from

Email address of the sender

=item mailer

Which mailer should be used to send the email. Defaults to I<SMTP>

=item mailer_host

Which host should send the email. Defaults to I<localhost>

=item stash

Hash ref used by the template rendering to supply values for variable
replacement

=item subject

Subject string

=item template

If it exists then the template is rendered and used as the body contents

=item to

Email address of the recipient

=back

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Constants>

=item L<Email::Sender::Transport::SMTP>

=item L<Email::MIME>

=item L<MIME::Types>

=item L<Template>

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
