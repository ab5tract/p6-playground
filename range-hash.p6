use v6.c;

# Let's explain this part later and get to the demo immediately
class RangeHash { ... }

my @values = ((0 .. 77777).roll xx 777);

my $range-hash = RangeHash.new([ (0..^5), (5..^555), (555..1555), (1556..1776), (1777..^Inf) ], :@values);

sub MAIN() {
    dd $range-hash.percentiles;
    say $range-hash;
    $range-hash.insert(3) xx 55;
    dd $range-hash.percentiles([ 0.5, 0.7, 0.8, 0.9, 0.99 ]);
    say "$range-hash";
}


=begin pod

=title RangeHash

C<RangeHash> wants to fulfill all of your bucketing needs. Tallies and
percentiles available at the flick of the wrist.

=end pod

# As promised, the good stuff...
class RangeHash {
    # Available for user definition
    has @.ranges is required;
    has @.values;
    has @.percents;
    has $.name;
    # Derived from object state
    has %.buckets{Range};
    has %.max = %( range => Range, hits => 0 );
    has @!percentiles;
    has $!is-sorted;

    method new(@ranges, :@values, :$name, :@percents) {
        self.bless(:@ranges, :$name, :@values, :@percents);
    }

    submethod BUILD(:@!ranges, :@values, :$!name, :@!percents) {
        @!percents = [ 0.50, 0.75, 0.8, 0.88, 0.90, 0.95, 0.99 ]; 

        %!buckets{$_} = 0 for @!ranges;

        if @values {
            @!values = @values.sort;
            $!is-sorted = True;
            for @!values -> $v {
                self.increment($v);
            }
        }
    }

    method AT-KEY($value) {
        my $range = binary-search(@!ranges, $value);
        return %!buckets{$range};
    }

    method ASSIGN-KEY($value, $hits) {
        my $range = binary-search(@!ranges, $value);
        if $hits > (%!max<hits>||0) {
            %!max{'range', 'hits'} = $range, $hits;
        }
        return %!buckets{$range} = $hits;
    }

    my sub binary-search(@ranges, $value) {
        my $lower = 0;
        my $upper = +@ranges - 1;
        while $lower <= $upper {
            my $current-idx = (($lower + $upper) / 2).floor;
            my $current-range = @ranges[$current-idx];
            if $value ~~ $current-range {
                return $current-range;
            } elsif $current-range > $value {
                $upper = $current-idx - 1;
            } else {
                $lower = $current-idx + 1;
            }
        }
        return Failure.new("Could not find $value in provided ranges");
    }

    method increment($value) {
        self.ASSIGN-KEY($value, self.AT-KEY($value) + 1);
    }

    method insert($value) {
        self.increment($value);
        self!add-value($value);
    }

    method !add-value($value) {
        @!values.append($value); 
        $!is-sorted = False;
        @!percentiles = [];
    }

    method percentiles(@percents = []) {
        return Failure.new("Cannot calculate percentiles without inserted values") unless +@!values;

        if @percents { 
            @!percents = @percents;
            @!percentiles = [];
        }

        return @!percentiles ||= do {
            my $max-index = +@!values; 
            my @answers;
            @!values .= sort unless $!is-sorted;
            for @!percents -> $p {
                @answers.push: $p => @!values[ ($p * $max-index).ceiling ];
            }
            @answers
        }
    }

    method gist { ~self }

    method Str { 
        my $str-form = "{$!name || self.WHICH}\n";
        $str-form ~= "  Buckets:\t" ~ @!ranges.map(-> $r { "{$r.perl}: {%!buckets{$r}}" }).join("\t");
        if @!values && self.percentiles {
            $str-form ~= "\n  Percentiles: " ~ self.percentiles.map(-> $p { "{$p.key}: {$p.value}" }).join("\t");
        }
        return $str-form;
    }
}
