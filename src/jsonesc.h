#pragma once

// jsonesc.h — A4-F27: the ONE canonical JSON string-escaping core, unifying three near-clone
// escapers (mcp.h's mcpdetail::jsonEscape, ccjson.h's ccJsonEscape, htmlexport.h's jsonEscape;
// --clones found them 0.92-similar). All three agree on the mandatory JSON set (control chars,
// `"`, `\`) — they diverge on exactly two axes, which this core takes as parameters instead of
// re-deriving per surface:
//
//   escapeAngleAmp — also escape `<` `>` `&` as \uXXXX. mcp's output never lands inside HTML/XML
//     markup (it's a JSON-RPC stdio protocol), so it skips this. ccjson's cc.json can be consumed
//     by tooling that re-embeds it in a page, and htmlexport's JSON is emitted literally inside an
//     inline <script> block where a bare `</script` would terminate the element early — both need
//     the hardening. Reason held on inspection; kept as a flag rather than dropped.
//
//   validateUtf8 — scrub invalid UTF-8 (bad lead byte, bad continuation, overlong, surrogate,
//     >U+10FFFF) to U+FFFD instead of passing raw bytes (A4-F20: source files can contain
//     arbitrary/Latin-1 bytes; one such byte in a non-validating escaper corrupts the whole
//     JSON-RPC/JSON-export response into invalid UTF-8 for a strict client parser). mcp.h and
//     ccjson.h already validate; htmlexport.h's escaper now validates too (follow-up fix: it
//     used to pass bytes ≥0x80 through raw, byte-for-byte — the same gap class A4-F20 named for
//     ccjson). Fixed by flipping `validateUtf8=true` for htmlexport's escapeHtml() below; this
//     CHANGES emitted bytes only for invalid-UTF-8 source files (a deliberate correctness fix,
//     not a no-op) — valid-UTF-8 input is byte-identical to before.
//
//   replacementAsTextEscape — how an invalid sequence is represented once validateUtf8 scrubs it.
//     mcp.h emits the raw 3-byte UTF-8 encoding of U+FFFD ("\xEF\xBF\xBD") straight into the JSON
//     string body (legal: U+FFFD is not a control character, needs no escape). ccjson.h instead
//     emits the 6-character JSON unicode-escape SEQUENCE "�" (backslash-u-f-f-f-d as literal
//     text). Both decode to the same character under any JSON parser, but the raw bytes differ —
//     preserved as a flag so unifying the core doesn't change either surface's byte output.
//
// Every existing call site keeps its original name/signature (mcpdetail::jsonEscape,
// rw::jsonEscape, rw::ccJsonEscape) — only their bodies now forward into escapeInto() here, so
// this header is a pure internal refactor: verified byte-identical against the pre-unification
// implementations.

#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>

namespace rw
{
namespace jsonesc
{

// Length (1-4) of the well-formed UTF-8 sequence starting at s[i], or 0 when the bytes are NOT
// valid UTF-8 (bad continuation, overlong encoding, surrogate half, or truncated at end-of-buffer).
// Pure, allocation-free, locale-independent — the single source of truth both validating escapers
// (mcp/ccjson) now share; previously duplicated as mcp.h's inline check and ccjson.h's ccUtf8SeqLen.
inline int utf8SeqLen( const char* s, std::size_t i, std::size_t n ) noexcept
{
    const unsigned char c = static_cast<unsigned char>( s[i] );
    if( c < 0x80 )
    {
        return 1;
    }
    const auto cont = [ & ]( std::size_t k ) noexcept
    { return k < n && ( static_cast<unsigned char>( s[k] ) & 0xC0 ) == 0x80; };
    if( ( c & 0xE0 ) == 0xC0 )
    {
        return ( c >= 0xC2 && cont( i + 1 ) ) ? 2 : 0;
    }
    if( ( c & 0xF0 ) == 0xE0 )
    {
        if( !cont( i + 1 ) || !cont( i + 2 ) )
        {
            return 0;
        }
        const unsigned char c1 = static_cast<unsigned char>( s[i + 1] );
        if( c == 0xE0 && c1 < 0xA0 )
        {
            return 0;
        }
        if( c == 0xED && c1 >= 0xA0 )
        {
            return 0;
        }
        return 3;
    }
    if( ( c & 0xF8 ) == 0xF0 && c <= 0xF4 )
    {
        if( !cont( i + 1 ) || !cont( i + 2 ) || !cont( i + 3 ) )
        {
            return 0;
        }
        const unsigned char c1 = static_cast<unsigned char>( s[i + 1] );
        if( c == 0xF0 && c1 < 0x90 )
        {
            return 0;
        }
        if( c == 0xF4 && c1 >= 0x90 )
        {
            return 0;
        }
        return 4;
    }
    return 0;
}

// Canonical escape core. Appends the escaped form of `s` to `out` (never returns by value — every
// call site controls its own allocation/reuse, matching ccjson's reused-scratch-buffer posture).
// Escapes `"` `\` and the C0 controls (\n \r \t as short forms, everything else as \u00XX) always;
// `<` `>` `&` and invalid-UTF-8 handling are parameterized per the divergence rationale above.
//
// ─── §B12.7: the C0 DIALECT DIVERGENCE, and why this side is deliberately NOT changed ──────────────────
//
// The two dialects do not agree about C0 controls, and cannot. XML 1.0 forbids the C0 set even ESCAPED
// (only \t \n \r are legal Chars), so serialize.h's xmlSafeByte MUST substitute a space; JSON has \uXXXX
// for every one of them, so this escaper round-trips them all. Measured on `--for=$'a\x0bb\x0cc\td\x01e'`:
//
//     XML  (CLI and MCP)  <ctx task="a b c&#9;d e">      VT, FF and 0x01 -> space; TAB survives as &#9;
//     JSON (CLI --json)   "task":"abc\tde"   every byte preserved
//
// So `<ctx task=…>`, whose entire §B1.7 point is being the VERBATIM copy of the user's task, is silently
// not verbatim — while the JSON twin of the same field is. `\t \n \r` round-trip correctly on both, so the
// divergence is exactly the other C0s.
//
// This escaper is the FAITHFUL side, and it stays faithful. Normalizing here to match XML would make the
// two dialects agree by making both lossy — deleting real bytes out of the machine-readable dialect to
// match a restriction the other dialect is under, on the one surface a consumer can actually recover the
// original from. The honest fix is a TELL on the XML side (the lossy side discloses that it substituted),
// which lives in serialize.h and belongs to the lane that owns it; recorded here so the next reader of THIS
// file knows the asymmetry is a decision rather than an oversight, and does not "fix" it by degrading JSON.
inline void escapeInto( std::string_view s, std::string& out,
                         bool escapeAngleAmp, bool validateUtf8, bool replacementAsTextEscape )
{
    const char*       d = s.data();
    const std::size_t n = s.size();
    std::size_t       i = 0;
    while( i < n )
    {
        const unsigned char c = static_cast<unsigned char>( d[i] );

        if( c < 0x80 )
        {
            switch( c )
            {
                case '"':  out += "\\\""; ++i; continue;
                case '\\': out += "\\\\"; ++i; continue;
                case '\n': out += "\\n";  ++i; continue;
                case '\r': out += "\\r";  ++i; continue;
                case '\t': out += "\\t";  ++i; continue;
                case '<':  if( escapeAngleAmp ) { out += "\\u003c"; ++i; continue; } break;
                case '>':  if( escapeAngleAmp ) { out += "\\u003e"; ++i; continue; } break;
                case '&':  if( escapeAngleAmp ) { out += "\\u0026"; ++i; continue; } break;
                default: break;
            }
            if( c < 0x20 )
            { char b[ 8 ]; std::snprintf( b, sizeof( b ), "\\u%04x", unsigned( c ) ); out += b; }
            else
            {
                out += char( c );
            }
            ++i;
            continue;
        }

        // c >= 0x80: a UTF-8 continuation/lead byte.
        if( !validateUtf8 ) { out += char( c ); ++i; continue; }   // raw passthrough (htmlexport posture)

        const int len = utf8SeqLen( d, i, n );
        if( len == 0 )
        {
            if( replacementAsTextEscape )
            {
                out += "\\ufffd"; // ccjson posture: literal escape text
            }
            else
            {
                out += "\xEF\xBF\xBD"; // mcp posture: raw U+FFFD bytes
            }
            ++i;
        }
        else { out.append( d + i, std::size_t( len ) ); i += std::size_t( len ); }
    }
}

// ── per-surface wrappers, one per existing call-site signature ──────────────────────────────

// mcp.h's mcpdetail::jsonEscape posture: no <>& hardening (stdio JSON-RPC, never re-embedded in
// markup), UTF-8-validated with raw U+FFFD bytes on scrub. std::string_view (not `const std::string&`)
// so every call site — a std::string, a std::string_view, or a `const char*` — binds without a temporary;
// L2's --json output (serialize.h rw::jsonStr) reuses this exact posture for its CLI-stdout stream (never
// re-embedded in HTML/markup, same as MCP's stdio JSON-RPC) instead of hand-rolling a near-clone.
inline std::string escapeMcp( std::string_view in )
{
    std::string out;
    out.reserve( in.size() + 16 );
    escapeInto( in, out, /*escapeAngleAmp=*/false, /*validateUtf8=*/true, /*replacementAsTextEscape=*/false );
    return out;
}

// htmlexport.h's jsonEscape posture: <>& hardened (JSON literal inside an inline <script> block —
// a bare "</script" must never appear), UTF-8-validated (invalid sequences scrub to raw U+FFFD
// bytes — same replacement posture as escapeMcp above, matching the "JSON literal, not re-escaped
// text" surface: htmlexport's page is a single self-contained HTML file, not JSON-RPC, so there is
// no downstream JSON-text-escape convention to match the way ccjson's does).
inline std::string escapeHtml( std::string_view s )
{
    std::string out;
    out.reserve( s.size() + 8 );
    escapeInto( s, out, /*escapeAngleAmp=*/true, /*validateUtf8=*/true, /*replacementAsTextEscape=*/false );
    return out;
}

// ccjson.h's ccJsonEscape posture: <>& hardened (defensive against the metrics blob landing in an
// HTML <script>), UTF-8-validated with the textual "�" escape sequence on scrub. Appends to
// `out` (ccjson.h reuses one scratch string across the whole emit).
inline void escapeCc( std::string_view s, std::string& out )
{
    escapeInto( s, out, /*escapeAngleAmp=*/true, /*validateUtf8=*/true, /*replacementAsTextEscape=*/true );
}

}   // namespace jsonesc

// ── jsonStringEnd / isJsonWs — the canonical JSON SCAN primitives ───────────────────────────────
//
// W2-M0: the escape-aware "where does this JSON string end" walk had two homes with two different
// return conventions — mcpdetail::stringEnd (mcpjson.h, which W1 had already collapsed from four
// inline copies) and minedjson::skipString (eval.h). --quality-delta's duplication kind flagged the
// pair, and the honest fix is here rather than in either caller: this header's own charter is to be
// the shared home for exactly this — the lightest header any surface can pull in (zero project
// includes), already the home of the escape core and shSingleQuote. Net repo count goes 4 inline
// copies (pre-W1) → 2 named clones (post-W1) → 1 core with two thin wrappers.
//
// The two return conventions are PRESERVED at their call sites, not unified: mcpdetail::stringEnd
// must distinguish "unterminated" (npos) because it IS §H3's truncation detector for the framing
// gate, while minedjson::skipString clamps to size() because its caller resumes scanning a
// deliberately narrow fixture line. Collapsing them into one convention would have made one of the
// two callers wrong; the WALK is what was duplicated, so the walk is what is shared.
//
// Returns the index of the CLOSING quote, or npos when the string is UNTERMINATED. `quotePos` is the
// index of the OPENING quote (not validated here — each wrapper states its own precondition). A `\"`
// never ends the string; a trailing backslash with nothing after it steps ONE byte, so the scan can
// never read past the end.
inline std::size_t jsonStringEnd( std::string_view s, std::size_t quotePos ) noexcept
{
    std::size_t q = quotePos + 1;
    while( q < s.size() && s[q] != '"' )
    {
        q += ( s[q] == '\\' && q + 1 < s.size() ) ? 2 : 1;
    }
    return q < s.size() ? q : std::string_view::npos;
}

// The JSON whitespace set, RFC 8259 §2 exactly (space, tab, LF, CR — and nothing else: JSON does not
// treat VT/FF/NBSP as whitespace, which is why this cannot be std::isspace). Was spelled out three
// times in mcpjson.h — twice as an `isWs` lambda and once negated inline in the bare-token terminator
// scan; all three agreed, so this is a clone family folded, not a bug fixed.
inline bool isJsonWs( char c ) noexcept
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

// ── shSingleQuote — A4-F27 residual: canonical shell single-quoting ─────────────────────────────
//
// Was duplicated as rw::shSingleQuote (gitmine.h) and docparse::detail::shellQuote (docparse.h) —
// byte-identical bodies (0.87-similar per --clones), security-relevant duplication: a quoting-bug
// fix in one wouldn't reach the other. Homed here, not in gitmine.h or docparse.h, because jsonesc.h
// is the lightest header both can include without a coupling cost: gitmine.h already pulls model.h +
// graph.h + Diagnostics.h (heavy, ingest-graph dependency chain), while docparse.h is deliberately
// STL-only (Diagnostics.h) so ingest.cpp's doc-parsing path stays decoupled from the graph. jsonesc.h
// has zero project includes beyond <cstdint>/<cstdio>/<string>/<string_view>, so either side can pull
// it in for free. gitmine.h's rw::shSingleQuote is the more widely used name (main.cpp, prcontext.h,
// quality.h, mcp server) — kept as the canonical spelling; docparse.h's detail::shellQuote now
// forwards here instead of carrying its own copy.
inline std::string shSingleQuote( const std::string& s )
{
    std::string out = "'";
    for( char c : s )
    {
        if( c == '\'' ) { out += "'\\''"; }
        else
        {
            out += c;
        }
    }
    out += "'";
    return out;
}

}   // namespace rw
