// Chapter 1.1: data types, dynamic containers, casting, streaming.
// Compile: vlog -sv datatypes_demo.sv ; Run: vsim -c datatypes_demo -do "run -all; quit"
// No DUT. Read the $display output alongside docs/01-sv-fundamentals/01-data-types.md.

`timescale 1ns/1ps

module datatypes_demo;

  typedef enum logic [1:0] {IDLE, BUSY, DONE} state_t;

  typedef struct packed {
    logic [3:0]  opcode;
    logic [11:0] addr;
    logic [15:0] imm;
  } instr_t;

  // 4-state vs 2-state defaults
  logic [7:0] four_state;
  bit   [7:0] two_state;

  // Dynamic containers
  int          dyn[];
  logic [7:0]  q[$];
  logic [31:0] mem[logic [31:0]];

  initial begin
    $display("--- 4-state vs 2-state defaults ---");
    $display("logic default = %b, bit default = %b", four_state, two_state);
    if (four_state != 8'h00) $display("this never prints: X != 0 evaluates to X, which is false");
    if (four_state !== 8'h00) $display("!== sees the X: four_state is %b", four_state);
    if ($isunknown(four_state)) $display("$isunknown is the cleanest way to test for X");

    $display("--- dynamic array ---");
    dyn = new[4];
    foreach (dyn[i]) dyn[i] = i * i;
    dyn = new[6](dyn);              // grow, keep contents
    $display("dyn = %p (size %0d)", dyn, dyn.size());

    $display("--- queue as a FIFO model ---");
    q.push_back(8'h11); q.push_back(8'h22); q.push_back(8'h33);
    $display("q = %p, head = %h, tail = %h", q, q[0], q[$]);
    $display("pop_front -> %h, q now %p", q.pop_front(), q);
    q.insert(1, 8'hAA);
    $display("after insert: %p", q);
    $display("sum = %0d, max = %p", q.sum(), q.max());

    $display("--- associative array as sparse memory ---");
    mem[32'h1000_0000] = 32'hDEAD_BEEF;
    mem[32'hFFFF_FFF0] = 32'hCAFE_F00D;
    $display("entries = %0d, exists(0x1000_0000) = %0d, exists(0) = %0d",
             mem.num(), mem.exists(32'h1000_0000), mem.exists(0));
    foreach (mem[a]) $display("  mem[%h] = %h", a, mem[a]);

    $display("--- enum ---");
    begin
      automatic state_t s = IDLE;
      $display("s = %s (%0d)", s.name(), s);
      s = s.next();
      $display("s.next() = %s", s.name());
      if (!$cast(s, 3)) $display("$cast(s, 3) failed: 3 is not a state_t member");
    end

    $display("--- packed struct as a bus word ---");
    begin
      automatic instr_t ins;
      ins = 32'h1_234_5678;
      $display("opcode=%h addr=%h imm=%h", ins.opcode, ins.addr, ins.imm);
      ins.imm = '1;
      $display("as a vector: %h", ins);
    end

    $display("--- width rules ---");
    begin
      automatic logic [7:0] a = 8'd200, b = 8'd100;
      automatic logic [7:0] s8;  automatic logic [8:0] s9;
      s8 = a + b;               $display("8-bit sum   = %0d (carry lost)", s8);
      s9 = a + b;               $display("9-bit sum   = %0d (carry kept: dest width sets context)", s9);
      s8 = (a + b) >> 1;        $display("bad average = %0d", s8);
      s8 = ({1'b0, a} + b) >> 1; $display("good average = %0d", s8);
    end

    $display("--- signed trap ---");
    begin
      automatic logic signed [7:0] s = -1;
      automatic logic        [7:0] u = 8'd1;
      $display("s < u          : %0d  (false! mixed signedness -> unsigned compare)", s < u);
      $display("s < signed'(u) : %0d", s < signed'(u));
    end

    $display("--- streaming ---");
    begin
      automatic byte payload[] = '{8'h11, 8'h22, 8'h33, 8'h44};
      automatic logic [31:0] w;
      w = {>>{payload}};        $display("{>>{}}     = %h", w);
      w = {<<byte{payload}};    $display("{<<byte{}} = %h", w);
    end

    $finish;
  end
endmodule
