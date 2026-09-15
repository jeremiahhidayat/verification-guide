# 10.1 Question Bank

Format: **Q** question. *Probe:* what the interviewer is really checking. **A** model answer
(compressed; expand with an example).

## SystemVerilog language

**Q1. `logic` vs `bit`?** *Probe: 4-state awareness.* **A** `logic` is 4-state (0/1/X/Z, default X);
`bit` is 2-state (default 0). Use `logic` for anything touching the DUT so X is visible; `bit` for
testbench bookkeeping and randomized fields (faster, solver-friendly). Sampling a DUT output into
`bit` converts X to 0 and hides bugs.

**Q2. `==` vs `===`?** *Probe: the X gotcha.* **A** `==` returns X if either operand has X/Z, and
`if (X)` is false, so `if (a != b) $error` never fires on X. `===`/`!==` compare X and Z literally.
Testbench checks use `!==`; RTL uses `==` (`===` is not synthesizable).

**Q3. Blocking vs nonblocking, and why does it prevent races?** *Probe: scheduling model.* **A**
`=` updates immediately in the Active region; `<=` evaluates the RHS now and schedules the update in
the NBA region after all Active-region reads. So all readers in the time step see the old value
regardless of process order. Rule: any variable written in one process and read in another under
the same event must be written with `<=`; hence all DUT inputs are driven with `<=`.

**Q4. Describe the SystemVerilog scheduling regions.** **A** Preponed (SVA sampling), Active
(blocking, RHS of NBA, continuous assigns), Inactive (`#0`), NBA (nonblocking updates), Observed
(assertion evaluation), Reactive (program blocks, action blocks, clocking drives), Postponed
(`$strobe`, `$monitor`). Active/NBA can loop within a time step (delta cycles).

**Q5. What is a race condition? Example and fix.** **A** Behavior depending on undefined process
order. `x = i; @(posedge clk)` in one process and `@(posedge clk); if (x != i)` in another: the
reader may see the new or old `x`. Fix: `x <= i`. Also reset races: `rst = 0` at the posedge vs the
DUT's `always_ff` reading `rst`; fix with `rst <= 0` and/or release on the negedge.

**Q6. Why release reset on the negative edge?** **A** No design process is sensitive to negedge,
so nothing races; and in timing simulations the deassertion is outside the setup/hold window.

**Q7. Packed vs unpacked arrays.** **A** Packed: contiguous bits, one vector, arithmetic and slicing
allowed, dimensions before the name. Unpacked: collection of elements, dimensions after the name,
any element type, `foreach`, synthesizes to RAM.

**Q8. Dynamic array vs queue vs associative array; when?** **A** Dynamic: runtime-sized, stable
after allocation (payloads). Queue: ordered, O(1) push/pop both ends (FIFO models, expected lists).
Associative: sparse keyed lookup (memories, ID-to-transaction maps).

**Q9. `automatic` vs `static` routines.** **A** Module tasks/functions are static by default: one
copy of locals shared by all concurrent calls, initializers run once. `automatic` gives per-call
storage; required for re-entrant forked calls and `ref` arguments. Class methods are automatic by
default.

**Q10. What does `$cast` do?** **A** Runtime checked conversion: downcast a base handle to a
derived handle (fails and returns 0 if the object is not that type); also validated int-to-enum.

**Q11. Width rule example.** **A** `logic [7:0] a, b; logic [7:0] s = (a+b)>>1;` computes `a+b` in
8 bits (context = max of operands and LHS) and loses the carry. Fix: `({1'b0,a}+b)>>1` or a 9-bit
temporary.

**Q12. Signed/unsigned pitfall.** **A** Mixed signedness makes the expression unsigned:
`signed -1 < unsigned 1` is false. Part-selects are always unsigned. Cast with `signed'()`.

**Q13. Interface, modport, virtual interface, clocking block.** **A** Interface: bundle of
signals plus tasks/assertions. Modport: directional view. Virtual interface: class handle to an
interface instance (parameters are part of the type). Clocking block: declares sampling/driving
skew relative to a clock; reads see pre-edge values, drives land after the DUT evaluates: race-free
by construction.

**Q14. Program block?** **A** Container executing in the Reactive region, ends sim when its
initials finish; designed for race-free testbenches; largely superseded by clocking blocks and UVM
conventions.

**Q15. `bind`?** **A** Instantiate a module/interface inside another scope without editing it; how
assertions and monitors are attached to RTL. `bind fifo fifo_sva u_sva (.*);`

**Q16. `$urandom` vs `$random`.** **A** `$urandom` is unsigned, thread-stable (per-thread seeding
from hierarchy), better distribution, has `$urandom_range`. `$random` is legacy, signed, global
seed, not stable. Never use `$random`.

**Q17. Implicit net declaration gotcha.** **A** An undeclared identifier in a port connection
becomes a 1-bit wire, silently truncating. Use `` `default_nettype none ``.

**Q18. `fork/join` variants; danger of `disable fork`.** **A** `join` waits all; `join_any` waits
one; `join_none` waits none. `disable fork` kills all children of the process, including unrelated
ones; wrap in an outer `fork ... join` to scope it. Loop variables captured by reference: copy to an
`automatic` local.

**Q19. Event vs mailbox vs semaphore.** **A** Event: signal only, can be missed (use
`.triggered`). Mailbox: typed FIFO of handles, remembers, blocking get/put. Semaphore: keys for
mutual exclusion.

**Q20. What is a delta cycle?** **A** A zero-time iteration of Active/NBA caused by an update
waking a process; multiple values at one timestamp.

## SVA

**Q21. Immediate vs concurrent assertion.** **A** Immediate: procedural, zero-time Boolean, like an
`if`. Concurrent: clocked, samples in Preponed, temporal, lives outside procedural code; the main
tool.

**Q22. When does a concurrent assertion sample and why does it matter?** **A** Preponed: values
just before the clock edge, same as the DUT's flops see; no races with the testbench; action blocks
must use `$sampled`; the clock itself is always 0 inside the property.

**Q23. `|->` vs `|=>`.** **A** Overlapping (consequent starts same cycle) vs non-overlapping
(next cycle; `|-> ##1`).

**Q24. `[*n]`, `[->n]`, `[=n]`.** **A** Consecutive repetition; go-to (nth occurrence, sequence
ends on it); non-consecutive (n occurrences, may end later before the next).

**Q25. Write "ack within 1 to 4 cycles after req; req held until ack."** **A**
`req |-> ##[1:4] ack` and `req && !ack |=> req` (or `$rose(req) |-> req[*1:$] ##0 ack` for the
combined form).

**Q26. What is a vacuous pass and how do you detect it?** **A** Antecedent never true, so nothing
checked. Detect with the tool's vacuity report, `cover property` on the antecedent, and mutation.

**Q27. `disable iff` semantics and the reset-release corner.** **A** Asynchronous, uses the
unsampled value, disables an attempt if true at any time during it. Reset released with `<=` on the
posedge leaves the starting attempt enabled with `$past` from reset. Fix: release on negedge,
`disable iff ($sampled(rst))`, or put `!rst` in the antecedent.

**Q28. Why pass everything into a function used in an assertion as arguments?** **A** Module-scope
variables read inside the function are unsampled (post-NBA); arguments come from the sampled
world. Mixing them compares different cycles.

**Q29. `throughout` vs `until`.** **A** `b throughout s`: Boolean holds for the entire sequence.
`p until q`: p holds each cycle until q first holds; q as a property like `en[->N]` is immediately
true, so `until` can check nothing where `throughout` checks the window.

**Q30. Local variables in properties?** **A** Per-attempt storage assigned in sequence match
items `(expr, v = x)`; carries the trigger value to the check without `$past`; formal-friendly.

**Q31. Why avoid `##[1:$]` in simulation?** **A** Never fails if the consequent never occurs; many
attempts in flight; matches the first occurrence which may be the wrong one. Bound it.

**Q32. `assume` and `cover`.** **A** `assume`: like assert in sim, constrains inputs in formal.
`cover`: counts sequence completions; reachability in formal; scenario coverage in sim.

## Coverage

**Q33. Code vs functional coverage; can you have 100% of one and be unverified?** **A** Tool-derived
vs plan-derived. 100% code coverage with an unimplemented feature; 100% functional coverage with a
shallow plan or disabled checkers. Need both, plus assertion coverage and checks-on discipline.

**Q34. Covergroup anatomy.** **A** Sampling event or `sample()`; coverpoints with explicit bins
(`{}`, `[]`, ranges, transitions, `ignore_bins`, `illegal_bins`, `wildcard`); crosses with `binsof`;
options (`per_instance`, `at_least`, `auto_bin_max`, `weight`).

**Q35. `ignore_bins` vs `illegal_bins`.** **A** Excluded from the space vs an error when hit
(coverage acting as a checker).

**Q36. How do you sample transaction coverage in UVM?** **A** `uvm_subscriber` connected to the
monitor's analysis port; `cg.sample()` in `write()`.

**Q37. Coverage is 85%; what next?** **A** Classify holes: unreachable (waive with reason, ideally
formal UNR), stimulus cannot reach (bias constraints, directed sequence), sampling bug (fix the
testbench), wrong config (add it). Review with the designer.

**Q38. What is cross coverage and why keep bins small?** **A** Combinations of coverpoint bins,
where bugs live; a cross of two 64-bin auto coverpoints is 4096 bins that never closes.

## Constrained-random

**Q39. `rand` vs `randc`.** **A** Random with repeats vs cyclic permutation without repeats until
exhausted; `randc` is per-object and should be small.

**Q40. Why is my `error -> len < 4` rarely producing errors?** **A** Solver is uniform over
solutions: 4 solutions with error vs 256 without. Fix with `solve error before len` or a `dist` on
`error`.

**Q41. `:=` vs `:/` in `dist`.** **A** Weight per value vs weight split across the range.

**Q42. What if you ignore `randomize()`'s return value?** **A** On failure the object is unchanged
and you re-drive stale data forever. Always check.

**Q43. In-line constraints, `constraint_mode`, `rand_mode`, `soft`.** **A** `with {}` adds for one
call; `constraint_mode(0)` disables a named block; `rand_mode(0)` freezes a variable; `soft`
constraints yield to hard/later ones (defaults a test can override without names).

**Q44. How do you reproduce a random failure?** **A** Log and pass the seed (`-sv_seed`); random
stability via `$urandom`/`randomize()` and stable object creation order; never `$random`.

**Q45. Constrain an array: unique elements, sum < N, size in [2:6].** **A**
`a.size() inside {[2:6]}; unique {a}; a.sum() with (int'(item)) < N;`

**Q46. Solver returns 0: debug steps.** **A** Read the conflict report; check state variables used
in constraints; widths (`bit [3:0] == 16`); array sizes vs indexed constraints; leftover
`rand_mode`/`constraint_mode`; bisect blocks.

## OOP and layered testbench

**Q47. Why `virtual` methods everywhere?** **A** Dispatch on the object's type through a base
handle: tests substitute derived components (or the factory does) without editing environments.

**Q48. Shallow vs deep copy.** **A** `new obj` copies fields; nested handles still shared. Deep copy
clones nested objects. UVM `clone()`/`do_copy`.

**Q49. What is an abstract class?** **A** `virtual class` with `pure virtual` methods; a contract;
cannot be instantiated.

**Q50. Describe the layered testbench and each component's responsibility.** **A** Transaction
(data), sequence/generator (what), driver (how, pins), monitor (observe, passive), scoreboard
(check, model), coverage, environment (wiring), test (config + scenario). Checking at transaction
level; monitor does not trust the driver.

**Q51. Why should monitors feed the scoreboard rather than the driver?** **A** Independence
(observe what the DUT saw) and passive-mode reuse at higher levels.

**Q52. Two agents need different widths of the same parameterized interface: options?** **A**
Package constants for defaults; parameterized agent classes (`*_param_utils`); widest-common
interface; abstract BFM wrapper.

**Q53. Constructor injection vs external initialization.** **A** Injection: valid on
construction, compile-time checked. External: flexible, runtime-checked; UVM's build/connect model.

## UVM

**Q54. `uvm_object` vs `uvm_component`.** **A** Data vs structure; parent and hierarchical name;
phases; `new(name)` vs `new(name, parent)`; `object_utils` vs `component_utils`.

**Q55. List the phases; what goes in build vs connect; direction.** **A** build (top-down:
create, config get), connect (bottom-up: TLM, vifs), end_of_elaboration, start_of_simulation, run
(task, parallel; with 12 run-time sub-phases), extract, check, report, final. Parent must exist
before children (build); children's ports must exist before connecting (connect).

**Q56. How does `run_phase` end?** **A** Objections: when all raised objections are dropped (plus
drain time). Typically the test raises around `seq.start`. Set `+UVM_TIMEOUT`.

**Q57. Driver/sequencer handshake.** **A** Sequence: `start_item` (wait for grant), randomize,
`finish_item` (blocks until driver's `item_done`). Driver: `get_next_item`, drive, `item_done`.
Responses via `rsp`/`put` or writing into `req`.

**Q58. `uvm_config_db`: how it works; why does `get` fail?** **A** Global typed store with
hierarchical scope and wildcards; higher/later sets win. `get` fails on type mismatch (most
common), path mismatch, set after get. Debug `+UVM_CONFIG_DB_TRACE`.

**Q59. The factory: why `type_id::create` not `new`?** **A** Overrides: a test replaces the type
(or instance) created anywhere in the env without editing it; override must be set before creation
and must extend the original.

**Q60. Analysis port vs put port; imp vs export.** **A** Analysis: nonblocking broadcast `write`,
0..N listeners. Put/get: point-to-point blocking. Export forwards; imp implements. Multiple
analysis inputs on one component: `uvm_analysis_imp_decl` or analysis FIFOs.

**Q61. What is a virtual sequence/sequencer?** **A** Sequence coordinating sub-sequences on
several real sequencers via a sequencer that holds their handles; scenarios spanning interfaces.

**Q62. Active vs passive agent in UVM.** **A** `is_active` from config; passive builds only the
monitor; enables vertical reuse.

**Q63. Field macros: pros and cons.** **A** Auto copy/compare/print/pack; slow and sometimes
wrong semantics; many teams hand-write `do_*`.

**Q64. How does a UVM test fail?** **A** `uvm_error`/`uvm_fatal` counted by the report server;
base test's `report_phase` reads counts; SVA routed via `else \`uvm_error`. Never `$display`.

**Q65. What is RAL? Adapter vs predictor? Front vs back door?** **A** Register model with mirror,
named access, built-in tests. Adapter: reg op to/from bus item. Predictor: updates mirror from
monitored bus traffic. Front door: real bus, takes time; back door: hierarchical poke, zero time.

**Q66. Reset in the middle of a UVM test?** **A** Phase jumping with run-time phases, or a
reset-aware driver plus sequences in `fork/join_any` with the reset event; decide early.

**Q67. Vertical reuse requirements on a block env.** **A** `is_active` from config; monitor-fed
scoreboard; config-driven vifs; relative paths; sequences startable from above.

**Q68. Name three UVM anti-patterns.** **A** Scoreboard on the driver; checking in sequences;
`new()` for factory types; `$display`; hierarchical refs from classes; objections everywhere.

## Formal

**Q69. Simulation vs formal.** **A** Sampled vs exhaustive; stimulus vs assumptions; coverage vs
proof/bound.

**Q70. Bounded vs full proof.** **A** No CEX within N cycles vs proven for all time (inductive
invariant found).

**Q71. Over-constraint: cause and detection.** **A** Assumptions too strong; covers become
unreachable; vacuous proofs. Review assumptions against spec; assume-guarantee with neighbors.

**Q72. How would you prove FIFO data integrity formally?** **A** Symbolic tracked write: free
constant data, free start, remember pointer, assert the read at that pointer returns the data;
helper invariants (`count == wr_ptr - rd_ptr`, `count <= DEPTH`).

**Q73. Inconclusive property: what do you do?** **A** Helper assertions, abstraction (memories,
counters, width), decomposition, case splitting, cut points, engine choice.

**Q74. Safety vs liveness.** **A** Bad never happens (finite CEX) vs good eventually happens
(infinite CEX, fairness); bound liveness in practice.

**Q75. Formal apps you know.** **A** FPV, connectivity, register, X-prop, deadlock, UNR, SEC vs
LEC, CDC, security, autochecks.

## Methodology and process

**Q76. How do you write a verification plan?** **A** Feature extraction from all specs; bug
hypotheses per feature; method and level per feature; coverage linkage; priorities; reviews.

**Q77. How do you know you are done?** **A** Exit criteria: coverage, bugs, assertions, formal,
regression stability, GLS subset, static checks, reviews, documented residual risk.

**Q78. Describe your regression flow and how you triage.** **A** Test lists, seeds, farm, log
parsing, coverage merge of passing runs, bucketing by signature, root cause, regression test per
bug.

**Q79. A test fails 1 in 100 seeds.** **A** Reproduce with the seed; suspect races/initialization/
timeouts; never waive without root cause.

**Q80. Block vs subsystem vs SoC verification.** **A** Active to passive; software as stimulus;
integration focus; speed; reuse.

**Q81. What does GLS catch that RTL does not?** **A** Un-reset flops (X-optimism in RTL), synthesis
pragmas, clock gating, DFT, timing on mis-constrained paths, power intent.

**Q82. How do you verify CDC?** **A** Structural tool, protocol assertions, metastability
injection; RTL sim alone cannot.

**Q83. Low-power verification?** **A** UPF, power-aware sim: isolation, retention, power FSM
sequences, no X across domains.

**Q84. Tell me about a bug you found.** *Probe: depth, method, communication.* **A** Structure:
symptom, hypothesis, evidence (cycle, signal), root cause (spec sentence), fix, and what check you
added so it cannot recur. See 10.4.

**Q85. Tell me about a disagreement with a designer.** **A** Facts and spec; escalate the spec not
the person; outcome.

**Q86. How do you speed up a slow testbench?** **A** Profile; covergroup sampling; solver; field
macros; messages; dumping; compile-once; optimized builds; test ranking.

**Q87. What is DPI and when did you use it?** **A** SV-C interface; C golden model in the
scoreboard; type mapping; `context`.

**Q88. What is PSS?** **A** Portable scenario description realized as UVM sequences, C tests, or
emulation drivers.

**Q89. cocotb vs UVM.** **A** Python speed of writing vs runtime; solver/coverage/reuse gaps.

**Q90. How do you review a testbench?** **A** Spec-derived checks, race freedom, `!==`, randomize
checks, monitor-fed scoreboard, covers on antecedents, logs, mutation check.

## Rapid-fire (one line each)

- Default value of `logic`? X. Of `int`? 0.
- `$clog2(16)`? 4. `$bits(logic [3:0][7:0])`? 32.
- `'1` means? All ones in the context width.
- Queue of `int` max element? `q.max()` returns a queue with one element.
- `q[$]`? Last element. `q[1:$]`? All but the first.
- `foreach (a[i, j])`? Two-dimensional iteration.
- What does `##0` do? Fuses sequences in the same cycle.
- `$past(x, 3, en)`? Value of x three *enabled* samples ago.
- `$onehot0`? Zero or one bit set.
- `option.at_least`? Hits needed for a bin to count.
- `randc bit [15:0]`? Legal but a 65536-entry permutation: slow; keep small.
- `uvm_analysis_port::write` returns? Nothing; nonblocking function.
- `phase.raise_objection` in a driver? Anti-pattern.
- `+UVM_TESTNAME`? Selects the test class via the factory.
- `set_type_override` after `create`? No effect on already-created objects.
- `disable iff` value: sampled or not? Not sampled.
- First region of a time step? Preponed.
- `#0`: good idea? No.
- `always_comb` at time 0? Executes once. `always @*`? Only on a change.
- What is `$sampled` for? Printing the value an assertion evaluated.
