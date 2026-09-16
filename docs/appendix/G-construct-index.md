# G. Construct Index: Every Keyword in a Small Testbench

A reference for the constructs a junior engineer meets in the first week, keyed to one 30-line
program. Read the program, then look up anything unfamiliar in the tables below. Each row says what
the construct does, the one thing people get wrong with it, and where the guide explains it.

The program is [`code/01-fundamentals/packet_dynarray.sv`](../../code/01-fundamentals/packet_dynarray.sv),
discussed in [1.1 Data types](../01-sv-fundamentals/01-data-types.md#dynamic-arrays-size-chosen-at-runtime):

```systemverilog
class packet;
  rand byte payload[];                                    // randomized payload as a dynamic array
  constraint c_len { payload.size() inside {[1:64]}; }    // constrain the length, not the contents

  function void display();
    $display("packet size = %0d, data = %p", payload.size(), payload);
  endfunction
endclass

module scratch;
  initial begin
    packet pkt_q[$];   // queue of packet handles
    packet p;

    repeat (5) begin
      p = new();
      assert(p.randomize());  // gets a fresh random size each time
      pkt_q.push_back(p);
    end

    foreach (pkt_q[i]) pkt_q[i].display();
    $finish;
  end
endmodule
```

## Types and containers

| Construct | What it is | Use it right | Explained in |
|---|---|---|---|
| `byte` | 2-state, signed, 8-bit integer type (`shortint` 16, `int` 32, `longint` 64) | It is **signed**: `byte b = 8'hFF` is -1, and `b > 127` is never true. Use `bit [7:0]` when you mean an unsigned bus value; `byte` is fine for payload storage | [1.1 Data types](../01-sv-fundamentals/01-data-types.md#the-first-principles-question-what-is-a-value) |
| `payload[]` | Dynamic array: size 0 until `new[n]` or `randomize()` allocates it | Never index it before allocating; out-of-range reads return the default, silently (G5). Resize with `new[n](old)` to keep contents | [1.1 Dynamic arrays](../01-sv-fundamentals/01-data-types.md#dynamic-arrays-size-chosen-at-runtime) |
| `.size()` | Element count of a dynamic array or queue (`.num()` for associative arrays) | In a constraint, `arr.size()` is what the solver solves *for*; in procedural code, it is what you loop to | [1.1 Array methods](../01-sv-fundamentals/01-data-types.md#array-methods-all-three-types-plus-fixed-arrays) |
| `pkt_q[$]` | Queue: ordered, resizable list with O(1) push/pop at both ends | `[$]` is the declaration; `q[$]` in an expression means the last element. `[$:7]` bounds it at 8 | [1.1 Queues](../01-sv-fundamentals/01-data-types.md#queues-the-most-useful-type-in-the-language) |
| `.push_back(x)` | Append to the tail (`push_front`, `pop_front`, `pop_back`, `insert`, `delete`) | `pop_*` on an empty queue returns the default value and warns; check `size()` first | [1.1 Queues](../01-sv-fundamentals/01-data-types.md#queues-the-most-useful-type-in-the-language) |
| `packet p;` | A class **handle** (reference), value `null`. No object exists yet | `p.display()` on a null handle is a fatal runtime error. Assigning handles aliases objects; it does not copy them | [6.1 Classes and handles](../06-oop-and-layered-tb/01-oop-for-verification.md#classes-and-handles), [G10](../01-sv-fundamentals/06-gotchas.md#g10-class-handle-vs-object-null-aliasing-shallow-copy) |

## Class constructs

| Construct | What it is | Use it right | Explained in |
|---|---|---|---|
| `class ... endclass` | A type that bundles data and methods; instances are created with `new` and referenced through handles | Define classes in a package for reuse; inside a module only for throwaway testbenches | [6.1 OOP for verification](../06-oop-and-layered-tb/01-oop-for-verification.md), [1.5 Packages](../01-sv-fundamentals/05-modules-packages-interfaces.md) |
| `rand` | Marks a class property as a random variable that `randomize()` may change (`randc` cycles through all values before repeating) | Non-`rand` properties are *state variables*: the solver reads them but never writes them. For a `rand` array, both the size and every element are random | [5.1 Random variables](../05-constrained-random/01-randomization-and-constraints.md#random-variables) |
| `constraint name { ... }` | A named block of declarative relations the solver must satisfy on every `randomize()` | Constraints are relations, not assignments: `a == b + 1` constrains both. Name every block so tests can turn it off with `constraint_mode(0)` | [5.1 Constraint blocks](../05-constrained-random/01-randomization-and-constraints.md#constraint-blocks), [Appendix B](B-constraints-cheatsheet.md) |
| `inside {[1:64]}` | Set membership: true if the value is any listed element or falls in any `[lo:hi]` range | Works in constraints **and** in ordinary expressions (`if (op inside {ADD, SUB})`). Negate with `!(x inside {...})`. Ranges are inclusive at both ends | [5.1 Constraint blocks](../05-constrained-random/01-randomization-and-constraints.md#constraint-blocks), [1.2 Loops and flow control](../01-sv-fundamentals/02-procedural-blocks-and-assignments.md#loops-and-flow-control) |
| `function void name();` | A method that returns nothing and consumes no simulation time | Functions cannot contain `#`, `@`, or `wait`; anything that waits must be a `task`. Calling a non-void function and dropping its result warns: wrap it in `void'()` | [1.4 Functions vs. tasks](../01-sv-fundamentals/04-tasks-functions-and-scope.md#functions-vs-tasks-the-one-rule), [`void'()`](../01-sv-fundamentals/04-tasks-functions-and-scope.md#void-and-return-values) |
| `new()` | The constructor: allocates an object and returns its handle. Default one exists if you do not write `function new()` | `new()` (parentheses) constructs; `new[n]` (brackets) sizes a dynamic array; `new src` shallow-copies. Three different things that share a keyword | [6.1 Classes and handles](../06-oop-and-layered-tb/01-oop-for-verification.md#classes-and-handles), [6.1 Copying](../06-oop-and-layered-tb/01-oop-for-verification.md#copying) |
| `p.randomize()` | Built-in method: picks new values for every `rand` property satisfying all active constraints; returns 1 on success, 0 if the constraints conflict | **Check the return value.** A failed `randomize()` leaves the object unchanged and the test happily re-drives stale data. Add per-call constraints with `randomize() with { ... }` | [5.1 Calling randomize()](../05-constrained-random/01-randomization-and-constraints.md#calling-randomize), [G11](../01-sv-fundamentals/06-gotchas.md#g11-randomize-failures-ignored) |

## Procedural constructs

| Construct | What it is | Use it right | Explained in |
|---|---|---|---|
| `module ... endmodule` | The top-level container; a testbench top is a module with no ports that instantiates the DUT | Everything in a module is static: variables live for the whole simulation. Local variables in `initial` blocks go at the top of the block, before any statement | [1.5 Modules, packages, interfaces](../01-sv-fundamentals/05-modules-packages-interfaces.md) |
| `initial begin ... end` | A process that starts at time 0, runs once, and ends. `always` blocks run forever; `initial` is testbench-only | Multiple `initial` blocks start in **unspecified order**; never depend on one running first. Not synthesizable | [1.2 Processes](../01-sv-fundamentals/02-procedural-blocks-and-assignments.md#processes-the-unit-of-concurrency), [initial ordering](../01-sv-fundamentals/02-procedural-blocks-and-assignments.md#initial-ordering-and-time-zero) |
| `repeat (n) ...` | Run the body `n` times, no loop variable | `n` is evaluated once at entry. `repeat (n) @(posedge clk);` is the idiom for "wait n cycles" | [1.2 foreach and repeat](../01-sv-fundamentals/02-procedural-blocks-and-assignments.md#foreach-and-repeat-the-two-testbench-loops) |
| `foreach (arr[i]) ...` | Iterate every element of any unpacked array; the index variable is declared for you | Works on fixed, dynamic, queue, and associative arrays (key order for the last). The size is read once at loop start: do not push or delete inside the body (G16). `foreach (m[i][j])` walks two dimensions in one loop | [1.2 foreach and repeat](../01-sv-fundamentals/02-procedural-blocks-and-assignments.md#foreach-and-repeat-the-two-testbench-loops), [G16](../01-sv-fundamentals/06-gotchas.md#g16-foreach-on-a-queue-while-modifying-it) |
| `assert (expr);` | Immediate assertion: evaluates `expr` right now; a false result is reported as an assertion failure (counted, visible in coverage tools) | `assert (p.randomize())` is the idiom for "randomize and complain if it fails". Add `else $fatal(...)` when a failure should stop the run; a bare `assert` only warns and continues | [3.1 Immediate vs. concurrent](../03-sva/01-immediate-vs-concurrent.md), [5.1 Calling randomize()](../05-constrained-random/01-randomization-and-constraints.md#calling-randomize) |
| `pkt_q[i].display()` | Method call through a handle stored in a container | Every element must have been constructed (`new()`) or the call is a null dereference. A queue of handles holds references: if you pushed the same handle five times, all five "elements" are one object | [1.1 Dynamic arrays](../01-sv-fundamentals/01-data-types.md#dynamic-arrays-size-chosen-at-runtime), [G10](../01-sv-fundamentals/06-gotchas.md#g10-class-handle-vs-object-null-aliasing-shallow-copy) |

## System tasks and formatting

| Construct | What it is | Use it right | Explained in |
|---|---|---|---|
| `$display("...", args)` | Print a line to the console (and the log) immediately | Prints in the Active region, so values updated by NBAs in the same time step are not visible yet; `$strobe` prints at the end of the step. In UVM, use `` `uvm_info `` so verbosity and filtering work | [1.4 System tasks](../01-sv-fundamentals/04-tasks-functions-and-scope.md#system-tasks-you-will-use-every-day) |
| `%0d` | Decimal with no width padding | Plain `%d` pads an `int` to 11 columns. Use `%0d` everywhere unless you want aligned columns | [1.4 Format specifiers](../01-sv-fundamentals/04-tasks-functions-and-scope.md#format-specifiers) |
| `%p` | Print any aggregate (array, queue, struct, object) as an assignment pattern | The quickest debug print: no loop needed. `%0p` drops whitespace. On a class handle it prints the fields, not the address | [1.4 Format specifiers](../01-sv-fundamentals/04-tasks-functions-and-scope.md#format-specifiers) |
| `$finish;` | Terminate the simulation | In a GUI simulator it pops a confirmation dialog; scripts pass `-do "run -all; quit"` or use `$finish(0)`. UVM calls it for you after `run_phase` ends. Without `$finish`, a sim with a free-running clock never ends | [1.2 Ending a simulation](../01-sv-fundamentals/02-procedural-blocks-and-assignments.md#ending-a-simulation) |

## Constructs the example does *not* use, but you will meet next

| Construct | What it is | Explained in |
|---|---|---|
| `logic`, `bit`, `wire`, `reg` | 4-state vs 2-state, variable vs net | [1.1 Data types](../01-sv-fundamentals/01-data-types.md) |
| `always_ff`, `always_comb`, `<=` vs `=` | RTL process types, nonblocking vs blocking | [1.2 Procedural blocks](../01-sv-fundamentals/02-procedural-blocks-and-assignments.md) |
| `task`, `automatic`, `ref` | Time-consuming subroutines, re-entrancy, pass by reference | [1.4 Tasks, functions, scope](../01-sv-fundamentals/04-tasks-functions-and-scope.md) |
| `interface`, `modport`, `clocking`, `virtual interface` | Signal bundles and race-free TB access | [1.5](../01-sv-fundamentals/05-modules-packages-interfaces.md), [6.4](../06-oop-and-layered-tb/04-interfaces-bfm-and-reuse.md) |
| `fork ... join`, `join_any`, `join_none`, `disable`, `wait fork` | Threads | [6.2 Threads and IPC](../06-oop-and-layered-tb/02-threads-and-ipc.md) |
| `mailbox`, `semaphore`, `event`, `->`, `@` | Inter-process communication | [6.2 Threads and IPC](../06-oop-and-layered-tb/02-threads-and-ipc.md) |
| `extends`, `virtual`, `super`, `$cast` | Inheritance, polymorphism, downcasting | [6.1 OOP for verification](../06-oop-and-layered-tb/01-oop-for-verification.md) |
| `dist`, `->`, `solve before`, `soft`, `randc` | Constraint vocabulary | [5.1](../05-constrained-random/01-randomization-and-constraints.md), [Appendix B](B-constraints-cheatsheet.md) |
| `covergroup`, `coverpoint`, `bins`, `cross` | Functional coverage | [4.2 Covergroups](../04-coverage/02-covergroups-in-depth.md) |
| `property`, `sequence`, `\|->`, `\|=>`, `##n`, `$rose`, `$past` | Concurrent assertions | [3.2](../03-sva/02-sequences-and-properties.md), [Appendix A](A-sva-cheatsheet.md) |
| `package`, `import`, `` `include ``, `typedef`, `enum`, `struct` | Organization and user types | [1.1](../01-sv-fundamentals/01-data-types.md#structs-unions-and-typedef), [1.5](../01-sv-fundamentals/05-modules-packages-interfaces.md) |
| `$urandom`, `$urandom_range`, `$sformatf`, `$error`, `$fatal`, `$value$plusargs` | Everyday system tasks | [1.4 System tasks](../01-sv-fundamentals/04-tasks-functions-and-scope.md#system-tasks-you-will-use-every-day) |

## How to read a construct you have never seen

1. **Is it a keyword or a system task?** Keywords are bare (`foreach`); system tasks start with `$`
   (`$display`); macros start with `` ` `` (`` `uvm_info ``). The LRM (IEEE 1800-2023) has a keyword
   index in Annex B and system tasks in clauses 20 and 21.
2. **Does it consume time?** Anything with `#`, `@`, `wait`, or a `task` call can block. Functions,
   constraints, and everything in a class declaration cannot.
3. **Is it a value or a reference?** Arrays, structs, and packed types copy on assignment. Class
   handles, virtual interfaces, and mailboxes are references: assignment aliases.
4. **Is it declarative or procedural?** `constraint`, `covergroup`, `property`, and `assert property`
   describe relations the tool enforces or measures; everything inside `initial`/`always`/`task` runs
   in order.
