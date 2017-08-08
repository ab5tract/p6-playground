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

Passing C<$self> to a method certainly does feel a bit weird, though.

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

    method !check-anagram($a, $b) { ... }
    method !check-partial-anagram($a, $b) { ... }
    method !from-cache($string) { ... }
}

role IterativeAnagramIntrospection does AnagramIntrospection {
    has %!cache;

    method !from-cache($string) {
        %!cache{$string} //= |$string.comb
    }

    method !check-anagram($a, $b) {
        my %a-letters;
        %a-letters{$_}++ for self!from-cache($a);
        %a-letters{$_}-- for self!from-cache($b);

        # .abs is required for making sure the two same-letter/different-case
        # keys don't cancel each other out.
        so not [+] %a-letters.values>>.abs
    }

    method !check-partial-anagram($a, $b) {
        # Excluded because technically this is from the 'functional' organs of Rakudo
        # my %b-letters = $b.comb X=> True;
        # my @a-letters  = $a.comb;
        # so +@a-letters == +@a-letters.grep({ %b-letters{$_} })

        my %a-letters = self!from-cache($a) X=> True;
        %a-letters{$_}:delete for self!from-cache($b); # Better living with autoviv
        so not %a-letters.keys
    }
}

role FunctionalAnagramIntrospection does AnagramIntrospection {
    has %!cache;
    method !from-cache($string) {
        %!cache{$string} //= do {
            my %h;
            %h{$_}++ for $string.comb;
            %h
        }
    }

    method !check-anagram($a, $b) {
        my %a = self!from-cache($a);
        my %b = self!from-cache($b);

        my $all-a-in-b = [&&] %a.kv.map: { (%b{$^k} // 0) - $^v == 0 };
        my $all-b-in-a = [&&] %b.kv.map: { (%a{$^k} // 0) - $^v == 0 };
        so $all-a-in-b && $all-b-in-a
    }

    method !check-partial-anagram($a, $b) {
        my %a = self!from-cache($a);
        my %b = self!from-cache($b);
        so [&&] %a.kv.map: { (%b{$^k} // 0) - $^v >= 0 }
    }
}

role QuantHashAnagramIntrospection does AnagramIntrospection {
    has %!cache;
    method !from-cache(*@strings) {
        @strings.map: -> $string { %!cache{$string} //= $string.comb.Bag }
    }

    method !check-anagram($a, $b) {
        my ($a-bag, $b-bag) = self!from-cache($a, $b);
        so $a-bag (^) $b-bag == bag()
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
