// Chapter 3: small self-contained DUTs and the assertions that specify them.
// Compile: vlog -sv sva_patterns_tb.sv ; Run: vsim -c sva_patterns_tb -do "run -all; quit"
// Each block is a mini lesson: the DUT, the spec in English, the assertion, and a knob to break it.
`timescale 1ns/1ps

// ---------------------------------------------------------------------------------------------
// DUT 1: request/acknowledge responder. Spec: ack rises 1..3 cycles after req rises; req must be
// held until ack; ack is a single-cycle pulse; no ack without req.
// ---------------------------------------------------------------------------------------------
module req_ack #(parameter int DELAY = 2) (
  input  logic clk, rst, req,
  output logic ack
);
  logic [2:0] cnt;
  logic busy;
  always_ff @(posedge clk) begin
    if (rst) begin cnt <= 0; busy <= 0; ack <= 0; end
    else begin
      ack <= 1'b0;
      if (!busy && req) begin busy <= 1'b1; cnt <= DELAY - 1; end
      else if (busy) begin
        if (cnt == 0) begin ack <= 1'b1; busy <= 1'b0; end
        else cnt <= cnt - 1;
      end
    end
  end
endmodule

// ---------------------------------------------------------------------------------------------
// DUT 2: 3-stage enabled pipeline. Spec: out = in * 2 + 1, LATENCY enabled cycles later; outputs
// hold when !en; valid tracks data.
// ---------------------------------------------------------------------------------------------
module pipe3 #(parameter int W = 8) (
  input  logic clk, rst, en, valid_in,
  input  logic [W-1:0] data_in,
  output logic valid_out,
  output logic [W-1:0] data_out
);
  localparam int LATENCY = 3;
  logic [W-1:0] d1, d2;  logic v1, v2;
  always_ff @(posedge clk) begin
    if (rst) begin {v1, v2, valid_out} <= '0; {d1, d2, data_out} <= '0; end
    else if (en) begin
      d1 <= data_in;      v1 <= valid_in;
      d2 <= d1 * 2;       v2 <= v1;
      data_out <= d2 + 1; valid_out <= v2;
    end
  end
endmodule

// ---------------------------------------------------------------------------------------------
// Testbench with the properties.
// ---------------------------------------------------------------------------------------------
module sva_patterns_tb;
  logic clk = 0, rst;
  always #5 clk = ~clk;

  // ---- DUT 1 ----
  logic req, ack;
  req_ack #(.DELAY(2)) u_ra (.clk, .rst, .req, .ack);

  // ---- DUT 2 ----
  localparam int W = 8;
  logic en, valid_in, valid_out;
  logic [W-1:0] data_in, data_out;
  pipe3 #(.W(W)) u_pipe (.clk, .rst, .en, .valid_in, .data_in, .valid_out, .data_out);

  // ---- stimulus ----
  initial begin
    $timeformat(-9, 0, " ns");
    rst <= 1; req <= 0; en <= 0; valid_in <= 0; data_in <= 0;
    repeat (4) @(posedge clk);
    @(negedge clk); rst <= 0;

    fork
      // req/ack traffic: raise req, hold until ack, drop, idle a random time
      begin : req_traffic
        repeat (200) begin
          req <= 1'b1;
          @(posedge clk iff ack);
          req <= 1'b0;
          repeat ($urandom_range(0, 3)) @(posedge clk);
        end
      end
      // pipeline traffic
      begin : pipe_traffic
        repeat (2000) begin
          en <= $urandom; valid_in <= $urandom; data_in <= $urandom;
          @(posedge clk);
        end
      end
    join
    $display("sva_patterns_tb: done");
    $finish;
  end

  default clocking cb @(posedge clk); endclocking
  default disable iff (rst);

  // ---- DUT 1 properties ----
  ap_ack_window:  assert property ($rose(req) |-> ##[1:3] ack)
    else $error("[%0t] no ack within 3 cycles of req", $realtime);
  ap_req_held:    assert property (req && !ack |=> req)
    else $error("[%0t] req dropped before ack", $realtime);
  ap_ack_pulse:   assert property (ack |=> !ack);
  ap_no_spur_ack: assert property (ack |-> $past(req));
  cp_ack_seen:    cover  property ($rose(req) ##[1:3] ack);

  // ---- DUT 2 properties ----
  localparam int L = u_pipe.LATENCY;       // read the constant from the DUT (or a package)
  function automatic logic [W-1:0] model(input logic [W-1:0] d);
    return d * 2 + 1;                       // width: W-bit context, wraps like the DUT
  endfunction

  // backward-looking, enable-gated history
  ap_pipe_data:  assert property (en[->L] |=> data_out == model($past(data_in, L, en)))
    else $error("[%0t] data_out=%h expected %h", $realtime, $sampled(data_out), model($past(data_in, L, en)));
  ap_pipe_valid: assert property (en[->L] |=> valid_out == $past(valid_in, L, en));

  // forward-looking with a local variable: same spec, formal-friendly
  property p_pipe_fwd;
    logic [W-1:0] exp;
    (en && valid_in, exp = model(data_in)) |-> en[->L] ##1 data_out == exp;
  endproperty
  ap_pipe_fwd: assert property (p_pipe_fwd);

  ap_pipe_stall: assert property (!en |=> $stable({valid_out, data_out}));
  ap_pipe_flush: assert property (@(posedge clk) disable iff (1'b0) $fell(rst) |-> !valid_out throughout en[->L]);
  ap_pipe_nox:   assert property (!$isunknown({valid_out, data_out}));

  cp_pipe_b2b:   cover property (en && valid_in [*4]);
  cp_pipe_stall: cover property (!en [*5]);
endmodule
