#!/usr/bin/env bash
# Build Gemmini's baremetal tests (gemmini-rocc-tests/bareMetalC) and run each one
# in Spike with the Gemmini extension (libgemmini), the functional reference for
# docs/plan.md stage 1. A test passes when Spike exits 0.
#
# Writes results/spike_baremetal.md. Requires scripts/setup_chipyard.sh to have run.
#
# Usage: scripts/spike_baremetal.sh [-j JOBS]

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
JOBS=$(nproc)
while getopts "j:" opt; do
    case $opt in
        j) JOBS=$OPTARG ;;
        *) echo "usage: $0 [-j JOBS]" >&2; exit 1 ;;
    esac
done

set +u
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/chipyard_env.sh" > /dev/null
set -u

TESTS=$CHIPYARD_DIR/generators/gemmini/software/gemmini-rocc-tests
OUT=$REPO_ROOT/results/spike_baremetal.md

if [[ ! -d $TESTS/build ]]; then
    (cd "$TESTS" && autoconf && mkdir build && cd build && ../configure)
fi
make -C "$TESTS/build" -j"$JOBS" BAREMETAL_ONLY=1 bareMetalC > /dev/null

# gemmini-rocc-tests skips these two for the standard config ("Normal configs dont
# have ext spad"); they need a Gemmini build with an external shared scratchpad.
EXPECTED_FAIL=" matmul_spad mvin_mvout_spad "

pass=0 fail=0 skipped=0 rows="" unexpected=""
cd "$TESTS/build/bareMetalC"
for bin in *-baremetal; do
    name=${bin%-baremetal}
    rc=0
    timeout 120 spike --extension=gemmini "$bin" > /dev/null 2>&1 || rc=$?
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
    echo "# Spike 功能測試：gemmini-rocc-tests／bareMetalC"
    echo
    echo "由 \`scripts/spike_baremetal.sh\` 產生，$(date -u '+%Y-%m-%d %H:%M UTC')。"
    echo "Spike 以 \`--extension=gemmini\` 執行，結束碼 0 算通過。這只驗證功能，不給效能數字。"
    echo
    echo "- gemmini：\`$(git -C "$CHIPYARD_DIR/generators/gemmini" rev-parse HEAD)\`"
    echo "- gemmini-rocc-tests：\`$(git -C "$TESTS" rev-parse HEAD)\`"
    echo "- libgemmini：\`$(git -C "$CHIPYARD_DIR/generators/gemmini/software/libgemmini" rev-parse HEAD)\`"
    echo "- 結果：通過 $pass、失敗 $fail、略過 $skipped"
    echo
    echo "| 測試 | 結果 | 結束碼 |"
    echo "|---|---|---|"
    printf '%s' "$rows"
} > "$OUT"

echo "pass=$pass fail=$fail skipped=$skipped -> $OUT"
if (( fail )); then
    echo "unexpected failures:$unexpected" >&2
    exit 1
fi
