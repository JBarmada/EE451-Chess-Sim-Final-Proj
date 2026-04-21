#!/usr/bin/env bash
# submit_all_runs.sh — Submit the full chess simulation benchmark suite to CARC.
#
# Jobs submitted:
#   [1] run_serial.job         — serial baseline, sizes 1k–100m  (~2.5hr)
#   [2] run_openmp_scaling.job — 10M games × threads 1,2,4,8,16,32,64  (~1.5hr, exclusive 64-CPU)
#   [3] run_openmp_sizes.job   — all sizes 1k–1b × 64 threads  (~2hr, exclusive 64-CPU)
#   [4] run_serial_1b.job      — 1B serial baseline  (~16hr)  [opt-in: --include-1b]
#   [5] run_analyze.job        — analysis, afterok all compute jobs above
#
# All jobs share a RUN_ID timestamp so results land in the same dated folder.
# Results:
#   results/cpu_serial/<RUN_ID>/{sim,csv,analysis}/
#   results/cpu_openmp/<RUN_ID>/{sim,csv,analysis}/
#
# Usage:
#   bash scripts/submit_all_runs.sh            # all jobs except 1B serial
#   bash scripts/submit_all_runs.sh --include-1b  # also submit 1B serial (~16hr)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${SCRIPT_DIR}/.."   # repo root

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
INCLUDE_1B=false
for arg in "$@"; do
    case "${arg}" in
        --include-1b) INCLUDE_1B=true ;;
        *) echo "Unknown argument: ${arg}"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate required binaries
# ---------------------------------------------------------------------------
echo "Validating binaries..."
REQUIRED="sim_serial_1k  sim_serial_10k  sim_serial_100k  sim_serial_1m  sim_serial_10m  sim_serial_100m
          sim_openmp_1k  sim_openmp_10k  sim_openmp_100k  sim_openmp_1m  sim_openmp_10m  sim_openmp_100m  sim_openmp_1b"
if [[ "${INCLUDE_1B}" == "true" ]]; then
    REQUIRED="${REQUIRED} sim_serial_1b"
fi

MISSING=false
for bin in ${REQUIRED}; do
    if [[ -x "${PROJ_DIR}/${bin}" ]]; then
        echo "  [OK] ${bin}"
    else
        echo "  [MISSING] ${bin}"
        MISSING=true
    fi
done

if [[ "${MISSING}" == "true" ]]; then
    echo ""
    echo "ERROR: Missing binaries. Run first:"
    echo "  module load gcc && bash scripts/build.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
mkdir -p "${SCRIPT_DIR}/logs"

# Shared timestamp — all jobs in this batch write under this RUN_ID
RUN_ID=$(date +%Y-%m-%d_%H%M%S)

echo ""
echo "========================================================"
echo " Chess Simulation Benchmark Suite"
echo " RUN_ID:  ${RUN_ID}"
echo " 1B serial included: ${INCLUDE_1B}"
echo "========================================================"
echo ""

# Submit from repo root so SLURM_SUBMIT_DIR resolves to repo root in all jobs
cd "${PROJ_DIR}"

# ---------------------------------------------------------------------------
# Submit compute jobs (run in parallel — no dependencies between them)
# ---------------------------------------------------------------------------
JID_SERIAL=$(sbatch --parsable \
    --export=ALL,RUN_ID="${RUN_ID}" \
    scripts/run_serial.job)
echo "  [${JID_SERIAL}]  run_serial.job         sizes: 1k–100m, 1 thread, ~2.5hr"

JID_OMP_SCALING=$(sbatch --parsable \
    --export=ALL,RUN_ID="${RUN_ID}" \
    scripts/run_openmp_scaling.job)
echo "  [${JID_OMP_SCALING}]  run_openmp_scaling.job 10M × threads 1,2,4,8,16,32,64, ~1.5hr"

JID_OMP_SIZES=$(sbatch --parsable \
    --export=ALL,RUN_ID="${RUN_ID}" \
    scripts/run_openmp_sizes.job)
echo "  [${JID_OMP_SIZES}]  run_openmp_sizes.job   sizes 1k–1b × 64 threads, ~2hr"

COMPUTE_DEPS="${JID_SERIAL}:${JID_OMP_SCALING}:${JID_OMP_SIZES}"

if [[ "${INCLUDE_1B}" == "true" ]]; then
    JID_SERIAL_1B=$(sbatch --parsable \
        --export=ALL,RUN_ID="${RUN_ID}" \
        scripts/run_serial_1b.job)
    echo "  [${JID_SERIAL_1B}]  run_serial_1b.job      1B games serial, ~16hr"
    COMPUTE_DEPS="${COMPUTE_DEPS}:${JID_SERIAL_1B}"
fi

# ---------------------------------------------------------------------------
# Analysis — afterok all compute jobs
# ---------------------------------------------------------------------------
JID_ANALYZE=$(sbatch --parsable \
    --dependency=afterok:${COMPUTE_DEPS} \
    --export=ALL,RUN_ID="${RUN_ID}" \
    scripts/run_analyze.job)
echo "  [${JID_ANALYZE}]  run_analyze.job        afterok all above, ~15min"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================================"
echo " All jobs submitted."
echo ""
echo " RUN_ID:  ${RUN_ID}"
echo " Thread counts (scaling study): 1, 2, 4, 8, 16, 32, 64"
echo " Problem sizes: 1k, 10k, 100k, 1m, 10m, 100m, 1b (OpenMP)"
echo "               1k, 10k, 100k, 1m, 10m, 100m (Serial)"
if [[ "${INCLUDE_1B}" == "true" ]]; then
    echo "               + 1b (Serial, ~16hr)"
fi
echo ""
echo " Monitor:  squeue -u \$USER --format='%.10i %.25j %.8T %.10M %.12l'"
echo " Cancel:   scancel ${JID_SERIAL} ${JID_OMP_SCALING} ${JID_OMP_SIZES} ${JID_ANALYZE}"
echo ""
echo " Results (after completion):"
echo "   results/cpu_serial/${RUN_ID}/sim/hardware.txt   <- node specs"
echo "   results/cpu_serial/${RUN_ID}/sim/               <- summary.txt per size"
echo "   results/cpu_openmp/${RUN_ID}/sim/               <- summary.txt per size+thread"
echo "   results/cpu_serial/${RUN_ID}/csv/               <- all metric CSVs"
echo "   results/cpu_serial/${RUN_ID}/analysis/report.md <- full analysis report"
echo "========================================================"
