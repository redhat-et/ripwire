#pragma once

// mirror_gpu.h — the DEVICE side of the same uniform block, drifted: `bias` was dropped here but not
// on the host, so the two sides disagree by 4 bytes and every field after gain reads garbage.
//   gain@0(4)  flags@4(4)  => 8, align 4     (host says 12)
typedef struct MirrorUniforms
{
    float        gain;
    unsigned int flags;
} MirrorUniforms;

// …and the twin that did NOT drift.
typedef struct TwinUniforms
{
    float        level;
    unsigned int mask;
} TwinUniforms;
