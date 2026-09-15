# 10.3 Design Challenges: "How Would You Verify X?"

Use the chapter-0 structure every time: (1) what does it do, what are the interfaces, what are the
configurations; (2) how could it be wrong (bug hypotheses); (3) stimulus; (4) checking; (5)
coverage and done criteria; plus (6) what formal takes and (7) what changes at the next level.
Talk for two minutes per item; draw the environment.

## D1. Synchronous FIFO

1. **Function**: WIDTH x DEPTH, write/read enables, full/empty (maybe count, almost-full), read
   latency, behavior on write-at-full / read-at-empty (ignore vs error flag), reset.
2. **Bugs**: full/empty off-by-one (pointer wrap), simultaneous read/write at boundaries,
   pointer MSB trick wrong, reset of pointers only (stale data OK?) vs memory, read latency mismatch
   with the flags, X on `rd_data` before first write.
3. **Stimulus**: phased (fill, drain, random with biases), bursts, back-to-back, reset mid-traffic;
   random `wr_data` with extremes.
4. **Checking**: queue model; full/empty/count invariants every cycle; read data one cycle after
   accepted read; write-at-full ignored (count stable); `!$isunknown`; end-of-test empty model.
5. **Coverage**: occupancy bins with transitions, the four corners in a cross, burst lengths, reset
   while non-empty; assertions non-vacuous.
6. **Formal**: local invariants + symbolic tracked write for integrity; covers for corners. This
   block is a textbook full-proof target.
7. **Next level**: agents passive; interface assertions remain; the subsystem scoreboard checks
   producer-to-consumer end-to-end.

## D2. Round-robin arbiter (N requesters, one grant)

1. Requests, grants, optional priority/weights, locking, back-pressure from the resource.
2. Two grants at once, grant to a non-requester, starvation, wrong rotation after a grant, grant
   during reset, behavior when all request every cycle vs sparse.
3. Random request patterns with modes: all-on, single, rotating, bursty; weights randomized.
4. `$onehot0(grant)`, `grant[i] -> req[i]`, bounded starvation `req[i] |-> ##[1:N] grant[i]`,
   rotation property (next grant is the first requester after the last granted index), a reference
   model computing the expected grant each cycle from the request vector and last-grant state.
5. Cross: request pattern x last grant; all N grant transitions; starvation depth histogram.
6. Formal: this is *the* formal target: fairness/liveness with bounded latency, one-hot, no
   starvation; case-split by N.

## D3. APB slave with a register bank

1. APB3/4 protocol (PSEL/PENABLE/PWRITE/PADDR/PWDATA/PRDATA/PREADY/PSLVERR); register map with
   RW/RO/W1C/RC fields; side effects (writing CTRL starts something); reserved addresses.
2. Wrong address decode, field masks, reset values, W1C behavior, read side effects, PSLVERR on
   bad address, PREADY timing, write during busy.
3. RAL-driven: built-in reset/bit-bash/access sequences first; then random register traffic with
   the APB agent; error injection (unaligned, out-of-range).
4. RAL mirror with predictor from the APB monitor; protocol assertions in the APB interface
   (PENABLE follows PSEL, signals stable during access); side-effect checks via the functional
   scoreboard.
5. Address-map coverage (every register R and W), field value coverage for enums, error response
   cover, cross register x access type.
6. Formal: register app (access policy per field, exhaustively), APB protocol compliance.

## D4. AXI-Stream width converter (e.g., 32-bit to 8-bit with tkeep/tlast)

1. Upsizing/downsizing, tkeep/tstrb handling, tlast alignment, back-pressure both sides,
   packet boundaries, null bytes.
2. Byte ordering, tlast on the wrong beat, dropped/duplicated bytes under back-pressure, tkeep
   holes, stall with valid held, ratio not integral.
3. Packet-level sequences with random lengths (including 1 byte and lengths not multiple of the
   ratio), random tkeep patterns, random ready toggling on the output, reset mid-packet.
4. Packet-level scoreboard: reassemble bytes from both monitors and compare payload and
   boundaries; AXI-Stream protocol assertions in the interface; throughput check (no bubble when
   both sides ready).
5. Length mod ratio bins, tkeep patterns, back-pressure duration bins, back-to-back packets.
6. Formal: protocol compliance; symbolic byte tracking through the converter (harder but doable).

## D5. Direct-mapped or set-associative cache controller

1. Hit/miss, write-back vs write-through, replacement (LRU/pseudo-LRU), fills, evictions,
   coherence if shared, flush/invalidate, bypass regions.
2. Wrong hit determination (tag compare, valid bit), dirty-line loss on eviction, replacement
   policy wrong, ordering of miss under miss, flush not writing back, X in uninitialized tag RAM.
3. Address streams with controlled locality (knobs for set conflicts), random mix of R/W, flushes,
   back-pressure from memory.
4. Memory model as golden (all writes visible to reads regardless of caching) plus a cache model
   for policy-level checks (expected hit/miss, eviction order); memory-side monitor checks only
   necessary traffic; assertions on tag/valid/dirty invariants.
5. Hit/miss x R/W, eviction with dirty line, set conflict depth, flush during miss.
6. Formal: coherence/consistency invariants on a reduced configuration (2 sets, 2 ways); memory
   abstracted with symbolic address tracking.

## D6. DMA engine (descriptor-driven, one or more channels)

1. Descriptor format, linked lists, channel arbitration, bus master interface (AXI), interrupts
   on completion/error, byte enables/unaligned transfers, pause/abort.
2. Off-by-one in length, unaligned corner cases, descriptor fetch ordering, interrupt lost or
   double, channel starvation, abort mid-burst leaving state, error propagation.
3. Randomized descriptors (lengths, alignment, chains), multiple channels concurrent, memory
   model with random latency and errors, abort/pause at random times, software-like control via
   register sequences.
4. Golden memory model: after completion, destination equals source for each descriptor; bus
   protocol assertions; interrupt-to-status consistency; scoreboard tracks descriptors in flight.
5. Length/alignment bins, chain lengths, channel concurrency, error types, abort points.
6. Formal: arbitration fairness, register access, control FSM deadlock; datapath left to sim.

## D7. Interrupt controller

1. Sources (level/edge), masking, priority, pending/clear semantics (W1C), nesting, vector
   output, CPU handshake.
2. Lost edge interrupts, mask timing (masking a pending interrupt), priority inversion, clear
   racing with a new event, spurious interrupts.
3. Random source activity with edge/level modes, random mask/priority register writes, CPU
   acknowledge with random latency, simultaneous events.
4. Model of pending/mask/priority computing the expected line and vector each cycle; assertions:
   pending set on event, cleared only by W1C, output equals highest-priority unmasked pending.
5. Sources x mode x masked; simultaneous events; clear-vs-event same cycle.
6. Formal: perfect target: small state, deep corners (clear/event same cycle), liveness (pending
   eventually serviced under fairness).

## D8. Clock-domain-crossing FIFO (async FIFO)

Everything in D1 plus: gray-code pointers (one bit change per cycle assertion), synchronizer depth
and its effect on full/empty pessimism, random clock ratios and phases in the testbench,
metastability injection, CDC tool run; formal for the gray-code and pointer properties per domain.

## How to close any answer

"...and I would run the designer's smoke test against my monitor and scoreboard on day one, break
the RTL on purpose to confirm the checks fire, and review the plan and coverage model with the
designer before closure." That sentence tells the interviewer you have done this before.
