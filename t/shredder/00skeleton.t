#!/usr/bin/perl -w

use strict;
use warnings;

use Test::Deep;
use File::Spec;
use RT::Test tests => 1, tests => 1;
BEGIN {
    my $shredder_utils = RT::Test::get_relocatable_file('utils.pl',
        File::Spec->curdir());
    require $shredder_utils;
}
init_db();


create_savepoint('clean'); # backup of the clean RT DB
my $shredder = shredder_new(); # new shredder object

# ....
# create and wipe RT objects
#

cmp_deeply( dump_current_and_savepoint('clean'), "current DB equal to savepoint");
