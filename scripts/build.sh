#!/usr/bin/env bash
# build.sh — Compile all chess simulation binaries on CARC.
# Run from the repo root (where Makefile lives).
# Usage: bash scripts/build.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${SCRIPT_DIR}/.."   # repo root

module purge
module load gcc

cd "${PROJ_DIR}"

# Log build environment
mkdir -p scripts/logs
{
    echo "Build timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Hostname: $(hostname)"
    echo "GCC version: $(g++ --version | head -1)"
    echo "Loaded modules: $(module list 2>&1 | tr '\n' ' ')"
    echo "CXXFLAGS: -std=c++17 -O3 -DNDEBUG"
    echo "OpenMP flags: -fopenmp"
} > scripts/build_manifest.txt

echo "Build environment logged to scripts/build_manifest.txt"
cat scripts/build_manifest.txt
echo ""

SERIAL_TARGETS="sim_serial_100k sim_serial_1m sim_serial_10m sim_serial_100m"
OPENMP_TARGETS="sim_openmp_100k sim_openmp_1m sim_openmp_10m sim_openmp_100m"

echo "Building serial targets..."
for target in ${SERIAL_TARGETS}; do
    echo "  make ${target}"
    make "${target}"
done

echo "Building OpenMP targets..."
for target in ${OPENMP_TARGETS}; do
    echo "  make ${target}"
    make "${target}"
done

echo ""
echo "Verifying binaries..."
ALL_OK=true
for target in ${SERIAL_TARGETS} ${OPENMP_TARGETS}; do
    if [[ -x "${target}" ]]; then
        echo "  [OK] ${target}"
    else
        echo "  [MISSING] ${target}"
        ALL_OK=false
    fi
done

if [[ "${ALL_OK}" == "true" ]]; then
    echo ""
    echo "All 8 binaries built successfully."
    echo "Next step: bash scripts/submit_all.sh"
else
    echo "ERROR: Some binaries missing." >&2
    exit 1
fi
