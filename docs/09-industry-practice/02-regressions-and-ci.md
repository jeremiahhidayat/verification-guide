# 9.2 Regressions and Continuous Integration

## What a regression is

A regression is the automated, repeatable execution of a test suite against a design revision,
producing a pass/fail verdict per test, merged coverage, and a comparison against the previous run.
It is the heartbeat of a verification project: the design changes daily; the regression tells you
what broke.

## Anatomy

```
  test list (name, args, seeds, timeout, tags)
        │
        ▼
  job launcher ──► compute farm (LSF/SGE/Slurm/Kubernetes) ──► N x simv +seed=...
        │                                                          │
        ▼                                                          ▼
  result database  ◄──── parse logs (PASS/FAIL, UVM_ERROR count, assertion summary, runtime)
        │
        ├──► coverage merge (passing runs only) ──► plan annotation ──► dashboard
        ├──► failure bucketing (by first error signature) ──► triage queue
        └──► trend: pass rate, bug rate, coverage delta, runtime
```

Every company has its own launcher (many now use open frameworks like `cocotb`'s runners, or
vendor managers: Questa VRM, VCS/Verdi vManager-like flows, Xcelium vManager). The concepts are
universal.

## Test lists and seeds

- Each test entry: test name, plusargs, number of seeds, timeout, priority/tag (smoke, nightly,
  weekly), owner.
- Seeds are random per run and *recorded*. A failing test's reproduction command is
  `<exact compile> && <exact run> -sv_seed <N>`; the result database stores it.
- Fixed seeds for a small **smoke** set (deterministic gate: "does the environment still build and
  run the basics?"). Random seeds for **nightly** (breadth). Many seeds, long runs for **weekly**
  (depth, soak).
- Random stability matters here: if adding a component reshuffles every seed's behavior, last
  night's failing seed will not fail tonight. UVM's name-based seeding helps; deterministic object
  creation order helps more.

## CI gating

Modern flows treat RTL and testbench as software:

- **Pre-commit / pull-request gate**: lint, compile, smoke regression (minutes). A PR that fails
  does not merge.
- **Post-merge**: nightly regression with coverage; results posted to the PR/commit.
- **Formal bounded proofs** as PR gates for protocol properties (fast, no testbench).
- **Weekly**: full seeds, gate-level subset, emulation regressions.

A green gate is not "verified"; it is "not obviously broken." Keep the gate fast (under 15 minutes)
or people bypass it.

## Failure triage

The regression produces failures faster than humans can read logs. The process:

1. **Bucket** by signature: first `UVM_ERROR`/`$error` message with numbers stripped, plus test
   name. One bucket = probably one bug.
2. **Prioritize** buckets by count and by test priority.
3. **Assign** each bucket to an owner (the testbench owner first: they decide RTL vs testbench).
4. **Root-cause** (chapter 9.3). Attach the bug ID to the bucket; future occurrences auto-link.
5. **Close** when the fix is in and the test passes on the seed that failed *and* on fresh seeds.

Never mark a failure "flaky" without a root cause. A flaky test is a race condition (1.3), an
uninitialized variable, a timeout too tight, or a real intermittent bug. All four need fixing.

## Reproducibility checklist

A regression failure is only actionable if it reproduces. Ensure:

- Exact tool version and options are logged (a `-version` line in every log).
- RTL and testbench git hashes are logged.
- Seed logged; all randomness goes through `$urandom`/`randomize()` (no `$random`, no time-based seeds).
- No dependence on filesystem state, environment variables, or wall-clock time.
- Waveform dumping can be re-enabled on rerun without changing behavior (dumping should never
  change simulation semantics; if it does, you have a race).

## Test ranking and suite maintenance

As the suite grows, runtime grows. Periodically rank tests by unique coverage contribution and by
bug-finding history; demote zero-contribution tests to weekly; delete tests made redundant by
better ones. Keep the *bug regression* tests (one directed test per escaped bug) forever; they are
cheap and they are the memory of the project.

## Compute and cost

Simulation licenses and farm hours are real money. Practices: run short smoke first and cancel
long runs on smoke failure; run `-O`/optimized builds for regression and debug builds only for
reruns; cap seeds per test by coverage saturation; measure cycles-per-second per test and fix
the slow ones (9.5).

## Interview angle

- "Describe your regression flow." Test list, seeds, farm, parsing, coverage merge, triage,
  dashboards.
- "A test passes 99 seeds and fails 1. What do you do?" Reproduce with that seed; suspect races and
  initialization; never waive.
- "What is a smoke test?" Fast deterministic gate.
- "How do you keep regression time under control?" Ranking, tagging, saturation, performance work.

## Mentor's notes

- Automate the reproduction command. A failing test's dashboard entry should have a
  copy-paste line that reproduces it with waveforms on. Every minute an engineer spends
  reconstructing a command is a minute stolen from debug.
- Track "time from failure to root cause" as a metric. When it climbs, the testbench's debug
  infrastructure (logs, transaction recording) needs investment.
