use Test;

sub overlaps-with( $r1, $r2 ) { 
    my @types := do for flat $r1.bounds,$r2.bounds { .WHAT };

    # this corner case of mismatched types still imperfect
    return False
        if my $some-infinity = ($r1.infinite or $r2.infinite) and @types.grep(not * ~~ Num).unique > 1;

    my $type := [&&] @types >>~~>> Numeric ?? Numeric !! @types[0];

    if $some-infinity {
        if $r1.infinite and $r2.infinite {
            my $r1-idx = $r1.bounds.first-index({ not $_ ~~ Numeric or not $_ ~~ Inf and not $_ ~~ -Inf });
            my $r2-idx = $r2.bounds.first-index({ not $_ ~~ Numeric or not $_ ~~ Inf and not $_ ~~ -Inf });

            my $r1-v = $r1.bounds[ $r1-idx ];
            my $r2-v = $r2.bounds[ $r2-idx ];

            my $eqv-cmp = $type ~~ Numeric  ?? * == *
                                            !! $type ~~ Str ?? * eq *
                                                            !! * eqv *;

            return so   (       ( $r1-v ~~ $r2  and not ( $r1-idx == 0 and $r1.excludes-min and $eqv-cmp($r1-v,$r2-v) )
                                                and not ( $r1-idx == 1 and $r1.excludes-max and $eqv-cmp($r1-v,$r2-v) ) )
                            or  ( $r2-v ~~ $r1  and not ( $r2-idx == 0 and $r2.excludes-min and $eqv-cmp($r2-v,$r1-v) )
                                                and not ( $r2-idx == 1 and $r2.excludes-max and $eqv-cmp($r2-v,$r1-v) ) )
                        );
        } else {
            if $r1.infinite {
                my $r1-v := $r1.bounds.first({ not $_ ~~ Numeric or not $_ ~~ Inf and not $_ ~~ -Inf });
                return $r1-v ~~ $r2;
            } else {
                my $r2-v := $r2.bounds.first({ not $_ ~~ Numeric or not $_ ~~ Inf and not $_ ~~ -Inf });
                return $r2-v ~~ $r1; 
            }

        }
    } else {
        if [||] @types >>~~>> Numeric {
    	    return	so  ( $r1.min ~~ $r2 and $r1.max ~~ $r2 or $r2.min ~~ $r1 and $r2.max ~~ $r1
    		                or ( $r1.min == $r2.min and ($r1.max <= $r2.max or $r2.max <= $r1.max) )
    		                or ( $r2.min < $r1.min < $r2.max <= $r1.max )
    		                or ( $r1.min < $r2.min < $r1.max <= $r2.max )
                        );
        } else {
            my $r1-min := $r1.excludes-min ?? $r1.min.succ !! $r1.min;
            my $r2-min := $r2.excludes-min ?? $r2.min.succ !! $r2.min;
    
            my $r1-max := $r1.excludes-max ?? $r1.max.pred !! $r1.max;
            my $r2-max := $r2.excludes-max ?? $r2.max.pred !! $r2.max;
    
            my $compare := $type ~~ Str   ?? * le * le * 
                                          !! * before * before * ;
    
            return so   ( $r1-min ~~ $r2 or $r1-max ~~ $r2 or $r2-min ~~ $r1 or $r2-max ~~ $r1
                            or ( $compare( $r1-min, $r2-min, $r1-max ) )
                            or ( $compare( $r2-min, $r1-min, $r2-min ) ) );
        }
    }
}

sub test-ranges( @range-tests ) {
    for @range-tests -> [ $r1, $r2, $outcome ] {
        my $message = $outcome ?? 'overlaps with' !! 'does not overlap with';
        is overlaps-with( $r1, $r2 ), $outcome, "$r1.gist() $message $r2.gist()";
        is overlaps-with( $r2, $r1 ), $outcome, "$r2.gist() $message $r1.gist()";
    }
}

my @range-tests = (
    [ $(0..6),      $(6^..12),      False ],
    [ $(12^..^23),  $(23..44),      False ],
    [ $(23..44),    $(42..64),      True  ],
    [ $(6^..^7),    $(6^..^8),      True  ],
    [ $(6^..^7),    $(7^..^8),      False ],
    [ $(-6^..^7),   $(-7^..^8),     True  ],
    [ $(-6^..^7),   $(-7..-6),      False ],
    [ $(3^..^7),    $(6^..^8),      True  ],
    [ $(3^..^20),   $(6^..^8),      True  ],
    [ $(3^..^20),   $(6^..^8),      True  ],
    [ $(6^..^8),    $(3^..^20),     True  ],
    [ $(6..2),      $(2..5),        False ],
    [ $(0..0),      $(0..0),        True  ],
    [ $(-10..10),   $(0..0),        True  ],
    [ $(0..2),      $(0^..^2),      True  ],
    [ $(5^..^6),    $(5.5^..^5.6),  True  ],
    [ $(5^..^6),    $(5.5^..6),     True  ],
    [ $(5.5..6),    $(5..6),        True  ],
    [ $(5.5^..^5.6), $(6..7),       False ],
);


test-ranges( @range-tests );

my $eighties = Date.new(:year(1980))..^Date.new(:year(1990));
my $nineties = Date.new(:year(1990))..^Date.new(:year(2000));
my $oughties = Date.new(:year(2000))..^Date.new(:year(2010));

my $early-perl  = Date.new('1987-12-18')..^Date.new(:year(2000));
my $nearly-perl = Date.new(:year(2000))..Date.new(:year(2015));

my $before-perl = *..^Date.new('1987-12-18');
my $after-perl  = Date.new('1987-12-18')..*;

@range-tests = (
    [ $('a'..'z'),  $('j'..'k'),    True    ],
    [ $nineties,    $oughties,      False   ],
    [ $early-perl,  $nineties,      True    ],
    #    [ $before

    [ $(-Inf..5),   $(-Inf..2),     True    ],
    [ $(-Inf..5),   $(2..Inf),      True    ],
    [ $(20..Inf),   $(30..Inf),     True    ],
    [ $(-Inf..20),  $(30..Inf),     False   ],
    [ $(-Inf..^6),  $(6..Inf),      False   ],
    [ $(-Inf..^5.9),$(5.9..Inf),    False   ],
    [ $before-perl, $eighties,      True    ],
    [ $before-perl, $oughties,      False   ],
    [ $before-perl, $after-perl,    False   ],
    [ $(-Inf..^7),  $(7..11),       False   ],
);

test-ranges( @range-tests );
