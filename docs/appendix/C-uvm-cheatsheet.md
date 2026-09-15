# C. UVM Cheat Sheet

## Hierarchy
`uvm_object` → `uvm_sequence_item`, `uvm_sequence`, config objects
`uvm_component` → `uvm_driver #(REQ,RSP)`, `uvm_monitor`, `uvm_sequencer #(REQ,RSP)`, `uvm_agent`,
`uvm_scoreboard`, `uvm_subscriber #(T)`, `uvm_env`, `uvm_test`

## Boilerplate
```systemverilog
import uvm_pkg::*;  `include "uvm_macros.svh"
class C extends uvm_component;  `uvm_component_utils(C)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
class O extends uvm_object;     `uvm_object_utils(O)
  function new(string name = "O"); super.new(name); endfunction
`uvm_component_param_utils(C#(P))   `uvm_object_param_utils(O#(P))
x = C::type_id::create("x", this);  o = O::type_id::create("o");
```

## Phases (in order)
build (↓, function) → connect (↑) → end_of_elaboration (↑) → start_of_simulation (↑) →
**run** (task; parallel with pre_reset/reset/post_reset/pre_configure/configure/post_configure/
pre_main/main/post_main/pre_shutdown/shutdown/post_shutdown) → extract (↑) → check (↑) → report (↑) → final (↓)
Always `super.<phase>(phase)`. `phase.raise_objection(this)` / `drop_objection` in tests.
`phase.phase_done.set_drain_time(this, t)`. `+UVM_TIMEOUT=t,YES`.

## config_db
```systemverilog
uvm_config_db#(T)::set(cntxt, "inst.path*", "field", value);   // cntxt=null → absolute from uvm_test_top
uvm_config_db#(T)::get(this, "", "field", var);                // returns bit; check it
```
Type must match exactly. Higher/later sets win. `+UVM_CONFIG_DB_TRACE`. `uvm_agent` reads `is_active`.

## Factory
```systemverilog
Base::type_id::set_type_override(Derived::get_type());
Base::type_id::set_inst_override(Derived::get_type(), "env.agent.*");
factory.set_type_override_by_name("Base", "Derived");   factory.print();
```
Set before `create`. Derived must extend Base.

## Sequences
```systemverilog
class S extends uvm_sequence #(ITEM);  task body();
  req = ITEM::type_id::create("req"); start_item(req); if (!req.randomize()) ...; finish_item(req);
  // responses: get_response(rsp);  driver: seq_item_port.item_done(rsp) or put(rsp); rsp.set_id_info(req)
seq.start(sequencer [, parent_seq, priority]);   `uvm_do(req)  `uvm_do_with(req, {..})  `uvm_do_on(req, sqr)
`uvm_declare_p_sequencer(VSQR)   // p_sequencer typed handle in virtual sequences
sequencer.set_arbitration(UVM_SEQ_ARB_FIFO|RANDOM|STRICT_FIFO|STRICT_RANDOM|WEIGHTED|USER);  lock()/grab()/unlock()/ungrab()
```
Driver: `seq_item_port.get_next_item(req); ... seq_item_port.item_done();` (or `get`/`put`, `try_next_item`).

## TLM
```systemverilog
uvm_analysis_port #(T) ap = new("ap", this);   ap.write(t);            // producer
uvm_analysis_imp #(T, THIS) imp = new("imp", this);  function void write(T t);   // consumer
`uvm_analysis_imp_decl(_x)  → uvm_analysis_imp_x #(T, THIS); function void write_x(T t);
uvm_subscriber #(T): built-in analysis_export + write(T t)
uvm_tlm_analysis_fifo #(T) f;  ap.connect(f.analysis_export);  f.get(t);   // buffered
uvm_blocking_put_port/get_port #(T); uvm_tlm_fifo #(T) f = new("f", this, depth);  put_export/get_export
connect in connect_phase: port.connect(export_or_imp)
```

## Reporting
`` `uvm_info(ID, msg, UVM_NONE|LOW|MEDIUM|HIGH|FULL|DEBUG) `` `` `uvm_warning `` `` `uvm_error `` `` `uvm_fatal ``
`+UVM_VERBOSITY=UVM_HIGH`; `set_report_verbosity_level_hier`; `set_report_severity_action(UVM_ERROR, UVM_DISPLAY|UVM_COUNT|UVM_STOP)`;
`set_report_max_quit_count(n)`; `uvm_report_server::get_server().get_severity_count(UVM_ERROR)`.

## Objects
`copy()`, `clone()`, `compare()`, `print()`, `sprint()`, `convert2string()`, `pack/unpack`;
override `do_copy`, `do_compare`, `do_print`, `do_pack`, `do_unpack`, `do_record`.
Field macros: `` `uvm_field_int(x, UVM_ALL_ON|UVM_NOCOMPARE|UVM_NOPRINT|...) `` between `*_utils_begin/_end`.

## RAL
`uvm_reg_block` > `uvm_reg` > `uvm_reg_field`; `uvm_reg_map`; `uvm_mem`; `uvm_reg_adapter` (`reg2bus`/`bus2reg`);
`uvm_reg_predictor #(BUS_ITEM)`; `map.set_sequencer(sqr, adapter)`; `reg.write/read(status, val [, UVM_FRONTDOOR|UVM_BACKDOOR])`;
`field.set()`, `reg.update()`, `reg.mirror(status, UVM_CHECK)`, `get_mirrored_value()`;
built-ins: `uvm_reg_hw_reset_seq`, `uvm_reg_bit_bash_seq`, `uvm_reg_access_seq`, `uvm_mem_walk_seq`, `uvm_reg_mem_built_in_seq`.

## Plusargs
`+UVM_TESTNAME=` `+UVM_VERBOSITY=` `+UVM_TIMEOUT=` `+UVM_OBJECTION_TRACE` `+UVM_PHASE_TRACE`
`+UVM_CONFIG_DB_TRACE` `+uvm_set_config_int=path,field,val` `+uvm_set_verbosity=comp,id,verb,phase`
`+UVM_NO_RELNOTES` `+UVM_DUMP_CMDLINE_ARGS`

## Top
```systemverilog
module tb_top; ... uvm_config_db#(virtual IF)::set(null, "uvm_test_top", "vif", if_inst); initial run_test(); endmodule
```
