#!/usr/bin/env bash
# Build libgemmini (Spike's Gemmini model) and the gemmini-rocc-tests baremetal
# binaries for ONE Chipyard config, using that config's own gemmini_params.h.
#
# Why: Gemmini's software and libgemmini hard-code the array size, scratchpad
# size and so on from gemmini_params.h, and elaborating a config rewrites the
# shared copy in gemmini-rocc-tests/include for whichever config was built last.
# scripts/build_sim.sh snapshots the header per config; this script builds
# against that snapshot in a private tree, never touching Chipyard's shared file.
#
# Output (under $CHIPYARD_DIR/.variants/<CONFIG>/):
#   lib/libgemmini.so      point Spike at it with LD_LIBRARY_PATH
#   rocc-tests/build/bareMetalC/*-baremetal
#
# Usage: scripts/gemmini_sw.sh CONFIG        e.g. Gemmini8x8RocketConfig

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG=${1:?usage: $0 CONFIG}

set +u
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/chipyard_env.sh" > /dev/null
set -u

GEMMINI=$CHIPYARD_DIR/generators/gemmini
VARIANT=$CHIPYARD_DIR/.variants/$CONFIG
HEADER=$VARIANT/gemmini_params.h
[[ -f $HEADER ]] || { echo "no $HEADER; run scripts/build_sim.sh $CONFIG first" >&2; exit 1; }

# libgemmini: gemmini.h includes "gemmini_params.h" from its own directory, so
# build from a private copy of the sources with this variant's header.
mkdir -p "$VARIANT/libgemmini" "$VARIANT/lib"
cp "$GEMMINI/software/libgemmini/gemmini.cc" "$GEMMINI/software/libgemmini/gemmini.h" "$VARIANT/libgemmini/"
cp "$HEADER" "$VARIANT/libgemmini/gemmini_params.h"
g++ -L "$RISCV/lib" -Wl,-rpath,"$RISCV/lib" -shared -o "$VARIANT/lib/libgemmini.so" \
    -std=c++17 -I "$RISCV/include" -fPIC -O3 "$VARIANT/libgemmini/gemmini.cc"

# Tests: same idea, a private copy of just what bareMetalC needs.
SRC=$GEMMINI/software/gemmini-rocc-tests
DST=$VARIANT/rocc-tests
rm -rf "$DST"
mkdir -p "$DST"
tar -C "$SRC" -cf - bareMetalC include riscv-tests rocc-software Makefile.in Makefrag configure configure.ac \
    | tar -C "$DST" -xf -
cp "$HEADER" "$DST/include/gemmini_params.h"

# Our own programs (sw/profile/*.c) are built the same way as the upstream tests:
# drop the source into bareMetalC and add it to the Makefile's test list.
for src in "$REPO_ROOT"/sw/profile/*.c; do
    [[ -e $src ]] || continue
    cp "$src" "$DST/bareMetalC/"
    entry=$(mktemp)
    printf '\t%s \\\n' "$(basename "$src" .c)" > "$entry"
    sed -i "/^tests = \\\\\$/r $entry" "$DST/bareMetalC/Makefile"
    rm -f "$entry"
done

mkdir "$DST/build"
(cd "$DST/build" && ../configure > configure.log 2>&1)
make -C "$DST/build" -j"$(nproc)" BAREMETAL_ONLY=1 bareMetalC > "$DST/build/make.log" 2>&1

echo "$CONFIG: DIM=$(awk '/define DIM /{print $3}' "$HEADER"), $(ls "$DST"/build/bareMetalC/*-baremetal | wc -l) tests, $VARIANT/lib/libgemmini.so"
