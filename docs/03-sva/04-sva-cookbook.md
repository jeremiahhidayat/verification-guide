# 3.4 SVA Cookbook

Copy these, rename the signals, and read each one aloud against your spec. All assume
`@(posedge clk) disable iff (rst)` unless stated (abbreviated below as `@clk`).

## Basic invariants

```systemverilog
// Never X after reset
ap_no_x:      assert property (@clk !$isunknown({valid, data}));

// One-hot / at most one
ap_onehot:    assert property (@clk $onehot(grant));
ap_onehot0:   assert property (@clk $onehot0(grant));          // zero or one

// Mutual exclusion
ap_mutex:     assert property (@clk !(rd_en && wr_en));

// Range
ap_range:     assert property (@clk count <= DEPTH);

// Relationship between flags and state
ap_full_def:  assert property (@clk full  == (count == DEPTH));
ap_empty_def: assert property (@clk empty == (count == 0));
```

## Handshakes

```systemverilog
// Request gets a response within [1:N]
ap_resp:      assert property (@clk req |-> ##[1:N] ack);

// Request held until acknowledged (valid/ready style)
ap_hold:      assert property (@clk valid && !ready |=> valid);
ap_hold_data: assert property (@clk valid && !ready |=> $stable(data));

// Combined AXI-style: once valid rises, it stays with stable payload until the handshake
ap_axi:       assert property (@clk $rose(valid) |-> (valid && $stable(data)) [*0:$] ##1 ready);
// Simpler and common: if valid fell, the previous cycle must have had ready
ap_axi2:      assert property (@clk $fell(valid) |-> $past(ready));

// No ack without a request
ap_no_spur:   assert property (@clk ack |-> $past(req, 1) || $past(req, 2));   // or track with a local var

// Exactly one ack per req (no double ack)
ap_one_ack:   assert property (@clk $rose(ack) |=> !ack [*1:$] ##0 req);   // no second ack until another req... adapt

// go/done FSMD
ap_done_drop: assert property (@clk go && done |=> !done);
ap_done_only_on_go: assert property (@clk $fell(done) |-> $past(go));
```

## Stability and change

```systemverilog
ap_stable_cfg:  assert property (@clk busy |-> $stable(config_reg));        // no config change while busy
ap_no_glitch:   assert property (@clk $changed(x) |=> $stable(x) [*MIN_HOLD-1]);  // x holds at least MIN_HOLD cycles
ap_toggle:      assert property (@clk $rose(en) |=> $fell(en) [->1] within ... );  // rarely needed; use covers instead
```

## Latency and pipelines

```systemverilog
// Fixed latency L, always enabled
ap_lat:   assert property (@clk valid_in |-> ##L valid_out);
ap_data:  assert property (@clk valid_in |-> ##L data_out == f($past(data_in, L)));

// With enable: count enabled cycles
ap_lat_en:  assert property (@clk en[->L] |=> valid_out == $past(valid_in, L, en));
ap_data_en: assert property (@clk en[->L] |=> data_out == f($past(data_in, L, en)));

// Forward-looking with a local variable (formal friendly)
property p_data_fwd;
  logic [W-1:0] exp;
  @clk (valid_in && en, exp = f(data_in)) |-> en[->L] ##1 data_out == exp;
endproperty

// Output stalls when not enabled
ap_stall: assert property (@clk !en |=> $stable({valid_out, data_out}));

// Reset clears the pipeline until it refills
ap_flush: assert property (@(posedge clk) $fell(rst) |-> !valid_out throughout en[->L]);
```

## Counters

```systemverilog
ap_inc:   assert property (@clk en && !clr |=> cnt == $past(cnt) + 1);
ap_clr:   assert property (@clk clr |=> cnt == 0);
ap_hold:  assert property (@clk !en && !clr |=> $stable(cnt));
ap_wrap:  assert property (@clk en && cnt == MAX |=> cnt == 0);
```

## FIFO (pins-only)

```systemverilog
ap_no_wr_full:  assert property (@clk wr_en && full  |=> $stable(count) || (rd_en_prev));  // adapt to spec: ignored vs error
ap_no_rd_empty: assert property (@clk rd_en && empty |=> $stable(count));
ap_count_up:    assert property (@clk wr_en && !full && !(rd_en && !empty) |=> count == $past(count) + 1);
ap_count_dn:    assert property (@clk rd_en && !empty && !(wr_en && !full) |=> count == $past(count) - 1);
ap_count_same:  assert property (@clk (wr_en && !full) == (rd_en && !empty) |=> $stable(count));
// Data ordering: use a queue model (chapter 2) or the tagged local-variable property (3.2).
```

## Arbiter

```systemverilog
ap_grant_req:   assert property (@clk grant[i] |-> req[i]);                       // never grant a non-requester (per i via generate)
ap_onehot:      assert property (@clk $onehot0(grant));
ap_fair:        assert property (@clk req[i] |-> ##[1:N_REQ] grant[i]);           // bounded starvation
ap_rr:          assert property (@clk grant[i] && req[i+1] |=> grant[i+1]);      // round-robin next (adapt)
```

Generate loops make per-index properties:

```systemverilog
for (genvar i = 0; i < N; i++) begin : g_req
  ap_gr: assert property (@clk grant[i] |-> req[i]);
end
```

## FSM

```systemverilog
ap_t_idle_run:  assert property (@clk state == IDLE && start |=> state == RUN);
ap_t_run_done:  assert property (@clk state == RUN && cnt == 0 |=> state == DONE);
ap_t_done_idle: assert property (@clk state == DONE |=> state == IDLE);
ap_legal:       assert property (@clk state inside {IDLE, RUN, DONE});
ap_out_done:    assert property (@clk done == (state == DONE));                   // Moore output
```

## Clock domain crossing (handshake style)

```systemverilog
// 4-phase: req rises, eventually ack rises; req falls only after ack; ack falls only after req
ap_cdc1: assert property (@(posedge clk_src) $rose(req) |-> req until_with ack_sync);
ap_cdc2: assert property (@(posedge clk_src) $fell(req) |-> $past(ack_sync));
// Data stable while req high
ap_cdc3: assert property (@(posedge clk_src) req |-> $stable(data));
// Gray code: at most one bit changes per cycle
ap_gray: assert property (@(posedge clk) $countones(ptr ^ $past(ptr)) <= 1);
```

## Memory / register

```systemverilog
// Write then read returns the written data (no intervening write to same address): local variables
property p_wr_rd;
  logic [AW-1:0] a; logic [DW-1:0] d;
  @clk (we, a = addr, d = wdata) |=> (!(we && addr == a)) [*0:$] ##1 (re && addr == a) |-> ##RD_LAT rdata == d;
endproperty
```

(This is the shape; for real memories use a model.)

## Using `bind`

```systemverilog
// fifo_sva.sv
module fifo_sva #(parameter int DEPTH = 16) (
  input logic clk, rst, wr_en, rd_en, full, empty,
  input logic [$clog2(DEPTH):0] count);
  default clocking cb @(posedge clk); endclocking      // default clock for all properties below
  default disable iff (rst);                           // default reset
  ap_full:  assert property (full  == (count == DEPTH));
  ap_empty: assert property (empty == (count == 0));
  ap_cnt:   assert property (count <= DEPTH);
  cp_full:  cover  property (full);
endmodule

// bind file (compile with the DUT; no RTL edits)
bind fifo fifo_sva #(.DEPTH(DEPTH)) u_fifo_sva (.*);   // .* binds to fifo's ports AND internal signals by name
```

`default clocking` and `default disable iff` remove the repetition in checker modules.

## Cover properties worth having on every design

```systemverilog
cp_reset_mid:   cover property (@(posedge clk) !rst ##[1:$] rst ##[1:$] !rst);   // reset asserted mid-test
cp_back2back:   cover property (@clk valid && ready [*4]);                       // sustained throughput
cp_stall_long:  cover property (@clk valid && !ready [*8]);                      // long back-pressure
cp_full_drain:  cover property (@clk full ##[1:$] empty);                        // full then drained
```

## Interview angle

Expect to write two or three of these on a whiteboard, then be asked to modify them ("now the ack
must come within 4 cycles *and* the request must stay high," "now there is an enable"). Practice
saying the English first, then writing the operator.

## Mentor's notes

- The vendor checker libraries (Questa QVL, VCS VCS-AIP/OVL, Xcelium IAL) implement most of this
  cookbook with parameters and better failure messages. Use them for standard interfaces; write your
  own for anything design-specific.
- Keep protocol assertions in the interface file; keep white-box assertions in a bound module named
  `<block>_sva.sv`. The formal team will thank you: they can turn the interface assertions into
  assumptions on the other side.
