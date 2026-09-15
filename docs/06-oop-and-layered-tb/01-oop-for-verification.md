# 6.1 OOP for Verification

Object-oriented programming in a testbench is not about elegance. It solves three concrete
problems: (1) a transaction is *data plus the operations on it* (randomize, print, compare, pack),
so a class is the natural container; (2) testbench components (driver, monitor, scoreboard) must be
*instantiated per interface* with per-instance state, which classes give you and modules give you
only statically; (3) tests must *change behavior without editing the environment*, which
inheritance and polymorphism give you.

## Classes and handles

```systemverilog
class fifo_txn;
  rand bit [7:0] data;
  rand bit       wr, rd;
  time           t_start;                 // non-random bookkeeping

  function new(bit [7:0] d = 0);          // constructor with a default argument
    data = d;
  endfunction

  function string convert2string();
    return $sformatf("wr=%0b rd=%0b data=%02h", wr, rd, data);
  endfunction
endclass

fifo_txn t;          // a HANDLE (pointer). Value: null. No object exists yet.
t = new();           // construct an object; t now refers to it
t = new(8'hA5);      // construct another; the first object is now unreferenced and garbage collected
fifo_txn u = t;      // u and t refer to the SAME object
u.data = 1;          // t.data is also 1
```

The handle/object distinction is the source of most beginner bugs:

- Calling a method on a `null` handle is a fatal runtime error. Construct before use.
- Assigning handles aliases objects. A monitor that reuses one object and hands it to a scoreboard
  every cycle corrupts the scoreboard's stored "expected" values retroactively. Allocate a new
  object per transaction.
- Comparing handles (`t == u`) compares identity, not contents. Write a `compare()` method.
- SystemVerilog garbage-collects unreferenced objects. There is no `delete`; set handles to `null`
  if you want to release early.

Where to define classes: in a package (`.svh` files included into the package). Classes can also be
defined in a module (Stitt's no-hierarchy example does this) for one-off testbenches.

## Copying

```systemverilog
fifo_txn a = new(), b;
b = new a;                    // SHALLOW copy: all fields copied; nested handles still point to the same objects
b = a.copy();                 // user-written: deep copy if you copy nested objects too

function fifo_txn copy();
  copy = new();               // 'copy' is the implicit return variable in SV functions
  copy.data = data; copy.wr = wr; copy.rd = rd; copy.t_start = t_start;
endfunction
```

A transaction that contains a dynamic array or a handle to another object needs a deep copy or
the copies share storage. UVM's `clone()`/`copy()` with field macros handle this; in plain SV you
write it.

## Inheritance

```systemverilog
class base_driver;
  virtual fifo_if vif;
  mailbox #(fifo_txn) mbx;
  function new(virtual fifo_if v, mailbox #(fifo_txn) m); vif = v; mbx = m; endfunction
  virtual task run();
    forever begin
      fifo_txn t;
      mbx.get(t);
      drive(t);
    end
  endtask
  virtual task drive(fifo_txn t);        // default behavior
    vif.wr_data <= t.data; vif.wr_en <= t.wr; vif.rd_en <= t.rd;
    @(posedge vif.clk);
  endtask
endclass

class slow_driver extends base_driver;
  function new(virtual fifo_if v, mailbox #(fifo_txn) m); super.new(v, m); endfunction
  virtual task drive(fifo_txn t);        // override: add random gaps
    repeat ($urandom_range(0, 3)) @(posedge vif.clk);
    super.drive(t);                      // reuse the base behavior
  endtask
endclass
```

`extends` gives the derived class every member of the base. `super.` reaches the base's version.
Constructors are not inherited; the derived `new` must call `super.new(...)` *first* (this is why
Stitt's `test` classes construct their generator/driver *after* `super.new`, a known awkwardness).

## Polymorphism and `virtual`

The environment holds a `base_driver` handle. At run time it may point to a `slow_driver`. Which
`drive()` runs?

- If `drive` is declared `virtual` in the base: the *object's* type decides. `slow_driver::drive`
  runs. This is polymorphism and it is the mechanism behind "the test swaps the driver without
  editing the environment."
- If not `virtual`: the *handle's* type decides. `base_driver::drive` runs even though the object
  is a `slow_driver`. Almost never what you want.

**Rule: every method you might override is `virtual`.** The cost is negligible. UVM declares
practically everything virtual.

## Abstract classes and pure virtual methods

```systemverilog
virtual class base_generator;           // cannot be instantiated
  mailbox #(fifo_txn) mbx;
  pure virtual task run();              // must be implemented by every concrete subclass
endclass
```

An abstract class is a contract: "every generator has a `run()`." The environment codes against the
contract; tests plug in concrete generators (random, consecutive, error-injecting). The tutorial's
`bit_diff_oop` has `base_generator`, `random_generator`, `consecutive_generator` in exactly this
shape.

## Casting handles

```systemverilog
base_driver bd = slow_driver_obj;      // upcast: always legal, implicit
slow_driver sd;
sd = bd;                               // compile error: downcast needs a check
if (!$cast(sd, bd)) $error("bd is not a slow_driver");   // dynamic cast: succeeds only if the object really is one
```

You downcast when a generic path (an analysis port carrying `base_txn`) delivers an object that a
consumer knows is a specific subtype. Prefer designing so downcasts are rare; they indicate the
abstraction leaked.

## Parameterized classes

```systemverilog
class fifo_model #(int WIDTH = 8, int DEPTH = 16);
  bit [WIDTH-1:0] q[$];
  function bit full(); return q.size() == DEPTH; endfunction
endclass
fifo_model #(.WIDTH(32), .DEPTH(64)) m = new();
```

Every distinct parameter set is a distinct *type*. `fifo_model#(8,16)` and `fifo_model#(8,32)`
cannot be assigned to each other. This matters enormously in UVM with parameterized interfaces
(chapter 7): the parameter must be threaded through every class that mentions the type, or fixed in
a package. Use `typedef fifo_model #(8,16) fm8_t;` to keep it readable.

## Static members

```systemverilog
class fifo_txn;
  static int count = 0;                // ONE copy shared by all objects
  int id;
  function new(); id = count++; endfunction
  static function int get_count(); return count; endfunction   // static methods cannot touch instance members
endclass
```

Use for: transaction IDs, global counters, a singleton configuration/registry (Spear's chapter 8
builds a config DB and a test registry this way, which is a preview of UVM's `config_db` and factory).

## `local` and `protected`

`local` members are visible only inside the class; `protected` also in subclasses. Testbench code
rarely bothers, but marking the internals of a reusable agent `protected` prevents tests from
reaching into them, which keeps the agent's interface stable.

## Composition vs. inheritance

Inheritance says "is a": `slow_driver` *is a* `base_driver`. Composition says "has a": an
`environment` *has a* driver, a monitor, a scoreboard. Use inheritance to *vary behavior*; use
composition to *assemble*. Deep inheritance trees are brittle (Spear's "problems with inheritance");
UVM's answer is the factory: compose with base types, let the test override which concrete type gets
constructed.

## Interview angle

- "What is a virtual method and why does UVM use them everywhere?" Object-type dispatch; enables
  tests to substitute derived components through base handles.
- "Difference between a shallow and deep copy?" Nested handles shared vs duplicated.
- "What is `$cast` for?" Checked downcast.
- "What is an abstract class?" Contract with pure virtual methods; cannot instantiate.
- "Why are two instances of a parameterized class with different parameters incompatible?"
  Distinct types.
- "What happens when you call a method on a null handle?"

## Mentor's notes

- Fully initialize objects in the constructor (Stitt's `generator3`/`driver4` style): the compiler
  then catches a missing connection. UVM deliberately does *not* do this (build/connect phases) to
  gain flexibility; understand the tradeoff rather than treating either as gospel.
- Give every transaction class a `convert2string()` and a `compare()`. You will call them a
  thousand times.
