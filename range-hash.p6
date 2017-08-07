use v6.c;

# Let's explain this part later and get to the demo immediately
class RangeHash { ... }

# Not possible to use map:
#   Seq objects are not valid endpoints for Ranges
# my @values = 1..100.map: { $_ xx $_ };

# Kind of gross version:
# my @values = flat do for 1..100 { $_ xx $_ };
# Better written as
my @values = flat 1..100 Zxx 1..100;
my @ranges = 1..50, 51..70, 71..80, 81..90, 91..99, 99..100;
my @percents = 0.5, 0.7, 0.8, 0.9, 0.99;

my $range-hash = RangeHash.new: @ranges, :@values, :@percents, name => '1..100 Zxx 1..100';

sub MAIN() {
    $range-hash{11} += 100;
    dd $range-hash.percentiles;
    say $range-hash;
#    $range-hash.insert(3) xx 55;
    dd $range-hash.percentiles([ 0.5, 0.7, 0.8, 0.9, 0.99 ]);
    say "$range-hash";

#    dd RangeHash.new([ (0..^5), (5..^555), (555..1555), (1556..1776), (1777..^Inf) ], :@values).percentiles;
}


=begin pod

=title RangeHash

C<RangeHash> wants to fulfill all of your bucketing needs. Tallies and
percentiles available at the flick of a wrist.

=end pod

# As promised, the good stuff...
class RangeHash {
    # Available for user definition
    has @.ranges is required;
    has @.values;
    has @.percents;
    has $.name;
    # Derived from object initialization/state
    has %.buckets{Range};
    has %.max = %( range => Range, hits => 0 );
    has @!percentiles;
    has $!is-sorted;

    method new(@ranges, :@values, :$name, :@percents) {
        self.bless(:@ranges, :$name, :@values, :@percents);
    }

    submethod BUILD(:@!ranges, :@values, :$!name, :@!percents) {
        # It would not accept a default in the BUILD signature
        @!percents ||= [ 0.50, 0.75, 0.8, 0.90, 0.95, 0.99 ];

        %!buckets{$_} = 0 for @!ranges;
        dd %!buckets;

        if @values {
            @!values = @values.sort;
            $!is-sorted = True;
            for @!values -> $v {
                self.increment($v);
            }
        }
    }

    #XXX I would have expected this to work:
    # class G {
    #     has %.g;
    #     method AT-KEY($k) { %!g{$k} //= 0 }
    #     method ASSIGN-KEY($k, $v) { %!g{$k} = $v }
    # }
    # > my $e = G.new: :g(k => 10)
    # G.new(g => {:k(10)})
    # > $e<k> += 10
    # Cannot assign to an immutable value
    #   in block <unit> at <unknown file> line 1

    method AT-KEY($value) {
        my $range = self!find-range($value);
        return %!buckets{$range};
    }

    method ASSIGN-KEY($value, $hits) {
        my $range = self!find-range($value);
        if $hits > (%!max<hits> || 0) {
            %!max{'range', 'hits'} = $range, $hits;
        }
        return %!buckets{$range} = $hits;
    }

    method !find-range($value) {
        return binary-search(@!ranges, $value);
        # Slow version:
        # for @!ranges -> $r {
        #     return $r if $value ~~ $r;
        # }
    }

    my sub binary-search(@ranges, $value) {
        my $lo = 0;
        my $hi = @ranges.end;
        until $lo > $hi {
            my $mid = ($lo + $hi) div 2;
            my $range = @ranges[$mid];
            if $value ~~ $range {
                return $range;
            } elsif $range.min > $value {
                $hi = $mid - 1;
            } else {
                $lo = $mid + 1;
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
            my @computed-percentiles;
            if not $!is-sorted {
                @!values .= sort;
                $!is-sorted = True;
            }
            for @!percents -> $p {
                @computed-percentiles.push: $p => @!values[ ($p * $max-index).ceiling ];
            }
            @computed-percentiles
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
