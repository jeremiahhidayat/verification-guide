# Chapter 3: SystemVerilog Assertions (SVA)

An assertion is a specification sentence made executable. "After `req`, `ack` must arrive within 4
cycles" becomes `req |-> ##[1:4] ack`. The simulator (or a formal tool) then checks it on *every*
cycle of *every* test, forever, and reports the exact cycle it is violated. Assertions are the highest
leverage checking tool you have: one line, always on, fails at the point of the bug, reusable in
formal.

They are also the source of the most subtle testbench bugs, because their sampling semantics differ
from procedural code and because temporal logic is unintuitive until it is not. This chapter builds
from the sampling model up.

| Section | Topic |
|---|---|
| [3.1](01-immediate-vs-concurrent.md) | Immediate vs concurrent assertions; the sampling model; `disable iff`; action blocks; severity |
| [3.2](02-sequences-and-properties.md) | Boolean, sequence, property layers; delays, repetition, implication, sampled-value functions, sequence operators, local variables |
| [3.3](03-pitfalls-and-debug.md) | Vacuity, `disable iff` timing, `$past` across reset, functions in assertions, multiple-match explosions, debugging with action blocks and `$sampled` |
| [3.4](04-sva-cookbook.md) | A cookbook: handshake, stability, one-hot, latency, ordering, FIFO, arbiter fairness, X-checks, `bind`, checker libraries |

Code: [`code/03-sva/`](../../code/03-sva/).
