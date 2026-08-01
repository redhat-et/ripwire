cmake_minimum_required(VERSION 3.24)
# The version string lives in exactly ONE place — this project() call. --version (main.cpp)
# reads it via the generated version.h below; test/versioncheck.sh asserts the two never drift.
project(ripwire VERSION 0.1.0 LANGUAGES C CXX)

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
# default: arch-neutral on anything that isn't Apple Silicon; auto-detected apple-m1 tuning (safe generic
# tuning, not a native-host bake-in) on real Apple Silicon. -DRIPWIRE_NATIVE=ON: dev-machine-only opt-in
# (-march=native bakes in host CPU extensions — never for a binary that ships or runs elsewhere).
# See cmake/PortableFlags.cmake for the full rationale and the RIPWIRE_PRETEND_LINUX test-only hook.
# DECLARED here, beside the other five options, rather than left to be conjured by a bare -D on the
# command line: an undeclared option is absent from `cmake -LH`, from ccmake, and from the IDE panes,
# so the only way to learn it exists is to read this comment — and `--flags` cannot report a CMake
# gate that no `option()` call ever names.
option(RIPWIRE_NATIVE "build with -march=native (DEV MACHINES ONLY — bakes in host CPU extensions)" OFF)
include(cmake/PortableFlags.cmake)
add_compile_options(${RIPWIRE_ARCH_FLAGS})

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
# -DCMAKE_BUILD_TYPE=Release" locally — Release defines NDEBUG, which compiles DEGRADED_PATH_ALERT out).
# "unspecified" told a bug reporter nothing about what they actually ran; "dev" is the honest, specific
# label for that configure (§P6.10, 2026-07-28 output audit) — it is the first thing a bug report pastes.
if(NOT CMAKE_BUILD_TYPE)
  set(_ripwire_build_type_str "dev")
else()
  set(_ripwire_build_type_str "${CMAKE_BUILD_TYPE}")
endif()
set(_ripwire_version_header "${_ripwire_generated_dir}/version.h")
file(WRITE "${_ripwire_version_header}"
"#pragma once\n\n// Generated by CMakeLists.txt from project(ripwire VERSION ...) — do not edit by hand.\nnamespace rw\n{\ninline constexpr const char* kRipwireVersion     = \"${PROJECT_VERSION}\";\ninline constexpr const char* kRipwireBuildType   = \"${_ripwire_build_type_str}\";\ninline constexpr const char* kRipwireCompilerId  = \"${CMAKE_CXX_COMPILER_ID}\";\ninline constexpr const char* kRipwireCompilerVer = \"${CMAKE_CXX_COMPILER_VERSION}\";\n} // namespace rw\n")

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
# diagnostics.cpp (VERIFY/DEGRADED handlers link partner) are the foundation.
set(RIPWIRE_SRCS
  src/ingest.cpp
  src/pagerank.cpp
  src/infra/diagnostics.cpp
)

# The global profile uses -ffast-math, but PageRank reductions must not reassociate (the determinism
# contract's no-reassociation rule — docs/ARCHITECTURE.md §3).
set_source_files_properties(src/pagerank.cpp PROPERTIES COMPILE_OPTIONS "-fno-fast-math")

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
  $<TARGET_OBJECTS:ts_csharp>
  $<TARGET_OBJECTS:ts_c>
)

# ---- probe target: the Phase-1/2 proof binary ----
add_executable(ripwire_probe
  src/tsprobe.cpp
  ${RIPWIRE_SRCS}
  ${RIPWIRE_TS_OBJECTS})
target_link_libraries(ripwire_probe PRIVATE tree-sitter)
target_include_directories(ripwire_probe PRIVATE
  ${tree_sitter_SOURCE_DIR}/lib/include
  ${_ripwire_generated_dir}
  src/infra
  third_party
  src)

# ---- the real ripwire binary: full pipeline (ingest → graph → PageRank → minified XML) ----
# main.cpp forward-declares rw::ingest(); linking ingest.cpp supplies the real tree-sitter one.
add_executable(ripwire
  src/main.cpp
  ${RIPWIRE_SRCS}
  ${RIPWIRE_TS_OBJECTS})
target_link_libraries(ripwire PRIVATE tree-sitter)
target_include_directories(ripwire PRIVATE
  ${tree_sitter_SOURCE_DIR}/lib/include
  ${_ripwire_generated_dir}
  src/infra
  third_party
  src)

# ---- global install: `cmake --install build --prefix /opt/homebrew --component ripwire` (see install.sh) ----
# COMPONENT ripwire + --component on install scopes this to just the binary: without it, `cmake --install`
# also runs the vendored tree-sitter subproject's own install() rules (headers/pkgconfig/static lib into
# the same --prefix) even though ripwire links it in statically and needs none of that at runtime.
install(TARGETS ripwire RUNTIME DESTINATION bin COMPONENT ripwire)

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

# ---- G1 sanitizer build (CONTRIBUTING.md §4): owned code + tree-sitter core + every grammar ----
set(RIPWIRE_GRAMMAR_TARGETS
  ts_cpp ts_python ts_go ts_rust ts_tsts ts_tstsx ts_swift ts_objc
  ts_javascript ts_bash ts_java ts_ruby ts_json ts_csharp ts_c)
set(RIPWIRE_RUNTIME_COMPILE_TARGETS ripwire_probe ripwire tree-sitter ${RIPWIRE_GRAMMAR_TARGETS})
set(RIPWIRE_RUNTIME_LINK_TARGETS ripwire_probe ripwire)
if(RIPWIRE_TESTS)
  list(APPEND RIPWIRE_RUNTIME_COMPILE_TARGETS ripwire_test_csr ripwire_test_pagerank ripwire_test_radix)
  list(APPEND RIPWIRE_RUNTIME_LINK_TARGETS ripwire_test_csr ripwire_test_pagerank ripwire_test_radix)
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
# Full G1 remains enabled on ripwire and every grammar. Pinned tree-sitter v0.26.9 intentionally uses
# defined C unsigned wrap throughout reverse loops and erase-at-zero iteration, so only that non-UB check
# is disabled target-wide for the pinned core. All other integer/undefined/conversion checks remain on.
# Pinned core uses defined unsigned wrap plus signed narrowing in its UINT16_MAX sentinel and inlined ICU
# UTF-8 macros, so those two checks are disabled only for the core target. Subtree progress quantization and
# generated external-scanner C function pointers remain exact-function exceptions. The lookahead sentinel
# remains on upstream master as of 2026-07-12.
file(WRITE "${_ripwire_tree_sitter_ignorelist}"
  "[implicit-unsigned-integer-truncation]\nfun:ts_parser__balance_subtree\n"
  "[function]\nfun:ts_parser__external_scanner_create\n")
# Swift's scanner stores lexer->lookahead (-1 at EOF) in uint32 inside this exact whitespace helper.
file(WRITE "${_ripwire_swift_ignorelist}"
  "[implicit-integer-sign-change]\nfun:eat_whitespace\n")
# Bash's scanner decrements zero-valued nesting depths after marking the scan complete; uint32 wrap is intentional.
file(WRITE "${_ripwire_bash_ignorelist}"
  "[unsigned-integer-overflow]\nfun:scan\n")

if(RIPWIRE_ASAN)
  foreach(_t IN LISTS RIPWIRE_RUNTIME_COMPILE_TARGETS)
    target_compile_options(${_t} PRIVATE ${RIPWIRE_G1_SANITIZERS}
      -fno-sanitize-recover=all -fno-omit-frame-pointer -O2 -g)
  endforeach()
  foreach(_t IN LISTS RIPWIRE_RUNTIME_LINK_TARGETS)
    target_link_options(${_t} PRIVATE ${RIPWIRE_G1_SANITIZERS})
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
  endif()

  # Xcode's arm64 Darwin runtime rejects both the standalone leak sanitizer and detect_leaks=1 at startup.
  # Keep the local ASan/UBSan gate executable and explicit; LeakSanitizer remains a Linux/upstream-runtime
  # CI gate using the committed tree-sitter suppressions rather than being falsely claimed on Apple Clang.
  if(APPLE)
    set(_ripwire_asan_options "detect_leaks=0:halt_on_error=1:abort_on_error=1")
  else()
    set(_ripwire_asan_options "detect_leaks=1:halt_on_error=1:abort_on_error=1")
  endif()
  add_custom_target(ripwire_asan_fixture
    COMMAND ${CMAKE_COMMAND} -E env
      "ASAN_OPTIONS=${_ripwire_asan_options}"
      "UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1"
      "LSAN_OPTIONS=suppressions=${CMAKE_CURRENT_SOURCE_DIR}/lsan_suppressions.txt"
      $<TARGET_FILE:ripwire> ${CMAKE_CURRENT_SOURCE_DIR}/test/fixture --no-cache
    DEPENDS ripwire
    COMMENT "Run the G1 fixture with the platform leak-detection policy")
endif()

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
  add_ripwire_fuzzer(csharp     tree_sitter_c_sharp    csharp)
  add_ripwire_fuzzer(c          tree_sitter_c          c)
  add_custom_target(ripwire_fuzzers DEPENDS ${RIPWIRE_FUZZ_TARGETS})
endif()
