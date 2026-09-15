// Chapter 2: a complete, race-free, self-checking module-level testbench for the FIFO.
// Compile: vlog -sv fifo.sv fifo_tb.sv
// Run:     vsim -c fifo_tb -do "run -all; quit"
// Try:     vlog -sv +define+BUG_FULL_OFF_BY_ONE fifo.sv fifo_tb.sv   (then run: the testbench must fail)
`timescale 1ns/1ps

module fifo_tb #(
  parameter int NUM_TESTS = 20000,
  parameter int WIDTH     = 8,
  parameter int DEPTH     = 16
);
  // ---------------- DUT connections ----------------
  logic             clk = 1'b0;
  logic             rst;
  logic             wr_en, rd_en, full, empty;
  logic [WIDTH-1:0] wr_data, rd_data;
  logic [$clog2(DEPTH):0] count;

  fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH)) dut (.*);

  // ---------------- clock and reset: one process each ----------------
  initial begin : generate_clock
    forever #5 clk = ~clk;
  end

  initial begin : generate_reset
    rst <= 1'b1;
    wr_en <= 1'b0; rd_en <= 1'b0; wr_data <= '0;
    repeat (5) @(posedge clk);
    @(negedge clk);
    rst <= 1'b0;
  end

  // ---------------- stimulus: phases that force the corners ----------------
  // Random traffic alone rarely fills a 16-deep FIFO when wr/rd are 50/50. So we bias by phase.
  int errors = 0;

  initial begin : stimulus
    $timeformat(-9, 0, " ns");
    @(negedge rst);
    @(posedge clk);

    // Phase 1: fill to full (write only), including several writes while full
    repeat (DEPTH + 4) begin wr_en <= 1'b1; rd_en <= 1'b0; wr_data <= $urandom; @(posedge clk); end
    // Phase 2: drain to empty, including reads while empty
    repeat (DEPTH + 4) begin wr_en <= 1'b0; rd_en <= 1'b1; @(posedge clk); end
    // Phase 3: random with write-heavy bias, then read-heavy bias, then balanced
    for (int i = 0; i < NUM_TESTS; i++) begin
      automatic int phase = (i * 3) / NUM_TESTS;
      case (phase)
        0: begin wr_en <= ($urandom_range(9) < 7); rd_en <= ($urandom_range(9) < 3); end
        1: begin wr_en <= ($urandom_range(9) < 3); rd_en <= ($urandom_range(9) < 7); end
        default: begin wr_en <= $urandom; rd_en <= $urandom; end
      endcase
      wr_data <= $urandom;
      @(posedge clk);
    end
    wr_en <= 1'b0; rd_en <= 1'b0;
    repeat (4) @(posedge clk);

    if (model_q.size() != count) begin errors++; $error("end of test: model has %0d entries, DUT count=%0d", model_q.size(), count); end
    $display("fifo_tb: %s (%0d errors)", errors == 0 ? "TEST PASSED" : "TEST FAILED", errors);
    disable generate_clock;
  end

  // ---------------- reference model: a queue ----------------
  logic [WIDTH-1:0] model_q[$];
  logic [WIDTH-1:0] expected_rd;
  bit               expect_rd_valid;    // set in the cycle a read is accepted; checked next cycle

  always @(posedge clk) begin
    if (rst) begin
      model_q.delete();
      expect_rd_valid <= 1'b0;
    end else begin
      automatic int size = model_q.size();        // size at the start of the cycle
      expect_rd_valid <= 1'b0;
      if (rd_en && size > 0) begin
        expected_rd     <= model_q.pop_front();
        expect_rd_valid <= 1'b1;
      end
      if (wr_en && size < DEPTH) model_q.push_back(wr_data);
    end
  end

  // ---------------- checks ----------------
  // (a) procedural check: read data one cycle after an accepted read
  always @(posedge clk) begin
    if (!rst && expect_rd_valid) begin
      if (rd_data !== expected_rd) begin
        errors++;
        $error("[%0t] rd_data=%h expected=%h", $realtime, rd_data, expected_rd);
      end
    end
  end

  // (b) invariants as concurrent assertions (chapter 3 explains the syntax)
  ap_full:  assert property (@(posedge clk) disable iff (rst) full  == (model_q.size() == DEPTH)) else begin errors++; end
  ap_empty: assert property (@(posedge clk) disable iff (rst) empty == (model_q.size() == 0))     else begin errors++; end
  ap_count: assert property (@(posedge clk) disable iff (rst) count == model_q.size())            else begin errors++; end
  ap_nox:   assert property (@(posedge clk) disable iff (rst) !$isunknown({full, empty, count}))  else begin errors++; end

  // (c) did we actually hit the corners? (chapter 4 turns these into a coverage model)
  cp_wr_full:  cover property (@(posedge clk) disable iff (rst) wr_en && full);
  cp_rd_empty: cover property (@(posedge clk) disable iff (rst) rd_en && empty);
  cp_simul_1:  cover property (@(posedge clk) disable iff (rst) wr_en && rd_en && count == 1);
  cp_simul_n1: cover property (@(posedge clk) disable iff (rst) wr_en && rd_en && count == DEPTH-1);
endmodule
