// test/stdqualfix — file 2: the std::-qualified call SITES against the lone decoys in buffers.h, plus the
// true member calls that must keep their edges. One spelling per function, so a per-spelling --callees
// literal is possible at all.
//
//   takeTwice   std::move x2            → external (was: 1 edge to Buf::move)
//   takeRooted  ::std::move             → external (leading-:: spelling, same immediate qualifier "std")
//   takeInline  std::__1::move          → external (libc++ inline ABI namespace spelling, qualifier "__1")
//   flipTwice   std::swap x2            → external (was: 1 edge to Slot::swap)
//   flipRooted  ::std::swap             → external
//   stopHere    std::unreachable()      → external (the .cpp twin of bridge.mm's ObjC++ floor)
//   useBuf      buf.move()              → Buf::move  — a TRUE member call, kept
//   useSlot     a.swap( b )             → Slot::swap — a TRUE member call, kept

#include "buffers.h"

#include <utility>

int takeTwice( int x )
{
    int y = std::move( x );
    int z = std::move( y );
    return z;
}

int takeRooted( int x )
{
    return ::std::move( x );
}

int takeInline( int x )
{
    return std::__1::move( x );
}

void flipTwice( int& a, int& b )
{
    std::swap( a, b );
    std::swap( b, a );
}

void flipRooted( int& a, int& b )
{
    ::std::swap( a, b );
}

void stopHere()
{
    std::unreachable();
}

void useBuf( store::Buf& buf )
{
    buf.move();
}

void useSlot( store::Slot& a, store::Slot& b )
{
    a.swap( b );
}
