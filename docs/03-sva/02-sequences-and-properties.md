# 3.2 Sequences, Properties, and the Operators

## The three layers

SVA is built in layers, and thinking in layers keeps you sane:

1. **Boolean layer**: expressions evaluated at one sampling point. `req && !busy`, `data == 8'hFF`,
   `$rose(valid)`.
2. **Sequence layer**: Booleans arranged in time. `req ##1 gnt`, `valid[*3]`, `a ##[1:5] b`. A
   sequence *matches* at the cycle where its last element is satisfied; it may match multiple times
   from one start.
3. **Property layer**: statements about sequences that are true or false. `s1 |-> s2`, `not s`,
   `s1 and s2`, `disable iff`. An `assert property` asserts a property.

```systemverilog
sequence s_req_gnt;            // reusable sequence
  req ##[1:3] gnt;
endsequence

property p_no_double_gnt;      // reusable property with a clock and reset
  @(posedge clk) disable iff (rst)
  $rose(gnt) |=> !gnt[*2];
endproperty

ap_req_gnt: assert property (@(posedge clk) disable iff (rst) s_req_gnt);
ap_no_dbl:  assert property (p_no_double_gnt);
```

Declaring named sequences and properties lets you reuse them, give them arguments (they are
templates: `sequence s_within(a, b, n); a ##[1:n] b; endsequence`), and put the clock in one place.

## Delays: `##`

```systemverilog
a ##1 b          // b one cycle after a
a ##0 b          // b in the SAME cycle as a (used to "fuse" sequences)
a ##[1:4] b      // b 1 to 4 cycles after a (any one match satisfies)
a ##[1:$] b      // b eventually (unbounded): dangerous in simulation, see 3.3
a ##[+] b        // same as ##[1:$];  ##[*] is ##[0:$]
```

`##N` counts *clock ticks of the property's clock*, not time. With `@(posedge clk iff en)` as the
clock, `##1` means "next enabled cycle."

## Repetition

```systemverilog
a[*3]            // a a a : three consecutive cycles of a
a[*1:5]          // 1 to 5 consecutive
a[*0:$]          // zero or more (a[*] shorthand)
a[->3]           // "go-to": the 3rd occurrence of a, not necessarily consecutive; sequence ends ON the 3rd a
a[=3]            // "non-consecutive": 3 occurrences of a, sequence may end any time after the 3rd (before the 4th)
```

The go-to operator is the one you reach for with enables: `en[->LATENCY]` = "wait until the
LATENCY-th enabled cycle." `[=N]` is used to check "exactly N of these happened before that": `(rd[=4])
##1 done`.

`[*0]` matches an empty sequence, which can make an antecedent match with zero cycles; be careful
combining it with `|->`.

## Implication

```systemverilog
a |-> b          // overlapping: if a matches at cycle t, b (a sequence) must hold starting at t
a |=> b          // non-overlapping: b starts at t+1. Same as a |-> ##1 b
```

Rules that trip people:

- The **antecedent is a sequence** and may match at several cycles from one start (`a ##[1:3] b
  |-> c`): the consequent must hold for *every* match.
- The **consequent is a property**, so it may itself contain implications or `not`.
- Implication is the only place a property gets a "trigger." Without one, the property is checked
  from every cycle unconditionally.
- Nested implications work but are hard to read; prefer `##` in the antecedent.

## Sampled-value functions

Evaluated on the sampled values; all take an optional clocking event if used outside a clocked
context.

```systemverilog
$rose(x)         // x was 0 (or X/Z) at the previous sample and 1 now (LSB for vectors)
$fell(x)
$stable(x)       // unchanged since previous sample
$changed(x)
$past(x)         // value at the previous sample
$past(x, N)      // N samples ago
$past(x, N, en)  // N samples ago counting only samples where en was true (gated history)
$sampled(x)      // the sampled value (for use in action blocks)
```

`$past` in the first N cycles returns the type's default (X for `logic`, 0 for `bit`). That is why
`out == $past(in)` fails or is meaningless right after time 0 / reset unless you gate the first
cycles; section 3.3.

## Sequence operators (composition)

| Operator | Meaning | Example |
|---|---|---|
| `s1 and s2` | Both match, starting together, ends when the later one ends | `(a ##2 b) and (c ##1 d)` |
| `s1 or s2` | Either matches | `req_a or req_b` |
| `s1 intersect s2` | Both match with the *same* length | `(a ##[1:5] b) intersect (1[*3])`: b exactly 3 after a |
| `s1 within s2` | s1 matches entirely inside s2's window | `ack within (req ##[1:10] done)` |
| `b throughout s` | Boolean b holds at every cycle of s | `!abort throughout (start ##[1:$] done)` |
| `first_match(s)` | Only the first of possibly many matches | `first_match(a ##[1:$] b)` |
| `s1 ##0 s2` | Fuse: s2 starts on s1's last cycle | `(en, x = d) ##0 en[->3]` |

`throughout` is the workhorse for "must stay stable/asserted during a transaction":
`$rose(busy) |-> $stable(cfg) throughout busy[*1:$] ##0 !busy`. Stitt's reset check:
`$fell(rst) |-> data_out == '0 throughout en[->LATENCY]`.

`until` / `s_until` / `until_with` are the property-level versions: `p1 until p2` = p1 holds every
cycle up to (not including) the cycle p2 first holds. Stitt documents a trap: `$fell(rst) |->
data_out == '0 until en[->N]` does not check what you think, because `en[->N]` as a *property* is
"true at the start of any window in which N enables will occur," which is immediately. Use
`throughout` with the sequence form.

## Local variables

Properties and sequences can declare variables that are *per attempt*. This is how you carry a value
from the trigger to the check without a model:

```systemverilog
property p_data_delayed;
  logic [WIDTH-1:0] captured;
  @(posedge clk) disable iff (rst)
  (valid && en, captured = data_in) |-> en[->LATENCY] ##1 data_out == captured;
endproperty
```

`(expr, assignment)` is a *sequence match item*: when `expr` is true, execute the assignment. You
can call void functions too (`(wr_en, tag = next_tag, inc_tag())`). Each attempt gets its own copy
of `captured`, so overlapping transactions are tracked independently. This "forward-looking" style
is often easier to debug (the variable is visible in the waveform in some tools) and is what formal
tools prefer over `$past` with large depths.

The FIFO-ordering property from the tutorial (credit: Ben Cohen) combines local variables,
`first_match`, and function calls:

```systemverilog
int tag = 0, serving = 0;
function void inc_tag();     tag++;     endfunction
function void inc_serving(); serving++; endfunction

property p_fifo_order;
  int         wr_tag;
  logic [7:0] wdata;
  @(posedge clk) disable iff (rst)
  (wr_en && !full, wr_tag = tag, inc_tag(), wdata = wr_data)
    |-> first_match(##[1:$] (rd_en && !empty && serving == wr_tag, inc_serving()))
        ##1 rd_data == wdata;
endproperty
```

It works. It is also the point where the tutorial says: when an assertion needs this much machinery,
a five-line queue model is clearer. Know how to write it; know when not to.

## Multiple clocks

```systemverilog
property p_cdc;
  @(posedge clk_a) $rose(req) |=> @(posedge clk_b) ##[1:3] ack;
endproperty
```

Clock changes are allowed at sequence boundaries with `|=>` (or `##1`) between them. Used for
handshake CDC checks. Keep them simple; tool support varies.

## `checker` and reusable assertion libraries

A `checker` is a container (like a module) for assertions, cover points, and modeling code, with
formal arguments, that can be instantiated in procedural context and bound. It is the LRM's
"assertion IP" construct. Many teams just use modules plus `bind`. The vendor libraries (`ovl`, Questa
QVL, VCS assertion IP) are checkers for common patterns: FIFO, arbiter, handshake, one-hot, window.

## Reading a property aloud (a discipline)

Before running, translate every assertion back to English and compare with the spec sentence:

`@(posedge clk) disable iff (rst) $rose(req) |-> ##[1:4] $rose(ack) ##1 !req`

"On every rising clock while not in reset: whenever `req` rises, `ack` must rise 1 to 4 cycles
later, and one cycle after that `req` must be low." If the English does not match the spec, the
property is wrong no matter how it simulates.

## Interview angle

- "Write an assertion for: `ack` within 1 to 5 cycles after `req`." `req |-> ##[1:5] ack`. Follow-ups:
  "and `req` must stay high until `ack`" (`req |-> req[*1:$] ##0 ack` or `req throughout ...`);
  "and no second `req` until `ack`."
- "Difference between `|->` and `|=>`?" Overlap by one cycle.
- "`[*3]` vs `[->3]` vs `[=3]`?" Consecutive vs go-to (ends on the 3rd) vs non-consecutive (ends
  any time before the 4th).
- "What is a local variable in a property for?" Carrying a per-attempt value to the check without
  `$past`.
- "Explain `throughout`." Boolean must hold across the whole sequence.

## Mentor's notes

- Start from the spec sentence. Write the antecedent as "when does this rule apply," the consequent
  as "what must then be true," and pick the delay operators last.
- If you cannot draw the property as a timing diagram with the attempt start marked, you do not yet
  understand it. Draw it. Stitt's comments do exactly this for every tricky property.
