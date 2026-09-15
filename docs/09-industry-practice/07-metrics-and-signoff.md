# 9.7 Metrics and Signoff

## Why metrics

"Are we done?" cannot be answered by feeling. It is answered by a set of measurements agreed
*before* the project against exit criteria, reviewed at signoff. Metrics also make trends visible:
a bug rate that is not decaying, a coverage curve that plateaued, a regression that is getting
slower, all of which are decisions waiting to be made.

## The metrics that matter

| Metric | What it tells you | Watch for |
|---|---|---|
| **Functional coverage %** (per feature area, priority-weighted) | Plan completion | Plateaus (stimulus cannot reach); 100% with low bug count (plan too shallow) |
| **Code coverage %** (line/branch/cond/FSM/toggle) with waiver count | Unexercised RTL | High waiver counts; waivers without justification |
| **Assertion metrics**: count, non-vacuous pass rate, cover hits | Are checks active? | Assertions with zero non-vacuous passes |
| **Bug discovery rate** (per week, by severity) | Health of the process | Zero early (no checking); non-decaying late (unstable RTL or plan) |
| **Open bugs by severity and age** | Risk | Old P1s |
| **Regression pass rate and runtime** | Stability, cost | Flaky tests; runtime growth |
| **Seeds per test / total cycles** | Stimulus volume | Coverage saturation vs seed count |
| **Plan completion** (rows done / total, weighted) | Progress | Rows without tests or coverage links |
| **Formal**: properties proven/bounded/failed/inconclusive; assumption count | Formal completeness | Bounded proofs with unjustified depth; many assumptions |
| **Review completion**: plan, testbench, coverage reviews held and actioned | Process | Skipped reviews |
| **Escapes** (bugs found at a later level or in silicon) with root cause | Effectiveness of each level | Repeat categories |

Dashboards combine these per block and per project; the weekly verification meeting reads the
dashboard, not status emails.

## Reading the bug curve

```
bugs/week
   ^         ___
   |        /   \
   |       /     \____
   |      /           \___
   |_____/                \______________
   +----------------------------------------> time
   bring-up  feature-complete  closure   signoff
```

Bring-up finds testbench bugs and easy RTL bugs; the peak is when random stimulus and coverage
drive into corners; decay follows closure. Decisions: if the curve is still high near the signoff
date, signoff moves, not the criteria. If the curve is flat at zero from the start, the checking is
missing; look at assertion and scoreboard activity before celebrating.

## Exit criteria (a typical block-level set)

- 100% of P1 and P2 plan rows covered (functional coverage bins hit at `at_least`); P3 covered or
  waived with designer signature.
- Code coverage: 100% line/branch with reviewed waivers; condition and FSM per team threshold;
  toggle on ports.
- Zero open P1/P2 bugs; P3s dispositioned.
- All P1 assertions have non-vacuous passes; all covers hit.
- Formal: all planned properties proven or bounded with documented depth; covers reachable;
  assumptions reviewed.
- Regression: N consecutive nightly runs at 100% pass with random seeds; weekly soak clean.
- GLS: reset/boot/DFT/low-power subset passing on the final netlist.
- Lint, CDC, RDC, UPF static checks clean or waived.
- Reviews: plan, testbench, coverage, formal assumptions all held; actions closed.
- Documentation: environment README, known limitations, list of features not verified at this
  level and where they are covered.

## The signoff review

A meeting with verification, design, architecture, and the program lead. The verification lead
presents the dashboard against the exit criteria, walks the waivers, walks the open bugs, walks
the escapes from earlier levels (with root causes), and states what is *not* verified. The
output is a signed record. If a criterion is not met, either the schedule moves or the criterion is
explicitly waived by the people who own the risk, in writing. "We'll catch it in silicon" is a
decision someone must sign.

## Metrics anti-patterns

- Coverage as a target rather than a measurement: engineers add `ignore_bins` to reach the number.
- Counting tests rather than coverage or bugs.
- Merging coverage from failing or checker-disabled runs.
- Treating 100% code coverage as done.
- Reporting averages that hide a zero (a 95% functional coverage average with one P1 feature at
  0%).

## Interview angle

- "How do you know when verification is done?" Exit criteria list; metrics; reviews; explicit
  residual risk.
- "What metrics did you track and what did they tell you?" Have a bug-curve story.
- "Tell me about an escape and what you changed." Post-mortem to plan-template change.

## Mentor's notes

- Publish the exit criteria on day one and never quietly change them. Loudly changing them, with
  signatures, is fine; that is what management is for.
- The signoff statement I most respect is "these three features are not verified at this level;
  here is where they are, and here is the risk if that is wrong." Honesty about gaps is the
  product.
