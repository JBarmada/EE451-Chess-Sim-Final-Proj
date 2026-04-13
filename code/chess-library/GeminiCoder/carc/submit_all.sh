#!/usr/bin/env bash
# submit_all.sh — Submit all CARC chess simulation jobs in dependency order.
#
# Prerequisites:
#   1. Run build.sh first to compile all binaries.
#   2. Call this script from the carc/ directory (or GeminiCoder/).
#
# Usage:
#   cd chess-library/GeminiCoder/carc/
#   bash submit_all.sh
#
# Job submission order:
#   [1] run_serial.job          — serial baseline (all 4 sizes)
#   [2] run_openmp_scaling.job  — thread scaling study (10M games)
#   [3] run_openmp_sizes.job    — problem-size study (32 threads)
#   [4] run_analyze.job         — analysis (depends on 1,2,3 completing OK)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${SCRIPT_DIR}/.."   # GeminiCoder/

# --- Validate all binaries are present ---
echo "Validating binaries in ${PROJ_DIR}..."
MISSING=false
for bin in sim100k_serial sim1m_serial sim10m_serial sim100m_serial \
           sim100k_openmp sim1m_openmp sim10m_openmp sim100m_openmp; do
    if [[ -x "${PROJ_DIR}/${bin}" ]]; then
        echo "  [OK] ${bin}"
    else
        echo "  [MISSING] ${bin}"
        MISSING=true
    fi
done

if [[ "${MISSING}" == "true" ]]; then
    echo ""
    echo "ERROR: Some binaries are missing. Run build.sh first:" >&2
    echo "  module load gcc/12.3.0 && bash carc/build.sh" >&2
    exit 1
fi

echo ""

# --- Create log and result directories ---
mkdir -p "${SCRIPT_DIR}/logs"
mkdir -p "${SCRIPT_DIR}/results"

# --- Submit jobs ---
# All job scripts use SLURM_SUBMIT_DIR to locate the project root,
# so we must submit from carc/ so that SLURM_SUBMIT_DIR == carc/.
cd "${SCRIPT_DIR}"

echo "Submitting jobs from: $(pwd)"
echo ""

JID_SERIAL=$(sbatch --parsable run_serial.job)
echo "  [${JID_SERIAL}] run_serial.job        (4hr, main, 1 CPU)"

JID_OMP_SCALING=$(sbatch --parsable run_openmp_scaling.job)
echo "  [${JID_OMP_SCALING}] run_openmp_scaling.job (1hr, epyc-64, 32 CPUs exclusive)"

JID_OMP_SIZES=$(sbatch --parsable run_openmp_sizes.job)
echo "  [${JID_OMP_SIZES}] run_openmp_sizes.job   (30min, epyc-64, 32 CPUs exclusive)"

JID_ANALYZE=$(sbatch --parsable \
    --dependency=afterok:${JID_SERIAL}:${JID_OMP_SCALING}:${JID_OMP_SIZES} \
    run_analyze.job)
echo "  [${JID_ANALYZE}] run_analyze.job       (15min, main, 1 CPU — depends on above)"

echo ""
echo "============================================================"
echo "All jobs submitted successfully."
echo ""
echo "Job IDs:"
echo "  Serial baseline:    ${JID_SERIAL}"
echo "  OMP thread scaling: ${JID_OMP_SCALING}"
echo "  OMP size study:     ${JID_OMP_SIZES}"
echo "  Analysis:           ${JID_ANALYZE} (runs after all three complete)"
echo ""
echo "Monitor status:  squeue -u \$USER --format='%.10i %.20j %.8T %.10M %.12l'"
echo "Cancel all:      scancel ${JID_SERIAL} ${JID_OMP_SCALING} ${JID_OMP_SIZES} ${JID_ANALYZE}"
echo ""
echo "Logs:    ${SCRIPT_DIR}/logs/"
echo "Results: ${PROJ_DIR}/results/  and  ${SCRIPT_DIR}/results/"
echo "Report:  ${SCRIPT_DIR}/results/report.md  (available after analysis job)"
echo "============================================================"
