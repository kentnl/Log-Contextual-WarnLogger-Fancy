use strict;
use warnings;

use Test::More;

BEGIN {
    unless ( $INC{'Sub/Util.pm'} or eval { require Sub::Util; 1 } ) {
        plan skip_all => "Sub::Util needed for this test";
        exit 0;
    }
}

require Log::Contextual::WarnLogger::Fancy;
ok( Sub::Util::subname( \&Log::Contextual::WarnLogger::Fancy::is_info ),
  'is_info' );

done_testing;

