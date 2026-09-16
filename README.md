# The Verification Engineer's Handbook

*SystemVerilog, testbenches, SVA, coverage, constrained-random, UVM, formal, and the way industry actually verifies chips: from first principles.*

This repository is a study guide and reference, written in the voice of a senior verification
engineer mentoring a junior. Every chapter tries to answer three questions before it shows you syntax:

1. **What problem does this construct or method actually solve?**
2. **What does it look like at the simulator / mathematical level, so you can predict its behavior instead of memorizing rules?**
3. **How does a senior engineer decide when to use it, and what mistakes have they already made so you don't have to?**

If you only remember one idea from the whole guide, make it this one:

> **Verification is the discipline of building an independent, executable argument that a design does what its specification says, and of measuring how complete that argument is.**
> Stimulus without checking is not verification. Checking without coverage is not verification. A test that passes but that you cannot explain is not verification.

## How to use this repo

- Read the chapters in order the first time. Later chapters assume the mental models built earlier
  (especially the simulation-semantics chapter; most "mysterious" testbench bugs come from not
  understanding it).
- Every chapter has runnable code under [`code/`](code/). Compile it, break it, fix it. The
  guide tells you which lines to change to see a failure.
- Each chapter ends with **"Interview angle"** (what an interviewer is really probing when they ask
  about this topic) and **"Mentor's notes"** (opinions, tradeoffs, war stories).
- Chapter 10 is a question bank with worked answers. The appendix holds cheat sheets, tool commands, a glossary, a reading list, and a construct index keyed to a small testbench.

## Study path

| Part | Chapter | You will be able to... |
|---|---|---|
| 0 | [How to think like a verification engineer](docs/00-mindset/README.md) | Frame any verification task as spec, stimulus, checking, coverage, and closure |
| 1 | [SystemVerilog fundamentals](docs/01-sv-fundamentals/README.md) | Predict what the simulator does with your code: types, X, assignments, scheduling, races, interfaces, gotchas |
| 2 | [Basic testbenches](docs/02-basic-testbenches/README.md) | Write clean, race-free, self-checking module-level testbenches with reference models |
| 3 | [SystemVerilog Assertions](docs/03-sva/README.md) | Turn a spec sentence into a temporal property, and know exactly when it samples and why it fails |
| 4 | [Functional coverage](docs/04-coverage/README.md) | Define "done" quantitatively with covergroups, cover properties, and closure strategy |
| 5 | [Constrained-random verification](docs/05-constrained-random/README.md) | Drive the solver instead of fighting it: constraints, distributions, solve order, debugging |
| 6 | [OOP and layered testbenches](docs/06-oop-and-layered-tb/README.md) | Build generator/driver/monitor/scoreboard/environment testbenches with threads, mailboxes, virtual interfaces |
| 7 | [UVM](docs/07-uvm/README.md) | Understand every UVM component's purpose, phases, factory, config_db, TLM, sequences, RAL, and reuse |
| 8 | [Formal verification](docs/08-formal/README.md) | Know what a proof is, write formal-friendly properties, use assumptions and abstractions, converge and sign off |
| 9 | [Industry-scale verification](docs/09-industry-practice/README.md) | Verification planning, regressions, CI, debug, block-to-SoC, emulation, GLS, low power, CDC, metrics, signoff |
| 10 | [Interview prep](docs/10-interview-prep/README.md) | Answer and *explain* the classic questions; whiteboard SVA, constraints, and testbench design |
| A | [Appendix](docs/appendix/README.md) | Cheat sheets for SVA, constraints, UVM, tool commands; glossary; reading list; construct index |

## Repository layout

```
docs/        the guide, one folder per chapter, README.md in each is the chapter index
code/        runnable examples per chapter; one DUT (a synchronous FIFO) verified six ways:
             02 module testbench -> 03 SVA checker (bind) -> 04 coverage -> 06 class-based layered TB
             -> 07 UVM -> 08 formal (SymbiYosys)
scripts/     check_all.sh compiles and elaborates every example (the CI gate); run_questa.sh runs one
```

## Running the code

Every example compiles and elaborates cleanly with Questa (`vlog -sv -lint` + `vopt`), which
`scripts/check_all.sh` verifies. The code avoids vendor extensions and should compile on VCS and
Xcelium unchanged. Verilator and Icarus support a subset (no covergroups, partial SVA, no classes
in Icarus); notes in each `code/` folder say what works where. Questa Intel FPGA Starter Edition
compiles everything but needs its (free) license set up to simulate.

```
# Questa / ModelSim
cd code/02-basic-tb
vlib work
vlog -sv fifo.sv fifo_tb.sv
vsim -c fifo_tb -do "run -all; quit"

# UVM example (Questa ships UVM 1.2 precompiled)
cd code/07-uvm
vlog -sv +incdir+. -f files.f
vsim -c tb_top +UVM_TESTNAME=fifo_random_test -do "run -all; quit"
```

See [appendix D](docs/appendix/D-tool-commands.md) for VCS, Xcelium, Verilator, and SymbiYosys equivalents.

## Sources and acknowledgements

This guide synthesizes and re-explains material from:

- Greg Stitt's [ARC-Lab-UF sv-tutorial](https://github.com/ARC-Lab-UF/sv-tutorial) and his article
  [Race Conditions: The Root of All Verilog Evil](https://stitt-hub.com/race-conditions-the-root-of-all-verilog-evil/).
  The testbench progression in chapters 2 to 7 (register, delay, FIFO, bit_diff, AXI-stream agents) follows his
  teaching order because it is the best one I know of.
- Chris Spear and Greg Tumbush, *SystemVerilog for Verification*, 3rd ed. (Springer, 2012). Chapters 1 to 11
  of that book map to chapters 1, 5, 6 here.
- [chipverify.com](https://www.chipverify.com) SystemVerilog and UVM tutorials, used as a checklist of topics.
- IEEE 1800-2017 (the SystemVerilog LRM) for the actual semantics. When this guide and a tutorial disagree,
  the LRM wins.
- Cliff Cummings' SNUG papers (nonblocking assignments, FSM coding, clocking blocks), Ben Cohen's SVA
  work, and the Accellera UVM 1.2 class reference.

The textbook PDF and the cloned tutorial are intentionally excluded from this repo by `.gitignore`.
Buy the book; clone the tutorial.
