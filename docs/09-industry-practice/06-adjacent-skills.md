# 9.6 Adjacent Skills

SystemVerilog and UVM are the core. These surround it, and senior engineers are expected to be
competent in most of them.

## Scripting: Python, Tcl, Make

- **Python** for everything around simulation: test-list generation, log parsing, result
  databases, coverage report post-processing, register-model generation from spreadsheets/RDL,
  golden-vector generation from reference algorithms (NumPy), stimulus file generation. Also for
  `cocotb`, a Python testbench framework that drives simulators through VPI/DPI; used for quick
  unit tests and by teams without UVM licenses. Know its tradeoffs: fast to write, Python-speed
  slow, no native constraint solver or covergroups (libraries exist), weak reuse compared to UVM.
- **Tcl** because every EDA tool is scripted in it: simulator `do` files, waveform setup, formal
  tool flows, synthesis. Enough to write loops, procs, and regexes.
- **Make / build systems** for compile-once-run-many flows with dependency tracking. Many teams
  use a Python-based flow (e.g., `fusesoc`, `edalize`, in-house) on top.
- **Shell and regex**: `grep -c UVM_ERROR`, `awk` over logs, `sed` over test lists. Daily.
- **Git**: branching, bisecting (`git bisect` to find the RTL commit that broke a test is a
  superpower), code review workflows.

## DPI-C: connecting SystemVerilog and C

The Direct Programming Interface lets SV call C functions (`import "DPI-C"`) and C call SV
(`export "DPI-C"`). Uses:

- **C reference models**: a codec, a crypto algorithm, an ISA model. Written once by the algorithm
  team; called from the scoreboard: `import "DPI-C" function int compute_expected(input int in0,
  input int in1);`.
- **Software tests** running natively (not on a CPU model) that access the DUT through an SV
  backdoor task exported to C.
- **File/OS interaction** beyond `$fopen`.

Type mapping: `int`, `byte`, `shortint`, `longint`, `real`, `string`, `chandle`; packed vectors
as `svBitVecVal`/`svLogicVecVal` arrays (4-state needs two bits per bit); open arrays via `svOpenArrayHandle`.
`context` imports may call exported SV tasks; `pure` imports have no side effects and can be
optimized. Spear chapter 12 is the standard reference.

## SystemC and TLM-2.0

SystemC (C++ library) models systems at the transaction level for architecture exploration and as
*virtual platforms* for early software development. Verification touches it when: the golden
reference model is a SystemC model (connect via UVM Connect / DPI), or when the testbench must
drive a mixed SV/SystemC simulation. TLM-2.0 defines the generic payload and blocking/nonblocking
transport sockets; UVM's `uvm_tlm_*` sockets mirror them for interoperability.

## Portable Stimulus (PSS)

Accellera's Portable Test and Stimulus Standard: a declarative language (with a C++ and a DSL
front end) for describing *scenarios* (actions, resources, data flow, constraints) that a tool
then realizes as UVM sequences, C tests for an embedded CPU, or emulation drivers. Motivation:
write the "DMA copies from memory A to B while the CPU polls" scenario once, run it at block level
(UVM), SoC level (C on the CPU), and emulation. Tools: Cadence Perspec, Synopsys VC PSS, Siemens
inFact/Questa PSS, Breker. Adoption is growing at SoC level; block-level teams rarely see it.
Know what it is and what problem it solves.

## Hardware/software co-verification, virtual platforms

Firmware teams need hardware before hardware exists. Virtual platforms (QEMU/SystemC-based
models of the SoC) run software early; hybrid emulation swaps blocks between fast models and RTL.
Verification supplies register models (the same RAL source), memory maps, and interrupt behavior to
the platform team, and uses the platform's software as SoC-level stimulus later.

## Mixed-signal

Analog blocks are verified with SPICE by analog engineers; the digital verification engineer's
role is the *interface*: real-number models (RNM, `real` types with `nettype` and resolution
functions in SV) of the analog blocks so the digital testbench can check ADC/DAC/PLL behavior at
digital-simulation speed; AMS co-simulation for the few tests that need it.

## Security verification

Increasingly a specialty: secure boot, key isolation, debug-port lockdown, side channels
(constant-time behavior), fault injection (glitch attacks modeled by forcing signals). Methods:
formal non-interference (taint) proofs, negative testing (attacker-model sequences), assertions
that secrets never appear on observable buses.

## AI-assisted verification

Current practical uses: generating boilerplate (agent skeletons, register models, test lists);
summarizing regression failures and suggesting buckets; drafting assertions from spec text for a
human to review; log and waveform question-answering; coverage-hole analysis suggesting
constraint changes. Where it fails today: anything requiring the precise LRM semantics this guide
spends a chapter on (Stitt notes that LLMs produced *no* valid race-condition examples). Treat
generated verification code as a junior engineer's first draft: review every line, run the
mutation check, and never let an unreviewed generated assertion into a signoff.

## Interview angle

- "What do you use Python for?" Have three concrete examples.
- "What is DPI and when have you used it?" C model, type mapping, `context`.
- "What is PSS?" Scenario portability across levels.
- "cocotb vs UVM?" Speed of writing vs runtime speed, reuse, solver/coverage.
- "How do you see AI tools in verification?" Boilerplate and analysis, with review; not semantics.

## Mentor's notes

- The engineer who can write the Python that turns a 40-page register spec into a RAL model and a
  register test in an afternoon is worth three who can only write UVM. Learn to automate the
  tedious parts of your own job.
- Read one DPI-C example end to end. It removes the fear of the C boundary, and the C boundary is
  where the algorithm team's golden model lives.
