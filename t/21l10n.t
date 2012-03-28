# @(#)$Id: 21l10n.t 1097 2012-01-28 23:31:29Z pjf $

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.4.%d', q$Rev: 1097 $ =~ /\d+/gmx );
use File::Spec::Functions;
use FindBin qw( $Bin );
use lib catdir( $Bin, updir, q(lib) );
use utf8;

use English qw(-no_match_vars);
use Module::Build;
use Test::More;

BEGIN {
   my $current = eval { Module::Build->current };

   $current and $current->notes->{stop_tests}
            and plan skip_all => $current->notes->{stop_tests};

   plan tests => 8;
}

use_ok q(CatalystX::Usul::L10N);

{  package Logger;

   sub new   { return bless {}, __PACKAGE__ }
   sub debug { warn '[DEBUG] '.$_[ 1 ] }
   sub error { warn '[ERROR] '.$_[ 1 ] }
   sub warn  { warn '[WARNING] '.$_[ 1 ] }
}

my $l10n = CatalystX::Usul::L10N->new( debug        => 0,
                                       domain_names => [ q(default) ],
                                       localedir    => catdir( qw(t locale) ),
                                       log          => Logger->new,
                                       tempdir      => q(t) );
my $args = { locale => 'de_DE' };
my $text = $l10n->localize( 'December', $args );

ok $text eq 'Dezember', 'translated';

$text = $l10n->localize( 'September', $args );
ok $text eq 'September', 'same';

$text = $l10n->localize( 'Not translated', $args );
ok $text eq 'Not translated', 'not translated';

$text = $l10n->localize( 'March', $args );
ok $text eq 'März', 'charset decode';

$args->{context} = 'Context here (2)';
$text = $l10n->localize( 'Singular', $args );
ok $text eq 'Einzahl 2', 'context';

$args->{count} = 2;
$text = $l10n->localize( 'Singular', $args );
ok $text eq 'Mehrzahl 2', 'context plural';

my $header = $l10n->get_po_header( $args );

ok $header->{project_id_version} eq q(libintl-perl-text 1.12),
   'get_po_header';

unlink catfile( qw(t ipc_srlock.lck) );
unlink catfile( qw(t ipc_srlock.shm) );
unlink catfile( qw(t file-dataclass-schema.dat) );

# Local Variables:
# coding: utf-8
# mode: perl
# tab-width: 3
# End:
