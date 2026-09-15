# Code for Chapter 3: SVA

| File | What it is |
|---|---|
| `fifo_sva.sv` | A checker module for the FIFO: white-box invariants, count arithmetic, misuse-ignored rules, the tagged ordering property, reset behavior, and cover properties. Uses `default clocking` and `default disable iff`. |
| `fifo_bind.sv` | One-line `bind` that attaches the checker to every `fifo` instance. |
| `sva_patterns_tb.sv` | Two tiny DUTs (req/ack, enabled pipeline) with their specs written as assertions, both backward-looking (`$past`) and forward-looking (local variable) styles. |

```
vlib work
# Bound checker on the chapter 2 testbench (no changes to fifo_tb needed)
vlog -sv -mfcu ../02-basic-tb/fifo.sv fifo_sva.sv fifo_bind.sv ../02-basic-tb/fifo_tb.sv   # -mfcu: bind at unit scope
vsim -c fifo_tb -do "run -all; quit"

# Pattern demo
vlog -sv sva_patterns_tb.sv
vsim -c sva_patterns_tb -do "run -all; quit"

# Mutation checks: each must produce assertion failures
vlog -sv +define+BUG_FULL_OFF_BY_ONE ../02-basic-tb/fifo.sv fifo_sva.sv fifo_bind.sv ../02-basic-tb/fifo_tb.sv
```

Exercises:
1. In `sva_patterns_tb.sv`, change `req_ack`'s `DELAY` to 4. Which assertion fails, and does the message tell you enough to diagnose it?
2. Remove `en` from the `$past(data_in, L, en)` call. Explain the failures using the sampling model.
3. Change reset release to happen on the posedge (`rst <= 0` right after `@(posedge clk)`). Which properties fail and why (section 3.3, P1)?
4. Look at the coverage report for the `cp_*` properties. Which corners does the random pipeline stimulus miss? Add directed stimulus to hit them.

Notes: `disable iff (1'b0)` on the reset-behaviour properties overrides the module's `default disable iff (rst)` (you cannot check reset while disabled by reset). Questa warns "No trigger event inferred in disable expression" for it; that is expected. Questa also wants `-mfcu` when a `bind` sits at compilation-unit scope.
