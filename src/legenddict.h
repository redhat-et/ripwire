#pragma once
// legenddict.h — the SESSION legend dictionary and the legend="ref" posture (lane r2-LO, round-2 prereg LO + L6).
//
// WHAT IT BUYS. The MCP server re-paid every answer's legend on every call: the compact dialect is ~300-1,500 B per
// answer and the same definitions reach the same agent dozens of times a session. Under legend="ref" a definition is
// served ONCE per server process and later answers point at it instead of repeating it.
//
// WHAT "SERVED" MEANS, and it is the whole honesty argument. A definition is an ENTRY of this dictionary: the ref-posture
// core (below), one purpose line per compact schema (compactlegend.h kCompactLegendSpecs), one reading per completeness
// term (kCompactCompletenessTerms), and the MCP `for` dialect's fixed clauses (graphlegend.h, lexical.h, forpage.h,
// serialize.h — named constants, so these are the very bytes the headers append). An entry is served in THIS process
// once its bytes went out verbatim: the core when the client reads ripwire://legend-dict (mcp.h), every other entry the
// first time an answer carries it. The session starts in the inline posture and switches to ref only when the core was
// read; after that an answer DROPS exactly the entries this process already served and KEEPS the rest inline, in a
// trailing comment, marking them served. So every attribute a ref answer carries is defined by bytes this process
// already sent, or by that answer itself — never by a dictionary the reader was only pointed at.
//
// WHY LAZY AND NOT ONE FETCH. The prereg registered a ~5.5 KB dictionary fetched once (the distinct compact clauses the
// five instrument verbs emit). The dictionary this binary can honestly serve for EVERY verb is the union over all 79
// schemas and 89 terms, ~19 KB, and a first-answer charge over 7.5 KB self-rejects LO (Amendment 1, R5). Served lazily
// the session pays the core once plus exactly the entries it uses, which is the quantity lo_dict.py estimated. The whole
// dictionary still resolves: ripwire://legend-dict/full on the server, `ripwire --legend-dict` on the CLI.
//
// THE REF ANSWER'S SHAPE. Rows first: the root keeps only the answer's identity (task= changed= from= to=); the legend
// comment is reduced to its unserved entries and moved, with every other head comment (they carry data: the map
// header, --for's notes and splices), after the rows; the LAST child is
//     <about ROOT-ATTRIBUTES legend="ref" dict="ripwire --legend-dict" dictv="16-hex"/>
// carrying every moved root attribute unchanged, in its original order. No attribute is dropped, rows keep all of theirs.
// L6: a runner-less <g n= p=> group of n <= 8 rows prints as its n single rows (grouping is a list-scale device) — only
// while the bytes the dropped legend freed pay for it.
//
// BUDGET. A ref answer is never longer than the inline answer it replaces, so every ceiling the inline answer met still
// holds and est_tokens=/over_ceiling= (priced on the inline answer) stay upper bounds. Where the trailer plus the unserved
// entries would not fit, the inline answer is served unchanged and its entries count as served (applyRefPosture).
//
// CONSUMERS: mcp.h (the session: resources/list, resources/read, textResult, batch sub-answers), cli.h (`--legend-dict`,
// `--legend-dict=roster`). Gate: test/legendrefcheck.sh.

#include "compactlegend.h"
#include "forhowbase.h"         // the how answer's named clauses (fix #10) and its pack-task legend opener
#include "forpage.h"            // kForCoverageLegend (and, through lexical.h, kForConfidenceNote)
#include "graphlegend.h"        // the named MCP `for` clauses, kForIdRouteLegend, kForRouteCodeLegend, the root-rel prose
#include "serialize.h"          // kForFileTailLegend
#include "infra/Diagnostics.h"
#include "infra/hashutil.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace rw::legenddict
{

// ── the entries ──────────────────────────────────────────────────────────────────────────────────────────────

// The ref-posture core: what a reader needs to read ANY ref answer, served by the one resource read that switches the
// session. The window and sub-cap readings are generic here because every compact legend spells them per answer.
inline constexpr std::string_view kCoreEntries[] =
{
    "<about legend=\"ref\" dict= dictv=>: the answer's rows come first; its root keeps only task= changed= from= to=, and "
    "this LAST child carries every other root attribute unchanged (schema= included); legend=\"ref\": a definition is sent "
    "once per session (this dictionary's core, or the first answer that needs it, in a trailing comment); dict= prints "
    "every definition, dictv= their version",
    "schema=ripwire.KEY/v1: the line ripwire.KEY/v1 below reads the answer's rows",
    "window: shown= total= capped= has_more= next_offset= offset= limit= page a list (capped=1 cut; next_offset= pastes as offset=)",
    "X_capped= (any attribute ending _capped): 1 = cut",
    "under ref, est_tokens= and over_ceiling= price the answer with its inline legend: an upper bound",
    "under ref, a <g n= p=> group of n <= 8 runner-less rows prints as its n single rows, each run_unknown=1",
};

// The MCP `for` dialect's fixed clauses, as its headers append them (leading punctuation included: the match is verbatim).
// Longest first is NOT required here: applyRefPosture sorts its own match order.
inline constexpr std::string_view kForClauseEntries[] =
{
    kMcpForBuildingBlocksLegend,
    kForIdRouteLegend,
    kForRouteCodeLegend,
    kMcpForBundleSigsLegend,
    kForConfidenceNote,
    kForCoverageLegend,
    kMcpForLensColumnsLegend,
    kForFileTailLegend,
    kForBudgetBytesNote,
    kForDocsDroppedNote,
    kForSigsShrunkNote,
    kForRootRelProse,
    kForAtStampProse,
    // fix #10: the shape="how" answer's clauses (forhowbase.h) — on its `for` lens legend and on the explore/pack-task
    // answer's own how legend comment (kHowPackTaskLegendOpen), both reduced below
    kHowShapeLegend,
    kHowPathLegend,
    kHowHopLegend,
    kHowBodyLegend,
    kHowNamesLegend,
    kHowEstLegend,
    kHowTaskLegend,
};

inline constexpr std::size_t kCoreCount     = std::size( kCoreEntries );
inline constexpr std::size_t kPurposeCount  = std::size( kCompactLegendSpecs );
inline constexpr std::size_t kTermCount     = kCompactReadingCount;   // BOTH reading tables, in compactlegend.h's joint order
inline constexpr std::size_t kForCount      = std::size( kForClauseEntries );
inline constexpr std::size_t kPurposeBase   = kCoreCount;
inline constexpr std::size_t kTermBase      = kPurposeBase + kPurposeCount;
inline constexpr std::size_t kForBase       = kTermBase + kTermCount;
inline constexpr std::size_t kEntryCount    = kForBase + kForCount;

// The bytes an answer carries for entry `id` (the purpose line WITHOUT its schema label — the compact legend spells the
// label in its opener; a term reading; a `for` clause with its leading punctuation).
inline std::string_view entryBody( std::size_t id ) noexcept
{
    EXPECTS( id < kEntryCount );
    if( id < kPurposeBase ) { return kCoreEntries[ id ]; }
    if( id < kTermBase )    { return kCompactLegendSpecs[ id - kPurposeBase ].purpose; }
    if( id < kForBase )     { return compactReading( id - kTermBase ).reading; }
    return kForClauseEntries[ id - kForBase ];
}

// The entry's line in the dictionary text: purpose lines gain their schema label, `for` clauses lose their leading
// punctuation and gain a "for:" label.
inline std::string entryLine( std::size_t id )
{
    EXPECTS( id < kEntryCount );
    if( id >= kPurposeBase && id < kTermBase )
    {
        const CompactLegendSpec& s = kCompactLegendSpecs[ id - kPurposeBase ];
        return "ripwire." + std::string( s.key ) + "/v1 <" + std::string( s.rootTag ) + ">: " + std::string( s.purpose );
    }
    if( id >= kForBase )
    {
        std::string_view body = entryBody( id );
        while( !body.empty() && ( body.front() == ' ' || body.front() == ';' || body.front() == ':' || body.front() == '[' ) )
        {
            body.remove_prefix( 1 );
        }
        if( !body.empty() && body.back() == ']' )
        {
            body.remove_suffix( 1 );
        }
        return "for: " + std::string( body );
    }
    return std::string( entryBody( id ) );
}

// Every entry line, one per line, in id order — the text dictv= hashes.
inline std::string dictionaryBody( std::size_t firstId, std::size_t endId )
{
    EXPECTS( firstId <= endId && endId <= kEntryCount );
    std::string out;
    for( std::size_t id = firstId; id < endId; ++id )
    {
        out += entryLine( id );
        out += '\n';
    }
    return out;
}

// dictv=: FNV-1a 64 over the whole dictionary body, 16 lowercase hex digits. Computed once per process.
inline const std::string& dictionaryVersion()
{
    static const std::string v = []
    {
        std::uint64_t h = 14695981039346656037ull;
        for( const char c : dictionaryBody( 0, kEntryCount ) )
        {
            h = hashutil::fnv1aAbsorb( h, c );
        }
        static constexpr char kHex[] = "0123456789abcdef";
        std::string s( 16, '0' );
        for( std::size_t i = 0; i < 16; ++i )
        {
            s[ 15 - i ] = kHex[ ( h >> ( 4 * i ) ) & 0xFu ];
        }
        return s;
    }();
    return v;
}

// The first line of both servings: the schema of the text and the version its body hashes to.
inline constexpr std::string_view kDictionaryHeadOpen = "ripwire legend dictionary ripwire.dict/v1 dictv=";

// One serving: the head line, the entries [0, endId), and an optional closing line.
inline std::string dictionaryText( std::size_t endId, std::string_view scope, std::string_view footer )
{
    std::string out( kDictionaryHeadOpen );
    out += dictionaryVersion();
    out += ' ';
    out += scope;
    out += '\n';
    out += dictionaryBody( 0, endId );
    out += footer;
    return out;
}

// The whole dictionary (`ripwire --legend-dict`, ripwire://legend-dict/full).
inline std::string fullDictionaryText()
{
    return dictionaryText( kEntryCount, "entries=" + std::to_string( kEntryCount ), {} );
}

// The core the session switch serves (ripwire://legend-dict): the core entries and how the rest arrives.
inline std::string coreDictionaryText()
{
    return dictionaryText( kCoreCount, "core",
                           "every other definition is sent once, the first time an answer in this session needs it, in a comment "
                           "after the rows; ripwire://legend-dict/full (or ripwire --legend-dict) holds all "
                           + std::to_string( kEntryCount ) + "\n" );
}

// ── the roster ────────────────────────────────────────────────────────────────────────────────────────────────
// The attributes this dictionary defines as COMPLETENESS / honesty vocabulary: a floor, a cap, a gauge, a could-not-prove
// or a degrade. legendrefcheck reads it (`ripwire --legend-dict=roster`) instead of a hand list, and fails the first one
// present in an answer with no definition the reader holds. Lines: attr TAB element (* = any) TAB source.
inline constexpr std::string_view kForRosterAttrs[] =
{
    "confidence", "margin_pct", "coverage", "dropped_positive", "budget_bytes", "lens",
};

inline std::string rosterText()
{
    std::string out;
    const auto row = [ & ]( std::string_view attr, std::string_view element, std::string_view source )
    {
        out.append( attr );
        out += '\t';
        out.append( element.empty() ? std::string_view( "*" ) : element );
        out += '\t';
        out.append( source );
        out += '\n';
    };
    for( std::size_t i = 0; i < kCompactReadingCount; ++i )
    {
        const CompactCompletenessTerm& t = compactReading( i );
        if( t.mapHeader != MapHeaderRead::Only )   // a header-ONLY field is not an attribute on any element
        {
            row( t.attr, t.onTag, i < kCompactTermCount ? "term" : "attr" );
        }
    }
    for( const std::string_view a : kCompactPagingAttrs )     { row( a, {}, "window" ); }
    for( const std::string_view a : kCompactPagingHeadAttrs ) { row( a, {}, "window" ); }
    for( const std::string_view a : kForRosterAttrs )         { row( a, "ctx", "for" ); }
    return out;
}

// ── the session ───────────────────────────────────────────────────────────────────────────────────────────────

// One per server process that can hold a session (the stdio loop; mcp.h). Never shared across threads: the stdio loop
// dispatches one line at a time, and the HTTP transport holds none (every answer there stays inline).
struct LegendSession
{
    bool                      refOn = false;   // the core was served in THIS process: answers may take the ref posture
    std::vector<std::uint8_t> served;          // per entry id: 1 once this process sent its bytes

    void serveCore()
    {
        served.resize( kEntryCount, 0 );
        std::fill( served.begin(), served.begin() + kCoreCount, std::uint8_t( 1 ) );
        refOn = true;
    }
    void serveAll()
    {
        served.assign( kEntryCount, 1 );
        refOn = true;
    }
    bool isServed( std::size_t id ) const noexcept
    {
        EXPECTS( id < kEntryCount );
        return id < served.size() && served[ id ] != 0;
    }
    void markServed( std::size_t id )
    {
        EXPECTS( id < kEntryCount );
        served.resize( kEntryCount, 0 );
        served[ id ] = 1;
    }
};

// ── the ref transform ─────────────────────────────────────────────────────────────────────────────────────────

enum class RefOutcome : std::uint8_t
{
    Ref,            // the answer took the ref posture
    InlineKept,     // the ref answer would not have been shorter: the inline answer is served, its entries count as served
    NotApplicable,  // not an answer this dictionary can reduce (no XML root, or a legend it does not hold): unchanged
};

namespace detail
{

// The attributes that stay on a ref root: the answer's identity (prereg R2-LO, KEEP).
inline constexpr std::string_view kIdentityAttrs[] = { "task", "changed", "from", "to" };

struct RootAttr
{
    std::string_view name;
    std::string_view whole;   // ` name="value"`, leading space included
};

// The ` name="value"` pairs of one start tag (whose name ends at `from`). Values are escaped XML: no raw quote inside.
inline std::vector<RootAttr> startTagAttrs( std::string_view tag, std::size_t from )
{
    std::vector<RootAttr> out;
    std::size_t i = from;
    while( i < tag.size() )
    {
        while( i < tag.size() && tag[ i ] == ' ' ) { ++i; }
        const std::size_t nameAt = i;
        while( i < tag.size() && tag[ i ] != '=' && tag[ i ] != ' ' && tag[ i ] != '>' && tag[ i ] != '/' ) { ++i; }
        if( i + 1 >= tag.size() || tag[ i ] != '=' || tag[ i + 1 ] != '"' )
        {
            break;
        }
        const std::size_t close = tag.find( '"', i + 2 );
        if( close == std::string_view::npos )
        {
            break;
        }
        out.push_back( { tag.substr( nameAt, i - nameAt ), tag.substr( nameAt - 1, close + 1 - ( nameAt - 1 ) ) } );
        i = close + 1;
    }
    return out;
}

struct Span
{
    std::size_t begin = 0;
    std::size_t end   = 0;
};

// The comments that stand before the root's open tag, and those between it and its first child: the answer's HEAD
// comments (the legend and the data a verb states before its rows).
inline std::vector<Span> headComments( std::string_view doc, const CompactRootInfo& root )
{
    std::vector<Span> out;
    std::size_t i = 0;
    const auto scan = [ & ]( std::size_t limit )
    {
        while( i < limit )
        {
            if( doc.substr( i ).starts_with( "<!--" ) )
            {
                const std::size_t j = doc.find( "-->", i );
                if( j == std::string_view::npos )
                {
                    i = limit;
                    return;
                }
                out.push_back( { i, j + 3 } );
                i = j + 3;
            }
            else if( doc[ i ] == ' ' || doc[ i ] == '\n' || doc[ i ] == '\t' || doc[ i ] == '\r' )
            {
                ++i;
            }
            else
            {
                return;
            }
        }
    };
    scan( root.openBegin );
    i = root.openEnd;
    scan( doc.size() );
    return out;
}

// A comment whose body is only punctuation and space after the removals carries nothing: dropped.
inline bool isEmptyComment( std::string_view comment ) noexcept
{
    if( comment.size() < 7 )
    {
        return true;
    }
    for( const char c : comment.substr( 4, comment.size() - 7 ) )
    {
        if( c != ' ' && c != '.' && c != ';' && c != ':' )
        {
            return false;
        }
    }
    return true;
}

// What a removal leaves at a comment's start (". dropped_positive=…" once the root-relative prose is gone) is
// punctuation with nothing before it: trimmed, so the comment reads "<!-- dropped_positive=… -->".
inline std::string tidyComment( std::string_view comment )
{
    std::string_view body = comment.substr( 4, comment.size() - 7 );   // between "<!--" and "-->"
    while( !body.empty() && ( body.front() == ' ' || body.front() == '.' || body.front() == ';' || body.front() == ':' ) )
    {
        body.remove_prefix( 1 );
    }
    return "<!-- " + std::string( body ) + "-->";
}

// The MCP `for` lens comment opens `<!-- ripwire lens for "TASK"`. When TASK is the root's own task= (escaped the same
// way) the echo repeats the root's identity, and a ref answer states it once: the opener goes, the notes after it stay
// (`<!-- [relevance floor: kept 1 of 40 …] -->`). Any difference — a task the comment scrub rewrote — keeps the comment
// whole. Returns the comment without the echo, or the comment unchanged.
inline std::string stripTaskEcho( std::string_view comment, std::string_view rootOpen )
{
    static constexpr std::string_view kOpen = "<!-- ripwire lens for \"";
    const std::size_t at = rootOpen.find( " task=\"" );
    if( !comment.starts_with( kOpen ) || at == std::string_view::npos )
    {
        return std::string( comment );
    }
    const std::size_t end = rootOpen.find( '"', at + 7 );
    if( end == std::string_view::npos )
    {
        return std::string( comment );
    }
    const std::string_view task = rootOpen.substr( at + 7, end - ( at + 7 ) );
    std::vector<char>      buf;
    for( std::size_t q = comment.find( '"', kOpen.size() ); q != std::string_view::npos; q = comment.find( '"', q + 1 ) )
    {
        if( escapeXml( comment.substr( kOpen.size(), q - kOpen.size() ), buf ) == task )
        {
            return "<!-- " + std::string( comment.substr( q + 1 ) );
        }
    }
    return std::string( comment );
}

// The row element a <g> group stands for, by the answer's schema (testmap.h: TestRowShape's tag at each emitter).
// A TABLE, not a chain of comparisons: the mapping is the fact, one row per emitter, and the lookup is the same
// ranges::find the schema tables here already use. Written as an if-chain it was also a token-for-token clone of
// mention.h's forHeaderPartnerKind — a duplication finding neither this lane nor main carries alone, emergent on
// the merge, and structural rather than cosmetic: the chain encoded a table in control flow.
struct GroupRowTag
{
    std::string_view key;
    std::string_view tag;
};

inline constexpr GroupRowTag kGroupRowTags[] =
{
    { "pack-task", "test" }, { "affected", "test" }, { "pr-context", "test" },
    { "test-gate", "t" },    { "handoff", "t" },     { "exercises", "t" },    { "flip", "t" },
};

inline std::string_view groupRowTag( std::string_view key ) noexcept
{
    const auto at = std::ranges::find( kGroupRowTags, key, &GroupRowTag::key );
    return at != std::end( kGroupRowTags ) ? at->tag : std::string_view{};
}

// `<g ATTRS n="N" p="a,b" run_unknown="1"/>` → N single rows `<TAG p="a"ATTRS run_unknown="1"/>`, or empty when the
// group is not that exact shape or holds more than 8 rows.
inline std::string ungroupRow( std::string_view g, std::string_view tag )
{
    static constexpr std::string_view kTail = " run_unknown=\"1\"/>";
    if( tag.empty() || !g.starts_with( "<g" ) || !g.ends_with( kTail ) )
    {
        return {};
    }
    const std::size_t nAt = g.find( " n=\"" );
    const std::size_t pAt = g.find( "\" p=\"", nAt == std::string_view::npos ? 0 : nAt );
    if( nAt == std::string_view::npos || pAt == std::string_view::npos )
    {
        return {};
    }
    const std::string_view attrs = g.substr( 2, nAt - 2 );
    const std::string_view nText = g.substr( nAt + 4, pAt - ( nAt + 4 ) );
    const std::string_view paths = g.substr( pAt + 5, g.size() - kTail.size() - 1 - ( pAt + 5 ) + 1 );
    if( paths.empty() || paths.back() != '"' || nText.empty() || nText.size() > 1 || nText[ 0 ] < '2' || nText[ 0 ] > '8' )
    {
        return {};
    }
    const std::string_view list  = paths.substr( 0, paths.size() - 1 );
    const std::size_t      count = static_cast<std::size_t>( nText[ 0 ] - '0' );
    if( std::size_t( std::count( list.begin(), list.end(), ',' ) ) + 1 != count )
    {
        return {};   // p= must split into exactly n= paths (testmap.h never groups a path holding ',')
    }
    std::string out;
    std::size_t begin = 0;
    for( std::size_t k = 0; k < count; ++k )
    {
        const std::size_t end = k + 1 == count ? list.size() : list.find( ',', begin );
        out += '<';
        out.append( tag );
        out += " p=\"";
        out.append( list.substr( begin, end - begin ) );
        out += '"';
        out.append( attrs );
        out.append( kTail );
        begin = end + 1;
    }
    return out;
}

// Un-group every eligible <g> in `body` (outside CDATA and comments), document order, while the bytes it adds fit `slack`.
inline void ungroupWithin( std::string& body, std::string_view tag, std::size_t& slack )
{
    if( tag.empty() )
    {
        return;
    }
    std::size_t i = 0;
    while( i < body.size() )
    {
        const std::string_view rest = std::string_view( body ).substr( i );
        if( rest.starts_with( "<![CDATA[" ) )
        {
            const std::size_t j = body.find( "]]>", i );
            i = j == std::string::npos ? body.size() : j + 3;
        }
        else if( rest.starts_with( "<!--" ) )
        {
            const std::size_t j = body.find( "-->", i );
            i = j == std::string::npos ? body.size() : j + 3;
        }
        else if( rest.starts_with( "<g " ) )
        {
            const std::size_t j = body.find( '>', i );
            if( j == std::string::npos )
            {
                return;
            }
            const std::string rows = ungroupRow( std::string_view( body ).substr( i, j + 1 - i ), tag );
            const std::size_t  was  = j + 1 - i;
            if( !rows.empty() && rows.size() >= was && rows.size() - was <= slack )
            {
                slack -= rows.size() - was;
                body.replace( i, was, rows );
                i += rows.size();
            }
            else
            {
                i = j + 1;
            }
        }
        else
        {
            const std::size_t j = body.find( '<', i + 1 );
            i = j == std::string::npos ? body.size() : j;
        }
    }
}

// The key of a compact schema id on the root (`schema="ripwire.KEY/v1"`), or empty.
inline std::string_view schemaKey( std::string_view rootOpen ) noexcept
{
    static constexpr std::string_view kOpen = " schema=\"ripwire.";
    const std::size_t at = rootOpen.find( kOpen );
    if( at == std::string_view::npos )
    {
        return {};
    }
    const std::size_t from = at + kOpen.size();
    const std::size_t end  = rootOpen.find( "/v1\"", from );
    return end == std::string_view::npos ? std::string_view() : rootOpen.substr( from, end - from );
}

inline std::size_t specEntryId( const CompactLegendSpec* spec ) noexcept
{
    return kPurposeBase + static_cast<std::size_t>( spec - kCompactLegendSpecs );
}

} // namespace detail

namespace detail
{

// What applyRefPosture needs to know about one answer before it touches it.
struct RefShape
{
    CompactRootInfo          root;
    std::string_view         rootOpen;
    std::string_view         key;              // the compact schema key, or empty (MCP `for`)
    const CompactLegendSpec* spec  = nullptr;  // the compact legend family, or null
    bool                     isFor = false;    // the MCP `for` bundle's native legend
    std::vector<Span>        head;
    std::string              closeTag;
    std::size_t              closeAt = 0;      // where the root's close begins (its open's end when self-closing)
    bool                     selfClosing = false;
};

// Which legend family the answer carries, and where its root closes; nullopt when the dictionary cannot reduce it (not
// XML, a legend it does not hold, or anything after the root's close).
inline std::optional<RefShape> inferRefShape( std::string_view view )
{
    RefShape s;
    s.root = findCompactRoot( view );
    if( s.root.tag.empty() )
    {
        return std::nullopt;   // a JSON or prose payload: no legend to reduce
    }
    s.rootOpen = view.substr( s.root.openBegin, s.root.openEnd - s.root.openBegin );
    s.key      = schemaKey( s.rootOpen );
    for( const CompactLegendSpec& c : kCompactLegendSpecs )
    {
        if( !s.key.empty() && c.rootTag == s.root.tag && c.key == s.key ) { s.spec = &c;  break; }
    }
    s.head  = headComments( view, s.root );
    s.isFor = s.spec == nullptr && s.root.tag == "ctx"
           && std::any_of( s.head.begin(), s.head.end(), [ & ]( const Span& c ) { return view.substr( c.begin ).starts_with( "<!-- ripwire lens for \"" ); } );
    if( s.spec == nullptr && !s.isFor )
    {
        return std::nullopt;   // a legend this dictionary does not hold stays inline, whole
    }
    s.selfClosing = s.rootOpen.ends_with( "/>" );
    s.closeTag    = "</" + std::string( s.root.tag ) + ">";
    const std::size_t closeAt = s.selfClosing ? s.root.openEnd : view.rfind( s.closeTag );
    const std::size_t after   = s.selfClosing ? s.root.openEnd : closeAt + s.closeTag.size();
    if( closeAt == std::string_view::npos || closeAt < s.root.openEnd || view.substr( after ).find_first_not_of( " \n\r\t" ) != std::string_view::npos )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "ref posture: the inline answer is served whole, every row and attribute unchanged",
                  "legenddict: the answer does not end with its root's close — nothing after it may move" );
        return std::nullopt;
    }
    s.closeAt = closeAt;
    return s;
}

// What the head comments leave: the entries the answer carries inline (`touched`, all marked served once it is sent)
// and the comments a ref answer keeps after its rows (`residual`: unserved entries and data).
struct HeadReduction
{
    std::vector<std::size_t> touched;
    std::vector<std::string> residual;
};

// THE compact legend, rebuilt from its parts — it must be byte-identical to what compactlegend.h wrote, or nothing is
// dropped. Its purpose and present terms are entries; its window and sub-cap clauses are core (served before any ref).
inline bool reduceCompactLegend( std::string_view comment, std::string_view view, const RefShape& s, const LegendSession& session,
                                 HeadReduction& r )
{
    const std::string_view docHead = compactDocHead( view, s.root );
    if( comment != compactLegendText( *s.spec, docHead, view ) )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "ref posture: the inline answer is served whole, every row and attribute unchanged",
                  "legenddict: the compact legend differs from its recomputed parts — no entry can be dropped safely" );
        return false;
    }
    // THE WITHHELD-MAP RECORD (L1 fix round, MED-3) reads its own purpose, not its schema's: the legend spells
    // kCompactWithheldMapPurpose where every other answer of that key spells spec.purpose. Its entry id would therefore
    // hand the session a definition the answer never carried, so this one record keeps its legend inline.
    if( isWithheldMapRecord( *s.spec, docHead ) )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "ref posture: the inline answer is served whole, every row and attribute unchanged",
                  "legenddict: the withheld-map record reads its own purpose, which is no dictionary entry — kept inline" );
        return false;
    }
    std::vector<std::size_t> ids{ specEntryId( s.spec ) };
    for( const std::uint16_t t : compactPresentTerms( docHead, view, s.spec->key ) )
    {
        ids.push_back( kTermBase + t );
    }
    std::string kept;
    for( const std::size_t id : ids )
    {
        r.touched.push_back( id );
        if( !session.isServed( id ) )
        {
            kept += kept.empty() ? "" : " ";
            kept.append( entryBody( id ) );
            kept += '.';
        }
    }
    if( !kept.empty() )
    {
        r.residual.push_back( "<!-- " + kept + " -->" );   // the schema id rides <about schema=>: no opener
    }
    return true;
}

// The fixed clauses a legend comment carries that the session was already sent come out of it (verbatim, longest first, so
// no match eats a longer one); every clause it carries is touched (it is sent now, in either posture).
inline std::string dropServedClauses( std::string rest, const std::vector<std::size_t>& forOrder, const LegendSession& session, HeadReduction& r )
{
    for( const std::size_t id : forOrder )
    {
        const std::size_t at = rest.find( entryBody( id ) );
        if( at == std::string::npos )
        {
            continue;
        }
        r.touched.push_back( id );
        if( session.isServed( id ) )
        {
            rest.erase( at, entryBody( id ).size() );
        }
    }
    return rest;
}

// fix #10: the how answer's own legend comment on an explore/pack-task answer (forhowbase.h kHowPackTaskLegendOpen)
inline bool isHowLegendComment( std::string_view comment ) noexcept
{
    return comment.starts_with( kHowPackTaskLegendOpen ) && comment.substr( kHowPackTaskLegendOpen.size() ).starts_with( "; " );
}

// Any other head comment: a native `for` legend — or the how answer's legend — loses every entry the session was already
// sent, and the `for` legend the task it echoes; a data comment moves whole. A how legend left with its opener alone
// defines nothing and goes.
inline bool reduceOtherComment( std::string_view comment, const RefShape& s, const std::vector<std::size_t>& forOrder,
                                const LegendSession& session, HeadReduction& r )
{
    std::string rest( comment );
    if( s.isFor )
    {
        rest = tidyComment( stripTaskEcho( dropServedClauses( std::move( rest ), forOrder, session, r ), s.rootOpen ) );
    }
    else if( isHowLegendComment( comment ) )
    {
        rest = tidyComment( dropServedClauses( std::move( rest ), forOrder, session, r ) );
        if( rest == std::string( kHowPackTaskLegendOpen ) + " -->" )
        {
            return true;
        }
    }
    if( isEmptyComment( rest ) )
    {
        return true;
    }
    if( rest.find( "--", 4 ) != rest.size() - 3 )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "ref posture: the inline answer is served whole, every row and attribute unchanged",
                  "legenddict: a reduced comment would hold \"--\" (ill-formed XML) — kept inline" );
        return false;
    }
    r.residual.push_back( std::move( rest ) );
    return true;
}

inline std::optional<HeadReduction> reduceHead( std::string_view view, const RefShape& s, const LegendSession& session )
{
    // The native legend's candidates: its fixed clauses, and the readings of the completeness terms it carries
    // (closeRosterGaps put any its own legend lacked into the answer).
    std::vector<std::size_t> forOrder;
    const bool hasHowLegend = std::any_of( s.head.begin(), s.head.end(), [ & ]( const Span& c ) { return view.substr( c.begin ).starts_with( kHowPackTaskLegendOpen ); } );
    if( s.isFor || hasHowLegend )
    {
        for( std::size_t k = 0; k < kForCount; ++k ) { forOrder.push_back( kForBase + k ); }
        for( const std::uint16_t t : compactPresentTerms( compactDocHead( view, s.root ), view ) ) { forOrder.push_back( kTermBase + t ); }
        std::sort( forOrder.begin(), forOrder.end(), []( std::size_t a, std::size_t b )
                   { return entryBody( a ).size() != entryBody( b ).size() ? entryBody( a ).size() > entryBody( b ).size() : a < b; } );
    }
    const std::string compactOpener = s.spec != nullptr ? compactLegendOpener( *s.spec ) : std::string();
    HeadReduction r;
    for( const Span& c : s.head )
    {
        const std::string_view comment = view.substr( c.begin, c.end - c.begin );
        const bool isLegend = s.spec != nullptr && comment.starts_with( compactOpener );
        if( !( isLegend ? reduceCompactLegend( comment, view, s, session, r ) : reduceOtherComment( comment, s, forOrder, session, r ) ) )
        {
            return std::nullopt;
        }
    }
    return r;
}

// The ref answer's four pieces: [before the root, head comments out] <root identity> rows [kept comments]<about/> </root>.
struct RefParts
{
    std::string prefix;
    std::string opened;
    std::string body;
    std::string trailer;

    std::size_t bytes( const RefShape& s ) const noexcept { return prefix.size() + opened.size() + body.size() + trailer.size() + s.closeTag.size(); }
};

inline RefParts assembleRef( std::string_view view, const RefShape& s, const HeadReduction& r )
{
    RefParts p;
    std::string moved;
    p.opened = "<" + std::string( s.root.tag );
    for( const RootAttr& a : startTagAttrs( s.rootOpen, s.root.nameEnd - s.root.openBegin ) )
    {
        bool isIdentity = false;
        for( const std::string_view k : kIdentityAttrs )
        {
            isIdentity = isIdentity || a.name == k;
        }
        ( isIdentity ? p.opened : moved ).append( a.whole );   // identity stays; the rest move, in order
    }
    p.opened += '>';
    std::size_t copied    = 0;
    std::size_t bodyBegin = s.root.openEnd;
    for( const Span& c : s.head )
    {
        if( c.begin < s.root.openBegin )
        {
            p.prefix.append( view.substr( copied, c.begin - copied ) );   // an XML declaration, if any, stays where it was
            copied = c.end;
        }
        else
        {
            bodyBegin = c.end;
        }
    }
    p.prefix.append( view.substr( copied, s.root.openBegin - copied ) );
    if( !s.selfClosing )
    {
        p.body.assign( view.substr( bodyBegin, s.closeAt - bodyBegin ) );
    }
    for( const std::string& kept : r.residual ) { p.trailer += kept; }
    p.trailer += "<about" + moved + " legend=\"ref\" dict=\"ripwire --legend-dict\" dictv=\"" + dictionaryVersion() + "\"/>";
    return p;
}

} // namespace detail

// Reduce one finished inline answer to the ref posture, in place — see the header. `doc` is the answer as the inline
// posture serves it: the compact dialect for a verb that declares `legend` (compactlegend.h already applied), the
// native legend for MCP `for`. Only called once `session.refOn`.
inline RefOutcome applyRefPosture( std::string& doc, LegendSession& session )
{
    EXPECTS( session.refOn, "the ref posture exists only after the session was served the dictionary core" );
    session.served.resize( kEntryCount, 0 );
    const std::string_view view = doc;
    const std::optional<detail::RefShape> shape = detail::inferRefShape( view );
    if( !shape )
    {
        return RefOutcome::NotApplicable;
    }
    const std::optional<detail::HeadReduction> head = detail::reduceHead( view, *shape, session );
    if( !head )
    {
        return RefOutcome::NotApplicable;
    }
    detail::RefParts  parts    = detail::assembleRef( view, *shape, *head );
    const std::size_t refBytes = parts.bytes( *shape );
    for( const std::size_t id : head->touched ) { session.markServed( id ); }   // sent now, in either posture
    if( refBytes > doc.size() )
    {
        // The trailer and the unserved entries cost more than the legend they replace: the inline answer is served and
        // everything it carried counts as served, so the next answer of this shape takes the ref posture.
        DISCLOSE( Diagnostics::answerUnchanged, "ref posture: the inline answer is served whole, every row and attribute unchanged",
                  "legenddict: the ref answer would be longer than the inline one — the budget the inline answer met holds" );
        return RefOutcome::InlineKept;
    }
    // L6: small runner-less groups print as rows, paid for by what the dropped legend freed.
    std::size_t slack = doc.size() - refBytes;
    detail::ungroupWithin( parts.body, detail::groupRowTag( shape->key ), slack );
    std::string out;
    out.reserve( doc.size() - slack );
    out += parts.prefix;
    out += parts.opened;
    out += parts.body;
    out += parts.trailer;
    out += shape->closeTag;
    ENSURES( out.size() <= doc.size(), "a ref answer is never longer than the inline answer it replaces" );
    doc.swap( out );
    return RefOutcome::Ref;
}

} // namespace rw::legenddict
