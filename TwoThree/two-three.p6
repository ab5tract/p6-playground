#!/usr/bin/env perl6

class Node {
    has Int @.d;
    has Node $.l;
    has Node $.m;
    has Node $.r;

    method is-two-node {
        return False unless $!l and $!r;
        @!d == 1
            and [&&] @!d X> $!l.d
            and [&&] @!d X< $!r.d;
    }

    method is-three-node {
        return False unless [&&] $!l,$!r,$!m;
        @!d == 2
            and [&&] @!d X> $!l.d, $!r.d
            and [&&] @!d X< $!m.d;
    }
}

class Tree {
    has Node @.nodes;

    method insert(Int $n) {
        unless +@!nodes {
            @!nodes.push: Node.new(d => [$n]);
            return $n;
        }
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
    ok $t.insert(5) == 5, "Inserting returns inserted value";
}

test-it;
