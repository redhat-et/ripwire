# The file graph's stores: what was measured, and what it decided

`src/infra/fileSetStore.h` holds the file graph's direct edges (`FileAdjacency`) and its transitive closure
(`FileSetStore`). This records the trial behind the closure's form, including the forms that lost.

History. The shape is old. Purdom (1970) collapsed cycles before closing a relation, Tarjan (1972) found the strong components in
linear time and in the sinks-first order the fold needs, and Nuutila (1995) built closure algorithms on them and measured
large digraphs. The row form borrows two later ideas: rank over a presence bitmap (Jacobson, 1989) and chunks that are
a sorted array or a bitset, whichever is smaller (Roaring bitmaps, 2015), minus the run containers and with the chunk size
chosen per graph. Hash sharing of identical rows, with a verify, is ordinary practice here, with no source checked for it.
A 1970 idea on today's cache lines; the citations are in `docs/LINEAGE.md`.

Method: ripwire's own include adjacency and the real membership probes of one index, captured from an instrumented build
and replayed single-threaded in order; the static-truth edge sets of the same repos (`-truth`, what the coming edge lanes
approach); generated layered graphs of 50,000 and 100,000 files (`sNNK-mMEAN`). Times are best of 3 on a loaded 16 GB Mac
(load 15-30), so treat small gaps as noise. No hardware cache counter is available without privilege on this machine, so
cache behaviour is reported as wall time and as lines touched by construction.

## Decisions

- Closure form: chunked hybrid rows, chunk size chosen per store. Smallest on every corpus with a closure to store, and on
  real probes as fast or faster than the sorted vectors it replaced (cpython 9.9 to 2.7 ns, vscode 9.7 to 2.3-5.7 ns).
  It loses on one measure, walk time (about 1 ns per item against 0.1-0.2), and no real run walked a row:
  `walks=0` on all six repos.
- Chunk size is a store field. Fewest bytes: 8 bits on the in-sample repos, 12 at 100,000 files and mean closure 3,497 or
  11,098, 16 at mean 258 or 606. A stride sample of up to 64 rows picked the byte-best size on 12 of 14 corpora, and the two
  misses were under 1 % (zed, zed-truth). The sample costs 64 file walks.
- Build: a fold over SCCs, sinks first. Each component's row is the OR of its successors' rows plus their ids, and goes into
  the store the moment it is known; a successor's row is then ORed back FROM THE STORE, into one working row that is cleared
  by the words it touched. The fold holds one working row (N / 8 bytes) whatever the graph. At mean 11,098 the process peak
  is 580 MB against 4.4 GB for the rows alone in sorted vectors.
  The first form kept each component's bitset until its last reader had run, and measured a "frontier" of 909 to 2,674 rows
  (11 to 33 MB) at 100,000 files on layered graphs. That bound does not hold in general: see the umbrella below.
- Row form: a row is true reachability, so a cycle's members share it, and the read skips the file itself. At 8 bits:
  cpython 0.169 to 0.108 MB, vscode 4.31 to 3.74 MB, Envoy's static truth unchanged.
- Directory: a presence bitmap per row, popcount rank. It replaces a `high` field per chunk and a hash over (row, high). A
  probe that misses the BITMAP stops at the row head; a miss inside a present chunk goes on to the chunk offset and payload.
  The set-miss rate is 82-100 % on the six repos, but the share that stops at the head is lower, measured on the real traces
  at the chosen chunk size:

  | repo | chunk bits | set miss | stops at head | array | bitset |
  |---|---|---|---|---|---|
  | terraform | 16 | 100 % | 100 % | 0 | 0 |
  | cockroach | 8 | 96.3 % | 94.3 % | 2.4 % | 3.3 % |
  | envoy | 16 | 99.9 % | 90.7 % | 9.3 % | 0 |
  | vscode | 8 | 88.6 % | 63.5 % | 9.7 % | 26.8 % |
  | cpython | 8 | 82.5 % | 51.5 % | 8.0 % | 40.4 % |
  | zed | 16 | 99.4 % | 0.0 % | 100 % | 0 |

  (array / bitset: the share of probes that end in a sorted-array search or a bitset word.) A head is 16 bytes at 16-bit
  chunks up to 128 K files and `heads_` is not aligned, so a longer head can straddle two cache lines; the cache-line counts in
  this file are by construction, with no hardware counter behind them.

## The fold's working set, and the umbrella shape

A file that imports many modules is the shape that broke the first fold: `umbrella.h` including 40,000 `x.h`, each of which
includes its own `y.h`. A component's bitset lived until its last reader, a reader only runs after all its successors, so the
umbrella held one N / 8-byte bitset per module it imports: N^2 / 32 bytes. Real repos are not at the synthetics' share
(vscode's frontier was 3,417 rows, 19.5 % of its files), and Go and Java edges make umbrellas of this kind common.

The harness (generated graphs, `-O2`, one process per arm, peak = `/usr/bin/time -l` footprint; the machine was loaded,
load 17-19, so wall times carry noise):

| shape | files | form | peak | wall |
|---|---|---|---|---|
| umbrella, mean closure 2.5 | 100,000 | first fold | 744 MB | 0.38 s |
| umbrella | 100,000 | OR from the store | 12 MB | 0.16 s |
| umbrella | 100,000 | + touched-word list | 11 MB | 0.01 s |
| umbrella | 200,000 | + touched-word list | 21 MB | 0.02 s |
| sparse (chains of 8, mean 3.5) | 200,000 | first fold | 30 MB | 1.64 s |
| sparse | 200,000 | OR from the store | 28 MB | 1.75 s |
| sparse | 200,000 | + touched-word list | 33 MB | 0.02 s |
| sparse (stress, not a target) | 1,000,000 | first fold | 132 MB | 34.6 s |
| sparse | 1,000,000 | OR from the store | 154 MB | 34.4 s |
| sparse | 1,000,000 | + touched-word list | 158 MB | 0.13 s |
| chain, mean closure 50,000 | 100,000 | first fold | 679 MB | 20.7 s |
| chain | 100,000 | + touched-word list, 4 words per OR | 674 MB | 22.8 s |
| layered (`synth 0.5 100 0 30`, mean 8,851) | 100,000 | first fold | 607 MB | 3.6-4.5 s |
| layered | 100,000 | OR from the store alone | 583 MB | 6.5-7.5 s |
| layered | 100,000 | + touched-word list, 4 words per OR | 582 MB | 4.0-5.1 s |

The sparse loss was never the decode. With the profile scopes on (`-DRIPWIRE_PROFILE=ON`; the harness at 1,000,000
sparse), the full-width clear and scan of the working row was 99 % of the fold (6,388 of 6,429 ms in `closure/4b`), and the
decode of the stored rows 0.25 % (16 ms in `closure/4a`). Touching only the words a component sets takes `closure/4` to
234 ms, of which the profile's own 875,000 scope entries are most. A cached run pays the fold too, since the graph is built on
every run.

The trade, stated: the OR-from-the-store form decodes a stored row (a bitset chunk four words at a time) where the first form
ORed whole `u64` words, so on DENSE graphs it can cost 10-15 % more wall (chain 100,000: 20.7 to 22.8 s), and on layered
graphs it is within the noise of the first form. It saves 99 % of the memory on umbrellas, and the full-width clear on sparse
graphs. If one had to give, wall on a 100,000-file dense graph is the one to give: it is a build step that runs once, where
the frontier was a peak that scales with fan-out. A frontier-free form that kept the first form's speed on dense graphs was not
found.

## What the fold does when it cannot finish

- Memory: every `kFoldCheckComponents` (4,096) components or 4 MiB of payload the fold asks `memguard::foldShouldStop()`,
  one footprint reading against the hard line. Over it, the fold stops, records why (`src/infra/fileGraphStop.h`), and
  `memguard::overHardLimit()` reads true from then on, so the CLI's hard line, the MCP per-request check and the second fold
  on `--deps` and `--arch=FILE` all refuse (exit 5, one stderr line) instead of answering from a partial store. An
  allocation failure inside the fold is caught the same way. `RIPWIRE_TEST_MEMGUARD=fold:N` stops the Nth fold of the process
  (buildGraph's is the first), for the gates.
- Width: chunk offsets are `u32`, so 2^32 - 1 payload words (8 GiB) is the most a store holds, and `FileAdjacency` offsets cap
  at 2^32 - 1 edges. Both limits are parameters, and the unit tests reach the stop at a small limit; the real wrap needs 8 GiB
  and was NOT run. A row that would pass the limit is rolled back, the fold stops, and the stop is disclosed.
- Reserve: the up-front reserve is the sample scaled to the components that reach something, then clamped (2 GiB of payload,
  512 MiB of offsets, address space only), and an allocation the OS refuses is no reserve. One giant cycle reserves one row.

## Rejected, with their numbers

- Whole-closure hash set (`unordered_dense`): vscode 131 MB against 3.7, and no faster on real probes (7.0 ns).
- `dynamic_map` keyed by (from << 32 | to): vscode 161 MB, 38 ns on real probes, 124 ns uniform.
- Eytzinger rows: same bytes as flat, 6.5 against 9.1 ns on vscode's real probes. Beaten by the store on both.
- Flat CSR of sorted u32: vscode 32.2 MB. Only saves the 24-byte row headers.
- Bitset per file: fastest lookup (0.5 ns), N^2/8 bytes: 38.6 MB on vscode, 12.9 MB on envoy for a closure of 493 entries.
- Lazy rows: vscode asks about 33.5 % of files holding 18 % of the entries. On top of the store that saves about 3 MB of a
  2.5 GB process, and needs a memo safe under the parallel resolver. The fold is cheap enough that nothing needs deferring.
- Participating-id remap: 3 % or less on vscode, 23 % at 100,000 files and mean 11,098, and worse on sparse repos (cockroach
  0.133 against 0.073 MB) since its two id maps cost 8 B per file, plus a cache line on every probe. Chunking already
  absorbs the empty id ranges.
- u8 lows at 8-bit chunks: about 15 % of a store that is 0.15 % of the process, for a branch on the read path.
- One decoded bitset for the current file: vscode makes 8,400 probes per probed file, so this was retested by arithmetic. The
  best case is 2.3 to 0.5 ns over 49.4 M probes, 84 ms of a 39 s run, before paying to decode.
- Prefetch: no gain on clustered probes, which is what real references are.

## Crossover

Below about 1/32 density a row is arrays, so wider chunks win on bytes (16 bits); once chunks start filling, narrower ones do
(12, then 8). Lookup favours 8 bits at every size measured; the choice is by bytes alone, which is why the store is sometimes
slower than a narrower chunk at 100,000 files (mean 606: 16 bits 43 ns clustered against 48 for 8 bits, a tie; mean 3,497:
12 bits 25 against 20).

## Full table

| corpus | files | edges | mean closure | form | MB | build ms | real probe ns | uniform ns | clustered ns | walk ns/item |
|---|---|---|---|---|---|---|---|---|---|---|
| envoy | 10140 | 394 | 0.0 | today vector&lt;vector> | 0.245 | 0.2 | 0.6 | 1.1 | 1.1 | 19.86 |
| envoy | 10140 | 394 | 0.0 | (a) flat CSR sorted u32 | 0.043 | 0.2 | 0.7 | 0.9 | 0.6 | 0.09 |
| envoy | 10140 | 394 | 0.0 | (g) Eytzinger u32 rows | 0.043 | 0.2 | 0.9 | 1.2 | 1.0 | 0.17 |
| envoy | 10140 | 394 | 0.0 | (b) bitset per file | 12.898 | 1.5 | 0.7 | 7.5 | 0.8 | 1695.40 |
| envoy | 10140 | 394 | 0.0 | (f) unordered_dense set | 0.008 | 0.2 | 3.2 | 2.8 | 3.3 | 14.11 |
| envoy | 10140 | 394 | 0.0 | (f) dynamic_map&lt;u64,char,16> | 0.033 | 0.2 | 13.5 | 19.6 | 10.3 | 14.87 |
| envoy | 10140 | 394 | 0.0 | store fold bits=16 | 0.045 | 0.2 | 1.9 | 2.4 | 1.8 | 28.40 |
| envoy | 10140 | 394 | 0.0 | store AUTO -> bits=16 | 0.045 | 0.2 | 2.0 | 2.4 | 2.2 | 29.16 |
| cpython | 4663 | 11232 | 105.5 | today vector&lt;vector> | 2.079 | 12.0 | 9.9 | 19.5 | 8.1 | 0.10 |
| cpython | 4663 | 11232 | 105.5 | (a) flat CSR sorted u32 | 1.986 | 12.3 | 9.8 | 16.7 | 7.7 | 0.05 |
| cpython | 4663 | 11232 | 105.5 | (g) Eytzinger u32 rows | 1.986 | 13.4 | 6.7 | 15.7 | 7.0 | 0.04 |
| cpython | 4663 | 11232 | 105.5 | (b) bitset per file | 2.723 | 13.2 | 0.5 | 0.7 | 0.5 | 0.78 |
| cpython | 4663 | 11232 | 105.5 | (f) unordered_dense set | 8.129 | 19.8 | 3.9 | 4.7 | 6.2 | 0.25 |
| cpython | 4663 | 11232 | 105.5 | (f) dynamic_map&lt;u64,char,16> | 9.863 | 37.6 | 32.1 | 38.7 | 32.3 | 0.13 |
| cpython | 4663 | 11232 | 105.5 | store fold bits=16 | 0.247 | 2.2 | 10.9 | 19.6 | 10.5 | 0.94 |
| cpython | 4663 | 11232 | 105.5 | store AUTO -> bits=8 | 0.108 | 2.0 | 2.7 | 3.5 | 3.3 | 1.10 |
| vscode | 17544 | 151181 | 457.7 | today vector&lt;vector> | 32.539 | 506.1 | 9.7 | 73.1 | 17.4 | 0.15 |
| vscode | 17544 | 151181 | 457.7 | (a) flat CSR sorted u32 | 32.188 | 514.6 | 12.3 | 172.8 | 34.9 | 0.07 |
| vscode | 17544 | 151181 | 457.7 | (g) Eytzinger u32 rows | 32.188 | 545.7 | 12.1 | 100.6 | 20.8 | 0.08 |
| vscode | 17544 | 151181 | 457.7 | (b) bitset per file | 38.597 | 532.5 | 0.7 | 5.7 | 6.0 | 1.33 |
| vscode | 17544 | 151181 | 457.7 | (f) unordered_dense set | 131.344 | 965.6 | 8.9 | 24.8 | 25.6 | 0.20 |
| vscode | 17544 | 151181 | 457.7 | (f) dynamic_map&lt;u64,char,16> | 160.694 | 1141.7 | 42.9 | 134.9 | 54.1 | 0.15 |
| vscode | 17544 | 151181 | 457.7 | store fold bits=16 | 7.877 | 45.5 | 9.5 | 34.3 | 15.8 | 1.09 |
| vscode | 17544 | 151181 | 457.7 | store AUTO -> bits=8 | 3.744 | 52.5 | 5.7 | 5.5 | 4.8 | 1.21 |
| cockroach | 11148 | 2807 | 8.5 | today vector&lt;vector> | 0.645 | 5.1 | 7.4 | 5.2 | 1.1 | 0.18 |
| cockroach | 11148 | 2807 | 8.5 | (a) flat CSR sorted u32 | 0.422 | 5.2 | 3.9 | 2.4 | 1.2 | 0.05 |
| cockroach | 11148 | 2807 | 8.5 | (g) Eytzinger u32 rows | 0.422 | 5.4 | 3.4 | 2.8 | 1.4 | 0.05 |
| cockroach | 11148 | 2807 | 8.5 | (b) bitset per file | 15.607 | 6.3 | 0.5 | 1.8 | 0.8 | 8.59 |
| cockroach | 11148 | 2807 | 8.5 | (f) unordered_dense set | 1.278 | 6.2 | 3.9 | 5.2 | 5.7 | 0.47 |
| cockroach | 11148 | 2807 | 8.5 | (f) dynamic_map&lt;u64,char,16> | 2.277 | 8.9 | 22.5 | 32.2 | 31.3 | 0.19 |
| cockroach | 11148 | 2807 | 8.5 | store fold bits=16 | 0.129 | 0.6 | 6.3 | 4.0 | 4.7 | 1.10 |
| cockroach | 11148 | 2807 | 8.5 | store AUTO -> bits=8 | 0.073 | 0.5 | 2.1 | 1.7 | 2.1 | 2.43 |
| envoy-truth | 7085 | 34973 | 213.5 | today vector&lt;vector> | 6.221 | 58.0 | - | 42.4 | 26.2 | 0.11 |
| envoy-truth | 7085 | 34973 | 213.5 | (a) flat CSR sorted u32 | 6.079 | 58.6 | - | 66.3 | 17.5 | 0.05 |
| envoy-truth | 7085 | 34973 | 213.5 | (g) Eytzinger u32 rows | 6.079 | 71.6 | - | 57.3 | 19.3 | 0.05 |
| envoy-truth | 7085 | 34973 | 213.5 | (b) bitset per file | 6.291 | 61.2 | - | 0.8 | 0.6 | 1.08 |
| envoy-truth | 7085 | 34973 | 213.5 | (f) unordered_dense set | 20.490 | 134.1 | - | 43.2 | 33.7 | 0.22 |
| envoy-truth | 7085 | 34973 | 213.5 | (f) dynamic_map&lt;u64,char,16> | 30.294 | 195.2 | - | 172.6 | 52.9 | 0.22 |
| envoy-truth | 7085 | 34973 | 213.5 | store fold bits=16 | 2.571 | 13.2 | - | 34.4 | 16.5 | 1.14 |
| envoy-truth | 7085 | 34973 | 213.5 | store AUTO -> bits=8 | 1.295 | 9.1 | - | 12.7 | 9.1 | 1.26 |
| vscode-truth | 14610 | 151511 | 550.9 | today vector&lt;vector> | 32.546 | 328.3 | - | 73.2 | 20.5 | 0.14 |
| vscode-truth | 14610 | 151511 | 550.9 | (a) flat CSR sorted u32 | 32.254 | 331.4 | - | 62.1 | 22.9 | 0.06 |
| vscode-truth | 14610 | 151511 | 550.9 | (g) Eytzinger u32 rows | 32.254 | 351.0 | - | 54.8 | 17.2 | 0.08 |
| vscode-truth | 14610 | 151511 | 550.9 | (b) bitset per file | 26.766 | 345.1 | - | 3.8 | 2.0 | 0.94 |
| vscode-truth | 14610 | 151511 | 550.9 | (f) unordered_dense set | 131.501 | 564.6 | - | 19.9 | 20.7 | 0.17 |
| vscode-truth | 14610 | 151511 | 550.9 | (f) dynamic_map&lt;u64,char,16> | 161.088 | 833.5 | - | 305.8 | 134.5 | 0.16 |
| vscode-truth | 14610 | 151511 | 550.9 | store fold bits=16 | 7.336 | 76.4 | - | 156.1 | 55.0 | 1.75 |
| vscode-truth | 14610 | 151511 | 550.9 | store AUTO -> bits=8 | 3.418 | 53.2 | - | 7.3 | 5.7 | 1.13 |
| s100K-m606 | 100000 | 343149 | 606.0 | today vector&lt;vector> | 244.787 | 3928.1 | - | 369.8 | 154.6 | 0.18 |
| s100K-m606 | 100000 | 343149 | 606.0 | (a) flat CSR sorted u32 | 242.787 | 3953.9 | - | 248.5 | 38.0 | 0.10 |
| s100K-m606 | 100000 | 343149 | 606.0 | (g) Eytzinger u32 rows | 242.787 | 4160.4 | - | 161.1 | 31.5 | 0.09 |
| s100K-m606 | 100000 | 343149 | 606.0 | (b) bitset per file | 1250.400 | 4429.0 | - | 6.8 | 8.2 | 3.75 |
| s100K-m606 | 100000 | 343149 | 606.0 | store fold bits=16 | 121.858 | 791.8 | - | 176.9 | 40.7 | 1.17 |
| s100K-m606 | 100000 | 343149 | 606.0 | store AUTO -> bits=16 | 121.858 | 729.6 | - | 158.8 | 43.0 | 1.25 |
| s100K-m3497 | 100000 | 333273 | 3496.7 | today vector&lt;vector> | 1401.083 | 23735.9 | - | 1259.4 | 197.4 | 1.29 |
| s100K-m3497 | 100000 | 333273 | 3496.7 | (a) flat CSR sorted u32 | 1399.083 | 24979.4 | - | 388.0 | 57.1 | 0.11 |
| s100K-m3497 | 100000 | 333273 | 3496.7 | (g) Eytzinger u32 rows | 1399.083 | 27251.3 | - | 571.5 | 67.5 | 0.10 |
| s100K-m3497 | 100000 | 333273 | 3496.7 | (b) bitset per file | 1250.400 | 25696.9 | - | 8.9 | 6.0 | 1.13 |
| s100K-m3497 | 100000 | 333273 | 3496.7 | store fold bits=16 | 551.068 | 2306.6 | - | 174.6 | 40.0 | 1.49 |
| s100K-m3497 | 100000 | 333273 | 3496.7 | store AUTO -> bits=12 | 471.413 | 1835.4 | - | 43.7 | 24.6 | 1.51 |
| s100K-m11098 | 100000 | 333273 | 11098.0 | today vector&lt;vector> | 4441.605 | 52378.1 | - | 2559.6 | 325.2 | 1.78 |
| s100K-m11098 | 100000 | 333273 | 11098.0 | (a) flat CSR sorted u32 | 4439.605 | 56625.7 | - | 7064.8 | 331.5 | 1.86 |
| s100K-m11098 | 100000 | 333273 | 11098.0 | (g) Eytzinger u32 rows | 4439.605 | 63901.5 | - | 4508.8 | 63.3 | 1.61 |
| s100K-m11098 | 100000 | 333273 | 11098.0 | (b) bitset per file | 1250.400 | 57257.1 | - | 9.1 | 7.6 | 1.70 |
| s100K-m11098 | 100000 | 333273 | 11098.0 | store fold bits=16 | 757.321 | 10593.9 | - | 72.2 | 21.7 | 1.26 |
| s100K-m11098 | 100000 | 333273 | 11098.0 | store AUTO -> bits=12 | 555.309 | 4679.4 | - | 27.6 | 15.6 | 1.58 |

