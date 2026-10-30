#!/usr/bin/env bash
# Run one baremetal binary on a Chipyard Verilator simulator and classify the result.
#
# The simulator exits silently at $finish when the program returns 0 and prints
# "*** FAILED *** (exit code = N)" otherwise; hitting +max-cycles is also a failure.
# This script reports PASS / FAIL / TIMEOUT plus wall-clock time, and keeps the
# full output in $OUT_DIR for inspection.
#
# Usage: scripts/run_rtl.sh CONFIG BINARY [MAX_CYCLES]
#   CONFIG      e.g. GemminiRocketConfig (simulator must already be built)
#   BINARY      path to a baremetal RISC-V binary
#   MAX_CYCLES  default 10000000

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG=${1:?usage: $0 CONFIG BINARY [MAX_CYCLES]}
BINARY=${2:?usage: $0 CONFIG BINARY [MAX_CYCLES]}
MAX_CYCLES=${3:-10000000}

set +u
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/chipyard_env.sh" > /dev/null
set -u

SIM=$CHIPYARD_DIR/sims/verilator/simulator-chipyard.harness-$CONFIG
DRAM=$CHIPYARD_DIR/generators/testchipip/src/main/resources/dramsim2_ini
OUT_DIR=${OUT_DIR:-$(dirname "$CHIPYARD_DIR")/.soc-setup/rtl_runs}
[[ -x $SIM ]] || { echo "no simulator $SIM; run scripts/build_sim.sh $CONFIG" >&2; exit 2; }
[[ -f $BINARY ]] || { echo "no binary $BINARY" >&2; exit 2; }
mkdir -p "$OUT_DIR"
# Key the log on the full binary path so runs of same-named binaries from
# different variants (or run in parallel) cannot overwrite each other.
LOG=$OUT_DIR/$CONFIG.$(basename "$BINARY").$(printf '%s' "$(realpath "$BINARY")" | cksum | cut -d' ' -f1).log

start=$(date +%s)
rc=0
# stdbuf -oL: a long run's output (e.g. a profiler's CSV) shows up as it is printed
# instead of only when the stdio buffer fills, and survives a timeout kill.
# TIMEOUT_SECS bounds the wall-clock time; the simulator runs at only ~2-3k cycles/s.
timeout "${TIMEOUT_SECS:-3600}" stdbuf -oL -eL "$SIM" +permissive +dramsim +dramsim_ini_dir="$DRAM" \
    +max-cycles="$MAX_CYCLES" +permissive-off "$BINARY" > "$LOG" 2>&1 || rc=$?
wall=$(( $(date +%s) - start ))

# A cycle-limit timeout prints "*** FAILED *** (timeout) after N simulation cycles",
# so it has to be recognized before the generic FAILED case.
if grep -q "\*\*\* FAILED \*\*\*.*(timeout)" "$LOG"; then
    verdict="TIMEOUT (max-cycles $MAX_CYCLES)"
elif grep -q "\*\*\* FAILED \*\*\*" "$LOG"; then
    verdict="FAIL ($(grep -m1 -o '\*\*\* FAILED \*\*\*.*' "$LOG"))"
elif (( rc == 0 )) && grep -q 'Verilog \$finish' "$LOG"; then
    verdict=PASS
else
    verdict="UNKNOWN (rc=$rc; see $LOG)"
fi

echo "$CONFIG $(basename "$BINARY"): $verdict, wall ${wall}s, log $LOG"
[[ $verdict == PASS ]]
