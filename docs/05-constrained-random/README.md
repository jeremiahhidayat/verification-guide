# Chapter 5: Constrained-Random Verification (CRV)

Directed tests scale linearly with engineer time: one scenario per test. Constrained-random stimulus
scales with CPU time: describe the *legal space* once, let the solver enumerate it, and let coverage
tell you what was hit. The catch is that you now write specifications of stimulus instead of
stimulus, which is a different and initially uncomfortable skill.

| Section | Topic |
|---|---|
| [5.1](01-randomization-and-constraints.md) | `rand`/`randc`, `randomize()`, constraint blocks, `inside`, `dist`, implication, `solve...before`, `soft`, in-line constraints, `pre_/post_randomize`, seeds and stability |
| [5.2](02-advanced-constraints.md) | Arrays and queues in constraints, `foreach`, `unique`, sum, array of handles, `randcase`, `randsequence`, constraint layering by inheritance, debugging solver failures, performance |

Classes themselves (handles, inheritance, virtual methods) are covered in chapter 6; this chapter
uses only what is needed to hold random fields.

Code: [`code/05-crv/`](../../code/05-crv/).
