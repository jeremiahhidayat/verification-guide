// Chapter 8: formal properties for the FIFO, in the SVA subset SymbiYosys understands and every
// commercial tool accepts. Wraps the DUT so the properties see internal signals without bind
// (SymbiYosys does not support bind; commercial tools do, so there you may use ../03-sva/fifo_bind.sv instead).
//
//   sby -f fifo.sby            (open source: yosys + SymbiYosys + yices/boolector)
//
// Structure: (1) reset behaviour, (2) local invariants, (3) helper invariants for induction,
// (4) end-to-end data integrity via a symbolic tracked write, (5) covers to prove reachability.
`timescale 1ns/1ps
`default_nettype none

module fifo_formal #(
  parameter int WIDTH = 8,
  parameter int DEPTH = 16
) (
  input  wire             clk,
  input  wire             rst,
  input  wire             wr_en,
  input  wire [WIDTH-1:0] wr_data,
  input  wire             rd_en,
  // Free inputs for the symbolic tracking (section 8.2). In every formal tool, top-level inputs are
  // unconstrained ("free"), so these need no special syntax. tracked_data is held constant by an assume.
  input  wire [WIDTH-1:0] tracked_data,
  input  wire             start
);
  localparam int AW = $clog2(DEPTH);

  wire             full, empty;
  wire [WIDTH-1:0] rd_data;
  wire [AW:0]      count;

  fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH)) dut (
    .clk, .rst, .wr_en, .wr_data, .full, .rd_en, .rd_data, .empty, .count
  );

  // Internal signals of the DUT (hierarchical reference; formal tools handle this fine).
  wire        do_wr  = dut.do_wr;
  wire        do_rd  = dut.do_rd;
  wire [AW:0] wr_ptr = dut.wr_ptr;
  wire [AW:0] rd_ptr = dut.rd_ptr;

  // ------------------------------------------------------------------------------------------
  // Reset: the tool starts with rst high; we assume it is asserted on the first cycle and then
  // free. Properties below are gated on !rst where the pre-reset state is irrelevant.
  // ------------------------------------------------------------------------------------------
  reg past_valid = 0;          // 1 after the first clock: guards $past in the first cycle
  always @(posedge clk) past_valid <= 1;

  initial assume (rst);
  am_reset_first: assume property (@(posedge clk) !past_valid |-> rst);

  // (1) reset behaviour, checked WITHOUT disable
  ap_rst_empty: assert property (@(posedge clk) past_valid && $past(rst) |-> empty && !full && count == 0);

  // ------------------------------------------------------------------------------------------
  // (2) local invariants: each is one or two cycles deep and converges immediately
  // ------------------------------------------------------------------------------------------
  ap_full_def:  assert property (@(posedge clk) disable iff (rst) full  == (count == DEPTH));
  ap_empty_def: assert property (@(posedge clk) disable iff (rst) empty == (count == 0));
  ap_not_both:  assert property (@(posedge clk) disable iff (rst) !(full && empty));
  ap_cnt_up:    assert property (@(posedge clk) disable iff (rst) past_valid && $past(do_wr && !do_rd) |-> count == $past(count) + 1);
  ap_cnt_dn:    assert property (@(posedge clk) disable iff (rst) past_valid && $past(do_rd && !do_wr) |-> count == $past(count) - 1);
  ap_cnt_same:  assert property (@(posedge clk) disable iff (rst) past_valid && $past(do_wr == do_rd) |-> $stable(count));
  ap_no_wr_full:  assert property (@(posedge clk) disable iff (rst) !(do_wr && full));
  ap_no_rd_empty: assert property (@(posedge clk) disable iff (rst) !(do_rd && empty));

  // ------------------------------------------------------------------------------------------
  // (3) helper invariants: not interesting to the spec, essential for induction to converge
  // ------------------------------------------------------------------------------------------
  ap_cnt_rng:   assert property (@(posedge clk) disable iff (rst) count <= DEPTH);
  ap_cnt_ptrs:  assert property (@(posedge clk) disable iff (rst) count == (wr_ptr - rd_ptr));

  // ------------------------------------------------------------------------------------------
  // (4) end-to-end data integrity: track ONE symbolic write and check it comes out unmodified,
  //     at the right time. Because tracked_data is free and stable, proving this proves it for
  //     every possible written value. Because start is free, it proves it for every write.
  // ------------------------------------------------------------------------------------------
  am_tracked_const: assume property (@(posedge clk) past_valid |-> $stable(tracked_data));   // one value per trace

  reg          tracking;
  reg [AW:0]   tracked_ptr;

  always @(posedge clk) begin
    if (rst) tracking <= 1'b0;
    else if (!tracking && start && do_wr && wr_data == tracked_data) begin
      tracking    <= 1'b1;
      tracked_ptr <= wr_ptr;
    end else if (tracking && do_rd && rd_ptr == tracked_ptr) begin
      tracking    <= 1'b0;
    end
  end

  // While tracked, the entry is still inside the FIFO: its slot has not been re-used.
  ap_tracked_inside: assert property (@(posedge clk) disable iff (rst)
      tracking |-> (tracked_ptr - rd_ptr) < count);

  // When the tracked entry is read, the data one cycle later is what we wrote.
  ap_e2e: assert property (@(posedge clk) disable iff (rst)
      past_valid && $past(tracking && do_rd && rd_ptr == tracked_ptr) |-> rd_data == tracked_data);

  // ------------------------------------------------------------------------------------------
  // (5) covers: reachability. If any of these is unreachable, the setup is over-constrained.
  // ------------------------------------------------------------------------------------------
  cp_full:      cover property (@(posedge clk) !rst && full);
  cp_wr_full:   cover property (@(posedge clk) !rst && wr_en && full);
  cp_rd_empty:  cover property (@(posedge clk) !rst && rd_en && empty);
  cp_simul_1:   cover property (@(posedge clk) !rst && do_wr && do_rd && count == 1);
  cp_simul_n1:  cover property (@(posedge clk) !rst && do_wr && do_rd && count == DEPTH - 1);
  cp_tracked_rd: cover property (@(posedge clk) !rst && tracking && do_rd && rd_ptr == tracked_ptr);
  cp_fill_drain: cover property (@(posedge clk) !rst && full ##[1:$] empty);
endmodule
`default_nettype wire
