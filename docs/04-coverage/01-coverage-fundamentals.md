# 4.1 Coverage Fundamentals

## Why "it passed" is not enough

Recall chapter 0: verification is `for all legal inputs s, DUT(s) == SPEC(s)`. Simulation samples a
finite set of `s`. Coverage is the map of which parts of the space those samples touched. Without
it, "all tests pass" could mean "we tested one thing." With it, you can make a defensible claim:
"every feature in the plan was exercised, in these combinations, and every check stayed green."

## The three kinds

| Kind | What it measures | Who defines it | Answers |
|---|---|---|---|
| **Code coverage** | Which RTL lines, branches, conditions, expressions, FSM states/transitions, and signal toggles were exercised | The tool, automatically from the RTL | "Is there RTL we never ran?" |
| **Functional coverage** | Whether *specification-level* events, values, and combinations occurred | You, from the verification plan | "Did we exercise the features and corners the spec describes?" |
| **Assertion coverage** | How many times each assertion attempted, passed non-vacuously, and how many cover properties hit | Derived from your assertions | "Were the checks actually active?" |

They are complementary because they miss different things:

- Code coverage cannot see what is *missing* from the RTL. If the designer forgot to implement the
  "abort" feature, there is no code for it, and code coverage is 100%. Functional coverage on the
  abort feature is 0% and tells you.
- Functional coverage cannot see RTL you did not know about. A leftover debug mode or an unreachable
  default branch shows up only in code coverage.
- Neither says the *checking* was on. A functional coverage bin for "write while full" can be 100%
  hit in a test whose scoreboard was accidentally disabled. Assertion coverage (and the discipline of
  "coverage only counts from tests with checkers enabled") closes that gap.

## Code coverage in detail

Enabled at compile/run time (`vlog +cover=bcesft`, `vcs -cm line+cond+fsm+tgl+branch`, `xrun
-coverage all`). Types:

- **Statement/line**: each executable statement ran. Cheapest, least meaningful.
- **Branch**: each `if`/`else`/`case` arm taken. Missing `else` arms are bugs-in-waiting.
- **Condition/expression**: each Boolean sub-term of a condition independently affected the
  outcome (MC/DC style). Catches `if (a && b)` where `b` was never the deciding factor.
- **FSM**: each state visited, each transition taken. The tool infers the FSM from the enum/case.
- **Toggle**: each bit of each signal went 0 to 1 and 1 to 0. Finds stuck bits, unconnected ports,
  and constant-tied inputs. Noisy; usually applied to ports only.

Reading a code coverage report is a *review* activity: every uncovered item is either (a)
unreachable by design (waive it, with a written reason), (b) reachable but not stimulated (add a
test), or (c) a bug in the RTL or spec (e.g., a branch that should be reachable but is provably not,
which formal can confirm). Industry expectation: near-100% statement/branch with documented
waivers, high condition and FSM, toggle on ports.

## Functional coverage in detail

You write it. It comes from the verification plan, feature by feature:

```
Feature: FIFO flow control
  - full asserted                         -> bin
  - write attempted while full            -> bin
  - read attempted while empty            -> bin
  - simultaneous rd/wr at count = 1       -> bin
  - simultaneous rd/wr at count = DEPTH-1 -> bin
  - reset while non-empty                 -> bin
Feature: data path
  - wr_data extremes: 0, all-ones          -> bins
  - wr_data distribution: 8 ranges         -> bins
  - cross: (wr while full) x (rd same cycle)
```

Each line becomes a `coverpoint`, a `bins` entry, a `cross`, or a `cover property`. The plan and
the coverage model are the same document viewed twice; tools (Questa Verification Management, VCS
VPlanner/Verdi Planner, Xcelium vManager) link them explicitly so a plan item shows its coverage
percentage.

Two mechanisms:

- **`covergroup`** (data-oriented): sample a set of variables at an event, count values into bins,
  cross them. Best for "which values/combinations occurred."
- **`cover property`** (temporal): count how many times a sequence completed. Best for "did this
  scenario happen" (fill then drain, back-to-back bursts, reset mid-transaction).

## Assertion coverage

Every `assert property` reports attempts, passes, non-vacuous passes, failures. Every `cover
property` reports hits. Use them to detect dead assertions (zero non-vacuous passes) and to prove
scenario reachability. Some teams count each assertion as a plan item.

## Coverage-driven verification: the loop

```
  plan ──► coverage model ──► run regression ──► merge coverage ──► analyze holes
    ▲                                                                   │
    └──── refine plan / add constraints / add directed tests ◄──────────┘
```

Constrained-random stimulus (chapter 5) generates volume; coverage tells you where the volume is not
landing; you adjust constraints (bias toward the holes), add a directed test for the stubborn ones,
or write a *reactive* sequence that reads coverage at run time (rare, and often not worth the
complexity). Repeat until the plan is closed.

## What coverage is not

- Not a proof. 100% functional coverage means every *item you thought of* was hit. The bugs that
  escape are in items nobody thought of. That is why plan reviews with designers, architects, and
  software matter.
- Not a target to game. A coverpoint with `auto_bin_max = 1` is 100% after one sample. Reviewers
  should read the coverage model, not just the number.
- Not free. Covergroups cost simulation time and memory; sample only what the plan needs (Spear:
  "gather information, not data"). Instantiate per-interface, not per-transaction object.

## Interview angle

- "Code vs functional coverage?" Tool-derived vs plan-derived; what each misses; why you need
  both. Have the "abort feature not implemented" example ready.
- "You have 100% code coverage and 100% functional coverage. Are you done?" Only if the plan was
  complete and the checkers were on; discuss reviews, assertion coverage, and bug-rate trends.
- "What is a coverage hole and how do you close one?" Unhit bin; analyze reachability; adjust
  constraints, write a directed test, or waive with justification.

## Mentor's notes

- Write the coverage model *before* the stimulus. It forces you to enumerate the corners, and it
  makes you notice when the random stimulus is structurally incapable of reaching one (a 50/50
  read/write FIFO test essentially never fills a 16-deep FIFO; the bin stays at zero and tells you
  to bias the constraints).
- A coverage bin that is hit exactly once is a warning, not a success. Corners need repetition
  with varied surrounding context. Set `option.at_least` for the ones that matter.
