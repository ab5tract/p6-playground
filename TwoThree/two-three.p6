#!/usr/bin/env perl6

class Node {
    has Int  @.d is rw;
    has Node $.p is rw;

    has Node $.l is rw;
    has Node $.m is rw;
    has Node $.r is rw;

    method is-two-node {
        not ($!l and $!r and +@!d)
            or  @!d == 1
            and [&&] @!d X> $!l.d and not $!r
            or  [&&] @!d X> $!l.d and [&&] @!d X< $!r.d;
    }

    method is-three-node {
        return False unless [&&] $!l,$!r,$!m,+@!d;
        @!d == 2
            and [&&] @!d[0] X> $!l.d and [&&] @!d[0] X< $!m.d
            and [&&] @!d[1] X> $!m.d and [&&] @!d[1] X< $!r.d;
    }

    method insert-value(Int $i) {
        my Int  $vfl;   # vfl = value for link
        if +@!d {
            if self.is-two-node {
                if not ($!l and +$!l.d) {
                    self.insert-helper(@!d[0],$i,ln=>'l');
                } else {
                    self.insert-helper(@!d[0],$i,ln=>'r');
                }
            } elsif self.is-three-node { # is-three-node !
                say "is a 3 node?";
            }
        } else {
            @!d.push: $i;
        }
        self;
    }

    method AT-POS($idx) {
        @!d[$idx];
    }

    method new( :$p? ) { self.bless( $p ) }
    submethod BUILD( :$p ) { $!p := $p if $p }

    method insert-helper($d, $i, :$ln) {
        my $vfl = $i;
        #dd $ln,$i,$d;
        given $ln {
            when 'l' {
                $!l //= Node.new(p => self);
                if my $d = @!d[0] and $d < $i {
                    @!d[0] = $i;
                    $vfl = $d;
                }
                return $!l.insert-value($vfl);
            }
            when 'm' {
                $!m //= Node.new(d => [$i], p => self);
                $!m.insert-value($i);
            }
            when 'r' {
                $!r //= Node.new(p => self);
                    if my $d = @!d[0] and $d > $i {
                        @!d[0] = $i;
                        $vfl = $d;
                    }
                $!r.insert-value($vfl);
            }
            default { die "wtf gimme real vfls, not: $vfl" }
        }    
    }
}

class Tree {
    has @.nodes;
    has $!ct; # current-tree

    method insert(Int $i) {
        @!nodes.push(Node.new) if not +@!nodes;
        $!ct := @!nodes[0] if not $!ct;
        my $found = self.search($i);
        $!ct.insert-value($i);
        $!ct;
    }

    method search(Int $i, Node $n?) {
        return Nil unless +@!nodes;

        my $truthy = so $!ct.d.grep(*==1);
        return ($!ct, $truthy) if $truthy;

        for @!nodes -> $n {
            when $n.is-two-node { 
                # ...
            }
            when $n.is-three-node {
                # ...
            }
            default { return ($n, False) };
        }
    }

    method prove {
        [&&] do for @!nodes -> $n {
            $n.is-two-node or $n.is-three-node;
        }
    }

    method AT-POS($i) {
        @!nodes[$i];
    }

    method Str {
        @!nodes.perl;
    }
}


sub test-it {
    use Test;

    my $n;
    lives-ok { $n = Node.new }, "Can create a Node object";
    ok $n.is-two-node, ".is-two-node returns True without any child nodes";
    nok $n.is-three-node, ".is-three-node returns False without any child nodes";

    my $t;

    lives-ok { $t = Tree.new }, "Can create Tree object";
    ok $t.search(6) ~~ Nil, ".search(6) on leafless tree returns Nil";
    ok $t.prove, ".prove on leafless tree returns True";
    lives-ok {
        my $n = $t.insert(5); 
        $n.d[0] == 5;
    }, ".insert(5) works returns the node containing the inserted value";
    #    ok do { 
    #        my ($n,$b) = $t.search(5);
    #        $n.d[0] == 5 and $b;
    #    },  ".search(5) on single leaf tree returns a Node and a True value";
    ok do {
        $t.insert(8);
        dd $t[0];
        $t[0].l[0] == 5 and $t[0][0] == 8; # lowest value;
    }, ".insert(8) works and the structure of the tree is sound";
    lives-ok {
        say ~$t;
    }, '~$t works';

    ok do { $t.nodes[0][0] > $t.nodes[0].l[0] }, "Top-level node is larger than it's L node";
    ok do {
        my $n = $t.insert(7);
        say ~$t;
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
    #    ok so $t.search(
}

test-it;
