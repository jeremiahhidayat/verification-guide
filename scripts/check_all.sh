#!/usr/bin/env bash
# Compile-check every code example with Questa (vlog + vopt). Run from the repo root in Git Bash:
#   bash scripts/check_all.sh
# Simulation needs a license; compile and elaboration do not on Questa FSE, so this is the CI gate.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/scripts/work_check"
mkdir -p "$WORK" && cd "$WORK" || exit 1
vlib work >/dev/null 2>&1

fail=0
step() {  # name, top, files...
  local name="$1"; local top="$2"; shift 2
  echo "== $name"
  if vlog -sv -quiet -mfcu "$@" && vopt -quiet "$top" -o "${top}_opt" >/dev/null; then
    echo "   ok"
  else
    echo "   FAILED"; fail=1
  fi
}

C="$ROOT/code"
step "ch1 races"        race_bad          "$C/01-fundamentals/races.sv"
step "ch1 datatypes"    datatypes_demo    "$C/01-fundamentals/datatypes_demo.sv"
step "ch2 fifo_tb"      fifo_tb           "$C/02-basic-tb/fifo.sv" "$C/02-basic-tb/fifo_tb.sv"
step "ch2 register_tb"  register_tb       "$C/02-basic-tb/register_tb.sv"
step "ch3 sva bound"    fifo_tb           "$C/02-basic-tb/fifo.sv" "$C/03-sva/fifo_sva.sv" "$C/03-sva/fifo_bind.sv" "$C/02-basic-tb/fifo_tb.sv"
step "ch3 patterns"     sva_patterns_tb   "$C/03-sva/sva_patterns_tb.sv"
step "ch4 coverage"     fifo_tb           "$C/02-basic-tb/fifo.sv" "$C/04-coverage/fifo_cov.sv" "$C/04-coverage/fifo_cov_bind.sv" "$C/02-basic-tb/fifo_tb.sv"
step "ch5 constraints"  constraints_demo  "$C/05-crv/constraints_demo.sv"
step "ch6 layered"      tb_top            "$C/02-basic-tb/fifo.sv" "$C/06-layered-tb/fifo_if.sv" "$C/06-layered-tb/fifo_tb_pkg.sv" "$C/06-layered-tb/tb_top.sv"
step "ch7 uvm"          tb_top            "$C/02-basic-tb/fifo.sv" "$C/06-layered-tb/fifo_if.sv" "$C/07-uvm/fifo_uvm_pkg.sv" "$C/07-uvm/tb_top.sv"
step "ch8 formal (sim)" fifo_formal       "$C/02-basic-tb/fifo.sv" "$C/08-formal/fifo_formal.sv"
step "bug hooks"        fifo              +define+BUG_FULL_OFF_BY_ONE +define+BUG_NO_RESET_RDPTR +define+BUG_DROP_ON_SIMUL "$C/02-basic-tb/fifo.sv"

echo
if [ $fail -eq 0 ]; then echo "ALL COMPILE CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit $fail
