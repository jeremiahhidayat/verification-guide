# F. Reading List

## Books
- Chris Spear, Greg Tumbush. *SystemVerilog for Verification*, 3rd ed. Springer, 2012. The
  language for testbenches: data types, OOP, randomization, threads, coverage, interfaces, DPI.
- Stuart Sutherland, Simon Davidmann, Peter Flake. *SystemVerilog for Design*, 2nd ed. Springer.
  The synthesizable side; pairs with the tutorial's design chapters.
- Ben Cohen, Srinivasan Venkataramanan, Ajeetha Kumari, Lisa Piper. *SystemVerilog Assertions
  Handbook*, 4th ed. VhdlCohen. Deep SVA, including the uniqueness/ordering techniques used in the
  FIFO property.
- Ashok Mehta. *SystemVerilog Assertions and Functional Coverage*, 3rd ed. Springer. Broad,
  example-driven.
- Ray Salemi. *The UVM Primer*. Boston Light Press. Gentlest UVM introduction.
- Vanessa Cooper, Paul Marriott. *Practical UVM*. Step-by-step; good on sequences.
- Janick Bergeron. *Writing Testbenches Using SystemVerilog*. Springer. Methodology rationale.
- Erik Seligman, Tom Schubert, M V Achutha Kiran Kumar. *Formal Verification: An Essential Toolkit
  for Modern VLSI Design*, 2nd ed. Morgan Kaufmann. The practical formal book.
- Harry Foster, Adam Krolnik, David Lacey. *Assertion-Based Design*, 2nd ed. Springer. Older but
  the reasoning is timeless.
- Bruce Wile, John Goss, Wolfgang Roesner. *Comprehensive Functional Verification*. Morgan
  Kaufmann. The industrial process end to end (IBM heritage).

## Papers (all free online; search by title)
- Greg Stitt. *Race Conditions: The Root of All Verilog Evil* (stitt-hub.com, 2024). Read twice.
- Clifford Cummings. *Nonblocking Assignments in Verilog Synthesis, Coding Styles That Kill!*
  (SNUG 2000). The origin of the blocking/nonblocking rules.
- Clifford Cummings. *SystemVerilog Event Regions, Race Avoidance & Guidelines* (SNUG 2006).
  The scheduling regions in depth.
- Clifford Cummings. *Clocking Blocks* and *FSM coding styles* SNUG papers.
- Clifford Cummings, Heath Chambers. *UVM Analysis Ports / Sequences / Objections* SNUG series.
- Ben Cohen. *Uniqueness in SVA* (systemverilog.us). The tagged FIFO ordering property.
- Doug Smith. *Asynchronous Behaviors Meet Their Match with SystemVerilog Assertions* (DVCon).
- Mark Glasser, John Aynsley. *UVM Cookbook* chapters (Verification Academy, free registration).
- Harry Foster. *Wilson Research Group Functional Verification Study* (biennial). Industry data on
  methodology adoption, bug escapes, effort split.
- Accellera. *UVM 1.2 Class Reference* and *User's Guide*. The actual API.
- IEEE 1800-2017 / 1800-2023 SystemVerilog LRM. Chapters 4 (scheduling), 16 (assertions), 18
  (constraints), 19 (coverage). The final authority.

## Sites
- chipverify.com: SystemVerilog and UVM tutorials with runnable snippets; interview question sets.
- verificationacademy.com (Siemens): UVM Cookbook, courses, forums with expert answers (Cliff
  Cummings, Dave Rich, Tudor Timi frequently answer).
- verificationguide.com, testbench.in, asic-world.com: older but useful examples.
- ARC-Lab-UF sv-tutorial (github.com/ARC-Lab-UF/sv-tutorial): Greg Stitt's commented progression
  from basic testbenches to UVM; the backbone of chapters 2 to 7.
- symbiyosys.readthedocs.io and the *Formal Verification with SymbiYosys* tutorials (zipcpu.com):
  hands-on open-source formal.
- Verilator and cocotb docs for open-source simulation flows.
- Accellera PSS, UVM, and 1800.2 documents (accellera.org).

## What to read in what order
1. This guide, chapters 0 to 3, with the tutorial's `testbenches/basic` and `assertions` folders open.
2. Spear chapters 1 to 8 alongside chapters 5 and 6 here.
3. The UVM Cookbook "Basics" and the tutorial's `uvm/` folders alongside chapter 7.
4. Seligman for chapter 8; then run SymbiYosys on the FIFO.
5. Wile/Goss/Roesner and the Wilson study for chapter 9.
6. Cummings' papers whenever a question about semantics comes up.
