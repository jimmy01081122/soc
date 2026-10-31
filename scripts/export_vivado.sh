#!/usr/bin/env bash
# Export the synthesizable Verilog of one Chipyard config for Vivado.
#
# Copies the files that module TOP needs (default: the Gemmini accelerator) out of
# the generated gen-collateral into vivado/<CONFIG>/<TOP>/rtl, plus files.txt (the
# read order). Synthesis itself is run with vivado/synth_ooc.tcl; see vivado/README.md.
# Needs scripts/build_sim.sh CONFIG to have run (that generates the Verilog).
#
# Usage: scripts/export_vivado.sh CONFIG [TOP]
#   e.g. scripts/export_vivado.sh Gemmini8x8RocketConfig Gemmini

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG=${1:?usage: $0 CONFIG [TOP]}
TOP=${2:-Gemmini}
CHIPYARD_DIR=${CHIPYARD_DIR:-$(dirname "$REPO_ROOT")/chipyard}

GEN=$CHIPYARD_DIR/sims/verilator/generated-src/chipyard.harness.TestHarness.$CONFIG/gen-collateral
OUT=$REPO_ROOT/vivado/$CONFIG/$TOP
[[ -d $GEN ]] || { echo "no $GEN; run scripts/build_sim.sh $CONFIG first" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/rtl"
python3 -I "$REPO_ROOT/model/rtl_closure.py" "$GEN" "$TOP" --copy-to "$OUT/rtl" --list "$OUT/files.txt"

# The tool over-includes at worst, but a missing module would only show up in
# Vivado; check the copied set is self-contained with a lint run when we can.
if command -v verilator > /dev/null; then
    mapfile -t FILES < <(sed "s#^#$OUT/rtl/#" "$OUT/files.txt")
    if verilator --lint-only -Wno-fatal -Wno-lint -Wno-style --top-module "$TOP" "${FILES[@]}" \
            > "$OUT/lint.log" 2>&1; then
        echo "verilator lint: ok ($(grep -c '%Warning' "$OUT/lint.log" || true) warnings, see $OUT/lint.log)"
    else
        echo "verilator lint FAILED; see $OUT/lint.log" >&2
        grep -m5 -E '%Error' "$OUT/lint.log" >&2 || true
        exit 1
    fi
fi

if grep -lE '^\s*`include' "$OUT"/rtl/* > /dev/null 2>&1; then
    echo "warning: some exported files use \`include; Vivado needs those files too:" >&2
    grep -hE '^\s*`include' "$OUT"/rtl/* | sort -u >&2
fi

{
    echo "config:  $CONFIG"
    echo "top:     $TOP"
    echo "chipyard: $(git -C "$CHIPYARD_DIR" rev-parse HEAD)"
    echo "gemmini:  $(git -C "$CHIPYARD_DIR/generators/gemmini" rev-parse HEAD)"
    echo "exported: $(date -u '+%Y-%m-%d %H:%M UTC')"
} > "$OUT/SOURCE.txt"
echo "exported $(wc -l < "$OUT/files.txt") files to $OUT"
