# 10.4 Behavioral Questions and Stories

Technical rounds prove you can do the work; behavioral rounds prove you can do it *with people* and
learn from it. Prepare five stories; rehearse them to two minutes each; keep them specific.

## The stories to have ready

1. **The hardest bug you found.** Symptom, how you narrowed it, the "aha," the fix, the check you
   added afterward. Show the method from 9.3, not luck.
2. **A testbench bug that looked like a design bug** (or vice versa). Shows honesty and independence
   of thinking.
3. **A disagreement with a designer or architect.** How you used the spec and data, how it resolved,
   what you would do differently. Never make the other person the villain.
4. **A time the schedule compressed.** How you prioritized (risk-based), what you explicitly
   dropped and communicated, what happened.
5. **Something you built that others reused** (an agent, a script, a flow). Shows leverage.
6. **A mistake you made.** An escape, a wrong waiver, a race you dismissed. What you changed.

Structure each as: situation (one sentence), what you did (most of the time), result (measurable),
lesson (one sentence).

## Questions you will hear

- "Tell me about a bug that escaped to a later stage. What did you change?" They want the
  post-mortem habit (9.3).
- "How do you handle a designer who says the testbench is wrong?" Reproduce, spec reference,
  minimal case, cycle number; be willing to be wrong; a third of the time you are.
- "How do you decide what not to verify?" Risk-based prioritization, documented and signed.
- "What is your biggest weakness in verification?" Pick a real one with a mitigation ("I under-
  invested in formal until project X; now I run autochecks on day one").
- "Where do you want to be in five years?" Verification lead, methodology owner, formal
  specialist, architect: all fine; connect it to what you are doing now.
- "Why verification, not design?" Have an honest answer. "I like finding what is wrong more than
  building what is right, and the leverage is higher" is a good one.

## Questions to ask them

- What is the ratio of verification to design engineers, and who owns the plan?
- How much of the testbench is reused across projects? Is there a VIP library?
- Formal: who uses it and for what?
- How are regressions run and how long do they take? Is there CI gating?
- What was the last silicon escape and what changed because of it?
- How do verification engineers get spec input early?

The answers tell you whether the team practices what this guide describes.

## Presenting yourself

- Your resume bullet points should be verifiable claims: "Built the UVM environment for a
  4-channel DMA; 38 RTL bugs found pre-tape-out, zero escapes in silicon; environment reused on two
  follow-on chips." Numbers, reuse, outcomes.
- Bring a one-page environment diagram of your best testbench. Interviewers love a whiteboard
  you already drew.
- If you are early-career: this repository *is* a portfolio. Point to the FIFO verified five ways
  (module testbench, SVA, coverage, class-based, UVM, formal) and explain the differences. That
  conversation demonstrates more than any resume line.
