#!/usr/bin/env perl6

class Decorator is Callable {
    has &.funk;
    has @.history;
    has $.cached-result;

    multi method new(&funk, @history = []) {
        self.bless(:&funk, :@history);
    }

    method wrap-with(&funk) {
        my &new-funk = &funk ~~ Decorator ?? { &funk.funk(&!funk) } !! { &funk(&!funk) };
        return Decorator.new(&new-funk);
    }

    method push-wrap(&funk) {
        my &new-funk = &funk ~~ Decorator ?? &funk.funk !! &funk;
        return Decorator.new(&new-funk, [|@!history, &!funk]);
    }

    method CALL-ME(*@args) {
        if @!history > 1 {
            return $!cached-result //= do {
                my &tmp = Decorator.new({ &!funk(@args) });
                for @!history -> $h {
                    &tmp = &tmp.wrap-with($h);
                }
                &tmp();
            }
        } else {
            $!cached-result //= &!funk(@args);
        }
    }
}

my $foo = { "hi" };
my &foo = Decorator.new($foo);

my &wrapped = &foo.wrap-with(&b);

say wrapped;

sub b(&f)   { "<b>" ~ &f() ~ "</b>" }
sub em(&f)  { "<em>" ~ &f() ~ "</em>" }
sub div(&f) { "<div>" ~ &f() ~ "</div>" }

my &t = &wrapped.wrap-with(&em).wrap-with(&div);
say t;

# infix for going from right to left (inner to outer)
sub infix:<DEC> (&a is copy, &b) {
    &a = Decorator.new(&a) unless &a ~~ Decorator;
    return &a.wrap-with(&b);
}

my &text = { "bold emotional text in a div" } DEC &b DEC &em DEC &div;
say text;

# infix for specifying the wrappers in order (inner to outer) but with the final sub last
sub infix:<♫>(&a is copy, &b) {
    &a = Decorator.new(&a) unless &a ~~ Decorator;
    return &a.push-wrap(&b);
}

my &text2 = &em ♫ &div ♫ &b ♫ { "similar emotional text, in a bold div" };
say text2;

my &text3 = &div ♫ &div ♫ &div ♫ sub ($a) { "three divs surrounding this text which displays arg '{ $a }'" };
say text3("foofoo");
