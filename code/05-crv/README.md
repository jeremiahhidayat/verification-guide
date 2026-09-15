# Code for Chapter 5: Constrained-Random

| File | What it is |
|---|---|
| `constraints_demo.sv` | Nine short experiments: soft defaults, in-line overrides, a deliberate hard-constraint conflict (and the correct reaction), same-name constraint override in a derived class, a `dist` histogram, the implication/`solve before` distribution trap measured numerically, array constraints with `unique`/`sum`/`post_randomize`, `rand_mode`/`constraint_mode`, and `randcase`. |

```
vlib work
vlog -sv constraints_demo.sv
vsim -c constraints_demo -do "run -all; quit"
```

Exercises:
1. Change `c_sum` to `payload.sum() < 600` (drop the cast). Observe that the sum is computed in 8 bits and the constraint becomes almost meaningless.
2. Add `constraint c_bad { payload.size() == 8; }` to `packet`. Run. Read the solver's conflict report and identify the two constraints it names.
3. Write a `scenario` class with `rand packet pkts[]` and a constraint that tags strictly increase. Print three scenarios.
4. Reseed with `vsim -sv_seed 7` and confirm the histograms are stable in shape but different in detail.
