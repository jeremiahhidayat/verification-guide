# 9.5 Testbench Performance, Reuse, and Governance

## Performance

Regression cost scales with cycles per second. Testbenches are frequently the bottleneck, not the
RTL. Where the time goes and what to do:

| Symptom | Cause | Fix |
|---|---|---|
| Slow with few transactions | `covergroup` sampled every clock on wide crosses | Sample per transaction; smaller bins; `iff` |
| Slow randomization | Solver on big arrays / nonlinear constraints / huge `dist` | Procedural payloads; linearize; `solve before`; randomize config once |
| Slow with UVM | Field macros on hot items; `uvm_info` string formatting at high verbosity; transaction recording on | Hand-written `do_*`; guard messages; disable recording in regression |
| Memory growth | Analysis FIFOs never drained; queues never popped; objects retained in associative arrays | Drain; delete; check `num()` at end of test |
| Slow assertions | Thousands of attempts in flight (`##[1:$]`, every-cycle antecedents on wide vectors) | Bound; `first_match`; implication triggers |
| Slow from waveforms | Full dumping in regression | Transaction-level only; dump on rerun |
| Slow from the DUT model | Behavioral memory models with per-bit loops; `$readmemh` of gigabytes | Sparse associative-array memories; lazy init |
| Slow compile | Everything recompiled per test | Compile once, elaborate once (`vopt`/`-o simv`), run many tests via plusargs; incremental compile |

Profile before optimizing: every simulator has one (`vsim -profile` + `profile report`, VCS
`-simprofile`, Xcelium `-profile`). The top three items are usually obvious once measured.

Optimization levels: debug builds (`+acc`, full visibility) for reruns; optimized builds (no `+acc`
except needed scopes) for regression. The difference is often 2 to 5x.

## Reuse: VIP and agent libraries

A verification IP (VIP) is an agent plus: sequences for common scenarios (reset, config, traffic
patterns, error injection), protocol assertions, a coverage model, documentation, and examples.
Commercial VIP exists for every standard interface (AMBA, PCIe, USB, Ethernet, DDR, MIPI...) and is
usually worth buying: protocol compliance is deep, and the vendor tracks the spec revisions.
In-house VIP for proprietary interfaces follows the same packaging.

Rules that make an agent reusable:

- Configured via a config object, not parameters where avoidable; interface widths via package or
  parameters with defaults.
- Active/passive switch; driver optional.
- Monitor publishes on an analysis port; never checks beyond protocol-level assertions.
- No knowledge of the DUT: no hierarchical references, no DUT-specific constraints in the item.
- Documented: item fields, config knobs, sequences, coverage, known limitations, version.
- Versioned and released like software; consumers pin a version.

## Methodology governance

Large teams need consistency more than cleverness:

- **Coding guidelines** for testbench SV/UVM (naming, file layout, one class per file, package
  structure, message IDs, no `$display`, no `new()` for factory types). Enforce with a linter
  (many UVM-aware lint tools exist) and code review.
- **Templates and generators**: a script that creates a new agent/env/test skeleton with the
  team's conventions. Removes hours and inconsistency.
- **A methodology owner** who reviews new environments, maintains the base classes (common base
  test, common scoreboard utilities, common config), and decides tool-version upgrades.
- **Shared infrastructure**: regression launcher, result DB, coverage merge, plan tooling, one
  `Makefile`/flow per project.

## Code review for testbenches

Testbench code is reviewed like RTL. What reviewers look for:

- Checks come from the spec, not the RTL; the reference model is transaction-level.
- No races: `<=` on DUT inputs; no `#1`; no `#0`.
- `!==`/`===` in checks; `!$isunknown` assertions on outputs.
- `randomize()` return values checked; constraints commented with spec references.
- Monitors feed scoreboards; new object per transaction; scoreboard empty in `check_phase`.
- Every `A |-> B` has a cover on `A`; every plan corner has a coverage item.
- Logs are transaction-level, time-stamped, greppable; message IDs consistent.
- The mutation check was done (reviewer may ask: "which RTL change would this catch?").

## Interview angle

- "Your regression takes 12 hours. How do you speed it up?" Profile; the table above; compile
  once; optimized builds; test ranking.
- "What makes an agent reusable?"
- "How do you keep a team of 20 writing consistent testbenches?" Guidelines, templates, lint,
  reviews, a methodology owner.

## Mentor's notes

- The first time you profile a testbench, you will find one covergroup or one `uvm_info` in a hot
  loop accounting for a third of the runtime. It is always something embarrassing. Profile early.
- Write the agent README before the agent. If you cannot describe its config knobs and item
  fields in a page, the design is not done.
