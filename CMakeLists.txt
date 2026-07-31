cmake_minimum_required(VERSION 3.24)
# The version string lives in exactly ONE place — this project() call. --version (main.cpp)
# reads it via the generated version.h below; test/versioncheck.sh asserts the two never drift.
project(ctxpack VERSION 0.1.0 LANGUAGES C CXX)

# ---- language standards (SPEC §7: C++23 / C11) ----
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# ---- verification build modes (SPEC §6/§8) ----
# Each sanitizer family owns a separate build tree; combining runtimes is unsupported and obscures failures.
option(CTXPACK_ASAN "build with the complete fail-fast G1 sanitizer stack" OFF)
option(CTXPACK_TSAN "build separately with ThreadSanitizer" OFF)
option(CTXPACK_FUZZ "build the opt-in per-grammar libFuzzer suite" OFF)
set(_ctxpack_verification_mode_count 0)
foreach(_ctxpack_mode CTXPACK_ASAN CTXPACK_TSAN CTXPACK_FUZZ)
  if(${_ctxpack_mode})
    math(EXPR _ctxpack_verification_mode_count "${_ctxpack_verification_mode_count} + 1")
  endif()
endforeach()
if(_ctxpack_verification_mode_count GREATER 1)
  message(FATAL_ERROR "CTXPACK_ASAN, CTXPACK_TSAN, and CTXPACK_FUZZ are mutually exclusive; use separate build trees")
endif()

# A flag probe is insufficient: Apple Clang accepts -fsanitize=fuzzer but some Xcode distributions omit
# libclang_rt.fuzzer_osx.a. Compile AND link a complete harness before creating fuzz targets, and never
# download a replacement toolchain from the build.
if(CTXPACK_FUZZ)
  if(NOT CMAKE_C_COMPILER_ID MATCHES "Clang" OR NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    message(FATAL_ERROR "CTXPACK_FUZZ requires Clang for both C and CXX")
  endif()
  include(CheckCXXSourceCompiles)
  set(_ctxpack_required_flags_save "${CMAKE_REQUIRED_FLAGS}")
  set(_ctxpack_required_link_options_save "${CMAKE_REQUIRED_LINK_OPTIONS}")
  set(CMAKE_REQUIRED_FLAGS "-fsanitize=fuzzer-no-link,address")
  set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=fuzzer,address")
  check_cxx_source_compiles(
    "#include <cstddef>\n#include <cstdint>\nextern \"C\" int LLVMFuzzerTestOneInput( const std::uint8_t*, std::size_t ) { return 0; }"
    CTXPACK_HAS_LIBFUZZER_RUNTIME)
  set(CMAKE_REQUIRED_FLAGS "${_ctxpack_required_flags_save}")
  set(CMAKE_REQUIRED_LINK_OPTIONS "${_ctxpack_required_link_options_save}")
  if(NOT CTXPACK_HAS_LIBFUZZER_RUNTIME)
    message(FATAL_ERROR
      "CTXPACK_FUZZ requires a Clang toolchain containing the libFuzzer runtime. "
      "Configure both CMAKE_C_COMPILER and CMAKE_CXX_COMPILER from the same upstream LLVM installation; "
      "the build will not install a compiler automatically.")
  endif()
endif()

# ---- optimization profile (portable by default) ----
# default: arch-neutral on anything that isn't Apple Silicon; auto-detected apple-m1 tuning (safe generic
# tuning, not a native-host bake-in) on real Apple Silicon. -DCTXPACK_NATIVE=ON: dev-machine-only opt-in
# (-march=native bakes in host CPU extensions — never for a binary that ships or runs elsewhere).
# See cmake/PortableFlags.cmake for the full rationale and the CTXPACK_PRETEND_LINUX test-only hook.
include(cmake/PortableFlags.cmake)
add_compile_options(${CTXPACK_ARCH_FLAGS})

# ---- FetchContent: SHARED sources, PER-BUILD-TREE build output ----
# "no network" is a RUNTIME rule only; configure-time fetches are fine and cached.
#
# Split by relocatability, because these two things have opposite sharing rules:
#   * SOURCES (the git clones) are relocatable and compiler-flag-independent -> SHARE them across the
#     fleet (~20 sessions) in ~/.cache so tree-sitter + 11 grammars clone exactly once. Each dep adopts
#     the shared clone via FETCHCONTENT_SOURCE_DIR_<NAME> (ctxpack_use_shared_source, below).
#   * BUILD + SUBBUILD dirs are NOT relocatable: their generated Makefiles bake in the consuming build
#     tree's absolute CMAKE_BINARY_DIR and run `cd $CMAKE_BINARY_DIR && cmake --check-build-system` on
#     every `cmake --build`. Sharing tree_sitter-build meant the LAST tree to configure won; when that
#     was a scratch/worktree/oldbuild dir that later got deleted, every other tree inherited a `cd` into
#     a now-missing path -> `tree_sitter-build/.../depend Error 1`. Keep them LOCAL (FETCHCONTENT_BASE_DIR
#     -> this tree's ${CMAKE_BINARY_DIR}/_deps), so a build tree is fully self-contained and disposable
#     with its own `build/`, and removing any OTHER build tree can never corrupt this one.
# Bonus: this also gives sanitizer builds their isolation for free (asan/_deps vs build/_deps hold
# separately-compiled libtree-sitter.a), so no more sanitizer-suffixed cache key is needed.
set(_ctxpack_src_cache "$ENV{HOME}/.cache/ctxpack-deps" CACHE PATH "shared, relocatable dep SOURCE cache")
set(FETCHCONTENT_BASE_DIR "${CMAKE_BINARY_DIR}/_deps")   # local build/subbuild (NOT the shared cache)
set(FETCHCONTENT_UPDATES_DISCONNECTED ON)
include(FetchContent)

# Reuse the fleet's shared clone WITHOUT letting FetchContent own it. Passing FETCHCONTENT_SOURCE_DIR_<NAME>
# makes FetchContent treat that dir as already-provisioned: no download, no subbuild git step, and crucially
# it never touches the dir (unlike a plain SOURCE_DIR override, whose clone stamp lives in the local subbuild
# so ExternalProject would rm -rf + re-clone the shared source on every fresh build tree, racing the fleet).
#
# The SENTINEL is the exact file this dep's targets will compile (parser.c for a grammar, lib/src/lib.c for
# the core). Adopting the shared clone only when its sentinel exists makes a partial/corrupt shared source
# (e.g. an interrupted checkout, or Swift's parser.c which lives only on the with-generated-files branch)
# SELF-HEAL: we simply don't adopt it, and FetchContent clones a fresh, correctly-checked-out copy into this
# tree's local ${CMAKE_BINARY_DIR}/_deps/<name>-src. Same fallback covers a cold / air-gapped machine. Either
# way the build output stays local, so the tree is self-contained and disposable with its own build/ dir.
macro(ctxpack_use_shared_source NAME SENTINEL)
  string(TOUPPER "${NAME}" _ctxpack_up)
  if(EXISTS "${_ctxpack_src_cache}/${NAME}-src/${SENTINEL}")
    set(FETCHCONTENT_SOURCE_DIR_${_ctxpack_up} "${_ctxpack_src_cache}/${NAME}-src")
  else()
    unset(FETCHCONTENT_SOURCE_DIR_${_ctxpack_up})
  endif()
endmacro()

# Adopt a shared source clone for an arbitrary commit only when its checked-out HEAD is the declared
# immutable revision. FETCHCONTENT_SOURCE_DIR bypasses FetchContent's checkout machinery entirely, so
# the sentinel-only helper above is insufficient for commit pins: a shared branch checkout could otherwise
# silently override GIT_TAG. A mismatch falls back to the build-local FetchContent clone.
macro(ctxpack_use_shared_source_commit NAME SENTINEL COMMIT)
  string(TOUPPER "${NAME}" _ctxpack_up)
  set(_ctxpack_shared_source "${_ctxpack_src_cache}/${NAME}-src")
  set(_ctxpack_shared_head "")
  set(_ctxpack_git_result 1)
  if(EXISTS "${_ctxpack_shared_source}/${SENTINEL}")
    execute_process(
      COMMAND git -C "${_ctxpack_shared_source}" rev-parse HEAD
      RESULT_VARIABLE _ctxpack_git_result
      OUTPUT_VARIABLE _ctxpack_shared_head
      OUTPUT_STRIP_TRAILING_WHITESPACE
      ERROR_QUIET)
  endif()
  if(_ctxpack_git_result EQUAL 0 AND _ctxpack_shared_head STREQUAL "${COMMIT}")
    set(FETCHCONTENT_SOURCE_DIR_${_ctxpack_up} "${_ctxpack_shared_source}")
  else()
    unset(FETCHCONTENT_SOURCE_DIR_${_ctxpack_up})
  endif()
endmacro()

# ---- configure-time query embedding (SPEC §1: one self-contained binary) ----
# queries/<language>/tags.scm remains the editable source of truth. CMake regenerates this constexpr
# table whenever any query changes; ingest reads only the binary's read-only data at runtime.
set(_ctxpack_query_names
  bash
  c
  cpp
  csharp
  go
  java
  javascript
  json
  objc
  python
  ruby
  rust
  swift
  typescript)
set(_ctxpack_generated_dir "${CMAKE_CURRENT_BINARY_DIR}/generated")
set(_ctxpack_embedded_queries "${_ctxpack_generated_dir}/embedded_queries.h")
file(MAKE_DIRECTORY "${_ctxpack_generated_dir}")
list(LENGTH _ctxpack_query_names _ctxpack_query_count)
file(WRITE "${_ctxpack_embedded_queries}" "#pragma once\n\n#include <array>\n#include <cstddef>\n#include <string_view>\n\nnamespace ctx::embedded_queries\n{\n\nstruct EmbeddedQuery\n{\n    std::string_view sub;\n    std::string_view source;\n};\n\ninline constexpr std::size_t kEmbeddedQueryCount = ${_ctxpack_query_count};\ninline constexpr std::array<EmbeddedQuery, kEmbeddedQueryCount> kEmbeddedQueries = {{\n")
foreach(_ctxpack_query_name IN LISTS _ctxpack_query_names)
  set(_ctxpack_query_path "${CMAKE_CURRENT_SOURCE_DIR}/queries/${_ctxpack_query_name}/tags.scm")
  file(READ "${_ctxpack_query_path}" _ctxpack_query_source)
  string(TOUPPER "${_ctxpack_query_name}" _ctxpack_query_upper)
  set(_ctxpack_query_delimiter "CTXQ_${_ctxpack_query_upper}")
  string(FIND "${_ctxpack_query_source}" ")${_ctxpack_query_delimiter}\"" _ctxpack_query_collision)
  if(NOT _ctxpack_query_collision EQUAL -1)
    message(FATAL_ERROR "tags query ${_ctxpack_query_name} collides with its generated raw-string delimiter")
  endif()
  file(APPEND "${_ctxpack_embedded_queries}"
    "    { \"${_ctxpack_query_name}\", R\"${_ctxpack_query_delimiter}(${_ctxpack_query_source})${_ctxpack_query_delimiter}\" },\n")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_ctxpack_query_path}")
endforeach()
file(APPEND "${_ctxpack_embedded_queries}" "}};\n\ninline constexpr std::string_view queryFor( std::string_view sub ) noexcept\n{\n    for( const EmbeddedQuery& query : kEmbeddedQueries )\n    {\n        if( query.sub == sub )\n            return query.source;\n    }\n    return {};\n}\n\n} // namespace ctx::embedded_queries\n")

# ---- generated version.h ----
# The version string lives in ONE place: the project(ctxpack VERSION ...) call above. --version reads
# this generated header; test/versioncheck.sh diffs its output against CMakeLists.txt's own VERSION so
# the two can never silently drift. Short build info (compiler id/version, build type) rides along so a
# bug report's "ctxpack --version" line is enough to reproduce the toolchain, no separate --doctor call.
# CMAKE_BUILD_TYPE is empty for the plain dev configure the house style mandates (CLAUDE.md: "never
# -DCMAKE_BUILD_TYPE=Release" locally — Release defines NDEBUG, which compiles DEGRADED_PATH_ALERT out).
# "unspecified" told a bug reporter nothing about what they actually ran; "dev" is the honest, specific
# label for that configure (§P6.10, 2026-07-28 output audit) — it is the first thing a bug report pastes.
if(NOT CMAKE_BUILD_TYPE)
  set(_ctxpack_build_type_str "dev")
else()
  set(_ctxpack_build_type_str "${CMAKE_BUILD_TYPE}")
endif()
set(_ctxpack_version_header "${_ctxpack_generated_dir}/version.h")
file(WRITE "${_ctxpack_version_header}"
"#pragma once\n\n// Generated by CMakeLists.txt from project(ctxpack VERSION ...) — do not edit by hand.\nnamespace ctx\n{\ninline constexpr const char* kCtxpackVersion     = \"${PROJECT_VERSION}\";\ninline constexpr const char* kCtxpackBuildType   = \"${_ctxpack_build_type_str}\";\ninline constexpr const char* kCtxpackCompilerId  = \"${CMAKE_CXX_COMPILER_ID}\";\ninline constexpr const char* kCtxpackCompilerVer = \"${CMAKE_CXX_COMPILER_VERSION}\";\n} // namespace ctx\n")

# ---- tree-sitter CORE (static) ----
# MUST precede MakeAvailable: tree-sitter defaults BUILD_SHARED_LIBS ON -> you'd get a dylib.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
# Dependency independence (SHA-pin): GIT_TAG is the commit the tag pointed to when resolved via
# `git ls-remote --tags <repo> "refs/tags/<tag>^{}"` (2026-07-22) — an immutable, un-force-pushable ref.
# The tag stays as a trailing comment so `git log`/README readers still see the human-legible version.
ctxpack_use_shared_source(tree_sitter lib/src/lib.c)
FetchContent_Declare(tree_sitter
  GIT_REPOSITORY https://github.com/tree-sitter/tree-sitter.git
  GIT_TAG 7f534862c3ec939c3a6ee147f7600ef5c1bf900f  # v0.26.9
  GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(tree_sitter)

# ---- grammar OBJECT-lib pattern (SPEC §7) ----
# Do NOT add_subdirectory the grammar repos: their CMakeLists find_program(tree-sitter),
# add a regenerate-parser.c custom command, and a SOVERSION/ABI trap. SOURCE_SUBDIR _none_
# makes FetchContent skip the grammar's own CMakeLists; we compile only parser.c (+scanner.c).
macro(add_ts_grammar NAME REPO TAG)
  ctxpack_use_shared_source(${NAME} src/parser.c)
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
  set(CTXPACK_TS_${NAME}_SOURCES ${_srcs})
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
  set(CTXPACK_TS_${NAME}_SOURCES ${_srcs} PARENT_SCOPE)
endfunction()

# ---- pinned grammars (SHA-pinned: each GIT_TAG below is the commit its comment's tag
# resolved to via `git ls-remote --tags <repo> "refs/tags/<tag>^{}"` on 2026-07-22 — mutable tags can
# be force-moved server-side, a SHA cannot; ABI verified at runtime) ----
add_ts_grammar(cpp    https://github.com/tree-sitter/tree-sitter-cpp.git        f41e1a044c8a84ea9fa8577fdd2eab92ec96de02)  # v0.23.4
add_ts_grammar(python https://github.com/tree-sitter/tree-sitter-python.git     bffb65a8cfe4e46290331dfef0dbf0ef3679de11)  # v0.23.6
add_ts_grammar(go     https://github.com/tree-sitter/tree-sitter-go.git         3c3775faa968158a8b4ac190a7fda867fd5fb748)  # v0.23.4
add_ts_grammar(rust   https://github.com/tree-sitter/tree-sitter-rust.git       cad8a206f2e4194676b9699f26f6560d07130d3f)  # v0.23.2
# Swift: main has no generated parser.c. Pin the audited generated-files commit exactly; an arbitrary
# SHA requires a full fetch (SPEC §7), and shared-source adoption must validate HEAD before bypassing it.
set(_ctxpack_swift_commit 31d17fe7e818a2048c808b5c6fdc2dc792f4f5b5)
ctxpack_use_shared_source_commit(swift src/parser.c ${_ctxpack_swift_commit})
FetchContent_Declare(swift
  GIT_REPOSITORY https://github.com/alex-pinkus/tree-sitter-swift.git
  GIT_TAG ${_ctxpack_swift_commit}
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

# TypeScript: ONE repo cloned once (SOURCE_SUBDIR _none_ skips its CMakeLists), then TWO
# OBJECT libs (ts_tsts from typescript/src, ts_tstsx from tsx/src). Both share common/scanner.c
# which each parser dir's own scanner.c #includes, so per-dir (parser.c + scanner.c) is correct.
ctxpack_use_shared_source(ts_typescript typescript/src/parser.c)
FetchContent_Declare(ts_typescript
  GIT_REPOSITORY https://github.com/tree-sitter/tree-sitter-typescript.git
  GIT_TAG f975a621f4e7f532fe322e13c4f79495e0a7b2e7  # v0.23.2
  GIT_SHALLOW TRUE
  SOURCE_SUBDIR _none_)
FetchContent_MakeAvailable(ts_typescript)
add_ts_object(tsts  ${ts_typescript_SOURCE_DIR}/typescript/src)
add_ts_object(tstsx ${ts_typescript_SOURCE_DIR}/tsx/src)

# ---- explicit, easy-to-extend executable source list ----
# Later stages (graph/rank/serialize/main) get appended here. ingest.cpp + the vendored
# fastmath.cpp (VERIFY/DEGRADED handlers link partner, SPEC §9) are the foundation.
set(CTXPACK_SRCS
  src/ingest.cpp
  src/pagerank.cpp
  src/infra/fastmath.cpp
)

# The global profile uses -ffast-math, but PageRank reductions must not reassociate (SPEC §3/§7).
set_source_files_properties(src/pagerank.cpp PROPERTIES COMPILE_OPTIONS "-fno-fast-math")

# All grammar OBJECT files, gathered once so every target links the same set.
set(CTXPACK_TS_OBJECTS
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
  $<TARGET_OBJECTS:ts_csharp>
  $<TARGET_OBJECTS:ts_c>
)

# ---- probe target: the Phase-1/2 proof binary ----
add_executable(ctxpack_probe
  src/tsprobe.cpp
  ${CTXPACK_SRCS}
  ${CTXPACK_TS_OBJECTS})
target_link_libraries(ctxpack_probe PRIVATE tree-sitter)
target_include_directories(ctxpack_probe PRIVATE
  ${tree_sitter_SOURCE_DIR}/lib/include
  ${_ctxpack_generated_dir}
  src/infra
  third_party
  src)

# ---- the real ctxpack binary: full pipeline (ingest → graph → PageRank → minified XML) ----
# main.cpp forward-declares ctx::ingest(); linking ingest.cpp supplies the real tree-sitter one.
add_executable(ctxpack
  src/main.cpp
  ${CTXPACK_SRCS}
  ${CTXPACK_TS_OBJECTS})
target_link_libraries(ctxpack PRIVATE tree-sitter)
target_include_directories(ctxpack PRIVATE
  ${tree_sitter_SOURCE_DIR}/lib/include
  ${_ctxpack_generated_dir}
  src/infra
  third_party
  src)

# ---- global install: `cmake --install build --prefix /opt/homebrew --component ctxpack` (see install.sh) ----
# COMPONENT ctxpack + --component on install scopes this to just the binary: without it, `cmake --install`
# also runs the vendored tree-sitter subproject's own install() rules (headers/pkgconfig/static lib into
# the same --prefix) even though ctxpack links it in statically and needs none of that at runtime.
install(TARGETS ctxpack RUNTIME DESTINATION bin COMPONENT ctxpack)

# ---- direct structural/numeric gates (SPEC §8) ----
option(CTXPACK_TESTS "build direct CSR and PageRank verification gates" OFF)
if(CTXPACK_TESTS)
  enable_testing()

  # SPEC §8: unit/property gates use a SHA-locked Doctest checkout. This is the exact v2.4.12
  # release commit; arbitrary commits require a full fetch, and shared adoption validates HEAD.
  set(_ctxpack_doctest_commit 1da23a3e8119ec5cce4f9388e91b065e20bf06f5)
  ctxpack_use_shared_source_commit(doctest doctest/doctest.h ${_ctxpack_doctest_commit})
  FetchContent_Declare(doctest
    GIT_REPOSITORY https://github.com/doctest/doctest.git
    GIT_TAG ${_ctxpack_doctest_commit}
    GIT_SHALLOW FALSE)
  FetchContent_MakeAvailable(doctest)

  add_executable(ctxpack_test_csr
    test/verify_csr.cpp
    src/infra/fastmath.cpp)
  target_include_directories(ctxpack_test_csr PRIVATE src/infra third_party src)
  target_link_libraries(ctxpack_test_csr PRIVATE doctest::doctest)
  add_test(NAME ctxpack.csr COMMAND ctxpack_test_csr)

  add_executable(ctxpack_test_pagerank
    test/verify_pagerank.cpp
    src/pagerank.cpp
    src/infra/fastmath.cpp)
  target_include_directories(ctxpack_test_pagerank PRIVATE src/infra third_party src)
  target_link_libraries(ctxpack_test_pagerank PRIVATE doctest::doctest)
  add_test(NAME ctxpack.pagerank COMMAND ctxpack_test_pagerank)

  add_executable(ctxpack_test_radix
    test/verify_radix.cpp
    src/infra/fastmath.cpp)
  target_include_directories(ctxpack_test_radix PRIVATE src/infra third_party src)
  add_test(NAME ctxpack.radix COMMAND ctxpack_test_radix)
endif()

# ---- self-profiling build (src/infra/profileScope.h): -DCTXPACK_PROFILE=ON ----
# OFF by default → every PROFILE_SCOPE compiles to ((void)0): byte-identical, zero-cost normal binary.
# ON → per-phase CNTVCT timing (+ Apple PMC cycles/instructions/cache-misses when run under sudo).
# Build in a SEPARATE dir so build/ctxpack (the bench binary) stays untouched:
#   cmake -S . -B build_prof -DCTXPACK_NATIVE=ON -DCTXPACK_PROFILE=ON && cmake --build build_prof -j
option(CTXPACK_PROFILE "instrument the pipeline with PROFILE_SCOPE self-profiling" OFF)
foreach(_pt ctxpack ctxpack_probe)
  target_compile_definitions(${_pt} PRIVATE PROFILE_ENABLED=$<BOOL:${CTXPACK_PROFILE}>)
endforeach()

# ---- G1 sanitizer build (SPEC §6/§8): owned code + tree-sitter core + every grammar ----
set(CTXPACK_GRAMMAR_TARGETS
  ts_cpp ts_python ts_go ts_rust ts_tsts ts_tstsx ts_swift ts_objc
  ts_javascript ts_bash ts_java ts_ruby ts_json ts_csharp ts_c)
set(CTXPACK_RUNTIME_COMPILE_TARGETS ctxpack_probe ctxpack tree-sitter ${CTXPACK_GRAMMAR_TARGETS})
set(CTXPACK_RUNTIME_LINK_TARGETS ctxpack_probe ctxpack)
if(CTXPACK_TESTS)
  list(APPEND CTXPACK_RUNTIME_COMPILE_TARGETS ctxpack_test_csr ctxpack_test_pagerank ctxpack_test_radix)
  list(APPEND CTXPACK_RUNTIME_LINK_TARGETS ctxpack_test_csr ctxpack_test_pagerank ctxpack_test_radix)
endif()
set(CTXPACK_G1_SANITIZERS "-fsanitize=address,undefined,integer,float-divide-by-zero,float-cast-overflow")
set(_ctxpack_tree_sitter_ignorelist "${_ctxpack_generated_dir}/tree_sitter_sanitizer_ignorelist.txt")
set(_ctxpack_swift_ignorelist "${_ctxpack_generated_dir}/swift_sanitizer_ignorelist.txt")
set(_ctxpack_bash_ignorelist "${_ctxpack_generated_dir}/bash_sanitizer_ignorelist.txt")
# Full G1 remains enabled on ctxpack and every grammar. Pinned tree-sitter v0.26.9 intentionally uses
# defined C unsigned wrap throughout reverse loops and erase-at-zero iteration, so only that non-UB check
# is disabled target-wide for the pinned core. All other integer/undefined/conversion checks remain on.
# Pinned core uses defined unsigned wrap plus signed narrowing in its UINT16_MAX sentinel and inlined ICU
# UTF-8 macros, so those two checks are disabled only for the core target. Subtree progress quantization and
# generated external-scanner C function pointers remain exact-function exceptions. The lookahead sentinel
# remains on upstream master as of 2026-07-12.
file(WRITE "${_ctxpack_tree_sitter_ignorelist}"
  "[implicit-unsigned-integer-truncation]\nfun:ts_parser__balance_subtree\n"
  "[function]\nfun:ts_parser__external_scanner_create\n")
# Swift's scanner stores lexer->lookahead (-1 at EOF) in uint32 inside this exact whitespace helper.
file(WRITE "${_ctxpack_swift_ignorelist}"
  "[implicit-integer-sign-change]\nfun:eat_whitespace\n")
# Bash's scanner decrements zero-valued nesting depths after marking the scan complete; uint32 wrap is intentional.
file(WRITE "${_ctxpack_bash_ignorelist}"
  "[unsigned-integer-overflow]\nfun:scan\n")

if(CTXPACK_ASAN)
  foreach(_t IN LISTS CTXPACK_RUNTIME_COMPILE_TARGETS)
    target_compile_options(${_t} PRIVATE ${CTXPACK_G1_SANITIZERS}
      -fno-sanitize-recover=all -fno-omit-frame-pointer -O2 -g)
  endforeach()
  foreach(_t IN LISTS CTXPACK_RUNTIME_LINK_TARGETS)
    target_link_options(${_t} PRIVATE ${CTXPACK_G1_SANITIZERS})
  endforeach()
  target_compile_options(tree-sitter PRIVATE
    -fno-sanitize=unsigned-integer-overflow
    -fno-sanitize=implicit-signed-integer-truncation
    -fno-sanitize=implicit-integer-sign-change
    "-fsanitize-ignorelist=${_ctxpack_tree_sitter_ignorelist}")
  target_compile_options(ts_swift PRIVATE "-fsanitize-ignorelist=${_ctxpack_swift_ignorelist}")
  target_compile_options(ts_bash PRIVATE "-fsanitize-ignorelist=${_ctxpack_bash_ignorelist}")

  # Xcode's arm64 Darwin runtime rejects both the standalone leak sanitizer and detect_leaks=1 at startup.
  # Keep the local ASan/UBSan gate executable and explicit; LeakSanitizer remains a Linux/upstream-runtime
  # CI gate using the committed tree-sitter suppressions rather than being falsely claimed on Apple Clang.
  if(APPLE)
    set(_ctxpack_asan_options "detect_leaks=0:halt_on_error=1:abort_on_error=1")
  else()
    set(_ctxpack_asan_options "detect_leaks=1:halt_on_error=1:abort_on_error=1")
  endif()
  add_custom_target(ctxpack_asan_fixture
    COMMAND ${CMAKE_COMMAND} -E env
      "ASAN_OPTIONS=${_ctxpack_asan_options}"
      "UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1"
      "LSAN_OPTIONS=suppressions=${CMAKE_CURRENT_SOURCE_DIR}/lsan_suppressions.txt"
      $<TARGET_FILE:ctxpack> ${CMAKE_CURRENT_SOURCE_DIR}/test/fixture --no-cache
    DEPENDS ctxpack
    COMMENT "Run the G1 fixture with the platform leak-detection policy")
endif()

# ---- G-race ThreadSanitizer build (SPEC §6/§8; Phase-M qsnap-prefetch worker vs the request loop) ----
# A SEPARATE target/dir from ASan (TSan and ASan are mutually exclusive). Vets the one concurrent path in the
# server: the detached HEAD-snapshot prefetch thread against a request-thread ingest, serialized by
# quality::headSnapshotIngestMutex + the single-flight atomic. Build + run the (b) non-vacuity scenario:
#   cmake -S . -B tsan -DCTXPACK_TSAN=ON && cmake --build tsan -j
if(CTXPACK_TSAN)
  foreach(_t IN LISTS CTXPACK_RUNTIME_COMPILE_TARGETS)
    target_compile_options(${_t} PRIVATE -fsanitize=thread -fno-omit-frame-pointer -O2 -g)
  endforeach()
  foreach(_t IN LISTS CTXPACK_RUNTIME_LINK_TARGETS)
    target_link_options(${_t} PRIVATE -fsanitize=thread)
  endforeach()
endif()

# ---- opt-in ingestion fuzzing (SPEC §8): isolated coverage-instrumented parser objects ----
# Keep these copies separate from production objects: fuzzer-no-link coverage callbacks must never leak
# into a normal executable. CTXPACK_FUZZ is OFF by default and every target is EXCLUDE_FROM_ALL.
if(CTXPACK_FUZZ)
  set(CTXPACK_FUZZ_COMPILE_OPTIONS
    -fsanitize=fuzzer-no-link,address,undefined,integer,float-divide-by-zero,float-cast-overflow
    -fno-sanitize-recover=all -fno-omit-frame-pointer -O2 -g)
  set(CTXPACK_FUZZ_LINK_OPTIONS
    -fsanitize=fuzzer,address,undefined,integer,float-divide-by-zero,float-cast-overflow)

  add_library(ctxpack_tree_sitter_fuzz STATIC EXCLUDE_FROM_ALL ${tree_sitter_SOURCE_DIR}/lib/src/lib.c)
  target_include_directories(ctxpack_tree_sitter_fuzz PRIVATE
    ${tree_sitter_SOURCE_DIR}/lib/src ${tree_sitter_SOURCE_DIR}/lib/src/wasm
    PUBLIC ${tree_sitter_SOURCE_DIR}/lib/include)
  target_compile_definitions(ctxpack_tree_sitter_fuzz PRIVATE
    _POSIX_C_SOURCE=200112L _DEFAULT_SOURCE _BSD_SOURCE _DARWIN_C_SOURCE)
  target_compile_options(ctxpack_tree_sitter_fuzz PRIVATE ${CTXPACK_FUZZ_COMPILE_OPTIONS}
    -fno-sanitize=unsigned-integer-overflow
    -fno-sanitize=implicit-signed-integer-truncation
    -fno-sanitize=implicit-integer-sign-change
    "-fsanitize-ignorelist=${_ctxpack_tree_sitter_ignorelist}")
  set_target_properties(ctxpack_tree_sitter_fuzz PROPERTIES C_STANDARD 11 POSITION_INDEPENDENT_CODE ON)

  set(CTXPACK_FUZZ_TARGETS)
  function(add_ctxpack_fuzzer NAME LANGUAGE GRAMMAR_SOURCE_KEY)
    set(_ctxpack_grammar_source_var "CTXPACK_TS_${GRAMMAR_SOURCE_KEY}_SOURCES")
    set(_ctxpack_fuzz_grammar_target "ctxpack_fuzz_grammar_${NAME}")
    add_library(${_ctxpack_fuzz_grammar_target} OBJECT EXCLUDE_FROM_ALL ${${_ctxpack_grammar_source_var}})
    list(GET ${_ctxpack_grammar_source_var} 0 _ctxpack_fuzz_parser_source)
    get_filename_component(_ctxpack_fuzz_grammar_dir "${_ctxpack_fuzz_parser_source}" DIRECTORY)
    target_include_directories(${_ctxpack_fuzz_grammar_target} PRIVATE
      ${tree_sitter_SOURCE_DIR}/lib/include ${_ctxpack_fuzz_grammar_dir})
    target_compile_options(${_ctxpack_fuzz_grammar_target} PRIVATE ${CTXPACK_FUZZ_COMPILE_OPTIONS})
    if(NAME STREQUAL "swift")
      target_compile_options(${_ctxpack_fuzz_grammar_target} PRIVATE "-fsanitize-ignorelist=${_ctxpack_swift_ignorelist}")
    elseif(NAME STREQUAL "bash")
      target_compile_options(${_ctxpack_fuzz_grammar_target} PRIVATE "-fsanitize-ignorelist=${_ctxpack_bash_ignorelist}")
    endif()
    set_target_properties(${_ctxpack_fuzz_grammar_target} PROPERTIES C_STANDARD 11 POSITION_INDEPENDENT_CODE ON)

    set(_ctxpack_fuzz_target "ctxpack_fuzz_${NAME}")
    add_executable(${_ctxpack_fuzz_target} EXCLUDE_FROM_ALL
      test/fuzz/fuzz_ingest.cpp $<TARGET_OBJECTS:${_ctxpack_fuzz_grammar_target}>)
    target_compile_definitions(${_ctxpack_fuzz_target} PRIVATE CTXPACK_FUZZ_LANGUAGE=${LANGUAGE})
    target_compile_options(${_ctxpack_fuzz_target} PRIVATE ${CTXPACK_FUZZ_COMPILE_OPTIONS})
    target_link_options(${_ctxpack_fuzz_target} PRIVATE ${CTXPACK_FUZZ_LINK_OPTIONS})
    target_link_libraries(${_ctxpack_fuzz_target} PRIVATE ctxpack_tree_sitter_fuzz)
    target_include_directories(${_ctxpack_fuzz_target} PRIVATE ${tree_sitter_SOURCE_DIR}/lib/include)
    set(CTXPACK_FUZZ_TARGETS ${CTXPACK_FUZZ_TARGETS} ${_ctxpack_fuzz_target} PARENT_SCOPE)
  endfunction()

  add_ctxpack_fuzzer(cpp        tree_sitter_cpp        cpp)
  add_ctxpack_fuzzer(python     tree_sitter_python     python)
  add_ctxpack_fuzzer(go         tree_sitter_go         go)
  add_ctxpack_fuzzer(rust       tree_sitter_rust       rust)
  add_ctxpack_fuzzer(typescript tree_sitter_typescript tsts)
  add_ctxpack_fuzzer(tsx        tree_sitter_tsx        tstsx)
  add_ctxpack_fuzzer(swift      tree_sitter_swift      swift)
  add_ctxpack_fuzzer(objc       tree_sitter_objc       objc)
  add_ctxpack_fuzzer(javascript tree_sitter_javascript javascript)
  add_ctxpack_fuzzer(bash       tree_sitter_bash       bash)
  add_ctxpack_fuzzer(java       tree_sitter_java       java)
  add_ctxpack_fuzzer(ruby       tree_sitter_ruby       ruby)
  add_ctxpack_fuzzer(json       tree_sitter_json       json)
  add_ctxpack_fuzzer(csharp     tree_sitter_c_sharp    csharp)
  add_ctxpack_fuzzer(c          tree_sitter_c          c)
  add_custom_target(ctxpack_fuzzers DEPENDS ${CTXPACK_FUZZ_TARGETS})
endif()
