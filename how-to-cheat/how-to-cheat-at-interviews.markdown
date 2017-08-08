
How to Cheat at Interviews With Perl 6

# Outline

tl;dr
    While 'operator-richness' certainly adds to Perl 6's cognitive complexity, it considerably increases expressivity.

    While 'bootstrapping' certainly adds to Perl 6's implementation complexity, it considerably increases the average developer's ability to poke at What is going on under the hood.

    By enabling practitioners to both give concise solutions _and_ in depth
    explanations of internal underpinnings, these two dynamics combine
    to create a potentially great choice for impressing anyone with an open mind and a love of programming.


# Complexity

- Programming language design is all about tradeoffs.
    - We are going to talk about the tradeoffs related to complexity.
    - There is a potential for a higher "up front" complexity to reduce
      the cognitive load of programming in a given language in the long term.
      - Small standard library because everything is easy leads to many divergent and (sometimes) subtly incompatible solutions to common tasks.
      - XXX: ADD SOME EXAMPLES (Forth, Lisp, but also Perl 5)

- Learning a programming language is all about tradeoffs.
    - How much time will it take? Will there be any returns on my time investment?
    - How much ridicule will I face? Will there be any returns on my emotional investment?
    - Only one certainty: You have to trade in the relative comfort of knee jerk biases by actually learning about which tradeoffs were accepted by the implementors and why.

# Why Perl 6?

- I can tell you about my experience: after seeing some of the positively tortured solutions in Java and C++ to some of our interview questions, I started to wonder what comparative solutions might look like in Perl 6.
    - In a world: smaller

- "All it took was a taste" ...
    - Of course, during one of my first solutions I ran into what I considered to be a sad situation with the state of 'quant' operations in Rakudo:
        - There was a distinction between set and bag/mix operators that led to
        significant duplication.
        - Most importantly, the symmetric difference operator had no equivalent for bags and mixes. Rather it would always coerce its arguments to sets.
        - This meant that the target question, about acquiring the symmetric difference of two arrays, did not cover the basic followups: what to do with repeating elements.

- It has been worth it.
    - Before moving on I want to just be quite clear: Learning Perl 6 has been wholly worth the effort.
    - Simply from the standpoint of simple command line operations and data munging, it's been amazing.
        - Using the REPL to aggregate, filter, and interact with (Perl 5) database objects was especially fun. Set operators, coupled with quants, make creating and manipulating histograms dead simple.
    - Only downside so far: I get homesick for Rakudo language features when I'm using something else.
        - This is also true of Perl in general.

# Symmetric differences

- Perl 6 is actually a bit on a limb with it's explorations of the `QuantHash` family -- `Set`, `Bag` and `Mix`.

- "Give me all elements that appear in only one of the two arrays"
    - In fact, set semantics for `(^)` are actually fine in the case that all elements in either array are unique anyway.
        - `<a b c>.Set (^) <b c d>.Set` --> `set(d, a)`

    - However, if the arrays can contain multiple values, then what we will actually need to know is more like "how greatly did the occurrence of these values differ between the two arrays".
        - `<a a b b c c>.Set (^) <b c d>.Set` --> `set(d, a) # Not doing it`
        - `<a a b b c c>.Bag (^) <b c d>.Bag` --> `bag(d, b, a(2), c)`





- "One operator, many (interview question) uses"
    - The one feeling I had for certain was that this should be true:
        - -  `sub is-anagram($a,$b) { $a.comb.Bag (^) $b.comb.Bag  == bag() }`
    - ... but how should list behavior go?

# Deep dive: Multi Method Dispatch

```
my @candidates := nqp::getattr($dcself, Routine, '@!dispatchees');
```

line 1969 in BOOTSTRAP.nqp

Multiple dispatach targets are sorted into a graph. A local `is_narrower` sub is used to define the edges of the graph.

On the way to graph construction each candidate is inspected in detail for edge cases such as the presence of signatures with coercion types.

The NQP routine `nqp::multicacheadd` is used to add a given `$capture`/`$entry` pair. This routine is expected to be defined by the underlying VM (or VM-specific glue code).
