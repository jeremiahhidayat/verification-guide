# Code for Chapter 1: SystemVerilog Fundamentals

| File | Demonstrates | Run |
|---|---|---|
| `races.sv` | The classic blocking-assignment race, the reset race (two file orderings), the NBA fix, and the proof that NBA order is irrelevant | `vsim -c race_bad`, `race_fixed`, `reset_race_a`, `reset_race_b`, `reset_race_fixed`, `nba_order_proof` |
| `datatypes_demo.sv` | 4-state vs 2-state, queues, dynamic and associative arrays, enums, packed structs, width and sign rules, streaming | `vsim -c datatypes_demo` |
| `multidim_demo.sv` | 3-D packed vs 3-D unpacked arrays: slicing, assignment patterns vs concatenation, `foreach` with two indexes | `vsim -c multidim_demo` |
| `packet_dynarray.sv` | A `rand` dynamic array in a class whose length is set by a `size()` constraint, collected into a queue of handles | `vsim -c packet_dynarray` |

```
vlib work
vlog -sv races.sv datatypes_demo.sv multidim_demo.sv packet_dynarray.sv
vsim -c race_bad -do "run -all; quit"
```

Verilator note: `race_*` modules compile with `--timing`; results may differ from event-driven
simulators, which is the point.
