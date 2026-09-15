# 1.6 Gotchas: Where SystemVerilog Silently Lies to You

SystemVerilog "does a lot for you automatically," and every automatic behavior is a place where a
mistake becomes invisible. Each item here has cost real projects real time. Learn to recognize them
on sight.

## G1. X in a comparison makes the check disappear

```systemverilog
logic [7:0] out, expected;    // expected is X during reset
...
if (out != expected) $error("mismatch");    // NEVER fires while either is X
```

`!=` with any X operand returns X. `if (X)` is false. So a check against an uninitialized or
un-reset value is silently skipped. The same applies to `==` inside `assert(...)`. Worse: `if (!x)`
is *also* false when `x` is X, so both branches of an if/else on an X condition can be skipped.

**Fix:** in testbench checks use the case-equality operators `===` / `!==`, which treat X and Z as
ordinary values (`8'hxx !== 8'h00` is true). They are not synthesizable, which is fine in a
testbench. Also assert `!$isunknown(sig)` on any output that should be known after reset; it is the
cheapest, highest-yield assertion you can write.

SVA note: inside concurrent assertions, `==` on X also gives X, and the property fails only if the
result is definitely false. An `X` on a checked signal therefore can *pass* a property. Add
`!$isunknown` properties.

## G2. Implicit net declarations

```systemverilog
mult #(.WIDTH(16)) m1 (.a(x), .b(y), .product(mult1_out));   // mult1_out never declared
assign result = mult1_out + mult2_out;                        // "compiles fine"
```

An undeclared identifier in a port connection becomes an implicit **1-bit wire**. The 32-bit product
is truncated to one bit; the tool may not even warn. `result` can only ever be 0, 1, or 2.

**Fix:** put `` `default_nettype none `` at the top of every file (and `` `default_nettype wire `` at
the end if you include third-party code that relies on implicit nets). Now the typo is a compile
error. Also declare every internal signal before use, and use `.*` where names must match exactly.

## G3. Width extension and truncation rules

Expression width is the **maximum of all operand widths and the destination width**, determined
*before* evaluation. Truncation happens *silently* on assignment.

```systemverilog
logic [7:0] a, b;  logic [7:0] s8;  logic [8:0] s9;
s8 = a + b;            // carry dropped silently
s9 = a + b;            // operands extended to 9 bits BEFORE adding: carry captured. Correct.
s8 = (a + b) >> 1;     // average? No: a+b is computed in 8 bits (destination is 8), carry lost, then shifted.
s8 = ({1'b0, a} + b) >> 1;   // force a 9-bit context. Correct.
logic [3:0] n = 8'd200;      // silently 8 (200 mod 16)
if (a + b > 8'd255) ...      // never true: all operands are 8 bits, so a+b is computed in 8 bits and
                             // can never exceed 255. The carry is lost before the comparison.
if ({1'b0,a} + b > 9'd255) ...   // Correct: a 9-bit operand forces a 9-bit context.
```

Rules that matter:

- Unsized integer literals (`1`, `'d5`) are at least 32 bits. `4'd1 << 4` is 0 if the context is 4 bits.
- `'0`, `'1`, `'x`, `'z` fill the destination width. `'1` is "all ones," which is what you want for
  "max value"; `-1` also works if the destination is unsigned and wide enough.
- Multiplication: `a * b` with two 8-bit operands in an 8-bit context keeps only 8 bits. Declare the
  product `[15:0]` and the operands extend automatically.
- Explicit cast to fix and document: `s8 = 8'(a + b);` (intentional truncation);
  `s9 = 9'(a) + b;`.

## G4. Signed arithmetic traps

An expression is signed only if **every** operand is signed. One unsigned operand makes the whole
thing unsigned, and negative values become huge positives.

```systemverilog
logic signed [7:0] s = -1;
logic        [7:0] u = 8'd1;
if (s < u)  ...          // s is treated as unsigned 255: false!
if (s < signed'(u)) ...  // true
int i = -1; logic [3:0] v = 4'd3;
if (i < v) ...           // v extended to 32 bits unsigned, i converted to unsigned 0xFFFFFFFF: false
```

- Part-selects and concatenations are **always unsigned** even of signed vectors: `s[3:0]` is unsigned.
- `$signed()` / `signed'()` to fix. Prefer `int` for counters and arithmetic in testbenches; it is
  signed and 32-bit, and matches your intuition.
- Comparing a `bit [7:0]` DUT field to a negative `int` constant will never match.

## G5. Out-of-range array indexes are legal

```systemverilog
logic [7:0] mem [64];
logic [7:0] rd_addr;   // 8 bits: can address 256 entries, but mem only has 64
data = mem[rd_addr];   // Reads of index >= 64 return X (or 0 for 2-state types).
mem[wr_addr] <= d;     // writes to index >= 64 are silently ignored.
```

The LRM *permits* a warning; it does not require one. Synthesis may truncate the address instead
(different behavior than simulation: the worst kind of bug). Stitt's `mux4x1` gotcha does
`inputs[4]` on a 4-element array, gets X, and the testbench with `!=` (G1) reports nothing. Two
gotchas conspiring.

**Fix:** size your index types with `$clog2` and typedefs; add an assertion `addr < DEPTH` on every
memory access in the model; use `unique case` so an unmatched index warns; use `!==` in checks.

## G6. `$random` vs `$urandom`

`$random` is signed (negative values when assigned to `int`), global-seeded, poorly distributed, and
not thread-stable. `$random % 10` can be negative. Use `$urandom` and `$urandom_range(max, min)`.
For anything with constraints, use `randomize()`.

## G7. Static task locals and initializers (repeat of 1.4, because it keeps happening)

```systemverilog
task wait_ready(int max);       // static by default in a module
  int n = 0;                    // initialized ONCE at time 0, not per call
  while (!ready && n < max) begin @(posedge clk); n++; end
endtask
```

Second call starts with `n` at whatever the first call left. Mark it `automatic`.

## G8. `always_comb` and latches, `always @*` and time zero

- Any path through a combinational block that does not assign an output infers a latch. Assign
  defaults at the top of the block (`out = '0;`) before the case.
- `always @*` does not run at time 0 if no input changes; outputs stay X until the first input
  toggle. `always_comb` runs once at time 0. Use `always_comb`.
- A function that reads a module-scope variable not passed as an argument: `always @*` is not
  sensitive to it; `always_comb` is. Better: pass everything as arguments (also required for SVA,
  see chapter 3).

## G9. Blocking assignment to a DUT input from the testbench

Covered exhaustively in 1.3. The symptom: the DUT appears to see your input "one cycle early" or
"one cycle late" and the behavior changes when you add an unrelated block. Grep for `= ` on interface
signals in `initial` blocks.

## G10. Class handle vs object: null, aliasing, shallow copy

```systemverilog
my_txn t;             // handle, value null
t.data = 5;           // runtime NULL dereference: fatal
t = new();            // now an object exists

my_txn a = new(), b;
b = a;                // b and a point to the SAME object; b.data = 1 changes a.data
b = new a;            // shallow copy: fields copied, but nested handles still shared
```

Monitors that reuse one transaction object and `write()` it to an analysis port every cycle corrupt
everything downstream, because every subscriber holds the same handle. Allocate a new object per
transaction (Stitt's monitor comment). Chapter 6 covers deep copy.

## G11. `randomize()` failures ignored

`item.randomize();` returns 0 on constraint conflict and leaves the object unchanged. If you do not
check the return, you drive the previous transaction again, forever, and the testbench "passes."
Always `if (!item.randomize()) $fatal(...)` or `assert(item.randomize()) else ...`.

## G12. `disable iff` reads the unsampled value

`assert property (@(posedge clk) disable iff (rst) ...)`: the disable expression is evaluated with the
*current* (not Preponed-sampled) value, asynchronously. If `rst` deasserts with `<=` at the same
posedge, the property attempt that started on that edge can be enabled even though `rst` was 1 when
the edge occurred. Symptom: an assertion fails exactly one cycle after reset release. Fixes: release
reset on `negedge`; or use `disable iff ($sampled(rst))`; or move the reset check into the antecedent
(`!rst && en |=> ...`). Details in chapter 3.

## G13. `$past` across reset

`out == $past(in)` in the first cycle after reset compares against the input value from *during*
reset. Either the input was held at the reset value (coincidence, fragile) or the check fails. Gate
the first cycle with implication: `!rst |=> out == $past(in)`.

## G14. Compilation-unit `import` and duplicate class definitions

`` `include "my_class.svh" `` in two files without a package produces two distinct `my_class` types.
Wrap classes in a package; include guards alone are not enough across compilation units.

## G15. Timescale drift

A file without a `` `timescale `` inherits the previous file's, in compile order. A DUT compiled at
`1ns/1ps` and a testbench that accidentally inherited `1ps/1ps` makes `#5` mean 5 ps, and your
"10 ns" clock runs at 10 ps. Declare timescale in every file or on the command line.

## G16. `foreach` on a queue while modifying it

Deleting elements inside `foreach (q[i])` skips elements. Iterate with a `while` and an explicit
index, or collect indexes first (`q.find_index`) and delete in reverse.

## G17. Integer division and modulo with negatives; `**` with integers

`-7 / 2` is `-3` (truncates toward zero); `-7 % 2` is `-1`. `2 ** 40` in a 32-bit int context
overflows to 0. Use `longint` or `2.0 ** 40` or a 64-bit literal `64'd1 << 40`.

## Interview angle

- "What is the difference between `==` and `===`?" Then "when would you use each?" Testbench
  checks use `===`; RTL uses `==`. Explain the X-in-if trap.
- "What does an out-of-range read return?" X for 4-state, and the write is ignored; no error
  required.
- "Explain the width rule with an example." The 8-bit average is the classic.
- "Why do we say never use `$random`?"

## Mentor's notes

- Before declaring a test passing on a new environment, deliberately break the DUT (invert a
  condition) and confirm the test fails. G1 and G11 are the two reasons this "mutation check" exists.
- Turn on your simulator's lint-style warnings (`vlog -lint`, `xrun -lint`, `vcs +lint=all`) and read
  them once. Then keep them on. The width and implicit-net warnings pay for themselves the first week.
