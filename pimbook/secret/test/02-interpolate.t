#!/usr/bin/env perl6

use Test;

use Secret;

ok interpolate([1,2]) ~~ Polynomial.new([2]),
	"interpolate: acts as expected for [1,2]";
ok interpolate([1,2], [2,3]) ~~ Polynomial.new([1,1]),
	"interpolate: acts as expected for [1,2], [2,3]";
