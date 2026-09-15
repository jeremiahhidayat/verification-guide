# 1.3 Simulation Semantics and Race Conditions

This is the section that separates people who can debug a testbench from people who add `#1` until
it passes. Read it slowly. Everything in SVA sampling, clocking blocks, and UVM driver timing rests
on it.

## The event-driven simulator, from first principles

A simulator does not "run hardware." It maintains a **time-ordered queue of events**, where an event is
"process P is ready to resume" or "variable V is to be updated." At each simulation time step it drains
the events for that time, in a set of **regions**, then advances to the next time that has events.

The IEEE 1800 scheduling regions for one time step (simplified to the ones that matter):

```
   ┌──────────────┐
   │  Preponed    │  Sample values for concurrent assertions (SVA) and clocking-block inputs.
   │              │  Nothing has changed yet in this time step; this is "just before the clock edge."
   ├──────────────┤
   │  Active      │  Run processes: blocking assignments, evaluate RHS of nonblocking assignments,
   │              │  continuous assigns, $display. Processes woken by events run here IN ANY ORDER.
   ├──────────────┤
   │  Inactive    │  #0-delayed processes.
   ├──────────────┤
   │  NBA         │  Perform the nonblocking assignment updates (copy future -> current).
   │              │  If any update wakes a process, go back to Active (another "delta cycle").
   ├──────────────┤
   │  Observed    │  Evaluate concurrent assertions using the Preponed samples.
   ├──────────────┤
   │  Reactive    │  program blocks, assertion action blocks, clocking-block output drives.
   ├──────────────┤
   │  Postponed   │  $strobe, $monitor: read final values of the time step.
   └──────────────┘
```

Two things to burn in:

1. **Within a region, the order in which ready processes execute is undefined.** The LRM says so
   explicitly. Any simulator is free to pick any order, to change it between runs, or between
   versions, or when you add an unrelated module. Code whose result depends on that order has a
   **race condition**.
2. **The Active/NBA loop can iterate many times in one time step** (delta cycles). A blocking
   assignment in Active that changes a signal wakes other processes, which run in Active again,
   before NBA. Time does not advance; only the "delta" count does. Waveform viewers show this as
   several values at the same time stamp (if you enable delta display).

## Anatomy of the classic race

```systemverilog
module race;
  logic clk = 0;  int x;
  always #5 clk = ~clk;

  initial begin : drive_x                 // Process A
    for (int i = 0; i < 10; i++) begin
      x = i;                              // BLOCKING write to a shared variable
      @(posedge clk);
    end
  end

  initial begin : check_x                 // Process B
    for (int i = 0; i < 10; i++) begin
      @(posedge clk);
      if (x != i) $error("x = %0d, expected %0d", x, i);
    end
  end
endmodule
```

Both processes wake on the same `posedge clk`. Two legal executions:

```
Order 1 (B first)            Order 2 (A first)
  B: reads x == 0, ok          A: x = 1        <- x changes before B reads it
  A: x = 1                     B: reads x == 1, expected 0: ERROR
```

Stitt reports Questa producing errors on *alternating* iterations: the simulator's order changed
between time steps. This is not a bug in the simulator. It is a bug in the code. The one-character fix
is `x <= i;`: the update is deferred to the NBA region, so no matter which process runs first in
Active, B reads the old value.

### The rule, restated with the mechanism

> If a variable is **written in process A** and **read in process B**, and A's write and B's read are
> triggered by **the same event**, then in the Active region A's write and B's read are unordered.
> Making the write nonblocking moves it to the NBA region, which is strictly after every Active-region
> read. That removes the race.

### Corollary: drive all DUT inputs with `<=`

The DUT is process B. Its `always_ff @(posedge clk)` reads your inputs in Active. If your `initial`
writes them with `=` at the same posedge, the DUT may see this cycle's or next cycle's value
depending on order. With `<=`, the DUT always sees the value from before the edge, i.e. the value you
"set up" during the previous cycle, exactly like real hardware with setup time.

## Reset races (the one that corrupts an entire chip's state)

```systemverilog
always @(posedge clk) rst = ~rst;                        // testbench toggles reset with a blocking write
always_ff @(posedge clk or posedge rst)                  // DUT flop
  if (rst) out <= '0; else out <= in;
```

At a rising clock edge, the simulator may run the DUT flop first (sees rst == 1, resets) or the
testbench first (clears rst, then the flop sees 0 and loads `in`). Stitt showed this yields 5000/5000
in one arrangement of the source file and 10000/0 when two blocks are swapped in the file, proving
the order is arbitrary. Now imagine a design with 10,000 flops in different `always_ff` blocks: some
may come out of reset one cycle before others *in the same simulation*. That is catastrophic and
nearly impossible to debug from a waveform.

Fixes, in order of preference:

1. `rst <= ~rst;` (NBA). The flop always sees the pre-edge value.
2. Deassert reset on the *falling* edge: `@(negedge clk); rst <= 0;`. Now nothing else is synchronized
   to that event, and there is setup margin to the next rising edge (this also avoids metastability
   in gate-level sims with timing).
3. Both. This is the standard pattern:

```systemverilog
initial begin
  rst <= 1'b1;
  repeat (5) @(posedge clk);
  @(negedge clk);
  rst <= 1'b0;
end
```

## The time-zero race

At time 0, `initial` blocks, variable initializers, and `always_comb` first executions all run in
Active in arbitrary order. `logic clk = 0;` plus `initial rst = 1;` plus a DUT with `always_ff
@(posedge clk or posedge rst)`: whether the flop sees the `posedge rst` (X to 1 counts as a posedge)
depends on whether it was already waiting. Solutions: assert reset with `<=`, hold it for several
cycles so the first real clock edge sees it, and never rely on time-0 edges.

## Clock generation races

```systemverilog
always #5 clk = ~clk;      // blocking: fine ONLY if nothing else writes clk and nobody reads it at the same instant except via @(posedge clk)
always #5 clk <= ~clk;     // nonblocking: also fine, and consistent with the rule
```

Either works for a clock because processes wait on the *edge event*, which is generated when the
value changes regardless of region. The problem arises when a testbench block drives a DUT input with
`=` *in the same process* that toggles the clock, or when two clocks are derived with blocking
assignments from a common source and a flop is sensitive to one while data comes from the other.
Keep the clock generator in its own labeled `initial`/`always` and touch nothing else in it.

## Combinational feedback through the testbench

```systemverilog
always @(*) ready = valid && !busy;      // testbench models a downstream ready
always_ff @(posedge clk) if (valid && ready) ...  // DUT
```

No race here (different regions/events), but if the testbench's `ready` depends on the DUT's `valid`
and the DUT's `valid` depends combinationally on `ready`, you have a *zero-delay loop* which either
oscillates (simulator hangs at one time step) or settles by luck. AXI-Stream forbids `valid`
depending on `ready` for exactly this reason. When you write a driver for a ready/valid protocol,
generate `ready` from a register or from randomness, never from the same-cycle `valid`.

## `$display` races

`$display` in the Active region shows the value at the moment that statement executes, which may be
before or after another process's blocking update in the same time step. If you print DUT outputs with
`$display` right after `@(posedge clk)`, you will see the *old* value (NBA has not happened). Use
`$strobe` (Postponed region: shows end-of-time-step values) or print on the next edge, or print
from within an assertion action block using `$sampled`.

## How NOT to fix a race

- **Adding `#1` after the edge** in the writer. It "fixes" that one pair by moving the write to a
  different time. Now every other reader of that signal is off by 1 ns, waveforms look wrong, and the
  next race is still there. Stitt: "I've never encountered a situation where waits were necessary to
  resolve race conditions."
- **Reordering blocks in the file.** Works until the simulator changes its scheduling heuristic.
- **Switching `always @(posedge clk)` to `always_ff`.** Same semantics; you just changed which order
  the simulator happened to pick.
- **Declaring victory because it passes.** Passing proves nothing about races. Run on a second
  simulator, or randomize process ordering if your tool supports it (Questa: `-permit_unmatched
  ...`; VCS: `+rad` scheduling variants). Better: follow the two rules and races cannot exist.

## Why SVA and clocking blocks do not race

Concurrent assertions sample in **Preponed**, before anything in the time step has executed. So
`assert property (@(posedge clk) a |=> b)` sees the values `a` and `b` had *just before* the edge,
i.e. exactly the values the DUT's flops sampled. No matter how the testbench drives `a`, the assertion
and the DUT agree. This is also why, inside an assertion action block, you must use `$sampled(x)` to
print the value the assertion evaluated; a bare `x` gives you the post-NBA value and confuses
everyone.

Clocking blocks (section 1.5) do the same for procedural testbench code: inputs are sampled in
Preponed (with an optional skew) and outputs are driven in Reactive, after the DUT has evaluated.
That is the LRM's official mechanism for a race-free testbench; nonblocking assignment to DUT inputs
is the pragmatic equivalent that most engineers use.

## Delta cycles and "why is my always_comb output one delta late?"

`assign b = a; assign c = b;` When `a` changes at time T, `b` updates in delta 1, `c` in delta 2, all
at time T. Waveforms show them at the same time. Any process that reads `c` at delta 0 or 1 of time
T sees the old value. This is normal and harmless *as long as* your reads are edge-triggered (the
combinational cone settles long before the next edge). It becomes a problem only when you sample
combinational outputs in the same time step they change, which is what `#1` hacks are trying to
avoid. Check on edges; let the deltas settle.

## Checklist: is my testbench race-free?

- [ ] Every DUT input is assigned with `<=` from testbench procedural code (or through a clocking block).
- [ ] Every variable shared between two clock-synchronized processes is written with `<=`.
- [ ] Reset is asserted with `<=` at time 0, held for several cycles, released on `negedge clk` (or with `<=`).
- [ ] The clock generator is alone in its block.
- [ ] No `#0`. No `#1`-after-the-edge. No `$display` of DUT outputs in the same edge (use `$strobe`, next edge, or `$sampled`).
- [ ] Testbench-generated `ready` does not depend combinationally on DUT `valid` in the same cycle.
- [ ] Checks happen on clock edges using values captured on previous edges, or in assertions.

## Interview angle

- "What are the simulation regions?" Name Preponed, Active, NBA, Observed, Reactive, Postponed and
  what happens in each. Bonus: which region SVA samples in and why that avoids races.
- "What is a race condition in SystemVerilog? Give an example and the fix." Use the `x = i` /
  `if (x != i)` example. The fix is NBA. Explain *why* NBA works (RHS evaluated in Active, LHS updated
  in NBA, strictly after all Active reads).
- "Why release reset on the negative edge?" No process is synchronized to that event, plus
  setup/hold margin in timing simulations.
- "What is a delta cycle?" Zero-time iteration of Active/NBA caused by updates waking processes.

## Mentor's notes

- I have watched a senior engineer refuse to fix a race because "the test has passed for two years."
  Two months later a simulator upgrade broke 40 tests overnight. The code never worked; it was lucky.
  Stitt's line: *"The fact that fixing the race condition broke the functionality just proved that
  the code never worked."*
- When a new failure appears after an unrelated change (new module added, file order changed), think
  "race" before "bug in my change." Grep the testbench for `= ` on DUT inputs.
- Run the examples in `code/01-fundamentals/races.sv`. Swap the two blocks. Watch the result change.
  You will never forget it.
