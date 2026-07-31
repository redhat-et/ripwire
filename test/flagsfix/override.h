// override.h — the same name the CMakeLists declares ON. A reader greps THIS and concludes "dark";
// the build passes -DFIXTURE_OVERRIDE=1. --flags must report cmake/ON with this as the <also> row.
#pragma once

#ifndef FIXTURE_OVERRIDE
#define FIXTURE_OVERRIDE 0
#endif

#if FIXTURE_OVERRIDE
int overrideOn();
#endif

#if FIXTURE_CMAKE_DARK
int cmakeDarkOn();
#endif

#if FIXTURE_CMAKE_LIT
int cmakeLitOn();
#endif
