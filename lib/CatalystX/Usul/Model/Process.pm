package CatalystX::Usul::Model::Process;

# @(#)$Id: Process.pm 402 2009-03-28 03:09:07Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Model);
use CatalystX::Usul::Process;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 402 $ =~ /\d+/gmx );

__PACKAGE__->config( fs_class   => q(FileSystem),
                     user_class => q(IdentityUnix) );

__PACKAGE__->mk_accessors( qw(fs_class fs_model processes user_class
                              user_model) );

my $NUL = q();

sub build_per_context_instance {
   my ($self, $c, @rest) = @_;

   my $new = $self->next::method( $c, @rest );

   $new->processes ( CatalystX::Usul::Process->new( $c )   );
   $new->fs_model  ( $c->model( $self->fs_class )          );
   $new->user_model( $c->model( $self->user_class )->users );

   return $new;
}

sub proc_table_form {
   my ($self, $ptype, $user, $fsystem, $signals) = @_;

   my ($data, $e, $fss, $res, $text, $users);

   my $pattern = $self->query_value( q(pattern) );
   my $form    = $self->context->stash->{form}->{name};

   # Retrieve data from model
   eval {
      my $ref = { pattern => [ $NUL, $NUL, $pattern, $NUL ] };

      $data = $self->processes->get_table( $ptype, $user, $fsystem, $ref );

      if ($ptype == 1) {
         $res   = $self->user_model->retrieve( q([^\?]+), $NUL );
         $users = $res->user_list; unshift @{ $users }, $NUL, q(All);
      }

      if ($ptype == 3) {
         $res = $self->fs_model->get_file_systems( $fsystem );
         $fss = $res->file_systems; unshift @{ $fss }, $NUL;
      }
   };

   return $self->add_error( $e ) if ($e = $self->catch);

   # Add HTML elements items to form
   $self->clear_form( { firstfld => q(ptype) } );

   if ($data->count) {
      $self->add_field( { data   => $data,
                          select => q(left), type => q(table) } );
   }
   else {
      if ($ptype == 1 || $ptype == 2) {
         if ($user eq q(All)) {
            $text = 'There are no killable processes for any user';
         }
         else { $text = "There are no killable processes for the user $user" }
      }
      else { $text = 'There are no processes on this filesystem' }

      $self->add_field( { text   => $text, type => q(note) } );
   }

   $self->group_fields( { id     => $form.q(.select), nitems => 1 } );

   # Add buttons to form
   $self->add_buttons( qw(Terminate Kill Abort) );

   # Add controls to append div
   $self->add_append( { default  => $ptype,
                        labels   => { 1 => 'All processes',
                                      2 => 'Specific Processes',
                                      3 => 'Processes by filesystem' },
                        name     => q(ptype),
                        prompt   => 'Display&nbsp;type',
                        onchange => 'submit()',
                        pwidth   => 10,
                        sep      => q(&nbsp;),
                        type     => q(popupMenu),
                        values   => [ $NUL, qw(1 2 3) ] } );

   if ($ptype) {
      if ($ptype == 1) {
         $self->add_append( { default   => $user,
                              name      => q(user),
                              onchange  => 'submit()',
                              prompt    => 'Show&nbsp;users',
                              pwidth    => 10,
                              sep       => q(&nbsp;),
                              type      => q(popupMenu),
                              values    => $users } );
         $self->add_hidden( q(pattern), $pattern );
         $self->add_hidden( q(fsystem), $fsystem );
      }
      elsif ($ptype == 2) {
         $self->add_append( { default   => $pattern,
                              maxlength => 64,
                              name      => q(pattern),
                              onblur    => 'submit()',
                              prompt    => 'Pattern',
                              pwidth    => 10,
                              sep       => q(&nbsp;),
                              type      => q(textfield),
                              width     => 15 } );
         $self->add_hidden( q(fsystem), $fsystem );
         $self->add_hidden( q(user), $user );
      }
      elsif ($ptype == 3) {
         $self->add_append( { default   => $fsystem,
                              name      => q(fsystem),
                              onchange  => 'submit()',
                              prompt    => 'Filesystem',
                              pwidth    => 10,
                              sep       => q(&nbsp;),
                              type      => q(popupMenu),
                              values    => $fss } );
         $self->add_hidden( q(pattern), $pattern );
         $self->add_hidden( q(user), $user );
      }
   }

   $self->add_append( { default => $signals,
                        labels  => { 1 => 'Process only',
                                     2 => 'Process and children' },
                        name    => q(signals),
                        prompt  => 'Propagation',
                        pwidth  => 10,
                        sep     => q(&nbsp;),
                        type    => q(popupMenu),
                        values  => [ $NUL, 1, 2 ] } );
   return;
}

sub signal_process {
   my $self = shift; my $pids = []; my ($nrows, $pid);

   unless ($nrows = $self->query_value( q(table_nrows) )) {
      $self->throw( q(eNoProcesses) );
   }

   for my $row (0 .. $nrows) {
      if ($pid = $self->query_value( q(table_select).$row )) {
         push @{ $pids }, $pid;
      }
   }

   $self->throw( q(eNoProcesses) ) unless ($pids->[0]);

   my $ref  = { Abort => q(ABRT), Kill => q(KILL), Terminate => q(TERM) };
   my $sig  = $ref->{ $self->context->stash->{_method} || q(Terminate) };
   my $flag = $self->query_value( q(signals) ) eq q(1) ? 1 : 0;
   my $res  = $self->processes->signal_process( $flag, $sig, $pids );

   $self->add_result( $res );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Process - View and signal processes

=head1 Version

0.1.$Revision: 402 $

=head1 Synopsis

   package MyApp;

   use Catalyst qw(ConfigComponents);

   # In the application configuration file
   <component name="Model::Process">
      <base_class>CatalystX::Usul::Model::Process</base_class>
   </component>

=head1 Description

Displays the process table and allows signals to be sent to selected
processes

=head1 Subroutines/Methods

=head2 build_per_context_instance

Copies the file system model and user model instances. Creates an instance
of L<CatalystX::Usul::Process>

=head2 proc_table_form

Stuffs the stash with the data for the process table screen

=head2 signal_process

Send a signal the the selected processes

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<Proc::ProcessTable>

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
