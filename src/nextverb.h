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
// --callers → --uses=SELECTOR (bare NAME for a narrowed selector with declined calls; otherwise the spelling is mirrored);
// --grep → --at=FILE:LINE of the top hit, or the
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

// attribute-escaped ` next="…"`; empty invocation ⇒ empty string (a root with nothing honest to suggest says nothing).
// `attr` names a SECONDARY listing's own follow-up (cut-fix E: --impact's importers_next=, beside the root's next=),
// escaped by the same policy; the default is the root's one next=.
inline std::string nextAttrXml( std::string_view invocation, std::string_view attr = "next" )
{
    if( invocation.empty() ) { return {}; }
    std::string a;
    a.reserve( invocation.size() + attr.size() + 8 );
    a += ' ';
    a += attr;
    a += "=\"";
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
                else if( const int len = rw::jsonesc::utf8SeqLen( d, i, n ); len == 0 ) { a += '?'; ++i; }
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
    // `~` IS SPECIAL ONLY WORD-INITIALLY, and "the word" is the whole argv element — not the part after `=`.
    // Tilde expansion is defined for a word whose FIRST character is `~` (plus the `~user` form); anywhere
    // else in the word it is an ordinary character. Treating every `~` as special quoted `HEAD~1` — the
    // commonest git revision spelling there is — and this attribute is XML, so the escaper then turned the
    // quotes into entities: `next="--since=&apos;HEAD~1&apos; …"`. A reader pasting that out of a raw document
    // (a captured showcase, a doc, anything not rendered by an XML parser) gets a literal &apos; the shell does
    // not decode, which is the whole job of a pasteable attribute lost on the most ordinary value it carries.
    //
    // `flag.empty()` IS THE WHOLE TEST (CodeRabbit, review of #212). `i == 0` alone asked "is this the first
    // character of the VALUE", and a value is not a word: with a flag, the argv element begins `--exclude=`, so
    // its first character is `-` and no shell expands the tilde — an argument is not an assignment. The guard
    // emitted `--exclude='~tmp'`, which this attribute then rendered `--exclude=&apos;~tmp&apos;`, corrupting
    // the replayed argument to protect against an expansion that cannot happen. Measured: `sh -c 'p ~root'`
    // passes /var/root, `sh -c 'p --exclude=~root'` passes the literal `--exclude=~root`, in sh, bash and zsh
    // alike. When `flag` IS empty the value is the whole word (editplan.h's `git -C <root>`), the tilde really
    // is word-initial, and the quotes are load-bearing — which is why this is a narrowing and not a deletion.
    // test/nextverbcheck.sh arm (9) pins the bare form, and a space-bearing value as the control that quoting
    // still happens where a shell would really act.
    bool plain = !value.empty();
    for( std::size_t i = 0; i < value.size(); ++i )
    {
        const char c = value[i];
        if( c == ' ' || c == '\t' || c == '\'' || c == '"' || c == '$' || c == '`' || c == '\\' || c == '|' || c == '&' || c == ';'
            || c == '(' || c == ')' || c == '<' || c == '>' || c == '*' || c == '?' || c == '[' || c == ']' || c == '{' || c == '}' || c == '!' || c == '#'
            || ( c == '~' && i == 0 && flag.empty() ) )
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

// cut-fix E: the NEXT PAGE of a default-windowed listing, as one pasteable call. The --tree/--zoom/--external-surface
// next= values were spelled `<verb> --offset=N` and dropped the caller's own --limit, so a `--limit=10` page
// pointed at a default-sized (80/40/100-row) second page: rows past the next ten were served without being asked
// for, and the page boundaries stopped lining up. `pageLimit` is the caller's --limit (0 = none was given, and
// then none is added: the default window is what the next page uses too). `invocation` carries every other flag
// that shapes the rows (--zoom=D, --zoom-levels=N), since the next page must be a page of the SAME listing.
//
// `offsetAtZero` (folded in on 2026-09-25 with the next=-length-ceiling removal): --tree/--zoom/--external-surface
// always page an already-cut
// listing, so their next offset is never 0 and `--offset=` always belongs — the default keeps that. --for's
// widening page (forpage.h's forPageInvocation) is the one caller whose FIRST page is offset 0, and there
// `--offset=0` must stay unemitted (forwidencheck.sh arm 5 pins the bare `--limit=40` tail); it passes false.
inline std::string pagedNext( std::string_view invocation, int pageLimit, std::size_t nextOffset, bool offsetAtZero = true )
{
    std::string out( invocation );
    if( pageLimit > 0 )
    {
        out += " --limit=" + std::to_string( pageLimit );
    }
    if( nextOffset > 0 || offsetAtZero )
    {
        out += " --offset=" + std::to_string( nextOffset );
    }
    return out;
}

} // namespace rw
