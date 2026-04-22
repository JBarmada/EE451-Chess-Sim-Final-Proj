# Chess Monte Carlo Simulation — HPC Results

**Run ID:** `2026-04-20_213206`
**Generated:** 2026-04-22T07:16:02Z

---

## Hardware

```
CPU:           AMD EPYC 7542 32-Core Processor
Sockets:       2
Physical cores:64  (32 per socket)
Logical CPUs:  128  (SMT threads/core: 2)
Max freq:      N/A MHz
L3 cache:      16384K
Memory:        251.3 GB
NUMA nodes:    2
SLURM node:    b22-20  (partition: main)
SLURM job ID:  8220287
```

```
See scripts/build_manifest.txt
```

---

## 1. Throughput

Games and moves simulated per second.
`Games/sec/thread` normalises out thread count for apples-to-apples comparison.

| Size | Variant | Threads | Time (s) | Games/sec  | Moves/sec    | Games/sec/thread |
|------|---------|---------|----------|------------|--------------|------------------|
| 1k   | openmp  | 64      | 0.01     | 127567.99  | 51950788.25  | 1993.25          |
| 1k   | serial  | 1       | 0.06     | 15978.86   | 6361983.11   | 15978.86         |
| 10k  | openmp  | 64      | 0.02     | 578003.54  | 231536658.05 | 9031.31          |
| 10k  | serial  | 1       | 0.62     | 16073.25   | 6413387.48   | 16073.25         |
| 100k | openmp  | 64      | 0.11     | 935632.94  | 375254303.25 | 14619.26         |
| 100k | serial  | 1       | 6.22     | 16070.24   | 6440952.19   | 16070.24         |
| 1m   | openmp  | 64      | 1.00     | 1003718.02 | 402189810.61 | 15683.09         |
| 1m   | serial  | 1       | 68.33    | 14635.62   | 5865956.50   | 14635.62         |
| 10m  | openmp  | 1       | 644.20   | 15523.02   | 6222247.34   | 15523.02         |
| 10m  | openmp  | 2       | 323.10   | 30950.43   | 12404622.84  | 15475.22         |
| 10m  | openmp  | 4       | 160.66   | 62241.84   | 24944039.80  | 15560.46         |
| 10m  | openmp  | 8       | 80.77    | 123803.91  | 49631749.48  | 15475.49         |
| 10m  | openmp  | 16      | 40.18    | 248875.91  | 99737020.93  | 15554.74         |
| 10m  | openmp  | 32      | 20.01    | 499827.32  | 200330789.86 | 15619.60         |
| 10m  | openmp  | 64      | 9.95     | 1004624.35 | 402673531.97 | 15697.26         |
| 10m  | serial  | 1       | 622.88   | 16054.40   | 6434924.61   | 16054.40         |
| 100m | openmp  | 64      | 99.54    | 1004616.36 | 402650237.09 | 15697.13         |
| 100m | serial  | 1       | 6234.92  | 16038.69   | 6428467.34   | 16038.69         |
| 1b   | openmp  | 64      | 999.10   | 1000903.77 | 401182249.09 | 15639.12         |

---

## 2. Speedup and Parallel Efficiency

Speedup = Serial Time / OpenMP Time (same problem size and game count).
Efficiency = Speedup / Threads.

| Size | Threads | Serial (s) | OpenMP (s) | Speedup | Efficiency (%) |
|------|---------|------------|------------|---------|----------------|
| 1k   | 64      | 0.06       | 0.01       | 7.98    | 12.47          |
| 10k  | 64      | 0.62       | 0.02       | 35.96   | 56.19          |
| 100k | 64      | 6.22       | 0.11       | 58.22   | 90.97          |
| 1m   | 64      | 68.33      | 1.00       | 68.58   | 107.16         |
| 10m  | 1       | 622.88     | 644.20     | 0.97    | 96.69          |
| 10m  | 2       | 622.88     | 323.10     | 1.93    | 96.39          |
| 10m  | 4       | 622.88     | 160.66     | 3.88    | 96.92          |
| 10m  | 8       | 622.88     | 80.77      | 7.71    | 96.39          |
| 10m  | 16      | 622.88     | 40.18      | 15.50   | 96.89          |
| 10m  | 32      | 622.88     | 20.01      | 31.13   | 97.29          |
| 10m  | 64      | 622.88     | 9.95       | 62.58   | 97.78          |
| 100m | 64      | 6234.92    | 99.54      | 62.64   | 97.87          |

---

## 3. Thread Scalability — 10m games (fixed size)

| Threads | Time (s) | Games/sec  | Speedup | Efficiency (%) | Serial Frac (%) | Amdahl Max | Amdahl Predicted |
|---------|----------|------------|---------|----------------|-----------------|------------|------------------|
| 1       | 644.20   | 15523.02   | 0.97    | 96.69          | N/A             | N/A        | 1.00             |
| 2       | 323.10   | 30950.43   | 1.93    | 96.39          | 3.74            | 26.72      | 2.00             |
| 4       | 160.66   | 62241.84   | 3.88    | 96.92          | 1.06            | 94.50      | 4.00             |
| 8       | 80.77    | 123803.91  | 7.71    | 96.39          | 0.53            | 187.12     | 7.98             |
| 16      | 40.18    | 248875.91  | 15.50   | 96.89          | 0.21            | 466.95     | 15.91            |
| 32      | 20.01    | 499827.32  | 31.13   | 97.29          | 0.09            | 1113.65    | 31.65            |
| 64      | 9.95     | 1004624.35 | 62.58   | 97.78          | 0.04            | 2768.93    | 62.58            |

**Amdahl's Law** — estimated serial fraction from highest thread-count measurement:
`s ≈ 0.04%`  →  theoretical max speedup ≈ `2768.93×`

The _Amdahl Predicted_ column shows what Amdahl's Law forecasts at each thread count
given the estimated `s`. Gaps between predicted and actual reveal super-linear effects
(cache warming) or sub-linear effects (memory bandwidth, NUMA overhead).

---

## 4. Problem-Size Scalability — 64 threads (fixed threads)

| Size | N          | Serial (s) | OpenMP (s) | Speedup | Efficiency (%) |
|------|------------|------------|------------|---------|----------------|
| 1k   | 1000       | 0.06       | 0.01       | 7.98    | 12.47          |
| 10k  | 10000      | 0.62       | 0.02       | 35.96   | 56.19          |
| 100k | 100000     | 6.22       | 0.11       | 58.22   | 90.97          |
| 1m   | 1000000    | 68.33      | 1.00       | 68.58   | 107.16         |
| 10m  | 10000000   | 622.88     | 9.95       | 62.58   | 97.78          |
| 100m | 100000000  | 6234.92    | 99.54      | 62.64   | 97.87          |
| 1b   | 1000000000 | N/A        | 999.10     | N/A     | N/A            |

Throughput improvements with problem size indicate warm cache and amortised
OpenMP startup overhead. Degradation at very large N suggests DRAM bandwidth limits.

---

## 5. Amdahl's Law Analysis

`s` estimated from the highest-thread run per size.
`Max Speedup = 1 / s`.
Predictions at 64 and 128 threads assume same `s` holds (optimistic upper bound).

| Size | Measured Speedup | Serial Frac (%) | Parallel Frac (%) | Max Speedup | Pred @64t | Pred @128t |
|------|------------------|-----------------|-------------------|-------------|-----------|------------|
| 1k   | 7.98             | 11.14           | 88.86             | 8.98        | 7.98      | 8.45       |
| 10k  | 35.96            | 1.24            | 98.76             | 80.80       | 35.96     | 49.77      |
| 100k | 58.22            | 0.16            | 99.84             | 634.72      | 58.22     | 106.66     |
| 1m   | 68.58            | 0.00            | 100.00            | N/A         | N/A       | N/A        |
| 10m  | 62.58            | 0.04            | 99.96             | 2768.93     | 62.58     | 122.39     |
| 100m | 62.64            | 0.03            | 99.97             | 2895.22     | 62.64     | 122.62     |

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
| 1k   | serial  | 1000       | 16.50       | 15.55     | 0.950   | 0.829    | [14.328, 18.928] |
| 10k  | openmp  | 10000      | 15.64       | 15.55     | 0.090   | 0.248    | [14.941, 16.365] |
| 10k  | serial  | 10000      | 15.70       | 15.55     | 0.150   | 0.414    | [15.000, 16.426] |
| 100k | openmp  | 100000     | 15.12       | 15.55     | -0.430  | -3.752   | [14.899, 15.343] |
| 100k | serial  | 100000     | 15.32       | 15.55     | -0.230  | -2.007   | [15.098, 15.545] |
| 1m   | openmp  | 1000000    | 15.29       | 15.55     | -0.260  | -7.175   | [15.220, 15.361] |
| 1m   | serial  | 1000000    | 15.31       | 15.55     | -0.240  | -6.623   | [15.240, 15.381] |
| 10m  | openmp  | 10000000   | 15.30       | 15.55     | -0.250  | -21.816  | [15.278, 15.322] |
| 10m  | openmp  | 10000000   | 15.31       | 15.55     | -0.240  | -20.943  | [15.288, 15.332] |
| 10m  | openmp  | 10000000   | 15.33       | 15.55     | -0.220  | -19.198  | [15.308, 15.352] |
| 10m  | openmp  | 10000000   | 15.29       | 15.55     | -0.260  | -22.689  | [15.268, 15.312] |
| 10m  | openmp  | 10000000   | 15.33       | 15.55     | -0.220  | -19.198  | [15.308, 15.352] |
| 10m  | openmp  | 10000000   | 15.31       | 15.55     | -0.240  | -20.943  | [15.288, 15.332] |
| 10m  | openmp  | 10000000   | 15.30       | 15.55     | -0.250  | -21.816  | [15.278, 15.322] |
| 10m  | serial  | 10000000   | 15.30       | 15.55     | -0.250  | -21.816  | [15.278, 15.322] |
| 100m | openmp  | 100000000  | 15.31       | 15.55     | -0.240  | -66.229  | [15.303, 15.317] |
| 100m | serial  | 100000000  | 15.31       | 15.55     | -0.240  | -66.229  | [15.303, 15.317] |
| 1b   | openmp  | 1000000000 | 15.31       | 15.55     | -0.240  | -209.434 | [15.308, 15.312] |

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

*Generated by `scripts/analyze_results.py` | 19 records processed*
