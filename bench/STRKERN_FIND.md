# strkern::find against std::string_view::find

`rw::strkern::find` (`src/infra/strkern.h`) is meant to be the fastest substring find at every size, so that a call site
never has a reason to keep `std::string_view::find`. This file is the evidence and the re-run recipe.
`bench/bench_strkern_find.cpp` produces it, and it is also the check: it exits 1 if `find` is slower than std in any cell.

## How it is measured

```bash
c++ -O2 -std=c++23 bench/bench_strkern_find.cpp -Isrc -Isrc/infra -o /tmp/ripwire_find_ab && /tmp/ripwire_find_ab .
# AVX2 slice on an arm64 Mac (Rosetta 2; it times the translation, not an x86 core):
c++ -O2 -std=c++23 -arch x86_64 -march=x86-64-v3 bench/bench_strkern_find.cpp -Isrc -Isrc/infra -o /tmp/ripwire_find_x86 && /tmp/ripwire_find_x86 .
```

The setup:

- **Haystacks.**
  - Cuts of 4 B to 4 KB, in powers of two, from a 1 MiB pool of this repository's `src/` and `docs/`. The pool is cache-hot, as a short string a caller probes is.
  - Plus the whole files ("file").
- **Needles.**
  - *Runtime* needles are 64 cuts of the corpus per length (1, 2, 3, 4, 8, 16), so their first bytes are as common as they are in real text.
  - *Literal* needles are one fixed literal per length, through the `Literal` overload, whose length is a compile-time constant.
- **The operation.** The find-all walk a scan does: `find`, then `find` again from hit + 1, until npos. Every arm must return the same hits.
- **Timing.**
  - Thread CPU time; under Rosetta, wall-clock time.
  - The arms alternate, and the figure is the best of 9 rounds, in ns per call.
  - A cell over 1.10× is re-raced, and it fails only if all three races are over.

## The dispatch the tables justify

1. **The lengths.** If the needle is longer than what is left, the answer is npos without reading a byte. The check is inlined, as std's is.
2. **A one-byte needle.**
   - From `kFindMemchrCutoff` (one vector block: 16 B on NEON, 32 B on AVX2) up, `find` uses memchr, which is std's own path.
   - Below that, it uses the block kernel.
3. **The first byte.** std's search is memchr on the first byte, then a compare.
   - **Rare first byte.** If the first byte is not in `kCommonLeadBytes`, memchr strides faster than a two-byte filter, so `find` is std.
     - `kCommonLeadBytes` holds the bytes at 0.5 % or more of the text in each of three corpora: this repo, VS Code `src/` and Envoy `source/`.
   - **Common first byte.** memchr stops at every occurrence, so `find` uses the block kernel at every size.
     - The kernel is Muła's first/last-byte filter: four 16-byte blocks per test, then one overlapped final block, so there is no byte-by-byte tail.
4. **A literal needle.**
   - Below one vector block of start positions (`kFindBlockStarts`), the compiler's constant-length specialization of std is faster, so `find` is std there.
   - Above that, the rules above apply.

## Results, 2026-11-26

M2, macOS, AppleClang. The machine was loaded with other builds, which is why the best of 9 thread-CPU rounds is used.

#### NEON (arm64 M2, native): runtime needles

| hay | m=1 std ns | find/std | m=2 std ns | find/std | m=3 std ns | find/std | m=4 std ns | find/std | m=8 std ns | find/std | m=16 std ns | find/std |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 4 | 12.62 | 0.78 | 12.87 | 0.89 | 10.97 | 1.01 | 8.16 | 1.05 | 1.27 | 1.05 | 1.28 | 1.04 |
| 8 | 14.37 | 0.97 | 17.62 | 0.78 | 14.82 | 0.85 | 13.92 | 0.85 | 8.07 | 1.02 | 1.31 | 1.00 |
| 16 | 13.19 | 1.05 | 23.16 | 0.43 | 24.36 | 0.42 | 22.33 | 0.45 | 18.18 | 0.51 | 7.96 | 1.04 |
| 32 | 13.41 | 1.06 | 35.08 | 0.26 | 32.94 | 0.29 | 33.70 | 0.26 | 26.12 | 0.36 | 25.14 | 0.31 |
| 64 | 14.20 | 1.03 | 48.19 | 0.27 | 62.50 | 0.24 | 64.17 | 0.19 | 59.30 | 0.20 | 51.64 | 0.24 |
| 128 | 14.31 | 1.07 | 76.38 | 0.26 | 100.54 | 0.24 | 104.99 | 0.21 | 98.47 | 0.22 | 108.27 | 0.21 |
| 256 | 14.48 | 1.04 | 101.45 | 0.27 | 186.18 | 0.21 | 182.40 | 0.20 | 200.13 | 0.19 | 221.36 | 0.17 |
| 512 | 14.25 | 1.02 | 143.44 | 0.21 | 265.95 | 0.21 | 396.21 | 0.16 | 381.93 | 0.17 | 378.93 | 0.15 |
| 1024 | 14.67 | 1.02 | 170.79 | 0.20 | 479.78 | 0.19 | 682.91 | 0.18 | 876.66 | 0.14 | 819.57 | 0.14 |
| 2048 | 13.53 | 1.04 | 157.90 | 0.25 | 726.23 | 0.17 | 989.74 | 0.16 | 1450.99 | 0.16 | 1668.64 | 0.14 |
| 4096 | 14.17 | 1.02 | 207.16 | 0.18 | 547.08 | 0.21 | 1114.31 | 0.19 | 2967.67 | 0.14 | 2926.56 | 0.14 |
| file | 13.93 | 1.02 | 111.15 | 0.23 | 369.66 | 0.16 | 435.60 | 0.16 | 12428.59 | 0.15 | 5695.71 | 0.12 |

#### NEON (arm64 M2, native): literal needles

| hay | `(` std ns | find/std | `::` std ns | find/std | `]]>` std ns | find/std | `<!--` std ns | find/std | `#include` std ns | find/std | `std::string_view` std ns | find/std |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 4 | 3.82 | 0.95 | 3.28 | 1.05 | 2.66 | 0.91 | 1.98 | 1.00 | 0.62 | 1.00 | 0.62 | 0.79 |
| 8 | 5.53 | 0.97 | 5.18 | 1.01 | 4.26 | 0.96 | 3.72 | 1.00 | 2.05 | 1.00 | 0.62 | 0.80 |
| 16 | 3.88 | 0.98 | 4.26 | 1.06 | 3.85 | 0.96 | 4.21 | 1.01 | 5.77 | 0.98 | 6.73 | 1.00 |
| 32 | 5.51 | 1.01 | 5.96 | 0.88 | 5.05 | 0.96 | 5.22 | 1.00 | 6.45 | 1.00 | 20.91 | 0.26 |
| 64 | 6.82 | 1.00 | 7.79 | 0.89 | 5.88 | 0.96 | 6.19 | 1.00 | 8.07 | 1.00 | 46.00 | 0.16 |
| 128 | 8.87 | 0.99 | 11.38 | 0.85 | 7.35 | 0.96 | 7.95 | 1.00 | 10.90 | 1.00 | 98.92 | 0.11 |
| 256 | 12.69 | 0.97 | 20.09 | 0.75 | 11.10 | 1.01 | 12.71 | 0.97 | 17.71 | 0.98 | 189.41 | 0.09 |
| 512 | 16.40 | 1.00 | 35.95 | 0.71 | 18.98 | 1.00 | 19.54 | 1.03 | 29.32 | 0.99 | 359.84 | 0.08 |
| 1024 | 19.27 | 1.00 | 67.58 | 0.66 | 34.59 | 1.00 | 37.72 | 0.99 | 55.53 | 1.00 | 716.33 | 0.08 |
| 4096 | 18.82 | 1.00 | 157.39 | 0.73 | 139.01 | 1.01 | 137.00 | 1.01 | 201.10 | 1.03 | 2734.90 | 0.07 |
| file | 19.87 | 1.00 | 63.21 | 0.61 | 449.41 | 1.00 | 361.31 | 0.97 | 422.37 | 0.99 | 2448.90 | 0.08 |

#### AVX2 (x86-64-v3 slice under Rosetta 2 — indicative only): runtime needles

| hay | m=1 std ns | find/std | m=2 std ns | find/std | m=3 std ns | find/std | m=4 std ns | find/std | m=8 std ns | find/std | m=16 std ns | find/std |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 4 | 16.86 | 1.70 **SLOWER** | 19.29 | 1.35 **SLOWER** | 17.22 | 1.54 **SLOWER** | 15.69 | 1.58 **SLOWER** | 1.68 | 1.51 **SLOWER** | 1.73 | 1.52 **SLOWER** |
| 8 | 18.86 | 1.53 **SLOWER** | 25.90 | 1.06 | 22.45 | 1.17 **SLOWER** | 21.69 | 1.17 **SLOWER** | 15.26 | 1.53 **SLOWER** | 1.65 | 1.52 **SLOWER** |
| 16 | 18.96 | 1.64 **SLOWER** | 35.84 | 0.73 | 34.75 | 0.82 | 33.61 | 0.83 | 26.93 | 1.02 | 16.04 | 1.57 **SLOWER** |
| 32 | 19.08 | 1.37 **SLOWER** | 45.40 | 0.71 | 43.34 | 0.74 | 46.40 | 0.74 | 36.18 | 0.77 | 39.21 | 0.76 |
| 64 | 18.74 | 1.36 **SLOWER** | 60.22 | 0.42 | 75.15 | 0.37 | 85.55 | 0.29 | 72.83 | 0.33 | 68.45 | 0.36 |
| 128 | 16.11 | 1.19 **SLOWER** | 88.72 | 0.40 | 116.18 | 0.35 | 126.18 | 0.32 | 116.81 | 0.33 | 124.33 | 0.33 |
| 256 | 16.37 | 1.07 | 110.08 | 0.39 | 203.40 | 0.30 | 209.23 | 0.28 | 228.79 | 0.27 | 240.48 | 0.27 |
| 512 | 15.83 | 1.01 | 155.96 | 0.32 | 316.92 | 0.28 | 457.63 | 0.23 | 445.12 | 0.25 | 434.36 | 0.23 |
| 1024 | 16.64 | 0.97 | 171.96 | 0.31 | 512.77 | 0.26 | 769.20 | 0.25 | 945.32 | 0.20 | 898.85 | 0.20 |
| 2048 | 15.08 | 0.97 | 174.70 | 0.35 | 782.36 | 0.23 | 1091.38 | 0.23 | 1585.67 | 0.23 | 1818.75 | 0.20 |
| 4096 | 15.49 | 0.98 | 219.05 | 0.27 | 589.34 | 0.28 | 1274.27 | 0.25 | 3370.18 | 0.20 | 3182.22 | 0.21 |
| file | 14.31 | 0.97 | 112.75 | 0.37 | 454.35 | 0.25 | 838.27 | 0.17 | 36316.17 | 0.09 | 16224.18 | 0.08 |

#### AVX2 (x86-64-v3 slice under Rosetta 2 — indicative only): literal needles

| hay | `(` std ns | find/std | `::` std ns | find/std | `]]>` std ns | find/std | `<!--` std ns | find/std | `#include` std ns | find/std | `std::string_view` std ns | find/std |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 4 | 6.39 | 1.01 | 5.92 | 1.02 | 5.11 | 1.00 | 4.86 | 1.00 | 0.61 | 1.00 | 0.61 | 1.31 **SLOWER** |
| 8 | 7.35 | 1.01 | 6.91 | 1.02 | 5.91 | 0.99 | 5.71 | 1.00 | 4.99 | 1.00 | 0.61 | 1.31 **SLOWER** |
| 16 | 9.06 | 1.00 | 8.99 | 1.01 | 7.60 | 1.00 | 7.48 | 1.00 | 6.87 | 1.01 | 11.76 | 1.03 |
| 32 | 8.46 | 0.99 | 8.54 | 1.02 | 6.55 | 1.00 | 6.80 | 1.00 | 7.92 | 1.00 | 28.24 | 1.02 |
| 64 | 10.37 | 1.03 | 11.24 | 1.44 **SLOWER** | 7.97 | 0.99 | 8.35 | 1.00 | 10.07 | 1.00 | 54.41 | 0.31 |
| 128 | 13.04 | 1.01 | 16.38 | 1.30 **SLOWER** | 10.62 | 0.97 | 11.15 | 0.99 | 14.16 | 1.00 | 108.58 | 0.22 |
| 256 | 16.98 | 1.02 | 26.56 | 1.19 **SLOWER** | 15.75 | 0.98 | 16.44 | 0.99 | 22.09 | 1.00 | 207.64 | 0.17 |
| 512 | 21.01 | 1.00 | 45.40 | 1.18 **SLOWER** | 26.61 | 0.99 | 26.90 | 0.99 | 38.33 | 0.99 | 397.22 | 0.16 |
| 1024 | 23.98 | 0.99 | 80.89 | 1.15 **SLOWER** | 46.75 | 0.99 | 49.84 | 1.00 | 71.70 | 0.99 | 1071.00 | 0.11 |
| 4096 | 23.12 | 1.08 | 189.67 | 1.28 **SLOWER** | 166.25 | 0.98 | 162.97 | 0.99 | 234.60 | 1.01 | 2970.00 | 0.14 |
| file | 24.38 | 0.96 | 77.00 | 0.88 | 548.27 | 1.00 | 407.95 | 1.01 | 491.89 | 1.00 | 2569.22 | 0.15 |

The AVX2 rows come from Rosetta 2 on the same loaded M2, with wall-clock timing. Rosetta emulates the 256-bit compares and
`pmovmskb` on arm64 and also translates libc's memchr, so these rows are not an x86 core's numbers, and they move from run to run
(24 cells over the bar in this run, 13 in the run before it). The AVX2 dispatch is NEON's carried over block for block: a 32 B
memchr cutoff and a 32-start literal cutoff, with the same `kCommonLeadBytes`. It is deliberately not tuned from Rosetta.

On x86-64 the bench prints its table and exits 0. CI runs it natively, report-only, on both ubuntu Release legs (gcc and clang),
shard 1. STRKERN-X86-TUNE will tune the AVX2 cutoffs and the lead-byte handling from that native table, then make the x86 check a
gate once every cell passes.
