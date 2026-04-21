#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${SCRIPT_DIR}/.."

if [[ ! -x "${PROJ_DIR}/sim_serial_100m" ]]; then
    echo "ERROR: sim_serial_100m not found. Run build.sh first." >&2
    exit 1
fi

mkdir -p "${SCRIPT_DIR}/logs"

RUN_ID=$(date +%Y-%m-%d_%H%M%S)
echo "RUN_ID: ${RUN_ID}"

cd "${PROJ_DIR}"

JID=$(sbatch --parsable --export=ALL,RUN_ID="${RUN_ID}" scripts/run_100m_serial.job)
echo "  [${JID}] run_100m_serial.job"

JID_ANALYZE=$(sbatch --parsable \
    --dependency=afterok:${JID} \
    --export=ALL,RUN_ID="${RUN_ID}" \
    scripts/run_analyze.job)
echo "  [${JID_ANALYZE}] run_analyze.job (afterok)"

echo ""
echo "Monitor: squeue -u \$USER"
echo "Results: results/cpu_serial/${RUN_ID}/"
