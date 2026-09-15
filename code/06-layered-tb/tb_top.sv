// Chapter 6: top level. Static world (interfaces, DUT, clock, reset) plus a bridge into the
// dynamic world (construct the environment and the selected test).
//
// Compile: vlog -sv ../02-basic-tb/fifo.sv fifo_if.sv fifo_tb_pkg.sv tb_top.sv
// Run:     vsim -c tb_top +TEST=random     -do "run -all; quit"
//          vsim -c tb_top +TEST=fill_drain -do "run -all; quit"
`timescale 1ns/1ps

module tb_top;
  import fifo_tb_pkg::*;

  logic clk = 1'b0;
  logic rst;
  always #5 clk = ~clk;

  fifo_wr_if #(WIDTH) wr_if (clk, rst);
  fifo_rd_if #(WIDTH) rd_if (clk, rst);

  logic full_unused, empty_unused;
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

  initial begin : run_test
    automatic string test_name = "random";
    environment env;
    base_test   test;

    $timeformat(-9, 0, " ns");
    void'($value$plusargs("TEST=%s", test_name));
    env = new(wr_if, rd_if);

    case (test_name)
      "random":     test = random_test::new(env);
      "fill_drain": test = fill_drain_test::new(env);
      default: $fatal(1, "unknown +TEST=%s", test_name);
    endcase

    @(negedge rst);
    fork
      test.run();
      begin #1ms; $fatal(1, "global timeout"); end     // a hang must fail, not run forever
    join_any
    disable fork;

    test.report();
    $finish;
  end

  // The full/empty consistency checks from chapter 3, kept here because they need 'count'.
  ap_full:  assert property (@(posedge clk) disable iff (rst) wr_if.full  == (count == DEPTH));
  ap_empty: assert property (@(posedge clk) disable iff (rst) rd_if.empty == (count == 0));
endmodule
