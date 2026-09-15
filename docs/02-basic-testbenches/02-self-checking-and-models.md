# 2.2 Self-Checking Testbenches and Reference Models

## The central question: who computes "expected"?

A testbench that prints outputs for a human to inspect is not self-checking and cannot be
regressed. A self-checking testbench needs an *oracle*: something that knows the right answer. Every
oracle is one of these:

| Oracle | Example | Strength | Weakness |
|---|---|---|---|
| **Closed-form expression** | `expected = a + b` | Trivial, exact | Only for trivially specified functions |
| **Behavioral reference model** (transaction-level) | A function/class that computes the bit-difference of a word; a queue modeling a FIFO; a C model of a codec | Independent of RTL timing, easy to write from the spec | Must be written and debugged; can share misreadings of the spec with the RTL if the same person writes both |
| **Cycle-accurate model** | A second RTL implementation, a previous tape-out, a high-level synthesis output | Catches timing-level differences | Expensive; two implementations can share bugs |
| **Properties** (assertions) | "every write is eventually read in order," "grant follows request within 4 cycles" | No model needed; checks *relationships* rather than values | Not a full functional spec; complex temporal behavior gets hard to express |
| **Invariants / end-to-end checks** | Data integrity: everything in comes out, once, in order, unmodified; checksum matches; count in == count out | Cheap, powerful, DUT-agnostic | Does not catch wrong-but-consistent behavior |
| **Golden vectors** | Recorded outputs from a known-good run | Fast to set up | Brittle; any legitimate change breaks them; tells you nothing about *why* |

Real testbenches combine several. The FIFO example below uses a queue model (behavioral), plus
invariant properties (never write when full), plus a data-integrity check.

## Rule 1: derive the model from the spec, not from the RTL

If you write `expected = dut.internal_count > 0 ? ...` you have verified that the RTL agrees with
itself. The model should be written by reading the specification and, ideally, by a different person
than the RTL author. When that is impossible (you are alone), write the model *before* reading the
RTL and in a different style (transaction-level, not cycle-level).

## Rule 2: prefer transaction-level models

A model that reproduces every cycle of the DUT is a second design, with all the same bugs. A model
that says "the k-th output word equals f(the k-th input word)" is one line and *cannot* have a
pipelining bug. The testbench's job then becomes mapping cycles to transactions, which is what
monitors do.

Example: the bit-difference FSMD from the tutorial takes `data`, runs for WIDTH cycles, asserts
`done` with `result`. The model is:

```systemverilog
function automatic int model_bit_diff(input logic [WIDTH-1:0] data);
  int diff = 0;
  for (int i = 0; i < WIDTH; i++) diff += data[i] ? 1 : -1;
  return diff;
endfunction
```

No cycles, no FSM, no `done`. The monitor waits for `done`, grabs `result`, and compares to
`model_bit_diff(data_at_start)`. That separation is the seed of driver/monitor/scoreboard.

## Queues as models: the FIFO

The FIFO is the canonical example because its spec *is* a data structure.

```systemverilog
// DUT: fifo #(WIDTH, DEPTH) with wr_en/wr_data/full and rd_en/rd_data/empty, 1-cycle read latency.
logic [WIDTH-1:0] model_q[$];
logic [WIDTH-1:0] expected_rd;

always @(posedge clk or posedge rst) begin
  if (rst) model_q.delete();
  else begin
    // Order matters only for the size check: use the size at the start of the cycle for both.
    automatic int size = model_q.size();
    if (rd_en && size > 0)      expected_rd <= model_q.pop_front();
    if (wr_en && size < DEPTH)  model_q.push_back(wr_data);
  end
end

// Invariants the model lets us state:
assert property (@(posedge clk) disable iff (rst) full  == (model_q.size() == DEPTH));
assert property (@(posedge clk) disable iff (rst) empty == (model_q.size() == 0));
assert property (@(posedge clk) disable iff (rst) rd_en && !empty |=> rd_data == expected_rd);
```

Three things to notice:

1. The model uses **blocking** operations on the queue inside one process and exposes results via
   `expected_rd <=`. Assertions sample `model_q.size()` in Preponed, before this block runs, so there is
   no race between the model update and the check.
2. `full`/`empty` are checked *every* cycle against the model, not just when they change. Continuous
   invariants are stronger than "check after a write."
3. The read-data check accounts for the DUT's 1-cycle latency with `|=>`. Latency is part of the spec.

## Scoreboards

A scoreboard is a reference model plus bookkeeping: it receives *observed inputs* (from a monitor on
the input side), computes or stores expected outputs, receives *observed outputs* (from a monitor on
the output side), compares, and counts. The word "scoreboard" comes from keeping score of
expected-vs-actual. Three flavors:

- **In-order**: expected values in a queue; each observed output pops and compares. Fits FIFOs,
  pipelines, streams.
- **Out-of-order**: expected values in an associative array keyed by an ID (tag, address, sequence
  number); each observed output looks up its key, compares, deletes. Fits memory controllers,
  network switches, anything with reordering.
- **Predictor-based**: the scoreboard *is* a model with state (a register file, a cache); observed
  inputs update the model; observed outputs are compared against model state.

```systemverilog
class scoreboard;
  int passed, failed;
  logic [31:0] expected_by_id [int];             // out-of-order example

  function void on_request(int id, logic [31:0] addr);
    expected_by_id[id] = model_read(addr);
  endfunction

  function void on_response(int id, logic [31:0] data);
    if (!expected_by_id.exists(id)) begin failed++; $error("response for unknown id %0d", id); return; end
    if (data !== expected_by_id[id]) begin failed++; $error("id %0d: got %h expected %h", id, data, expected_by_id[id]); end
    else passed++;
    expected_by_id.delete(id);
  endfunction

  function void report();
    $display("SCOREBOARD: %0d passed, %0d failed, %0d outstanding", passed, failed, expected_by_id.num());
    if (expected_by_id.num() != 0) $error("outstanding transactions at end of test");
  endfunction
endclass
```

The last line is important and often forgotten: **at end of test, the scoreboard must be empty**.
Dropped transactions are bugs too.

## End-to-end data integrity checks

Independent of any model, for any block that moves data you can check:

- Count in == count out (plus/minus what is legitimately dropped, and check *that* count too).
- Order preserved (or, for reordering blocks, each ID seen exactly once).
- Payload unmodified (or transformed by the documented function).
- No output without a corresponding input (the `expected_by_id.exists` check above).
- Nothing left in flight at the end.

These are cheap, they catch a shocking fraction of bugs, and they are what the *system-level*
scoreboard usually reduces to.

## Modeling latency and back-pressure

"The output appears LATENCY cycles after the input" is only true when the pipeline is always
enabled. With an enable or a ready/valid handshake, count *enabled cycles*, not raw cycles. Stitt's
delay testbench walks through this: `$past(data_in, CYCLES, en)` gates the history by `en`, and
`en[->CYCLES]` waits for the CYCLES-th enabled cycle. The model-based alternative is a queue that is
pushed only on accepted inputs and popped only on valid outputs; latency then never appears in the
model at all. Transaction-level modeling again.

## Golden files and log comparison

Sometimes the practical oracle is "the output must equal this file" (image processing, DSP with a
MATLAB reference). Use `$readmemh` to load expected vectors, compare element by element, and print
the first N mismatches with indexes. Regenerate the golden file with a script, never by hand, and keep
the generator in the repo.

## X-checking as a model-free oracle

`assert property (@(posedge clk) disable iff (rst) !$isunknown(out));` for every output that should
be known after reset. A model cannot express "not X"; an assertion can. It catches un-reset flops,
uninitialized memories, and out-of-range indexes, all before any functional check is even needed.

## Interview angle

- "How would you check a FIFO?" Queue model, full/empty invariants, latency-aware read check, no
  write when full, no read when empty, data integrity at end. Bonus: cover the corners (write while
  full, read while empty, simultaneous read/write at full-1 and at empty+1).
- "What is a scoreboard?" Expected vs actual with bookkeeping; in-order vs out-of-order; must be
  empty at the end.
- "How do you avoid the model having the same bug as the RTL?" Spec-derived, transaction-level,
  different author or different abstraction, plus invariants that do not need a model.

## Mentor's notes

- When the scoreboard and the DUT disagree, I look at the scoreboard first. It is smaller, and I
  wrote it faster. About a third of the time it is wrong. That is not wasted effort; every scoreboard
  bug I fix is a spec sentence I now understand better.
- Ask the designer: "what is the one internal signal that, if I could assert on it, would tell you
  the block is healthy?" Then bind an assertion to it. Designers know where their block is fragile.
