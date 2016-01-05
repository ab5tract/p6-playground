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
        @!d == 1 and do when @!d[0] -> $v {
                [&&] $v X> $!l.d and not $!r
            or  [&&] $v X> $!l.d and [&&] $v X< $!r.d
        } 
    }

    multi method insert-value( $val where { not +@!d } ) {
        @!d.push: $val; 
    }
    multi method insert-value( $val where { $!l and $!r } ) {
        ...
    }
    multi method insert-value( $val where { @!d[0] and @!d[0] < $_ } ) {
        ...
    }
    multi method insert-value( $val where { @!d[0] and @!d[0] > $_ } ) {
        ...
    }
}

use Test;

my $node;
lives-ok { $node = TwoNode.new }, "Can create TwoNode.new";
lives-ok { $node.insert-value(9); dd $node }, "Can insert the value 9";
