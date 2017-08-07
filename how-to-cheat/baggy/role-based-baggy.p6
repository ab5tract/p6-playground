#!/usr/bin/env perl6

use v6.c;

role AnagramIntrospection {
    method is-anagram($self: $other) {
        so $self.lc.comb.Bag (^) $other.lc.comb.Bag == bag();
    }
}

my $string = 'Elvis' but AnagramIntrospection;

use Test;

ok $string.is-anagram('lives'), "<Elvis> <lives>";
nok $string.is-anagram('livestrong'), "<Elvis> is only partial to <livestrong>, not fully in it";
