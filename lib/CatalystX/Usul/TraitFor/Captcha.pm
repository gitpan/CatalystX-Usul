# @(#)Ident: Captcha.pm 2013-09-29 01:37 pjf ;

package CatalystX::Usul::TraitFor::Captcha;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.16.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Constraints qw( NullLoadingClass );
use CatalystX::Usul::Functions   qw( throw);
use Class::Null;
use English                      qw( -no_match_vars );
use HTTP::Date;
use Moose::Role;
use MooseX::AttributeShortcuts;

requires qw( context );

has 'captcha_class' => is => 'lazy', isa => NullLoadingClass, coerce => TRUE,
   default          => sub { 'GD::SecurityImage' };

sub clear_captcha_string {
   my $self = shift; my $c = $self->context;

   my $cfg  = $c->config->{ __CONFIG_KEY() };

   delete $c->session->{ $cfg->{session_name} || __SESSION_KEY() };
   return;
}

sub create_captcha {
   my $self = shift; my $c = $self->context;

   my $cfg  = $c->config->{ __CONFIG_KEY() };

   $cfg->{create      } ||= [];
   $cfg->{new         } ||= {};
   $cfg->{out         } ||= {};
   $cfg->{particle    } ||= [];
   $cfg->{session_name} ||= __SESSION_KEY();

   my ($image_data, $mime_type, $random_string); $self->captcha_class->import;

   if (my $image = $self->captcha_class->new( %{ $cfg->{new} } )) {
      $image->random  ();
      $image->create  ( @{ $cfg->{create  } } );
      $image->particle( @{ $cfg->{particle} } );

      ($image_data, $mime_type, $random_string)
         = $image->out( %{ $cfg->{out} } );
   }

   $c->session->{ $cfg->{session_name} } = $random_string;

   $c->res->headers->expires( time );
   $c->res->headers->header ( 'Last-Modified' => HTTP::Date::time2str );
   $c->res->headers->header ( 'Pragma'        => 'no-cache' );
   $c->res->headers->header ( 'Cache-Control' => 'no-cache' );
   $c->res->content_type    ( 'image/'.($mime_type || q(png) ) );
   $c->res->output          ( $image_data || NUL );
   return;
}

sub validate_captcha {
   my ($self, $supplied) = @_; my $c = $self->context;

   my $cfg    = $c->config->{ __CONFIG_KEY() };
   my $stored = $c->session->{ $cfg->{session_name} || __SESSION_KEY() };

   ($supplied and $stored and $supplied eq $stored)
      or throw error => 'Security code [_1] incorrect', args => [ $supplied ];

   return;
}

# Private functions

sub __CONFIG_KEY () {
   return q(Plugin::Captcha);
}

sub __SESSION_KEY () {
   return q(captcha_string);
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::TraitFor::Captcha - Role to implement captchas

=head1 Version

Describes v0.16.$Rev: 1 $

=head1 Synopsis

   use CatalystX::Usul::Moose;

   extends qw(CatalystX::Usul::Model);
   with    qw(CatalystX::Usul::TraitFor::Captcha);

   sub create_captcha {
      return shift->context->create_captcha;
   }

=head1 Description

Implements create and validate methods for captchas

=head1 Configuration and Environment

Requires the I<context> attribute. Uses the key I<Plugin::Captcha> in
the C<< $context->config >> hash

=head1 Subroutines/Methods

=head2 clear_captcha_string

   $self->clear_captcha_string;

Deletes I<captcha_string> from the session

=head2 create_captcha

   $self->create_captcha

Generates the captcha image and sets the response body and headers. Stores
the captcha string on the session

=head2 validate_captcha

   $self->validate_captcha( $string_to_verify );

Verifies that the supplied string matches the one stored on the session.
Returns if it does, throws an exception if it does not

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul::Constraints>

=item L<GD::SecurityImage>

Depends on C<libgd2-noxpm> and C<libgd2-noxpm-dev>

=item L<HTTP::Date>

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
