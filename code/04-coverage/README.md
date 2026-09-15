# Code for Chapter 4: Coverage

| File | What it is |
|---|---|
| `fifo_cov.sv` | A bindable coverage module: occupancy bins with `at_least`, level-transition bins, an `illegal_bins` overflow check, a `binsof` cross naming the six corner combinations, `iff`-gated data bins, cover properties for scenarios, and a `final` summary. |
| `fifo_cov_bind.sv` | Attaches it to every `fifo`. |

```
vlib work
vlog -sv -mfcu +cover=bcesf ../02-basic-tb/fifo.sv fifo_cov.sv fifo_cov_bind.sv ../02-basic-tb/fifo_tb.sv
vsim -c -coverage fifo_tb -do "run -all; coverage report -details -cvg -file cov.txt; coverage save fifo.ucdb; quit"
```

Exercises:
1. Run with `-gNUM_TESTS=500`. Which cross bins are missing? Now run the full test. Which are *still* missing, and which stimulus phase would hit them?
2. Change the chapter 2 stimulus to pure 50/50 random (delete phases 1 and 2). Watch `wr_at_full` and `rd_at_empty` go to zero. This is why constraints get biased.
3. Add a coverpoint for "number of cycles spent full" using a counter, with bins `{[1:2], [3:8], [9:$]}`.
4. Merge two runs with different seeds (`coverage save` each, then `vcover merge`) and compare the cross percentage to each run alone.
