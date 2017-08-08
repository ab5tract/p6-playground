use v6.c;

=begin pod

=head2 DRY-d out Iterative Style

This variant shows more benefit from the DRY refactor than the C<QuantHash>
equivalent as these solutions all involve multiple lines of code.

=head3 Absolute requirements

C<.abs> is "hyper-ed" onto of C<%a-letters.values> to account for a corner case
that we only encounter in C<:strict> mode: letters of different-case but same-letter
will cancel each other out in the addition. By taking the absolute value, we can be
sure that all of our C<.values> are C<0>.

=head3 autoviv par excellénce

    %a-letters{$_}:delete for $b.comb

This expression is enabled by the fundamental-to-Perl concept of autovivification.
In my experience, the language tradeoffs off including autoviv are well worth the
pitfallse.

XXX: Include some pitfalls in Perl 5, Perl 6

=head3 C<not> a problem

Keeping in mind the importance of calling C<.abs> on the C<.values>, we can change

    # so ([+] %a-letters.values>>.abs) == 0
    so 0 == ([+] %a-letters.values>>.abs)

into

    so not [+] %a-letters.values>>.abs

This is because Perlish-ness goes hand-in-hand with considering C<0> to be C<False>.
Rakudo's primary divergence from earlier Perls is in its inclusion of a specific
C<Bool> type.

XXX: This type is implemented in some way via C<Enum>?

Even more so, an empty C<List> or C<Array> also equal C<False>. This allows for us
to change

    # so +%a-letters.keys == 0
    so 0 == +%a-letts.keys

into

    so not %a-letters.keys

If C<%a-letters> has any keys left after the deluge of C<:delete> adverbs thrown
at it by C<for $b.comb>, then C<.keys> will return a non-empty list. In all other
cases, we've identified a partial anagram.

=head3 Reduce the line noise

They say Perl reads like line noise. Rakudo allows you to take any (list-producing) line noise
and apply an infix operator thereupon.

    so ([+] 1..3) == 1 + 2 + 3

This provides the foundation for a (currently) more optimized way for reaching the
dream of C<Junctions>.

    so [||] (1..5)>>.is-prime
    so [&&] @connections>>.is-alive

are the same as

    so any (1..5)>>.is-prime
    so all @connections>>.is-alive

In fact, due to the grand capablities the reduce meta-operator, the C<[&&]> variant
is more immediately readable to my eyes.

XXX: A bit more justification than that?

=end pod

role AnagramIntrospection {
    multi method is-anagram-of($self: $other, :$partial!, :$strict! --> Bool) {
        check-partial-anagram($self, $other);
    }

    multi method is-anagram-of($self: $other, :$strict! --> Bool) {
        check-anagram($self, $other)
    }

    multi method is-anagram-of($self: $other, :$partial! --> Bool) {
        check-partial-anagram($self.lc, $other.lc)
    }

    multi method is-anagram-of($self: $other --> Bool) {
        check-anagram($self.lc, $other.lc)
    }

    sub check-anagram($a, $b) {
        my %a-letters;
        %a-letters{$_}++ for $a.comb;
        %a-letters{$_}-- for $b.comb;

        # .abs is required for making sure the two same-letter/different-case
        # keys don't cancel each other out.
        so not [+] %a-letters.values>>.abs
    }

    sub check-partial-anagram($a, $b) {
        # Excluded because technically this is from the 'functional' organs of Rakudo
        # my %b-letters = $b.comb X=> True;
        # my @a-letters  = $a.comb;
        # so +@a-letters == +@a-letters.grep({ %b-letters{$_} })

        my %b-letters;
        %b-letters{$_}++ for $b.comb;
        %b-letters{$_}-- for $a.comb; # Better living with autoviv
        so [&&] %b-letters.values >= 0
    }
}

my $string = 'Elvis' but AnagramIntrospection;

use Test;

ok $string.is-anagram-of('lives'), "<Elvis> <lives>";
nok $string.is-anagram-of('livestrong'), "<Elvis> by himself isn't enough to <livestrong>";
nok $string.is-anagram-of('lives', :strict), "Strictly speaking, <Elvis> ain't <lives>";
ok $string.is-anagram-of('livestrong', :partial), "<Elvis> can <livestrong> in a lenient universe, though";
nok $string.is-anagram-of('livestrong', :partial, :strict), "<Elvis> is dead";
