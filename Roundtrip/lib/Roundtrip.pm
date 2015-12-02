unit module Roundtrip;

use v6;

class Roundtrip::String {
    has Buf $.original;
    has Str $.normalized;
    method Str { $!normalized };
    method Buf { $!original };
}

sub roundtrip-slurp( $filename ) is export {
    my $bin-slurp = $filename.IO.slurp :bin;
    my $str-slurp = $filename.IO.slurp;
    say $str-slurp;
    Roundtrip::String.new( :original($bin-slurp), :normalized($str-slurp) );
}

sub roundtrip-spurt( $filename, Roundtrip::String $roundtrip ) is export {
    $filename.IO.spurt($roundtrip.original) :bin;
}
