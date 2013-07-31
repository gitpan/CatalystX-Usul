package MyApp;

use Moose;

use Catalyst qw(ConfigComponents);

with qw(CatalystX::Usul::TraitFor::CreatingUsul);

__PACKAGE__->config
   ( action_class             => q(CatalystX::Usul::Action),
     appldir                  => File::Spec->curdir,
     content_map              => { 'text/html' => q(HTML) },
     content_type             => q(text/html),
     ctrldir                  => q(t),
     default_action           => q(redirect_to_default),
     has_loaded               => 1,
     localedir                => File::Spec->catdir( qw(t locale) ),
     name                     => q(MyApp),
     negotiate_content_type   => 0,
     root                     => q(t),
     rprtdir                  => q(t),
     skindir                  => q(t),
     skins                    => q(),
     stylesheet               => q(colour-green.css),
     tempdir                  => q(t),
     template_dir             => q(t),
     'Model::Config'          => {
        parent_classes        => q(CatalystX::Usul::Model::Config) },
     'Model::Help'            => {
        parent_classes        => q(CatalystX::Usul::Model::Help) },
     'Model::Config::Levels'  => {
        parent_classes        => q(CatalystX::Usul::Model::Config::Levels) },
     'Model::UsersSimple'     => {
        parent_classes        => q(CatalystX::Usul::Model::Users),
        domain_attributes     => {
           role_class         => q(CatalystX::Usul::Roles::Simple), },
        domain_class          => q(CatalystX::Usul::Users::Simple) },
        role_model_class      => q(RolesSimple),
     'Plugin::Authentication' => {
        default_realm         => q(R00-Internal), },
     'View::HTML'             => {
        parent_classes        => q(CatalystX::Usul::View::HTML),
        jscript_dir           => q(t),
        template_dir          => q(t), },
     );

__PACKAGE__->setup;

no Moose;

1;
