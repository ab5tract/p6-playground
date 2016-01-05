#!/usr/bin/env perl6

class Leaf      { ... }
class TwoNode   { ... }
#class ThreeNode { ... }

role Nodal {
    has Int   @.d is rw;
    has Nodal $.parent is rw;

    method new(:@d?, :$parent?) { self.bless(:@d,:$parent) }
}

class Leaf does Nodal {
    submethod BUILD( :@d, :$parent ) {
        die "Cannot have a leaf with more than one value" if +@d > 1;
        @!d = @d if @d;
        $!parent := $parent if $parent;
    }

    multi method insert-value( $val where { not +@!d } ) {
        @!d.push: $val;
        self;
    }
    multi method insert-value( $val where { +@!d } ) {
        TwoNode.new( d => [@!d[0],$val], :$!parent);
    }
}

class TwoNode does Nodal {
    has Nodal $.l is rw;
    has Nodal $.r is rw;
    has Int $.d1;

    submethod BUILD( :@d, :$parent  ) {
        if +@d > 1 {
            if @d[0] > @d[1] {
                my $d = [ @d[1]:delete ];
                $!l := Leaf.new(:$d, parent => self);
            } else {
                my $d = [ @d[0]:delete ];
                $!l := Leaf.new(:$d, parent => self);
            }
        }
        @!d = @d;
        $!d1 := @!d[0];
    }

    method Bool {
        !$!l and $!r or
        @!d == 1 and -> $v {
                [&&] $v X> $!l.d and not $!r
            or  [&&] $v X> $!l.d and [&&] $v X< $!r.d
        }, @!d[0]; 
    }

    multi method insert-value( $val where { not +@!d } ) {
        @!d.push: $val; 
    }
    multi method insert-value( $val where { $val X> $!l.d and not $!r } ) {
        if $val > $!d1 {
            $!r := Leaf.new(d => $val, parent => self);
        } else {
            $!r := Leaf.new(d => $!d1, parent => self);
            $!d1 = $val;
        }
    }
    multi method insert-value( $val where { $!l and $!r } ) {
        ...
    }
}

class Tree {
    has Nodal @.nodes;

    method search($v, $cursor is rw) {
        given $v {
            when { $cursor.d.contains($_) }          { $cursor }
            # if it doesn't contain, and is a Leaf, we will return the cursor
            when $cursor ~~ Leaf                {
                return-rw $cursor;
            }
            when $cursor ~~ TwoNode {
                when { $cursor.l.d.contains($_) }    { $cursor.l } 
                when { $cursor.r.d.contains($_) }    { $cursor.r }
                when * < $cursor.d[0]           { self.search($v,$cursor.l) }
                when * > $cursor.d[0]           { self.search($v,$cursor.r) }
            }
            #            when $cursor ~~ ThreeNode {
            #                ...
            #            }
        }
    }

    multi method insert($v where { not +@!nodes }) {
        my $n = Leaf.new;
        $n.insert-value($v);
        @!nodes.push: $n;
    }

    multi method insert($v) {
        my $n := self.search($v,@!nodes[0]);
        my $m = $n.insert-value($v);
        $n = $m;
    }
}

use Test;

my $leaf;
lives-ok { $leaf = Leaf.new }, "Can create a Leaf";
lives-ok { $leaf.insert-value(9); dd $leaf }, "Can insert a 9 into a Leaf";
ok $leaf.insert-value(8) ~~ TwoNode, "Inserting a second value creates and returns a TwoNode";

my $node;
lives-ok { $node = TwoNode.new }, "Can create a TwoNode";
lives-ok { $node.insert-value(9); dd $node }, "Can insert a 9 into the TwoNode";

my $tree;
lives-ok { $tree = Tree.new }, "Can create a Tree";
lives-ok { $tree.insert(9); dd $tree }, "Can insert a 9 into the Tree";
lives-ok { $tree.insert(5); dd $tree }, "Can insert a 5 into the Tree";
#lives-ok { $tree.insert(3); dd $tree }, "Can insert a 3 into the Tree";

