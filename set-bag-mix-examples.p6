#!/usr/bin/env perl6

=begin pod
=head2 primitive example

    > my @ordered-list-of-set-types = Set, SetHash, Bag, BagHash, Mix, MixHash;
    [(Set) (SetHash) (Bag) (BagHash) (Mix) (MixHash)]
    > my $set-of-set-types = set @ordered-list-of-set-types
    set((MixHash), (Mix), (SetHash), (BagHash), (Bag), (Set))

=end pod

my @ordered-list-of-set-types = Set, SetHash, Bag, BagHash, Mix, MixHash;
my $set-of-set-types = set @ordered-list-of-set-types;
# note that there is pretty different behavior if you use a $ container instead of an @

subset Bagatelle where { $set-of-set-types (cont) $_ };

sub count-bagatelles(Bagatelle $hmm) {
    state $bag-of-bagatelles = BagHash.new;
    my $ret = ++$bag-of-bagatelles{ $hmm.WHAT };
    $ret
}


sub MAIN {
    test();
}

sub test {
    use Test;

    my @bagatelles = (set <a b c>), (bag <a a b b c c>), ((a => 2.2, b => 2.2, c => 2.2).Mix);

    count-bagatelles($_) for @bagatelles;
}
