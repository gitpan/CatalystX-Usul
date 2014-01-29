# @(#)Ident: 07podspelling.t 2014-01-09 16:38 pjf ;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.17.%d', q$Rev: 1 $ =~ /\d+/gmx );
use File::Spec::Functions qw(catdir catfile updir);
use FindBin qw( $Bin );
use lib catdir( $Bin, updir, q(lib) );

use English qw(-no_match_vars);
use Test::More;

BEGIN {
   $ENV{AUTHOR_TESTING}
      or plan skip_all => 'POD spelling test only for developers';
}

eval "use Test::Spelling";

$EVAL_ERROR and plan skip_all => 'Test::Spelling required but not installed';

$ENV{TEST_SPELLING}
   or plan skip_all => 'Environment variable TEST_SPELLING not set';

my $checker = has_working_spellchecker(); # Aspell is prefered

if ($checker) { warn "Check using ${checker}\n" }
else { plan skip_all => 'No OS spell checkers found' }

add_stopwords( <DATA> );

all_pod_files_spelling_ok();

done_testing();

# Local Variables:
# mode: perl
# tab-width: 3
# End:

__DATA__
BSON
DDL
acl
api
appldir
async
auth
backend
binsdir
brk
bson
buildargs
blowfish
captcha
captchas
checkbox
classname
cpan
csrf
dbattrs
dbic
deserialize
deserializes
deserialization
dsn
embeded
fieldset
filename
filenames
flanigan
gettext
hostname
html
iframe
imager
javascript
jpeg
json
lbrace
loc
localhost
login
logout
lookup
lsb
mvc
namespace
namespaces
nbsp
nul
online
pathname
pathnames
plack
plugins
popup
postfix
postgresql
rdbms
rdbmss
redispatches
restful
resultset
rsb
runtime
schemas
sep
serializer
sitemap
smtp
spc
stacktrace
stderr
stdin
stdout
stringifies
suid
tts
typelist
unarchive
uninstall
unix
unshifts
uri
uris
username
usernames
usul
uuid
xhtml
xmlhttprequest
xmlhttprequests
http's
jshirley's
