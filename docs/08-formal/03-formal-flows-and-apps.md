# 8.3 Formal Flows, Apps, and Tools

## Setting up a formal property verification (FPV) run

Every tool follows the same shape; the syntax differs.

1. **Compile the RTL** (and the property files: bound checker modules, `assume`s). Blackbox anything
   you do not want analyzed (memories replaced with abstract models, analog, encrypted IP).
2. **Define clocks and resets**: which signals are clocks (and their relationships if several), the
   reset signal, polarity, and duration. Formal starts *after* reset is released.
3. **Declare the properties**: assertions to prove, assumptions to apply, covers to reach. Usually
   via `bind`ed checker modules so the RTL is untouched.
4. **Set the proof configuration**: engines, per-property time/memory limits, proof depth for
   bounded runs.
5. **Run**; triage results: CEXs (debug in the tool's waveform viewer, which shows the assumption
   values chosen), inconclusives (converge, 8.4), unreachable covers (fix constraints).
6. **Report**: proven / bounded / failed / undetermined, plus formal coverage.

A minimal SymbiYosys script (open source, Yosys-based; fine for learning and for small blocks):

```
[options]
mode prove              # or: bmc (bounded only), cover
depth 40                # bound for BMC / induction depth
multiclock off

[engines]
smtbmc yices            # or: abc pdr  (unbounded IC3)

[script]
read -formal fifo.sv fifo_formal.sv
prep -top fifo_formal

[files]
../02-basic-tb/fifo.sv
fifo_formal.sv
```

Run `sby -f fifo.sby`. Results land in `fifo_sby/` with a `.vcd` per failing property. SymbiYosys
supports the immediate-assertion-in-`always` style and a growing subset of SVA (`assert property`
with `##`, `|->`, `$past`, `$stable`, `$rose`; sequences with repetition are limited). The chapter's
code uses the widely supported subset.

Commercial equivalents: Cadence JasperGold (FPV app; `clock`, `reset`, `prove` in a Tcl flow),
Synopsys VC Formal (FPV; `read_file`, `create_clock`, `check_fv`), Siemens Questa Formal / PropCheck.
Their SVA support is complete and their engines are far stronger; the workflow is the same six steps.

## The "apps": formal packaged for specific questions

Vendors ship pre-built flows that generate the properties for you. Knowing what they are is
expected in interviews.

| App | Question it answers | How it works |
|---|---|---|
| **FPV** (property verification) | Do my assertions hold? | The general case above |
| **Connectivity** | Is signal A connected to pin B, possibly through muxes and under conditions, exactly as the spreadsheet says? | Generates a property per row of a connectivity table; proves each. Replaces thousands of directed tests at SoC top level. |
| **Register / CSR** | Do registers reset, read, write, and mask per the register spec? | From IP-XACT/SystemRDL, generates access-policy properties per field. Formal equivalent of the RAL built-in sequences, exhaustive. |
| **X-propagation (X-prop)** | Can an X (from an uninitialized or don't-care source) reach an output or a control point? | Models X semantically (not as simulation's optimistic/pessimistic X); finds reset-domain and initialization bugs GLS would find, but at RTL. |
| **Deadlock / livelock** | Can an FSM or handshake get stuck forever? | Generates liveness properties per FSM/handshake with fairness. |
| **Unreachability (UNR) / coverage** | Which code-coverage items are structurally unreachable? | Proves each uncovered line/branch/toggle unreachable; exports waivers for the simulation coverage database. Most widely used app. |
| **Sequential equivalence checking (SEC)** | Are two RTL versions functionally identical (after a refactor, clock gating insertion, retiming, ECO)? | Miter of both designs; proves outputs equal for all inputs. Different from combinational LEC (RTL vs gates), which assumes matching state. |
| **Clock-domain crossing** (formal CDC) | Are CDC protocols (handshake, gray code, mux-select stability) obeyed? | Structural CDC finds crossings; formal proves the protocol assertions on them. |
| **Security / non-interference** | Can secret data reach an unprivileged output, or can an untrusted port write a protected register? | Taint-propagation properties; proves isolation. |
| **Automatic property generation / autochecks** | Common bugs with no properties written: arithmetic overflow, out-of-range index, FSM lockup, unreachable case arms, one-hot violations | Structural analysis plus formal proof of the auto-generated checks. Cheap, run first. |
| **Post-silicon / bug hunting** | Hit a specific deep scenario | Cover-directed search with waypoints; sometimes semi-formal (random + formal) |

## Formal coverage

How do you know your properties are enough? Formal tools measure:

- **Stimulus (assumption) coverage**: which RTL is exercisable under the assumptions (dead code
  under constraints = over-constraint).
- **Checker (proof) coverage / mutation coverage**: which RTL elements influence some proven
  assertion (a flop that no property observes is unverified). Some tools mutate the RTL and check
  whether a property fails: "formal core" or "proof core" analysis.
- **Bounded-proof depth vs required depth**: for each bounded property, did the bound exceed the
  design's sequential depth for that property (estimated via cover traces)?

Signoff for a formally verified block reports: properties proven (full/bounded with depth), covers
reached, checker coverage %, and the list of assumptions reviewed against the spec.

## Combining formal and simulation

- Assertions written for formal run in simulation for free (same SVA). Write once.
- Simulation coverage plus formal UNR removes the waiver burden.
- Formal proves the control corners; simulation runs the data through. A FIFO gets: formal for
  full/empty/pointer/integrity; simulation for throughput with realistic traffic and for the
  integration with real producers/consumers.
- Bounded-formal "smoke" runs in CI catch protocol regressions in minutes with no testbench.
- CEX traces can be replayed in simulation (tools export a testbench) to debug with familiar tools.

## Interview angle

- "Which formal apps have you used and for what?" Have a story for UNR (coverage closure) and
  connectivity or register checking; know what SEC vs LEC is.
- "How would you set up FPV on a new block?" The six steps; start with covers and autochecks.
- "What is formal coverage?"
- "How does formal fit with simulation on a project?"

## Mentor's notes

- Run the autochecks app on every block the day the RTL first compiles. It costs an hour and finds
  the out-of-range index and the missing default arm before anyone writes a test.
- SymbiYosys on your laptop is enough to learn the mental model. The commercial tools are
  different in scale, not in kind.
