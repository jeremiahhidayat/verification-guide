// Synchronous FIFO used as the running DUT for chapters 2 through 8.
// - WIDTH-bit data, DEPTH entries (DEPTH must be a power of 2)
// - 1-cycle read latency: rd_data is valid the cycle after rd_en && !empty
// - Writes when full and reads when empty are ignored (not errors at the pins)
// - Synchronous active-high reset
//
// Deliberate bug hooks for exercises (all default off):
//   +define+BUG_FULL_OFF_BY_ONE   : full asserts one entry early
//   +define+BUG_NO_RESET_RDPTR    : rd_ptr not reset
//   +define+BUG_DROP_ON_SIMUL     : simultaneous read+write at count==1 loses the write
`timescale 1ns/1ps

module fifo #(
  parameter int WIDTH = 8,
  parameter int DEPTH = 16
) (
  input  logic             clk,
  input  logic             rst,
  input  logic             wr_en,
  input  logic [WIDTH-1:0] wr_data,
  output logic             full,
  input  logic             rd_en,
  output logic [WIDTH-1:0] rd_data,
  output logic             empty,
  output logic [$clog2(DEPTH):0] count
);
  localparam int AW = $clog2(DEPTH);

  logic [WIDTH-1:0] mem [DEPTH];
  logic [AW:0]      wr_ptr, rd_ptr;     // one extra bit distinguishes full from empty
  logic             do_wr, do_rd;

  assign do_wr = wr_en && !full;
`ifdef BUG_DROP_ON_SIMUL
  assign do_rd = rd_en && !empty && !(wr_en && count == 1);
`else
  assign do_rd = rd_en && !empty;
`endif

  always_ff @(posedge clk) begin
    if (rst) begin
      wr_ptr <= '0;
`ifndef BUG_NO_RESET_RDPTR
      rd_ptr <= '0;
`endif
    end else begin
      if (do_wr) begin
        mem[wr_ptr[AW-1:0]] <= wr_data;
        wr_ptr <= wr_ptr + 1'b1;
      end
      if (do_rd) begin
        rd_data <= mem[rd_ptr[AW-1:0]];
        rd_ptr  <= rd_ptr + 1'b1;
      end
    end
  end

  assign count = wr_ptr - rd_ptr;
  assign empty = (wr_ptr == rd_ptr);
`ifdef BUG_FULL_OFF_BY_ONE
  assign full  = (count == DEPTH - 1);
`else
  assign full  = (wr_ptr[AW-1:0] == rd_ptr[AW-1:0]) && (wr_ptr[AW] != rd_ptr[AW]);
`endif

  // Designer-owned assertions: cheap, always on, catch misuse and internal inconsistency.
  // Synthesis ignores them.
  assert property (@(posedge clk) disable iff (rst) do_wr |-> !full);
  assert property (@(posedge clk) disable iff (rst) do_rd |-> !empty);
  assert property (@(posedge clk) disable iff (rst) count <= DEPTH);
endmodule
