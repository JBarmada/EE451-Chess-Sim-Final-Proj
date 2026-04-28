#!/usr/bin/env bash
# capture_hardware.sh — Capture full hardware + environment profile for research reproducibility.
# Usage: bash scripts/capture_hardware.sh <output_file>
#
# Captures everything needed for quantitative parallel performance analysis:
#   CPU model, core/thread counts, frequency, cache hierarchy, memory, NUMA,
#   SLURM allocation, compiler, OpenMP version, GPU (if present).

set -uo pipefail  # no -e: hardware capture is informational; a failed query must not kill the job

OUTPUT="${1:?Usage: capture_hardware.sh <output_file>}"
mkdir -p "$(dirname "${OUTPUT}")"

{
echo "========================================================"
echo "  HARDWARE & ENVIRONMENT PROFILE"
echo "  Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  Host:      $(hostname -f 2>/dev/null || hostname)"
echo "========================================================"
echo ""

# ------------------------------------------------------------------
echo "=== SYSTEM ==="
uname -a
echo ""

# ------------------------------------------------------------------
echo "=== CPU SUMMARY (lscpu) ==="
lscpu
echo ""

# ------------------------------------------------------------------
echo "=== CPU EXTENDED — per-logical-CPU topology ==="
lscpu --extended 2>/dev/null || echo "(lscpu --extended not available)"
echo ""

# ------------------------------------------------------------------
echo "=== CPU FLAGS (instruction sets) ==="
# Relevant for chess move-gen performance: AVX2, AVX-512, BMI2, POPCNT
grep -m1 "^flags" /proc/cpuinfo 2>/dev/null || echo "(unavailable)"
echo ""

# ------------------------------------------------------------------
echo "=== CPU FREQUENCY ==="
CPU0_FREQ="/sys/devices/system/cpu/cpu0/cpufreq"
for attr in cpuinfo_min_freq cpuinfo_max_freq scaling_cur_freq \
            scaling_min_freq scaling_max_freq scaling_governor; do
    if [[ -f "${CPU0_FREQ}/${attr}" ]]; then
        val=$(cat "${CPU0_FREQ}/${attr}")
        # Convert kHz to GHz for freq values
        if [[ "${attr}" == *freq* ]] && [[ "${val}" =~ ^[0-9]+$ ]]; then
            ghz=$(echo "scale=3; ${val}/1000000" | bc 2>/dev/null || echo "${val} kHz")
            echo "  ${attr}: ${val} kHz  (${ghz} GHz)"
        else
            echo "  ${attr}: ${val}"
        fi
    fi
done
echo ""

# ------------------------------------------------------------------
echo "=== CACHE HIERARCHY ==="
for idx_dir in /sys/devices/system/cpu/cpu0/cache/index*/; do
    [[ -d "${idx_dir}" ]] || continue
    echo "  Cache $(basename ${idx_dir}):"
    for attr in level type size coherency_line_size ways_of_associativity number_of_sets; do
        [[ -f "${idx_dir}${attr}" ]] && echo "    ${attr}: $(cat ${idx_dir}${attr})"
    done
done
echo ""

# ------------------------------------------------------------------
echo "=== SIMULTANEOUS MULTITHREADING (HT/SMT) ==="
ht=$(lscpu | awk '/^Thread\(s\) per core:/ {print $NF}')
cores=$(lscpu | awk '/^Core\(s\) per socket:/ {print $NF}')
sockets=$(lscpu | awk '/^Socket\(s\):/ {print $NF}')
logical=$(lscpu | awk '/^CPU\(s\):/ {print $NF}')
echo "  Sockets:              ${sockets}"
echo "  Physical cores/socket:${cores}"
echo "  Physical cores total: $((sockets * cores))"
echo "  Threads/core (SMT):   ${ht}"
echo "  Logical CPUs total:   ${logical}"
echo ""

# ------------------------------------------------------------------
echo "=== MEMORY ==="
free -h
echo ""
echo "--- /proc/meminfo ---"
cat /proc/meminfo
echo ""

# ------------------------------------------------------------------
echo "=== NUMA TOPOLOGY ==="
numactl --hardware 2>/dev/null || echo "(numactl not available)"
echo ""

# ------------------------------------------------------------------
echo "=== FULL /proc/cpuinfo ==="
cat /proc/cpuinfo
echo ""

# ------------------------------------------------------------------
echo "=== SLURM JOB INFO ==="
echo "  SLURM_JOB_ID:          ${SLURM_JOB_ID:-N/A}"
echo "  SLURM_JOB_NAME:        ${SLURM_JOB_NAME:-N/A}"
echo "  SLURM_JOB_PARTITION:   ${SLURM_JOB_PARTITION:-N/A}"
echo "  SLURM_JOB_NODELIST:    ${SLURM_JOB_NODELIST:-N/A}"
echo "  SLURM_NTASKS:          ${SLURM_NTASKS:-N/A}"
echo "  SLURM_CPUS_PER_TASK:   ${SLURM_CPUS_PER_TASK:-N/A}"
echo "  SLURM_MEM_PER_NODE:    ${SLURM_MEM_PER_NODE:-N/A}"
echo "  SLURM_JOB_NUM_NODES:   ${SLURM_JOB_NUM_NODES:-N/A}"
echo ""
echo "--- scontrol show job ---"
scontrol show job "${SLURM_JOB_ID:-}" 2>/dev/null || echo "(not in SLURM environment)"
echo ""
echo "--- scontrol show node ---"
scontrol show node "${SLURM_JOB_NODELIST:-$(hostname)}" 2>/dev/null || echo "(unavailable)"
echo ""

# ------------------------------------------------------------------
echo "=== COMPILER ==="
g++ --version
echo "Build flags: -std=c++17 -O3 -DNDEBUG"
echo ""

# ------------------------------------------------------------------
echo "=== OpenMP ==="
echo "  OMP_NUM_THREADS:   ${OMP_NUM_THREADS:-not set}"
echo "  OMP_PROC_BIND:     ${OMP_PROC_BIND:-not set}"
echo "  OMP_PLACES:        ${OMP_PLACES:-not set}"
echo "  GOMP_CPU_AFFINITY: ${GOMP_CPU_AFFINITY:-not set}"

# Detect _OPENMP version macro
OMP_VER_SRC=$(mktemp /tmp/omp_ver_XXXX.cpp)
cat > "${OMP_VER_SRC}" <<'OMPSRC'
#include <cstdio>
#include <omp.h>
int main() {
    printf("  _OPENMP macro:     %d\n", _OPENMP);
    printf("  omp_get_max_threads(): %d\n", omp_get_max_threads());
    printf("  omp_get_num_procs():   %d\n", omp_get_num_procs());
    return 0;
}
OMPSRC
g++ -fopenmp -O0 "${OMP_VER_SRC}" -o /tmp/omp_ver_check 2>/dev/null \
    && /tmp/omp_ver_check \
    || echo "  (OpenMP version check failed)"
rm -f "${OMP_VER_SRC}" /tmp/omp_ver_check
echo ""

# ------------------------------------------------------------------
echo "=== LOADED MODULES ==="
module list 2>&1 || echo "(module system not available)"
echo ""

# ------------------------------------------------------------------
echo "=== GPU ==="
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi
    echo ""
    echo "--- GPU properties (csv) ---"
    nvidia-smi \
        --query-gpu=index,name,driver_version,cuda_version,\
memory.total,clocks.max.sm,clocks.max.memory,clocks.max.graphics,\
pcie.link.width.max,pcie.link.gen.max,power.limit \
        --format=csv 2>/dev/null || true
else
    echo "nvidia-smi not available (no GPU module loaded or no GPU on node)"
fi
echo ""

# ------------------------------------------------------------------
echo "=== PROCESS BINDING ==="
taskset -cp $$ 2>/dev/null || echo "(taskset not available)"
echo ""

# ------------------------------------------------------------------
echo "=== ENVIRONMENT VARIABLES ==="
env | sort
echo ""

echo "========================================================"
echo "  END OF HARDWARE PROFILE"
echo "  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "========================================================"
} > "${OUTPUT}"

echo "[hardware] Saved to ${OUTPUT}"
