# 1.1 Data Types

## The first-principles question: what is a value?

In software, a bit is 0 or 1. In hardware simulation, a wire can also be **unknown** (`X`: uninitialized,
or two drivers fighting) or **high-impedance** (`Z`: nothing is driving it). SystemVerilog therefore
has two families of types:

| Family | Values | Types | Default value | Use for |
|---|---|---|---|---|
| **4-state** | 0, 1, X, Z | `logic`, `reg`, `wire`, `integer`, `time` | `X` | Anything connected to the DUT; anything where "uninitialized" is a bug you want to see |
| **2-state** | 0, 1 | `bit`, `byte`, `shortint`, `int`, `longint` | `0` | Testbench bookkeeping: counters, loop indices, transaction fields, class members |

Why does this matter? Because **X is information**. A DUT output that is X after reset tells you a
flop was not reset. If you sample it into a `bit`, the X silently becomes 0 and the bug disappears.
Conversely, comparing two 4-state values with `==` when one is X yields X, which `if` treats as false,
so `if (a != b) $error(...)` never fires when `a` is X. (See [1.6 Gotchas](06-gotchas.md); this one
bites everyone once.)

**Rule of thumb:** DUT-facing signals and anything you sample from the DUT are `logic`. Class
properties for stimulus (data you *generate*) are usually `bit`, because the solver works on 2-state
values and 2-state is faster and smaller. When a transaction also carries *observed* DUT data, use
`logic` for those fields so X is preserved through the scoreboard.

```systemverilog
logic [7:0]  dut_out;     // 4-state, starts as 8'hxx: good, you will notice if it is never driven
bit   [7:0]  expected;    // 2-state, starts as 0
int          count;       // 2-state 32-bit signed; the workhorse loop/counter type
integer      old_style;   // 4-state 32-bit signed; avoid in new code, use int
```

### `logic` vs `wire` vs `reg`

`logic` is a *data type*; `wire` is a *net type*. A `logic` variable can be assigned by exactly one
procedural block *or* one continuous assignment. A `wire` can have multiple drivers (resolved to X on
conflict) and is required for tri-state buses and for `inout` ports. In testbenches you almost only
need `logic`. `reg` is a Verilog-2001 synonym for `logic`; do not use it in new code.

## Packed vs. unpacked arrays

This distinction is about *memory layout* and *what operations are allowed*.

```systemverilog
logic [7:0]        byte_v;          // packed: 8 bits, one contiguous vector
logic [3:0][7:0]   word_packed;     // packed 2-D: 32 contiguous bits, word_packed[1] is bits [15:8]
logic [7:0]        mem [0:255];     // unpacked: 256 separate 8-bit elements
logic [7:0]        mem2 [256];      // same, C-style size (0..255)
bit   [31:0]       regs [16];       // 16 x 32-bit
```

- **Packed** dimensions go *before* the name. The whole thing is one vector: you can slice it, do
  arithmetic on it, compare it as a number, assign it from an integer.
- **Unpacked** dimensions go *after* the name. It is a collection of elements. You cannot add two
  unpacked arrays; you can compare them for equality, copy them whole, iterate with `foreach`.
- Packed arrays can only hold single-bit types (`bit`, `logic`) and other packed types. Unpacked
  arrays can hold anything (ints, structs, classes, other arrays).

Why choose one? Packed when the data is *a number or a bus* (a 64-bit data word made of 8 bytes).
Unpacked when the data is *a collection* (a memory, a list of transactions). Synthesis tools infer
RAMs from unpacked arrays.

```systemverilog
// Iterating: foreach walks every index of every unpacked dimension
logic [7:0] mem [256];
foreach (mem[i]) mem[i] = i;                // initialize
foreach (mem[i]) if (mem[i] === 8'hxx) $error("mem[%0d] uninitialized", i);

// Array literals
int primes [5] = '{2, 3, 5, 7, 11};
logic [7:0] zeros [4] = '{default: '0};     // every element 0
```

### Worked example: a "3-D array" that compiles and still lies to you

Here is a snippet of the kind a beginner writes to try out multi-dimensional arrays. It has four
problems; only one of them is caught by the compiler.

```systemverilog
module scratch;
  initial begin
    logic [0:7][0:7][0:7] 3d_array;         // (1) illegal name  (2) this is PACKED: one 512-bit vector
    3d_array <= {8'hf, 8'hf, 8'hf};         // (3) NBA in an initial  (4) 24 bits into 512: zero-extended
    $display("array data = %p", 3d_array);  // prints all X: the NBA has not happened yet
  end
endmodule
```

1. **Identifiers cannot start with a digit.** `3d_array` is a syntax error. Call it `cube` or
   `arr3d`. This is the only line the compiler rejects; fix it and the rest compiles cleanly.
2. **Three packed dimensions make one vector, not a cube of elements.** `logic [0:7][0:7][0:7]` is
   a single 512-bit value that you can slice as `[plane][row][bit]`. If you wanted 64 separate bytes,
   the dimensions belong *after* the name: `logic [7:0] cube [8][8]`. Also, `[0:7]` puts index 0 at
   the MSB; the hardware convention is `[7:0]`, and mixing the two is a classic source of
   off-by-reversal bugs.
3. **Nonblocking assignment then `$display` in the same step prints the *old* value.** `<=`
   schedules the update for the NBA region; `$display` runs now, in the Active region, and sees the
   uninitialized X. Testbench-local variables take `=`. (1.2 explains the regions; this exact race
   is G9's cousin.)
4. **`{8'hf, 8'hf, 8'hf}` is a 24-bit concatenation.** Assigned to a 512-bit vector it is
   zero-extended: bits `[23:0]` get `0F0F0F`, the other 488 bits are 0. No warning. To fill every
   element you replicate (`{64{8'hF}}`) or, for an unpacked array, use an assignment pattern
   (`'{default: 8'hF}`). Note `'{` versus `{`: the apostrophe means "assignment pattern for an
   aggregate", the bare brace means "bit concatenation", and they are not interchangeable.

The corrected program shows both layouts side by side
([`code/01-fundamentals/multidim_demo.sv`](../../code/01-fundamentals/multidim_demo.sv)):

```systemverilog
module multidim_demo;
  initial begin
    logic [7:0][7:0][7:0] cube_p;   // 3-D PACKED: one 512-bit vector, [plane][row][bit]
    logic [7:0] cube_u [8][8];      // 3-D UNPACKED: 8x8 separate 8-bit elements

    cube_p = '0;
    cube_p[0][0] = 8'hF;            // element [0][0] is bits [7:0] of the vector
    cube_p[7][7] = 8'hA5;           // bits [511:504]
    $display("packed: %h", cube_p);
    $display("packed slice [7] = %h, [7][7] = %h", cube_p[7], cube_p[7][7]);

    cube_u = '{default: 8'h0};      // assignment pattern
    cube_u[0][0] = 8'hF;
    cube_u[1] = '{8{8'hFF}};        // whole row via replication inside a pattern
    $display("unpacked: %p", cube_u);

    foreach (cube_u[i, j])          // two indexes, one loop: note the comma form for unpacked dims
      if (cube_u[i][j] != 0) $display("cube_u[%0d][%0d] = %h", i, j, cube_u[i][j]);
    $finish;
  end
endmodule
```

How to choose between them: packed when you will treat the whole thing as a number or a bus (send it
through a port, compare it in one `==`, slice arbitrary bit ranges). Unpacked when it is a
collection you index element by element (a memory, a lookup table, a frame buffer). Mixed is common
and correct: `logic [7:0] mem [1024]` is a memory of bytes, and `logic [3:0][7:0] word [256]` is a
memory of 32-bit words that you can also address byte-wise.

## Dynamic data structures: the verification engineer's toolbox

These three types are why SystemVerilog testbenches are so much shorter than Verilog ones. Each is a
reference model waiting to happen.

### Dynamic arrays: size chosen at runtime

```systemverilog
int   data[];                 // declared, size 0, no storage yet
data = new[16];               // allocate 16 elements (all 0)
data = new[32](data);         // grow to 32, keeping the first 16
$display("%0d", data.size());
data.delete();                // back to size 0
```

Use when the size is known before you fill it (a packet payload whose length is a randomized field).

The most common place you will meet a dynamic array is as a class member, where the randomizer picks
its size for you. A `rand` dynamic array is resized by `randomize()` to satisfy whatever constraint
you put on `.size()`; you never call `new[]` yourself:

```systemverilog
class packet;
  rand byte payload[];                                    // randomized payload as a dynamic array
  constraint c_len { payload.size() inside {[1:64]}; }    // constrain the length, not the contents

  function void display();
    $display("packet size = %0d, data = %p", payload.size(), payload);
  endfunction
endclass

module scratch;
  initial begin
    packet pkt_q[$];   // queue of packet handles
    packet p;

    repeat (5) begin
      p = new();
      assert(p.randomize());  // gets a fresh random size each time
      pkt_q.push_back(p);
    end

    foreach (pkt_q[i]) pkt_q[i].display();
    $finish;
  end
endmodule
```

Three things to notice:

- **The constraint is on `payload.size()`, not on the elements.** Without a size constraint the
  solver is free to pick size 0 (and usually does). The element values are also randomized because
  the array itself is `rand`; if you only wanted the length randomized, you would constrain the
  contents separately or make the elements non-random.
- **Each `randomize()` call reallocates.** Every packet above gets its own length; printing them
  shows five different sizes. If you had reused the same handle instead of calling `new()` inside
  the loop, the queue would hold five copies of the *same* object, all showing the last
  randomization. Handles are references, not values (see the classes chapter).
- **`%p` prints the whole aggregate.** It is the quickest way to dump an array, struct, or object
  during debug without writing a loop.

This pattern (a dynamic array inside a class, a queue of handles outside it) is the skeleton of every
stimulus generator: the class describes one transaction, the queue is the stream of them.
Every construct in this example (`rand`, `constraint`, `inside`, `function void`, `new()`,
`randomize()`, `repeat`, `foreach`, `%p`, `$finish`, ...) is indexed in
[Appendix G](../appendix/G-construct-index.md) with a pointer to where it is explained.

### Queues: the most useful type in the language

A queue is a variable-size ordered list with O(1) push/pop at both ends. Declared with `$` as the
size. It is a FIFO, a stack, a scoreboard's expected list, and a sliding-window history, all in one.

```systemverilog
logic [7:0] q[$];             // unbounded queue of bytes
logic [7:0] q8[$:7];          // bounded: at most 8 elements

q.push_back(8'hA5);           // enqueue at tail
q.push_front(8'h00);          // insert at head
x = q.pop_front();            // dequeue from head (FIFO behavior)
y = q.pop_back();             // pop from tail (stack behavior)
z = q[0];                     // peek head;  q[$] is the tail
n = q.size();
q.insert(2, 8'hFF);           // insert at index 2
q.delete(1);                  // delete index 1
q.delete();                   // clear
q = {q[1:$]};                 // slice: drop the head (same as pop_front)
q = {q, 8'h33};               // concatenation: same as push_back
```

The canonical use: modeling a DUT FIFO or any in-order pipe. Push expected values when the DUT
accepts input; pop and compare when the DUT produces output. The whole reference model is three lines.

```systemverilog
logic [7:0] expected_q[$];
always @(posedge clk) begin
  if (wr_en && !full)  expected_q.push_back(wr_data);
  if (rd_valid) begin
    if (expected_q.size() == 0) $error("DUT produced data with nothing expected");
    else if (rd_data !== expected_q.pop_front()) $error("data mismatch");
  end
end
```

### Associative arrays: sparse maps

Indexed by any type (int, string, a packed struct). Storage is allocated only for indexes you write.
This is your sparse memory model, your ID-to-transaction lookup, your histogram.

```systemverilog
logic [31:0] mem [logic [31:0]];    // memory indexed by 32-bit address; only touched addresses exist
int          count_by_opcode [string];
bit          seen [int];

mem[32'h1000_0000] = 32'hDEAD_BEEF;
if (mem.exists(addr)) data = mem[addr]; else data = 'x;  // reading a missing key returns default
count_by_opcode["ADD"]++;                                // missing key: created with default 0, then ++
mem.delete(addr);
$display("%0d entries", mem.num());

// Iterate in key order
int key;
if (mem.first(key)) do $display("%h: %h", key, mem[key]); while (mem.next(key));
foreach (mem[k]) $display("%h", mem[k]);                 // simpler
```

Out-of-order scoreboards use an associative array keyed by transaction ID: store the expected
response when the request is issued; look it up and delete it when the response arrives.

### Array methods (all three types, plus fixed arrays)

```systemverilog
int a[] = '{4, 1, 3, 1};
int idx[$], vals[$];

a.sort();                    // in place: 1 1 3 4
a.rsort();                   // descending
a.reverse();  a.shuffle();
vals = a.find with (item > 2);            // {4, 3} (order of a)
idx  = a.find_index with (item == 1);     // {1, 3}
vals = a.find_first with (item > 2);      // {4}
vals = a.unique();                        // {4,1,3}
vals = a.min();  vals = a.max();          // queues of one element
s = a.sum();  p = a.product();            // reductions
s = a.sum with (item * 2);                // reduce over an expression
n = a.sum with (int'(item > 2));          // count matches: cast the boolean to int
```

`item` is the implicit iterator name; `item.index` gives its index. These replace most for-loops in
scoreboards and coverage post-processing.

### Choosing

| Need | Type |
|---|---|
| Known fixed size, hardware-like | Fixed unpacked array |
| Size decided at runtime, then stable | Dynamic array |
| Ordered, grows/shrinks, FIFO/LIFO access | Queue |
| Sparse, keyed lookup | Associative array |

## Structs, unions, and typedef

A `struct` groups fields. **Packed** structs are bit-addressable and can be assigned to/from vectors,
which makes them ideal for describing bus fields (a header word, a register with bitfields).
**Unpacked** structs are just records.

```systemverilog
typedef struct packed {         // total width 32; fields laid out MSB first
  logic [3:0]  opcode;
  logic [11:0] addr;
  logic [15:0] imm;
} instr_t;

instr_t ins;
ins = 32'h1_234_5678;           // whole-vector assignment
$display("%h", ins.opcode);     // 4'h1
ins.addr = '1;

typedef struct {                // unpacked: a record for testbench use
  int       id;
  string    name;
  bit [7:0] payload[];          // may contain dynamic types
} pkt_t;
pkt_t p = '{id: 1, name: "hello", payload: '{1,2,3}};
```

A `union` overlays several views on the same storage. Packed unions are occasionally useful for
"interpret this word as either format A or format B." Tagged unions exist but are rare in practice.

### `typedef`: give a type a name

`typedef` creates a name for an existing type. It does not create a *new* type: `addr_t` below is
still `logic [31:0]` and is assignment-compatible with any other 32-bit vector. What you gain is a
single place where the width is decided.

```systemverilog
typedef logic [ADDR_W-1:0] addr_t;     // "addr_t" now means "a logic vector ADDR_W bits wide"
addr_t a, b;                            // same as: logic [ADDR_W-1:0] a, b;
```

Read it as `typedef <existing type> <new name>;`. The `_t` suffix is convention, not syntax, but
use it: it tells the reader "this is a type, not a signal."

The reason `typedef` matters is not one declaration, it is *hundreds*. A bus address appears in the
DUT ports, the interface, the transaction class, the scoreboard's associative array key, the
covergroup, and the assertions. Written as `logic [31:0]` in each place, changing the width means a
grep-and-hope edit across the codebase and a bug wherever you missed one. Written as `addr_t`, the
width lives in one line, and the natural home for that line is a package:

```systemverilog
package my_pkg;
  parameter int ADDR_W = 32;
  parameter int DATA_W = 64;

  typedef logic [ADDR_W-1:0] addr_t;
  typedef logic [DATA_W-1:0] data_t;
endpackage

module mem_ctrl
  import my_pkg::*;          // import BEFORE the port list so the port types are visible
(
  input  addr_t addr,
  input  data_t wdata,
  output data_t rdata
);
  // ...
endmodule
```

Things to notice:

- **The `import` sits between the module name and the port list.** An `import` inside the module
  body would come *after* the ports, and `addr_t` would be undefined when the compiler reads
  `input addr_t addr`. This header-import position exists precisely for package types in ports.
  (For everything else, 1.5's advice stands: import inside the module, not at compilation-unit
  scope.)
- **The package is the single source of truth.** The testbench imports the same package, so the
  driver's `addr_t` and the DUT's `addr_t` cannot disagree. Change `ADDR_W` to 40 and the DUT, the
  interface, the transaction class, and the checkers all follow.
- **Package `parameter`s are constants, not overridable.** `mem_ctrl` above cannot be instantiated
  with a different address width; that is the trade-off for global agreement. If a block needs
  per-instance widths, keep a module `parameter` and derive a local typedef:
  `typedef logic [ADDR_W-1:0] addr_t;` inside the module, where `ADDR_W` is the module parameter.
  Chapter 7 discusses when each is appropriate.
- **`typedef` reads better than the raw type in every direction.** `input addr_t addr` says what
  the port *is*; `input logic [31:0] addr` says how wide it is and leaves you to guess the rest.
  Ports, function arguments, and class properties all benefit.

The same mechanism names structs, enums, and even other typedefs: `typedef instr_t insn_word_t;`.
Anything you write twice deserves a name.

## Enumerated types

```systemverilog
typedef enum logic [1:0] {IDLE = 2'b00, BUSY = 2'b01, DONE = 2'b10} state_t;
state_t state;

state = IDLE;
state = state.next();                 // BUSY (wraps at the end)
$display("%s", state.name());          // "BUSY"   <- priceless in logs and waveforms
state = state_t'(2'b11);              // explicit cast; 3 is not a member, this is how you get a bad value in
// state = 2;                         // compile error: no implicit int -> enum. Good.

// Iterate all members
state_t s = s.first();
do begin $display("%s = %0d", s.name(), s); s = s.next(); end while (s != s.first());
```

Enums are strongly typed on assignment (you must cast from integers) but silently convert *to*
integers. Give the base type explicitly (`logic [1:0]`) when it must match an RTL signal; leave the
default (`int`) for testbench-only enums. Coverage of an enum coverpoint automatically creates one
bin per member, which is exactly the FSM state coverage you want.

## Strings

`string` is a dynamic, mutable text type with methods. Verilog's "string" was just a packed vector of
ASCII; do not confuse them.

```systemverilog
string s = "abc";
s = {s, "def"};                       // concatenation
s = $sformatf("%s_%0d", s, 7);        // formatted build: the most used string function in testbenches
$display("%0d %s %s", s.len(), s.toupper(), s.substr(0, 2));
if (s.compare("abcdef") == 0) ...     // or just s == "abcdef"
int v = s.atoi();  s = $sformatf("%h", 255); v = s.atohex();
byte c = s[0];                        // characters are indexable
```

`$sformatf` is what you use to build messages for `$display`, `$error`, and `uvm_info`. `%0d` and
`%0h` suppress leading padding; `%t` prints time (set the format once with `$timeformat`); `%p`
pretty-prints any aggregate (arrays, structs), invaluable for debug; `%s` with an enum prints its name
via `.name()`.

## Casting and conversion

There are three mechanisms, and confusing them is a classic bug source.

```systemverilog
// 1. Implicit conversion: silent truncation/extension by assignment
logic [3:0] a = 8'hAB;        // a = 4'hB, upper bits dropped, no warning required by the LRM
int i = 4'hF;                 // zero-extended to 15 (unsigned source)

// 2. Static cast: type'(expr) or size'(expr) or signed'/unsigned'(expr). Compile-time; always succeeds.
logic [7:0] w = 8'(some_int);            // explicit truncation, documents intent, silences lint
int s = signed'(some_logic_vec);         // reinterpret sign
state_t st = state_t'(2);                // int -> enum
real r = real'(i) / 3.0;

// 3. Dynamic cast: $cast(dest, src). Run-time; returns 0 on failure. Used for class downcasting
//    and for int -> enum with checking.
if (!$cast(st, 3)) $error("3 is not a valid state_t");   // fails at run time instead of corrupting
base_txn b; my_txn m;
if (!$cast(m, b)) `uvm_fatal("CAST", "b is not a my_txn")  // class downcast, see chapter 6
```

**Width rule you must internalize:** in an expression, operands are extended to the width of the
*largest* operand *or the destination*, whichever is bigger, *before* the operation. So
`logic [7:0] a, b; logic [8:0] sum = a + b;` correctly captures the carry, but
`logic [7:0] sum = a + b;` silently drops it, and `(a + b) >> 1` computes in 8 bits and loses the carry
even though you "only" wanted the average. Force width with a cast or a dummy 9-bit operand
(`{1'b0, a} + b`). Chapter 1.6 has the full set of width and sign rules.

## Streaming operators

`{>>{...}}` and `{<<{...}}` pack/unpack between aggregates and vectors. Useful for turning a byte
queue into a word and back, i.e. protocol packing.

```systemverilog
byte payload[] = '{8'h11, 8'h22, 8'h33, 8'h44};
logic [31:0] word;
word = {>>{payload}};              // 32'h11223344: first element goes to MSB
word = {<<byte{payload}};          // 32'h44332211: reverse byte order
payload = {>>{word}};              // unpack back into bytes (array is resized)
logic [7:0] rev = {<<{8'b1100_0001}}; // bit reversal: 8'b1000_0011
```

## Constants and parameters

```systemverilog
parameter  int WIDTH = 8;        // module parameter: overridable at instantiation
localparam int DEPTH = 2**4;     // computed constant, not overridable
const  int    LIMIT = 100;       // run-time constant (classes, procedural scope)
`define MAX 42                   // text macro: global, no scope, no type. Prefer parameters/localparams.
```

## Interview angle

- "Difference between `logic` and `bit`?" They want: 4-state vs 2-state, default X vs 0, why you
  would pick each (observability of X vs solver speed and memory), and the `==` on X gotcha.
- "Packed vs unpacked?" Contiguous vector vs collection; what operations each supports; which
  synthesizes to RAM.
- "How would you model a FIFO / memory / out-of-order response tracker?" Queue / associative array /
  associative array keyed by ID. Say the O(1) properties.
- "What does `$cast` do that a static cast does not?" Runtime type check with failure indication;
  needed for downcasting class handles and validated enum conversion.

## Mentor's notes

- Write `logic` on every DUT-facing signal even in the testbench top. You will catch un-reset flops
  during the first week of bring-up, when they are cheap to fix.
- Use `%p` and `.name()` liberally in messages. Debug time is dominated by reading logs; make them
  human.
- The first time your scoreboard uses a queue instead of a hand-rolled circular buffer with
  read/write pointers, you will wonder why anyone still writes Verilog testbenches. That feeling is
  correct.
