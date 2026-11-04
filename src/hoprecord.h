#pragma once
// hoprecord.h — THE hop record (HOP-CONTEXT-1, IDEAS_LIST card 20; reports/hop-context-s0.md "Recommended design").
//
// A call edge an answer prints (a --path hop row, a --connect <e> row) used to say only which two definitions it joins.
// What an agent opens next is the CALL: where the caller makes it, with which arguments, and what the callee takes and
// returns. This file is the one place that knows those facts for an edge, and every edge-printing verb reads them here:
//
//   HopWant      — an edge the answer will print, and whether it prints in full (site + call + sig) or site only;
//   hopFacts()   — the ONE provider: one pass over ing.references for EVERY wanted edge of the answer (never one scan per hop),
//                  then one read per distinct file (FileTextCache), then per-edge slicing that reads no file and scans nothing;
//   hopAttrsXml()— the ONE renderer, with the shed level: ` site="f:l" [sites="N"] [call="…"] [sig="…"]`;
//   hopRootAttrsXml() / hopLegend() / the compact readings (compactlegend.h) — the disclosures, present-only.
//
// Site selection is option A (lane 1): the calls inside the caller whose callee NAME is the edge's callee (the --uses /
// sites_at= filter, editcheck.h callSiteCounts + CallSiteCalleeTest), a call whose written qualifier is the callee's owner
// first, then file/line order. It is a name match, not proof that this call is the one the edge binds; the legend says so,
// and sites="N" counts the others. Per-edge stored sites (option B, Graph::outSite) are a follow-on.
//
// Honesty (CR lens 4): a call= or sig= is never guessed and never printed empty. A file that cannot be read or changed since
// indexing withholds it (hop_unread=); a site whose text does not spell the callee (a macro-expanded or generated call)
// withholds call= (hop_notext=); an edge with no call naming the callee in its caller (an inherit/impl/link edge, an alias,
// a constructor reached by another name) prints no site= (hop_nosite=). Under a budget the renderer sheds sig=, then
// call=, then site= — all before the budget touches anything the answer printed without them (a join sig=, a leg: the hop
// attributes take their own allowance, never the answer's; owner rule: a budget that cuts answers is a bad budget).

#include "infra/emit.h"     // emitTo — the stats line
#include "editcheck.h"     // callSiteCounts / CallSiteCalleeTest — the --uses call-site filter and callee-name test
#include "elixir_resolve.h"   // elixirBaseName — an Elixir callee spells name/N in the index, name in the source
#include "filetext.h"      // FileTextCache — one read per file per answer
#include "graph.h"
#include "model.h"
#include "redact.h"        // redactSecrets — call text is emitted source text (a credential seam, like cleanSig)
#include "sarif.h"         // rootRelativeUri — site= in the row's own path dialect
#include "serialize.h"     // cleanSig / escapeXml / truncateUtf8WithEllipsis

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <span>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

namespace rw
{

inline constexpr std::size_t   kHopCallMaxBytes  = 120;   // call= cap (U+2026 marks a cut)
inline constexpr std::size_t   kHopCallMaxLines  = 3;     // a call whose arguments continue joins up to this many lines
inline constexpr std::size_t   kHopSigMaxBytes   = 160;   // sig= cap on a hop (cleanSig's own 240 cap applies first)
inline constexpr std::size_t   kHopWindowBytes   = 512;   // source bytes read before the callee name (twice that after): a minified line costs a window
inline constexpr std::uint32_t kHopNoRef         = UINT32_MAX;

// The kill switch (like RIPWIRE_NO_HOP_BODY): set, no hop attribute and no hop disclosure prints, byte for byte the
// answer before this lane (test/hopcontextcheck.sh arm 1 reads it).
inline bool hopContextOn()
{
    return std::getenv( "RIPWIRE_NO_HOP_CONTEXT" ) == nullptr;
}

// What the renderer prints, most first; each level drops what the one before kept. Proof detail sheds before sig=, but
// this lane adds no proof word (via=/prov= are the proof and are never shed), so the first shed is sig=.
enum class HopShed : std::uint8_t
{
    Full,       // site= sites= call= sig=
    NoSig,      // site= sites= call=
    SiteOnly,   // site= sites=
    Off,        // nothing: shed before a budget touches anything the answer printed without the hop record (a join sig, a leg)
};

struct HopWant
{
    NodeId from;
    NodeId to;
    bool   full;   // false: the answer prints site= only for it (a later --path pair), so no text is read for it
};

enum class HopGap : std::uint8_t
{
    None,
    Unread,   // the file could not be read, or it changed since indexing
    NoText,   // the site's text does not spell the callee (macro-expanded, generated)
};

struct HopRecord
{
    NodeId        from    = kNoNode;
    NodeId        to      = kNoNode;
    bool          full    = false;
    std::uint32_t ref     = kHopNoRef;   // the chosen call reference (ing.references index); kHopNoRef = no site
    std::uint32_t nSites  = 0;           // distinct lines in `from` that call the callee's name
    std::string   call;                  // trimmed call text, unescaped; "" = not printed (see callGap)
    std::string   sig;                   // callee signature, unescaped; "" = not printed (see sigGap)
    HopGap        callGap = HopGap::None;
    HopGap        sigGap  = HopGap::None;
};

struct HopFacts
{
    bool                   on = false;   // false: the kill switch, or nothing wanted — renders nothing
    std::vector<HopRecord> recs;         // sorted by (from, to)
    std::size_t            nosite = 0, unread = 0, notext = 0;
    std::size_t            referenceScans = 0, filesRead = 0;   // arm 8: one scan per answer

    const HopRecord* find( NodeId from, NodeId to ) const noexcept
    {
        const auto it = std::lower_bound( recs.begin(), recs.end(), std::pair{ from, to },
                                          []( const HopRecord& r, const std::pair<NodeId, NodeId>& k ) { return r.from != k.first ? r.from < k.first : r.to < k.second; } );
        return it != recs.end() && it->from == from && it->to == to ? &*it : nullptr;
    }
    bool                   anySite = false, anySites = false, anyCall = false, anySig = false;   // set once, by hopFacts' slice pass
};

namespace hopdetail
{

inline bool identByte( char c ) noexcept
{
    const unsigned char u = static_cast<unsigned char>( c );
    return u >= 0x80 || ( u >= '0' && u <= '9' ) || ( u >= 'a' && u <= 'z' ) || ( u >= 'A' && u <= 'Z' ) || c == '_' || c == '$';
}

// The last segment of a qualified spelling (`A` for "ns::A", `m` for "pkg.T#m"): the text after the final ::, . or #.
inline std::string_view lastSegment( std::string_view n ) noexcept
{
    for( const std::string_view sep : { std::string_view( "::" ), std::string_view( "." ), std::string_view( "#" ) } )
    {
        if( const std::size_t at = n.rfind( sep ); at != std::string_view::npos && at + sep.size() < n.size() )
        {
            n = n.substr( at + sep.size() );
        }
    }
    return n;
}

// The source spelling of a callee's name: the leaf segment (an index name may carry an owner), Elixir's /N dropped.
inline std::string_view leafName( const Symbol& s ) noexcept
{
    return lastSegment( editCheckContractId( s.name, s ) );   // Elixir's /N dropped (the one Lang:: compare, editcheck.h)
}

// The first whole-word occurrence of `name` in text[from, to), npos when none.
inline std::size_t findWord( std::string_view text, std::size_t from, std::size_t to, std::string_view name ) noexcept
{
    const std::string_view hay  = text.substr( 0, std::min( to, text.size() ) );   // a match must end by `to`
    const auto             edge = [ & ]( std::size_t before, std::size_t after ) { return ( before == 0 || !identByte( text[ before - 1 ] ) ) && ( after >= text.size() || !identByte( text[ after ] ) ); };
    std::size_t            at   = name.empty() ? std::string_view::npos : hay.find( name, from );
    while( at != std::string_view::npos && !edge( at, at + name.size() ) )
    {
        at = hay.find( name, at + 1 );
    }
    return at;
}

// The call text of one site: from its line's first non-blank byte, joined across up to kHopCallMaxLines lines while the
// call's parentheses are open, whitespace runs collapsed, redacted, then cut at kHopCallMaxBytes on a codepoint boundary
// (a callee name past the cut moves the window so the name stays in view). Gap set when no honest text exists.
struct CallText
{
    std::string text;
    HopGap      gap = HopGap::None;
};
inline CallText callText( FileTextCache& files, const Reference& r, std::string_view name, RedactCounts* redact )
{
    CallText out;
    const std::string* src = files.text( r.fileId );
    if( src == nullptr || files.stale( r.fileId ) )
    {
        out.gap = HopGap::Unread;
        return out;
    }
    const std::span<const std::uint32_t> lines = files.lineStarts( r.fileId );
    if( r.line == 0 || r.line > lines.size() || r.startByte >= src->size() )
    {
        out.gap = HopGap::Unread;   // the stored line or offset is outside the file read: it changed since indexing
        return out;
    }
    const std::size_t lineAt  = lines[ r.line - 1 ];
    const auto        lineEnd = [ & ]( std::size_t ln ) -> std::size_t   // 1-based line ln, end before its '\n'
    {
        const std::size_t e = ln < lines.size() ? lines[ ln ] - 1 : src->size();
        return e > 0 && e <= src->size() && ( *src )[ e - 1 ] == '\r' ? e - 1 : e;
    };
    if( r.startByte < lineAt || r.startByte > lineEnd( r.line ) )
    {
        out.gap = HopGap::Unread;   // the offset no longer sits on the stored line
        return out;
    }
    // the window: the site's line, then continuation lines while the call's parentheses stay open
    std::size_t endAt   = lineEnd( r.line );
    std::size_t lastLn  = r.line;
    std::size_t namePos = findWord( *src, r.startByte, endAt, name );
    const auto  depthOf = [ & ]( std::size_t a, std::size_t b )
    {
        long d = 0;
        for( std::size_t i = a; i < b; ++i )
        {
            d += ( *src )[i] == '(' ? 1 : ( *src )[i] == ')' ? -1 : 0;
        }
        return d;
    };
    while( lastLn < r.line + kHopCallMaxLines - 1 && lastLn < lines.size()
           && ( namePos == std::string_view::npos || depthOf( namePos, endAt ) > 0 ) )
    {
        ++lastLn;
        endAt = lineEnd( lastLn );
        if( namePos == std::string_view::npos )
        {
            namePos = findWord( *src, r.startByte, endAt, name );
        }
    }
    if( namePos == std::string_view::npos )
    {
        out.gap = HopGap::NoText;   // nothing in the window spells the callee: a macro-expanded or generated call
        return out;
    }
    std::size_t begin = lineAt;
    while( begin < r.startByte && ( ( *src )[ begin ] == ' ' || ( *src )[ begin ] == '\t' ) )
    {
        ++begin;
    }
    // a minified or generated line: read a bounded window around the name, never the whole line (the cut below is marked)
    bool leadCut = false;
    if( namePos - begin > kHopWindowBytes )
    {
        begin = namePos - kHopWindowBytes;
        while( begin < namePos && ( static_cast<unsigned char>( ( *src )[ begin ] ) & 0xC0 ) == 0x80 )
        {
            ++begin;
        }
        leadCut = true;
    }
    endAt = std::min( endAt, namePos + 2 * kHopWindowBytes );
    // collapse whitespace (tabs, CR, LF, runs) to one space; remember where the name lands in the collapsed text
    std::string flat;
    flat.reserve( endAt - begin );
    std::size_t flatName = 0;
    bool        inSpace  = false;
    for( std::size_t i = begin; i < endAt; ++i )
    {
        if( i == namePos )
        {
            flatName = flat.size();
        }
        const char c = ( *src )[i];
        if( c == ' ' || c == '\t' || c == '\n' || c == '\r' )
        {
            if( !flat.empty() && !inSpace )
            {
                flat.push_back( ' ' );
                inSpace = true;
            }
            continue;
        }
        flat.push_back( c );
        inSpace = false;
    }
    while( !flat.empty() && flat.back() == ' ' )
    {
        flat.pop_back();
    }
    if( depthOf( namePos, endAt ) > 0 )
    {
        flat += " \xE2\x80\xA6";   // the arguments run past kHopCallMaxLines: the cut is marked, never silent
    }
    if( leadCut )
    {
        flat.insert( 0, "\xE2\x80\xA6" );
        flatName += 3;
    }
    // the name past the cut: start the window ~40 bytes before it (on a codepoint boundary), marked with a leading U+2026
    if( flatName + name.size() > kHopCallMaxBytes - 10 && flatName > 40 )
    {
        std::size_t from = flatName - 40;
        while( from < flat.size() && ( static_cast<unsigned char>( flat[ from ] ) & 0xC0 ) == 0x80 )
        {
            ++from;
        }
        flat = "\xE2\x80\xA6" + flat.substr( from );
    }
    std::string redacted;
    if( redact != nullptr && redactSecrets( flat, redacted, *redact ) )
    {
        flat = std::move( redacted );   // before the cap, so a secret straddling it cannot survive as a prefix (cleanSig's order)
    }
    truncateUtf8WithEllipsis( flat, kHopCallMaxBytes );
    out.text = std::move( flat );
    return out;
}

// The callee's declaration signature (cleanSig, cut at kHopSigMaxBytes). Unread when the file cannot be read, changed, or
// the stored span no longer holds the callee's name.
inline CallText calleeSig( FileTextCache& files, const Symbol& s, RedactCounts* redact )
{
    CallText out;
    if( s.sigStartByte >= s.sigEndByte )
    {
        return out;   // the index recorded no signature for it: nothing to print, nothing withheld
    }
    const std::string* src = files.text( s.fileId );
    if( src == nullptr || files.stale( s.fileId ) || s.sigEndByte > src->size()
        || findWord( *src, s.sigStartByte, s.sigEndByte, leafName( s ) ) == std::string_view::npos )
    {
        out.gap = HopGap::Unread;
        return out;
    }
    out.text = cleanSig( src->data(), s.sigStartByte, s.sigEndByte, redact );
    truncateUtf8WithEllipsis( out.text, kHopSigMaxBytes );
    return out;
}

// The callee's owner as a call would qualify it (`A` for scope "ns::A"), "" when it has none.
inline std::string_view ownerLeaf( const Symbol& s ) noexcept
{
    return lastSegment( s.scope );
}

}   // namespace hopdetail

// THE provider. `wanted` may repeat an edge (a full want wins over a site-only one). Work, stated per loop (owner 11-04):
//   (1) per wanted edge: sort + unique, mark the caller bit — no scan;
//   (2) ONE pass over ing.references: per call reference in a marked caller, the wanted edges of that caller (an
//       equal_range of the sorted keys, usually 1-2) test the callee name; a hit keeps the best site and counts lines;
//   (3) per distinct file of a chosen site or callee: one read (FileTextCache);
//   (4) per edge: slice the cached text — no file read, no reference scan, no name lookup.
inline HopFacts hopFacts( const IngestResult& ing, const Graph& g, std::vector<HopWant> wanted, RedactCounts* redact, FileTextCache& files )
{
    HopFacts out;
    if( !hopContextOn() || wanted.empty() )
    {
        return out;
    }
    out.on = true;
    std::sort( wanted.begin(), wanted.end(), []( const HopWant& a, const HopWant& b )
               { return a.from != b.from ? a.from < b.from : a.to != b.to ? a.to < b.to : a.full > b.full; } );
    wanted.erase( std::unique( wanted.begin(), wanted.end(), []( const HopWant& a, const HopWant& b ) { return a.from == b.from && a.to == b.to; } ), wanted.end() );
    out.recs.resize( wanted.size() );
    std::vector<char> callerSel( ing.symbols.size(), 0 );
    for( std::size_t k = 0; k < wanted.size(); ++k )   // (1)
    {
        EXPECTS( wanted[k].from < ing.symbols.size() && wanted[k].to < ing.symbols.size(), "a hop joins two indexed symbols" );
        out.recs[k].from = wanted[k].from;
        out.recs[k].to   = wanted[k].to;
        out.recs[k].full = wanted[k].full;
        callerSel[ wanted[k].from ] = 1;
    }
    // one callee test per wanted edge, built before the pass (an Elixir callee builds its resolver once, here)
    std::vector<CallSiteCalleeTest> tests;
    tests.reserve( wanted.size() );
    for( const HopWant& w : wanted )
    {
        tests.emplace_back( ing, ing.symbols[ w.to ], std::span<const NodeId>( &w.to, 1 ) );
    }
    std::vector<std::uint32_t>                                     best( wanted.size(), kHopNoRef );
    std::vector<std::vector<std::pair<std::uint32_t, std::uint32_t>>> siteLines( wanted.size() );   // (file, line) per edge
    const auto        score = [ & ]( std::size_t k, const Reference& r ) -> std::tuple<int, std::uint32_t, std::uint32_t, std::uint32_t>
    {
        const std::string_view owner = hopdetail::ownerLeaf( ing.symbols[ wanted[k].to ] );
        const bool ownerMatch = !owner.empty() && ( r.qualifier == owner || r.recvVar == owner || r.memberRoot == owner );
        return { ownerMatch ? 0 : 1, r.fileId, r.line, r.startByte };
    };
    ++out.referenceScans;   // (2)
    for( std::uint32_t refIndex = 0; refIndex < ing.references.size(); ++refIndex )
    {
        const Reference& r = ing.references[ refIndex ];
        // a macro invocation is a hop the graph prints too (viamacro -> WRAP): its site is the invocation, same filter otherwise
        const bool site = callSiteCounts( r, refIndex, g.keptForwards )
                       || ( r.role == RefRole::Macro && refTextCounts( r, refIndex, g.keptForwards ) );
        if( r.fromSymbol >= callerSel.size() || !callerSel[ r.fromSymbol ] || !site )
        {
            continue;
        }
        const auto lo = std::lower_bound( wanted.begin(), wanted.end(), r.fromSymbol, []( const HopWant& w, NodeId f ) { return w.from < f; } );
        for( auto it = lo; it != wanted.end() && it->from == r.fromSymbol; ++it )
        {
            const std::size_t k = std::size_t( it - wanted.begin() );
            if( !tests[k].reaches( r ) )
            {
                continue;
            }
            siteLines[k].emplace_back( r.fileId, r.line );
            if( best[k] == kHopNoRef || score( k, r ) < score( k, ing.references[ best[k] ] ) )
            {
                best[k] = refIndex;
            }
        }
    }
    for( std::size_t k = 0; k < wanted.size(); ++k )   // (3) the files the text slices read, each once
    {
        std::sort( siteLines[k].begin(), siteLines[k].end() );   // two calls on one line are one site (sites_at='s rule)
        out.recs[k].nSites = std::uint32_t( std::unique( siteLines[k].begin(), siteLines[k].end() ) - siteLines[k].begin() );
        out.recs[k].ref    = best[k];
        if( out.recs[k].full )
        {
            if( best[k] != kHopNoRef )
            {
                (void)files.text( ing.references[ best[k] ].fileId );
            }
            (void)files.text( ing.symbols[ wanted[k].to ].fileId );
        }
    }
    out.filesRead = files.filesRead();
    for( HopRecord& rec : out.recs )   // (4)
    {
        if( rec.ref == kHopNoRef )
        {
            ++out.nosite;
            continue;
        }
        out.anySite  = true;
        out.anySites = out.anySites || rec.nSites > 1;
        if( !rec.full )
        {
            continue;
        }
        const Symbol&            callee = ing.symbols[ rec.to ];
        const hopdetail::CallText ct    = hopdetail::callText( files, ing.references[ rec.ref ], hopdetail::leafName( callee ), redact );
        const hopdetail::CallText st    = hopdetail::calleeSig( files, callee, redact );
        rec.call    = ct.text;
        rec.callGap = ct.gap;
        rec.sig     = st.text;
        rec.sigGap  = st.gap;
        out.unread += rec.callGap == HopGap::Unread || rec.sigGap == HopGap::Unread ? 1 : 0;
        out.notext += rec.callGap == HopGap::NoText ? 1 : 0;
        out.anyCall = out.anyCall || !rec.call.empty();
        out.anySig  = out.anySig || !rec.sig.empty();
    }
    if( std::getenv( "RIPWIRE_HOP_STATS" ) != nullptr )
    {
        emitTo( stderr, "ripwire: hop facts: edges={} reference_scans={} files_read={}\n", out.recs.size(), out.referenceScans, out.filesRead );
    }
    return out;
}

// The same provider with a reader of its own, for a verb that reads no other file for the answer.
inline HopFacts hopFacts( const IngestResult& ing, const Graph& g, std::vector<HopWant> wanted, RedactCounts* redact )
{
    FileTextCache files( ing );
    return hopFacts( ing, g, std::move( wanted ), redact, files );
}

// THE renderer: one hop's attributes at a shed level. `withSig` false when the answer already prints the callee's
// signature on another row (a --connect join <s sig=>, an earlier <e> to the same callee).
inline std::string hopAttrsXml( const IngestResult& ing, const HopRecord& rec, HopShed shed, bool withSig, bool singleRoot, std::string_view rootPrefix )
{
    if( rec.ref == kHopNoRef || shed == HopShed::Off )
    {
        return {};
    }
    std::vector<char>      esc;
    const Reference&       r   = ing.references[ rec.ref ];
    const std::string_view rp  = singleRoot ? sarif::rootRelativeUri( ing.files[ r.fileId ], rootPrefix ) : std::string_view( ing.files[ r.fileId ] );
    std::string            out = " site=\"" + std::string( escapeXml( rp, esc ) ) + ":" + std::to_string( r.line ) + "\"";
    if( rec.nSites > 1 )
    {
        out += " sites=\"" + std::to_string( rec.nSites ) + "\"";
    }
    if( shed < HopShed::SiteOnly && !rec.call.empty() )
    {
        out += " call=\"" + std::string( escapeXml( rec.call, esc ) ) + "\"";
    }
    if( shed < HopShed::NoSig && withSig && !rec.sig.empty() )
    {
        out += " sig=\"" + std::string( escapeXml( rec.sig, esc ) ) + "\"";
    }
    return out;
}

// --connect: the callee sigs a group already shows (its join rows' sig=, when sigs print), sorted for hopEdgeXml's lookup.
inline std::vector<NodeId> hopSigShown( std::span<const NodeId> joins, bool withSigs )
{
    std::vector<NodeId> shown;
    if( withSigs )
    {
        shown.assign( joins.begin(), joins.end() );
        std::sort( shown.begin(), shown.end() );   // a leg-dropped union need not list its joins in id order
    }
    return shown;
}

// --connect: rows that would read alike (homeassistant-08: f="get" t="async_handle" twice) print the definitions they join.
// One sort of the rows by printed names, one scan per run of alike rows. Bit 1 = fp= (the froms differ), bit 2 = tp=.
template <class Edge>
std::vector<std::uint8_t> hopAlikeRows( const IngestResult& ing, std::span<const Edge> edges )
{
    std::vector<std::uint8_t> need( edges.size(), 0 );
    std::vector<std::size_t>  byName( edges.size() );
    for( std::size_t k = 0; k < edges.size(); ++k )
    {
        byName[k] = k;
    }
    const auto names = [ & ]( std::size_t k ) { return std::pair<std::string_view, std::string_view>( ing.symbols[ edges[k].from ].name, ing.symbols[ edges[k].to ].name ); };
    std::sort( byName.begin(), byName.end(), [ & ]( std::size_t a, std::size_t b ) { return names( a ) != names( b ) ? names( a ) < names( b ) : a < b; } );
    for( std::size_t lo = 0, hi = 0; lo < byName.size(); lo = hi )
    {
        hi = lo + 1;
        bool fromsDiffer = false, tosDiffer = false;
        for( ; hi < byName.size() && names( byName[hi] ) == names( byName[lo] ); ++hi )
        {
            fromsDiffer = fromsDiffer || edges[ byName[hi] ].from != edges[ byName[lo] ].from;
            tosDiffer   = tosDiffer || edges[ byName[hi] ].to != edges[ byName[lo] ].to;
        }
        for( std::size_t k = lo; k < hi && hi - lo > 1; ++k )
        {
            need[ byName[k] ] = std::uint8_t( ( fromsDiffer ? 1 : 0 ) | ( tosDiffer ? 2 : 0 ) );
        }
    }
    return need;
}

// --connect: one <e> row's hop attributes — fp=/tp= when it reads alike, then site=/call=/sig= at the shed level, the callee's
// sig= once per group (`sigShown` grows as rows print it). `endpointRows` is set when fp=/tp= printed (its legend clause rides).
inline std::string hopEdgeXml( const IngestResult& ing, const HopFacts& hops, NodeId from, NodeId to, std::uint8_t alike, HopShed shed,
                               std::vector<NodeId>& sigShown, bool singleRoot, std::string_view rootPrefix, bool& endpointRows )
{
    std::string out;
    if( !hops.on )
    {
        return out;
    }
    std::vector<char> esc;
    const auto        defAt = [ & ]( const char* key, NodeId n )
    {
        const Symbol&          s  = ing.symbols[n];
        const std::string_view rp = singleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix ) : std::string_view( ing.files[ s.fileId ] );
        out.append( key ).append( std::string( escapeXml( rp, esc ) ) ).append( ":" ).append( std::to_string( s.line ) ).append( "\"" );
    };
    if( ( alike & 1 ) != 0 ) { defAt( " fp=\"", from ); }
    if( ( alike & 2 ) != 0 ) { defAt( " tp=\"", to ); }
    endpointRows = endpointRows || alike != 0;
    if( const HopRecord* rec = hops.find( from, to ) )
    {
        const auto at      = std::lower_bound( sigShown.begin(), sigShown.end(), to );
        const bool withSig = at == sigShown.end() || *at != to;
        out += hopAttrsXml( ing, *rec, shed, withSig, singleRoot, rootPrefix );
        if( withSig && shed == HopShed::Full && !rec->sig.empty() )
        {
            sigShown.insert( at, to );
        }
    }
    return out;
}

// --connect --max-tokens: advance the hop shed one step (sig=, then call=, then site=); false when nothing is left to shed.
// The hop attributes take their own allowance and never displace what the answer printed before them (COMMON no-displacement).
inline bool hopShedNext( const HopFacts& hops, HopShed& shed ) noexcept
{
    if( hops.on && shed < HopShed::SiteOnly && ( hops.anyCall || hops.anySig ) )
    {
        shed = shed == HopShed::Full ? HopShed::NoSig : HopShed::SiteOnly;
        return true;
    }
    if( hops.on && shed != HopShed::Off && hops.anySite )
    {
        shed = HopShed::Off;
        return true;
    }
    return false;
}

// The root's disclosures, present-only: hops with no site, texts withheld, and the shed level a budget reached.
inline std::string hopRootAttrsXml( const HopFacts& f, HopShed shed = HopShed::Full )
{
    if( !f.on )
    {
        return {};
    }
    if( shed == HopShed::Off )
    {
        return f.anySite ? " hop_shed=\"sig,call,site\"" : std::string();
    }
    std::string out;
    if( f.nosite > 0 ) { out += " hop_nosite=\"" + std::to_string( f.nosite ) + "\""; }
    if( f.unread > 0 ) { out += " hop_unread=\"" + std::to_string( f.unread ) + "\""; }
    if( f.notext > 0 ) { out += " hop_notext=\"" + std::to_string( f.notext ) + "\""; }
    if( shed != HopShed::Full && ( f.anyCall || f.anySig ) )
    {
        out += shed == HopShed::NoSig ? " hop_shed=\"sig\"" : " hop_shed=\"sig,call\"";
    }
    return out;
}

// The full dialect's clause (present-only, no "--": it rides inside the verb's own comment). `row` names the element.
inline std::string hopLegend( const HopFacts& f, std::string_view row, HopShed shed = HopShed::Full, bool endpointRows = false )
{
    if( !f.on )
    {
        return {};
    }
    std::string out;
    const std::string r( row );
    if( shed == HopShed::Off )
    {
        return f.anySite ? "hop_shed=: hop attributes max_tokens shed first (sig, call, site). " : std::string();
    }
    if( f.anySite )
    {
        out += r + " site=file:line: a call (or macro invocation) in the hop's caller whose callee name is this hop's callee (one whose written owner is the callee's first); "
               "matched by name, not proof that this call is the one the edge binds. ";
    }
    if( f.anySites )
    {
        out += r + " sites=N: the caller calls that name on N lines; site= is one of them. ";
    }
    if( f.anyCall && shed < HopShed::SiteOnly )
    {
        out += r + " call=: that call's text from its line start, whitespace collapsed, joined up to 3 lines while its parentheses are open, at most 120 bytes (U+2026 marks either cut). ";
    }
    if( f.anySig && shed < HopShed::NoSig )
    {
        out += r + " sig=: the callee's declaration signature, cut at 160 bytes. ";
    }
    if( endpointRows )
    {
        out += r + " fp=/tp=: the from/to definition, printed when two rows of a group would read alike. ";
    }
    if( f.nosite > 0 )
    {
        out += "hop_nosite=N: N hops whose caller has no call naming the callee (an inherit, impl or link edge, an alias, a constructor), so no site=. ";
    }
    if( f.unread > 0 )
    {
        out += "hop_unread=N: call= or sig= withheld on N hops: the file could not be read or changed since indexing. ";
    }
    if( f.notext > 0 )
    {
        out += "hop_notext=N: call= withheld on N hops whose site text does not spell the callee (a macro-expanded or generated call). ";
    }
    if( shed != HopShed::Full && ( f.anyCall || f.anySig ) )
    {
        out += "hop_shed=: hop attributes max_tokens shed first (sig, call, site). ";
    }
    return out;
}

}   // namespace rw
