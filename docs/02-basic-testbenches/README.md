# Chapter 2: Basic Testbenches

Before classes, before UVM, you must be able to write a small, race-free, self-checking testbench
for a single module in a few dozen lines. Every advanced technique is a way of *organizing* what you
learn here; none of them removes the need for it. Senior engineers still write plain module-level
testbenches for unit-testing a FIFO or a pipeline stage, because they take ten minutes and catch
most bugs.

| Section | Topic |
|---|---|
| [2.1](01-anatomy.md) | Anatomy of a testbench: clock, reset, stimulus, checking, termination, and separating responsibilities into processes |
| [2.2](02-self-checking-and-models.md) | Self-checking: reference models, golden models, queues as models, scoreboards, and the "who computes expected?" question |
| [2.3](03-templates-and-patterns.md) | Reusable templates: register, delay/pipeline, FIFO, FSM, handshake; and a checklist |

Code: [`code/02-basic-tb/`](../../code/02-basic-tb/). The FIFO introduced here is the DUT for the
SVA, coverage, layered-testbench, UVM, and formal chapters, so you can watch the *same* verification
problem solved with increasing power.
