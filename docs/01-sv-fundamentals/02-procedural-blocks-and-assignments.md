# 1.2 Procedural Blocks, Assignments, and Timing Control

## Processes: the unit of concurrency

Every `initial`, `always`, `always_comb`, `always_ff`, `always_latch`, continuous `assign`, and forked
thread is a **process**. The simulator runs all processes concurrently, in an order *you do not
control*. Understanding that one sentence is the foundation of section 1.3.

```systemverilog
initial begin            // runs once, starting at time 0
  ...
end

always begin             // runs forever; must contain a timing control or the sim hangs
  #5 clk = ~clk;
end

always @(posedge clk)    // Verilog-style sensitivity list
always_ff @(posedge clk or posedge rst)   // SV: "I intend a flop"; tools check for that
always_comb              // SV: "I intend combinational logic"; sensitivity inferred; runs once at time 0
always_latch             // SV: "I intend a latch"
```

Why the `always_*` variants exist: `always @(*)` infers sensitivity but does not *check* your intent.
`always_comb` additionally (a) executes once at time zero so outputs are defined even if no input
changes, (b) is sensitive to variables read inside called functions, (c) forbids the same variable
being written from another process, and (d) lets synthesis and lint warn if you accidentally
described a latch. Use `always_comb`/`always_ff` in RTL; in testbenches you mostly write `initial`
and `always @(posedge clk)`.

A testbench top usually has several `initial` blocks, each with one responsibility (clock, reset,
stimulus, checking). Label them; it makes waveform navigation and `disable` possible:

```systemverilog
initial begin : generate_clock
  clk = 0;
  forever #5 clk = ~clk;      // 10 ns period
end
...
disable generate_clock;       // from another block: kills the clock, and the sim ends naturally
```

## Blocking vs. nonblocking assignment: the mechanism, not the folklore

Everyone is taught "use `<=` in `always_ff`, `=` in `always_comb`." Fine for RTL. For testbenches you
need to know *why*, because the reason is what stops race conditions.

- **Blocking `=`**: evaluate the right-hand side, update the variable *immediately*, then continue to
  the next statement. Later statements in this process see the new value. Other processes see it
  whenever they happen to run, which may be before or after this one.
- **Nonblocking `<=`**: evaluate the right-hand side *now*, but schedule the update for the **NBA
  region** at the end of the current time step. Every read of the variable in this time step, by any
  process, sees the *old* value. All NBA updates in a time step then happen "at once."

Think of a nonblocking assignment as a variable having a *current* value and a *future* value. The
assignment sets the future; the end of the time step copies future to current.

```systemverilog
int x;
initial begin
  x <= 0;              // current: X   future: 0
  @(posedge clk);      // time step ends: current = 0
  x <= 1;              // current: 0   future: 1
  $display(x);         // prints 0
  x <= 2;              // current: 0   future: 2 (the future value 1 was overwritten, never seen)
  $display(x);         // prints 0
  @(posedge clk);      // current = 2
  $display(x);         // prints 2
end
```

Because every NBA right-hand side is evaluated before any NBA left-hand side is updated, the *order*
of nonblocking assignments in a time step does not matter, and neither does the order in which the
simulator chooses to run the processes that contain them. That is the property that eliminates
races. Stitt's article proves it with this test, which is worth running once to believe it:

```systemverilog
// c1, c2, c3 are always equal, even though c3 is "computed before" a3 and b3 are assigned.
a1 <= i; b1 <= j; c1 <= a1 + b1;
a2 <= i; c2 <= a2 + b2; b2 <= j;
c3 <= a3 + b3; a3 <= i; b3 <= j;
@(posedge clk);
```

This is exactly how a hardware register behaves: D is sampled at the clock edge, Q changes just
after. Nonblocking assignment *is* a register whose clock is "end of this time step."

### The two testbench rules (memorize these)

1. **Any variable written in one process and read in another, where both are synchronized to the same
   event, must be written with a nonblocking assignment.**
2. **Therefore, every assignment to a DUT input from the testbench is nonblocking.** The DUT's
   `always_ff` blocks read those inputs at the clock edge; if you write them with `=` at the same
   edge, whether the DUT sees the old or new value depends on process order.

It is fine to use `=` for local bookkeeping inside a single process (computing an expected value you
compare immediately). It is fine to mix `=` and `<=` in a testbench. It is *not* fine to write a
shared, clock-synchronized variable with `=`.

The full derivation, with waveforms, is in section 1.3.

## Timing control: how a process gives up the CPU

A process runs until it hits a timing control, then suspends. There are three kinds:

```systemverilog
#10;                       // delay: resume 10 time units later (units from `timescale)
#10ns;                     // explicit unit
@(posedge clk);            // event control: resume on the next rising edge of clk
@(negedge clk);  @(clk);   // falling edge; any change
@(posedge clk iff en);     // resume on a posedge where en is true (iff is evaluated at the edge)
@(a or b);  @(a, b);       // any change on a or b
@(my_event);               // named event (chapter 6)
wait (done == 1);          // level-sensitive: resume when the expression is true (immediately if already true)
wait fork;                 // wait for all child threads
```

`@(posedge sig)` versus `wait(sig)`: the first waits for a *transition* and will hang if the signal is
already high and stays high; the second returns immediately if the condition already holds. For
"wait until the DUT says done," `@(posedge clk iff done)` is usually what you want, because it also
aligns you to the clock and ignores combinational glitches on `done`.

### Waiting for N cycles

```systemverilog
repeat (5) @(posedge clk);
for (int i = 0; i < N; i++) @(posedge clk);
```

### `#0` and why you should not use it

`#0` says "suspend, and resume later in this same time step, in the Inactive region." People use it
to "let other processes go first." It does not create determinism; it creates a different race
that depends on how many other processes also used `#0`. If you feel you need `#0`, you have a
blocking-assignment race. Fix the assignment.

### Small delays after the clock (`#1`)

You will see testbenches that do `@(posedge clk); #1; check(out);` to "give the output time to
settle." It works, and it is a habit to break: it shifts every subsequent stimulus off the clock edge,
it hides races instead of removing them, and it does not scale to many processes. The clean pattern
is: drive with nonblocking assignments, check on the *next* edge using values you sampled on the
previous edge (or use assertions, which sample in the Preponed region for you). Section 2.1 shows both.

## Loops and flow control

```systemverilog
for (int i = 0; i < 8; i++) ...          // loop variable declared in the loop is local and automatic
foreach (arr[i]) ...                      // every index of an unpacked array (nested: foreach (m[i][j]))
while (!done) @(posedge clk);
do begin ... end while (cond);
repeat (n) ...
forever ...                               // until disable/$finish; always contains a timing control
break; continue;                          // work in all loops
return;                                   // exit a task/function early
```

`unique case` / `priority case` / `unique if`: RTL constructs that tell synthesis (and simulation
checkers) that exactly one branch matches (unique) or that priority encoding is intended. In
simulation, `unique case` reports a runtime warning if no branch or more than one branch matches:
a free assertion. `case` vs `casez`/`casex`: `casez` treats `?`/`z` in the case items as wildcards;
`casex` also treats `x` as wildcard, which can mask real Xs; prefer `casez` or the `inside` operator
(`if (op inside {ADD, SUB})`).

## `initial` ordering and time zero

All `initial` blocks start at time 0 in an unspecified order. Variable declaration initializers
(`logic clk = 0;`) also happen at time 0, before any `initial` runs in most simulators but the LRM
allows them to interleave. Two consequences:

1. Never rely on one `initial` running before another. Communicate with events, mailboxes, or NBAs.
2. If you assert reset with `rst = 1` at time 0 in an `initial` and the DUT has `always_ff @(posedge
   clk or posedge rst)`, there is no posedge of rst (it goes X to 1, which *is* a posedge in
   4-state semantics, but the flop block may or may not have started). Use `rst <= 1` and hold it for
   several cycles; release it away from the clock edge. See 1.3 and 2.1.

## Ending a simulation

```systemverilog
$finish;              // exit the simulator (in a GUI: asks to confirm)
$stop;                // pause; useful for interactive debug
disable generate_clock;   // stop the clock; with no events left, the sim ends on its own
```

UVM calls `$finish` for you after the phases complete. In plain testbenches, either approach works;
Stitt's tutorial prefers `disable` on the clock generator because the sim then ends "naturally" and
no dialog appears in a GUI.

## Interview angle

- "Explain blocking vs nonblocking" is asked at every level. Junior answer: `=` is sequential, `<=`
  is parallel. Senior answer: NBA schedules the update to the NBA region so all RHS are evaluated
  before any LHS update, which makes results independent of process order; that is why registers
  use it and why testbenches drive DUT inputs with it. Draw the current/future picture.
- "What does `always_comb` do that `always @(*)` does not?" Time-zero execution, function
  sensitivity, single-driver checking, latch intent checking.
- "Why is `#0` bad?" It reorders within the time step but does not remove the dependency on ordering.

## Mentor's notes

- Label every `initial` block and every `fork` branch. Future you, staring at a hung simulation in a
  process browser, will be grateful.
- When you see `#1` sprinkled through a testbench you inherited, you have found where the races
  are. Do not remove them all at once; convert one process at a time to NBA-driven, edge-checked
  style and re-run.
