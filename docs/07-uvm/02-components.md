# 7.2 The Components

Each component below is shown as a minimal, correct template with the reasoning. The chapter's
`code/07-uvm/` has the full FIFO versions.

## Sequence item

```systemverilog
class fifo_wr_item extends uvm_sequence_item;
  rand bit [7:0] data;
  rand int       gap;
  bit            accepted;      // observed by the monitor, not randomized

  constraint c_gap { gap inside {[0:4]}; }

  `uvm_object_utils(fifo_wr_item)
  function new(string name = "fifo_wr_item"); super.new(name); endfunction

  virtual function void do_copy(uvm_object rhs);
    fifo_wr_item o; if (!$cast(o, rhs)) `uvm_fatal("CPY", "type mismatch");
    super.do_copy(rhs); data = o.data; gap = o.gap; accepted = o.accepted;
  endfunction
  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    fifo_wr_item o; if (!$cast(o, rhs)) return 0;
    return super.do_compare(rhs, comparer) && data == o.data;      // compare only what matters
  endfunction
  virtual function string convert2string();
    return $sformatf("data=%02h gap=%0d accepted=%0b", data, gap, accepted);
  endfunction
endclass
```

Keep interface-level legality constraints here; keep application-specific distributions in the
sequence (tutorial's `mult_sequence` argument). The item is what agents, monitors, and scoreboards
have in common, so it must be interface-specific and DUT-agnostic.

## Sequencer

```systemverilog
class fifo_wr_sequencer extends uvm_sequencer #(fifo_wr_item);
  `uvm_component_utils(fifo_wr_sequencer)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
endclass
// or simply:  typedef uvm_sequencer #(fifo_wr_item) fifo_wr_sequencer;
```

The sequencer arbitrates between sequences that want to send items and hands each item to the
driver. For one sequence at a time the base class is complete; you subclass only to add handles
(virtual sequencers, 7.3) or custom arbitration.

## Driver

```systemverilog
class fifo_wr_driver extends uvm_driver #(fifo_wr_item);
  `uvm_component_utils(fifo_wr_driver)
  virtual fifo_wr_if vif;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fifo_wr_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", {"no virtual interface for ", get_full_name()})
  endfunction

  task run_phase(uvm_phase phase);
    vif.wr_en <= 0;
    @(posedge vif.clk iff !vif.rst);
    forever begin
      seq_item_port.get_next_item(req);        // blocks until a sequence provides an item
      repeat (req.gap) @(posedge vif.clk);
      vif.wr_data <= req.data;  vif.wr_en <= 1'b1;
      @(posedge vif.clk);
      vif.wr_en <= 1'b0;
      seq_item_port.item_done();               // tells the sequencer (and the sequence) it is done
    end
  endtask
endclass
```

`req` is a member inherited from `uvm_driver`. `get_next_item` + `item_done` is the standard
handshake: the sequence's `finish_item` returns when `item_done` is called, so the sequence knows the
item has been driven. Alternative: `get` (implies `item_done`) and `put(rsp)` for responses (7.3).

The driver knows the protocol and nothing else. It does not check (that is the monitor and
scoreboard). It does not know which DUT it is talking to.

## Monitor

```systemverilog
class fifo_wr_monitor extends uvm_monitor;
  `uvm_component_utils(fifo_wr_monitor)
  virtual fifo_wr_if vif;
  uvm_analysis_port #(fifo_wr_item) ap;

  function new(string name, uvm_component parent); super.new(name, parent); ap = new("ap", this); endfunction
  function void build_phase(uvm_phase phase); ... get vif ... endfunction

  task run_phase(uvm_phase phase);
    forever begin
      fifo_wr_item t;
      @(posedge vif.clk iff (!vif.rst && vif.wr_en));
      t = fifo_wr_item::type_id::create("t");        // NEW object per observation
      t.data = vif.wr_data;  t.accepted = !vif.full;
      ap.write(t);                                   // broadcast to whoever is connected
    end
  endtask
endclass
```

The analysis port is deliberately unconnected here; the environment decides who listens. That is
what makes the agent reusable.

## Agent

```systemverilog
class fifo_wr_agent extends uvm_agent;
  `uvm_component_utils(fifo_wr_agent)
  fifo_wr_sequencer sequencer;
  fifo_wr_driver    driver;
  fifo_wr_monitor   monitor;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);                        // base reads "is_active" from config_db into is_active
    monitor = fifo_wr_monitor::type_id::create("monitor", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sequencer = fifo_wr_sequencer::type_id::create("sequencer", this);
      driver    = fifo_wr_driver::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE) driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass
```

An agent is "everything for one interface": the BFM of old. Active builds the driver and sequencer;
passive builds only the monitor. `is_active` comes from `uvm_config_db#(uvm_active_passive_enum)::set(this,
"env.wr_agent", "is_active", UVM_PASSIVE)` in a test. One agent class, N instances (tutorial's three
AXI-stream agents on one multiplier).

## Scoreboard

```systemverilog
class fifo_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(fifo_scoreboard)
  uvm_analysis_imp_wr #(fifo_wr_item, fifo_scoreboard) wr_imp;    // one imp per source (see 7.4)
  uvm_analysis_imp_rd #(fifo_rd_item, fifo_scoreboard) rd_imp;
  bit [7:0] model_q[$];
  int passed, failed;

  function new(string name, uvm_component parent);
    super.new(name, parent); wr_imp = new("wr_imp", this); rd_imp = new("rd_imp", this);
  endfunction

  function void write_wr(fifo_wr_item t);  if (t.accepted) model_q.push_back(t.data);  endfunction
  function void write_rd(fifo_rd_item t);
    if (model_q.size() == 0) begin failed++; `uvm_error("SB", "read with empty model") end
    else if (t.data !== model_q.pop_front()) begin failed++; `uvm_error("SB", "data mismatch") end
    else passed++;
  endfunction

  function void check_phase(uvm_phase phase);
    if (model_q.size() != 0) `uvm_error("SB", $sformatf("%0d items left in model", model_q.size()))
  endfunction
  function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf("%0d passed, %0d failed", passed, failed), UVM_LOW)
  endfunction
endclass
```

Analysis `write()` calls are *functions*: they must not block. For scoreboards that need to wait
(match a response to a request that arrives later), store into a queue in `write()` and process in
`run_phase`, or use `uvm_tlm_analysis_fifo` and `get()` in `run_phase` (tutorial's style, 7.4).

## Subscriber (coverage)

```systemverilog
class fifo_wr_coverage extends uvm_subscriber #(fifo_wr_item);
  `uvm_component_utils(fifo_wr_coverage)
  fifo_wr_item t;
  covergroup cg;  cp_data: coverpoint t.data { bins zero = {0}; bins max = {8'hFF}; bins mid[4] = {[1:254]}; }
                  cp_acc:  coverpoint t.accepted;  endgroup
  function new(string name, uvm_component parent); super.new(name, parent); cg = new(); endfunction
  function void write(fifo_wr_item t_);  t = t_;  cg.sample();  endfunction     // 'write' is the required name
endclass
```

`uvm_subscriber` is a component with a built-in `analysis_export`; connect a monitor's `ap` to it
and implement `write`. The standard home for coverage.

## Environment

```systemverilog
class fifo_env extends uvm_env;
  `uvm_component_utils(fifo_env)
  fifo_wr_agent    wr_agent;   fifo_rd_agent rd_agent;
  fifo_scoreboard  sb;
  fifo_wr_coverage wr_cov;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    wr_agent = fifo_wr_agent::type_id::create("wr_agent", this);
    rd_agent = fifo_rd_agent::type_id::create("rd_agent", this);
    sb       = fifo_scoreboard::type_id::create("sb", this);
    wr_cov   = fifo_wr_coverage::type_id::create("wr_cov", this);
  endfunction
  function void connect_phase(uvm_phase phase);
    wr_agent.monitor.ap.connect(sb.wr_imp);
    rd_agent.monitor.ap.connect(sb.rd_imp);
    wr_agent.monitor.ap.connect(wr_cov.analysis_export);      // one port, many listeners
  endfunction
endclass
```

The env is the DUT-specific wiring diagram. Agents are generic; the env knows there is a write side
and a read side and what to check between them.

## Test

```systemverilog
class fifo_base_test extends uvm_test;
  `uvm_component_utils(fifo_base_test)
  fifo_env env;
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = fifo_env::type_id::create("env", this);
  endfunction
  function void end_of_elaboration_phase(uvm_phase phase); uvm_top.print_topology(); endfunction
  function void report_phase(uvm_phase phase);
    uvm_report_server svr = uvm_report_server::get_server();
    if (svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR) == 0)
      `uvm_info("TEST", "*** TEST PASSED ***", UVM_NONE)
    else `uvm_info("TEST", "*** TEST FAILED ***", UVM_NONE)
  endfunction
endclass

class fifo_random_test extends fifo_base_test;
  `uvm_component_utils(fifo_random_test)
  task run_phase(uvm_phase phase);
    fifo_random_vseq vseq = fifo_random_vseq::type_id::create("vseq");
    phase.raise_objection(this);
    vseq.start(env.vsequencer);
    phase.drop_objection(this);
  endtask
endclass
```

A base test builds the env and prints the verdict; concrete tests set configuration (7.5) and start
sequences. Selected with `+UVM_TESTNAME=fifo_random_test`. New scenario = new test class; the
environment is untouched.

## Interview angle

- "Explain the driver/sequencer handshake." `get_next_item` blocks; drive; `item_done`; the
  sequence's `finish_item` returns.
- "Why is the monitor's analysis port unconnected inside the agent?" Reuse; the env connects it.
- "Active vs passive agent in UVM?" `is_active` from config_db; build driver/sequencer conditionally.
- "What is `uvm_subscriber`?" Component with an analysis export and a `write` you implement.
- "Where does the scoreboard check for leftovers?" `check_phase`.

## Mentor's notes

- Write the monitor first, hook it to a subscriber that just prints, and run the designer's
  test. You will understand the interface before writing a line of driver.
- Every agent needs a README with: item fields, constraints, config knobs, what the monitor
  publishes and when. Agents outlive projects; their documentation is what makes them reusable.
