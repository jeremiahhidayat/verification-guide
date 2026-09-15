# 7.5 Configuration, the Factory, and Reporting

## `uvm_config_db`

A global, hierarchical key-value store. `set` from anywhere with a *scope* (context + instance-path
pattern); `get` from a component (or object with a context) resolves the most specific matching
entry.

```systemverilog
// set(context, instance_path_pattern, field_name, value)
uvm_config_db#(virtual fifo_wr_if)::set(null, "*", "wr_vif", wr_if);              // from the top: everyone
uvm_config_db#(virtual fifo_wr_if)::set(null, "uvm_test_top.env.wr_agent*", "vif", wr_if);   // targeted
uvm_config_db#(int)::set(this, "env.wr_agent.driver", "max_gap", 8);              // from a test: relative to 'this'
uvm_config_db#(uvm_active_passive_enum)::set(this, "env.rd_agent", "is_active", UVM_PASSIVE);
uvm_config_db#(fifo_cfg)::set(this, "env", "cfg", cfg);                           // a whole config object

// get(context, "", field_name, out)  in build_phase
if (!uvm_config_db#(virtual fifo_wr_if)::get(this, "", "vif", vif))
  `uvm_fatal("NOVIF", "vif not set for " ) 
```

Rules of thumb:

- The **type parameter must match exactly** between set and get (`int` vs `bit [31:0]` do not
  match; `virtual fifo_if #(8)` vs `virtual fifo_if #(16)` do not match). This is the number one
  "config_db get fails" cause.
- Sets made *higher* in the hierarchy (closer to the test) win over lower ones, and later sets win
  over earlier ones at the same level. So a test can override an env's default.
- `set` in `build_phase` *before* creating the child that will `get` it (build is top-down, so
  setting in the parent's build is early enough).
- Wildcards: `*` and `?` in the instance path, `"*"` for everyone. Broad wildcards are convenient
  and slow in big testbenches; prefer targeted paths for anything but the virtual interfaces.
- Always check the return value of `get` (or provide a default).
- `+uvm_set_config_int=path,field,value` / `+uvm_set_config_string=...` set integral/string entries
  from the command line.

**Config objects** bundle knobs: a `fifo_env_cfg` class with `is_active` per agent, gap ranges,
enable flags, and the virtual interfaces. The test builds and randomizes one, sets it once at
`"env"`, and components pull what they need from it. One `get` per component, one type to keep in
sync, `randomize()`able configuration for free.

`uvm_resource_db` is the lower-level store `uvm_config_db` is built on (no hierarchy semantics).
Use `uvm_config_db`.

## The factory

The factory answers "when component X asks for a `fifo_wr_driver`, what should it actually get?"

```systemverilog
// Registration (in the class): creates a proxy and registers the type by name
`uvm_component_utils(fifo_wr_driver)
`uvm_object_utils(fifo_wr_item)

// Creation (never call new() for components/items you may want to override)
driver = fifo_wr_driver::type_id::create("driver", this);
req    = fifo_wr_item::type_id::create("req");

// Overrides (in a test's build_phase, BEFORE the env creates the objects)
fifo_wr_driver::type_id::set_type_override(slow_wr_driver::get_type());              // everywhere
fifo_wr_item::type_id::set_inst_override(err_wr_item::get_type(), "env.wr_agent.*"); // one path
factory.set_type_override_by_type(fifo_wr_item::get_type(), err_wr_item::get_type());
factory.set_type_override_by_name("fifo_wr_item", "err_wr_item");                    // string form
factory.print();                                                                     // see what is registered/overridden
```

The override type must extend the original (`slow_wr_driver extends fifo_wr_driver`). Because
components hold base-type handles and every method worth overriding is virtual, the env runs the
derived behavior without knowing.

What this buys you, concretely:

- **Error-injecting transactions**: `err_wr_item extends fifo_wr_item` adds `constraint c_err`; the
  test overrides the type; every sequence now generates error items with no sequence changes.
- **A different driver timing model** for a stress test.
- **A stub scoreboard** for a performance run.
- **Swapping a monitor** for a debug version that logs everything.

Without the factory you would edit the env or thread "which type" parameters through every level.

Pitfalls: overrides must be set before `create` is called (so: in the test's `build_phase` before
`super.build_phase` creates the env, or at least before the env's build runs); string-based
overrides silently do nothing on a typo (prefer the type-based form); parameterized classes need
`` `uvm_component_param_utils(T#(P)) `` and each parameter value is a separate registered type.

## Field macros vs. `do_*` methods

```systemverilog
`uvm_object_utils_begin(fifo_wr_item)
  `uvm_field_int(data, UVM_ALL_ON)
  `uvm_field_int(gap,  UVM_ALL_ON | UVM_NOCOMPARE)
`uvm_object_utils_end
// gives you: copy(), compare(), print(), sprint(), pack(), unpack(), record(), and config_db auto-apply
```

Cost: significant run-time overhead per operation and code bloat; subtle semantics (`UVM_NOCOMPARE`
flags, `UVM_REFERENCE` for handles). Many production teams use `` `uvm_object_utils(T) `` alone and
write `do_copy`, `do_compare`, `do_print` (or `convert2string`) by hand. This chapter's code does the
latter; the tutorial does the former. Either is acceptable; be consistent within a project.

## Reporting control

```systemverilog
// Verbosity
+UVM_VERBOSITY=UVM_HIGH                                  // global, command line
env.wr_agent.set_report_verbosity_level_hier(UVM_DEBUG); // subtree
set_report_id_verbosity("DRV", UVM_NONE);                // silence one ID

// Actions: what happens on a message
set_report_severity_action(UVM_ERROR, UVM_DISPLAY | UVM_COUNT | UVM_STOP);   // stop on first error
set_report_max_quit_count(10);                                               // or after 10
set_report_severity_id_override(UVM_ERROR, "SB_NONFATAL", UVM_WARNING);      // demote a known issue

// Files
set_report_severity_file(UVM_ERROR, fh); set_report_default_file(fh); set_report_severity_action(UVM_INFO, UVM_LOG);
```

The report server summary at the end (`--- UVM Report Summary ---`) lists counts per severity and
per ID. Regression scripts parse it; a clean run has `UVM_ERROR : 0` and `UVM_FATAL : 0`, plus your
own PASSED banner.

## Command-line processor

`uvm_cmdline_processor` reads plusargs: `+UVM_TESTNAME`, `+UVM_VERBOSITY`, `+UVM_TIMEOUT`,
`+uvm_set_config_*`, `+uvm_set_verbosity=comp,id,verbosity,phase`, `+UVM_OBJECTION_TRACE`,
`+UVM_PHASE_TRACE`, `+UVM_CONFIG_DB_TRACE` (prints every set/get: the way to debug config_db
mismatches), `+UVM_DUMP_CMDLINE_ARGS`. User plusargs: `clp.get_arg_value("+seed=", s)`.

## Interview angle

- "config_db `get` returns 0. Causes?" Type mismatch, path mismatch, set after get, wrong context.
  Debug with `+UVM_CONFIG_DB_TRACE`.
- "What is the factory and why `type_id::create` instead of `new`?" Overrides; test-controlled
  substitution without editing the env.
- "Type override vs instance override?"
- "How do you make a test fail on the first error?" `UVM_STOP` action or `set_report_max_quit_count(1)`.
- "Field macros: pros and cons?"

## Mentor's notes

- One config object per env, randomized in the test, printed at `UVM_LOW` in the env's
  `end_of_elaboration_phase`. When a regression fails, the first thing you need is the
  configuration, and the log should have it.
- `factory.print()` in the base test's `end_of_elaboration_phase` costs nothing and answers "is my
  override actually active?" before you spend an hour on it.
