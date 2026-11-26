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
   - From `kFindMemchrCutoff` (16 B) up, `find` uses memchr, which is std's own path.
   - Below 16 B, it uses the block kernel.
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
| 4 | 31.48 | 0.72 | 30.90 | 0.66 | 17.55 | 1.09 | 16.55 | 1.06 | 1.76 | 1.47 **SLOWER** | 1.73 | 1.49 **SLOWER** |
| 8 | 19.36 | 1.16 **SLOWER** | 25.54 | 0.88 | 24.35 | 0.92 | 23.17 | 0.90 | 15.78 | 1.13 **SLOWER** | 1.73 | 1.49 **SLOWER** |
| 16 | 20.49 | 1.08 | 43.54 | 0.47 | 36.36 | 0.57 | 32.93 | 0.63 | 35.31 | 0.59 | 16.18 | 1.08 |
| 32 | 19.08 | 1.05 | 45.44 | 0.52 | 43.25 | 0.56 | 46.88 | 0.51 | 36.44 | 0.61 | 39.36 | 0.56 |
| 64 | 18.19 | 1.04 | 60.02 | 0.41 | 74.92 | 0.37 | 82.70 | 0.30 | 74.94 | 0.32 | 68.54 | 0.37 |
| 128 | 16.64 | 1.02 | 87.38 | 0.41 | 115.24 | 0.35 | 127.45 | 0.31 | 120.04 | 0.32 | 128.78 | 0.33 |
| 256 | 17.20 | 0.98 | 113.93 | 0.40 | 210.74 | 0.31 | 215.46 | 0.28 | 238.04 | 0.27 | 247.44 | 0.27 |
| 512 | 16.43 | 0.98 | 161.30 | 0.32 | 299.11 | 0.29 | 455.37 | 0.23 | 443.90 | 0.25 | 435.82 | 0.23 |
| 1024 | 16.45 | 0.97 | 178.89 | 0.32 | 532.38 | 0.26 | 773.01 | 0.26 | 973.28 | 0.20 | 925.57 | 0.21 |
| 2048 | 15.19 | 0.97 | 178.68 | 0.36 | 798.44 | 0.24 | 1137.15 | 0.23 | 1654.72 | 0.23 | 1845.00 | 0.21 |
| 4096 | 24.95 | 0.62 | 222.50 | 0.29 | 906.66 | 0.22 | 1369.31 | 0.24 | 3432.50 | 0.21 | 8934.96 | 0.08 |
| file | 32.59 | 0.65 | 144.08 | 0.33 | 884.81 | 0.20 | 789.64 | 0.15 | 18911.36 | 0.17 | 8147.55 | 0.15 |

#### AVX2 (x86-64-v3 slice under Rosetta 2 — indicative only): literal needles

| hay | `(` std ns | find/std | `::` std ns | find/std | `]]>` std ns | find/std | `<!--` std ns | find/std | `#include` std ns | find/std | `std::string_view` std ns | find/std |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 4 | 6.34 | 1.00 | 5.91 | 1.04 | 5.11 | 0.98 | 4.96 | 0.98 | 0.61 | 1.00 | 0.61 | 1.32 **SLOWER** |
| 8 | 7.35 | 1.01 | 7.00 | 1.04 | 5.84 | 1.00 | 5.71 | 1.00 | 4.98 | 1.00 | 0.61 | 1.31 **SLOWER** |
| 16 | 9.08 | 1.00 | 8.91 | 1.03 | 7.55 | 1.00 | 7.42 | 1.00 | 6.84 | 1.00 | 11.80 | 1.03 |
| 32 | 8.40 | 0.98 | 8.50 | 1.04 | 6.56 | 1.00 | 6.80 | 1.00 | 7.87 | 1.00 | 28.32 | 1.01 |
| 64 | 10.44 | 1.01 | 11.21 | 1.44 **SLOWER** | 7.87 | 1.00 | 8.38 | 1.00 | 10.10 | 1.00 | 54.35 | 0.31 |
| 128 | 13.08 | 1.00 | 16.38 | 1.30 **SLOWER** | 10.25 | 1.01 | 11.03 | 1.00 | 14.10 | 1.00 | 108.09 | 0.22 |
| 256 | 17.04 | 1.00 | 26.80 | 1.19 **SLOWER** | 15.62 | 0.99 | 16.20 | 1.01 | 21.73 | 1.00 | 207.15 | 0.17 |
| 512 | 21.01 | 0.99 | 46.09 | 1.16 **SLOWER** | 26.12 | 1.00 | 26.42 | 1.00 | 38.09 | 1.00 | 396.73 | 0.15 |
| 1024 | 24.04 | 1.00 | 81.78 | 1.13 **SLOWER** | 46.75 | 0.99 | 49.84 | 1.06 | 71.45 | 0.99 | 786.25 | 0.15 |
| 4096 | 23.02 | 0.99 | 193.52 | 1.30 **SLOWER** | 167.50 | 1.00 | 166.79 | 0.99 | 243.08 | 1.00 | 2999.00 | 0.14 |
| file | 28.67 | 0.83 | 132.87 | 0.55 | 587.96 | 0.96 | 418.64 | 1.00 | 484.97 | 1.01 | 4012.80 | 0.09 |

The AVX2 rows come from Rosetta 2, which emulates the 256-bit compares and `pmovmskb` on arm64 and also translates libc's memchr. A
translated run prints its SLOWER cells but exits 0. The gate is a native run: NEON on arm64, or AVX2 on an x86-64-v3 machine.
The Rosetta SLOWER cells are:

- the needle-longer-than-haystack early out (about 0.8 ns);
- one-byte needles at 8 B;
- the `"::"` literal from 64 B up.

These are left for a native x86 run to confirm or refute before anything is tuned for them.
