#!/usr/bin/env perl6

use v6.c;
use Text::CSV;

sub MAIN($file, Rat :$start, Rat :$end, :$plus = 'Bij', :$minus = 'Af') {
    my %ops = $plus => &[+], $minus => &[-];

    my @data = csv(in => $file)[1..*];

    my @mutations = @data[*;5].reverse;
    my @amounts   = @data[*;6].reverse.map: *.subst(q{.},q{}).subst(q{,},q{.}).Rat;

    my $max = max $start, $end;
    say "Initial Maximum: $max";
    my $running = $start;
    for @mutations Z @amounts -> ($op, $amount) {
        my &op = %ops{$op}; # Yeah, I personally enjoy a bit of harmless evil >:-)
        $running = op($running, $amount);
        if $running > $max {
            $max = $running;
        }
    }
    say "End value sanity check: $running == $end ? {$running == $end}";
    say "Final Max: $max";
}
