# 4.2 Covergroups in Depth

## Anatomy

```systemverilog
covergroup cg_fifo @(posedge clk);            // sampling event: every clock edge
  option.per_instance = 1;                     // report each instance separately
  option.name = "fifo_cov";

  cp_count: coverpoint count {                 // a variable (or expression) to bin
    bins empty     = {0};
    bins low       = {[1:3]};
    bins mid       = {[4:DEPTH-2]};
    bins almost    = {DEPTH-1};
    bins full      = {DEPTH};
    option.at_least = 5;                       // a bin counts as covered after 5 hits
  }

  cp_wr: coverpoint wr_en { bins yes = {1}; bins no = {0}; }
  cp_rd: coverpoint rd_en { bins yes = {1}; bins no = {0}; }

  x_ops_at_count: cross cp_wr, cp_rd, cp_count {      // every combination of the three
    ignore_bins  no_op   = binsof(cp_wr.no) && binsof(cp_rd.no);   // idle cycles: not interesting
    illegal_bins bad     = binsof(cp_count.full) && binsof(cp_wr.yes) && ... ; // if the spec forbids it
  }
endgroup

cg_fifo cov = new();                           // instantiate (in a module: at elaboration; in a class: in new())
```

Concepts, one at a time.

## Sampling

Three ways to say *when* the values are captured:

1. **Clocking event in the declaration**: `covergroup cg @(posedge clk);` samples every edge.
   Simple; can over-sample (idle cycles inflate "no-op" bins; use `iff`).
2. **Explicit `sample()` call**: `covergroup cg; ... endgroup` then `cov.sample();` from a monitor
   when a transaction completes. This is the UVM style: sample *transactions*, not cycles.
3. **`with function sample(args)`**: pass values in, so the covergroup does not need visibility of the
   variables: `covergroup cg with function sample(bit [7:0] d, bit last);`. Needed when the
   covergroup is declared outside the class that holds the data, and for reusable coverage
   components.

Conditional sampling per coverpoint: `coverpoint x iff (!rst && valid)`.

## Bins

A coverpoint divides the variable's value space into bins. Each bin has a hit count; the coverpoint
is covered when every (non-ignored) bin reaches `at_least`.

```systemverilog
coverpoint addr {
  bins zero      = {0};                          // one value
  bins low[]     = {[1:15]};                     // [] : one bin PER value (15 bins)
  bins ranges[4] = {[16:255]};                   // split the range into 4 equal bins
  bins high      = {[256:$]};                    // $ : max value of the type
  bins evens     = {[0:$]} with (item % 2 == 0); // filter by expression
  wildcard bins  top = {8'b1???_????};           // ? matches 0/1
  ignore_bins    reserved = {[200:210]};         // excluded from the space and from the percentage
  illegal_bins   never    = {255};               // hitting it is an ERROR (coverage as a checker)
  bins others    = default;                      // everything not otherwise binned (not counted in coverage)
}
```

Without explicit bins, the tool creates automatic bins: up to `option.auto_bin_max` (default 64)
equal ranges. For a 1-bit signal that is two bins; for an enum, one per member; for a 32-bit value,
64 ranges of 2^26 each, which is almost never what you want. **Auto bins are for quick looks; the
plan wants explicit bins with names.**

### Transition bins

```systemverilog
coverpoint state {
  bins legal[]  = (IDLE => RUN), (RUN => DONE), (DONE => IDLE), (RUN => RUN);
  bins run_to_done_via_stall = (RUN => STALL[*1:5] => DONE);   // with repetition
  illegal_bins bad = (IDLE => DONE), (DONE => RUN);
}
```

Transition coverage of an FSM is the closest thing to "prove every arc of the diagram was taken."
`illegal_bins` on forbidden arcs turns the coverpoint into an FSM checker for free.

## Cross coverage

A cross creates one bin per *combination* of the bins of its coverpoints. That is the point: bugs
live in combinations (chapter 0). Three coverpoints of 5, 2, 2 bins cross to 20 bins.

```systemverilog
x_ops: cross cp_count, cp_wr, cp_rd {
  bins wr_at_full  = binsof(cp_count.full) && binsof(cp_wr.yes);
  bins rd_at_empty = binsof(cp_count.empty) && binsof(cp_rd.yes);
  ignore_bins idle = binsof(cp_wr.no) && binsof(cp_rd.no);
}
```

Named cross bins with `binsof` let you call out the corners you care about and ignore the rest. A
cross of two 64-auto-bin coverpoints is 4096 bins and will never close: cross *small, meaningful*
bins only.

## Options

| Option | Scope | Meaning |
|---|---|---|
| `option.per_instance = 1` | covergroup | Keep per-instance data (otherwise merged per type) |
| `option.at_least = N` | cg / cp / cross | Hits required for a bin to count |
| `option.auto_bin_max = N` | cp | Max automatic bins |
| `option.weight = W` | cg / cp / cross | Weight in the parent's percentage (0 to exclude helper points) |
| `option.goal = P` | cg / cp | Target percentage |
| `option.comment = "..."` | any | Text in the report: link to the plan item |
| `option.cross_num_print_missing` | cross | How many missing cross bins to list |
| `type_option.merge_instances = 1` | cg | Merge instance data into the type view |

`get_coverage()` / `get_inst_coverage()` return the percentage at run time, which is how a test can
print a summary or a reactive sequence can steer.

## Where covergroups live

| Location | Sampling | Use |
|---|---|---|
| Module / interface (static) | Clock event or explicit call | Cycle-level coverage of pins; quick module testbenches; bindable coverage |
| Class, embedded (`covergroup cg; ... endgroup` inside a class; instance auto-declared as `cg`) | `cg.sample()` from a method | Transaction coverage in monitors / subscribers; the UVM norm |
| Class, external with `with function sample` | Explicit args | Reusable coverage for multiple instances or widths (Stitt's `toggle_coverage` example) |

An embedded covergroup must be constructed in the class constructor (`cg = new();`). A covergroup
declared *outside* a class cannot be parameterized, so for width-parameterized coverage wrap it in a
parameterized class (tutorial's `accum_coverage.svh`).

## Cover properties vs. covergroups

| | `cover property` | `covergroup` |
|---|---|---|
| Measures | A temporal sequence completed | Values and combinations at sample points |
| Example | "full, then eventually empty" | "count was in each of 5 ranges while wr_en" |
| Reporting | Hit count per property | Per bin, with percentage and cross matrix |
| Best for | Scenarios, protocol sequences, reachability | Data distribution, configuration combos, FSM |

Use both. A plan item like "burst of 4 back-to-back writes at count >= DEPTH-4" is a cover property;
"all combinations of burst length x starting count" is a cross.

## Example: a coverage class for the FIFO

```systemverilog
class fifo_coverage;
  // transaction-level view supplied by the monitor
  bit       wr, rd, full, empty;
  int       count;
  bit [7:0] wdata;

  covergroup cg;
    option.per_instance = 1;
    cp_count: coverpoint count {
      bins empty = {0}; bins one = {1}; bins mid = {[2:DEPTH-2]}; bins almost = {DEPTH-1}; bins full = {DEPTH};
    }
    cp_wr:    coverpoint wr;
    cp_rd:    coverpoint rd;
    cp_wdata: coverpoint wdata { bins zero = {0}; bins max = {8'hFF}; bins ranges[4] = {[1:8'hFE]}; }
    x_ops:    cross cp_count, cp_wr, cp_rd { ignore_bins idle = binsof(cp_wr) intersect {0} && binsof(cp_rd) intersect {0}; }
  endgroup

  function new(); cg = new(); endfunction
  function void sample(bit wr_, bit rd_, int count_, bit [7:0] wdata_);
    wr = wr_; rd = rd_; count = count_; wdata = wdata_;
    cg.sample();
  endfunction
endclass
```

The cross `x_ops` is the whole point: `wr && full`, `rd && empty`, `wr && rd && count == 1`,
`wr && rd && count == DEPTH-1` are all bins of it. When you look at the cross report and see those
four at zero, you know exactly which constraints to bias.

## Interview angle

- "How do you write a covergroup for an FSM?" Enum coverpoint plus transition bins plus
  `illegal_bins`.
- "What is a cross and why?" Combinations; bugs live there; keep crossed points small.
- "How do you sample transaction coverage in UVM?" Subscriber/analysis port -> `cg.sample()` in
  `write()`. Chapter 7.
- "`ignore_bins` vs `illegal_bins`?" Excluded from the count vs. an error when hit.

## Mentor's notes

- Name every bin. `bin auto[3]` in a report means nothing at 2 a.m.; `bin wr_at_full` does.
- Put a `option.comment = "VPLAN 3.2.1"` on each coverpoint. Linking plan and coverage by hand is
  the alternative, and nobody keeps it up to date.
