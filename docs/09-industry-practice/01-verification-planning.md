# 9.1 Verification Planning

## Why plan

Without a plan, verification is "run tests until the schedule ends." With one, it is "prove these N
features to this standard, track progress, and know what is left." The plan is also the contract
between verification, design, architecture, and management: it says what will and will not be
verified at each level, so that gaps are chosen, not discovered.

## Feature extraction

Start from every document that constrains the block: architecture spec, micro-architecture spec,
interface standards, register spec, integration guide, errata from previous generations. For each,
extract *verifiable statements*:

- **Functions**: "the FIFO stores up to DEPTH entries in order."
- **Interfaces**: "the read port has one cycle latency and a read at empty is ignored."
- **Configuration**: "DEPTH is a power of two from 2 to 1024; WIDTH from 8 to 512."
- **Error behavior**: "a write at full sets the `overflow` status bit and drops the data."
- **Performance**: "sustains one write and one read per cycle."
- **Reset/power**: "all state resets synchronously; contents are not preserved across power gating."
- **Negative requirements**: "software shall not..." (these become assumptions or error tests).

Then ask the chapter-0 question for each: how could it be wrong? That produces the corner list.
Then ask: at what level is each best verified (block/subsystem/SoC/formal/emulation)?

## Structure of a plan

Hierarchical, one row per verifiable item:

| ID | Feature / requirement | Spec ref | Level | Method | Check | Coverage item | Test/sequence | Priority | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| FIFO-3.2 | Write at full is dropped, count unchanged | uarch 3.2 | block | sim + formal | `ap_wr_full_ign`; SB | `x_ops.wr_at_full` | `fill_drain_vseq` | P1 | JH | 100% |

Tools (Questa VM, Verdi/VPlanner, vManager) read this table (as XML/spreadsheet) and annotate each
row with live coverage from the merged regression, so the plan *is* the dashboard. Keep the plan
in version control next to the testbench.

## Risk-based prioritization

Not every feature deserves the same effort. Rank by likelihood of a bug times cost of the bug:

- New logic > reused logic; complex control > simple datapath; interactions > isolated features;
  features the designer said "I'm not sure about"; anything changed late.
- Cost: a bug in the boot path or a security feature is a respin; a bug in a debug counter is an
  errata note.

P1 items get formal plus directed plus random plus reviews; P3 items get random coverage and a
waiver review. Write the priorities down; they are what you defend when the schedule compresses.

## Reviews

Three reviews, each with the designer in the room:

1. **Plan review** (before coding): are the features complete? Do the corners match the designer's
   worries? Are the methods right (formal for the arbiter, not random)?
2. **Testbench/architecture review** (after the skeleton runs): are the checks independent of the
   RTL? Are the agents reusable? Is the reference model derived from the spec?
3. **Coverage review** (before signoff): every hole justified; every waiver signed.

Review findings are plan rows; the plan changes throughout the project.

## Estimating and staffing

Rough industry rules: verification is 50 to 70% of design effort in engineer-months; a block
environment takes 2 to 6 weeks to first traffic and 2 to 4 months to closure depending on
complexity; reuse of existing agents halves the first number. Plans list milestones: environment
bring-up (first transaction checked), feature complete (all P1 tests written), coverage closure,
signoff. Track *bugs found per week* against these; a healthy project's bug curve rises during
bring-up and decays toward zero at closure. A flat curve at zero early means checking is missing;
a curve that will not decay means the plan or the RTL is unstable.

## Spec ambiguity is a deliverable

Every "the spec doesn't say" you find during planning is a bug report against the spec, filed
before RTL is written if possible. Verification engineers are the first people to read the spec
adversarially; that reading is one of the highest-value outputs of the planning phase.

## Interview angle

- "How do you write a verification plan?" Feature extraction from docs, corners from bug
  hypotheses, method per feature, coverage linkage, priorities, reviews.
- "How do you prioritize when there is not enough time?" Risk = likelihood x cost; protect P1;
  document what is not done.
- "What goes in a plan review?"

## Mentor's notes

- Plan rows should be sentences a designer can disagree with. "Verify the FIFO" is not a row.
  "A write in the same cycle the FIFO becomes full is accepted" is.
- The plan is never finished. Every bug found adds a row ("regression test for bug 1234") and
  usually reveals a missing feature nearby.
