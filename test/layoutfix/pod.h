#pragma once

// pod.h — layout fixture: structs whose byte offsets are known BY HAND, one per modelled rule.
// Never compiled; ripwire indexes it as C++ and test/layoutcheck.sh asserts the computed table.

#define SLOT_COUNT 4

// PADDING: char/int/char/double — 3 B of interior pad before b, 7 B before d, no tail pad.
//   a@0(1)  pad3  b@4(4)  c@8(1)  pad7  d@16(8)  => 24, align 8
typedef struct PadCase
{
    char   a;
    int    b;
    char   c;
    double d;
} PadCase;

static_assert( sizeof( PadCase ) == 24, "pad-case byte contract" );

// ALIGNMENT: alignas on the struct itself raises its alignment and therefore its SIZE — the natural
// size is 8, but the trailing pad up to align 32 makes the object 32 B.
struct alignas( 32 ) AlignCase
{
    float x;
    float y;
};

static_assert( sizeof( AlignCase ) == 32, "align-case byte contract" );

// ARRAY + NESTED STRUCT + a MACRO extent: the array's element type is another struct in this tree and
// its extent is a #define, so both have to be resolved before an offset exists.
//   slots@0(32)  tag@32(2)  pad2(tail, to align 4)  => 36, align 4
typedef struct Slot
{
    float u;
    float v;
} Slot;

typedef struct ArrayCase
{
    Slot           slots[ SLOT_COUNT ];
    unsigned short tag;
} ArrayCase;

static_assert( sizeof( ArrayCase ) == 36, "array-case byte contract" );
