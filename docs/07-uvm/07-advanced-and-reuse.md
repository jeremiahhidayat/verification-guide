# 7.7 Advanced UVM and Reuse

## Parameterized agents and interfaces

The tutorial spends two examples on this because it is the most common practical headache.

- A parameterized interface's virtual handle type includes the parameter value; every class that
  holds it must be parameterized too, or must use a package constant for the default.
- Register parameterized classes with `` `uvm_component_param_utils(T#(P1, P2)) `` /
  `` `uvm_object_param_utils ``. Each parameter combination is a distinct factory type; overrides must
  name the exact specialization.
- `uvm_config_db` keys are typed; `virtual axi_if #(32)` and `#(64)` are different entries.
- The pragmatic layered approach (tutorial's `agents_parameterized`): parameterize the *generic*
  classes (item, driver, monitor, sequencer, agent) with defaults from a package; keep the
  *DUT-specific* classes (env, scoreboard, test) unparameterized, using the package's known widths.
  `typedef axi_item #(pkg::W, ...) my_item_t;` keeps the code readable.

## Vertical reuse: block env inside a subsystem env

```systemverilog
class subsys_env extends uvm_env;
  fifo_env  fifo_env_h;       // the block env, unchanged
  dma_env   dma_env_h;
  axi_agent sys_axi_agent;    // new active agent at the subsystem boundary
  subsys_scoreboard sb;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // make the block agents passive: the RTL now drives those interfaces
    uvm_config_db#(uvm_active_passive_enum)::set(this, "fifo_env_h.wr_agent", "is_active", UVM_PASSIVE);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "fifo_env_h.rd_agent", "is_active", UVM_PASSIVE);
    fifo_env_h = fifo_env::type_id::create("fifo_env_h", this);
    ...
  endfunction
endclass
```

Requirements on the block env for this to work: it must not set its own agents active
unconditionally (read `is_active` from config); its scoreboard must subscribe to monitors; it must
get interfaces from config_db with names the subsystem can provide; it must not assume it is
`uvm_test_top.env` (use relative paths and `get_full_name()`); its sequences must be startable on
its sequencers from a higher virtual sequence when active.

Horizontal reuse (same agent on many DUTs) is the other axis; a VIP (verification IP) is an agent
plus its sequences, coverage, and documentation, packaged for reuse across projects.

## Objections done right

- Only the test (and possibly the scoreboard) raise objections. Drivers/monitors do not.
- The scoreboard raises when it has outstanding expected items and drops when they are matched;
  this prevents the phase from ending with data in flight. Alternatively set a drain time:
  `phase.phase_done.set_drain_time(this, 200ns)`.
- `+UVM_OBJECTION_TRACE` prints every raise/drop when a test ends early or never.
- Always set `+UVM_TIMEOUT`.

## Phase jumping and reset in the middle

To model an asynchronous reset mid-test: a reset monitor detects reset, calls
`phase.jump(uvm_pre_reset_phase::get())` (run-time phases), components clean up in `reset_phase`,
sequences restart in `main_phase`. Works but requires every component to be phase-aware. The common
alternative: a reset-aware driver (aborts on reset, waits for release) plus sequences wrapped in
`fork/join_any` with the reset event, restarted by the test. Choose per project; both are asked in
interviews as "how do you handle reset during a UVM test?"

## Callbacks

`uvm_callback` + `` `uvm_register_cb `` + `uvm_do_callbacks` let a test register an object whose
methods the driver calls at hook points (`pre_drive(item)`). Use for error injection into an agent
you cannot modify. Analysis ports have replaced most other historical callback uses.

## Heartbeat and end-of-test hygiene

`uvm_heartbeat` fails the test if a set of components stops raising objections for N cycles: a
watchdog for hung traffic. `check_phase` in every scoreboard for leftovers. `report_phase` in the
base test for the verdict. `final_phase` to close files.

## Performance

- Avoid field macros in hot transactions; hand-write `do_*`.
- `` `uvm_info `` with `$sformatf` evaluates the string even if not printed; guard expensive
  messages with `if (uvm_report_enabled(UVM_HIGH, UVM_INFO, "ID"))`.
- Analysis FIFOs are unbounded: a consumer that never reads leaks memory.
- `+UVM_NO_RELNOTES`, disable transaction recording (`+define+UVM_DISABLE_AUTO_ITEM_RECORDING`, as
  the tutorial's Makefile does) unless you use it.
- Sequencer arbitration with many concurrent sequences is slow; batch items.

## Anti-patterns to recognize (and fix) in inherited code

| Anti-pattern | Why it hurts | Fix |
|---|---|---|
| Scoreboard subscribed to the driver | Cannot go passive; checks intent, not reality | Subscribe to monitors |
| Checking inside sequences | Not reusable; duplicated logic | Scoreboard |
| `new()` instead of `type_id::create` | Factory overrides silently ignored | `create` |
| `$display`/`$error` in components | Not counted; verbosity uncontrollable | `uvm_info/error` |
| Hierarchical references from classes into the DUT (`tb_top.dut.x`) | Breaks at subsystem level | Interfaces, `bind`, config |
| One giant test with `if (mode == ...)` | Untestable, un-parallelizable | One test class per scenario, shared sequences |
| Virtual interface set with a broad `"*"` for multiple agents with the same field name | Wrong agent gets the wrong interface | Targeted paths or config object |
| Monitors that reuse one item object | Corrupts subscribers | New per transaction |
| Objections raised in every component | Test never ends; no one knows why | Test (+ scoreboard) only |

## UVM 1.2 / IEEE 1800.2 differences worth knowing

- `uvm_sequence::starting_phase` (1.1) became `get_starting_phase()`/`set_starting_phase()` (1.2).
- `uvm_reg` API gained `uvm_reg_field::get_mirrored_value` widely used; `uvm_reg_map::set_auto_predict`.
- 1800.2 renames some internals (`uvm_report_server` methods), removes deprecated APIs, and adds
  `uvm_policy` classes for copy/compare. Code written against the documented 1.2 API mostly works.
- `run_test()` and phases are unchanged in spirit throughout.

## Interview angle

- "How do you reuse a block-level UVM env at subsystem level?" Passive agents via config,
  monitor-fed scoreboards, config-driven interface lookup, virtual sequences on top.
- "How do you handle reset in the middle of a UVM test?" Phase jumping vs reset-aware driver.
- "What is a VIP?" Agent + sequences + coverage + docs, reusable.
- "Name three UVM anti-patterns you have fixed."

## Mentor's notes

- The best UVM code I have seen is boring: every agent looks the same, every env looks the same,
  and a new engineer can find the scoreboard in ten seconds. Cleverness in a testbench is a cost
  paid by every future reader.
- Keep a `uvm_debug_test` that builds the env, prints topology, prints the factory, prints the
  config, runs one item per agent, and exits. It is the first test you run after any refactor.
