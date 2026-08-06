// The REAL-WORLD shape that made this a false positive rather than a rounding error: a translation unit
// whose entire body is wrapped in one feature guard, so all but one of its includes live inside the `#if`.
// (Measured on a private C++ tree: levelEdit2/LevelEditor.cpp wraps its body in `#if LEVELEDIT` and
// ripwire captured 1 of its ~29 includes — including MISSING its own header, which is what shipped the
// pair (LevelEditor.cpp, LevelEditor.h) as --cochange `surprising="1"`.)
//
// whole_pre.h is the analogue of the single include above the guard; whole.h is this file's OWN header,
// visible only from inside the guard, and is what the cochange arm of the gate keys on.

#include "whole_pre.h"

#if RIPWIRE_WHOLE_ENABLED

#import "whole.h"
#include "whole_dep.h"

int wholeFn()
{
    return 0;
}

#endif
