# 5.2 Advanced Constraints, Scenario Generation, and Solver Debugging

## Arrays and queues

```systemverilog
class burst;
  rand bit [7:0]  data[];
  rand bit [3:0]  strb[];
  rand int        len;

  constraint c_size   { data.size() inside {[1:16]}; strb.size() == data.size(); }   // size is constrainable
  constraint c_elems  { foreach (data[i]) data[i] != 8'hFF; }                        // per-element
  constraint c_pairs  { foreach (data[i]) if (i > 0) data[i] != data[i-1]; }         // relation between elements
  constraint c_sum    { data.sum() with (int'(item)) < 1000; }                        // reduction with widening cast
  constraint c_unique { unique {data}; }                                              // all elements distinct
  constraint c_first  { data[0] inside {[1:7]}; }                                     // index must be legal for all sizes: guard it
endclass
```

Rules of thumb:

- Always constrain `size()` explicitly (the default is unconstrained, and some tools choose 0 or
  huge sizes).
- `sum()` on 8-bit elements is computed in 8 bits unless you widen with `with (int'(item))`.
- `foreach` constraints over large arrays are expensive; keep arrays under a few hundred elements or
  randomize per-element in a loop instead (see "when not to use the solver").
- Constraining `data[5]` when size may be less than 6 fails; write `if (data.size() > 5) data[5] ...`.

The tutorial's packet sequence shows this in practice: `tdata.size() inside {[min:max]}; foreach
(tdata[i]) { tdata[i] dist {...}; tstrb[i] == '1; }`.

## Arrays of handles (randomizing a scenario)

`rand` on a class handle randomizes the *object it points to* (recursively). An array of handles
gives you a randomized list of transactions with constraints across them:

```systemverilog
class scenario;
  rand packet pkts[];
  constraint c_n   { pkts.size() inside {[2:8]}; }
  constraint c_ord { foreach (pkts[i]) if (i > 0) pkts[i].tag > pkts[i-1].tag; }   // increasing tags
  function void pre_randomize();       // objects must exist before the solver can see them
    pkts = new[8];
    foreach (pkts[i]) pkts[i] = new();
  endfunction
endclass
```

Cross-object constraints are how you express "a read after a write to the same address" or
"exactly one error in the burst." They are also where solver time explodes; keep the scenario
small and let the sequence loop over scenarios.

## Layering constraints with inheritance

```systemverilog
class packet;               constraint c_len { len inside {[4:64]}; }  endclass
class short_packet extends packet;  constraint c_len { len inside {[4:8]}; }  endclass   // OVERRIDE by same name
class err_packet   extends packet;  constraint c_err { error == 1; }         endclass   // ADD
```

A derived class constraint with the same name *replaces* the base one; a new name *adds* to it. The
factory pattern (chapter 6/7) is what makes this useful: the driver and sequencer deal in `packet`,
the test says "make every `packet` a `short_packet`," and no other code changes.

## `randcase` and `randsequence`

```systemverilog
randcase                     // weighted procedural choice; weights need not sum to 100
  70: do_read();
  25: do_write();
   5: do_idle();
endcase

randsequence (main)          // a randomized grammar: generate structured scenarios
  main    : setup traffic teardown;
  traffic : { repeat ($urandom_range(3, 10)) burst; };
  burst   : read := 3 | write := 1;
  read    : { send_read(); };
  write   : { send_write(); };
  setup   : { reset_dut(); };
  teardown: { drain(); };
endsequence
```

`randcase` is the simplest way to choose a transaction *type* in a sequence. `randsequence` is
rarely used in practice (UVM sequences with `randcase` inside cover the need) but it is the
answer to "how would you generate a random *program* of transactions."

## When not to use the solver

The solver is for *relationships*. For a plain uniform value, `$urandom_range` is faster and
simpler; for a large array of independent values, a loop of `$urandom` beats a `foreach`
constraint by orders of magnitude; for "pick one of N items" use `randcase` or `$urandom_range`
into a queue. A monitor never needs `randomize()`. The driver's inter-transaction delay is usually
`$urandom_range(min, max)` (tutorial's AXI driver), not a constrained field, unless a sequence must
control it.

## Debugging solver failures

`randomize()` returned 0. Steps:

1. **Read the tool's conflict report.** Questa (`-solvefaildebug`), VCS (`-cm_seqnoconst`... use
   `+ntb_solver_debug`), Xcelium (`-nc_solvedebug`) list a minimal conflicting subset of
   constraints. It is usually two lines that cannot both be true, often one of them an in-line
   constraint from the sequence.
2. **Look for a hidden state variable.** A non-`rand` field used in a constraint has a fixed value;
   if it was never set (`0`), `len < max_len` is unsatisfiable when `max_len == 0`.
3. **Check widths.** `bit [3:0] x; constraint { x == 16; }` is a silent conflict (16 does not fit).
   `x < 0` on an unsigned is unsatisfiable. `x inside {[a:b]}` with `a > b` is empty.
4. **Check array sizes** versus indexed constraints.
5. **Check `rand_mode`/`constraint_mode` state** left over from a previous test.
6. **Bisect**: turn off constraint blocks one at a time with `constraint_mode(0)` until it
   randomizes, then reason about the last one.

## Debugging bad distributions (it randomizes, but coverage says otherwise)

- Print a histogram: randomize 10,000 times, count values into an associative array, `$display`.
  Cheaper than a coverage run and immediate.
- Suspect implication and `->` (uniform-over-solutions effect). Add `solve before`.
- Suspect `dist` being overridden by a hard constraint elsewhere.
- Suspect `randc` with a large domain being silently downgraded.
- In UVM, suspect a *different* sequence than you think is running, or a factory override.

## Performance

- Prefer `inside {[lo:hi]}` over arithmetic expressions; prefer `dist` on small variables.
- Avoid `%`, `/`, and `*` between two random variables; solvers handle linear constraints well and
  nonlinear ones badly. `x * y == z` with all three random is a classic hang.
- Keep `foreach` over small arrays; randomize large payloads procedurally in `post_randomize`.
- Do not randomize the whole environment configuration on every transaction; randomize config once
  in the test.
- Profile: `randomize` calls per second is a tool metric; a healthy transaction takes microseconds.

## Interview angle

- "Constrain an array so its elements are unique and its sum is below N." `unique {a}; a.sum() with
  (int'(item)) < N; a.size() == K;`
- "How do you generate a random sequence of dependent transactions?" Array of handles with
  cross-object constraints, or a sequence with state and `randcase`.
- "Solver returns 0. What now?" The six steps.
- "How does inheritance interact with constraints?" Same-name override, new-name add, factory
  makes it useful.
- "When would you *not* use `randomize()`?" Independent uniform values, big payloads, monitors.

## Mentor's notes

- Every constraint gets a comment saying which spec rule or plan item it encodes. Six months later,
  "why is `len < 48`?" should not require archaeology.
- I keep a `histogram.sv` snippet that randomizes a class N times and prints the distribution of a
  field. Run it whenever you write a `dist`; the solver's idea of your intent is not always yours.
