use v6.c;

role AnagramIntrospection {
    multi method is-anagram-of($self: $other --> Bool) {
        my %self-letters;
        %self-letters{$_}++ for $self.lc.comb;
        %self-letters{$_}-- for $other.lc.comb;

        so ([+] %self-letters.values) == 0
    }

    multi method is-anagram-of($self: $other, :$partial! --> Bool) {
        my %other-letters = $other.lc.comb X=> True;
        my @self-letters  = $self.lc.comb;

        so +@self-letters == +@self-letters.grep({ %other-letters{$_} })
    }
}

my $string = 'Elvis' but AnagramIntrospection;

use Test;

ok $string.is-anagram-of('lives'), "<Elvis> <lives>";
nok $string.is-anagram-of('livestrong'), "<Elvis> is only partial to <livestrong>, not fully in it";
ok $string.is-anagram-of('livestrong', :partial), "<Elvis> can <livestrong> in a lenient universe";
