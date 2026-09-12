// test/stdqualfix — file 13: the ObjC++ arm, and a STATED FLOOR. tree-sitter-objc parses `std::move( x )` as an
// ERROR node spelling `std::` beside a bare `move( x )` call (measured with --match='(ERROR) @e'), and ingest sets
// no call qualifier for Lang::ObjC, so the reference arrives UNQUALIFIED and the std:: guard never sees it. Both
// sites below are therefore bare calls to the resolver, before the fix and after it:
//   bridgeMove  std::move       → refused by the Phase-5 veto (move is in the table, no free move exists)
//   bridgeStop  std::unreachable → NOT in the table, so it still binds Cursor::unreachable — the floor.
// Closing it needs the qualifier recovered at EXTRACTION for the ObjC grammar, which is a parser change.

#include "buffers.h"

#include <utility>

int bridgeMove( int x )
{
    return std::move( x );
}

void bridgeStop()
{
    std::unreachable();
}
