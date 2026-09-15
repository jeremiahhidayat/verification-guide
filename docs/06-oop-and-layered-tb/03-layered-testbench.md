# 6.3 The Layered Testbench

## Why layers

A flat testbench mixes four concerns in one process: *what* to send (scenario), *how* to send it on
pins (protocol), *what came back* (observation), and *was it right* (checking). Any change to one
concern risks the others, and nothing is reusable. Layers separate them:

```
  ┌────────────────────────────────────────────────────────────────────┐
  │ TEST         picks the environment configuration and the scenarios │
  ├────────────────────────────────────────────────────────────────────┤
  │ ENVIRONMENT  builds and connects everything below                  │
  ├──────────────────────┬─────────────────────────┬───────────────────┤
  │ SCENARIO/FUNCTIONAL  │ generator / sequence    │ scoreboard,       │
  │                      │ (what to send)          │ coverage,         │
  │                      │                         │ reference model   │
  ├──────────────────────┼─────────────────────────┼───────────────────┤
  │ COMMAND              │ driver (transaction ->  │ monitor (pins ->  │
  │                      │ pin wiggles)            │ transaction)      │
  ├──────────────────────┴─────────────────────────┴───────────────────┤
  │ SIGNAL       interface / virtual interface / BFM tasks             │
  ├────────────────────────────────────────────────────────────────────┤
  │ DUT                                                                │
  └────────────────────────────────────────────────────────────────────┘
```

Data flows down the left (transactions become pins) and up the right (pins become transactions).
Checking lives at the transaction level, where it is independent of pin timing. The test at the top
touches only configuration and scenarios.

## The components, and the one question each answers

### Transaction ("what is one unit of work?")

A class with `rand` fields for stimulus, plain fields for observed data, constraints for legality,
and `convert2string`/`compare`/`copy`. It carries no timing. The same class is used on the way down
(generated) and on the way up (observed), which is what makes the scoreboard's comparison trivial.

Abstraction level is a design decision: a beat-level AXI item (one `tdata`) vs a packet-level item
(an array of beats with `tlast` implied). The tutorial's `multiple_tests` example supports both in
one item and shows the tradeoff: packet level is more convenient, beat level reports errors in the
cycle they occur.

### Generator / sequence ("what to send, in what order?")

Produces transactions, usually by `randomize()` in a loop, sometimes with state (consecutive values,
a read after each write). Hands them to the driver through a mailbox. Knows nothing about pins.
Different tests use different generators; that is the whole point of making it a class with a
virtual `run()`.

### Driver ("how does a transaction become pin activity?")

Gets a transaction, executes the protocol on the virtual interface (`<=` on signals, waits for
`ready`, honors delays), signals completion. The *only* place that knows the protocol's timing.
Reusable across every DUT with that interface. Optional randomization of protocol-legal timing
(gaps, `valid` de-assertion) lives here or in the transaction.

### Monitor ("what actually happened on the pins?")

Watches the interface, reconstructs transactions from handshakes (`@(posedge clk iff valid &&
ready)`), and publishes them. Passive: never drives. Never trusts the driver: it observes what the
DUT *saw* and *produced*, which is different from what the generator intended whenever the driver
or DUT drops, delays, or reorders. One monitor per interface, on both the input and output sides.

### Scoreboard ("was it right?")

Receives observed input transactions, computes/stores expected outputs; receives observed output
transactions, compares. Owns the reference model. Counts pass/fail; must be empty at the end.

### Coverage collector ("did we exercise what we planned?")

Receives the same observed transactions as the scoreboard and samples covergroups. Kept separate
from the scoreboard so either can be swapped.

### Environment ("how is it all wired?")

Constructs the components (via constructor arguments or a factory), creates the mailboxes, connects
them, starts the threads (`fork` of every `run()`), and knows when the test is done. Configurable:
number of agents, active/passive, knobs.

### Test ("which scenario, which configuration?")

Selects generators, sets knobs, runs the environment, reports. Multiple tests per environment, chosen
at run time by a plusarg (`+TEST=random`) so one compile serves all.

## Constructing and connecting: two styles

**External initialization** (tutorial's `env`/`env2`): construct with `new()`, then assign
`drv.vif = vif; drv.mbx = mbx;` from outside. Flexible (you can swap pieces after construction),
but a missing assignment is a runtime null error, not a compile error.

**Constructor injection** (tutorial's `env3`): every dependency is a constructor argument.
Objects are valid the moment they exist; forgetting one is a compile error. Less flexible.

UVM uses external initialization with phases (`build_phase` constructs, `connect_phase` wires) and
a factory, trading compile-time safety for run-time configurability. Know both; use injection in
plain SV, and understand why UVM does not.

## The blueprint / factory pattern

The environment should construct *whatever type the test wants* without being edited. Two plain-SV
ways:

1. **Blueprint object**: the environment holds a `base_txn blueprint`; the generator does
   `t = blueprint.copy(); t.randomize();`. The test replaces `env.blueprint` with a `short_txn`
   before running. Every generated transaction is now a `short_txn`, with its extra constraints.
   Spear chapter 8.
2. **Virtual generator/driver hierarchy**: the test constructs the concrete `random_generator` or
   `consecutive_generator` and passes it to the environment as a `base_generator` (tutorial's
   `bit_diff_oop/test.svh`).

UVM's factory generalizes both: `type_id::create()` consults a registry of overrides that the test
sets by type or by instance path. Section 7.5.

## Callbacks

A callback is a hook the environment calls at defined points (`pre_drive`, `post_monitor`), with an
empty default; a test registers an object that overrides it. Uses: inject an error into 1% of
transactions without touching the driver; feed the scoreboard from the monitor without the monitor
knowing the scoreboard exists. UVM has `uvm_callback`; analysis ports cover the second use so well
that callbacks are mostly used for the first.

## Configuration objects

Instead of passing ten knobs to every constructor, bundle them in a `config` class (`num_agents`,
`is_active`, `min_gap`, `max_gap`, `error_rate`), randomize it in the test (with constraints), and
hand one handle down the hierarchy. Spear 7.7.2, UVM `uvm_config_db` with a config object in 7.5.

## A complete plain-SV example

[`code/06-layered-tb/`](../../code/06-layered-tb/) implements all of this for the FIFO: a write
agent (generator, driver, monitor) on the write interface, a read agent on the read interface, a
scoreboard with a queue model, a coverage collector, an environment, a base test, and two tests
(`random`, `fill_drain`) selected by `+TEST=`. Read it top down starting at `tb_top.sv`, then bottom
up starting at `fifo_txn.svh`.

## When is this overkill?

The tutorial ends its CRV section with `bit_diff_tb_no_hierarchy`: the same responsibilities as
separate `initial` blocks and mailboxes, no classes, and the comment "this is likely how I would do
it." For a single-interface unit test that will never be reused, that is the right call. The class
hierarchy earns its cost when any of these is true: more than one interface, more than one test
scenario, reuse at a higher level, more than one engineer. Which describes nearly every real block.

## Interview angle

- "Draw a layered testbench and explain each component." Use the diagram; emphasize that checking
  is at transaction level and that the monitor does not trust the driver.
- "Driver vs monitor?" Active vs passive; one converts down, the other up.
- "Where does the reference model live?" Scoreboard.
- "How does a test change stimulus without modifying the environment?" Blueprint/factory,
  polymorphic generators, callbacks, configuration objects.
- "Why should the monitor be separate from the driver?" Independence: it observes what happened,
  including what the DUT dropped; it works in passive mode when another block drives the interface.

## Mentor's notes

- Build the monitor and scoreboard *first*, driven by the designer's own directed test. You get
  checking immediately, and you learn the interface by observing it before you write a driver for
  it.
- Every component prints a one-line transaction log at `UVM_MEDIUM`-equivalent verbosity with a
  consistent prefix (`[DRV]`, `[MON_WR]`, `[SB]`). Debugging a layered testbench is reading four
  logs side by side; make them line up.
