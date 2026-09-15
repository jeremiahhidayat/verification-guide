# Chapter 1: SystemVerilog Fundamentals (for verification)

SystemVerilog is two languages wearing one trench coat: a hardware description language (the
synthesizable subset, inherited from Verilog) and a hardware *verification* language (classes,
constraints, assertions, coverage, dynamic data). Verification engineers must be fluent in both,
because the testbench talks to the DUT through the first and is written in the second.

This chapter builds the mental model of *what the simulator does* with your code. Memorizing syntax
without that model is how people write testbenches that "work" until the simulator version changes.

| Section | Topic | Why it matters for verification |
|---|---|---|
| [1.1](01-data-types.md) | Data types, 4-state vs 2-state, arrays, structs, enums, strings, casting | Choosing `logic` vs `bit` changes which bugs you can see. Queues and associative arrays are your reference models. |
| [1.2](02-procedural-blocks-and-assignments.md) | `always_*`, `initial`, blocking vs nonblocking, loops, timing control | Nonblocking assignments are the single most important race-condition tool. |
| [1.3](03-simulation-semantics-and-races.md) | The event scheduler, regions, delta cycles, race conditions | The section to read twice. Explains every "it worked yesterday" bug. |
| [1.4](04-tasks-functions-and-scope.md) | Tasks, functions, `automatic`, arguments, `void'()`, time, system tasks | Reusable testbench code; reentrancy in forked threads. |
| [1.5](05-modules-packages-interfaces.md) | Parameters, packages, `generate`, hierarchical references, interfaces, modports, clocking blocks, program blocks | How the testbench connects to and observes the DUT. |
| [1.6](06-gotchas.md) | X semantics, `==` vs `===`, implicit nets, width and sign rules, out-of-range indexing, `$random` vs `$urandom` | Each one has silently hidden a real bug in a real project. |

Code for this chapter: [`code/01-fundamentals/`](../../code/01-fundamentals/).
