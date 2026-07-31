# The --flags fixture's CMAKE lane.
cmake_minimum_required(VERSION 3.20)

option(FIXTURE_CMAKE_DARK "a build switch that ships OFF"                       OFF)
option(FIXTURE_CMAKE_LIT  "a build switch that ships ON"                        ON)
# The OVERRIDE case: also a header gate defaulting to 0 — the CMake default must WIN.
option(FIXTURE_OVERRIDE   "header says 0, the build says ON — cmake wins"       ON)

target_compile_definitions(fixture PRIVATE
    $<$<BOOL:${FIXTURE_CMAKE_DARK}>:FIXTURE_CMAKE_DARK=1>
    $<$<BOOL:${FIXTURE_CMAKE_LIT}>:FIXTURE_CMAKE_LIT=1>
    $<$<BOOL:${FIXTURE_OVERRIDE}>:FIXTURE_OVERRIDE=1>)
