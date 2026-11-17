# Generate version.h at BUILD time, not only configure time. Agent worktrees are edited between
# configure/build constantly; a configure-time SHA becomes false provenance after the first edit.
execute_process(
  COMMAND git -C "${RIPWIRE_SOURCE_DIR}" rev-parse --short=9 HEAD
  RESULT_VARIABLE _git_rc
  OUTPUT_VARIABLE _git_sha
  ERROR_QUIET
  OUTPUT_STRIP_TRAILING_WHITESPACE)

# The version LABEL every surface prints (--version, MCP/LSP serverInfo, --html, --doctor): a build that is not exactly
# on the tag v${RIPWIRE_VERSION} says so (DEV-VERSION-LABEL, 0.7.0 rehearsal: a build of main 46 commits past v0.6.10
# printed a plain 0.6.10). test/versionlabelcheck.sh pins every row:
#   on the tag, clean                      -> X.Y.Z                 (a release build is unchanged)
#   on the tag, tracked edits              -> X.Y.Z+dirty
#   N first-parent commits past the tag    -> X.Y.Z-dev.N+g<sha9>   (main's own commits; a merged branch counts once)
#   a checkout with no v X.Y.Z tag in reach -> X.Y.Z-dev+g<sha9>     (a tagless shallow CI clone, a bump before its tag)
#   no git at all (an exported tarball)    -> X.Y.Z-dev             (unknown provenance is never called a release)
# a dirty dev build appends .dirty to the build metadata. kRipwireVersion stays the bare X.Y.Z the release triple
# comparisons parse (verbs_doctor.h doctorReleaseTriple).
set(_label "${RIPWIRE_VERSION}-dev")
if(NOT _git_rc EQUAL 0 OR _git_sha STREQUAL "")
  set(_git_stamp "unknown")
else()
  set(_git_stamp "${_git_sha}")
  set(_dirty FALSE)
  execute_process(COMMAND git -C "${RIPWIRE_SOURCE_DIR}" diff --quiet --ignore-submodules -- RESULT_VARIABLE _work_dirty ERROR_QUIET)
  execute_process(COMMAND git -C "${RIPWIRE_SOURCE_DIR}" diff --cached --quiet --ignore-submodules -- RESULT_VARIABLE _index_dirty ERROR_QUIET)
  if(NOT _work_dirty EQUAL 0 OR NOT _index_dirty EQUAL 0)
    string(APPEND _git_stamp "+dirty")
    set(_dirty TRUE)
  endif()
  execute_process(COMMAND git -C "${RIPWIRE_SOURCE_DIR}" describe --tags --exact-match --match "v${RIPWIRE_VERSION}" HEAD
                  RESULT_VARIABLE _on_tag OUTPUT_QUIET ERROR_QUIET)
  execute_process(COMMAND git -C "${RIPWIRE_SOURCE_DIR}" describe --tags --first-parent --long --match "v${RIPWIRE_VERSION}" HEAD
                  RESULT_VARIABLE _desc_rc OUTPUT_VARIABLE _desc ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(_on_tag EQUAL 0)
    set(_label "${RIPWIRE_VERSION}")
    if(_dirty)
      string(APPEND _label "+dirty")
    endif()
  else()
    if(_desc_rc EQUAL 0 AND _desc MATCHES "^v${RIPWIRE_VERSION}-([0-9]+)-g[0-9a-f]+$")
      set(_label "${RIPWIRE_VERSION}-dev.${CMAKE_MATCH_1}+g${_git_sha}")
    else()
      set(_label "${RIPWIRE_VERSION}-dev+g${_git_sha}")
    endif()
    if(_dirty)
      string(APPEND _label ".dirty")
    endif()
  endif()
endif()

set(_body "#pragma once\n\n// Generated at build time by cmake/version_stamp.cmake — do not edit.\nnamespace rw\n{\ninline constexpr const char* kRipwireVersion     = \"${RIPWIRE_VERSION}\";\ninline constexpr const char* kRipwireVersionLabel = \"${_label}\";\ninline constexpr const char* kRipwireBuildType   = \"${RIPWIRE_BUILD_TYPE}\";\ninline constexpr const char* kRipwireCompilerId  = \"${RIPWIRE_COMPILER_ID}\";\ninline constexpr const char* kRipwireCompilerVer = \"${RIPWIRE_COMPILER_VER}\";\ninline constexpr const char* kRipwireGitStamp    = \"${_git_stamp}\";\n} // namespace rw\n")

# A tmp name of its own, next to the output: two concurrent builds of the same configuration in one tree shared
# "<output>.tmp" (the same race cmake/source_identity.cmake closes). string(RANDOM) is seeded per process.
string(RANDOM LENGTH 12 _tmp_tag)
set(_tmp "${RIPWIRE_OUTPUT}.${_tmp_tag}.tmp")
file(WRITE "${_tmp}" "${_body}")
execute_process(COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${_tmp}" "${RIPWIRE_OUTPUT}" RESULT_VARIABLE _copy_rc)
file(REMOVE "${_tmp}")
if(NOT _copy_rc EQUAL 0)
  message(FATAL_ERROR "could not write ${RIPWIRE_OUTPUT}")
endif()
