# Generate version.h at BUILD time, not only configure time. Agent worktrees are edited between
# configure/build constantly; a configure-time SHA becomes false provenance after the first edit.
execute_process(
  COMMAND git -C "${RIPWIRE_SOURCE_DIR}" rev-parse --short=9 HEAD
  RESULT_VARIABLE _git_rc
  OUTPUT_VARIABLE _git_sha
  ERROR_QUIET
  OUTPUT_STRIP_TRAILING_WHITESPACE)

if(NOT _git_rc EQUAL 0 OR _git_sha STREQUAL "")
  set(_git_stamp "unknown")
else()
  set(_git_stamp "${_git_sha}")
  execute_process(COMMAND git -C "${RIPWIRE_SOURCE_DIR}" diff --quiet --ignore-submodules -- RESULT_VARIABLE _work_dirty ERROR_QUIET)
  execute_process(COMMAND git -C "${RIPWIRE_SOURCE_DIR}" diff --cached --quiet --ignore-submodules -- RESULT_VARIABLE _index_dirty ERROR_QUIET)
  if(NOT _work_dirty EQUAL 0 OR NOT _index_dirty EQUAL 0)
    string(APPEND _git_stamp "+dirty")
  endif()
endif()

set(_body "#pragma once\n\n// Generated at build time by cmake/version_stamp.cmake — do not edit.\nnamespace rw\n{\ninline constexpr const char* kRipwireVersion     = \"${RIPWIRE_VERSION}\";\ninline constexpr const char* kRipwireBuildType   = \"${RIPWIRE_BUILD_TYPE}\";\ninline constexpr const char* kRipwireCompilerId  = \"${RIPWIRE_COMPILER_ID}\";\ninline constexpr const char* kRipwireCompilerVer = \"${RIPWIRE_COMPILER_VER}\";\ninline constexpr const char* kRipwireGitStamp    = \"${_git_stamp}\";\n} // namespace rw\n")

set(_tmp "${RIPWIRE_OUTPUT}.tmp")
file(WRITE "${_tmp}" "${_body}")
execute_process(COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${_tmp}" "${RIPWIRE_OUTPUT}" RESULT_VARIABLE _copy_rc)
file(REMOVE "${_tmp}")
if(NOT _copy_rc EQUAL 0)
  message(FATAL_ERROR "could not write ${RIPWIRE_OUTPUT}")
endif()
