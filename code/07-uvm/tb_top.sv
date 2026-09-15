// Chapter 7: UVM testbench top. The static world is identical to chapter 6; only the bridge differs:
// publish the interfaces to the config_db and call run_test().
//
// Questa:  vlog -sv -mfcu +incdir+$QUESTA_HOME/verilog_src/uvm-1.2/src -f files.f
//          vsim -c tb_top +UVM_TESTNAME=fifo_random_test +UVM_VERBOSITY=UVM_LOW -do "run -all; quit"
// VCS:     vcs -sverilog -ntb_opts uvm-1.2 -f files.f && ./simv +UVM_TESTNAME=fifo_random_test
// Xcelium: xrun -uvm -f files.f +UVM_TESTNAME=fifo_random_test
`timescale 1ns/1ps

module tb_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import fifo_uvm_pkg::*;

  logic clk = 1'b0;
  logic rst;
  always #5 clk = ~clk;

  fifo_wr_if #(WIDTH) wr_if (clk, rst);
  fifo_rd_if #(WIDTH) rd_if (clk, rst);
  logic [$clog2(DEPTH):0] count;

  fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH)) dut (
    .clk, .rst,
    .wr_en(wr_if.wr_en), .wr_data(wr_if.wr_data), .full(wr_if.full),
    .rd_en(rd_if.rd_en), .rd_data(rd_if.rd_data), .empty(rd_if.empty),
    .count
  );

  initial begin : generate_reset
    rst <= 1'b1;
    repeat (5) @(posedge clk);
    @(negedge clk);
    rst <= 1'b0;
  end

  initial begin
    $timeformat(-9, 0, " ns");
    uvm_config_db#(wr_vif_t)::set(null, "uvm_test_top", "wr_vif", wr_if);
    uvm_config_db#(rd_vif_t)::set(null, "uvm_test_top", "rd_vif", rd_if);
    run_test();                                  // +UVM_TESTNAME selects the test class
  end

  // Module-level assertions route failures into the UVM error count.
  ap_full:  assert property (@(posedge clk) disable iff (rst) wr_if.full  == (count == DEPTH))
    else `uvm_error("SVA", "full flag inconsistent with count");
  ap_empty: assert property (@(posedge clk) disable iff (rst) rd_if.empty == (count == 0))
    else `uvm_error("SVA", "empty flag inconsistent with count");
endmodule
