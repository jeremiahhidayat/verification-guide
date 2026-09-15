# 5.1 Randomization and Constraints

## What the solver is

`obj.randomize()` asks a constraint solver to find *one* assignment to all `rand` variables in `obj`
such that every active constraint is satisfied, chosen (by default) uniformly among all solutions.
If no assignment exists, it returns 0 and leaves the variables unchanged. That is the entire
mechanism; everything else is syntax for describing the solution space.

Three consequences you should internalize:

1. **Constraints are declarative, not procedural.** `a < b; b < c;` is the same as `b < c; a < b;`.
   Order in the block is irrelevant (except for `solve...before`, which affects *distribution*, not
   legality).
2. **Constraints are bidirectional.** `a == b + 1` constrains `a` given `b` *and* `b` given `a`.
   The solver does not "compute" one from the other; it finds values satisfying the relation.
3. **The distribution is over solutions, not over variables.** If `a` is 1 bit and `b` is 8 bits
   with `a -> b == 0`, then there are 1 (for a=1) + 256 (for a=0) solutions; uniform over solutions
   makes `a` true about 0.4% of the time. This surprises everyone once. `solve a before b` fixes it.

## Random variables

```systemverilog
class packet;
  rand  bit [7:0]  len;        // random, may repeat
  randc bit [3:0]  tag;        // random-cyclic: every value once before any repeats (per object)
  rand  bit        error;
  rand  bit [7:0]  payload[];  // dynamic array: size and elements can be constrained
        bit [15:0] crc;        // not random: computed in post_randomize
  rand  enum {SHORT, LONG} kind;
endclass
```

`randc` is implemented with a permutation table; keep it small (a few bits) or the tool falls back
or gets slow. It is per-object: two objects each cycle independently.

`randomize()` also exists on module-scope variables and as `std::randomize(a, b) with {...}` for
locals; handy in a quick testbench, but classes are the norm.

## Constraint blocks

```systemverilog
class packet;
  rand bit [7:0] len;
  rand bit [3:0] kind;
  rand bit       error;
  rand bit [7:0] payload[];

  constraint c_len   { len inside {[4:64]}; }
  constraint c_size  { payload.size() == len; }
  constraint c_kind  { kind inside {0, 1, 2, [8:11]}; }
  constraint c_dist  { len dist {4 := 5, [5:63] :/ 90, 64 := 5}; }   // := per value, :/ split across the range
  constraint c_impl  { error -> len < 16; }                          // implication: if error, then short
  constraint c_iff   { (kind == 0) <-> (len == 4); }                 // equivalence (both directions)
  constraint c_if    { if (kind inside {[8:11]}) len > 32; else len <= 32; }
  constraint c_order { solve kind before len; }                      // distribution hint only
  constraint c_soft  { soft error == 0; }                            // default that a test may override
endclass
```

Operators allowed: the usual arithmetic/relational/logical, `inside`, `dist`, `->`, `<->`,
`if/else`, `foreach`, function calls (see below), array reduction methods on arrays of rands.
Not allowed: side effects, most non-integral types (real is allowed in recent LRMs, tool-dependent).

### `dist`

`:=` gives each listed value or *each value in the range* that weight. `:/` divides the weight
across the range. `len dist {[5:63] :/ 90}` gives the whole range 90 units, so each value gets
90/59. `len dist {[5:63] := 90}` gives *each* of 59 values 90 units. The tutorial's
`in0 dist {0 :/ 10, 2**W-1 :/ 10, [1:2**W-2] :/ 80}` is the standard "extremes plus body" shape
that gets you to coverage of `zero` and `max` bins without directed tests.

`dist` only applies when the variable is otherwise unconstrained by the values it picks; a `dist`
that conflicts with another constraint is not an error, the other constraint just narrows it.

### Implication and equivalence

`a -> b` reads "if a then b" and is exactly `!a || b`. Because constraints are bidirectional, the
solver may choose `a = 0` to satisfy it when `b` is hard to make true. That is the source of the
"my error flag is almost never set" surprise. Fix the *distribution* with `solve a before b` or with
`dist` on `a`.

### `solve ... before`

Tells the solver to pick values for the first variables first, then solve the rest given those. It
does not change which solutions are legal; it changes the probability of each. Use it whenever a
small variable implies constraints on a big one. Cannot be applied to `randc` variables (they are
always solved first) or create a cycle.

### `soft`

A soft constraint is satisfied if possible and silently dropped if it conflicts with a hard
constraint or a later soft one. It is how a base class provides defaults ("no errors") that a test
overrides in-line without having to know the constraint's name to turn it off. Priority: later soft
constraints (in derived classes or in-line) beat earlier ones.

## Calling `randomize()`

```systemverilog
packet p = new();
if (!p.randomize()) $fatal(1, "randomize failed");            // ALWAYS check
assert (p.randomize()) else $fatal(1, "randomize failed");    // same thing, counts as an assertion

// In-line constraints: added for this call only
if (!p.randomize() with { len == 64; error == 1; }) ...
// Randomize a subset (other rand vars keep their values but still participate in constraints)
if (!p.randomize(len)) ...
// Turn constraint blocks on/off
p.c_dist.constraint_mode(0);
p.constraint_mode(0);           // all off
// Turn a variable's randomness on/off
p.len.rand_mode(0);             // len is now a state variable for the solver: keeps its current value
```

`randomize()` fails when constraints contradict each other or the in-line ones. Solvers print
the conflicting constraint set; read it. Section 5.2 covers debugging.

In-line constraints are how a *sequence* or *test* specializes a generic transaction: the AXI
sequence item has no application-specific constraints (it does not know it will feed a multiplier);
the multiplier sequence adds `data dist {...}` at randomize time (tutorial's `mult_sequence`). Keep
interface-level constraints (legal protocol) in the item and application-level ones in the sequence.

## `pre_randomize()` and `post_randomize()`

Called automatically before/after every `randomize()`. `post_randomize` is where derived,
non-random fields are computed (CRC, parity, packed header) and where you can *shape*
distributions the solver cannot (bathtub curves: randomize a uniform value, then transform it).
`pre_randomize` can set up state variables used by constraints (`rand_mode` toggles).

```systemverilog
function void post_randomize();
  crc = compute_crc(payload);
endfunction
```

Both must call `super.pre/post_randomize()` if a base class relies on them.

## Seeds, stability, and reproducibility

Every random failure must be reproducible. The rules:

- The simulator seed comes from the command line (`vsim -sv_seed 1234`, `+ntb_random_seed=1234`,
  `xrun -svseed 1234`). Log it at the start of every run. Regressions pick random seeds and record
  them with the results.
- **Random stability**: each thread and each object gets its own random number generator, seeded
  from the hierarchy (thread creation order and object creation order). Adding a `$urandom` call in
  an unrelated component does not change the stream elsewhere... *provided* you do not change
  creation order. Inserting a new object early in the build changes every later object's seed. UVM
  seeds objects by their full names to make this more robust.
- `$random` and `$dist_*` functions are *not* stable. Use `$urandom`, `$urandom_range`, and
  `randomize()`.
- `srandom(seed)` on an object or `process::self().srandom()` for a thread re-seeds locally, used
  for controlled experiments.

## What to randomize (Spear's list, still right)

- **Device configuration**: register settings, modes, enables. Most escapes are configuration
  interactions.
- **Environment configuration**: number of agents, bus widths, clock ratios, back-pressure
  probability, driver delays (the tutorial's `min/max_driver_delay`).
- **Primary input data**: the obvious one.
- **Encapsulated data**: headers, lengths, packing.
- **Protocol exceptions, errors, violations**: everything the spec says "shall be rejected."
- **Delays and synchronization**: gaps between transactions, ready toggling, simultaneous arrivals
  on multiple ports.

A transaction class typically randomizes 1 and 4; an environment/config class randomizes 2; the
driver randomizes 6; a sequence layers 5 on top.

## Interview angle

- "`rand` vs `randc`?" Repeat vs cyclic-permutation; per object; keep `randc` small.
- "Why is my implication constraint rarely triggering the condition?" Uniform over solutions; fix
  with `solve before` or `dist`.
- "What happens if `randomize()` fails and you do not check?" Values unchanged; you re-drive the
  previous transaction forever.
- "In-line constraints vs. `constraint_mode`?" Add for one call vs. disable a named block.
- "How do you reproduce a random failure?" Seed logging, random stability, `-sv_seed`.
- "`:=` vs `:/`?"

## Mentor's notes

- Write the constraints so that an *unconstrained* `randomize()` produces a *legal* transaction.
  Then every sequence starts from something that at least does not violate the protocol.
- Put `soft` defaults for "no errors, normal sizes" in the item. Tests that want chaos override
  them in-line. Tests that do not, get sane traffic without knowing the constraint names.
- When the solver is slow, the usual cause is a big `dist` or `inside` over a 32-bit variable
  crossed with an array constraint. Section 5.2 has the fixes.
