#!/usr/bin/env perl6

class Node {
    has Int  @.d is rw;
    has Node $.l is rw;
    has Node $.m is rw;
    has Node $.r is rw;

    method is-two-node {
        return False unless $!l and $!r;
        @!d == 1
            and [&&] @!d X> $!l.d and [&&] @!d X< $!r.d;
    }

    method is-three-node {
        return False unless [&&] $!l,$!r,$!m;
        @!d == 2
            and [&&] @!d[0] X> $!l.d and [&&] @!d[0] X< $!m.d
            and [&&] @!d[1] X> $!m.d and [&&] @!d[1] X< $!r.d;
    }
}

class Tree {
    has @.nodes;
    has $!ct; # current-tree

    method insert(Int $i) {
        my ($node,$found);
        if +@!nodes {  
            if $!ct.is-two-node {
                ($node,$found) = self.search($i); 
                # ...
            } elsif $!ct.is-three-node {
                ($node,$found) = self.search($i); 
                # ...
            } else {
                # we can only be in this case when the tree only has one leaf
                #   aka $!ct := @!nodes[0] and $!ct.r is still undefined
                if $!ct.l {
                    # guess it's time to build the second node on our leaf
                    # little $!ct blossoms into a tree (todo: fact-check that)
                    if (my $d = $!ct.d[0]) > $i { 
                        $!ct.d[0] = $i;
                        $!ct.r = Node.new(d => [$d]);
                    } else {
                        $!ct.r = Node.new(d => [$i]);
                    }
                } else {
                    if (my $d = $!ct.d[0]) > $i {
                        $!ct.l = Node.new(d => [$i]);
                    } else {
                        $!ct.d[0] = $i;
                        $!ct.l = Node.new(d => [$d]);
                    }
                }
            }
        } else {
            @!nodes = [ Node.new(d => [$i]) ];
            $!ct := @!nodes[0];
        }
        $!ct := $node if $found;
        $!ct;
    }
        
    method search(Int $i) {
        return Nil unless +@!nodes;

        my $truthy = so [||] $!ct[0].d.map({ $_ == $i });
        return ($!ct[0],$truthy) if $truthy;

        gather for @!nodes -> $n {
            when $n.is-two-node { 
                #                given $n.d[0] {
            }
            when $n.is-three-node {
            }
            default { return $n };
        }
    }

    method prove {
        so do for @!nodes -> $n {
            $n.is-two-node or $n.is-three-node or +@!nodes == 1;
        }
    }

    method Str {
        @!nodes.perl;
    }
}


sub test-it {
    use Test;

    my $n;
    lives-ok { $n = Node.new }, "Can create a Node object";
    nok $n.is-two-node, ".is-two-node returns False without any nodes";
    nok $n.is-three-node, ".is-three-node returns False without any nodes";

    my $t;

    lives-ok { $t = Tree.new }, "Can create Tree object";
    ok $t.search(6) ~~ Nil, ".search(6) on leafless tree returns Nil";
    nok $t.prove, ".prove on leafless tree returns False";
    lives-ok {
        my $n = $t.insert(5); 
        $n.d[0] == 5;
    }, ".insert(5) returns the node containing the inserted value";
    ok do { 
        my ($n,$b) = $t.search(5);
        $n.d[0] == 5 and $b;
    },  ".search(5) on single leaf tree returns a Node and a True value";
    ok $t.insert(8), "Inserting a second value works";
    lives-ok {
        say ~$t;
    }, '~$t works';

    ok $t.nodes[0].d[0] > $t.nodes[0].l.d[0], "Top-level node is larger than it's L node";
    ok do {
        my $n = $t.insert(7);
        dd $n;
        $n.d[0] == 7;
    }, "Inserting a third value works";
    ok $t.nodes[0].is-two-node, ".is-two-node now returns True for the root node";
    nok $t.nodes[0].is-three-node, ".is-three-node still returns False for the root node";
    #    ok do {
    #        my ($n,$b) = $t.search(5);
    #        dd $n;
    #        $n.d[0] == 5;
    #    }, "Search for 5 (previously inserted value) returns the L node";
    ok $t.prove, ".prove returns True";
}

test-it;
