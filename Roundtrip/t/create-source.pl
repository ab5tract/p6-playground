use strict;
use warnings;
use 5.16.1;

my $contents = "caf\x{65}\x{301}";
open my $fh, ">:encoding(UTF-8)", "source.txt";
print $fh $contents;
close($fh);
