# Teach the string kernels a new instruction set: AVX-512 or RISC-V Vector

You are adding a vector path to `src/infra/strkern.h`, the one header that holds every byte-parallel
string kernel ripwire ships. Today each kernel has three mirrored bodies: NEON, AVX2 and a scalar
twin. You are adding a fourth. It is either **AVX-512**, compiled only where the compiler targets it
and never the default floor, or **RISC-V Vector (RVV)**. Call it **ISA** below.

The intrinsics are not the hard part. The hard part is proving, on hardware most CI does not have,
that the new path returns exactly the bits the scalar twin returns. Then you have to measure whether
it is faster at all.

Work in a git worktree, not the main checkout. Run gates in the foreground.

---

## Why this matters

These kernels sit under the text-scanning half of every retrieval verb:

- the query-time tokenizer (`src/lexindex.h`);
- the BM25 scan (`src/lexical.h`);
- the XML and JSON escapers (`src/serialize.h`, `src/infra/jsonesc.h`).

PR #127 moved them from per-byte loops to mask algebra. Warm `--pack-task` went from 8.13 to 5.88 s
CPU on golang/go (−27.6%), −10.9% on rocksdb and −15.5% on ripwire's own tree. Every output stayed
`cmp`-identical.

That work does not reach two kinds of machine yet:

- **x86 servers with AVX-512.** AVX-512BW is part of the x86-64-v4 level (AVX512F/BW/CD/DQ/VL). That
  level lines up with Intel's 2017 Skylake-X generation and is supported by AMD from Zen 4 on
  ([x86-64 microarchitecture levels](https://en.wikipedia.org/wiki/X86-64#Microarchitecture_levels)).
  Shared machines that index large trees are often machines like these.
- **RISC-V application processors.** The RVA23 profile was ratified in October 2024. It makes the V
  extension mandatory for application processors that follow it
  ([RISC-V International](https://riscv.org/blog/risc-v-announces-ratification-of-the-rva23-profile-standard/)).
  On such a machine ripwire runs its scalar twins today. An RVV path makes text scanning fast there
  as the hardware arrives.

**The counterweight — answer it, don't ignore it.** `cmake/PortableFlags.cmake` says of x86-64-v4:
"NEVER v4 (AVX-512): the downclocking and the fragmented server support make it a portability loss,
and nothing here is 512-bit-shaped."

- The **floor** stays v3. This kit does not revisit that.
- Whether nothing here is 512-bit-*shaped* is a claim you can measure.
- If you measure it true, that negative result is a deliverable. Honest counterexamples belong in
  `docs/EVALS.md` §7.

---

## STEP 0 — the measurement that decides whether to start

**Before writing an intrinsic, find out how much of a verb the kernels are.** The F3 lesson (PR #107,
restated at the top of `strkern.h`): a compare that decides at byte 0 or 1 is call overhead, not
string work, and widening it loses. SIMD pays only inside a loop that touches every byte.

1. Build plain (no build type). Pick invocations that reach the kernels:
   - warm `--pack-task="<task>"`;
   - warm `--for="<task>"`;
   - a warm map with `--top-k=100000`, which reaches the escapers;
   - warm `--grep=<literal>`.
2. Profile each on a mid-size corpus ([golang/go](https://github.com/golang/go)) and on the scale
   rung ([llvm/llvm-project](https://github.com/llvm/llvm-project)).
   - Linux: `perf record -g`.
   - macOS: `sample`, or Instruments' Time Profiler.

   Report two shares of busy samples: inside `rw::strkern::` functions, and inside
   `forEachLexTokenSpan`, whose block walk calls `classMasks`.
3. Work out the ceiling. If the kernels are 3% of a verb, a path twice as fast buys at most 1.5%.
   `strkern.h` records a real case:
   - The run-copy rewrite cut 15–23% from escapeXml.
   - escapeXml is about 1% of a warm map, so that is ~0.2% of the verb.
   - An interleaved whole-verb A/B, 12 runs a side, could not resolve it, so no verb number was
     claimed.

Write the shares and the ceiling into the plan. If the ceiling is small, the plan says so. Either
stop there, or pick the kernel with the largest share and justify it.

---

## Background — the kernel contract, read off the source

Read `src/infra/strkern.h` top to bottom before designing anything. It states this contract, and the
gate enforces it:

- **One header, paths side by side.**
  - No SIMD intrinsic for string work lives anywhere else.
  - `kPathName` names the compiled path: `NEON`, `AVX2` or `scalar`.
  - `kBlockBytes` is 16 on NEON, 32 on AVX2 and 16 on scalar. `kMaxBlockBytes` is 32.
- **The preprocessor selects a path at compile time.** The chain is `#if defined( __ARM_NEON )`, then
  `#elif defined( __AVX2__ )`, then the scalar `#else`. There is no runtime dispatch, on purpose.
  `cmake/PortableFlags.cmake` gives the reason: "a dispatch table is a second code path nothing here
  would keep honest".
- **`( const char*, std::size_t )` only.**
  - No kernel takes a NUL terminator or a `std::string`, and none reads past `p + n`.
  - `classMasks` copies a short block into a zero-filled stack buffer. A zero byte classifies as a
    separator, so the padding cannot invent a class bit.
- **The scalar twins are always compiled.** They are portable C++: no intrinsic, no UB, every wide
  read through `std::memcpy`, trailing zeros through `std::countr_zero`. The gate refuses any
  `__builtin_`.
- **Integer and exact.** A kernel returns a bit pattern, so every path returns identical values for
  identical input (`docs/ARCHITECTURE.md` §3, the determinism contract).
- **The kernels.**
  - `classMasks` fills `Masks { alnum, upper, lower, digit }`: four `std::uint32_t`, one bit per byte,
    zero at and above `n`. It is built on a two-stage nibble table.
  - `lowerFoldAscii` / `lowerFoldedEquals` fold A–Z only and leave bytes ≥ 0x80 alone.
  - `findByte` / `find3` / `findByteset` return the first index, or `n`, never `npos`.
  - `Byteset256` carries two derived representations: `bits` for vector lookups, `words` for the
    scalar tail. A tail that re-derived the set on every call once took escapeXml from 4.62% to 22.46%
    of a warm map (the note above `Byteset256`).
  - `appendCleanRun` is the escapers' run-copy step.
- **`STRKERN_MUTATE`** breaks details the scalar oracle does not share:
  - one nibble-table bit;
  - the fold span;
  - `findByteset`'s high half;
  - the high half of `Byteset256::words`.

  A mutated build must fail. That failure is the gate's proof that the parity assertions bind.

**Where a wider block would reach.** `forEachLexTokenSpan` in `src/lexindex.h` walks `kBlockBytes` at
a time. Three carries cross the block seam: the previous byte's alnum bit, its upper bit, and whether
the byte after the block is lowercase.

Two expressions there exist only because a 32-byte block fills a `std::uint32_t`:

- The `valid` mask special-cases `width >= 32`, because `1u << 32` is undefined.
- `kBelowTop` clears the top bit before `<< 1`, because `-fsanitize=integer` rejects an unsigned shift
  that loses a set bit.

That shift did reach CI in #127. NEON's 16-bit masks never have a bit there to lose, and the x86
mirror first ran without sanitizers.

A 64-byte AVX-512 block makes `Masks` 64 bits wide, which moves both traps to bit 63. It also changes
the type of every expression in a walk that NEON and AVX2 still run.

**The gate.** `test/strkerncheck.sh` drives the doctest target `ripwire_test_strkern`
(`test/verify_strkern.cpp`; configure with `-DRIPWIRE_TESTS=ON`).

The TU compares every kernel with its scalar oracle over three inputs:

- all 256 byte values, at every offset and length;
- a fixed-seed sweep of 100k random buffers, lengths 0..300, drawn from four alphabets;
- every byte of `src/` and `docs/`.

The tokenizer cases (F1, F2, G4) compare spans and fused hashes against verbatim copies of the
pre-mask walkers. A compiled-path case prints `strkern path: NEON|AVX2|scalar`.

The script builds that target three times, and each build answers a different question:

- **Arm 1** builds the target under the full G1 sanitizer stack. It requires the assertion count to
  be at least a floor.
- **Non-vacuity** requires the banner to say NEON on arm64 and AVX2 on x86_64. A scalar-only build
  on those architectures compares the oracle to itself and proves nothing.
- **The portability arm** reads the source. It requires zero `__builtin_`, at least eight
  `std::countr_zero(` sites and `#include <bit>`.
- **Arm 2** builds with `-DSTRKERN_MUTATE=1` and must go red.
- **Arm 2b** requires the mutated build's `strkern sweep-rng:` line to equal the green build's. That
  shows the red run swept the same corpus.
- **Arms 3, 3b and 3c** run an x86_64 mirror under Rosetta 2, on arm64 hosts only. First comes a
  probe:
  - It is compiled with `-march=x86-64-v3` and touches every v3 extension.
  - It is then disassembled. The gate requires ymm, pdep, pext, lzcnt, tzcnt, vfmadd and F16C opcodes
    before it trusts the exit code.

  If the probe runs, the v3 slice runs. Otherwise the x86-64 baseline slice runs, which means the
  scalar twins. Either slice runs three ways: under the same assertions (3), under UBSan's integer
  checks (3b), and under a mutation control that must fail on its own assertions (3c). A SIGILL can
  never satisfy the control. Only an exec-format failure counts as a SKIP.

**The build flags.** `cmake/PortableFlags.cmake` sets `-march=x86-64-v3` for every x86-64 build, and
`-march=native` when `-DRIPWIRE_NATIVE=ON` is set (dev machines only). `test/portablebuildcheck.sh`
includes that module and inspects the flags it produces.

**What `-march=native` does on an AVX-512 host.** It defines `__AVX512BW__`. A path selected by
`#if defined( __AVX512BW__ )` therefore compiles into every native dev build on that host. The
non-vacuity arm expects `AVX2` on x86_64, so it fails. The plan must say what the banner prints and
what that arm expects.

---

## How to verify on hardware CI does not have

**Be honest about CI first.**

- GitHub-hosted runners come in x64 and arm64 only; there is no RISC-V runner
  ([GitHub docs](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)).
- AVX-512 on the x64 runners is not guaranteed.
  [actions/runner#1069](https://github.com/actions/runner/issues/1069), the request to let jobs select
  AVX-512 runners, is closed.
  [runner-images discussion #5734](https://github.com/actions/runner-images/discussions/5734) shows
  `avx512f` turning up on some runners.

So a CI arm can always **compile** the new slice, and **disassemble** it to prove the opcodes are
present. It can **execute** the slice only where the host says yes at run time. Where it cannot, the
arm prints SKIP with the reason, never PASS.

**AVX-512**

- **Real hardware.** Use any Linux x86-64 host whose `/proc/cpuinfo` flags include `avx512bw`, plus
  `avx512vl` if you use 256-bit masked forms. Name the CPU model in the PR.
- **The [Intel Software Development Emulator (SDE)](https://www.intel.com/content/www/us/en/developer/articles/tool/software-development-emulator.html).**
  - It emulates AVX-512, AVX10.2 and APX on Intel 64 hosts, under the Intel Simplified Software
    License. Read that license yourself before downloading.
  - The documented invocation is `sde [sde args] -- app [app args]`.
  - Run the doctest target under it, both green and mutated.
- **Do not assume Rosetta 2 can run an AVX-512 slice.** The existing probe checks v3 only. If you
  extend the mirror, add a probe in the same style: the slice's own `-march`, every extension touched,
  the binary disassembled. Then let the probe decide.

**RVV**

- **Toolchain.** Use Ubuntu 24.04 in a container or VM. It packages
  [`g++-14-riscv64-linux-gnu`](https://packages.ubuntu.com/noble/g++-14-riscv64-linux-gnu) (GCC 14.2)
  and [`qemu-user`](https://packages.ubuntu.com/noble/qemu-user) (QEMU 8.2.2).
- **Intrinsics.** The RVV C intrinsics specification is at v1.0, supported by GCC 14 and Clang 19
  ([rvv-intrinsic-doc](https://github.com/riscv-non-isa/rvv-intrinsic-doc)). Guard
  `#include <riscv_vector.h>` with `__riscv_v_intrinsic >= 1000000`, as the specification suggests.
- **Build.** Use the cross compiler that package installs, with `-march=rv64gcv -O2`. Pass the same
  sources and include directories `strkerncheck.sh` uses for its direct builds.
- **Run.** `qemu-riscv64 -L /usr/riscv64-linux-gnu -cpu rv64,v=true,vlen=256 ./verify_strkern`.
  QEMU's RISC-V CPU has a `vlen` property whose default is 128 (`target/riscv/cpu.c` at v8.2.2).
- **The VLEN matrix is the determinism arm.** RVV code is vector-length agnostic, so one binary must
  return identical results at `vlen=128`, `256` and `512`. Run all three, green and mutated. A
  chunking choice that moves a carry at only one VLEN is exactly the bug this arm exists to catch.
- **Real hardware.** If you have an RVA23 machine it is a bonus row, not a requirement. Name the
  board and kernel.

**Emulators prove correctness, never speed.** SDE and QEMU run far slower than silicon, and the
slowdown differs from instruction to instruction. A speed-up measured under an emulator is not a
result, and the PR must not report one.

---

## Design space and constraints

**Constraints — CLAUDE.md, not negotiable**

- **Determinism is a contract.**
  - The new path returns exactly what the scalar twin returns.
  - Verb output is byte-identical across ISAs, VLENs and repeated runs.
  - No floating point enters a kernel.
- **G1.** The full sanitizer stack applies, including `-fsanitize=integer` with
  `-fno-sanitize-recover=all`. A cross-ISA or emulated arm carries every sanitizer its runtime
  supports, and never fewer than arm 3b's `undefined,integer`.
- **G2/G3.**
  - Selection happens at compile time; there is no runtime CPU-dispatch layer.
  - No new dependency.
  - Everything stays in one header, and the scalar twin stays compiled and callable.
- **The x86-64 floor stays `-march=x86-64-v3`.** That is an owner decision. AVX-512 is opt-in.
- **Never `VERIFY( false )` on a degrade path.** Use `DEGRADED_PATH_ALERT`.
- **Style** follows `CONTRIBUTING.md` §3.
- **No perf-budget gate.** No gate may fail on a timing threshold. The gates are the parity,
  mutation, non-vacuity and opcode-presence arms. Speed is a reported measurement.
- **Quality first.** If the new path does not make a verb faster, do not ship it to win a
  microbenchmark. Record the negative result instead.

**AVX-512 options, in order of blast radius**

1. **256-bit AVX-512BW+VL.**
   - Byte compares return `__mmask32` directly (`_mm256_cmpeq_epi8_mask`, which GCC declares under
     `target("avx512vl,avx512bw")`). That drops the movemask-and-invert steps.
   - `kBlockBytes` stays 32 and `Masks` stays 32 bits wide, so `src/lexindex.h` is untouched.
   - The only question is whether fewer instructions per block measure faster.
2. **512-bit blocks with `__mmask64`.**
   - `Masks` widens to 64 bits and `kMaxBlockBytes` to 64.
   - The tokenizer's `valid`, `kBelowTop` and carry expressions change type on every path.
   - This has the largest possible win on long texts, and the largest review.
   - Doing it well includes proving, byte for byte, that NEON and AVX2 spans are unchanged.
3. **Masked loads for the tail instead of the padded copy.**
   - Any argument that a masked load "cannot fault" must still survive arm 1's ASan run.
   - It must never read memory ASan considers out of bounds. Otherwise keep the copy.

**How the path is switched on.** On an AVX-512 host, `-march=native` already defines `__AVX512BW__`.
A shippable opt-in needs a named CMake option in `cmake/PortableFlags.cmake`, for example one that
selects `-march=x86-64-v4`, and `test/portablebuildcheck.sh` must see that option. Put the option's
name in the plan as a question for the owner.

**RVV options**

- **RVV has no movemask.** A mask reaches scalar code in one of three ways: a first-set-bit query
  (`vfirst`), a population count (`vcpop`), or by materializing it.
- **The find kernels and the fold map onto that naturally. `classMasks` does not:** the tokenizer
  consumes its per-byte bitmask as integer algebra.
- **A first PR can vectorize only `findByte`, `find3`, `findByteset` and `lowerFoldAscii`.** That is
  legitimate. `classMasks` stays on the scalar twin, and the banner says which kernels are
  vectorized. Do not claim the whole header.
- **`kBlockBytes` is a compile-time constant the tokenizer relies on; hardware VLEN is not.** Either
  chunk at a fixed width every VLEN supports, or prove that a variable chunk leaves every carry
  unchanged. The VLEN matrix is how you prove it.
- **Branch ordering.** `strkern.h` checks `__ARM_NEON` first, then `__AVX2__`, then falls to scalar.
  `__AVX2__` is defined whenever `__AVX512BW__` is, so an AVX-512 branch must come **before** the AVX2
  branch. An RVV branch needs its own test macro.

---

## Acceptance criteria

1. **Parity on the new path.**
   - Every existing TEST_CASE passes.
   - The assertion count stays at or above the floor.
   - `strkern path:` names the new path, and which kernels it covers if not all of them.
2. **It can go red.**
   - `STRKERN_MUTATE` gains a mutation in every new vector body, one the scalar oracle does not share.
   - The mutated build fails.
   - Its `strkern sweep-rng:` line equals the green build's.
3. **Opcode presence.**
   - The new slice is disassembled before any exit code counts. It must contain the ISA's own
     instructions: zmm registers or k-mask operations for AVX-512, `vsetvli` and vector operations for
     RVV.
   - A slice the compiler folded to scalar turns this arm red. Show that red once.
4. **Honest execution arms.**
   - The slice runs wherever it can: on real hardware, under SDE, and under `qemu-riscv64` at three
     VLENs.
   - Exec-unavailable is a SKIP with a reason.
   - A slice that ran and exited nonzero is a FAIL.
   - The mutation control fails on its own assertions, never on SIGILL.
5. **Existing arms stay green.**
   - NEON on arm64, v3 on x86-64, the Rosetta mirror, and the portability arm.
   - `test/portablebuildcheck.sh` passes if `PortableFlags.cmake` changed.
   - A new `test/*check.sh` is listed in `test/regression.sh` in the same commit
     (`test/manifestcheck.sh` enforces this).
6. **Verb output is byte-identical to a v3 or NEON build.**
   - Corpora: ripwire's own tree, golang/go and llvm-project.
   - Verbs: map, `--for`, `--pack-task`, `--grep`, `--lint`.
   - Compare with `cmp`.
7. **Measured on silicon.** An interleaved A/B table on the target hardware:
   - CPU as user+sys, same argv, median and min over n pairs;
   - load recorded, output identical;
   - the verbs that did not move included;
   - no emulator numbers.
8. **Lineage.** `docs/LINEAGE.md` gains a row only for a source whose technique is in the shipped
   code, the rule #127 applied.

---

## Known traps — each one already cost somebody a day here

- **A probe the compiler folds.** The first Rosetta probe was one AVX2 add compiled with `-mavx2`.
  clang turned it into a scalar `addb`, and it printed "ok" on every host. Disassemble.
- **Emulation lies to the OS.** Under Rosetta, `arch -x86_64 sysctl hw.optional.avx2_0` printed 0 on
  a host whose Rosetta ran the v3 slice green. Execute an instruction; don't ask the OS.
- **SIGILL satisfies "nonzero exit".** A mutation control must require the mutation's own assertion
  failure.
- **Cross-ISA without sanitizers.** The shift that lost bit 31 existed only on full-width masks. Your
  widest mask is where the next one will be.
- **A native build silently changes the compiled path.** See the `-march=native` note above.
- **A kernel win is not a verb win.** A 15–23% cut in escapeXml was ~0.2% of the verb.
- **Widening a short, early-deciding compare loses.** `lowerFoldedEquals` ships unwired for exactly
  that reason (F3, PR #107).
- **Per-call preamble in a tail.** 4.62% → 22.46%, `Byteset256`.
- **Mixed objects after a branch switch.** CLAUDE.md's `sizeof(Symbol)` stories apply to a kernel
  header as much as to the model. When in doubt, `cmake --build build --clean-first -j`.
- **Emulator timings.** Never publish one.

---

## What the PR description should contain

- **Scope.** The ISA, which kernels are vectorized, and which stay scalar and why.
- **STEP 0.** The profile share and the ceiling for each verb and corpus.
- **Environments.** For every execution row: compiler versions, the host CPU model, or the emulator
  and its version. For RVV, the VLEN matrix.
- **Red runs.** The mutated build's failing output. The opcode-presence arm red on a folded or absent
  slice.
- **Byte-identity.** The list of corpus × verb pairs compared.
- **Speed.** The silicon A/B table, including the verbs that did not move. If the answer is "not
  faster", that is the headline, and the path does not ship.
- **CI.** What CI can compile, disassemble and execute, stated plainly.
- **Owner questions.** The CMake option's name, and whether an emulated CI leg is wanted.

---

**Write the plan — the ISA, the STEP 0 numbers, the kernels in scope, the arms, and the hardware or
emulator each arm will run on — then STOP for my go-ahead.**
