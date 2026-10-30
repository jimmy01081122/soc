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
unset _soc_root _work_root
