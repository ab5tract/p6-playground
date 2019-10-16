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

$p = Polynomial.new: [1, 2, 3];
$f = Polynomial.new: [4, 5, 6];
ok ($p * $f) ~~ Polynomial.new([4, 13, 28, 27, 18]),
	'polynomial: inline:<*> works as expected for two polynomials';
ok ($f * $p) ~~ Polynomial.new([4, 13, 28, 27, 18]),
	'polynomial: inline:<*> works as expected for two polynomials (reflexivity)';

ok ~$p eq '1 + 2x + 3x^2',
	"polynomial: stringification works as expected ({~$p})";

ok $p(1) == 6,
 	"polynomial: CALL-ME evaluates for x = 1 ({$p(1)})";
ok $p(2) == 17,
	"polynomial: CALL-ME evaluates for x = 2 ({$p(2)})";

done-testing;
