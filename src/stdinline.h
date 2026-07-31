#pragma once

// stdinline.h — the ONE byte-safe line reader for every stdin-consuming surface (R4).
//
// WHY THIS EXISTS. `std::getline( std::cin, line )` is not byte-safe under the G1 sanitizer stack.
// libc++'s `getline( basic_istream&, basic_string& )` refills through a one-character fallback
// (`istream:1283`, `_CharT __1buf = __next;`) whenever the streambuf exposes NO get area — which is
// exactly the case for `std::cin`, whose stdio-synced buffer keeps `gptr() == egptr()` on every read.
// That assignment narrows `int_type`(int) to `char`, so ANY byte in 0x80..0xFF trips
// `-fsanitize=integer` (implicit-integer-sign-change) and, with `-fno-sanitize-recover=all`, ABORTS
// the process mid-request. Consequence before this file existed: the whole `--mcp` server plus the
// two `-`-from-stdin CLI verbs were sanitizer-DARK for non-ASCII input — a hostile UTF-8 byte killed
// the asan build instead of being answered, so no gate could observe behaviour past that byte.
// The owner ruling (R4, 2026-07-29) is an explicit reader here, NOT a UBSan suppression.
//
// A real `basic_filebuf` (every `std::ifstream` getline in this tree) keeps a get area, so
// `__first != __last` and the narrowing branch is never taken — those sites are unaffected and were
// probed to confirm it. Only the `std::cin` family needed replacing.
//
// PARITY CONTRACT (byte-for-byte with the getline it replaces — every MCP/batch gate must stay
// byte-identical, so this list is the specification, not a summary):
//   • the string is CLEARED first, then grows dynamically — a >1 MB line is never split into garbage
//   • the '\n' delimiter is CONSUMED and NOT appended
//   • a trailing '\r' is LEFT IN PLACE — CRLF input yields "...\r", exactly as getline does today
//     (callers that care already strip it; none may start seeing a different string)
//   • an embedded NUL is appended like any other byte
//   • a final line with NO trailing newline is still delivered once, and the call AFTER it reports
//     end-of-stream — i.e. false is returned ONLY at EOF with nothing accumulated
//
// stdio-vs-iostream mixing is safe here: nothing in this tree calls
// `std::ios::sync_with_stdio( false )`, so `std::cin` and `stdin` share one buffer and one position.

#include "Diagnostics.h"   // VERIFY — the null-stream precondition

#include <cstdio>
#include <string>

namespace ctx
{

// Read one '\n'-terminated line of RAW BYTES from `in` into `line`. See the parity contract above.
// Byte safety comes from staying on fgetc's int contract and doing the only narrowing EXPLICITLY,
// through `unsigned char`, so a high byte can never be implicitly sign-changed.
inline bool readByteSafeLine( std::FILE* in, std::string& line )
{
    VERIFY( in != nullptr );

    line.clear();

    // one byte at a time; EOF is an int sentinel distinct from every 0x00..0xFF byte value.
    bool didReadAnyByte = false;
    for( int byteOrEof = std::fgetc( in ); byteOrEof != EOF; byteOrEof = std::fgetc( in ) )
    {
        didReadAnyByte = true;
        if( byteOrEof == '\n' ) return true;                                        // delimiter consumed, not appended

        line.push_back( static_cast< char >( static_cast< unsigned char >( byteOrEof ) ) );
    }

    // EOF. An unterminated tail line is delivered exactly once (getline's behaviour); the next call
    // sees nothing and reports end-of-stream.
    return didReadAnyByte;
}

}   // namespace ctx
