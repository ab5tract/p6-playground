use v6.c;

role AnagramIntrospection {
    method is-anagram-of($self: $other) {
        my %self-letters;
        %self-letters{$_}++ for $self.lc.comb;
        %self-letters{$_}-- for $other.lc.comb;

        so ([+] %self-letters.values) == 0;
    }
}

my $string = 'Elvis' but AnagramIntrospection;

use Test;

ok $string.is-anagram-of('lives'), "<Elvis> <lives>";
nok $string.is-anagram-of('livestrong'), "<Elvis> is only partial to <livestrong>";
