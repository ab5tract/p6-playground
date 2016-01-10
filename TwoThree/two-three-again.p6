#!/usr/bin/env perl6

constant DEBUG = 1;

class Leaf      { ... }
class TwoNode   { ... }
class ThreeNode { ... }

role Nodal {
    has Int   @.d is rw;
    has Nodal $.parent is rw;

    method new(:@d?, :$parent?) { self.bless(:@d, :$parent) }

    method TwoNode($SELF is rw : @d where so *.elems == 2|3) {
        $SELF = TwoNode.new(d => @d, parent => self!pass-parent);
    }
    method ThreeNode($SELF is rw : @d where so *.elems == 3|4|5) {
        $SELF = ThreeNode.new(d => @d, parent => self!pass-parent);
    }

    method !pass-parent {
        my $parent;
        if not $!parent === self {
            $parent := $!parent;
        }
    }
}

class Leaf does Nodal {
    submethod BUILD( :@d, :$parent ) {
        @!d = @d // [];
        say "{self.WHICH} Leaf constructor was passed parent {$parent.WHICH}" if DEBUG;
        if defined $parent {
            $!parent = $parent;
        } else {
            $!parent = self;
        }
    }

    multi method insert-value( $val where { not +@!d } ) {
        say "inserting $val in {self.WHICH} (first value)" if DEBUG;
        @!d.push: $val;
        self;
    }
    multi method insert-value($SELF is rw : $val where { +@!d } ) {
        say "creating a new TwoNode with $val from {self.WHICH}" if DEBUG;
        $SELF.TwoNode( [@!d[0], $val] );
    }

    method Bool {
        so +@!d == 1;
    }
}

class TwoNode does Nodal {
    has Nodal $.l is rw;
    has Nodal $.r is rw;
    has Int $.d1;

    submethod BUILD( :@d, :$parent  ) {
        my ($ld, $rd);
        die "Cannot build a TwoNode with more than 3 values" if +@d > 3;
        @d .= sort;
        if +@d > 1 {
            if +@d > 2 {
                $rd = [ @d.pop ];
                $ld = [ @d.shift ];
            } else {
                if @d[0] > @d[1] {
                    $ld = [ @d.pop ];
                } else {
                    $ld = [ @d.shift ];
                }
            }
        }
        $!l = Leaf.new(d => $ld // [], parent => self);
        $!r = Leaf.new(d => $rd // [], parent => self);
        @!d = @d;
        $!d1 := @!d[0];

        if defined $parent {
            $!parent = $parent;
        } else {
            $!parent = self;
        }
    }

    method Bool {
        +@!d == 1 &&
            ([&&] $!d1 X> $!l.d and not $!r)
            ||
            ([&&] $!d1 X> $!l.d and [&&] $!d1 X< $!r.d);
    }

    multi method insert-value( $val where { not +@!d } ) {
        say "inserting $val where not @!d in {self.WHICH}" if DEBUG;
        @!d.push: $val; 
        self;
    }

    multi method insert-value( $val where { not $!r.d and [&&] $val X> $!l.d } ) {
        say "inserting $val on in, with a d1 of $!d1 and and l.d of {$!l.d} in {self.WHICH}" if DEBUG;
        if $val > $!d1 {
            $!r.insert-values($val);
        } else {
            $!r.insert-value($!d1);
        }
        self;
    }

    multi method insert-value( $val where { not $!r.d and [&&] $val X< $!l.d } ) {
        say "inserting a smaller value $val in {self.WHICH}" if DEBUG;
        my @old-ld = $!l.d;
        # we use this slice syntax so that we aren't replacing containers
        # and the $!d1 bind will point to the proper place.
        $!l.d[*] = $val;
        $!r.d[ @!d.keys ] = @!d[*];
        @!d[*] = @old-ld[*];
        self;
    }

    multi method insert-value( $SELF is rw : $val where { +$!l.d and +$!r.d } ) {
        $SELF.ThreeNode( [|$!l.d, |@!d, |$!r.d, $val] );
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
        my ($l-d, $m-d, $r-d);
        my $max = @d.pop;
        my $min = @d.shift;

        if +@d == 3 {
            say "hello big boy!";
            my @final-d = [ @d.shift, @d.pop ];
            $m-d = [ @d.pop ]; # the middle one pops last
            @d = @final-d;
        }

        @!d = @d;
        $!d1 := @!d[0];
        $!d2 := @!d[1];

        $l-d = [$min];
        $r-d = [$max];
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

    multi method insert-value($SELF is rw : $val where { not +$!m.d } ) {
        #        $!m.insert-value($val);
        $SELF.ThreeNode( [|$!l.d, |@!d, |$!r.d, $val] );
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
        say "origin insert" if DEBUG;
        $!origin.insert-value($v);
    }

    multi method insert($v) {
        if DEBUG {
            say "{++$} insert via search";
            dd $!origin;
        }

        my $n := self.search($v, $!origin);

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

ok $tree.origin ~~ Leaf,
    "The tree now has an origin of type Leaf";

ok $tree.origin === $tree.origin.parent,
    "The parent of the tree's origin is the parent itself";

ok ($tree.origin.d[0] == 9 && +$tree.origin.d == 1) && $tree.origin,
    "The tree's origin has only one element and that element is 9 and the boolean context of tree's origin reflects this";

my $node;
lives-ok { $node := $tree.insert(5) },
    "Can insert a second value (5) into the Tree";

dd $tree if DEBUG;

ok $node ~~ TwoNode,
    "The node returned by the insert operation is a TwoNode";

ok so $node,
    "The node is a valid TwoNode node per boolean context";

ok $node === $tree.origin,
    "This node is also the the origin of the tree";

ok $tree.origin.l.parent === $tree.origin,
    "The parent of origin.l is origin";

lives-ok { $node := $tree.insert(3) },
    "Can insert a third value (4) into the Tree, filling the TwoNode";

dd $node if DEBUG;

ok so $node,
    "The returned node is a valid TwoNode per boolean context";

ok $node === $tree.origin,
    "This node is still the origin of the tree";

ok $tree.origin.r.parent === $tree.origin,
    "The parent of origin.r is origin";

# Now for the ThreeNode ...

lives-ok { $node := $tree.insert(6) },
    "Can insert a fourth value (6) into the Tree";

ok $node ~~ ThreeNode,
    "The node is now of type ThreeNode";

ok $node === $tree.origin,
    "The returned node is also the origin.";

lives-ok { $node := $tree.insert(1) },
    "Can insert a fifth value (1) into the Tree";

dd $node;

#lives-ok { $node := $tree.insert(10) },
#    "Can insert a sixth value (10) into the Tree";

dd $tree if DEBUG;
