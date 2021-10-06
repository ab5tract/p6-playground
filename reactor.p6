#!/usr/bin/env perl6

class R {
    has @.t;
    has Supplier $!supply .= new;

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

say "starting " ~  (my $start = now).DateTime.gist;
$r.begin;

say "filling";
await do for ^160 { start {  $r.insert( (^66).roll ) } }


say "finished " ~ (my $finish = now).DateTime.gist;
say "elapsed {$finish - $start}";
