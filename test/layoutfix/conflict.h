#pragma once

// conflict.h — a tripwire that DISAGREES with the computed size on purpose. The verb must report the
// static_assert with agree="0" rather than quietly trusting either number.
//   p@0(4)  q@4(4)  => 8, align 4 ... but the assert claims 12.
typedef struct WrongAssertCase
{
    float p;
    float q;
} WrongAssertCase;

static_assert( sizeof( WrongAssertCase ) == 12, "deliberately wrong — the gate proves the conflict is reported" );
