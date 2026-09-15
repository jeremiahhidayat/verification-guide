# Code for Chapter 2: Basic Testbenches

| File | What it is |
|---|---|
| `fifo.sv` | The synchronous FIFO used through chapter 8. Has `+define+BUG_*` hooks so you can prove your testbench catches bugs. |
| `fifo_tb.sv` | Complete module-level testbench: phased stimulus that forces corners, queue reference model, procedural and assertion checks, cover properties. |
| `register_tb.sv` | Pattern A: register with enable, checked two ways (monitor+checker processes, and assertions). |

```
vlib work
vlog -sv fifo.sv fifo_tb.sv register_tb.sv
vsim -c fifo_tb -do "run -all; quit"
vsim -c register_tb -do "run -all; quit"

# Mutation check: the testbench MUST fail on each of these
vlog -sv +define+BUG_FULL_OFF_BY_ONE fifo.sv fifo_tb.sv && vsim -c fifo_tb -do "run -all; quit"
vlog -sv +define+BUG_NO_RESET_RDPTR  fifo.sv fifo_tb.sv && vsim -c fifo_tb -do "run -all; quit"
vlog -sv +define+BUG_DROP_ON_SIMUL   fifo.sv fifo_tb.sv && vsim -c fifo_tb -do "run -all; quit"
```

Exercises:
1. Change `wr_data <= $urandom` to `wr_data = $urandom` in the stimulus. Does the test still pass? Why might it (luck), and what does the waveform show at the edge?
2. Remove phase 1 and 2 of the stimulus. Check the cover properties in the simulator's coverage report: which corners are no longer hit?
3. Add a second reset pulse in the middle of phase 3 and make the model and checks survive it.
