package MyApp;

use Catalyst qw(ConfigComponents);

__PACKAGE__->config
   ( action_class            => q(CatalystX::Usul::Action),
     appldir                 => File::Spec->curdir,
     content_map             => { 'text/html' => q(HTML) },
     content_type            => q(text/html),
     ctrldir                 => q(t),
     default_action          => q(redirect_to_default),
     has_loaded              => 1,
     localedir               => File::Spec->catdir( qw(t locale) ),
     negotiate_content_type  => 0,
     root                    => q(t),
     skindir                 => q(t),
     skins                   => q(),
     stylesheet              => q(colour-green.css),
     tempdir                 => q(t),
     "Model::Config"         => {
        parent_classes       => q(CatalystX::Usul::Model::Config) },
     "Model::Config::Levels" => {
        parent_classes       => q(CatalystX::Usul::Model::Config::Levels) },
     'View::HTML'            => {
        parent_classes       => q(CatalystX::Usul::View::HTML),
        fonts_dir            => q(),
        jscript_dir          => q(t),
        template_dir         => q(t), },
     );

__PACKAGE__->setup;

1;
