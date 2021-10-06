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

=head3 A note on I<nomic verbosity>

I like to argue that the I<nomic verbosity> should increase in proportion to the
I<expressivity> of the code solution.

For example, I choose to use the detailed temporary variables C<$all-A-in-B> and
C<$all-B-in-A> inside of the functional implementation of C<!check-anagram>.

Sure, it could have looked like this:

    so  ([&&] $a.kv.map: { ($b{$^k} ||= 0) - $^v == 0 })
            &&
        ([&&] $b.kv.map: { ($a{$^k} ||= 0) - $^v == 0 })

But this degree of expressivitiy is actually adding unnecessary complexity by
elevating the "expression itself" to the level of signifier.

All we have to do to make the code self-documenting is stash the results in a couple
of temporary variables before checking to make sure that they are both true. The
tiny number of lines required to implement the C<FunctionalAnagramIntrospection> role
means that we can add some I<nomic verbosity> without negatively impacting the readability
or density of the implementation.

=end pod

role AnagramIntrospection {
    multi method is-anagram-of($self: $other, :$partial!, :$strict! --> Bool) {
        my ($a, $b) = self!from-cache($self, $other);
        $self!check-partial-anagram($a, $b);
    }

    multi method is-anagram-of($self: $other, :$strict! --> Bool) {
        my ($a, $b) = self!from-cache($self, $other);
        $self!check-anagram($a, $b)
    }

    multi method is-anagram-of($self: $other, :$partial! --> Bool) {
        my ($a, $b) = self!from-cache:  $self.subst(/\s/,'').lc,
                                        $other.subst(/\s/,'').lc;
        $self!check-partial-anagram($a, $b)
    }

    multi method is-anagram-of($self: $other --> Bool) {
        my ($a, $b) = self!from-cache:  $self.subst(/\s/,'').lc,
                                        $other.subst(/\s/,'').lc;
        $self!check-anagram($a, $b)
    }

    # Your implementation role is expected to have these present, one way
    # or another.
    method !check-anagram($a, $b) { ... }
    method !check-partial-anagram($a, $b) { ... }
    method !from-cache(*@strings) { ... }
}

# This could be included inside the "base" role C<AnagramIntrospection>, but then
# our quant solution would include some unnecessary code.
role PrimitiveHashCache {
    has %!cache;
    method !from-cache(*@strings) {
        @strings.map: { %!cache{$^string} //= self!create-count-hash($string) }
    }

    method !create-count-hash($string) {
        my $h = Hash.new;
        $h{$_}++ for $string.comb;
        $h
    }
}

role IterativeAnagramIntrospection does AnagramIntrospection does PrimitiveHashCache {
    method !check-anagram($a, $b) {
        my %tmp;
        for $b.kv -> $k, $v {
            %tmp{$k} ||= $a{$k} // 0;
            %tmp{$k} -= $v;
        }
        so not [+] %tmp.values>>.abs
    }

    method !check-partial-anagram($a, $b) {
        my $all-A-in-B = True;
        for $a.kv -> $k, $v {
            if not $b{$k}:exists {
                $all-A-in-B = False;
            } else {
                $all-A-in-B &&= ($b{$k} - $v) >= 0;
            }
            last unless $all-A-in-B; # so far
        }
        so $all-A-in-B
    }
}

role FunctionalAnagramIntrospection does AnagramIntrospection does PrimitiveHashCache {
    method !check-anagram($a, $b) {
        my $all-A-in-B = [&&] $a.kv.map: { ($b{$^k} ||= 0) - $^v == 0 }
        my $all-B-in-A = [&&] $b.kv.map: { ($a{$^k} ||= 0) - $^v == 0 };
        so $all-A-in-B && $all-B-in-A
    }

    method !check-partial-anagram($a, $b) {
        so [&&] $a.kv.map: { ($b{$^k} ||= 0) - $^v >= 0 }
    }
}

role QuantHashAnagramIntrospection does AnagramIntrospection {
    has %!bag-cache;
    method !from-cache(*@strings) {
        @strings.map: -> $string { %!bag-cache{$string} //= $string.comb.Bag }
    }

    method !check-anagram($a, $b) {
        so not $a (^) $b
    }

    method !check-partial-anagram($a, $b) {
        so $a (<=) $b
    }
}

my $iterative-string  = 'Elvis' but IterativeAnagramIntrospection;
my $functional-string = 'Elvis' but FunctionalAnagramIntrospection;
my $quanthash-string  = 'Elvis' but QuantHashAnagramIntrospection;

use Test;

my %test-strings{Any};

for IterativeAnagramIntrospection,
    FunctionalAnagramIntrospection,
    QuantHashAnagramIntrospection -> $implementation {
    %test-strings{$implementation} = 'Elvis' but $implementation
}

sub recreate-strings(%hash, $string) {
    for %hash.keys -> $k {
        %hash{$k} = $string but $k;
    }
}

# $role just feels so unnecessarily 'generic' in this context
# I would personally prefer $implementation
subtest "Elvis tests" => {
    for %test-strings.kv -> $role, $string {
        subtest "implementation: {$role.^name}" => {
            plan 5;
            ok $string.is-anagram-of('lives'), "<Elvis> <lives>";
            nok $string.is-anagram-of('livestrong'), "<Elvis> by himself isn't enough to <livestrong>";
            nok $string.is-anagram-of('lives', :strict), "Strictly speaking, <Elvis> ain't <lives>";
            ok $string.is-anagram-of('livestrong', :partial), "<Elvis> can <livestrong> in a lenient universe, though";
            nok $string.is-anagram-of('livestrong', :partial, :strict), "<Elvis> is dead";
        }
    }
}

recreate-strings(%test-strings, 'King Boon');
subtest "King Boon tests" => {
    for %test-strings.kv -> $implementation, $string {
        subtest "implementation: {$implementation.^name}" => {
            plan 5;
            ok $string.is-anagram-of('boonking'), "<King Boon> is an anagram of <boonking> (spaces and casing are ignored without :strict)";
            nok $string.is-anagram-of('booking'), "<King Boon> is not an anagram of <booking>";
            nok $string.is-anagram-of('booking', :partial), "<King Boon> is not a :partial anagram of <booking> (even though <booking> is a partial anagram of <King Boon>)";
            ok $string.is-anagram-of('booking king', :partial), "<King Boon> is a :partial anagram of <booking king>";
            ok $string.is-anagram-of('nooB King', :strict), "<King Boon> is a :strict anagram of <nooB King>";
        }
    }
}
