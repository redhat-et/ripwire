// fieldaffinityfix — HAND-COMPUTED layouts for the --field-affinity gate. Every offset below is written
// out so the gate asserts a number a human derived, not a number the binary produced. LP64 / natural
// alignment, no pragma pack, no bitfields, no virtuals, no bases — deliberately inside the subset
// layout.h models with modeled="1".
#pragma once

#include <cstdint>

// Particle — the SPLIT-LINE case. Position (x,y,z) sits at bytes 0..11 and velocity (vx,vy,vz) at
// bytes 64..75, so a function that integrates position from velocity co-accesses two fields whose byte
// distance is EXACTLY 64: Chilimbi's wt = (64 - 64)/64 = 0.00, and no layout puts them on one line.
//   x     off 0    sz 4
//   y     off 4    sz 4
//   z     off 8    sz 4
//   pad0  off 12   sz 4
//   tagA  off 16   sz 8      (uint64 alignment is already satisfied at 16)
//   tagB  off 24   sz 8
//   tagC  off 32   sz 8
//   tagD  off 40   sz 8
//   tagE  off 48   sz 8
//   tagF  off 56   sz 8      -> ends at 64, so the first cache line is exactly full
//   vx    off 64   sz 4
//   vy    off 68   sz 4
//   vz    off 72   sz 4      -> 76, trailing pad 4 to align 8
// size 80, align 8, tail_pad 4
struct Particle
{
    float         x;
    float         y;
    float         z;
    float         pad0;
    std::uint64_t tagA;
    std::uint64_t tagB;
    std::uint64_t tagC;
    std::uint64_t tagD;
    std::uint64_t tagE;
    std::uint64_t tagF;
    float         vx;
    float         vy;
    float         vz;
};

// Straddler — the STRADDLE case. `payload` is 16 bytes starting at offset 56, so it occupies bytes
// 56..71 and CROSSES the 64-byte boundary: one field, two cache lines, on every access.
//   headA off 0   sz 8
//   headB off 8   sz 8
//   headC off 16  sz 8
//   headD off 24  sz 8
//   headE off 32  sz 8
//   headF off 40  sz 8
//   headG off 48  sz 8
//   payload off 56 sz 16  (double[2], align 8)   -> crosses 64
//   trailer off 72 sz 8
// size 80, align 8, tail_pad 0
struct Straddler
{
    std::uint64_t headA;
    std::uint64_t headB;
    std::uint64_t headC;
    std::uint64_t headD;
    std::uint64_t headE;
    std::uint64_t headF;
    std::uint64_t headG;
    double        payload[2];
    std::uint64_t trailer;
};

// Compact — the NEGATIVE case. Three co-accessed fields inside ONE 64-byte line. Nothing may fire here:
// "fire only where you can say which way is bad" — there is no bad direction for an already-adjacent set,
// and the tempting advice (pack tighter / sort by size) is exactly the non-monotonic move this lens refuses.
//   red off 0 sz 4 / green off 4 sz 4 / blue off 8 sz 4 / alpha off 12 sz 4   -> size 16, align 4
struct Compact
{
    float red;
    float green;
    float blue;
    float alpha;
};
