# Code for Chapter 6: A Class-Based Layered Testbench

A complete plain-SystemVerilog layered environment for the FIFO. No UVM. Every wire is visible.

| File | Layer |
|---|---|
| `fifo_if.sv` | Signal layer: `fifo_wr_if`, `fifo_rd_if` with BFM tasks and interface-owned assertions |
| `fifo_tb_pkg.sv` | Everything else, in one package: transactions, generators (abstract base + 4 concrete), drivers, monitors, scoreboard (queue model), coverage collector, environment (constructor injection), base test + 2 tests |
| `tb_top.sv` | Static top: clock, reset, interfaces, DUT, `+TEST=` selection, global timeout |

```
vlib work
vlog -sv ../02-basic-tb/fifo.sv fifo_if.sv fifo_tb_pkg.sv tb_top.sv
vsim -c tb_top +TEST=random     -do "run -all; quit"
vsim -c tb_top +TEST=fill_drain -do "run -all; quit"

# Mutation check
vlog -sv +define+BUG_DROP_ON_SIMUL ../02-basic-tb/fifo.sv fifo_if.sv fifo_tb_pkg.sv tb_top.sv
vsim -c tb_top +TEST=random -do "run -all; quit"     # must report FAILED
```

Things to notice while reading:

- The monitors, not the drivers, feed the scoreboard. Rejected writes (FIFO full) are observed with `accepted = 0` and are *not* pushed to the model; the scoreboard therefore checks what the DUT actually did.
- The read monitor waits one extra cycle for the 1-cycle read latency. Latency knowledge lives in exactly one place.
- The environment is valid as soon as `new()` returns (constructor injection). The only thing a test sets afterward is *which generators* to use, through abstract base handles: that is polymorphism doing the work of a factory.
- `random_test` and `fill_drain_test` share the environment untouched. Adding a third test is one class.
- The global timeout in `tb_top` uses the nested `fork ... join_any; disable fork` idiom from section 6.2.

Exercises:
1. Add an `error_test` that uses `random_wr_gen` with an in-line constraint forcing `gap == 0` and a `random_rd_gen` with `gap inside {[3:4]}`, so the FIFO is usually full. Check the coverage report for `rejected_full`.
2. Make the write agent passive (skip constructing `wr_drv`) and drive the write interface from a plain `initial` block in `tb_top`. Confirm the scoreboard still checks everything.
3. Replace the two `mailbox` connections from monitors to scoreboard/coverage with a small "analysis port" class that broadcasts to a list of subscribers. You have just reinvented `uvm_analysis_port`.
