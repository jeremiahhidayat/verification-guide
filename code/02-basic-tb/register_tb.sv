// Chapter 2, pattern A: register with enable, three checking styles side by side.
// Compile: vlog -sv register_tb.sv ; Run: vsim -c register_tb -do "run -all; quit"
`timescale 1ns/1ps

module register #(parameter int WIDTH = 8) (
  input  logic clk, rst, en,
  input  logic [WIDTH-1:0] in,
  output logic [WIDTH-1:0] out
);
  always_ff @(posedge clk or posedge rst)
    if (rst) out <= '0;
    else if (en) out <= in;
endmodule

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
      in <= $urandom;
      en <= $urandom;
      @(posedge clk);
    end
    $display("register_tb: done");
    disable generate_clock;
  end

  // Style 1: monitor computes expected from pre-edge values; checker compares next edge.
  logic [WIDTH-1:0] expected = '0;
  initial begin : monitor
    forever begin
      @(posedge clk);
      expected <= rst ? '0 : (en ? in : out);
    end
  end
  initial begin : check_output
    forever begin
      @(posedge clk);
      if (out !== expected) $error("[%0t] style1: out=%h expected=%h", $realtime, out, expected);
    end
  end

  // Style 2: the same spec as concurrent assertions.
  assert property (@(posedge clk) rst |=> out == '0);
  assert property (@(posedge clk) !rst && en |=> out == $past(in));
  assert property (@(posedge clk) disable iff (rst) !en |=> $stable(out));
  assert property (@(posedge clk) disable iff (rst) !$isunknown(out));
endmodule
