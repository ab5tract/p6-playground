#!/usr/bin/env perl6

use v6.c;

role AnagramIntrospection {
    multi method is-anagram($self: $other, :$partial!, :$strict!) {
        so $self.comb.Bag (-) $other.comb.Bag == bag();
    }

    multi method is-anagram($self: $other, :$strict!) {
        so $self.comb.Bag (^) $other.comb.Bag == bag();
    }

    multi method is-anagram($self: $other, :$partial!) {
        so $self.lc.comb.Bag (-) $other.lc.comb.Bag == bag();
    }

    multi method is-anagram($self: $other) {
        so $self.lc.comb.Bag (^) $other.lc.comb.Bag == bag();
    }
}

my $string = 'Elvis' but AnagramIntrospection;

use Test;

ok $string.is-anagram('lives'), "<Elvis> <lives>";
nok $string.is-anagram('livestrong'), "<Elvis> is only partial to <livestrong>, not fully in it";
nok $string.is-anagram('lives', :strict), "Strictly speaking, <Elvis> ain't <lives>";

ok $string.is-anagram('livestrong', :partial), "<Elvis> can <livestrong> in a world of lenient drug laws";
nok $string.is-anagram('livestrong', :partial, :strict), "<Elvis> is dead";
