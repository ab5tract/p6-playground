# This file contains some work-in-progress bottom-up design work for the GLR.
# All types and operators introduced are prefixed with GLR, so there are no
# conflicts with those in core (the GLR prefix has even been used where there
# isn't anything in core to conflict with, to make clear what's being added).
# There's no syntax sugar, but rather explanations of what some syntax will
# desugar to are included. The various MAIN subs do tests to check correctness
# and various benchmarks to compare with what we have in Rakudo today.

# Up-front summary:
# * (1, 2, 3) makes a List; there is no Parcel. List supports laziness and
#   positional read access, but notably not push/pop/shift/unshift/splice
# * [1, 2, 3] makes an Array, which supports binding to slots, enforces
#   Scalar containers, provides push/pop/shift/unshift/splice, etc. It
#   inherits from List.
# * slip(1, 2, 3) makes a Slip, which "slips" its values into an iterator
#   that sees it. It also inherits from List.
# * (1, (2, 3), 4).elems is 3, (1, slip(2, 3), 4).elems is 4
# * xx, map/grep/etc., gather/take, and ... (and likely more) all return a
#   Seq. A Seq is something that you can only iterate once; it does not
#   remember its values. Calling .list on it obtains the iterator and
#   gives back a List that will be populated (and cache) values from the
#   iteration. It also remembers this list, so multiple calls to .list
#   will work out. Effectively, a Seq is memoized through .list. Trying to
#   obtain the iterator from a Seq more than once will result in an
#   exception. It's also possible to .List and .Slip a Seq; both take
#   ownership of the iterator and do not memoize the result.
# * A Seq is not Positional, thus:
#       my @a := (^10).map(* + 1);               # Type check error
#       my @a := gather { loop { take 'away' } } # The same
#       my @a := 1 xx 100;                       # You guessed it...
#   The ::= binding form (which is used in signature binding) will call
#   .list on the Seq and bind the result of that, however.
#       my @a ::= 1 xx 1000000; # Works
#       for @a { }              # Congrats, you now have 1 million Ints
#   A Scalar container can hold anything, and so such an assignment or
#   binding works out. However, you're talking about a thing that can
#   produce values in that case.
#       my $a = 1 xx 1000000;   # Works
#       for $a { }              # Iterates 1000000 times, constant memory
#       for $a { }              # Exception: you already consumed that Seq
#   Note that since the Seq is not Positional, you can't index it:
#       my $a = (2, 4 ... *);   # Assigns a Seq
#       say $a[10];             # Exception because you can't index a Seq
#   Note that every single example in this section failed to use what most
#   programmers will actually use: assignment into an array.
#       my @a = 2, 4, ... 100;  # Works, and eagerly assigns
#       for @a.map(* + 1) { }   # But won't remember the map results
#       for lines() { }         # Constant in memory as lines() returns Seq
# * Iterable is just a role saying you have an iterator method. It implies
#   that flat should flatten the values unless there is a Scalar container
#   around the Iterable thing.
# * Iterator is a role done by iterators, with common infrastructure. We don't
#   expect normal code to ever see the objects that do Iterator. Unless it
#   calls .iterator, of course. The Iterator API only demands implementation
#   of the pull-one method, which asks for a single value. Every other method
#   has a default implementation in terms of this. However, any Iterator is
#   free to override other methods when it can do something smarter. (This is
#   how we realize the negotiation that Larry has mentioned. For example, an
#   .elems call on a List will tell any iterators to simply dump all of their
#   things into its reified items buffer, and they can do their best to make
#   that happen quickly.)
# * A couple of other types show up as infrastructure, but they're only of
#   interest to anyone implementing the Iterator API.
# * The [...] array constructor does not flatten, but respects Slips. It will
#   eagerly evluate up until it encounters something infinite.
# * Array assignment (@a = ...) considers the right hand side as a whole. If
#   it's not Iterable, the Array ends up with one item. If it is Iterable, the
#   iterator is obtained and used to populate the array up until something
#   infinite is encountered. Remembering that an array also stores all of the
#   things you put in it into a Scalar container, this gives:
#       my @a = 1, 2, 3;          # 3 elements [1, 2, 3]
#       my @b = [1, 2], [3, 4];   # 2 elements [$[1, 2], $[3, 4]]
#       my @c = @a, @b;           # 2 elements [$[1, 2, 3], $[$[1, 2], $[3, 4]]]
#       my @d = @a.Slip, @b.Slip; # 5 elements [1, 2, 3, $[1, 2], $[3, 4]]
#       my @e = flat @a, @b;      # 5 elements [1, 2, 3, $[1, 2], $[3, 4]]
#       my @f = 'ale' xx 4;       # 4 elements
#       my @g = 1..10;            # 10 elements
#   Noting that [...] is not an item, then:
#       my @x = flat [1, 2], [3]; # 3 elements, [1, 2, 3]
# * The desire to iterate until an infinite thing is hit is carried deep into
#   the iterator, so composites that may iterate many things along the way can
#   do the right thing. Thus, there's no hang from doing:
#       my @y = 1, 2, (3 xx *).Slip;
#   Or, as it is more comfortably written:
#       my @y = flat 1, 2, 3 xx *;
#   Note that [...] not producing an item is the reason the flat is needed. If
#   we didn't demand it, then we'd end up with assigning [1, 2], [3, 4] giving
#   4 values, which is clearly worse than having to write flat now and then!

use nqp;
use MONKEY-TYPING;

# IterationBuffer is used when the list/iteration implementation needs a
# lightweight way to store/transmit values. Replaces the use of nqp::list in
# the list guts, which is an impediment to introspectability and also to
# allowing the implementation of custom iterators (though in reality most
# folks won't implement Iterator directly, but instead use gather/take or lazy
# loops). It doesn't make Scalar containers, and only supports mutation
# through implementing push and BIND-POS, and access by implementing AT-POS.
# Hot-paths are free to use the nqp:: op set directly on this, and do things
# outside the scope of the method API it exposes. This type is engineered for
# performance over friendliness, and normal Perl 6 users should never see it,
# just as they never saw the things we did with nqp::list(...) in previous
# list guts implementations. Do NOT add any checks and validation to methods
# in here. They need to remain trivially inlineable for performance reasons.
my class GLRIterationBuffer is repr('VMArray') {
    method clear(GLRIterationBuffer:D:) {
        nqp::setelems(self, 0)
    }

    multi method elems(GLRIterationBuffer:D:) {
        nqp::elems(self)
    }

    multi method push(GLRIterationBuffer:D: Mu \value) {
        nqp::push(self, value)
    }

    multi method AT-POS(GLRIterationBuffer:D: int $pos) {
        nqp::atpos(self, $pos)
    }

    multi method AT-POS(GLRIterationBuffer:D: Int $pos) {
        nqp::atpos(self, $pos)
    }

    multi method BIND-POS(GLRIterationBuffer:D: int $pos, Mu \value) {
        nqp::bindpos(self, $pos, value)
    }

    multi method BIND-POS(GLRIterationBuffer:D: Int $pos, Mu \value) {
        nqp::bindpos(self, $pos, value)
    }
}

# We use a sentinel value to mark the end of an iteration.
my constant GLRIterationEnd = Mu.new;

# The Iterator role defines the API for an iterator and provides simple
# fallback implementations for most of it, so any given iterator can pick
# and choose what bits it can implement better for performance and/or
# correctness reasons.
my role GLRIterator {
    # Pulls one value from the iterator. If there's nothing more to pull,
    # returns the constant IterationEnd. If you don't override any other
    # methods in this role, they'll all end up falling back to using this.
    method pull-one() { ... }

    # Has the iterator produce a certain number of values and push them into
    # the target. The only time the iterator may push less values than asked
    # for is when it reaches the end of the iteration. It may never push more
    # values than are requested. Iterators that can do something smarter than
    # the default implementation here should override this method. Should
    # return how many things were pushed. Note that if the iterator does any
    # side-effects as a result of producing values then up to $n of them will
    # occur; you must be sure this is desired. Returns the number of things
    # pushed, or IterationEnd if it reached the end of the iteration.
    method push-exactly($target, int $n) {
        my int $i = 0;
        my $pulled;
        while $i < $n {
            $pulled := self.pull-one();
            last if $pulled =:= GLRIterationEnd;
            $target.push($pulled);
            $i = $i + 1;
        }
        $pulled =:= GLRIterationEnd
            ?? GLRIterationEnd
            !! $i
    }

    # Has the iteration push at least a certain number of values into the
    # target buffer. For iterators that do side-effects, this should always
    # be the same as push-exactly. Those that know they can safely work ahead
    # to achieve better throughput may do so. Returns the number of things
    # pushed, or IterationEnd if it reached the end of the iteration.
    method push-at-least($target, int $n) {
        self.push-exactly($target, $n)
    }

    # Has the iterator produce all of its values into the target. This is
    # mostly just for convenience/clarity; it calls push-at-least with a
    # very large value in a loop, but will probably only ever need to do
    # one call to it. Thus, overriding push-at-least or push-exactly is
    # sufficient; you needn't override this. Returns IterationEnd.
    method push-all($target) {
        # Size chosen for when int is 32-bit
        until self.push-at-least($target, 0x7FFFFFFF) =:= GLRIterationEnd { }
        GLRIterationEnd
    }

    # Pushes things until we hit a known infinite iterator. The default works
    # well for non-composite iterators (that is, those that don't trigger the
    # evaluation of other iterators): it looks at the infinite property of
    # itself, and if it's true, does nothing, otherwise it calls push-all. If
    # all values the iterator can produce are pushed, then IterationEnd should
    # be returned. Otherwise, return something else (Mu will do fine).
    method push-until-infinite($target) {
        self.infinite
            ?? Mu
            !! self.push-all($target)
    }

    # Consumes all of the values in the iterator for their side-effects only.
    # May be overridden by iterators to either warn about use of things in
    # sink context that should not be used that way, or to process things in
    # a more efficient way when we know we don't need the results.
    method sink-all() {
        until self.pull-one() =:= GLRIterationEnd { }
        GLRIterationEnd
    }

    # Whether the iterator is infinite (True for known infinite, False for
    # known finite, Mu for unknown).
    method infinite() {
        Mu
    }
}

# A SlippyIterator is one that comes with some infrastructure for handling
# flattening a received Slip into its own stream of values.
my class GLRSlip { ... }
my role GLRSlippyIterator does GLRIterator {
    # Flat set to non-zero if the iterator is currently consuming a Slip.
    has int $!slipping;

    # The current Slip we're iterating.
    has $!slip-iter;

    method start-slip(GLRSlip:D $slip) {
        $!slipping = 1;
        $!slip-iter := $slip.iterator;
        self.slip-one()
    }

    method slip-one() {
        my \result = $!slip-iter.pull-one;
        if result =:= GLRIterationEnd {
            $!slipping = 0;
            $!slip-iter := Mu;
        }
        result
    }
}

# Iterable is done by anything that we should be able to get an iterator
# from. Things that are Iterable will flatten in flattening contexts, so a
# default implementation of .flat is provided by this role. Also, since
# itemization is what defeats flattening, this role also provides a default
# .item method.
my class GLRSeq { ... }
my role GLRIterable {
    method iterator() returns GLRIterator { ... }

    method item() {
        nqp::p6bindattrinvres(nqp::create(Scalar), Scalar, '$!value', self)
    }

    method flat() {
        GLRSeq.new(class :: does GLRIterator {
            has $!source;
            has GLRIterator $!nested-iter;

            method new(\source-iter) {
                my \iter = self.CREATE;
                nqp::bindattr(iter, self, '$!source', source-iter);
                iter
            }

            method pull-one() {
                my $result;
                loop {
                    if $!nested-iter {
                        $result := $!nested-iter.pull-one();
                        last unless $result =:= GLRIterationEnd;
                        $!nested-iter := GLRIterator;
                    }
                    $result := $!source.pull-one();
                    last unless nqp::istype($result, GLRIterable) && !nqp::iscont($result);
                    $!nested-iter := $result.flat.iterator;
                }
                $result
            }

            # This is a prime candidate for implementing most of the other
            # methods, for speed reasons
        }.new(self.iterator))
    }
}

# A Seq represents anything that can lazily produce a sequence of values. A
# Seq is born in a state where iterating it will consume the values. However,
# calling .list on a Seq will return a List that will lazily reify to the
# values in the Seq. The List is memoized, so that subsequent calls to .list
# will always return the same List (safe thanks to List being immutable). More
# than one call to .iterator throws an exception (and calling .list calls the
# .iterator method the first time also). The memoization can be avoided by
# asking very specifically for the Seq to be coerced to a List (.List), a
# Slip (.Slip) or an Array (.Array).
my class GLRList { ... }
my class GLRArray { ... }
class X::GLRSeq::Consumed is Exception {
    method message() {
        "This Seq has already been iterated, and its values consumed"
    }
}
class X::GLRSeq::NotIndexable is Exception {
    method message() {
        "Cannot index a Seq; coerce it to a list or assign it to an array first"
    }
}
my class GLRSeq does GLRIterable {
    # The underlying iterator that iterating this sequence will work its
    # way through. Can only be obtained once.
    has GLRIterator $!iter;

    # A memoized list that this Seq was coerced into, if any.
    has $!list;

    # The only valid way to create a Seq directly is by giving it the
    # iterator it will consume and maybe memoize.
    method new(GLRIterator:D $iter) {
        my $seq := self.CREATE;
        nqp::bindattr($seq, GLRSeq, '$!iter', nqp::decont($iter));
        $seq
    }

    method iterator(GLRSeq:D:) {
        my \iter = $!iter;
        X::GLRSeq::Consumed.new.throw unless iter.DEFINITE;
        $!iter := GLRIterator;
        iter
    }

    method list() {
        $!list.DEFINITE
            ?? $!list
            !! ($!list := GLRList.from-iterator(self.iterator))
    }

    method List() {
        GLRList.from-iterator(self.iterator)
    }

    method Slip() {
        GLRSlip.from-iterator(self.iterator)
    }

    method Array() {
        GLRArray.from-iterator(self.iterator)
    }

    method sink() {
        self.iterator.sink-all;
        self
    }

    multi method AT-POS(GLRSeq:D: $) {
        X::GLRSeq::NotIndexable.new.throw
    }

    multi method EXISTS-POS(GLRSeq:D: $) {
        X::GLRSeq::NotIndexable.new.throw
    }

    multi method DELETE-POS(GLRSeq:D: $) {
        X::GLRSeq::NotIndexable.new.throw
    }

    # Lazy loops produce a Seq wrapping a loop iterator. We have a few
    # special cases of that.
    my class InfiniteLoopIter does GLRSlippyIterator {
        has &!body;

        method new(&body) {
            my \iter = self.CREATE;
            nqp::bindattr(iter, self, '&!body', &body);
            iter
        }

        method pull-one() {
            my int $redo = 1;
            my $result;
            if $!slipping && ($result := self.slip-one()) !=:= GLRIterationEnd {
                $result
            }
            else {
                nqp::while(
                    $redo,
                    nqp::stmts(
                        $redo = 0,
                        nqp::handle(
                            nqp::stmts(
                                ($result := &!body()),
                                nqp::if(
                                    nqp::istype($result, GLRSlip),
                                    nqp::stmts(
                                        ($result := self.start-slip($result)),
                                        nqp::if(
                                            nqp::eqaddr($result, GLRIterationEnd),
                                            ($redo = 1)
                                        ))
                                    )),
                            'NEXT', ($redo = 1),
                            'REDO', ($redo = 1),
                            'LAST', ($result := GLRIterationEnd))),
                    :nohandler);
                $result
            }
        }

        method infinite() { True }
    }

    my class WhileLoopIter does GLRSlippyIterator {
        has &!body;
        has &!cond;
        has int $!skip-cond;

        method new(&body, &cond, :$repeat) {
            my \iter = self.CREATE;
            nqp::bindattr(iter, self, '&!body', &body);
            nqp::bindattr(iter, self, '&!cond', &cond);
            nqp::bindattr_i(iter, self, '$!skip-cond', $repeat ?? 1 !! 0);
            iter
        }

        method pull-one() {
            my int $redo = 1;
            my $result;
            if $!slipping && ($result := self.slip-one()) !=:= GLRIterationEnd {
                $result
            }
            else {
                if $!skip-cond || &!cond() {
                    $!skip-cond = 0;
                    nqp::while(
                        $redo,
                        nqp::stmts(
                            $redo = 0,
                            nqp::handle(
                                nqp::stmts(
                                    ($result := &!body()),
                                    nqp::if(
                                        nqp::istype($result, GLRSlip),
                                        nqp::stmts(
                                            ($result := self.start-slip($result)),
                                            nqp::if(
                                                nqp::eqaddr($result, GLRIterationEnd),
                                                ($redo = &!cond() ?? 1 !! 0)
                                            ))
                                        )),
                                'NEXT', ($redo = &!cond() ?? 1 !! 0),
                                'REDO', ($redo = 1),
                                'LAST', ($result := GLRIterationEnd))),
                        :nohandler);
                    $result
                }
                else {
                    GLRIterationEnd
                }
            }
        }

        method infinite() { Mu }
    }

    my class CStyleLoopIter does GLRSlippyIterator {
        has &!body;
        has &!cond;
        has &!afterwards;
        has int $!first-time;

        method new(&body, &cond, &afterwards) {
            my \iter = self.CREATE;
            nqp::bindattr(iter, self, '&!body', &body);
            nqp::bindattr(iter, self, '&!cond', &cond);
            nqp::bindattr(iter, self, '&!afterwards', &afterwards);
            nqp::bindattr_i(iter, self, '$!first-time', 1);
            iter
        }

        method pull-one() {
            my int $redo = 1;
            my $result;
            if $!slipping && ($result := self.slip-one()) !=:= GLRIterationEnd {
                $result
            }
            else {
                $!first-time
                    ?? ($!first-time = 0)
                    !! &!afterwards();
                if &!cond() {
                    nqp::while(
                        $redo,
                        nqp::stmts(
                            $redo = 0,
                            nqp::handle(
                                nqp::stmts(
                                    ($result := &!body()),
                                    nqp::if(
                                        nqp::istype($result, GLRSlip),
                                        nqp::stmts(
                                            ($result := self.start-slip($result)),
                                            nqp::if(
                                                nqp::eqaddr($result, GLRIterationEnd),
                                                nqp::stmts(
                                                    &!afterwards(),
                                                    ($redo = &!cond() ?? 1 !! 0))
                                            ))
                                        )),
                                'NEXT', nqp::stmts(
                                    &!afterwards(),
                                    ($redo = &!cond() ?? 1 !! 0)),
                                'REDO', ($redo = 1),
                                'LAST', ($result := GLRIterationEnd))),
                        :nohandler);
                    $result
                }
                else {
                    GLRIterationEnd
                }
            }
        }

        method infinite() { Mu }
    }

    proto method from-loop(|) { * }
    multi method from-loop(&body) {
        GLRSeq.new(InfiniteLoopIter.new(&body))
    }
    multi method from-loop(&body, &cond, :$repeat) {
        GLRSeq.new(WhileLoopIter.new(&body, &cond, :$repeat))
    }
    multi method from-loop(&body, &cond, &afterwards) {
        GLRSeq.new(CStyleLoopIter.new(&body, &cond, &afterwards))
    }
}

# A List is a (potentially infite) immutable list. The immutability is not
# deep; a List may contain Scalar containers that can be assigned to. However,
# it is not possible to shift/unshift/push/pop/splice/bind. A List is also
# Positional, and so may be indexed.
my class GLRList does GLRIterable does Positional {
    # The reified elements in the list so far (that is, those that we already
    # have produced the values for).
    has $!reified;

    # Object that reifies the rest of the list. We don't just inline it into
    # the List class itself, because a STORE on Array can clear things and
    # upset an ongoing iteration. (An easy way to create such a case is to
    # assign an array with lazy parts into itself.)
    has $!todo;

    # The object that goes into $!todo.
    class Reifier {
        # Our copy of the reified elements in the list so far.
        has $!reified;

        # The current iterator, if any, that we're working our way through in
        # order to lazily reify values. Must be depleted before $!future is
        # considered.
        has GLRIterator $!current-iter;

        # The (possibly lazy) values we've not yet incorporated into the list. The
        # only thing we can't simply copy from $!future into $!reified is a Slip
        # (and so the only reason to have a $!future is that there is at least one
        # Slip).
        has $!future;

        # The reification target (what .reify-* will .push to). Exists so we can
        # share the reification code between List/Array. List just uses its own
        # $!reified buffer; the Array one shoves stuff into Scalar containers
        # first.
        has $!reification-target;

        method reify-at-least(int $elems) {
            if $!current-iter.DEFINITE {
                if $!current-iter.push-at-least($!reification-target, $elems) =:= GLRIterationEnd {
                    $!current-iter := GLRIterator;
                }
            }
            if nqp::elems($!reified) < $elems && $!future.DEFINITE {
                repeat while nqp::elems($!reified) < $elems && nqp::elems($!future) {
                    my \current = nqp::shift($!future);
                    $!future := Mu unless nqp::elems($!future);
                    if nqp::istype(current, GLRSlip) && nqp::isconcrete(current) {
                        my \iter = current.iterator;
                        my int $deficit = $elems - nqp::elems($!reified);
                        unless iter.push-at-least($!reification-target, $deficit) =:= GLRIterationEnd {
                            # The iterator produced enough values to fill the need,
                            # but did not reach its end. We save it for next time. We
                            # know we'll exit the loop, since the < $elems check must
                            # come out False (unless the iterator broke contract).
                            $!current-iter := iter;
                        }
                    }
                    else {
                        $!reification-target.push(current);
                    }
                }
            }
            nqp::elems($!reified);
        }

        method reify-until-infinite() {
            if $!current-iter.DEFINITE {
                if $!current-iter.push-until-infinite($!reification-target) =:= GLRIterationEnd {
                    $!current-iter := GLRIterator;
                }
            }
            if $!future.DEFINITE && !$!current-iter.DEFINITE {
                while nqp::elems($!future) {
                    my \current = nqp::shift($!future);
                    if nqp::istype(current, GLRSlip) && nqp::isconcrete(current) {
                        my \iter = current.iterator;
                        unless iter.push-until-infinite($!reification-target) =:= GLRIterationEnd {
                            $!current-iter := iter;
                            last;
                        }
                    }
                    else {
                        $!reification-target.push(current);
                    }
                }
                $!future := Mu unless nqp::elems($!future);
            }
            nqp::elems($!reified);
        }

        method reify-all() {
            if $!current-iter.DEFINITE {
                $!current-iter.push-all($!reification-target);
                $!current-iter := GLRIterator;
            }
            if $!future.DEFINITE {
                while nqp::elems($!future) {
                    my \current = nqp::shift($!future);
                    nqp::istype(current, GLRSlip) && nqp::isconcrete(current)
                        ?? current.iterator.push-all($!reification-target)
                        !! $!reification-target.push(current);
                }
                $!future := Mu;
            }
            nqp::elems($!reified);
        }

        method fully-reified() {
            !$!current-iter.DEFINITE && !$!future.DEFINITE
        }

        method infinite() {
            $!current-iter.DEFINITE ?? $!current-iter.infinite !! Mu
        }
    }

    method from-iterator(GLRList:U: GLRIterator $iter) {
        my \result := self.CREATE;
        my \buffer := GLRIterationBuffer.CREATE;
        my \todo := Reifier.CREATE;
        nqp::bindattr(result, GLRList, '$!reified', buffer);
        nqp::bindattr(result, GLRList, '$!todo', todo);
        nqp::bindattr(todo, Reifier, '$!reified', buffer);
        nqp::bindattr(todo, Reifier, '$!current-iter', $iter);
        nqp::bindattr(todo, Reifier, '$!reification-target',
            result.reification-target());
        result
    }

    method reification-target(GLRList:D:) {
        $!reified
    }

    multi method elems(GLRList:D:) {
        $!todo.DEFINITE
            ?? $!todo.reify-all()
            !! nqp::elems($!reified)
    }

    multi method AT-POS(GLRList:D: Int $pos) is rw {
        my int $ipos = nqp::unbox_i($pos);
        $ipos < nqp::elems($!reified) && $ipos >= 0
            ?? nqp::atpos($!reified, $ipos)
            !! self!AT-POS-SLOWPATH($ipos);
    }

    multi method AT-POS(GLRList:D: int $pos) is rw {
        $pos < nqp::elems($!reified) && $pos >= 0
            ?? nqp::atpos($!reified, $pos)
            !! self!AT-POS-SLOWPATH($pos);
    }

    method !AT-POS-SLOWPATH(int $pos) is rw {
        fail X::OutOfRange.new(:what<Index>, :got($pos), :range<0..Inf>)
            if $pos < 0;
        $!todo.DEFINITE && $!todo.reify-at-least($pos + 1) > $pos
            ?? nqp::atpos($!reified, $pos)
            !! Nil
    }

    method iterator(GLRList:D:) {
        class :: does GLRIterator {
            has int $!i;
            has $!reified;
            has $!todo;

            method new(\list) {
                my $iter := self.CREATE;
                nqp::bindattr($iter, self, '$!reified',
                    nqp::getattr(list, GLRList, '$!reified'));
                nqp::bindattr($iter, self, '$!todo',
                    nqp::getattr(list, GLRList, '$!todo'));
                $iter
            }

            method pull-one() {
                my int $i = $!i;
                $i < nqp::elems($!reified)
                    ?? nqp::atpos($!reified, ($!i = $i + 1) - 1)
                    !! self!reify-and-pull-one()
            }

            method !reify-and-pull-one() {
                my int $i = $!i;
                $!todo.DEFINITE && $i < $!todo.reify-at-least($i + 1)
                    ?? nqp::atpos($!reified, ($!i = $i + 1) - 1)
                    !! GLRIterationEnd
            }

            method push-until-infinite($target) {
                my int $n = $!todo.DEFINITE
                    ?? $!todo.reify-until-infinite()
                    !! nqp::elems($!reified);
                my int $i = $!i;
                while $i < $n {
                    $target.push(nqp::atpos($!reified, $i));
                    $i = $i + 1;
                }
                $!i = $n;
                !$!todo.DEFINITE || $!todo.fully-reified ?? GLRIterationEnd !! Mu
            }

            method infinite() {
                $!todo.DEFINITE ?? $!todo.infinite !! Mu
            }
        }.new(self)
    }

    method Slip() {
        if $!todo.DEFINITE {
            # We're not fully reified, and so have internal mutability still.
            # The safe thing to do is to take an iterator of ourself and build
            # the Slip out of that.
            GLRSlip.from-iterator(self.iterator)
        }
        else {
            # We're fully reified - and so immutable inside and out! Just make
            # a Slip that shares our reified buffer.
            my \result := GLRSlip.CREATE;
            nqp::bindattr(result, GLRList, '$!reified', $!reified);
            result
        }
    }

    method Array() {
        # We need to populate the Array slots with Scalar containers, so no
        # shortcuts (and no special casing is likely worth it; iterators can
        # batch up the work too).
        GLRArray.from-iterator(self.iterator)
    }
}

# The , operator produces a List.
proto infix:<GLR,>(|) is assoc('list') {*}
multi infix:<GLR,>() {
    my \result = GLRList.CREATE;
    nqp::bindattr(result, GLRList, '$!reified', BEGIN GLRIterationBuffer.CREATE);
    result
}
multi infix:<GLR,>(|) {
    my \result  = GLRList.CREATE;
    my \in      = nqp::p6argvmarray();
    my \reified = GLRIterationBuffer.CREATE;
    nqp::bindattr(result, GLRList, '$!reified', reified);
    while nqp::elems(in) {
        if nqp::istype(nqp::atpos(in, 0), GLRSlip) {
            # We saw a Slip, so we'll lazily deal with the rest of the things
            # (as the Slip may expand to something infinite).
            my \todo := GLRList::Reifier.CREATE;
            nqp::bindattr(result, GLRList, '$!todo', todo);
            nqp::bindattr(todo, GLRList::Reifier, '$!reified', reified);
            nqp::bindattr(todo, GLRList::Reifier, '$!future', in);
            nqp::bindattr(todo, GLRList::Reifier, '$!reification-target',
                result.reification-target());
            last;
        }
        else {
            nqp::push(reified, nqp::shift(in));
            Nil # don't Sink the thing above
        }
    }
    result
}

# A Slip is a kind of List that is immediately incorporated into an iteration
# or another List. Other than that, it's a totally normal List.
my class GLRSlip is GLRList {
}

# The slip(...) function creates a Slip.
proto GLRslip(|) { * }
multi GLRslip() {
    my \result = GLRSlip.CREATE;
    nqp::bindattr(result, GLRList, '$!reified', BEGIN GLRIterationBuffer.CREATE);
    result
}
multi GLRslip(|) {
    my \result  = GLRSlip.CREATE;
    my \in      = nqp::p6argvmarray();
    my \reified = GLRIterationBuffer.CREATE;
    nqp::bindattr(result, GLRList, '$!reified', reified);
    while nqp::elems(in) {
        if nqp::istype(nqp::atpos(in, 0), GLRSlip) {
            # We saw a Slip, so we'll lazily deal with the rest of the things
            # (as the Slip may expand to something infinite).
            my \todo := GLRList::Reifier.CREATE;
            nqp::bindattr(result, GLRList, '$!todo', todo);
            nqp::bindattr(todo, GLRList::Reifier, '$!reified', reified);
            nqp::bindattr(todo, GLRList::Reifier, '$!future', in);
            nqp::bindattr(todo, GLRList::Reifier, '$!reification-target',
                result.reification-target());
            last;
        }
        else {
            nqp::push(reified, nqp::shift(in));
            Nil # don't Sink the thing above
        }
    }
    result
}

# An Array is a List that ensures every item added to it is in a Scalar
# container. It also supports push, pop, shift, unshift, splice, BIND-POS,
# and so forth.
my class GLRArray is GLRList {
    has Mu $!descriptor;

    my class ArrayReificationTarget {
        has $!target;
        has $!descriptor;

        method new(\target, Mu \descriptor) {
            my \rt = self.CREATE;
            nqp::bindattr(rt, self, '$!target', target);
            nqp::bindattr(rt, self, '$!descriptor', descriptor);
            rt
        }

        method push(\value) {
            nqp::push($!target,
                nqp::assign(nqp::p6scalarfromdesc($!descriptor), value));
        }
    }

    method from-iterator(GLRArray:U: GLRIterator $iter) {
        my \result := self.CREATE;
        my \buffer := GLRIterationBuffer.CREATE;
        my \todo := GLRList::Reifier.CREATE;
        nqp::bindattr(result, GLRList, '$!reified', buffer);
        nqp::bindattr(result, GLRList, '$!todo', todo);
        nqp::bindattr(todo, GLRList::Reifier, '$!reified', buffer);
        nqp::bindattr(todo, GLRList::Reifier, '$!current-iter', $iter);
        nqp::bindattr(todo, GLRList::Reifier, '$!reification-target',
            result.reification-target());
        todo.reify-until-infinite();
        result
    }

    proto method STORE(|) { * }
    multi method STORE(GLRArray:D: GLRIterable:D \iterable) {
        nqp::iscont(iterable)
            ?? self!STORE-ONE(iterable)
            !! self!STORE-ITERABLE(iterable)
    }
    multi method STORE(GLRArray:D: \item) {
        self!STORE-ONE(item)
    }
    method !STORE-ITERABLE(\iterable) {
        my \new-storage = GLRIterationBuffer.CREATE;
        my \iter = iterable.iterator;
        my \target = ArrayReificationTarget.new(new-storage,
            nqp::decont($!descriptor));
        if iter.push-until-infinite(target) =:= GLRIterationEnd {
            nqp::bindattr(self, GLRList, '$!todo', Mu);
        }
        else {
            my \new-todo = GLRList::Reifier.CREATE;
            nqp::bindattr(new-todo, GLRList::Reifier, '$!reified', new-storage);
            nqp::bindattr(new-todo, GLRList::Reifier, '$!current-iter', iter);
            nqp::bindattr(new-todo, GLRList::Reifier, '$!reification-target', target);
            nqp::bindattr(self, GLRList, '$!todo', new-todo);
        }
        nqp::bindattr(self, GLRList, '$!reified', new-storage);
        self
    }
    method !STORE-ONE(\item) {
        my \new-storage = GLRIterationBuffer.CREATE;
        nqp::push(new-storage, item);
        nqp::bindattr(self, GLRList, '$!reified', new-storage);
        nqp::bindattr(self, GLRList, '$!todo', Mu);
        self
    }

    method reification-target() {
        ArrayReificationTarget.new(
            nqp::getattr(self, GLRList, '$!reified'),
            nqp::decont($!descriptor))
    }
}

# The [...] term creates an Array. BUT at the moment a custom circumfix
# ends up with a Parcel which means we will end up in a tangle with the
# existing list model in Rakudo. So we just do it as a normal function. So
# wherever you see GLRArrayCircumfix(...), imagine it's [...] instead.
proto GLRArrayCircumfix(|) { * }
multi GLRArrayCircumfix() {
    my \result = GLRArray.CREATE;
    nqp::bindattr(result, GLRList, '$!reified', GLRIterationBuffer.CREATE);
    result
}
multi GLRArrayCircumfix(GLRIterable:D \iterable) {
    GLRArray.from-iterator(iterable.iterator)
}
multi GLRArrayCircumfix(|) {
    my \in      = nqp::p6argvmarray();
    my \result  = GLRArray.CREATE;
    my \reified = GLRIterationBuffer.CREATE;
    nqp::bindattr(result, GLRList, '$!reified', reified);
    while nqp::elems(in) {
        if nqp::istype(nqp::atpos(in, 0), GLRSlip) {
            # We saw a Slip, which may expand to something infinite. Put all
            # that remains in the future, and let normal reification take care
            # of it.
            my \todo := GLRList::Reifier.CREATE;
            nqp::bindattr(result, GLRList, '$!todo', todo);
            nqp::bindattr(todo, GLRList::Reifier, '$!reified', reified);
            nqp::bindattr(todo, GLRList::Reifier, '$!future', in);
            nqp::bindattr(todo, GLRList::Reifier, '$!reification-target',
                result.reification-target());
            todo.reify-until-infinite();
            last;
        }
        else {
            # Just an item, no need to go through the whole maybe-lazy
            # business.
            nqp::push(reified,
                nqp::assign(nqp::p6scalarfromdesc(nqp::null()), nqp::shift(in)));
        }
    }
    result
}

# GLR implementation of gather/take.
sub GLRgather(&block) {
    GLRSeq.new(class :: does GLRSlippyIterator {
        has &!resumption;
        has $!push-target;
        has int $!wanted;

        my constant PROMPT = Mu.CREATE;

        method new(&block) {
            my \iter = self.CREATE;
            my int $wanted;
            my $taken;
            nqp::bindattr(iter, self, '&!resumption', {
                nqp::handle(&block(),
                    'TAKE', nqp::stmts(
                        ($taken := nqp::getpayload(nqp::exception())),
                        nqp::if(nqp::istype($taken, GLRSlip),
                            nqp::stmts(
                                iter!start-slip-wanted($taken),
                                ($wanted = nqp::getattr_i(iter, self, '$!wanted'))),
                            nqp::stmts(
                                nqp::getattr(iter, self, '$!push-target').push($taken),
                                ($wanted = nqp::bindattr_i(iter, self, '$!wanted',
                                    nqp::sub_i(nqp::getattr_i(iter, self, '$!wanted'), 1))))),
                        nqp::if(nqp::iseq_i($wanted, 0),
                            nqp::continuationcontrol(0, PROMPT, -> Mu \c {
                                nqp::bindattr(iter, self, '&!resumption', c);
                            })),
                        nqp::resume(nqp::exception())
                    ));
                nqp::continuationcontrol(0, PROMPT, -> | {
                    nqp::bindattr(iter, self, '&!resumption', Callable)
                });
            });
            iter
        }

        method pull-one() {
            if $!slipping && (my \result = self.slip-one()) !=:= GLRIterationEnd {
                result
            }
            else {
                $!push-target := GLRIterationBuffer.CREATE
                    unless $!push-target.DEFINITE;
                $!wanted = 1;
                nqp::continuationreset(PROMPT, &!resumption);
                &!resumption.DEFINITE
                    ?? nqp::shift($!push-target)
                    !! GLRIterationEnd
            }
        }

        method push-exactly($target, int $n) {
            $!wanted = $n;
            $!push-target := $target;
            if $!slipping && self!slip-wanted() !=:= GLRIterationEnd {
                $!push-target := Mu;
                $n
            }
            else {
                nqp::continuationreset(PROMPT, &!resumption);
                $!push-target := Mu;
                &!resumption.DEFINITE
                    ?? $n - $!wanted
                    !! GLRIterationEnd
            }
        }

        method !start-slip-wanted(\slip) {
            my $value := self.start-slip(slip);
            unless $value =:= GLRIterationEnd {
                $!push-target.push($value);
                my int $i = 1;
                my int $n = $!wanted;
                while $i < $n {
                    last if ($value := self.slip-one()) =:= GLRIterationEnd;
                    $!push-target.push($value);
                    $i = $i + 1;
                }
                $!wanted = $!wanted - $i;
            }
        }

        method !slip-wanted() {
            my int $i = 0;
            my int $n = $!wanted;
            my $value;
            while $i < $n {
                last if ($value := self.slip-one()) =:= GLRIterationEnd;
                $!push-target.push($value);
                $i = $i + 1;
            }
            $!wanted = $!wanted - $i;
            $value =:= GLRIterationEnd
                ?? GLRIterationEnd
                !! $n
        }
    }.new(&block))
}

# We add GLR implementations of various methods.
augment class Any {
    method GLRmap(&block) {
        my role GLRMapIterCommon does GLRSlippyIterator {
            has &!block;
            has $!source;

            method new(&block, $source) {
                my $iter := self.CREATE;
                nqp::bindattr($iter, self, '&!block', &block);
                nqp::bindattr($iter, self, '$!source', $source);
                $iter
            }

            method infinite() {
                $!source.infinite
            }
        }

        # Obtain source iterator we'll work through.
        my $source = self.DEFINITE && nqp::istype(self, GLRIterable)
            ?? self.iterator
            !! self.GLRlist.iterator;

        # We want map to be fast, so we go to some effort to build special
        # case iterators that can ignore various interesting cases.
        my $count = &block.count;
        if $count == 1 {
            # XXX We need a funkier iterator to care about phasers. Will
            # put that on a different code-path to keep the commonest
            # case fast.
            # XXX Support labels
            GLRSeq.new(class :: does GLRMapIterCommon {
                method pull-one() {
                    my int $redo = 1;
                    my $value;
                    my $result;
                    if $!slipping && ($result := self.slip-one()) !=:= GLRIterationEnd {
                        $result
                    }
                    elsif ($value := $!source.pull-one()) =:= GLRIterationEnd {
                        $value
                    }
                    else {
                        nqp::while(
                            $redo,
                            nqp::stmts(
                                $redo = 0,
                                nqp::handle(
                                    nqp::stmts(
                                        ($result := &!block($value)),
                                        nqp::if(
                                            nqp::istype($result, GLRSlip),
                                            nqp::stmts(
                                                ($result := self.start-slip($result)),
                                                nqp::if(
                                                    nqp::eqaddr($result, GLRIterationEnd),
                                                    nqp::stmts(
                                                        ($value = $!source.pull-one()),
                                                        ($redo = 1 unless nqp::eqaddr($value, GLRIterationEnd))
                                                ))
                                            ))
                                    ),
                                    'NEXT', nqp::stmts(
                                        ($value := $!source.pull-one()),
                                        nqp::eqaddr($value, GLRIterationEnd)
                                            ?? ($result := GLRIterationEnd)
                                            !! ($redo = 1)),
                                    'REDO', $redo = 1,
                                    'LAST', ($result := GLRIterationEnd))),
                            :nohandler);
                        $result
                    }
                }
            }.new(&block, $source));
        }
        else {
            die "map with .count > 1 NYI";
        }
    }
}

# And here are GLR versions of various operators. (Note: xx was actually the
# first thing implemented, since it's about the simplest possible Iterator
# implementation to write. When we're further along, these may well get a
# good bit of simplification.)
multi infix:<GLRxx>(Mu \x, Whatever) {
    GLRSeq.new(class :: does GLRIterator {
        has $!value;

        method new(\value) {
            my $iter := self.CREATE;
            nqp::bindattr($iter, self, '$!value', value);
            $iter
        }

        method pull-one() { $!value }

        method sink-all() {
            warn "Useless use of xx with literal value in sink context";
        }

        method infinite() { True }
    }.new(x))
}
multi infix:<GLRxx>(Mu \x, Int $i) {
    GLRSeq.new(class :: does GLRIterator {
        has $!value;
        has int $!remaining;

        method new(\value, $limit) {
            my $iter := self.CREATE;
            nqp::bindattr($iter, self, '$!value', value);
            nqp::bindattr_i($iter, self, '$!remaining', $limit);
            $iter
        }

        method pull-one() {
            ($!remaining = $!remaining - 1) >= 0
                ?? $!value
                !! GLRIterationEnd
        }

        method push-exactly($target, int $n) {
            my int $to-take = $n > $!remaining ?? $!remaining !! $n;
            my int $i = 0;
            my \value = $!value;
            while $i < $to-take {
                $target.push(value);
                $i = $i + 1;
            }
            $!remaining = $!remaining - $to-take;
            $!remaining == 0 ?? GLRIterationEnd !! $to-take
        }
        
        method push-at-least($target, int $n) {
            self.push-exactly($target, $n < 256 ?? 256 !! $n)
        }

        method sink-all() {
            warn "Useless use of xx with literal value in sink context";
        }
    }.new(x, $i))
}
proto GLRflat(|) { * }
multi GLRflat(GLRIterable:D \iterable) is rw {
    nqp::iscont(iterable) ?? iterable !! iterable.flat
}
multi GLRflat(|c) {
    infix:<GLR,>(|c).flat
}

# Re-compose classes after adding methods.
GLRSeq.^compose;
GLRList.^compose;
GLRSlip.^compose;
GLRArray.^compose;

# A for loop at statement list level will do code-gen something like this,
# though it statically knows the .count thing so will only emit one of the
# two branches, and with some optimizer work we can likely often inline the
# block also.
sub GLRfor(\iterable, &block) {
    if &block.count == 1 {
        my $iter := iterable.iterator();
        until (my \value = $iter.pull-one) =:= GLRIterationEnd {
            block(value);
        }
    }
    else {
        die "GLRfor NYI when count > 0";
    }
}

multi MAIN('test') {
    use Test;

    # A very basic case of iteration with xx.
    {
        my $simple-seq = &infix:<GLRxx>('beer', *); # Defeat auto-currying
        ok $simple-seq ~~ GLRSeq, 'xx * returns a Seq';
        my $iter = $simple-seq.iterator;
        ok $iter ~~ GLRIterator, '.iterator returns something that does Iterator';
        is $iter.pull-one, 'beer', 'infinite iterator produces value';
        is $iter.pull-one, 'beer', 'infinite iterator produces another value';
    }

    # Iteration with xx and a limit.
    {
        my $finite-seq = 'beer' GLRxx 3;
        ok $finite-seq ~~ GLRSeq, 'xx 3 returns a Seq';
        my $iter = $finite-seq.iterator;
        ok $iter ~~ GLRIterator, '.iterator returns something that does Iterator';
        is $iter.pull-one, 'beer', 'iterator produces value (1)';
        is $iter.pull-one, 'beer', 'iterator produces value (2)';
        is $iter.pull-one, 'beer', 'iterator produces value (3)';
        ok $iter.pull-one =:= GLRIterationEnd, 'iterator reached end';
    }

    # Basic for loop over xx.
    {
        my $i = 0;
        GLRfor('beer' GLRxx 300, -> $beer {
            $i++;
        });
        is $i, 300, "Iterating 'beer' xx 300 works";
    }

    # Map
    {
        my $test-seq = ('beer' GLRxx 3).GLRmap(*.uc);
        ok $test-seq ~~ GLRSeq, 'map returns a Seq';
        my $iter = $test-seq.iterator;
        ok $iter ~~ GLRIterator, '.iterator returns something that does Iterator';
        is $iter.pull-one, 'BEER', 'map iterator produces value (1)';
        is $iter.pull-one, 'BEER', 'map iterator produces value (2)';
        is $iter.pull-one, 'BEER', 'map iterator produces value (3)';
        ok $iter.pull-one =:= GLRIterationEnd, 'iterator reached end';
    }

    # Map with last
    {
        my $test-seq = ('beer' GLRxx 3).GLRmap({ last if state $i++; .uc });
        my $iter = $test-seq.iterator;
        is $iter.pull-one, 'BEER', 'map iterator produces value before last used';
        ok $iter.pull-one =:= GLRIterationEnd, 'iterator reached end when last used';
    }

    # Map with next
    {
        my $test-seq = ('beer' GLRxx 4).GLRmap({ next if state $i++ > 1; .uc });
        my $iter = $test-seq.iterator;
        is $iter.pull-one, 'BEER', 'map iterator produces value before next (1)';
        is $iter.pull-one, 'BEER', 'map iterator produces value before next (2)';
        ok $iter.pull-one =:= GLRIterationEnd, 'iterator reached end due to next skipping iterations';
    }

    # Map with redo
    {
        my $i = 0;
        my $test-seq = ('beer' GLRxx 2).GLRmap({ redo if $i++ == 1; .uc });
        my $iter = $test-seq.iterator;
        is $iter.pull-one, 'BEER', 'map iterator with redo produces 2 values (1)';
        is $iter.pull-one, 'BEER', 'map iterator with redo produces 2 values (2)';
        ok $iter.pull-one =:= GLRIterationEnd, 'iterator reached end in loop with redo';
        is $i, 3, 'Did 3 iterations thanks to redo';
    }

    # List basics.
    {
        my $x = (2 GLR, 4 GLR, 6);
        ok $x ~~ GLRList, ', makes a List';
        is $x.elems, 3, 'List.elems gives correct result';
        is $x[0], 2, 'Can access list (1)';
        is $x[1], 4, 'Can access list (2)';
        is $x[2], 6, 'Can access list (3)';

        {
            my $n = 0;
            GLRfor($x, -> $i {
                $n += $i;
            });
            is $n, 12, 'Can iterate a List';
        }

        {
            my $n = 0;
            GLRfor($x.GLRmap(* + 2), -> $i {
                $n += $i;
            });
            is $n, 18, 'Can iterate a mapped List';
        }
    }

    # Slip basics (dealing with empty slips; easy).
    {
        my $x = (2 GLR, GLRslip() GLR, 6);
        ok $x ~~ GLRList, ', with an empty slip in middle makes a List';
        is $x.elems, 2, 'List.elems reflects the vanishing slip()';
        is $x[0], 2, 'Can access list with slip in middle (1)';
        is $x[1], 6, 'Can access list with slip in middle (2)';
    }
    {
        my $x = (GLRslip() GLR, 4 GLR, 6);
        ok $x ~~ GLRList, ', with an empty slip at start makes a List';
        is $x.elems, 2, 'List.elems reflects the vanishing slip()';
        is $x[0], 4, 'Can access list with slip at start (1)';
        is $x[1], 6, 'Can access list with slip at start (2)';
    }
    {
        my $x = (2 GLR, 4 GLR, GLRslip());
        ok $x ~~ GLRList, ', with an empty slip at end makes a List';
        is $x.elems, 2, 'List.elems reflects the vanishing slip()';
        is $x[0], 2, 'Can access list with slip at end (1)';
        is $x[1], 4, 'Can access list with slip at end (2)';
    }
    {
        my $x = (2 GLR, GLRslip() GLR, 6);
        is $x[0], 2, 'Can index list with slip in middle without calling .elems first (1)';
        is $x[1], 6, 'Can index list with slip in middle without calling .elems first (2)';
    }
    {
        my $x = (2 GLR, GLRslip() GLR, 4 GLR, GLRslip() GLR, 6);
        my $n = 0;
        GLRfor($x, -> $i {
            $n += $i;
        });
        is $n, 12, 'Can iterate a List with empty slips in it';
    }

    # A Seq is not Positional and can not be indexed.
    {
        dies-ok { my @a := 1 GLRxx 100 }, 'Seq is not Positional';
        throws-like { (1 GLRxx 100)[42] }, X::GLRSeq::NotIndexable, 'Indexing a Seq dies...';
        throws-like { (1 GLRxx 100)[0] }, X::GLRSeq::NotIndexable, '...even with 0';
    }

    # Trying to iterate a Seq twice is an error.
    {
        my $a = 1 GLRxx 100;
        lives-ok { $a.iterator }, 'Can get iterator for a Seq once...';
        throws-like { $a.iterator }, X::GLRSeq::Consumed, '...and only once';
    }

    # A Seq can become a list, and the list it becomes is memoized.
    {
        my $seq = 1 GLRxx 100;
        my $list;
        lives-ok { $list := $seq.list }, 'Seq can be coerced into a .list';
        isa-ok $list, GLRList, 'Actually got a List back';
        ok $list =:= $seq.list, 'Seq gives back the same List every time';
        throws-like { $seq.iterator }, X::GLRSeq::Consumed, '.list takes the iterator';
        is $list[0], 1, 'Can index into List from Seq (1)';
        is $list[5], 1, 'Can index into List from Seq (2)';
        is $list.elems, 100, '.elems on the List gives the correct answer';
    }

    # Can iterate a List created from a Seq.
    {
        my @list := (5 GLRxx 100).list;
        my $n = 0;
        GLRfor(@list, -> $i {
            $n += $i;
        });
        is $n, 500, 'Can iterate a List created from a Seq';
    }

    # Slip with values in it
    {
        my @xs := 1 GLR, GLRslip(2, 3) GLR, 4 GLR, GLRslip(5, 6);
        is @xs.elems, 6, 'A slip in a , list automatically flattens (elems)';        
    }
    {
        my @xs := 1 GLR, GLRslip(2, 3) GLR, 4 GLR, GLRslip(5, 6);
        is @xs[0], 1, 'A slip in a , list automatically flattens (index 0)';
        is @xs[1], 2, 'A slip in a , list automatically flattens (index 1)';
        is @xs[2], 3, 'A slip in a , list automatically flattens (index 2)';
        is @xs[3], 4, 'A slip in a , list automatically flattens (index 3)';
        is @xs[4], 5, 'A slip in a , list automatically flattens (index 4)';
        is @xs[5], 6, 'A slip in a , list automatically flattens (index 5)';
    }
    {
        my $n = 0;
        GLRfor((1 GLR, GLRslip(2, 3) GLR, 4 GLR, GLRslip(5, 6)), -> $i {
            $n += $i;
        });
        is $n, 21, 'Loop over list with slips in it works as expected';
    }

    # Can coerce a Seq into a Slip
    {
        my $seq = 2 GLRxx 5;
        my $n = 0;
        GLRfor((1 GLR, $seq.Slip GLR, 3), -> $i {
            $n += $i;
        });
        is $n, 14, 'A Seq can be made into a Slip';
    }

    # Can coerce a List into a Slip also
    {
        my $list = 2 GLR, 4 GLR, 6;
        my $n = 0;
        GLRfor((1 GLR, $list.Slip GLR, 3), -> $i {
            $n += $i;
        });
        is $n, 16, 'A List can be made into a Slip';
    }

    # map deals with Slip correctly
    {
        my @slippy := (1 GLR, 2 GLR, 3).GLRmap({ GLRslip($_, 3 * $_) }).list;
        is @slippy[0], 1, 'map/Slip interaction produces correct elements (1)';
        is @slippy[1], 3, 'map/Slip interaction produces correct elements (2)';
        is @slippy[2], 2, 'map/Slip interaction produces correct elements (3)';
        is @slippy[3], 6, 'map/Slip interaction produces correct elements (4)';
        is @slippy[4], 3, 'map/Slip interaction produces correct elements (5)';
        is @slippy[5], 9, 'map/Slip interaction produces correct elements (6)';
        is @slippy.elems, 6, 'map/Slip interaction has correct .elems';
    }
    {
        my @slippy := (1 GLR, 2 GLR, 3).GLRmap({ GLRslip($_, 3 * $_) }).list;
        is @slippy.elems, 6, 'map/Slip interaction has correct .elems (.elems first)';
        is @slippy[0], 1, 'map/Slip interaction produces correct elements (.elems first) (1)';
        is @slippy[1], 3, 'map/Slip interaction produces correct elements (.elems first) (2)';
        is @slippy[2], 2, 'map/Slip interaction produces correct elements (.elems first) (3)';
        is @slippy[3], 6, 'map/Slip interaction produces correct elements (.elems first) (4)';
        is @slippy[4], 3, 'map/Slip interaction produces correct elements (.elems first) (5)';
        is @slippy[5], 9, 'map/Slip interaction produces correct elements (.elems first) (6)';
    }

    # [...] creates an Array, which can be indexed. No flattening, but same
    # single-item rule as assignment (so [1 xx 10] has 10 elements).
    {
        isa-ok GLRArrayCircumfix(), GLRArray, '[] creates an Array';
        isa-ok GLRArrayCircumfix(1, 2), GLRArray, '[1, 2] creates an Array';
        is GLRArrayCircumfix(1, 2).elems, 2, '[1, 2].elems is 2';
        is GLRArrayCircumfix(GLRArrayCircumfix(1, 2), GLRArrayCircumfix(3, 4)).elems,
            2, '[[1, 2], [3, 4]].elems is 2';
    }
    {
        my @a := GLRArrayCircumfix(1, 2);
        is @a[0], 1, 'Can index an array (1)';
        is @a[1], 2, 'Can index an array (2)';
        lives-ok { @a[0] = 3; @a[1] = 4; }, 'Can assign to array elements';
        is @a[0], 3, 'Array elements have new values after assignment (1)';
        is @a[1], 4, 'Array elements have new values after assignment (2)';
    }
    {
        my @a := GLRArrayCircumfix(1, GLRslip(2, 3), 4);
        is @a[0], 1, 'Can index an array with a slip in it (1)';
        is @a[1], 2, 'Can index an array with a slip in it (2)';
        is @a[2], 3, 'Can index an array with a slip in it (3)';
        is @a[3], 4, 'Can index an array with a slip in it (4)';
        
        lives-ok { @a[0] = 6 }, 'Can assign to array element before slip';
        is @a[0], 6, 'Array elements before slip has new value after assignment';
        lives-ok { @a[1] = 7; @a[2] = 8 }, 'Can assign to array element getting value from slip';
        is @a[1], 7, 'Array elements from slip have new values after assignment (1)';
        is @a[2], 8, 'Array elements from slip have new values after assignment (2)';
        lives-ok { @a[3] = 9 }, 'Can assign to array element after slip';
        is @a[3], 9, 'Array elements after slip has new value after assignment';
    }
    {
        # XXX auto-extension tests
    }

    # [...] evaluates eagerly...up until an infinite thing is encountered.
    {
        my @a := GLRArrayCircumfix(1, 2);
        my @b := GLRArrayCircumfix(@a);
        @a[0] = 3;
        @a[1] = 4;
        is @b[0], 1, 'Inside of [...] is eager on a single array';
        is @b[1], 2, 'Inside of [...] is eager on a single array';
    }
    {
        my @a := GLRArrayCircumfix(1, 2, infix:<GLRxx>(42, *).Slip);
        pass "Array constructed with infinite slip didn't hang";
        is @a[0], 1, 'Can index into array with infinite slip (1)';
        is @a[1], 2, 'Can index into array with infinite slip (2)';
        is @a[2], 42, 'Can index into array with infinite slip (3)';
        is @a[3], 42, 'Can index into array with infinite slip (4)';
        is @a[4], 42, 'Can index into array with infinite slip (5)';
    }

    # Can STORE into an Array, which also evaluates everything eagerly that is
    # not known to be infinite.
    {
        my @a := GLRArrayCircumfix();
        @a = 1 GLR, 2 GLR, 3;
        is @a.elems, 3, 'Assigned list of 3 things into array';
        is @a[0], 1, 'Can access assigned array value (1)';
        is @a[1], 2, 'Can access assigned array value (2)';
        is @a[2], 3, 'Can access assigned array value (3)';
    }
    {
        my @a := GLRArrayCircumfix();
        my @b := GLRArrayCircumfix(1, 2);
        @a = @b;
        is @a.elems, 2, 'Assigned array of 2 things into array';
        is @a[0], 1, 'Can access assigned array value (1)';
        is @a[1], 2, 'Can access assigned array value (2)';
        @b[0] = 3;
        is @a[0], 1, 'Changing array that was asigned does not mutate one assinged to';
    }
    {
        my @a := GLRArrayCircumfix();
        @a = GLRArrayCircumfix(1, 2) GLR, GLRArrayCircumfix(3, 4);
        is @a.elems, 2, 'Array assignment does not flatten beyond top level list';
        is @a[0][0], 1, 'Nested array preserved as expected (1)';
        is @a[0][1], 2, 'Nested array preserved as expected (2)';
        is @a[1][0], 3, 'Nested array preserved as expected (3)';
        is @a[1][1], 4, 'Nested array preserved as expected (4)';
    }
    {
        my @a := GLRArrayCircumfix();
        @a = 'beer' GLRxx 3;
        is @a.elems, 3, 'Array assigned a Seq gets correct number of elements';
        is @a[0], 'beer', 'Can access assigned array value (1)';
        is @a[1], 'beer', 'Can access assigned array value (2)';
        is @a[2], 'beer', 'Can access assigned array value (3)';
    }
    {
        my @a := GLRArrayCircumfix();
        @a = infix:<GLRxx>('whisky', *);
        pass 'Assigning infinite sequence to an array did not hang';
        is @a[0], 'whisky', 'Can access assigned array value (1)';
        is @a[42], 'whisky', 'Can access assigned array value (2)';
    }
    {
        my @a := GLRArrayCircumfix();
        @a = 'ale' GLR, 'barley wine' GLR, infix:<GLRxx>('whisky', *).Slip;
        pass 'Assigning list containing infinite slip does not hang';
        is @a[0], 'ale', 'Can access assigned array value (1)';
        is @a[1], 'barley wine', 'Can access assigned array value (2)';
        is @a[2], 'whisky', 'Can access assigned array value (3)';
        is @a[3], 'whisky', 'Can access assigned array value (4)';
        is @a[99], 'whisky', 'Can access assigned array value (5)';
    }
    {
        my @a := GLRArrayCircumfix();
        @a = 'lonely';
        is @a.elems, 1, 'Array assigned a single item has 1 element';
        is @a[0], 'lonely', 'Can access assigned array value';
    }

    # Storing into an array actually replaces existing content
    {
        my @a := GLRArrayCircumfix(1, 2, 3);
        is @a.elems, 3, 'Storing an item clears array (sanity check)';
        @a = 'one thing';
        is @a.elems, 1, 'Correct number of items after single item assignment';
        is @a[0], 'one thing', 'Correct element after single item assignment';
        nok @a[1].DEFINITE, 'Original elements gone (1)';
        nok @a[1].DEFINITE, 'Original elements gone (2)';
    }
    {
        my @a := GLRArrayCircumfix(1, 2, GLRslip(3, 4));
        is @a.elems, 4, 'Storing a list clears array (sanity check)';
        @a = 5 GLRxx 3;
        is @a.elems, 3, 'Correct number of items after list assignment';
        is @a[0], 5, 'Correct element after list assignment (1)';
        is @a[1], 5, 'Correct element after list assignment (2)';
        is @a[2], 5, 'Correct element after list assignment (3)';
        nok @a[3].DEFINITE, 'Original elements gone';
    }

    # Storing into an array respects $ and .item
    {
        my @a := GLRArrayCircumfix();
        @a = $(1 GLR, 2);
        is @a.elems, 1, 'Array has one element after assigning list as item ($)';
        isa-ok @a[0], GLRList, 'The one element is a list';
        is @a[0][0], 1, 'Can access nested list (1)';
        is @a[0][1], 2, 'Can access nested list (2)';
    }
    {
        my @a := GLRArrayCircumfix();
        @a = (1 GLR, 2).item;
        is @a.elems, 1, 'Array has one element after assigning list as item (.item)';
        isa-ok @a[0], GLRList, 'The one element is a list';
        is @a[0][0], 1, 'Can access nested list (1)';
        is @a[0][1], 2, 'Can access nested list (2)';
    }
    {
        my @a := GLRArrayCircumfix();
        @a = $(GLRArrayCircumfix(1, 2));
        is @a.elems, 1, 'Array has one element after assigning array as item ($)';
        isa-ok @a[0], GLRArray, 'The one element is an array';
        is @a[0][0], 1, 'Can access nested array (1)';
        is @a[0][1], 2, 'Can access nested array (2)';
    }
    {
        my @a := GLRArrayCircumfix();
        @a = GLRArrayCircumfix(1, 2).item;
        is @a.elems, 1, 'Array has one element after assigning list as item (.item)';
        isa-ok @a[0], GLRArray, 'The one element is an array';
        is @a[0][0], 1, 'Can access nested array (1)';
        is @a[0][1], 2, 'Can access nested array (2)';
    }
    {
        my @a := GLRArrayCircumfix();
        @a = $(1 GLRxx 5);
        is @a.elems, 1, 'Array has one element after assigning Seq as item ($)';
        isa-ok @a[0], GLRSeq, 'The one element is a Seq';
    }
    {
        my @a := GLRArrayCircumfix();
        @a = (1 GLRxx 5).item;
        is @a.elems, 1, 'Array has one element after assigning Seq as item (.item)';
        isa-ok @a[0], GLRSeq, 'The one element is a Seq';
    }

    # flat flattens all iterable non-item things recursively, and returns a
    # Seq
    {
        my $flat-seq := GLRflat (1 GLR, 2) GLR, (3 GLR, 4);
        isa-ok $flat-seq, GLRSeq, 'flat returns a Seq';
        my @flattened := $flat-seq.list;
        pass 'Can .list a Seq obtained from flat';
        is @flattened.elems, 4, 'Flattened to 4 elements';
        is @flattened[0], 1, 'Correct flattened element (1)';
        is @flattened[1], 2, 'Correct flattened element (2)';
        is @flattened[2], 3, 'Correct flattened element (3)';
        is @flattened[3], 4, 'Correct flattened element (4)';
    }
    {
        my $flat-seq := ((1 GLR, 2) GLR, (3 GLR, 4 GLR, 5)).flat;
        isa-ok $flat-seq, GLRSeq, '.flat on a List returns a Seq';
        my @flattened := $flat-seq.list;
        pass 'Can .list a Seq obtained from .flat';
        is @flattened.elems, 5, 'Flattened to 5 elements';
        is @flattened[0], 1, 'Correct flattened element (1)';
        is @flattened[1], 2, 'Correct flattened element (2)';
        is @flattened[2], 3, 'Correct flattened element (3)';
        is @flattened[3], 4, 'Correct flattened element (4)';
        is @flattened[4], 5, 'Correct flattened element (5)';
    }
    {
        my $flat-seq := ((1 GLR, (2 GLR, (3 GLR, 4 GLR, 5) GLR, 6))).flat;
        my @flattened := $flat-seq.list;
        is @flattened.elems, 6, 'Flattened nested lists to 6 elements';
        is @flattened[0], 1, 'Correct flattened element (1)';
        is @flattened[1], 2, 'Correct flattened element (2)';
        is @flattened[2], 3, 'Correct flattened element (3)';
        is @flattened[3], 4, 'Correct flattened element (4)';
        is @flattened[4], 5, 'Correct flattened element (5)';
        is @flattened[5], 6, 'Correct flattened element (6)';
    }
    {
        my $flat-seq := ((1 GLR, (2 GLR, $(3 GLR, 4 GLR, 5) GLR, 6))).flat;
        my @flattened := $flat-seq.list;
        is @flattened.elems, 4, 'Flattened nested lists, one with $, to 4 elements';
        is @flattened[0], 1, 'Correct flattened element (1)';
        is @flattened[1], 2, 'Correct flattened element (2)';
        is @flattened[3], 6, 'Correct flattened element (3)';
        isa-ok @flattened[2], GLRList, 'Respected $ and did not flatten list with it';
        is @flattened[2][0], 3, 'Can access unflattened item list (1)';
        is @flattened[2][1], 4, 'Can access unflattened item list (2)';
        is @flattened[2][2], 5, 'Can access unflattened item list (3)';
    }

    # my @a = flat ...;
    {
        my @a := GLRArrayCircumfix();
        @a = GLRflat 1, 2, (3 GLRxx 3);
        is @a.elems, 5, 'flat with array assignment gives correct element count';
        is @a[0], 1, 'flattening array assignment got correct element (1)';
        is @a[1], 2, 'flattening array assignment got correct element (2)';
        is @a[2], 3, 'flattening array assignment got correct element (3)';
        is @a[3], 3, 'flattening array assignment got correct element (4)';
        is @a[4], 3, 'flattening array assignment got correct element (5)';
    }

    # Storing an Array into itself is unproblematic (including if we are
    # assigning a map over it, etc.)
    {
        my @a := GLRArrayCircumfix(1, 2);
        @a = @a;
        is @a.elems, 2, 'Array assigned to itself retains elements (simple)';
        is @a[0], 1, 'Array assigned to itself retains element values (simple) (1)';
        is @a[1], 2, 'Array assigned to itself retains element values (simple) (2)';
    }
    {
        my @a := GLRArrayCircumfix(infix:<GLRxx>(42, *));
        @a = @a;
        is @a[0], 42, 'Array assigned to itself retains element values (infinite seq) (1)';
        is @a[1], 42, 'Array assigned to itself retains element values (infinite seq) (2)';
        is @a[2], 42, 'Array assigned to itself retains element values (infinite seq) (3)';
    }
    {
        my @a := GLRArrayCircumfix(infix:<GLRxx>(42, *));
        is @a[1], 42, 'Infinite array OK before assignment to self';
        @a = @a;
        is @a[0], 42, 'Array assigned to itself retains element values (infinite seq part reified) (1)';
        is @a[1], 42, 'Array assigned to itself retains element values (infinite seq part reified) (2)';
        is @a[2], 42, 'Array assigned to itself retains element values (infinite seq part reified) (3)';
    }
    {
        my @a := GLRArrayCircumfix(infix:<GLRxx>(42, *));
        is @a[1], 42, 'Infinite array OK before assignment to mapped self';
        @a = @a.GLRmap(* + 10);
        is @a[0], 52, 'Array assigned to its mapped self gets correct element values (1)';
        is @a[1], 52, 'Array assigned to its mapped self gets correct element values (2)';
        is @a[2], 52, 'Array assigned to its mapped self gets correct element values (3)';
    }

    # Seq.Array, List.Array, Slip.Array
    {
        my $seq = 2 GLRxx 4;
        my @arr := $seq.Array;
        is @arr.elems, 4, 'Seq coerced to Array got correct number of elements';
        is @arr[0], 2, 'Seq coerced to Array got correct element (1)';
        is @arr[1], 2, 'Seq coerced to Array got correct element (2)';
        is @arr[2], 2, 'Seq coerced to Array got correct element (3)';
        is @arr[3], 2, 'Seq coerced to Array got correct element (4)';
        lives-ok { @arr[1] = 5 }, 'Can assign to array element populated by coerced Seq';
        is @arr[1], 5, 'Assigned value actually updated array';
    }
    {
        my @list := 5 GLR, 6 GLR, 7;
        my @arr := @list.Array;
        is @arr.elems, 3, 'List coerced to Array got correct number of elements';
        is @arr[0], 5, 'List coerced to Array got correct element (1)';
        is @arr[1], 6, 'List coerced to Array got correct element (2)';
        is @arr[2], 7, 'List coerced to Array got correct element (3)';
        lives-ok { @arr[1] = 8 }, 'Can assign to array element populated by coerced List';
        is @arr[1], 8, 'Assigned value actually updated array';
    }
    {
        my @slip := GLRslip(6, 7, 8, 9);
        my @arr := @slip.Array;
        is @arr.elems, 4, 'Slip coerced to Array got correct number of elements';
        is @arr[0], 6, 'Slip coerced to Array got correct element (1)';
        is @arr[1], 7, 'Slip coerced to Array got correct element (2)';
        is @arr[2], 8, 'Slip coerced to Array got correct element (3)';
        is @arr[3], 9, 'Slip coerced to Array got correct element (4)';
        lives-ok { @arr[1] = 1 }, 'Can assign to array element populated by coerced Slip';
        is @arr[1], 1, 'Assigned value actually updated array';
    }

    # gather/take
    {
        my $gt := GLRgather({ take 'lunch'; take 'siesta'; });
        isa-ok $gt, GLRSeq, 'gather block returns a Seq';
        my $iter := $gt.iterator;
        is $iter.pull-one, 'lunch', 'first take produced result';
        is $iter.pull-one, 'siesta', 'second take produced result';
        ok $iter.pull-one =:= GLRIterationEnd, 'reached end of iteration at block end';
    }
    {
        my $state = 1;
        my $gt := GLRgather({ loop { take $state } });
        my $iter := $gt.iterator;
        is $iter.pull-one, 1, 'first take in loop produces initial value of state';
        $state++;
        is $iter.pull-one, 2, 'second take in loop produces updated state';
    }
    {
        my @arr := GLRArrayCircumfix();
        lives-ok { @arr = GLRgather({ take 'tram'; take 'train'; take 'plane'; }) },
            'Can assign a gather into an array';
        is @arr.elems, 3, 'Array has correct number of elements';
        is @arr[0], 'tram', 'Array got correct element (1)';
        is @arr[1], 'train', 'Array got correct element (2)';
        is @arr[2], 'plane', 'Array got correct element (3)';
    }
    {
        my $gt := GLRgather({
            take GLRslip('pale ale', 'ipa');
            take 'brown ale';
            take GLRslip('stout', 'barley wine');
        });
        my $iter := $gt.iterator;
        is $iter.pull-one, 'pale ale', 'first result is first value from first slip';
        is $iter.pull-one, 'ipa', 'second result is second value from first slip';
        is $iter.pull-one, 'brown ale', 'third result is from take without slip';
        is $iter.pull-one, 'stout', 'forth result is first value from second slip';
        is $iter.pull-one, 'barley wine', 'fifth result is second value from second slip';
        ok $iter.pull-one =:= GLRIterationEnd, 'reached end of iteration at block end';
    }
    {
        my @arr := GLRArrayCircumfix();
        @arr = GLRgather({
            take GLRslip('pale ale', 'ipa');
            take 'brown ale';
            take GLRslip('stout', 'barley wine');
        });
        is @arr.elems, 5, 'Array assigned gather/take with Slips has correct number of elements';
        is @arr[0], 'pale ale', 'Array assigned gather/take with slips has correct values (1)';
        is @arr[1], 'ipa', 'Array assigned gather/take with slips has correct values (2)';
        is @arr[2], 'brown ale', 'Array assigned gather/take with slips has correct values (3)';
        is @arr[3], 'stout', 'Array assigned gather/take with slips has correct values (4)';
        is @arr[4], 'barley wine', 'Array assigned gather/take with slips has correct values (5)';
    }
    {
        my $gt := GLRgather({
            take GLRslip('pale ale', 'ipa');
            take 'brown ale';
            take GLRslip('stout', 'barley wine');
        });
        my $iter := $gt.iterator;
        is $iter.pull-one, 'pale ale', 'first result is first value from first slip';
        my \buffer = GLRIterationBuffer.CREATE;
        $iter.push-exactly(buffer, 2);
        is buffer[0], 'ipa', 'push-exactly(2) got second value from slip as first item';
        is buffer[1], 'brown ale', 'push-exactly(2) got second take value as second item';
        is $iter.pull-one, 'stout', 'forth result is first value from second slip';
        my \buffer2 = GLRIterationBuffer.CREATE;
        ok $iter.push-exactly(buffer2, 2) =:= GLRIterationEnd,
            'asking for 2 things when only one more to be taken returns GLRIterationEnd';
        is buffer2[0], 'barley wine', 'the one available result was pushed';
    }

    # Lazy loops (loop/while/until/repeat while/repeat until). Note that there
    # are no negated forms; the compiler can do that bit.
    {
        # Below is how we compile 'lazy loop { 42 }', an infinite loop
        my $seq := GLRSeq.from-loop({ ++(state $i = 0) });
        my @a := GLRArrayCircumfix();
        @a = $seq;
        pass 'loop { ... } with no condition is known infinite; array assign OK';
        is @a[0], 1, 'correct value from infinite loop (1)';
        is @a[1], 2, 'correct value from infinite loop (2)';
        is @a[42], 43, 'correct value from infinite loop (3)';
        is @a[19], 20, 'correct value from infinite loop (4)';
    }
    {
        my $seq := GLRSeq.from-loop({ GLRslip(++(state $i = 0), ++(state $j = 2)) });
        my @a := GLRArrayCircumfix();
        @a = $seq;
        is @a[0], 1, 'correct value from infinite loop with slip (1)';
        is @a[1], 3, 'correct value from infinite loop with slip (2)';
        is @a[2], 2, 'correct value from infinite loop with slip (3)';
        is @a[3], 4, 'correct value from infinite loop with slip (4)';
    }
    {
        my $seq := GLRSeq.from-loop({
            (state $a)++; 
            next if (state $)++ < 2;
            redo if (state $)++ == 4;
            last if (state $)++ == 6;
            $a
        });
        my @a := GLRArrayCircumfix();
        @a = $seq;
        is @a.elems, 6, 'infinite loop with next/redo/last produced correct number of elements';
        is @a[0], 3, 'correct value from infinite loop with next/redo/last (1)';
        is @a[1], 4, 'correct value from infinite loop with next/redo/last (2)';
        is @a[2], 5, 'correct value from infinite loop with next/redo/last (3)';
        is @a[3], 6, 'correct value from infinite loop with next/redo/last (4)';
        is @a[4], 8, 'correct value from infinite loop with next/redo/last (5)';
        is @a[5], 9, 'correct value from infinite loop with next/redo/last (6)';
    }
    {
        # This is how we compile 'lazy loop (my $i = 0; $i < 5; $i++) { $i * 2 }'
        # (with the caveat that the second two args to from-loop will be Code,
        # not Block, because it doesn't imply a lexical scope):
        my $i = 0;
        my $seq := GLRSeq.from-loop({ $i * 2 }, { $i < 5 }, { $i++ });
        my @a := GLRArrayCircumfix();
        @a = $seq;
        is @a.elems, 5, 'Got correct number of elements from lazy C-style loop';
        is @a[0], 0, 'correct value from lazy C-style loop (1)';
        is @a[1], 2, 'correct value from lazy C-style loop (2)';
        is @a[2], 4, 'correct value from lazy C-style loop (3)';
        is @a[3], 6, 'correct value from lazy C-style loop (4)';
        is @a[4], 8, 'correct value from lazy C-style loop (5)';
    }
    {
        my $i = 0;
        my $seq := GLRSeq.from-loop(
            {
                (state $a)++;
                redo if $a == 2;
                next if $a == 4;
                last if $a == 6;
                GLRslip($i, $a)
            },
            { $i < 10 },
            { $i++ });
        my @a := GLRArrayCircumfix();
        @a = $seq;
        is @a.elems, 6, 'Got correct number of elements from lazy C-style loop (control + slip)';
        is @a[0], 0, 'correct value from lazy C-style loop (control + slip) (1)';
        is @a[1], 1, 'correct value from lazy C-style loop (control + slip) (2)';
        is @a[2], 1, 'correct value from lazy C-style loop (control + slip) (3)';
        is @a[3], 3, 'correct value from lazy C-style loop (control + slip) (4)';
        is @a[4], 3, 'correct value from lazy C-style loop (control + slip) (5)';
        is @a[5], 5, 'correct value from lazy C-style loop (control + slip) (6)';
    }
    {
        # This is how we compile 'lazy while $i < 5 { $i++ * 2 }'  (with the
        # caveat that the second args to from-loop will be Code, not Block,
        # because they don't imply a lexical scope):
        my $i = 0;
        my $seq := GLRSeq.from-loop({ $i++ * 2 }, { $i < 5 });
        my @a := GLRArrayCircumfix();
        @a = $seq;
        is @a.elems, 5, 'Got correct number of elements from lazy while loop';
        is @a[0], 0, 'correct value from lazy while loop (1)';
        is @a[1], 2, 'correct value from lazy while loop (2)';
        is @a[2], 4, 'correct value from lazy while loop (3)';
        is @a[3], 6, 'correct value from lazy while loop (4)';
        is @a[4], 8, 'correct value from lazy while loop (5)';
    }
    {
        my $i = 0;
        my $seq := GLRSeq.from-loop(
            {
                (state $a)++;
                redo if $a == 2;
                next if $a == 4;
                last if $a == 6;
                GLRslip($i++, $a)
            },
            { $i < 10 });
        my @a := GLRArrayCircumfix();
        @a = $seq;
        is @a.elems, 6, 'Got correct number of elements from lazy while loop (control + slip)';
        is @a[0], 0, 'correct value from lazy while loop (control + slip) (1)';
        is @a[1], 1, 'correct value from lazy while loop (control + slip) (2)';
        is @a[2], 1, 'correct value from lazy while loop (control + slip) (3)';
        is @a[3], 3, 'correct value from lazy while loop (control + slip) (4)';
        is @a[4], 2, 'correct value from lazy while loop (control + slip) (5)';
        is @a[5], 5, 'correct value from lazy while loop (control + slip) (6)';
    }
    {
        # A lazy repeat while just passes :repeat.
        my $i = 42;
        my $seq := GLRSeq.from-loop({ $i++ }, { $i < 0 }, :repeat);
        my @a := GLRArrayCircumfix();
        @a = $seq;
        is @a.elems, 1, 'Got element from lazy repeat despite false start condition';
        is @a[0], 42, 'correct value from lazy repeat';
    }

    done;
}

# Run with --optimize=3 to give the code the same set of optimizations it'll
# get when incorporated into CORE.setting.
multi MAIN('benchmark') {
    contrast("for loop over 'beer' xx 100000",
        before => { for 'beer' xx 100000 -> $beer { } },
        after  => { GLRfor('beer' GLRxx 100000, -> $beer { }) });

    contrast("for loop over 'beer' xx 100000 with map",
        before => { for ('beer' xx 100000).map(*.uc) -> $beer { } },
        after  => { GLRfor(('beer' GLRxx 100000).GLRmap(*.uc), -> $beer { }) });

    contrast("for loop over ('beer' xx 100000) in a list (so must remember values)",
        before => {
            my @a := ('beer' xx 100000).list;
            for @a -> $beer { }
            die 'oops' unless @a.elems == 100000;
        },
        after => {
            my @a := ('beer' GLRxx 100000).list;
            GLRfor(@a, -> $beer { });
            die 'oops' unless @a.elems == 100000;
        });

    contrast("for loop over ('beer' xx 100000) in a list, mapping it with *.uc",
        before => {
            my @a := ('beer' xx 100000).list;
            for @a.map(*.uc) -> $beer { }
            die 'oops' unless @a.elems == 100000;
        },
        after => {
            my @a := ('beer' GLRxx 100000).list;
            GLRfor(@a.GLRmap(*.uc), -> $beer { });
            die 'oops' unless @a.elems == 100000;
        });

    contrast("for loop over ('beer' xx 100000).map(*.uc) in a list",
        before => {
            my @a := ('beer' xx 100000).map(*.uc).list;
            for @a -> $beer { }
            die 'oops' unless @a.elems == 100000;
        },
        after => {
            my @a := ('beer' GLRxx 100000).GLRmap(*.uc).list;
            GLRfor(@a, -> $beer { });
            die 'oops' unless @a.elems == 100000;
        });

    contrast("gather/take assigned into an array",
        before => {
            my @a = gather {
                my int $i = 0;
                while $i < 100000 {
                    take 'x';
                    $i = $i + 1;
                }
            }
            die 'oops' unless @a.elems == 100000;
        },
        after => {
            my @a := GLRArrayCircumfix();
            @a = GLRgather {
                my int $i = 0;
                while $i < 100000 {
                    take 'x';
                    $i = $i + 1;
                }
            }
            die 'oops' unless @a.elems == 100000;
        });

    contrast("for loop over gather/take",
        before => {
            my \things = gather {
                my int $i = 0;
                while $i < 100000 {
                    take 'x';
                    $i = $i + 1;
                }
            }
            for things -> $i { }
        },
        after => {
            my \things = GLRgather {
                my int $i = 0;
                while $i < 100000 {
                    take 'x';
                    $i = $i + 1;
                }
            }
            GLRfor(things, -> $i { });
        });

    sub contrast($title, :&before, :&after) {
        # Run to allow most warm-up (for JIT, etc.)
        before(); after();

        # Measure runs before and after.
        sub time(&task) {
            my num $start = nqp::time_n();
            task();
            return nqp::time_n() - $start
        }
        my @before-times = time(&before) xx 3;
        my @after-times  = time(&after) xx 3;

        # Show means.
        sub mean(@times) { # insert bad pun involving Greenwich here...
            @times R/ [+] @times
        }
        say "$title ==> was &mean(@before-times)s, now &mean(@after-times)s";
    }
}

# Run with --profile to actually get profiling output
multi MAIN('profile') {
    my @a := ('beer' GLRxx 100000).list;
    GLRfor(@a, -> $beer { });
    die 'oops' unless @a.elems == 100000;
}

# Outstanding GLR issues
# * $foo[1..10] calls .list on the thing it'll index into, which creates an
#   extra burden for those doing custom list types (see discussion with smls
#   on 2015-08-01).
# * Document all the known infinite things
