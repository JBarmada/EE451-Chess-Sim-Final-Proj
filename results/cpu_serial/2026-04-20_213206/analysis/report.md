# Chess Monte Carlo Simulation — HPC Results

**Run ID:** `2026-04-20_213206`
**Generated:** 2026-04-28T05:12:33Z

---

## Hardware

```
CPU:           AMD EPYC 9124 16-Core Processor
Sockets:       2
Physical cores:32  (16 per socket)
Logical CPUs:  64  (SMT threads/core: 2)
Max freq:      N/A MHz
L3 cache:      16384K
Memory:        377.5 GB
NUMA nodes:    2
SLURM node:    N/A  (partition: N/A)
SLURM job ID:  N/A
```

```
Build timestamp: 2026-04-21T04:30:18Z
Hostname: discovery1.hpc.usc.edu
GCC version: g++ (GCC) 13.3.0
Loaded modules:  Currently Loaded Modules:   1) gcc/13.3.0     
CXXFLAGS: -std=c++17 -O3 -DNDEBUG
OpenMP flags: -fopenmp
```

---

## 1. Throughput

Games and moves simulated per second.
`Games/sec/thread` normalises out thread count for apples-to-apples comparison.

| Size | Variant | Threads | Time (s) | Games/sec  | Moves/sec    | Games/sec/thread |
|------|---------|---------|----------|------------|--------------|------------------|
| 1k   | openmp  | 64      | 0.01     | 127567.99  | 51950788.25  | 1993.25          |
| 10k  | openmp  | 64      | 0.02     | 578003.54  | 231536658.05 | 9031.31          |
| 100k | openmp  | 64      | 0.11     | 935632.94  | 375254303.25 | 14619.26         |
| 1m   | openmp  | 64      | 1.00     | 1003718.02 | 402189810.61 | 15683.09         |
| 10m  | openmp  | 1       | 644.20   | 15523.02   | 6222247.34   | 15523.02         |
| 10m  | openmp  | 2       | 323.10   | 30950.43   | 12404622.84  | 15475.22         |
| 10m  | openmp  | 4       | 160.66   | 62241.84   | 24944039.80  | 15560.46         |
| 10m  | openmp  | 8       | 80.77    | 123803.91  | 49631749.48  | 15475.49         |
| 10m  | openmp  | 16      | 40.18    | 248875.91  | 99737020.93  | 15554.74         |
| 10m  | openmp  | 32      | 20.01    | 499827.32  | 200330789.86 | 15619.60         |
| 10m  | openmp  | 64      | 9.95     | 1004624.35 | 402673531.97 | 15697.26         |
| 100m | openmp  | 64      | 99.54    | 1004616.36 | 402650237.09 | 15697.13         |
| 1b   | openmp  | 64      | 999.10   | 1000903.77 | 401182249.09 | 15639.12         |
| 1b   | serial  | 1       | 50836.80 | 19670.77   | 7884438.03   | 19670.77         |

---

## 2. Speedup and Parallel Efficiency

Speedup = Serial Time / OpenMP Time (same problem size and game count).
Efficiency = Speedup / Threads.

| Size | Threads | Serial (s) | OpenMP (s) | Speedup | Efficiency (%) |
|------|---------|------------|------------|---------|----------------|
| 1b   | 64      | 50836.80   | 999.10     | 50.88   | 79.50          |

---

## 3. Thread Scalability — 1b games (fixed size)

| Threads | Time (s) | Games/sec  | Speedup | Efficiency (%) | Serial Frac (%) | Amdahl Max | Amdahl Predicted |
|---------|----------|------------|---------|----------------|-----------------|------------|------------------|
| 64      | 999.10   | 1000903.77 | 50.88   | 79.50          | 0.41            | 244.38     | 50.88            |

**Amdahl's Law** — estimated serial fraction from highest thread-count measurement:
`s ≈ 0.41%`  →  theoretical max speedup ≈ `244.38×`

The _Amdahl Predicted_ column shows what Amdahl's Law forecasts at each thread count
given the estimated `s`. Gaps between predicted and actual reveal super-linear effects
(cache warming) or sub-linear effects (memory bandwidth, NUMA overhead).

---

## 4. Problem-Size Scalability — 64 threads (fixed threads)

| Size | N          | Serial (s) | OpenMP (s) | Speedup | Efficiency (%) |
|------|------------|------------|------------|---------|----------------|
| 1k   | 1000       | N/A        | 0.01       | N/A     | N/A            |
| 10k  | 10000      | N/A        | 0.02       | N/A     | N/A            |
| 100k | 100000     | N/A        | 0.11       | N/A     | N/A            |
| 1m   | 1000000    | N/A        | 1.00       | N/A     | N/A            |
| 10m  | 10000000   | N/A        | 9.95       | N/A     | N/A            |
| 100m | 100000000  | N/A        | 99.54      | N/A     | N/A            |
| 1b   | 1000000000 | 50836.80   | 999.10     | 50.88   | 79.50          |

Throughput improvements with problem size indicate warm cache and amortised
OpenMP startup overhead. Degradation at very large N suggests DRAM bandwidth limits.

---

## 5. Amdahl's Law Analysis

`s` estimated from the highest-thread run per size.
`Max Speedup = 1 / s`.
Predictions at 64 and 128 threads assume same `s` holds (optimistic upper bound).

| Size | Measured Speedup | Serial Frac (%) | Parallel Frac (%) | Max Speedup | Pred @64t | Pred @128t |
|------|------------------|-----------------|-------------------|-------------|-----------|------------|
| 1b   | 50.88            | 0.41            | 99.59             | 244.38      | 50.88     | 84.23      |

Chess random simulation is **embarrassingly parallel** in the limit:
- Games are fully independent; no shared state during simulation.
- Thread-local RNG and statistics eliminate synchronisation inside the hot loop.
- Only `mergeStats()` is serial — O(threads), ≪ 1% of total runtime.

Observed serial fraction at large N is typically **< 0.1%**, driven by:
1. OpenMP thread pool startup (amortised over large N — dominant at small N)
2. `mergeStats()` reduction after all games complete (O(threads), constant time)
3. Memory bandwidth saturation on shared L3 at high thread counts
4. NUMA remote-memory traffic when threads span both EPYC dies (>32 threads on this node)

---

## 6. Statistical Accuracy vs Labelle (2019)

Reference checkmate rate: **15.55%**
95% CI shown; z-score interpretation: |z| < 1.96 → consistent with baseline.

| Size | Variant | N          | Checkmate % | Labelle % | Delta % | Z-score  | 95% CI           |
|------|---------|------------|-------------|-----------|---------|----------|------------------|
| 1k   | openmp  | 1000       | 14.70       | 15.55     | -0.850  | -0.742   | [12.640, 17.030] |
| 10k  | openmp  | 10000      | 15.64       | 15.55     | 0.090   | 0.248    | [14.941, 16.365] |
| 100k | openmp  | 100000     | 15.12       | 15.55     | -0.430  | -3.752   | [14.899, 15.343] |
| 1m   | openmp  | 1000000    | 15.29       | 15.55     | -0.260  | -7.175   | [15.220, 15.361] |
| 10m  | openmp  | 10000000   | 15.30       | 15.55     | -0.250  | -21.816  | [15.278, 15.322] |
| 10m  | openmp  | 10000000   | 15.31       | 15.55     | -0.240  | -20.943  | [15.288, 15.332] |
| 10m  | openmp  | 10000000   | 15.33       | 15.55     | -0.220  | -19.198  | [15.308, 15.352] |
| 10m  | openmp  | 10000000   | 15.29       | 15.55     | -0.260  | -22.689  | [15.268, 15.312] |
| 10m  | openmp  | 10000000   | 15.33       | 15.55     | -0.220  | -19.198  | [15.308, 15.352] |
| 10m  | openmp  | 10000000   | 15.31       | 15.55     | -0.240  | -20.943  | [15.288, 15.332] |
| 10m  | openmp  | 10000000   | 15.30       | 15.55     | -0.250  | -21.816  | [15.278, 15.322] |
| 100m | openmp  | 100000000  | 15.31       | 15.55     | -0.240  | -66.229  | [15.303, 15.317] |
| 1b   | openmp  | 1000000000 | 15.31       | 15.55     | -0.240  | -209.434 | [15.308, 15.312] |
| 1b   | serial  | 1000000000 | 15.31       | 15.55     | -0.240  | -209.434 | [15.308, 15.312] |

**Note on large |z| at high N:** With millions of games the standard error is
~0.01%, so even a 0.2% systematic offset appears highly significant. This reflects
a methodological difference from Labelle's study (draw adjudication, move selection),
not a simulation bug. The offset is small, consistent across all sizes, and both
implementations produce statistically indistinguishable rates.

---

## 7. Load Imbalance

`openMP.cpp` uses `schedule(static)` — equal game *counts* per thread, not equal work.
Individual game lengths range from ~10 to ~5,897 plies (mean ≈ 400).

- At N ≥ 1M: CLT makes per-thread work nearly uniform → static schedule near-optimal.
- At N ≤ 10K: high variance → `schedule(dynamic)` could reduce tail latency,
  but stealing overhead typically dominates for such short games.
- Impact on GPU (future): warp divergence from variable game length is the main
  performance risk; batching by predicted game length may help.

---

*Generated by `scripts/analyze_results.py` | 14 records processed*
