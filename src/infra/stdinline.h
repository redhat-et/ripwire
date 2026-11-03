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

#include "Diagnostics.h" // ASSUME — the null-stream precondition

#include <atomic>
#include <cstdio>
#include <string>

namespace rw
{

namespace detail
{

// The ONE reader both public entry points below are. `Bounded` picks the codegen at COMPILE TIME, not a
// runtime branch on `maxBytes`: the `Bounded=false` instantiation carries NO size check and NO write to
// `overflowed` at all (the `if constexpr` branches not taken are not compiled), so `readByteSafeLine`
// costs exactly what it did before this function had a bounded sibling — the two callers below are
// separate specializations of one template, not one function with an extra runtime comparison per byte.
//
// Byte safety comes from staying on fgetc's int contract and doing the only narrowing EXPLICITLY, through
// `unsigned char`, so a high byte can never be implicitly sign-changed. See readByteSafeLine's own comment
// for the PARITY CONTRACT the unbounded instantiation must keep, and readByteSafeLineBounded's for what
// bounded draining adds on top.
template<bool Bounded>
inline bool readByteSafeLineCore( std::FILE* in, std::string& line, std::size_t maxBytes, bool& overflowed )
{
    ASSUME( in != nullptr );

    line.clear();
    if constexpr( Bounded )
    {
        overflowed = false;
    }

    // one byte at a time; EOF is an int sentinel distinct from every 0x00..0xFF byte value.
    bool didReadAnyByte = false;
    for( int byteOrEof = std::fgetc( in ); byteOrEof != EOF; byteOrEof = std::fgetc( in ) )
    {
        didReadAnyByte = true;
        if( byteOrEof == '\n' )
        {
            return true; // delimiter consumed, not appended
        }

        if constexpr( Bounded )
        {
            if( line.size() < maxBytes )
            {
                line.push_back( static_cast<char>( static_cast<unsigned char>( byteOrEof ) ) );
            }
            else
            {
                overflowed = true; // keep draining to the delimiter — never grow past maxBytes
            }
        }
        else
        {
            line.push_back( static_cast<char>( static_cast<unsigned char>( byteOrEof ) ) );
        }
    }

    // EOF. An unterminated tail line is delivered exactly once (getline's behaviour); the next call
    // sees nothing and reports end-of-stream.
    return didReadAnyByte;
}

} // namespace detail

// Read one '\n'-terminated line of RAW BYTES from `in` into `line`.
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
inline bool readByteSafeLine( std::FILE* in, std::string& line )
{
    bool unused = false; // the Bounded=false instantiation never touches this — see readByteSafeLineCore
    return detail::readByteSafeLineCore<false>( in, line, 0, unused );
}

// ── input blow-up guard: a BOUNDED line reader for peers whose line length is NOT the caller's own
// invariant to keep unbounded (the MCP stdio request line — readByteSafeLine's own parity contract above
// is deliberate for the trusted callers that need it: a git-pipe reader must never split a long path, so
// growing without limit is the CORRECT behaviour there, not a bug to fix everywhere).
//
// A stdio JSON-RPC peer is untrusted the same way an HTTP client is (mcpserver.h bounds a request body at
// kMaxBodyBytes before it ever reaches the JSON-RPC layer — see runMcp()'s own comment on this reader),
// but stdio had no equivalent: one line with no '\n' grows the buffer for as long as the peer keeps
// writing, so a single hostile or runaway request can exhaust memory on a long-lived server that would
// otherwise happily keep serving every request after it.
//
// Same fgetc contract and the same byte-safety as readByteSafeLine (explicit unsigned-char narrowing —
// see readByteSafeLineCore's comment); the only difference is what happens once `line` reaches maxBytes:
// further bytes of THIS line are read and DISCARDED (not buffered) rather than growing `line`, so memory
// stays bounded at maxBytes regardless of how long the peer's line actually is, and the stream position
// still recovers at the next '\n' — the call after an overflowed line reads the NEXT real line, never a
// decoded fragment of the runaway one. `line` holds only the first maxBytes bytes when overflowed is set;
// callers must not dispatch it as if it were the whole request (it isn't).
inline bool readByteSafeLineBounded( std::FILE* in, std::string& line, std::size_t maxBytes, bool& overflowed )
{
    return detail::readByteSafeLineCore<true>( in, line, maxBytes, overflowed );
}

} // namespace rw
