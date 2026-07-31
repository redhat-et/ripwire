#pragma once

// tracein.h — B11/L2 trace-to-locus (--from-trace=FILE, '-' = stdin, PLAN_agentLeverage2026.md).
//
// Agents hand-translate stack traces / sanitizer reports / compiler errors into ctxpack queries many times
// per session (this round: a UBSan `mention.h:95:48` turned into a manual file read). This module is the
// deterministic, zero-dependency FRAME EXTRACTOR: it turns the raw text of such an artifact into an ordered
// list of {path, line, func, format} frames. The corpus resolution (frame → indexed file → enclosing symbol)
// and the bundle emission live in the runFromTrace handler (src/main.cpp), reusing mention.h's
// pathSuffixMatches and the --grep enclosing-symbol lookup — this header stays pure string work so it is
// unit-testable in isolation (test/tracecheck.sh) and shares nothing with the graph.
//
// Table-driven (the route-detector / kHttpMethodTable precedent, src/model.h): one constexpr FormatSpec row
// per recognised shape carries its human label and the ONE fact the ranker needs — whether frame #0 (the
// text-topmost frame) is the INNERMOST (crash/throw site) or the OUTERMOST. Python traceback frames are
// printed outermost-first (innermost LAST); every other shape here prints innermost-first.
//
// Contract (each promise pinned in test/tracecheck.sh):
//   * Per-line extraction tries the formats in a FIXED priority order; the first match wins, so a Python
//     `File "..."` line never falls through to the generic `path:line` fallback.
//   * DETERMINISTIC — frames keep text appearance order (`seq`); the innermost-first ordering is a pure
//     function of `seq` and the dominant format's `innermostIsFirst`. No hashing, no RNG, no I/O.
//   * NEVER FABRICATES — a line that does not match any shape yields no frame (empty input → zero frames →
//     the handler refuses loudly rather than emitting an empty map).

#include "Diagnostics.h"   // VERIFY — the frames-seen tally's own invariant (§B10)

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace ctx
{
namespace tracein
{

// the recognised frame shapes, in priority order (Python's `File "..."` line is the most specific, the bare
// `path:line` generic fallback is the least). Count is the table-size tripwire, never a real format.
enum class FrameFormat : std::uint8_t { Python, Asan, Node, Compiler, Generic, Count };

struct FormatSpec
{
    const char* label;             // the header's format="..." value
    bool        innermostIsFirst;  // is the text-topmost frame the innermost (crash/throw) site?
};

// ONE row per FrameFormat, index == enum value (the static_assert pins the correspondence). Python prints
// outermost-first (innermost is the LAST frame); ASan (#0 = crash), node (throw site topmost), compiler
// (primary diagnostic first) and the generic fallback all print innermost-first.
inline constexpr FormatSpec kFormatTable[] = {
    { "python",   false },   // File "x.py", line N, in fn
    { "asan",     true  },   // #k 0x.. in fn path:line:col
    { "node",     true  },   // at fn (path:line:col)
    { "compiler", true  },   // path:line:col: error/warning/note
    { "generic",  true  },   // path:line
};
static_assert( sizeof( kFormatTable ) / sizeof( kFormatTable[0] ) == std::size_t( FrameFormat::Count ),
               "kFormatTable must carry exactly one row per FrameFormat" );

inline const FormatSpec& formatSpec( FrameFormat f ) noexcept { return kFormatTable[ std::size_t( f ) ]; }

// one extracted frame — `func` is best-effort (empty when the shape carries no name); `line` is 1-based.
struct ParsedFrame
{
    std::string   path;
    std::string   func;
    std::uint32_t line           = 0;
    FrameFormat   format         = FrameFormat::Generic;
    std::uint32_t seq            = 0;      // 0-based appearance index, top-to-bottom in the source text
    bool          lineOverflowed = false;  // AUDIT5 F7: the raw digit span for `line` would wrap uint32_t —
                                            // saturate-and-miss (never wrap mod 2^32 into a real, wrong line)
};

namespace detail
{

inline bool isDigits( std::string_view s ) noexcept
{
    if( s.empty() ) return false;
    for( const char c : s ) if( c < '0' || c > '9' ) return false;
    return true;
}

// AUDIT5 F7: a hostile/garbled frame line number (e.g. a fuzzed or truncated trace) can exceed UINT32_MAX;
// unchecked `v*10+d` wraps mod 2^32 (4294967297 -> 1), which then confidently maps to a REAL line in the
// corpus and emits the wrong symbol's full body as the innermost frame — silently wrong, never refused.
// Saturate-and-miss instead (the overflow-checked style of every other CLI parser here, AUDIT4 F6 sweep):
// on overflow, set `overflowed` and return 0; callers propagate this onto ParsedFrame::lineOverflowed so
// the frame still parses (format/path/func are honest) but degrades to unmapped — it lands in <skipped>,
// never <suspects>. `overflowed` is only ever SET here, never cleared, so a caller may share one flag
// across a path:line:col span where only the line group matters.
inline std::uint32_t toUint( std::string_view s, bool& overflowed ) noexcept
{
    std::uint32_t v = 0;
    for( const char c : s )   // callers pass only isDigits() spans
    {
        const std::uint32_t d = std::uint32_t( c - '0' );
        if( v > ( UINT32_MAX - d ) / 10u ) { overflowed = true; return 0; }
        v = v * 10u + d;
    }
    return v;
}

// trim ASCII whitespace from both ends
inline std::string_view trim( std::string_view s ) noexcept
{
    std::size_t a = 0, b = s.size();
    while( a < b && ( s[a] == ' ' || s[a] == '\t' || s[a] == '\r' ) ) ++a;
    while( b > a && ( s[b - 1] == ' ' || s[b - 1] == '\t' || s[b - 1] == '\r' ) ) --b;
    return s.substr( a, b - a );
}

// a token is path-shaped enough to be a source location if it carries a directory sep or an extension dot —
// this is what keeps the generic `path:line` fallback from matching prose like "step:3" or "note:".
inline bool looksLikePath( std::string_view p ) noexcept
{
    return !p.empty() && ( p.find( '/' ) != std::string_view::npos || p.find( '.' ) != std::string_view::npos );
}

// split a trailing `:line` or `:line:col` off `s`, leaving the path. Returns false unless the tail is a real
// 1+-digit line number AND the remaining head looks like a path. Handles both node/asan location shapes.
// `overflowed` (F7): set true, `line` left at 0, when the line digits would wrap uint32_t — the frame still
// parses (path/format are honest) but its caller degrades it to unmapped rather than trust a wrapped line.
inline bool splitPathLine( std::string_view s, std::string& path, std::uint32_t& line, bool& overflowed ) noexcept
{
    const std::size_t c1 = s.rfind( ':' );
    if( c1 == std::string_view::npos ) return false;
    const std::string_view tail1 = s.substr( c1 + 1 );
    if( !isDigits( tail1 ) ) return false;
    const std::string_view head1 = s.substr( 0, c1 );

    // `path:line:col` → the second-from-right colon-group is the line, tail1 was the column
    const std::size_t c2 = head1.rfind( ':' );
    if( c2 != std::string_view::npos && isDigits( head1.substr( c2 + 1 ) ) )
    {
        const std::string_view head2 = head1.substr( 0, c2 );
        if( looksLikePath( head2 ) ) { path.assign( head2 ); line = toUint( head1.substr( c2 + 1 ), overflowed ); return true; }
    }
    // `path:line`
    if( !looksLikePath( head1 ) ) return false;
    path.assign( head1 );
    line = toUint( tail1, overflowed );
    return true;
}

// Python: `  File "app/main.py", line 2, in outer`  (func optional; frames printed outermost-first)
inline std::optional<ParsedFrame> parsePython( std::string_view line )
{
    const std::size_t f = line.find( "File \"" );
    if( f == std::string_view::npos ) return std::nullopt;
    const std::size_t q1 = f + 6;
    const std::size_t q2 = line.find( '"', q1 );
    if( q2 == std::string_view::npos ) return std::nullopt;
    const std::size_t ln = line.find( ", line ", q2 );
    if( ln == std::string_view::npos ) return std::nullopt;
    std::size_t d = ln + 7;
    const std::size_t ds = d;
    while( d < line.size() && line[d] >= '0' && line[d] <= '9' ) ++d;
    if( d == ds ) return std::nullopt;

    ParsedFrame fr;
    fr.format = FrameFormat::Python;
    fr.path.assign( line.substr( q1, q2 - q1 ) );
    fr.line = toUint( line.substr( ds, d - ds ), fr.lineOverflowed );
    if( const std::size_t in = line.find( ", in ", d ); in != std::string_view::npos )
        fr.func.assign( trim( line.substr( in + 5 ) ) );
    return fr;
}

// ASan/UBSan stack frame: `    #0 0x108a in doWork src/engine.cpp:5:8`  (#0 = innermost crash site)
inline std::optional<ParsedFrame> parseAsan( std::string_view line )
{
    const std::string_view t = trim( line );
    if( t.size() < 2 || t[0] != '#' || t[1] < '0' || t[1] > '9' ) return std::nullopt;
    const std::size_t in = t.find( " in " );
    if( in == std::string_view::npos ) return std::nullopt;
    const std::string_view after = trim( t.substr( in + 4 ) );      // `doWork src/engine.cpp:5:8`
    ParsedFrame fr;
    fr.format = FrameFormat::Asan;

    // §A2a: the source location is the LAST space-separated token that parses as path:line[:col], so scan from
    // the RIGHT. Splitting at the FIRST space cut a DEMANGLED C++ name in half — `runDefaultMap(MainDispatch
    // const&) src/main.cpp:5155` yielded func="runDefaultMap(MainDispatch" and path="const&) src/main.cpp",
    // which still suffix-matched the file while destroying the one thing name resolution needs. Trailing
    // non-location junk (a `(BuildId: …)` tail) just fails the probe and the scan steps left.
    for( std::size_t sp = after.rfind( ' ' ); sp != std::string_view::npos; sp = sp == 0 ? std::string_view::npos : after.rfind( ' ', sp - 1 ) )
    {
        if( !splitPathLine( trim( after.substr( sp + 1 ) ), fr.path, fr.line, fr.lineOverflowed ) ) continue;
        fr.func.assign( trim( after.substr( 0, sp ) ) );
        return fr;
    }
    return std::nullopt;                                             // no source location → an in-module-only frame
}

// node/js stack frame: `    at inner (web/worker.js:2:9)` or `    at web/worker.js:2:9`  (throw site topmost)
inline std::optional<ParsedFrame> parseNode( std::string_view line )
{
    const std::string_view t = trim( line );
    if( t.size() < 3 || t.substr( 0, 3 ) != "at " ) return std::nullopt;
    const std::string_view rest = trim( t.substr( 3 ) );
    ParsedFrame fr;
    fr.format = FrameFormat::Node;
    if( const std::size_t lp = rest.find( '(' ); lp != std::string_view::npos )
    {
        const std::size_t rp = rest.find( ')', lp );
        if( rp == std::string_view::npos ) return std::nullopt;
        if( !splitPathLine( trim( rest.substr( lp + 1, rp - lp - 1 ) ), fr.path, fr.line, fr.lineOverflowed ) ) return std::nullopt;
        fr.func.assign( trim( rest.substr( 0, lp ) ) );
    }
    else if( !splitPathLine( rest, fr.path, fr.line, fr.lineOverflowed ) )
        return std::nullopt;
    return fr;
}

// compiler diagnostic: `src/parser.cpp:5:14: error: ...` or `src/parser.cpp:3: note: ...` (primary first).
// The distinguishing mark vs the generic fallback is the trailing diagnostic colon after the location.
inline std::optional<ParsedFrame> parseCompiler( std::string_view line )
{
    const std::string_view t = trim( line );
    const std::size_t c1 = t.find( ':' );
    if( c1 == std::string_view::npos ) return std::nullopt;
    const std::string_view path = t.substr( 0, c1 );
    if( !looksLikePath( path ) ) return std::nullopt;

    std::size_t p = c1 + 1;                                          // parse line digits
    const std::size_t ls = p;
    while( p < t.size() && t[p] >= '0' && t[p] <= '9' ) ++p;
    if( p == ls ) return std::nullopt;
    bool lineOverflowed = false;
    const std::uint32_t lineNo = toUint( t.substr( ls, p - ls ), lineOverflowed );

    if( p < t.size() && t[p] == ':' )                               // optional `:col`, then the diagnostic colon
    {
        std::size_t q = p + 1;
        const std::size_t cs = q;
        while( q < t.size() && t[q] >= '0' && t[q] <= '9' ) ++q;
        if( q > cs ) p = q;                                         // consumed a column; p now sits on the trailing ':'
    }
    if( p >= t.size() || t[p] != ':' ) return std::nullopt;         // no trailing diagnostic colon → this is generic

    ParsedFrame fr;
    fr.format = FrameFormat::Compiler;
    fr.path.assign( path );
    fr.line = lineNo;
    fr.lineOverflowed = lineOverflowed;
    return fr;
}

// bare `path:line` (or `path:line:col`) — the least specific fallback; the WHOLE trimmed line must be the
// location (no trailing diagnostic text, which parseCompiler already claimed).
inline std::optional<ParsedFrame> parseGeneric( std::string_view line )
{
    ParsedFrame fr;
    fr.format = FrameFormat::Generic;
    if( !splitPathLine( trim( line ), fr.path, fr.line, fr.lineOverflowed ) ) return std::nullopt;
    return fr;
}

} // namespace detail

// §B10 — the OUTER denominator. Everything downstream partitions the frames this file EXTRACTED
// (`in_corpus = suspects + merged + unresolved`, airtight and VERIFY-backed), but a line the input clearly
// presented as a stack frame and no format shape could read lands in NO bucket and simply vanishes: the
// capture's own ASan trace has five `#N` frames and reports parsed="4", because the dyld frame carries no
// source location at all. Nothing in the report said a frame had been dropped, so 4 read as "this trace has
// 4 frames" rather than "1 of 5 could not be extracted". The tally below is the missing denominator.
//
// A line is FRAME-SHAPED when it carries a stack-frame MARKER: a `#<digit>` at the start of the trimmed
// line (ASan/UBSan/gdb/lldb), a leading `at ` (node/JVM), or a Python `File "`. Deliberately marker-only —
// a bare `path:line` that fails to parse is not recognisably a frame, and counting every unparsed line
// would make the denominator meaningless. Every EXTRACTED frame counts too, whatever its shape, so
// `frames.size() <= frameShapedLines` holds by construction and the difference is exactly "frame-shaped,
// not extractable".
inline bool isFrameShapedLine( std::string_view line ) noexcept
{
    const std::string_view t = detail::trim( line );
    if( t.size() >= 2 && t[0] == '#' && t[1] >= '0' && t[1] <= '9' ) return true;
    if( t.size() >= 3 && t.substr( 0, 3 ) == "at " )                 return true;
    return line.find( "File \"" ) != std::string_view::npos;
}

// The scan's whole result: the frames, and how many frame-shaped lines they were extracted FROM.
struct FrameScan
{
    std::vector<ParsedFrame> frames;
    std::size_t              frameShapedLines = 0;   // >= frames.size(); the difference never entered a bucket
};

// extract every recognised frame from the raw trace text, in text order. Priority per line: Python, ASan,
// node, compiler, generic (first match wins) — the ordering that keeps each shape from stealing another's
// lines. `seq` is assigned in appearance order for the deterministic innermost-first sort downstream.
inline FrameScan extractFrames( std::string_view text )
{
    FrameScan   scan;
    std::size_t start = 0;
    while( start <= text.size() )
    {
        const std::size_t      nl   = text.find( '\n', start );
        const std::string_view line = text.substr( start, ( nl == std::string_view::npos ? text.size() : nl ) - start );
        start = ( nl == std::string_view::npos ) ? text.size() + 1 : nl + 1;

        std::optional<ParsedFrame> fr = detail::parsePython( line );
        if( !fr ) fr = detail::parseAsan( line );
        if( !fr ) fr = detail::parseNode( line );
        if( !fr ) fr = detail::parseCompiler( line );
        if( !fr ) fr = detail::parseGeneric( line );
        if( fr )
        {
            fr->seq = std::uint32_t( scan.frames.size() );
            scan.frames.push_back( std::move( *fr ) );
            ++scan.frameShapedLines;                        // an extracted frame is frame-shaped by definition
        }
        else if( isFrameShapedLine( line ) ) ++scan.frameShapedLines;
    }
    VERIFY( scan.frames.size() <= scan.frameShapedLines );
    return scan;
}

// the trace's dominant format = the most frequent frame format; ties break to the format whose FIRST frame
// appears earliest (smallest seq) — a total order, so the header label and the innermost sort are stable.
inline FrameFormat dominantFormat( const std::vector<ParsedFrame>& frames )
{
    std::uint32_t count[ std::size_t( FrameFormat::Count ) ] = {};
    std::uint32_t firstSeq[ std::size_t( FrameFormat::Count ) ];
    for( auto& v : firstSeq ) v = UINT32_MAX;
    for( const ParsedFrame& f : frames )
    {
        const std::size_t k = std::size_t( f.format );
        ++count[k];
        firstSeq[k] = std::min( firstSeq[k], f.seq );
    }
    FrameFormat best     = FrameFormat::Generic;
    std::uint32_t bestN  = 0;
    std::uint32_t bestFs = UINT32_MAX;
    for( std::size_t k = 0; k < std::size_t( FrameFormat::Count ); ++k )
    {
        if( count[k] == 0 ) continue;
        if( count[k] > bestN || ( count[k] == bestN && firstSeq[k] < bestFs ) )
        {
            best   = FrameFormat( k );
            bestN  = count[k];
            bestFs = firstSeq[k];
        }
    }
    return best;
}

// innermost-first sort key for `f` under the dominant format: the text-topmost frame is innermost for every
// shape except Python (printed outermost-first), where the key is reversed. `frameCount` is the total so the
// reversal stays non-negative. Smaller key == more innermost == higher rank.
inline std::uint32_t innermostKey( const ParsedFrame& f, FrameFormat dominant, std::size_t frameCount ) noexcept
{
    return formatSpec( dominant ).innermostIsFirst ? f.seq : std::uint32_t( frameCount ) - f.seq;
}

} // namespace tracein
} // namespace ctx
