# 2.1 Anatomy of a Testbench

## What a testbench is

A testbench is a module with no ports that instantiates the DUT, generates its inputs, and checks its
outputs. Nothing more mysterious than that. Its job is to *make the DUT wrong in a visible way*.

```
        ┌─────────────────────────────────────────────┐
        │ tb (module, no ports)                       │
        │  clock gen ──► clk ─────────┐               │
        │  reset gen ──► rst ─────────┤               │
        │  stimulus  ──► inputs ──► ┌─┴───┐ ──► outputs ──► checker ──► $error / pass count
        │                           │ DUT │            │
        │  reference model ────────►└─────┘ expected ──┘
        └─────────────────────────────────────────────┘
```

## The minimal viable testbench

For a 2:1 mux (combinational):

```systemverilog
`timescale 1ns/1ps
module mux2x1_tb;
  logic in0, in1, sel, out;
  logic expected;

  mux2x1 dut (.in0, .in1, .sel, .out);       // .name shorthand: connects port 'in0' to signal 'in0'

  initial begin
    $timeformat(-9, 0, " ns");
    for (int i = 0; i < 8; i++) begin       // exhaustive: 3 inputs -> 8 combinations
      {sel, in1, in0} <= i;                 // drive with NBA (habit, even for combinational DUTs)
      #10;                                  // let it settle
      expected = sel ? in1 : in0;           // local bookkeeping: blocking is fine
      if (out !== expected) $error("[%0t] sel=%b in1=%b in0=%b: out=%b expected %b", $realtime, sel, in1, in0, out, expected);
    end
    $display("mux2x1_tb: done");
  end
endmodule
```

Observe the ingredients: a timeformat so messages have units, exhaustive stimulus because the space
is tiny, a reference expression (`sel ? in1 : in0`) *written from the spec, not copied from the RTL*,
and `!==` so an X output is reported. This is complete verification of a mux.

## Clock and reset

Sequential DUTs need a clock and a reset. Give each its own process:

```systemverilog
logic clk = 1'b0;
logic rst;

initial begin : generate_clock
  forever #5 clk = ~clk;                    // 100 MHz. Alone in its block. Nothing else here.
end

initial begin : generate_reset
  rst <= 1'b1;                              // NBA at time 0: DUT sees it on the first edge regardless of order
  repeat (5) @(posedge clk);                // hold for several cycles: lets X clear out of the DUT
  @(negedge clk);                           // release away from the sampling edge
  rst <= 1'b0;
end
```

Why hold reset for several cycles? Real designs have reset synchronizers and multi-stage reset
trees; a one-cycle pulse may not propagate. Also, any X on a DUT output *after* this window is a real
finding (a flop that is not reset).

Why release on the negedge? No process in the design is sensitive to `negedge clk` (usually), so
there is nothing to race with, and in a gate-level simulation with timing, deasserting reset in the
setup window of a flop would cause metastability warnings.

## Stimulus

Directed, exhaustive, or random; the *mechanics* are the same: assign DUT inputs with `<=`, then
wait for a clock edge.

```systemverilog
initial begin : stimulus
  @(negedge rst);                           // wait for reset release (or @(posedge clk iff !rst))
  @(posedge clk);
  for (int i = 0; i < NUM_TESTS; i++) begin
    in <= $urandom;
    en <= $urandom;                         // 1-bit target: takes LSB of the 32-bit random value
    @(posedge clk);
  end
  $display("stimulus done");
  disable generate_clock;                   // ends the simulation once other processes idle
end
```

A very common question: *"the DUT samples at the posedge; I assign at the posedge; which value does
it see?"* With NBA, the DUT sees the value assigned in the *previous* iteration (the value that was
stable during the whole cycle). The value assigned in this iteration takes effect just after this
edge and is what the DUT will sample at the *next* edge. Draw it:

```
cycle:        n                 n+1
clk:      ____|‾‾‾‾‾‾|____|‾‾‾‾‾‾|____
in:       ====X== v(n) ====X== v(n+1) ==
              ^ NBA lands   ^ DUT samples v(n) here, TB assigns v(n+1) here (lands right after)
```

This is exactly setup/hold in real hardware, which is why the pattern feels natural after a week.

## Checking, and the "when do I check?" problem

The output of a register changes just after the edge (NBA). If you check right at the edge you see
the old value. Three approaches, worst to best:

**(a) Check after a small delay.** `@(posedge clk); #1; if (out !== expected) ...`. Works. Shifts
everything by 1 ns, hides races, does not scale. Avoid.

**(b) Check on the next edge against saved expectations.** Compute what the output *should become*
when you drive the input, remember it, compare on the next edge.

```systemverilog
logic [7:0] expected = '0;

initial begin : monitor          // decides what "correct" means each cycle
  forever begin
    @(posedge clk);
    expected <= rst ? '0 : (en ? in : out);     // reads pre-edge values of rst/en/in/out (they are NBA-driven)
  end
end

initial begin : checker          // compares
  forever begin
    @(posedge clk);
    if (out !== expected) $error("[%0t] out=%h expected=%h", $realtime, out, expected);
  end
end
```

This is Stitt's `register_tb4` and it is the right shape: one process decides the expected value from
the values present at the edge, another process compares at the next edge. Both read only NBA-driven
values, so there is no race. Note `expected` must be initialized to the reset value so the first
comparison is not against X.

**(c) Use assertions.** Chapter 3 shows that (b) collapses to one line:
`assert property (@(posedge clk) disable iff (rst) en |=> out == $past(in));` Assertions sample in the
Preponed region, so "when do I check?" is answered for you.

## Separating responsibilities

A monolithic `initial` that drives, waits, and checks becomes unmaintainable at about 50 lines.
Separate processes by responsibility, synchronized only by the clock:

| Process | Responsibility | Talks to |
|---|---|---|
| `generate_clock` | Toggle `clk` | nobody |
| `generate_reset` | Reset sequence | `rst` |
| `stimulus` (generator + driver) | Decide values, drive DUT inputs with NBA | DUT inputs |
| `monitor` | Observe DUT pins, compute expected (or hand observed values to a scoreboard) | DUT outputs |
| `checker` / scoreboard | Compare actual vs expected, count pass/fail | expected values |
| `end_of_test` | Wait for completion, print summary, stop | everyone |

This is the layered testbench of chapter 6 and the UVM agent of chapter 7 in embryonic form. The
class-based versions add reuse and configurability; the *responsibilities* do not change.

## Ending the simulation

- `disable generate_clock;` from the last active process: the clock stops, the event queue drains,
  the simulator exits cleanly. Elegant, but it requires that no other process is stuck in a
  `forever` loop waiting on something other than the clock.
- `$finish;` Explicit, always works. In UVM, the framework does this after the report phase.
- Print a summary first: pass count, fail count, and a single unambiguous line like `TEST PASSED` /
  `TEST FAILED` that a regression script can grep. Also check the simulator's own error count (an
  `$error` from an assertion may have fired even if your scoreboard is happy).

## Parameterize the testbench

```systemverilog
module register_tb #(parameter int NUM_TESTS = 10000, parameter int WIDTH = 8);
```

Override from the command line (`vsim -gNUM_TESTS=100 register_tb`, `xrun -defparam
register_tb.NUM_TESTS=100`) or with `$value$plusargs` for run-time knobs. A testbench that can run
"short" for smoke tests and "long" for overnight regressions is one you will actually use.

## Comparing multiple implementations

When a designer offers three implementations of the same function, instantiate all three and drive
them from the same stimulus; the checker compares each against the model (or against each other).
Stitt's `mux2x1_all_tb` does this with a `check_output(name, actual, expected)` function to avoid
copy-paste. This is also how you validate a *new* RTL version against a *golden* one.

## Interview angle

- "Write a testbench for a register with enable." They want: clock/reset processes, NBA-driven
  stimulus, a check on the next edge (or an assertion), `!==`, a summary. Then they will ask "what
  happens if you assign with `=`?" and "why release reset on the negedge?"
- "How do you end a simulation?" and "how does a regression know the test passed?"

## Mentor's notes

- Print the time in every message. Print the *inputs* in every failure message, not just the
  actual/expected outputs. The person debugging (probably you, next week) needs to reproduce.
- Keep a template testbench in your personal notes. Mine is Stitt's `register_tb4` with the
  assertion variants from chapter 3. New DUT: copy, rename, replace the model, run.
