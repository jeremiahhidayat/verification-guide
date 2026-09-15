# 3.1 Immediate vs. Concurrent Assertions, and the Sampling Model

## Immediate assertions: an `if` with a severity

```systemverilog
function void check_output(string name, logic actual, logic expected);
  assert (actual === expected)
    else $error("[%0t] %s = %b, expected %b", $realtime, name, actual, expected);
endfunction

always @(posedge clk) assert (!(wr_en && full)) else $error("write while full");
```

An immediate assertion evaluates a Boolean expression *when the statement executes*, exactly like
`if (!(expr)) $error(...)`. It lives in procedural code (`initial`, `always`, tasks, functions,
class methods). It has no notion of time or clocks. Its advantages over a plain `if`: the tool counts
it as an assertion (coverage, reports, `$assertoff`), the pass/fail action blocks are optional, and
the intent is explicit.

Use them for: checking a return value (`assert (obj.randomize())`), checking function arguments,
checking inside a class-based scoreboard, checking configuration at time 0.

A `deferred` immediate assertion (`assert #0 (...)` or `assert final (...)`) delays reporting to the
end of the time step, which suppresses glitch-induced false failures from combinational logic
settling. Rarely needed in testbenches; mention it in interviews.

## Concurrent assertions: properties over time

```systemverilog
assert property (@(posedge clk) disable iff (rst) req |-> ##[1:4] ack);
```

A concurrent assertion is not executed by a process. It is a *separate observer* that the simulator
evaluates at every clock event, sampling values in the **Preponed** region. Its property can span
many clock cycles. Every clock edge starts a new *evaluation attempt* of the property; many attempts
can be in flight at once (one per cycle in which `req` was true above).

Syntax skeleton:

```
[label:] assert property (
   @(clocking_event)              // when to sample and advance: almost always @(posedge clk)
   [disable iff (reset_expr)]     // asynchronously abandon attempts while true
   property_expression            // the temporal statement
) [pass_action] [else fail_action];
```

Where they can live: in a module, interface, program, or `checker` at the same level as `always`
blocks (not inside one), and via `bind` into any scope.

## The sampling model (the thing that makes SVA work)

At every clock event, before any process runs, the simulator takes a snapshot of every variable the
property references. The property is evaluated (in the Observed region) using *only* those samples.
Consequences:

1. **Assertions never race with the testbench or the DUT.** The sample is the value just before the
   edge, which is precisely what the DUT's flops sampled. If you drive a DUT input with `<=` at the
   edge, the assertion sees the old value, same as the DUT.
2. **Inside a property, the clock is always 0** (for `posedge clk`), because just before a rising
   edge the clock is low. Do not reference the clock signal inside the property.
3. **In an action block, a bare variable name gives the *current* (post-NBA) value**, which is not
   what the assertion evaluated. Use `$sampled(x)` in messages. This is the single most confusing
   thing when reading assertion failure messages.
4. **Combinational glitches between edges are invisible** to the property. That is a feature (you
   want to check the settled value) and a limitation (a glitch on an asynchronous signal like a
   `done` pulse between edges is not seen; check those with an immediate assertion in an
   `always @(signal)` block or sample on the right clock).

```
                 Preponed sample      Observed evaluate
                       |                    |
clk   ______|‾‾‾‾‾‾|______|‾‾‾‾‾‾|______
            ^ attempt N starts       ^ attempt N+1 starts; attempt N advances one cycle
```

## `disable iff`

`disable iff (rst)` says: while `rst` is true, kill every attempt in flight (they end as *disabled*,
neither pass nor fail) and do not start new ones. It is evaluated **asynchronously with the
current, unsampled value**, and an attempt is disabled if the expression is true at *any* point
between its start (Observed region of the starting edge) and its end.

That last sentence is why an assertion can fail one cycle after reset release when reset is
released with `<=` on the posedge: the attempt starting on the release edge was *not* disabled (the
disable condition became false in the NBA region of that same time step, before the attempt
finished its first cycle), so it evaluated with `$past` values from during reset. Section 3.3 shows
the three fixes. The easy one: release reset on the negedge.

## Implication, and the concept of vacuous success

`antecedent |-> consequent`: "whenever the antecedent matches, the consequent must hold starting in
the same cycle." `|=>` is the same starting one cycle later (`|-> ##1`).

If the antecedent does not match in a given attempt, the attempt succeeds **vacuously**: nothing was
checked. An assertion whose antecedent is never true never fails and has verified nothing. Every
simulator can report vacuous vs. non-vacuous passes (Questa: `-assertcover` / assertion browser;
VCS: `-assert vacuous` off...). **Always check that your key assertions have non-vacuous passes.**
Cover properties (chapter 4) on the antecedent are the systematic way.

Without implication, the property must hold on *every* attempt: `assert property (@(posedge clk)
valid |-> ready)` vs `assert property (@(posedge clk) !valid || ready)`; these are equivalent for a
Boolean consequent, but the first is reported as vacuous when `valid` is 0, which is useful
information; the second is a non-vacuous pass every cycle, which hides that `valid` never happened.

## Action blocks and severity

```systemverilog
ap_ack: assert property (@(posedge clk) disable iff (rst) req |-> ##[1:4] ack)
  else $error("[%0t] req at %0t got no ack within 4 cycles (req=%b)", $realtime, $sampled(req));

// Pass action: rare, but useful when debugging "is this ever checked?"
assert property (p_handshake) $info("handshake OK at %0t", $realtime); else $error("handshake broke");

// UVM: route into the UVM report server so the test result reflects assertion failures
assert property (p_handshake) else `uvm_error("SVA", "handshake broke");
```

Severity: `$info`, `$warning`, `$error` (increments error count, continues), `$fatal` (stops). Default
failure action if you omit `else` is `$error` with a tool-generated message; always add your own with
the relevant *sampled* values. Label every assertion (`ap_ack:`); labels appear in reports, waveforms,
and coverage, and let you `$assertoff(0, tb.ap_ack)` selectively.

## Controlling assertions

```systemverilog
initial begin
  $assertoff;                 // all off (e.g., during a messy power-up sequence)
  @(negedge rst);
  $asserton;
end
$assertkill;                  // abort attempts in flight, then off
$assertoff(0, dut.u_ctrl);    // hierarchy-selective
```

Most designs simply use `disable iff (rst)` on every property instead.

## `assume` and `cover`

Same syntax, different directive:

- `assume property (...)`: in simulation, identical to `assert` (a violated assumption is reported).
  In formal, it *constrains the inputs*: the tool only explores traces where the assumption holds.
  Chapter 8.
- `cover property (...)`: report how many times the sequence/property completed (non-vacuously).
  Never fails. This is how you prove your stimulus reached a scenario. Chapter 4.

## Where to put assertions

| Location | Owner | Purpose |
|---|---|---|
| Inside the RTL module | Designer | Internal invariants, assumptions about inputs ("never write when full"), one-hot state |
| Inside the interface | Protocol owner | Protocol rules (AXI: `valid` held until `ready`), reused by every DUT and by formal |
| Bound checker module | Verification | End-to-end and white-box properties on a block you do not own, without touching its source |
| Testbench top | Verification | Test-specific expectations, scoreboard-style checks with local models |
| Class-based components | Verification | Only *immediate* assertions (classes cannot host concurrent assertions) |

## Interview angle

- "Immediate vs concurrent?" Procedural/zero-time vs clocked/temporal; where each can live; sampling.
- "When does a concurrent assertion sample?" Preponed region; consequence: no races; `$sampled` in
  action blocks.
- "What does `disable iff` do and when is it evaluated?" Asynchronous, unsampled; the
  reset-release corner case.
- "What is a vacuous pass?" And "how would you know your assertion is actually checking something?"

## Mentor's notes

- I write the `!$isunknown` and the "never write when full" assertions before I write any stimulus.
  Then I run the designer's smoke test. Half the time something fires within a minute.
- Put `$sampled(...)` in every assertion message. It is tedious. It saves you from filing a bug
  against the designer with the wrong value in it, which is the kind of mistake that costs credibility.
