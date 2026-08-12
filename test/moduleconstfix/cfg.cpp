// cfg.cpp — translation-unit-scope const-qualified camel constants (the C++ file-scope arm of the
// module-constant family) plus the mutable/local negatives that keep the gate honest about scope.
#include "verpin.h"

// TU-scope constexpr, camel — must index t="var" post-fix
constexpr int kMcTuConstexpr = 12;

// TU-scope plain const pointer, camel
const char* kMcTuConstPtr = "hosts";

// TU-scope static const, camel
static const int kMcTuStaticConst = 4096;

// NEGATIVE: mutable camel global — no const qualifier, not SCREAMING → stays unindexed
int mcMutableCamelGlobal = 5;

int mcConsumeAll()
{
    // a real read site for the --uses arm
    int total = kMcTuConstexpr + kMcTuStaticConst + mcfix::kMcNsConstexpr;

    // NEGATIVE: function-local constexpr camel — compound_statement scope, stays unindexed
    constexpr int kMcLocalConstexpr = 3;
    total += kMcLocalConstexpr + int( kMcTuConstPtr[0] );
    return total;
}
