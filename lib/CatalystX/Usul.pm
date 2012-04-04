# @(#)$Id: Usul.pm 1168 2012-04-04 12:02:28Z pjf $

package CatalystX::Usul;

use strict;
use warnings;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.6.%d', q$Rev: 1168 $ =~ /\d+/gmsx );
use parent qw(CatalystX::Usul::Base CatalystX::Usul::File CatalystX::Usul::Log);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions
    qw(arg_list is_arrayref is_hashref merge_attributes my_prefix);
use CatalystX::Usul::L10N;
use Class::Null;
use File::Spec;
use IPC::SRLock;
use Module::Pluggable::Object;
use MRO::Compat;
use Scalar::Util qw(blessed);

my $ATTRS = { config   => {},       debug    => FALSE,
              encoding => q(UTF-8), log      => Class::Null->new,
              suid     => NUL,      tempdir  => File::Spec->tmpdir, };

__PACKAGE__->mk_accessors( qw(config debug encoding l10n lock
                              log prefix secret suid tempdir) );

__PACKAGE__->mk_log_methods();

sub new {
   my ($self, @rest) = @_; my $class = blessed $self || $self;

   my $new = bless BUILDARGS( q(_arg_list), $class, @rest ), $class;

   $new->build_attributes( [ qw(prefix secret lock l10n) ] );

   return $new;
}

sub BUILDARGS {
   my ($next, $class, $app, @rest) = @_; my $attrs = $class->$next( @rest );

   __merge_attrs( $attrs, $app || {},       [ qw(config debug log)      ] );
   __merge_attrs( $attrs, $attrs->{config}, [ qw(encoding suid tempdir) ] );

   return $attrs;
}

sub build_attributes {
   my ($self, $attrs, $force) = @_;

   for (@{ $attrs || [] }) {
      my $builder = q(_build_).$_;

      ($force or not defined $self->$_) and $self->$_( $self->$builder() );
   }

   return;
}

sub build_subcomponents {
   # Voodo by mst. Finds and loads component subclasses
   my ($self, $base_class) = @_; my $my_class = blessed $self || $self;

   (my $dir = $self->find_source( $base_class )) =~ s{ [.]pm \z }{}msx;

   for my $path (glob $self->catfile( $dir, q(*.pm) )) {
      my $subcomponent = $self->basename( $path, q(.pm) );
      my $component    = join q(::), $my_class,   $subcomponent;
      my $base         = join q(::), $base_class, $subcomponent;

      $self->_load_component( $component, $base );
   }

   return;
}

sub loc {
   my ($self, $params, $key, @rest) = @_; my $car = $rest[ 0 ];

   my $args = (is_hashref $car) ? $car : { params => (is_arrayref $car)
                                                   ? $car : [ @rest ] };

   $args->{domain_names} = [ DEFAULT_L10N_DOMAIN, $params->{ns} ];
   $args->{locale      } = $params->{lang};

   return $self->l10n->localize( $key, $args );
}

sub setup_plugins {
   # Searches for and then loads plugins in the search path
   my ($class, $config) = @_;

   my $child_class = delete $config->{child_class    } || $class;
   my $exclude     = delete $config->{exclude_pattern} || q(\A \z);
   my @paths       = @{ delete $config->{search_paths} || [] };
   my $spath       = [ map { m{ \A :: }msx ? __PACKAGE__.$_ : $_ } @paths ];
   my $finder      = Module::Pluggable::Object->new
                        ( search_path => $spath, %{ $config } );
   my @plugins     = grep { not m{ $exclude }msx }
                     sort { length $a <=> length $b } $finder->plugins;

   $class->_load_component( $child_class, @plugins );

   return \@plugins;
}

sub supports {
   my ($self, @spec) = @_; my $cursor = eval { $self->get_features } || {};

   @spec == 1 and exists $cursor->{ $spec[ 0 ] } and return TRUE;

   # Traverse the feature list
   for (@spec) {
      ref $cursor eq HASH or return FALSE; $cursor = $cursor->{ $_ };
   }

   ref $cursor or return $cursor; ref $cursor eq ARRAY or return FALSE;

   # Check that all the keys required for a feature are in here
   for (@{ $cursor }) { exists $self->{ $_ } or return FALSE }

   return TRUE;
}

# Private methods

sub _arg_list {
   my $self = shift; return arg_list @_;
}

sub _build_l10n {
   my $self = shift;

   my $cfg  = $self->config; my $attrs = arg_list $cfg->{l10n_attrs};

   __merge_attrs( $attrs, $self, [ qw(debug lock log tempdir) ] );

   defined $cfg->{localedir} and $attrs->{localedir} ||= $cfg->{localedir};

   return CatalystX::Usul::L10N->new( $attrs );
}

sub _build_lock {
   # There is only one lock object. Instantiate on first use
   my $self = shift;

   my $lock; $lock = __PACKAGE__->get_inherited( q(lock) ) and return $lock;

   my $attrs = arg_list $self->config->{lock_attrs};

   __merge_attrs( $attrs, $self, [ qw(debug log tempdir) ] );

   return __PACKAGE__->set_inherited( q(lock), IPC::SRLock->new( $attrs ) );
}

sub _build_prefix {
   my $self = shift; return $self->config->{prefix} || my_prefix $self->suid;
}

sub _build_secret {
   my $self = shift; return $self->config->{secret} || $self->prefix;
}

sub _load_component {
   my ($self, $child, @parents) = @_;

   ## no critic
   for my $parent (reverse @parents) {
      $self->ensure_class_loaded( $parent );
      {  no strict q(refs);

         $child eq $parent or $child->isa( $parent )
            or unshift @{ "${child}::ISA" }, $parent;
      }
   }

   exists $Class::C3::MRO{ $child } or eval "package $child; import Class::C3;";
   ## critic
   return;
}

# Private subroutines

sub __merge_attrs {
   return merge_attributes $_[ 0 ], $_[ 1 ], $ATTRS, $_[ 2 ];
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul - A base class for Catalyst MVC components

=head1 Version

This document describes CatalystX::Usul version 0.6.$Revision: 1168 $

=head1 Synopsis

   use parent qw(CatalystX::Usul);

=head1 Description

These modules provide a set of base classes for a Catalyst web
application. Features include:

=over 3

=item Targeted at intranet applications

The identity model supports multiple backend authentication stores
including the underlying operating system accounts

=item Thin controllers

Most controllers make a single call to the model and so comprise of
only a few lines of code. The interface model stashes data used by the
view to render the page

=item No further view programing required

A single L<template tookit|Template::Toolkit> instance is used to
render all pages as either HTML or XHTML. The template forms one
component of the "skin", the other components are: a Javascript file
containing the use cases for the Javascript libraries, a primary CSS
file with support for alternative CSS files, and a set of image files

Designers can create new skins with different layout, presentation and
behaviour for the whole application. They can do this for the example
application, L<Munchies|App::Munchies>, whilst the programmers write the "real"
application in parallel with the designers work

=item Flexable development methodology

These base classes are used by an example application,
L<Munchies|App::Munchies>, which can be deployed to staging and production
servers at the beginning of the project. Setting up the example
application allows issues regarding the software technology to be
resolved whilst the "real" application is being written. The example
application can be deleted leaving these base classes for the "real"
application to use

=back

=head1 Configuration and Environment

Catalyst will set the C<$config> argument passed to the constructor to
the section of the configuration appropriate for the component being
initialised

=head1 Subroutines/Methods

This module provides methods common to
C<controllers|CatalystX::Usul::Controller> and
C<models|CatalystX::Usul::Model> which both inherit from this
class. This means that you should probably inherit from one of them
instead

=head2 new

   $self = CatalystX::Usul->new( $app, $attrs );

Constructor. Inherits from the L<base|CatalystX::Usul::Base> and the
L<encoding|CatalystX::Usul::Encoding> classes. The
L<Catalyst|Catalyst> application context is C<$app> and C<$attrs> is a
hash ref containing the object attributes. Defines the following
attributes:

=over 3

=item config

Hash of attributes read from the config file

=item debug

The application context debug is used to set this. Defaults to false

=item encoding

Which character encoding to use, defaults to C<UTF-8>

=item lock

The lock object. This is readonly and instantiates on first use

=item log

The application context log. Defaults to a L<null|Class::Null> object

=item prefix

The prefix applied to executable programs in the I<bin>
directory. This is extracted from the I<suid> key in the config hash

=item secret

This applications secret key as set by the administrators in the
configuration. It is used to perturb the encryption methods. Defaults to
the I<prefix> attribute value

=item suid

Supplied by the config hash, it is the name of the setuid root
program in the I<bin> directory. Defaults to the null string

=item tempdir

Location of any temporary files created by the application. Defaults
to the L<system|File::Spec> tempdir

=back

=head2 BUILDARGS

Preprocesses the are passed to the constructor

=head2 build_attributes

   $self->build_attributes( [ qw(a list of attributes names) ], $force );

For each attribute in the list, if it is undefined or C<$force> is true,
this method calls the builder method C<_build_attribute_name> and sets the
attribute with the result

=head2 build_subcomponents

   __PACKAGE__->build_subcomponents( $base_class );

Class method that allows us to define components that inherit from the base
class at runtime

=head2 loc

   $local_text = $self->loc( $args, $key, $params );

Localizes the message. Calls L<CatalystX::Usul::L10N/localize>

=head2 setup_plugins

   @plugins = __PACKAGE__->setup_plugins( $config_ref );

Load the given list of plugins and have the supplied class inherit from them.
Returns an array ref of available plugins

=head2 supports

   $bool = $self->supports( @spec );

Returns true if the hash returned by our I<get_features> attribute
contains all the elements of the required specification

=head2 _build_lock

A L<lock|IPC::SRLock> object which is used to single thread the
application where required. This is a singleton object.  Provides
defaults for and returns a new L<set/reset|IPC::SRLock> lock
object. The keys of the C<$attrs> hash are:

=over 3

=item debug

Debug status. Defaults to C<< $self->debug >>

=item log

Logging object. Defaults to C<< $self->log >>

=item tempdir

Directory used to store the lock file and lock table if the C<fcntl> backend
is used. Defaults to C<< $self->tempdir >>

=back

=head2 _load_component

   $self->_load_component( $child, @parents );

Ensures that each component is loaded then fixes @ISA for the child so that
it inherits from the parents

=head1 Diagnostics

Setting the I<debug> attribute to true causes messages to be logged at the
debug level

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Base>

=item L<CatalystX::Usul::Constants>

=item L<CatalystX::Usul::File>

=item L<CatalystX::Usul::Functions>

=item L<CatalystX::Usul::L10N>

=item L<CatalystX::Usul::Log>

=item L<IPC::SRLock>

=item L<Module::Pluggable::Object>

=back

To make the Captchas work L<GD::SecurityImage> needs to be installed which
has a documented dependency on C<libgd> which should be installed first

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

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. See the L<Perl Artistic
License|perlartistic>

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE

=cut

# Local Variables:
# mode: perl
# tab-width: 3
# End:

