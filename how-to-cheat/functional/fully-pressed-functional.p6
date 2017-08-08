use v6.c;

=begin pod

=head2 Roles are awesome

=head3 Test all the approaches!

This is an attempt to make a more or less idiomatic Rakudo way to compose our
various types of anagram introspection. This way we can test each of them with a
single test suite.

=head3 Role-only behavior modification

There are some aspects of the code that are a bit quirky that are introduced by
the lack of a formal (sub)class. We pass C<$self> and C<$self.lc> as the first
argument to the C<check-anagram> and C<check-partial-anagram> private methods in order
to keep the C<:strict> logic in the "base" role, B<AnagramIntrospection>.

Otherwise we would have to complicate the derived-role implementations by asking
them to juggle C<.lc> or not.

Passing C<$self> to a method certainly does feel a bit weird, though. We keep our
shame private.

=head3 A more (or less) traditional approach using OO

A more traditional OO approach could involve a singleton class of B<AnagramInspector>
that provides a class method for checking anagrams. We could then create inspectors
for each individual implementation. For example:

    my $iterative-inspector = AnagramInspector but IterativeAnagramIntrospection;
    $iterative-inspector.check-anagram($a, $b);

I would make C<check-anagram> and C<check-partial-anagram> public (class) methods.
I would also throw out all of the C<is-anagram-of> candidates since they no longer
make sense semantically.

In fact, you could code such an

=head3 A note on I<nomic verbosity>

I like to argue that the I<nomic verbosity> should increase in proportion to the
I<expressivity> of the code solution.

For example, I choose to use the detailed temporary variables C<$all-A-in-B> and
C<$all-B-in-A>

    so  ([&&] $ah.kv.map: { ($bh{$^k} ||= 0) - $^v == 0 })
            &&
        ([&&] $bh.kv.map: { ($ah{$^k} ||= 0) - $^v == 0 })

=end pod

role AnagramIntrospection {
    multi method is-anagram-of($self: $other, :$partial!, :$strict! --> Bool) {
        $self!check-partial-anagram($self, $other);
    }

    multi method is-anagram-of($self: $other, :$strict! --> Bool) {
        $self!check-anagram($self, $other)
    }

    multi method is-anagram-of($self: $other, :$partial! --> Bool) {
        $self!check-partial-anagram($self.lc, $other.lc)
    }

    multi method is-anagram-of($self: $other --> Bool) {
        $self!check-anagram($self.lc, $other.lc)
    }

    # Our base role provides a basic caching layer. Howev
    has %!cache;
    method !from-cache(*@strings) {
        @strings.map: { %!cache{$^string} //= self!create-count-hash($string) }
    }

    method !create-count-hash($string) {
        my $h = Hash.new;
        $h{$_}++ for $string.comb;
        $h
    }

    # Our implementation-specific roles are expected to implement
    # the following:
    method !check-anagram($a, $b) { ... }
    method !check-partial-anagram($a, $b) { ... }

}

role IterativeAnagramIntrospection does AnagramIntrospection {
    method !check-anagram($a, $b) {
        my ($ah, $bh) = self!from-cache($a, $b);
        for $bh.kv -> $k, $v {
            ($bh{$k} ||= 0) -= $ah{$k} || 0;
            ($ah{$k} ||= 0) -= $v;
        }
        so not ([+] $ah.values>>.abs) + ([+] $bh.values>>.abs)
    }

    method !check-partial-anagram($a, $b) {
        my ($ah, $bh) = self!from-cache($a, $b);
        my $all-A-in-B = True;

        for $ah.kv -> $k, $v {
            if not $bh{$k}:exists {
                $all-A-in-B = False;
            } else {
                $all-A-in-B &&= ($bh{$k} - $v) >= 0;
            }
            last unless $all-A-in-B; # so far
        }

        so $all-A-in-B
    }
}

role FunctionalAnagramIntrospection does AnagramIntrospection {
    method !check-anagram($a, $b) {
        my ($ah, $bh) = self!from-cache($a, $b);



        my $all-A-in-B = [&&] $ah.kv.map: { ($bh{$^k} ||= 0) - $^v == 0 }
        my $all-B-in-A = [&&] $bh.kv.map: { ($ah{$^k} ||= 0) - $^v == 0 };
        so $all-A-in-B && $all-B-in-A
    }

    method !check-partial-anagram($a, $b) {
        my ($ah, $bh) = self!from-cache($a, $b);
        so [&&] $ah.kv.map: { ($bh{$^k} ||= 0) - $^v >= 0 }
    }
}

role QuantHashAnagramIntrospection does AnagramIntrospection {
    has %!bag-cache;
    method !from-cache(*@strings) {
        @strings.map: -> $string { %!bag-cache{$string} //= $string.comb.Bag }
    }

    method !check-anagram($a, $b) {
        my ($a-bag, $b-bag) = self!from-cache($a, $b);
        so not $a-bag (^) $b-bag
    }

    method !check-partial-anagram($a, $b) {
        my ($a-bag, $b-bag) = self!from-cache($a, $b);
        so $a-bag (<) $b-bag
    }
}

my $iterative-string  = 'Elvis' but IterativeAnagramIntrospection;
my $functional-string = 'Elvis' but FunctionalAnagramIntrospection;
my $quanthash-string  = 'Elvis' but QuantHashAnagramIntrospection;

use Test;

for $iterative-string, $functional-string, $quanthash-string -> $string {
    ok $string.is-anagram-of('lives'), "<Elvis> <lives>";
    nok $string.is-anagram-of('livestrong'), "<Elvis> by himself isn't enough to <livestrong>";
    nok $string.is-anagram-of('lives', :strict), "Strictly speaking, <Elvis> ain't <lives>";
    ok $string.is-anagram-of('livestrong', :partial), "<Elvis> can <livestrong> in a lenient universe, though";
    nok $string.is-anagram-of('livestrong', :partial, :strict), "<Elvis> is dead";
}
