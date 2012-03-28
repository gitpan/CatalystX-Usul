# @(#)$Id: L10N.pm 1139 2012-03-28 23:49:18Z pjf $

package CatalystX::Usul::L10N;

use strict;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.5.%d', q$Rev: 1139 $ =~ /\d+/gmx );

use Moose;
use Class::Null;
use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(assert is_arrayref);
use File::DataClass::Constraints;
use File::Gettext::Constants;
use File::Gettext;
use File::Spec;
use TryCatch;

has 'debug'             => is => 'ro', isa => 'Bool',
   default              => FALSE;

has 'domain_attributes' => is => 'ro', isa => 'HashRef',
   default              => sub { {} };

has 'domain_names'      => is => 'ro', isa => 'ArrayRef[Str]',
   default              => sub { [ q(messages) ] };

has 'localedir'         => is => 'ro', isa => 'F_DC_Path',
   default              => sub { DIRECTORIES->[ 0 ] }, coerce => TRUE;

has 'lock'              => is => 'ro', isa => 'F_DC_Lock',
   default              => sub { Class::Null->new };

has 'log'               => is => 'ro', isa => 'Object',
   default              => sub { Class::Null->new };

has 'tempdir'           => is => 'ro', isa => 'F_DC_Directory',
   default              => File::Spec->tmpdir, coerce => TRUE;

has 'use_country'       => is => 'ro', isa => 'Bool',
   default              => FALSE;

sub BUILD {
   my $self = shift; my $da = $self->domain_attributes;

   $da->{localedir} ||= $self->localedir; $da->{source_name} ||= q(po);

   return;
}

sub get_po_header {
   my ($self, $args) = @_;
   my $domain        = $self->_load_domains( $args || {} ) or return {};
   my $header        = $domain->{po_header} or return {};

   return $header->{msgstr} || {};
}

sub localize {
   my ($self, $key, $args) = @_;

   $key or return; $key = NUL.$key; chomp $key; $args ||= {};

   # Lookup the message using the supplied key from the po file
   my $text = $self->_gettext( $key, $args );

   if (is_arrayref $args->{params}) {
      0 > index $text, LOCALIZE and return $text;

      # Expand positional parameters of the form [_<n>]
      my @args = @{ $args->{params} }; push @args, map { '[?]' } 0 .. 10;

      $text =~ s{ \[ _ (\d+) \] }{$args[ $1 - 1 ]}gmx; return $text;
   }

   0 > index $text, LBRACE and return $text;

   # Expand named parameters of the form {param_name}
   my %args = %{ $args }; my $re = join q(|), map { quotemeta $_ } keys %args;

   $text =~ s{ \{($re)\} }{ defined $args{ $1 } ? $args{ $1 } : "{$1}" }egmx;
   return $text;
}

# Private methods

{  my $cache = {};

   sub _extract_lang_from {
      my ($self, $locale) = @_;

      defined $cache->{ $locale } and return $cache->{ $locale };

      my $sep  = $self->use_country ? q(.) : q(_);
      my $lang = (split m{ \Q$sep\E }msx, $locale.$sep )[ 0 ];

      return $cache->{ $locale } = $lang;
   }
}

sub _gettext {
   my ($self, $key, $args) = @_;

   my $count   = $args->{count} || 1;
   my $default = $args->{no_default} ? NUL : $key;
   my $domain  = $self->_load_domains( $args )
      or return ($key, $args->{plural_key})[ $count > 1 ] || $default;
   # Select either singular or plural translation
   my ($nplurals, $plural) = $domain->{plural_func}->( $count );

   defined     $nplurals or $nplurals = 0;
   defined      $plural  or  $plural  = 0;
   $nplurals <= $plural and  $plural  = 0;

   my $id   = defined $args->{context}
            ? $args->{context}.CONTEXT_SEP.$key : $key;
   my $msgs = $domain->{ $self->domain_attributes->{source_name} } || {};
   my $msg  = $msgs->{ $id } || {};

   return @{ $msg->{msgstr} || [] }[ $plural ] || $default;
}

{  my $cache = {};

   sub _load_domains {
      my ($self, $args) = @_; my ($charset, $data);

      assert $self, sub { $args->{locale} }, 'No locale id';

      my $locale = $args->{locale} or return;
      my $lang   = $self->_extract_lang_from( $locale );
      my $names  = $args->{domain_names} || $self->domain_names;
      my @names  = grep { defined and length } @{ $names };
      my $key    = $lang.SEP.(join q(+), @names );

      defined $cache->{ $key } and return $cache->{ $key };

      my $attrs  = { %{ $self->domain_attributes }, ioc_obj => $self };

      $locale    =~ m{ \A (?: [a-z][a-z] )
                          (?: (?:_[A-Z][A-Z] )? \. ( [-_A-Za-z0-9]+ )? )?
                          (?: \@[-_A-Za-z0-9=;]+ )? \z }msx and $charset = $1;
      $charset and $attrs->{charset} = $charset;

      try        { $data = File::Gettext->new( $attrs )->load( $lang, @names ) }
      catch ($e) { $self->log->error( $e ); return }

      return $cache->{ $key } = $data;
   }
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::L10N - Localize text strings

=head1 Version

0.5.$Revision: 1139 $

=head1 Synopsis

   use CatalystX::Usul::L10N;

   my $l10n = CatalystX::Usul::L10N->new( {
      debug        => $c->debug,
      log          => $c->log,
      tempdir      => File::Spec->tmpdir } );

   $local_text = $l10n->localize( $key, {
      domain_names => [ 'default', $c->action->namespace ],
      locale       => q(de_DE),
      params       => { name => 'value', }, } );

=head1 Description

Localize text strings

=head1 Configuration and Environment

A POSIX locale id has the form

   <language>_<country>.<charset>@<key>=<value>;...

If the I<use_country> attribute is set to true in the constructor call
then the language and country are used from I<locale>. By default
I<use_country> is false and only the language from the I<locale>
attribute is used

=head1 Subroutines/Methods

=head2 BUILD

Finish initializing the object

=head2 get_po_header

   $po_header_hash_ref = $l10n->get_po_header( { locale => q(de) } );

Returns a hash ref containing the keys and values of the PO header record

=head2 localize

   $local_text = $l10n->localize( $key, $args );

Localizes the message. The message catalog is loaded from a GNU
Gettext portable object file. Returns the C<$key> if the message is
not in the catalog. Language is selected by the C<< $args->{locale} >>
attribute. Expands positional parameters of the form C<< [_<n>] >> if
C<< $args->{params} >> is an array ref of values to substitute. Otherwise
expands named attributes of the form C<< {attr_name} >> using the C<$args>
hash for substitution values. The attribute C<< $args->{count} >> is passed
to the machine object files plural function which is used to select either
the singular or plural form of the translation. If C<< $args->{context} >>
is supplied it is prepended to the C<$key> before the lookup in the catalog
takes place

=head1 Diagnostics

Asserts that the I<locale> attribute is set

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Constants>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Author

Peter Flanigan, C<< <Support at RoxSoft.co.uk> >>

=head1 Acknowledgements

Larry Wall - For the Perl programming language

=head1 License and Copyright

Copyright (c) 2012 Peter Flanigan. All rights reserved

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

