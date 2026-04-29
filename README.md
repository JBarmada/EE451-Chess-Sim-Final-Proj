# Parallel Checkmate

A high-performance Monte Carlo chess simulator. Serial CPU, multi-threaded OpenMP, and CUDA GPU implementations, benchmarked on the USC CARC Discovery cluster.

**Authors:** Jad Barmada · Eli Fast · Joyce Ng · Lian Fouse
**Course:** EE 451 — Parallel and Distributed Computation, USC, Spring 2026

---

## TL;DR for graders

```bash
git clone https://github.com/JBarmada/Parallel-Checkmate.git
cd Parallel-Checkmate
```

Then jump to one of:

| Goal                                  | Section |
|---------------------------------------|---------|
| Run a 1-minute smoke test (any host)  | [Quick smoke test](#1-quick-smoke-test-1-minute) |
| Reproduce the full CPU study on CARC  | [CPU reproduction](#2-cpu-reproduction-on-carc) |
| Just regenerate the report from existing CSVs | [Re-analyze](#3-re-analyze-existing-results) |
| See the headline numbers              | [Headline results](#headline-results) |

---

## Headline results

| Metric                                | Value                |
|---------------------------------------|----------------------|
| Best OpenMP throughput (64t, 1B games)| **1.00 M games/sec** |
| Best GPU throughput (RTX 3090 Ti)     | **920 K games/sec**  |
| Serial 1B baseline                    | 50,837 s (14.1 hrs)  |
| Best speedup (64 threads, 1B games)   | **50.88×**           |
| Parallel efficiency (64t, 10M)        | **97.78%**           |
| Empirical Amdahl `s` (averaged)       | ~0.95%               |
| Checkmate rate vs Labelle's 15.55%    | 15.31% ✓             |

Full data: [`results/cpu_serial/2026-04-20_213206/`](results/cpu_serial/2026-04-20_213206/).
Full report: [`results/cpu_serial/2026-04-20_213206/analysis/report.md`](results/cpu_serial/2026-04-20_213206/analysis/report.md).

---

## Repository layout

```
Parallel-Checkmate/
├── README.md                 ← you are here
├── Makefile                  Builds 14 CPU binaries (7 sizes × 2 variants)
├── CPU_Serial/
│   ├── serial.cpp            Serial implementation
│   └── chess.hpp             Disservin chess-library v0.9.4 (header-only)
├── CPU_OpenMP/
│   ├── openMP.cpp            OpenMP implementation
│   └── chess.hpp
├── GPU_CUDA/                 CUDA implementation
│   ├── main.cu               Kernel entry + host driver
│   ├── board.cuh / game.cuh / movegen.cuh / recording.cuh
│   ├── test_*.cu             Per-piece movegen unit tests
│   ├── Makefile              `make -C GPU_CUDA all` builds build/chess
│   └── job.sl                SLURM job for V100
├── scripts/
│   ├── build.sh              Compile all 14 CPU binaries
│   ├── submit_all_runs.sh    Submit the full CPU benchmark suite
│   ├── run_serial.job        SLURM: serial 1k–100m (~2 hr)
│   ├── run_serial_1b.job     SLURM: serial 1B  (~14 hr)
│   ├── run_openmp_scaling.job   SLURM: 10M × {1,2,4,8,16,32,64} threads
│   ├── run_openmp_sizes.job  SLURM: all sizes × 64 threads
│   ├── run_analyze.job       SLURM: post-processing
│   ├── analyze_results.py    Aggregates raw summaries → CSVs + report
│   └── capture_hardware.sh   Per-run hardware profile capture
└── results/
    ├── cpu_serial/<run_id>/{sim,csv,analysis}/
    └── cpu_openmp/<run_id>/{sim,csv,analysis}/
```

---

## Software requirements

| Tool      | Version                  | Where it's needed                  |
|-----------|--------------------------|------------------------------------|
| GCC / g++ | ≥ 9 (C++17 + OpenMP)     | CPU build (`module load gcc` on CARC) |
| NVCC      | CUDA 11+, `sm_70`        | GPU build (`module load cuda`) |
| Python    | ≥ 3.9, **stdlib only**   | Analysis script (`module load python`) |
| SLURM     | any                      | CARC job submission |

No `pip install` and no external chess library — `chess.hpp` is vendored in-tree.

---

## 1. Quick smoke test (1 minute)

Verifies the toolchain works. Compiles one OpenMP binary and runs 100k games on whatever cores are available locally.

```bash
make sim_openmp_100k
OMP_NUM_THREADS=4 ./sim_openmp_100k
```

**Expected output** ends with a summary like:

```
Execution Time: ~0.15 seconds
Throughput:     ~700,000 games/sec
White Wins:     ~7.7%
Black Wins:     ~7.7%
CHECKMATE:      ~15.3%
```

Detailed stats land in `results/100k_openmp/4/summary.txt`. If you see this, the build works.

---

## 2. CPU reproduction on CARC

This is the canonical reproduction path. Five steps, ~2.5 hours wall time (or +14 hr if you also want the 1B serial baseline).

### Step 2.1 — Build all CPU binaries

```bash
module load gcc
bash scripts/build.sh
```

This writes a build manifest to `scripts/build_manifest.txt` and produces 14 binaries (`sim_serial_{1k…1b}`, `sim_openmp_{1k…1b}`).

### Step 2.2 — Submit the benchmark suite

```bash
bash scripts/submit_all_runs.sh                # ~2.5 hours total
# or, including the 14-hour serial 1B baseline:
bash scripts/submit_all_runs.sh --include-1b
```

Submits 4 SLURM jobs in parallel and a 5th analysis job that depends on them via `--dependency=afterok`:

| Job                    | Wall   | What it does                                |
|------------------------|--------|---------------------------------------------|
| `run_serial.job`       | 2.5 hr | Serial 1k → 100M baselines                  |
| `run_serial_1b.job`    | 14 hr  | Serial 1B baseline (opt-in via `--include-1b`) |
| `run_openmp_scaling.job` | 1.5 hr | 10M games × {1,2,4,8,16,32,64} threads (exclusive node) |
| `run_openmp_sizes.job` | 2 hr   | All sizes × 64 threads (exclusive node)     |
| `run_analyze.job`      | 15 min | Aggregates everything → CSVs + Markdown report |

All 5 jobs share a single `RUN_ID=$(date +%Y-%m-%d_%H%M%S)` so their outputs land in the same dated folder.

### Step 2.3 — Monitor

```bash
squeue -u $USER --format='%.10i %.25j %.8T %.10M %.12l'
```

### Step 2.4 — Inspect the results

After the analysis job completes (~2.5 hr total wall, less if you have priority):

```
results/cpu_serial/<RUN_ID>/sim/        ← per-size raw summary.txt files + hardware.txt
results/cpu_openmp/<RUN_ID>/sim/        ← per-(size,threads) raw summary.txt files
results/cpu_serial/<RUN_ID>/csv/        ← 8 aggregated CSVs
results/cpu_serial/<RUN_ID>/analysis/report.md  ← human-readable report
```

The report contains a hardware block, the throughput table, the speedup/efficiency table, the size-scaling table, the Amdahl analysis, and a statistical-accuracy table.

### Step 2.5 — Verify

Quick sanity checks the grader can run on the report:

| Check                                         | Expected               |
|-----------------------------------------------|------------------------|
| Throughput at 64 threads, 10M games           | ≈ 1.0 M games/sec      |
| Speedup at 64 threads, 10M games              | ≈ 62×                  |
| Parallel efficiency at all thread counts      | 96–98%                 |
| Checkmate rate at 1B games                    | 15.31% (Labelle: 15.55%) |
| White/Black win rate symmetry                 | 7.66% / 7.65% within 0.1 pp |

---

## 3. Re-analyze existing results

If raw `summary.txt` files already exist (e.g. for the committed `2026-04-20_213206` run), regenerate the CSVs and report locally without re-running any simulations:

```bash
python3 scripts/analyze_results.py \
  --serial-sim-dir  results/cpu_serial/2026-04-20_213206/sim \
  --openmp-sim-dir  results/cpu_openmp/2026-04-20_213206/sim \
  --csv-dir         results/cpu_serial/2026-04-20_213206/csv \
  --analysis-dir    results/cpu_serial/2026-04-20_213206/analysis \
  --build-manifest  scripts/build_manifest.txt \
  --run-id          2026-04-20_213206
```

Standard library only — no `pip install`, no external dependencies.

---

## How the code works

### CPU: game count is compile-time, thread count is runtime

Each binary is compiled with a fixed `-DNUM_GAMES=N` (`Makefile` produces 7 sizes per variant: 1k, 10k, 100k, 1m, 10m, 100m, 1b). This lets the compiler unroll/optimise more aggressively than a runtime parameter would.

The OpenMP binary calls `omp_get_max_threads()`, which respects `OMP_NUM_THREADS`. So a single binary handles every thread count — no recompilation needed. Output paths automatically include the thread count: `results/<size>_openmp/<threads>/summary.txt`.

### GPU: 1 thread = 1 game; templated variants

Each CUDA thread plays one complete game from initial position to termination. 256 threads per block; grid sizes to cover the requested game count. Per-thread `curandState` ensures statistically independent random streams. No on-device reduction — each thread writes its result into `d_results[global_id]`, and the host scans the array after `cudaMemcpy`. Sliding-attack and legality-filter algorithm choices are compile-time template parameters; the host picks one of the four pre-compiled variants at launch via the CLI flags above.

### Output redirection

Both CPU binaries respect `CHESS_RUN_DIR` (env var). The SLURM jobs set this to a dated run folder so results don't overwrite each other across runs. Without the env var, output lands in `./results/...` (relative to CWD).

### Memory: O(1)

The accumulators (`gameLengthSum`, win/draw counters, etc.) are constant-size scalars — no per-game storage. This was a fix from an earlier version that pre-allocated a `std::vector<int>` of length `NUM_GAMES`, which OOMed at 1B games.

---

## Reproducibility

- **RNG:** Per-thread `std::mt19937` (CPU) / `curandState` (GPU), seeded from `std::random_device` / `time(nullptr)`. Runs are **not** bit-for-bit reproducible by design — the study targets statistical convergence at 10M+ games.
- **Hardware capture:** Every SLURM run records `lscpu`, cache hierarchy, NUMA topology, frequency governor, SLURM allocation details, compiler version, and OpenMP runtime info to `hardware.txt` alongside the simulation outputs.
- **Build manifest:** `scripts/build.sh` writes timestamp, hostname, GCC version, modules loaded, and exact compile flags to `scripts/build_manifest.txt`. The analysis report quotes this verbatim.
- **CARC modules:** Unversioned (`module load gcc`, `module load cuda`); the manifest records the actual versions resolved at build time. Current defaults: GCC 13.3.0 for CPU, CUDA via the `nvhpc` module for GPU.

---

## Citing

> Barmada, J., Fast, E., Ng, J., & Fouse, L. (2026). *Parallel Checkmate: A Performance Study of Monte Carlo Chess Simulation on USC CARC.* EE 451 Final Project, University of Southern California.

Vendored library:

> Disservin. (2024). *chess-library* v0.9.4. https://github.com/Disservin/chess-library

Reference checkmate-rate baseline:

> Labelle, F. (2019). *Statistics on chess games.* http://wismuth.com/chess/random-results.html

---

## License

Source code under `CPU_Serial/`, `CPU_OpenMP/`, `GPU_CUDA/`, and `scripts/` is released under the MIT License. The vendored `chess.hpp` retains its original [MIT license](https://github.com/Disservin/chess-library/blob/master/LICENSE).
