# Chapter 4: Coverage

Assertions answer "did anything go wrong?" Coverage answers "did we look?" A design with zero
assertion failures after one directed test is not verified; a design with zero failures after every
feature, corner, and cross in the plan has been hit *while checkers were active* is as verified as
simulation can make it. Coverage is how you define "done" before you start, and how you measure it
as you go.

| Section | Topic |
|---|---|
| [4.1](01-coverage-fundamentals.md) | Kinds of coverage (code, functional, assertion), what each can and cannot tell you, and how coverage drives the flow |
| [4.2](02-covergroups-in-depth.md) | `covergroup`, coverpoints, bins (explicit, auto, transition, ignore, illegal), crosses, sampling, options, cover properties |
| [4.3](03-coverage-closure.md) | Building a coverage model from a verification plan, coverage-driven stimulus, merging, ranking, closure, waivers |

Code: [`code/04-coverage/`](../../code/04-coverage/).
