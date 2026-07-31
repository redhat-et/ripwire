# cmake/PortableFlags.cmake — arch-flag selection for the default (non-NATIVE) optimization profile
# (SPEC §7; L1 / AUDIT5 independence MUST-FIX #5: "Non-NATIVE build hardcodes -mcpu=apple-m1
# -ffast-math — Linux/x86 fails out of the box").
#
# Factored into its own module (rather than inlined in CMakeLists.txt) so test/portablebuildcheck.sh
# can `include()` it into a tiny standalone project and inspect CTXPACK_ARCH_FLAGS WITHOUT paying for
# the full FetchContent grammar fetch — the gate exercises the real logic, not a reimplementation.
#
#   -DCTXPACK_NATIVE=ON   dev-machine-only opt-in: -march=native bakes in whatever ISA extensions the
#                         CONFIGURING host happens to have. Never use for a binary that will run on any
#                         other machine (a release artifact, CI, a teammate's laptop).
#   default (OFF)         portable. On real Apple Silicon, -mcpu=apple-m1 is safe GENERIC tuning (every
#                         shipping Apple Silicon core, M1 through the current line, is an M1-superset —
#                         this is not a native-host bake-in), so we auto-apply it there. The moment we are
#                         NOT on Apple Silicon — any Linux, x86-64 macOS, or cross build — we must emit
#                         ZERO Apple-specific flags: `-mcpu=apple-m1` is a hard configure/compile failure
#                         on every other target (clang: "unknown target CPU"; gcc: flag not recognized).
#
# -fno-finite-math-only is load-bearing in EVERY branch: it keeps isnan/isinf live for isFiniteFast even
# under -ffast-math. src/pagerank.cpp overrides all of this with -fno-fast-math regardless of branch
# (SPEC §3/§7 no-reassoc contract for the PageRank reduction) — that override lives in CMakeLists.txt
# and is untouched by this module.
#
# CTXPACK_PRETEND_LINUX is a TEST-ONLY hook: it forces the non-Apple-Silicon branch even when actually
# configuring ON Apple Silicon hardware (this repo's own dev machines), so the portability contract is
# provable here without needing literal non-Apple hardware. It has no effect on the CTXPACK_NATIVE branch
# (an explicit --native request always means "trust this exact host", pretend or not).
option(CTXPACK_PRETEND_LINUX
  "TEST-ONLY (test/portablebuildcheck.sh): force the portable non-Apple-Silicon flag path for testability, even on real Apple Silicon"
  OFF)

set(CTXPACK_IS_APPLE_SILICON OFF)
if(APPLE AND NOT CTXPACK_PRETEND_LINUX AND CMAKE_SYSTEM_PROCESSOR MATCHES "^(arm64|aarch64)$")
  set(CTXPACK_IS_APPLE_SILICON ON)
endif()

if(CTXPACK_NATIVE)
  set(CTXPACK_ARCH_FLAGS -O3 -march=native -ffast-math -fno-finite-math-only)
elseif(CTXPACK_IS_APPLE_SILICON)
  set(CTXPACK_ARCH_FLAGS -O2 -mcpu=apple-m1 -ffast-math -fno-finite-math-only)
else()
  # Portable default: no host- or vendor-specific ISA flag at all. Compiles clean on any x86-64/aarch64
  # target (Linux, Intel macOS, BSD, a cross toolchain) with generic -O2 codegen.
  set(CTXPACK_ARCH_FLAGS -O2 -ffast-math -fno-finite-math-only)
endif()

# Machine-parseable line for the gate (and for anyone debugging `cmake -S . -B build -LA`) to grep.
message(STATUS "CTXPACK_ARCH_FLAGS:${CTXPACK_ARCH_FLAGS}")
