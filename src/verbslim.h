#pragma once
// verbslim.h — VERB-SLIM-1 (BRIEF-SHAPE-AUDIT 2026-11-25): the default posture's cut of two verbs' answers, --expand and
// --quality-delta. A finished answer is rewritten here, once, right before the compact layer builds its legend, so every
// clause the layer would have written for a removed attribute goes with it (its readings are present-only).
//
// THE CUT ONLY REMOVES OR REORDERS. It adds no analysis and no slot, so it cannot lose an item the answer had: the audit
// re-scored its PREREG items on the transformed answers of 71 cells (tmp/orch-1125/brief-shape-audit/RESULT.md).
//   --expand   the <ctx> root's topk_default= and map_next= (the exact-name default
//              that dropped a map the caller never asked for), est_tokens= (the answer's price; kept whenever a budget
//              names a ceiling or the price is a degraded estimate, the two readers who act on it).
//              ORDER: sibs=/inc= sat in the <b> tag, BEFORE the body, 22-85 % of the answer. They move to <fctx>, the
//              element right after the </b> (the <b> keeps its CDATA-then-<calls> inside, which callers parse). They are not deleted: a trace check over 142 expand answers found 9 calls
//              whose next Read/Grep took a name only the sibs= list carried (traceuse/RESULT.md). The include list
//              had no such use: it becomes inc_total= plus inc_next=, the call that prints it, unless the list itself is
//              shorter than that pointer.
//   --quality-delta  the root's zero counters that only count (acked= stale= register-macro-excluded= api-new-surface=
//              value-ref-excluded= declined-call-excluded=). regressions= minor= gating= preexisting-worse= new-symbol=
//              always print: the legend's opener and the skills (debt-ci.md: "parse new-symbol=") name them. Every row's
//              sym= stays whole: it is the canonical id scripts and --ack-only read (test/qualitycheck.sh parses it).
// NOT HERE: the <r kind=> row shape (consumers parse it), the MCP surface (its own posture), the held-dictionary postures
// (--legend-have= / --legend-seen=: main.cpp applyVerbSlim; the slim --expand purpose is no dictionary entry), the full dialect
// (--legend=full prints today's answer: it is inc_next='s target), and every other verb.
//
// OFF SWITCH: RIPWIRE_VERB_SLIM=0 skips this file and the answer is today's byte for byte (test/verbslimcheck.sh (1)).

#include <cstddef>
#include <string>
#include <string_view>

#include "compactlegend.h"     // isElementNamed — the one "is this <…> span element NAME" test
#include "infra/envnumber.h"   // readEnvNumber — RIPWIRE_VERB_SLIM read like every other numeric knob
#include "nextverb.h"          // nextAttrXml / nextFlag — inc_next= is pasteable like every other next-family value

namespace rw::verbslim
{

// ON unless RIPWIRE_VERB_SLIM holds the number 0; unset, empty or any other text reads the default.
[[nodiscard]] inline bool verbSlimOn() noexcept
{
    const EnvNumber v = readEnvNumber( "RIPWIRE_VERB_SLIM" );
    return !( v.parsed && v.value == 0 );
}

// One ` name="value"` inside an element's open tag: [at, end) spans the leading space through the closing quote. The value
// is the escaped text as written; an escaped value carries no raw `"`, so the first quote after it closes it.
struct AttrSpan
{
    std::size_t      at  = std::string::npos;
    std::size_t      end = std::string::npos;
    std::string_view value;
    [[nodiscard]] bool found() const noexcept { return at != std::string::npos; }
};

[[nodiscard]] inline AttrSpan findAttr( std::string_view tag, std::string_view name ) noexcept
{
    AttrSpan          a;
    const std::string needle = " " + std::string( name ) + "=\"";
    const std::size_t at     = tag.find( needle );
    if( at == std::string_view::npos )
    {
        return a;
    }
    const std::size_t vb = at + needle.size();
    const std::size_t q  = tag.find( '"', vb );
    if( q == std::string_view::npos )
    {
        return a;
    }
    a.at    = at;
    a.end   = q + 1;
    a.value = tag.substr( vb, q - vb );
    return a;
}

// Removes ` name="…"` from `tag` and returns what it held (with its leading space), or "" when absent.
inline std::string takeAttr( std::string& tag, std::string_view name )
{
    const AttrSpan a = findAttr( tag, name );
    if( !a.found() )
    {
        return {};
    }
    std::string held = tag.substr( a.at, a.end - a.at );
    tag.erase( a.at, a.end - a.at );
    return held;
}

// The XML attribute escapes undone, for a value that is re-escaped as a next= call (nextverb.h appendNextValueXml).
[[nodiscard]] inline std::string unescapeAttr( std::string_view v )
{
    std::string out;
    out.reserve( v.size() );
    for( std::size_t i = 0; i < v.size(); )
    {
        if( v[ i ] == '&' )
        {
            static constexpr std::string_view kEnt[][ 2 ] = { { "&amp;", "&" }, { "&lt;", "<" }, { "&gt;", ">" }, { "&quot;", "\"" }, { "&apos;", "'" } };
            bool matched = false;
            for( const auto& e : kEnt )
            {
                if( v.substr( i ).starts_with( e[ 0 ] ) )
                {
                    out += e[ 1 ];
                    i += e[ 0 ].size();
                    matched = true;
                    break;
                }
            }
            if( matched )
            {
                continue;
            }
        }
        out += v[ i++ ];
    }
    return out;
}

// THE WALK both rewrites share: the document copied piece by piece — a CDATA section, a comment, text, or one element tag —
// with each tag outside CDATA and comments offered to `onTag( tag, out )`, which appends what replaces it. CDATA and
// comments are copied untouched: a body that quotes `<b sibs=` is data.
template<class OnTag>
inline std::string rewriteTags( std::string_view doc, OnTag&& onTag )
{
    std::string out;
    out.reserve( doc.size() );
    std::size_t i = 0;
    while( i < doc.size() )
    {
        const std::string_view rest = doc.substr( i );
        std::size_t            e    = std::string_view::npos;
        if( rest.starts_with( "<![CDATA[" ) || rest.starts_with( "<!--" ) )
        {
            const std::string_view close = rest.starts_with( "<!--" ) ? std::string_view( "-->" ) : std::string_view( "]]>" );
            const std::size_t      j     = doc.find( close, i );
            e = j == std::string_view::npos ? doc.size() : j + close.size();
            out.append( doc.substr( i, e - i ) );
        }
        else if( doc[ i ] == '<' )
        {
            const std::size_t j = doc.find( '>', i );
            e = j == std::string_view::npos ? doc.size() : j + 1;
            onTag( doc.substr( i, e - i ), out );
        }
        else
        {
            const std::size_t j = doc.find( '<', i );
            e = j == std::string_view::npos ? doc.size() : j;
            out.append( doc.substr( i, e - i ) );
        }
        i = e;
    }
    return out;
}

// An element's open (or self-closing) tag: not a close tag, a comment or a processing instruction.
[[nodiscard]] inline bool isOpenElementTag( std::string_view tag ) noexcept
{
    return tag.size() > 1 && tag[ 1 ] != '?' && tag[ 1 ] != '!' && tag[ 1 ] != '/';
}

// ── --expand ─────────────────────────────────────────────────────────────────────────────────────────────────────────

// est_tokens= is a price; a reader acts on it only beside a ceiling it is judged against, or when it is an estimate the
// root labels as one — there it stays.
[[nodiscard]] inline bool expandRootKeepsPrice( std::string_view rootTag ) noexcept
{
    for( const std::string_view a : { "max_tokens", "budget_tokens", "over_ceiling", "est_measured" } )
    {
        if( findAttr( rootTag, a ).found() )
        {
            return true;
        }
    }
    return false;
}

// The <fctx> element that follows a </b>, from the attributes taken off its <b>: sibs= as it was (its count and cap with
// it), inc= as inc_total= plus the call that prints the list — or the list itself when that is no longer than the call.
[[nodiscard]] inline std::string expandFileContext( std::string& bTag )
{
    const std::string sibs       = takeAttr( bTag, "sibs" );
    const std::string sibsTotal  = takeAttr( bTag, "sibs_total" );
    const std::string sibsCapped = takeAttr( bTag, "sibs_capped" );
    const std::string inc        = takeAttr( bTag, "inc" );
    const std::string incTotal   = takeAttr( bTag, "inc_total" );
    const std::string incCapped  = takeAttr( bTag, "inc_capped" );
    if( sibs.empty() && incTotal.empty() )
    {
        return {};
    }
    std::string incPart;
    if( !incTotal.empty() )
    {
        const AttrSpan p = findAttr( bTag, "p" );
        const AttrSpan n = findAttr( bTag, "n" );
        const std::string next = p.found() && n.found()
            ? nextAttrXml( nextFlag( "--expand=", unescapeAttr( p.value ) + ":" + unescapeAttr( n.value ) ) + " --legend=full", "inc_next" )
            : std::string();
        incPart = !next.empty() && next.size() < inc.size() + incCapped.size() ? incTotal + next : inc + incTotal + incCapped;
    }
    return "<fctx" + sibs + sibsTotal + sibsCapped + incPart + "/>";
}

inline void slimExpandAnswer( std::string& doc )
{
    bool        rootSeen = false;
    std::string pending;   // the open <b>'s <fctx>, written right AFTER its </b>: the <b> keeps today's inner shape
                           // (CDATA body, then <calls>), which edit round trips and scripts parse up to `]]></b>`
    doc = rewriteTags( doc, [ & ]( std::string_view tag, std::string& out )
    {
        const bool isElement = isOpenElementTag( tag );
        if( !rootSeen && isElement )
        {
            rootSeen = true;
            std::string t( tag );
            if( isElementNamed( t, "ctx" ) )
            {
                takeAttr( t, "topk_default" );
                takeAttr( t, "map_next" );
                if( !expandRootKeepsPrice( t ) )
                {
                    takeAttr( t, "est_tokens" );
                }
            }
            out += t;
            return;
        }
        if( isElementNamed( tag, "b" ) )
        {
            std::string       t( tag );
            const std::string fctx = expandFileContext( t );
            out += t;
            if( t.ends_with( "/>" ) )
            {
                out += fctx;
            }
            else
            {
                pending = fctx;
            }
            return;
        }
        out.append( tag );
        if( tag == "</b>" )
        {
            out += pending;
            pending.clear();
        }
    } );
}

// ── --quality-delta ──────────────────────────────────────────────────────────────────────────────────────────────────

// The root counters that only count: printed when non-zero (their legend reading rides with them), absent at 0.
inline constexpr std::string_view kQdZeroCounters[] = { "acked", "stale", "register-macro-excluded", "api-new-surface",
                                                        "value-ref-excluded", "declined-call-excluded" };

// The <quality-delta> root tag without its zero counters. It says what it did, so the answer explains itself: omit0="1"
// when a counter left (its reading: a count not printed is 0).
inline void slimQualityDeltaRoot( std::string& root )
{
    bool omitted = false;
    for( const std::string_view c : kQdZeroCounters )
    {
        if( const AttrSpan a = findAttr( root, c ); a.found() && a.value == "0" )
        {
            root.erase( a.at, a.end - a.at );
            omitted = true;
        }
    }
    if( omitted )
    {
        root.insert( root.size() - ( root.ends_with( "/>" ) ? 2 : 1 ), " omit0=\"1\"" );
    }
}

// The caller (main.cpp applyVerbSlim) has checked that the answer's root is <quality-delta>.
inline void slimQualityDeltaAnswer( std::string& doc )
{
    bool rootSeen = false;
    doc = rewriteTags( doc, [ & ]( std::string_view tag, std::string& o )
    {
        std::string t( tag );
        if( !rootSeen && isOpenElementTag( tag ) )
        {
            rootSeen = true;
            slimQualityDeltaRoot( t );
        }
        o += t;
    } );
}

} // namespace rw::verbslim
