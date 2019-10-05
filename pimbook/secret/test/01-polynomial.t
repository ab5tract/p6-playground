#!/usr/bin/env perl6

use Test;
use Secret;

my $p;
lives-ok {
    $p = Polynomial.new([0,4,5,9,0]);
}, 'polynomial: can create a new object without issue';

ok $p.coefficients ~~ [0,4,5,9],
    'polynomial: coefficients have been properly reduced from rhs zeroes';

my $f = Polynomial.new([0,3,4,5]);

ok ($p + $f) ~~ Polynomial.new([0,7,9,14]),
	'polynomial: inline:<+> works as expected for two polynomials';

ok ($f + $p) ~~ Polynomial.new([0,7,9,14]),
	'polynomial: inline:<+> works as expected for two polynomials (reflexivity)';

dd $p * $f;
ok ($p * $f) ~~ Polynomial.new([0,12,20,45]),
	'polynomial: inline:<*> works as expected for two polynomials';

done-testing;
