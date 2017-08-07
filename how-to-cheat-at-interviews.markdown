
How to Cheat at Interviews With Perl 6

# Outline

tl;dr
    While 'operator-richness' certainly adds to Perl 6's cognitive complexity, it
    considerably increases expressivity.

    While 'bootstrapping' certainly adds to Perl 6's implementation complexity,
    it considerably increases the average developer's ability to poke at What
    is going on under the hood.

    By enabling practitioners to both give concise solutions _and_ in depth
    explanations of internal underpinnings, these two dynamics combine
    to create a potentially great choice for impressing



# Complexity

- Programming language design is all about tradeoffs.
    - We are going to talk about the tradeoffs related to complexity.
    - There is a potential for a higher "up front" complexity to reduce
      the cognitive load of programming in a given language in the long term.
      - Small standard library because everything is easy leads to many divergent
        and (sometimes) subtly incompatible solutions to common tasks.
      - XXX: ADD SOME EXAMPLES (Forth, Lisp, but also Perl 5)

- Learning a programming language is all about tradeoffs.
    - How much time will it take? Will there be any returns on my time investment?
    - How much ridicule will I face? Will there be any returns on my emotional investment?
    - Only one certainty: You have to trade in the relative comfort of knee jerk biases by actually learning about which
      tradeoffs were accepted by the implementors and why.

# Symmetric differences

- Perl 6 is actually a bit on a limb with it's explorations of the `QuantHash` family -- `Set`, `Bag` and `Mix`.
    - The one feeling I had for certain was that this should be true:
        - -  `sub is-anagram($a,$b) { $a.comb.Bag (^) $b.comb.Bag  === bag() }`
    - ... but how should list behavior go?
