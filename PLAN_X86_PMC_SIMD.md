# PLAN — x86 for PROFILE_SCOPE perf counters, dynamic_map vectorized lookup, FixedStr equality

Status: IMPLEMENTED 2026-08-04 (same day) — gates `test/dynmapsimdcheck.sh` + `test/pmccheck.sh`
(wired into regression.sh, pinned in gateexitcheck FAILFAST), SSE2/SSE4.2 `node_rank` kernels,
FixedStr SSE2 `operator==`, Linux perf_event_open backend (pinned group, one-syscall read), plus an
unplanned extra: M5 Pro kpep verification (5/6 M1-era names resolved; `llc-misses` now resolves via
`PL2_CACHE_MISS_LD`, added to the probe table). Validated: macOS NEON + amd64 Rosetta container
(g++/clang, SSE2 baseline + x86-64-v2, full G1 sanitizer set), ASan/LSan corpus run, determinism,
xmllint. REMAINING: live ACTIVE-arm validation — `sudo bash test/pmccheck.sh` on this Mac (kperf
arming needs root), and the real-PMU Linux box for the perf_event_open live path (§3.3); AVX2 and
rdpmc fast path stay bench-gated round-2 items.

## 0. What exists today (findings, verified)

- `src/infra/profilePmc.h` is the PMC backend behind a deliberately tiny surface
  (`ensure_thread_counting() / read() / active() / event_count() / event_name() / event_label()`,
  shared `Snapshot { uint64_t values[kMaxEvents=8] }`). The whole Apple-silicon kperf/kpep
  implementation lives inside `#if defined(__APPLE__) && arm64`; everything else gets inert stubs
  (`active()==false`, `read()` returns zeros) and the timing path stays intact. The header's own
  WHY section says this boundary exists precisely so another backend can slot in.
- `src/infra/profileScope.h` brackets each scope with two `pmc::read()` calls, gated by
  `PROFILE_PMC` (defaults to `PROFILE_ENABLED`, i.e. `-DRIPWIRE_PROFILE=ON` builds only). Only the
  outermost frame of a recursive site samples. Deltas of monotonic per-thread counters — any
  backend that returns monotonic per-thread values satisfies the contract.
- `src/infra/dynamic_map.hpp` is a B+ tree whose only SIMD is the per-node rank kernel
  `node_rank<Key,B>::lt/le` (count of keys `<` / `<=` x over all B slots, sentinel-padded). The
  scalar template is the portable contract; `#if DYNMAP_HAS_NEON` (aarch64 only today) provides
  128-bit specializations for i32/u32/f32 (4 lanes) and i64/u64/f64 (2 lanes) via the
  count-of-true-lanes trick. Nodes are `alignas(16)` with keys first — a 128-bit x86 kernel needs
  **zero layout changes**. `B` is static-asserted to be a multiple of `16/sizeof(Key)`.
- Production instantiation: `src/quality.h:113` — `dynamic_map<std::uint64_t, Value, 32>`.
  **u64 is the kernel that matters**; on SSE that is the hardest one (no unsigned 64-bit compare
  until SSE4.2's `_mm_cmpgt_epi64` + sign-bias trick).
- Tests: no scalar-vs-SIMD parity gate exists for `node_rank` (NEON is trusted by construction).
  `bench/bench_ordered_map.cpp` is the perf harness. Hardware-dependent gate precedent:
  `test/cudacheck.sh` skips cleanly when the hardware/toolchain is absent. New `test/*check.sh`
  must be added to `test/regression.sh` in the same commit (manifestcheck).

## 1. Feature A — Linux/x86 perf-counter backend for profilePmc.h

### Design

Add a second real backend inside profilePmc.h's existing `#if` ladder:

```
#if   __APPLE__ && arm64      → kperf/kpep (unchanged)
#elif __linux__               → perf_event_open backend (new)
#else                         → inert stubs (unchanged)
```

- **Events**: same logical selection & labels as the Apple side (cycles, instructions,
  branch-misses, cache-misses) via `PERF_TYPE_HARDWARE`. Per-event graceful skip, same as the
  kperf side: an event that fails `perf_event_open` drops a column; bail to `active()==false`
  only if nothing opens. Keep the default selection ≤ 4 events so nothing multiplexes
  (cycles/instructions land on fixed counters on Intel; 2 programmable left for the misses).
- **Group the events (Filament pattern — see reference below)**: open the first surviving event
  as group leader (`disabled=1`), each follower with `group_fd=leader`, leader `read_format =
  PERF_FORMAT_GROUP | PERF_FORMAT_ID | PERF_FORMAT_TOTAL_TIME_ENABLED | TOTAL_TIME_RUNNING`, one
  `ioctl(PERF_EVENT_IOC_ENABLE, PERF_IOC_FLAG_GROUP)` at arm time. Two wins: the kernel schedules
  the group **atomically** (all counters cover the same instruction window — no cross-column
  skew), and the syscall fallback becomes **one `read()` for all events** instead of N. The
  kernel returns group members in its own order with ids — build a slot→position map at init,
  which is the exact analogue of the kperf side's `kpc_map` (keep the naming symmetry). A
  follower that fails to open into the group is skipped (column dropped), same rule as above.
- **Per-thread**: `perf_event_open(pid=0, cpu=-1, inherit=0, exclude_kernel=1, exclude_hv=1)`,
  fds + mmap pages held in `thread_local` state; `ensure_thread_counting()` does the per-thread
  open, mirroring the kperf side's shape. `exclude_kernel=1` means `perf_event_paranoid=2`
  (the Ubuntu default) is sufficient — no root, no CAP_PERFMON.
- **Hot path**: mmap each event's `perf_event_mmap_page` and read userspace via the seqlock +
  `rdpmc` protocol (x86_64 only): `lock/index/offset` loop, sign-extend the raw PMC by
  `pmc_width`, add `offset`. If `cap_user_rdpmc==0` or `index==0`, fall back to the `read()`
  syscall on the fd (correct everywhere, just heavier — same "far heavier than the timing path"
  caveat the kperf backend already documents). Non-x86 Linux gets the syscall path only.
- **Honesty (non-negotiable #3)**: if `time_enabled != time_running` on a snapshot (the kernel
  multiplexed after all), do NOT silently scale — drop that column for the run and say so in the
  banner. No surface that quietly guesses.
- **Degrade**: EACCES/ENOENT/EPERM → `active()==false`, silent by default, traced under the
  existing `PROFILE_PMC_VERBOSE`. This is normal operation (same posture as unprivileged macOS),
  not a `DEGRADED_PATH_ALERT` case.
- `Snapshot`, `kMaxEvents`, and every accessor keep their exact signatures — profileScope.h
  should need **zero changes** (verify; if any, they're `#if PROFILE_PMC` cosmetics only).

### Reference implementation: Filament utils::Profiler (Apache-2.0)

`google/filament` → `libs/utils/include/utils/Profiler.h` + `libs/utils/src/Profiler.cpp` is a
battle-tested perf_event_open scope profiler and the closest prior art to what Feature A builds.
Adopted from it: the group-leader + `PERF_FORMAT_GROUP|ID|TOTAL_TIME_*` read shape (above), the
per-event enabled-bitmask graceful skip (identical in spirit to our kperf skip), and its richer
event menu — `PERF_TYPE_HW_CACHE` encodings (`cache | op<<8 | result<<16`) for L1D/L1I
refs/misses, with `PERF_TYPE_RAW` ARMv8 PMU codes as the ARM-Linux fallback — worth keeping in
the event table as optional rows beyond the default 4 (the table is declarative; adding rows is
free, the PMC budget decides what survives). Its derived metrics (IPC, MPKI, miss rates) are a
report-side nicety to consider once raw columns land. NOT adopted: its start/stop-per-measurement
ioctl model — ripwire's scope profiler brackets nested scopes with reads against free-running
counters, so counters stay enabled from arm time (one group ENABLE) and never toggle per scope.
If the code shape is followed closely, add a CREDIT comment at the top of the Linux section
(house pattern — the kperf side credits lib_kperf the same way) and a THIRD_PARTY.md row.

### Gates (written FIRST — non-negotiable #1)

- `test/pmccheck.sh`: builds a `RIPWIRE_PROFILE=ON` binary, runs it, and asserts one of exactly
  two honest outcomes: (a) counters active → counter columns present and every reported delta
  plausible (instructions > 0 for a non-trivial run; rdpmc value cross-checked against a `read()`
  syscall on the same thread — catches the classic pmc_width sign-extension bug); (b) counters
  unavailable → columns absent, exit clean, no stderr spam. Skips like cudacheck when the
  platform can't even attempt it. Listed in `test/regression.sh` same commit.
- Degrade matrix run manually on the server: `perf_event_paranoid` 2/3 (3 = -1 for everything →
  must go inactive), `/sys/devices/cpu/rdpmc` 0 (syscall fallback path), event blacklisting
  (unplumb one event name → column drops, run survives).

## 2. Feature B — x86 (SSE) rank kernels for dynamic_map

### Design

Purely additive `#elif` block parallel to the NEON one — no node-layout, width, or API changes:

- `#elif defined(__x86_64__) || defined(_M_X64)` → `DYNMAP_HAS_SSE 1`, `<emmintrin.h>` etc.
- Same accumulate-true-lanes structure as NEON (`acc = _mm_sub_epi32(acc, cmp)` since a true lane
  is −1; one horizontal sum at the end). B is already a multiple of the 128-bit lane count.
- Per key type:
  - `i32`: `_mm_cmplt_epi32` (lt); `le = B_slots_scanned − count(gt)` via `_mm_cmpgt_epi32`.
  - `u32`: XOR-bias both sides with `0x80000000`, then the signed compares. (SSE2 baseline.)
  - `f32/f64`: `_mm_cmplt_ps/pd`, `_mm_cmple_ps/pd` directly. NaN never occurs (sentinel is a
    real max value), and `cmplt` matches scalar `<` semantics anyway. (SSE2 baseline.)
  - `i64/u64`: needs `_mm_cmpgt_epi64` → **guard with `#if defined(__SSE4_2__)`** (u64 = sign-bias
    + cmpgt). Below SSE4.2 these fall back to the scalar contract automatically.
- **Decision point**: the production key is u64, and a stock `-march=x86-64` build doesn't define
  `__SSE4_2__` — the kernel that matters would stay scalar. Recommendation: bump the x86 baseline
  in CMakeLists to `-march=x86-64-v2` (Nehalem 2008+; every distro that matters has moved or is
  moving there). Alternative if unpalatable: leave baseline alone and document that
  `RIPWIRE_NATIVE=ON` (already exists) lights up the 64-bit kernels.
- AVX2 (256-bit) is **round 2, bench-gated**: Rosetta support for AVX2 is uncertain (can't
  pre-validate locally) and Algorithmica saw no throughput win from wider nodes — but AVX2 is
  where the production u64 key gets interesting (4 lanes via `_mm256_cmpgt_epi64` + sign-bias vs
  SSE4.2's 2). Nodes are alignas(16), so an AVX2 kernel uses `loadu` (16-aligned unaligned loads
  are near-free on modern cores) rather than forcing an alignas(32) layout change. Decide with
  bench_ordered_map numbers from the real box, not by assumption.

### Ideas adopted from Algorithmica's S-tree write-up (en.algorithmica.org/hpc/data-structures/s-tree/)

- **Rank by popcount-of-movemask, not tzcnt.** Their fastest S+ tree kernel
  (`packs_epi32` → one `movemask_epi8` → `tzcnt`) is order-dependent and forces a permuted node
  layout. But a **popcount-based rank is order-independent**, which they themselves note as the
  permutation-free alternative — and it is exactly the count-of-true-lanes contract our scalar
  template and NEON kernels already implement. So dynamic_map keeps its sorted, sentinel-padded
  layout untouched; the x86 kernel is `cmp → movemask → popcount` (or the NEON-mirroring
  vector-accumulate + one horizontal sum — pick whichever benches better at B=32; movemask has
  fewer uops per vector, accumulate has fewer total reductions).
- **Their headline numbers are int32 at B=16 (one cache line of keys).** Our production node is
  u64 × B=32 = 256 B of keys = 4 cache lines per node scan — expectations for the SSE win should
  be calibrated to that (2 lanes per vector, 16 vectors), which is another reason the u64 AVX2
  kernel (8 vectors) is the interesting round-2 measurement, possibly alongside a B=16-for-u64
  width experiment in the bench (width is a template param; trying it costs one bench line, not
  a layout change).
- **Round-2 candidates from the same article, all bench-gated:** explicit child-node prefetch
  during descent (they report it keeps ~15× with pointer-chasing trees), hugepage-backed node
  pool on Linux (`madvise(MADV_HUGEPAGE)` — allocation-side only, zero structural change), and
  branchless fixed-height descent (structural; only if profiling shows descent branches matter).
- **Not applicable:** their float-key epsilon/bit-trick (we compare floats directly with
  `cmplt_ps/pd`, no subtract-one hack needed); the permuted-node layout (see popcount point).

### Gates (written FIRST)

- `test/dynmapsimdcheck.sh` + a small standalone binary (house pattern: `DYNMAP_VERIFY` stays
  live): exhaustive parity of `node_rank<K,B>::lt/le` SIMD-vs-scalar for every key type × every
  legal B × adversarial patterns (all-sentinel, all-equal, x below/above/equal every slot,
  sign-boundary values ±2^31/±2^63, random sweeps with fixed seed). This gate is
  **architecture-portable** — on arm64 it verifies the existing NEON kernels (new coverage for
  free), on x86 the new SSE ones. Listed in `test/regression.sh` same commit.
- Determinism + xmllint gates re-run on x86 (integer kernels can't disturb output, prove it
  anyway). ASan/UBSan build on x86 Linux over the parity binary and a full corpus run.

## 2b. Feature C — x86 equality for FixedStr

`src/fixedStr.h` — 32-byte alignas(16) short string; only `operator==` is SIMD (NEON: two
16-byte loads, `vceqq`+`vandq`, `vminvq==0xFF`). The hash and construction are already portable.
The existing `#else` fallback (4×u64 XOR-fold) is branchless and decent — this is a small,
measured win, not a correctness gap.

- `#elif defined(__SSE2__)`: two `_mm_load_si128` (alignas(16) ⇒ aligned loads are legal),
  `_mm_cmpeq_epi8`, `_mm_and_si128`, `_mm_movemask_epi8(eq) == 0xFFFF`. Len byte participates,
  same as NEON.
- Optional `#if defined(__AVX2__)` above it: one `_mm256_loadu_si256` (object is 16-aligned, not
  32) + `_mm256_cmpeq_epi8` + `movemask == -1`. Bench-gated like the rest of the AVX2 story.
- Header stays vendorable: standard library + optionally `<arm_neon.h>` / `<emmintrin.h>` only.
- **Gate first**: fold into the same parity binary as the dynamic_map kernels — SIMD `==` vs the
  u64-fold reference over: equal pairs, every single-byte difference position (0..31 including
  the len byte), same-prefix/different-len, truncation boundary (31/32-char inputs), zero-pad
  invariant (construct → bytes past len are zero), and hash consistency (a==b ⇒ hash equal).
  `bench/bench_fixedstr.cpp` already exists for the before/after numbers.

## 3. Remote Linux — what actually needs it (the "ubuntu server?" question)

Three different environments, in escalating order of need:

1. **Local x86 emulation (no server): most of Feature B.** colima/Docker with
   `--platform linux/amd64` runs x86_64 Ubuntu under Rosetta — SSE2/SSE4.2 work there, so the
   SSE kernels' compile + parity gate + ASan/UBSan can all be validated locally before any server
   exists. (Same rig as the Linux LSan gate recipe.) What it can NOT do: real performance numbers
   (it's translation), possibly AVX2, and **no PMU at all** — perf_event_open hardware events
   don't exist under emulation, so Feature A only exercises its degrade path here (which is
   itself worth a run).
2. **Any cheap Ubuntu x86 VPS: builds, gates, and Feature A's *degrade* validation.** Most KVM
   VPSes don't expose a vPMU, so `PERF_TYPE_HARDWARE` opens fail → the backend must go
   `active()==false` silently. That's a required test, but it never proves the live path.
3. **Real PMU for Feature A's *live* path — this is the machine that matters.** Options, best
   first: (a) Hetzner dedicated (AX/EX line) or any bare-metal host — full PMU, rdpmc, cheap by
   the hour is not a thing but monthly is ~€40; (b) AWS `*.metal` or a full-socket Nitro size —
   PMU exposed, hourly billing; (c) a borrowed physical x86 Linux box. First command on any
   candidate, before writing code for it:
   `perf stat -e cycles,instructions,branch-misses,cache-misses true` — if that reports
   `<not supported>`, the box is tier-2, pick another. Also record
   `cat /proc/sys/kernel/perf_event_paranoid` (expect 2) and `cat /sys/devices/cpu/rdpmc`
   (expect 1 = rdpmc allowed for mmap'd events; 0 forces the syscall fallback).
- **Workflow**: push a branch, clone/pull on the box (repo is public), build BOTH flavours —
  plain (degrade paths live) and Release (optimizer bugs) — run `python3 test/pargates.py`,
  the two new gates, ASan/UBSan, LSan with the committed suppressions, and
  `bench/bench_ordered_map` before/after for the SSE numbers.

## 4. Ordered steps

1. **Env bring-up (parallel with everything):** stand up the amd64 Rosetta container locally;
   provision the PMU-capable box and run the probe checklist (§3.3). Decide box tier from the
   probe, not the price page.
2. **Gates first:** write `test/dynmapsimdcheck.sh` (+ parity binary, covering both the
   dynamic_map rank kernels and FixedStr equality/hash invariants) and `test/pmccheck.sh`;
   wire both into `test/regression.sh`; run on macOS — the parity gate must already pass against
   NEON, pmccheck exercises its skip/degrade arms. Commit.
3. **Features B + C:** SSE2/SSE4.2 `node_rank` block and the FixedStr SSE2 `operator==`;
   baseline decision (`x86-64-v2` vs `RIPWIRE_NATIVE` docs). Validate in the Rosetta container:
   parity green, ASan/UBSan clean. Bench (`bench_ordered_map`, `bench_fixedstr`) on the real box
   once it exists. Commit.
4. **Feature A:** restructure the profilePmc.h `#if` ladder; implement perf_event_open backend
   (syscall read first — correct everywhere; then the rdpmc fast path with syscall
   cross-check). Degrade matrix on the VPS-tier environment, live-path validation on the PMU box.
   Commit.
5. **Full sweep on the PMU box:** pargates, determinism diff, xmllint, ASan/UBSan/LSan, both
   build flavours, `RIPWIRE_PROFILE=ON` run showing per-scope counter columns.
6. **Docs:** `bench/PROFILE.md` (new backend + its privilege/availability story),
   `docs/ARCHITECTURE.md` if it names the PMC layer, CHANGELOG. `--quality-delta` then
   `--test-gate` before calling it done.

## 5. Risks / honesty notes

- **rdpmc sign-extension** (`pmc_width < 64`) is the classic silent-corruption bug — the gate's
  rdpmc-vs-syscall cross-check exists specifically for it.
- **Multiplexed counters lie.** The ≤4-event default plus the drop-column-if-scaled rule keeps
  reported deltas raw and true; never scale silently.
- **Rosetta ≠ x86.** Anything Rosetta-validated is correctness-only; every performance claim
  comes from the real box.
- **u64 below SSE4.2 stays scalar** unless the baseline decision (§2) is taken — without it,
  Feature B doesn't touch the production instantiation on default builds.
- **kperf side untouched**: the only shared code is the `Snapshot`/accessor surface at the top of
  profilePmc.h; the Apple `#if` body must not move (keeps the diff reviewable and the blame
  history clean).
