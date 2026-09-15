# Chapter 7: UVM (Universal Verification Methodology)

UVM is the layered testbench of chapter 6 turned into a standard library: base classes for every
component, a phasing system so everyone builds/connects/runs in the same order, a factory so tests
can swap components without editing environments, a configuration database so anything can be
configured from anywhere, TLM ports so components connect without knowing each other, a sequence
mechanism so stimulus is layered and reusable, a reporting system, and a register model.

If you understood chapter 6, UVM is mostly *names for things you already built*. This chapter maps
each UVM concept to its chapter-6 ancestor, then covers what UVM adds. The tutorial's four UVM
examples (basics, agents, agents_parameterized, multiple_tests) are the recommended companion; the
code here follows their conventions.

| Section | Topic |
|---|---|
| [7.1](01-uvm-fundamentals.md) | Class hierarchy, `uvm_object` vs `uvm_component`, phases, objections, the testbench top, `run_test`, reporting |
| [7.2](02-components.md) | Sequence item, sequencer, driver, monitor, agent, scoreboard, subscriber, environment, test: purpose and template of each |
| [7.3](03-sequences.md) | Sequences in depth: `body`, `start_item`/`finish_item`, `uvm_do` macros, responses, nested and virtual sequences, virtual sequencers, arbitration, sequence libraries |
| [7.4](04-tlm-and-analysis.md) | TLM: put/get ports, exports, imps, FIFOs, analysis ports and `uvm_subscriber`, connecting monitors to scoreboards and coverage |
| [7.5](05-config-factory-reporting.md) | `uvm_config_db`, config objects, the factory and overrides, field macros vs `do_*` methods, reporting and verbosity, command-line control |
| [7.6](06-ral.md) | The register abstraction layer: register model, adapter, predictor, front/back-door access, built-in register tests |
| [7.7](07-advanced-and-reuse.md) | Parameterized agents, active/passive, vertical reuse, callbacks, phase jumping, heartbeats, common anti-patterns, UVM 1.1 vs 1.2 vs IEEE 1800.2 |

Code: [`code/07-uvm/`](../../code/07-uvm/), a complete UVM environment for the FIFO with two
agents, a scoreboard, a coverage subscriber, a virtual sequence, and three tests.
