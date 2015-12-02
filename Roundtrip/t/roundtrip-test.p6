use v6;

use lib './lib';

use Roundtrip;

my $roundtrip = roundtrip-slurp("t/source.txt");
say $roundtrip;
roundtrip-spurt("t/output.txt", $roundtrip);

my $source-hex = q:x{ hexdump t/source.txt };
my $output-hex = q:x{ hexdump t/output.txt };

.say for $source-hex, $output-hex;

use Test;

ok $source-hex eq $output-hex, "Source and output match on a byte level";

q:x{ rm t/output.txt };
