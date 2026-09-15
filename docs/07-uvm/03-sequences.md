# 7.3 Sequences in Depth

## What a sequence is

A `uvm_sequence #(REQ, RSP)` is an object with a `body()` task that produces items and sends them to
a sequencer. It is the generator of chapter 6 made composable: sequences can call other sequences,
run in parallel on the same sequencer, be parameterized, randomized, and layered from beat level up
to "run the whole test."

```systemverilog
class fifo_wr_seq extends uvm_sequence #(fifo_wr_item);
  `uvm_object_utils(fifo_wr_seq)
  rand int n;
  constraint c_n { n inside {[1:100]}; }

  function new(string name = "fifo_wr_seq"); super.new(name); endfunction

  virtual task body();
    repeat (n) begin
      req = fifo_wr_item::type_id::create("req");       // factory: a test can override the item type
      start_item(req);                                   // wait for the sequencer to grant us the driver
      if (!req.randomize() with { data != 8'h00; }) `uvm_fatal("RND", "randomize failed")
      finish_item(req);                                  // hand to the driver; returns after item_done
    end
  endtask
endclass
```

Start it: `seq.start(sequencer)` (blocks until `body` returns). From a test, inside
`raise/drop_objection`.

## The item lifecycle

```
sequence                    sequencer                 driver
   |-- start_item(req) ------> arbitrate, grant ----->|
   |   (randomize here: late randomization sees the latest state)
   |-- finish_item(req) -----> queue item -----------> get_next_item(req)
   |                                                  drive...
   |<-- finish_item returns <-- item_done() <---------- item_done()
```

Randomize *between* `start_item` and `finish_item` ("late randomization"): by the time the sequencer
grants, other sequences may have changed shared state, and you want the freshest constraints.

The `` `uvm_do(req) `` family of macros wraps create/start/randomize/finish in one line
(`uvm_do_with(req, {data > 4;})`, `uvm_do_on(req, other_sqr)`). They are convenient, hide the
lifecycle, and make it awkward to check `randomize()` return values or to set fields before
randomization. Most style guides prefer the explicit form; know both.

The tutorial's sequences use the older `wait_for_grant()` / `send_request()` /
`wait_for_item_done()` triple, which is exactly what `start_item`/`finish_item` call internally.

## Responses

If the driver must return data (a read transaction), it fills `rsp` and calls
`seq_item_port.put(rsp)` (or `item_done(rsp)`); the sequence calls `get_response(rsp)` after
`finish_item`. Set `rsp.set_id_info(req)` so responses match requests. Alternatively, have the
driver write the result into the *same* `req` object before `item_done` (the sequence still holds
the handle), which is simpler and common for in-order protocols.

## Nested sequences

A sequence can start other sequences on its own sequencer:

```systemverilog
virtual task body();
  fifo_wr_seq fill  = fifo_wr_seq::type_id::create("fill");
  fifo_wr_seq drain = fifo_wr_seq::type_id::create("drain");
  if (!fill.randomize() with { n == 16; }) ...
  fill.start(m_sequencer, this);       // this = parent sequence; m_sequencer = the one we run on
  ...
endtask
```

`` `uvm_do(subseq) `` also works for sequences. Nesting is how you build scenario libraries: `reset_seq`,
`config_seq`, `fill_seq`, `drain_seq`, then `full_traffic_seq` composed of them.

## Virtual sequences and virtual sequencers

A DUT with two interfaces needs coordinated stimulus on both (fill from the write side while
throttling the read side). A **virtual sequence** runs on a **virtual sequencer** that holds handles
to the real sequencers and starts sub-sequences on them:

```systemverilog
class fifo_vsequencer extends uvm_sequencer;          // no item type: it never drives
  `uvm_component_utils(fifo_vsequencer)
  fifo_wr_sequencer wr_sqr;                           // set by the env in connect_phase
  fifo_rd_sequencer rd_sqr;
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
endclass

class fifo_fill_drain_vseq extends uvm_sequence;
  `uvm_object_utils(fifo_fill_drain_vseq)
  `uvm_declare_p_sequencer(fifo_vsequencer)           // gives 'p_sequencer' typed as fifo_vsequencer

  virtual task body();
    fifo_wr_seq wr = fifo_wr_seq::type_id::create("wr");
    fifo_rd_seq rd = fifo_rd_seq::type_id::create("rd");
    if (!wr.randomize() with { n == 20; gap == 0; }) ...
    wr.start(p_sequencer.wr_sqr, this);               // fill (4 writes rejected)
    if (!rd.randomize() with { n == 20; }) ...
    rd.start(p_sequencer.rd_sqr, this);               // drain (4 reads rejected)
    fork                                              // then concurrent traffic
      begin wr = ...; wr.start(p_sequencer.wr_sqr, this); end
      begin rd = ...; rd.start(p_sequencer.rd_sqr, this); end
    join
  endtask
endclass
```

The test starts one virtual sequence; the virtual sequence is the *scenario*. Without a virtual
sequencer you can still do this from the test with `fork` (tutorial's `mult_simple_test`), which is
fine for simple cases; the virtual sequence makes scenarios reusable objects and keeps tests tiny.

## Arbitration and priorities

When several sequences run on one sequencer concurrently, the sequencer picks the next item by
arbitration mode: `UVM_SEQ_ARB_FIFO` (default), `RANDOM`, `STRICT_FIFO`, `STRICT_RANDOM`,
`WEIGHTED`, `USER`. Set with `sequencer.set_arbitration(...)`; priorities via `start(..., priority)`
and `uvm_do_pri`. `lock()`/`grab()` give a sequence exclusive access (grab jumps the queue). Used for
interrupt-style sequences that must preempt background traffic.

## Sequence libraries and randomly chosen sequences

`uvm_sequence_library` holds registered sequence types and runs a random selection with a chosen
mode (random, cyclic, item). Handy for "run 50 random scenarios from this menu." A plain `randcase`
in a wrapper sequence does the same with less machinery.

## Configuration from a sequence

Sequences are objects, not components; `uvm_config_db::get(this, "", ...)` in a sequence uses the
sequence's context via `m_sequencer` (or `null` + full name). Tutorial pattern:

```systemverilog
if (!uvm_config_db#(int)::get(null, get_full_name(), "num_tests", num_tests))   // or get(m_sequencer, ...)
```

Better practice: put knobs in a config *object* set once by the test, retrieved by the sequence
(7.5), or make the knobs `rand` fields of the sequence constrained in-line by the test.

## Reset, and sequences that must survive it

If reset can occur mid-test, the driver must abort the current item and the sequence must be
killed or restarted (`seq.kill()`, or run sequences in a `fork` that a reset monitor disables).
UVM 1.2's run-time phases (`reset_phase`, `main_phase`) and phase jumping (`phase.jump(uvm_reset_phase::get())`)
formalize this; many teams handle it with a reset-aware driver plus a `reset_seq` instead. Decide
early; retrofitting reset-in-the-middle into a testbench is painful.

## Interview angle

- "Walk through `start_item`/`finish_item`." And why randomize between them.
- "What is a virtual sequence and when do you need one?" Multi-interface coordination.
- "How do you get a response from the driver?" `rsp` with `set_id_info`, or write into `req`.
- "How would you make a background traffic sequence yield to an interrupt sequence?" `grab`/
  priorities/arbitration.
- "Sequence vs test: where does the scenario belong?" Sequence (reusable); test selects and
  configures.

## Mentor's notes

- Every sequence gets `rand` knobs with sane default constraints and a `convert2string` that prints
  them at `UVM_LOW` on start. When a regression fails, the log should say which scenario ran with
  which knobs.
- Resist putting checking in sequences. A sequence that "checks the response" is a sequence that
  cannot be reused in passive mode. Check in the scoreboard.
