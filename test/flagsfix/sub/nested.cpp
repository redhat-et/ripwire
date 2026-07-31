// nested.cpp — a second read site for FIXTURE_DARK_FEATURE, and nesting: an inner #if must not close
// the outer one (the region/LOC accounting depends on the stack).
#include "../wiringFlags.h"

#if FIXTURE_DARK_FEATURE
int nestedDark()
{
#if FIXTURE_LIT_FEATURE
    return 10;
#else
    return 11;
#endif
}
#endif
