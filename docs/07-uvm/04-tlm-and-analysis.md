# 7.4 TLM Ports, Exports, and Analysis

## Why TLM

In chapter 6, components were connected by sharing mailbox handles: the environment created a
mailbox and gave it to both the monitor and the scoreboard. That works, but every connection is a
special case and the producer must know its consumer's mailbox type. Transaction-Level Modeling
(TLM) ports standardize this: a producer has a **port** (it *calls* a method), a consumer has an
**export** or **imp** (it *implements* the method), and the environment `connect`s them. Neither
side knows the other's class.

## The vocabulary

| Term | Meaning |
|---|---|
| **port** | The caller side. `put_port.put(t)` calls whoever is connected. Declared in the producer. |
| **export** | A forwarding point: passes the call through a hierarchy level (e.g., from an agent's boundary to its monitor). |
| **imp** (implementation) | The end of the line: the component that actually implements `put`/`get`/`write`. |
| **blocking / nonblocking** | `put`/`get` (tasks, may wait) vs `try_put`/`can_put`/`try_get` (functions). |
| **analysis** | One-to-many, nonblocking, function-based `write(t)`. Ports can connect to zero or more imps. |

Connection rules: port to port (child to parent going up), port to export, port to imp, export to
export, export to imp. Connections are made in `connect_phase` with `a.connect(b)`.

## Blocking put/get (point-to-point)

```systemverilog
// producer
uvm_blocking_put_port #(int) done_port;   // in monitor: done_port = new("done_port", this)
done_port.put(vif.result);                // blocks if the consumer is not ready

// consumer
uvm_blocking_get_port #(int) done_port;   // in scoreboard
done_port.get(actual);                    // blocks until something arrives

// environment: decouple with a FIFO so neither blocks the other
uvm_tlm_fifo #(int) done_fifo;            // done_fifo = new("done_fifo", this, 8)
agent.done_monitor.done_port.connect(done_fifo.put_export);
scoreboard.done_port.connect(done_fifo.get_export);
```

This is the tutorial's `uvm/basics` style: one producer, one consumer, mailbox-like semantics.
Use it for request/response channels between a driver and a model, or when the consumer *must*
process every item in order and may fall behind.

## Analysis ports (broadcast)

```systemverilog
// producer (monitor)
uvm_analysis_port #(fifo_wr_item) ap;     // ap = new("ap", this)
ap.write(t);                              // nonblocking; calls write() on every connected imp; returns immediately

// consumer option A: uvm_subscriber (has 'analysis_export' built in)
class cov extends uvm_subscriber #(fifo_wr_item);
  function void write(fifo_wr_item t); ... endfunction
endclass

// consumer option B: explicit imp in any component
uvm_analysis_imp #(fifo_wr_item, fifo_scoreboard) wr_imp;   // wr_imp = new("wr_imp", this)
function void write(fifo_wr_item t); ... endfunction         // must be named 'write'

// consumer option C: a component that needs SEVERAL analysis inputs -> distinct imp types
`uvm_analysis_imp_decl(_wr)                                  // generates uvm_analysis_imp_wr
`uvm_analysis_imp_decl(_rd)
uvm_analysis_imp_wr #(fifo_wr_item, fifo_scoreboard) wr_imp;
uvm_analysis_imp_rd #(fifo_rd_item, fifo_scoreboard) rd_imp;
function void write_wr(fifo_wr_item t); ... endfunction
function void write_rd(fifo_rd_item t); ... endfunction

// consumer option D: analysis FIFO, then get() in run_phase (tutorial's agents example)
uvm_tlm_analysis_fifo #(fifo_wr_item) wr_fifo;               // wr_fifo = new("wr_fifo", this)
// env: monitor.ap.connect(sb.wr_fifo.analysis_export);
// sb run_phase: forever begin wr_fifo.get(t); ... end

// environment
wr_agent.monitor.ap.connect(sb.wr_imp);
wr_agent.monitor.ap.connect(wr_cov.analysis_export);         // same port, second listener
```

Choosing:

- **A/B** (`write` function): simplest; the consumer reacts immediately; must not block. Right for
  coverage and for scoreboards whose logic is "update model or compare now."
- **C** (`_decl`): when one scoreboard receives from several monitors with different item types.
- **D** (analysis FIFO): when the consumer needs to *wait* (match an input to an output that arrives
  later, in a `run_phase` loop). The FIFO is unbounded; nothing blocks the monitor.

`write()` receives the *same object handle* the monitor wrote. Consumers that store it (a
scoreboard queue) rely on the monitor never modifying it again, hence "new object per
transaction." Consumers that need a private copy call `t.clone()` / `$cast(mine, t.clone())`.

## Transaction classes and analysis ports across widths

An analysis port is typed. `uvm_analysis_port #(fifo_wr_item)` cannot connect to
`uvm_analysis_imp #(other_item, ...)`. With parameterized items (`axi_item #(32)` vs
`axi_item #(64)`) the port types differ too; the tutorial's `agents_parameterized` threads the
parameter through, and the scoreboard uses the package's known widths. Alternative: a non-parameterized
base item with a dynamic array payload, so one port type serves all widths.

## TLM 2.0 sockets

`uvm_tlm_b_initiator_socket`/`target_socket` with generic payloads exist for SystemC interoperability
(UVM Connect). Rare in pure-SV testbenches; mention them in interviews only if asked about
SystemC co-simulation.

## Debugging connections

- "Port not connected" fatal at end of elaboration: a port with `min_size = 1` (the default for
  non-analysis ports) had no connection. Analysis ports default to `min_size = 0` (unconnected is
  legal, and silent, which is its own trap: a scoreboard that receives nothing passes).
- `uvm_top.print_topology()` and `port.debug_connected_to()` show the graph.
- A scoreboard that never fails is suspicious; count received items and error in `check_phase` if
  zero.

## Interview angle

- "Port vs export vs imp?" Caller / forwarder / implementer.
- "Analysis port vs put port?" Broadcast nonblocking function vs point-to-point blocking task.
- "How does one scoreboard receive from two monitors?" `uvm_analysis_imp_decl` or analysis FIFOs.
- "Why must `write()` not block?" It is a function called in the producer's thread.
- "What happens if you `write()` the same object every cycle?" Every subscriber's stored handle
  changes underneath it.

## Mentor's notes

- Connect coverage and scoreboard to the *same* monitor port. If they ever disagree about what
  happened, you have a bug in one of them, and the disagreement is free.
- Add a `uvm_analysis_port` to your scoreboard that emits (expected, actual) pairs. A debug
  subscriber that logs them beats print statements inside the scoreboard.
