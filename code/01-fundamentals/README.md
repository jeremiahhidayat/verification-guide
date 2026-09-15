# Code for Chapter 1: SystemVerilog Fundamentals

| File | Demonstrates | Run |
|---|---|---|
| `races.sv` | The classic blocking-assignment race, the reset race (two file orderings), the NBA fix, and the proof that NBA order is irrelevant | `vsim -c race_bad`, `race_fixed`, `reset_race_a`, `reset_race_b`, `reset_race_fixed`, `nba_order_proof` |
| `datatypes_demo.sv` | 4-state vs 2-state, queues, dynamic and associative arrays, enums, packed structs, width and sign rules, streaming | `vsim -c datatypes_demo` |

```
vlib work
vlog -sv races.sv datatypes_demo.sv
vsim -c race_bad -do "run -all; quit"
```

Verilator note: `race_*` modules compile with `--timing`; results may differ from event-driven
simulators, which is the point.
