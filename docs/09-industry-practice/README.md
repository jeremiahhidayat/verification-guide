# Chapter 9: Verification at Industrial Scale

Everything so far is what one engineer does with one block. A chip has hundreds of blocks, dozens of
engineers, a schedule, and a tape-out date after which bugs cost millions. This chapter is about the
practices that make verification *scale*: planning, regressions, debug discipline, the levels from
block to SoC, the flows beyond RTL simulation, and the metrics by which "done" is decided.

| Section | Topic |
|---|---|
| [9.1](01-verification-planning.md) | The verification plan; feature extraction; risk-based prioritization; reviews; plan-to-coverage linkage; schedules and staffing |
| [9.2](02-regressions-and-ci.md) | Regression architecture; seeds; test ranking; CI gating; compute farms; result databases; flakiness; reproducibility |
| [9.3](03-debug.md) | Systematic debug: triage, bucketing, root-cause discipline, waveform strategy, transaction logs, bug reports, and working with designers |
| [9.4](04-levels-and-flows.md) | Block, subsystem, SoC; emulation and FPGA prototyping; gate-level simulation; low-power (UPF); CDC/RDC; lint; DFT; post-silicon |
| [9.5](05-performance-and-reuse.md) | Testbench performance; VIP and agent reuse; methodology governance; code review for testbenches |
| [9.6](06-adjacent-skills.md) | Scripting (Python, Tcl, Make), DPI-C and C reference models, SystemC/TLM, Portable Stimulus (PSS), hardware/software co-verification, AI-assisted verification |
| [9.7](07-metrics-and-signoff.md) | What to measure, how to read it, exit criteria, the signoff review |
