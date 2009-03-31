package CatalystX::Usul::Model::Identity::Users;

# @(#)$Id: Users.pm 418 2009-03-31 01:17:43Z pjf $

use strict;
use warnings;
use parent qw(CatalystX::Usul::Model);
use CatalystX::Usul::FileSystem;
use CatalystX::Usul::Shells;
use Class::C3;
use Class::Null;
use Crypt::PassGen;
use Crypt::PasswdMD5;
use Scalar::Util qw(weaken);
use Sys::Hostname;
use XML::Simple;

use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 418 $ =~ /\d+/gmx );

my $NUL    = q();
my $SEP    = q(/);
my $SPC    = q( );
my @CSET   = ( q(.), q(/), 0 .. 9, q(A) .. q(Z), q(a) .. q(z) );
my %FIELDS =
   ( active           => 0,             auth_realm       => undef,
     crypted_password => $NUL,          email_address    => $NUL,
     first_name       => $NUL,          homedir          => q(/tmp),
     home_phone       => $NUL,          uid              => $NUL,
     last_name        => $NUL,          location         => $NUL,
     pgid             => $NUL,          project          => $NUL,
     pwafter          => 0,             pwdisable        => 0,
     pwlast           => 0,             pwnext           => 0,
     pwwarn           => 0,             pwexpires        => 0,
     shell            => q(/bin/false), username         => q(unknown),
     work_phone       => $NUL, );

__PACKAGE__->config( common_home        => q(/home/common),
                     def_passwd         => q(*DISABLED*),
                     email_content_type => q(text/html),
                     email_template     => q(new_account.tt),
                     host               => hostname,
                     mail_domain        => q(localhost),
                     max_login_trys     => 3,
                     max_pass_hist      => 10,
                     min_fullname_len   => 6,
                     rprtdir            => q(root/reports),
                     sessdir            => q(hist),
                     user_pattern       => q(\A [a-zA-Z0-9]+),
                     userid_len         => 3, );

__PACKAGE__->mk_accessors( qw(app_name auth_realms aliases_ref
                              common_home def_passwd
                              email_content_type email_template
                              field_defaults fs_model host
                              mail_domain max_login_trys max_pass_hist
                              min_fullname_len profiles_ref
                              register_queue_path roles_obj rprtdir
                              sessdir shells_model user_list user_model
                              user_pattern userid_len _cache
                              _rid2users _uid2name) );

__PACKAGE__->mk_accessors( keys %FIELDS );

sub new {
   my ($self, $app, @rest) = @_;

   my $new      = $self->next::method( $app, @rest );
   my $app_conf = $app->config || {};
   my $rprt_dir = $self->catdir( $app_conf->{vardir}, $new->rprtdir );
   my $sess_dir = $self->catdir( $app_conf->{vardir}, $new->sessdir );

   $new->app_name(       $app_conf->{name} );
   $new->field_defaults( \%FIELDS );
   $new->fs_model(       CatalystX::Usul::FileSystem->new( $app, @rest ) );
   $new->rprtdir(        $app_conf->{rprtdir} || $rprt_dir );
   $new->sessdir(        $app_conf->{sessdir} || $sess_dir );
   $new->shells_model(   CatalystX::Usul::Shells->new( $app, @rest ) );
   return $new;
}

# C::A::Store methods

sub check_password {
   my ($self, $password) = @_;

   return unless (my $model = $self->user_model);

   return if (not $self->username or $self->username eq q(unknown));

   return $model->f_check_password( $self->username, $password );
}

sub find_user {
   my ($self, $user, $verbose) = @_;

   my $user_ref = $self->f_get_user( $user, $verbose );
   my $new      = bless $user_ref, ref $self || $self;

   if ($new->username ne q(unknown) && $self->supports( qw(roles) )) {
      $new->roles( [ $self->roles_obj->get_roles( $user, $new->pgid ) ] );
   }
   else { $new->roles( [] ) }

   $new->user_model( $self ); weaken( $new->{user_model} );

   return $new;
}

sub for_session {
   my $self = shift; delete $self->{user_model}; return $self;
}

sub get {
   my ($self, $field) = @_;

   return $self->can( $field ) ? $self->$field() : undef;
}

sub get_object {
   return shift;
}

sub id {
   return shift->username;
}

# Base class methods

sub activate_account {
   my ($self, $key) = @_; my ($path, $user);

   $path = $self->catfile( $self->sessdir, $key );

   return $self->add_error_msg( q(eNotFound), $path ) unless (-f $path);

   unless ($user = $self->io( $path )->chomp->lock->getline) {
      return $self->add_error_msg( q(eNoData), $path );
   }

   unlink $path;

   unless ($self->is_user( $user )) {
      return $self->add_error_msg( q(eUnknownUser), $user );
   }

   $self->f_activate_account( $user );
   $self->add_result_msg( q(accountActivated), $user );
   return;
}

sub authenticate {
   my ($self, $flag, $user, $passwd) = @_;
   my ($e, $n_trys, $path, $res, $user_obj, $wtr);

   $self->throw( q(eNoUser) ) unless ($user);

   $user_obj = $self->find_user( $user );

   if ($user_obj->username eq q(unknown)) {
      $self->throw( error => q(eUnknownUser), arg1 => $user );
   }

   unless ($user_obj->active) {
      $self->throw( error => q(eAccountInactive), arg1 => $user );
   }

   if ($flag and $self->_is_password_expired( $user_obj )) {
      $self->throw( error => q(ePasswordExpired), arg1 => $user );
   }

   if ($passwd eq q(stdin)) {
      $passwd = <STDIN>; $passwd ||= q(); chomp $passwd;
   }

   if ($user_obj->crypted_password =~ m{ \A \$ 1 \$ }msx) {
      $res = unix_md5_crypt( $passwd, $user_obj->crypted_password );
   }
   else { $res = crypt $passwd, $user_obj->crypted_password }

   $path = $self->catfile( $self->sessdir, $user );
   $self->lock->set( k => $path );

   if ($res eq $user_obj->crypted_password) {
      unlink $path if (-f $path);
      $self->lock->reset( k => $path );
      return $user_obj;
   }

   if (-f $path) {
      $n_trys = eval { $self->io( $path )->chomp->getline };

      if ($e = $self->catch) {
         $self->lock->reset( k => $path ); $self->throw( $e );
      }

      $n_trys ||= 0; $n_trys++;
   }
   else { $n_trys = 1 }

   if ($self->max_login_trys and $n_trys >= $self->max_login_trys) {
      unlink $path if (-f $path);
      $self->lock->reset( k => $path );
      $self->update_password( 1, $user, q(), q(*DISABLED*), 1 );
      $self->throw( error => q(eMaxLoginAttempts),
                    arg1  => $user,
                    arg2  => $self->max_login_trys );
   }

   eval { $self->io( $path )->println( $n_trys ) };

   if ($e = $self->catch) {
      $self->lock->reset( k => $path ); $self->throw( $e );
   }

   $self->lock->reset( k => $path );
   $self->throw( error => q(eIncorrectPassword), arg1 => $user );
   return;
}

sub authentication_form {
   my ($self, $user) = @_;
   my $s             = $self->context->stash;
   my $form          = $s->{form}->{name};
   my $id            = $form.q(.user);

   ($user ||= $s->{user}) =~ s{ \A unknown \z }{}msx;

   $self->clear_form(  { firstfld   => $id,
                         heading    => $self->loc( $form.q(.header) ),
                         subHeading => { content => q(&nbsp;) } } );
   $self->add_field(   { default    => $user, id => $id } );
   $self->add_field(   { id         => $form.q(.passwd) } );
   $self->add_field(   { id         => $form.q(.login_text) } );
   $self->add_buttons( qw(Login) );
   return;
}

sub authentication_reminder {
   my $self = shift;

   if ($self->context->stash->{user} eq q(unknown)) {
      $self->add_field( { id => q(authentication_reminder.login_now_text) } );
   }

   return;
}

sub change_password {
   my $self = shift; my ($flds, $val);

   for ( qw(user oldPass newPass1 newPass2) ) {
      $flds->{ $_ } = $val if (defined ($val = $self->query_value( $_ )));
   }

   $flds = $self->check_form( $flds );

   if ($flds->{newPass1} ne $flds->{newPass2}) {
      $self->throw( q(ePasswordsNotSame) );
   }

   $self->f_change_password( $flds->{user},
                             $flds->{oldPass}, $flds->{newPass1} );
   $self->add_result_msg( q(passwordChanged), $flds->{user} );
   return;
}

sub change_password_form {
   my ($self, $realm, $user) = @_;

   my $values = [ q(), sort keys %{ $self->auth_realms } ];
   my $s      = $self->context->stash; $s->{pwidth} -= 10;
   my $form   = $s->{form}->{name};
   my $nitems = 0;
   my $step   = 1;

   ($user ||= $s->{user}) =~ s{ unknown }{}mx;

   $self->clear_form(   { firstfld => $form.q(.user) } );
   $self->add_field(    { default  => $realm,
                          id       => $form.q(.realm),
                          stepno   => 0,
                          values   => $values } ); $nitems++;

   if ($realm) {
      $self->add_field( { ajaxid   => $form.q(.user),
                          default  => $user,
                          stepno   => 0 } ); $nitems++;
      $self->add_field( { id       => $form.q(.oldPass),
                          stepno   => $step++ } ); $nitems++;
      $self->add_field( { ajaxid   => $form.q(.newPass1),
                          stepno   => $step++ } ); $nitems++;
   }

   my $id = $form.($realm && $user ? q(.select) : q(.selectUnknown));

   $self->group_fields( { id       => $id, nitems => $nitems } );
   $self->add_buttons(  qw(Set) );
   return;
}

sub create_or_update {
   my $self = shift; my ($email_addr, $flds, $user);

   unless ($user = $self->query_value( q(username) )) {
      $self->throw( q(eNoUser) );
   }

   for ( qw(username profile first_name last_name location work_phone
            email_address home_phone project homedir shell populate) ) {
      if ($_ eq q(first_name) || $_ eq q(last_name)) {
         $flds->{ $_ } = ucfirst $self->query_value( $_ );
      }
      else { $flds->{ $_ } = $self->query_value( $_ ) }
   }

   unless ($flds->{email_address}) {
      $email_addr = join q(.), map { ucfirst $_ } ( $flds->{first_name},
                                                    $flds->{last_name} );
      $email_addr .= q(@).$self->mail_domain;
      $flds->{email_address} = $email_addr;
   }

   $flds->{active    } = 1;
   $flds->{alias_name} = $flds->{username};
   $flds->{recipients} = [ $flds->{email_address} ];
   $flds->{owner     } = $ENV{LOGNAME};
   $flds->{comment   } = 'Local user';
   $flds = $self->check_form( $flds );

   if ($self->is_user( $user )) {
      $self->f_update( $flds );
      $self->add_result_msg( q(accountUpdated), $user );
   }
   else {
      $self->f_create( $flds );
      $self->add_result_msg( q(accountCreated), $user );
   }

   return $user;
}

sub delete {
   my $self = shift; my $user;

   $self->throw( q(eNoUser) ) unless ($user = $self->query_value( q(user) ));

   unless ($self->is_user( $user )) {
      $self->throw( error => q(eUnknownUser), arg1 => $user );
   }

   $self->f_delete( $user );
   $self->add_result_msg( q(accountDeleted), $user );
   return;
}

sub get_new_user_id {
   my ($self, $first_name, $last_name, $prefix) = @_;
   my ($carry, @chars, $i, $lastp, $lid, $name_len, $ripple, @words);

   my $name = (lc $last_name).(lc $first_name);

   if ((length $name) < $self->min_fullname_len) {
      $self->throw( error => q(eNameToShort),
                    arg1  => $first_name.$SPC.$last_name,
                    arg2  => $self->min_fullname_len );
   }

   $name_len  = $self->userid_len;
   $prefix    = $NUL unless (defined $prefix);
   $lastp     = length $name < $name_len ? length $name : $name_len;
   @chars     = ();
   $chars[$_] = $_ for (0 .. $lastp - 1);

   while ($chars[ $lastp - 1 ] < length $name) {
      $lid = $NUL; $i = 0;

      while ($i < $lastp) { $lid .= substr $name, $chars[ $i++ ], 1 }

      last unless ($self->is_user( $prefix.$lid ));

      $i = $lastp - 1; $chars[ $i ] += 1;

      while ($i >= 0 && $chars[ $i ] >= length $name) {
         $ripple = $i - 1; $chars[ $ripple ] += 1;

         while ($ripple < $lastp) {
            $carry = $ripple + 1; $chars[ $carry ] = $chars[ $ripple++ ] + 1;
         }

         $i--;
      }
   }

   if ($chars[ $lastp - 1 ] >= length $name) {
      $self->throw( 'no user ids left for '.$first_name.$SPC.$last_name );
   }

   unless ($lid) {
      $self->throw( 'account name generation failed for '.$name );
   }

   return ($prefix || $NUL).$lid;
}

sub get_primary_rid {
   my ($self, $user) = @_;

   return defined $user ? $self->f_get_primary_rid( $user ) : undef;
}

sub get_users_by_rid {
   my ($self, $rid) = @_;

   return defined $rid ? $self->f_get_users_by_rid( $rid ) : undef;
}

sub is_user {
   my ($self, $user) = @_; return $user ? $self->f_is_user( $user ) : undef;
}

sub purge {
   my $self = shift; my ($nrows, $rno, $user);

   unless ($nrows = $self->query_value( q(_nrows) )) {
      $self->throw( $self->loc( q(eNoAccount) ) );
   }

   for $rno (0 .. $nrows - 1) {
      if ($user = $self->query_value( q(select).$rno )) {
         $self->f_delete( $user );
         $self->add_result_msg( q(accountDeleted), $user );
      }
   }

   return;
}

sub register {
   my ($self, $path) = @_; my ($args, $e, $flds, $key, $link, $subject, $val);

   my $s = $self->context->stash;

   unless ($path) {
      for ( qw(email_address first_name last_name newPass1 newPass2
               work_phone home_phone location project) ) {
         if (defined ($val = $self->query_value( $_ ))) {
            $flds->{ $_ } = $val;
         }
      }

      $flds->{active  } = 0;
      $flds->{password} = $flds->{newPass1};
      $flds->{profile } = $s->{register}->{profile};
   }

   if (!$path && $self->register_queue_path) {
      $self->_register_write_queue( $flds );
      # TODO:  Add email message to authorising authority
      $self->add_result_msg( q(awaitingAuthorisation), $flds->{email} );
      return;
   }

   $flds = $self->_register_read_queue( $path ) if ($path);

   $self->lock->set( k => q(register_user) );

   eval {
      $self->_register_validation( $flds );
      $self->f_create( $flds );
   };

   if ($e = $self->catch) {
      $self->lock->reset( k => q(register_user) );
      $self->throw( $e );
   }

   $self->lock->reset( k => q(register_user) );
   $self->add_result_msg( q(accountCreated), $flds->{username} );

   # Registration verification email
   $key     = $self->create_token;
   $self->io( $self->catfile( $self->sessdir,
                              $key ) )->println( $flds->{username} );
   $link    = $self->uri_for( q(entrance/activate_account), $s->{lang}, $key );
   $subject = $self->loc( q(accountVerification), $self->app_name );
   $args    = { attributes  => { charset      => $s->{encoding},
                                 content_type => $self->email_content_type },
                from        => q(UserRegistration@).$s->{host},
                mailer      => $s->{mailer},
                mailer_host => $s->{mailer_host},
                stash       => { %{ $flds },
                                 app_name => $self->app_name, link => $link },
                subject     => $subject,
                template    => $self->email_template,
                to          => $flds->{email_address} };

   $self->add_result( $self->send_email( $args ).$SPC.$flds->{email_address} );
   return;
}

sub _register_read_queue {
   my ($self, $path) = @_; my ($e, $flds, $io, $xs);

   $xs = XML::Simple->new( SuppressEmpty => undef );

   $self->lock->set( k => $path );

   eval {
      $self->throw( error => q(eNotFound), arg1 => $path ) unless (-f $path);
      $io   = $self->io( $self->register_queue_path )->chomp->lock;
      $io->println( grep { !m{ \A $path \z }mx } $io->getlines );
      $flds = $xs->xml_in( $path );
      unlink $path;
   };

   if ($e = $self->catch) {
      $self->lock->reset( k => $path ); $self->throw( $e );
   }

   $self->lock->reset( k => $path );
   return $flds;
}

sub _register_write_queue {
   my ($self, $flds) = @_; my ($e, $path, $xs);

   $path = $self->tempname( $self->dirname( $self->register_queue_path ) );
   $xs   = XML::Simple->new( NoAttr        => 1,
                             SuppressEmpty => 1,
                             RootName      => q(config) );
   $self->lock->set( k => $path );

   eval {
      $xs->xml_out( $flds, OutputFile => $path );
      $self->io( $self->register_queue_path )->lock->appendln( $path );
   };

   if ($e = $self->catch) {
      $self->lock->reset( k => $path ); $self->throw( $e );
   }

   $self->lock->reset( k => $path );
   return;
}

sub _register_validation {
   my ($self, $flds) = @_;

   my $prefix = $self->profiles_ref->find( $flds->{profile} )->prefix;
   $flds->{username} = $self->get_new_user_id( $flds->{first_name},
                                               $flds->{last_name},
                                               $prefix );
   $flds = $self->check_form( $flds );

   if ($flds->{newPass1} ne $flds->{newPass2}) {
      $self->throw( q(ePasswordsNotSame) );
   }

   delete $flds->{newPass1}; delete $flds->{newPass2};
   return;
}

sub register_form {
   my $self = shift; my $s = $self->context->stash;

   my $form = $s->{form}->{name}; my $step = 1; $s->{pwidth} -= 10;

   my $captcha_uri = $self->uri_for( q(root).$SEP.q(captcha), $s->{lang} );

   $self->clear_form(   { firstfld => $form.q(.first_name) } ); my $nitems = 0;
   $self->add_field(    { ajaxid   => $form.q(.first_name),
                          stepno   => $step++ } ); $nitems++;
   $self->add_field(    { ajaxid   => $form.q(.last_name),
                          stepno   => $step++ } ); $nitems++;
   $self->add_field(    { ajaxid   => $form.q(.email_address),
                          stepno   => $step++ } ); $nitems++;
   $self->add_field(    { ajaxid   => $form.q(.newPass1),
                          stepno   => $step++ } ); $nitems++;
   $self->add_field(    { id       => $form.q(.work_phone),
                          stepno   => $step++ } ); $nitems++;
   $self->add_field(    { id       => $form.q(.location),
                          stepno   => $step++ } ); $nitems++;
   $self->add_field(    { id       => $form.q(.project),
                          stepno   => $step++ } ); $nitems++;
   $self->add_field(    { id       => $form.q(.home_phone),
                          stepno   => $step++ } ); $nitems++;
   $self->add_field(    { name     => $form.q(.captcha),
                          stepno   => 0,
                          text     => $captcha_uri } ); $nitems++;
   $self->add_field(    { ajaxid   => $form.q(.security),
                          stepno   => $step++ } ); $nitems++;
   $self->group_fields( { id       => $form.q(.legend), nitems => $nitems } );
   $self->add_buttons(  qw(Insert) );
   return;
}

sub retrieve {
   my ($self, $pattern, $user) = @_;

   my $user_obj = $self->find_user( $user, 1 );

   $user_obj->user_list( $self->f_list( $pattern || $self->user_pattern ) );
   return $user_obj;
}

sub set_password {
   my ($self, $user) = @_; my ($encrypted, $password, $ptype);

   $self->throw( q(eNoUser) ) unless ($user);

   $ptype = $self->query_value( q(p_type) );

   if ($ptype && $ptype == 4) {
      $encrypted = 0; $password = $self->query_value( q(p_generated) );
   }
   elsif ($ptype && $ptype == 3) {
      unless ($self->query_value( q(p_word1) )
              && $self->query_value( q(p_word2) )) {
         $self->throw( q(ePasswordMissing) );
      }

      unless ($self->query_value( q(p_word1) )
              eq $self->query_value( q(p_word2) )) {
         $self->throw( q(ePasswordsNotSame) );
      }

      $encrypted = 0; $password = $self->query_value( q(p_word1) );
   }
   elsif ($ptype && $ptype == 2) {
      $encrypted = 1;
      $password  = q(*).$self->query_value( q(p_value) ).q(*);
   }
   else {
      $encrypted = 0; $password = $self->query_value( q(p_default) );
   }

   $self->f_set_password( $user, $password, $encrypted );
   $self->add_result_msg( q(passwordSet), $user );
   return;
}

sub update_password {
   my ($self, $force, $user, $old_pass, $new_pass, $encrypted) = @_;
   my ($e, $enc_pass, @flds, $i, $line, $path, $res, $text, $user_obj, $wtr);

   $self->throw( q(eNoUser) ) unless ($user);

   unless ($self->is_user( $user )) {
      $self->throw( error => q(eUnknownUser), arg1 => $user );
   }

   unless ($force) {
      $user_obj = $self->authenticate( 0, $user, $old_pass );

      if (($res = $self->_can_change_password( $user_obj )) > 0) {
         $text  = 'You cannot change your password for another '.$res.' days';
         $self->throw( $text );
      }
   }

   $path = $self->catfile( $self->sessdir, $user.'_history' );

   unless ($encrypted) {
      if (not $force
          and -f $path
          and $line = $self->io( $path )->chomp->lock->getline) {
         @flds = split m{ , }mx, $line;

         for $i (0 .. $#flds - 1) {
            if ($self->passwd_type eq q(md5)) {
               $enc_pass = unix_md5_crypt( $new_pass, $flds[ $i ] );
            }
            else { $enc_pass = crypt $new_pass, $flds[ $i ] }

            $self->throw( q(ePasswordUsedBefore) ) if ($enc_pass eq $flds[$i]);
         }
      }

      if ($self->passwd_type eq q(md5)) {
         $enc_pass  = unix_md5_crypt( $new_pass );
      }
      else {
         $enc_pass  = crypt $new_pass, join q(), @CSET[ rand 64, rand 64 ];
      }
   }
   else { $enc_pass = $new_pass }

   unless ($force) {
      push @flds, $enc_pass;

      while ($#flds > $self->max_pass_hist) { shift @flds }

      $self->io( $path )->lock->println( join q(,), @flds );
   }

   $self->f_update_password( $user, $enc_pass, $force );
   return;
}

sub user_fill {
   my $self = shift; my $s = $self->context->stash; my $fill = $s->{fill} = {};

   $fill->{first_name} = ucfirst $self->query_value( q(first_name) );
   $fill->{last_name } = ucfirst $self->query_value( q(last_name) );
   $fill->{email     }
      = $fill->{first_name}.q(.).$fill->{last_name}.q(@).$self->mail_domain;
   return 1;
}

sub user_manager_form {
   my ($self, $realm, $user, $profile_name) = @_;
   my ($e, $fill, $labels, $profile, $profile_list, $profiles, $shell_def);
   my ($shells_obj, $shells, $text, $user_obj, $users, $values);

   my $s          = $self->context->stash; $s->{pwidth} -= 10;
   my $form       = $s->{form}->{name};
   my $email      = $NUL;
   my $first_name = $NUL;
   my $homedir    = $NUL;
   my $home_tel   = $NUL;
   my $last_name  = $NUL;
   my $location   = $NUL;
   my $name       = $NUL;
   my $project    = $NUL;
   my $role       = $NUL;
   my $shell      = $NUL;
   my $work_tel   = $NUL;
   my $nitems     = 0;
   my $step       = 1;

   # Retrieve data from model
   eval {
      $user_obj = $self->retrieve( $NUL, $user );
      $users    = $user_obj->user_list;
      unshift @{ $users }, $NUL, $s->{newtag};

      $profile_list = $self->profiles_ref->get_list( $profile_name );
      $profiles     = $profile_list->list; unshift @{ $profiles }, $NUL;
      $profile      = $profile_list->element;
      $labels       = $profile_list->labels;

      if ($self->supports( qw(fields shells) )) {
         $shells_obj = $self->shells_model->retrieve();
         $shell_def  = $shells_obj->default;
         $shells     = $shells_obj->shells;
      }

      $homedir = $profile->homedir;
      $project = $profile->project;
      $shell   = $profile->shell || $shell_def || q(/bin/ksh);

      if ($user and $user eq $s->{newtag} and $fill = $s->{fill}) {
         $email      = $fill->{email};
         $first_name = $fill->{first_name};
         $last_name  = $fill->{last_name};
         $name       = $self->get_new_user_id( $first_name,
                                               $last_name,
                                               $profile->prefix );

         if ($name
             and $self->supports( qw(fields homedir) )
             and $homedir ne $self->common_home) {
            $homedir = $self->catdir( $homedir, $name );
         }
      }
      elsif ($user and $user ne $s->{newtag} and $user !~ m{ \A all \s }imsx) {
         $email      = $user_obj->email_address;
         $first_name = $user_obj->first_name;
         $homedir    = $user_obj->homedir;
         $home_tel   = $user_obj->home_phone;
         $last_name  = $user_obj->last_name;
         $location   = $user_obj->location;
         $name       = $user;
         $project    = $user_obj->project;
         $role       = shift @{ $user_obj->roles };
         $shell      = $user_obj->shell;
         $work_tel   = $user_obj->work_phone;
      }
   };

   $self->add_error( $e ) if ($e = $self->catch);

   # Add elements to form
   $self->clear_form( { firstfld => $form.'.realm' } );

   $values = [ q(), sort keys %{ $self->auth_realms } ];
   $self->add_field(  { default => $realm,
                        id      => $form.'.realm',
                        stepno  => 0,
                        values  => $values } ); $nitems++;

   if ($realm) {
      $self->add_field( { default => $user,
                          id      => $form.'.user',
                          stepno  => 0,
                          values  => $users } ); $nitems++;

      if ($user && $user eq $s->{newtag}) {
         $self->add_field( { default => $profile_name,
                             id      => $form.'.profile',
                             labels  => $labels,
                             stepno  => 0,
                             values  => $profiles } ); $nitems++;
      }
      else {
         $self->add_hidden( q(profile), $profile_name );

         if ($role) {
            $text  = $self->loc( $form.'.pgroup' );
            $text .= ($labels->{ $role } || q()).' ('.$role.') ';
            $self->add_field( { id     => $form.'.pgroup',
                                stepno => 0,
                                text   => $text } ); $nitems++;
         }
      }
   }

   $self->group_fields( { id => $form.'.select', nitems => $nitems } );
   $nitems   = 0;

   return if (not $user or lc $user eq q(all));
   return if ($user eq $s->{newtag} and not $profile_name);

   $self->add_field( { default => $first_name,
                       id      => $form.'.first_name',
                       stepno  => $step++ } ); $nitems++;
   $self->add_field( { default => $last_name,
                       id      => $form.'.last_name',
                       stepno  => $step++ } ); $nitems++;

   if ($user eq $s->{newtag} && !$name) { # Create new account
      $self->add_field( { id => $form.'.afill' } ); $nitems++;
   }

   $self->add_field( { default => $email,
                       id      => $form.'.email_address',
                       stepno  => $step++ } ); $nitems++;

   if ($user eq $s->{newtag}) { # Create new accounts
      if ($name) {
         $self->add_field( { default => $name,
                             id      => $form.'.username',
                             stepno  => $step++ } ); $nitems++;
      }

      $self->add_buttons( qw(Fill Insert) );
   }
   else { # Edit existing account
      $self->add_hidden(  q(username), $user );
      $self->add_buttons( qw(Save Delete) );
   }

   $self->add_field( { default => $location,
                       id      => $form.'.location',
                       stepno  => $step++ } ); $nitems++;
   $self->add_field( { default => $work_tel,
                       id      => $form.'.work_phone',
                       stepno  => $step++ } ); $nitems++;
   $self->add_field( { default => $home_tel,
                       id      => $form.'.home_phone',
                       stepno  => $step++ } ); $nitems++;
   $self->add_field( { default => $project,
                       id      => $form.'.project',
                       stepno  => $step++ } ); $nitems++;

   if ($self->supports( qw(fields homedir) )) {
      $self->add_field( { default => $homedir,
                          id      => $form.'.homedir',
                          stepno  => $step++ } ); $nitems++;

      if ($user eq $s->{newtag} && $homedir ne $self->common_home) {
         $self->add_field( { label  => $SPC,
                             id     => $form.'.populate',
                             stepno => $step++ } ); $nitems++;
      }
   }

   if (defined $shells) {
      $self->add_field( { default => $shell,
                          id      => $form.'.shell',
                          stepno  => $step++,
                          values  => $shells } ); $nitems++;
   }

   $self->group_fields( { id => $form.'.edit', nitems => $nitems } );
   return;
}

sub user_report_execute {
   my ($self, $type) = @_;
   my $s     = $self->context->stash;
   my $stamp = $self->time2str( '%Y%m%d%H%M', time );
   my $path  = $self->catfile( $self->rprtdir, 'userReport_'.$stamp.'.csv' );

   $self->add_result( $self->f_user_report( { debug => $s->{debug},
                                              path  => $path,
                                              type  => $type } ) );
   return;
}

sub user_report_form {
   my ($self, $realm, $id) = @_;
   my ($data, $dir, $e, $grp_id, $key, $pat, $path, $ref, $values);

   my $s      = $self->context->stash; $s->{pwidth} -= 10;
   my $form   = $s->{form}->{name};
   my $nitems = 0;

   unless ($dir = $self->query_value( q(dir) )) {
      $dir = $self->{rprtdir}; $pat = q(userReport*);
      $key = sub { return (split m{ \. }mx, (split m{ _ }mx, $_[0])[1])[0] };
   }
   else { $pat = q(.*); $key = undef }

   $self->clear_form;

   if ($id) {
      $path = $self->catfile( $dir, 'userReport_'.$id.'.csv' );
      $self->add_field(   { path    => $path,
                            select  => 1,
                            subtype => q(csv),
                            type    => q(file) } ); $nitems++;
      $self->add_field(   { id      => $form.'.keynote' } ); $nitems++;
      $self->add_buttons( qw(List Purge) );
   }
   else {
      $values = [ q(), sort keys %{ $self->auth_realms } ];
      $self->add_field(   { default => $realm,
                            id      => $form.'.realm',
                            stepno  => 0,
                            values  => $values } ); $nitems++;
      $self->add_buttons( qw(Execute) );
      $ref  = { action   => $s->{form}->{action},
                assets   => $s->{assets},
                dir      => $dir,
                make_key => $key,
                pattern  => $pat };
      $data = eval { $self->fs_model->list_subdirectory( $ref ) };

      unless ($e = $self->catch) {
         $self->add_field( { data => $data, type => q(table) } );
         $nitems++;
      }
      else { $self->add_error( $e, ($s->{debug} ? 3 : 2), 2 ) }
   }

   $grp_id = $form.($id ? q(.select_purge) : q(.select_view));
   $self->group_fields( { id => $grp_id, nitems => $nitems } );
   return;
}

sub user_security_form {
   my ($self, $realm, $user) = @_;
   my (@all_roles, $def, $e, $field, $form, $generated, $html, %labels);
   my ($nitems, @opts, $passwd, $profile, $ref, $res, $role, @roles);
   my ($s, $step, $user_obj, @users, $values);

   $s      = $self->context->stash;
   $form   = $s->{form}->{name};

   eval {
      $user_obj  = $self->retrieve( $NUL, $user );
      @users     = @{ $user_obj->user_list }; unshift @users, $NUL;
      @roles     = $user ? @{ $user_obj->roles } : ();
      @all_roles = grep { !$self->is_member( $_, @roles ) }
                   $self->roles_obj->get_roles( q(all) );
      $profile   = $self->profiles_ref->find( $roles[0] );
      $passwd    = $profile ? $profile->passwd : $NUL;
      $generated = (Crypt::PassGen::passgen( NLETT => 6, NWORDS => 1 ))[ 0 ]
         or $self->throw( $Crypt::PassGen::ERRSTR );

      shift @roles if ($user_obj->pgid);

      $s->{messages}->{p_default  }->{text} = $passwd;
      $s->{messages}->{p_generated}->{text} = $generated;
      $s->{fullname} = $user_obj->first_name.$SPC.$user_obj->last_name;

      $labels{1} = $SPC.$self->loc( $form.'.set_password_option1' );
      $labels{2} = $SPC.$self->loc( $form.'.set_password_option2' );
      $labels{3} = $SPC.$self->loc( $form.'.set_password_option3' );
      $labels{4} = $SPC.$self->loc( $form.'.set_password_option4' );
      $ref       = { default  => $self->query_value( q(p_type) ) || 1,
                     id       => $form.'.popt',
                     labels   => \%labels,
                     messages => $s->{messages},
                     name     => q(p_type),
                     type     => q(radioGroup),
                     values   => [ qw(1 2 3 4) ] };
      # TODO: Remove this coz it breaks MVC
      $html      = HTML::FormWidgets->new( $ref )->render;
      $html      =~ s{ <div [^>]*> }{}msx; $html =~ s{ </div> }{}msx;
      $html      =~ s{ </label> }{}gmsx;
      @opts      = split m{ <label> }mx, $html; shift @opts;
   };

   return $self->add_error( $e ) if ($e = $self->catch);

   $s->{pwidth} -= 8;
   $field  = $form.($realm ? q(.user) : q(.realm));
   $self->clear_form(   { firstfld => $field } ); $nitems = 0;
   $self->add_hidden(   q(p_default), $passwd );
   $self->add_hidden(   q(p_generated), $generated );
   $values = [ q(), sort keys %{ $self->auth_realms } ];
   $self->add_field(    { default => $realm,
                          id      => $form.'.realm',
                          values  => $values } ); $nitems++;

   if ($realm) {
      $self->add_field( { default => $user,
                          id      => $form.'.user',
                          values  => \@users } ); $nitems++;
   }

   $self->group_fields( { id => $form.'.select', nitems => $nitems } );
   $nitems = 0;

   return unless ($user and $user ne $s->{newtag});

   if ($passwd) {
      $self->add_field( { id      => $form.'.p_default',
                          prompt  => $opts[0] } ); $nitems++;
   }

   $self->add_field(    { id      => $form.'.p_generated',
                          prompt  => $opts[3] } ); $nitems++;
   $def    = $self->query_value( q(p_value) ) || $NUL;
   $values = [ qw(disabled left nologin unused) ];
   $self->add_field(    { default => $def,
                          id      => $form.'.p_value',
                          prompt  => $opts[1],
                          values  => $values } ); $nitems++;
   $self->add_field(    { id      => $form.'.p_word1',
                          prompt  => $opts[2] } ); $nitems++;
   $self->group_fields( { id      => $form.'.set_password',
                          nitems  => $nitems } ); $nitems = 0;
   $self->add_field(    { all     => \@all_roles,
                          current => \@roles,
                          id      => $form.'.groups',
                          labels  => \%labels } ); $nitems++;
   $self->group_fields( { id      => $form.'.secondary',
                          nitems  => $nitems } ); $nitems = 0;
   $self->add_buttons(  qw(Set Update) );
   return;
}

# Private methods

sub _can_change_password {
   my ($self, $user_obj) = @_;

   return 0 unless ($user_obj->pwnext);

   my $now        = int time / 86_400;
   my $min_period = $user_obj->pwlast + $user_obj->pwnext;

   return $now >= $min_period ? 0 : $min_period - $now;
}

sub _is_password_expired {
   my ($self, $user_obj) = @_;
   my $now     = int time / 86_400;
   my $expires = $user_obj->pwlast && $user_obj->pwafter
               ? $user_obj->pwlast +  $user_obj->pwafter : 0;

   return 1 if (defined $user_obj->pwlast and $user_obj->pwlast == 0);
   return 1 if ($expires and $now > $expires);
   return 1 if ($user_obj->pwdisable and $now > $user_obj->pwdisable);
   return 0;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Identity::Users - Manager user data stores

=head1 Version

0.1.$Revision: 418 $

=head1 Synopsis

   use CatalystX::Usul::Model::Identity::Users::DBIC;

   my $class    = CatalystX::Usul::Model::Identity::Users::DBIC;
   my $user_obj = $class->new( $app, $config );

=head1 Description

Implements the base class for user data stores. Each factory subclass
should inherit from this and implement the required list of methods

=head1 Subroutines/Methods

=head2 new

Constructor initialises these attributes

=over 3

=item app_name

Name of the application using this identity model. Prefixes the subject line
of the account activation email sent to users who create an account via the
registration method

=item field_defaults

A hashref of the user object attributes and their default values

=item fs_model

An instance of L<CatalystX::Usul::FileSystem> used by the
L</user_report_form> method to list the available user reports

=item mail_domain

The default email domain used when users are created and a specific email
address is not supplied

=item rprtdir

Location in the filesystem of the user reports

=item sessdir

Location in the filesystem of used user passwords and account activation
keys

=back

=head2 activate_account

Checks for the existence of the file created by the L</register> method. If
it exists it contains the username of a recently created account. The
accounts I<active> attribute is set to true, enabling the account

=head2 authenticate

Called by the L</check_password> method via the factory subclass. The
supplied password is encrypted and compared to the one in storage.
Failures are counted and when I<max_login_trys> are exceeded the
account is disabled. Errors can be thrown for; unknown user, inactive
account, expired password, maximum attempts exceeded and incorrect
password

=head2 authentication_form

Adds fields to the stash for the login screen

=head2 authentication_reminder

If the user is unknown this method adds a label field to the stash
reminding the user to login

=head2 change_password

Method to change the users password. Throws exceptions for field
constraint failures and if the passwords entered are not the same

=head2 change_password_form

Adds field data to the stash for the change password screen. Allows users
to change their own password

=head2 check_password

This method is required by the L<Catalyst::Authentication::Store> API. It
calls the factory method in the subclass to check that the supplied
password is the correct one

=head2 create_or_update

Method to create a new account or update an existing one. Throws exceptions
for field constraint failures. Calls methods in the subclass to do the
actual work

=head2 delete

Deletes the selected account

=head2 find_user

This method is required by the L<Catalyst::Authentication::Store> API. It
returns a user object even if the user is unknown. If the user is known
a list of roles that the user belongs to is also returned. A weakened
copy of the self referential object is included in the returned object
so that the L<Catalyst::Authentication> plugin can call the
L</check_password> method

=head2 for_session

This method is required by the L<Catalyst::Authentication::Store> API.
Removes the copy of the self referential object so that the user
object can be serialized for the session store

=head2 get

This method is required by the L<Catalyst::Authentication::Store> API.
Field accessor returns undef if the field does not exist, otherwise
returns the value of the required field

=head2 get_new_user_id

Implements the algorithmn that derives the username from the users first
name and surname. The supplied prefix from the user profile is prepended
to the generated value. If the prefix contains unique domain information
then the generated username will be globally unique to the organisation

=head2 get_object

This method is required by the L<Catalyst::Authentication::Store> API.
Returns the self referential object

=head2 get_primary_rid

Returns the primary role id for the given user. Note not all storage models
support primary_role ids

=head2 get_users_by_rid

Returns the list of users that share the given primary role id

=head2 id

This method is required by the L<Catalyst::Authentication::Store> API.
Returns the username of the user object

=head2 is_user

Returns true if the given user exists, false otherwise

=head2 purge

Delete the list of selected accounts

=head2 register

Create the self registered account. The account is created in an inactive
state and a confirmation email is sent

=head2 register_form

Added the fields to the stash for the self registration screen. Users can
use this screen to create their own accounts

=head2 retrieve

Returns a user object for the selected user and a list of usernames

=head2 set_password

Sets the users password to a given value

=head2 update_password

Updates the users password only if the new one has not been used before or
there is an administrative override

=head2 user_fill

Sets the I<fill> attribute of the stash in response to clicking the
auto fill button

=head2 user_manager_form

Adds fields to the stash for the user management screen. Adminstrators can
create new accounts or modify the details of existing ones

=head2 user_report_execute

Creates a report of the user accounts in this realm

=head2 user_report_form

View either the list of available account reports or the contents of a
specific report

=head2 user_security_form

Add fields to the stash for the security administration screen. From here
administrators can reset passwords and change the list of roles to which
the selected user belongs

=head1 Diagnostics

None

=head1 Configuration and Environment

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::Model::FileSystem>

=item L<Class::Null>

=item L<Crypt::PasswdMD5>

=item L<Scalar::Util>

=item L<Sys::Hostname>

=item L<XML::Simple>

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
