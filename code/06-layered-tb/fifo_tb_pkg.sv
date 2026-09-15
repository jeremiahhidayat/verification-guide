// Chapter 6: the whole class-based testbench lives in one package.
// Read order: fifo_txn -> generators -> drivers -> monitors -> scoreboard -> coverage -> env -> tests.
`timescale 1ns/1ps

package fifo_tb_pkg;

  localparam int WIDTH = 8;
  localparam int DEPTH = 16;

  typedef virtual fifo_wr_if #(WIDTH) wr_vif_t;
  typedef virtual fifo_rd_if #(WIDTH) rd_vif_t;

  // =============================================================================================
  // Transactions. Two kinds because the two interfaces carry different information.
  // =============================================================================================
  class wr_txn;
    rand bit [WIDTH-1:0] data;
    rand int             gap;          // idle cycles before the write
    bit                  accepted;     // filled by the monitor: was the FIFO not full?
    time                 t;            // observed time

    constraint c_gap  { gap inside {[0:4]}; soft gap dist {0 := 6, [1:4] :/ 4}; }
    constraint c_data { data dist {'0 :/ 5, '1 :/ 5, [1:{WIDTH{1'b1}}-1] :/ 90}; }

    function string convert2string();
      return $sformatf("WR data=%02h gap=%0d accepted=%0b", data, gap, accepted);
    endfunction
  endclass

  class rd_txn;
    rand int          gap;
    bit [WIDTH-1:0]   data;            // observed
    bit               accepted;        // observed: was the FIFO not empty?
    time              t;

    constraint c_gap { gap inside {[0:4]}; soft gap dist {0 := 6, [1:4] :/ 4}; }

    function string convert2string();
      return $sformatf("RD data=%02h gap=%0d accepted=%0b", data, gap, accepted);
    endfunction
  endclass

  // =============================================================================================
  // Generators: abstract base + concrete scenarios. Tests choose which to instantiate.
  // =============================================================================================
  virtual class base_gen #(type T = wr_txn);
    mailbox #(T) mbx;
    int          n;
    function new(mailbox #(T) m, int num); mbx = m; n = num; endfunction
    pure virtual task run();
  endclass

  class random_wr_gen extends base_gen #(wr_txn);
    function new(mailbox #(wr_txn) m, int num); super.new(m, num); endfunction
    virtual task run();
      repeat (n) begin
        wr_txn t = new();
        if (!t.randomize()) $fatal(1, "wr_txn randomize failed");
        mbx.put(t);
      end
    endtask
  endclass

  class random_rd_gen extends base_gen #(rd_txn);
    function new(mailbox #(rd_txn) m, int num); super.new(m, num); endfunction
    virtual task run();
      repeat (n) begin
        rd_txn t = new();
        if (!t.randomize()) $fatal(1, "rd_txn randomize failed");
        mbx.put(t);
      end
    endtask
  endclass

  // Burst generator: no gaps, sequential data. Used by the fill/drain test to force full and empty.
  class burst_wr_gen extends base_gen #(wr_txn);
    function new(mailbox #(wr_txn) m, int num); super.new(m, num); endfunction
    virtual task run();
      for (int i = 0; i < n; i++) begin
        wr_txn t = new();
        if (!t.randomize() with { gap == 0; data == i[WIDTH-1:0]; }) $fatal(1, "randomize failed");
        mbx.put(t);
      end
    endtask
  endclass

  class burst_rd_gen extends base_gen #(rd_txn);
    function new(mailbox #(rd_txn) m, int num); super.new(m, num); endfunction
    virtual task run();
      repeat (n) begin
        rd_txn t = new();
        if (!t.randomize() with { gap == 0; }) $fatal(1, "randomize failed");
        mbx.put(t);
      end
    endtask
  endclass

  // =============================================================================================
  // Drivers: transaction -> pins. The only place that knows the write/read timing.
  // =============================================================================================
  class wr_driver;
    wr_vif_t          vif;
    mailbox #(wr_txn) mbx;
    event             done;              // pulsed after each transaction (lets a test know progress)
    int               driven;

    function new(wr_vif_t v, mailbox #(wr_txn) m); vif = v; mbx = m; endfunction

    virtual task run();
      vif.idle();
      @(posedge vif.clk iff !vif.rst);
      forever begin
        wr_txn t;
        mbx.get(t);
        repeat (t.gap) @(posedge vif.clk);
        vif.write(t.data);
        driven++;
        -> done;
      end
    endtask
  endclass

  class rd_driver;
    rd_vif_t          vif;
    mailbox #(rd_txn) mbx;
    event             done;
    int               driven;

    function new(rd_vif_t v, mailbox #(rd_txn) m); vif = v; mbx = m; endfunction

    virtual task run();
      vif.idle();
      @(posedge vif.clk iff !vif.rst);
      forever begin
        rd_txn t;
        mbx.get(t);
        repeat (t.gap) @(posedge vif.clk);
        vif.read();
        driven++;
        -> done;
      end
    endtask
  endclass

  // =============================================================================================
  // Monitors: pins -> transactions. Passive. They report what the DUT SAW, not what we intended.
  // =============================================================================================
  class wr_monitor;
    wr_vif_t          vif;
    mailbox #(wr_txn) to_sb, to_cov;
    function new(wr_vif_t v, mailbox #(wr_txn) sb, mailbox #(wr_txn) cov); vif = v; to_sb = sb; to_cov = cov; endfunction

    virtual task run();
      forever begin
        @(posedge vif.clk iff (!vif.rst && vif.wr_en));
        begin
          wr_txn t = new();                 // NEW object per observation: consumers keep handles
          t.data     = vif.wr_data;
          t.accepted = !vif.full;
          t.t        = $realtime;
          to_sb.put(t);
          to_cov.put(t);
        end
      end
    endtask
  endclass

  class rd_monitor;
    rd_vif_t          vif;
    mailbox #(rd_txn) to_sb, to_cov;
    function new(rd_vif_t v, mailbox #(rd_txn) sb, mailbox #(rd_txn) cov); vif = v; to_sb = sb; to_cov = cov; endfunction

    virtual task run();
      forever begin
        bit accepted;
        @(posedge vif.clk iff (!vif.rst && vif.rd_en));
        accepted = !vif.empty;
        if (accepted) begin
          @(posedge vif.clk);               // 1-cycle read latency: data is valid now
          begin
            rd_txn t = new();
            t.data = vif.rd_data; t.accepted = 1; t.t = $realtime;
            to_sb.put(t);
            to_cov.put(t);
          end
        end else begin
          rd_txn t = new();
          t.accepted = 0; t.t = $realtime;
          to_cov.put(t);                    // scoreboard does not care about rejected reads
        end
      end
    endtask
  endclass

  // =============================================================================================
  // Scoreboard: reference model (a queue) + comparison + bookkeeping.
  // =============================================================================================
  class scoreboard;
    mailbox #(wr_txn) from_wr;
    mailbox #(rd_txn) from_rd;
    bit [WIDTH-1:0]   model_q[$];
    int               passed, failed, writes_seen, reads_seen;

    function new(mailbox #(wr_txn) w, mailbox #(rd_txn) r); from_wr = w; from_rd = r; endfunction

    virtual task run();
      fork
        forever begin
          wr_txn t;
          from_wr.get(t);
          writes_seen++;
          if (t.accepted) begin
            if (model_q.size() >= DEPTH) begin
              failed++;
              $error("[%0t] SB: DUT accepted a write while the model is full", t.t);
            end else model_q.push_back(t.data);
          end
        end
        forever begin
          rd_txn t;
          bit [WIDTH-1:0] exp;
          from_rd.get(t);
          reads_seen++;
          if (model_q.size() == 0) begin
            failed++;
            $error("[%0t] SB: DUT produced read data %02h but the model is empty", t.t, t.data);
          end else begin
            exp = model_q.pop_front();
            if (t.data !== exp) begin
              failed++;
              $error("[%0t] SB: rd_data=%02h expected=%02h", t.t, t.data, exp);
            end else passed++;
          end
        end
      join
    endtask

    function void report(string name);
      $display("[%0t] SB(%s): %0d passed, %0d failed, %0d writes, %0d reads, %0d left in model",
               $realtime, name, passed, failed, writes_seen, reads_seen, model_q.size());
    endfunction
  endclass

  // =============================================================================================
  // Coverage collector: transaction-level sampling.
  // =============================================================================================
  class coverage;
    mailbox #(wr_txn) from_wr;
    mailbox #(rd_txn) from_rd;
    bit [WIDTH-1:0] wdata;  bit w_acc, r_acc;

    covergroup cg_wr;
      option.per_instance = 1;
      cp_data: coverpoint wdata { bins zero = {0}; bins max = {'1}; bins mid[4] = {[1:{WIDTH{1'b1}}-1]}; }
      cp_acc:  coverpoint w_acc { bins accepted = {1}; bins rejected_full = {0}; }
    endgroup
    covergroup cg_rd;
      option.per_instance = 1;
      cp_acc:  coverpoint r_acc { bins accepted = {1}; bins rejected_empty = {0}; }
    endgroup

    function new(mailbox #(wr_txn) w, mailbox #(rd_txn) r);
      from_wr = w; from_rd = r; cg_wr = new(); cg_rd = new();
    endfunction

    virtual task run();
      fork
        forever begin wr_txn t; from_wr.get(t); wdata = t.data; w_acc = t.accepted; cg_wr.sample(); end
        forever begin rd_txn t; from_rd.get(t); r_acc = t.accepted; cg_rd.sample(); end
      join
    endtask

    function void report();
      $display("COV: write %0.1f%%  read %0.1f%%", cg_wr.get_inst_coverage(), cg_rd.get_inst_coverage());
    endfunction
  endclass

  // =============================================================================================
  // Environment: constructs, connects, runs. Constructor injection: valid on construction.
  // =============================================================================================
  class environment;
    wr_vif_t wr_vif;  rd_vif_t rd_vif;

    mailbox #(wr_txn) gen2wr  = new();
    mailbox #(rd_txn) gen2rd  = new();
    mailbox #(wr_txn) wr2sb   = new();
    mailbox #(rd_txn) rd2sb   = new();
    mailbox #(wr_txn) wr2cov  = new();
    mailbox #(rd_txn) rd2cov  = new();

    base_gen #(wr_txn) wr_gen;         // chosen by the test
    base_gen #(rd_txn) rd_gen;
    wr_driver  wr_drv;   rd_driver  rd_drv;
    wr_monitor wr_mon;   rd_monitor rd_mon;
    scoreboard sb;
    coverage   cov;

    function new(wr_vif_t w, rd_vif_t r);
      wr_vif = w; rd_vif = r;
      wr_drv = new(w, gen2wr);
      rd_drv = new(r, gen2rd);
      wr_mon = new(w, wr2sb, wr2cov);
      rd_mon = new(r, rd2sb, rd2cov);
      sb     = new(wr2sb, rd2sb);
      cov    = new(wr2cov, rd2cov);
    endfunction

    // Run until both generators are exhausted and the drivers have drained, then a settle time.
    virtual task run(int drain_cycles = 20);
      fork
        wr_drv.run(); rd_drv.run(); wr_mon.run(); rd_mon.run(); sb.run(); cov.run();
      join_none
      fork
        wr_gen.run();
        rd_gen.run();
      join
      wait (gen2wr.num() == 0 && gen2rd.num() == 0);
      repeat (drain_cycles) @(posedge wr_vif.clk);
    endtask
  endclass

  // =============================================================================================
  // Tests: choose generators and scenario. Selected at run time with +TEST=<name>.
  // =============================================================================================
  virtual class base_test;
    string      name;
    environment env;
    function new(string n, environment e); name = n; env = e; endfunction
    pure virtual task run();
    function bit passed();
      return env.sb.failed == 0 && env.sb.model_q.size() == 0;
    endfunction
    function void report();
      env.sb.report(name);
      env.cov.report();
      $display("[%0t] TEST %s: %s", $realtime, name, passed() ? "PASSED" : "FAILED");
    endfunction
  endclass

  class random_test extends base_test;
    int n;
    function new(environment e, int num = 2000); super.new("random", e); n = num; endfunction
    virtual task run();
      env.wr_gen = random_wr_gen::new(env.gen2wr, n);
      env.rd_gen = random_rd_gen::new(env.gen2rd, n);
      env.run();
    endtask
  endclass

  // Fill completely (with extra writes rejected), then drain completely (with extra reads rejected).
  class fill_drain_test extends base_test;
    function new(environment e); super.new("fill_drain", e); endfunction
    virtual task run();
      env.wr_gen = burst_wr_gen::new(env.gen2wr, DEPTH + 4);
      env.rd_gen = burst_rd_gen::new(env.gen2rd, 0);
      env.run();
      env.wr_gen = burst_wr_gen::new(env.gen2wr, 0);
      env.rd_gen = burst_rd_gen::new(env.gen2rd, DEPTH + 4);
      env.run();
    endtask
  endclass

endpackage
