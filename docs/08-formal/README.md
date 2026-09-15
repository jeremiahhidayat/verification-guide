# Chapter 8: Formal Verification

Simulation samples the input space. Formal verification *reasons about all of it*: a property is
either proven true for every possible input sequence from every reachable state, or the tool hands
you a counterexample trace. No stimulus, no seeds, no coverage holes for the properties it proves.
The cost is that formal is limited by design size and property depth, and that writing properties
that are both correct and provable is a skill distinct from writing simulation checkers.

This chapter is about *how to do formal well*: what a proof means, how to choose targets, how to
write properties and assumptions that converge, and how formal fits next to simulation in a real
flow.

| Section | Topic |
|---|---|
| [8.1](01-formal-fundamentals.md) | What a model checker does; assert/assume/cover in formal; bounded vs full proofs; reachable states; the results vocabulary |
| [8.2](02-formal-friendly-properties.md) | Writing properties that converge: end-to-end vs local, forward-looking local variables, liveness vs safety, fairness, assumptions and over-constraint |
| [8.3](03-formal-flows-and-apps.md) | Formal property verification setup; the "apps": connectivity, register, X-prop, deadlock, unreachability (UNR), sequential equivalence, security; tool landscape incl. open-source SymbiYosys |
| [8.4](04-formal-in-practice.md) | Choosing what to formally verify, convergence techniques (abstractions, case splitting, helper assertions, cut points), coverage and signoff for formal, typical project workflow |

Code: [`code/08-formal/`](../../code/08-formal/), formal properties for the FIFO with a
SymbiYosys script and notes for commercial tools.
