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
        my %ln;         # ln  = linked node
        my Int  $vfl;   # vfl = value for link
        if +@!d {
            if self.is-two-node {
                if $!l {
                    if (my $d = @!d[0]) && $d > $i
    
                            { %ln<ln> = 'r'; @!d[0] = $i; $vfl = $d }
                    else    { %ln<ln> = 'r'; $vfl = $i }
                } else {
                    if (my $d = @!d[0]) && $d > $i
    
                            { %ln<ln> = 'l'; $vfl = $i }
                    else    { %ln<ln> = 'l'; @!d[0] = $i; $vfl = $d }
                }
            } elsif self.is-three-node { # is-three-node !
                say "is a 3 node?";
            }
            dd %ln;
            self.insert-helper($vfl, :%ln);
        } else {
            @!d.push: $i;
        }
        self;
    }

    method AT-POS($idx) {
        @!d[$idx];
    }

    method new( :@d = [], :$p? ) { self.bless( @d, $p ) }
    submethod BUILD( :@!d, :$p ) { $!p := $p if $p }

    multi method insert-helper($i, :%ln) {
        given %ln<ln> {
            when 'l' {
                $!l ?? $!l.insert-value($i)
                    !! $!l = Node.new(d => [$i], p => self);
            }
            when 'm' {
                $!m ?? $!m.insert-value($i)
                    !! $!m = Node.new(d => [$i], p => self);
            }
            when 'r' {
                $!r ?? $!r.insert-value($i)
                    !! $!r = Node.new(d => [$i], p => self);
            }
            default { die "wtf gimme real vfls: %ln<ln>" }
        }    
    }
}

class Tree {
    has @.nodes;
    has $!ct; # current-tree

    method insert(Int $i) {
        my ($node,$found);
        #        if +@!nodes {  
        #            #    if $!ct.is-two-node {
        #            #        ($node,$found) = self.search($i); 
        #            #        # ...
        #            #    } elsif $!ct.is-three-node {
        #            #        ($node,$found) = self.search($i); 
        #            #        # ...
        #            #    } else {
        #            #    }
        #        } else {
            @!nodes.push: Node.new;
            @!nodes[0].insert-value($i);
            # }
        $!ct := @!nodes[0]; # if $found;
        $!ct;
    }
        
    method search(Int $i) {
        return Nil unless +@!nodes;
        dd $!ct;

        my $truthy = so $!ct.d.grep({ $_ == $i });
        return ($!ct, $truthy) if $truthy;

        for @!nodes -> $n {
            when $n.is-two-node { 

            }
            when $n.is-three-node {

            }
            default { return ($n, False) };
        }
    }

    method prove {
        [&&] do for @!nodes -> $n {
            $n.is-two-node or $n.is-three-node;
        }
    }

    method Str {
        @!nodes.perl;
    }
}


sub test-it {
    use Test;

    my $n;
    lives-ok { $n = Node.new; dd $n }, "Can create a Node object";
    ok $n.is-two-node, ".is-two-node returns True without any child nodes";
    nok $n.is-three-node, ".is-three-node returns False without any child nodes";

    my $t;

    lives-ok { $t = Tree.new }, "Can create Tree object";
    ok $t.search(6) ~~ Nil, ".search(6) on leafless tree returns Nil";
    ok $t.prove, ".prove on leafless tree returns True";
    lives-ok {
        my $n = $t.insert(5); 
        dd $n;
        dd $t;
        $n.d[0] == 5;
    }, ".insert(5) returns the node containing the inserted value";
    #    ok do { 
    #        my ($n,$b) = $t.search(5);
    #        $n.d[0] == 5 and $b;
    #    },  ".search(5) on single leaf tree returns a Node and a True value";
    ok $t.insert(8), "Inserting a second value works";
    lives-ok {
        say ~$t;
    }, '~$t works';

    ok do { dd $t.nodes[0].l; $t.nodes[0][0] > $t.nodes[0].l[0] }, "Top-level node is larger than it's L node";
    ok do {
        my $n = $t.insert(7);
        dd $t;
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
my $n = Node.new; dd $n;
test-it;
