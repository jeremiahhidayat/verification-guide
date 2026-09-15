# 1.4 Tasks, Functions, Scope, and Time

## Functions vs. tasks: the one rule

- A **function** executes in zero simulation time. It cannot contain `#`, `@`, or `wait`, and cannot
  call a task. It returns a value (or is `void`).
- A **task** may consume time. It can block on events and call other tasks and functions. It returns
  nothing (use `output`/`ref` arguments).

So: computing an expected value, formatting a message, packing a struct: function. Driving a
transaction onto pins, waiting for a response: task.

```systemverilog
function automatic int model_bit_diff(input logic [15:0] data);
  int diff = 0;
  for (int i = 0; i < 16; i++) diff += data[i] ? 1 : -1;
  return diff;
endfunction

task automatic drive_word(input logic [7:0] w);
  data  <= w;
  valid <= 1'b1;
  @(posedge clk iff ready);
  valid <= 1'b0;
endtask
```

## `automatic` vs. `static`: the bug you will hit in forked threads

By default, a task or function declared in a **module** has **static** storage: every local variable
is allocated *once*, shared by all concurrent invocations. If two threads call the same static task
at the same time (a driver task forked per interface, a checker per port), they overwrite each
other's locals. This is Verilog heritage and it is wrong for almost all verification code.

```systemverilog
task static bad_wait(int n);   // (this is the default in modules)
  int count = 0;               // ONE copy of count for every caller
  repeat (n) begin @(posedge clk); count++; end
endtask

task automatic good_wait(int n);  // fresh locals per call, like C
  int count = 0;
  ...
endtask
```

Rules:

- Write `automatic` on every task/function in a module or interface unless you specifically want
  shared state. Or declare the whole module `module tb automatic;`... but simulators vary; per-routine
  is clearer.
- In **classes**, methods are automatic by default. In **programs**, also automatic by default.
- `automatic` variables cannot be referenced hierarchically or dumped to waveforms in some tools
  (they do not exist statically). If you need to see a task's local in a waveform, make that one
  variable `static` explicitly (`static int dbg;`).
- A variable declared with an initializer inside a *static* routine is initialized **once** at time
  0, not each call. `int count = 0;` in a static task does not reset `count` on each call. This is a
  real bug source; `automatic` fixes it.

## Arguments

```systemverilog
task automatic xfer(
  input  logic [31:0] addr,          // copied in (default direction)
  output logic [31:0] data,          // copied out at the end
  inout  int          credits,       // copied in and out
  ref    logic [7:0]  buffer[]       // passed by reference: no copy; changes visible to caller immediately
);
```

- `input` is the default, so `task t(int a, int b)` means two inputs.
- `ref` requires the routine to be `automatic` and the argument to be a variable (not an expression).
  Use `const ref` for large arrays you only read: avoids a copy without allowing modification.
- Default values: `function void log(string msg, int level = 1);`. Callers can omit trailing args or
  pass by name: `log(.msg("hi"), .level(2))`.
- Passing a class handle is passing a pointer; the callee can modify the object. Passing an array by
  value copies the entire array. For big arrays or queues, use `ref`.

## `void'()` and return values

Calling a function that returns a value without using the result triggers a warning in most tools
(it usually indicates a mistake). Cast to void to say "I meant that":

```systemverilog
void'(q.pop_front());        // discard the popped element
void'(item.randomize());     // NO: you must check randomize's return value. See chapter 5.
if (!item.randomize()) $fatal(1, "randomize failed");   // YES
```

## Scope and hierarchical references

Every module instance, block, and class has a scope. A testbench can reach *into* the DUT with a
hierarchical name. This is called white-box access and it is both powerful and dangerous.

```systemverilog
// From the testbench top:
if (DUT.fifo_inst.count > DEPTH) $error("internal count overflow");
assert property (@(posedge clk) DUT.valid_wr |-> !full);
force DUT.u_ctrl.state = IDLE;   release DUT.u_ctrl.state;    // brute-force error injection
$root.tb_top.clk                                            // absolute path from the root
```

When to use it: assertions on internal state that the designer agreed is architecturally meaningful
(FSM state, credit counters), probing latency constants (`DUT.LATENCY`), forcing errors that cannot be
produced from the pins. When not to: as a substitute for observing the output. If your checks depend
on internal names, a refactor breaks your testbench, and you have verified the RTL against itself.

`bind` (section 3 of the SVA chapter) is the clean way to attach assertions and monitors to internal
scopes without editing RTL.

## Time: units, precision, formatting

```systemverilog
`timescale 1ns / 1ps          // unit / precision. #1 means 1 ns; delays are rounded to 1 ps.
#10;  #10ns;  #0.5;           // 10 ns, 10 ns, 500 ps
localparam time PERIOD = 10ns;   // the 'time' type carries units
realtime t = $realtime;       // current time as real in current units; $time truncates to integer
$timeformat(-9, 3, " ns", 10); // print times in ns with 3 decimals, min width 10: do this once in every tb
$display("[%0t] hello", $realtime);
```

`timescale` is per compilation unit and inherits to subsequent files if not re-declared, which is a
classic cause of "my delay is 1000x off." Put `timescale` at the top of every file or pass it on the
command line (`-timescale 1ns/1ps`) and keep it consistent between DUT and testbench.

## System tasks you will use every day

| Task | Purpose |
|---|---|
| `$display`, `$write` | Print now (Active region). `$strobe` prints at end of time step. `$monitor` prints whenever args change. |
| `$sformatf` | Build a string with printf formatting. |
| `$error`, `$warning`, `$info`, `$fatal(code, msg)` | Severity messages. `$error` increments the tool's error count; `$fatal` terminates. |
| `$urandom`, `$urandom_range(hi, lo)` | Thread-stable random 32-bit unsigned. Never `$random`. |
| `$time`, `$realtime`, `$timeformat` | Time. |
| `$finish`, `$stop` | End / pause simulation. |
| `$clog2(n)` | Ceiling log2: address widths. `$bits(x)`: width of any type. `$size`, `$dimensions`, `$high`, `$low`. |
| `$past`, `$rose`, `$fell`, `$stable`, `$sampled`, `$changed` | Sampled-value functions, mostly in SVA (chapter 3) but usable in procedural code with an explicit clock. |
| `$countones`, `$onehot`, `$onehot0`, `$isunknown` | Bit-vector queries; `$isunknown(v)` is true if any bit is X/Z. Use it in checkers. |
| `$readmemh`, `$readmemb`, `$writememh` | Load/save memories from hex/bin files. |
| `$fopen`, `$fdisplay`, `$fclose`, `$fgets`, `$fscanf` | File I/O. |
| `$value$plusargs("NAME=%d", var)`, `$test$plusargs("NAME")` | Read command-line `+NAME=...` options: how you parameterize tests at run time without recompiling. |
| `$dumpfile`, `$dumpvars` | VCD waveform dump (simulators have faster native formats). |
| `$cast` | Dynamic cast (section 1.1). |
| `$assertoff`, `$asserton`, `$assertkill` | Control assertions during reset or in specific tests. |

### `$random` vs `$urandom`

`$random` is a 1995 leftover: signed 32-bit, a single global seed, poor distribution, and it is *not*
thread-stable (adding an unrelated thread changes every subsequent value). `$urandom` and
`$urandom_range` are per-thread seeded from the object/thread hierarchy, so a change in one part of
the testbench does not alter the random sequence elsewhere. Use `$urandom`. Use `randomize()` on
classes for anything with constraints.

## Interview angle

- "Function vs task?" Time consumption, return value, calling rules. Then they will ask when you
  would use each in a driver (task) and a scoreboard (function).
- "What does `automatic` mean and why does it matter?" Per-call storage; forked concurrent calls;
  initializer semantics; `ref` arguments require it.
- "How do you pass a large array to a task efficiently?" `ref` / `const ref`.
- "How do you make a test configurable without recompiling?" `$value$plusargs` (and in UVM,
  `uvm_cmdline_processor` / `+uvm_set_config_int`).

## Mentor's notes

- I default every routine to `automatic` and have never regretted it. The one exception is a
  debug counter I want in the waveform, which I mark `static` on purpose with a comment.
- Hierarchical references are like `goto`: occasionally exactly right, usually a sign you should
  expose the information properly (a port, a `bind`, or a package constant).
