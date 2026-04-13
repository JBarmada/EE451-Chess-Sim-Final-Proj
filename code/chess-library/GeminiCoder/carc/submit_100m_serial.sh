#!/usr/bin/env bash
# submit_100m_serial.sh — Submit just the 100M serial run + analysis.
# Run from the carc/ directory:
#   cd chess-library/GeminiCoder/carc/
#   bash submit_100m_serial.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${SCRIPT_DIR}/.."

if [[ ! -x "${PROJ_DIR}/sim100m_serial" ]]; then
    echo "ERROR: sim100m_serial not found. Run build.sh first." >&2
    exit 1
fi

mkdir -p "${SCRIPT_DIR}/logs" "${SCRIPT_DIR}/results"

cd "${SCRIPT_DIR}"

JID_100M=$(sbatch --parsable run_100m_serial.job)
echo "  [${JID_100M}] run_100m_serial.job  (4hr, 1 CPU)"

JID_ANALYZE=$(sbatch --parsable \
    --dependency=afterok:${JID_100M} \
    run_analyze.job)
echo "  [${JID_ANALYZE}] run_analyze.job     (15min, depends on above)"

echo ""
echo "Monitor: squeue -u \$USER"
echo "Results: ${SCRIPT_DIR}/results/report.md  (after analysis completes)"
