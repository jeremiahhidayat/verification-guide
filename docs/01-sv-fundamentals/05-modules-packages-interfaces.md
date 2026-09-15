# 1.5 Modules, Parameters, Packages, Interfaces, Clocking Blocks, Program Blocks

## Modules and parameters

A module is a hardware boundary with ports and parameters. In verification you care about three
things: how to parameterize a DUT and match the testbench to it, how to instantiate cleanly, and
how to reach across the boundary.

```systemverilog
module fifo #(
  parameter int WIDTH = 8,
  parameter int DEPTH = 16,
  localparam int ADDR_W = $clog2(DEPTH)      // derived; not overridable
) (
  input  logic             clk, rst,
  input  logic             wr_en, rd_en,
  input  logic [WIDTH-1:0] wr_data,
  output logic [WIDTH-1:0] rd_data,
  output logic             full, empty
);
```

Instantiation styles:

```systemverilog
fifo #(.WIDTH(8), .DEPTH(16)) dut (.clk(clk), .rst(rst), .wr_en(wr_en), ...);   // explicit: safest, verbose
fifo #(.WIDTH(8)) dut (.*);              // wildcard: connects ports to same-named signals in scope
fifo #(.WIDTH(8)) dut (.rd_data(dout), .*);   // wildcard with exceptions
```

`.*` is convenient in testbenches (name your local signals after the ports) and dangerous in RTL
(a typo in a signal name silently becomes an implicit 1-bit net; see gotchas). Even in testbenches,
`.*` errors if widths or names do not match exactly, which is actually a nice safety net.

Parameter typing: always write `parameter int` (or the intended type). An untyped
`parameter WIDTH = 8` takes the type of whatever value overrides it; `parameter WIDTH = 8'd8` is
8-bit and `2**WIDTH` overflows.

### `generate`

Compile-time structural loops and conditionals. The testbench uses them to instantiate N agents or N
checkers, or to select a reference model by parameter.

```systemverilog
generate
  for (genvar i = 0; i < N_PORTS; i++) begin : g_port
    port_checker #(.ID(i)) chk (.clk, .valid(valid[i]), .data(data[i]));
  end
  if (CYCLES == 0) begin : g_bypass
    assign expected = data_in;
  end else begin : g_delay
    ...
  end
endgenerate
```

Always label generate blocks; the label is part of the hierarchical name (`tb.g_port[3].chk`).

## Packages

A package is a namespace for types, parameters, functions, and classes that must be shared across
files. Every real testbench has at least one.

```systemverilog
package fifo_tb_pkg;
  localparam int WIDTH = 8;
  typedef logic [WIDTH-1:0] data_t;
  typedef enum {READ, WRITE} op_t;
  function automatic int latency(int depth); return depth > 8 ? 2 : 1; endfunction
  `include "fifo_transaction.svh"      // classes are usually `include-d into a package
  `include "fifo_scoreboard.svh"
endpackage

// Using it
import fifo_tb_pkg::*;                 // everything (in a module or at compilation-unit scope)
import fifo_tb_pkg::data_t;            // one symbol
fifo_tb_pkg::WIDTH                     // scope resolution without import
```

Why packages instead of `include` everywhere? Compilation order and single definition. A package is
compiled once; classes inside it are compiled once; every user gets the same type. With bare
`include`, each including file gets its own copy of the class definition, which yields duplicate-type
errors or, worse, two different `my_txn` types that cannot be assigned to each other. The convention:

- `.svh` files hold one class each, with an include guard (`` `ifndef _FOO_SVH_ ``), and are only ever
  `include`d from inside a package.
- `.sv` files hold modules, interfaces, and packages, and are compiled directly.
- Compilation-unit-scope `import` before a module is legal but sloppy; import inside the module.

**Package parameters and UVM:** UVM's config_db passes *run-time* values; class parameters, interface
widths, and module parameters must be *compile-time*. Putting widths in a package (Stitt's
`bit_diff_if_pkg::WIDTH` trick) is the pragmatic way to make every class, interface, and module agree
without parameterizing the whole UVM hierarchy. Chapter 7 discusses when to parameterize instead.

## Interfaces

An interface bundles the signals of a port group into one named object, optionally with tasks,
functions, assertions, modports, and clocking blocks. It exists to solve a scaling problem: a DUT with
200 signals across 6 buses is unmaintainable when every signal is passed individually to every
driver, monitor, and checker.

```systemverilog
interface axi_stream_if #(parameter int DATA_W = 32) (input logic aclk, input logic aresetn);
  logic              tvalid, tready, tlast;
  logic [DATA_W-1:0] tdata;

  // Protocol-level helper tasks: a "BFM" (bus functional model) lives naturally here
  task automatic send(input logic [DATA_W-1:0] d, input bit last = 0);
    tdata  <= d;  tlast <= last;  tvalid <= 1'b1;
    @(posedge aclk iff tready);
    tvalid <= 1'b0;
  endtask

  // Protocol assertions belong with the protocol, not with any one DUT
  assert property (@(posedge aclk) disable iff (!aresetn) tvalid && !tready |=> tvalid && $stable(tdata))
    else $error("AXI-Stream: tvalid dropped or tdata changed before handshake");

  // Modports: direction views for each side
  modport master  (output tvalid, tdata, tlast, input tready, aclk, aresetn);
  modport slave   (input  tvalid, tdata, tlast, output tready, input aclk, aresetn);
  modport monitor (input  tvalid, tdata, tlast, tready, aclk, aresetn);
endinterface
```

Connect it:

```systemverilog
axi_stream_if #(.DATA_W(32)) in_if (clk, rst_n);
dut u_dut (.aclk(clk), .aresetn(rst_n),
           .in_tvalid(in_if.tvalid), .in_tready(in_if.tready), .in_tdata(in_if.tdata), .in_tlast(in_if.tlast));
// or, if the DUT is written to take an interface port:
dut2 u_dut2 (.in(in_if.slave));
```

### Virtual interfaces: how classes see pins

Classes are dynamic; interfaces are static hierarchy. A class cannot instantiate an interface, but it
can hold a **handle** to one:

```systemverilog
class axi_stream_driver;
  virtual axi_stream_if #(.DATA_W(32)) vif;      // "virtual" = a pointer to an interface instance
  task run();
    forever begin
      ...
      vif.tdata <= txn.data;   // drive through the handle
      @(posedge vif.aclk);
    end
  endtask
endclass

// In the top module: hand the real interface to the driver
drv.vif = in_if;                                   // plain class-based TB
uvm_config_db#(virtual axi_stream_if #(32))::set(null, "*", "in_vif", in_if);   // UVM
```

The parameter values are part of the type: `virtual axi_stream_if #(32)` and `virtual axi_stream_if
#(64)` are different types. This is the root of most "UVM and parameterized interfaces" pain;
chapter 7 shows the standard workarounds (package defaults, `typedef`, parameterized agents).

### Modports

A modport restricts which signals are visible and their directions, from the perspective of the
module that uses it. Two reasons to bother: (1) synthesis of a DUT that takes an interface port needs
directions; (2) it documents and enforces roles (a monitor cannot accidentally drive). Testbench code
often ignores modports and uses the full interface via a virtual interface, which is acceptable.

## Clocking blocks

A clocking block is the LRM's formal answer to testbench/DUT races. It declares, for a group of
signals, *when* they are sampled and driven relative to a clock:

```systemverilog
interface fifo_if (input logic clk);
  logic wr_en, rd_en, full, empty;
  logic [7:0] wr_data, rd_data;

  clocking cb @(posedge clk);
    default input #1step output #0;     // sample inputs 1 step before the edge (Preponed); drive outputs at the edge (Reactive/NBA)
    output wr_en, rd_en, wr_data;
    input  full, empty, rd_data;
  endclocking

  modport tb (clocking cb);
endinterface
```

Using it from a driver:

```systemverilog
task automatic write(logic [7:0] d);
  vif.cb.wr_data <= d;          // clocking-block drive: MUST use <= ; takes effect per output skew
  vif.cb.wr_en   <= 1'b1;
  @(vif.cb);                    // wait for the clocking event
  vif.cb.wr_en   <= 1'b0;
endtask
if (vif.cb.full) ...            // read the value sampled in Preponed at the last clocking event
```

What you get: reads through `cb.` always return the value from just before the edge (same as SVA
sampling); writes through `cb.` are scheduled after the DUT has evaluated the edge. No race, no `#1`,
and if you later need to model output delay (drive 2 ns after the edge for a gate-level sim), you
change one `output #2ns` line.

What it costs: another layer of names, subtle errors if you mix `cb.sig` and raw `sig` accesses to
the same signal, and some tool quirks with `#1step` on inputs that are also driven combinationally.
Many teams use clocking blocks for every UVM agent; many others just use `<=` on raw interface
signals and sample on `@(posedge clk)`. Both are defensible; the second is what this guide's examples
use for readability. Know both for interviews.

## Program blocks

`program` is a container like `module` whose code executes in the **Reactive** region (after the
DUT's Active/NBA activity) and which ends the simulation when its initial blocks finish. It was
introduced (from OpenVera) as another race-avoidance mechanism: testbench code in a program always
runs after design code in the same time step.

```systemverilog
program automatic test(fifo_if.tb bus);
  initial begin
    bus.cb.wr_en <= 1;  ...
  end
endprogram
```

Reality: UVM does not use program blocks (UVM runs from a module's `initial run_test()`), and the
Reactive-region semantics interact confusingly with assertions and with `$finish`. The Spear book
uses them throughout; most modern methodology guides say "modules plus NBA/clocking blocks are
sufficient." Know what a program block is and why it was invented; do not feel obligated to use one.

## Hierarchical access into interfaces and the `bind` construct

`bind` instantiates a module or interface *inside* another module without editing that module's
source. This is how you attach assertion modules to RTL you do not own, or add a monitor to an
internal bus:

```systemverilog
// fifo_sva.sv: a checker with the same port names as the signals inside fifo
module fifo_sva #(parameter int DEPTH = 16) (input logic clk, rst, wr_en, rd_en, full, empty, input logic [$clog2(DEPTH):0] count);
  assert property (@(posedge clk) disable iff (rst) full |-> count == DEPTH);
  assert property (@(posedge clk) disable iff (rst) empty |-> count == 0);
endmodule

// In the testbench (or a separate bind file compiled with the DUT):
bind fifo fifo_sva #(.DEPTH(DEPTH)) u_sva (.*);   // every instance of fifo gets one; .* binds to fifo's internal names
```

The bound instance sees the target's internal signals as if it were declared inside. This is the
standard way both simulation and formal teams add properties to a design.

## Interview angle

- "What is an interface and why use one?" Bundling, reuse across DUT/driver/monitor, tasks and
  assertions inside it, modports for direction, virtual interface for classes.
- "What is a virtual interface?" A class-side handle to a static interface instance, set from the top
  or via config_db. Parameter values are part of its type.
- "What is a clocking block?" Declares sampling/driving skew relative to a clock so testbench reads
  see pre-edge values and writes land after the DUT evaluates. Race-free by construction.
- "Program block?" Reactive-region execution; designed for race avoidance; largely superseded by
  clocking blocks plus UVM conventions.
- "What is `bind`?" Non-intrusive instantiation of checkers into RTL scope.

## Mentor's notes

- Put protocol assertions *in the interface*. Then every DUT that uses the protocol gets them for
  free, and the formal team can reuse them as assumptions on the other side of the boundary.
- If you catch yourself connecting 40 signals by hand from a class to a DUT, stop and write an
  interface. Stitt's `bit_diff_tb1` shows the pain on purpose (`always @(drv.go) go = drv.go;`), then
  `bit_diff_tb2` shows the fix. Feel the pain once, then never again.
