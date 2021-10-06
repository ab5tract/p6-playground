#!/usr/bin/env perl6

use v6.c;

role AnagramIntrospection {
    multi method is-anagram($self: $other, :$partial!, :$strict!) {
        check-partial-anagram($self, $other);
    }

    multi method is-anagram($self: $other, :$strict!) {
        check-anagram($self, $other);
    }

    multi method is-anagram($self: $other, :$partial!) {
        check-partial-anagram($self.lc, $other.lc);
    }

    multi method is-anagram($self: $other) {
        check-anagram($self.lc, $other.lc);
    }

    sub check-anagram($a, $b) {
        so $a.comb.Bag (^) $b.comb.Bag == bag();
    }

    sub check-partial-anagram($a, $b) {
        so $a.comb.Bag (-) $b.comb.Bag == bag();
    }
}

my $string = 'Elvis' but AnagramIntrospection;

use Test;

ok $string.is-anagram('lives'), "<Elvis> <lives>";
nok $string.is-anagram('livestrong'), "<Elvis> is only partial to <livestrong>, not fully in it";
nok $string.is-anagram('lives', :strict), "Strictly speaking, <Elvis> ain't <lives>";

ok $string.is-anagram('livestrong', :partial), "<Elvis> can <livestrong> in a world of lenient drug laws";
nok $string.is-anagram('livestrong', :partial, :strict), "<Elvis> is dead";
