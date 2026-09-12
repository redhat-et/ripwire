# cmake/PortableFlags.cmake — arch-flag selection for the default (non-NATIVE) optimization profile.
# Fixes a portability bug found in review: "Non-NATIVE build hardcodes -mcpu=apple-m1 -ffast-math —
# Linux/x86 fails out of the box".
#
# Factored into its own module (rather than inlined in CMakeLists.txt) so test/portablebuildcheck.sh
# can `include()` it into a tiny standalone project and inspect RIPWIRE_ARCH_FLAGS WITHOUT paying for
# the full FetchContent grammar fetch — the gate exercises the real logic, not a reimplementation.
#
#   -DRIPWIRE_NATIVE=ON   dev-machine-only opt-in: -march=native bakes in whatever ISA extensions the
#                         CONFIGURING host happens to have. Never use for a binary that will run on any
#                         other machine (a release artifact, CI, a teammate's laptop).
#   default (OFF)         portable, WITH ONE ARCHITECTURE FLOOR: an x86-64 target gets -march=x86-64-v3
#                         (owner, 2026-09-10 — see the branch below for why, and for the FMA caveat).
#                         That is an architecture LEVEL, not a host bake-in, and it is what makes
#                         src/infra/strkern.h's AVX2 kernels compile at all.
#                         For an Apple Silicon TARGET, -mcpu=apple-m1 is safe GENERIC tuning (every
#                         shipping Apple Silicon core, M1 through the current line, is an M1-superset —
#                         this is not a native-host bake-in), so we auto-apply it there. The moment the
#                         target is NOT Apple Silicon — any Linux, x86-64 macOS, a cross build — we must emit
#                         ZERO Apple-specific flags: `-mcpu=apple-m1` is a hard configure/compile failure
#                         on every other target (clang: "unknown target CPU", or on clang >= 17 for x86
#                         "unsupported option '-mcpu=' for target"; gcc: flag not recognized).
#   TARGET, NOT HOST      every branch keys on RIPWIRE_TARGET_ARCH, set below: CMAKE_OSX_ARCHITECTURES when
#                         it names one arch, else CMAKE_SYSTEM_PROCESSOR.
#
# -fno-finite-math-only is load-bearing in EVERY branch: it keeps isnan/isinf live for isFiniteFast even
# under -ffast-math. src/pagerank.cpp overrides all of this with -fno-fast-math regardless of branch
# (the determinism contract's no-reassociation rule for the PageRank reduction — docs/ARCHITECTURE.md
# §3) — that override lives in CMakeLists.txt and is untouched by this module.
#
# RIPWIRE_PRETEND_LINUX is a TEST-ONLY hook: it forces the non-Apple-Silicon branch even when actually
# configuring ON Apple Silicon hardware (this repo's own dev machines), so the portability contract is
# provable here without needing literal non-Apple hardware. It has no effect on the RIPWIRE_NATIVE branch
# (an explicit --native request always means "trust this exact host", pretend or not).
option(RIPWIRE_PRETEND_LINUX
  "TEST-ONLY (test/portablebuildcheck.sh): force the portable non-Apple-Silicon flag path for testability, even on real Apple Silicon"
  OFF)

# ── the TARGET architecture — never the host's ─────────────────────────────────────────────────────────
# CMAKE_SYSTEM_PROCESSOR names the HOST on a macOS cross build: CMake derives it from the running machine
# (CMakeDetermineSystem honours only CMAKE_APPLE_SILICON_PROCESSOR) and never from CMAKE_OSX_ARCHITECTURES.
# release.yml builds the macOS x86_64 binary on an arm64 runner with -DCMAKE_OSX_ARCHITECTURES=x86_64, and
# keyed on CMAKE_SYSTEM_PROCESSOR that compile got -mcpu=apple-m1 and no -march: a hard driver error on
# clang >= 17 (AppleClang 16, the Xcode 16.2 the release pins), and on clang 16 a baseline x86-64 binary
# running strkern.h's scalar twins. test/portablebuildcheck.sh #2d-#2g hold both directions.
set(RIPWIRE_TARGET_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
if(APPLE AND CMAKE_OSX_ARCHITECTURES)
  list(LENGTH CMAKE_OSX_ARCHITECTURES _ripwire_osx_arch_count)
  if(_ripwire_osx_arch_count EQUAL 1)
    set(RIPWIRE_TARGET_ARCH "${CMAKE_OSX_ARCHITECTURES}")
  elseif(NOT RIPWIRE_NATIVE)
    # One add_compile_options() cannot give an x86_64 slice -march=x86-64-v3 and an arm64 slice
    # -mcpu=apple-m1: a universal tree would hand both slices ONE arch's flags, which is the defect above on
    # half the binary. Nothing here builds one; a universal binary is `lipo -create` of two single-arch trees.
    message(FATAL_ERROR
      "ripwire builds one architecture per build tree (CMAKE_OSX_ARCHITECTURES='${CMAKE_OSX_ARCHITECTURES}'): "
      "configure one tree per architecture and combine the binaries with `lipo -create`.")
  endif()
  unset(_ripwire_osx_arch_count)
endif()
message(STATUS "RIPWIRE_TARGET_ARCH:${RIPWIRE_TARGET_ARCH}")

set(RIPWIRE_IS_APPLE_SILICON OFF)
if(APPLE AND NOT RIPWIRE_PRETEND_LINUX AND RIPWIRE_TARGET_ARCH MATCHES "^(arm64|arm64e|aarch64)$")
  set(RIPWIRE_IS_APPLE_SILICON ON)
endif()

set(RIPWIRE_IS_X86_64 OFF)
if(RIPWIRE_TARGET_ARCH MATCHES "^(x86_64|x86_64h|amd64|AMD64)$")
  set(RIPWIRE_IS_X86_64 ON)
endif()

if(RIPWIRE_NATIVE)
  set(RIPWIRE_ARCH_FLAGS -O3 -march=native -ffast-math -fno-finite-math-only)
elseif(RIPWIRE_IS_APPLE_SILICON)
  set(RIPWIRE_ARCH_FLAGS -O2 -mcpu=apple-m1 -ffast-math -fno-finite-math-only)
elseif(RIPWIRE_IS_X86_64)
  # ── the x86-64 FLOOR (owner decision, 2026-09-10) ────────────────────────────────────────────────
  # "No machine older than ten years", and then "is v3 better? do not want to go backwards". So the
  # shipped x86-64 binary requires x86-64-v3: AVX2 + BMI1/BMI2 + FMA + LZCNT + MOVBE — the same floor
  # RHEL 10 sets, hardware from 2015 (Haswell/Excavator) onward. This is NOT a host bake-in: the flag
  # names an ARCHITECTURE LEVEL that every supported x86-64 target implements, exactly as -mcpu=apple-m1
  # names a generic Apple Silicon level above. It is unconditional rather than a runtime dispatch
  # because a dispatch table is a second code path nothing here would keep honest (G3: one deterministic
  # build step, no host-installed anything).
  #
  # WHAT DEPENDS ON IT: src/infra/strkern.h compiles its AVX2 mirror behind `__AVX2__`, which v3 defines.
  # Without this line an x86-64 build silently drops to the scalar twins — correct, and several times
  # slower on every text-scanning verb. arm64 needs no counterpart: NEON is in the arm64 baseline.
  #
  # NEVER v4 (AVX-512): the downclocking and the fragmented server support make it a portability loss,
  # and nothing here is 512-bit-shaped.
  #
  # THE FMA CAVEAT, spelled out because it is the one way this line could move a NUMBER rather than a
  # timing: v3 includes FMA, and a compiler is allowed to contract `a*b+c` into one fused instruction
  # with a single rounding, which changes float results. src/pagerank.cpp — the only translation unit
  # whose float reassociation the determinism contract pins (docs/ARCHITECTURE.md §3) — is already
  # compiled with -fno-fast-math by CMakeLists.txt. If a pinned float gate ever moves on the Ubuntu CI
  # legs, the fix is `-ffp-contract=off` on THAT translation unit, never lowering this floor.
  set(RIPWIRE_ARCH_FLAGS -O2 -march=x86-64-v3 -ffast-math -fno-finite-math-only)
else()
  # Portable default: no host- or vendor-specific ISA flag at all. Compiles clean on any non-x86-64,
  # non-Apple-Silicon target (aarch64 Linux, BSD, a cross toolchain) with generic -O2 codegen.
  set(RIPWIRE_ARCH_FLAGS -O2 -ffast-math -fno-finite-math-only)
endif()

# Machine-parseable line for the gate (and for anyone debugging `cmake -S . -B build -LA`) to grep.
message(STATUS "RIPWIRE_ARCH_FLAGS:${RIPWIRE_ARCH_FLAGS}")
