# 8.1 Formal Fundamentals

## The design as a state machine

Any synchronous digital design is a finite state machine: a state vector S (every flop and memory
bit), an input vector I, a next-state function `S' = f(S, I)`, and outputs `O = g(S, I)`. A property
P is a claim about sequences of (S, I, O). Formal property verification (FPV, model checking) asks:

> Starting from the reset state(s), is there *any* sequence of inputs that reaches a state where P is
> violated?

If no: P is **proven**. If yes: the tool returns the shortest such sequence as a **counterexample**
(CEX), a waveform you can debug exactly like a simulation failure. There is no third answer, except
"I ran out of resources," which is the practical reality for large designs and deep properties.

## How the tools search

You do not need to implement a model checker, but knowing the two main strategies explains
convergence behavior:

- **Bounded model checking (BMC)**: unroll the design k cycles from reset, encode "P fails at cycle
  k" as a Boolean satisfiability (SAT) problem, ask a SAT solver. Increase k. A failure at depth k is
  a real CEX. Passing to depth k proves P holds for *all traces of length up to k* (a **bounded
  proof**), not in general.
- **Unbounded proof engines** (k-induction, IC3/PDR, interpolation, BDD reachability): try to prove
  that no reachable state violates P by finding an inductive invariant. When they succeed, P is
  proven for all time (a **full proof**). They can also fail to converge without either result.

Commercial tools run many engines in parallel and take the first to answer. Your job is to make the
problem small enough that one of them does.

## The three directives, in formal terms

| Directive | Simulation meaning | Formal meaning |
|---|---|---|
| `assert property (P)` | Check P on each cycle of this run; report violations | **Prove** P for all input sequences; or find a CEX |
| `assume property (A)` | Same as assert (a violated assumption is reported) | **Constrain**: only consider input sequences where A holds on every cycle. Assumptions are the legal-input specification. |
| `cover property (C)` | Count how often C completed | **Reachability**: find *some* input sequence that makes C complete; the trace is a witness. Unreachable covers indicate over-constraint or dead logic. |

The relationship: formal proves `assumptions -> assertions`. If your assumptions are too weak,
you get CEXs that are illegal in the real system (false failures). If they are too strong, the tool
proves your assertions over an empty or tiny set of behaviors (false proofs). Cover properties are
how you detect the second case.

## Reachable states and reset

Formal starts from the reset state, defined by asserting reset for some cycles with the tool's reset
spec. Everything not reset is free (any value, including X in tools that model it). Unreachable
states (e.g., a one-hot FSM with two bits set) are never explored *if* the tool can prove them
unreachable; if it cannot (deep), an inductive engine may report a "spurious" CEX starting from an
unreachable state. Helper assertions (`$onehot(state)`) that the tool *can* prove then strengthen
the induction and remove the spurious CEX. This "help the induction" loop is the daily work of
formal convergence.

## Results vocabulary

| Result | Meaning | Action |
|---|---|---|
| **Proven** / **pass** (full) | Holds from reset for all inputs, all time | Done for this property; check it is not vacuous (see cover) |
| **Bounded proven** / **pass (bounded, depth N)** | No CEX within N cycles of reset | Decide if N is enough (does the design's interesting behavior fit in N cycles? deeper FIFOs need larger N) |
| **CEX** / **fail** | A trace violates the property | Debug: RTL bug, wrong property, or missing assumption |
| **Undetermined** / **inconclusive** | Engines gave up (memory/time) | Abstract, cut, split, or strengthen with helpers |
| **Vacuous** | Antecedent can never be true under the assumptions | Over-constrained; fix assumptions |
| **Covered** / **unreachable** (for cover) | A witness exists / provably none | Unreachable = over-constraint or dead code |

## Safety vs. liveness

- **Safety**: "something bad never happens." Violated by a finite trace. `grant |-> req`,
  `!(wr && full)`, `count <= DEPTH`. Provable by all engines; the bulk of formal work.
- **Liveness**: "something good eventually happens." `req |-> s_eventually ack`, `##[1:$] ack`
  (strong). Violated only by an infinite trace (a loop where `ack` never comes). Needs special
  engine support and **fairness assumptions** (e.g., "the downstream `ready` is asserted infinitely
  often," or the tool finds the trivial loop where `ready` is stuck low). In practice, most liveness
  is checked as *bounded* liveness: `req |-> ##[1:MAX] ack`, a safety property.

## What formal is good at, and not

Good: control logic, arbiters, FSMs, handshakes, FIFOs and flow control, interface protocol
compliance, register access policies, connectivity, X-propagation, deadlock, security
(non-interference), anything where the bug is a *corner-case combination* of a few dozen signals.
Formal finds the 1-in-10^9 sequence in seconds.

Weak: wide datapaths with multiplication (SAT hates multipliers), deep sequential behavior
(thousands of cycles), whole-chip end-to-end data integrity, performance/throughput claims,
anything involving analog or software. Those stay with simulation and emulation.

## Interview angle

- "What is the difference between simulation and formal?" Sampled vs exhaustive; stimulus vs
  assumptions; coverage vs proof depth.
- "What does a bounded proof mean and is it useful?" No CEX up to depth N; useful when N exceeds
  the design's sequential depth for the property; otherwise a strong smoke check.
- "assert vs assume in formal?" Prove vs constrain; over/under-constraint dangers; covers detect
  over-constraint.
- "Safety vs liveness?"

## Mentor's notes

- The first formal run on any block finds bugs in the *assumptions* (your understanding of legal
  input), then bugs in the *properties*, then bugs in the RTL, in that order. Budget for it.
- A CEX from formal is the best bug report a designer can receive: minimal, exact, reproducible,
  no testbench to argue about. Learn to read them fast.
