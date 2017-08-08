unit module Roundtrip;

use v6;

class Roundtrip::String is Str is Buf {
    has Buf $.original;
    has Str $.normalized;
    method Str { $!normalized };
    method Buf { $!original };
}

method roundtrip-slurp( $filename ) is export {
    my $bin-slurp = $filename.IO.slurp :bin;
    Roundtrip::String.new( :original($bin-slurp), :normalized($bin-slurp.Str) );
}

method roundtrip-spurt( $filename, Roundtrip::String $string ) is export {
    $filename.IO.spurt($string.original) :bin;
}
