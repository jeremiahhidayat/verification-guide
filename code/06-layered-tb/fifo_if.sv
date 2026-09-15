// Chapter 6: the signal layer. Two interfaces, one per DUT port group, with helper tasks (BFM style)
// and the protocol assertions that belong to the interface rather than to any DUT.
`timescale 1ns/1ps

interface fifo_wr_if #(parameter int WIDTH = 8) (input logic clk, input logic rst);
  logic             wr_en;
  logic [WIDTH-1:0] wr_data;
  logic             full;

  task automatic idle();
    wr_en <= 1'b0;
  endtask

  // Drive one write attempt for exactly one cycle (the DUT ignores it if full; the monitor sees the truth).
  task automatic write(input logic [WIDTH-1:0] d);
    wr_data <= d;
    wr_en   <= 1'b1;
    @(posedge clk);
    wr_en   <= 1'b0;
  endtask

  // Interface-owned assertion: nobody may drive X on the control pin after reset.
  ap_wr_en_known: assert property (@(posedge clk) disable iff (rst) !$isunknown(wr_en));
endinterface

interface fifo_rd_if #(parameter int WIDTH = 8) (input logic clk, input logic rst);
  logic             rd_en;
  logic [WIDTH-1:0] rd_data;
  logic             empty;

  task automatic idle();
    rd_en <= 1'b0;
  endtask

  task automatic read();
    rd_en <= 1'b1;
    @(posedge clk);
    rd_en <= 1'b0;
  endtask

  ap_rd_en_known: assert property (@(posedge clk) disable iff (rst) !$isunknown(rd_en));
endinterface
