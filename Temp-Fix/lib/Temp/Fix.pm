use v6;

unit module Temp; 

module Fix {

    sub lol ( $block, @lol ) is export {
        @lol.values.map: { @($^v)>>.map({ $block($_) }) };
    }
    
    sub overlaps-with( Range:D $r1, Range:D $r2 ) is export { 
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
}
