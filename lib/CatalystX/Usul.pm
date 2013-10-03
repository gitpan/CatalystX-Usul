# @(#)$Ident: Usul.pm 2013-09-03 12:49 pjf ;

package CatalystX::Usul;

use 5.010001;
use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.13.%d', q$Rev: 1 $ =~ /\d+/gmx );

1;

__END__

=pod

=head1 Name

CatalystX::Usul - A base class for Catalyst MVC components

=head1 Version

This document describes CatalystX::Usul version v0.13.$Rev: 1 $

=head1 Synopsis

   package MyApp::Controller;

   use Moose;

   BEGIN { extends qw(CatalystX::Usul::Controller) }


   package MyApp::Model;

   use Moose;

   extends qw(CatalystX::Usul::Model);


=head1 Description

These modules provide a set of extension base classes for a Catalyst web
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

A single L<template toolkit|Template::Toolkit> instance is used to
render all pages as either HTML or XHTML. The template forms one
component of the "skin", the other components are: a Javascript file
containing the use cases for the Javascript libraries, a primary CSS
file with support for alternative CSS files, and a set of image files

Designers can create new skins with different layout, presentation and
behaviour for the whole application. They can do this for the example
application, L<Munchies|App::Munchies>, whilst the programmers write the "real"
application in parallel with the designers work

=item Flexible development methodology

These base classes are used by an example application,
L<Munchies|App::Munchies>, which can be deployed to staging and production
servers at the beginning of the project. Setting up the example
application allows issues regarding the software technology to be
resolved whilst the "real" application is being written. The example
application can be deleted leaving these base classes for the "real"
application to use

=back

=head1 Subroutines/Methods

This package is a placeholder for POD and contains no methods or
functions

=head1 Configuration and Environment

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul>

=back

To make the Captchas work L<GD::SecurityImage> needs to be installed which
has a documented dependency on C<libgd> which should be installed first

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

=head1 Author

Peter Flanigan, C<< <pjfl@cpan.org> >>

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

