// foractedges.h — THE EDGES LINE of a `--for` page 1 (lane ACT-EDGES, 11-26; the switch and ACT-8's constants are
// foractedgesswitch.h, the wide act line foractline.h).
//
// WHY (tmp/orch-1125/hard-orient/RESULT.md, PA1 R BD n 12 + TR1 D n 22, the follow-on calls after the answer, P-cached): 11 % of
// retrieval cost (17 % on TR1) was a cross-file relation hunt from the answer's own symbols (usages, callers, callees), 8 % (10 %)
// an orientation hunt for the test, doc, changelog and build files that go with the files it named. Each answer already knows its
// act symbols, and the graph knows their edges and their tests; the agent re-derived both with greps and Reads.
//
// WHAT. Right after the act line (and so with it, before the fold, the bodies and the tail), when the page has one:
//   <edges><![CDATA[NAME: called by P:L N, P:L N (+K); calls P:L N (+K) | NAME2: …]]></edges>
//     for each of the act line's first kActShippedRanges symbols (the rows at those P:L): its 1-hop callers in non-test files (the
//     callers verb's rows and order, callhierarchy.h oneHopCallerRows) and its callees in OTHER non-test files (graph out-edges, call
//     edges only, one per name, fewest callers first: the specific helper before the utility), each exact-resolved first and
//     name-only (via="name") after (the θ6e rule), distinct files first; an edge whose target line an act range already holds is
//     left out (the agent reads it anyway), and so is the symbol itself. At most kEdgeCallers callers and kEdgeCallees callees per
//     symbol; (+K) counts the rest of that kind (a floor: resolved edges only).
//     A symbol with no such edge has no group; no group at all, no line.
// The bytes are COUNTED by paging (they are blocks of the row stream): they come out of the bottom of page 1, not out of an item
// (owner rule "answers to the top, then cut the bottom"; MODEL-V2: one item ≈ 36-47 KB of page 1).
//
// WHERE IT RUNS. Right after insertActLine, on the same raw render (so the answer-first permutation, KB1, paging and the row-line
// encoding treat the line as they treat every block). Its clause joins the leading legend run, as the act line's does;
// est_tokens= is re-priced for the added bytes through the render's ledger. Under RIPWIRE_ACT_EDGES=0 nothing is written: the answer is
// byte-identical to the one served before this lane. Gate: test/actedgescheck.sh.
#pragma once

#include "callhierarchy.h"      // oneHopCallerRows — the callers verb's rows, ranked before the cap
#include "filter.h"             // isTestPath — the one test-path convention
#include "foractedgesswitch.h"  // actEdgesOn, kActShippedRanges
#include "foractline.h"         // detail::listedRangeHolds / lineNumber — the act line's one containment test and number reader
#include "foranswerfirst.h"     // rootBody / topLevelBlocks
#include "forfilesyms.h"        // filesyms_detail::fanIn — a callee's caller count, the specificity order
#include "forbudgetfit.h"       // ForAnswerLedger
#include "forrowlines.h"        // unescaped — an attribute value as the agent reads it
#include "graph.h"              // Graph, edgeKindByte, kEdgeName, kEdgeLink
#include "model.h"
#include "sarif.h"              // rootRelativeUri / rootPrefixOf — p= as every row prints it
#include "serialize.h"          // attrOf, escapeXml, repriceRootAfterCut

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw::actedges
{

inline constexpr std::size_t kEdgeCallers = 2;   // callers shown per act symbol; (+K) counts the rest
inline constexpr std::size_t kEdgeCallees = 2;   // other-file callees shown per act symbol; (+K) counts the rest


namespace detail
{
// One act range as printed (escaped p=, numbers parsed).
struct ActRange
{
    std::string   p;   // unescaped: what lensRowPath prints before escaping
    std::uint32_t l = 0, e = 0;
};

// The act line's ranges, in order; empty for a value this reader does not know.
[[nodiscard]] inline std::vector<ActRange> actRanges( std::string_view value )
{
    std::vector<ActRange> out;
    for( std::size_t at = 0; at < value.size(); )
    {
        const std::size_t      next  = std::min( value.find( ',', at ), value.size() );
        const std::string_view item  = value.substr( at, next - at );
        const std::size_t      colon = item.rfind( ':' ), dash = item.rfind( '-' );
        if( colon == std::string_view::npos || dash == std::string_view::npos || dash < colon ) { return {}; }
        out.push_back( { rowlines::unescaped( item.substr( 0, colon ) ), actline::detail::lineNumber( item.substr( colon + 1, dash - colon - 1 ) ),
                         actline::detail::lineNumber( item.substr( dash + 1 ) ) } );
        at = next + 1;
    }
    return out;
}

// What the line reads: the index, the rows' path dialect, and the act line's ranges (raw value, for the containment test).
struct Ctx
{
    const IngestResult& ing;
    const Graph&        g;
    std::string         rootPrefix;   // "" = p= is ing.files as stored
    std::string_view    value;        // the act line's read= as printed
};

[[nodiscard]] inline std::string_view rowPath( const Ctx& c, std::uint32_t fileId )
{
    const std::string_view f = c.ing.files[ fileId ];
    return c.rootPrefix.empty() ? f : rw::sarif::rootRelativeUri( f, c.rootPrefix );
}

// The act range's symbol: the definition in that file that starts on that line (symbols are sorted by (fileId, line)).
[[nodiscard]] inline NodeId symbolAt( const Ctx& c, const ActRange& r )
{
    std::uint32_t fileId = UINT32_MAX;
    for( std::uint32_t f = 0; f < c.ing.files.size(); ++f )
    {
        if( rowPath( c, f ) == r.p ) { fileId = f; break; }
    }
    if( fileId == UINT32_MAX ) { return kNoNode; }
    const auto& syms = c.ing.symbols;
    const auto  it   = std::ranges::lower_bound( syms, std::pair{ fileId, r.l }, {}, []( const Symbol& s ) { return std::pair{ s.fileId, s.line }; } );
    return it != syms.end() && it->fileId == fileId && it->line == r.l ? NodeId( it - syms.begin() ) : kNoNode;
}

// Does an act range already hold the definition `n` starts at?
[[nodiscard]] inline bool heldByAct( const Ctx& c, NodeId n )
{
    const Symbol&     s    = c.ing.symbols[ n ];
    const std::string line = std::to_string( s.line );
    return actline::detail::listedRangeHolds( c.value, std::string( rowPath( c, s.fileId ) ) + ":" + line + "-" + line );
}

struct Edge
{
    NodeId n        = kNoNode;
    bool   nameOnly = false;
};

// Exact-resolved first, then name-only; within each, a file's first edge before any file's second (so a capped list names as many
// files as it can), the incoming order kept otherwise.
inline void rankEdges( const IngestResult& ing, std::vector<Edge>& edges )
{
    std::ranges::stable_partition( edges, []( const Edge& e ) { return !e.nameOnly; } );
    std::vector<Edge>          ranked;
    std::vector<std::uint32_t> seenFiles;
    for( const bool nameOnly : { false, true } )
    {
        std::vector<Edge> repeat;
        for( const Edge& e : edges )
        {
            if( e.nameOnly != nameOnly ) { continue; }
            const std::uint32_t f = ing.symbols[ e.n ].fileId;
            if( std::ranges::find( seenFiles, f ) == seenFiles.end() ) { seenFiles.push_back( f ); ranked.push_back( e ); }
            else { repeat.push_back( e ); }
        }
        ranked.insert( ranked.end(), repeat.begin(), repeat.end() );
    }
    edges.swap( ranked );
}

[[nodiscard]] inline std::vector<Edge> callersOf( const Ctx& c, NodeId id )
{
    std::vector<Edge> out;
    for( const NodeId r : oneHopCallerRows( c.ing, c.g, std::span<const NodeId>( &id, 1 ) ) )
    {
        if( r != id && !isTestPath( rowPath( c, c.ing.symbols[ r ].fileId ) ) && !heldByAct( c, r ) )
        {
            out.push_back( { r, edgeNameOnly( c.g, r, id ) } );
        }
    }
    rankEdges( c.ing, out );
    return out;
}

[[nodiscard]] inline std::vector<Edge> calleesOf( const Ctx& c, NodeId id )
{
    std::vector<Edge> out;
    if( std::size_t( id ) + 1 >= c.g.outOff.size() ) { return out; }
    const std::uint32_t home = c.ing.symbols[ id ].fileId;
    for( std::uint32_t k = c.g.outOff[ id ]; k < c.g.outOff[ std::size_t( id ) + 1 ]; ++k )
    {
        const NodeId       t    = c.g.outTargets[ k ];
        const std::uint8_t kind = c.g.outNameOnly.empty() ? 0 : edgeKindByte( c.g.outNameOnly[ k ] );
        if( t >= c.ing.symbols.size() || kind == kEdgeLink || c.ing.symbols[ t ].fileId == home ) { continue; }
        if( isTestPath( rowPath( c, c.ing.symbols[ t ].fileId ) ) || heldByAct( c, t ) ) { continue; }
        // one row per callee name: the overloads of one helper (emitTo's two) are one hunt
        if( std::ranges::any_of( out, [ & ]( const Edge& e ) { return c.ing.symbols[ e.n ].name == c.ing.symbols[ t ].name; } ) ) { continue; }
        out.push_back( { t, kind == kEdgeName } );
    }
    // the most specific callee first: a helper few symbols call says more about this one than a utility every file calls (emitTo)
    std::ranges::stable_sort( out, {}, [ & ]( const Edge& e ) { return filesyms_detail::fanIn( c.g, e.n ); } );
    rankEdges( c.ing, out );
    return out;
}

// "called by P:L N, P:L N (+K)" over the first `cap` edges; empty for none.
[[nodiscard]] inline std::string edgeGroup( const Ctx& c, std::string_view lead, const std::vector<Edge>& edges, std::size_t cap )
{
    if( edges.empty() ) { return {}; }
    std::string out( lead );
    for( std::size_t i = 0; i < edges.size() && i < cap; ++i )
    {
        const Symbol& s = c.ing.symbols[ edges[ i ].n ];
        out.append( i == 0 ? " " : ", " ).append( rowPath( c, s.fileId ) ).append( ":" ).append( std::to_string( s.line ) ).append( " " ).append( s.name );
    }
    if( edges.size() > cap ) { out.append( " (+" ).append( std::to_string( edges.size() - cap ) ).append( ")" ); }
    return out;
}

// The <edges> element for the act symbols, or "" when none has an edge to name (or the text could not ride a CDATA section).
[[nodiscard]] inline std::string edgesElement( const Ctx& c, const std::vector<NodeId>& syms )
{
    std::string text;
    for( const NodeId id : syms )
    {
        const std::string callers = edgeGroup( c, "called by", callersOf( c, id ), kEdgeCallers );
        const std::string callees = edgeGroup( c, "calls", calleesOf( c, id ), kEdgeCallees );
        if( callers.empty() && callees.empty() ) { continue; }
        text.append( text.empty() ? "" : " | " ).append( c.ing.symbols[ id ].name ).append( ": " ).append( callers );
        text.append( callers.empty() || callees.empty() ? "" : "; " ).append( callees );
    }
    if( text.empty() || text.find( "]]>" ) != std::string::npos ) { return {}; }
    return "<edges><![CDATA[" + text + "]]></edges>";
}

// The act line's symbols — the definitions its first kActShippedRanges ranges start at — and their files, in act order.
struct ActSymbols
{
    std::vector<NodeId>        syms;
    std::vector<std::uint32_t> files;
};
[[nodiscard]] inline ActSymbols actSymbols( const Ctx& c )
{
    ActSymbols                  out;
    const std::vector<ActRange> ranges = actRanges( c.value );
    for( std::size_t i = 0; i < ranges.size() && i < kActShippedRanges; ++i )
    {
        const NodeId n = symbolAt( c, ranges[ i ] );
        if( n == kNoNode || std::ranges::find( out.syms, n ) != out.syms.end() ) { continue; }
        out.syms.push_back( n );
        if( std::ranges::find( out.files, c.ing.symbols[ n ].fileId ) == out.files.end() ) { out.files.push_back( c.ing.symbols[ n ].fileId ); }
    }
    return out;
}

// Insert `lines` at `lineAt` (right after the act line) and `clauses` at `clauseAt` (the leading legend run, before it), then re-price
// est_tokens= for the added bytes: through the render's ledger when it is priced (kept current), else from the number alone.
inline void spliceLines( std::string& doc, std::size_t lineAt, const std::string& lines, std::size_t clauseAt, const std::string& clauses, ForAnswerLedger* ledger )
{
    const std::size_t before = doc.size();
    doc.insert( lineAt, lines );   // the later position first, so clauseAt still holds
    doc.insert( clauseAt, clauses );
    if( ledger != nullptr && ledger->priced )
    {
        repriceRootAfterCut( doc, PricedRootInputs{ ledger->markupBytes, ledger->bodyTokens }, before );
        ledger->markupBytes += doc.size() - before;
    }
    else
    {
        actline::detail::repriceAdded( doc, doc.size() - before );
    }
}
}   // namespace detail

// Write the EDGES line into `doc` — the raw render insertActLine just wrote its act line into — right after that line, its
// clause into the leading legend run. `rootArg` is the root the rows' p= are relative to ("" = as stored), as forBodyPointers passes
// it. `ledger`: the render's priced ledger, re-priced through and kept current (nullptr: no reprice, as the fallback path has none).
// Returns whether it wrote anything.
inline bool insertActEdges( std::string& doc, const IngestResult& ing, const Graph& g, std::string_view rootArg, ForAnswerLedger* ledger )
{
    const std::optional<answerfirst::RootBody> rb = actEdgesOn( kPartEdges ) && std::string_view( doc ).starts_with( "<ctx" ) ? answerfirst::rootBody( doc ) : std::nullopt;
    if( !rb ) { return false; }
    const std::vector<answerfirst::Block> blocks = answerfirst::topLevelBlocks( doc, rb->openEnd + 1, rb->closeAt );
    const auto act = std::ranges::find_if( blocks, []( const answerfirst::Block& b ) { return !b.comment && b.name == "act"; } );
    if( act == blocks.end() ) { return false; }
    const std::string        value( rw::attrOf( std::string_view( doc ).substr( act->begin, act->end - act->begin ), "read" ) );
    const detail::Ctx        c{ ing, g, rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( rootArg ), value };
    const detail::ActSymbols a = detail::actSymbols( c );
    if( a.syms.empty() ) { return false; }
    const std::string edges = actEdgesOn( kPartEdges ) ? detail::edgesElement( c, a.syms ) : std::string();
    if( edges.empty() ) { return false; }
    const auto        lead     = std::ranges::find_if( blocks, []( const answerfirst::Block& b ) { return !b.comment; } );
    const std::size_t clauseAt = lead == blocks.begin() ? rb->openEnd + 1 : std::prev( lead )->end;
    detail::spliceLines( doc, act->end, edges, clauseAt, std::string( kEdgesClause ), ledger );
    return true;
}

}   // namespace rw::actedges
