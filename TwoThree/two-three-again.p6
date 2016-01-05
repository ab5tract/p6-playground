#!/usr/bin/env perl6

role Nodal {
    has Int  @.d is rw;
    has Nodal $.l is rw;
    has Nodal $.r is rw;
    has Nodal $.parent is rw;

    method new(:$p?) { self.bless($p) }
}

class TwoNode does Nodal {

    submethod BUILD( :$p ) {
        $!parent := $p if $p;
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
    }
    multi method insert-value( $val where { $!l and $!r } ) {
        ...
    }
}

class Tree {
    has Nodal @.nodes;

    method search($v,$cursor?) {
        $cursor //= @!nodes[0];
        given $v {
            when $cursor ~~ TwoNode {
                when $cursor.d.contains(*)     { $cursor }
                when $cursor.l.d.contains(*)   { $cursor.l } 
                when $cursor.r.d.contains(*)   { $cursor.r }
                when * < $cursor.d[0]          { self.search($v,$cursor.l) }
                when * > $cursor.d[0]          { self.search($v,$cursor.r) }
            }
            #            when $cursor ~~ ThreeNode {
            #                ...
            #            }
        }
    }

    method insert($v where { not +@!nodes } ) {
        my $n = TwoNode.new;
        $n.insert-value($v);
        @!nodes.push: $n;
    }
}

use Test;

my $node;
lives-ok { $node = TwoNode.new }, "Can create a TwoNode";
lives-ok { $node.insert-value(9); dd $node }, "Can insert the value 9";

my $tree;
lives-ok { $tree = Tree.new }, "Can create a Tree";
lives-ok { $tree.insert(9); dd $tree }, "Can insert the value 9 into the Tree";
