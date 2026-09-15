# 2.3 Templates and Patterns

These are shapes you will reuse for years. Each pattern names the DUT class it fits, the checking
strategy, and the corner cases to force.

## Pattern A: Register / datapath with enable

**Fits:** anything where `out(n+1) = f(in(n))` when enabled, else holds.

```systemverilog
module register_tb #(parameter int NUM_TESTS = 10000, parameter int WIDTH = 8);
  logic clk = 1'b0, rst, en;
  logic [WIDTH-1:0] in, out;

  register #(.WIDTH(WIDTH)) dut (.*);

  initial begin : generate_clock
    forever #5 clk = ~clk;
  end

  initial begin : stimulus
    $timeformat(-9, 0, " ns");
    rst <= 1'b1; in <= '0; en <= 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk); rst <= 1'b0;
    repeat (2) @(posedge clk);
    for (int i = 0; i < NUM_TESTS; i++) begin
      in <= $urandom; en <= $urandom;
      @(posedge clk);
    end
    $display("register_tb: done");
    disable generate_clock;
  end

  // The whole spec in three lines (chapter 3 explains each operator):
  assert property (@(posedge clk) rst |=> out == '0);                                  // reset value
  assert property (@(posedge clk) !rst && en |=> out == $past(in));                    // load
  assert property (@(posedge clk) disable iff (rst) !en |=> $stable(out));             // hold
  assert property (@(posedge clk) disable iff (rst) !$isunknown(out));                 // no X after reset
endmodule
```

**Corners to force:** enable toggling every cycle; enable held low for a long stretch; input
changing while enable is low (must be ignored); reset asserted mid-operation (add a second reset
pulse in the stimulus and confirm `out` clears).

## Pattern B: Delay line / pipeline with enable and valid

**Fits:** anything with a fixed latency L where inputs are accepted only when enabled.

Model options, from most to least explicit:

1. Queue pushed on `en`, popped on `en`, initialized with L reset values (exact, easy to read).
2. `$past(data_in, L, en)` gated history in an assertion (concise, no model).
3. Local-variable property: capture the input when accepted, wait L enables, compare (formal
   friendly).

```systemverilog
// Option 2: assertion-only pipeline testbench (Stitt's simple_pipeline template)
localparam int L = dut.LATENCY;    // or from a package function: pipe_pkg::latency(PARAMS)

function automatic logic [WIDTH-1:0] model(input logic [WIDTH-1:0] d[8]);   // ALL inputs as arguments
  logic [WIDTH-1:0] sum = '0;
  for (int i = 0; i < 4; i++) sum += d[2*i] * d[2*i+1];
  return sum;
endfunction

assert property (@(posedge clk) disable iff (rst) en[->L] |=> data_out == model($past(data_in, L, en)));
assert property (@(posedge clk) disable iff (rst) en[->L] |=> valid_out == $past(valid_in, L, en));
assert property (@(posedge clk) $fell(rst) |-> data_out == '0 throughout en[->L]);   // outputs clear until pipe fills
assert property (@(posedge clk) disable iff (rst) !en |=> $stable(data_out) && $stable(valid_out));
```

The trap in this pattern (Stitt's `_tb_bad`): a model function that reads `data_out` from module
scope instead of taking it as an argument compares the *sampled* input against the *already
updated* output. Everything an assertion evaluates must come in through the assertion's sampled
arguments.

**Corners:** `en` low for longer than L; `valid_in` low with garbage `data_in` (output data may be
don't-care; `valid_out` must still be 0); back-to-back valid; reset in the middle of the pipe being
full.

## Pattern C: FIFO / in-order buffer

See section 2.2. Queue model, invariants on `full`/`empty`, latency-aware data check, and these
covers (chapter 4): write while full, read while empty, simultaneous read and write when
`count == DEPTH-1` and when `count == 1`, fill to full then drain to empty.

## Pattern D: FSM

**Fits:** control logic with named states.

- Check the state encoding and transitions with assertions on `dut.state` (hierarchical or `bind`):
  `assert property (@(posedge clk) disable iff (rst) state == IDLE && go |=> state == RUN);` one per
  arc in the state diagram. This is tedious and it is exactly what you want: the state diagram *is*
  the spec.
- Check outputs per state: `state == DONE |-> done` (Moore), `state == RUN && cnt == 0 |-> done`
  (Mealy).
- Coverage: an enum coverpoint on `state` (all states hit) and a transition coverpoint (`bins t[] =
  (IDLE => RUN), (RUN => DONE), ...`) for all legal arcs. Illegal-transition bins turn coverage into a
  checker.
- Stimulus: random inputs *including* inputs that are "not supposed to happen" (go while running),
  because the spec says what the FSM must do then, and designers rarely test it.

## Pattern E: Handshake (go/done, req/ack, valid/ready)

**Fits:** blocks that start on a pulse and finish later; bus interfaces.

The tutorial's `bit_diff` is the go/done case. Key lessons:

- Wait for completion on **clock edges**, not on `@(posedge done)`: a combinational `done` can
  glitch, and you want to sample in the same phase as the DUT.
  `@(posedge clk iff done == 0); @(posedge clk iff done == 1);`
- The scoreboard needs the input *as of the start of the transaction*, not the input now. Capture it
  in a start monitor (or the driver) and pair it with the result from a done monitor. Two mailboxes,
  one scoreboard: the layered structure of chapter 6 falls out naturally.
- Protocol assertions: `go && done |=> !done` (done drops after a new go); `$fell(done) |-> $past(go)`
  (done only drops because of go). Valid/ready: `valid && !ready |=> valid && $stable(data)`.

**Corners:** `go` asserted while busy (must be ignored, or queued, per spec); data changed while
busy (must not affect the current result); back-to-back go; go in the same cycle as done.

## Pattern F: Multiple clock domains

Even a "basic" testbench sometimes has two clocks. Rules: one generator per clock; drive each
interface's inputs synchronously to *its* clock; never compare a signal from domain A to domain B
on the same edge; use a queue between the two sides of the scoreboard so ordering is checked, not
timing. Ratio and phase should be parameters and should be randomized in regressions.

## The pre-flight checklist

Before you trust a new testbench:

- [ ] Every DUT input driven with `<=`; reset released on `negedge`.
- [ ] `$timeformat` set; every message prints time and the relevant inputs.
- [ ] Checks use `!==`/`===` or assertions; `!$isunknown` on outputs after reset.
- [ ] A reference model that came from the spec, at transaction level where possible.
- [ ] The testbench reports PASS/FAIL in one greppable line and returns a nonzero exit or error
      count on failure.
- [ ] You broke the DUT on purpose and the testbench caught it.
- [ ] You ran it with at least two seeds (or a different `NUM_TESTS`) and it still passes.
- [ ] Corner cases from the pattern above are either forced by directed stimulus or covered (ch. 4).

## Interview angle

- "Write a testbench for a FIFO on the whiteboard." Draw Pattern C; talk through the queue, the
  three assertions, the four corners. Mention latency.
- "How do you test an FSM?" Transition assertions from the diagram, enum coverage, transition
  coverage with illegal bins, stimulus that includes illegal inputs.
- "How do you wait for `done`?" Edge-aligned `iff`, and why not `@(posedge done)`.

## Mentor's notes

- These patterns are not a substitute for reading the spec; they are the *questions you ask* the
  spec. "What is the latency? What happens on go-while-busy? What is the reset value of the
  output?" If the spec does not say, that is your first bug report.
