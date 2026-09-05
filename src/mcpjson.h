#pragma once

// mcpjson.h — JSON-RPC 2.0 protocol layer for --mcp. Hand-rolled minimal JSON
// parse/escape helpers (sufficient for these well-formed shapes) — no JSON library dependency.
// Extracted from mcp.h (the mcp.h/main.cpp concern-split): the pure protocol layer, no index
// dependency. Included by mcpindex.h (and thus by mcpverbs.h / mcpedit.h / mcp.h).

#include "infra/jsonesc.h"        // A4-F27: canonical JSON escape core; mcpdetail::jsonEscape below is a thin wrapper

#include <cctype>
#include <cstdint>
#include <cstdlib>          // std::strtod — findRawId's clean-number validation
#include <cstring>
#include <limits>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

namespace mcpdetail
{
    // 4 hex digits at s[p..p+3] → v; false if out of bounds or not hex.
    inline bool hex4( const std::string& s, std::size_t p, std::uint32_t& v )
    {
        if( p + 4 > s.size() )
        {
            return false;
        }
        v = 0;
        for( std::size_t i = 0; i < 4; ++i )
        {
            const char c = s[ p + i ];
            v <<= 4;
            if( c >= '0' && c <= '9' )
            {
                v |= std::uint32_t( c - '0' );
            }
            else if( c >= 'a' && c <= 'f' )
            {
                v |= std::uint32_t( c - 'a' + 10 );
            }
            else if( c >= 'A' && c <= 'F' )
            {
                v |= std::uint32_t( c - 'A' + 10 );
            }
            else
            {
                return false;
            }
        }
        return true;
    }

    // codepoint → UTF-8 bytes appended to out (cp must be a valid scalar value; callers map bad input to U+FFFD first).
    inline void appendUtf8( std::string& out, std::uint32_t cp )
    {
        if( cp < 0x80 )
        {
            out += char( cp );
        }
        else if( cp < 0x800 )
        { out += char( 0xC0 | ( cp >> 6 ) );  out += char( 0x80 | ( cp & 0x3F ) ); }
        else if( cp < 0x10000 )
        { out += char( 0xE0 | ( cp >> 12 ) ); out += char( 0x80 | ( ( cp >> 6 ) & 0x3F ) );  out += char( 0x80 | ( cp & 0x3F ) ); }
        else
        { out += char( 0xF0 | ( cp >> 18 ) ); out += char( 0x80 | ( ( cp >> 12 ) & 0x3F ) ); out += char( 0x80 | ( ( cp >> 6 ) & 0x3F ) ); out += char( 0x80 | ( cp & 0x3F ) ); }
    }

    // ─── the ONE string walk: where does the JSON string opening at s[quotePos] END? ─────────────────────
    //
    // Four scans in this file skipped string interiors so a `{`/`}`/`:`/`"` inside a VALUE could not miscount
    // (forEachTopLevelKey, containerSpanAt, arrayObjects, findRawId), and each spelled the same two-line
    // escape-aware loop out again — a Type-2 clone family sitting on the scan that decides what every request
    // MEANS, which is the worst possible place for four copies to drift. §H3's framing gate needed a fifth, so
    // the walk is this function and the five callers share it.
    //
    // Returns the index of the CLOSING quote, or npos when the string is UNTERMINATED (which is what makes it
    // the framing gate's truncation detector too). A `\"` never ends the string; a trailing backslash with
    // nothing after it steps ONE byte, so the scan can never read past the end.
    //
    // W2-M0: the walk itself now lives in jsonesc.h as rw::jsonStringEnd — eval.h's minedjson::skipString was
    // the same walk with a different return convention, and this header is not a home a doc/eval reader can
    // pull in. THIS name, signature and npos convention are unchanged; only the body forwards.
    inline std::size_t stringEnd( const std::string& s, std::size_t quotePos ) noexcept
    {
        return jsonStringEnd( s, quotePos );
    }

    // ─── W3FIX H3: WHERE a key may be matched — object-KEY position, TOP LEVEL of the span ───────────────
    //
    // Every lookup in this file used to be `s.find( "\"key\"" )` followed by `s.find( ':', … )`: a scan that
    // cannot tell an object KEY from a string VALUE that happens to spell the key, and that then searches
    // FORWARD for a colon across whatever lies between the two. One scan, two shipped bugs:
    //
    //     grep pattern="limit" offset=2 limit=5   → the pattern's VALUE matched, the NEXT colon was
    //                                               offset's, and the request was answered with limit=2
    //                                               while the disclosure printed limit=2 as if asked.
    //     grep pattern="limit" offset=0           → the same shadow, landing on offset's 0, refused with
    //                                               "invalid value for field: limit … got '0'" — a hard
    //                                               refusal naming a field the caller never sent.
    //
    // This is the ONE seam that fixes them for every consumer (findString / findObject / findArray /
    // arrayStrings / findRawValue / findRawId, and thus mcpIntArg / mcpStringArg / mcpPageArgs and every
    // refusal that echoes a value). It returns the position of the VALUE for `key` when `key` occurs as an
    // object key — a JSON string whose very next non-whitespace byte is ':', which is precisely the
    // discriminator the forward colon search threw away (in valid JSON a string VALUE is never followed by
    // ':') — skipping string interiors escape-aware, and counting container depth so only keys of the
    // OUTERMOST object of `s` match: `{"filter":{"limit":9},"limit":3}` reads 3, and a `limit` buried in a
    // nested object or a `queries` sub-object is not this request's `limit`.
    //
    // TOP-LEVEL-ONLY is the whole rule; there is no any-depth mode. Every caller passes the span whose own
    // keys it means (the request line, the `params` object, the `arguments` object, one batch sub-query
    // object), so "reach through a wrapper" is spelled as two lookups at the call site (see the initialize
    // branch's params-then-line read of protocolVersion) instead of as a flag that every other caller then
    // has to reason about.
    //
    // DUPLICATE KEYS: FIRST-WINS, pinned deliberately. Most JSON parsers are last-wins and this is not,
    // because the value a verb ultimately READS comes from findString/arrayStrings/decodeStringAt — all of
    // which stop at their first key-position match — so validating the LAST occurrence would validate a
    // value the verb never uses: the classic validator/parser split, which is a worse failure than
    // disagreeing with an external convention. One rule for shape-checking and for reading.
    // The scan itself, ONCE. `onKey( keyText, valuePos )` is called for each top-level key in source order and
    // returns true to stop. Two callers need it — "where is key K's value" (findKeyValuePos) and "what keys did
    // this request actually send" (objectKeys, the W3FIX M4 unknown-field check) — and they would otherwise be
    // the Type-2 clone pair --quality-delta exists to catch, on the scan that decides what every request means.
    template<class OnKey>
    inline void forEachTopLevelKey( const std::string& s, std::size_t from, OnKey onKey )
    {
        const auto isWs = []( char c ) { return isJsonWs( c ); };   // W2-M0: RFC 8259 §2, one home (jsonesc.h)

        int depth = 0;
        for( std::size_t p = from; p < s.size(); ++p )
        {
            const char c = s[p];
            if( c == '{' || c == '[' ) { ++depth;  continue; }
            if( c == '}' || c == ']' ) { --depth;  continue; }
            if( c != '"' )
            {
                continue;
            }

            // a JSON string starts here — walk to its closing quote, escape-aware (a `\"` never ends it).
            const std::size_t textStart = p + 1;
            const std::size_t q         = stringEnd( s, p );
            if( q == std::string::npos )
            {
                return; // unterminated string ⇒ nothing past it parses
            }

            // KEY position iff the next non-whitespace byte is ':' — otherwise it is a VALUE or an array element.
            std::size_t colon = q + 1;
            while( colon < s.size() && isWs( s[colon] ) )
            {
                ++colon;
            }
            const bool isKey = ( colon < s.size() && s[colon] == ':' );

            p = isKey ? colon : q;                                        // resume after the ':' / after the closing quote
            if( !isKey )
            {
                continue;
            }
            if( depth != 1 )
            {
                continue; // a nested object's/array's key, not this span's
            }

            std::size_t v = colon + 1;
            while( v < s.size() && isWs( s[v] ) )
            {
                ++v;
            }
            if( onKey( std::string_view( s ).substr( textStart, q - textStart ), v ) )
            {
                return;
            }
        }
    }

    inline std::size_t findKeyValuePos( const std::string& s, std::string_view key, std::size_t from = 0 )
    {
        std::size_t found = std::string::npos;
        forEachTopLevelKey( s, from, [ & ]( std::string_view k, std::size_t valuePos )
                            {
                                if( k != key )
                                {
                                    return false;
                                }
                                found = valuePos < s.size() ? valuePos : std::string::npos;
                                return true;                                                  // FIRST-WINS (see the header above)
                            } );
        return found;
    }

    // Every TOP-LEVEL key of the object span `s`, in source order, duplicates included — the caller decides
    // what a duplicate means. (W3FIX M4: the unknown-argument check needs the keys the request ACTUALLY sent,
    // which is the one question a per-key lookup cannot answer.)
    inline std::vector<std::string> objectKeys( const std::string& s )
    {
        std::vector<std::string> out;
        forEachTopLevelKey( s, 0, [ & ]( std::string_view k, std::size_t )
        {
            out.emplace_back( k );
            return false;
        } );
        return out;
    }

    // The JSON string at s[at] ("" when s[at] is not a string), decoding the FULL escape set
    // (\" \\ \/ \b \f \n \r \t \uXXXX incl. surrogate pairs → UTF-8; a lone surrogate → U+FFFD) —
    // clients that escape non-ASCII must not hand us mangled path/task/pattern args. Split out of
    // findString so a caller that ALREADY located the value (mcpStringArg, which must validate the SHAPE at
    // the same position it decodes) reads the same bytes the plain lookup would, with no second scan.
    inline std::string decodeStringAt( const std::string& s, std::size_t at )
    {
        if( at >= s.size() || s[at] != '"' )
        {
            return {};
        }
        std::size_t p = at + 1;
        std::string out;
        for( ; p < s.size() && s[p] != '"'; ++p )
        {
            // ordinary byte, or a trailing backslash with nothing after it (kept literally — degrade, don't drop)
            if( s[p] != '\\' || p + 1 >= s.size() ) { out += s[p]; continue; }

            ++p;
            switch( s[p] )
            {
                case '"':  out += '"';  break;
                case '\\': out += '\\'; break;
                case '/':  out += '/';  break;
                case 'b':  out += '\b'; break;
                case 'f':  out += '\f'; break;
                case 'n':  out += '\n'; break;
                case 'r':  out += '\r'; break;
                case 't':  out += '\t'; break;
                case 'u':
                {
                    std::uint32_t cp = 0;
                    if( !hex4( s, p + 1, cp ) ) { appendUtf8( out, 0xFFFD ); break; }   // malformed \uXXXX → U+FFFD
                    p += 4;                                                             // p = last hex digit

                    // surrogate handling: a high surrogate must pair with an immediately following \uDC00–\uDFFF;
                    // a lone surrogate (either half) decodes to U+FFFD.
                    if( cp >= 0xD800 && cp <= 0xDBFF )
                    {
                        std::uint32_t lo = 0;
                        if( p + 2 < s.size() && s[ p + 1 ] == '\\' && s[ p + 2 ] == 'u'
                            && hex4( s, p + 3, lo ) && lo >= 0xDC00 && lo <= 0xDFFF )
                        { cp = 0x10000 + ( ( cp - 0xD800 ) << 10 ) + ( lo - 0xDC00 ); p += 6; }
                        else
                        { cp = 0xFFFD; }
                    }
                    else if( cp >= 0xDC00 && cp <= 0xDFFF )
                    { cp = 0xFFFD; }

                    appendUtf8( out, cp );
                    break;
                }
                default:   out += s[p]; break;   // unknown escape: keep the char (lenient)
            }
        }
        return out;
    }

    // value of the  "key": "..."  string at the TOP LEVEL of the object span `s` ("" if absent or not a
    // string). findKeyValuePos owns WHERE, decodeStringAt owns WHAT — this is the two composed, and it is
    // every caller's plain "read this argument as a string" front door.
    inline std::string findString( const std::string& s, const char* key )
    {
        return decodeStringAt( s, findKeyValuePos( s, key ) );
    }

    // W3FIX M5: findInt() lived here and is GONE. Its contract was "a value I cannot parse reads as absent",
    // which stopped at the first non-digit and truncated silently: `start_line:3.9` became 3, `top_k:"1e3"`
    // became 1, `budget_tokens:"1e3"` became 1 — a DIFFERENT question answered confidently under a number the
    // caller never typed. Every one of its call sites now reads through mcpverbs.h's mcpIntArg, which parses
    // the WHOLE token (parseWholeInt, below), checks a declared domain and refuses out of it. Nothing needs a
    // lenient integer read, so there is no lenient integer reader.

    // F9: findObject/findArray were Type-2 clones of each other — same escape-aware depth-tracking scan,
    // different delimiter pair; the scan is now this one core and both are thin key-lookup wrappers over it.
    // The balanced container that STARTS at s[at] (which must be `openCh`) through its matching `closeCh`,
    // tracking depth while SKIPPING string contents (escape-aware, so an openCh/closeCh inside a string value
    // never miscounts). Returns the inclusive [at..closeCh] span, or "" when s[at] is not that container
    // shape or the container is unterminated. Never throws. (A3-F6 / A4-R3.)
    inline std::string containerSpanAt( const std::string& s, std::size_t at, char openCh, char closeCh )
    {
        if( at >= s.size() || s[at] != openCh )
        {
            return {}; // not this container shape
        }

        int depth = 0;
        for( std::size_t p = at; p < s.size(); ++p )
        {
            const char c = s[p];
            if( c == '"' )                                              // skip the string interior via the ONE walk
            {
                const std::size_t close = stringEnd( s, p );
                if( close == std::string::npos )
                {
                    return {}; // unterminated string ⇒ unterminated container
                }
                p = close;
                continue;
            }
            if( c == openCh )
            {
                ++depth;
            }
            else if( c == closeCh )
            {
                --depth;
                if( depth == 0 )
                {
                    return s.substr( at, p - at + 1 ); // inclusive of the closing delimiter
                }
            }
        }
        return {};                                                       // unterminated container
    }

    // The JSON OBJECT value at the top-level key `"<key>"` of `s`, or "" when that key is absent / not an
    // object. (`from` skips a prefix of the span — the scan still only accepts keys of the span's own
    // outermost object.)
    inline std::string findObject( const std::string& s, const char* key, std::size_t from = 0, char openCh = '{', char closeCh = '}' )
    {
        return containerSpanAt( s, findKeyValuePos( s, key, from ), openCh, closeCh );
    }

    // A4-R3: the JSON ARRAY value at `"<key>":` (see findObject above — same core, array delimiter pair).
    // (batch verb: the `queries` array of sub-query objects.)
    inline std::string findArray( const std::string& s, const char* key, std::size_t from = 0 )
    {
        return findObject( s, key, from, '[', ']' );
    }

    // Every "…" STRING element of the JSON array at `"<key>"`, in order; empties skipped, escape-aware (a
    // `\"` inside an element never ends it early). dispatchMcpLine spelled this scan out TWICE — once for the
    // multi-root `paths` array and once for `connect`'s `symbols` array — byte-for-byte the same loop with a
    // different output vector, i.e. exactly the clone pair --quality-delta exists to catch, sitting on the two
    // arguments that decide WHICH TREE a request answers about and WHICH SYMBOLS it connects. One scan now.
    inline std::vector<std::string> arrayStrings( const std::string& s, const char* key )
    {
        const std::string        arr = findArray( s, key );
        std::vector<std::string> out;
        bool                     inStr = false;
        std::string              cur;
        for( std::size_t p = 0; p < arr.size(); ++p )
        {
            const char ch = arr[p];
            if( !inStr )
            {
                if( ch == '"' )
                {
                    inStr = true;
                }
                continue;
            }
            if( ch == '\\' && p + 1 < arr.size() ) { cur.push_back( arr[ ++p ] ); continue; }
            if( ch == '"' )
            {
                inStr = false;
                if( !cur.empty() )
                {
                    out.push_back( cur );
                }
                cur.clear();
                continue;
            }
            cur.push_back( ch );
        }
        return out;
    }

    // A4-R3: every TOP-LEVEL '{…}' object element inside an array span (the substring INCLUDING the outer
    // '[' ']'), in order. Escape-aware string skip + brace-depth tracking, so nested objects/arrays inside an
    // element belong to that element (findString on the element still finds its own keys). Non-object elements
    // (bare numbers/strings/nulls) are skipped — a hostile `queries:[1,"x",{…}]` yields only the real object.
    // Never throws; bounded by the input size. Caller caps the count it actually processes.
    inline std::vector<std::string> arrayObjects( const std::string& arr )
    {
        std::vector<std::string> out;
        int         objDepth = 0;
        std::size_t objStart = 0;
        for( std::size_t p = 0; p < arr.size(); ++p )
        {
            const char c = arr[p];
            if( c == '"' )                                              // skip the string interior via the ONE walk
            {
                const std::size_t close = stringEnd( arr, p );
                if( close == std::string::npos )
                {
                    break; // unterminated element string ⇒ nothing past it parses
                }
                p = close;
                continue;
            }
            if( c == '{' )
            {
                if( objDepth == 0 )
                {
                    objStart = p;
                }
                ++objDepth;
            }
            else if( c == '}' && objDepth > 0 )
            {
                --objDepth;
                if( objDepth == 0 )
                {
                    out.push_back( arr.substr( objStart, p - objStart + 1 ) );
                }
            }
        }
        return out;
    }

    // F8 (capture-audit verify-wave2 2026-09-05): the array's TOP-LEVEL elements, raw and untrimmed of their
    // own structure — the one thing neither arrayObjects (which finds every brace-balanced object at any
    // nesting) nor arrayStrings (which finds every quoted string, INCLUDING the keys and values inside those
    // objects) can answer. Both were sound for their own callers and neither could tell a MIXED array from a
    // uniform one: an all-object `[{"verb":"callers","symbol":"escapeXml"}]` yields four "strings" to
    // arrayStrings, so a mixed-array check built on it refuses every object array. Depth-aware, string-aware,
    // and it classifies nothing — the caller reads the first byte of each element and decides.
    inline std::vector<std::string> arrayTopLevelElements( const std::string& arr )
    {
        std::vector<std::string> out;
        // The span a caller hands us includes its own brackets. Enter the container first, or every element
        // sits at depth 1 and the scan finds no top-level comma at all (measured: a mixed array read as zero
        // elements, i.e. the check silently never fired).
        std::size_t first = arr.find_first_not_of( " \t\n\r" );
        std::size_t begin = ( first != std::string::npos && arr[ first ] == '[' ) ? first + 1 : 0;
        int         depth = 0;
        std::size_t start = std::string::npos;
        const auto  flush = [ & ]( std::size_t end )
        {
            if( start == std::string::npos ) { return; }
            std::string_view e( arr.data() + start, end - start );
            while( !e.empty() && ( e.back() == ' ' || e.back() == '\t' || e.back() == '\n' || e.back() == '\r' ) )
            {
                e.remove_suffix( 1 );
            }
            if( !e.empty() ) { out.emplace_back( e ); }
            start = std::string::npos;
        };
        for( std::size_t p = begin; p < arr.size(); ++p )
        {
            const char c = arr[p];
            if( c == ']' && depth == 0 )
            {
                break;   // the container's own close — anything after it is not an element
            }
            if( c == '"' )
            {
                if( depth == 0 && start == std::string::npos ) { start = p; }
                const std::size_t close = stringEnd( arr, p );
                if( close == std::string::npos ) { break; }   // unterminated ⇒ nothing past it parses
                p = close;
                continue;
            }
            if( c == '{' || c == '[' )
            {
                if( depth == 0 && start == std::string::npos ) { start = p; }
                ++depth;
                continue;
            }
            if( c == '}' || c == ']' )
            {
                if( depth > 0 ) { --depth; }
                continue;
            }
            if( depth == 0 && c == ',' )
            {
                flush( p );
                continue;
            }
            if( depth == 0 && start == std::string::npos && c != ' ' && c != '\t' && c != '\n' && c != '\r' )
            {
                start = p;
            }
        }
        flush( arr.size() );
        return out;
    }

    // ─── §H3: the FRAMING gate — is this frame ONE COMPLETE JSON-RPC request object? ──────────────────────
    //
    // THE INCIDENT. Nothing sat between the stdio read loop (mcp.h's readByteSafeLine) and the key-position
    // scanner above, and that scanner reads a COMPLETE `params` out of a TRUNCATED envelope — so a frame that
    // was cut off mid-write was DISPATCHED as if it were whole:
    //
    //   • a truncated `replace_symbol_body` frame (no closing brace) REWROTE THE FILE and the session carried
    //     on — the one class of request where "answer what we could parse" is a write, not a wrong answer;
    //   • `{"jsonrpc":"2.0","id":816,"method":"tools/list"`  (no closing brace) returned a full, successful
    //     tool listing, indistinguishable from a well-formed call;
    //   • a truncated tail at EOF was refused with a FALSE CAUSE ("missing required field: path" for a request
    //     whose `path` was in the bytes, just past the cut).
    //
    // The HTTP transport was immune by accident (a Content-Length-short body never reaches dispatch,
    // mcpserver.h), and stdio is the transport `ripwire wrap claude` ships AND the one where the edit verbs
    // are enabled — so the gate lives in the SHARED handler (dispatchMcpLine), not in the stdio loop, and both
    // transports get the same verdict for the same bytes.
    //
    // WHAT THIS IS NOT. It is not a JSON parser and does not replace one: the key-position scanners above stay
    // exactly as they are. It answers the one structural question they cannot — "could these bytes possibly be
    // a whole request?" — by balancing containers OUTSIDE strings with the shared string walk, on a stack so a
    // closer must match its own opener, and requiring the first complete value to be the LAST thing on the
    // frame. Everything it accepts is dispatched exactly as before; what it rejects could not have been
    // answered honestly.
    enum class FrameShape : std::uint8_t
    {
        Object     = 0,   // exactly one complete '{…}' object, nothing after it but whitespace — DISPATCH
        Blank      = 1,   // whitespace only (the stdio loop skips these itself; an empty HTTP body lands here)
        Incomplete = 2,   // §H3: cut off — a container or a string never closed
        Mismatched = 3,   // a closer that does not match its opener (`{"a":[1}`) — invalid JSON, not truncation
        BatchArray = 4,   // §B6 M6: a top-level '[…]' JSON-RPC batch — refused explicitly, never half-answered
        NotObject  = 5,   // a complete JSON value that is not an object (`5`, `"x"`, `true`, plain garbage)
        Trailing   = 6,   // §B6 M8: a SECOND value on the same frame — only the first was ever answered
    };

    // The offending bytes travel with the verdict so the refusal can ECHO them (mcprefusal.h caps the echo).
    // Bounded at capture: a hostile 8 MB frame must not mint an 8 MB copy on the path a hostile frame takes.
    inline constexpr std::size_t kFrameEchoCaptureBytes = 240;   // > mcprefusal.h's kMcpEchoMaxBytes, so the cap still shows

    struct FrameCheck
    {
        FrameShape  shape = FrameShape::Object;
        std::string got;                              // the trailing bytes / the value as typed; "" when there is nothing to show
    };

    inline FrameCheck checkFrame( const std::string& s )
    {
        const auto isWs = []( char c ) { return isJsonWs( c ); };   // W2-M0: RFC 8259 §2, one home (jsonesc.h)

        std::size_t start = 0;
        while( start < s.size() && isWs( s[start] ) )
        {
            ++start;
        }
        if( start >= s.size() )
        {
            return { FrameShape::Blank, {} };
        }

        const bool isArrayFrame = s[start] == '[';
        if( s[start] != '{' && !isArrayFrame )
        {
            return { FrameShape::NotObject, s.substr( start, kFrameEchoCaptureBytes ) };
        }

        // ONE pass. `openers` is the stack of containers still waiting for their closer — its SIZE is the depth,
        // and its BACK is what the next closer must match. Empty again ⇒ the first top-level value ended here.
        std::string openers;
        std::size_t endIndex = std::string::npos;
        for( std::size_t p = start; p < s.size(); ++p )
        {
            const char c = s[p];
            if( c == '"' )
            {
                const std::size_t close = stringEnd( s, p );
                if( close == std::string::npos )
                {
                    return { FrameShape::Incomplete, {} }; // string never closed
                }
                p = close;
                continue;
            }
            if( c == '{' || c == '[' ) { openers.push_back( c );  continue; }
            if( c != '}' && c != ']' )
            {
                continue;
            }
            // a closer with NO opener is unreachable by construction (the first byte pushed one, and the loop
            // breaks the moment the stack empties) — but this is untrusted input and an empty-stack back() would
            // be UB, so the impossible case is spelled as the truthful verdict rather than assumed away.
            if( openers.empty() || openers.back() != ( c == '}' ? '{' : '[' ) )
            {
                return { FrameShape::Mismatched, {} };
            }
            openers.pop_back();
            if( openers.empty() ) { endIndex = p;  break; }
        }
        if( endIndex == std::string::npos )
        {
            return { FrameShape::Incomplete, {} }; // container never closed
        }

        std::size_t after = endIndex + 1;
        while( after < s.size() && isWs( s[after] ) )
        {
            ++after;
        }
        if( after < s.size() )
        {
            return { FrameShape::Trailing, s.substr( after, kFrameEchoCaptureBytes ) };
        }

        return { isArrayFrame ? FrameShape::BatchArray : FrameShape::Object, {} };
    }

    // ─── verifier N2/N3/N11: the RAW value of an argument ────────────────────────────────────────────────
    //
    // findInt() and findString() both collapse "the key is absent" and "the key is present but not the shape
    // I read" onto the SAME answer ({0,false} / ""), which is precisely how three accept-and-ignore bugs got
    // in: `limit:"abc"` and `offset:-2` read as absent (so the verb served its default and never said why),
    // `limit:3.9` was truncated to 3, and `files:["a","b"]` on situational_awareness read as absent so the
    // verb answered about `git diff` and reported a clean working tree with full confidence.
    //
    // This returns the bytes the caller actually TYPED plus the two bits that separate the cases, so a
    // refusal can echo the value the way every CLI refusal has since §A10.2. It reads the value SHAPE only —
    // no validation lives here; mcpverbs.h's mcpIntArg/mcpStringArg own the domains, and mcprefusal.h owns
    // the wording.
    struct RawValue
    {
        std::string text;                          // the value verbatim: a string's CONTENTS, else the bare token / container span
        bool        isPresent = false;             // the key exists in this scope and carries a value
        bool        isQuoted  = false;             // it was a JSON string, not a bare token / array / object
        bool        isArray   = false;             // it was a JSON '[…]' array (M8: array-shaped fields need this half)
        std::size_t valuePos  = std::string::npos; // where the value starts — so a caller that DECODES it (mcpStringArg)
                                                   // reads the same occurrence this shape check accepted
    };

    // W3FIX H3: the lookup is findKeyValuePos — an object-KEY match at the TOP LEVEL of `s`, so an argument
    // VALUE that spells a key name can no longer shadow the real one (see that function's header for the two
    // bugs this closes and for the first-wins duplicate-key pin).
    inline RawValue findRawValue( const std::string& s, const char* key )
    {
        const std::size_t p = findKeyValuePos( s, key );
        if( p == std::string::npos )
        {
            return {};
        }

        // a STRING value: escape-aware scan to the closing quote (a `\"` inside never ends it early).
        if( s[p] == '"' )
        {
            RawValue out;
            out.isPresent = true;
            out.isQuoted  = true;
            out.valuePos  = p;
            for( std::size_t q = p + 1; q < s.size(); ++q )
            {
                if( s[q] == '\\' && q + 1 < s.size() ) { out.text.push_back( s[++q] ); continue; }
                if( s[q] == '"' )
                {
                    break;
                }
                out.text.push_back( s[q] );
            }
            return out;
        }

        // a CONTAINER value: the whole span, so an echo shows the array the caller passed, not its first element.
        if( s[p] == '[' )
        {
            return { containerSpanAt( s, p, '[', ']' ), true, false, true, p };
        }
        if( s[p] == '{' )
        {
            return { containerSpanAt( s, p, '{', '}' ), true, false, false, p };
        }

        // a BARE token (number / true / false / null): up to the element or container terminator.
        std::size_t       q     = p;
        while( q < s.size() && s[q] != ',' && s[q] != '}' && s[q] != ']' && !isJsonWs( s[q] ) )
        {
            ++q; // W2-M0
        }
        if( q == p )
        {
            return {};
        }
        return { s.substr( p, q - p ), true, false, false, p };
    }

    // Parse an ENTIRE token as a signed integer — no trailing bytes, no truncation at a '.', no overflow.
    // This is the CLI's parsePosInt contract (cli.h) restated for a JSON argument value, and the "entire" is
    // the whole point: findInt() stops at the first non-digit, so `3.9` became 3 and `12abc` became 12 —
    // answering a DIFFERENT question than the one asked, silently, which is the accept-and-ignore class
    // wearing a plausible number. Returns false for an empty token, a lone sign, junk, or overflow.
    inline bool parseWholeInt( std::string_view token, long long& out ) noexcept
    {
        if( token.empty() )
        {
            return false;
        }
        std::size_t i = 0;
        const bool  isNeg = token[0] == '-';
        if( isNeg || token[0] == '+' )
        {
            ++i;
        }
        if( i >= token.size() )
        {
            return false;
        }

        long long v = 0;
        for( ; i < token.size(); ++i )
        {
            if( token[i] < '0' || token[i] > '9' )
            {
                return false; // '.', 'e', a unit suffix — not an integer
            }
            const int d = token[i] - '0';
            if( v > ( std::numeric_limits<long long>::max() - d ) / 10 )
            {
                return false; // overflow ⇒ refuse, never wrap
            }
            v = v * 10 + d;
        }
        out = isNeg ? -v : v;
        return true;
    }

    // A3-F6 established WHICH SUBSTRING per-argument key lookups may scan: the request's `params` span, so an
    // envelope-level string value equal to a key literal (id:"path") can never shadow a real argument, and —
    // since spec-conforming clients nest arguments under `params.arguments` while some callers flatten them to
    // `params` level — the nested `arguments` object when present, else `params`.
    //
    // §B6 M7: findArgsScope() lived here and is GONE. It composed findObject twice, and findObject answers ""
    // for BOTH "absent" and "present but not an object" — so `arguments:5`, and the common host bug of sending
    // `arguments` as a STRING of JSON, silently fell back to the `params` scope: the caller's `path` was
    // dropped and the verb answered about the default startup root, confidently, about the wrong tree. The
    // scope selection now happens at mcp.h's tools/call branch through mcpverbs.h's mcpObjectArg, which
    // separates absent from wrong-shaped and REFUSES the second — the same seam every other argument reads
    // through. There is no unguarded scope reader, so nothing can inherit the fallback again.

    // findRawId result — presence and value are DISTINCT facts: JSON-RPC 2.0 forbids replying to a
    // NOTIFICATION (no "id" key at all), while a request with a literal id:null still gets a reply
    // (spec-pragmatics: the key was present). The dispatch loop suppresses the response when !hasId.
    struct RawId
    {
        bool        hasId = false;    // false = "id" key absent → the line is a notification
        std::string token = "null";   // validated raw token (number, "string", null) to echo verbatim
    };

    // raw "id" token (number, "string", or null) to echo back verbatim, plus whether the key exists at all.
    //
    // W3FIX H3 (same family, one function away): this used the identical find-the-text-then-find-a-colon scan,
    // so an ARGUMENT whose string value spelled `id` shadowed the envelope's own id and the reply echoed the
    // wrong one — `{"params":{"arguments":{"path":"id","limit":3}},"id":7}` answered with id 3. The lookup is
    // now the shared key-position scan at the TOP LEVEL of the request line, which is where JSON-RPC 2.0 puts
    // `id` by construction, so no value at any nesting depth can be mistaken for it.
    //
    // §B6 M5 — the THIRD property an id must have to be echoable: WELL-FORMED UTF-8. This is the one value in
    // the whole protocol layer that is spliced into the response VERBATIM; every other agent-controlled string
    // goes through jsonEscape, whose own header states the rule this bypassed — ONE invalid byte makes the
    // entire JSON-RPC line invalid UTF-8 and a strict client parser rejects it (reproduced with `\xff\xfe` and
    // the overlong `\xc0\xaf`: json.loads() raises on a response the server called a success). The C0-control
    // and JSON-escape checks were already here; the UTF-8 walk joins them below.
    //
    // FAILURE MODE = the id degrades to `null`, which is (a) exactly what this function already does for every
    // other malformed id (unterminated string, raw control byte, non-JSON escape, junk number), so "this id
    // cannot be echoed" has ONE outcome rather than two, and (b) what JSON-RPC 2.0 requires when the id cannot
    // be determined ("If there was an error in detecting the id ... it MUST be Null"). Escaping the bad bytes
    // instead was rejected: that invents an id the caller never sent and hands it back as if it were theirs.
    inline RawId findRawId( const std::string& s )
    {
        std::size_t p = findKeyValuePos( s, "id" );
        if( p == std::string::npos )
        {
            return {};
        }
        std::size_t e = p;
        if( p < s.size() && s[p] == '"' )
        {
            // the shared escape-aware walk: an escaped \" inside the id must not terminate the token
            // (id "a\"b" would otherwise truncate to `"a\"` and be spliced verbatim into every response).
            const std::size_t close = stringEnd( s, p );
            if( close == std::string::npos )
            {
                return { true, "null" }; // unterminated string id → degrade to null
            }
            e = close + 1;                                             // include the closing quote
        }
        else
        {
            while( e < s.size() && s[e] != ',' && s[e] != '}' && s[e] != ' ' )
            {
                ++e;
            }
        }

        // VALIDATE before the caller echoes it verbatim — a malformed id must never corrupt the response.
        //
        // §B6 M11: `true` and `false` used to be echoed VERBATIM here, and that is not a legal JSON-RPC 2.0
        // id — the spec allows String, Number or Null and nothing else, so the server was emitting an invalid
        // frame in reply to an invalid one. Worse, it was the ONLY invalid-id class that behaved this way:
        // `id:{}` and `id:[]` fall through to the number check below, fail it, and degrade to null. Two
        // invalid-id classes, two different silent behaviours. Both are now the one documented outcome this
        // function's own header specifies — degrade to `null`, which the spec REQUIRES when the id cannot be
        // determined. `null` itself stays echoable: it is a legal id, and the RawId.hasId flag (not the token)
        // is what distinguishes a notification from a request that really sent id:null.
        const std::string tok = s.substr( p, e - p );
        if( tok == "null" )
        {
            return { true, tok };
        }
        if( tok == "true" || tok == "false" )
        {
            return { true, "null" };
        }

        // §B6 M5 (ruling + reproduction in the header above): well-formed UTF-8, or the id is not echoable.
        for( std::size_t i = 0; i < tok.size(); )
        {
            const int len = jsonesc::utf8SeqLen( tok.data(), i, tok.size() );
            if( len == 0 )
            {
                return { true, "null" };
            }
            i += std::size_t( len );
        }

        if( !tok.empty() && tok.front() == '"' )
        {
            if( tok.size() < 2 || tok.back() != '"' )
            {
                return { true, "null" }; // require closing quote
            }
            for( std::size_t i = 1; i + 1 < tok.size(); ++i )                    // interior must stay a sane JSON string
            {
                const unsigned char c = (unsigned char)tok[i];
                if( c < 0x20 )
                {
                    return { true, "null" }; // raw control byte → reject
                }
                if( c != '\\' )
                {
                    continue;
                }
                ++i;
                if( i + 1 >= tok.size() )
                {
                    return { true, "null" }; // backslash right before the closing quote
                }
                const char esc = tok[i];
                if( esc == 'u' )
                {
                    std::uint32_t v = 0;
                    if( !hex4( tok, i + 1, v ) )
                    {
                        return { true, "null" };
                    }
                    i += 4;
                }
                else if( esc != '"' && esc != '\\' && esc != '/' && esc != 'b' && esc != 'f' && esc != 'n' && esc != 'r' && esc != 't' )
                { return { true, "null" }; }                                     // not a JSON escape → reject
            }
            return { true, tok };
        }
        char* endp = nullptr;
        std::strtod( tok.c_str(), &endp );
        if( !tok.empty() && endp == tok.c_str() + tok.size() )
        {
            return { true, tok }; // a clean JSON number
        }
        return { true, "null" };
    }

    // escape a string for splicing into a JSON response. Also VALIDATES UTF-8 in the same single pass:
    // source files can contain Latin-1 / arbitrary bytes, and ONE such byte would make the whole JSON-RPC
    // response line invalid UTF-8 (client parsers reject it) — every invalid sequence (bad lead byte, bad
    // continuation, overlong, surrogate, > U+10FFFF) becomes U+FFFD and the scan resyncs at the next byte.
    //
    // A4-F27: thin wrapper over the canonical core in jsonesc.h (jsonesc::escapeMcp) — this was the
    // reference implementation the shared core was modeled on (no <>& hardening; raw U+FFFD bytes on
    // scrub, not a textual escape); ccjson.h and htmlexport.h's escapers now delegate to the same core
    // with their own flags. Byte-identical to the pre-unification body.
    inline std::string jsonEscape( const std::string& in )
    {
        return rw::jsonesc::escapeMcp( in );
    }
}   // namespace mcpdetail

}   // namespace rw
