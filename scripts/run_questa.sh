#!/usr/bin/env bash
# Compile and run one chapter example with Questa.
#   bash scripts/run_questa.sh <chapter-dir> <top> [plusargs...]
# Examples:
#   bash scripts/run_questa.sh code/02-basic-tb fifo_tb
#   bash scripts/run_questa.sh code/06-layered-tb tb_top +TEST=fill_drain
#   bash scripts/run_questa.sh code/07-uvm tb_top +UVM_TESTNAME=fifo_random_test +UVM_VERBOSITY=UVM_LOW
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/$1"; TOP="$2"; shift 2
cd "$DIR"
vlib work >/dev/null 2>&1 || true
case "$DIR" in
  *02-basic-tb)   FILES="fifo.sv fifo_tb.sv register_tb.sv" ;;
  *03-sva)        FILES="../02-basic-tb/fifo.sv fifo_sva.sv fifo_bind.sv ../02-basic-tb/fifo_tb.sv sva_patterns_tb.sv" ;;
  *04-coverage)   FILES="../02-basic-tb/fifo.sv fifo_cov.sv fifo_cov_bind.sv ../02-basic-tb/fifo_tb.sv" ;;
  *05-crv)        FILES="constraints_demo.sv" ;;
  *06-layered-tb) FILES="../02-basic-tb/fifo.sv fifo_if.sv fifo_tb_pkg.sv tb_top.sv" ;;
  *07-uvm)        FILES="-f files.f" ;;
  *08-formal)     FILES="../02-basic-tb/fifo.sv fifo_formal.sv" ;;
  *)              FILES="*.sv" ;;
esac
vlog -sv -mfcu +cover=bcesf $FILES
vsim -c -coverage -sv_seed random "$TOP" "$@" -do "run -all; coverage report -summary; quit -f"
