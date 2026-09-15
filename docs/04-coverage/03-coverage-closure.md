# 4.3 Coverage Closure

## From plan to model

A verification plan (vPlan, test plan) is a hierarchical list of features, each with:

- a reference to the spec (section, requirement ID),
- the checks that verify it (assertions, scoreboard checks),
- the coverage items that measure it (covergroup bins, cover properties, code coverage of a block),
- the tests/sequences intended to hit it,
- a priority and an owner.

The coverage model is the executable projection of the plan. Building it is a *design* exercise:

1. **List features** from the spec's table of contents, register map, interface list, and
   configuration parameters. Add "negative" features: error responses, illegal inputs, reset
   during activity.
2. **For each feature, list the interesting values and events.** Boundaries (0, 1, max-1, max),
   enable/disable, each enum value, each state transition.
3. **List the crosses that matter.** Not all pairs; the ones where the spec says "when A and B."
   Config x traffic type. State x input. Burst length x alignment.
4. **Decide the sampling point** for each: cycle (pins), transaction (monitor), end-of-test
   (configuration).
5. **Assign `at_least`** for corners that need repetition.
6. **Write it**, one covergroup per logical area, with `option.comment` back-references.
7. **Review it** with the designer. They will say "that combination cannot happen" (ignore bin, with
   a reason) or "you forgot the case where..." (new bin, and probably a new assertion).

## Coverage-driven stimulus

Random stimulus lands where the constraints send it. Closing coverage is mostly *constraint
engineering*:

- **Bias distributions** toward corners: `dist {0 :/ 5, [1:MAX-1] :/ 90, MAX :/ 5}`.
- **Phase the test**: fill-heavy, then drain-heavy, then balanced (chapter 2's FIFO testbench does
  this with plain loops; in UVM, three sequences).
- **Add knobs**: a `mode` field with constraints per mode; the test picks or randomizes the mode.
- **Directed-random**: constrain everything except the corner, randomize the rest. A test that
  forces `count == DEPTH-1` and then randomizes rd/wr for 100 cycles will hit the simultaneous
  corners many times.
- **Coverage-reactive** (rare): read `cg.get_coverage()` during the run and switch modes. Usually
  simpler to add a directed sequence.

## Merging and regression

Each simulation writes a coverage database (UCDB for Questa, VDB for VCS, UCD/ICC for Xcelium).
The regression merges them (`vcover merge`, `urg`, `imc -merge`). The merged view is what closure is
judged on: no single test needs 100%.

Merging rules:

- Merge only *passing* tests. A failing test may have stopped early or run with a broken checker;
  its coverage is not evidence.
- Merge across seeds and across configurations, but keep per-configuration views for
  parameter-dependent features.
- Keep coverage databases with the RTL/testbench version. Coverage from last week's RTL is not
  coverage of this week's.

## Analyzing holes

For each unhit bin, decide:

| Cause | Action |
|---|---|
| Stimulus never generates it | Bias constraints or write a directed sequence |
| Stimulus generates it but the checker/sampling window misses it | Fix the monitor/sampling point (this is a testbench bug) |
| Unreachable by design (e.g., count > DEPTH) | `ignore_bins` with a comment, or a waiver in the plan; ideally proven unreachable by formal |
| Reachable only through a path the spec forbids | `illegal_bins` and an assertion; confirm with the designer |
| Requires a configuration you are not testing | Add the configuration to the regression or document the exclusion |

Formal tools can prove code-coverage items unreachable ("UNR" analysis), which turns hundreds of
waivers into a machine-generated exclusion file. Use it.

## Ranking and trimming

Once coverage is closed, tools can rank tests by unique contribution (`vcover ranktest`, `urg
-grade`). Tests contributing nothing unique are candidates for removal from the nightly run (keep
them in the weekly). This keeps regression time bounded as the suite grows.

## Metrics that go with coverage

Coverage percentage alone is gameable. Track together:

- Functional coverage % (per feature area, weighted by priority).
- Code coverage % with waiver count and review status.
- Assertion count and non-vacuous pass rate; cover property hit rate.
- Bug discovery rate over time (should decay toward zero as coverage closes; if coverage is 95% and
  bugs are still being found weekly, the plan is incomplete).
- Regression pass rate and seeds run.
- Open bugs by severity.

Signoff (chapter 9) is a review of all of these against exit criteria agreed at the start.

## Common closure mistakes

- Sampling coverage in tests with checkers disabled ("coverage runs"). Every coverage sample must
  come from a checked simulation.
- Sampling every cycle so idle bins dominate the percentage. Use `iff (valid)`.
- Crossing large auto-binned coverpoints; the cross never closes and gets waived wholesale.
- Waiving holes to hit a date without a designer's signature on the waiver.
- Closing coverage on one configuration and calling the block done.

## Interview angle

- "Coverage is at 85%. What do you do?" Analyze holes by cause; constraint changes; directed
  sequences; waivers with justification; formal UNR; talk to the designer.
- "How do you avoid coverage from broken runs polluting the merge?" Merge passing tests only.
- "What is test ranking?"
- "What does 'coverage closure' mean at signoff?" All plan items covered or explicitly waived with
  review, plus the accompanying metrics.

## Mentor's notes

- The most valuable coverage review I ever attended was 90 minutes with the designer walking my
  cross bins. He crossed out six as unreachable and added eleven I had missed, three of which found
  bugs that week. Do that review early.
- Track the *first time* each corner bin was hit in a regression. If a corner is only hit by one
  seed of one test, it is one constraint tweak away from silently disappearing.
