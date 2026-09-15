// Chapter 4: a coverage module for the FIFO, bindable like the SVA checker.
// Shows: explicit bins, transition bins, ignore/illegal bins, a named cross with binsof,
// per-instance options, at_least, cover properties for scenarios, and a run-time summary.
//
// Compile: vlog -sv -mfcu +cover ../02-basic-tb/fifo.sv fifo_cov.sv fifo_cov_bind.sv ../02-basic-tb/fifo_tb.sv
// Run:     vsim -c -coverage fifo_tb -do "run -all; coverage report -details -cvg; quit"
`timescale 1ns/1ps

module fifo_cov #(
  parameter int WIDTH = 8,
  parameter int DEPTH = 16
) (
  input logic             clk, rst,
  input logic             wr_en, rd_en, full, empty,
  input logic [WIDTH-1:0] wr_data,
  input logic [$clog2(DEPTH):0] count,
  input logic             do_wr, do_rd
);
  // Occupancy "level" for transition coverage: an enum makes the report readable.
  typedef enum {LVL_EMPTY, LVL_LOW, LVL_MID, LVL_ALMOST, LVL_FULL} level_t;
  level_t level;
  always_comb begin
    if      (count == 0)         level = LVL_EMPTY;
    else if (count < 4)          level = LVL_LOW;
    else if (count < DEPTH - 1)  level = LVL_MID;
    else if (count == DEPTH - 1) level = LVL_ALMOST;
    else                         level = LVL_FULL;
  end

  covergroup cg_fifo @(posedge clk iff !rst);
    option.per_instance = 1;
    option.comment      = "VPLAN 2.x FIFO flow control";

    cp_count: coverpoint count {
      bins empty  = {0};
      bins one    = {1};
      bins mid    = {[2:DEPTH-2]};
      bins almost = {DEPTH-1};
      bins full   = {DEPTH};
      illegal_bins overflow = {[DEPTH+1:$]};      // impossible if the DUT is correct: coverage as a checker
      option.at_least = 4;
    }

    cp_level_trans: coverpoint level {
      bins fill_up[]  = (LVL_EMPTY => LVL_LOW), (LVL_LOW => LVL_MID), (LVL_MID => LVL_ALMOST), (LVL_ALMOST => LVL_FULL);
      bins drain[]    = (LVL_FULL => LVL_ALMOST), (LVL_ALMOST => LVL_MID), (LVL_MID => LVL_LOW), (LVL_LOW => LVL_EMPTY);
      bins hold_full  = (LVL_FULL => LVL_FULL);
      bins hold_empty = (LVL_EMPTY => LVL_EMPTY);
    }

    cp_wr: coverpoint wr_en { bins no = {0}; bins yes = {1}; }
    cp_rd: coverpoint rd_en { bins no = {0}; bins yes = {1}; }

    cp_wdata: coverpoint wr_data iff (do_wr) {
      bins zero      = {0};
      bins max       = {{WIDTH{1'b1}}};
      bins ranges[4] = {[1:{WIDTH{1'b1}}-1]};
    }

    // The cross is where the corners live. Name the ones from the plan; ignore the noise.
    x_ops_at_count: cross cp_count, cp_wr, cp_rd {
      bins wr_at_full     = binsof(cp_count.full)  && binsof(cp_wr.yes) && binsof(cp_rd.no);
      bins rd_at_empty    = binsof(cp_count.empty) && binsof(cp_rd.yes) && binsof(cp_wr.no);
      bins simul_at_one   = binsof(cp_count.one)    && binsof(cp_wr.yes) && binsof(cp_rd.yes);
      bins simul_at_alm   = binsof(cp_count.almost) && binsof(cp_wr.yes) && binsof(cp_rd.yes);
      bins simul_at_full  = binsof(cp_count.full)   && binsof(cp_wr.yes) && binsof(cp_rd.yes);
      bins simul_at_empty = binsof(cp_count.empty)  && binsof(cp_wr.yes) && binsof(cp_rd.yes);
      ignore_bins idle    = binsof(cp_wr.no) && binsof(cp_rd.no);
    }
  endgroup

  cg_fifo cov = new();

  // Scenario coverage: temporal, so cover properties.
  default clocking cb @(posedge clk); endclocking
  default disable iff (rst);
  cp_fill_then_drain: cover property (empty ##[1:$] full ##[1:$] empty);
  cp_burst_wr_8:      cover property (do_wr [*8]);
  cp_burst_rd_8:      cover property (do_rd [*8]);
  cp_wr_full_3:       cover property ((wr_en && full) [*3]);        // sustained back-pressure
  cp_reset_nonempty:  cover property (@(posedge clk) disable iff (1'b0) !empty ##1 rst);

  final begin
    $display("fifo_cov: covergroup coverage = %0.2f%%  (cross = %0.2f%%)",
             cov.get_inst_coverage(), cov.x_ops_at_count.get_inst_coverage());
  end
endmodule
