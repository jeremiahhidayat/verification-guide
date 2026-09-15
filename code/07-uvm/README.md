# Code for Chapter 7: A UVM Environment for the FIFO

| File | Contents |
|---|---|
| `fifo_uvm_pkg.sv` | Config object, two sequence items (hand-written `do_*`), drivers, monitors, agents (active/passive), scoreboard with `uvm_analysis_imp_decl`, two coverage subscribers, virtual sequencer, environment, per-interface sequences, two virtual sequences, base test + 3 tests, a factory-override demo |
| `tb_top.sv` | Static top: clock, reset, interfaces (reused from chapter 6), DUT, config_db publish, `run_test()`, SVA routed to `uvm_error` |
| `files.f` | Compile list |

```
# Questa (UVM 1.2 ships precompiled; QUESTA_HOME is your install dir)
vlib work
vlog -sv -mfcu -f files.f          # Questa auto-imports its bundled uvm_pkg (mtiUvm); add +incdir+$QUESTA_HOME/verilog_src/uvm-1.2/src to pin 1.2
vsim -c tb_top +UVM_TESTNAME=fifo_random_test     +UVM_VERBOSITY=UVM_LOW -do "run -all; quit"
vsim -c tb_top +UVM_TESTNAME=fifo_fill_drain_test +UVM_VERBOSITY=UVM_LOW -do "run -all; quit"
vsim -c tb_top +UVM_TESTNAME=fifo_corner_test     +UVM_VERBOSITY=UVM_LOW -do "run -all; quit"

# Useful plusargs
+UVM_VERBOSITY=UVM_HIGH        # see every driver/monitor transaction
+UVM_CONFIG_DB_TRACE           # debug config_db set/get mismatches
+UVM_OBJECTION_TRACE           # debug a test that ends early or never
+UVM_TIMEOUT=2000000,YES       # global watchdog
-sv_seed 1234                  # reproduce a failure

# Mutation check
vlog -sv -mfcu +define+BUG_FULL_OFF_BY_ONE -f files.f
vsim -c tb_top +UVM_TESTNAME=fifo_fill_drain_test -do "run -all; quit"   # must report TEST FAILED
```

Map from the chapter-6 plain-SV testbench to this one:

| Chapter 6 | Chapter 7 |
|---|---|
| `mailbox #(wr_txn) gen2wr` | `sequencer` + `seq_item_port` |
| `random_wr_gen::run()` | `fifo_wr_seq::body()` with `start_item`/`finish_item` |
| `wr_monitor.to_sb.put(t)` | `ap.write(t)` to `uvm_analysis_imp_wr` |
| `environment::new(w, r)` constructor injection | `build_phase` + `connect_phase` + `uvm_config_db` |
| `+TEST=random` `case` in the top | `+UVM_TESTNAME` and the factory |
| `base_test.report()` | `report_phase` reading the report server |
| `#1ms $fatal` timeout | `+UVM_TIMEOUT` |
| polymorphic `base_gen` handle | factory type override (`fifo_corner_test`) |

Exercises:
1. Run `fifo_corner_test` and find the `factory.print()` output confirming the override. Then move the `set_type_override` call *after* `super.build_phase` and observe that it no longer takes effect.
2. Make the read agent passive (`cfg.rd_active = UVM_PASSIVE` in a new test) and drive `rd_en` from an `initial` block in `tb_top`. Confirm the scoreboard still checks.
3. Add `+UVM_CONFIG_DB_TRACE` and change the field name `"vif"` to `"vif_"` in one driver's `get`. Read the trace to find the mismatch.
4. Add a `fifo_reset_vseq` that pulses `rst` mid-traffic (drive it from a new `reset_if` or a task in `tb_top` reached via config_db) and make the scoreboard and monitors survive it.
