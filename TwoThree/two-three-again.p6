#!/usr/bin/env perl6

constant DEBUG = @*ARGS.contains(<debug>) // 0;

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
        return-rw $SELF;
    }

    method ThreeNode($SELF is rw : @d) {
        @d .= sort;
        say "Attempting to promote {$SELF.WHICH} to ThreeNode with d=[{@d}]" if DEBUG;
        $SELF = ThreeNode.new(d => @d, parent => self!pass-parent);
        say "Successful promotion to {$SELF.WHICH}.\n$SELF" if DEBUG;
        return-rw $SELF;
    }

    method !pass-parent {
        my $parent;
        if not $!parent === self {
            $parent := $!parent;
        }
        return-rw $parent;
    }

    method !all-values {
        [@!d];
    }

    method gist {
        "{self.WHICH}: [{self!all-values}]";
    }
    method Str { self.gist }
}

class Leaf does Nodal {
    submethod BUILD(:@d, :$parent ) {
        @!d = @d // [];
        say "{self.WHICH} Leaf constructor was passed parent {$parent.WHICH}" if DEBUG;
        $!parent = (defined $parent) ?? $parent !! self;
    }

    multi method insert-value($SELF is rw : $val where { not +@!d }) {
        @!d = [$val];
        return-rw $SELF; 
    }

    multi method insert-value($SELF is rw : $val where { +@!d == 1 }) {
        @!d = [sort $val, @!d];
        return-rw $SELF;
    }

    multi method insert-value($SELF is rw : $val where { $!parent === self && +@!d == 2 }) {
        return-rw $SELF.TwoNode([|@!d, $val]);
    }

    multi method insert-value($SELF is rw : $val where { $!parent !=== self }) {
        return-rw $!parent.insert-value($val);
    }

    method Bool {
        say "Checking validity of {self.WHICH}" if DEBUG;
        so +@!d <= 2;
    }
}

class TwoNode does Nodal {
    has Nodal $.l is rw;
    has Nodal $.r is rw;
    has Int $.d1;

    multi submethod BUILD($SELF is rw : :@d where *.elems > 3, :$parent) {
        $SELF.ThreeNode(@d);
    }

    multi submethod BUILD(:@d where *.elems == 3, :$parent) {
        my ($l-d, $r-d) = [@d.shift], [@d.pop];
        self!build-helper(:$l-d, :$r-d, :@d, :$parent);
    }

    multi submethod BUILD(:@d where *.elems == 2, :$parent) {
        my $l-d = @d[0] > @d[1] ?? [@d.pop] !! [@d.shift];
        self!build-helper(:$l-d, :@d, :$parent);
    }

    multi submethod BUILD(:@d where *.elems == 1, :$parent) {
        self!build-helper(:@d, :$parent);
    }

    method !build-helper(:$l-d = [], :$r-d = [], :@d, :$parent) {
        $!l = Leaf.new(d => $l-d, parent => self);
        $!r = Leaf.new(d => $r-d, parent => self);
        @!d = @d;
        $!d1 := @!d[0];
        $!parent = (defined $parent) ?? $parent !! self;
    }

    method !all-values {
        [ |$!l.d, |$!r.d, |@!d ];
    }

    multi method insert-value($SELF is rw : $val) {
        return-rw $SELF.TwoNode([ |$SELF!all-values, $val ]);
    }

    multi method insert-value($SELF is rw : $val where { +$!l.d == 2 and $val < $!d1 }) {
        my @opts = sort |@!d, $val, |$!l.d;
        my ($l-d, $self-d, $m-d) = [@opts.shift] xx 3;
        $self-d.push: @opts.shift;

        my $three-node = ThreeNode.new(d => $self-d);
        $three-node.l = Leaf.new(d => $l-d, parent => $three-node);
        $three-node.m = Leaf.new(d => $m-d, parent => $three-node);
        $!r.parent = $three-node;
        $three-node.r = $!r;

        $SELF = $three-node;
        return-rw $SELF.l;
    }

    multi method insert-value($SELF is rw : $val where { +$!r.d == 2 and $val > $!d1 }) {
        my @opts = sort |@!d, $val, |$!r.d;
        my ($r-d, $self-d, $m-d) = [@opts.pop] xx 3;
        $self-d.unshift: @opts.pop;

        my $three-node = ThreeNode.new(d => $self-d);
        $three-node.r = Leaf.new(d => $r-d, parent => $three-node);
        $three-node.m = Leaf.new(d => $m-d, parent => $three-node);
        $!l.parent = $three-node;
        $three-node.l = $!l;

        $SELF = $three-node;
        return-rw $SELF.r;
    }

    method gist {
        qq:to/END/;
        Node {self.WHICH}
            d: [{@!d}]
            l: [{$!l.d}] ({$!l.WHICH})
            r: [{$!r.d}] ({$!r.WHICH})
        END
    }

    method Bool {
        say "Checking validity of {self.WHICH}" if DEBUG;
        +@!d == 1 && (so $!l && so $!r) &&
            ([&&] $!d1 X> $!l.d and not $!r)
            ||
            ([&&] $!d1 X> $!l.d and [&&] $!d1 X< $!r.d);
    }
}

class ThreeNode does Nodal {
    has Nodal $.l is rw;
    has Nodal $.m is rw;
    has Nodal $.r is rw;
    has Int $.d1;
    has Int $.d2;

    multi submethod BUILD(:@d where *.elems == 2, :$parent) {
        self!build-helper(:@d, :$parent);
    }

    multi submethod BUILD(:@d where *.elems == 4, :$parent) {
        my $l-d = [ @d.shift ];
        my $r-d = [ @d.pop ];
        self!build-helper(:@d, :$parent, :$l-d, :$r-d);
    }

    multi submethod BUILD(:@d where *.elems == 5, :$parent ) {
        my $l-d = [ @d.shift ];
        my $r-d = [ @d.pop ];
        my @final-d = [ @d.shift, @d.pop ];
        my $m-d = [ @d.pop ]; # the middle one pops last
        @d = @final-d;
        self!build-helper(:@d, :$parent, :$l-d, :$r-d, :$m-d);
    }

    #    multi submethod BUILD(:@d where *.elems == 6, :$parent ) {
    #        my $l-d = [ @d.shift ];
    #        my $r-d = [ @d.pop ];
    #        my @final-d = [ @d.shift, @d.pop ];
    #        my $m-d = [ @d ]; # the middle one pops last
    #        @d = @final-d;
    #        self!build-helper(:@d, :$parent, :$l-d, :$r-d, :$m-d);
    #    }

    method !build-helper(:@d, :$parent, :$l-d = [], :$r-d = [], :$m-d = []) {
        $!l = Leaf.new(d => $l-d, parent => self);
        $!r = Leaf.new(d => $r-d, parent => self);
        $!m = Leaf.new(d => $m-d, parent => self);

        @!d = @d;
        $!d1 := @!d[0];
        $!d2 := @!d[1];
        $!parent = (defined $parent) ?? $parent !! self;
    }

    method !insert-helper($n, $val) { ... }

    multi method insert-value($SELF is rw : $val where { not +$!m.d }) {
        return-rw $SELF.ThreeNode( [$SELF!all-values.Slip, $val] );
    }

    multi method insert-value($SELF is rw : $val where { $val < $!d1 }) {
        return-rw (+$!l.d == 1) ?? $!l.insert-value($val)
                                !! self!insert-helper($!l, $val);
    }

    multi method insert-value($SELF is rw : $val where { $!d1 < $val < $!d2 }) {
        return-rw (+$!m.d == 1) ?? $!m.insert-value($val)
                                !! self!insert-helper($!m, $val);
    }

    multi method insert-value($SELF is rw : $val where { $val > $!d2 }) {
        return-rw (+$!r.d == 1) ?? $!m.insert-value($val)
                                !! self!insert-helper($!r, $val);
    }

    method !all-values {
        [|$!l.d, |$!r.d, |$!m.d, |@!d];
    }

    method gist {
        qq:to/END/;
        Node: {self.WHICH}
            d: [{@!d}]
            l: [{$!l.d}] ({$!l.WHICH})
            m: [{$!m.d}] ({$!m.WHICH})
            r: [{$!r.d}] ({$!r.WHICH})
        END
    }

    method Bool {
        say "Checking validity of {self.WHICH}" if DEBUG;
        +@!d == 2 && (so $!l && so $!m && so $!r) &&
            (not +$!m.d and [&&] $!d1 X> $!l.d and [&&] $!d2 X< $!r.d)
            ||
            ([&&] $!d1 X> $!l.d and [&&] $!d1 X< $!m.d and
             [&&] $!d2 X> $!m.d and [&&] $!d1 X< $!r.d);
    }
}

class Tree {
    has Nodal $.origin is rw = Leaf.new;

    method search($val, $cursor is rw) {
        given $val {
            when { $cursor.d.contains($_) }          { $cursor }
            # if it doesn't contain $val, and is a Leaf, we will return the cursor
            when $cursor ~~ Leaf                     { return-rw $cursor }
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

    multi method insert($v where { not +$!origin.d }) {
        my $node := $!origin.insert-value($v);
        say "Tree origin is {self.WHICH} after insert and looks like:\n{~self}" if DEBUG;
        return-rw $node;
    }

    multi method insert($v) {
        say "{++$} insert via search" if DEBUG;
        my $n := self.search($v, $!origin);
        say "Search found the node {$n.WHICH}\n$n" if DEBUG;
        $n .= insert-value($v);
        self!update-origin;
        return-rw $n;
    }

    multi method insert(*@vals) {
        self.insert($_) for @vals;
    }

    method !update-origin {
        if $!origin ~~ Leaf {
            if not $!origin.parent === $!origin {
                $!origin := $!origin.parent;
                say "Updated origin to {$!origin.WHICH}" if DEBUG;
            }
        } else {
            if not $!origin.parent === $!origin {
                $!origin := $!origin.parent;
            } elsif not $!origin.l.parent === $!origin {
                $!origin := $!origin.l.parent;
            } elsif not $!origin.r.parent === $!origin {
                $!origin := $!origin.r.parent;
            }
            say "Updated origin to {$!origin.WHICH}" if DEBUG;
        }
        say "origin is {$!origin.WHICH} and looks like:\n{~$!origin}" if DEBUG;
    }

    method contains($val) {
        self.search($val, $!origin).d.contains($val);
    }

    method AT-KEY($val) {
        self.contains($val);
    }

    method Bool {
        say "Checking the validity of {~$!origin}" if DEBUG;
        so $!origin;
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

ok $tree.origin === $tree.origin.parent,
    "The parent of the tree's origin is also the tree's origin itself";

my $node;
lives-ok { $node := $tree.insert(7) },
    "Can insert a first value (7)";

ok $node ~~ Leaf,
    "The returned node of first-value-insert is a Leaf";

ok $node === $tree.origin,
    "The returned node of first-value-insert is the Tree's origin";

ok $tree.origin === $tree.origin.parent,
    "The parent of the tree's origin is also the tree's origin itself";

lives-ok { $node := $tree.insert(5) },
    "Can insert a second value (5)";

ok $node ~~ Leaf,
    "The returned node of second-value-insert is a Leaf";

ok $node === $tree.origin,
    "The returned node of second-value-insert is the Tree's origin";

ok $tree.origin === $tree.origin.parent,
    "The parent of the tree's origin is also the tree's origin itself";

my $pre-promoted-node := $node;
lives-ok { $node := $tree.insert(6) },
    "Can insert a third value (6)";

ok $node ~~ TwoNode,
    "The returned node of third-value-insert is a TwoNode";

ok so $node,
    "The returned node of third-value-insert is a valid TwoNode  (returns True in Boolean context)";

ok $node === $tree.origin,
    "The returned node of third-value-insert is the Tree's origin";

ok $tree.origin === $tree.origin.parent,
    "The parent of the Tree's origin is also the Tree's origin itself";

lives-ok { $node := $tree.insert(3) },
    "Can insert a fourth value (3)";

lives-ok { $node := $tree.insert(8) },
    "Can insert a fifth value (8)";

lives-ok { $node := $tree.insert(4) },
    "Can insert a sixth value (4) which will result in creating a ThreeNode based on a full left node";

ok $node === $node.parent.l && $node === $tree.origin.l,
    "sixth-value-insert occurred on the left node of the Tree's origin";

ok $node ~~ Leaf && +$node.d == 1,
    "The return value of sixth-value-insert is a Leaf containing only one value";

ok $tree.origin ~~ ThreeNode,
    "The Tree's origin after sixth-value-insert is a ThreeNode";

ok so $node, 
    "The returned node of sixth-value-insert is a valid Leaf (returns True in Boolean context)";

ok $tree<4> && $tree.contains(4),
    ".contains(4) returns True in both method and AT-KEY forms";

ok !$tree<14> && !$tree.contains(14),
    "Tree does not .contains(14) or AT-KEY<14> (non-existent value doesn't exist)";

ok so $tree,
    "Tree is valid according to the validity of the descendants of its origins";

lives-ok { $node := $tree.insert(1) },
    "Can insert a seventh value (1)";

ok $node ~~ Leaf && +$node.d == 2,
    "The returned node of seventh-value-insert is a Leaf with two values";

ok $node.parent ~~ ThreeNode && $node.parent === $tree.origin,
    "The parent of the returned node is a ThreeNode and that ThreeNode is the Tree's origin";

ok so $tree,
    "The Tree is valid";

say $tree.origin;
say $node;

my $other-tree = Tree.new;

lives-ok { $other-tree.insert(|(^7)) },
    "Can create an other Tree and .insert 5 values at once";

ok so $other-tree,
    "Other Tree is valid (True in Boolean context)";

    # broken
    #lives-ok { $other-tree.insert(2,3,9,4,21,11) },
    #    "Can create an other Tree and .insert 6 values at once";
