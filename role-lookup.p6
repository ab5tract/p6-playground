
use v6.c;

role Lookup {
    has %!lookup;

    method check($value) {
        %!lookup ||= (@(self) Z=> True);
        so %!lookup{$value};
    }
}

use Test;

my @heros := [<Frodo Bilbo Samwise>] but Lookup;
ok @heros.check(<Frodo>), "Frodo is a hero";
nok @heros.check(<Suaron>), "Sauron is not a hero";
