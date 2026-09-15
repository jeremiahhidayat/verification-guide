# D. Tool Commands

Equivalent flows for the common simulators and for open-source tools. Replace `<top>` and files.

## Questa / ModelSim (Siemens)
```
vlib work; vmap work work
vlog -sv -lint -mfcu [+cover=bcesft] [+define+NAME] [+incdir+dir] -f files.f
vopt <top> -o <top>_opt [+acc]                    # +acc keeps visibility (slower)
vsim -c <top>_opt -sv_seed 1234 [+UVM_TESTNAME=t] [-coverage] -do "run -all; quit -f"
vsim -c ... -do "coverage save -onexit cov.ucdb; run -all"
vcover merge all.ucdb run*.ucdb;  vcover report -details -html all.ucdb
vsim -assertdebug ...                             # assertion browser
vsim -c ... -do "log -r /*; run -all"             # WLF waves for all signals
UVM: bundled (mtiUvm); pin a version: +incdir+$QUESTA_HOME/verilog_src/uvm-1.2/src, -L $QUESTA_HOME/uvm-1.2
-suppress <id>, -permissive, -timescale 1ns/1ps, -solvefaildebug, -profile
```

## VCS (Synopsys)
```
vcs -sverilog -full64 -timescale=1ns/1ps -debug_access+all [-ntb_opts uvm-1.2] \
    -cm line+cond+fsm+tgl+branch+assert [+define+NAME] -f files.f -o simv
./simv +ntb_random_seed=1234 [+UVM_TESTNAME=t] -cm line+... [+fsdbfile=w.fsdb]
urg -dir simv.vdb -report cov_html;  urg -dir a.vdb b.vdb -dbname merged
-assert enable_diag; +ntb_random_seed_automatic; -assert vacuous (off); +vcs+lic+wait; -kdb (Verdi)
```

## Xcelium (Cadence)
```
xrun -64bit -sv -uvm -timescale 1ns/1ps -access +rwc -coverage all -covoverwrite \
     [+define+NAME] -f files.f +UVM_TESTNAME=t -svseed 1234 [-input probe.tcl]
imc -load cov_work/scope/test -execcmd "report -detail -html -out cov_html"
imc -execcmd "merge run1 run2 -out merged"
-linedebug, -assert_count_vacuous (check docs), -profile, -xmlibdirname
```

## Verilator (open source; 2-state, cycle-based; SV subset incl. classes/constraints partially)
```
verilator --binary --timing -Wall --assert --coverage [--trace-fst] -f files.f --top <top>
./obj_dir/V<top> +verilator+seed+1234
verilator_coverage --annotate annotated coverage.dat
```
Limits: no `covergroup` (as of 5.x limited), partial SVA (immediate + simple concurrent), no UVM
without the community fork; excellent for fast RTL regressions and cocotb.

## Icarus Verilog (open source; no classes/SVA)
```
iverilog -g2012 -o sim.vvp -f files.f && vvp sim.vvp +seed=1
```
Fine for chapter 1 and 2 module-level testbenches minus assertions.

## SymbiYosys / Yosys (open-source formal)
```
sby -f design.sby [prove|bmc|cover]       # tasks; results in <name>_<task>/
# .sby: [options] mode prove|bmc|cover ; depth N   [engines] smtbmc yices | abc pdr   [script] read -formal ... ; prep -top X   [files]
```
Uses `assert/assume/cover` (immediate in `always @(posedge clk)` or a subset of `assert property`),
`$past`, `$stable`, `$rose`, `$initstate`, `(* anyconst *)`, `(* anyseq *)`, `$anyconst`, `$anyseq`.

## Commercial formal (shape only)
JasperGold: `analyze -sv files; elaborate -top X; clock clk; reset rst; prove -all; report`.
VC Formal: `read_file -sva -top X files; create_clock clk; create_reset rst; sim_run; check_fv; report_fv`.
Questa Formal: `formal compile -d X; formal verify; formal report`.

## Waves
Questa: `.wlf` (`vsim -wlf`, `log -r /*`); VCS/Verdi: `.fsdb` (`$fsdbDumpvars`); Xcelium: `.shm`
(`probe -create -all -depth all -shm`); everyone: `$dumpfile/$dumpvars` → `.vcd` (large, portable);
GTKWave and Surfer read VCD/FST.

## Seeds and reproduction
Log at start: tool version, git hashes, seed, full command line. Rerun with the same seed and
`+define+`s. UVM: object seeding derived from names; changing creation order changes streams.

## Lint / static
Questa `vlog -lint`; VCS `+lint=all,noVCDE`; Xcelium `-lint`; Verilator `--lint-only -Wall`;
commercial: SpyGlass, Ascent, HAL, Questa Lint/CDC/RDC.
