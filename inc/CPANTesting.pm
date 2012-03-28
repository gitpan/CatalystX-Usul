# @(#)$Id: CPANTesting.pm 1136 2012-03-28 19:44:56Z pjf $

package CPANTesting;

use strict;
use warnings;

my $uname = qx(uname -a);

sub broken {
   $uname     =~ m{ bandsman      }mx and return 'Stopped Horne';
   $uname     =~ m{ higgsboson    }mx and return 'Stopped dcollins';
   $uname     =~ m{ profvince.com }mx and return 'Stopped vpit';
   $uname     =~ m{ fremen        }mx and return 'Stopped Bingo';
   $ENV{PATH} =~ m{ \A /home/sand }mx and return 'Stopped Konig';
   return 0;
}

1;

__END__
