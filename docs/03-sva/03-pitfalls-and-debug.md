# 3.3 SVA Pitfalls and Debugging

Every item here comes from a real failure. The pattern is always the same: the property "reads
right" in English but the sampling model or the temporal semantics differ from the English.

## P1. The reset-release edge and `disable iff`

Setup: `disable iff (rst)`, reset released with `rst <= 0` at a posedge.

The attempt that starts on the release edge samples `rst == 1` in Preponed, but `disable iff` uses
the *unsampled* value, and the NBA region sets `rst` to 0 before the attempt's first evaluation
completes. The LRM: "If the disable condition is true at any time between the start of the attempt
in the Observed region, inclusive, and the end of the evaluation attempt, inclusive, then the overall
evaluation results in disabled." At the Observed region of the release edge, `rst` is already 0. The
attempt is *not* disabled and evaluates `$past(in)` from during reset.

Symptom: a failure exactly one cycle after reset release, only in some testbenches.

Fixes (any one):
1. Release reset on `negedge clk` (the testbench convention; nothing else is sampled there).
2. `disable iff ($sampled(rst))`: forces the sampled value.
3. Move reset into the antecedent: `!rst && en |=> out == $past(in)`. Antecedent terms *are* sampled.
4. Delay the consequent an extra cycle (`1 |-> ##2 ...`): masks the issue, not recommended.

## P2. `$past` at time 0 and across reset

`out == $past(in)` on the first cycle after reset compares against the input during reset. If your
stimulus happened to hold `in` at the reset value it passes by coincidence; change the stimulus and it
fails. Stitt's `register_no_en_tb_bad` sets `in <= 1` during reset to expose exactly this.

Fix: give the property a trigger so the first post-reset cycle is skipped:
`assert property (@(posedge clk) disable iff (rst) 1 |=> out == $past(in));` or better,
`!rst |=> out == $past(in)` (the antecedent is sampled in the cycle before the check).

For pipelines with latency L: `$past(data_in, L, en)` after reset returns values from during reset
for the first L enabled cycles. Either check "output is the reset value until L enables"
(`$fell(rst) |-> data_out == '0 throughout en[->L]`) and trigger the data check with `en[->L]`, or use a
counter/local-variable style. Stitt's `delay_tb3..5` walks through all of these.

## P3. Functions that read module-scope variables

```systemverilog
function automatic logic is_out_correct(logic [7:0] d[8]);
  ...
  return sum == data_out;          // data_out is NOT an argument: read from module scope, unsampled
endfunction
assert property (@(posedge clk) en[->L] |=> is_out_correct($past(data_in, L, en)));   // WRONG
```

The `$past(data_in...)` argument is sampled; `data_out` inside the function is the *current* value,
post-NBA, which is one cycle newer than the sampled world the assertion lives in. Result: mismatches
that make no sense in the waveform.

Rule: **everything a property uses must enter through sampled expressions**. Pass `data_out` as an
argument (`is_out_correct($past(...), data_out)`; the `data_out` in the assertion is sampled). The
same applies to class handles and queues referenced from properties: `model_q.size()` in a property
is evaluated at sampling time, which is why the FIFO model in chapter 2 works (the model updates in
Active, the property sampled in Preponed before that).

## P4. Unbounded delay `##[1:$]` never fails

`req |-> ##[1:$] ack`: if `ack` never comes, the attempt stays pending until the end of simulation
and is reported (at best) as "not completed," not as a failure. In simulation, always bound
liveness: `##[1:MAX]`. In formal, unbounded liveness is a real proof obligation (chapter 8), but you
still usually bound it for practicality.

Related: multiple matches. `(wr_en, d = wr_data) |-> ##[1:$] (rd_en ##1 rd_data == d)` matches the
*first* read whose data equals `d`, which could be a later write with the same value. The tutorial's
`fifo_tb2_bad` has this bug; `fifo_tb3` fixes it with tags and `first_match`, and `fifo_tb4` replaces
the whole thing with a queue. Lesson: the more `##[1:$]` you have, the more likely a queue model is
the right tool.

## P5. Vacuous assertions

An assertion whose antecedent never fires is green forever. Detect with:
- The simulator's vacuity report (Questa `vsim -assertdebug` + assertion browser; VCS
  `-assert vacuous`; Xcelium `-assert_count_vacuous`... check your tool).
- A `cover property` on the antecedent sequence, reviewed in the coverage report.
- The mutation habit: break the DUT and confirm the assertion fails.

Also watch for antecedents that can never be true because of a typo (`state == IDEL`), a width
mismatch (`cnt == 16` on a 4-bit `cnt`), or an X in a compared signal (X comparisons are neither
true nor false; the property does not fail).

## P6. Every-cycle attempts and `throughout`

`assert property (@(posedge clk) data_out == '0 throughout en[->N]);` without an implication starts a
new attempt *every cycle*, each of which requires `data_out == 0` for the next N enables. It fails
as soon as data flows. You wanted it to run once, after reset: `$fell(rst) |-> ... throughout ...`.
Any property without an antecedent is being checked from every cycle; ask yourself whether that is
what you mean.

## P7. `until` vs `throughout`

`a until b` (property): a holds every cycle until b becomes true; b need not ever happen (weak) or
must (`s_until`). `a throughout s` (sequence): a holds at every cycle *of the sequence s*. Stitt
shows `$fell(rst) |-> data_out == '0 until en[->N]` checks nothing (the property `en[->N]` is
"there exists a window starting now with N enables" and is immediately true), whereas
`throughout en[->N]` checks the entire window. Prefer `throughout` with a sequence for windows.

## P8. Using `posedge` of a data signal as the clock

`@(posedge done)`: fine if `done` is a clean registered pulse; wrong if `done` is combinational and
can glitch (the property clocks on the glitch). Clock properties on the real clock and detect the
event with `$rose(done)`.

## P9. Overlapping attempts and local variables with `##[1:$]`

A property with a local variable and an unbounded consequent may keep many attempts in flight, each
with its own copy. Simulation slows down, and the "which attempt failed" question becomes hard.
Bound the delay and, for genuinely queue-like behavior, use a queue.

## P10. Assertions inside classes

Concurrent assertions cannot be declared in classes. Options: put them in the interface (protocol
rules), in a bound checker module, or in the top. Classes may use immediate assertions in tasks
(e.g., in a monitor's `run_phase`, `assert (vif.tready !== 1'bx)`).

## Debugging techniques

1. **Read the failure message with `$sampled`.** If your message prints unsampled values, fix that
   first; you may be chasing a phantom.
2. **Turn on the assertion debugger.** Questa: `vsim -assertdebug`, then the Assertions window
   shows each attempt's start time, current cycle, and which term failed. VCS: `-assert
   enable_diag` / Verdi's assertion browser. Xcelium: SimVision assertion browser. These show you the
   *attempt timeline*, which the waveform alone does not.
3. **Add a pass action temporarily.** `assert property (p) $info("passed: start=%0t", $realtime);`
   Stitt uses this to confirm the window a `throughout` property actually checked (the report shows
   "Time" and "Started"). Remove it after; pass messages drown logs.
4. **Bisect the property.** Replace the consequent with `1` (does the antecedent fire when you
   expect?). Then replace the antecedent with `1` (does the consequent hold unconditionally where it
   should?). Then reassemble.
5. **Check the clock and reset of the property**, not just the signals. Wrong clock domain, or
   `disable iff` on the wrong polarity, explains many "impossible" failures.
6. **Write the timing diagram** with the attempt start marked and each `##` step labeled. Compare
   against the waveform cursor by cursor.
7. **Suspect the testbench.** In a new environment, half of assertion failures are testbench
   driving issues (blocking assignment, reset timing, wrong latency constant).

## Performance notes

Assertions cost simulation time proportional to attempts in flight times property complexity. A
handful of properties is free. A thousand properties with `##[1:$]` on a 10M-cycle test is not.
Bound delays, use `first_match`, avoid every-cycle attempts on wide vectors, and profile
(`vsim -assertprofile`, VCS `-assert profile`).

## Interview angle

- "Your assertion fails one cycle after reset. What do you check?" P1 and P2, in that order.
- "How do you know an assertion is not vacuous?" P5.
- "Why should a function called from an assertion take all its inputs as arguments?" P3.
- "What is wrong with `##[1:$]` in simulation?" P4.

## Mentor's notes

- Keep a personal "assertion failed for a stupid reason" list. Mine is this file. Reading it takes
  two minutes and has saved days.
- The moment a property needs a third local variable or a `first_match`, stop and ask whether a
  ten-line procedural model would be clearer for the next engineer. Usually yes.
