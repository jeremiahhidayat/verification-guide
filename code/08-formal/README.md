# Code for Chapter 8: Formal

| File | What it is |
|---|---|
| `fifo_formal.sv` | A wrapper around the FIFO with formal properties: reset checks without `disable iff`, local invariants, helper invariants for induction, end-to-end data integrity via a symbolic tracked write, and reachability covers. Uses the SVA subset SymbiYosys supports. |
| `fifo.sby` | SymbiYosys script with three tasks: unbounded `prove` (IC3/PDR via abc), `bmc` to depth 40, and `cover`. |

```
# Open-source flow (install: yosys, SymbiYosys, yices or boolector; e.g. via OSS CAD Suite)
sby -f fifo.sby prove      # expect: all assertions PASS (full proof)
sby -f fifo.sby cover      # expect: every cover reached; traces in fifo_cover/engine_0/trace*.vcd
sby -f fifo.sby bmc

# Mutation check: formal must produce a counterexample
cp ../02-basic-tb/fifo.sv fifo_bug.sv
sed -i '1i `define BUG_DROP_ON_SIMUL' fifo_bug.sv          # enable one of the bug hooks
sed -i 's|../02-basic-tb/fifo.sv|fifo_bug.sv|' fifo.sby     # point the script at it
sby -f fifo.sby prove   # -> ap_e2e / ap_cnt_* FAIL with a short trace in fifo_prove/engine_0/trace.vcd
```

Commercial tools (JasperGold, VC Formal, Questa Formal): compile `../02-basic-tb/fifo.sv` and
`fifo_formal.sv` as the top (its `tracked_data`/`start` ports are free inputs, which is exactly what
the symbolic tracking needs), or use `../03-sva/fifo_sva.sv` with the bind file from chapter 3.
Everything is standard SVA and compiles unchanged in Questa (`vlog -sv`), so the properties can also
be run in simulation.

Exercises:
1. Remove `ap_cnt_ptrs` (a helper). Does `ap_e2e` still prove in `prove` mode, or does it become inconclusive / need more depth? This is what "helper invariants strengthen induction" means.
2. Add `assume property (@(posedge clk) full |-> !wr_en);` and rerun `cover`. Which cover becomes unreachable? That is over-constraint detection working.
3. Change `DEPTH` to 64 and rerun. Note how BMC depth requirements grow with FIFO depth while the unbounded proof does not.
4. Write a bounded liveness property: "an accepted write is read within DEPTH + 2 cycles provided `rd_en` is held high." Add the necessary assumption and prove it.
