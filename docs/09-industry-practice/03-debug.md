# 9.3 Debug

Debug is where most verification hours go. Doing it systematically is the difference between an
engineer who closes three bugs a day and one who closes three a week.

## The method

1. **Read the first error, not the last.** Errors cascade. The first `UVM_ERROR`, assertion
   failure, or X is the one to chase. Configure the report server to stop after the first (or first
   few) errors during debug.
2. **State the symptom precisely.** "Scoreboard mismatch at 41,230 ns on read #517: got 0x3C,
   expected 0x2B." Not "the FIFO test fails."
3. **Form a hypothesis before opening waveforms.** From the symptom and the design: "expected
   value is the *previous* entry, so a read pointer did not increment, or a write was double-counted
   by the model." Two hypotheses; each predicts something specific in the waveform.
4. **Go to the transaction log first, waveform second.** The log shows what the testbench
   believed at transaction level; the waveform shows the pins. Most debugs resolve at the log level
   ("the monitor saw a write the driver did not send: reset glitch").
5. **Bisect in time and in space.** Time: find the last cycle where model and DUT agree. Space:
   is the mismatch already present inside the DUT (internal state diverged) or only at the
   output (observation wrong)?
6. **Decide: DUT, testbench, or spec.** Prove it with the spec sentence. About a third of new
   failures are testbench bugs; call them honestly.
7. **Minimize.** Shortest seed, fewest transactions, smallest configuration that reproduces. A
   10-cycle directed reproduction is worth an hour of effort; it becomes the regression test.
8. **Write it up** (below), fix or file, add a regression test, and add the assertion that would
   have caught it earlier.

## Waveform strategy

- Dump only what you need: transaction-level recording (UVM `recording_detail`) plus the DUT
  interface signals for nightly; full-hierarchy dumps only on rerun of a failure.
- Use the simulator's *transaction* views (Questa transaction streams, Verdi transaction/FSDB
  with UVM recording, SimVision transaction browser). Seeing packets as bars above signal traces
  turns a 10,000-cycle waveform into a readable story.
- Learn the assertion debugger for your tool (3.3). An assertion failure shows the attempt
  timeline; a waveform alone does not.
- Learn to use `force`/`release` and checkpoint/restore for hypothesis testing without recompiling.
- For long runs, save a checkpoint before the failure region and rerun from it with dumping on.

## Logs that make debug fast

- Every component: one line per transaction at medium verbosity, with time, component, direction,
  and a `convert2string()` of the item. Consistent format so `grep`/`awk` can align them.
- Configuration printed at start; seed printed at start; summary at end.
- Verbosity controllable per component from the command line so a rerun can turn one component to
  DEBUG without re-flooding everything.
- Unique message IDs (`[SB_MISMATCH]`, `[DRV_TIMEOUT]`) so buckets group correctly.

## Debugging X

An X on an output after reset: trace it backward with the tool's X-source tracing (Verdi "trace X,"
Questa "cause"), or bind `!$isunknown` assertions at internal points and rerun; the earliest
failing one is nearest the source. Usual causes: un-reset flop, uninitialized memory read,
out-of-range index, `casex`, an interface signal the testbench forgot to drive, a `bit` in the
testbench that should be `logic` (it hid an X and let it propagate).

## Debugging hangs

Simulation stalls at a time and CPU stays busy: a zero-delay loop (combinational feedback through
the testbench, or a `forever` without timing control). Simulation stops advancing and CPU idles:
every process is blocked; open the process browser and look at each `initial`/`run_phase`: the
blocked `get()`, the `@(event)` that will never fire, the sequence waiting for a `ready` the
driver never asserts. Named processes and `+UVM_OBJECTION_TRACE`/`+UVM_PHASE_TRACE` are your
friends. Always have a global timeout so the regression reports a hang as a failure.

## Working with designers

The bug report template that gets bugs fixed fast:

```
Title:     FIFO drops write when read and write coincide at count==1
Severity:  P1 (data loss)
RTL:       git 3f2a1c, fifo.sv line 44
Test:      fifo_fill_drain_test, seed 88213, fails at 41,230 ns
Symptom:   read #517 returned 0x3C; expected 0x2B (SB log attached)
Spec:      uarch 3.2: "simultaneous read and write are both performed regardless of occupancy"
Analysis:  waveform at 41,210 ns: do_rd and do_wr both high, count==1; wr_ptr does not advance.
           `do_rd` gates `do_wr` via ... (line 44). Model and assertion ap_cnt_same also fire.
Repro:     make sim TEST=fifo_fill_drain_test SEED=88213 WAVES=1  (or attached 12-cycle directed test)
```

Facts, spec reference, cycle number, reproduction. No speculation about blame. Designers fix
bugs reported this way in hours; they argue with bugs reported as "your FIFO is broken."

## The post-mortem habit

For every escaped bug (found late, or in silicon), ask: which check would have caught it earlier,
and why was it not there? Add the check, and add the *category* to the plan template so the next
project starts with it. Teams that do this get measurably better each generation.

## Interview angle

- "Walk me through debugging a scoreboard mismatch." The method above, with emphasis on first
  error, hypothesis, log before waveform, DUT vs testbench decision.
- "How do you debug an X?" Backward tracing; `$isunknown` assertions; usual causes.
- "How do you debug a hang?" Process browser; timeouts; objection trace.
- "How do you write a bug report?"

## Mentor's notes

- Keep a debug journal for hard bugs: hypothesis, evidence, next step. When you are interrupted
  (you will be), you resume in one minute instead of thirty.
- The fastest debuggers I know are not faster at reading waveforms. They are faster at forming
  the right hypothesis, because they understand the design. Read the RTL.
