#!/usr/bin/env perl6

use Test;

use Secret;

ok right-strip([0,5,0,5,0,0,0], 0) ~~ [0,5,0,5], 'right-strip: removes zeroes as expected';

nok right-strip([0,5,0,5,0,0,0], 5) ~~ [0,5,0,5], 'right-strip: changing the removal value works (difference)';

ok right-strip([0,5,0,5,0,0,0], 5) ~~ [0,5,0,5,0,0,0], 'right-strip: changing the removal value works (equality)';

ok right-pad([6], [5,5]) ~~ ([6,0], [5,5]), 'right-pad: can correct the length when the first list is shorter';

ok right-pad([6,6,7,8], [5]) ~~ ([6,6,7,8], [5,0,0,0]), 'right-pad: can correct the length when the second list is shorter';

done-testing;
