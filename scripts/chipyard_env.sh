# Source this file to enter the Chipyard environment installed by
# scripts/setup_chipyard.sh:
#
#   source scripts/chipyard_env.sh
#
# Honors the same WORK_ROOT / CONDA_ROOT / CHIPYARD_DIR overrides as the setup script.

_soc_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
_work_root=${WORK_ROOT:-$(dirname "$_soc_root")}
export CHIPYARD_DIR=${CHIPYARD_DIR:-$_work_root/chipyard}
# shellcheck disable=SC1091
source "${CONDA_ROOT:-$_work_root/miniforge3}/etc/profile.d/conda.sh"
# shellcheck disable=SC1091
source "$CHIPYARD_DIR/env.sh"

if [[ -z ${SOC_BUILD_ENV_SET:-} ]]; then
    # Chipyard's makefiles only apply their JVM and sbt defaults with `?=`, so a
    # JAVA_TOOL_OPTIONS already exported by the host (the cloud sandbox sets proxy
    # options there) silently drops -Xmx and -Xss. Append them here instead.
    mkdir -p "$CHIPYARD_DIR/.java_tmp"
    export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:+$JAVA_TOOL_OPTIONS }-Xmx${JAVA_HEAP_SIZE:-8G} -Xss8M -Djava.io.tmpdir=$CHIPYARD_DIR/.java_tmp"

    # Same options as Chipyard's variables.mk, plus the repository list written by
    # setup_chipyard.sh (a Maven Central mirror; Maven Central itself answers
    # about a third of requests from the shared sandbox proxy with HTTP 429).
    export SBT_OPTS="-Dsbt.ivy.home=$CHIPYARD_DIR/.ivy2 -Dsbt.global.base=$CHIPYARD_DIR/.sbt -Dsbt.boot.directory=$CHIPYARD_DIR/.sbt/boot/ -Dsbt.color=false -Dsbt.supershell=false -Dsbt.server.forcestart=true"
    if [[ -f $CHIPYARD_DIR/.sbt/repositories ]]; then
        SBT_OPTS="$SBT_OPTS -Dsbt.repository.config=$CHIPYARD_DIR/.sbt/repositories"
    fi
    if [[ -f $CHIPYARD_DIR/.sbt/coursier-mirrors.properties ]]; then
        export COURSIER_MIRRORS=$CHIPYARD_DIR/.sbt/coursier-mirrors.properties
    fi
    export SOC_BUILD_ENV_SET=1
fi
unset _soc_root _work_root
