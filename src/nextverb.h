#pragma once
// nextverb.h — P3 (capture-audit 2026-09-04, lane L7): the ONE pasteable follow-up a root carries, next="…".
//
// Lens 8 counted it: of 103 live outputs only five named a follow-up verb (grep's <suggest>, --for's "expand=p:n"
// prose, tree/communities/zoom's drill=, whereis's legend); --callers/--impact/--uses/--edit-check/--quality-delta/
// --test-gate/--safe-delete/--situ handed the agent nothing, so "contract-change → find the sites → open the
// file" was three calls with the middle one guessed. The owner's frame for this lane: an answer should TERMINATE
// the search in one compact shot — so every root in P3's enumeration carries exactly one next= holding a
// pasteable invocation of ≤ kNextAttrMaxBytes: --edit-check contract-change → --uses=SYM; --impact →
// --safe-delete=SYM; a gating --quality-delta row → --expand=FILE:NAME; --test-gate → its first run= command;
// --situ → --test-gate; --from-trace/--run-trace → --slice=@FILE:LINE (the innermost in-corpus frame);
// --callers → --uses=SELECTOR (the @FILE:LINE spelling mirrored); --grep → --at=FILE:LINE of the top hit, or the
// next page under --legend=compact when the answer is capped, or --for=PAT on a zero-hit answer; --for → the
// top-ranked row's --expand=FILE:NAME. Gate: test/nextverbcheck.sh — every next= that starts with `--` is run
// through the argv parser and must exit 0 or 4, never 1; a shell next= (test-gate) must be one of the rows' run=.

#include <cstddef>
#include <string>
#include <string_view>

#include "infra/jsonesc.h"   // utf8SeqLen — the one UTF-8 validator (escapeXml's scrub rule, mirrored here)

namespace rw
{

inline constexpr std::size_t kNextAttrMaxBytes = 120;

// the ONE definition every legend that meets next= splices (legendcoveragecheck: an attribute is defined where
// the reader meets it); the verb-specific reading follows it in the verb's own legend
inline constexpr const char* kNextLegendClause =
    "next= is ONE pasteable follow-up — this tool's flags, or a shell line copied from a run= row — the call that "
    "ends this search; paste it as-is. ";

// attribute-escaped ` next="…"`; empty invocation ⇒ empty string (a root with nothing honest to suggest says nothing)
inline std::string nextAttrXml( std::string_view invocation )
{
    if( invocation.empty() ) { return {}; }
    std::string a;
    a.reserve( invocation.size() + 12 );
    a += " next=\"";
    // serialize.h escapeXml's policy, byte for byte (w3fixbudgetcheck: a --grep pattern with a raw newline / C0 /
    // invalid UTF-8 byte is echoed by grep's next= and MUST NOT reach markup — G4): the five XML escapes, the three
    // legal control bytes as character references, every other C0 byte (and DEL) as '?', invalid UTF-8 as '?'.
    const char*       d = invocation.data();
    const std::size_t n = invocation.size();
    for( std::size_t i = 0; i < n; )
    {
        const char c = d[ i ];
        switch( c )
        {
            case '&':  a += "&amp;";  ++i; break;
            case '<':  a += "&lt;";   ++i; break;
            case '>':  a += "&gt;";   ++i; break;
            case '"':  a += "&quot;"; ++i; break;
            case '\'': a += "&apos;"; ++i; break;
            case '\t': a += "&#9;";   ++i; break;
            case '\n': a += "&#10;";  ++i; break;
            case '\r': a += "&#13;";  ++i; break;
            default:
                if( static_cast<unsigned char>( c ) < 0x20 || c == 0x7f ) { a += '?'; ++i; }
                else if( static_cast<unsigned char>( c ) < 0x80 ) { a += c; ++i; }
                else if( const int len = rw::utf8SeqLen( d, i, n ); len == 0 ) { a += '?'; ++i; }
                else { a.append( d + i, std::size_t( len ) ); i += std::size_t( len ); }
                break;
        }
    }
    a += "\"";
    return a;
}

// the JSON twin: `,"next":"…"` with the JSON escapes a flag value can need
inline std::string nextFieldJson( std::string_view invocation )
{
    if( invocation.empty() ) { return {}; }
    std::string a = ",\"next\":\"";
    for( const char c : invocation )
    {
        switch( c )
        {
            case '"':  a += "\\\""; break;
            case '\\': a += "\\\\"; break;
            case '\n': a += "\\n";  break;
            case '\t': a += "\\t";  break;
            default:
                if( static_cast<unsigned char>( c ) < 0x20 ) { a += ' '; } else { a += c; }
                break;
        }
    }
    a += "\"";
    return a;
}

// `--flag=VALUE`, the value single-quoted when a shell would otherwise split or expand it — so the attribute
// pastes into a terminal or an argv array verbatim (the gate splits it with shlex)
inline std::string nextFlag( std::string_view flag, std::string_view value )
{
    bool plain = !value.empty();
    for( const char c : value )
    {
        if( c == ' ' || c == '\t' || c == '\'' || c == '"' || c == '$' || c == '`' || c == '\\' || c == '|' || c == '&' || c == ';'
            || c == '(' || c == ')' || c == '<' || c == '>' || c == '*' || c == '?' || c == '[' || c == ']' || c == '{' || c == '}' || c == '!' || c == '#' || c == '~' )
        {
            plain = false;
            break;
        }
    }
    std::string out( flag );
    if( plain )
    {
        out.append( value );
        return out;
    }
    out += '\'';
    for( const char c : value )
    {
        if( c == '\'' ) { out += "'\\''"; } else { out += c; }
    }
    out += '\'';
    return out;
}

} // namespace rw
