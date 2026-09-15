# B. Constraints and Randomization Cheat Sheet

## Declarations
```systemverilog
rand  bit [7:0] x;      // random
randc bit [3:0] y;      // cyclic (keep small)
rand  int arr[];        // dynamic: size and elements constrainable
rand  pkt   p;          // handle: randomizes the object (must exist)
constraint name { ... } // block; same-name in subclass overrides; new name adds
```

## Constraint expressions
| Form | Meaning |
|---|---|
| `x < y; x + y == 10;` | relational/arithmetic (bidirectional) |
| `x inside {1, 3, [8:15]};` | set membership (`!(x inside {...})` for exclusion) |
| `x dist {0 := 5, [1:9] :/ 90, 10 := 5};` | weighted: `:=` per value, `:/` per range |
| `a -> b;` | implication (`!a \|\| b`) |
| `a <-> b;` | equivalence |
| `if (c) x < 4; else x > 4;` | conditional |
| `solve a before b;` | ordering (distribution only) |
| `soft x == 0;` | default that yields to hard/later constraints |
| `unique {arr};` / `unique {a, b, c};` | all distinct |
| `arr.size() inside {[1:8]};` | size |
| `foreach (arr[i]) arr[i] < 100;` | per element |
| `foreach (arr[i]) if (i>0) arr[i] > arr[i-1];` | relations between elements |
| `arr.sum() with (int'(item)) < N;` | reduction (widen!) |
| `x % 4 == 0;` → prefer `x[1:0] == 0;` | alignment (bit form is faster) |
| `f(x) == 3;` | function call (function must be pure-ish; args are solved first) |

## Calls and control
```systemverilog
if (!obj.randomize()) $fatal(1, "randomize failed");        // ALWAYS check
obj.randomize() with { x > 3; y == local::y; }             // in-line (local:: refers to caller scope)
obj.randomize(x);                                          // only x
obj.randomize(null);                                       // check constraints without changing
obj.c_name.constraint_mode(0);   obj.constraint_mode(1);    // block on/off
obj.x.rand_mode(0);              obj.rand_mode(1);          // variable on/off
std::randomize(a, b) with { a < b; };                       // scope randomize
function void pre_randomize();  function void post_randomize();   // hooks (call super)
obj.srandom(seed);  process::self().srandom(seed);         // local reseed
```

## Procedural randomness
```systemverilog
$urandom;  $urandom(seed);  $urandom_range(max, min);  $urandom_range(max);   // never $random
randcase  70: a(); 30: b(); endcase
randsequence(main) main : a b | c; ... endsequence
```

## Distribution traps
- Uniform over **solutions**: implications make the antecedent rare → `solve before` / `dist`.
- `dist` is overridden by any hard constraint that narrows the variable.
- `randc` on wide variables silently degrades.
- Unsigned subtraction in constraints wraps.

## Debug
Tool flags: Questa `-solvefaildebug` / `-solveflags`; VCS `+ntb_solver_debug` / `-cm_seqnoconst`;
Xcelium `-nc_solvedebug`. Histogram fields with a loop + associative array before trusting a `dist`.
