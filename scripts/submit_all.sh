#!/usr/bin/env bash
# submit_all.sh — Submit all CARC jobs with a shared RUN_ID timestamp.
# Usage: bash scripts/submit_all.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${SCRIPT_DIR}/.."

echo "Validating binaries in ${PROJ_DIR}..."
MISSING=false
for bin in sim_serial_100k sim_serial_1m sim_serial_10m sim_serial_100m \
           sim_openmp_100k sim_openmp_1m sim_openmp_10m sim_openmp_100m; do
    if [[ -x "${PROJ_DIR}/${bin}" ]]; then
        echo "  [OK] ${bin}"
    else
        echo "  [MISSING] ${bin}"
        MISSING=true
    fi
done

if [[ "${MISSING}" == "true" ]]; then
    echo "ERROR: Run bash scripts/build.sh first." >&2
    exit 1
fi

mkdir -p "${SCRIPT_DIR}/logs"

# Shared run ID for all jobs in this batch
RUN_ID=$(date +%Y-%m-%d_%H%M%S)
echo ""
echo "RUN_ID: ${RUN_ID}"
echo ""

# Submit from repo root so SLURM_SUBMIT_DIR = repo root
cd "${PROJ_DIR}"

JID_SERIAL=$(sbatch --parsable --export=ALL,RUN_ID="${RUN_ID}" scripts/run_serial.job)
echo "  [${JID_SERIAL}] run_serial.job"

JID_OMP_SCALING=$(sbatch --parsable --export=ALL,RUN_ID="${RUN_ID}" scripts/run_openmp_scaling.job)
echo "  [${JID_OMP_SCALING}] run_openmp_scaling.job"

JID_OMP_SIZES=$(sbatch --parsable --export=ALL,RUN_ID="${RUN_ID}" scripts/run_openmp_sizes.job)
echo "  [${JID_OMP_SIZES}] run_openmp_sizes.job"

JID_ANALYZE=$(sbatch --parsable \
    --dependency=afterok:${JID_SERIAL}:${JID_OMP_SCALING}:${JID_OMP_SIZES} \
    --export=ALL,RUN_ID="${RUN_ID}" \
    scripts/run_analyze.job)
echo "  [${JID_ANALYZE}] run_analyze.job (afterok)"

echo ""
echo "RUN_ID: ${RUN_ID}"
echo "Monitor: squeue -u \$USER"
echo "Results: results/cpu_serial/${RUN_ID}/ and results/cpu_openmp/${RUN_ID}/"
