# @(#)Ident: ;

package CatalystX::Usul::Users;

use strict;
use version; our $VERSION = qv( sprintf '0.9.%d', q$Rev: 0 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Constraints qw( Directory Path );
use CatalystX::Usul::Functions   qw( create_token exception is_arrayref
                                     is_hashref is_member throw );
use CatalystX::Usul::Moose;
use CatalystX::Usul::Response::Users;
use Class::Usul::File;
use Class::Usul::IPC;
use Crypt::Eksblowfish::Bcrypt   qw( bcrypt en_base64 );
use File::Spec::Functions        qw( catdir catfile );
use TryCatch;

with q(Class::Usul::TraitFor::LoadingClasses);
with q(CatalystX::Usul::TraitFor::Email);

has 'alias_class'       => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default              => sub { 'File::MailAlias' };

has 'aliases_path'      => is => 'lazy', isa => Path, coerce => TRUE,
   default              => sub { [ $_[ 0 ]->config->ctrldir, 'aliases' ] };

has 'aliases'           => is => 'lazy', isa => Object;

has 'cache'             => is => 'ro',   isa => HashRef, default => sub { {} };

has 'def_passwd'        => is => 'ro',   isa => NonEmptySimpleStr,
   default              => '*DISABLED*';

has 'language'          => is => 'ro',   isa => NonEmptySimpleStr,
   default              => LANG;

has 'load_factor'       => is => 'ro',   isa => PositiveInt, default => 14;

has 'max_login_trys'    => is => 'ro',   isa => PositiveOrZeroInt, default => 3;

has 'max_pass_hist'     => is => 'ro',   isa => PositiveOrZeroInt,
   default              => 10;

has 'max_sess_time'     => is => 'ro',   isa => PositiveInt,
   default              => MAX_SESSION_TIME;

has 'min_name_len'      => is => 'ro',   isa => PositiveInt, default => 6;

has 'passwd_type'       => is => 'ro',   isa => NonEmptySimpleStr,
   default              => 'Blowfish';

has 'profile_class'     => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default              => sub { 'CatalystX::Usul::UserProfiles' };

has 'profiles'          => is => 'lazy', isa => Object;

has 'register_queue_path' => is => 'lazy', isa => Path, coerce => TRUE;

# Not LoadableClass. Must be loaded when session plugin thaws the user object
has 'response_class'    => is => 'ro',   isa => ClassName,
   default              => 'CatalystX::Usul::Response::Users';

has 'role_cache'        => is => 'ro',   isa => HashRef, default => sub { {} };

has 'role_class'        => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default              => sub { 'Class::Null' };

has 'roles'             => is => 'lazy', isa => Object, init_arg => undef;

has 'sess_updt_period'  => is => 'ro',   isa => PositiveInt, default => 300;

has 'sessdir'           => is => 'lazy', isa => Directory, coerce => TRUE,
   default              => sub { $_[ 0 ]->config->sessdir };

has 'shells_attributes' => is => 'ro',   isa => HashRef, default => sub { {} };

has 'shells_class'      => is => 'lazy', isa => LoadableClass, coerce => TRUE,
   default              => sub { 'CatalystX::Usul::Shells' };

has '_shells'           => is => 'lazy', isa => Object, init_arg => undef,
   reader               => 'shells';

has 'user_pattern'      => is => 'ro',   isa => NonEmptySimpleStr,
   default              => '\A [a-zA-Z0-9]+';

has 'userid_len'        => is => 'ro',   isa => PositiveInt, default => 3;


has '_file' => is => 'lazy', isa => FileClass,
   default  => sub { Class::Usul::File->new( builder => $_[ 0 ]->usul ) },
   handles  => [ qw(io) ], init_arg => undef, reader => 'file';

has '_ipc'  => is => 'lazy', isa => IPCClass,
   default  => sub { Class::Usul::IPC->new( builder => $_[ 0 ]->usul ) },
   handles  => [ qw(run_cmd) ], init_arg => undef, reader => 'ipc';

has '_usul' => is => 'ro',   isa => BaseClass,
   handles  => [ qw(config debug lock log) ], init_arg => 'builder',
   reader   => 'usul', required => TRUE, weak_ref => TRUE;

# Object methods
sub activate_account { # Override in subclass to support feature
   throw error => 'Class [_1] account activation not supported',
         args  => [ blessed $_[ 0 ] ];
}

sub authenticate {
   my ($self, $username, $passwd) = @_;

   my $user = $self->_assert_user( $username, FALSE );

   $user->active or throw error => 'User [_1] account inactive',
                          args  => [ $username ], class => 'AccountInactive';

   if ($passwd eq q(stdin)) {
      $passwd = <STDIN>; $passwd ||= NUL; chomp $passwd;
   }

   my $stored   = $user->crypted_password || NUL;
   my $supplied = $self->_encrypt_password( $passwd, $stored );
   my $path     = $self->io( [ $self->sessdir, $username ] );

   $self->lock->set( k => $path );

   if ($supplied ne $stored) { # User has failed to authenticate
      $self->_count_login_attempt( $username, $path );
      $self->lock->reset( k => $path );
      throw error => 'User [_1] incorrect password for class [_2]',
            args  => [ $username, blessed $self ], class => 'IncorrectPassword';
   }

   $path->is_file and $path->unlink; $self->lock->reset( k => $path );

   return $user;
}

sub change_password {
   return shift->update_password( FALSE, @_ );
}

sub dequeue_activation_file {
   my ($self, $file) = @_; my $path = $self->io( [ $self->sessdir, $file ] );

   $path->is_file or throw error => 'Path [_1] not found', args => [ $path ];

   my $username = $path->chomp->lock->getline
      or throw error => 'Path [_1] contained no data', args => [ $path ];

   $path->unlink; return $username;
}

sub disable_account {
   return $_[ 0 ]->update_password( TRUE, $_[ 1 ], NUL, q(*DISABLED*), TRUE );
}

sub encrypt_password {
   my ($self, $force, $username, $old_pass, $new_pass, $encrypted) = @_;

   unless ($force) {
      my $user = $self->authenticate( $username, $old_pass );

      if ((my $days = $user->when_can_change_password) > 0) {
         throw error => 'User [_1] cannot change password for [_2] days',
               args  => [ $username, $days ];
      }
   }

   my $history   = substr create_token( "${username}_history" ), 0, 32;
   my $io        = $self->io( [ $self->sessdir, $history ] )->chomp->lock;
   my @passwords = ();
   my $enc_pass;

   if ($encrypted) { $enc_pass = $new_pass }
   else {
      if (not $force and $io->is_file and @passwords = $io->getlines) {
         for my $used_pass (@passwords) {
            $enc_pass = $self->_encrypt_password( $new_pass, $used_pass );
            $enc_pass eq $used_pass and throw 'Password used before';
         }
      }

      $enc_pass = $self->_encrypt_password( $new_pass );
   }

   unless ($force) {
      push @passwords, $enc_pass;
      shift @passwords while ($#passwords > $self->max_pass_hist);
      $io->println( @passwords );
   }

   return $enc_pass;
}

sub find_user {
   my ($self, $username, $verbose) = @_;

   my $user = $self->get_user( $username, $verbose );

   $user->username ne q(unknown) and $self->supports( q(roles) )
      and $user->roles( [ $self->roles->get_roles( $username, $user->pgid ) ] );

   return $user;
}

sub get_new_user_id {
   my ($self, $first_name, $last_name, $prefix) = @_; $prefix //= NUL;

   my $name = (lc $last_name).(lc $first_name); $name =~ s{ [ \-\'] }{}gmx;

   if ((length $name) < $self->min_name_len) {
      throw error => 'User name [_1] too short [_2] character min.',
            args  => [ $first_name.SPC.$last_name, $self->min_name_len ];
   }

   my $name_len = $self->userid_len;
   my $lastp    = length $name < $name_len ? length $name : $name_len;
   my @chars    = (); $chars[ $_ ] = $_ for (0 .. $lastp - 1);
   my $lid;

   while ($chars[ $lastp - 1 ] < length $name) {
      my $i = 0; $lid = NUL;

      while ($i < $lastp) { $lid .= substr $name, $chars[ $i++ ], 1 }

      $self->is_user( $prefix.$lid ) or last;

      $i = $lastp - 1; $chars[ $i ] += 1;

      while ($i >= 0 and $chars[ $i ] >= length $name) {
         my $ripple = $i - 1; $chars[ $ripple ] += 1;

         while ($ripple < $lastp) {
            my $carry = $ripple + 1; $chars[ $carry ] = $chars[ $ripple++ ] + 1;
         }

         $i--;
      }
   }

   $chars[ $lastp - 1 ] >= length $name
      and throw error => 'User name [_1] no ids left',
                args  => [ $first_name.SPC.$last_name ];

   $lid or throw error => 'User name [_1] no user id', args => [ $name ];

   return $prefix.$lid;
}

sub get_primary_rid {
   return;
}

sub get_security_data { # For the admin security form
   my ($self, $username, $passwd_type) = @_;

   my $user    = $self->find_user( $username, TRUE );
   my @roles   = $username ? @{ $user->roles } : ();
   my $profile = $roles[ 0 ] ? $self->profiles->find( $roles[ 0 ] ) : FALSE;
   my $sec_ref = {};

   $sec_ref->{users    } = [ NUL, @{ $self->list } ];
   $sec_ref->{all_roles} = [ grep { not is_member $_, @roles }
                             $self->roles->get_roles( q(all) ) ];

   $user->pgid and shift @roles;

   $sec_ref->{roles    } = \@roles;
   $sec_ref->{fullname } = $user->fullname;
   $sec_ref->{passwd   } = $profile ? $profile->passwd : NUL;
   $sec_ref->{generated} = $self->_generate_password;

   for my $i (1 .. 4) {
      $sec_ref->{prompts}->[ $i - 1 ] = {
         container_class => q(step_number),
         labels          => { $i => undef },
         name            => q(p_type),
         type            => q(radioGroup),
         values          => [ $i ] };
      $passwd_type == $i and $sec_ref->{prompts}->[ $i - 1 ]->{default} = $i;
   }

   return $sec_ref;
}

sub get_user {
   my ($self, $username, $verbose) = @_; my $class = $self->response_class;

   my $uref = $self->_get_user_ref( $username );

   $uref->{max_sess_time   } ||= $self->max_sess_time;
   $uref->{sess_updt_period} ||= $self->sess_updt_period;

   return $class->new( builder => $self, user_data => $uref || {},
                       verbose => $verbose );
}

sub get_user_data { # For the admin user management form
   my ($self, $options, $username) = @_;

   my $auto_fill   = $options->{fill};
   my $new_tag     = $options->{newtag};
   my $user_params = $options->{user_params} || {};

   my $uref        = {}; $uref->{profile_name} = $user_params->{profile};
   my $profile_obj = $self->profiles->list( $uref->{profile_name} );
   my $profile     = $profile_obj->result;

   $uref->{common_home} = $profile->common_home;
   $uref->{homedir    } = $profile->homedir;
   $uref->{project    } = $profile->project;
   $uref->{labels     } = $profile_obj->labels;
   $uref->{profiles   } = [ NUL, @{ $profile_obj->list } ];
   $uref->{users      } = [ NUL, $new_tag, @{ $self->list } ];

   if ($self->supports( qw(fields shells) )) {
      my $shells_obj = $self->shells;

      $uref->{shells  }   = $shells_obj->shells;
      $uref->{shell   }   = $profile->shell || $shells_obj->default;
      $uref->{supports} ||= {}; $uref->{supports}->{fields_shells} = TRUE;
   }

   $username or return $uref;

   if ($username eq $new_tag and $auto_fill) {
      my $first = $uref->{first_name} = $auto_fill->{first_name};
      my $last  = $uref->{last_name } = $auto_fill->{last_name};

      $uref->{name} = $self->get_new_user_id( $first, $last, $profile->prefix );
      $uref->{email_address}
         = $self->aliases->email_address( "${first}.${last}" );

      if ($self->supports( qw(fields homedir) )) {
         $uref->{supports} ||= {}; $uref->{supports}->{fields_homedir} = TRUE;
         $uref->{name} and $profile->homedir ne $profile->common_home and
            $uref->{homedir} = catdir( NUL.$uref->{homedir}, $uref->{name} );
      }
   }
   elsif ($username ne $new_tag and lc $username ne q(all)) {
      my $user = $self->find_user( $username, TRUE );

      $uref->{email_address} = $user->email_address;
      $uref->{first_name   } = $user->first_name;
      $uref->{last_name    } = $user->last_name;
      $uref->{name         } = $user->username;

      $uref->{home_phone   } = $user->home_phone;
      $uref->{location     } = $user->location;
      $uref->{project      } = $user->project;
      $uref->{role         } = shift @{ $user->roles };
      $uref->{shell        } = $user->shell;
      $uref->{work_phone   } = $user->work_phone;

      if ($self->supports( qw(fields homedir) )) {
         $uref->{supports} ||= {}; $uref->{supports}->{fields_homedir} = TRUE;
         $uref->{homedir } = NUL.$user->homedir;
      }
   }

   return $uref;
}

sub get_users_by_rid {
   return ();
}

sub invalidate_cache {
   $_[ 0 ]->cache->{_dirty} = $_[ 0 ]->role_cache->{_dirty} = TRUE; return;
}

sub invalidate_user_cache {
   $_[ 0 ]->cache->{_dirty} = TRUE; return;
}

sub is_user {
   return $_[ 1 ] && $_[ 0 ]->_get_user_ref( $_[ 1 ] ) ? TRUE : FALSE;
}

sub list {
   my ($self, $pattern) = @_; my (%found, @users);

   $pattern //= $self->user_pattern;

   push @users, map  {     $found{ $_ } = TRUE; $_ }
                grep { not $found{ $_ } and $_ =~ m{ $pattern }mx }
                sort keys %{ ($self->_load)[ 0 ] };

   return \@users;
}

sub loc {
   my ($self, $key, @args) = @_; my $car = $args[ 0 ];

   my $args = (is_hashref $car) ? { %{ $car } }
            : { params => (is_arrayref $car) ? $car : [ @args ] };

   $args->{domain_names} ||= [ DEFAULT_L10N_DOMAIN ];
   $args->{locale      } ||= $self->language;

   return $self->usul->localize( $key, $args );
}

sub register {
   my ($self, $args, $fields) = @_; my $msg = [];

   $self->lock->set( k => q(register_user) );

   try {
      $args->{path} and $fields = $self->_register_dequeue( $args->{path} );
      $fields->{pwlast} = int time / 86_400;
      $msg->[ 0 ] = [ $self->create( $fields ) ];
      $msg->[ 1 ] = [ $self->_register_verification_email( $args, $fields ) ];
   }
   catch ($e) { $self->lock->reset( k => q(register_user) ); throw $e }

   $self->lock->reset( k => q(register_user) );
   return $msg;
}

sub register_authorisation {
   my ($self, $fields) = @_; my $path;

   $self->lock->set( k => q(register_user) );

   try {
      $path = $self->_register_enqueue( $fields );
      # TODO: Add email message to authorising authority passing in $path
   }
   catch ($e) { $self->lock->reset( k => q(register_user) ); throw $e }

   $self->lock->reset( k => q(register_user) );

   my $msg = 'User [_1] awaiting authorisation in [_2]';

   return ($msg, $fields->{email_address}, $path);
}

sub set_password {
   my ($self, $username, @rest) = @_;

   return $self->update_password( TRUE, $username, NUL, @rest );
}

sub supports {
   my ($self, @spec) = @_; my $cursor = $self->get_features;

   @spec == 1 and exists $cursor->{ $spec[ 0 ] } and return TRUE;

   # Traverse the feature list
   for (@spec) {
      is_hashref $cursor or return FALSE; $cursor = $cursor->{ $_ };
   }

   ref $cursor or return $cursor; is_arrayref $cursor or return FALSE;

   # Check that all the keys required for a feature are in here
   for (@{ $cursor }) { exists $self->{ $_ } or return FALSE }

   return TRUE;
}

sub user_attributes {
   return CatalystX::Usul::Response::Users->_attribute_list;
}

sub validate_password {
   my ($self, @rest) = @_;

   try        { $self->authenticate( @rest ) }
   catch ($e) { $self->log->warn( exception $e ); return FALSE }

   return TRUE;
}

# Private methods
sub _assert_user {
   my ($self, $username, $verbose) = @_;

   $username or throw 'User not specified';

   my $user = $self->get_user( $username, $verbose );

   $user->username eq q(unknown)
      and throw error => 'User [_1] unknown', args => [ $username ];

   return $user;
}

sub _build_aliases {
   return $_[ 0 ]->alias_class->new( { builder => $_[ 0 ]->usul,
                                       path    => $_[ 0 ]->aliases_path } );
}

sub _build_profiles {
   return $_[ 0 ]->profile_class->new( builder => $_[ 0 ]->usul );
}

sub _build_register_queue_path {
   return catfile( $_[ 0 ]->sessdir, q(register_queue) );
}

sub _build_roles {
   return $_[ 0 ]->role_class->new( builder => $_[ 0 ]->usul,
                                    cache   => $_[ 0 ]->role_cache,
                                    users   => $_[ 0 ] );
}

sub _build__shells {
   return $_[ 0 ]->shells_class->new( $_[ 0 ]->shells_attributes );
}

sub _cache_results {
   my ($self, $key) = @_; my $cache = { %{ $self->cache } };

   $self->lock->reset( k => $key );

   return ($cache->{users}, $cache->{rid2users}, $cache->{uid2name});
}

sub _count_login_attempt {
   my ($self, $user, $path) = @_;

   my $n_trys = $path->exists ? $path->chomp->getline || 0 : 0;

   $path->println( ++$n_trys );
   (not $self->max_login_trys or $n_trys < $self->max_login_trys) and return;
   $path->exists and $path->unlink;
   $self->lock->reset( k => $path );
   $self->disable_account( $user );
   throw error => 'User [_1] max login attempts [_2] exceeded',
         args  => [ $user, $self->max_login_trys ], class => 'MaxLoginAttempts';
   return; # Never reached
}

sub _encrypt_password {
   my ($self, $password, $salt) = @_;

   my $type = $salt && $salt =~ m{ \A \$ 1    \$ }msx ? q(MD5)
            : $salt && $salt =~ m{ \A \$ 2 a? \$ }msx ? q(Blowfish)
            : $salt && $salt =~ m{ \A \$ 5    \$ }msx ? q(SHA-256)
            : $salt && $salt =~ m{ \A \$ 6    \$ }msx ? q(SHA-512)
            : $salt                                   ? q(unix)
                                                      : $self->passwd_type;

   $salt ||= $self->_get_salt_for( $type );

   return $type eq q(Blowfish) ? bcrypt( $password, $salt )
                               :  crypt  $password, $salt;
}

sub _generate_password {
   my $self = shift;

   try {
      $self->ensure_class_loaded( q(Crypt::PassGen) );

      my $passwd = (Crypt::PassGen::passgen( NLETT => 6, NWORDS => 1 ))[ 0 ]
         or throw $Crypt::PassGen::ERRSTR;

      return $passwd;
   }
   catch ($e) { $self->log->error( $e ) }

   return $self->usul->prefix;
}

sub _get_salt_for {
   my ($self, $type) = @_; my $lf = $self->load_factor;

   $type eq q(MD5)      and return '$1$'.__get_salt_bytes( 8 );
   $type eq q(Blowfish) and
            return "\$2a\$${lf}\$".(en_base64( __get_salt_bytes( 16 ) ));
   $type eq q(SHA-256)  and return '$5$'.__get_salt_bytes( 8 );
   $type eq q(SHA-512)  and return '$6$'.__get_salt_bytes( 8 );

   return __get_salt_bytes( 2 );
}

sub _get_user_ref {
   my ($self, $username) = @_; $username or return {};

   my ($cache) = $self->_load( $username ); return $cache->{ $username };
}

sub _load {
   return ({}, {}, {}); # Override in subclass
}

sub _register_dequeue {
   my ($self, $path) = @_;

   -f $path or throw error => 'File [_1] not found', args => [ $path ];

   my $fields = $self->file->dataclass_schema( { lock => TRUE } )->load( $path);
   my $io     = $self->io( $self->register_queue_path )->chomp->lock;

   $io->println( grep { not m{ \A $path \z }mx } $io->getlines ); unlink $path;

   return $fields;
}

sub _register_enqueue {
   my ($self, $fields) = @_;

   my $path = $self->tempname( dirname( $self->register_queue_path ) );
   my $fdcs = $self->file->dataclass_schema( { lock => TRUE } );

   $fdcs->dump( { data => $fields, path => $path } );
   $self->io( $self->register_queue_path )->lock->appendln( $path );
   return $path;
}

sub _register_verification_email {
   my ($self, $args, $fields) = @_;

   my $key = $args->{key} or return 'No activation key, no email sent';

   $self->io( [ $self->sessdir, $key ] )->println( $fields->{username} );

   $args->{post}->{to   } = $fields->{email_address};
   $args->{post}->{stash} = { %{ $fields }, %{ $args->{post}->{stash} } };

   return 'Email sent to [_1]', $self->send_email( $args->{post} );
}

# Private functions

sub __BASE64 () {
   return [ q(a) .. q(z), q(A) .. q(Z), 0 .. 9, q(.), q(/) ];
}

sub __get_salt_bytes ($) {
   return join NUL, map { __BASE64()->[ rand 64 ] } 1 .. $_[ 0 ];
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Users - User domain model

=head1 Version

Describes v0.9.$Rev: 0 $

=head1 Synopsis

   package CatalystX::Usul::Users::DBIC;

   extends CatalystX::Usul::Users;

=head1 Description

Implements the base class for user objects. Each subclass
that inherits from this should implement the required list of methods

=head1 Configuration and Environment

Defines the following attributes

=over 3

=item C<alias_class>

A loadable class which defaults to L<File::MailAlias>

=item C<aliases>

An instance of the I<alias_class> attribute

=item C<cache>

A hash ref that caches L<CatalystX::Usul::Response::Users> objects

=item C<def_passwd>

Default password string which defaults I<*DISABLED*>

=item C<load_factor>

Integer which defaults to 14. Used by L<Crypt::Eksblowfish::Bcrypt> to
determine how expensive the key distribution algorithm should be

=item C<max_login_trys>

Maximum number of login attempts before an account is disabled. An
integer that defaults to 3

=item C<max_pass_hist>

Maximum number of previous password to store thereby preventing
reuse. An integer that defaults to 10

=item C<min_name_len>

Minimum combined length of the users first and last names. Used to create the
account name. An integer that defaults to 6

=item C<passwd_type>

Default encryption algorithm to use when encrypting passwords. A
string that defaults to I<Blowfish>

=item C<profile_class>

A loadable class which defaults to L<CatalystX::Usul::UserProfiles>

=item C<profiles>

An instance of the I<profile_class>

=item C<role_cache>

A hash ref that caches L<CatalystX::Usul::Role> objects

=item C<role_class>

A required loadable class which defaults to L<Class::Null>

=item C<roles>

An instance of the I<role_class>

=item C<sessdir>

Path to the directory containing the user password history files and
the count of failed login attempts. Location of used user passwords
and account activation keys

=item C<user_pattern>

The default pattern used to filter user accounts. A string that
defaults to I<\A [a-zA-Z0-9]+>

=item C<userid_len>

The length of the generated user id, without the prefix. An integer
that defaults to 3

=back

=head1 Subroutines/Methods

=head2 activate_account

Activation is not currently supported by the base user store

=head2 authenticate

   $user_obj = $self->authenticate( $test_for_expired, $username, $password );

Called by the C<check_password> method in the user response class. If
the C<$test_for_expired> flag is true then the accounts password must
not have expired or an exception will be thrown. The supplied password
is encrypted and compared to the one in storage.  Failures are counted
and when I<max_login_trys> are exceeded the account is
disabled. Errors can be thrown for; unknown user, inactive account,
expired password, maximum attempts exceeded and incorrect password

=head2 change_password

   $self->change_password( $username, $old, $new, $encrypted );

Proxies a call to C<update_password> which must be implemented by
the subclass. Requires the user to authenticate

=head2 dequeue_activation_file

   $username = $self->dequeue_activation_file( $file );

Reads and deletes the supplied activation file. Returns the username

=head2 disable_account

   $self->disable_account( $user );

Calls C<update_password> in the subclass to set the users encrypted
password to I<*DISABLED*> thereby preventing the user from logging in

=head2 encrypt_password

   $enc_pass = $self->encrypt_password( $force, $username, $old, $new, $encrypted );

Encrypts the I<new> password and returns it. If the I<encrypted> flag
is true then I<new> is assumed to be already encrypted and is returned
unchanged. The I<old> password is used to authenticate the I<user> unless
the I<force> flag is true

=head2 find_user

   $user_obj = $self->find_user( $username, [ $verbose ] );

This method is required by the L<Catalyst::Authentication::Store>
API. It returns a user object (obtained by calling L</get_user>)
even if the user is unknown. If the user is known a list of roles that
the user belongs to is also returned. Adds a weakened reference to
self so that L<Catalyst::Authentication> can call the
C<check_password> method on the response class. If the C<$verbose> flag
is true will load additional information about the user, e.g. their
F<.project>

=head2 get_new_user_id

   $user_id = $self->get_new_user_id( $first_name, $last_name, [ $prefix ] );

Implements the algorithm that derives the username from the users first
name and last name. The supplied prefix from the user profile is prepended
to the generated value. If the prefix contains unique domain information
then the generated username will be globally unique to the organisation

=head2 get_primary_rid

   $role_id = $self->get_primary_rid( $username );

Placeholder methods returns undef. May be overridden in a subclass

=head2 get_security_data

   $user_security_ref = $self->get_security_data( $username, $password_type );

Returns a hash ref of security data about the requested user.

=head2 get_user

   $user_obj = $self->get_user( $username, [ $verbose ] );

Returns a user object for the given user id. If the user does not
exist then a user object with a name of I<unknown> is returned. If
the C<$verbose> flag is true will load additional information about
the user, e.g. their F<.project>

=head2 get_user_data

   $user_data_ref = $self->get_user_data( \%options, $username );

Returns a hash ref of data about the requested user. Includes the fields
from L</find_user> plus profile data

=head2 get_users_by_rid

   @user_list = $self->get_users_by_rid( $role_id );

Placeholder methods returns an empty list. May be overridden in a subclass

=head2 invalidate_cache

   $self->invalidate_cache;

Marks the user and role caches as invalid thereby forcing a reload

=head2 invalidate_user_cache

   $self->invalidate_user_cache;

Marks the user cache as invalid thereby forcing a reload

=head2 is_user

   $bool = $self->is_user( $username );

Returns true if the given user exists, false otherwise

=head2 list

   $user_list = $self->list( [ $pattern ] );

Returns an array ref of all users whose ids match the optional pattern

=head2 loc

   $localised_text = $self->loc( $key, @args );

Return text localised to a given language

=head2 register

   $list_of_list_of_localisable_messages = $self->register( $args, $fields );

Create a new self registered user

=head2 register_authorisation

   @localisable_message = $self->register_authorisation( $fields );

Write the user data fields to disk and await authorisation before creating
the new user

=head2 set_password

   $self->set_password( $username, $new, $encrypted );

Proxies a call to C<update_password> which must be implemented by
the subclass. Does not require user authentication

=head2 supports

   $bool = $self->supports( @spec );

Returns true if the hash returned by our I<get_features> attribute
contains all the elements of the required specification

=head2 user_attributes

   @attribute_list = $self->user_attributes

Class methods returns the list of attributes supported by the
L<CatalystX::Usul::Response::Users> response object

=head2 validate_password

   $bool = $self->validate_password( $username, $password );

Wraps a call to L</authenticate> in a try block so that a failure
to validate the password returns false rather than throwing an
exception

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Response::Users>

=item L<CatalystX::Usul::Shells>

=item L<CatalystX::Usul::Moose>

=item L<Class::Usul::File>

=item L<Class::Usul::IPC>

=item L<Crypt::Eksblowfish::Bcrypt>

=item L<CatalystX::Usul::Constraints>

=item L<TryCatch>

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
