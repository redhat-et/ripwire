#pragma once

// packed.h — `__attribute__((packed))` is LOCAL and unambiguous: it sits on the aggregate, so the model
// applies it (every field aligns to 1, no interior or trailing padding) and reports packed="1".
//   a@0(1)  b@1(4)  c@5(1)  => 6, align 1
// Its file-scoped cousin `#pragma pack` lives in pragmapack.h — deliberately a SEPARATE file, because the
// pragma withdraws the numbers for every aggregate in whatever file it appears in, this one included.
struct __attribute__((packed)) PackedAttrCase
{
    char  a;
    int   b;
    char  c;
};

static_assert( sizeof( PackedAttrCase ) == 6, "packed-attribute byte contract" );
