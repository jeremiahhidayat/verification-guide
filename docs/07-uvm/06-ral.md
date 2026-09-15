# 7.6 The Register Abstraction Layer (RAL / UVM_REG)

## The problem RAL solves

Most blocks have a programming interface: a bank of registers reached over a bus (APB, AXI-Lite,
AHB, a proprietary CSR bus). Tests must configure the block by writing registers and check status by
reading them. Without abstraction, every test hard-codes addresses and bit positions, changes to the
register map break every test, and there is no automatic check that a register's reset value,
access policy (RW/RO/W1C), or side effects are correct.

RAL gives you a *model* of the register map as classes (`uvm_reg_block` > `uvm_reg` >
`uvm_reg_field`), generated from a machine-readable spec (IP-XACT, SystemRDL, a spreadsheet, via a
generator tool), plus:

- `reg.write(status, value)` / `reg.read(status, value)` / `field.set()` / `reg.update()` /
  `reg.mirror()` by *name*, on any bus, from any sequence.
- A **mirror**: the model's belief about each register's current value, updated on every access it
  sees (and optionally on every access the *monitor* sees, via a predictor), so `read` can be
  checked against expectation automatically.
- **Front-door** access (real bus transactions through an adapter to your bus agent) and
  **back-door** access (direct hierarchical peek/poke into the RTL flops, zero time) with the same API.
- **Built-in test sequences**: reset value check, bit-bash (every bit writable/readable as its
  access policy says), aliasing/access checks, memory walk.

## Structure

```
uvm_reg_block  (fifo_regs)                      the map: one per block, nestable
 ├── uvm_reg_map (default_map, base 0x0, APB)   address map: reg -> offset, endianness, bus
 ├── uvm_reg     CTRL  @0x00                    a register
 │    ├── uvm_reg_field enable  [0:0]  RW  reset 0
 │    └── uvm_reg_field flush   [1:1]  W1C reset 0
 ├── uvm_reg     STATUS @0x04
 │    ├── uvm_reg_field full   [0:0]  RO
 │    └── uvm_reg_field count  [8:1]  RO
 └── uvm_mem     BUF   @0x100, 256 x 32
```

Hand-writing this is tedious and error-prone; in practice it is generated. What you write by hand
is the **adapter** and the **integration** in the env.

## Adapter: register operations to bus transactions

```systemverilog
class apb_reg_adapter extends uvm_reg_adapter;
  `uvm_object_utils(apb_reg_adapter)
  function new(string name = "apb_reg_adapter");
    super.new(name);
    supports_byte_enable = 0;  provides_responses = 0;
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    apb_item t = apb_item::type_id::create("t");
    t.addr  = rw.addr;  t.write = (rw.kind == UVM_WRITE);  t.wdata = rw.data;
    return t;
  endfunction

  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    apb_item t;  if (!$cast(t, bus_item)) `uvm_fatal("ADPT", "wrong item type");
    rw.kind = t.write ? UVM_WRITE : UVM_READ;  rw.addr = t.addr;  rw.data = t.write ? t.wdata : t.rdata;
    rw.status = t.error ? UVM_NOT_OK : UVM_IS_OK;
  endfunction
endclass
```

## Integration in the environment

```systemverilog
function void build_phase(uvm_phase phase);
  ...
  regmodel = fifo_regs::type_id::create("regmodel");
  regmodel.build();                 // generated: creates regs/fields/map
  regmodel.lock_model();
  uvm_config_db#(fifo_regs)::set(this, "*", "regmodel", regmodel);   // sequences pick it up
  predictor = uvm_reg_predictor #(apb_item)::type_id::create("predictor", this);
  adapter   = apb_reg_adapter::type_id::create("adapter");
endfunction

function void connect_phase(uvm_phase phase);
  regmodel.default_map.set_sequencer(apb_agent.sequencer, adapter);   // front door goes through this agent
  regmodel.default_map.set_auto_predict(0);                            // use the explicit predictor instead
  predictor.map     = regmodel.default_map;
  predictor.adapter = adapter;
  apb_agent.monitor.ap.connect(predictor.bus_in);                      // mirror updated from OBSERVED traffic
  regmodel.add_hdl_path("tb_top.dut", "RTL");                          // for back-door; fields need hdl paths too
endfunction
```

Auto-predict (`set_auto_predict(1)`) updates the mirror from the *sequence's own* accesses; the
explicit predictor updates it from the *monitor*, so accesses from other masters (or the CPU at SoC
level) are also tracked. Use the predictor.

## Using it from a sequence

```systemverilog
class fifo_cfg_seq extends uvm_sequence;
  fifo_regs regmodel;
  virtual task body();
    uvm_status_e status;  uvm_reg_data_t val;
    if (!uvm_config_db#(fifo_regs)::get(null, get_full_name(), "regmodel", regmodel)) `uvm_fatal(...)
    regmodel.CTRL.enable.set(1);          // change the desired value in the model
    regmodel.CTRL.update(status);         // write only if desired != mirrored
    regmodel.STATUS.read(status, val);    // front door; mirror updated; compare against mirror if check enabled
    regmodel.STATUS.mirror(status, UVM_CHECK);   // read and CHECK against mirrored value
    regmodel.CTRL.write(status, 32'h3, UVM_BACKDOOR);   // zero-time poke into RTL
    val = regmodel.STATUS.count.get_mirrored_value();
  endtask
endclass
```

Access policies (`"RW"`, `"RO"`, `"WO"`, `"W1C"`, `"RC"`, `"W1S"`, ...) tell the model how the
mirror changes on write/read; `volatile` fields (hardware-updated status) are excluded from mirror
checks unless you predict them yourself.

## Built-in sequences

`uvm_reg_hw_reset_seq` (reset values), `uvm_reg_bit_bash_seq` (each bit per policy),
`uvm_reg_access_seq` (front-door write / back-door read consistency), `uvm_mem_walk_seq`,
`uvm_reg_shared_access_seq`, and the `uvm_reg_mem_built_in_seq` that runs them all. Running these on
day one of a new block finds register-map bugs before any functional test exists. Mark registers to
skip with `uvm_resource_db#(bit)::set({"REG::", reg.get_full_name()}, "NO_REG_TESTS", 1)`.

## Coverage

`uvm_reg` supports coverage models (`UVM_CVR_REG_BITS`, `UVM_CVR_ADDR_MAP`, `UVM_CVR_FIELD_VALS`)
if the generator emits covergroups; `regmodel.set_coverage(UVM_CVR_ALL)`. Address-map coverage
(every register accessed) is the cheap and useful one.

## Interview angle

- "What is RAL and why use it?" Named access, mirror, front/back door, built-in tests,
  independence from the address map.
- "Adapter vs predictor?" Adapter converts reg op to/from bus item; predictor updates the mirror
  from monitored traffic.
- "Front door vs back door?" Bus vs hierarchical poke; time vs zero time; when to use each (back
  door for setup speed and for checking that the front door actually wrote the flop).
- "`write`/`read` vs `set`/`update`/`mirror`?" Immediate bus op vs desired-value then conditional
  write; mirror = read and compare.
- "How does the mirror stay correct if the CPU writes a register?" Explicit predictor on the bus
  monitor.

## Mentor's notes

- Generate the model. Never hand-write more than a demo. If the project has no generator, that is
  the first script you write, and you own it.
- Volatile status fields are where RAL checks go wrong (`mirror(UVM_CHECK)` on a `count` field
  that changed since the last access). Either predict them from the scoreboard model or exclude
  them from checks; do not "fix" it by disabling checking everywhere.
