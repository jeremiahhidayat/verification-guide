# Chapter 0: How to Think Like a Verification Engineer

Before any syntax, you need the frame. Designers think "how do I build it?" Verification engineers
think "how would I *know* it is wrong?" That flip is the whole job. Everything else (SystemVerilog,
UVM, formal) is tooling in service of that question.

## 0.1 The verification problem, from first principles

A design is a function from an input sequence to an output sequence: `outputs = DUT(inputs)`. The
specification is another such function, usually written in English, tables, and timing diagrams:
`outputs = SPEC(inputs)`. Verification is the attempt to establish

```
for all legal input sequences s:   DUT(s) == SPEC(s)
```

Three facts make this hard, and every technique in this guide exists because of one of them:

1. **The input space is astronomically large.** A 32-bit adder has 2^64 input pairs. A bus interface with
   a few hundred cycles of history has more states than atoms in the universe. You cannot enumerate. So
   you must *sample* (simulation) or *reason symbolically* (formal), and you need a way to say how much
   of the space you have covered (coverage).
2. **The spec is not executable.** Someone must translate English into something a machine can compare
   against: a reference model, a scoreboard, an assertion. That translation is itself a design activity
   and can itself be wrong. A good verification engineer treats the testbench as a second,
   independent implementation of the spec, and treats disagreement between the two as *information*,
   not as "the test is broken."
3. **You are looking for the absence of bugs, which cannot be observed.** You can only observe the
   presence of bugs. So the output of verification is never "it is correct"; it is "I looked in these
   places, this hard, and found nothing." That is why coverage, planning, and metrics matter as much as
   the testbench itself.

## 0.2 The five questions

For any block you are asked to verify, answer these in order. Do this on paper before writing code.

| # | Question | Produces |
|---|---|---|
| 1 | **What is it supposed to do?** (spec, interfaces, timing, corner cases, error behavior) | Feature list, interface list, list of "shall" statements |
| 2 | **How could it be wrong?** (what would a tired designer get wrong?) | Bug hypotheses: off-by-one, reset, full/empty, back-pressure, simultaneous events, width overflow, X-propagation |
| 3 | **How will I drive it?** | Stimulus strategy: directed, constrained-random, protocol-aware drivers, error injection |
| 4 | **How will I know it is wrong?** | Checking strategy: assertions, scoreboard with reference model, end-to-end data integrity |
| 5 | **How will I know I am done?** | Coverage model: functional coverage tied to features, code coverage, assertion coverage; exit criteria |

Questions 1, 2, and 5 are the verification plan. Questions 3 and 4 are the testbench. Juniors jump to
3. Seniors spend most of their thinking on 2 and 4.

## 0.3 Stimulus vs. checking vs. coverage: three independent axes

A common mental error is to treat "I ran a lot of random traffic" as verification. Pull these apart:

- **Stimulus** answers "what did we exercise?" A test that drives a million random packets but only
  checks that the simulation does not crash has verified almost nothing.
- **Checking** answers "did the DUT respond correctly to what we exercised?" A perfect scoreboard with
  only one directed test has verified one point in the space.
- **Coverage** answers "what fraction of the interesting space did we exercise *while checking was
  active*?" Coverage without checking is theater. Checking without coverage is guessing.

The product of the three is your confidence. Weakness in any one axis bounds the whole.

## 0.4 Where bugs actually live

After a few projects, you will notice bugs cluster. Use this list to seed question 2:

- **Boundaries**: FIFO full/empty, counter wrap, max burst length, address range edges, first and last
  beat of a packet, width transitions (8-bit to 32-bit packing).
- **Simultaneity**: read and write in the same cycle, request arriving in the cycle a state machine
  transitions, reset asserted mid-transaction, two masters requesting at once.
- **Back-pressure and stalls**: ready dropping mid-burst, valid held with ready low, credit exhaustion.
- **Reset and initialization**: registers that reset to the wrong value, logic that depends on an
  uninitialized memory, reset released synchronously to a clock edge (race).
- **Control/data mismatch**: the datapath is right but the valid/last/strobe sideband is wrong.
- **Error paths**: everything the spec says "shall be ignored" or "shall return an error" is
  rarely exercised by the designer's own tests.
- **Configuration interactions**: feature A works, feature B works, A and B enabled together do not.
- **Clock domain crossings**: metastability is not modeled in RTL simulation; you need CDC tools and
  protocol-level checks (handshakes, gray codes) instead.

## 0.5 The testbench is a design too

Treat it like one. It has an architecture (layers: signal, command, functional, scenario, test), it has
interfaces (transactions, TLM ports), it has requirements (must be race-free, must be reusable at the
next level up, must run fast enough for overnight regressions), and it has bugs. About a third of the
"failures" in a new environment are testbench bugs. That is fine; it is the cost of independence.
What is not fine is "fixing" a testbench failure by loosening the check until it passes. Every
mismatch gets root-caused to either the DUT, the testbench, or the spec.

## 0.6 Levels of verification and why you need all of them

| Level | Tool | What it is good at | What it cannot do |
|---|---|---|---|
| Lint / static | Lint, CDC, RDC tools | Structural mistakes, width mismatch, unreachable code, missing synchronizers | Anything about function |
| Formal (FPV) | Model checkers | Exhaustive proof of local properties, corner cases you would never think to hit, dead code, reachability | Whole-chip datapath behavior, anything needing very deep sequential state |
| Block-level simulation | SV/UVM testbench | Thorough functional check of one block with full controllability and observability | System interactions |
| Subsystem / SoC simulation | Reused UVM + C tests | Integration, address maps, interrupts, software-visible behavior | Speed (thousands of cycles/sec) |
| Emulation / FPGA prototyping | Hardware | Running real software, long scenarios, performance | Observability, X behavior, fast iteration |
| Gate-level simulation | Netlist sim | Reset/X issues, timing with SDF, DFT logic | Coverage; it is slow and painful |

You verify a feature at the lowest level that can fully exercise and observe it, then re-verify the
*integration* at the next level up. Reuse (of agents, sequences, checkers) is what makes the levels
affordable, which is the real reason UVM exists.

## 0.7 Habits that separate good verification engineers

1. **Read the spec twice; read the RTL once.** Your checks must come from the spec, or you will only
   verify that the RTL does what the RTL does.
2. **Write the check before the stimulus.** If you cannot say what "correct" means, you are not ready
   to drive anything.
3. **Make failures loud and early.** An assertion that fires in the cycle the bug happens saves hours
   over a scoreboard mismatch 10,000 cycles later. Layer both.
4. **Be suspicious of passing tests.** Inject a bug into the RTL (flip a condition) and confirm the
   testbench catches it. This "mutation" habit catches vacuous assertions, X-comparison gotchas, and
   dead scoreboards.
5. **Own the seed.** Every random failure must be reproducible from a seed and a command line.
6. **Log for the next person.** Transaction-level logs with timestamps, not signal dumps.
7. **Measure.** Coverage, bug rate, regression pass rate, simulation throughput. Decisions about
   "are we done" are made from data, not feelings.

## Interview angle

"Walk me through how you would verify X" is the most common senior-level question. The interviewer
is not looking for UVM class names. They want to hear the five questions in section 0.2, in that
order, with specific bug hypotheses for X. Practice on: a FIFO, an arbiter, an APB slave with a
register bank, an AXI-Stream width converter, a cache controller.

## Mentor's notes

- The fastest way to grow is to find bugs. Volunteer for the messiest block. Bugs are where the
  learning is.
- Designers are your customers and your partners, not your adversaries. Report bugs with a waveform,
  a cycle number, the spec sentence violated, and a minimal reproduction. That earns trust, and trust
  is how you get access to the designer's own worries (which are usually right).
- When you disagree with the spec, escalate the spec, not the design. A surprising number of "bugs"
  are spec ambiguities, and resolving them early is the highest-leverage work on the team.
