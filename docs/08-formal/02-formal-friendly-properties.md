# 8.2 Writing Formal-Friendly Properties

The same SVA syntax serves simulation and formal, but the *style* that converges in formal differs
from the style that reads nicely in simulation. Principles, with the FIFO as the example.

## 1. Prefer local, structural properties over end-to-end ones

End-to-end: "every value written is eventually read, in order." Proving this requires the tool to
reason about every entry of the FIFO memory across arbitrary delays: a deep, hard problem.

Local: "the count increments on write-only, decrements on read-only, holds otherwise," "full is
`count == DEPTH`," "the read pointer never passes the write pointer," "the value read is the value at
`mem[rd_ptr]`." Each is one or two cycles deep and proves in seconds. Together they *imply* the
end-to-end property. Decomposing the big property into local ones is the core craft.

```systemverilog
// Local, converges instantly:
ap_cnt_up:   assert property (do_wr && !do_rd |=> count == $past(count) + 1);
ap_cnt_dn:   assert property (do_rd && !do_wr |=> count == $past(count) - 1);
ap_cnt_hold: assert property (do_wr == do_rd  |=> $stable(count));
ap_full:     assert property (full  == (count == DEPTH));
ap_empty:    assert property (empty == (count == 0));
ap_rd_val:   assert property (do_rd |=> rd_data == $past(mem[rd_ptr_idx]));   // white-box, bound in
```

## 2. When you must go end-to-end, use the "single tracked transaction" trick

Instead of tracking every write, track *one*, chosen nondeterministically:

```systemverilog
// A free (undriven) symbolic value: the tool considers ALL values of it.
logic [WIDTH-1:0] tracked_data;
logic             tracked_valid;      // "we have latched a write and are waiting for its read"
logic [AW:0]      tracked_ptr;
logic             start_tracking;     // free input: formal chooses WHEN to start tracking

assume property (@(posedge clk) $stable(tracked_data));            // pick one value for the whole trace
always_ff @(posedge clk) begin
  if (rst) tracked_valid <= 0;
  else if (!tracked_valid && start_tracking && do_wr && wr_data == tracked_data) begin
    tracked_valid <= 1;  tracked_ptr <= wr_ptr;                     // remember where it went
  end else if (tracked_valid && do_rd && rd_ptr == tracked_ptr) tracked_valid <= 0;
end
ap_e2e: assert property (@(posedge clk) disable iff (rst)
  tracked_valid && do_rd && rd_ptr == tracked_ptr |=> rd_data == tracked_data);
```

Because `tracked_data` and `start_tracking` are free, proving this for "the one we tracked" proves
it for every write. The tool only has to remember one value and one pointer. This pattern (also
called "symbolic" or "nondeterministic" tracking) is the standard way to get end-to-end data
integrity proofs on FIFOs, arbiters, crossbars, and memories.

## 3. Forward-looking local variables over deep `$past`

`data_out == f($past(data_in, 12, en))` forces the tool to keep 12 cycles of history for every
variable in the expression. A local-variable property captures the input once and waits:

```systemverilog
property p_fwd;
  logic [W-1:0] d;
  (valid_in && en, d = data_in) |-> en[->L] ##1 data_out == f(d);
endproperty
```

Same meaning, much less state. (Stitt's remark that "the forward-looking version is more
formal-verification friendly" is exactly this.)

## 4. Bound everything you can

`##[1:$]` (liveness) becomes `##[1:N]` (safety) whenever the spec gives you a bound (or you can
derive one from the design: "ack within DEPTH+2 cycles because the FIFO drains at one per cycle
when ready is high"). If the spec has no bound, prove the true liveness property separately with
fairness assumptions, and keep the bounded version as the everyday check.

## 5. Assumptions: exactly the legal input space, no more

Assumptions encode the environment. Sources:

- The interface protocol (AXI: `valid` held until `ready`; `ready` may depend on `valid` on the
  slave side, not on the master side).
- The spec's "shall not" statements about inputs ("software shall not write CTRL while busy").
- The reset sequence.

```systemverilog
// Environment obeys the protocol on the FIFO's write side (if the spec says writes when full are illegal)
am_no_wr_full:  assume property (@(posedge clk) disable iff (rst) full  |-> !wr_en);
am_no_rd_empty: assume property (@(posedge clk) disable iff (rst) empty |-> !rd_en);
```

Beware **over-constraint**: an assumption that references DUT outputs (`full`) is legal and
common, but if the DUT is buggy such that `full` is stuck high, the assumption forbids all writes
and every assertion passes vacuously. Always pair such assumptions with covers (`cover property
(do_wr ##[1:$] full)`). And prefer to *not* assume what you can *check*: the FIFO here ignores
illegal writes by design, so we do not need the assumptions at all and can prove more.

A useful discipline: interface assertions written for simulation (chapter 3) become assumptions for
the block under formal (they constrain the other side) and remain assertions for that other side.
Tools let you flip the direction per module.

## 6. Reset and initial state

Specify reset to the tool (which signal, polarity, how many cycles). Do not `disable iff (rst)`
everything and then forget to check reset behavior: add explicit properties for reset values
(`rst |=> count == 0`) with no disable. Uninitialized memories are free variables: if your design
reads an unwritten location, formal will show you X or a random value coming out, which is either a
real bug or a case for an assumption ("no read before write," tracked with a written-bitmap).

## 7. Helper assertions strengthen induction

If a property is inconclusive, add simpler properties about internal state that you *believe* are
invariants: `count <= DEPTH`, `wr_ptr - rd_ptr == count`, `$onehot(state)`, `!(valid_a && valid_b)`.
Once the tool proves them, it can use them as lemmas, and the hard property often converges. This is
not a hack; you are supplying the inductive invariant the engine could not find.

## 8. Avoid what SAT hates

Multipliers, dividers, modulo by non-powers of two, wide comparisons of products, CRC polynomials
over long payloads. Abstract them (replace with a free function output plus constraints on its
properties, or cut the datapath and check control only). Formal is for control; let simulation
verify the arithmetic.

## 9. Keep properties on the clock, and sample cleanly

Same as simulation: properties clocked on the design clock, no `posedge data_signal` clocks,
`$sampled` semantics, `disable iff` with the sampled-reset caveat (3.3 P1). Formal tools follow the
LRM sampling model exactly, so simulation-tested properties port directly.

## 10. Write covers for every antecedent and every interesting scenario

Vacuity is the silent killer in formal. For every `A |-> B`, add `cover property (A)`. Add scenario
covers (`full`, `empty ##[1:$] full ##[1:$] empty`, `do_wr && do_rd && count == 1`). If a cover is
unreachable, your assumptions or reset spec are wrong, or the logic is dead, and you have learned
something either way.

## Property style checklist for formal

- [ ] Decomposed into local properties where possible
- [ ] End-to-end integrity via symbolic tracked transaction
- [ ] Forward-looking local variables instead of deep `$past`
- [ ] Bounded delays; liveness separately with fairness
- [ ] Assumptions minimal, protocol-derived, paired with covers
- [ ] Explicit reset-value properties without `disable iff`
- [ ] Helper invariants for induction
- [ ] No arithmetic-heavy expressions in the proof cone
- [ ] Cover on every antecedent

## Interview angle

- "How would you formally verify a FIFO's data integrity?" Symbolic tracked-transaction pattern.
- "What is over-constraint and how do you detect it?" Assumptions too strong; covers unreachable.
- "Why do `$past`-heavy properties hurt formal?" State the tool must carry.
- "What is a helper assertion?" Lemma for induction.

## Mentor's notes

- Write covers *first*. Before any assertion, prove you can reach full, empty, and simultaneous
  read/write. A formal setup where covers are unreachable is a formal setup that proves nothing.
- The symbolic tracking pattern is the single most valuable formal technique to be able to
  reproduce on a whiteboard. Practice it until it takes two minutes.
