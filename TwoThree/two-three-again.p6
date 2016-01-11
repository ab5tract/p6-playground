#!/usr/bin/env perl6

constant DEBUG = 0;

class Leaf      { ... }
class TwoNode   { ... }
class ThreeNode { ... }

role Nodal {
    has Int   @.d is rw;
    has Nodal $.parent is rw;

    method new(:@d?, :$parent?) { self.bless(:@d, :$parent) }

    method TwoNode($SELF is rw : @d) {
        @d .= sort;
        say "Attempting to promote {$SELF.WHICH} to TwoNode with d=[{@d}]" if DEBUG;
        $SELF = TwoNode.new(d => @d, parent => self!pass-parent);
        say "Successful promotion to {$SELF.WHICH}.\n$SELF" if DEBUG;
    }

    method ThreeNode($SELF is rw : @d) {
        @d .= sort;
        say "Attempting to promote {$SELF.WHICH} to ThreeNode with d=[{@d}]" if DEBUG;
        $SELF = ThreeNode.new(d => @d, parent => self!pass-parent);
        say "Successful promotion to {$SELF.WHICH}.\n$SELF" if DEBUG;
    }

    method !pass-parent {
        my $parent;
        if not $!parent === self {
            $parent := $!parent;
        }
    }

    method !all-values {
        [@!d];
    }

    method Str {
        self.gist;
    }

    method gist {
        "{self.WHICH}: {self!all-values}";
    }
}

class Leaf does Nodal {
    submethod BUILD( :@d, :$parent ) {
        @!d = @d // [];
        say "{self.WHICH} Leaf constructor was passed parent {$parent.WHICH}" if DEBUG;
        $!parent = (defined $parent) ?? $parent !! self;
    }

    multi method insert-value($SELF is rw : $val ) {
        $SELF.TwoNode([|@!d, $val]);
    }

    multi method insert-value($SELF is rw : $val where { +@!d } ) {
        $SELF.ThreeNode([|@!d, $val]);
    }

    method Bool {
        so +@!d == 1;
    }
}

class TwoNode does Nodal {
    has Nodal $.l is rw;
    has Nodal $.r is rw;
    has Int $.d1;

    multi submethod BUILD($SELF is rw : :@d where *.elems > 3) {
        $SELF.ThreeNode(@d);
    }

    multi submethod BUILD(:@d where *.elems == 3, :$parent) {
        my ($ld, $rd) = [@d.shift], [@d.pop];
        self!build-helper(:$ld, :$rd, :@d, :$parent);
    }

    multi submethod BUILD(:@d where *.elems == 2, :$parent) {
        my $ld = @d[0] > @d[1] ?? [@d.pop] !! [@d.shift];
        self!build-helper(:$ld, :@d, :$parent);
    }

    multi submethod BUILD(:@d where *.elems == 1, :$parent) {
        self!build-helper(:@d, :$parent);
    }

    method !build-helper(:$ld, :$rd, :@d, :$parent) {
        $!l = Leaf.new(d => $ld // [], parent => self);
        $!r = Leaf.new(d => $rd // [], parent => self);
        @!d = @d;
        $!d1 := @!d[0];
        $!parent = (defined $parent) ?? $parent !! self;
    }

    method Bool {
        +@!d == 1 &&
            ([&&] $!d1 X> $!l.d and not $!r)
            ||
            ([&&] $!d1 X> $!l.d and [&&] $!d1 X< $!r.d);
    }

    method !all-values {
        [ |$!l.d, |$!r.d, |@!d ];
    }

    multi method insert-value($SELF is rw : $val) {
        $SELF.TwoNode([ |self!all-values, $val ]);
    }

    multi method insert-value($SELF is rw : $val where { +$!l.d and +$!r.d }) {
        if $val < $!d1 {
            $!l.insert-value($val);
        } else {
            $!r.insert-value($val);
        }
    }

    method gist {
        qq:to/END/;
        Node {self.WHICH}
            d: [{@!d}]
            l: [{$!l.d}] ({$!l.WHICH})
            r: [{$!r.d}] ({$!r.WHICH})
        END
    }
}

class ThreeNode does Nodal {
    has Nodal $.l is rw;
    has Nodal $.m is rw;
    has Nodal $.r is rw;
    has Int $.d1;
    has Int $.d2;

    submethod BUILD( :@d, :$parent ) {
        @d .= sort;
        my ($min, $max, $l-d, $m-d, $r-d);

        if +@d > 2 {
            $l-d = [ @d.shift ];
            $r-d = [ @d.pop ];
    
            if +@d == 3 {
                my @final-d = [ @d.shift, @d.pop ];
                $m-d = [ @d.pop ]; # the middle one pops last
                @d = @final-d;
            }
        }

        @!d = @d;
        $!d1 := @!d[0];
        $!d2 := @!d[1];

        $l-d //= [];
        $r-d //= [];
        $m-d //= [];

        $!l = Leaf.new(d => $l-d, parent => self);
        $!r = Leaf.new(d => $r-d, parent => self);
        $!m = Leaf.new(d => $m-d, parent => self);

        if defined $parent {
            $!parent = $parent;
        } else {
            $!parent = self;
        }
    }

    multi method insert-value($SELF is rw : $val where { not +$!m.d }) {
        $SELF.ThreeNode( [$SELF!all-values.Slip, $val] );
    }

    multi method insert-value($SELF is rw : $val) {
        ...
    }

    method !all-values {
        [|$!l.d, |$!r.d, |$!m.d, |@!d];
    }

    method gist {
        qq:to/END/;
        Node: {self.WHICH}
            d: {@!d}
            l: {$!l.d} ({$!l.WHICH})
            m: {$!m.d} ({$!m.WHICH})
            r: {$!r.d} ({$!r.WHICH})
        END
    }

    method Bool {
        +@!d == 2 &&
            (not +$!m.d and [&&] $!d1 X> $!l.d and [&&] $!d2 X< $!r.d)
            ||
            ([&&] $!d1 X> $!l.d and [&&] $!d1 X< $!m.d and
             [&&] $!d2 X> $!m.d and [&&] $!d1 X< $!r.d);
    }
}

class Tree {
    has Nodal $.origin is rw = Leaf.new;

    method search($val, $cursor) {
        given $val {
            when { $cursor.d.contains($_) }          { $cursor }
            # if it doesn't contain $val, and is a Leaf, we will return the cursor
            when $cursor ~~ Leaf                     { return-rw $cursor.parent }
            when $cursor ~~ TwoNode|ThreeNode {
                when { $cursor.l.d.contains($_) }    { return-rw $cursor.l }
                when { $cursor.r.d.contains($_) }    { return-rw $cursor.r }

                when * < $cursor.d1 {
                    return-rw self.search($val, $cursor.l);
                }

                when $cursor ~~ ThreeNode {
                    when { $cursor.m.d.contains($_) }  { return-rw $cursor.m }
                    when $cursor.d1 < * < $cursor.d2 {
                        return-rw self.search($val, $cursor.m);
                    }
                    when * > $cursor.d2 {
                        return-rw self.search($val, $cursor.r);
                    }
                }

                # This will be a valid code path for ThreeNodes, due to the d1
                # < * < d2 check in the ThreeNode specific conditions
                when * > $cursor.d1 {
                    return-rw self.search($val, $cursor.r);
                }
            }
        }
    }

    multi method insert($v where { not $!origin.d }) {
        $!origin.insert-value($v);
        say "Tree origin is {self.WHICH} after insert and looks like:\n{~self}" if DEBUG;
    }

    multi method insert($v) {
        say "{++$} insert via search" if DEBUG;

        my $n := self.search($v, $!origin);

        say "Search found the node {$n.WHICH}\n$n" if DEBUG;

        $n.insert-value($v);
        self!update-origin;

        $n;
    }

    method !update-origin {
        if not $!origin.parent === $!origin {
            $!origin := $!origin.parent;
        } elsif not $!origin.l.parent === $!origin {
            $!origin := $!origin.l.parent;
        } elsif not $!origin.r.parent === $!origin {
            $!origin := $!origin.r.parent;
        }
        say "origin is {$!origin.WHICH} and looks like:\n{~$!origin}" if DEBUG;
    }
}


# Leaf, TwoNode, and ThreeNode will all be lexically scoped. This is because
# they are designed to optimize the internal coding of Tree, rather than to
# provide any real use to a developer. For one thing, the containers change
# type all the time. That's not really ideal for an API.
#
# So I'm going to fudge all of that and lexically scope them to the Tree class.

use Test;

my $tree;
lives-ok { $tree = Tree.new },
    "Can create a Tree";

lives-ok { $tree.insert(9) },
    "Can insert a first value (9) into the Tree";

ok $tree.origin ~~ TwoNode,
    "The tree now has an origin of type TwoNode";

ok $tree.origin === $tree.origin.parent,
    "The parent of the tree's origin is the parent itself";

ok ($tree.origin.d[0] == 9 && +$tree.origin.d == 1) && $tree.origin,
    "The tree's origin has only one element and that element is 9 and the boolean context of tree's origin reflects this";

my $node;
lives-ok { $node := $tree.insert(5) },
    "Can insert a second value (5) into the Tree";

ok $node ~~ TwoNode,
    "The node returned by the insert operation is a TwoNode";

ok so $node,
    "The node is a valid TwoNode node per boolean context";

ok $node === $tree.origin,
    "This node is also the the origin of the tree";

ok $tree.origin.l.parent === $tree.origin,
    "The parent of origin.l is origin";

lives-ok { $node := $tree.insert(4) },
    "Can insert a third value (4) into the Tree, filling the TwoNode";

ok so $node,
    "The returned node is a valid TwoNode per boolean context";

ok $node === $tree.origin,
    "This node is still the origin of the tree";

ok $tree.origin.r.parent === $tree.origin,
    "The parent of origin.r is origin";

# Now for the ThreeNode ...

lives-ok { $node := $tree.insert(6) },
    "Can insert a fourth value (6) into the Tree";

ok $node ~~ TwoNode,
    "The returned node is still of type TwoNode";

ok so $node,
    "The node is a valid TwoNode as per boolean context";

ok $tree.origin ~~ TwoNode,
    "The origin of the Tree is still a TwoNode";


ok $node === $tree.origin,
    "The returned node is still the origin of the Tree";

lives-ok { $node := $tree.insert(1) },
    "Can insert a fifth value (1) into the Tree";

ok $node ~~ TwoNode,
    "The returned node is still a TwoNode";

ok so $node,
    "The node is a valid TwoNode as per boolean context";

ok $node === $tree.origin,
    "The returned node is still the origin of the Tree";

    #lives-ok { $node := $tree.insert(10) },
    #    "Can insert a sixth value (10) into the Tree";
    #
    #say $node if DEBUG;
