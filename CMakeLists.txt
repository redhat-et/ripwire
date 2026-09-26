cmake_minimum_required(VERSION 3.24)
# The version string lives in exactly ONE place — this project() call. --version (main.cpp)
# reads it via the generated version.h below; test/versioncheck.sh asserts the two never drift.
project(ripwire VERSION 0.6.4 LANGUAGES C CXX)

# ---- language standards (C++23 for our own code / C11 for the vendored C dependencies) ----
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# ---- verification build modes (the sanitizer stacks + gate targets — CONTRIBUTING.md §4) ----
# Each sanitizer family owns a separate build tree; combining runtimes is unsupported and obscures failures.
option(RIPWIRE_ASAN "build with the complete fail-fast G1 sanitizer stack" OFF)
option(RIPWIRE_TSAN "build separately with ThreadSanitizer" OFF)
option(RIPWIRE_FUZZ "build the opt-in per-grammar libFuzzer suite" OFF)
set(_ripwire_verification_mode_count 0)
foreach(_ripwire_mode RIPWIRE_ASAN RIPWIRE_TSAN RIPWIRE_FUZZ)
  if(${_ripwire_mode})
    math(EXPR _ripwire_verification_mode_count "${_ripwire_verification_mode_count} + 1")
  endif()
endforeach()
if(_ripwire_verification_mode_count GREATER 1)
  message(FATAL_ERROR "RIPWIRE_ASAN, RIPWIRE_TSAN, and RIPWIRE_FUZZ are mutually exclusive; use separate build trees")
endif()

# ---- the MSVC C runtime the ASan flavour has to use, chosen BEFORE any target exists ----
# Only the RELEASE DLL runtime (/MD) is shipped with an AddressSanitizer build on the MSVC ABI: clang-cl refuses the
# debug one at the driver, "invalid argument '-MDd' not allowed with '-fsanitize=address'", and cl.exe's own /fsanitize
# =address has the same rule. A plain configure (no CMAKE_BUILD_TYPE, which is what CONTRIBUTING.md's ASan tree uses)
# selects /MDd by default, so the ASan tree could not configure at all on Windows — the third failure of @lennix1337's
# validation run of #44. CMAKE_MSVC_RUNTIME_LIBRARY is read into each target's MSVC_RUNTIME_LIBRARY property at
# add_executable/add_library time, so it has to be set here, above every target block, not beside the sanitizer flags
# far below. Never overridden if the configurer already chose one: an explicit -DCMAKE_MSVC_RUNTIME_LIBRARY is a
# deliberate answer to this same question and this build has no better one. Inert off Windows and off the ASan tree.
if(WIN32 AND MSVC AND RIPWIRE_ASAN AND NOT DEFINED CMAKE_MSVC_RUNTIME_LIBRARY)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")
  message(STATUS "RIPWIRE_ASAN: MSVC runtime pinned to MultiThreadedDLL (/MD) — the sanitizer runtime has no debug-CRT build")
endif()

# A flag probe is insufficient: Apple Clang accepts -fsanitize=fuzzer but some Xcode distributions omit
# libclang_rt.fuzzer_osx.a. Compile AND link a complete harness before creating fuzz targets, and never
# download a replacement toolchain from the build.
if(RIPWIRE_FUZZ)
  if(NOT CMAKE_C_COMPILER_ID MATCHES "Clang" OR NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    message(FATAL_ERROR "RIPWIRE_FUZZ requires Clang for both C and CXX")
  endif()
  include(CheckCXXSourceCompiles)
  set(_ripwire_required_flags_save "${CMAKE_REQUIRED_FLAGS}")
  set(_ripwire_required_link_options_save "${CMAKE_REQUIRED_LINK_OPTIONS}")
  set(CMAKE_REQUIRED_FLAGS "-fsanitize=fuzzer-no-link,address")
  set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=fuzzer,address")
  check_cxx_source_compiles(
    "#include <cstddef>\n#include <cstdint>\nextern \"C\" int LLVMFuzzerTestOneInput( const std::uint8_t*, std::size_t ) { return 0; }"
    RIPWIRE_HAS_LIBFUZZER_RUNTIME)
  set(CMAKE_REQUIRED_FLAGS "${_ripwire_required_flags_save}")
  set(CMAKE_REQUIRED_LINK_OPTIONS "${_ripwire_required_link_options_save}")
  if(NOT RIPWIRE_HAS_LIBFUZZER_RUNTIME)
    message(FATAL_ERROR
      "RIPWIRE_FUZZ requires a Clang toolchain containing the libFuzzer runtime. "
      "Configure both CMAKE_C_COMPILER and CMAKE_CXX_COMPILER from the same upstream LLVM installation; "
      "the build will not install a compiler automatically.")
  endif()
endif()

# ---- optimization profile (portable by default) ----
# default: the TARGET architecture decides — -march=x86-64-v3 for x86-64 (the owner's floor), generic apple-m1
# tuning (not a native-host bake-in) for Apple Silicon, arch-neutral otherwise. -DRIPWIRE_NATIVE=ON: dev-machine-only opt-in
# (-march=native bakes in host CPU extensions — never for a binary that ships or runs elsewhere).
# See cmake/PortableFlags.cmake for the full rationale and the RIPWIRE_PRETEND_LINUX test-only hook.
# DECLARED here, beside the other five options, rather than left to be conjured by a bare -D on the
# command line: an undeclared option is absent from `cmake -LH`, from ccmake, and from the IDE panes,
# so the only way to learn it exists is to read this comment — and `--flags` cannot report a CMake
# gate that no `option()` call ever names.
option(RIPWIRE_NATIVE "build with -march=native (DEV MACHINES ONLY — bakes in host CPU extensions)" OFF)
include(cmake/PortableFlags.cmake)
add_compile_options(${RIPWIRE_ARCH_FLAGS})

# Windows adds one source (src/infra/os_win32.cpp), a manifest and three system libraries to each target — all in
# cmake/Windows.cmake. Elsewhere the hook is empty, so the target blocks below call it unconditionally.
if(WIN32)
  include(cmake/Windows.cmake)
else()
  function(ripwire_windows_target tgt)
  endfunction()
endif()

# ---- link-time optimization: -DRIPWIRE_LTO=ON ----
# The one change the optimization-remarks pass actually justified (docs/OPTREMARKS.md, finding F1).
#
# WHAT THE REMARKS SAID. In the ingest translation unit — where the profiler puts ~24% of a cold run,
# in `captureTagsFacts` (src/ingest_sidecap.h since the split) — 831 of 1437 distinct
# `inline/NoDefinition` remarks name a tree-sitter C entry point (ts_node_child_by_field_name,
# ts_node_is_null, ts_node_type, ts_node_start_byte, …). Those are three-line accessors, but they live
# in separately compiled C objects, so each one is an opaque call that also acts as a memory barrier:
# 7683 `gvn/LoadClobbered … clobbered by call` remarks in that same TU are the downstream damage.
# (Counts re-derived 2026-09-10 over the whole TU; the original 397/636 and 5448 were measured against
# src/ingest.cpp alone, which after the split is 0.2% of it — docs/OPTREMARKS.md §8.) No source edit reaches this — the definitions are in another
# translation unit, which is precisely what LTO fixes.
#
# WHAT IT MEASURED (this repo as corpus, 937 files, Apple Silicon; FOUR independent interleaved A/Bs,
# 9/21/21/31 runs per arm). The direction is unanimous — every cold statistic in every run favours LTO
# — but the magnitude is not crisp, and the honest claim is a RANGE, not the best run:
#   cold  median  -0.8% .. -5.9%   (4/4 runs favour LTO)
#   cold  min     -3.1% .. -5.8%   (4/4)
#   warm  median   0.0% .. -3.0%   (3/4; the weakest run's warm min went the WRONG way by 4.8%)
#   output byte-identical; binary 38.2 -> 37.1 MB; rebuild-after-touching-main.cpp 34 s -> 89 s (2.6x).
# Full per-run table: docs/OPTREMARKS.md F1.
#
# THE DEFAULT TRACKS THE BUILD TYPE, because the two builds have different jobs.
#   plain configure (no CMAKE_BUILD_TYPE — the dev tree CLAUDE.md mandates)  =>  LTO OFF
#   -DCMAKE_BUILD_TYPE=Release (CI, and anyone building to USE the tool)     =>  LTO ON
# A rebuild after touching src/main.cpp goes 34 s -> 89 s with LTO, and this repo runs many agent
# edit loops; paying 2.6x link on every one of them to speed up a binary nobody is timing is a bad
# trade. The person building to USE ripwire wants the fast binary and is already on Release, so they
# get it without asking. Both are overridable: -DRIPWIRE_LTO=ON on a dev tree, OFF on Release.
#
# DELIBERATELY NOT COUPLED TO NDEBUG/ASSUME. It would be tidier to say "checked build = slow, real
# build = fast" and fold LTO into the Release flavour, but that puts LTO and the assertions in
# mutually exclusive builds — and LTO is precisely an OPTIMIZER change, the class of bug CLAUDE.md
# says the Release leg exists to catch. Keeping the axes independent means a CI leg can run LTO WITH
# ASSUME and the DISCLOSE( msg ) trace live, which is the only configuration that can catch an
# LTO-induced miscompile the assertions would have flagged. Coupling them would create the blind
# spot exactly where this optimization can hurt.
# Determinism is unaffected: pagerank.cpp's -fno-fast-math is a per-function IR attribute that
# survives LTO, output is byte-identical to a non-LTO build, and the determinism gate passes on this
# tree three times running.
#
# GOTCHA, and it is why this is a plain variable and not a cached option() when unset: option() never
# overwrites an existing cache entry, so an ALREADY-CONFIGURED tree keeps whatever it was born with
# and silently builds the other flavour. If you DID pass -DRIPWIRE_LTO explicitly it is cached and
# sticky by design; `cmake -S . -B build` will not clear it — delete the tree to get back to the
# build-type default.
if(DEFINED RIPWIRE_LTO OR DEFINED CACHE{RIPWIRE_LTO})
  set(RIPWIRE_LTO "${RIPWIRE_LTO}" CACHE BOOL "build with link-time optimization (inlines the tree-sitter C API into the hot capture loop)" FORCE)
elseif(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
  set(RIPWIRE_LTO ON)
  message(STATUS "RIPWIRE_LTO: ON (implied by CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE})")
else()
  set(RIPWIRE_LTO OFF)
  message(STATUS "RIPWIRE_LTO: OFF (plain dev configure — fast edit loop; use -DCMAKE_BUILD_TYPE=Release or -DRIPWIRE_LTO=ON for the fast binary)")
endif()
if(RIPWIRE_LTO)
  include(CheckIPOSupported)
  if(WIN32 AND CMAKE_EXE_LINKER_FLAGS)
    # ClangCL + lld-link does not inherit the SDK /libpath entries from the parent configure during
    # check_ipo_supported()'s try_compile. Propagate the explicitly selected linker flags so the LTO
    # capability check exercises the same Windows CRT/toolchain that the real targets will link against.
    list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES CMAKE_EXE_LINKER_FLAGS)
  endif()
  check_ipo_supported(RESULT _ripwire_ipo_ok OUTPUT _ripwire_ipo_why LANGUAGES C CXX)
  if(NOT _ripwire_ipo_ok)
    # Fail loudly. A silently-ignored LTO request produces a normal binary that someone then benchmarks
    # as "LTO made no difference" — the same green-while-inert failure §2 gates against elsewhere.
    message(FATAL_ERROR "RIPWIRE_LTO=ON but this toolchain cannot do IPO: ${_ripwire_ipo_why}")
  endif()
  # The VARIABLE, set HERE — before the first add_executable/add_library and before FetchContent pulls
  # the vendored tree-sitter subproject in. CMAKE_INTERPROCEDURAL_OPTIMIZATION seeds the property on
  # targets created AFTER it, so this placement (and only this placement) reaches all three groups that
  # matter: our C++, the twenty-two C grammar objects, and the tree-sitter core in its own subdirectory.
  # Cross-language is the point — the accessors we want inlined are C, the loop calling them is C++.
  set(CMAKE_INTERPROCEDURAL_OPTIMIZATION ON)
  message(STATUS "RIPWIRE_LTO: ON — link-time optimization across our code and the vendored C (slower link, see docs/OPTREMARKS.md F1)")
endif()

# ---- profile-guided optimization: -DRIPWIRE_PGO=generate|use ----
# LTO's bigger sibling, and the direct answer to the remark classes LTO does NOT touch. `inline/TooCostly`
# and `loop-vectorize/VectorizationNotBeneficial` are both the cost model guessing with no idea which
# branch is taken or which call is hot; PGO replaces the guess with counted data. Measured effect on top
# of LTO is several times LTO's own (docs/OPTREMARKS.md, finding F2).
#
# Two phases, and scripts/pgobuild.sh runs both plus the training workload as ONE command:
#   cmake -S . -B build_pgogen -DRIPWIRE_LTO=ON -DRIPWIRE_PGO=generate   # instrumented
#   <run the instrumented binary over a representative workload>
#   xcrun llvm-profdata merge -output=ripwire.profdata build_pgogen/prof/*.profraw
#   cmake -S . -B build_pgo -DRIPWIRE_LTO=ON -DRIPWIRE_PGO=use -DRIPWIRE_PGO_PROFILE=<abs path>
#
# G3 HONESTY. "One deterministic build step" is the guardrail, and PGO is genuinely in tension with it:
# it needs two configures, a training run, and llvm-profdata. Three deliberate choices keep the tension
# as small as it can be, rather than pretending it is absent:
#   * The .profdata is NOT committed. A 3.3 MB binary blob that silently goes stale against source — and
#     whose staleness clang reports as a warning, not an error — would trade a visible two-step build for
#     an invisible wrong one. It is generated locally, by the script, from the source in front of you.
#   * llvm-profdata is not a NEW host dependency: it ships inside the same Clang the build already
#     requires (`xcrun llvm-profdata` on macOS, `llvm-profdata-NN` on Linux).
#   * `use` FAILS if the profile is missing. A -fprofile-use pointed at nothing compiles fine and yields
#     an ordinary binary, which someone then benchmarks as "PGO did nothing" — the green-while-inert
#     shape CONTRIBUTING.md §2 gates against. The existence check below is that gate, at configure time.
set(RIPWIRE_PGO "" CACHE STRING "profile-guided optimization phase: generate | use (empty = off)")
set_property(CACHE RIPWIRE_PGO PROPERTY STRINGS "" generate use)
set(RIPWIRE_PGO_PROFILE "" CACHE FILEPATH "RIPWIRE_PGO=use: absolute path to the merged .profdata")
if(RIPWIRE_PGO)
  if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    # GCC spells the same idea with -fprofile-generate/-fprofile-use too, but its profile is per-object
    # .gcda merged by a different tool; the paths below would half-work and mislead.
    message(FATAL_ERROR "RIPWIRE_PGO requires Clang (the .profdata/llvm-profdata flavour). GCC's -fprofile-* uses .gcda and different tooling.")
  endif()
  get_filename_component(_ripwire_pgo_build_name "${CMAKE_BINARY_DIR}" NAME)
  if(_ripwire_pgo_build_name STREQUAL "build" OR _ripwire_pgo_build_name STREQUAL "asan")
    message(FATAL_ERROR
      "RIPWIRE_PGO must not be enabled in ${_ripwire_pgo_build_name}/ — that is the tree the gates and "
      "benches measure, and a silently PGO'd build/ripwire moves every recorded number. Use build_pgo/.")
  endif()
  if(RIPWIRE_PGO STREQUAL "generate")
    # Counters land in <build>/prof as default_*.profraw, one per process image.
    set(_ripwire_pgo_flag "-fprofile-generate=${CMAKE_BINARY_DIR}/prof")
  elseif(RIPWIRE_PGO STREQUAL "use")
    if(NOT RIPWIRE_PGO_PROFILE OR NOT EXISTS "${RIPWIRE_PGO_PROFILE}")
      message(FATAL_ERROR
        "RIPWIRE_PGO=use needs -DRIPWIRE_PGO_PROFILE=<absolute path to a merged .profdata> that exists "
        "(got '${RIPWIRE_PGO_PROFILE}'). Run scripts/pgobuild.sh to produce one.")
    endif()
    # The two -Wno- are not a way to hide staleness: a profile is expected to cover only the code the
    # training run reached, and every uncovered function legitimately reports "unprofiled". Without these
    # the build drowns in thousands of such warnings and a real diagnostic cannot be seen in the noise.
    set(_ripwire_pgo_flag "-fprofile-use=${RIPWIRE_PGO_PROFILE}" -Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date)
  else()
    message(FATAL_ERROR "RIPWIRE_PGO must be 'generate' or 'use' (got '${RIPWIRE_PGO}')")
  endif()
  # Compile AND link, before the first target and before FetchContent: instrumentation has a runtime that
  # must be linked in, and the vendored C is where the parse loop lives — profiling only our C++ would
  # profile the caller of the hot code and not the hot code.
  add_compile_options(${_ripwire_pgo_flag})
  add_link_options(${_ripwire_pgo_flag})
  message(STATUS "RIPWIRE_PGO: ${RIPWIRE_PGO} — see docs/OPTREMARKS.md F2 and scripts/pgobuild.sh")
endif()


# ---- FetchContent: VENDORED sources, PER-BUILD-TREE build output ----
# Every dependency lives IN THIS REPO under third_party/deps/<name>: a cold clone builds with the
# network unplugged — no git fetch, no ~/.cache priming, no CI cache step, no upstream that can
# disappear or force-push under us. The proof is a gate, not a claim — test/dependencypincheck.sh
# runs a real disconnected CONFIGURE (the step at which FetchContent would fetch):
#   cmake -S . -B scratch -DFETCHCONTENT_FULLY_DISCONNECTED=ON && cmake --build scratch -j
#
# The FetchContent_Declare blocks below are kept for PROVENANCE only. Their GIT_REPOSITORY/GIT_TAG
# record exactly which upstream commit each vendored tree was cut from (mirrored in THIRD_PARTY.md);
# FETCHCONTENT_SOURCE_DIR_<NAME> makes FetchContent treat the vendored dir as already-provisioned —
# no download step, no update step, no subbuild git step, and it never writes into the dir — so those
# URLs are documentation of origin, not a code path anything can take.
#
# BUILD + SUBBUILD dirs stay LOCAL to the consuming build tree (FETCHCONTENT_BASE_DIR ->
# ${CMAKE_BINARY_DIR}/_deps). They are not relocatable: their generated Makefiles bake in that tree's
# absolute CMAKE_BINARY_DIR and run `cd $CMAKE_BINARY_DIR && cmake --check-build-system` on every
# `cmake --build`, so a shared build dir lets the LAST tree to configure win — and deleting that tree
# then breaks every other one. Local also gives sanitizer builds their isolation for free (asan/_deps
# and build/_deps hold separately-compiled libtree-sitter.a).
set(_ripwire_vendored_deps "${CMAKE_CURRENT_SOURCE_DIR}/third_party/deps" CACHE PATH "in-repo dependency SOURCE trees")
set(FETCHCONTENT_BASE_DIR "${CMAKE_BINARY_DIR}/_deps")   # local build/subbuild (never the source tree)
set(FETCHCONTENT_UPDATES_DISCONNECTED ON)
include(FetchContent)

# Point one dep at its vendored tree. SENTINEL is the exact file this dep's targets will compile
# (src/parser.c for a grammar, lib/src/lib.c for the core) — a missing sentinel means the vendored tree
# was pruned wrong or the checkout is incomplete, and that has to be a loud configure-time error, NEVER
# a silent fall back to a network clone. A public build that quietly reaches for github is precisely the
# failure this vendoring exists to remove, so the degrade direction here is "stop", not "download".
macro(ripwire_use_vendored_source NAME SENTINEL)
  string(TOUPPER "${NAME}" _ripwire_up)
  if(NOT EXISTS "${_ripwire_vendored_deps}/${NAME}/${SENTINEL}")
    message(FATAL_ERROR
      "vendored dependency '${NAME}' is missing ${SENTINEL} under ${_ripwire_vendored_deps}/${NAME} — "
      "the checkout is incomplete; this build will not fetch a replacement from the network")
  endif()
  set(FETCHCONTENT_SOURCE_DIR_${_ripwire_up} "${_ripwire_vendored_deps}/${NAME}")
endmacro()

# ---- configure-time query embedding (baked into the binary — no data files to ship alongside it) ----
# queries/<language>/tags.scm remains the editable source of truth. CMake regenerates this constexpr
# table whenever any query changes; ingest reads only the binary's read-only data at runtime.
set(_ripwire_query_names
  bash
  c
  cpp
  csharp
  dart
  elixir
  go
  java
  javascript
  json
  gdscript
  kotlin
  lua
  objc
  php
  python
  ruby
  rust
  swift
  toml
  tsx
  typescript
  yaml)
set(_ripwire_generated_dir "${CMAKE_CURRENT_BINARY_DIR}/generated")
set(_ripwire_embedded_queries "${_ripwire_generated_dir}/embedded_queries.h")
file(MAKE_DIRECTORY "${_ripwire_generated_dir}")
list(LENGTH _ripwire_query_names _ripwire_query_count)
file(WRITE "${_ripwire_embedded_queries}" "#pragma once\n\n#include <array>\n#include <cstddef>\n#include <string_view>\n\nnamespace rw::embedded_queries\n{\n\nstruct EmbeddedQuery\n{\n    std::string_view sub;\n    std::string_view source;\n};\n\ninline constexpr std::size_t kEmbeddedQueryCount = ${_ripwire_query_count};\ninline constexpr std::array<EmbeddedQuery, kEmbeddedQueryCount> kEmbeddedQueries = {{\n")
foreach(_ripwire_query_name IN LISTS _ripwire_query_names)
  set(_ripwire_query_path "${CMAKE_CURRENT_SOURCE_DIR}/queries/${_ripwire_query_name}/tags.scm")
  file(READ "${_ripwire_query_path}" _ripwire_query_source)
  string(TOUPPER "${_ripwire_query_name}" _ripwire_query_upper)
  set(_ripwire_query_delimiter "CTXQ_${_ripwire_query_upper}")
  string(FIND "${_ripwire_query_source}" ")${_ripwire_query_delimiter}\"" _ripwire_query_collision)
  if(NOT _ripwire_query_collision EQUAL -1)
    message(FATAL_ERROR "tags query ${_ripwire_query_name} collides with its generated raw-string delimiter")
  endif()
  file(APPEND "${_ripwire_embedded_queries}"
    "    { \"${_ripwire_query_name}\", R\"${_ripwire_query_delimiter}(${_ripwire_query_source})${_ripwire_query_delimiter}\" },\n")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_ripwire_query_path}")
endforeach()
file(APPEND "${_ripwire_embedded_queries}" "}};\n\ninline constexpr std::string_view queryFor( std::string_view sub ) noexcept\n{\n    for( const EmbeddedQuery& query : kEmbeddedQueries )\n    {\n        if( query.sub == sub )\n            return query.source;\n    }\n    return {};\n}\n\n} // namespace rw::embedded_queries\n")

# ---- generated version.h ----
# The version string lives in ONE place: the project(ripwire VERSION ...) call above. --version reads
# this generated header; test/versioncheck.sh diffs its output against CMakeLists.txt's own VERSION so
# the two can never silently drift. Short build info (compiler id/version, build type) rides along so a
# bug report's "ripwire --version" line is enough to reproduce the toolchain, no separate --doctor call.
# CMAKE_BUILD_TYPE is empty for the plain dev configure the house style mandates (CLAUDE.md: "never
# -DCMAKE_BUILD_TYPE=Release" locally — Release defines NDEBUG, which compiles the DISCLOSE( msg ) trace out).
# "unspecified" told a bug reporter nothing about what they actually ran; "dev" is the honest, specific
# label for that configure (§P6.10, 2026-07-28 output audit) — it is the first thing a bug report pastes.
# A MULTI-CONFIG generator (Ninja Multi-Config, Xcode) has no CMAKE_BUILD_TYPE: the configuration is picked at
# build time (`cmake --build b --config Release`), so "dev" would mislabel an NDEBUG binary, and gates that read
# the token to decide whether alerts are compiled in would believe it. The token is `$<CONFIG>` there, and the
# header is per-configuration too: one shared version.h is rewritten by whichever configuration stamped last, and
# a cross-config Ninja Multi-Config build collapses the stamp into ONE command, so every configuration's binary
# carried the first one's token. Each configuration owns generated/<Config>/version.h, searched ahead of
# generated/. A single-config tree keeps generated/version.h and its exact command line
# (test/buildtypestampcheck.sh).
get_property(_ripwire_multi_config GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(_ripwire_multi_config)
  set(_ripwire_build_type_str "$<CONFIG>")
  set(_ripwire_version_header "${_ripwire_generated_dir}/$<CONFIG>/version.h")
  set(_ripwire_generated_include_dirs "${_ripwire_generated_dir}/$<CONFIG>" "${_ripwire_generated_dir}")
else()
  if(NOT CMAKE_BUILD_TYPE)
    set(_ripwire_build_type_str "dev")
  else()
    set(_ripwire_build_type_str "${CMAKE_BUILD_TYPE}")
  endif()
  set(_ripwire_version_header "${_ripwire_generated_dir}/version.h")
  set(_ripwire_generated_include_dirs "${_ripwire_generated_dir}")
endif()
# Always run before the two executable targets. copy_if_different inside the script keeps the header's
# mtime stable when neither HEAD nor tracked bytes changed (per configuration on a multi-config generator,
# so switching --config does not rewrite the other's header), so this gives exact provenance without
# recompiling main.cpp on every incremental build.
add_custom_target(ripwire_version_stamp ALL
  COMMAND ${CMAKE_COMMAND}
    -DRIPWIRE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
    -DRIPWIRE_OUTPUT=${_ripwire_version_header}
    -DRIPWIRE_VERSION=${PROJECT_VERSION}
    -DRIPWIRE_BUILD_TYPE=${_ripwire_build_type_str}
    -DRIPWIRE_COMPILER_ID=${CMAKE_CXX_COMPILER_ID}
    -DRIPWIRE_COMPILER_VER=${CMAKE_CXX_COMPILER_VERSION}
    -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/version_stamp.cmake
  BYPRODUCTS ${_ripwire_version_header}
  VERBATIM)

# The producer identity (cmake/source_identity.cmake): one generated DEFINITION, compiled into both
# executables, that src/quality.h keys its Snapshot caches on — so a blob one build computed is never
# served to a build whose sources differ. A .cpp rather than a header: see src/sourceidentity.h.
# It is a hash of src/ and queries/ only, the same for every configuration, so it is ONE shared file with its
# OWN always-run target, never a second COMMAND of ripwire_version_stamp. In a cross-config Ninja Multi-Config
# build, a target with a shared byproduct runs one configuration's commands only, so it cannot also write the
# per-configuration version.h. Every other configuration's header is then "missing and no known rule"
# (test/buildtypestampcheck.sh #6). Collapsing is harmless for the identity alone, whose command does not
# depend on the configuration. copy_if_different keeps an unchanged tree from recompiling it.
set(_ripwire_source_identity_cpp "${_ripwire_generated_dir}/source_identity.cpp")
add_custom_target(ripwire_source_identity ALL
  COMMAND ${CMAKE_COMMAND}
    -DRIPWIRE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
    -DRIPWIRE_OUTPUT=${_ripwire_source_identity_cpp}
    -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/source_identity.cmake
  BYPRODUCTS ${_ripwire_source_identity_cpp}
  VERBATIM)

# ---- tree-sitter CORE (static) ----
# MUST precede MakeAvailable: tree-sitter defaults BUILD_SHARED_LIBS ON -> you'd get a dylib.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
# Dependency independence (SHA-pin): GIT_TAG is the commit the tag pointed to when resolved via
# `git ls-remote --tags <repo> "refs/tags/<tag>^{}"` (2026-07-22) — an immutable, un-force-pushable ref.
# The tag stays as a trailing comment so `git log`/README readers still see the human-legible version.
ripwire_use_vendored_source(tree_sitter lib/src/lib.c)
FetchContent_Declare(tree_sitter
  GIT_REPOSITORY https://github.com/tree-sitter/tree-sitter.git
  GIT_TAG 7f534862c3ec939c3a6ee147f7600ef5c1bf900f  # v0.26.9
  GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(tree_sitter)

# ---- grammar OBJECT-lib pattern ----
# Do NOT add_subdirectory the grammar repos: their CMakeLists find_program(tree-sitter),
# add a regenerate-parser.c custom command, and a SOVERSION/ABI trap. SOURCE_SUBDIR _none_
# makes FetchContent skip the grammar's own CMakeLists; we compile only parser.c (+scanner.c).
macro(add_ts_grammar NAME REPO TAG)
  ripwire_use_vendored_source(${NAME} src/parser.c)
  FetchContent_Declare(${NAME}
    GIT_REPOSITORY ${REPO}
    GIT_TAG ${TAG}
    GIT_SHALLOW TRUE
    SOURCE_SUBDIR _none_)
  FetchContent_MakeAvailable(${NAME})

  set(_src ${${NAME}_SOURCE_DIR}/src)
  set(_srcs ${_src}/parser.c)
  if(EXISTS ${_src}/scanner.c)
    list(APPEND _srcs ${_src}/scanner.c)
  endif()

  add_library(ts_${NAME} OBJECT ${_srcs})
  target_include_directories(ts_${NAME} PRIVATE ${tree_sitter_SOURCE_DIR}/lib/include ${_src})
  set_target_properties(ts_${NAME} PROPERTIES C_STANDARD 11 POSITION_INDEPENDENT_CODE ON)
  set(RIPWIRE_TS_${NAME}_SOURCES ${_srcs})
endmacro()

# Build one OBJECT lib from an already-fetched grammar's SUBDIR/src (parser.c [+scanner.c]).
# Used for the dual-TypeScript case: ONE fetched repo, TWO sub-grammars, no second clone.
function(add_ts_object NAME SRCDIR)
  set(_srcs ${SRCDIR}/parser.c)
  if(EXISTS ${SRCDIR}/scanner.c)
    list(APPEND _srcs ${SRCDIR}/scanner.c)
  endif()
  add_library(ts_${NAME} OBJECT ${_srcs})
  target_include_directories(ts_${NAME} PRIVATE ${tree_sitter_SOURCE_DIR}/lib/include ${SRCDIR})
  set_target_properties(ts_${NAME} PROPERTIES C_STANDARD 11 POSITION_INDEPENDENT_CODE ON)
  set(RIPWIRE_TS_${NAME}_SOURCES ${_srcs} PARENT_SCOPE)
endfunction()

# ---- pinned grammars (SHA-pinned: each GIT_TAG below is the commit its comment's tag
# resolved to via `git ls-remote --tags <repo> "refs/tags/<tag>^{}"` on 2026-07-22 — mutable tags can
# be force-moved server-side, a SHA cannot; ABI verified at runtime) ----
add_ts_grammar(cpp    https://github.com/tree-sitter/tree-sitter-cpp.git        f41e1a044c8a84ea9fa8577fdd2eab92ec96de02)  # v0.23.4
add_ts_grammar(python https://github.com/tree-sitter/tree-sitter-python.git     bffb65a8cfe4e46290331dfef0dbf0ef3679de11)  # v0.23.6
add_ts_grammar(go     https://github.com/tree-sitter/tree-sitter-go.git         3c3775faa968158a8b4ac190a7fda867fd5fb748)  # v0.23.4
add_ts_grammar(rust   https://github.com/tree-sitter/tree-sitter-rust.git       cad8a206f2e4194676b9699f26f6560d07130d3f)  # v0.23.2
# Swift: upstream main has no generated parser.c — only the audited generated-files commit below does,
# which is why the pin is a bare SHA rather than a tag. Vendoring settles it permanently: the tree under
# third_party/deps/swift IS that commit's generated output, so nothing has to resolve a branch to find it.
set(_ripwire_swift_commit 31d17fe7e818a2048c808b5c6fdc2dc792f4f5b5)
ripwire_use_vendored_source(swift src/parser.c)
FetchContent_Declare(swift
  GIT_REPOSITORY https://github.com/alex-pinkus/tree-sitter-swift.git
  GIT_TAG ${_ripwire_swift_commit}
  GIT_SHALLOW FALSE
  SOURCE_SUBDIR _none_)
FetchContent_MakeAvailable(swift)
add_ts_object(swift ${swift_SOURCE_DIR}/src)
# Objective-C / Objective-C++ (.m/.mm): amaanq/tree-sitter-objc inherits tree-sitter-C, so it parses
# the ObjC layer (@interface/@implementation/methods/[msg sends]) AND C-style calls. It does NOT
# understand C++ (templates/namespaces/::); C++-heavy regions of a .mm error-recover and are partial.
add_ts_grammar(objc   https://github.com/amaanq/tree-sitter-objc.git            18802acf31d0b5c1c1d50bdbc9eb0e1636cab9ed)  # v3.0.2
# JavaScript (.js/.jsx/.mjs/.cjs): the PARENT grammar of tree-sitter-typescript. Own repo (separate
# clone from the TS one). v0.23.1 → ABI 14, in [MIN_COMPATIBLE, LANGUAGE_VERSION] for core v0.26.9.
add_ts_grammar(javascript https://github.com/tree-sitter/tree-sitter-javascript.git 3a837b6f3658ca3618f2022f8707e29739c91364)  # v0.23.1
# Bash (.sh/.bash/.zsh): ships a scanner.c (heredocs/expansions) which the macro picks up. v0.23.3 → ABI 14.
add_ts_grammar(bash   https://github.com/tree-sitter/tree-sitter-bash.git        487734f87fd87118028a65a4599352fa99c9cde8)  # v0.23.3
# Java (.java): big grammar (classes/interfaces/enums/methods/ctors). v0.23.5 → ABI 14, in
# [MIN_COMPATIBLE, LANGUAGE_VERSION] for core v0.26.9. No external scanner (pure parser.c).
add_ts_grammar(java   https://github.com/tree-sitter/tree-sitter-java.git        94703d5a6bed02b98e438d7cad1136c01a60ba2c)  # v0.23.5
# Ruby (.rb): ships a scanner.c (heredocs/string interp) which the macro picks up. v0.23.1 → ABI 14.
add_ts_grammar(ruby   https://github.com/tree-sitter/tree-sitter-ruby.git        71bd32fb7607035768799732addba884a37a6210)  # v0.23.1
# JSON (.json): config-file visibility (package.json/tsconfig/composer.json). Small grammar, no external
# scanner (pure parser.c). v0.24.8 → ABI 14, in [MIN_COMPATIBLE, LANGUAGE_VERSION] for core v0.26.9.
# Data only: keys become def nodes (t="sec"), NO call edges (see queries/json/tags.scm).
add_ts_grammar(json   https://github.com/tree-sitter/tree-sitter-json.git        ee35a6ebefcef0c5c416c0d1ccec7370cfca5a24)  # v0.24.8
# TOML (.toml): config-file visibility, JSON's sibling lane (pyproject.toml / Cargo.toml / rustfmt.toml).
# tree-sitter-grammars/, not tree-sitter/ — there is no first-party TOML grammar. v0.7.0 → ABI 14, in
# [MIN_COMPATIBLE, LANGUAGE_VERSION]=[13,15] for core v0.26.9 (SHA and ABI both re-verified against the
# tag at vendoring time, not taken on faith). Ships a scanner.c (multiline basic/literal strings and the
# line-ending-or-EOF token) which the macro picks up; that scanner is STATELESS — create() returns NULL,
# serialize() returns 0, and it never allocates — so it carries none of the serialization or leak
# hazard an external scanner usually implies.
# Data only: table headers and keys become def nodes (t="sec"), NO call edges (see queries/toml/tags.scm).
add_ts_grammar(toml   https://github.com/tree-sitter-grammars/tree-sitter-toml.git 64b56832c2cffe41758f28e05c756a3a98d16f41)  # v0.7.0
# YAML (.yml/.yaml): config-file visibility, the third data lane (CI workflows / k8s manifests / ansible).
# tree-sitter-grammars/, not tree-sitter/ — there is no first-party YAML grammar. v0.7.2 → ABI 14, in
# [MIN_COMPATIBLE, LANGUAGE_VERSION]=[13,15] for core v0.26.9. Its scanner.c is STATEFUL (an indent-type/
# indent-length stack serialized between runs) and #includes schema.core.c from its own src/ dir — the
# macro's ${_src} include path covers that. UNLIKE toml, this scanner's serialize() had a real
# out-of-bounds write (4-byte writes behind a guard that only proves 1 byte fits; SIGABRT at ~254 block
# indent levels, SILENT corruption under NDEBUG) — the vendored tree carries the one-line bounds fix
# under third_party/patches/yaml/ (drift-gated by test/vendorpatchcheck.sh), and ingest refuses
# pathological indentation BEFORE any parse (ingest.h kMaxYamlNestDepth prescan).
# Data only: mapping keys become def nodes (t="sec"), NO call edges (see queries/yaml/tags.scm).
add_ts_grammar(yaml   https://github.com/tree-sitter-grammars/tree-sitter-yaml.git 7708026449bed86239b1cd5bce6e3c34dbca6415)  # v0.7.2
# Markdown (.md/.markdown): the DOC tier — headings become sections (t="sec") with real spans, so
# --for/--expand/--recall serve the SECTION, not the whole doc. tree-sitter-grammars/, not
# tree-sitter/ — there is no first-party markdown grammar. The upstream repo hosts TWO grammars in
# subdirectories; only the BLOCK grammar (tree-sitter-markdown/) is vendored, FLATTENED to the house
# deps/<name>/src layout (the inline grammar is deferred: inline constructs are extracted by
# ingest's own fence-aware line scan — see extractMarkdown). v0.5.3 → ABI 15, in [MIN_COMPATIBLE,
# LANGUAGE_VERSION]=[13,15] for core v0.26.9. Its scanner.c is STATEFUL (an open-blocks stack
# serialized between runs) and — LIKE yaml, worse — its serialize() had NO bounds check at all
# (5-byte header + a raw memcpy of the stack; SIGABRT at ~255 nested blockquote/list markers,
# SILENT heap corruption under NDEBUG): the vendored tree carries the whole-write clamp under
# third_party/patches/markdown/ (drift-gated by test/vendorpatchcheck.sh arm H, class "upfront"),
# and ingest refuses pathological nesting BEFORE any parse (ingest.h kMaxMdBlockDepth prescan).
# NO tags.scm: extraction is a custom tree walk (section spans + heading hierarchy need the tree,
# not a capture list), so this grammar is deliberately absent from _ripwire_query_names.
add_ts_grammar(markdown https://github.com/tree-sitter-grammars/tree-sitter-markdown.git f969cd3ae3f9fbd4e43205431d0ae286014c05b5)  # v0.5.3 (subdir tree-sitter-markdown/, flattened)
# C# (.cs): the official tree-sitter org grammar (classes/structs/interfaces/records/enums/methods/
# properties/ctors + invocation & object-creation calls). v0.23.5 → ABI 15, in [MIN_COMPATIBLE,
# LANGUAGE_VERSION]=[13,15] for core v0.26.9. Ships a scanner.c (raw/interpolated string literals)
# which the macro picks up.
add_ts_grammar(csharp https://github.com/tree-sitter/tree-sitter-c-sharp.git     cac6d5fb595f5811a076336682d5d595ac1c9e85)  # v0.23.5
# C (.c): the official tree-sitter org grammar (structs/unions/enums/typedefs/function definitions +
# object-like & function-like #define macros + calls). v0.24.1 -> ABI 15, in [MIN_COMPATIBLE,
# LANGUAGE_VERSION]=[13,15] for core v0.26.9 (same ABI as csharp above). No external scanner (pure
# parser.c). `.h` deliberately stays routed to the C++ grammar (kLangTable, ingest.cpp) — see the
# comment there and in model.h's Lang enum for the ownership rationale.
add_ts_grammar(c      https://github.com/tree-sitter/tree-sitter-c.git           7fa1be1b694b6e763686793d97da01f36a0e5c12)  # v0.24.1
# CUDA (.cu/.cuh): tree-sitter-grammars/tree-sitter-cuda, a GENERATED superset of tree-sitter-cpp
# (grammar.js requires cpp's and adds __global__/__device__/… qualifiers, __launch_bounds__, and the
# `<<<grid, block>>>` kernel-call — ALIASED to call_expression, so the C++ tags.scm captures launches
# with no CUDA-specific patterns; see test/cudacheck.sh for the measured failure that justified a real
# grammar over Metal-style C++-grammar riding). v0.21.1 → ABI 15, in [MIN_COMPATIBLE,
# LANGUAGE_VERSION]=[13,15] for core v0.26.9. Ships a scanner.c (inherited from cpp: raw strings)
# which the macro picks up. The tag is lightweight, so the SHA below IS the tagged commit.
add_ts_grammar(cuda   https://github.com/tree-sitter-grammars/tree-sitter-cuda.git 48b066f334f4cf2174e05a50218ce2ed98b6fd01)  # v0.21.1
add_ts_grammar(dart   https://github.com/UserNobody14/tree-sitter-dart.git be07cf7118d3dba06236a3f19541685a68209934)  # ABI 15
add_ts_grammar(elixir https://github.com/elixir-lang/tree-sitter-elixir.git 4b0c7118760af58a2e7081bbc8396e136f820b37)  # ABI 14
# Lua (.lua): tree-sitter-grammars/tree-sitter-lua — there is no first-party Lua grammar under
# tree-sitter/. v0.5.0 → ABI 15, in [MIN_COMPATIBLE, LANGUAGE_VERSION]=[13,15] for core v0.26.9.
# Ships a scanner.c (long-bracket `[[ … ]]` strings and `--[[ … ]]` block comments, whose level count
# the LR parser cannot express) which the macro picks up. That scanner DOES allocate and DOES
# serialize (unlike toml's stateless one), but through create/destroy/serialize callbacks the core
# owns — no new leak surface, and the G1 leg is run with the existing suppressions unchanged.
add_ts_grammar(lua    https://github.com/tree-sitter-grammars/tree-sitter-lua.git 10fe0054734eec83049514ea2e718b2a56acd0c9)  # v0.5.0

# Kotlin (.kt): fwcd/tree-sitter-kotlin — the only actively maintained Kotlin grammar. Pinned
# to a bare commit on `main`, not the last tag (v0.3.8, Aug 2024): that tag predates a scanner
# segfault fix (upstream #136), and main's scanner.c is still plain C, so add_ts_grammar's
# scanner.c-only glob applies unchanged. Local-corpus probe (501 real .kt files, 2026-09-07):
# 0.03% of bytes fall in ERROR subtrees, concentrated in one understood construct
# (`@Composable () -> Unit`-shaped annotated function-type parameters: ~23% of Composable-heavy files
# carry one, localized to a few bytes each with the enclosing declaration intact); zero ASan/UBSan
# reports parsing the same corpus, despite the grammar's own scanner-segfault history. `.kts` is
# deliberately not a kLangTable row yet — see the note there.
add_ts_grammar(kotlin https://github.com/fwcd/tree-sitter-kotlin.git 1852ea17b7f60fb3f9d84e0b1555d56b46b39fb1)  # main, post-0.3.8

# GDScript (.gd): PrestonKnopp/tree-sitter-gdscript — the only maintained GDScript grammar; there is no
# first-party one under tree-sitter/. LANGUAGE_VERSION 14, inside [MIN_COMPATIBLE, LANGUAGE_VERSION]=[13,15]
# for the vendored core. Ships a scanner.c (significant indentation: INDENT/DEDENT/NEWLINE, like Python's)
# which the macro picks up. The SHA below is 12 commits ahead of upstream's newest tag — `git describe
# --tags` reports v6.1.0-12-gc5c8fa4 — so it is a master commit by choice, not for want of a tag.
# PARSE RATE MEASURED, not assumed, before vendoring (STEP 0 of prompts/add-a-language.md): 98.88% of 2938
# real .gd files parse with zero ERROR/MISSING nodes — 13 open-source Godot projects (2611 files, 98.81%)
# plus a private 327-file game (99.39%); 8159 error bytes out of 25.3 MB (0.032%). The three known blind
# spots are disclosed in queries/gdscript/tags.scm and test/gdscriptcheck.sh; all three are upstream grammar
# gaps, NOT patched here (guardrail G3 — this repo carries no grammar fork).
add_ts_grammar(gdscript https://github.com/PrestonKnopp/tree-sitter-gdscript.git c5c8fa4861b5a4f04a7e60d97587fc3b6cc5639e)  # master, ABI 14

# PHP (.php): the official tree-sitter org grammar. Like TypeScript this repo hosts TWO sub-grammars
# in subdirectories — `php/` (the full one: HTML text interleaved with `<?php … ?>` blocks) and
# `php_only/` (no surrounding text). ONLY `php/` is vendored and built: a real .php file in a real
# project can and does open with markup, and the `php_only` grammar reports the whole file as an
# ERROR node when it does. Both sub-grammars' scanner.c `#include "../../common/scanner.h"`, so the
# vendored tree keeps the repo-relative layout (deps/php/common + deps/php/php/src) exactly as
# deps/ts_typescript does — flattening to deps/php/src would break that relative include.
# v0.24.2 → ABI 15, in [MIN_COMPATIBLE, LANGUAGE_VERSION]=[13,15] for core v0.26.9.
ripwire_use_vendored_source(php php/src/parser.c)
FetchContent_Declare(php
  GIT_REPOSITORY https://github.com/tree-sitter/tree-sitter-php.git
  GIT_TAG 5b5627faaa290d89eb3d01b9bf47c3bb9e797dea  # v0.24.2
  GIT_SHALLOW TRUE
  SOURCE_SUBDIR _none_)
FetchContent_MakeAvailable(php)
add_ts_object(php ${php_SOURCE_DIR}/php/src)

# TypeScript: ONE repo cloned once (SOURCE_SUBDIR _none_ skips its CMakeLists), then TWO
# OBJECT libs (ts_tsts from typescript/src, ts_tstsx from tsx/src). Both share common/scanner.c
# which each parser dir's own scanner.c #includes, so per-dir (parser.c + scanner.c) is correct.
ripwire_use_vendored_source(ts_typescript typescript/src/parser.c)
FetchContent_Declare(ts_typescript
  GIT_REPOSITORY https://github.com/tree-sitter/tree-sitter-typescript.git
  GIT_TAG f975a621f4e7f532fe322e13c4f79495e0a7b2e7  # v0.23.2
  GIT_SHALLOW TRUE
  SOURCE_SUBDIR _none_)
FetchContent_MakeAvailable(ts_typescript)
add_ts_object(tsts  ${ts_typescript_SOURCE_DIR}/typescript/src)
add_ts_object(tstsx ${ts_typescript_SOURCE_DIR}/tsx/src)

# ---- explicit, easy-to-extend executable source list ----
# Later stages (graph/rank/serialize/main) get appended here. ingest.cpp + infra's
# diagnostics.cpp (ASSUME/DEGRADED handlers link partner) are the foundation.
set(RIPWIRE_SRCS
  src/ingest.cpp
  src/pagerank.cpp
  src/infra/diagnostics.cpp
)

# ---- RIPWIRE_LAYOUT_TU: the translation unit's own identity, where __BASE_FILE__ does not exist ----
# src/structlayout.h registers each TU's struct layouts under a name that must differ per TU, so that two
# objects compiled from one header with disagreeing layouts can be told apart (that is the whole point of the
# registry, and --doctor's `layout` row reads it). __FILE__ is the wrong identity: the registration macro is
# expanded inside headers, so it names the header and every TU would register the same string. GCC and Clang
# spell the right one __BASE_FILE__; it is a compiler EXTENSION, not a platform feature, and cl.exe has no
# counterpart, so structlayout.h #errors rather than guess (three C1189s on the cl leg, windows-latest CI,
# 2026-09-20). The header documents the override and test/structlayoutcheck.sh already drives it with
# -DRIPWIRE_LAYOUT_TU; this supplies it from the build system for the front end that needs it.
#
# Keyed on the COMPILER, never the platform: clang-cl targets Windows and HAS __BASE_FILE__, so a condition on
# MSVC-ness (the CMAKE_CXX_COMPILER_FRONTEND_VARIANT test used for /fp:precise just below) would wrongly claim
# this leg too.
#
# The value is the path RELATIVE to the source root, not ${CMAKE_CURRENT_SOURCE_DIR}/... . Relative is the
# reproducible choice: two checkouts in different directories then register byte-identical strings, where
# __BASE_FILE__ on the GNU legs already carries whatever absolute path CMake passed. Nothing here reaches the
# map — LayoutRecord::unit is read in exactly two places, both in structlayout.h, a sort comparator and the
# mismatch report — but a build-system value that differs by checkout directory is the shape that makes a build
# non-reproducible later, and relative costs nothing.
if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  set(_ripwire_layout_tus
    src/main.cpp
    src/tsprobe.cpp
    ${RIPWIRE_SRCS}
    test/verify_csr.cpp
    test/verify_pagerank.cpp
    test/verify_radix.cpp
    test/verify_strkern.cpp
    test/verify_os_win32_logic.cpp)
  foreach(_ripwire_tu IN LISTS _ripwire_layout_tus)
    set_property(SOURCE ${_ripwire_tu} APPEND PROPERTY COMPILE_DEFINITIONS "RIPWIRE_LAYOUT_TU=\"${_ripwire_tu}\"")
  endforeach()
  # The generated identity TU is written into the build tree, so its source path is absolute and varies by
  # build directory; it registers under its bare name for the same reproducibility reason as above.
  set_property(SOURCE ${_ripwire_source_identity_cpp} APPEND PROPERTY
    COMPILE_DEFINITIONS "RIPWIRE_LAYOUT_TU=\"source_identity.cpp\"")
endif()

# The global profile uses -ffast-math, but PageRank reductions must not reassociate (the determinism
# contract's no-reassociation rule — docs/ARCHITECTURE.md §3).
if(CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
  set_source_files_properties(src/pagerank.cpp PROPERTIES COMPILE_OPTIONS "/fp:precise")
else()
  set_source_files_properties(src/pagerank.cpp PROPERTIES COMPILE_OPTIONS "-fno-fast-math")
endif()

# All grammar OBJECT files, gathered once so every target links the same set.
set(RIPWIRE_TS_OBJECTS
  $<TARGET_OBJECTS:ts_cpp>
  $<TARGET_OBJECTS:ts_python>
  $<TARGET_OBJECTS:ts_go>
  $<TARGET_OBJECTS:ts_rust>
  $<TARGET_OBJECTS:ts_tsts>
  $<TARGET_OBJECTS:ts_tstsx>
  $<TARGET_OBJECTS:ts_swift>
  $<TARGET_OBJECTS:ts_objc>
  $<TARGET_OBJECTS:ts_javascript>
  $<TARGET_OBJECTS:ts_bash>
  $<TARGET_OBJECTS:ts_java>
  $<TARGET_OBJECTS:ts_ruby>
  $<TARGET_OBJECTS:ts_json>
  $<TARGET_OBJECTS:ts_lua>
  $<TARGET_OBJECTS:ts_dart>
  $<TARGET_OBJECTS:ts_kotlin>
  $<TARGET_OBJECTS:ts_gdscript>
  $<TARGET_OBJECTS:ts_elixir>
  $<TARGET_OBJECTS:ts_php>
  $<TARGET_OBJECTS:ts_toml>
  $<TARGET_OBJECTS:ts_yaml>
  $<TARGET_OBJECTS:ts_csharp>
  $<TARGET_OBJECTS:ts_c>
  $<TARGET_OBJECTS:ts_cuda>
  $<TARGET_OBJECTS:ts_markdown>
)

# ---- threading: std::thread / std::mutex need an explicit link on most Unixes ----
# The parallel ingest and the MCP qsnap-prefetch worker are std::thread; on Apple platforms the pthread
# runtime is inside libSystem and nothing extra is needed, which is why this was never noticed here. On
# Linux it depends on the glibc version — merged into libc from 2.34 (so ubuntu-24.04 happens to link
# without it), a separate -lpthread before that, and -pthread also changes CODEGEN, not just the link
# line. Threads::Threads asks CMake for whatever this platform actually requires; on macOS it resolves
# to nothing, so the dev build is untouched.
find_package(Threads REQUIRED)

# ---- probe target: the Phase-1/2 proof binary ----
add_executable(ripwire_probe
  src/tsprobe.cpp
  ${RIPWIRE_SRCS}
  ${_ripwire_source_identity_cpp}
  ${RIPWIRE_TS_OBJECTS})
target_link_libraries(ripwire_probe PRIVATE tree-sitter Threads::Threads)
ripwire_windows_target(ripwire_probe)
target_include_directories(ripwire_probe PRIVATE
  ${tree_sitter_SOURCE_DIR}/lib/include
  ${_ripwire_generated_include_dirs}
  src/infra
  third_party
  src)
add_dependencies(ripwire_probe ripwire_version_stamp ripwire_source_identity)

# ---- the real ripwire binary: full pipeline (ingest → graph → PageRank → minified XML) ----
# main.cpp forward-declares rw::ingest(); linking ingest.cpp supplies the real tree-sitter one.
add_executable(ripwire
  src/main.cpp
  ${RIPWIRE_SRCS}
  ${_ripwire_source_identity_cpp}
  ${RIPWIRE_TS_OBJECTS})
target_link_libraries(ripwire PRIVATE tree-sitter Threads::Threads)
ripwire_windows_target(ripwire)
target_include_directories(ripwire PRIVATE
  ${tree_sitter_SOURCE_DIR}/lib/include
  ${_ripwire_generated_include_dirs}
  src/infra
  third_party
  src)
add_dependencies(ripwire ripwire_version_stamp ripwire_source_identity)

# ---- small-vector A/B knobs (bench/svectorab.py drives both; see bench/SVECTORAB.md) ----
# RIPWIRE_SMALLVEC selects which container src/smallvec.h's `rw::SmallVec` alias resolves to:
#   0 std::vector   1 ankerl::svector   2 rw::svector (default, the shipped one)
# Unset means unset: src/smallvec.h carries the default, so the ordinary build
# passes no -D at all and its preprocessor state is byte-identical to a tree without this option.
set(RIPWIRE_SMALLVEC "" CACHE STRING "small-vector arm: 0=std::vector 1=ankerl 2=rw (default)")
if(NOT RIPWIRE_SMALLVEC STREQUAL "")
  target_compile_definitions(ripwire PRIVATE RIPWIRE_SMALLVEC=${RIPWIRE_SMALLVEC})
  target_compile_definitions(ripwire_probe PRIVATE RIPWIRE_SMALLVEC=${RIPWIRE_SMALLVEC})
  message(STATUS "small-vector arm: RIPWIRE_SMALLVEC=${RIPWIRE_SMALLVEC}")
endif()

# RIPWIRE_ALLOC_COUNT links src/alloccount.cpp, which replaces the global operator new/delete pair with a
# counting one and prints ALLOC_REPORT to stderr at exit. OFF everywhere except the A/B: a shipped binary
# must not carry it, and no gate sets it. See the honesty note at the top of src/alloccount.cpp — only the
# DELTA between arms is attributable to the container.
option(RIPWIRE_ALLOC_COUNT "count heap allocations (A/B instrument; never for a shipped build)" OFF)
if(RIPWIRE_ALLOC_COUNT)
  target_sources(ripwire PRIVATE src/alloccount.cpp)
  message(STATUS "heap-allocation counting: ON (ALLOC_REPORT on stderr at exit)")
endif()

# ---- global install: `cmake --install build --prefix /opt/homebrew --component ripwire` (see install.sh) ----
# COMPONENT ripwire + --component on install scopes this to just the binary: without it, `cmake --install`
# also runs the vendored tree-sitter subproject's own install() rules (headers/pkgconfig/static lib into
# the same --prefix) even though ripwire links it in statically and needs none of that at runtime.
install(TARGETS ripwire RUNTIME DESTINATION bin COMPONENT ripwire)
install(DIRECTORY skills/ DESTINATION share/ripwire/skills COMPONENT ripwire USE_SOURCE_PERMISSIONS)
install(DIRECTORY hooks/ DESTINATION share/ripwire/hooks COMPONENT ripwire USE_SOURCE_PERMISSIONS)

# ---- direct structural/numeric gates ----
option(RIPWIRE_TESTS "build direct CSR and PageRank verification gates" OFF)
if(RIPWIRE_TESTS)
  enable_testing()

  # unit/property gates use a SHA-locked Doctest checkout — the exact v2.4.12 release commit,
  # vendored under third_party/deps/doctest (header + parts + the cmake scripts its CMakeLists reads).
  set(_ripwire_doctest_commit 1da23a3e8119ec5cce4f9388e91b065e20bf06f5)
  # doctest is a test-only dependency: it must contribute no install() rules to this project, and the
  # vendored copy is pruned to what the build compiles (the single header + parts/ + its cmake
  # scripts). Its upstream install() block would otherwise try to install a doctest/extensions
  # directory that pruning removed — turned off at the source rather than left to `--component` luck.
  set(DOCTEST_NO_INSTALL ON)
  ripwire_use_vendored_source(doctest doctest/doctest.h)
  FetchContent_Declare(doctest
    GIT_REPOSITORY https://github.com/doctest/doctest.git
    GIT_TAG ${_ripwire_doctest_commit}
    GIT_SHALLOW FALSE)
  FetchContent_MakeAvailable(doctest)

  add_executable(ripwire_test_csr
    test/verify_csr.cpp
    src/infra/diagnostics.cpp)
  target_include_directories(ripwire_test_csr PRIVATE src/infra third_party src)
  target_link_libraries(ripwire_test_csr PRIVATE doctest::doctest)
  add_test(NAME ripwire.csr COMMAND ripwire_test_csr)

  add_executable(ripwire_test_pagerank
    test/verify_pagerank.cpp
    src/pagerank.cpp
    src/infra/diagnostics.cpp)
  target_include_directories(ripwire_test_pagerank PRIVATE src/infra third_party src)
  target_link_libraries(ripwire_test_pagerank PRIVATE doctest::doctest)
  add_test(NAME ripwire.pagerank COMMAND ripwire_test_pagerank)

  add_executable(ripwire_test_radix
    test/verify_radix.cpp
    src/infra/diagnostics.cpp)
  target_include_directories(ripwire_test_radix PRIVATE src/infra third_party src)
  add_test(NAME ripwire.radix COMMAND ripwire_test_radix)

  # src/infra/strkern.h's SIMD-vs-scalar parity, src/lexindex.h's tokenizer equivalence, and the three
  # emit escapers' byte-identity — one target, driven by test/strkerncheck.sh and test/emitescapecheck.sh
  # (each adds its own mutation and cross-arch arms, which are compile flags a second configure cannot
  # express in this tree). RIPWIRE_TEST_ROOT is the repo whose src/ and docs/ the real-text arms read, so
  # a bare `ctest` is as honest as a gate run; the gates override it with RIPWIRE_ROOT in the environment.
  add_executable(ripwire_test_strkern
    test/verify_strkern.cpp
    src/infra/diagnostics.cpp)
  target_include_directories(ripwire_test_strkern PRIVATE src/infra third_party src)
  target_compile_definitions(ripwire_test_strkern PRIVATE RIPWIRE_TEST_ROOT="${CMAKE_CURRENT_SOURCE_DIR}")
  target_link_libraries(ripwire_test_strkern PRIVATE doctest::doctest)
  add_test(NAME ripwire.strkern COMMAND ripwire_test_strkern)

  # src/infra/os_win32_logic.h — the Windows port's pure logic (Win32→errno table, UTF-8/UTF-16 and WidePath,
  # path spelling, CreateProcessW quoting, reparse/st_mode classification, wait-status and timeout conversions,
  # trusted-shell predicates). It has no <windows.h> and no platform test, so every leg compiles and runs it;
  # driven by test/oswin32logiccheck.sh (which adds the sanitizer and can-go-red arms).
  # diagnostics.cpp is not optional here, for the same reason the four targets above carry it: os_win32_logic.h states
  # its invariants with the self-check macros, and every one of them calls ::Diagnostics::ConsoleLog::handleAssert,
  # which lives out of line in that file (Diagnostics.h §"out of the static analyzer's reach"). A toolchain that keeps
  # the call — clang-cl on a plain configure — then fails to link it; the POSIX legs happened to fold every one of
  # these checks away and never referenced the symbol, so the gap was invisible until @lennix1337 linked the target
  # on Windows for #44. Listing it makes the target's sources complete rather than optimizer-dependent.
  add_executable(ripwire_test_oswin32logic
    test/verify_os_win32_logic.cpp
    src/infra/diagnostics.cpp)
  target_include_directories(ripwire_test_oswin32logic PRIVATE src/infra third_party src)
  target_link_libraries(ripwire_test_oswin32logic PRIVATE doctest::doctest)
  add_test(NAME ripwire.oswin32logic COMMAND ripwire_test_oswin32logic)

  foreach(_ripwire_test_target ripwire_test_csr ripwire_test_pagerank ripwire_test_radix ripwire_test_strkern ripwire_test_oswin32logic)
    ripwire_windows_target(${_ripwire_test_target})   # the manifest too: a test binary runs under the same code page as the product
  endforeach()
endif()

# ---- self-profiling build (src/infra/profileScope.h): -DRIPWIRE_PROFILE=ON ----
# OFF by default → every PROFILE_SCOPE compiles to ((void)0): byte-identical, zero-cost normal binary.
# ON → per-phase CNTVCT timing (+ Apple PMC cycles/instructions/cache-misses when run under sudo).
# Build in a SEPARATE dir so build/ripwire (the bench binary) stays untouched:
#   cmake -S . -B build_prof -DRIPWIRE_NATIVE=ON -DRIPWIRE_PROFILE=ON && cmake --build build_prof -j
option(RIPWIRE_PROFILE "instrument the pipeline with PROFILE_SCOPE self-profiling" OFF)
foreach(_pt ripwire ripwire_probe)
  target_compile_definitions(${_pt} PRIVATE PROFILE_ENABLED=$<BOOL:${RIPWIRE_PROFILE}>)
endforeach()

# ---- optimization-remarks build (clang -Rpass / YAML opt-record): -DRIPWIRE_OPT_REMARKS=ON ----
# Asks the optimizer what it DID and — the useful half — what it DECLINED to do: failed vectorization,
# declined inlining, LICM/unswitch bail-outs, alias-blocked hoists. Every remark is an OBSERVATION, never
# a defect: acting on one without a bench number is how readable G2-shaped code gets churned for nothing.
# scripts/optremarks.sh drives the whole loop (configure → build → triage); see docs/OPTREMARKS.md.
#
# Three properties this option deliberately keeps:
#   * SEPARATE BUILD TREE, no build type. Remarks only describe an OPTIMIZED build, but the repo forbids
#     -DCMAKE_BUILD_TYPE=Release in a dev tree (NDEBUG compiles the DISCLOSE( msg ) trace out and blinds the
#     degrade-path gates — CONTRIBUTING.md §5). No build type is needed here: RIPWIRE_ARCH_FLAGS already
#     puts the plain configuration at -O2, so build_remarks/ describes the SAME codegen build/ ships,
#     with the degrade paths still compiled in. The option is nonetheless refused inside build/ below.
#   * OUR TARGETS ONLY. Attached with target_compile_options to ripwire + ripwire_probe, never
#     add_compile_options — the vendored tree-sitter core and the sixteen grammar objects are C code we
#     do not own and their remarks are pure noise (G3: third_party is out of scope for triage).
#   * -gline-tables-only, not -g. A remark without a DebugLoc cannot be triaged (you get a mangled
#     function name and no site), and line tables are the whole of what the opt-record needs.
option(RIPWIRE_OPT_REMARKS "build with clang optimization remarks + a YAML opt-record (SEPARATE build dir)" OFF)
if(RIPWIRE_OPT_REMARKS)
  if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    # GCC's spelling is -fopt-info-*, with different pass names and no YAML opt-record; a silent no-op
    # here would hand back an empty triage that reads as "nothing to fix".
    message(FATAL_ERROR
      "RIPWIRE_OPT_REMARKS requires Clang (-Rpass=/-fsave-optimization-record are Clang spellings; "
      "GCC ${CMAKE_CXX_COMPILER_VERSION} uses -fopt-info-* instead). Configure with CMAKE_CXX_COMPILER=clang++.")
  endif()
  # Refuse to turn the ordinary dev tree into the remarks tree: build/ripwire is the binary every gate
  # and every bench number in this repo is measured against, and an accidental reconfigure would leave
  # it carrying opt-record files and 100+ MB of build-log noise with nothing on stderr to say why.
  get_filename_component(_ripwire_remarks_build_name "${CMAKE_BINARY_DIR}" NAME)
  if(_ripwire_remarks_build_name STREQUAL "build" OR _ripwire_remarks_build_name STREQUAL "asan")
    message(FATAL_ERROR
      "RIPWIRE_OPT_REMARKS must not be enabled in ${_ripwire_remarks_build_name}/ — that is the tree the "
      "gates and benches measure. Use a separate dir: cmake -S . -B build_remarks -DRIPWIRE_OPT_REMARKS=ON")
  endif()
  # -Rpass* stream human-readable remarks to stderr; -fsave-optimization-record writes the same facts
  # as one <object>.opt.yaml per TU, which is the form scripts/optremarks.py triages. Both are emitted:
  # the YAML is machine-triagable, the stderr text is what you read when you want the surrounding
  # compile context of a single site.
  #
  # RIPWIRE_OPT_REMARKS_FILTER is the same regex for all four flags. `.*` — the default — is the honest
  # first pass: you cannot decide which remark classes matter until you have seen which ones fire. It is
  # also genuinely expensive, and the cost is NOT spread evenly across the tree: src/main.cpp is one
  # ~605 KB TU holding thousands of functions, and the per-function-per-pass bookkeeping classes
  # (size-info, asm-printer, prologepilog, stack-frame-layout) grow with functions x passes. On this
  # tree the unfiltered record for main.cpp passes 800 MB and its stderr passes 400 MB, and the compile
  # slows to a crawl writing them. Do the wide pass once on the SMALL TUs, then narrow:
  #   -DRIPWIRE_OPT_REMARKS_FILTER='inline|loop-vectorize|slp-vectorizer|licm|loop-unswitch|loop-idiom'
  # which is exactly the set of passes CLAUDE.md's G2 cares about, and which cuts the record ~30x.
  set(RIPWIRE_OPT_REMARKS_FILTER ".*" CACHE STRING "regex of optimizer passes to report remarks for")
  set(RIPWIRE_OPT_REMARKS_FLAGS
    -Rpass=${RIPWIRE_OPT_REMARKS_FILTER}
    -Rpass-missed=${RIPWIRE_OPT_REMARKS_FILTER}
    -Rpass-analysis=${RIPWIRE_OPT_REMARKS_FILTER}
    -foptimization-record-passes=${RIPWIRE_OPT_REMARKS_FILTER}
    -gline-tables-only
    -fsave-optimization-record)
  foreach(_rt ripwire ripwire_probe)
    target_compile_options(${_rt} PRIVATE ${RIPWIRE_OPT_REMARKS_FLAGS})
  endforeach()
  message(STATUS "RIPWIRE_OPT_REMARKS: ON, filter='${RIPWIRE_OPT_REMARKS_FILTER}' — <object>.opt.yaml per TU under ${CMAKE_BINARY_DIR}; triage with scripts/optremarks.py")
endif()

# ---- G1 sanitizer build (CONTRIBUTING.md §4): owned code + tree-sitter core + every grammar ----
set(RIPWIRE_GRAMMAR_TARGETS
  ts_cpp ts_python ts_go ts_rust ts_tsts ts_tstsx ts_swift ts_objc
  ts_javascript ts_bash ts_java ts_ruby ts_json ts_toml ts_yaml ts_csharp ts_c ts_cuda ts_markdown
  ts_php ts_lua ts_elixir ts_dart ts_kotlin ts_gdscript)
set(RIPWIRE_RUNTIME_COMPILE_TARGETS ripwire_probe ripwire tree-sitter ${RIPWIRE_GRAMMAR_TARGETS})
set(RIPWIRE_RUNTIME_LINK_TARGETS ripwire_probe ripwire)
# The C++ subset of the compile list — the only targets that include a C++ standard library at all, and so
# the only ones the libstdc++ header exemption below has anything to say about (the grammars are C).
set(RIPWIRE_OWNED_CXX_TARGETS ripwire_probe ripwire)
if(RIPWIRE_TESTS)
  list(APPEND RIPWIRE_RUNTIME_COMPILE_TARGETS ripwire_test_csr ripwire_test_pagerank ripwire_test_radix ripwire_test_strkern ripwire_test_oswin32logic)
  list(APPEND RIPWIRE_RUNTIME_LINK_TARGETS ripwire_test_csr ripwire_test_pagerank ripwire_test_radix ripwire_test_strkern ripwire_test_oswin32logic)
  list(APPEND RIPWIRE_OWNED_CXX_TARGETS ripwire_test_csr ripwire_test_pagerank ripwire_test_radix ripwire_test_strkern ripwire_test_oswin32logic)
endif()
# G1's `integer` is a CLANG-ONLY UBSan group (unsigned-integer-overflow, implicit-*-truncation,
# implicit-integer-sign-change — the defined-but-suspicious conversions, not UB). GCC has no such group
# and rejects the whole option: "cc: error: unrecognized argument to '-fsanitize=' option: 'integer'",
# which is where the ubuntu asan leg of the first public CI run died (default cc there is gcc). The three
# `-fno-sanitize=` names and `-fsanitize-ignorelist=` below are members/features of that same Clang-only
# group, so they are dropped together — under GCC there is nothing for them to switch off.
#
# address / undefined / float-divide-by-zero / float-cast-overflow ARE all supported by GCC and stay.
# The result is a REAL but reduced stack on gcc, announced at configure time so nobody reads a green gcc
# asan run as full-G1 evidence. Public CI does not rely on this path: ci.yml pins the Linux asan job to
# clang and keeps the complete stack (see the job comment there). This branch is for a contributor who
# builds -DRIPWIRE_ASAN=ON with gcc — it must degrade honestly rather than fail to configure.
set(RIPWIRE_G1_SANITIZER_CHECKS address undefined integer float-divide-by-zero float-cast-overflow)
set(RIPWIRE_HAS_CLANG_INTEGER_SANITIZER ON)
if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  list(REMOVE_ITEM RIPWIRE_G1_SANITIZER_CHECKS integer)
  set(RIPWIRE_HAS_CLANG_INTEGER_SANITIZER OFF)
  message(STATUS "G1 sanitizers: dropped 'integer' (+ its -fno-sanitize= members and -fsanitize-ignorelist=) "
                 "— Clang-only, GCC ${CMAKE_CXX_COMPILER_VERSION} rejects the option. Remaining: "
                 "${RIPWIRE_G1_SANITIZER_CHECKS}. Build with clang for the complete G1 stack.")
endif()
list(JOIN RIPWIRE_G1_SANITIZER_CHECKS "," _ripwire_g1_check_list)
set(RIPWIRE_G1_SANITIZERS "-fsanitize=${_ripwire_g1_check_list}")
set(_ripwire_tree_sitter_ignorelist "${_ripwire_generated_dir}/tree_sitter_sanitizer_ignorelist.txt")
set(_ripwire_swift_ignorelist "${_ripwire_generated_dir}/swift_sanitizer_ignorelist.txt")
set(_ripwire_bash_ignorelist "${_ripwire_generated_dir}/bash_sanitizer_ignorelist.txt")
set(_ripwire_libstdcxx_ignorelist "${_ripwire_generated_dir}/libstdcxx_sanitizer_ignorelist.txt")
# Full G1 remains enabled on ripwire and every grammar. Pinned tree-sitter v0.26.9 intentionally uses
# defined C unsigned wrap throughout reverse loops and erase-at-zero iteration, so only that non-UB check
# is disabled target-wide for the pinned core. All other integer/undefined/conversion checks remain on.
# Pinned core uses defined unsigned wrap plus signed narrowing in its UINT16_MAX sentinel and inlined ICU
# UTF-8 macros, so those two checks are disabled only for the core target. Subtree progress quantization and
# generated external-scanner C function pointers remain exact-function exceptions. The lookahead sentinel
# remains on upstream master as of 2026-07-12.
# The two truncation exemptions are exact-function and both quantization-by-design in the pinned core:
#   * ts_subtree_summarize_children stores a uint32 repeat depth into the uint16 repeat_depth field
#     (subtree.c:469/471) — a >65535-deep repeat chain (a ~70K-element generated initializer, e.g.
#     cpython's Modules/unicodename_db.h) wraps it by design and balancing still succeeds. Verified
#     live 2026-08-11: without this entry the G1 stack aborts at subtree.c:469:34 ("value 65536 …
#     changed the value to 0"); the historical balance_subtree entry alone never covered this site.
#   * ts_parser__balance_subtree quantizes its compression counter into a uint8 operations budget
#     (parser.c:1903, `i >> 4` into uint8_t) — live whenever i >= 4096, so that entry stays.
# test/vendorpatchcheck.sh arms D/E/G pin this block: every fun: entry must name a function that
# exists in the vendored tree, the summarize_children entry must be present, and a generated
# 70001-element initializer must parse clean under the asan flavour.
file(WRITE "${_ripwire_tree_sitter_ignorelist}"
  "[implicit-unsigned-integer-truncation]\nfun:ts_subtree_summarize_children\nfun:ts_parser__balance_subtree\n"
  "[function]\nfun:ts_parser__external_scanner_create\n")
# Swift's scanner stores lexer->lookahead (-1 at EOF) in uint32 inside this exact whitespace helper.
file(WRITE "${_ripwire_swift_ignorelist}"
  "[implicit-integer-sign-change]\nfun:eat_whitespace\n")
# Bash's scanner decrements zero-valued nesting depths after marking the scan complete; uint32 wrap is intentional.
file(WRITE "${_ripwire_bash_ignorelist}"
  "[unsigned-integer-overflow]\nfun:scan\n")
# libstdc++'s std::basic_string_view::find/rfind scan loops are written `for (++__size; __size-- > 0;)`, so
# the counter wraps past zero BY DESIGN on the iteration that ends the loop. Under G1's Clang-only
# `integer` group that is a hard stop, because G1 is -fno-sanitize-recover=all: the first real Linux run
# (Ubuntu 24.04, clang 18 + libstdc++, full G1) aborted with
#   string_view.tcc:124:25: runtime error: unsigned integer overflow: 0 - 1
# reached from rw::lowerExtensionOf (src/ingest.cpp:160) via string_view::rfind, and again at :109 (the
# find twin) partway through cachefuzzcheck's qsnap ASan sweep. This is library-internal, intentional, and
# not UB — nothing in ripwire can avoid it short of not calling find/rfind. libc++ has no such wrap, which
# is why macOS never saw it and why this entry is inert (but must still parse) on the Apple leg.
# Scoped as narrowly as the mechanism allows: these THREE libstdc++ headers' code, this ONE check. Every
# other integer and conversion check stays on for our own code, including in the same translation units.
#
# The re-smoke on the same Ubuntu 24.04 / clang 18 / libstdc++ image found std::basic_string carrying the
# identical deliberate-wrap idiom in two more headers, so all three entries share the one section:
#   * bits/basic_string.h:490 — `_S_compare` returns `__n1 - __n2` computed in size_type, so any comparison
#     whose left operand is the shorter string wraps by design. Reached from a plain `std::string`
#     `operator<=`/`operator<` inside a sort comparator, i.e. from ordinary ripwire code that cannot avoid
#     it short of not comparing strings.
#   * bits/basic_string.tcc:689 — the basic_string twin of the string_view find/rfind loop above, same
#     `for (++__size; __size-- > 0;)` shape, same wrap on the iteration that ends the loop.
# Both are library-internal, intentional and not UB; both abort the run under -fno-sanitize-recover=all;
# both are absent on libc++, which is why the Apple leg never saw them and why these entries are inert
# (but must still parse) on macOS. With the three entries in place the Linux ASan self-run exits 0 with
# empty stderr and cachefuzzcheck's 13 UBSan arms go green.
# <format> / <print> (libstdc++ 14): the formatting scanner spells "npos" as an int -1 converted to size_t
# (c++/14/format:3903 under GCC 14.2, reached from std::print via vprint_nonunicode) — a DEFINED conversion the
# Clang-only integer group flags as suspicious, in library code this tree does not own; exempted the way
# basic_string's wrap idiom is below, for the group's four conversion/overflow checks. Found by the first
# std::print CI run (34284272539, asan ubuntu-24.04: `ripwire --version` aborted, exit 134) — the emitter
# (src/infra/emit.h) routes every formatted write through these headers, so the exemption is what lets the
# complete G1 stack keep running on the clang leg now that --version itself exercises std::format.
# Spelled c\+\+, not c++: LLVM before 18 (Xcode 16.2's Apple clang 16 among them) parses this list as REGEX
# with * expanded to .*, and a bare c++ is a malformed regex — the macOS asan leg's BUILD failed on it
# (run 34288200871, "malformed sanitizer ignorelist"). The escape is a literal + under both the regex and
# the glob (LLVM 18+) readers; proved both ways locally by forcing v1 with #!special-case-list-v1.
file(WRITE "${_ripwire_libstdcxx_ignorelist}"
  "[unsigned-integer-overflow]\nsrc:*/bits/string_view.tcc\n"
  "src:*/bits/basic_string.h\n"
  "src:*/bits/basic_string.tcc\n"
  "src:*/include/c\\+\\+/*/format\n"
  "src:*/include/c\\+\\+/*/print\n"
  "[implicit-integer-sign-change]\nsrc:*/include/c\\+\\+/*/format\n"
  "src:*/include/c\\+\\+/*/print\n"
  "[implicit-signed-integer-truncation]\nsrc:*/include/c\\+\\+/*/format\n"
  "src:*/include/c\\+\\+/*/print\n"
  "[implicit-unsigned-integer-truncation]\nsrc:*/include/c\\+\\+/*/format\n"
  "src:*/include/c\\+\\+/*/print\n")
if(WIN32)
  # MSVC STL _Is_drive_prefix performs a defined unsigned wrap; third-party header, Windows-only.
  # A single file-scoped rule below covers every function in the vendor header, so no function-name
  # pattern (which g1configcheck.sh's audited list bans outright — a wildcard by name is the easy way
  # to smuggle an unrelated symbol out of the sanitizer) is needed; project arithmetic elsewhere,
  # including in this same header should it ever gain project-authored code, stays covered by G1.
  file(APPEND "${_ripwire_libstdcxx_ignorelist}"
    "[unsigned-integer-overflow]\nsrc:*/include/filesystem\n")
endif()

if(RIPWIRE_ASAN)
  # AppleClang 17's ASan runtime hangs in its own start-up on macOS 26 (Darwin 25), before main, so every
  # sanitizer run times out. CI's Xcode 26.6 AppleClang 21 is unaffected. A warning, not an error: the
  # tree still builds, and CONTRIBUTING's sanitizer section has the Homebrew LLVM 22 recipe.
  if(APPLE AND CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang" AND CMAKE_CXX_COMPILER_VERSION VERSION_LESS 21
     AND CMAKE_HOST_SYSTEM_VERSION VERSION_GREATER_EQUAL 25)
    message(WARNING "RIPWIRE_ASAN: AppleClang ${CMAKE_CXX_COMPILER_VERSION} on macOS 26 is known to hang in "
      "ASan start-up before main. Configure this tree with Homebrew LLVM 22 (CONTRIBUTING.md, Sanitizer build).")
  endif()
  set(_ripwire_windows_clangcl_asan OFF)
  set(_ripwire_no_omit_frame_pointer -fno-omit-frame-pointer)
  # The optimization and debug-info spellings the sanitizer arm needs, in the driver's own dialect. clang-cl only
  # WARNS on a GNU-spelled -O2/-g ("unknown argument ignored in clang-cl"), which is the worst of the two outcomes:
  # the flavour silently builds unoptimized and without line tables, so a sanitizer report has no frames. Chosen here
  # beside /Oy- rather than at the two foreach loops below, so the dialect is decided once.
  set(_ripwire_asan_opt_debug -O2 -g)
  # CMake's MSVC linker rule invokes CMAKE_LINKER directly. With ClangCL, passing the LLVM
  # -fsanitize flags to link.exe instruments the objects but never loads the Clang sanitizer
  # runtime, leaving __asan_* unresolved. Use clang-cl as the link driver for this one flavour;
  # its driver preserves the MSVC ABI/import libraries and adds the matching runtime.
  if(WIN32 AND CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
    set(_ripwire_windows_clangcl_asan ON)
    set(_ripwire_no_omit_frame_pointer /Oy-)
    set(_ripwire_asan_opt_debug /O2 /Z7)
    string(REPLACE "<CMAKE_LINKER>" "<CMAKE_CXX_COMPILER>" CMAKE_CXX_LINK_EXECUTABLE
      "${CMAKE_CXX_LINK_EXECUTABLE}")
    # The replacement template does not carry the generator's per-target FLAGS. Keep the
    # sanitizer thunk and the instrumented objects on the same dynamic CRT as the compile rule.
    string(REPLACE "<CMAKE_CXX_COMPILER> ${CMAKE_CL_NOLOGO} <OBJECTS>"
      "<CMAKE_CXX_COMPILER> ${CMAKE_CL_NOLOGO} /MD <OBJECTS> ${RIPWIRE_G1_SANITIZERS}"
      CMAKE_CXX_LINK_EXECUTABLE "${CMAKE_CXX_LINK_EXECUTABLE}")
    string(REPLACE " /out:<TARGET>" " /link /out:<TARGET>"
      CMAKE_CXX_LINK_EXECUTABLE "${CMAKE_CXX_LINK_EXECUTABLE}")
    message(STATUS "RIPWIRE_ASAN: using the ClangCL driver for Windows sanitizer links")
  endif()
  foreach(_t IN LISTS RIPWIRE_RUNTIME_COMPILE_TARGETS)
    target_compile_options(${_t} PRIVATE ${RIPWIRE_G1_SANITIZERS}
      -fno-sanitize-recover=all ${_ripwire_no_omit_frame_pointer} ${_ripwire_asan_opt_debug})
  endforeach()
  foreach(_t IN LISTS RIPWIRE_RUNTIME_LINK_TARGETS)
    if(NOT _ripwire_windows_clangcl_asan)
      target_link_options(${_t} PRIVATE ${RIPWIRE_G1_SANITIZERS})
    endif()
  endforeach()
  # Every exemption below names a check inside the Clang-only `integer` group, or uses
  # -fsanitize-ignorelist=, which GCC does not implement. With `integer` absent there is nothing to
  # exempt, and passing them anyway is the same "unrecognized argument" failure one level down.
  if(RIPWIRE_HAS_CLANG_INTEGER_SANITIZER)
    target_compile_options(tree-sitter PRIVATE
      -fno-sanitize=unsigned-integer-overflow
      -fno-sanitize=implicit-signed-integer-truncation
      -fno-sanitize=implicit-integer-sign-change
      "-fsanitize-ignorelist=${_ripwire_tree_sitter_ignorelist}")
    target_compile_options(ts_swift PRIVATE "-fsanitize-ignorelist=${_ripwire_swift_ignorelist}")
    target_compile_options(ts_bash PRIVATE "-fsanitize-ignorelist=${_ripwire_bash_ignorelist}")
    foreach(_t IN LISTS RIPWIRE_OWNED_CXX_TARGETS)
      target_compile_options(${_t} PRIVATE "-fsanitize-ignorelist=${_ripwire_libstdcxx_ignorelist}")
    endforeach()
  endif()

  # Darwin and Windows runtimes reject detect_leaks=1 at startup. Keep the local ASan/UBSan gate
  # executable and explicit; LeakSanitizer remains a Linux/upstream-runtime CI gate using the
  # committed tree-sitter suppressions rather than being falsely claimed on either platform.
  if(APPLE OR WIN32)
    set(_ripwire_asan_options "detect_leaks=0:halt_on_error=1:abort_on_error=1")
  else()
    set(_ripwire_asan_options "detect_leaks=1:halt_on_error=1:abort_on_error=1")
  endif()
  set(_ripwire_asan_runtime_copy_command)
  if(WIN32 AND CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    # clang-cl links the ASAN dynamic runtime, but Windows does not search Clang's resource
    # directory for DLLs. Discover the matching directory from the active compiler so the fixture
    # exercises this build without requiring a system-wide DLL installation. Copying beside the
    # executable is deliberate: putting a semicolon-separated Windows PATH in a CMake command is
    # parsed as a list of unrelated arguments by the Ninja generator.
    execute_process(
      COMMAND "${CMAKE_CXX_COMPILER}" -print-resource-dir
      OUTPUT_VARIABLE _ripwire_clang_resource_dir
      OUTPUT_STRIP_TRAILING_WHITESPACE
      ERROR_QUIET)
    if(_ripwire_clang_resource_dir)
      file(TO_CMAKE_PATH "${_ripwire_clang_resource_dir}/lib/windows" _ripwire_asan_runtime_dir)
      list(APPEND _ripwire_asan_runtime_copy_command
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "${_ripwire_asan_runtime_dir}/clang_rt.asan_dynamic-x86_64.dll"
          "$<TARGET_FILE_DIR:ripwire>")
      message(STATUS "RIPWIRE_ASAN: fixture copies the runtime DLL from ${_ripwire_asan_runtime_dir}")
    else()
      message(WARNING "RIPWIRE_ASAN: clang resource directory was not discoverable; runtime fixture may miss the ASAN DLL")
    endif()
  endif()
  if(WIN32 AND _ripwire_asan_runtime_dir)
    foreach(_t IN LISTS RIPWIRE_RUNTIME_LINK_TARGETS)
      add_custom_command(TARGET ${_t} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "${_ripwire_asan_runtime_dir}/clang_rt.asan_dynamic-x86_64.dll"
          "$<TARGET_FILE_DIR:${_t}>")
    endforeach()
  endif()
  add_custom_target(ripwire_asan_fixture
    ${_ripwire_asan_runtime_copy_command}
    COMMAND ${CMAKE_COMMAND} -E env
      "ASAN_OPTIONS=${_ripwire_asan_options}"
      "UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1"
      "LSAN_OPTIONS=suppressions=${CMAKE_CURRENT_SOURCE_DIR}/lsan_suppressions.txt"
      $<TARGET_FILE:ripwire> ${CMAKE_CURRENT_SOURCE_DIR}/test/fixture --no-cache
    DEPENDS ripwire
    COMMENT "Run the G1 fixture with the platform leak-detection policy")
endif()

# ---- compile-time fences: warnings that are errors on OUR C++ targets, every compiler, every flavour ----
# The tree passes no warning set (no -Wall), so until this block a check only a warning could make was a check nobody
# read, and on GCC -Wswitch did not run at all: GCC enables it only under -Wall, Clang by default.
#   -Werror=switch                  a switch over an enum with no `default:` must name every enumerator, so appending
#                                   one (a Lang, a SymKind, a RefRole) is a compile error at every per-value switch that
#                                   has to decide it. The house rule that makes this bite: a switch returning one answer
#                                   PER ENUMERATOR carries no `default:`, and ends with a plain `return` for a byte past
#                                   the enum (a corrupt cache value); GCC's -Wreturn-type needs that line and Clang
#                                   accepts it. A switch over a deliberate SUBSET keeps its `default:`.
#   -Werror=implicit-fallthrough    a case body that falls into the next label says so with [[fallthrough]].
# Both were measured at 0 diagnostics on this tree before they became errors (AppleClang and Homebrew clang, debug and
# -DNDEBUG), so they cost nothing today and fence the next edit. GCC's first run of them is CI's.
# OUR TARGETS ONLY, the same rule the sanitizer and separate-storage blocks follow: the tree-sitter core and the grammar
# objects are generated C we do not own, and their scanners fall through by design.
#
# PER COMPILER, in ONE place. `-Werror=switch` is a GCC/Clang driver spelling. clang-cl takes it (its driver accepts
# clang's own warning flags beside the MSVC ones — @lennix1337's Windows run compiled with these two attached and
# reported one warning, not a flag error), but plain cl.exe reads `-W` + a number and refuses the whole command line:
# "command line error D8021: invalid numeric argument '/Werror=switch'", the fifth failure of that run. cl.exe's
# nearest equivalent to -Wswitch is C4062 (an enumerator not handled and no `default:`), promoted to an error with
# /we4062; it has no counterpart for -Wimplicit-fallthrough at all — MSVC spells that one only as the /analyze-only
# C26819 — so on cl.exe that half of the fence is NOT held, and the [[fallthrough]] rule is enforced by every other
# leg instead. This is the only clang-dialect flag set in this file that is not already chosen per compiler
# (cmake/PortableFlags.cmake branches on the same two conditions; the -mllvm option below is probed before use).
#
# UB-CLASS FENCES (0.6.3): diagnostics whose every hit is a program that computes a silently wrong answer — a value
# read before it was written, a function that falls off its end, a pointer to a dead frame, a printf whose arguments
# do not match its format, an index past a fixed array. NOT a style set: nothing here is -Wall, -Wextra or -Wshadow.
# Measured 2026-09-24 on 60b65f02 over all 11 owned TUs (ripwire, ripwire_probe, the five RIPWIRE_TESTS verifiers),
# each flag as a plain -W first: AppleClang 17 and Homebrew clang 22 (-fsyntax-only, debug and -DNDEBUG), GCC 13.4,
# 14.4 and 16.2 (a real compile, -O0 and -O3 -DNDEBUG): 0 hits for every flag kept below, on every one of them. A
# planted instance of each fires, so the zero is not a flag that never ran. cl.exe: 0 of the mapped C-numbers in the
# last full-matrix Windows log (the default /W1, where each one below is on). Windows-only code (src/infra/os_win32.cpp)
# compiles only there, so the two Windows legs are the first run of these errors on it, as they were for the two above.
#   return-type          a non-void function that can reach its closing brace (C4715 on cl.exe).
#   uninitialized        a read of a local that no path wrote (C4700). Clang adds sometimes-uninitialized (one branch
#                        skips the write) and conditional-uninitialized (a loop may skip it): both front-end CFG
#                        passes, identical at every -O. GCC's -Werror=uninitialized ALSO promotes -Wmaybe-uninitialized
#                        (verified on gcc 16: a loop-conditional write is a hard error with the one flag), and that
#                        one is the optimizer's guess — it moves with -O level and GCC release — so -Wno-maybe-
#                        uninitialized keeps it exactly as off as it was before this block.
#   format format-security  printf-family argument/format mismatch, and a non-literal format (C4477/C4473 on
#                        cl.exe; the non-literal half is C4774, a level-4 warning never measured on this tree: not held).
#                        On GCC, -Werror=format also makes -Wformat-overflow=1 and -Wformat-truncation=1 errors (a
#                        planted sprintf/snprintf overflow is a hard error on g++ 13/14/16 at -O0 and -O2). Both are
#                        middle-end passes that read value ranges, like the ones ruled out here, but level 1 fires only
#                        on a certain or likely overflow, the snprintf-truncation class this repo has shipped as a bug,
#                        and both are 0 on this tree: kept. If one proves optimizer-noisy on a CI GCC, drop it on GCC
#                        with -Wno-error=format-truncation / -Wno-error=format-overflow and write it down here.
#   return-stack-address (GCC: return-local-addr) the address of a local or a temporary returned (C4172).
#   dangling             Clang only: the -Wdangling group (a view or pointer that outlives the object it names —
#                        string_view of a temporary, a dangling member, a gsl::Pointer from a dead owner). cl.exe has
#                        only the /analyze-only C26815/C26816: not held there.
#   array-bounds         Clang only: a constant index past a fixed-size array, decided in Sema. GCC's -Warray-bounds is a
#                        different pass: it needs -O2 and reads the optimizer's value ranges, so its answer moves with
#                        -O level, inlining and GCC release — the property that rules out maybe-uninitialized. It is 0
#                        here on GCC 13/14/16 at -O3 too, and still OFF on GCC for that reason. cl.exe's C4789 is a
#                        backend warning of optimised builds, which the plain Windows legs never run: not held.
# A flag that is noise on one compiler is dropped on that compiler and written down here, never silenced by a pragma.
if(MSVC AND NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  set(RIPWIRE_COMPILE_TIME_FENCE_FLAGS /we4062
    /we4715 /we4700 /we4477 /we4473 /we4172)
elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  set(RIPWIRE_COMPILE_TIME_FENCE_FLAGS -Werror=switch -Werror=implicit-fallthrough
    -Werror=return-type -Werror=uninitialized -Werror=sometimes-uninitialized -Werror=conditional-uninitialized
    -Werror=format -Werror=format-security -Werror=return-stack-address -Werror=dangling -Werror=array-bounds)
else()
  set(RIPWIRE_COMPILE_TIME_FENCE_FLAGS -Werror=switch -Werror=implicit-fallthrough
    -Werror=return-type -Werror=uninitialized -Wno-maybe-uninitialized
    -Werror=format -Werror=format-security -Werror=return-local-addr)
endif()
foreach(_t IN LISTS RIPWIRE_OWNED_CXX_TARGETS)
  target_compile_options(${_t} PRIVATE ${RIPWIRE_COMPILE_TIME_FENCE_FLAGS})
endforeach()

# ---- G-race ThreadSanitizer build (the qsnap-prefetch worker vs the request loop) ----
# A SEPARATE target/dir from ASan (TSan and ASan are mutually exclusive). Vets the one concurrent path in the
# server: the detached HEAD-snapshot prefetch thread against a request-thread ingest, serialized by
# quality::headSnapshotIngestMutex + the single-flight atomic. Build + run the (b) non-vacuity scenario:
#   cmake -S . -B tsan -DRIPWIRE_TSAN=ON && cmake --build tsan -j
if(RIPWIRE_TSAN)
  foreach(_t IN LISTS RIPWIRE_RUNTIME_COMPILE_TARGETS)
    target_compile_options(${_t} PRIVATE -fsanitize=thread -fno-omit-frame-pointer -O2 -g)
  endforeach()
  foreach(_t IN LISTS RIPWIRE_RUNTIME_LINK_TARGETS)
    target_link_options(${_t} PRIVATE -fsanitize=thread)
  endforeach()
endif()

# ---- separate-storage alias analysis: -mllvm -basic-aa-separate-storage (LLVM 17 keeps it OFF) ----
# src/infra/Diagnostics.h §6's ASSUME_NO_ALIAS lowers, in release, to `llvm.assume [ "separate_storage"(a, b) ]`
# through __builtin_assume_separate_storage. The FRONT END has emitted that bundle since clang 17; whether BasicAA
# READS it is a separate switch inside the optimizer, llvm/lib/Analysis/BasicAliasAnalysis.cpp:
#     static cl::opt<bool> EnableSeparateStorageAnalysis("basic-aa-separate-storage", cl::Hidden, cl::init(false))
# in LLVM 17, and cl::init(true) from LLVM 18 on. So on an LLVM-17 toolchain — AppleClang 16.0.0.16000026 (Xcode
# 16.2: the macos-14 CI runners and release.yml's macos-arm64 leg through 0.6.1) — the header compiles, the IR carries the bundle,
# and codegen is byte-identical to no promise at all. Found by CI job "release (macos-14, plain, appleclang, shard
# 4/4)" on PR #200: test/noaliascheck.sh arms 2, 2/3 and 6 red ("accNew still reloads a after the store", "NO
# CONTRAST", "not at least 2 below plain"), arm 7 and the IR-bundle row green — the front-end half worked, the
# optimizer half was off. Reproduced on Apple clang 21: the arm-2 probe is 5 instructions by default, 9 with
# `-mllvm -basic-aa-separate-storage=false`, 5 with `=true`.
#
# Why LLVM 17 left it off, and why turning it on there is safe: llvm/llvm-project#76864 "[BasicAA] Enable separate
# storage hints by default" (merged 2024-01-03) flipped the default because "a few months of experimentation in a
# large codebase did not reveal any significant build speed regressions" — the LLVM-17 default was a compile-time
# hedge, not a soundness one; #76770 the same week only makes the hint fire in more contexts. LLVM 17 with the option
# on runs the analysis LLVM 18+ runs unconditionally.
#
# The option's name is the same from LLVM 17 through 21 and clang takes it as a compile flag, so it is passed
# wherever the compiler accepts it: on LLVM 17 it turns the analysis on, on 18+ it restates the default (a no-op).
# What the option buys on LLVM 17 is the SCALAR half only: the reload after a store through a possibly-aliasing
# pointer goes away, but the loop vectorizer's overlap checks stay, because LLVM 17 consults the hint only at the
# assume's own context and LoopAccessAnalysis never supplies one (llvm/llvm-project#64666, fixed in LLVM 18 by
# #76770). CI showed exactly that split on PR #200 head 5156d668: noaliascheck arm 2 green, arm 6 at plain.
# Probed, never assumed — GCC rejects -mllvm outright and a clang whose LLVM had dropped the name would reject the
# option; either way the check says no, the build keeps the compiler default, and the header's debug check still
# runs. The two-token option rides in CMAKE_REQUIRED_FLAGS (a whitespace-split string, the way the libFuzzer probe
# above passes its flags). Verified 2026-09-12 in a scratch configure: Apple clang 21 says yes, and the same probe
# over `-mllvm -bogus-option-xyz` says no (clang exits 1 on an unknown -mllvm name). test/noaliascheck.sh reads the
# cached answer back out of build/CMakeCache.txt and fails if its own probe of the same compiler disagrees.
#
# OUR TARGETS ONLY, via target_compile_options — never add_compile_options: the tree-sitter core and the grammar
# objects are C that never spells the builtin, and per-target attachment is the rule this file already follows for
# the remarks and sanitizer flags. RIPWIRE_OWNED_CXX_TARGETS is ripwire, ripwire_probe and the test executables, in
# every flavour (plain, Release, asan, tsan): the list is flavour-independent, so nothing here is.
#
# LTO. With -flto the compile step still runs the PRE-link pipeline (which already removes the arm-2 reload under
# this option — measured: compile default + link `=false` gives 5), and ld64's libLLVMLTO runs the POST-link one,
# whose BasicAA reads the same cl::opt. So under LTO the option must reach the link as well, or every inlining
# opportunity the link step creates on an LLVM-17 toolchain is analysed with the promise off. Apple ld64 takes it as
# `-Wl,-mllvm,-basic-aa-separate-storage` — verified: compile `=false` + link `=false` gives 9 instructions, compile
# `=false` + link `=true` gives 5, and a bogus name fails the link ("libLLVMLTO: Unknown command line argument") —
# and it is probed below with a real -flto link before it is attached. The ELF spelling
# (`-Wl,-plugin-opt=-basic-aa-separate-storage` for lld / gold) is deliberately NOT added: it could not be verified
# on this machine, and no CI or release leg pairs LTO with an LLVM-17 ELF toolchain (ubuntu-24.04's clang is 18,
# the Linux release leg is gcc, which never sees the builtin). An LTO build on such a toolchain keeps the compile-time
# option and the linker's default; that limit is stated here rather than papered over with an unverified flag.
include(CheckCXXCompilerFlag)
set(_ripwire_required_flags_save "${CMAKE_REQUIRED_FLAGS}")
set(CMAKE_REQUIRED_FLAGS "-mllvm -basic-aa-separate-storage")
check_cxx_compiler_flag("" RIPWIRE_CXX_HAS_BASIC_AA_SEPARATE_STORAGE)
set(CMAKE_REQUIRED_FLAGS "${_ripwire_required_flags_save}")
if(RIPWIRE_CXX_HAS_BASIC_AA_SEPARATE_STORAGE)
  foreach(_t IN LISTS RIPWIRE_OWNED_CXX_TARGETS)
    target_compile_options(${_t} PRIVATE -mllvm -basic-aa-separate-storage)
  endforeach()
  set(_ripwire_separate_storage_link "no LTO, so nothing runs at link")
  if(RIPWIRE_LTO)
    if(APPLE)
      include(CheckCXXSourceCompiles)
      set(_ripwire_required_flags_save "${CMAKE_REQUIRED_FLAGS}")
      set(_ripwire_required_link_options_save "${CMAKE_REQUIRED_LINK_OPTIONS}")
      set(CMAKE_REQUIRED_FLAGS "-flto")
      set(CMAKE_REQUIRED_LINK_OPTIONS "-flto;-Wl,-mllvm,-basic-aa-separate-storage")
      check_cxx_source_compiles("int main() { return 0; }" RIPWIRE_LD64_HAS_BASIC_AA_SEPARATE_STORAGE)
      set(CMAKE_REQUIRED_FLAGS "${_ripwire_required_flags_save}")
      set(CMAKE_REQUIRED_LINK_OPTIONS "${_ripwire_required_link_options_save}")
      if(RIPWIRE_LD64_HAS_BASIC_AA_SEPARATE_STORAGE)
        foreach(_t IN LISTS RIPWIRE_OWNED_CXX_TARGETS)
          target_link_options(${_t} PRIVATE "-Wl,-mllvm,-basic-aa-separate-storage")
        endforeach()
        set(_ripwire_separate_storage_link "forced on at the LTO link too (-Wl,-mllvm,-basic-aa-separate-storage)")
      else()
        set(_ripwire_separate_storage_link "LTO link keeps the linker default (ld64 refused -Wl,-mllvm,-basic-aa-separate-storage)")
      endif()
    else()
      set(_ripwire_separate_storage_link "LTO link keeps the linker default (the ELF -plugin-opt spelling is unverified — see the comment above)")
    endif()
  endif()
  message(STATUS "separate-storage alias analysis: forced on (-mllvm -basic-aa-separate-storage — turns BasicAA's separate_storage reader on for LLVM 17 / AppleClang 16, a no-op on LLVM 18+); ${_ripwire_separate_storage_link}")
else()
  message(STATUS "separate-storage alias analysis: compiler default (${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION} does not accept -mllvm -basic-aa-separate-storage; ASSUME_NO_ALIAS keeps its debug check, the release promise is whatever this optimizer does by default)")
endif()

# ---- opt-in ingestion fuzzing: isolated coverage-instrumented parser objects ----
# Keep these copies separate from production objects: fuzzer-no-link coverage callbacks must never leak
# into a normal executable. RIPWIRE_FUZZ is OFF by default and every target is EXCLUDE_FROM_ALL.
if(RIPWIRE_FUZZ)
  set(RIPWIRE_FUZZ_COMPILE_OPTIONS
    -fsanitize=fuzzer-no-link,address,undefined,integer,float-divide-by-zero,float-cast-overflow
    -fno-sanitize-recover=all -fno-omit-frame-pointer -O2 -g)
  set(RIPWIRE_FUZZ_LINK_OPTIONS
    -fsanitize=fuzzer,address,undefined,integer,float-divide-by-zero,float-cast-overflow)

  add_library(ripwire_tree_sitter_fuzz STATIC EXCLUDE_FROM_ALL ${tree_sitter_SOURCE_DIR}/lib/src/lib.c)
  target_include_directories(ripwire_tree_sitter_fuzz PRIVATE
    ${tree_sitter_SOURCE_DIR}/lib/src ${tree_sitter_SOURCE_DIR}/lib/src/wasm
    PUBLIC ${tree_sitter_SOURCE_DIR}/lib/include)
  target_compile_definitions(ripwire_tree_sitter_fuzz PRIVATE
    _POSIX_C_SOURCE=200112L _DEFAULT_SOURCE _BSD_SOURCE _DARWIN_C_SOURCE)
  target_compile_options(ripwire_tree_sitter_fuzz PRIVATE ${RIPWIRE_FUZZ_COMPILE_OPTIONS}
    -fno-sanitize=unsigned-integer-overflow
    -fno-sanitize=implicit-signed-integer-truncation
    -fno-sanitize=implicit-integer-sign-change
    "-fsanitize-ignorelist=${_ripwire_tree_sitter_ignorelist}")
  set_target_properties(ripwire_tree_sitter_fuzz PROPERTIES C_STANDARD 11 POSITION_INDEPENDENT_CODE ON)

  set(RIPWIRE_FUZZ_TARGETS)
  function(add_ripwire_fuzzer NAME LANGUAGE GRAMMAR_SOURCE_KEY)
    set(_ripwire_grammar_source_var "RIPWIRE_TS_${GRAMMAR_SOURCE_KEY}_SOURCES")
    set(_ripwire_fuzz_grammar_target "ripwire_fuzz_grammar_${NAME}")
    add_library(${_ripwire_fuzz_grammar_target} OBJECT EXCLUDE_FROM_ALL ${${_ripwire_grammar_source_var}})
    list(GET ${_ripwire_grammar_source_var} 0 _ripwire_fuzz_parser_source)
    get_filename_component(_ripwire_fuzz_grammar_dir "${_ripwire_fuzz_parser_source}" DIRECTORY)
    target_include_directories(${_ripwire_fuzz_grammar_target} PRIVATE
      ${tree_sitter_SOURCE_DIR}/lib/include ${_ripwire_fuzz_grammar_dir})
    target_compile_options(${_ripwire_fuzz_grammar_target} PRIVATE ${RIPWIRE_FUZZ_COMPILE_OPTIONS})
    if(NAME STREQUAL "swift")
      target_compile_options(${_ripwire_fuzz_grammar_target} PRIVATE "-fsanitize-ignorelist=${_ripwire_swift_ignorelist}")
    elseif(NAME STREQUAL "bash")
      target_compile_options(${_ripwire_fuzz_grammar_target} PRIVATE "-fsanitize-ignorelist=${_ripwire_bash_ignorelist}")
    endif()
    set_target_properties(${_ripwire_fuzz_grammar_target} PROPERTIES C_STANDARD 11 POSITION_INDEPENDENT_CODE ON)

    set(_ripwire_fuzz_target "ripwire_fuzz_${NAME}")
    add_executable(${_ripwire_fuzz_target} EXCLUDE_FROM_ALL
      test/fuzz/fuzz_ingest.cpp $<TARGET_OBJECTS:${_ripwire_fuzz_grammar_target}>)
    target_compile_definitions(${_ripwire_fuzz_target} PRIVATE RIPWIRE_FUZZ_LANGUAGE=${LANGUAGE})
    target_compile_options(${_ripwire_fuzz_target} PRIVATE ${RIPWIRE_FUZZ_COMPILE_OPTIONS})
    target_link_options(${_ripwire_fuzz_target} PRIVATE ${RIPWIRE_FUZZ_LINK_OPTIONS})
    target_link_libraries(${_ripwire_fuzz_target} PRIVATE ripwire_tree_sitter_fuzz)
    target_include_directories(${_ripwire_fuzz_target} PRIVATE ${tree_sitter_SOURCE_DIR}/lib/include)
    set(RIPWIRE_FUZZ_TARGETS ${RIPWIRE_FUZZ_TARGETS} ${_ripwire_fuzz_target} PARENT_SCOPE)
  endfunction()

  add_ripwire_fuzzer(cpp        tree_sitter_cpp        cpp)
  add_ripwire_fuzzer(python     tree_sitter_python     python)
  add_ripwire_fuzzer(go         tree_sitter_go         go)
  add_ripwire_fuzzer(rust       tree_sitter_rust       rust)
  add_ripwire_fuzzer(typescript tree_sitter_typescript tsts)
  add_ripwire_fuzzer(tsx        tree_sitter_tsx        tstsx)
  add_ripwire_fuzzer(swift      tree_sitter_swift      swift)
  add_ripwire_fuzzer(objc       tree_sitter_objc       objc)
  add_ripwire_fuzzer(javascript tree_sitter_javascript javascript)
  add_ripwire_fuzzer(bash       tree_sitter_bash       bash)
  add_ripwire_fuzzer(java       tree_sitter_java       java)
  add_ripwire_fuzzer(ruby       tree_sitter_ruby       ruby)
  add_ripwire_fuzzer(json       tree_sitter_json       json)
  add_ripwire_fuzzer(toml       tree_sitter_toml       toml)
  add_ripwire_fuzzer(yaml       tree_sitter_yaml       yaml)
  add_ripwire_fuzzer(csharp     tree_sitter_c_sharp    csharp)
  add_ripwire_fuzzer(c          tree_sitter_c          c)
  add_ripwire_fuzzer(php        tree_sitter_php        php)
  add_ripwire_fuzzer(dart       tree_sitter_dart       dart)
  add_ripwire_fuzzer(elixir     tree_sitter_elixir     elixir)
  add_ripwire_fuzzer(lua        tree_sitter_lua        lua)
  add_ripwire_fuzzer(kotlin     tree_sitter_kotlin     kotlin)
  add_ripwire_fuzzer(gdscript   tree_sitter_gdscript   gdscript)
  add_custom_target(ripwire_fuzzers DEPENDS ${RIPWIRE_FUZZ_TARGETS})

  # ---- reader fuzzers: ripwire's OWN parsers of bytes it did not create (test/fuzz/readers/) ----
  # The grammar targets above fuzz the vendored parsers; these fuzz the code a hostile cache blob, sidecar, SCIP
  # index, MCP frame or repository document actually reaches. Each reader family compiles ONCE into the static
  # library (readers_ingest.cpp IS the ingest translation unit, instrumented); each ripwire_fuzz_reader_<name> is one
  # tiny entry TU that names its reader, so the linker pulls only the family it calls. Crash oracles only — the
  # correctness oracles are help-wanted issue #149's.
  set(RIPWIRE_FUZZ_READER_SOURCES
    test/fuzz/readers/readers_light.cpp
    test/fuzz/readers/readers_domain.cpp
    test/fuzz/readers/readers_mcphttp.cpp
    test/fuzz/readers/readers_ingest.cpp
    src/pagerank.cpp
    src/infra/diagnostics.cpp)
  set(RIPWIRE_FUZZ_READER_INCLUDES
    ${tree_sitter_SOURCE_DIR}/lib/include ${_ripwire_generated_dir} src/infra third_party src test/fuzz/readers)
  add_library(ripwire_fuzz_readers STATIC EXCLUDE_FROM_ALL ${RIPWIRE_FUZZ_READER_SOURCES})
  target_include_directories(ripwire_fuzz_readers PRIVATE ${RIPWIRE_FUZZ_READER_INCLUDES})
  target_compile_definitions(ripwire_fuzz_readers PRIVATE PROFILE_ENABLED=0)
  target_compile_options(ripwire_fuzz_readers PRIVATE ${RIPWIRE_FUZZ_COMPILE_OPTIONS})
  if(RIPWIRE_HAS_CLANG_INTEGER_SANITIZER)
    target_compile_options(ripwire_fuzz_readers PRIVATE "-fsanitize-ignorelist=${_ripwire_libstdcxx_ignorelist}")
  endif()
  add_dependencies(ripwire_fuzz_readers ripwire_version_stamp)
  add_library(ripwire_fuzz_reader_grammars STATIC EXCLUDE_FROM_ALL ${RIPWIRE_TS_OBJECTS})
  set_target_properties(ripwire_fuzz_reader_grammars PROPERTIES LINKER_LANGUAGE C)

  set(RIPWIRE_FUZZ_READER_TARGETS)
  function(add_ripwire_reader_fuzzer NAME)
    set(_ripwire_reader_target "ripwire_fuzz_reader_${NAME}")
    add_executable(${_ripwire_reader_target} EXCLUDE_FROM_ALL test/fuzz/readers/fuzz_reader.cpp)
    target_compile_definitions(${_ripwire_reader_target} PRIVATE RIPWIRE_FUZZ_READER=${NAME})
    target_compile_options(${_ripwire_reader_target} PRIVATE ${RIPWIRE_FUZZ_COMPILE_OPTIONS})
    target_link_options(${_ripwire_reader_target} PRIVATE ${RIPWIRE_FUZZ_LINK_OPTIONS})
    target_link_libraries(${_ripwire_reader_target} PRIVATE
      ripwire_fuzz_readers ripwire_fuzz_reader_grammars ripwire_tree_sitter_fuzz Threads::Threads)
    set(RIPWIRE_FUZZ_READER_TARGETS ${RIPWIRE_FUZZ_READER_TARGETS} ${_ripwire_reader_target} PARENT_SCOPE)
  endfunction()

  # The reader list is declared ONCE, here; test/fuzz/readers/run.sh and test/g1configcheck.sh derive theirs from it.
  set(RIPWIRE_FUZZ_READERS
    mcpjson mcphttp docparse tracein skillscan scip resolvecfg lintrules
    qsnap qchurn oracle sidecars qscope ingestrecord ingestframe stiermemo)
  foreach(_ripwire_reader IN LISTS RIPWIRE_FUZZ_READERS)
    add_ripwire_reader_fuzzer(${_ripwire_reader})
  endforeach()
  add_custom_target(ripwire_reader_fuzzers DEPENDS ${RIPWIRE_FUZZ_READER_TARGETS})
endif()
