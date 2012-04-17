# @(#)$Id: Users.pm 1181 2012-04-17 19:06:07Z pjf $

package CatalystX::Usul::Model::Users;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.7.%d', q$Rev: 1181 $ =~ /\d+/gmx );
use parent qw(CatalystX::Usul::Model
              CatalystX::Usul::Email CatalystX::Usul::Captcha);

use CatalystX::Usul::Constants;
use CatalystX::Usul::Functions qw(create_token is_member throw);
use CatalystX::Usul::Shells;
use CatalystX::Usul::Time;
use MRO::Compat;
use TryCatch;

__PACKAGE__->config( activate_path       => q(entrance/activate_account),
                     app_name            => NUL,
                     email_content_type  => q(text/html),
                     email_template      => q(new_account.tt),
                     rprtdir             => q(root/reports),
                     sessdir             => q(hist),
                     shells_attributes   => {},
                     shells_class        => q(CatalystX::Usul::Shells),
                     template_attributes => {}, );

__PACKAGE__->mk_accessors( qw(activate_path app_name auth_realms
                              domain_cache email_content_type
                              email_template fs_model
                              register_queue_path roles rprtdir
                              sessdir shells shells_attributes
                              shells_class template_attributes) );

sub COMPONENT {
   my ($class, $app, $config) = @_; my $ac = $app->config || {};

   my $rprtdir = $class->catdir( $ac->{vardir}, $class->config->{rprtdir} );
   my $sessdir = $class->catdir( $ac->{vardir}, $class->config->{sessdir} );

   $config->{app_name} ||= $ac->{name   };
   $config->{rprtdir } ||= $ac->{rprtdir} || $rprtdir;
   $config->{sessdir } ||= $ac->{sessdir} || $sessdir;

   my $new = $class->next::method( $app, $config );

   $new->ensure_class_loaded( $new->domain_class );
   $new->domain_cache( { dirty => TRUE } );
   return $new;
}

sub build_per_context_instance {
   my ($self, $c, @rest) = @_; my $class;

   my $clone = $self->next::method( $c, @rest );
   my $attrs = { %{ $clone->domain_attributes || {} },
                 sessdir => $clone->sessdir,
                 cache   => $clone->domain_cache, };
   my $dm    = $clone->domain_model( $clone->domain_class->new( $c, $attrs ) );

   $clone->fs_model( $c->model( q(FileSystem) ) );
   $attrs = { %{ $clone->shells_attributes || {} }, };
   $clone->shells( $clone->shells_class->new( $c, $attrs ) );
   return $clone;
}

sub activate_account {
   my ($self, $key) = @_;

   my $path = $self->io( $self->catfile( $self->sessdir, $key ) );

   $path->is_file
      or return $self->add_error_msg( 'Path [_1] not found', $path );

   my $user = $path->chomp->lock->getline
      or return $self->add_error_msg( 'Path [_1] contained no data', $path );

   $path->unlink;

   try        { $self->domain_model->activate_account( $user ) }
   catch ($e) { return $self->add_error( $e ) }

   $self->add_result_msg( 'Account [_1] activated', $user );
   return;
}

sub authenticate {
   # Try to authenticate the supplied user info with each defined realm
   my $self = shift; my $c = $self->context; my $s = $c->stash;

   my ($msg, $user_ref, $wanted); $self->scrubbing( TRUE );

   my $realm = $self->query_value( q(realm)  );
   my $user  = $self->query_value( q(user)   );
   my $pass  = $self->query_value( q(passwd) );

   unless ($user and $pass) {
      $s->{user} = q(unknown); throw 'Id and/or password not set';
   }

   my $userinfo = { username => $user, password => $pass };
   my @realms   = $realm ? ( $realm ) : sort keys %{ $c->auth_realms };

   for $realm (@realms) {
      $realm eq q(default) and next;
      ($user_ref = $c->find_user( $userinfo, $realm )
       and $user_ref->username eq $user) or next;
      $c->authenticate( $userinfo, $realm ) or next;

      $msg = 'User [_1] logged in to realm [_2]';
      $self->log_info( $self->loc( $msg, $user, $realm ) );

      if ($c->can( q(session) )) {
         $c->session->{last_visit} = time;
         $s->{wanted} = $c->session->{wanted};
         $c->session->{wanted} = NUL;
      }

      $s->{wanted} ||= $c->controller( q(Root) )->default_namespace;
      $s->{realm }   = $realm;
      return;
   }

   $c->logout;
   $s->{override} = TRUE;
   $s->{user    } = q(unknown);
   $c->can( q(session) ) and $c->session_expire_key( __user => FALSE );
   $msg = 'Login id ([_1]) and password not recognised';
   throw error => $msg, args => [ $user ];
   return; # Never reached
}

sub authentication_form {
   my ($self, $user) = @_; my $s = $self->context->stash;

   my $form = $s->{form}->{name}; $s->{pwidth} += 3;

   ($user ||= $s->{user}) =~ s{ \A unknown \z }{}msx;

   $self->clear_form ( { firstfld => $form.q(.user),
                         heading  => $self->loc( $form.q(.header) ) } );
   $self->add_field  ( { default  => $user, id => $form.q(.user) } );
   $self->add_field  ( { id       => $form.q(.passwd) } );
   $self->add_field  ( { id       => $form.q(.login_text) } );
   $self->add_buttons( qw(Login) );
   return;
}

sub change_password {
   my $self = shift; $self->scrubbing( TRUE );
   my @flds = ( qw(user oldPass newPass1 newPass2) );
   my $flds = $self->check_form( $self->query_value_by_fields( @flds ) );

   $self->domain_model->change_password
      ( $flds->{user}, $flds->{oldPass}, $flds->{newPass1} );
   $self->add_result_msg( 'User [_1] password changed', $flds->{user} );
   return TRUE;
}

sub change_password_form {
   my ($self, $user) = @_;

   my $s      = $self->context->stash; $s->{pwidth} -= 10;
   my $form   = $s->{form}->{name};
   my $realm  = $s->{user_realm};
   my $values = [ q(), sort keys %{ $self->auth_realms } ];

   ($user ||= $s->{user}) =~ s{ unknown }{}mx;

   $self->clear_form( { firstfld => $form.q(.user) } );
   $self->add_field ( { default  => $realm,
                        id       => $form.q(.realm),
                        values   => $values } );

   if ($realm) {
      $self->add_field  ( { ajaxid  => $form.q(.user), default => $user } );
      $self->add_field  ( { id      => $form.q(.oldPass)  } );
      $self->add_field  ( { ajaxid  => $form.q(.newPass1) } );
      $self->add_buttons( qw(Set) );
   }

   my $id = $form.($realm && $user ? q(.select) : q(.selectUnknown));

   $self->group_fields( { id => $id } );
   return;
}

sub create_or_update {
   my $self   = shift;
   my @fields = ( qw(username profile first_name last_name
                     location work_phone email_address home_phone
                     project homedir shell populate) );
   my $fields = $self->query_value_by_fields( @fields );
   my $user   = $fields->{username} or throw 'User not specified';
   my $method = $self->is_user( $user ) ? q(update) : q(create);
   my $model  = $self->domain_model;

   $fields->{active       }   = TRUE;
   $fields->{alias_name   }   = $fields->{username};
   $fields->{first_name   }   = ucfirst $fields->{first_name};
   $fields->{last_name    }   = ucfirst $fields->{last_name };
   $fields->{email_address} ||= $model->make_email_address( $user );
   $fields->{owner        }   = $self->context->stash->{user};
   $fields->{comment      }   = [ 'Local user' ];
   $fields->{recipients   }   = [ $fields->{email_address} ];
   $fields                    = $self->check_form( $fields );

   $self->add_result_msg( $model->$method( $fields ), $user );
   return $user;
}

sub delete {
   my $self = shift;
   my $user = $self->query_value( q(user) ) or throw 'User not specified';

   $self->add_result_msg( $self->domain_model->delete( $user ), $user );
   return TRUE;
}

sub find_user {
   my ($self, @rest) = @_; return $self->domain_model->find_user( @rest );
}

sub get_features {
   my ($self, @rest) = @_; return $self->domain_model->get_features( @rest );
}

sub get_primary_rid {
   my ($self, $user) = @_; return $self->domain_model->get_primary_rid( $user);
}

sub get_users_by_rid {
   my ($self, $rid) = @_; return $self->domain_model->get_users_by_rid( $rid );
}

sub is_user {
   my ($self, $user) = @_; return $self->domain_model->is_user( $user );
}

sub profiles {
   return shift->domain_model->profiles;
}

sub purge {
   my $self  = shift;
   my $nrows = $self->query_value( q(__nrows) )
      or throw 'Account not specified';

   for my $rno (0 .. $nrows - 1) {
      my $user = $self->query_value( q(select).$rno ) or next;
      my $msg  = $self->domain_model->delete( $user );

      $self->add_result_msg( $msg, $user );
   }

   return TRUE;
}

sub register {
   my ($self, $path) = @_; my $c = $self->context; my $s = $c->stash;

   my $code = $self->query_value( q(security) ); my $fields;

   $self->validate_captcha( $code )
      or throw error => 'Security code [_1] incorrect', args => [ $code ];

   unless ($path) {
      my @fields = ( qw(email_address first_name last_name newPass1 newPass2
                        work_phone home_phone location project) );

      $fields             = $self->query_value_by_fields( @fields );
      $fields->{active  } = FALSE;
      $fields->{password} = $fields->{newPass1};
      $fields->{profile } = $s->{register}->{profile};
   }

   if (not $path and $self->register_queue_path) {
      $self->_register_write_queue( $fields );
      # TODO:  Add email message to authorising authority
      $self->add_result_msg( 'Awaiting authorisation', $fields->{email} );
      return TRUE;
   }

   try {
      $self->lock->set( k => q(register_user) );
      $path and $fields = $self->_register_read_queue( $path );
      $fields = $self->_register_validation( $fields );
      $self->domain_model->create( $fields );
      $self->_register_verification_email( $fields );
      $self->add_result_msg( 'User [_1] account created', $fields->{username} );
      $self->lock->reset( k => q(register_user) );
   }
   catch ($e) { $self->lock->reset( k => q(register_user) ); throw $e }

   return TRUE;
}

sub register_form {
   my ($self, $captcha_action) = @_;

   my $c    = $self->context;
   my $form = $c->stash->{form}->{name};
   my $uri  = $c->uri_for_action( $captcha_action );

   $self->clear_form  ( { firstfld => $form.q(.first_name)    } );
   $self->add_field   ( { ajaxid   => $form.q(.first_name)    } );
   $self->add_field   ( { ajaxid   => $form.q(.last_name)     } );
   $self->add_field   ( { ajaxid   => $form.q(.email_address) } );
   $self->add_field   ( { ajaxid   => $form.q(.newPass1)      } );
   $self->add_field   ( { id       => $form.q(.work_phone)    } );
   $self->add_field   ( { id       => $form.q(.location)      } );
   $self->add_field   ( { id       => $form.q(.project)       } );
   $self->add_field   ( { id       => $form.q(.home_phone)    } );
   $self->add_field   ( { name     => $form.q(.captcha), text => $uri } );
   $self->add_field   ( { ajaxid   => $form.q(.security)      } );
   $self->group_fields( { id       => $form.q(.legend)        } );
   $self->add_buttons ( qw(Insert) );
   return;
}

sub retrieve {
   my ($self, @rest) = @_; return $self->domain_model->retrieve( @rest );
}

sub set_password {
   my $self      = shift;
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

      $p_word1 eq $p_word2 or throw 'Passwords are not the same';

      $password = $p_word1;
   }
   elsif ($ptype == 2) {
      $password = q(*).$self->query_value( q(p_value) ).q(*); $encrypted = TRUE;
   }

   $self->domain_model->set_password( $user, $password, $encrypted );
   $self->add_result_msg( 'User [_1] password set', $user );
   return TRUE;
}

sub user_fill {
   my $self  = shift;
   my $s     = $self->context->stash;
   my $fill  = $s->{fill} = {};
   my $first = $fill->{first_name} = $self->query_value( q(first_name) );
   my $last  = $fill->{last_name } = $self->query_value( q(last_name) );
   my $model = $self->domain_model;

   $fill->{email} = $model->make_email_address( $first.q(.).$last );
   $s->{override} = TRUE;
   return TRUE;
}

sub user_manager_form {
   my ($self, $user) = @_; my $s = $self->context->stash; my $data = {};

   # Retrieve data from models
   try        { $data = $self->_get_user_data( $user ) }
   catch ($e) { return $self->add_error( $e ) }

   # Add elements to form
   my $form   = $s->{form}->{name};
   my $realm  = $s->{user_realm};
   my $realms = [ NUL, sort keys %{ $self->auth_realms } ];

   $self->clear_form( { firstfld => $form.($realm ? '.user' : '.realm') } );
   $self->add_field ( { default  => $realm,
                        id       => $form.'.realm',
                        values   => $realms } );

   if ($realm) {
      $self->add_field( { default => $user,
                          id      => $form.'.user',
                          values  => $data->{users} } );

      if ($user and $user eq $s->{newtag}) {
         $self->add_field( { default => $data->{profile_name},
                             id      => $form.'.profile',
                             labels  => $data->{labels},
                             values  => $data->{profiles} } );
      }
      else {
         $self->add_hidden( q(profile), $data->{profile_name} );

         if ($data->{role}) {
            my $text  = $self->loc( $form.'.pgroup' );
               $text .= ($data->{labels}->{ $data->{role} } || NUL);
               $text .= ' ('.$data->{role}.') ';

            $self->add_field( { id => $form.'.pgroup', text => $text } );
         }
      }
   }

   $self->group_fields( { id => $form.'.select' } );

   (not $user or lc $user eq q(all)) and return;
   $user eq $s->{newtag} and not $data->{profile_name} and return;

   $self->add_field( { default => $data->{first_name},
                       id      => $form.'.first_name' } );
   $self->add_field( { default => $data->{last_name},
                       id      => $form.'.last_name'  } );

   if ($user eq $s->{newtag}) { # Create new account
      if ($data->{name}) {
         $self->add_field( { default => $data->{name},
                             id      => $form.'.username' } );
         $self->add_buttons( qw(Insert) );
      }
      else {
         $self->add_field( { id => $form.'.afill' } );
         $self->add_buttons( qw(Fill) );
      }
   }
   else { # Edit existing account
      $self->add_hidden ( q(username), $user );
      $self->add_buttons( qw(Save Delete) );
   }

   unless ($data->{name}) {
      $self->group_fields( { id => $form.'.edit' } ); return;
   }

   $self->add_field( { default => $data->{email},
                       id      => $form.'.email_address' } );
   $self->add_field( { default => $data->{location},
                       id      => $form.'.location'      } );
   $self->add_field( { default => $data->{work_tel},
                       id      => $form.'.work_phone'    } );
   $self->add_field( { default => $data->{home_tel},
                       id      => $form.'.home_phone'    } );
   $self->add_field( { default => $data->{project},
                       id      => $form.'.project'       } );

   if ($self->supports( qw(fields homedir) )
       and $data->{homedir} ne $data->{common_home}) {
      $user eq $s->{newtag}
         and $self->add_field( { label => SPC, id => $form.'.populate' } );

      $self->add_field( { default  => $data->{homedir},
                          id       => $form.'.homedir',
                          readonly => $user eq $s->{newtag} ? 0 : 1 } );
   }

   defined $data->{shells}
      and $self->add_field( { default => $data->{shell},
                              id      => $form.'.shell',
                              values  => $data->{shells} } );

   $self->group_fields( { id => $form.'.edit' } );
   return;
}

sub user_report {
   my ($self, $type) = @_;
   my $s     = $self->context->stash;
   my $stamp = time2str( '%Y%m%d%H%M' );
   my $path  = $self->catfile( $self->rprtdir, 'userReport_'.$stamp.'.csv' );

   $self->add_result( $self->domain_model->user_report( { debug => $s->{debug},
                                                          path  => $path,
                                                          type  => $type } ) );
   return TRUE;
}

sub user_report_form {
   my ($self, $id) = @_; my ($data, $dir, $key, $pat, $ref);

   my $s     = $self->context->stash; $s->{pwidth} -= 10;
   my $form  = $s->{form}->{name};
   my $realm = $s->{user_realm};

   unless ($dir = $self->query_value( q(dir) )) {
      $dir = $self->{rprtdir}; $pat = q(userReport*);
      $key = sub { return (split m{ \. }mx, (split m{ _ }mx, $_[0])[1])[0] };
   }
   else { $pat = q(.*); $key = undef }

   $self->clear_form;

   if ($id) {
      my $path = $self->catfile( $dir, 'userReport_'.$id.'.csv' );

      $self->add_field( { path    => $path, id => $form.'.file' } );
      $self->add_field( { id      => $form.'.keynote' } );
      $self->add_buttons( qw(List Purge) );
   }
   else {
      my $values = [ q(), sort keys %{ $self->auth_realms } ];

      $self->add_field( { default => $realm,
                          id      => $form.'.realm',
                          values  => $values } );
      $self->add_buttons( qw(Execute) );
      $ref  = { action   => $s->{form}->{action},
                assets   => $s->{assets},
                dir      => $dir,
                make_key => $key,
                pattern  => qr{ $pat }mx };

      try {
         $data = $self->fs_model->list_subdirectory( $ref );
         $self->add_field( { data => $data, type => q(table) } );
      }
      catch ($e) { return $self->add_error( $e ) }
   }

   my $grp_id = $form.($id ? q(.select_purge) : q(.select_view));

   $self->group_fields( { id => $grp_id } );
   return;
}

sub user_security_form {
   my ($self, $user) = @_; my $s = $self->context->stash; my $data = {};

   try        { $data = $self->_get_security_data( $user ) }
   catch ($e) { return $self->add_error( $e ) }

   my $form   = $s->{form}->{name};
   my $realm  = $s->{user_realm};
   my $realms = [ NUL, sort keys %{ $self->auth_realms } ];

   $s->{messages}->{p_default  }->{text} = $data->{passwd};
   $s->{messages}->{p_generated}->{text} = $data->{generated};
   $s->{fullname} = $data->{fullname};

   $self->clear_form  ( { firstfld => $form.($realm ? q(.user) : q(.realm)) } );
   $self->add_hidden  ( q(p_default),   $data->{passwd   } );
   $self->add_hidden  ( q(p_generated), $data->{generated} );
   $self->add_field   ( { default  => $realm,
                          id       => $form.'.realm',
                          values   => $realms } );
   $realm and
      $self->add_field( { default  => $user,
                          id       => $form.'.user',
                          values   => $data->{users} } );
   $self->group_fields( { id       => $form.'.select' } );

   ($user and $user ne $s->{newtag} and lc $user ne q(all)) or return;

   $data->{passwd} and
      $self->add_field( { id       => $form.'.p_default',
                          prompt   => $data->{labels   }->[ 0 ],
                          stepno   => $data->{prompts  }->[ 0 ],
                          text     => $data->{passwd   }, } );
   $self->add_field   ( { id       => $form.'.p_generated',
                          prompt   => $data->{labels   }->[ 3 ],
                          stepno   => $data->{prompts  }->[ 3 ],
                          text     => $data->{generated}, } );
   $self->add_field   ( { default  => $self->query_value( q(p_value) ) || NUL,
                          id       => $form.'.p_value',
                          prompt   => $data->{labels   }->[ 1 ],
                          stepno   => $data->{prompts  }->[ 1 ],
                          values   => [ qw(disabled left nologin unused) ] } );
   $self->add_field   ( { id       => $form.'.p_word1',
                          prompt   => $data->{labels   }->[ 2 ],
                          stepno   => $data->{prompts  }->[ 2 ], } );
   $self->group_fields( { id       => $form.'.set_password' } );
   $self->add_field   ( { all      => $data->{all_roles},
                          current  => $data->{roles    },
                          id       => $form.'.groups' } );
   $self->group_fields( { id       => $form.'.secondary' } );
   $self->add_buttons ( qw(Set Update) );
   return;
}

# Private methods

sub _get_security_data {
   my ($self, $user) = @_; my $s = $self->context->stash; my $data = {};

   my $user_obj = $self->domain_model->retrieve( NUL, $user );
   my @roles    = $user ? @{ $user_obj->roles } : ();

   $data->{users    } = [ NUL, @{ $user_obj->user_list } ];
   $data->{all_roles} = [ grep { not is_member $_, @roles }
                               $self->roles->get_roles( q(all) ) ];

   my $profile = $roles[ 0 ] ? $self->profiles->find( $roles[ 0 ] ) : FALSE;

   $user_obj->pgid and shift @roles;

   $data->{roles   } = \@roles;
   $data->{passwd  } = $profile ? $profile->passwd : NUL;
   $data->{fullname} = $user_obj->first_name.SPC.$user_obj->last_name;

   try {
      $self->ensure_class_loaded( q(Crypt::PassGen) );
      $data->{generated} = (Crypt::PassGen::passgen( NLETT  => 6,
                                                     NWORDS => 1 ))[ 0 ]
         or throw $Crypt::PassGen::ERRSTR;
   }
   catch ($e) { $data->{generated} = $e }

   my $form = $s->{form}->{name}; my $labels = {};

   $data->{labels  } = [ SPC.$self->loc( $form.'.set_password_option1' ),
                         SPC.$self->loc( $form.'.set_password_option2' ),
                         SPC.$self->loc( $form.'.set_password_option3' ),
                         SPC.$self->loc( $form.'.set_password_option4' ) ];

   my $p_type = $self->query_value( q(p_type) ) || 1;

   for my $i (1 .. 4) {
      $data->{prompts}->[ $i - 1 ] = { container_class => q(step_number),
                                       labels          => { $i => undef },
                                       name            => q(p_type),
                                       type            => q(radioGroup),
                                       values          => [ $i ] };
      $p_type == $i and $data->{prompts}->[ $i - 1 ]->{default} = $i;
   }

   return $data;
}

sub _get_user_data {
   my ($self, $user) = @_; my $s = $self->context->stash; my $data = {};

   $data->{profile_name} = $s->{user_params}->{profile};

   my $profile_obj   = $self->profiles->list( $data->{profile_name} );
   my $user_obj      = $self->retrieve( NUL, $user );
   my $profile       = $profile_obj->result;

   $data->{homedir } = $profile->homedir;
   $data->{project } = $profile->project;
   $data->{labels  } = $profile_obj->labels;
   $data->{profiles} = [ NUL, @{ $profile_obj->list } ];
   $data->{users   } = [ NUL, $s->{newtag}, @{ $user_obj->user_list } ];

   if ($self->supports( qw(fields shells) )) {
      my $shells_obj = $self->shells->retrieve;

      $data->{shells} = $shells_obj->shells;
      $data->{shell } = $profile->shell || $shells_obj->default || q(/bin/ksh);
   }

   $user or return $data; my $auto_fill;

   if ($user eq $s->{newtag} and $auto_fill = $s->{fill}) {
      $data->{email     } = $auto_fill->{email};
      $data->{first_name} = $auto_fill->{first_name};
      $data->{last_name } = $auto_fill->{last_name};

      try {
         $data->{name   } = $self->domain_model->get_new_user_id
            ( $data->{first_name}, $data->{last_name}, $profile->prefix );
      }
      catch ($e) { $self->add_error( $e ) }

      if ($data->{name} and $self->supports( qw(fields homedir) )) {
         $data->{common_home} = $user_obj->common_home;
         $data->{homedir} ne $data->{common_home}
            and $data->{homedir} = $self->catdir( $data->{homedir},
                                                  $data->{name} );
      }
   }
   elsif ($user ne $s->{newtag} and lc $user ne q(all)) {
      $data->{email     } = $user_obj->email_address;
      $data->{first_name} = $user_obj->first_name;
      $data->{last_name } = $user_obj->last_name;
      $data->{name      } = $user;

      $data->{home_tel  } = $user_obj->home_phone;
      $data->{location  } = $user_obj->location;
      $data->{project   } = $user_obj->project;
      $data->{role      } = shift @{ $user_obj->roles };
      $data->{shell     } = $user_obj->shell;
      $data->{work_tel  } = $user_obj->work_phone;

      if ($self->supports( qw(fields homedir) )) {
         $data->{common_home} = $user_obj->common_home;
         $data->{homedir    } = $user_obj->homedir;
      }
   }

   return $data;
}

sub _register_read_queue {
   my ($self, $path) = @_;

   -f $path or throw error => 'File [_1] not found', args  => [ $path ];

   my $fields = $self->file_dataclass_schema( { lock => TRUE } )->load( $path );
   my $io     = $self->io( $self->register_queue_path )->chomp->lock;

   $io->println( grep { not m{ \A $path \z }mx } $io->getlines ); unlink $path;

   return $fields;
}

sub _register_validation {
   my ($self, $fields) = @_; $fields = $self->check_form( $fields || {} );

   $fields->{newPass1} eq $fields->{newPass2}
      or throw 'Passwords are not the same';

   delete $fields->{newPass1}; delete $fields->{newPass2}; my $profile;

   $fields->{profile} and $profile = $self->profiles->find( $fields->{profile});

   my $prefix = $profile ? $profile->prefix : NUL;

   $fields->{username} = $self->domain_model->get_new_user_id
      ( $fields->{first_name}, $fields->{last_name}, $prefix );

   return $fields;
}

sub _register_verification_email {
   # Registration verification email
   my ($self, $fields) = @_;

   my $c       = $self->context;
   my $s       = $c->stash;
   my $key     = substr create_token, 0, 32;
   my $path    = $self->io( $self->catfile( $self->sessdir, $key ) );

   $path->println( $fields->{username} );

   my $link    = $c->uri_for_action( $self->activate_path, $key );
   my $subject = $self->loc( q(accountVerification), $self->app_name );
   my $post    = {
      attributes      => {
         charset      => $s->{encoding},
         content_type => $self->email_content_type },
      from            => q(UserRegistration@).$s->{domain},
      mailer          => $s->{mailer},
      mailer_host     => $s->{mailer_host},
      stash           => {
         %{ $fields },
         app_name     => $self->app_name,
         link         => $link,
         title        => $subject, },
      subject         => $subject,
      template        => $self->email_template,
      template_attrs  => $self->template_attributes,
      to              => $fields->{email_address}, };

   $self->add_result( $self->send_email( $post ).SPC.$fields->{email_address} );
   return;
}

sub _register_write_queue {
   my ($self, $fields) = @_;

   my $path = $self->tempname( $self->dirname( $self->register_queue_path ) );
   my $fdss = $self->file_dataclass_schema( { lock => TRUE } );

   $fdss->dump( { data => $fields, path => $path } );
   $self->io( $self->register_queue_path )->lock->appendln( $path );
   return;
}

1;

__END__

=pod

=head1 Name

CatalystX::Usul::Model::Users - Catalyst user model

=head1 Version

0.7.$Revision: 1181 $

=head1 Synopsis

   use CatalystX::Usul::Model::Users;

   my $user_obj = CatalystX::Usul::Model::Users->new( $app, $config );

=head1 Description

Forms and actions for user maintainence

=head1 Subroutines/Methods

=head2 COMPONENT

Constructor initialises these attributes

=over 3

=item app_name

Name of the application using this identity model. Prefixes the subject line
of the account activation email sent to users who create an account via the
registration method

=item rprtdir

Location in the filesystem of the user reports

=item sessdir

Location in the filesystem of used user passwords and account activation
keys

=back

=head2 build_per_context_instance

=over 3

=item fs_domain

An clone of the I<FileSystem> model used by the L</user_report_form>
method to list the available user reports

=back

=head2 activate_account

Checks for the existence of the file created by the L</register> method. If
it exists it contains the username of a recently created account. The
accounts I<active> attribute is set to true, enabling the account

=head2 authenticate

Calls L<authenticate|CatalystX::Usul::Users/authenticate> in the domain model

=head2 authentication_form

Adds fields to the stash for the login screen

=head2 authenticate_user

Authenticate the user. If another controller was wanted and the user
was forced to authenticate first, redirect the session to the
originally requested controller. This was stored in the session by the
auto method prior to redirecting to the authentication controller
which forwarded to here

=head2 change_password

Method to change the users password. Throws exceptions for field
constraint failures and if the passwords entered are not the same

=head2 change_password_form

Adds field data to the stash for the change password screen. Allows users
to change their own password

=head2 create_or_update

Method to create a new account or update an existing one. Throws exceptions
for field constraint failures. Calls methods in the subclass to do the
actual work

=head2 delete

Deletes the selected account

=head2 find_user

Calls L<find_user|CatalystX::Usul::Users/find_user> in the domain model

=head2 get_features

Delegates the call to the domain model

=head2 get_primary_rid

Returns the primary role id for the given user. Note not all storage models
support primary_role ids

=head2 get_users_by_rid

Returns the list of users that share the given primary role id

=head2 is_user

Calls L<is_user|CatalystX::Usul::Users/is_user> in the domain model

=head2 profiles

Returns the domain model's profiles object

=head2 purge

Delete the list of selected accounts

=head2 register

Create the self registered account. The account is created in an inactive
state and a confirmation email is sent

=head2 register_form

Added the fields to the stash for the self registration screen. Users can
use this screen to create their own accounts

=head2 retrieve

Calls L<retrieve|CatalystX::Usul::Users/retrieve> in the domain model

=head2 set_password

Sets the users password to a given value

=head2 user_fill

Sets the I<fill> attribute of the stash in response to clicking the
auto fill button

=head2 user_manager_form

Adds fields to the stash for the user management screen. Adminstrators can
create new accounts or modify the details of existing ones

=head2 user_report

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

=item L<CatalystX::Usul::Captcha>

=item L<CatalystX::Usul::Email>

=item L<CatalystX::Usul::Model>

=item L<CatalystX::Usul::Shells>

=item L<CatalystX::Usul::Time>

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
