# E. Glossary

| Term | Meaning |
|---|---|
| **Agent** | UVM component bundling sequencer, driver, monitor for one interface |
| **AMBA / AXI / AHB / APB** | ARM bus standards: AXI (high performance, channels), AHB (pipelined), APB (simple peripheral) |
| **AXI-Stream** | Unidirectional data-stream protocol: tvalid/tready/tdata/tlast/tkeep/tstrb/tid/tdest/tuser |
| **Assertion** | Executable check; immediate (procedural) or concurrent (temporal, clocked) |
| **Assumption** | Constraint on inputs (formal); checked like an assertion in simulation |
| **ATPG** | Automatic test pattern generation (for manufacturing test, DFT) |
| **BFM** | Bus functional model: procedural code that drives/monitors a protocol |
| **BMC** | Bounded model checking: exhaustive search to a fixed depth |
| **Bin** | A bucket in a coverpoint; hit count decides coverage |
| **bind** | SV construct to instantiate a checker inside another scope without editing it |
| **CDC / RDC** | Clock / reset domain crossing |
| **CEX** | Counterexample: a formal trace violating a property |
| **Checker** | SV container for assertions and modeling code; also generic term for any checking component |
| **Clocking block** | Interface construct defining sampling/driving skew for race-free testbench access |
| **Constraint** | Declarative restriction on random variables |
| **Coverage (code / functional / assertion)** | Metrics of what was exercised (RTL structure / plan items / assertion activity) |
| **Covergroup / coverpoint / cross** | SV functional coverage constructs |
| **CRV** | Constrained-random verification |
| **Delta cycle** | Zero-time iteration within a simulation time step |
| **DFT** | Design for test (scan, BIST, JTAG) |
| **DPI** | Direct Programming Interface: SV to C/C++ |
| **Driver** | Converts transactions to pin activity |
| **DUT / DUV** | Design under test / verification |
| **Emulation** | Running RTL on specialized hardware at MHz speeds |
| **Environment (env)** | Container that builds and connects agents, scoreboards, coverage |
| **Escape** | A bug found at a later stage than it should have been |
| **Factory** | UVM registry allowing type/instance overrides at creation |
| **Formal (FPV)** | Exhaustive property proof via model checking |
| **FSDB / WLF / VCD / SHM** | Waveform file formats (Verdi / Questa / standard / Xcelium) |
| **GLS** | Gate-level simulation |
| **Golden model / reference model** | Independent implementation used to compute expected results |
| **IC3 / PDR** | Unbounded formal engines (inductive) |
| **Immediate assertion** | `assert (expr)` in procedural code |
| **Implication** | `\|->` / `\|=>` in SVA; `->` in constraints |
| **Interface** | SV bundle of signals with optional tasks, assertions, modports |
| **IP-XACT / SystemRDL** | Register/IP description formats used to generate RAL models |
| **k-induction** | Formal proof technique: base case + inductive step of length k |
| **LEC / SEC** | Logic (combinational) / sequential equivalence checking |
| **Lint** | Static RTL/testbench rule checking |
| **Liveness / safety** | "Eventually good" / "never bad" properties |
| **LRM** | Language Reference Manual (IEEE 1800) |
| **Mailbox / semaphore / event** | SV inter-process communication primitives |
| **Modport** | Directional view of an interface |
| **Monitor** | Passive component reconstructing transactions from pins |
| **Mutation** | Deliberately breaking the DUT to confirm checks fire |
| **NBA** | Nonblocking assignment (region) |
| **Objection** | UVM mechanism holding a phase open |
| **OVM / VMM / eRM** | Predecessor methodologies to UVM |
| **Passive / active** | Agent that only monitors / also drives |
| **Phase** | UVM lifecycle step (build, connect, run, ...) |
| **Plusarg** | `+NAME=value` command-line option (`$value$plusargs`) |
| **Predictor** | RAL component updating the register mirror from bus traffic |
| **PSS** | Portable Test and Stimulus Standard |
| **Race condition** | Behavior dependent on undefined process ordering |
| **RAL / uvm_reg** | Register abstraction layer |
| **Regression** | Automated run of the test suite against a design revision |
| **RTL** | Register-transfer level |
| **Sampled value** | Value captured in the Preponed region for SVA |
| **Scoreboard** | Component comparing expected and actual transactions |
| **Seed** | Random number generator initialization; reproduction key |
| **Sequence / sequencer / sequence item** | UVM stimulus program / arbiter / transaction |
| **Signoff** | Formal review deciding verification is complete against exit criteria |
| **SVA** | SystemVerilog Assertions |
| **TLM** | Transaction-level modeling (UVM ports; SystemC TLM-2.0) |
| **UNR** | Unreachability analysis (formal for coverage waivers) |
| **UPF / CPF** | Power intent formats |
| **UVM** | Universal Verification Methodology |
| **Vacuous** | Assertion pass with the antecedent never true |
| **VIP** | Verification IP: reusable agent + sequences + coverage + docs |
| **Virtual interface** | Class handle to an interface instance |
| **Virtual sequence / sequencer** | Coordinates sequences across multiple sequencers |
| **vPlan** | Verification plan |
| **X / Z** | Unknown / high impedance (4-state) |
| **X-prop** | X-propagation analysis |
