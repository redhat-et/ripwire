#pragma once

// mirror_cpu.h — the HOST side of a dual-compile uniform block. Its GPU-side mirror
// (mirror_gpu.h) has DRIFTED: this is the bug --layout exists to catch.
//   gain@0(4)  bias@4(4)  flags@8(4)  => 12, align 4
typedef struct MirrorUniforms
{
    float        gain;
    float        bias;
    unsigned int flags;
} MirrorUniforms;

// The twin pair below is the NEGATIVE control: identical on both sides, so the verb must say
// "match" and must NOT cry mismatch on every multiply-defined name it sees.
typedef struct TwinUniforms
{
    float        level;
    unsigned int mask;
} TwinUniforms;
