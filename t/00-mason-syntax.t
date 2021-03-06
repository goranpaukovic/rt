#!/usr/bin/perl

use strict;
use warnings;

use RT::Test tests => 1, tests => 1;

my $ok = 1;

use File::Find;
find( {
    no_chdir => 1,
    wanted   => sub {
        return if /(?:\.(?:jpe?g|png|gif|rej)|\~)$/i;
        return if m{/\.[^/]+\.swp$}; # vim swap files
        if (m{/\.svn$}) {
            $File::Find::prune = 1;
            return;
        }
        return unless -f $_;
        diag "testing $_" if $ENV{'TEST_VERBOSE'};
        eval { compile_file($_) } and return;
        $ok = 0;
        diag "error in ${File::Find::name}:\n$@";
    },
}, RT::Test::get_relocatable_dir('../share/html'));
ok($ok, "mason syntax is ok");

use HTML::Mason;
use HTML::Mason::Compiler;
use HTML::Mason::Compiler::ToObject;
BEGIN { require RT::Test; }
use Encode qw(decode_utf8);

sub compile_file {
    my $file = shift;

    my $text = decode_utf8(RT::Test->file_content($file));

    my $compiler = new HTML::Mason::Compiler::ToObject;
    $compiler->compile(
        comp_source => $text,
        name => 'my',
        $HTML::Mason::VERSION >= 1.36? (comp_path => 'my'): (),
    );
    return 1;
}

