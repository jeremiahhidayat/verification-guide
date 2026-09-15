# 7.1 UVM Fundamentals

## What UVM gives you, in chapter-6 terms

| Chapter 6 (plain SV) | UVM | What UVM adds |
|---|---|---|
| Transaction class | `uvm_sequence_item` | Factory registration, print/copy/compare/pack via macros or `do_*` |
| Generator | `uvm_sequence` running on a `uvm_sequencer` | Layering, arbitration between sequences, request/response, virtual sequences |
| Driver | `uvm_driver` | Standard handshake with the sequencer (`get_next_item`/`item_done`) |
| Monitor | `uvm_monitor` + `uvm_analysis_port` | Broadcast to any number of subscribers |
| Scoreboard | `uvm_scoreboard` + analysis exports/FIFOs | Standard connection points |
| Coverage class | `uvm_subscriber` | One-line connection to a monitor |
| Environment | `uvm_env` | Phased construction, nesting |
| Test | `uvm_test` + `run_test()` | Selected by `+UVM_TESTNAME`, factory overrides, config |
| Constructor injection / external init | `build_phase` + `connect_phase` + `uvm_config_db` | Late binding, hierarchical configuration |
| Polymorphic generator handles | Factory (`type_id::create`, `set_type_override`) | Replace *any* component or object from the test |
| `$display` with prefixes | `uvm_info/warning/error/fatal` | Verbosity, IDs, per-component control, counting |
| Scoreboard counts tests done | Objections | Any component can hold the phase open |

## The class hierarchy

```
uvm_void
└── uvm_object                     transient data: transactions, sequences, config objects
    ├── uvm_transaction
    │   └── uvm_sequence_item      <- your transactions
    ├── uvm_sequence_base
    │   └── uvm_sequence #(REQ,RSP) <- your sequences
    └── uvm_report_object
        └── uvm_component          structural, has a parent, participates in phases
            ├── uvm_driver #(REQ,RSP)
            ├── uvm_monitor
            ├── uvm_sequencer #(REQ,RSP)
            ├── uvm_agent
            ├── uvm_scoreboard
            ├── uvm_subscriber #(T)
            ├── uvm_env
            └── uvm_test
```

**`uvm_object` vs `uvm_component`** is the first distinction to internalize:

- Objects are *data*. Created any time, anywhere, by anyone; no parent; no phases. Constructor
  `new(string name)`. Registered with `` `uvm_object_utils ``.
- Components are *structure*. Created in `build_phase`, have a parent and therefore a hierarchical
  name (`uvm_test_top.env.wr_agent.driver`), participate in every phase, cannot be created after
  build. Constructor `new(string name, uvm_component parent)`. Registered with
  `` `uvm_component_utils ``.

A sequence is an object (it is a *program* of transactions, not a piece of the structure). A
sequencer is a component (it is the *place* sequences run). This is why sequences are started on
sequencers and why `uvm_config_db::get` from a sequence uses a different context (7.5).

## Phases

Every component has the same phase methods, called top-down or bottom-up by UVM at the right time:

| Phase | Kind | Direction | What you do there |
|---|---|---|---|
| `build_phase` | function | top-down | `type_id::create` children; `uvm_config_db::get` configuration |
| `connect_phase` | function | bottom-up | Connect TLM ports/exports; assign virtual interfaces to children |
| `end_of_elaboration_phase` | function | bottom-up | Final checks; print topology |
| `start_of_simulation_phase` | function | bottom-up | Rarely used; banner messages |
| `run_phase` | task (time-consuming) | all in parallel | Drivers, monitors, scoreboards run `forever`; tests start sequences |
| `extract_phase` | function | bottom-up | Pull data out of scoreboards/coverage |
| `check_phase` | function | bottom-up | Final checks: scoreboard empty, no outstanding transactions |
| `report_phase` | function | bottom-up | Print summary; decide PASS/FAIL |
| `final_phase` | function | top-down | Last words; close files |

`run_phase` is subdivided into twelve *run-time* phases (`pre_reset`, `reset`, `post_reset`,
`pre_configure`, `configure`, ..., `main`, ..., `shutdown`, `post_shutdown`) that run *in parallel
with* `run_phase`. Some teams use `reset_phase`/`main_phase` for sequencing reset vs traffic; most
use `run_phase` only and handle reset in the top or a reset sequence. Know they exist; do not mix the
two styles carelessly (a component that raises an objection in `main_phase` while another only uses
`run_phase` creates confusing end-of-test behavior).

**Why top-down build and bottom-up connect?** A parent must exist and be configured before it can
create children (build); children's ports must exist before the parent can connect them (connect).

**Always call `super.<phase>(phase)`** in your override. `build_phase` in particular does the
automatic config-db-to-field application (`uvm_field_*` macros) in the base.

## Objections: how the run phase ends

`run_phase` ends when no component holds an objection. The pattern:

```systemverilog
task run_phase(uvm_phase phase);
  phase.raise_objection(this, "starting traffic");
  seq.start(env.wr_agent.sequencer);      // blocks until the sequence's body finishes
  phase.drop_objection(this, "traffic done");
endtask
```

Typically only the test raises/drops. Drivers and monitors run `forever` and never object. After
the last drop, UVM waits `phase.phase_done.set_drain_time(this, 100ns)` (if set) and then ends the
phase, killing all `run_phase` threads. If the scoreboard still has expected items, `check_phase`
must catch it, because `run_phase` will not wait for them. A common refinement: the scoreboard
raises an objection while it has outstanding expected transactions (7.7).

`+UVM_TIMEOUT=<time>` (or `uvm_top.set_timeout`) sets a global watchdog; always set one.

## The testbench top

```systemverilog
module tb_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import fifo_uvm_pkg::*;

  logic clk = 0, rst;
  always #5 clk = ~clk;
  fifo_wr_if wr_if (clk, rst);
  fifo_rd_if rd_if (clk, rst);
  fifo dut (...);

  initial begin : reset ... end                        // reset in the top, or via a reset sequence

  initial begin
    uvm_config_db#(virtual fifo_wr_if)::set(null, "*", "wr_vif", wr_if);   // publish interfaces
    uvm_config_db#(virtual fifo_rd_if)::set(null, "*", "rd_vif", rd_if);
    run_test();                                        // +UVM_TESTNAME=<class> selects the test
  end
endmodule
```

`run_test()` creates the test by name through the factory (as `uvm_test_top`), which creates the
env, which creates the agents, ... then runs every phase and calls `$finish`. The module-level world
(clock, reset, interfaces, DUT, `bind`ed assertions) stays exactly as in chapter 6.

## Reporting

```systemverilog
`uvm_info("DRV", $sformatf("driving %s", req.convert2string()), UVM_MEDIUM)
`uvm_warning("SB", "unexpected but tolerable")
`uvm_error("SB", $sformatf("got %h expected %h", act, exp))     // counted; test fails
`uvm_fatal("CFG", "no virtual interface")                       // stops immediately
```

Verbosity levels `UVM_NONE < LOW < MEDIUM < HIGH < FULL < DEBUG`; a message prints if its level is
at or below the current verbosity (`+UVM_VERBOSITY=UVM_HIGH`, or per component
`set_report_verbosity_level_hier`). IDs (`"DRV"`) let you filter and change actions per message
type (`set_report_severity_id_action`). The report server counts errors; the standard
`report_phase` in a base test reads `uvm_report_server::get_server().get_severity_count(UVM_ERROR)`
and prints PASSED/FAILED (tutorial's base tests do exactly this). SVA failures route into the same
count with `else \`uvm_error(...)` in the action block.

Rule: **`uvm_error` for anything the test should fail on; never `$error` or `$display` in UVM
components.** Regression scripts key on the UVM summary.

## Macros vs. no macros

`` `uvm_component_utils(T) `` / `` `uvm_object_utils(T) `` register the class with the factory and
define `get_type_name`. Non-negotiable.

`` `uvm_field_int(x, UVM_ALL_ON) `` etc. between `_utils_begin`/`_end` auto-generate copy, compare,
print, pack, record. Convenient; slow (reflection-like code at run time) and occasionally wrong
(compare of don't-care fields). Many teams forbid field macros in transactions on performance
grounds and hand-write `do_copy`, `do_compare`, `do_print`, `convert2string`. Know both; the tutorial
uses field macros for brevity, this chapter's code hand-writes `do_*` for the item so you see the
shape.

## UVM versions

- **UVM 1.1d** (2013): the long-lived workhorse; what most legacy code targets.
- **UVM 1.2** (2014): minor API changes (`uvm_config_db` unchanged; `starting_phase` became
  `get_starting_phase()`; `uvm_reg` updates). Questa ships 1.1c/1.1d/1.2.
- **IEEE 1800.2** (2017/2020) and the Accellera 1800.2 implementation: the standard; small API
  renames; the concepts are identical.

Interviewers rarely care which; they care whether you know phases, factory, config_db, TLM,
sequences, and objections. That is 7.2 to 7.5.

## Interview angle

- "`uvm_object` vs `uvm_component`?" Data vs structure; parent; phases; constructor signature.
- "List the phases and what you do in build vs connect." And "why top-down/bottom-up?"
- "How does the run phase end?" Objections; drain time; timeout.
- "Where do you set the virtual interface, and how does a driver get it?" Top publishes with
  `config_db::set`; driver/agent `get`s in `build_phase`.
- "`uvm_error` vs `$error`?" Report server counting; test pass/fail.

## Mentor's notes

- Read the UVM source once. `uvm_root::run_test`, `uvm_phase`, `uvm_sequencer_base`, and
  `uvm_config_db` are shorter than you fear, and after reading them "why does UVM do X" stops being
  mysterious.
- The tutorial's remark is right: UVM is overkill for an ALU and exactly right for a block with
  standard interfaces that must be reused at the next level. Choose accordingly and be able to
  defend the choice.
