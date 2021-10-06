#!/usr/bin/env perl6

use v6.c;

=begin pod

=head2 Adding a :partial target

=head3 C<(-)>, maybe?

Here we could utilize a crucial C<Baggy> dynamic of C<(-)>:

There are no negative values in a C<Bag>. This means that
you can easily check for a C<:partial> because the equivalent
of "exhausting" your pool of letters leaves only an empty bag
if you've subtracted a larger bag.

Thus:

    so $a.lc.comb.Bag (-) $b.lc.comb.Bag == bag()

provides us with a means to implement C<check-partial-anagram>.

=head3 C<<(<)>> !

However, we can also use the C<QuantHash> concept of a C<sub-bag>.

This is the C<Baggy> equivalent of the set theory concept of a C<subset>:

If B<Set $a> is a C<subset> of B<Set $b> when all members of B<Set $a> are present
in B<Set $b>, then B<Bag $c> is a C<sub-bag> of B<Bag $d> if all C<weights> in B<Bag $c>
are present and C<heavier> in B<Bag $d>.

Therefore our partial anagram implementation is as simple as:

    so $a.lc.comb.Bag (<) $b.lc.comb.Bag

=head3 C<<Not (<+) ?>>

Note that we cannot use C<Set> objects to accomplish anagram goals because
they do not respect the B<quantity> of any given letter within a word.

But in Rakudo we have the a whole family of "set-like" things, of which C<Set>
is arguably the least useful member.

This is in fact reflected in a hierarchical relationship of B<quantiness> amongst
the C<QuantHash> family:

    Mix -> Bag -> Set

If a C<Mix> is present, C<<(<)>> will coerce any C<Bag> or C<Set> argument(s) to C<Mix>.
Likewise, if a C<Bag> is present, it will coerce any C<Set> argument.

Rakudo originally held an operator-level distinction between C<Set> and C<Bag>/C<Mix>,
similar to how C<"fifty" == "sixty"> gives an error caused by using C<==> for C<Str>
(or, to be more precise, non-C<Numeric> candidates).

This was removed due to some prodding on my part and Larry agreeing that "a C<Set>
is a deginerate form of C<Mix>, and so on".


=head2 A name change

The addition of C<:partial> introduces a semantic gap in our API.

When we ask "C<$a.is-anagram($b, :partial)">, are we asking whether
C<$a> is a partial anagram of C<$b>, or are we asking whether C<$b> is
a partial anagram of C<$a>?

We can clear this up with a simple refactor: C<s/is-anagram/is-anagram-of/>

=end pod

role AnagramIntrospection {
    multi method is-anagram-of($self: $other, :$strict!) {
        so $self.comb.Bag (^) $other.comb.Bag == bag();
    }

    multi method is-anagram-of($self: $other, :$partial!) {
        so $self.lc.comb.Bag (<) $other.comb.Bag;
        # so $self.lc.comb.Bag (-) $other.lc.comb.Bag == bag();
    }

    multi method is-anagram-of($self: $other) {
        so $self.lc.comb.Bag (^) $other.lc.comb.Bag == bag();
    }
}

my $string = 'Elvis' but AnagramIntrospection;

use Test;

ok $string.is-anagram-of('lives'), "<Elvis> <lives>";
nok $string.is-anagram-of('livestrong'), "<Elvis> is only partial to <livestrong>, not fully in it";
nok $string.is-anagram-of('lives', :strict), "Strictly speaking, <Elvis> ain't <lives>";

my $partial-string = 'run' but AnagramIntrospection;
ok $partial-string.is-anagram-of('runaway', :partial), "Can't <runaway> without <run>ning";
