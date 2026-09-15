# 8.4 Formal in Practice: Targets, Convergence, Signoff

## Choosing targets

Ask three questions about a block:

1. **Is it control-dominated?** Arbiters, FSMs, flow control, interconnect, credit management,
   power sequencing, interrupt controllers, register banks: yes. Video pipelines, FFTs, crypto
   cores: mostly no (except their control paths).
2. **Is it small or decomposable?** Under ~50k flops proves comfortably; up to a few hundred k with
   abstraction; above that, only local properties or apps. Interfaces of big blocks (the AXI
   slave port of a DMA) are still good targets when you cut the datapath.
3. **Is the cost of a bug high and the scenario deep?** Deadlocks, protocol violations under
   unusual back-pressure, security isolation: formal finds what random simulation practically
   cannot.

Typical formal targets on an SoC: every arbiter and interconnect; all standard-interface
protocol compliance (bind the vendor's AXI/AHB/APB formal VIP); CSR access; connectivity at top
level; clock/reset controllers; power management FSMs; cache coherence controllers (the classic
"only formal finds it" domain); UNR for every block's coverage closure.

## The convergence toolbox

When a property is inconclusive:

| Technique | What it does | When |
|---|---|---|
| **Increase bound / time** | Sometimes it just needs more | First, cheaply |
| **Helper assertions** | Prove simple invariants first; engines use them as lemmas | Inconclusive on properties about counters/pointers/FSMs |
| **Case splitting** | Prove the property under `assume (mode == A)`, then `mode == B`, ... | Configuration-dependent behavior |
| **Cut points / blackboxing** | Replace a sub-block's outputs with free variables | Datapath, memories, arithmetic, sub-blocks proven separately |
| **Abstraction: counters** | Replace a 32-bit timer with a small counter and a "timeout fired" free input, constrained to be plausible | Long delays (timeouts, refresh intervals) |
| **Abstraction: memories** | Replace the array with a single tracked address/data pair (symbolic) | FIFOs, caches, tables |
| **Abstraction: data width** | Reduce a 512-bit data path to 8 bits via parameters | When data width does not affect control (verify the width-dependence separately) |
| **Reset-state abstraction / initial value assumptions** | Start from an arbitrary state satisfying invariants instead of walking from reset | Deep properties; requires proven invariants |
| **Symbolic (nondeterministic) tracking** | Track one arbitrary transaction | End-to-end ordering/integrity |
| **Property decomposition** | Split `A |-> B && C` into two; split long sequences into stages with intermediate assertions | Long temporal chains |
| **Engine selection** | Try IC3/PDR for control invariants, BMC for bug hunting, interpolation for deep | Tool-specific |

Order of attack: helpers, then abstraction of whatever is obviously heavy (memories, arithmetic,
big counters), then decomposition, then case splitting. Document every abstraction and assumption:
they are part of the proof's meaning.

## Debugging a CEX

1. Read the property back in English; confirm it says what the spec says (half of first CEXs are
   property bugs).
2. In the CEX waveform, check the *inputs* the tool chose. If they are illegal per the spec, you are
   missing an assumption. Add it (and a cover to make sure it is not over-constraining).
3. Check the initial state. If the trace starts from a state you believe unreachable (inductive
   CEX), add the invariant as a helper assertion and prove it.
4. If inputs and initial state are legal: it is an RTL bug. Extract the minimal cycle-by-cycle
   story and file it. Formal CEXs are typically 5 to 30 cycles: perfect bug reports.

## Assumption review

Assumptions are the contract with the environment. Before signoff, list every `assume` and map it
to a spec sentence or an interface-standard rule. Any assumption without a spec source is a risk:
you have proven correctness for a world that may not exist. The complementary check: each
assumption on this block should be an *assertion* proven (or simulated) on the neighboring block
that drives those inputs. This "assume-guarantee" pairing is how formal composes across a system.

## What "formal signoff" means for a block

- All planned properties (from the vPlan, same plan as simulation) proven; bounded proofs have
  documented depth justification.
- All covers reachable; no vacuous proofs.
- Assumption list reviewed against the spec and against neighboring blocks' assertions.
- Formal checker coverage reported; unobserved logic explained (datapath left to simulation).
- Abstractions documented and their soundness argued (an abstraction that removes behavior can hide
  bugs; over-approximating abstractions, which add behavior, are safe if the proof still passes).
- Regression: properties rerun on every RTL change, with bounded proofs as fast CI gates.

## Workflow on a project

```
RTL first compile ──► autochecks + X-prop + lint-like formal (hours, no properties)
                 ──► interface protocol VIP bound as assumptions/assertions (day 1)
                 ──► covers for key scenarios; fix reset/assumptions until reachable
                 ──► local control properties from the spec (week 1)
                 ──► end-to-end via symbolic tracking (week 2+)
                 ──► convergence work; abstractions documented
                 ──► CI: bounded rerun per commit; full proofs nightly
                 ──► UNR for coverage closure late in the project
                 ──► signoff review
```

Formal engineers and simulation engineers share the plan and the property files; the block's
scoreboard covers what formal abstracted away.

## Interview angle

- "A property is inconclusive. What do you do?" Helpers, abstraction, decomposition, case split,
  in that order, with examples.
- "How do you know your formal environment is not over-constrained?" Covers; assumption review;
  assume-guarantee with neighbors.
- "What blocks would you *not* use formal on?"
- "Describe a formal signoff."

## Mentor's notes

- Keep a running list of assumptions in the property file header with the spec reference next to
  each. It is the first thing a reviewer (or an auditor) asks for.
- When formal finds nothing after the assumptions settle, run a mutation (flip a condition in the
  RTL) and confirm a property fails. Formal has vacuity too; the mutation habit from chapter 0
  applies.
