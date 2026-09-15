# A. SVA Cheat Sheet

## Skeleton
```systemverilog
label: assert property (@(posedge clk) disable iff (rst) antecedent |-> consequent)
  else $error("... %0d", $sampled(sig));
default clocking cb @(posedge clk); endclocking     // then omit @(...) in properties
default disable iff (rst);
property p (a, b); ... endproperty   sequence s (x); ... endsequence   // parameterizable
assume property (...);   cover property (...);   restrict property (...);  // formal-only restrict
```

## Delays and repetition
| Syntax | Meaning |
|---|---|
| `a ##1 b` | b next cycle |
| `a ##0 b` | same cycle (fuse) |
| `a ##[m:n] b` | b m..n cycles later |
| `a ##[1:$] b` | eventually (`##[+]`); `##[*]` = `##[0:$]` |
| `a[*n]`, `a[*m:n]` | n consecutive |
| `a[*]`, `a[+]` | 0+ / 1+ consecutive |
| `a[->n]` | nth occurrence, ends on it (go-to) |
| `a[=n]` | n occurrences, may end later (non-consecutive) |

## Implication and property operators
| Syntax | Meaning |
|---|---|
| `s \|-> p` | overlapping implication |
| `s \|=> p` | non-overlapping (`\|-> ##1`) |
| `not p`, `p1 and p2`, `p1 or p2`, `p1 implies p2` | Boolean over properties |
| `if (c) p1 else p2` | conditional |
| `p until q`, `p s_until q`, `p until_with q` | p holds until q (weak/strong/inclusive) |
| `s_eventually p`, `eventually [n:m] p`, `always p`, `nexttime p` | LTL-style (formal) |
| `first_match(s)` | first of multiple matches |
| `b throughout s` | b true across all of s |
| `s1 within s2` | s1 inside s2's window |
| `s1 intersect s2` | both, same length |
| `s1 and s2`, `s1 or s2` | both (any lengths) / either |
| `(expr, v = x, f())` | match item: local var assignment / void call |
| `@(posedge clk iff en)` | gated clock: `##1` = next enabled cycle |

## Sampled-value functions
`$rose(x)` `$fell(x)` `$stable(x)` `$changed(x)` `$past(x [,n] [,gate] [,@clk])` `$sampled(x)`
Bit-vector: `$onehot`, `$onehot0`, `$countones`, `$isunknown`, `$countbits(v, '1)`

## Semantics to remember
- Sampled in **Preponed**; evaluated in **Observed**; action blocks in Reactive.
- `disable iff` is **asynchronous and unsampled**; use `$sampled(rst)` or negedge release.
- `$past` in the first cycles returns default (X for logic).
- No antecedent = attempt every cycle. Antecedent never true = vacuous pass.
- Clock is always 0 inside a `posedge`-clocked property.
- Concurrent assertions cannot live in classes; bind them.

## Frequent properties
```systemverilog
req |-> ##[1:N] ack                          // response window
valid && !ready |=> valid && $stable(data)   // hold until handshake
$fell(valid) |-> $past(ready)                // valid only drops after ready
$onehot0(grant)                              // at most one
grant[i] |-> req[i]                          // no spurious grant
en[->L] |=> out == f($past(in, L, en))       // enabled latency
(v && en, d = in) |-> en[->L] ##1 out == f(d) // forward-looking
$fell(rst) |-> out == '0 throughout en[->L]  // reset clears until refill
!en |=> $stable(out)                         // stall
full == (count == DEPTH)                     // flag definition
!$isunknown(out)                             // no X
rst |=> out == '0                            // reset value (no disable iff)
```

## Control
`$assertoff [(levels, scope)]` `$asserton` `$assertkill` `$assertcontrol`

## bind
`bind <target_module_or_instance> <checker_module> #(params) <inst_name> (.*);`
