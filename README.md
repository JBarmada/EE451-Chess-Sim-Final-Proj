# Parallel Checkmate

A high-performance Monte Carlo chess simulator. Serial CPU, multi-threaded OpenMP, and (planned) CUDA GPU implementations, benchmarked on the USC CARC Discovery cluster.

**Authors:** Jad Barmada · Eli Fast · Joyce Ng · Lian Fouse
**Course:** EE 451 — Parallel and Distributed Computation, USC, Spring 2026

---

## Research Question

How does throughput, speedup, and statistical accuracy of Monte Carlo random-chess simulation scale across:

1. **Implementation strategy** — serial vs OpenMP vs CUDA
2. **Thread count** — 1, 2, 4, 8, 16, 32, 64 threads
3. **Problem size** — 1K to 1B simulated games

Statistical accuracy is validated against François Labelle's 2019 reference checkmate rate of **15.55%**.

---

## Key Results

Full results are in [`results/cpu_serial/2026-04-20_213206/`](results/cpu_serial/2026-04-20_213206/).

| Metric                                | Value                |
|---------------------------------------|----------------------|
| Peak throughput (64 threads, 1B games)| ~1.00 M games/sec    |
| Serial 1B baseline                    | ~50,837 s (14.1 hrs) |
| Best speedup (64 threads, 1B games)   | **50.88×**           |
| Parallel efficiency (64t, 1B)         | 79.5%                |
| Estimated serial fraction (Amdahl `s`)| ~0.04%               |
| Checkmate rate (1B games)             | 15.31% ✓             |

The full report is at [`results/cpu_serial/2026-04-20_213206/analysis/report.md`](results/cpu_serial/2026-04-20_213206/analysis/report.md).

---

## Hardware

Benchmarks ran on a CARC `epyc-64` node:

- **CPU:** 2× AMD EPYC 9124 (16 cores/socket, 32 physical / 64 logical)
- **Memory:** 377 GB
- **NUMA:** 2 nodes
- **L3 cache:** 16 MB

Full hardware profiles are captured per run in `results/cpu_*/<run_id>/sim/hardware.txt`.

---

## Repository Layout

```
.
├── CPU_Serial/              Serial C++ simulator
│   ├── serial.cpp           Main entry
│   └── chess.hpp            Disservin chess-library v0.9.4 (header-only)
├── CPU_OpenMP/              OpenMP-parallel simulator
│   ├── openMP.cpp
│   └── chess.hpp
├── GPU_CUDA/                CUDA implementation (planned)
├── Makefile                 Builds all 14 binaries (7 sizes × 2 variants)
├── scripts/
│   ├── build.sh             Compile all binaries on CARC
│   ├── submit_all_runs.sh   Submit the full benchmark suite
│   ├── run_serial.job       SLURM: serial 1k–100m
│   ├── run_serial_1b.job    SLURM: serial 1B (~14 hrs)
│   ├── run_openmp_scaling.job  SLURM: 10m × {1,2,4,8,16,32,64} threads
│   ├── run_openmp_sizes.job    SLURM: all sizes × 64 threads
│   ├── run_analyze.job      SLURM: post-processing
│   ├── analyze_results.py   Aggregate raw summaries → CSVs + report
│   └── capture_hardware.sh  Per-run hardware profile capture
└── results/
    ├── cpu_serial/<run_id>/{sim,csv,analysis}/
    └── cpu_openmp/<run_id>/{sim,csv,analysis}/
```

---

## Requirements

- **GCC ≥ 9** with OpenMP (`-fopenmp`)
- **C++17** (the code uses `std::filesystem`)
- **Python ≥ 3.9** (standard library only — no `pip install` needed)
- **SLURM** scheduler (only required for the CARC workflow)

The `chess.hpp` library by [Disservin](https://github.com/Disservin/chess-library) is vendored at v0.9.4. No external chess dependencies.

---

## Reproducing the Study

### Option A — Full reproduction on CARC

```bash
# 1. Clone and enter the repo
git clone https://github.com/JBarmada/Parallel-Checkmate.git
cd Parallel-Checkmate

# 2. Build all 14 binaries
module load gcc
bash scripts/build.sh

# 3. Submit the full benchmark suite
#    Submits 4 jobs in parallel (serial, omp_scaling, omp_sizes)
#    plus an analysis job that runs after they all succeed.
bash scripts/submit_all_runs.sh

# Optional: include the 14-hour 1B serial baseline
bash scripts/submit_all_runs.sh --include-1b

# 4. Monitor
squeue -u $USER --format='%.10i %.25j %.8T %.10M %.12l'
```

All four jobs share a single `RUN_ID=$(date +%Y-%m-%d_%H%M%S)` so their results land in the same dated folder. The analysis job aggregates everything into CSVs and a Markdown report.

### Option B — Single benchmark locally

```bash
# Compile a single binary
make sim_openmp_10m

# Run it (output respects CHESS_RUN_DIR if set)
OMP_NUM_THREADS=8 ./sim_openmp_10m

# Result lands in results/10m_openmp/8/summary.txt by default
```

### Option C — Re-analyse existing raw results

```bash
python3 scripts/analyze_results.py \
  --serial-sim-dir  results/cpu_serial/<run_id>/sim \
  --openmp-sim-dir  results/cpu_openmp/<run_id>/sim \
  --csv-dir         results/cpu_serial/<run_id>/csv \
  --analysis-dir    results/cpu_serial/<run_id>/analysis \
  --build-manifest  scripts/build_manifest.txt \
  --run-id          <run_id>
```

---

## Implementation Notes

### Game-count is compile-time

Each binary is compiled with a fixed `-DNUM_GAMES=N`. The `Makefile` defines 7 sizes per variant:

```
sim_serial_1k  sim_serial_10k  sim_serial_100k  sim_serial_1m
sim_serial_10m sim_serial_100m sim_serial_1b
sim_openmp_*  (same 7 sizes)
```

This lets the compiler unroll/optimise more aggressively than a runtime parameter.

### Thread count is runtime

The OpenMP binary calls `omp_get_max_threads()`, which respects `OMP_NUM_THREADS`. This means a single binary handles every thread count — no recompilation needed. The output path includes the thread count: `results/<size>_openmp/<threads>/summary.txt`.

### Output redirection

Both binaries respect `CHESS_RUN_DIR` (env var). The SLURM jobs set this to the dated run folder so results don't overwrite each other across runs.

### Memory: O(1)

A previous version stored every game's ply count in a `std::vector<int>`, exhausting memory at 1B games (~4 GB just for that vector). The current version uses a `long long` running sum — constant memory regardless of game count.

---

## Analysis Outputs

Each completed analysis produces 8 CSVs and one report:

| File                          | Contents                                                    |
|-------------------------------|-------------------------------------------------------------|
| `metrics_raw.csv`             | Full record per `summary.txt` — all metrics, all runs       |
| `throughput.csv`              | Games/sec, moves/sec, games/sec/thread                      |
| `speedup_table.csv`           | Speedup + efficiency per (size, threads)                    |
| `scaling_table.csv`           | Thread sweep at fixed problem size with Amdahl predictions  |
| `size_scaling_table.csv`      | Size sweep at fixed max thread count                        |
| `full_matrix.csv`             | Complete size × thread matrix                               |
| `amdahl_table.csv`            | Estimated serial fraction + predictions at 64 / 128 threads |
| `statistical_accuracy.csv`    | Wilson 95% CI + z-test vs Labelle 15.55% baseline           |
| `analysis/report.md`          | Markdown report aggregating all of the above with prose     |

---

## Reproducibility

- **Source determinism:** Each game uses a thread-local `std::mt19937` seeded from `std::random_device`. Runs are not bit-for-bit reproducible — the design philosophy is **statistical** convergence at 10M+ games (where standard errors become negligible).
- **Hardware capture:** Every run records `lscpu`, cache hierarchy, NUMA topology, SLURM allocation, compiler version, and OpenMP runtime info to `hardware.txt`.
- **Build manifest:** `scripts/build.sh` writes timestamp, hostname, GCC version, and flags to `scripts/build_manifest.txt` — included verbatim in every analysis report.
- **Module versions:** CARC uses unversioned modules (`module load gcc`); current default is GCC 13.3.0. The build manifest records the actual version used.

---

## Citing

If you use this code or data, please reference:

> Barmada, J., Fast, E., Ng, J., & Fouse, L. (2026). *Parallel Checkmate: A Performance Study of Monte Carlo Chess Simulation on USC CARC.* EE 451 Final Project, University of Southern California.

The vendored chess move-generation library:

> Disservin. (2024). *chess-library* v0.9.4. https://github.com/Disservin/chess-library

Reference checkmate-rate baseline:

> Labelle, F. (2019). *Statistics on chess games.* http://wismuth.com/chess/random-results.html

---

## License

Source code in `CPU_Serial/`, `CPU_OpenMP/`, `GPU_CUDA/`, and `scripts/` is released under the MIT License. The vendored `chess.hpp` retains its original [MIT license](https://github.com/Disservin/chess-library/blob/master/LICENSE).
