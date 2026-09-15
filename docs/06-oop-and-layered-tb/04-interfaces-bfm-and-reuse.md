# 6.4 Interfaces, BFMs, Virtual Interfaces, and Reuse

## The signal layer

Classes cannot have ports. The bridge between the dynamic class world and the static module world
is the **interface** instance in the testbench top plus a **virtual interface** handle in the
classes. Chapter 1.5 covered the syntax; here is the methodology.

```
   tb_top (module)
     ├── fifo_wr_if wr_if (clk, rst)     ┐  static: instantiated once, connected to DUT pins
     ├── fifo_rd_if rd_if (clk, rst)     ┘
     ├── fifo dut (.wr_en(wr_if.wr_en), ...)
     └── initial: env = new(wr_if, rd_if); env.run();
                   └── wr_agent.driver.vif  = wr_if   (virtual handle)
                       wr_agent.monitor.vif = wr_if
                       rd_agent.driver.vif  = rd_if
                       ...
```

One interface instance per DUT port group; one virtual handle per component that touches it. The
same class type (`fifo_wr_driver`) can drive any number of `fifo_wr_if` instances because the handle
is per-object.

## BFM tasks in the interface

A bus-functional model is procedural code that performs protocol operations. Putting the *lowest
level* of it in the interface (tutorial's `bit_diff_bfm`: `reset()`, `start()`, `wait_for_done()`,
`monitor()`) has advantages:

- The protocol timing is written once, next to the signals, and tested once.
- Drivers and monitors become one-liners that call `vif.send(...)` / `vif.wait_for_beat(...)`.
- The tasks are usable from a plain-module testbench, from classes, and from a C/DPI test.
- With `automatic` tasks, multiple threads can use them concurrently on different interface
  instances.

Disadvantages: interface tasks cannot be overridden by inheritance (they are not class methods),
and some teams prefer the driver to own all protocol knowledge so the interface is "just wires."
UVM practice leans toward wires-only interfaces with the protocol in the driver, but helper tasks
(`wait_for_reset`, `wait_for_handshake`) are common and harmless. Pick one convention per project.

## Active vs. passive

An agent is **active** when it drives (has a generator/sequencer and driver) and **passive** when it
only monitors. The same agent class serves both: a flag decides whether the driver is constructed.
Why it matters:

- At block level, the FIFO's write interface is driven by the write agent (active) and its read
  interface by the read agent (active).
- At subsystem level, the FIFO sits between a producer block and a consumer block. Both of its
  interfaces are now driven by *other RTL*. You instantiate the same two agents in passive mode:
  monitors still reconstruct transactions, the scoreboard still checks the FIFO, and nothing else
  changes. That is vertical reuse, and it is the single biggest argument for the layered
  architecture.

## Reuse across levels

| Level | What changes | What is reused |
|---|---|---|
| Block | Everything active; block-specific scoreboard | Interface agents (from a library or a previous block) |
| Subsystem | Block agents flip to passive; new active agents on subsystem boundaries; subsystem scoreboard | Block scoreboards keep checking their blocks; block coverage keeps collecting |
| SoC | Most agents passive; stimulus from embedded software via a C testbench or a processor model | Everything below, plus protocol checkers as assertions in interfaces |

Prerequisites for this to work: agents get their interfaces from configuration (not hard-coded
paths), scoreboards subscribe to monitors (not to drivers), and nothing in a block environment
assumes it is at the top of the hierarchy. UVM's `uvm_config_db` with wildcard paths, analysis
ports, and `uvm_env` nesting exist precisely to enforce these.

## Multiple interfaces of different widths

`virtual fifo_if #(8)` and `virtual fifo_if #(32)` are different types. Options:

1. **Fix widths in a package** used by the interface's default parameter and by every class
   (tutorial's `bit_diff_if_pkg::WIDTH`). Works when every instance of that interface has the same
   width. Simplest; recompilation needed to change.
2. **Parameterize the agent classes** and pass the width down (tutorial's `agents` example). Works
   for multiple widths; every class that names the type carries the parameter, and UVM registration
   needs `*_param_utils`.
3. **Widest-common interface**: make the interface the maximum width and ignore upper bits for
   narrower instances; the transaction carries the real width. Pragmatic; common in real
   codebases; loses width checking.
4. **Abstract class / polymorphic interface wrapper**: an abstract BFM class per interface instance
   with a width-specific concrete subclass created in the top; classes hold the abstract type. The
   most flexible; the most code.

Know 1 and 2 well; recognize 3 and 4.

## Clocking blocks in the agent

If your team uses clocking blocks (1.5), the driver writes `vif.cb.wr_en <= 1` and waits `@(vif.cb)`;
the monitor reads `vif.cb.rd_data`. Declare a modport per role (`modport drv (clocking cb, ...)`)
and type the virtual interface with it (`virtual fifo_if.drv vif`) so a monitor cannot drive by
accident. If your team does not, drive with `<=` and sample at `@(posedge vif.clk)`. Do not mix the
two styles on one signal.

## Interview angle

- "How do classes access DUT signals?" Virtual interface; set from the top or config_db.
- "Active vs passive agent, and why?" Vertical reuse.
- "How do you reuse a block testbench at subsystem level?" Passive agents, scoreboard subscribed to
  monitors, configuration-driven interface lookup.
- "Two instances of a parameterized interface with different widths in one UVM testbench: how?"
  Options 1 to 4.

## Mentor's notes

- Put protocol assertions in the interface (chapter 3). At subsystem level, when the block agents
  go passive, those assertions are the only *active* checking of the protocol between two RTL
  blocks, and they catch integration bugs the block scoreboards cannot see.
- When you inherit an environment, the first thing to check is whether the monitors subscribe to
  the driver (bad) or to the pins (good). If the former, the environment cannot go passive, and
  someone will rewrite it at subsystem time. Better it be you, now.
