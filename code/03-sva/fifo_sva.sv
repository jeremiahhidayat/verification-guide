// Chapter 3: a bound assertion module for the FIFO (white-box + pins), plus cover properties.
// Compile with the DUT and the bind file:
//   vlog -sv ../02-basic-tb/fifo.sv fifo_sva.sv fifo_bind.sv ../02-basic-tb/fifo_tb.sv
//   vsim -c fifo_tb -do "run -all; quit"
// Because it is bound, fifo_tb needs no changes. Every instance of `fifo` gets one u_fifo_sva.
`timescale 1ns/1ps

module fifo_sva #(
  parameter int WIDTH = 8,
  parameter int DEPTH = 16
) (
  input logic             clk, rst,
  input logic             wr_en, rd_en, full, empty,
  input logic [WIDTH-1:0] wr_data, rd_data,
  input logic [$clog2(DEPTH):0] count,
  // internal signals of fifo, reachable because bind places this module inside fifo's scope
  input logic             do_wr, do_rd,
  input logic [$clog2(DEPTH):0] wr_ptr, rd_ptr
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (rst);

  // ---- flag/state consistency (white-box) ----
  ap_full_def:   assert property (full  == (count == DEPTH))
    else $error("full=%b but count=%0d", $sampled(full), $sampled(count));
  ap_empty_def:  assert property (empty == (count == 0))
    else $error("empty=%b but count=%0d", $sampled(empty), $sampled(count));
  ap_count_def:  assert property (count == (wr_ptr - rd_ptr));
  ap_count_rng:  assert property (count <= DEPTH);
  ap_no_x:       assert property (!$isunknown({full, empty, count, wr_ptr, rd_ptr}));

  // ---- count arithmetic from the pins ----
  ap_cnt_up:     assert property (do_wr && !do_rd |=> count == $past(count) + 1);
  ap_cnt_dn:     assert property (do_rd && !do_wr |=> count == $past(count) - 1);
  ap_cnt_same:   assert property (do_wr == do_rd  |=> $stable(count));

  // ---- misuse is ignored, not fatal ----
  ap_wr_full_ign:  assert property (wr_en && full && !rd_en |=> $stable(count) && $stable(wr_ptr));
  ap_rd_empty_ign: assert property (rd_en && empty && !wr_en |=> $stable(count) && $stable(rd_ptr));

  // ---- read data: tagged forward-looking property (Ben Cohen's ordering technique) ----
  int tag = 0, serving = 0;
  function void inc_tag();     tag++;     endfunction
  function void inc_serving(); serving++; endfunction

  property p_order;
    int wr_tag;
    logic [WIDTH-1:0] d;
    (do_wr, wr_tag = tag, inc_tag(), d = wr_data)
      |-> first_match(##[1:$] (do_rd && serving == wr_tag, inc_serving()))
          ##1 rd_data == d;
  endproperty
  ap_order: assert property (p_order)
    else $error("FIFO ordering violated: rd_data=%h", $sampled(rd_data));

  // ---- reset behaviour (checked with reset NOT disabled) ----
  ap_rst: assert property (@(posedge clk) disable iff (1'b0) rst |=> empty && !full && count == 0);

  // ---- covers: did the stimulus reach the corners? ----
  cp_full:        cover property (full);
  cp_wr_at_full:  cover property (wr_en && full);
  cp_rd_at_empty: cover property (rd_en && empty);
  cp_simul_1:     cover property (do_wr && do_rd && count == 1);
  cp_simul_n1:    cover property (do_wr && do_rd && count == DEPTH - 1);
  cp_fill_drain:  cover property (empty ##[1:$] full ##[1:$] empty);
  cp_wrap:        cover property ($past(wr_ptr[$clog2(DEPTH)-1:0]) == DEPTH-1 && wr_ptr[$clog2(DEPTH)-1:0] == 0);
endmodule
