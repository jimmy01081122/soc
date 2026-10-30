#!/usr/bin/env bash
# Run every gemmini-rocc-tests baremetal test in Spike with the Gemmini extension
# (libgemmini), the functional reference for docs/plan.md stage 1. A test passes
# when Spike exits 0. Software and libgemmini are built to match CONFIG's
# parameters by scripts/gemmini_sw.sh.
#
# Writes results/spike_baremetal_<CONFIG>.md. Requires scripts/build_sim.sh CONFIG
# to have run (it saves the config's gemmini_params.h).
#
# Usage: scripts/spike_baremetal.sh [CONFIG]      default GemminiRocketConfig

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG=${1:-GemminiRocketConfig}

"$REPO_ROOT/scripts/gemmini_sw.sh" "$CONFIG"

set +u
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/chipyard_env.sh" > /dev/null
set -u

VARIANT=$CHIPYARD_DIR/.variants/$CONFIG
OUT=$REPO_ROOT/results/spike_baremetal_$CONFIG.md
DIM=$(awk '/define DIM /{print $3}' "$VARIANT/gemmini_params.h")

# Load this variant's libgemmini explicitly. LD_LIBRARY_PATH does not work: the
# conda-built spike has DT_RPATH, which is searched first and would pick the
# libgemmini installed into $RISCV/lib (built for the default 16x16 config).
SPIKE_ARGS=(--extlib="$VARIANT/lib/libgemmini.so" --extension=gemmini)

# Spike prints the array size it was built with; it must match the binaries.
probe=$(cd "$VARIANT/rocc-tests/build/bareMetalC" && timeout 60 spike "${SPIKE_ARGS[@]}" mvin_mvout-baremetal 2>&1 || true)
if ! grep -q "dim = $DIM\$" <<< "$probe"; then
    echo "Spike did not load the DIM=$DIM libgemmini; got: $(grep 'dim = ' <<< "$probe" || echo none)" >&2
    exit 1
fi

# gemmini-rocc-tests skips these two for the standard config ("Normal configs dont
# have ext spad"); they need a Gemmini build with an external shared scratchpad.
EXPECTED_FAIL=" matmul_spad mvin_mvout_spad "

pass=0 fail=0 skipped=0 rows="" unexpected=""
cd "$VARIANT/rocc-tests/build/bareMetalC"
for bin in *-baremetal; do
    name=${bin%-baremetal}
    rc=0
    timeout 120 spike "${SPIKE_ARGS[@]}" "$bin" > /dev/null 2>&1 || rc=$?
    if (( rc == 0 )); then
        status=pass; pass=$((pass + 1))
    elif [[ $EXPECTED_FAIL == *" $name "* ]]; then
        status="skipped (needs ext spad)"; skipped=$((skipped + 1))
    else
        status="FAIL"; fail=$((fail + 1)); unexpected+=" $name"
    fi
    rows+="| $name | $status | $rc |"$'\n'
done

mkdir -p "$(dirname "$OUT")"
{
    echo "# Spike 功能測試：$CONFIG（DIM=$DIM）"
    echo
    echo "由 \`scripts/spike_baremetal.sh\` 產生，$(date -u '+%Y-%m-%d %H:%M UTC')。"
    echo "Spike 以 \`--extension=gemmini\` 執行，libgemmini 與測試程式都依這個設定的 \`gemmini_params.h\` 建置。"
    echo "結束碼 0 算通過；這只驗證功能，不給效能數字。"
    echo
    echo "- gemmini：\`$(git -C "$CHIPYARD_DIR/generators/gemmini" rev-parse HEAD)\`"
    echo "- gemmini-rocc-tests：\`$(git -C "$CHIPYARD_DIR/generators/gemmini/software/gemmini-rocc-tests" rev-parse HEAD)\`"
    echo "- libgemmini：\`$(git -C "$CHIPYARD_DIR/generators/gemmini/software/libgemmini" rev-parse HEAD)\`"
    echo "- 結果：通過 $pass、失敗 $fail、略過 $skipped"
    echo
    echo "| 測試 | 結果 | 結束碼 |"
    echo "|---|---|---|"
    printf '%s' "$rows"
} > "$OUT"

echo "$CONFIG (DIM=$DIM): pass=$pass fail=$fail skipped=$skipped -> $OUT"
if (( fail )); then
    echo "unexpected failures:$unexpected" >&2
    exit 1
fi
