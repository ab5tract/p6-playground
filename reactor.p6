#!/usr/bin/env perl6

class R {
    has @.t;
    has Supply $!supply .= new;

    method begin {
        start {
            react {
                whenever $!supply -> $v {
                    say $v;
                    push @!t, $v;
                    dd @!t;
                }
            }
        }
    }

    method insert($v) {
        $!supply.emit($v);
    }
}

my $r = R.new;

say "starting";
$r.begin;

say "filling";
for ^70 {  sleep (^2.0).roll; $r.insert( (^66).roll ); }
