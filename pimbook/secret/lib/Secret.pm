#!/usr/bin/env perl6

module Secret {
    multi sub right-strip(@l where *.elems == 0, $x = 0) is export { [] }
    multi sub right-strip(@l, $x = 0) is export {
        my $i = @l.elems - 1;
        while @l[$i] == $x {
            $i--;
        }
        @l[ ^($i+1) ] # range slice
    }

	multi sub right-pad(@l where *.elems == 0, $x = 0) is export { [] }
	multi sub right-pad(@f, @g, $x = 0) is export {
		if (my $f-elems = @f.elems) != (my $g-elems = @g.elems) {
	        my $max = ($f-elems, $g-elems).maxpairs.first;
			if $max.key == 0 { # meaning, @f is bigger
				@g.append: $x xx ($f-elems - $g-elems);
			} else {
				@f.append: $x xx ($g-elems - $f-elems);
			}
		}
		@f, @g
    }

    class Polynomial is export {
        has @.coefficients;
        has $.indeterminate is rw = 'x';

        method new(@c) {
            my @coefficients = right-strip @c;
            self.bless(:@coefficients);
        }

		method Str {
			my $str-rep;
			@!coefficients.kv.map: -> $idx, $coefficient {
				$str-rep ~= $coefficient if $coefficient > 0;
				$str-rep ~= $!indeterminate if $idx > 0;
				$str-rep ~= '^' ~ $idx if $idx > 1;
				$str-rep ~= ' + ' if $idx < @!coefficients - 1;
			}
			$str-rep
		}

		multi method ACCEPTS(Polynomial $g) {
			self.coefficients ~~ $g.coefficients
		}

		submethod CALL-ME(Int $x) is pure {
			[+] @!coefficients.kv.map: -> $i, $c {
				$c * $i.exp($x)
			}
		}
    }

    multi sub infix:<+> (Polynomial $f, Polynomial $g, @z = zip(right-pad($f.coefficients, $g.coefficients))) is export {
		Polynomial.new: @z.map(*.sum)
	}

    multi sub infix:<*> (Polynomial $f, Polynomial $g, @f = $f.coefficients, @g = $g.coefficients) is export {
		# Cannot be initialized in signature because we mutate -- v6.d
		my @new = 0 xx (@f.elems + @g.elems - 1);
		for @f.kv -> $i, $a {
			for @g.kv -> $j, $b {
				@new[$i + $j] += $a * $b;
			}
		}
		Polynomial.new: @new
	}

}
