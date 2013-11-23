# @(#)Ident: Users.pm 2013-11-21 23:40 pjf ;

package CatalystX::Usul::Model::Users;

use strict;
use version; our $VERSION = qv( sprintf '0.14.%d', q$Rev: 1 $ =~ /\d+/gmx );

use CatalystX::Usul::Constants;
use CatalystX::Usul::Constraints qw( Directory Path );
use CatalystX::Usul::Functions   qw( create_token merge_attributes throw );
use CatalystX::Usul::Moose;
use Class::Usul::File;
use Class::Usul::Time            qw( time2str );
use File::Basename               qw( dirname );
use File::Spec::Functions        qw( catdir catfile );
use TryCatch;

extends q(CatalystX::Usul::Model);
with    q(CatalystX::Usul::TraitFor::Model::StashHelper);
with    q(CatalystX::Usul::TraitFor::Model::QueryingRequest);
with    q(CatalystX::Usul::TraitFor::Captcha);

has 'default_realm'      => is => 'ro',   isa => NonEmptySimpleStr,
   required              => TRUE;

has 'email_attributes'   => is => 'ro',   isa => HashRef,
   default               => sub {
      { content_type     => q(text/html),
        template         => q(new_account.tt),
        template_attrs   => { ABSOLUTE => TRUE, }, } };

has 'register_authorise' => is => 'ro',   isa => Bool, default => FALSE;

has 'role_model_class'   => is => 'ro',   isa => NonEmptySimpleStr,
   required              => TRUE;

has 'rprtdir'            => is => 'ro',   isa => Directory, coerce => TRUE,
   required              => TRUE;

has 'template_dir'       => is => 'ro',   isa => Directory, coerce => TRUE,
   required              => TRUE;

has 'user_model_classes' => is => 'ro',   isa => HashRef,
   default               => sub { {} };


has '_file'     => is => 'lazy', isa => FileClass,
   default      => sub { Class::Usul::File->new( builder => $_[ 0 ]->usul ) },
   handles      => [ qw(io) ], init_arg => undef, reader => 'file';

has '_fs_model' => is => 'lazy', isa => Object,
   default      => sub { $_[ 0 ]->context->model( q(FileSystem) ) },
   init_arg     => undef, reader => 'fs_model';

sub COMPONENT {
   my ($class, $app, $attr) = @_; my $ac = $app->config || {};

   merge_attributes $attr, $class->config, $ac,
      [ qw(auth_component role_model_class rprtdir template_dir) ];

   my $comp    = delete $attr->{auth_component} || q(Plugin::Authentication);
   my $realms  = $ac->{ $comp }->{realms};
   my %classes = map   { $_ => $realms->{ $_ }->{store}->{model_class} }
                 keys %{ $realms };

   $attr->{user_model_classes}   = \%classes;
   $attr->{default_realm     }   = $ac->{ $comp }->{default_realm};
   $attr->{rprtdir           } ||= catdir( $ac->{root}, qw(reports)   );
   $attr->{template_dir      } ||= catdir( $ac->{root}, qw(templates) );

   return $class->next::method( $app, $attr );
}

{  my $user_cache = {}; my $role_cache = {};

   sub build_per_context_instance {
      my ($self, $c, @args) = @_; my $class = blessed $self;

      my $is_dirty = exists $user_cache->{ $class } ? FALSE : TRUE;
      my $clone    = $self->next::method( $c, @args );
      my $attr     = { %{ $clone->domain_attributes },
                       builder    => $clone->usul,
                       cache      => $user_cache->{ $class } ||= {},
                       locale     => $c->stash->{language},
                       role_cache => $role_cache->{ $class } ||= {}, };

      $attr->{dbic_user_class} and $attr->{dbic_user_model}
         = $c->model( $attr->{dbic_user_class} );

      $attr->{dbic_role_class} and $attr->{dbic_role_model}
         = $c->model( $attr->{dbic_role_class} );

      $attr->{dbic_user_roles_class} and $attr->{dbic_user_roles_model}
         = $c->model( $attr->{dbic_user_roles_class} );

      $clone->domain_model( $clone->domain_class->new( $attr ) );
      $is_dirty and $clone->invalidate_cache;
      return $clone;
   }
}

sub activate_account_form {
   my ($self, $file) = @_; my $dm = $self->domain_model;

   try        { $self->add_result_msg( $dm->activate_account( $file ) ) }
   catch ($e) { return $self->add_error( $e ) }

   return;
}

sub authenticate {
   # Try to authenticate the supplied user info with each defined realm
   my $self = shift; my $c = $self->context; my $s = $c->stash;

   $s->{query_scrubbing} = TRUE;

   my $realm    = $self->query_value( q(realm)  );
   my $username = $self->query_value( q(user)   );
   my $pass     = $self->query_value( q(passwd) );

   ($username and $pass) or throw 'Id and/or password not set';

   my $userinfo = { username => $username, password => $pass };
   my @realms   = $realm ? ( $realm ) : sort keys %{ $c->auth_realms };

   for $realm (@realms) {
      $realm eq q(default) and next; my $user;

      ($user = $c->find_user( $userinfo, $realm )
          and $user->username eq $username) or next;

      $user = $c->authenticate( $userinfo, $realm ) or next;

      $user->has_password_expired
         and return $self->_user_password_expired( $c, $username, $realm );

      return $self->_user_authenticated( $c, $username, $realm, $user );
   }

   $c->stash( override => TRUE ); __logout( $c );

   throw error => 'Login id ([_1]) and password not recognised',
         args  => [ $username ];
   return; # Never reached
}

sub authentication_form {
   my ($self, $username) = @_; my $s = $self->context->stash;

   my $form = $s->{form}->{name}; $s->{pwidth} += 3;

   ($username ||= $s->{user}->username) =~ s{ \A unknown \z }{}msx;

   $self->clear_form ( { firstfld => $username ? "${form}.passwd"
                                               : "${form}.user",
                         heading  => $self->loc( "${form}.header" ) } );
   $self->add_field  ( { default  => $username, id => "${form}.user" } );
   $self->add_field  ( { id       => "${form}.passwd" } );
   $self->add_field  ( { id       => "${form}.login_text" } );
   $self->add_buttons( qw(Login) );
   return;
}

sub change_password {
   my $self = shift; my $c = $self->context; my $s = $c->stash;

   $s->{query_scrubbing} = TRUE;

   my @fields = ( qw(user oldPass newPass1 newPass2) );
   my $fields = $self->check_form( $self->query_value_by_fields( @fields ) );
   my @args   = ( map { $fields->{ $_ } } qw(user oldPass newPass1) );
   my $msg    = $self->loc( $self->domain_model->change_password( @args ) );
   my $mid    = $c->set_status_msg( $msg );

   if ($s->{user}->username eq q(unknown)) {
      $c->stash( wanted          => $s->{action_paths}->{authenticate},
                 redirect_params => [ $fields->{user}, { mid => $mid } ] );
   }
   else {
      my $wanted   = $c->session->{wanted} and $c->session( wanted => NUL );
         $wanted ||= $c->controller( q(Root) )->default_namespace;

      $c->stash( wanted => $wanted, redirect_params => [ { mid => $mid } ] );
   }

   return TRUE;
}

sub change_password_form {
   my ($self, $username) = @_; my $c = $self->context;

   my $s      = $c->stash; $s->{pwidth} -= 10;
   my $form   = $s->{form}->{name};
   my $realm  = $s->{user_realm};
   my @realms = grep { $_ ne q(default) } sort keys %{ $c->auth_realms };

   ($username ||= $s->{user}->username) =~ s{ unknown }{}mx;

   $self->clear_form( { firstfld => $username ? "${form}.oldPass"
                                              : "${form}.user" } );
   $self->add_field ( { default  => $realm,
                        id       => "${form}.realm",
                        values   => [ NUL, @realms ] } );

   if ($realm) {
      $self->add_field  ( { id => "${form}.user", default => $username } );
      $self->add_field  ( { id => "${form}.oldPass"  } );
      $self->add_field  ( { id => "${form}.newPass1" } );
      $self->add_buttons( qw(Set) );
   }

   my $id = $form.($realm && $username ? q(.select) : q(.selectUnknown));

   $self->group_fields( { id => $id } );
   return;
}

sub create_or_update {
   my $self     = shift;
   my @fields   = ( qw( username profile first_name last_name
                        location work_phone email_address home_phone
                        project homedir shell populate ) );
   my $fields   = $self->query_value_by_fields( @fields );
   my $username = $fields->{username} or throw 'User not specified';
   my $method   = $self->is_user( $username ) ? q(update) : q(create);
   my $dm       = $self->domain_model;
   my $aliases  = $dm->aliases;

   $fields->{active       }   = TRUE;
   $fields->{alias_name   }   = $username;
   $fields->{first_name   }   = my $first = ucfirst $fields->{first_name};
   $fields->{last_name    }   = my $last  = ucfirst $fields->{last_name };
   $fields->{email_address} ||= $aliases->email_address( "${first}.${last}" );
   $fields->{owner        }   = $self->context->stash->{user}->username;
   $fields->{comment      }   = [ 'Local user' ];
   $fields->{recipients   }   = [ $fields->{email_address} ];

   $self->add_result_msg( $dm->$method( $self->check_form( $fields ) ) );

   return $username;
}

sub delete {
   my $self = shift;

   if (my $username = $self->query_value( q(user) )) {
      $self->add_result_msg( $self->domain_model->delete( $username ) );
   }
   else { $self->add_error( 'User not specified' ) }

   return TRUE;
}

sub find_user {
   return shift->domain_model->find_user( @_ );
}

sub get_user_model_class {
   my ($self, $default, $realm) = @_;

   $realm ||= $self->default_realm; my $user_class;

   exists $self->user_model_classes->{ $realm }
      or $realm = $self->default_realm;

   unless ($realm and $user_class = $self->user_model_classes->{ $realm }) {
      my $msg = 'Defaulting identity model [_1]';

      $self->log->warning( $self->loc( $msg, $user_class = $default ) );
   }

   return ($user_class, $realm);
}

sub invalidate_cache {
   $_[ 0 ]->domain_model->invalidate_cache; return;
}

sub is_user {
   return shift->domain_model->is_user( @_ );
}

sub list {
   return shift->domain_model->list( @_ );
}

sub logout {
   my ($self, $args) = @_; $args ||= {};

   my $user  = $args->{user} or return FALSE; my $c = $self->context;

   my $realm = $user->auth_realm; my $username = $user->username;

   my $msg   = $args->{message} || 'User [_1] logged out from realm [_2]';

   $self->log->info( $msg = $self->loc( $msg, $username, $realm ) );
   $args->{no_redirect} or $c->stash( redirect_params => [ {
      mid => $c->set_status_msg( $msg ) } ] );
   __logout( $c );
   return TRUE;
}

sub profiles {
   return $_[ 0 ]->domain_model->profiles;
}

sub purge {
   my $self = shift; my $selected = $self->query_array( q(file) );

   $selected->[ 0 ] or throw 'Nothing selected';

   for my $username (@{ $selected }) {
      $self->add_result_msg( $self->domain_model->delete( $username ) );
   }

   return TRUE;
}

sub register {
   my ($self, $path) = @_; my $c = $self->context; my $s = $c->stash;

   my $dm = $self->domain_model; my $fields;

   unless ($path) {
      my @fields = ( qw(email_address first_name last_name newPass1 newPass2
                        work_phone home_phone location project security) );

      $fields = $self->query_value_by_fields( @fields );
      $fields = $self->_validate_registration( $s, $fields );

      if ($self->register_authorise) {
         $self->add_result_msg( $dm->register_authorisation( $fields ) );
         return TRUE;
      }
   }

   my $attr     = $self->email_attributes;
   my $activate = $s->{action_paths}->{activate_account};
   my $key      = $activate ? substr create_token, 0, 32 : undef;
   my $link     = $key ? $c->uri_for_action( $activate, $key ) : undef;
   my $subject  = $self->loc( q(accountVerification), $c->config->{name} );
   my $post     = {
      attributes      => {
         charset      => $attr->{encoding} || $self->encoding,
         content_type => $attr->{content_type} },
      from            => q(UserRegistration@).($s->{domain} || $s->{host}),
      mailer          => $s->{mailer},
      mailer_host     => $s->{mailer_host},
      stash           => {
         app_name     => $c->config->{name},
         link         => $link,
         title        => $subject, },
      subject         => $subject,
      template        => catfile( $self->template_dir, $attr->{template} ),
      template_attrs  => $attr->{template_attrs}, };

   my $args = { key => $key, path => $path, post => $post };

   $self->add_result_msg( $dm->register( $args, $fields ) );
   return TRUE;
}

sub register_form {
   my $self = shift; my $c = $self->context; my $s = $c->stash;

   my $form = $s->{form}->{name};
   my $uri  = $c->uri_for_action( $s->{action_paths}->{captcha} );

   $self->clear_form  ( { firstfld => "${form}.first_name"    } );
   $self->add_field   ( { id       => "${form}.first_name"    } );
   $self->add_field   ( { id       => "${form}.last_name"     } );
   $self->add_field   ( { id       => "${form}.email_address" } );
   $self->add_field   ( { id       => "${form}.newPass1"      } );
   $self->add_field   ( { id       => "${form}.work_phone"    } );
   $self->add_field   ( { id       => "${form}.location"      } );
   $self->add_field   ( { id       => "${form}.project"       } );
   $self->add_field   ( { id       => "${form}.home_phone"    } );
   $self->add_field   ( { name     => "${form}.captcha", text => $uri } );
   $self->add_field   ( { id       => "${form}.security"      } );
   $self->group_fields( { id       => "${form}.legend"        } );
   $self->add_buttons ( qw(Insert) );
   return;
}

sub set_password {
   my $self      = shift;
   my $dm        = $self->domain_model;
   my $user      = $self->query_value( q(user) ) or throw 'User not specified';
   my $ptype     = $self->query_value( q(p_type) ) || 1;
   my $password  = $self->query_value( q(p_default) );
   my $encrypted = FALSE;

   if ($ptype == 4) {
      $password = $self->query_value( q(p_generated) );
   }
   elsif ($ptype == 3) {
      my $p_word1 = $self->query_value( q(p_word1) );
      my $p_word2 = $self->query_value( q(p_word2) );

     ($p_word1 and $p_word2) or throw 'Passwords not specified';
      $p_word1 eq  $p_word2  or throw 'Passwords are not the same';
      $password = $p_word1;
   }
   elsif ($ptype == 2) {
      $password = q(*).$self->query_value( q(p_value) ).q(*); $encrypted = TRUE;
   }

   $self->add_result_msg( $dm->set_password( $user, $password, $encrypted ) );
   return TRUE;
}

sub user_fill {
   my $self  = shift;
   my $s     = $self->context->stash;
   my $fill  = $s->{fill} = {};
   my $first = $fill->{first_name} = $self->query_value( q(first_name) );
   my $last  = $fill->{last_name } = $self->query_value( q(last_name) );

   return $s->{override} = TRUE;
}

sub user_manager_form {
   my ($self, $username) = @_; my $c = $self->context; my $s = $c->stash;

   my $uref = {}; my $is_new = ($username || '') eq $s->{newtag} ? TRUE : FALSE;

   # Retrieve data from models
   try        { $uref = $self->domain_model->get_user_data( $s, $username ) }
   catch ($e) { return $self->add_error( $e ) }

   # Add elements to form
   my $form   = $s->{form}->{name}; my $realm = $s->{user_realm};

   my @realms = grep { $_ ne q(default) } sort keys %{ $c->auth_realms };

   $self->clear_form( { firstfld => $form.($realm ? '.user' : '.realm') } );
   $self->add_field ( { default  => $realm,
                        id       => "${form}.realm",
                        values   => [ NUL, @realms ] } );

   if ($realm) {
      $self->add_field( { default => $username,
                          id      => "${form}.user",
                          values  => $uref->{users} } );

      if ($is_new) {
         $self->add_field( { default => $uref->{profile_name},
                             id      => "${form}.profile",
                             labels  => $uref->{labels},
                             values  => $uref->{profiles} } );
      }
      else {
         $self->add_hidden( q(profile), $uref->{profile_name} );

         if ($uref->{role}) {
            my $text  = $self->loc( "${form}.pgroup" );
               $text .= ($uref->{labels}->{ $uref->{role} } || NUL);
               $text .= ' ('.$uref->{role}.') ';

            $self->add_field( { id => "${form}.pgroup", text => $text } );
         }
      }
   }

   $self->group_fields( { id => "${form}.select" } );

   ($username and lc $username ne q(all)) or return;
   $is_new and not $uref->{profile_name} and return;

   $self->add_field( { default => $uref->{first_name},
                       id      => "${form}.first_name" } );
   $self->add_field( { default => $uref->{last_name},
                       id      => "${form}.last_name"  } );

   if ($is_new) { # Create new account
      if ($uref->{name}) {
         $self->add_field( { default => $uref->{name},
                             id      => "${form}.username" } );
         $self->add_buttons( qw(Insert) );
      }
      else {
         $self->add_field( { id => "${form}.afill" } );
         $self->add_buttons( qw(Fill) );
      }
   }
   else { # Edit existing account
      $self->add_hidden ( q(username), $username );
      $self->add_buttons( qw(Save Delete) );
   }

   unless ($uref->{name}) {
      $self->group_fields( { id => "${form}.edit" } ); return;
   }

   $self->add_field( { default => $uref->{email_address},
                       id      => "${form}.email_address" } );
   $self->add_field( { default => $uref->{location},
                       id      => "${form}.location"      } );
   $self->add_field( { default => $uref->{work_phone},
                       id      => "${form}.work_phone"    } );
   $self->add_field( { default => $uref->{home_phone},
                       id      => "${form}.home_phone"    } );
   $self->add_field( { default => $uref->{project},
                       id      => "${form}.project"       } );

   if ($uref->{supports}->{fields_homedir}
       and $uref->{homedir} ne $uref->{common_home}) {
      $is_new and $self->add_field( { label => SPC, id => "${form}.populate" });
      $self->add_field( { default  => $uref->{homedir},
                          id       => "${form}.homedir",
                          readonly => $is_new ? FALSE : TRUE } );
   }

   defined $uref->{shells}
      and $self->add_field( { default => $uref->{shell},
                              id      => "${form}.shell",
                              values  => $uref->{shells} } );

   $self->group_fields( { id => "${form}.edit" } );
   return;
}

sub user_report {
   my ($self, $type) = @_;
   my $dm    = $self->domain_model;
   my $s     = $self->context->stash;
   my $stamp = time2str( '%Y%m%d%H%M' );
   my $path  = catfile( $self->rprtdir, "userReport_${stamp}.csv" );

   $self->add_result( $dm->user_report( {
      debug => $s->{debug}, path => $path, type => $type } ) );
   return TRUE;
}

sub user_report_form {
   my ($self, $id) = @_; my ($dir, $key, $pat);

   my $c     = $self->context;
   my $s     = $c->stash; $s->{pwidth} -= 10;
   my $form  = $s->{form}->{name};
   my $realm = $s->{user_realm};

   if ($dir = $self->query_value( q(dir) )) { $pat = q(.*); $key = undef }
   else {
      $dir = $self->{rprtdir}; $pat = q(userReport*);
      $key = sub { return (split m{ \. }mx, (split m{ _ }mx, $_[0])[1])[0] };
   }

   $self->clear_form;

   if ($id) {
      my $path = catfile( $dir, "userReport_${id}.csv" );

      $self->add_field( { path => $path, id => "${form}.file" } );
      $self->add_field( { id   => "${form}.keynote" } );
      $self->add_buttons( qw(List Purge) );
   }
   else {
      my @realms = grep { $_ ne q(default) } sort keys %{ $c->auth_realms };

      $self->add_field( { default => $realm,
                          id      => "${form}.realm",
                          values  => [ NUL, @realms ] } );
      $self->add_buttons( qw(Execute) );

      try {
         my $subdir = $self->fs_model->list_subdirectory( {
            action   => $s->{form}->{action},
            assets   => $s->{assets},
            dir      => $dir,
            make_key => $key,
            pattern  => qr{ $pat }mx } );
         $self->add_field( { data => $subdir, type => q(table) } );
      }
      catch ($e) { return $self->add_error( $e ) }
   }

   my $grp_id = $form.($id ? q(.select_purge) : q(.select_view));

   $self->group_fields( { id => $grp_id } );
   return;
}

sub user_security_form {
   my ($self, $username) = @_; my $c = $self->context; my $s = $c->stash;

   my $sec_ref = {}; my $p_type = $self->query_value( q(p_type) ) || 1;

   try {
      $sec_ref = $self->domain_model->get_security_data( $username, $p_type );
   }
   catch ($e) { return $self->add_error( $e ) }

   my $form   = $s->{form}->{name};
   my $realm  = $s->{user_realm};
   my @realms = grep { $_ ne q(default) } sort keys %{ $c->auth_realms };

   $s->{fullname} = $sec_ref->{fullname};
   $s->{messages}->{p_default  }->{text} = $sec_ref->{passwd};
   $s->{messages}->{p_generated}->{text} = $sec_ref->{generated};

   $self->clear_form  ( { firstfld => $form.($realm ? q(.user) : q(.realm)) } );
   $self->add_hidden  ( q(p_default),   $sec_ref->{passwd   } );
   $self->add_hidden  ( q(p_generated), $sec_ref->{generated} );
   $self->add_field   ( { default  => $realm,
                          id       => "${form}.realm",
                          values   => [ NUL, @realms ] } );
   $realm and
      $self->add_field( { default  => $username,
                          id       => "${form}.user",
                          values   => $sec_ref->{users} } );
   $self->group_fields( { id       => "${form}.select" } );

   ($username and $username ne $s->{newtag} and lc $username ne q(all))
      or return;

   my $labels = [ SPC.$self->loc( "${form}.set_password_option1" ),
                  SPC.$self->loc( "${form}.set_password_option2" ),
                  SPC.$self->loc( "${form}.set_password_option3" ),
                  SPC.$self->loc( "${form}.set_password_option4" ) ];

   $sec_ref->{passwd} and
      $self->add_field( { id       => "${form}.p_default",
                          prompt   => $labels->[ 0 ],
                          stepno   => $sec_ref->{prompts  }->[ 0 ],
                          text     => $sec_ref->{passwd   }, } );
   $self->add_field   ( { id       => "${form}.p_generated",
                          prompt   => $labels->[ 3 ],
                          stepno   => $sec_ref->{prompts  }->[ 3 ],
                          text     => $sec_ref->{generated}, } );
   $self->add_field   ( { default  => $self->query_value( q(p_value) ) || NUL,
                          id       => "${form}.p_value",
                          prompt   => $labels->[ 1 ],
                          stepno   => $sec_ref->{prompts  }->[ 1 ],
                          values   => [ qw(disabled left nologin unused) ] } );
   $self->add_field   ( { id       => "${form}.p_word1",
                          prompt   => $labels->[ 2 ],
                          stepno   => $sec_ref->{prompts  }->[ 2 ], } );
   $self->group_fields( { id       => "${form}.set_password" } );
   $self->add_field   ( { all      => $sec_ref->{all_roles},
                          current  => $sec_ref->{roles    },
                          id       => "${form}.groups" } );
   $self->group_fields( { id       => "${form}.secondary" } );
   $self->add_buttons ( qw(Set Update) );
   return;
}

# Private methods
sub _user_authenticated {
   my ($self, $c, $username, $realm, $user) = @_;

   my $msg = 'User [_1] logged in to realm [_2]';

   $self->log->info( $msg = $self->loc( $msg, $username, $realm ) );

   $user->should_warn_of_expiry
      and $msg = "${msg}\n".$self->loc( 'Password will expire soon' );

   my $wanted   = $c->session->{wanted} and $c->session( wanted => NUL );
      $wanted ||= $c->controller( q(Root) )->default_namespace;

   $c->stash( realm           => $realm,
              redirect_params => [ { mid => $c->set_status_msg( $msg ) } ],
              wanted          => $wanted, );
   return;
}

sub _user_password_expired {
   my ($self, $c, $username, $realm) = @_;

   my $msg    = 'User [_1] password expired in realm [_2]';
   my $wanted = $c->stash->{action_paths}->{change_password};

   $self->log->info( $msg = $self->loc( $msg, $username, $realm ) );

   $c->stash( override        => TRUE,
              realm           => $realm,
              redirect_params => [ $username, {
                 mid          => $c->set_error_msg( $msg ),
                 realm        => $realm, } ],
              wanted          => $wanted, );
   __logout( $c );
   return;
}

sub _validate_registration {
   my ($self, $s, $fields) = @_;

   $self->validate_captcha( delete $fields->{security} );
   $self->clear_captcha_string;
   $fields->{active  } = FALSE;
   $fields->{password} = $fields->{newPass1};
   $fields->{profile } = $s->{register}->{profile};
   $fields = $self->check_form( $fields );

   $fields->{newPass1} eq $fields->{newPass2}
      or throw 'Passwords are not the same';

   delete $fields->{newPass1}; delete $fields->{newPass2}; my $profile;

   $fields->{profile} and $profile = $self->profiles->find( $fields->{profile});

   my $prefix = $profile ? $profile->prefix : NUL;

   $fields->{username} = $self->domain_model->get_new_user_id
      ( $fields->{first_name}, $fields->{last_name}, $prefix );

   return $fields;
}

# Private functions
sub __logout {
   my $c = shift; $c->session_expire_key( __user => 0 ); $c->logout; return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Users - Catalyst user model

=head1 Version

Describes v0.14.$Rev: 1 $

=head1 Synopsis

   package YourApp;

   use Catalyst qw(ConfigComponents...);

   __PACKAGE__->config(
     'Model::UsersDBIC'          => {
        parent_classes           => 'CatalystX::Usul::Model::Users',
        domain_attributes        => {
           dbic_user_class       => 'Authentication::Users',
           dbic_role_class       => 'Authentication::Roles',
           dbic_user_roles_class => 'Authentication::UserRoles',
           role_class            => 'CatalystX::Usul::Roles::DBIC', },
        domain_class             => 'CatalystX::Usul::Users::DBIC',
        role_model_class         => 'RolesDBIC',
        template_attributes      => {
           COMPILE_DIR           => '__appldir(var/tmp)__',
           INCLUDE_PATH          => '__appldir(var/root/templates)__', }, }, );

=head1 Description

Forms and actions for user maintenance

=head1 Configuration and Environment

Defines the following list of attributes;

=over 3

=item C<default_realm>

A required non-empty simple string. The name of the default
authentication realm

=item C<email_attributes>

A hash ref used to provide static config for the user registration email

=item C<register_authorise>

A boolean which defaults to false. If true then new user registrations
require authorisation before the account is created

=item C<register_queue_path>

Pathname to the file which contains the list of pending user registrations

=item C<role_model_class>

Class of the role model

=item C<rprtdir>

Directory location in the filesystem of the user reports

=item C<template_dir>

Path to the directory which contains the user registration email template

=item C<user_model_classes>

Hash ref containing the map between realm names and storage model classes.
Initialised by L</COMPONENT>

=back

=head1 Subroutines/Methods

=head2 COMPONENT

Constructor initialises default attribute values

=head2 build_per_context_instance

Completes the initialisation process on a per request basis

=head2 activate_account_form

   $self->activate_account_form( $filename );

Checks for the existence of the file created by the L</register> method. If
it exists it contains the username of a recently created account. The
accounts I<active> attribute is set to true, enabling the account

=head2 authenticate

   $self->authenticate;

Calls L<authenticate|CatalystX::Usul::Users/authenticate> in the domain model.

Authenticate the user. If another controller was wanted and the user
was forced to authenticate first, redirect the session to the
originally requested controller. This was stored in the session by the
auto method prior to redirecting to the authentication controller
which forwarded to here

Redirects to the change password form it the users password has expired

=head2 authentication_form

   $self->authentication_form( $username );

Adds fields to the stash for the login screen

=head2 change_password

   $bool = $self->change_password;

Method to change the users password. Throws exceptions for field
constraint failures and if the passwords entered are not the same

=head2 change_password_form

   $self->change_password_form( $username );

Adds field data to the stash for the change password screen. Allows users
to change their own password

=head2 create_or_update

   $username = $self->create_or_update;

Method to create a new account or update an existing one. Throws exceptions
for field constraint failures. Calls methods on the domain model to do the
actual work

=head2 delete

   $bool = $self->delete;

Deletes the selected account

=head2 find_user

   $user_object = $self->find_user( $username, $verbose );

Calls L<find_user|CatalystX::Usul::Users/find_user> on the domain model.
The verbose flag maximises the information returned about the user

=head2 get_user_model_class

   ($model_class, $realm) = $self->get_user_model_class( $default, $realm );

Return the user model class for the specified realm. If not found return
the default user model

=head2 invalidate_cache

   $self->invalidate_cache;

Invalidates the user cache in the domain model

=head2 is_user

   $bool = $self->is_user( $username );

Calls L<is_user|CatalystX::Usul::Users/is_user> in the domain model

=head2 list

Proxy the call to the domain method

=head2 logout

   $bool = $self->logout( $args );

Expires the user object on the session store. The C<$args> hash takes an
optional C<message> attribute and an optional C<no_redirect> attribute

=head2 profiles

   $profile_object = $self->profiles;

Returns the domain model's profiles object

=head2 purge

   $bool = $self->purge;

Delete the list of selected accounts

=head2 register

   $bool = $self->register( [ $path ] );

Create the self registered account. The account is created in an inactive
state and a confirmation email is sent

=head2 register_form

   $self->register_form( $captcha_action_path );

Added the fields to the stash for the self registration screen. Users can
use this screen to create their own accounts

=head2 set_password

   $bool = $self->set_password;

Sets the users password to a given value

=head2 user_fill

   $bool = $self->user_fill;

Sets the I<fill> attribute of the stash in response to clicking the
auto fill button

=head2 user_manager_form

   $self->user_manager_form( $username );

Adds fields to the stash for the user management screen. Administrators can
create new accounts or modify the details of existing ones

=head2 user_report

   $bool = $self->user_report( $type );

Creates a report of the user accounts in this realm

=head2 user_report_form

   $self->user_report_form( $id );

View either the list of available account reports or the contents of a
specific report

=head2 user_security_form

   $self->user_security_form( $username );

Add fields to the stash for the security administration screen. From here
administrators can reset passwords and change the list of roles to which
the selected user belongs

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<CatalystX::Usul::TraitFor::Captcha>

=item L<CatalystX::Usul::TraitFor::Email>

=item L<CatalystX::Usul::Model>

=item L<Class::Usul::Time>

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
