#!/usr/bin/env perl6

module Secret {
	class MathVar {}; # Not instantiated
	class Polynomial {...}; # Avoid compilation errors

	sub create-var() is export {
		my sub { MathVar }
	}

    multi sub right-strip(@l where *.elems == 0, $x = 0) is export { [] }
	multi sub right-strip(@l where *.elems == 1, $x = 0) is export { @l }
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

	# XXX: I admit, this is cryptic :( ... maybe we can include smiley face variants?
	sub interpolate(**@points) is export {
		my $p = Polynomial.new: [0];
		my @f = @points.keys.map: -> $i {
			$p += single-term @points, $i;
		}
		$p + Polynomial.new([])
		# Bullshit that this doesn't work...
		# [+] @points.keys.map: -> $i {
		# 	single-term @points, $i;
		# })
	}

	sub single-term(@points, $i) {
		my $term = Polynomial.new: [1];
		my ($xi, $yi) = @points[$i];

		for @points.kv -> $j, $p {
			next if $j == $i;
			my $xj = $p[0];
			$term *= Polynomial.new: [ -$xj / ($xi - $xj), 1 / ($xi - $xj) ];
		}
		$term * Polynomial.new: [$yi]
	}

    class Polynomial does Callable is export {
        has @.coefficients;
        has $.indeterminate is rw = 'x';

        method new(@c) {
            my @coefficients = right-strip @c;
            self.bless(:@coefficients);
        }

		method Str {
			my $str-rep;
			@!coefficients.kv.map: -> $pos, $coef {
				$str-rep ~= $coef if $coef > 0;
				$str-rep ~= $!indeterminate if $pos > 0;
				$str-rep ~= '^' ~ $pos if $pos > 1;
				$str-rep ~= ' + ' if $pos < @!coefficients - 1;
			}
			$str-rep
		}

		multi method ACCEPTS(Polynomial $g) {
			self.coefficients ~~ $g.coefficients
		}

		multi submethod CALL-ME(MathVar:U) {
			Polynomial.new: @!coefficients
		}
		multi submethod CALL-ME(Int $x) is pure {
			[+] @!coefficients.kv.map: -> $pos, $coef {
				$coef * $pos.exp($x)
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
