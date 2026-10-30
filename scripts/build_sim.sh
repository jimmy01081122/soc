#!/usr/bin/env bash
# Build the Chipyard Verilator simulator for one config and record what it cost.
#
# Copies hw/chipyard/*.scala into Chipyard's config directory first, so our own
# configs (e.g. Gemmini8x8RocketConfig) can be built by name. Writes
# results/sim_builds/<CONFIG>.md: wall time (total and per phase), the lowest
# available memory seen while building, and disk use.
#
# Usage: scripts/build_sim.sh CONFIG [-j JOBS]
#   e.g. scripts/build_sim.sh Gemmini8x8RocketConfig -j 4

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG=${1:?usage: $0 CONFIG [-j JOBS]}
shift
JOBS=$(nproc)
while getopts "j:" opt; do
    case $opt in
        j) JOBS=$OPTARG ;;
        *) echo "usage: $0 CONFIG [-j JOBS]" >&2; exit 1 ;;
    esac
done

set +u
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/chipyard_env.sh" > /dev/null
set -u

SIM_DIR=$CHIPYARD_DIR/sims/verilator
CONFIG_DIR=$CHIPYARD_DIR/generators/chipyard/src/main/scala/config
OUT=$REPO_ROOT/results/sim_builds/$CONFIG.md
LOG_DIR=${LOG_DIR:-$(dirname "$CHIPYARD_DIR")/.soc-setup/logs}
LOG=$LOG_DIR/build_sim_$CONFIG.log
SIM=$SIM_DIR/simulator-chipyard.harness-$CONFIG
mkdir -p "$LOG_DIR" "$(dirname "$OUT")"

# Our configs live in this repo; Chipyard compiles whatever sits in its config dir.
for f in "$REPO_ROOT"/hw/chipyard/*.scala; do
    [[ -e $f ]] && cp "$f" "$CONFIG_DIR/"
done

# A leftover simulator from an earlier build must not be mistaken for this one.
rm -f "$SIM"

STATS=$(mktemp)    # "<lowest MemAvailable MiB> <highest swap MiB>"
PHASES=$(mktemp)   # "<seconds> <label>" lines
start=$(date +%s)
echo "$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo) 0" > "$STATS"

# Sample memory and notice phase changes every 5 s while make runs.
(
    got_sv=0
    got_mk=0
    while sleep 5; do
        avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
        swap=$(awk '/SwapTotal/ {t=$2} /SwapFree/ {f=$2} END {print int((t-f)/1024)}' /proc/meminfo)
        read -r min_avail max_swap < "$STATS"
        (( avail < min_avail )) && min_avail=$avail
        (( swap > max_swap )) && max_swap=$swap
        echo "$min_avail $max_swap" > "$STATS"
        now=$(( $(date +%s) - start ))
        if (( ! got_sv )) && [[ -n $(find "$SIM_DIR/generated-src" -name '*.sv' -path "*$CONFIG*" -print -quit 2>/dev/null) ]]; then
            got_sv=1; echo "$now Verilog 已產生（firtool 完成）" >> "$PHASES"
        fi
        if (( ! got_mk )) && [[ -n $(find "$SIM_DIR/generated-src" -name 'V*.mk' -path "*$CONFIG*" -print -quit 2>/dev/null) ]]; then
            got_mk=1; echo "$now Verilator 轉換完成，開始編譯 C++" >> "$PHASES"
        fi
    done
) &
SAMPLER=$!
trap 'kill $SAMPLER 2>/dev/null || true' EXIT

disk_before=$(df -Pk "$CHIPYARD_DIR" | awk 'NR==2 {print $3}')
status=0
make -C "$SIM_DIR" -j"$JOBS" CONFIG="$CONFIG" > "$LOG" 2>&1 || status=$?
end=$(date +%s)
disk_after=$(df -Pk "$CHIPYARD_DIR" | awk 'NR==2 {print $3}')
kill "$SAMPLER" 2>/dev/null || true
read -r min_avail max_swap < "$STATS"

result=ok
if (( status != 0 )) || [[ ! -x $SIM ]]; then
    result="失敗（make 結束碼 $status）"
fi

gen=$SIM_DIR/generated-src
{
    echo "# Verilator 模擬器建置：$CONFIG"
    echo
    echo "由 \`scripts/build_sim.sh\` 產生，$(date -u '+%Y-%m-%d %H:%M UTC')。"
    echo
    echo "| 項目 | 值 |"
    echo "|---|---|"
    echo "| 結果 | $result |"
    echo "| 平行度（make -j） | $JOBS |"
    echo "| 總耗時 | $(( end - start )) 秒 |"
    echo "| 建置期間最低可用記憶體 | ${min_avail} MiB（共 $(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo) MiB） |"
    echo "| 建置期間最高 swap 用量 | ${max_swap} MiB |"
    echo "| 磁碟增加 | $(( (disk_after - disk_before) / 1024 )) MiB |"
    [[ -d $gen ]] && echo "| generated-src 大小 | $(du -sh "$gen" | cut -f1) |"
    [[ -x $SIM ]] && echo "| 模擬器執行檔 | $(du -h "$SIM" | cut -f1) |"
    if [[ -s $PHASES ]]; then
        echo
        echo "各階段時間（距建置開始的秒數，每 5 秒取樣一次）："
        echo
        sed 's/^\([0-9]*\) \(.*\)$/- \1 秒：\2/' "$PHASES"
    fi
} > "$OUT"
rm -f "$STATS" "$PHASES"

echo "$CONFIG: $result, $(( end - start ))s, lowest MemAvailable ${min_avail} MiB -> $OUT (log: $LOG)"
[[ $result == ok ]]
