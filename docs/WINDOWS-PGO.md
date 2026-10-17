# Windows clang-cl PGO workaround

## Scope and observed failure

PR #410 (split from #402) covers **clang-cl on Windows**, tested with LLVM
22.1.8 on Windows 11 / x64, targeting `x86_64-v3`. It does not change the
GNU-style `clang++` driver on Windows; that combination has not been tested,
not established to be immune. AppleClang and non-Windows Clang are unchanged.

During profile generation, instruction selection failed with
`Cannot select: ch = brind ..., v2i64 CopyFromReg` when SLP was enabled.
There is no upstream LLVM issue or standalone reduced source reproducer yet.
This is an observed backend failure, not a diagnosed LLVM root cause.
The following repository-level reproduction is retained rather than inventing
an upstream issue number or claiming a reduced reproducer.

## Reproduction / removal check

From a VS x64 developer command prompt with LLVM 22.1.8 and Ninja on PATH:

1. On the PR source, temporarily remove **both** generate-only SLP options
   (`/clang:-fno-slp-vectorize` and `/mllvm:-vectorize-slp=false`).
2. Configure a fresh tree (do not reuse objects from another source revision):

   ```bat
   cmake -S . -B build_pgo_repro -G Ninja -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl -DCMAKE_BUILD_TYPE=Release -DRIPWIRE_PGO=generate
   cmake --build build_pgo_repro --verbose -j 2
   ```

3. Preserve the failing compile/link command and full backend output. Release
   enables LTO, so the failure can occur in lld-link's code-generation backend;
   the compiler flag alone does not reach that backend. A reduced LLVM report
   must be derived from the failing input, not just the diagnostic fragment.
4. Restore the workaround, configure a separate fresh generate tree, build and
   run a representative crawl. Verify that `.profraw` files are written.
5. Merge with the matching `llvm-profdata`, then build a separate use tree.
   For a Ninja validation tree, replace `-Wno-profile-instr-out-of-date` with
   `-Werror=profile-instr-out-of-date` in its generated `build.ninja` before
   building (no source edit or reconfigure between replacement and build).
   This removes the suppression for both C and C++. Build `--target ripwire`
   when the training profile came from `ripwire.exe` alone.
   Confirm no SLP-disabling flag exists in the use compile/link commands.

Remove the workaround only after the original failure reproduces on the old
compiler and the same inputs pass generate, training and use on the replacement
compiler with SLP enabled. A successful configure or suppressed warning alone
is not evidence that the profile matches.

clang-cl embeds a target-specific compiler-rt profile runtime dependency in
objects (`clang_rt.profile-x86_64.lib` is the x64 example). CMake sends its
link options directly to lld-link, which does not accept the compiler driver's
`-fprofile-*` options; those are therefore compile-only for this driver.

## Follow-up validation

Validation results and exact commands are recorded in the PR follow-up.
The source changes preserve the existing use-phase flags; mismatch diagnostics
are enabled explicitly for validation rather than changing the warning policy
for all users.

### Verified follow-up (2026-10-16)

On Windows x64, clang-cl 22.1.8, VS Build Tools 2022 / SDK 10.0.22621.0:

- Fresh Release+LTO generate build succeeded (`build_pr410_gen`, Ninja, `-j 2`).
- `build_pr410_gen\ripwire.exe test` produced an 8,016,480-byte `.profraw`;
  the matching LLVM tool merged it into a 7,922,792-byte `.profdata`.
- A separate Release+LTO use configure used that profile. In its generated
  `build.ninja`, **every** `-Wno-profile-instr-out-of-date` was replaced with
  `-Werror=profile-instr-out-of-date` (71 occurrences). No SLP-disable option
  remained in the use tree. This changes validation output only, not source.
- `cmake --build build_pr410_use --target ripwire --clean-first -j 2` completed
  all 69 steps with **zero warnings, zero hash-mismatch diagnostics**, and
  `build_pr410_use\ripwire.exe test` completed successfully.
- The initial all-target use build did emit a backend hash-mismatch warning for
  `src/tsprobe.cpp`'s `main`: the profile had trained the main CLI, not the
  different `ripwire_probe` executable. That run is **not** called warning-free.
  The clean targeted build above validates the trained executable; it does not
  claim profile coverage/compatibility for the untrained probe.
- `ripwire . --quality-delta --legend=compact`, `ripwire . --test-gate`, and
  `git diff --check` all returned zero. No runtime C++ sources changed.

This validates profile use with SLP re-enabled for the CLI. It does not establish
that the original backend failure is fixed upstream, and no minimized LLVM
reproducer or upstream issue is claimed.
