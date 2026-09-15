# Chapter 6: OOP and Layered Testbenches

Chapters 2 to 5 gave you the pieces: race-free driving, reference models, assertions, coverage,
constrained-random transactions. This chapter organizes them into an architecture that survives
growth: the *layered testbench*. It is the same architecture UVM formalizes, built here from plain
SystemVerilog classes so you see every wire.

The tutorial's `bit_diff_tb.sv` evolves one monolithic testbench into a class hierarchy in eight
steps; read it alongside this chapter. Our running DUT is the FIFO, which has two interfaces (write
side, read side) and therefore needs two agents, which is where the architecture starts to pay off.

| Section | Topic |
|---|---|
| [6.1](01-oop-for-verification.md) | Classes, handles, constructors, inheritance, polymorphism, virtual/abstract, parameterized classes, static, copy/clone, casting: what each is *for* in a testbench |
| [6.2](02-threads-and-ipc.md) | `fork/join` variants, `disable fork`, `wait fork`, events, semaphores, mailboxes; synchronizing generator, driver, monitor, scoreboard |
| [6.3](03-layered-testbench.md) | Transaction, generator/sequence, driver, monitor, scoreboard, environment, test; the blueprint/factory pattern; callbacks; configuration objects |
| [6.4](04-interfaces-bfm-and-reuse.md) | Virtual interfaces, BFM tasks in interfaces, passive vs active agents, reusing a block environment at the next level |

Code: [`code/06-layered-tb/`](../../code/06-layered-tb/), a complete class-based FIFO testbench
with two agents, a scoreboard, coverage, and two tests selected by plusarg.
