// test/stdqualfix — file 13: the ObjC++ arm (was a STATED FLOOR). tree-sitter-objc parses `std::move( x )` as an
// ERROR node spelling `std::` beside a bare `move( x )` call (measured with --match='(ERROR) @e'). Since lane
// objcxx-std-qualified, ingest reads the std-rooted chain back (ingest_names.h objcxxStdQualifierBefore), so the
// reference arrives qualified `std` and the std:: guard refuses both sites, as it does in callers.cpp:
//   bridgeMove  std::move       → refused (also a Phase-5 veto table name: no free move exists)
//   bridgeStop  std::unreachable → refused (NOT a table name: before the lane it bound Cursor::unreachable — the floor).
// A non-std chain in a .mm keeps the bare-call ladder (stdqualcheck §16's vendor:: controls).

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
