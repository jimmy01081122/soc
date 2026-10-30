#!/usr/bin/env bash
# Set up Chipyard with Gemmini for stage 1 of docs/plan.md.
#
# Installs, next to this repository (override with WORK_ROOT, CONDA_ROOT, CHIPYARD_DIR):
#   - Miniforge (conda)                                   -> $CONDA_ROOT
#   - Chipyard at a pinned tag                            -> $CHIPYARD_DIR
#   - Chipyard's lean conda env from its pinned lockfile (no FireSim/FireMarshal)
#   - the minimal Chipyard submodules plus Gemmini and libgemmini
#   - Spike, pk, riscv-tests, Scala precompile and CIRCT (via build-setup.sh)
#   - libgemmini, the Spike extension used as the functional reference
# and writes versions, step timings and disk usage to results/env/setup_manifest.md.
#
# Finished steps leave a marker and are skipped when the script is rerun.
#
# Usage: scripts/setup_chipyard.sh [--list] [--from STEP] [--only STEP]
#
# Afterwards, enter the environment with:  source scripts/chipyard_env.sh

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK_ROOT=${WORK_ROOT:-$(dirname "$REPO_ROOT")}
CONDA_ROOT=${CONDA_ROOT:-$WORK_ROOT/miniforge3}
CHIPYARD_DIR=${CHIPYARD_DIR:-$WORK_ROOT/chipyard}
STATE_DIR=${STATE_DIR:-$WORK_ROOT/.soc-setup}
LOG_DIR=$STATE_DIR/logs
MANIFEST=$REPO_ROOT/results/env/setup_manifest.md
MIN_FREE_GB=${MIN_FREE_GB:-20}

MINIFORGE_VERSION=26.7.2-1
CHIPYARD_TAG=1.15.0
CHIPYARD_COMMIT=157dd69e49b9866be2bf8db390ee78bc38cd4438
CHIPYARD_URL=https://github.com/ucb-bar/chipyard.git
# Shipped with the tag; sysroot 2.34, so it also runs on newer-glibc hosts.
LOCKFILE_REL=conda-reqs/conda-lock-reqs/conda-requirements-riscv-tools-linux-64-lean.conda-lock.yml

STEPS=(miniforge clone conda submodules toolchain scalacompile circt libgemmini)
# Maven Central answers ~30% of requests from the sandbox's shared proxy with 429.
MAVEN_MIRROR=https://maven-central.storage-download.googleapis.com/maven2/
SBT_TRIES=${SBT_TRIES:-8}

die() { echo "ERROR: $*" >&2; exit 1; }

valid_step() {
    local s
    for s in "${STEPS[@]}"; do
        [[ $s == "$1" ]] && return 0
    done
    return 1
}

usage() {
    sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    echo "Steps: ${STEPS[*]}"
    exit "${1:-0}"
}

activate_env() {
    set +u
    export WORK_ROOT CONDA_ROOT CHIPYARD_DIR
    # shellcheck disable=SC1091
    source "$REPO_ROOT/scripts/chipyard_env.sh"
    set -u
}

# ---------------------------------------------------------------- steps

preflight() {
    [[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] \
        || die "only Linux x86_64 is supported (pinned lockfile is linux-64)"
    local cmd
    for cmd in git curl make gcc sha256sum; do
        command -v "$cmd" >/dev/null || die "missing command: $cmd"
    done
    mkdir -p "$LOG_DIR"
    local free_gb
    free_gb=$(df -Pk "$WORK_ROOT" | awk 'NR==2 {print int($4 / 1048576)}')
    echo "host: $(nproc) cores, $(free -g | awk '/^Mem:/ {print $2}') GiB RAM, ${free_gb} GiB free at $WORK_ROOT"
    if (( free_gb < MIN_FREE_GB )) && [[ ! -d $CHIPYARD_DIR/.conda-env ]]; then
        die "less than ${MIN_FREE_GB} GiB free; free space or set MIN_FREE_GB"
    fi
}

step_miniforge() {
    if [[ -x $CONDA_ROOT/bin/conda ]]; then
        echo "conda already present at $CONDA_ROOT"
        return
    fi
    local name=Miniforge3-$MINIFORGE_VERSION-Linux-x86_64.sh
    local url=https://github.com/conda-forge/miniforge/releases/download/$MINIFORGE_VERSION/$name
    local tmp
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/$name" "$url"
    curl -fsSL -o "$tmp/$name.sha256" "$url.sha256"
    (cd "$tmp" && sha256sum -c "$name.sha256")
    bash "$tmp/$name" -b -p "$CONDA_ROOT"
    rm -rf "$tmp"
}

step_clone() {
    if [[ ! -d $CHIPYARD_DIR/.git ]]; then
        git clone --depth 1 --branch "$CHIPYARD_TAG" "$CHIPYARD_URL" "$CHIPYARD_DIR"
    fi
    local head
    head=$(git -C "$CHIPYARD_DIR" rev-parse HEAD)
    [[ $head == "$CHIPYARD_COMMIT" ]] \
        || die "$CHIPYARD_DIR is at $head, expected $CHIPYARD_TAG ($CHIPYARD_COMMIT)"
}

# Replaces build-setup.sh step 1, which on hosts with glibc newer than the
# lockfile's sysroot regenerates every lockfile (slow, and no longer pinned).
step_conda() {
    local lock=$CHIPYARD_DIR/$LOCKFILE_REL
    [[ -f $lock ]] || die "missing lockfile $lock"
    if [[ ! -x $CHIPYARD_DIR/.conda-lock-env/bin/conda-lock ]]; then
        "$CONDA_ROOT/bin/conda" create -y -p "$CHIPYARD_DIR/.conda-lock-env" -c conda-forge conda-lock
    fi
    rm -rf "$CHIPYARD_DIR/.conda-env"
    PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring \
        "$CHIPYARD_DIR/.conda-lock-env/bin/conda-lock" install \
        --conda "$CONDA_ROOT/bin/conda" -p "$CHIPYARD_DIR/.conda-env" "$lock"

    # Same env.sh block that build-setup.sh step 1 writes.
    local preamble
    preamble=$(cat <<'EOF'
if ! type conda >& /dev/null; then
    echo "::ERROR:: you must have conda in your environment first"
    return 1  # don't want to exit here because this file is sourced
fi

source $(conda info --base)/etc/profile.d/conda.sh
EOF
)
    (
        cd "$CHIPYARD_DIR"
        # shellcheck disable=SC1091
        source scripts/utils.sh
        replace_content env.sh build-setup-conda "# line auto-generated by setup_chipyard.sh
$preamble
conda activate $CHIPYARD_DIR/.conda-env
source $CHIPYARD_DIR/scripts/fix-open-files.sh"
    )
}

step_submodules() {
    (cd "$CHIPYARD_DIR" && ./scripts/init-submodules-no-riscv-tools.sh --gemmini)
    git -C "$CHIPYARD_DIR/generators/gemmini" submodule update --init software/libgemmini
}

# Runs one numbered step of Chipyard's build-setup.sh, skipping all the others
# (--use-lean-conda already skips 4 and 6-9). Steps: 3 Spike/pk/riscv-tests,
# 5 Scala precompile, 10 CIRCT, 11 repository cleanup.
build_setup_steps() {
    local want=" $* " skips=() n
    for n in 1 2 3 4 5 6 7 8 9 10 11; do
        [[ $want == *" $n "* ]] || skips+=(-s "$n")
    done
    (cd "$CHIPYARD_DIR" && ./build-setup.sh riscv-tools --use-lean-conda "${skips[@]}")
}

step_toolchain() {
    activate_env
    build_setup_steps 3
    [[ -x $RISCV/bin/spike ]] || die "spike not installed in $RISCV"
}

# Replace sbt's repository list (launcher, plugins and the build itself) with a
# Maven Central mirror first and Maven Central as the fallback. chipyard_env.sh
# passes this file to sbt with -Dsbt.override.build.repos=true. That drops the
# sonatype resolvers in Chipyard's build.sbt, which is fine because every
# dependency it pins (Chisel 3.6.1 / 6.7.0 / 7.13.0 etc.) is a Central release.
# (coursier's COURSIER_MIRRORS file is not honored by sbt's shaded coursier.)
write_build_mirrors() {
    mkdir -p "$CHIPYARD_DIR/.sbt"
    rm -f "$CHIPYARD_DIR/.sbt/coursier-mirrors.properties"
    cat > "$CHIPYARD_DIR/.sbt/repositories" <<EOF
[repositories]
  local
  maven-local
  maven-mirror: $MAVEN_MIRROR
  maven-central
  sbt-plugin-releases: https://repo.scala-sbt.org/scalasbt/sbt-plugin-releases/, [organization]/[module](/scala_[scalaVersion])(/sbt_[sbtVersion])/[revision]/[type]s/[artifact](-[classifier]).[ext]
EOF
}

# sbt keeps what it already downloaded, so each retry only fetches what is missing.
step_scalacompile() {
    write_build_mirrors
    activate_env
    local try
    for (( try = 1; try <= SBT_TRIES; try++ )); do
        echo "-- sbt precompile, attempt $try of $SBT_TRIES"
        if build_setup_steps 5; then
            return 0
        fi
        sleep $(( 15 * try ))
    done
    die "Scala precompile still failing after $SBT_TRIES attempts"
}

step_circt() {
    activate_env
    build_setup_steps 10 11
    command -v firtool >/dev/null || die "firtool not on PATH"
}

step_libgemmini() {
    activate_env
    make -C "$CHIPYARD_DIR/generators/gemmini/software/libgemmini" install
    ls "$RISCV"/lib/*gemmini* >/dev/null 2>&1 || die "libgemmini not found in $RISCV/lib"
}

# ---------------------------------------------------------------- manifest

write_manifest() {
    mkdir -p "$(dirname "$MANIFEST")"
    local have_env=0
    [[ -d $CHIPYARD_DIR/.conda-env ]] && have_env=1
    {
        echo "# Chipyard 環境紀錄"
        echo
        echo "由 \`scripts/setup_chipyard.sh\` 產生，$(date -u '+%Y-%m-%d %H:%M UTC')。"
        echo
        echo "## 主機"
        echo
        echo "| 項目 | 值 |"
        echo "|---|---|"
        echo "| OS | $(. /etc/os-release && echo "$PRETTY_NAME")，kernel $(uname -r) |"
        echo "| glibc | $(ldd --version | awk 'NR==1 {print $NF}') |"
        echo "| CPU | $(nproc) 核 |"
        echo "| 記憶體 | $(free -g | awk '/^Mem:/ {print $2}') GiB |"
        echo "| 磁碟可用（$WORK_ROOT） | $(df -Ph "$WORK_ROOT" | awk 'NR==2 {print $4}') |"
        echo
        echo "## 版本"
        echo
        echo "| 項目 | 版本 |"
        echo "|---|---|"
        echo "| Miniforge | $MINIFORGE_VERSION |"
        [[ -x $CONDA_ROOT/bin/conda ]] && echo "| conda | $("$CONDA_ROOT/bin/conda" --version | awk '{print $2}') |"
        [[ -x $CHIPYARD_DIR/.conda-lock-env/bin/conda-lock ]] \
            && echo "| conda-lock | $("$CHIPYARD_DIR/.conda-lock-env/bin/conda-lock" --version 2>/dev/null | awk '{print $NF}') |"
        echo "| conda lockfile | \`$LOCKFILE_REL\` |"
        if [[ -d $CHIPYARD_DIR/.git ]]; then
            echo "| Chipyard | $CHIPYARD_TAG（\`$(git -C "$CHIPYARD_DIR" rev-parse HEAD)\`） |"
            local sub
            for sub in generators/gemmini generators/gemmini/software/gemmini-rocc-tests \
                       generators/gemmini/software/libgemmini generators/rocket-chip \
                       generators/testchipip toolchains/riscv-tools/riscv-isa-sim \
                       toolchains/riscv-tools/riscv-pk; do
                [[ -e $CHIPYARD_DIR/$sub/.git ]] \
                    && echo "| $sub | \`$(git -C "$CHIPYARD_DIR/$sub" rev-parse HEAD)\` |"
            done
        fi
        if (( have_env )); then
            (
                activate_env
                echo "| riscv64-unknown-elf-gcc | $(riscv64-unknown-elf-gcc --version 2>/dev/null | head -1) |"
                echo "| Verilator | $(verilator --version 2>/dev/null) |"
                echo "| firtool | $(firtool --version 2>/dev/null | grep -m1 CIRCT | xargs) |"
                echo "| Java | $(java -version 2>&1 | grep -v JAVA_TOOL_OPTIONS | head -1) |"
            )
        fi
        echo
        echo "## 步驟耗時"
        echo
        echo "| 步驟 | 狀態 | 開始（UTC） | 秒數 |"
        echo "|---|---|---|---|"
        [[ -f $STATE_DIR/timings.tsv ]] \
            && awk -F'\t' '{printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4}' "$STATE_DIR/timings.tsv"
        echo
        echo "## 磁碟用量"
        echo
        echo "| 路徑 | 大小 |"
        echo "|---|---|"
        local p
        for p in "$CHIPYARD_DIR" "$CHIPYARD_DIR/.conda-env" "$CONDA_ROOT" \
                 "$HOME/.cache/coursier" "$HOME/.sbt" "$HOME/.ivy2"; do
            if [[ -e $p ]]; then
                echo "| \`$p\` | $(du -sh "$p" 2>/dev/null | cut -f1) |"
            fi
        done
    } > "$MANIFEST"
    echo "manifest written to $MANIFEST"
}

# ---------------------------------------------------------------- driver

run_step() {
    local name=$1 force=$2
    local marker=$STATE_DIR/$name.done log=$LOG_DIR/$name.log
    if [[ -f $marker && $force == 0 ]]; then
        echo "== $name: already done, skipping"
        return
    fi
    echo "== $name: starting (log: $log)"
    local start status
    start=$(date +%s)
    set +e
    ( set -e; "step_$name" ) 2>&1 | tee "$log"
    status=${PIPESTATUS[0]}
    set -e
    local secs=$(( $(date +%s) - start ))
    printf '%s\t%s\t%s\t%s\n' "$name" "$([[ $status == 0 ]] && echo ok || echo "failed($status)")" \
        "$(date -u -d "@$start" '+%Y-%m-%d %H:%M')" "$secs" >> "$STATE_DIR/timings.tsv"
    if [[ $status != 0 ]]; then
        write_manifest
        die "step $name failed after ${secs}s; see $log"
    fi
    touch "$marker"
    echo "== $name: done in ${secs}s"
}

main() {
    local from="" only=""
    while (( $# )); do
        case $1 in
            --list) printf '%s\n' "${STEPS[@]}"; exit 0 ;;
            --from) from=${2:?}; shift ;;
            --only) only=${2:?}; shift ;;
            -h|--help) usage 0 ;;
            *) echo "unknown option: $1" >&2; usage 1 ;;
        esac
        shift
    done
    [[ -z $from ]] || valid_step "$from" || die "unknown step: $from (see --list)"
    [[ -z $only ]] || valid_step "$only" || die "unknown step: $only (see --list)"

    local s
    preflight
    if [[ -n $only ]]; then
        run_step "$only" 1
    else
        local started=0
        [[ -z $from ]] && started=1
        for s in "${STEPS[@]}"; do
            [[ $s == "$from" ]] && started=1
            (( started )) || continue
            run_step "$s" "$([[ -n $from ]] && echo 1 || echo 0)"
        done
    fi
    write_manifest
}

main "$@"
