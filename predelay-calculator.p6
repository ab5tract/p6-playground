#!/usr/bin/env perl6

use v6.c;

sub MAIN($bpm = 120) {
    my $whole-note = 60_000 / $bpm * 4;

    for 1, * * 2 ... 128 -> $div {
        say "1/$div\t" ~ ($whole-note / $div).fmt("%.1f");
    }
}
