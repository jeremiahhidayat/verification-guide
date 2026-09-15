# 6.2 Threads and Inter-Process Communication

A layered testbench is a set of cooperating threads: the generator produces, the driver consumes and
drives, the monitors watch, the scoreboard compares. They must start together, hand data to each
other without races, and stop cleanly. SystemVerilog gives you `fork/join` for threads and
events/semaphores/mailboxes for communication.

## `fork` / `join` variants

```systemverilog
fork
  gen.run();
  drv.run();
  mon.run();
  sb.run();
join          // block until ALL branches finish (never, if any is a forever loop)

fork
  gen.run();       // finishes after N transactions
  drv.run();       // forever
  mon.run();       // forever
join_any      // block until ANY branch finishes: here, when the generator is done
disable fork; // then kill the remaining branches

fork
  monitor_forever();
join_none     // do not block; the parent continues immediately. Background threads.
...
wait fork;    // later: block until all children spawned by this process finish
```

Rules and traps:

- Each branch is a separate thread. A branch is a single statement; use `begin ... end` for more.
- **Loop variables in forked branches**: a `fork` inside a `for` loop captures the loop variable
  by *reference* unless you copy it into an `automatic` local first:

  ```systemverilog
  for (int i = 0; i < 4; i++) begin
    fork
      automatic int k = i;       // per-iteration copy
      drive_port(k);
    join_none
  end
  ```
  Without `automatic int k`, every branch sees the final value of `i`.
- `disable fork` kills *all* child threads of the current process, including ones you did not intend
  (e.g., a monitor started earlier with `join_none`). Wrap the fork you want to control in an outer
  `fork ... join` so `disable fork` has a limited scope:

  ```systemverilog
  fork begin
    fork
      do_work();
      #TIMEOUT $error("timeout");
    join_any
    disable fork;                 // kills only do_work/timeout, not siblings outside this block
  end join
  ```
  This is the standard **timeout** idiom.
- `disable <label>` kills a named block/task from anywhere. Coarser and less composable than
  `disable fork`; fine for `disable generate_clock`.
- Threads started in a class method with `join_none` keep running after the method returns; the
  object stays alive as long as the thread references it.

## Events

```systemverilog
event driver_done;
-> driver_done;              // trigger (instantaneous)
@(driver_done);              // wait for the NEXT trigger; misses one that already happened
wait (driver_done.triggered); // true for the rest of the time step in which it was triggered: no miss if same step
->> driver_done;             // nonblocking trigger (scheduled in NBA region)
```

Events are the lightest synchronization: "you may proceed." The tutorial's generator waits on
`driver_done_event` after each `put`, so the generator never runs ahead. The classic bug: the
trigger happens before the waiter reaches `@(...)`, and the waiter hangs. Use
`wait(e.triggered)` when the trigger may come in the same time step, or use a mailbox (which
remembers).

Events can be passed to constructors and compared/assigned (`event a = b;` makes them the same
event), which is how two classes share one.

## Semaphores

```systemverilog
semaphore bus_lock = new(1);     // 1 key: a mutex
bus_lock.get();                  // block until a key is available, take it
... drive ...
bus_lock.put();                  // return it
if (bus_lock.try_get()) ...      // non-blocking attempt
```

Use when several threads share a resource that admits one user at a time: two sequences driving
one bus, a shared memory model being updated. `new(N)` allows N concurrent users. UVM's sequencer
arbitration is a semaphore-like mechanism with priorities.

## Mailboxes

```systemverilog
mailbox #(fifo_txn) gen2drv = new();     // parameterized (typed): compile-time checked; ALWAYS do this
mailbox untyped = new();                 // legacy: holds anything, runtime type errors
mailbox #(fifo_txn) bounded = new(4);    // capacity 4: put() blocks when full

gen2drv.put(t);                          // blocking put (blocks only if bounded and full)
gen2drv.get(t);                          // blocking get: waits until something is there
gen2drv.peek(t);                         // look without removing
if (gen2drv.try_get(t)) ...              // non-blocking
n = gen2drv.num();
```

A mailbox is a thread-safe FIFO of handles. It is the standard producer/consumer channel: generator
to driver, monitor to scoreboard. Because it stores the item, there is no "missed trigger" problem.
Because it stores *handles*, the producer must not modify the object after `put` (allocate a new
one per transaction).

Bounded mailboxes provide flow control: a generator that must not run more than N transactions
ahead of the driver. Unbounded ones with a "done" event (tutorial) provide lock-step.

## Synchronizing the layered testbench

Two common topologies:

**Lock-step (tutorial's generator/driver):** generator `put`s one item, waits for `driver_done`;
driver `get`s, drives, triggers `driver_done`. Simple, deterministic, and the generator can react
to results. Throughput limited to one item in flight.

**Pipelined:** generator `put`s freely into a bounded mailbox; driver `get`s at its own pace.
Higher throughput; the generator cannot know when its item was driven unless the driver sends a
response back (a second mailbox, or the transaction object itself carries a response field that
the driver fills in and the generator reads after a `done` event). This is precisely UVM's
`get_next_item`/`item_done` + `rsp` mechanism.

The scoreboard waits on *two* sources (expected from the input monitor, actual from the output
monitor). Two mailboxes and a `get` on each in order works when transactions are in order. For
out-of-order, `get` from either (a `fork ... join_any` over the two `get`s, or one mailbox carrying
a tagged union) and match by ID.

## Ending: who decides the test is over?

- Simple: the generator finishes; `join_any` returns; wait a drain time; `disable fork`; report.
- Better: the scoreboard counts expected transactions and signals done when the last one matched
  (tutorial's `scoreboard2.run(num_tests)`), because the *last* transaction has not been checked
  when the generator finishes.
- Best (UVM): objections. Every component that has work in flight raises one; the phase ends when
  all are dropped. Section 7.5.

A drain-time guard and a global timeout (`fork ... #MAX_TIME $fatal ... join_any`) belong in every
testbench so a hang fails instead of running forever.

## Process control

`process::self()` gives a handle to the current thread; `p.kill()`, `p.await()`, `p.status()`,
`p.srandom(seed)`. Used for fine-grained control (kill one specific child) and per-thread seeding.
Rare in day-to-day work; know it exists.

## Interview angle

- "`join` vs `join_any` vs `join_none`?" Then: "how do you kill the remaining threads?" and "what is
  the danger of `disable fork`?" (kills siblings; wrap in an outer fork).
- "Event vs mailbox?" Signal vs data; missed-trigger problem.
- "Write a timeout around a task." The nested-fork idiom.
- "How does the scoreboard know the test is done?" Counting, or objections.
- "Fork inside a for loop: what goes wrong?" Loop variable capture; `automatic` copy.

## Mentor's notes

- Name every forked branch with `begin : name ... end`. When the simulation hangs, the process
  window shows you the names, and you find the stuck `get()` in seconds.
- Every blocking `get()` and every `@(event)` is a place the testbench can hang. When you write
  one, ask "what guarantees this ever returns?" and add the timeout if the answer is "the DUT."
