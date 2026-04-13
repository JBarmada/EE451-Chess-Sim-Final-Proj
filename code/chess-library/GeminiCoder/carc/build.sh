#!/usr/bin/env bash
# build.sh — Compile all chess simulation binaries on CARC.
# Run this from the GeminiCoder/ directory (or let it cd there automatically).
# Usage: bash carc/build.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${SCRIPT_DIR}/.."   # chess-library/GeminiCoder/

# --- Module load ---
module purge
module load gcc

cd "${PROJ_DIR}"

# --- Log build environment ---
mkdir -p carc
{
    echo "Build timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Hostname: $(hostname)"
    echo "GCC version: $(g++ --version | head -1)"
    echo "Loaded modules: $(module list 2>&1 | tr '\n' ' ')"
    echo "CXXFLAGS: -std=c++17 -O3 -DNDEBUG"
    echo "OpenMP flags: -fopenmp"
} > carc/build_manifest.txt

echo "Build environment logged to carc/build_manifest.txt"
cat carc/build_manifest.txt
echo ""

# --- Build targets (skip 1b — wall time too long) ---
SERIAL_TARGETS="sim100k_serial sim1m_serial sim10m_serial sim100m_serial"
OPENMP_TARGETS="sim100k_openmp sim1m_openmp sim10m_openmp sim100m_openmp"

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

# --- Verify ---
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
    echo "Next step: cd carc/ && bash submit_all.sh"
else
    echo ""
    echo "ERROR: Some binaries are missing. Check make output above." >&2
    exit 1
fi
