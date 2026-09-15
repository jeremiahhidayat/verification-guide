// Chapter 7: a complete UVM environment for the FIFO.
// Two agents (write side, read side), a scoreboard fed by both monitors through analysis imps,
// a coverage subscriber, a config object, a virtual sequencer + virtual sequences, and three tests.
// Read order matches docs/07-uvm/02-components.md.
`timescale 1ns/1ps

package fifo_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int WIDTH = 8;
  localparam int DEPTH = 16;

  typedef virtual fifo_wr_if #(WIDTH) wr_vif_t;
  typedef virtual fifo_rd_if #(WIDTH) rd_vif_t;

  // =============================================================================================
  // Configuration object: one per env, set by the test, read by everyone.
  // =============================================================================================
  class fifo_env_cfg extends uvm_object;
    `uvm_object_utils(fifo_env_cfg)
    wr_vif_t wr_vif;
    rd_vif_t rd_vif;
    uvm_active_passive_enum wr_active = UVM_ACTIVE;
    uvm_active_passive_enum rd_active = UVM_ACTIVE;
    rand int wr_max_gap = 4;
    rand int rd_max_gap = 4;
    constraint c_gaps { wr_max_gap inside {[0:8]}; rd_max_gap inside {[0:8]}; }
    function new(string name = "fifo_env_cfg"); super.new(name); endfunction
    virtual function string convert2string();
      return $sformatf("wr_active=%s rd_active=%s wr_max_gap=%0d rd_max_gap=%0d",
                       wr_active.name(), rd_active.name(), wr_max_gap, rd_max_gap);
    endfunction
  endclass

  // =============================================================================================
  // Sequence items. Hand-written do_copy/do_compare/convert2string (no field macros).
  // =============================================================================================
  class fifo_wr_item extends uvm_sequence_item;
    `uvm_object_utils(fifo_wr_item)
    rand bit [WIDTH-1:0] data;
    rand int             gap;
    bit                  accepted;          // observed
    int                  max_gap = 4;       // knob copied from cfg by the sequence

    constraint c_gap  { gap inside {[0:max_gap]}; soft gap dist {0 := 6, [1:8] :/ 4}; }
    constraint c_data { data dist {'0 :/ 5, '1 :/ 5, [1:{WIDTH{1'b1}}-1] :/ 90}; }

    function new(string name = "fifo_wr_item"); super.new(name); endfunction

    virtual function void do_copy(uvm_object rhs);
      fifo_wr_item o;
      if (!$cast(o, rhs)) `uvm_fatal("CPY", "do_copy type mismatch")
      super.do_copy(rhs);
      data = o.data; gap = o.gap; accepted = o.accepted; max_gap = o.max_gap;
    endfunction

    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      fifo_wr_item o;
      if (!$cast(o, rhs)) return 0;
      return super.do_compare(rhs, comparer) && (data == o.data);
    endfunction

    virtual function string convert2string();
      return $sformatf("WR data=%02h gap=%0d accepted=%0b", data, gap, accepted);
    endfunction
  endclass

  class fifo_rd_item extends uvm_sequence_item;
    `uvm_object_utils(fifo_rd_item)
    rand int          gap;
    bit [WIDTH-1:0]   data;                 // observed
    bit               accepted;             // observed
    int               max_gap = 4;

    constraint c_gap { gap inside {[0:max_gap]}; soft gap dist {0 := 6, [1:8] :/ 4}; }

    function new(string name = "fifo_rd_item"); super.new(name); endfunction

    virtual function void do_copy(uvm_object rhs);
      fifo_rd_item o;
      if (!$cast(o, rhs)) `uvm_fatal("CPY", "do_copy type mismatch")
      super.do_copy(rhs);
      gap = o.gap; data = o.data; accepted = o.accepted; max_gap = o.max_gap;
    endfunction

    virtual function string convert2string();
      return $sformatf("RD data=%02h gap=%0d accepted=%0b", data, gap, accepted);
    endfunction
  endclass

  // =============================================================================================
  // Sequencers: the base class is sufficient.
  // =============================================================================================
  typedef uvm_sequencer #(fifo_wr_item) fifo_wr_sequencer;
  typedef uvm_sequencer #(fifo_rd_item) fifo_rd_sequencer;

  // =============================================================================================
  // Drivers: transaction -> pins. Protocol timing lives here and nowhere else.
  // =============================================================================================
  class fifo_wr_driver extends uvm_driver #(fifo_wr_item);
    `uvm_component_utils(fifo_wr_driver)
    wr_vif_t vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(wr_vif_t)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", {"no wr vif for ", get_full_name()})
    endfunction

    task run_phase(uvm_phase phase);
      vif.wr_en <= 1'b0;
      @(posedge vif.clk iff !vif.rst);
      forever begin
        seq_item_port.get_next_item(req);
        `uvm_info("DRV", req.convert2string(), UVM_HIGH)
        repeat (req.gap) @(posedge vif.clk);
        vif.wr_data <= req.data;
        vif.wr_en   <= 1'b1;
        @(posedge vif.clk);
        vif.wr_en   <= 1'b0;
        seq_item_port.item_done();
      end
    endtask
  endclass

  class fifo_rd_driver extends uvm_driver #(fifo_rd_item);
    `uvm_component_utils(fifo_rd_driver)
    rd_vif_t vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(rd_vif_t)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", {"no rd vif for ", get_full_name()})
    endfunction

    task run_phase(uvm_phase phase);
      vif.rd_en <= 1'b0;
      @(posedge vif.clk iff !vif.rst);
      forever begin
        seq_item_port.get_next_item(req);
        repeat (req.gap) @(posedge vif.clk);
        vif.rd_en <= 1'b1;
        @(posedge vif.clk);
        vif.rd_en <= 1'b0;
        seq_item_port.item_done();
      end
    endtask
  endclass

  // =============================================================================================
  // Monitors: pins -> transactions, broadcast on analysis ports. Never trust the driver.
  // =============================================================================================
  class fifo_wr_monitor extends uvm_monitor;
    `uvm_component_utils(fifo_wr_monitor)
    wr_vif_t vif;
    uvm_analysis_port #(fifo_wr_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(wr_vif_t)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", {"no wr vif for ", get_full_name()})
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        fifo_wr_item t;
        @(posedge vif.clk iff (!vif.rst && vif.wr_en));
        t = fifo_wr_item::type_id::create("t");     // new object per observation
        t.data     = vif.wr_data;
        t.accepted = !vif.full;
        `uvm_info("MON_WR", t.convert2string(), UVM_HIGH)
        ap.write(t);
      end
    endtask
  endclass

  class fifo_rd_monitor extends uvm_monitor;
    `uvm_component_utils(fifo_rd_monitor)
    rd_vif_t vif;
    uvm_analysis_port #(fifo_rd_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(rd_vif_t)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", {"no rd vif for ", get_full_name()})
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        fifo_rd_item t;
        @(posedge vif.clk iff (!vif.rst && vif.rd_en));
        t = fifo_rd_item::type_id::create("t");
        t.accepted = !vif.empty;
        if (t.accepted) begin
          @(posedge vif.clk);                        // 1-cycle read latency
          t.data = vif.rd_data;
        end
        `uvm_info("MON_RD", t.convert2string(), UVM_HIGH)
        ap.write(t);
      end
    endtask
  endclass

  // =============================================================================================
  // Agents: active builds driver+sequencer; passive builds only the monitor.
  // =============================================================================================
  class fifo_wr_agent extends uvm_agent;
    `uvm_component_utils(fifo_wr_agent)
    fifo_wr_sequencer sequencer;
    fifo_wr_driver    driver;
    fifo_wr_monitor   monitor;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);                       // reads "is_active" from config_db
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

  class fifo_rd_agent extends uvm_agent;
    `uvm_component_utils(fifo_rd_agent)
    fifo_rd_sequencer sequencer;
    fifo_rd_driver    driver;
    fifo_rd_monitor   monitor;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      monitor = fifo_rd_monitor::type_id::create("monitor", this);
      if (get_is_active() == UVM_ACTIVE) begin
        sequencer = fifo_rd_sequencer::type_id::create("sequencer", this);
        driver    = fifo_rd_driver::type_id::create("driver", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if (get_is_active() == UVM_ACTIVE) driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass

  // =============================================================================================
  // Scoreboard: two analysis imps (one per monitor), a queue model, leftovers checked in check_phase.
  // =============================================================================================
  `uvm_analysis_imp_decl(_wr)
  `uvm_analysis_imp_decl(_rd)

  class fifo_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(fifo_scoreboard)
    uvm_analysis_imp_wr #(fifo_wr_item, fifo_scoreboard) wr_imp;
    uvm_analysis_imp_rd #(fifo_rd_item, fifo_scoreboard) rd_imp;
    bit [WIDTH-1:0] model_q[$];
    int passed, failed, writes_seen, reads_seen;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      wr_imp = new("wr_imp", this);
      rd_imp = new("rd_imp", this);
    endfunction

    function void write_wr(fifo_wr_item t);
      writes_seen++;
      if (t.accepted) begin
        if (model_q.size() >= DEPTH) begin
          failed++;
          `uvm_error("SB", "DUT accepted a write while the model is full")
        end else model_q.push_back(t.data);
      end
    endfunction

    function void write_rd(fifo_rd_item t);
      bit [WIDTH-1:0] exp;
      if (!t.accepted) return;
      reads_seen++;
      if (model_q.size() == 0) begin
        failed++;
        `uvm_error("SB", $sformatf("DUT produced read data %02h with an empty model", t.data))
        return;
      end
      exp = model_q.pop_front();
      if (t.data !== exp) begin
        failed++;
        `uvm_error("SB", $sformatf("rd_data=%02h expected=%02h", t.data, exp))
      end else passed++;
    endfunction

    function void check_phase(uvm_phase phase);
      if (model_q.size() != 0)
        `uvm_error("SB", $sformatf("%0d items left in the model at end of test", model_q.size()))
      if (writes_seen == 0 || reads_seen == 0)
        `uvm_error("SB", $sformatf("scoreboard saw %0d writes and %0d reads: is it connected?", writes_seen, reads_seen))
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("SB", $sformatf("%0d passed, %0d failed, %0d writes seen, %0d reads seen", passed, failed, writes_seen, reads_seen), UVM_LOW)
    endfunction
  endclass

  // =============================================================================================
  // Coverage subscribers.
  // =============================================================================================
  class fifo_wr_coverage extends uvm_subscriber #(fifo_wr_item);
    `uvm_component_utils(fifo_wr_coverage)
    fifo_wr_item t;
    covergroup cg;
      option.per_instance = 1;
      cp_data: coverpoint t.data { bins zero = {0}; bins max = {'1}; bins mid[4] = {[1:{WIDTH{1'b1}}-1]}; }
      cp_acc:  coverpoint t.accepted { bins accepted = {1}; bins rejected_full = {0}; }
      cp_gap:  coverpoint t.gap { bins b2b = {0}; bins gap[] = {[1:4]}; bins big = {[5:$]}; }
    endgroup
    function new(string name, uvm_component parent); super.new(name, parent); cg = new(); endfunction
    function void write(fifo_wr_item t);
      this.t = t;
      cg.sample();
    endfunction
    function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("write coverage %0.1f%%", cg.get_inst_coverage()), UVM_LOW)
    endfunction
  endclass

  class fifo_rd_coverage extends uvm_subscriber #(fifo_rd_item);
    `uvm_component_utils(fifo_rd_coverage)
    fifo_rd_item t;
    covergroup cg;
      option.per_instance = 1;
      cp_acc: coverpoint t.accepted { bins accepted = {1}; bins rejected_empty = {0}; }
    endgroup
    function new(string name, uvm_component parent); super.new(name, parent); cg = new(); endfunction
    function void write(fifo_rd_item t);
      this.t = t;
      cg.sample();
    endfunction
    function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("read coverage %0.1f%%", cg.get_inst_coverage()), UVM_LOW)
    endfunction
  endclass

  // =============================================================================================
  // Virtual sequencer: holds handles to the real sequencers; drives nothing itself.
  // =============================================================================================
  class fifo_vsequencer extends uvm_sequencer;
    `uvm_component_utils(fifo_vsequencer)
    fifo_wr_sequencer wr_sqr;
    fifo_rd_sequencer rd_sqr;
    fifo_env_cfg      cfg;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
  endclass

  // =============================================================================================
  // Environment.
  // =============================================================================================
  class fifo_env extends uvm_env;
    `uvm_component_utils(fifo_env)
    fifo_env_cfg     cfg;
    fifo_wr_agent    wr_agent;
    fifo_rd_agent    rd_agent;
    fifo_scoreboard  sb;
    fifo_wr_coverage wr_cov;
    fifo_rd_coverage rd_cov;
    fifo_vsequencer  vsqr;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(fifo_env_cfg)::get(this, "", "cfg", cfg)) `uvm_fatal("NOCFG", "fifo_env_cfg not set")
      `uvm_info("ENV", {"config: ", cfg.convert2string()}, UVM_LOW)

      // Distribute what the children need. Targeted paths, not "*".
      uvm_config_db#(wr_vif_t)::set(this, "wr_agent.*", "vif", cfg.wr_vif);
      uvm_config_db#(rd_vif_t)::set(this, "rd_agent.*", "vif", cfg.rd_vif);
      uvm_config_db#(uvm_active_passive_enum)::set(this, "wr_agent", "is_active", cfg.wr_active);
      uvm_config_db#(uvm_active_passive_enum)::set(this, "rd_agent", "is_active", cfg.rd_active);

      wr_agent = fifo_wr_agent::type_id::create("wr_agent", this);
      rd_agent = fifo_rd_agent::type_id::create("rd_agent", this);
      sb       = fifo_scoreboard::type_id::create("sb", this);
      wr_cov   = fifo_wr_coverage::type_id::create("wr_cov", this);
      rd_cov   = fifo_rd_coverage::type_id::create("rd_cov", this);
      vsqr     = fifo_vsequencer::type_id::create("vsqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      wr_agent.monitor.ap.connect(sb.wr_imp);
      rd_agent.monitor.ap.connect(sb.rd_imp);
      wr_agent.monitor.ap.connect(wr_cov.analysis_export);
      rd_agent.monitor.ap.connect(rd_cov.analysis_export);
      vsqr.cfg = cfg;
      if (cfg.wr_active == UVM_ACTIVE) vsqr.wr_sqr = wr_agent.sequencer;
      if (cfg.rd_active == UVM_ACTIVE) vsqr.rd_sqr = rd_agent.sequencer;
    endfunction
  endclass

  // =============================================================================================
  // Sequences: per-interface, then virtual.
  // =============================================================================================
  class fifo_wr_seq extends uvm_sequence #(fifo_wr_item);
    `uvm_object_utils(fifo_wr_seq)
    rand int n;
    rand int max_gap;
    bit      sequential_data;                          // knob: 0,1,2,... instead of random
    constraint c_n   { n inside {[1:2000]}; }
    constraint c_gap { max_gap inside {[0:8]}; }
    function new(string name = "fifo_wr_seq"); super.new(name); endfunction

    virtual task body();
      `uvm_info("SEQ", $sformatf("fifo_wr_seq: n=%0d max_gap=%0d sequential=%0b", n, max_gap, sequential_data), UVM_LOW)
      for (int i = 0; i < n; i++) begin
        req = fifo_wr_item::type_id::create("req");   // factory: tests may override the item type
        req.max_gap = max_gap;
        start_item(req);
        if (sequential_data) begin
          if (!req.randomize() with { data == i[WIDTH-1:0]; gap == 0; }) `uvm_fatal("RND", "randomize failed")
        end else begin
          if (!req.randomize()) `uvm_fatal("RND", "randomize failed")
        end
        finish_item(req);
      end
    endtask
  endclass

  class fifo_rd_seq extends uvm_sequence #(fifo_rd_item);
    `uvm_object_utils(fifo_rd_seq)
    rand int n;
    rand int max_gap;
    constraint c_n   { n inside {[1:2000]}; }
    constraint c_gap { max_gap inside {[0:8]}; }
    function new(string name = "fifo_rd_seq"); super.new(name); endfunction

    virtual task body();
      `uvm_info("SEQ", $sformatf("fifo_rd_seq: n=%0d max_gap=%0d", n, max_gap), UVM_LOW)
      repeat (n) begin
        req = fifo_rd_item::type_id::create("req");
        req.max_gap = max_gap;
        start_item(req);
        if (!req.randomize()) `uvm_fatal("RND", "randomize failed")
        finish_item(req);
      end
    endtask
  endclass

  // Base virtual sequence: gives every scenario a typed p_sequencer.
  class fifo_base_vseq extends uvm_sequence;
    `uvm_object_utils(fifo_base_vseq)
    `uvm_declare_p_sequencer(fifo_vsequencer)
    function new(string name = "fifo_base_vseq"); super.new(name); endfunction
  endclass

  // Random concurrent traffic on both sides.
  class fifo_random_vseq extends fifo_base_vseq;
    `uvm_object_utils(fifo_random_vseq)
    rand int n;
    constraint c_n { n inside {[500:2000]}; }
    function new(string name = "fifo_random_vseq"); super.new(name); endfunction

    virtual task body();
      fifo_wr_seq wr = fifo_wr_seq::type_id::create("wr");
      fifo_rd_seq rd = fifo_rd_seq::type_id::create("rd");
      if (!wr.randomize() with { n == local::n; max_gap == p_sequencer.cfg.wr_max_gap; }) `uvm_fatal("RND", "")
      if (!rd.randomize() with { n == local::n; max_gap == p_sequencer.cfg.rd_max_gap; }) `uvm_fatal("RND", "")
      fork
        wr.start(p_sequencer.wr_sqr, this);
        rd.start(p_sequencer.rd_sqr, this);
      join
    endtask
  endclass

  // Fill completely (extra writes rejected), drain completely (extra reads rejected), then random.
  class fifo_fill_drain_vseq extends fifo_base_vseq;
    `uvm_object_utils(fifo_fill_drain_vseq)
    function new(string name = "fifo_fill_drain_vseq"); super.new(name); endfunction

    virtual task body();
      fifo_wr_seq wr = fifo_wr_seq::type_id::create("wr");
      fifo_rd_seq rd = fifo_rd_seq::type_id::create("rd");
      fifo_random_vseq rnd = fifo_random_vseq::type_id::create("rnd");

      wr.sequential_data = 1;
      if (!wr.randomize() with { n == DEPTH + 4; max_gap == 0; }) `uvm_fatal("RND", "")
      wr.start(p_sequencer.wr_sqr, this);

      if (!rd.randomize() with { n == DEPTH + 4; max_gap == 0; }) `uvm_fatal("RND", "")
      rd.start(p_sequencer.rd_sqr, this);

      if (!rnd.randomize() with { n == 300; }) `uvm_fatal("RND", "")
      rnd.start(p_sequencer, this);
    endtask
  endclass

  // =============================================================================================
  // Tests.
  // =============================================================================================
  class fifo_base_test extends uvm_test;
    `uvm_component_utils(fifo_base_test)
    fifo_env     env;
    fifo_env_cfg cfg;

    function new(string name = "fifo_base_test", uvm_component parent = null); super.new(name, parent); endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = fifo_env_cfg::type_id::create("cfg");
      if (!uvm_config_db#(wr_vif_t)::get(this, "", "wr_vif", cfg.wr_vif)) `uvm_fatal("NOVIF", "wr_vif not set by tb_top")
      if (!uvm_config_db#(rd_vif_t)::get(this, "", "rd_vif", cfg.rd_vif)) `uvm_fatal("NOVIF", "rd_vif not set by tb_top")
      configure();                                            // hook for derived tests
      uvm_config_db#(fifo_env_cfg)::set(this, "env", "cfg", cfg);
      env = fifo_env::type_id::create("env", this);
    endfunction

    virtual function void configure();
      if (!cfg.randomize()) `uvm_fatal("RND", "cfg randomize failed")
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
      uvm_top.print_topology();
    endfunction

    virtual function void report_phase(uvm_phase phase);
      uvm_report_server svr = uvm_report_server::get_server();
      if (svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR) == 0)
        `uvm_info("TEST", "*** TEST PASSED ***", UVM_NONE)
      else
        `uvm_info("TEST", "*** TEST FAILED ***", UVM_NONE)
    endfunction
  endclass

  class fifo_random_test extends fifo_base_test;
    `uvm_component_utils(fifo_random_test)
    function new(string name = "fifo_random_test", uvm_component parent = null); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
      fifo_random_vseq vseq = fifo_random_vseq::type_id::create("vseq");
      phase.raise_objection(this, "random traffic");
      if (!vseq.randomize()) `uvm_fatal("RND", "")
      vseq.start(env.vsqr);
      phase.phase_done.set_drain_time(this, 200ns);
      phase.drop_objection(this, "random traffic done");
    endtask
  endclass

  class fifo_fill_drain_test extends fifo_base_test;
    `uvm_component_utils(fifo_fill_drain_test)
    function new(string name = "fifo_fill_drain_test", uvm_component parent = null); super.new(name, parent); endfunction
    virtual function void configure();
      super.configure();
      cfg.wr_max_gap = 0;                    // override after randomization: deterministic bursts
    endfunction
    task run_phase(uvm_phase phase);
      fifo_fill_drain_vseq vseq = fifo_fill_drain_vseq::type_id::create("vseq");
      phase.raise_objection(this);
      vseq.start(env.vsqr);
      phase.phase_done.set_drain_time(this, 200ns);
      phase.drop_objection(this);
    endtask
  endclass

  // Factory override demo: every fifo_wr_item becomes a corner-heavy item without touching sequences.
  class corner_wr_item extends fifo_wr_item;
    `uvm_object_utils(corner_wr_item)
    constraint c_corner { data inside {8'h00, 8'h01, 8'h7F, 8'h80, 8'hFE, 8'hFF}; }
    function new(string name = "corner_wr_item"); super.new(name); endfunction
  endclass

  class fifo_corner_test extends fifo_random_test;
    `uvm_component_utils(fifo_corner_test)
    function new(string name = "fifo_corner_test", uvm_component parent = null); super.new(name, parent); endfunction
    virtual function void build_phase(uvm_phase phase);
      fifo_wr_item::type_id::set_type_override(corner_wr_item::get_type());   // BEFORE anything is created
      super.build_phase(phase);
    endfunction
    virtual function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      factory.print();
    endfunction
  endclass

endpackage
