# @(#)$Id: Captcha.pm 1165 2012-04-03 10:40:39Z pjf $

package CatalystX::Usul::Captcha;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1165 $ =~ /\d+/gmx );

use English qw(-no_match_vars);
use Class::Null;
use HTTP::Date;

eval { require GD::SecurityImage; GD::SecurityImage->import; };

my $captcha_class = $EVAL_ERROR ? q(Class::Null) : q(GD::SecurityImage);

sub clear_captcha_string {
   my $self = shift; my $c = $self->context;

   my $cfg  = $c->config->{ 'Plugin::Captcha' };

   delete $c->session->{ $cfg->{session_name} || q(captcha_string) };
   return 1;
}

sub create_captcha {
   my $self = shift; my $c = $self->context;

   my $cfg  = $c->config->{ 'Plugin::Captcha' };

   $cfg->{create      } ||= [];
   $cfg->{new         } ||= {};
   $cfg->{out         } ||= {};
   $cfg->{particle    } ||= [];
   $cfg->{session_name} ||= q(captcha_string);

   my $image = $captcha_class->new( %{ $cfg->{new} } );

   $image->random  ();
   $image->create  ( @{ $cfg->{create  } } );
   $image->particle( @{ $cfg->{particle} } );

   my ($image_data, $mime_type, $random_string)
      = $image->out( %{ $cfg->{out} } );

   $c->session->{ $cfg->{session_name} } = $random_string;

   $c->res->headers->expires( time );
   $c->res->headers->header ( 'Last-Modified' => HTTP::Date::time2str );
   $c->res->headers->header ( 'Pragma'        => 'no-cache' );
   $c->res->headers->header ( 'Cache-Control' => 'no-cache' );
   $c->res->content_type    ( 'image/'.($mime_type || q(png) ) );
   $c->res->output          ( $image_data );
   return;
}

sub validate_captcha {
   my ($self, $verify) = @_; my $c = $self->context;

   my $cfg    = $c->config->{ 'Plugin::Captcha' };
   my $string = $c->session->{ $cfg->{session_name} || q(captcha_string) };

   return $verify and $string and $verify eq $string;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Captcha - Role to implement captchas

=head1 Version

0.6.$Revision: 1165 $

=head1 Synopsis

   use parent qw(CatalystX::Usul::Model CatalystX::Usul::Captcha);

   sub create_captcha {
      return shift->context->create_captcha;
   }

=head1 Description

Implements create and validate methods for captchas

=head1 Subroutines/Methods

=head2 clear_captcha_string

=head2 create_captcha

=head2 validate_captcha

=head1 Configuration and Environment

Uses the key C<Plugin::Captcha> in the C<$c->config> hash

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<GD::SecurityImage>

Depends on C<libgd2-noxpm> and C<libgd2-noxpm-dev>

=item L<HTTP::Date>

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

Copyright (c) 2011 Peter Flanigan. All rights reserved

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
