// Chapter 1.3: race conditions, demonstrated.
// Compile:  vlog -sv races.sv
// Run:      vsim -c race_bad   -do "run -all; quit"     (expect errors, possibly on alternating cycles)
//           vsim -c race_fixed -do "run -all; quit"     (expect none)
//           vsim -c reset_race_a / reset_race_b / reset_race_fixed
// Exercise: in reset_race_a, move the always_ff block above the "always @(posedge clk) rst = ~rst;"
// line, recompile, and watch the zeros/ones count change. Nothing semantic changed. That is the
// definition of a race.
// Credit: patterns from Greg Stitt's sv-tutorial (basic/race.sv, basic/reset_race.sv).

`timescale 1ns/1ps

// ---------------------------------------------------------------------------------------------
// The classic: writer uses a blocking assignment, reader wakes on the same edge.
// ---------------------------------------------------------------------------------------------
module race_bad;
  logic clk = 1'b0;
  int   x;

  initial begin : generate_clock
    forever #5 clk = ~clk;
  end

  initial begin : drive_x
    $timeformat(-9, 0, " ns");
    for (int i = 0; i < 10; i++) begin
      x = i;                 // BLOCKING write to a variable another process reads on the same edge
      @(posedge clk);
    end
    $display("race_bad done (errors above, if any, are the race)");
    disable generate_clock;
  end

  initial begin : check_x
    for (int i = 0; i < 10; i++) begin
      @(posedge clk);
      if (x !== i) $error("[%0t] x = %0d, expected %0d", $realtime, x, i);
    end
  end
endmodule

module race_fixed;
  logic clk = 1'b0;
  int   x;

  initial begin : generate_clock
    forever #5 clk = ~clk;
  end

  initial begin : drive_x
    $timeformat(-9, 0, " ns");
    for (int i = 0; i < 10; i++) begin
      x <= i;                // NONBLOCKING: update lands in the NBA region, after every Active read
      @(posedge clk);
    end
    $display("race_fixed done (no errors expected)");
    disable generate_clock;
  end

  initial begin : check_x
    for (int i = 0; i < 10; i++) begin
      @(posedge clk);
      if (x !== i) $error("[%0t] x = %0d, expected %0d", $realtime, x, i);
    end
  end
endmodule

// ---------------------------------------------------------------------------------------------
// Reset race: rst toggled with a blocking assignment on the same edge the DUT samples it.
// ---------------------------------------------------------------------------------------------
module reset_race_a;
  localparam int WIDTH = 8;
  logic clk = 1'b0, rst = 1'b1, en = 1'b1;
  logic [WIDTH-1:0] in = '1, out;
  int zeros = 0, ones = 0;

  initial begin : generate_clock
    forever #5 clk = ~clk;
  end

  always @(posedge clk) rst = ~rst;          // BAD: blocking write, same event as the flop below

  always_ff @(posedge clk or posedge rst) begin
    if (rst) out <= '0;
    else if (en) out <= in;
  end

  initial begin
    for (int i = 0; i < 10000; i++) begin
      @(negedge clk);
      if (out == '0) zeros++;
      if (out == '1) ones++;
    end
    $display("reset_race_a: %0d zeros, %0d ones", zeros, ones);
    disable generate_clock;
  end
endmodule

// Same code, blocks reordered. Compare the printed counts with reset_race_a.
module reset_race_b;
  localparam int WIDTH = 8;
  logic clk = 1'b0, rst = 1'b1, en = 1'b1;
  logic [WIDTH-1:0] in = '1, out;
  int zeros = 0, ones = 0;

  initial begin : generate_clock
    forever #5 clk = ~clk;
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) out <= '0;
    else if (en) out <= in;
  end

  always @(posedge clk) rst = ~rst;          // same BAD line, different position in the file

  initial begin
    for (int i = 0; i < 10000; i++) begin
      @(negedge clk);
      if (out == '0) zeros++;
      if (out == '1) ones++;
    end
    $display("reset_race_b: %0d zeros, %0d ones", zeros, ones);
    disable generate_clock;
  end
endmodule

module reset_race_fixed;
  localparam int WIDTH = 8;
  logic clk = 1'b0, rst = 1'b1, en = 1'b1;
  logic [WIDTH-1:0] in = '1, out;
  int zeros = 0, ones = 0;

  initial begin : generate_clock
    forever #5 clk = ~clk;
  end

  always @(posedge clk) rst <= ~rst;         // FIXED: the flop always sees the pre-edge value of rst

  always_ff @(posedge clk or posedge rst) begin
    if (rst) out <= '0;
    else if (en) out <= in;
  end

  initial begin
    for (int i = 0; i < 10000; i++) begin
      @(negedge clk);
      if (out == '0) zeros++;
      if (out == '1) ones++;
    end
    $display("reset_race_fixed: %0d zeros, %0d ones (deterministic: 5000/5000)", zeros, ones);
    disable generate_clock;
  end
endmodule

// ---------------------------------------------------------------------------------------------
// Proof that NBA order does not matter within a time step (Stitt's nonblocking_test2).
// ---------------------------------------------------------------------------------------------
module nba_order_proof;
  logic clk = 1'b0;
  initial begin : generate_clock
    forever #5 clk <= ~clk;
  end

  int a1 = 0, a2 = 0, a3 = 0, b1 = 0, b2 = 0, b3 = 0, c1 = 0, c2 = 0, c3 = 0;

  initial begin
    for (int i = 0; i < 100; i++) begin
      for (int j = 0; j < 100; j++) begin
        a1 <= i; b1 <= j; c1 <= a1 + b1;     // c after its inputs
        a2 <= i; c2 <= a2 + b2; b2 <= j;     // c in the middle
        c3 <= a3 + b3; a3 <= i; b3 <= j;     // c BEFORE its inputs
        @(posedge clk);
      end
    end
    $display("nba_order_proof done: c1, c2, c3 were always equal");
    disable generate_clock;
  end

  assert property (@(posedge clk) c1 == c2 && c2 == c3);
endmodule
