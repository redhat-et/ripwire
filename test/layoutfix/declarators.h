#pragma once

// declarators.h — the declarator LABEL cases and the in-body #define leak (LAYOUT-PTR-STAR, 2026-11-11 audit).
// Sizes and offsets were always right here; the ty= label was not: `char *name` printed `char **` (the `*` was
// kept in the type text AND appended again), a comma list's plain follow-on `b` inherited `char *`, and a
// #define line inside the body was glued onto the next field's type.

struct PtrStarCase
{
    char *name;     // ty="char *"   off 0
    char *a, b;     // a: "char *"   off 8;  b: "char", 1 B, off 16
    char* c;        // ty="char*"    off 24 (spacing as written)
    char **argv;    // ty="char **"  off 32
    int *p, *q;     // both "int *"  off 40 / 48
};                  // 56 B

struct DefineLeakCase
{
    int flags;
#define DLC_REDRAW 0x1
#define DLC_WIDE ( DLC_REDRAW \
                   | 0x2 )
    unsigned int sync_dirty;   // ty="unsigned int" off 4, never the #define text
};                             // 8 B
