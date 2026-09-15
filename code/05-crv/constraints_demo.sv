// Chapter 5: constraints in practice. No DUT; the output IS the lesson.
// Compile: vlog -sv constraints_demo.sv ; Run: vsim -c constraints_demo -do "run -all; quit"
// Read each section's $display against docs/05-constrained-random/.
`timescale 1ns/1ps

// ---------------------------------------------------------------------------------------------
// A FIFO write transaction with layered constraints.
// ---------------------------------------------------------------------------------------------
class fifo_txn;
  rand bit [7:0] data;
  rand bit       wr, rd;
  rand int       gap;              // idle cycles before this transaction

  // Legal space (hard): what the interface allows
  constraint c_gap   { gap inside {[0:8]}; }
  // Defaults (soft): what a test gets if it says nothing
  constraint c_dflt  { soft wr dist {1 := 7, 0 := 3}; soft rd dist {1 := 5, 0 := 5}; soft gap == 0; }
  // Bias data toward corners so the 'zero' and 'max' coverage bins close without directed tests
  constraint c_data  { data dist {8'h00 :/ 5, 8'hFF :/ 5, [8'h01:8'hFE] :/ 90}; }

  function string str();
    return $sformatf("wr=%0b rd=%0b data=%02h gap=%0d", wr, rd, data, gap);
  endfunction
endclass

// Same-name override narrows the legal gap; new-name adds a rule.
class bursty_txn extends fifo_txn;
  constraint c_gap { gap inside {[0:1]}; }            // OVERRIDES fifo_txn::c_gap
  constraint c_wr  { wr == 1; }                       // ADDS
endclass

// ---------------------------------------------------------------------------------------------
// The implication trap: uniform-over-solutions makes 'error' rare.
// ---------------------------------------------------------------------------------------------
class impl_trap;
  rand bit       error;
  rand bit [7:0] len;
  constraint c { error -> len < 4; }                  // when error, only 4 lens; else 256 lens
endclass

class impl_fixed extends impl_trap;
  constraint c_order { solve error before len; }      // pick error first, uniformly
endclass

// ---------------------------------------------------------------------------------------------
// Arrays: size, per-element, uniqueness, sum.
// ---------------------------------------------------------------------------------------------
class packet;
  rand bit [7:0] payload[];
  rand bit [3:0] tag;
  bit   [7:0]    checksum;                            // derived, not rand
  constraint c_size { payload.size() inside {[2:6]}; }
  constraint c_uniq { unique {payload}; }
  constraint c_sum  { payload.sum() with (int'(item)) < 600; }
  constraint c_e0   { payload[0] inside {[1:15]}; }   // index 0 always exists because size >= 2
  function void post_randomize();
    checksum = 0;
    foreach (payload[i]) checksum ^= payload[i];
  endfunction
endclass

// ---------------------------------------------------------------------------------------------
module constraints_demo;
  int hist[int];

  function automatic void print_hist(string title, ref int h[int]);
    $display("--- %s ---", title);
    foreach (h[k]) $display("  %0d : %0d", k, h[k]);
    h.delete();
  endfunction

  initial begin
    automatic fifo_txn   t   = new();
    automatic bursty_txn bt  = new();
    automatic impl_trap  it  = new();
    automatic impl_fixed ifx = new();
    automatic packet     p   = new();

    $display("=== 1. default (soft) behaviour ===");
    repeat (5) begin
      if (!t.randomize()) $fatal(1, "randomize failed");
      $display("  %s", t.str());
    end

    $display("=== 2. in-line constraints override soft defaults ===");
    repeat (3) begin
      if (!t.randomize() with { rd == 0; gap inside {[4:8]}; }) $fatal(1, "randomize failed");
      $display("  %s", t.str());
    end

    $display("=== 3. in-line constraint that conflicts with a HARD one: must fail, and we must notice ===");
    if (!t.randomize() with { gap == 20; }) $display("  randomize() returned 0 as expected (gap==20 vs gap inside [0:8]). Object unchanged: %s", t.str());
    else $display("  UNEXPECTED: solver accepted gap==20");

    $display("=== 4. derived class: same-name override + added constraint ===");
    repeat (4) begin
      if (!bt.randomize()) $fatal(1, "randomize failed");
      $display("  %s", bt.str());
    end

    $display("=== 5. data distribution: extremes should be ~5%% each ===");
    repeat (2000) begin
      void'(t.randomize());
      if (t.data == 8'h00) hist[0]++; else if (t.data == 8'hFF) hist[255]++; else hist[1]++;
    end
    print_hist("data histogram (0, body=1, 255) over 2000", hist);

    $display("=== 6. implication trap vs solve...before ===");
    repeat (2000) begin void'(it.randomize());  hist[it.error]++;  end
    print_hist("impl_trap: error over 2000 (expect ~1.5%% ones)", hist);
    repeat (2000) begin void'(ifx.randomize()); hist[ifx.error]++; end
    print_hist("impl_fixed: error over 2000 (expect ~50%% ones)", hist);

    $display("=== 7. arrays ===");
    repeat (3) begin
      if (!p.randomize()) $fatal(1, "randomize failed");
      $display("  size=%0d payload=%p sum=%0d checksum=%02h tag=%0d", p.payload.size(), p.payload, p.payload.sum() with (int'(item)), p.checksum, p.tag);
    end

    $display("=== 8. rand_mode / constraint_mode ===");
    t.data.rand_mode(0);  t.data = 8'h42;
    repeat (2) begin void'(t.randomize()); $display("  data frozen: %s", t.str()); end
    t.data.rand_mode(1);
    t.c_data.constraint_mode(0);
    $display("  c_data off: data now uniform (no extreme bias)");
    t.c_data.constraint_mode(1);

    $display("=== 9. randcase for choosing a transaction type ===");
    repeat (1000) begin
      randcase
        70: hist[0]++;   // read
        25: hist[1]++;   // write
         5: hist[2]++;   // idle
      endcase
    end
    print_hist("randcase (0=read 70%%, 1=write 25%%, 2=idle 5%%)", hist);

    $finish;
  end
endmodule
