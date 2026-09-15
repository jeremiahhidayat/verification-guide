# 10.2 Coding Exercises

Whiteboard-style. Write your answer before reading the solution. Each solution notes the mistakes
interviewers see most.

## E1. Register with enable: testbench and assertions

**Task.** A register `out <= en ? in : out` with async active-high reset. Write a testbench that
checks it, then the same as assertions.

**Solution (procedural).**
```systemverilog
initial begin : generate_clock  forever #5 clk = ~clk; end
initial begin : stimulus
  rst <= 1; in <= 0; en <= 0; repeat (3) @(posedge clk); @(negedge clk); rst <= 0;
  repeat (1000) begin in <= $urandom; en <= $urandom; @(posedge clk); end
  disable generate_clock;
end
logic [7:0] expected = '0;
initial begin : monitor  forever begin @(posedge clk); expected <= rst ? '0 : (en ? in : out); end end
initial begin : check    forever begin @(posedge clk); if (out !== expected) $error("out=%h exp=%h", out, expected); end end
```
**Solution (SVA).**
```systemverilog
assert property (@(posedge clk) rst |=> out == '0);
assert property (@(posedge clk) !rst && en |=> out == $past(in));
assert property (@(posedge clk) disable iff (rst) !en |=> $stable(out));
assert property (@(posedge clk) disable iff (rst) !$isunknown(out));
```
**Common mistakes.** `=` on DUT inputs; `!=` instead of `!==`; checking at the same edge the input
changed; forgetting the reset check; `disable iff (rst) out == $past(in)` failing right after reset.

## E2. Write these assertions

a) `req` must be followed by `gnt` within 1 to 3 cycles, and `req` must stay high until `gnt`.
b) `gnt` never without a `req` in the previous cycle or the same cycle.
c) `valid` and `data` stable while `!ready` (AXI-style).
d) `state` is always one of three enum values and `done` is high exactly when `state == DONE`.
e) A FIFO count changes by at most 1 per cycle.
f) After `start`, `busy` rises next cycle and stays until `done`, and `done` is one cycle.

**Solutions.**
```systemverilog
// a
assert property (@(posedge clk) disable iff (rst) $rose(req) |-> req[*1:3] ##0 gnt);   // or: req |-> ##[1:3] gnt  plus  req && !gnt |=> req
// b
assert property (@(posedge clk) disable iff (rst) gnt |-> req || $past(req));
// c
assert property (@(posedge clk) disable iff (rst) valid && !ready |=> valid && $stable(data));
// d
assert property (@(posedge clk) disable iff (rst) state inside {IDLE, RUN, DONE});
assert property (@(posedge clk) disable iff (rst) done == (state == DONE));
// e
assert property (@(posedge clk) disable iff (rst) $past(count) - count inside {-1, 0, 1});   // careful: unsigned! cast:
assert property (@(posedge clk) disable iff (rst) (int'(count) - int'($past(count))) inside {[-1:1]});
// f
assert property (@(posedge clk) disable iff (rst) $rose(start) |=> busy[*1:$] ##0 done);
assert property (@(posedge clk) disable iff (rst) done |=> !done && !busy);
```
**Common mistakes.** (a) `req |-> ##[1:3] gnt` alone does not enforce holding; (e) unsigned
subtraction; (f) `busy[*1:$] ##1 done` when `done` coincides with the last busy cycle (use `##0`).

## E3. Constraints

**Task.** A packet: `len` in [1:64] with 10% chance of exactly 64 and 10% of exactly 1; `payload`
sized `len`; `kind` in {DATA, CTRL}; if CTRL then `len <= 8`; `addr` 4-byte aligned; no two
consecutive payload bytes equal.

```systemverilog
class pkt;
  rand int         len;
  rand byte        payload[];
  rand kind_t      kind;
  rand bit [31:0]  addr;
  constraint c_len  { len dist {1 := 10, [2:63] :/ 80, 64 := 10}; }
  constraint c_size { payload.size() == len; }
  constraint c_kind { kind == CTRL -> len <= 8; solve kind before len; }
  constraint c_addr { addr[1:0] == 2'b00; }
  constraint c_adj  { foreach (payload[i]) if (i > 0) payload[i] != payload[i-1]; }
endclass
```
**Common mistakes.** Forgetting `solve kind before len` (CTRL becomes rare); `:=` vs `:/`
confusion; `payload[i-1]` at `i == 0`; `addr % 4 == 0` (works but `%` is slower than a bit
constraint).

## E4. Covergroup for a FIFO

**Task.** Cover occupancy (empty, 1, mid, DEPTH-1, full), read/write enables, and the corners
write-at-full, read-at-empty, simultaneous at 1 and at DEPTH-1.

```systemverilog
covergroup cg @(posedge clk iff !rst);
  cp_cnt: coverpoint count { bins empty = {0}; bins one = {1}; bins mid = {[2:DEPTH-2]}; bins almost = {DEPTH-1}; bins full = {DEPTH}; }
  cp_wr:  coverpoint wr_en;
  cp_rd:  coverpoint rd_en;
  x: cross cp_cnt, cp_wr, cp_rd {
    bins wr_full  = binsof(cp_cnt.full)   && binsof(cp_wr) intersect {1};
    bins rd_empty = binsof(cp_cnt.empty)  && binsof(cp_rd) intersect {1};
    bins sim_1    = binsof(cp_cnt.one)    && binsof(cp_wr) intersect {1} && binsof(cp_rd) intersect {1};
    bins sim_n1   = binsof(cp_cnt.almost) && binsof(cp_wr) intersect {1} && binsof(cp_rd) intersect {1};
    ignore_bins idle = binsof(cp_wr) intersect {0} && binsof(cp_rd) intersect {0};
  }
endgroup
```

## E5. Queue-based scoreboard for an in-order pipe

```systemverilog
class sb;
  bit [31:0] exp_q[$];
  int passed, failed;
  function void on_input(bit [31:0] d);  exp_q.push_back(model(d));  endfunction
  function void on_output(bit [31:0] d);
    if (exp_q.size() == 0) begin failed++; $error("unexpected output %h", d); return; end
    if (d !== exp_q.pop_front()) failed++; else passed++;
  endfunction
  function void report();
    if (exp_q.size()) $error("%0d expected outputs never arrived", exp_q.size());
    $display("%0d passed %0d failed", passed, failed);
  endfunction
endclass
```
**Common mistakes.** Not checking for leftovers; comparing with `!=`; popping before checking
size.

## E6. Out-of-order scoreboard

Same, keyed by ID: `bit [31:0] exp[int]; on_input(id, d): exp[id] = model(d); on_output(id, d): if
(!exp.exists(id)) error; else compare, exp.delete(id);` and `exp.num()` must be 0 at the end.

## E7. Timeout around a blocking call

```systemverilog
task automatic wait_done_or_timeout(int max_cycles);
  fork begin
    fork
      @(posedge clk iff done);
      begin repeat (max_cycles) @(posedge clk); $error("timeout waiting for done"); end
    join_any
    disable fork;
  end join
endtask
```
**Common mistake.** `disable fork` without the outer `fork ... join`, killing sibling threads.

## E8. Minimal UVM driver

```systemverilog
class my_driver extends uvm_driver #(my_item);
  `uvm_component_utils(my_driver)
  virtual my_if vif;
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual my_if)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "vif")
  endfunction
  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      vif.data <= req.data; vif.valid <= 1; @(posedge vif.clk iff vif.ready); vif.valid <= 0;
      seq_item_port.item_done();
    end
  endtask
endclass
```
**Common mistakes.** Missing `super.build_phase`; missing `item_done`; raising objections in the
driver; `=` on interface signals.

## E9. Minimal UVM sequence and test

```systemverilog
class my_seq extends uvm_sequence #(my_item);
  `uvm_object_utils(my_seq)
  rand int n = 10;
  function new(string name = "my_seq"); super.new(name); endfunction
  task body();
    repeat (n) begin
      req = my_item::type_id::create("req");
      start_item(req);
      if (!req.randomize()) `uvm_fatal("RND", "")
      finish_item(req);
    end
  endtask
endclass

class my_test extends uvm_test;
  `uvm_component_utils(my_test)
  my_env env;
  function new(string name = "my_test", uvm_component parent = null); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase); super.build_phase(phase); env = my_env::type_id::create("env", this); endfunction
  task run_phase(uvm_phase phase);
    my_seq seq = my_seq::type_id::create("seq");
    phase.raise_objection(this);
    seq.start(env.agent.sequencer);
    phase.drop_objection(this);
  endtask
endclass
```

## E10. Find the bugs

```systemverilog
task check(int expected);          // (1)
  int count = 0;                   // (2)
  @(posedge clk);
  data = $random;                  // (3)(4)
  if (out != expected)             // (5)
    $display("bad");               // (6)
endtask
```
(1) static task: not re-entrant, (2) initializer runs once, (3) blocking assignment to a DUT
input, (4) `$random`, (5) `!=` misses X, (6) `$display` is not counted as an error (use
`$error`/`uvm_error`). Also: checks `out` at the same edge `data` changed.

## E11. Symbolic tracking property (formal)

**Task.** Prove every accepted write to a FIFO is read unmodified.

```systemverilog
input  logic [W-1:0] tracked;   assume property (@(posedge clk) $stable(tracked));
input  logic         start;
logic tracking; logic [AW:0] tptr;
always_ff @(posedge clk) if (rst) tracking <= 0;
  else if (!tracking && start && do_wr && wr_data == tracked) begin tracking <= 1; tptr <= wr_ptr; end
  else if (tracking && do_rd && rd_ptr == tptr) tracking <= 0;
assert property (@(posedge clk) disable iff (rst) $past(tracking && do_rd && rd_ptr == tptr) |-> rd_data == tracked);
assert property (@(posedge clk) disable iff (rst) count == wr_ptr - rd_ptr);   // helper
```

## E12. Clock generator with a parameterized period and a phase offset

```systemverilog
parameter time PERIOD = 10ns, OFFSET = 2ns;
logic clk = 0;
initial begin #OFFSET; forever #(PERIOD/2) clk = ~clk; end
```
Bonus question: what if `PERIOD/2` is not representable in the timescale precision? It rounds;
declare `timescale` with enough precision or use `realtime`.
