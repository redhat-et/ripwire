#pragma once
// forsiblingdemote.h — SIBLING-DEMOTE (precision card P1, variant b): a ranked <sigs> <d> row that is a lower sibling of a file the answer
// already shows, deep in the answer, is printed as a tail pointer `<t p="FILE" sym="NAME"/>` in its place (still printed, no longer an
// answer row). On the graded sets these rows are where most picked decoys sit (a same-file neighbour of the right row, median <d> rank 16),
// beside a right item that is already printed.
//
// THE RULE, read off the answer's own bytes (every block before <syms>, as the CLI and MCP `for` emit them — one renderer, both surfaces):
// a <d> row inside <sigs> is demoted when ALL hold
//   (r) its <d> rank (place among the answer's <d> rows) is past kDemoteMinRank,
//   (p) its answer-row position (the <d>, <y>, <s> and non-`used` <u> rows in output order) is past kDemoteMinPos — the first 10 answer
//       rows are never touched, so nothing moves up into them,
//   (f) a higher <d> row shows the same file,
// and no keep guard holds:
//   (K1) TYPE-WITH-MEMBERS: the row carries mem= (a type with its member list is a definition the reader follows, not a sibling decoy);
//   (K2) HOP-CALLEE: its name, or its last segment, is a callee <c n=> under a <h> hop row of the answer;
//   (K3) OWNER-NEAR: it is Owner.member / Owner::member and one of the kOwnerNearRows <d> rows right above it is named exactly Owner;
//   (K4) CALL-PATH: the index holds a call path of at most two PROVEN edges (a call: not bound by name alone, not a link) between it and
//        one of the first kCallPathSeeds resolved answer rows, either way round (ROW-FEATURES-2: a tail rule lost credited call-site
//        rows that are proven callers of the head);
//   (K5) a kept <d> row's same_as= names it (its doc+signature text is the one that row points to).
// The pointer keeps the row's p= and n= bytes; a short legend comment rides before the first one. A token budget (CLI --token-budget /
// --max-tokens, MCP budget_tokens) leaves the answer as shaped. The demoted bytes are priced markup, so the root's est_tokens= is
// re-priced once over both post-passes (R-DEDUP's tail cut, then this one: serialize.h repriceRootAfterCut).
// RIPWIRE_NO_SIBLING_DEMOTE=1 turns it off (byte identity and the gate's twins).
#include "forfilesyms.h" // FileSymsArgs, renderForFileSyms, filesyms_detail::FileLookup / leafName / unescapeXmlAttr
#include "graph.h" // Graph::outOff / outTargets / outNameOnly / inEdges, edgeIndex, edgeKindByte
#include "model.h"
#include "serialize.h" // attrOf, PricedRootInputs, repriceRootAfterCut

#include <algorithm>
#include <charconv>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iterator>
#include <ranges>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
inline constexpr std::size_t kDemoteMinRank = 5; // (r): rows past the 5th <d> row
inline constexpr std::size_t kDemoteMinPos = 10; // (p): rows past the first 10 answer rows
inline constexpr std::size_t kOwnerNearRows = 4; // (K3): the <d> rows right above that may name the owner
inline constexpr std::size_t kCallPathSeeds = 3; // (K4): the first resolved answer rows a call path may reach

inline constexpr std::string_view kSiblingDemoteLegend =
    "<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name), not the answer -->";

inline bool siblingDemoteOn()
{
    return std::getenv( "RIPWIRE_NO_SIBLING_DEMOTE" ) == nullptr;
}

namespace demote_detail
{
struct AnswerRow
{
    char tag = 0; // 'd', 'y', 's' or 'u'
    std::size_t at = 0, end = 0; // the element's bytes in the answer (a <d> row through its </d>)
    std::string_view attrs; // the open tag's attribute run
    std::string_view parentP; // the nearest enclosing element's p= (an <unused_in_file p=> table's <u> rows carry none of their own)
    std::size_t pos = 0; // 1-based answer-row position
    std::size_t dpos = 0; // 1-based <d> rank (0: not a <d> row)
    bool inSigs = false;
};
struct AnswerScan
{
    std::vector<AnswerRow> rows; // the answer rows in output order
    std::vector<std::string> callees; // n= of every <c> under a <h> hop row, unescaped
};

inline bool tagStarts( std::string_view rest, std::string_view name ) noexcept
{
    return rest.size() > name.size() + 1 && rest.substr( 1, name.size() ) == name && ( rest[name.size() + 1] == ' ' || rest[name.size() + 1] == '>' );
}

// One walk over the answer's tags outside comments and CDATA.
inline AnswerScan scanAnswer( std::string_view text )
{
    AnswerScan out;
    bool inSigs = false, inHop = false;
    std::size_t dRows = 0;
    std::vector<std::pair<std::string_view, std::string_view>> open; // (element name, its p=) of the open elements
    for( std::size_t i = text.find( '<' ); i != std::string_view::npos && i + 2 < text.size(); i = text.find( '<', i + 1 ) )
    {
        const std::string_view rest = text.substr( i );
        const std::string_view skipTo = rest.starts_with( "<!--" ) ? "-->" : rest.starts_with( "<![CDATA[" ) ? "]]>"
                                                                                                             : "";
        if( !skipTo.empty() )
        {
            const std::size_t end = text.find( skipTo, i );
            if( end == std::string_view::npos )
            {
                break;
            }
            i = end;
            continue;
        }
        const std::size_t close = text.find( '>', i );
        if( close == std::string_view::npos )
        {
            break;
        }
        if( rest[1] == '/' )
        {
            const std::string_view name = text.substr( i + 2, close - i - 2 );
            inSigs = inSigs && name != "sigs";
            inHop = inHop && name != "h";
            const auto at = std::ranges::find( open | std::views::reverse, name, &std::pair<std::string_view, std::string_view>::first );
            open.erase( at == open.rend() ? open.end() : std::prev( at.base() ), open.end() );
            continue;
        }
        const bool selfClosing = text[close - 1] == '/';
        const std::size_t nameEnd = std::min( text.find_first_of( " />", i + 1 ), close );
        const std::string_view attrs = text.substr( nameEnd, close - nameEnd - ( selfClosing ? 1 : 0 ) );
        const std::string_view parentP = [&]
        {
            const auto withP = std::ranges::find_if( open | std::views::reverse, []( const auto& e ) { return !e.second.empty(); } );
            return withP == open.rend() ? std::string_view() : withP->second;
        }();
        if( !selfClosing && rest[1] != '?' && rest[1] != '!' )
        {
            open.emplace_back( text.substr( i + 1, nameEnd - i - 1 ), attrOf( attrs, "p" ) );
        }
        if( tagStarts( rest, "sigs" ) )
        {
            inSigs = !selfClosing;
        }
        else if( tagStarts( rest, "h" ) && rest[2] == ' ' )
        {
            inHop = !selfClosing;
        }
        else if( inHop && rest[1] == 'c' && rest[2] == ' ' )
        {
            out.callees.push_back( filesyms_detail::unescapeXmlAttr( attrOf( attrs, "n" ) ) );
        }
        else if( const char k = rest[1]; ( k == 'd' || k == 'y' || k == 's' || k == 'u' ) && rest[2] == ' ' && !( k == 'u' && attrOf( attrs, "v" ) == "used" ) )
        {
            AnswerRow r { .tag = k, .at = i, .end = close + 1, .attrs = attrs, .parentP = parentP, .pos = out.rows.size() + 1, .inSigs = inSigs };
            if( k == 'd' )
            {
                r.dpos = ++dRows;
                const std::size_t endTag = selfClosing ? std::string_view::npos : text.find( "</d>", close );
                r.end = endTag == std::string_view::npos ? r.end : endTag + 4;
            }
            out.rows.push_back( r );
        }
        i = close;
    }
    return out;
}

inline std::string_view fileOf( const AnswerRow& r )
{
    const std::string_view p = attrOf( r.attrs, "p" );
    return p.substr( 0, p.find( ':' ) );
}
// The last segment after `.`, `#` or `::` (the whole name when there is none).
inline std::string_view lastSegment( std::string_view n ) noexcept
{
    const std::size_t dot = n.find_last_of( ".#" );
    const std::size_t colons = n.rfind( "::" );
    const std::size_t dotAfter = dot == std::string_view::npos ? 0 : dot + 1;
    const std::size_t colonsAfter = colons == std::string_view::npos ? 0 : colons + 2;
    return n.substr( std::max( dotAfter, colonsAfter ) );
}
// Owner of Owner.member / Owner::member: the name up to its first `.` or `::` ("" when it has neither).
inline std::string_view firstSegment( std::string_view n ) noexcept
{
    const std::size_t cut = std::min( n.find( '.' ), n.find( "::" ) );
    return cut == std::string_view::npos ? std::string_view() : n.substr( 0, cut );
}

inline bool hasMembers( const AnswerRow& r ) noexcept
{
    return r.attrs.contains( " mem=\"" );
}
inline bool hopCallee( const AnswerScan& scan, std::string_view name )
{
    const std::string_view last = lastSegment( name );
    return std::ranges::any_of( scan.callees, [&]( const std::string& c )
                                { return c == name || c == last; } );
}
inline bool ownerNear( const std::vector<const AnswerRow*>& dRows, const AnswerRow& r, std::string_view name )
{
    const std::string_view owner = firstSegment( name );
    if( owner.empty() )
    {
        return false;
    }
    for( std::size_t k = r.dpos > kOwnerNearRows ? r.dpos - kOwnerNearRows : 1; k < r.dpos; ++k )
    {
        if( filesyms_detail::unescapeXmlAttr( attrOf( dRows[k - 1]->attrs, "n" ) ) == owner )
        {
            return true;
        }
    }
    return false;
}

// The index definition an answer row names: in its file, by its last segment, at its line when one is (first by id otherwise).
struct RowWant
{
    std::uint32_t file = UINT32_MAX, line = 0;
    std::string leaf;
    NodeId id = kNoNode;
    bool atLine = false;
};
inline RowWant rowWant( filesyms_detail::FileLookup& files, const AnswerRow& r )
{
    RowWant w;
    const std::string_view ownP = attrOf( r.attrs, "p" );
    std::string p = filesyms_detail::unescapeXmlAttr( ownP.empty() ? r.parentP : ownP );
    const std::string_view l = attrOf( r.attrs, "l" );
    std::from_chars( l.data(), l.data() + l.size(), w.line );
    if( const std::size_t colon = p.rfind( ':' ); colon != std::string::npos && colon + 1 < p.size()
        && std::ranges::all_of( std::string_view( p ).substr( colon + 1 ), []( char c ) { return c >= '0' && c <= '9'; } ) )
    {
        const std::string_view tail = std::string_view( p ).substr( colon + 1 );
        std::uint32_t line = 0;
        std::from_chars( tail.data(), tail.data() + tail.size(), line );
        w.line = w.line != 0 ? w.line : line;
        p.resize( colon );
    }
    w.file = p.empty() ? UINT32_MAX : files.of( p );
    w.leaf = std::string( filesyms_detail::leafName( filesyms_detail::unescapeXmlAttr( attrOf( r.attrs, "n" ) ) ) );
    return w;
}
// ONE pass over the symbols resolves every wanted row.
inline void resolveWants( const IngestResult& ing, std::vector<RowWant>& wants )
{
    std::vector<std::uint32_t> wantedFiles;
    for( const RowWant& w : wants )
    {
        wantedFiles.push_back( w.file );
    }
    std::ranges::sort( wantedFiles );
    for( const Symbol& s : ing.symbols )
    {
        if( !std::ranges::binary_search( wantedFiles, s.fileId ) )
        {
            continue;
        }
        for( RowWant& w : wants )
        {
            if( w.file == s.fileId && !w.atLine && s.name == w.leaf && ( w.id == kNoNode || s.line == w.line ) )
            {
                w.id = s.id;
                w.atLine = s.line == w.line;
            }
        }
    }
}

inline bool provenEdge( const Graph& g, std::size_t edge ) noexcept
{
    return edge != SIZE_MAX && ( g.outNameOnly.empty() || ( edge < g.outNameOnly.size() && edgeKindByte( g.outNameOnly[edge] ) == 0 ) );
}
// Proven out-neighbours (forward) or in-neighbours (!forward) of `u`, itself left out.
template<class F>
inline void forProvenNeighbours( const Graph& g, NodeId u, bool forward, F&& visit )
{
    if( forward )
    {
        for( std::uint32_t k = std::size_t( u ) + 1 < g.outOff.size() ? g.outOff[u] : 0; std::size_t( u ) + 1 < g.outOff.size() && k < g.outOff[u + 1]; ++k )
        {
            if( g.outTargets[k] != u && provenEdge( g, k ) )
            {
                visit( g.outTargets[k] );
            }
        }
        return;
    }
    const std::uint32_t* ro = g.inEdges.rowOffsets();
    const std::uint32_t* ci = g.inEdges.colIndices();
    if( ro == nullptr || ci == nullptr || std::size_t( u ) >= g.inEdges.rows() )
    {
        return;
    }
    for( std::uint32_t k = ro[u]; k < ro[u + 1]; ++k )
    {
        if( ci[k] != u && provenEdge( g, edgeIndex( g, ci[k], u ) ) )
        {
            visit( NodeId( ci[k] ) );
        }
    }
}
// The seeds' one-hop proven neighbourhoods, each way round: a row is within two proven hops of a seed when the seed, or a node one hop
// from it in the same direction, is its own neighbour.
struct SeedReach
{
    std::vector<NodeId> seeds;
    std::vector<std::pair<NodeId, NodeId>> out1, in1; // (node, seed) sorted: node is one proven hop after / before seed
};
inline SeedReach seedReach( const Graph& g, std::vector<NodeId> seeds )
{
    SeedReach r { .seeds = std::move( seeds ) };
    for( const NodeId s : r.seeds )
    {
        forProvenNeighbours( g, s, true, [&]( NodeId v ) { r.out1.emplace_back( v, s ); } );
        forProvenNeighbours( g, s, false, [&]( NodeId v ) { r.in1.emplace_back( v, s ); } );
    }
    std::ranges::sort( r.out1 );
    std::ranges::sort( r.in1 );
    return r;
}
inline bool provenPathToSeed( const Graph& g, const SeedReach& sr, NodeId id )
{
    const auto otherSeed = [&]( NodeId s ) { return s != id && std::ranges::contains( sr.seeds, s ); };
    const auto oneHopFromOther = [&]( const std::vector<std::pair<NodeId, NodeId>>& hop1, NodeId v )
    {
        const auto [lo, hi] = std::ranges::equal_range( hop1, v, {}, &std::pair<NodeId, NodeId>::first );
        return std::ranges::any_of( lo, hi, [&]( const auto& e ) { return e.second != id; } );
    };
    bool found = false;
    // the row reaches a seed: row -> seed, or row -> v -> seed (v one hop before the seed)
    forProvenNeighbours( g, id, true, [&]( NodeId v ) { found = found || otherSeed( v ) || oneHopFromOther( sr.in1, v ); } );
    // a seed reaches the row: seed -> row, or seed -> v -> row (v one hop after the seed)
    forProvenNeighbours( g, id, false, [&]( NodeId v ) { found = found || otherSeed( v ) || oneHopFromOther( sr.out1, v ); } );
    return found;
}

// The answer with the demoted rows rewritten as tail pointers; "" when none is.
inline std::string demoteSiblingRows( const IngestResult& ing, const Graph& g, std::string_view answer )
{
    const AnswerScan scan = scanAnswer( answer );
    std::vector<const AnswerRow*> dRows;
    for( const AnswerRow& r : scan.rows )
    {
        if( r.tag == 'd' )
        {
            dRows.push_back( &r );
        }
    }
    std::vector<const AnswerRow*> picked; // (r)(p)(f) and not K1-K3, in answer order
    for( const AnswerRow* r : dRows )
    {
        if( !r->inSigs || r->dpos <= kDemoteMinRank || r->pos <= kDemoteMinPos || hasMembers( *r ) )
        {
            continue;
        }
        const std::string_view file = fileOf( *r );
        const bool sameFileAbove = std::any_of( dRows.begin(), dRows.begin() + std::ptrdiff_t( r->dpos - 1 ), [&]( const AnswerRow* x ) { return fileOf( *x ) == file; } );
        const std::string name = filesyms_detail::unescapeXmlAttr( attrOf( r->attrs, "n" ) );
        if( sameFileAbove && !hopCallee( scan, name ) && !ownerNear( dRows, *r, name ) )
        {
            picked.push_back( r );
        }
    }
    if( picked.empty() )
    {
        return {};
    }
    // K4: every answer row resolved in one pass — the seeds are the first kCallPathSeeds distinct ones
    filesyms_detail::FileLookup files( ing );
    std::vector<RowWant> wants;
    for( const AnswerRow& r : scan.rows )
    {
        wants.push_back( rowWant( files, r ) );
    }
    resolveWants( ing, wants );
    std::vector<NodeId> seeds;
    for( std::size_t k = 0; k < wants.size() && seeds.size() < kCallPathSeeds; ++k )
    {
        if( wants[k].id != kNoNode && !std::ranges::contains( seeds, wants[k].id ) )
        {
            seeds.push_back( wants[k].id );
        }
    }
    const SeedReach reach = seedReach( g, std::move( seeds ) );
    std::vector<char> demote( scan.rows.size(), 0 );
    for( const AnswerRow* r : picked )
    {
        const NodeId id = wants[r->pos - 1].id;
        demote[r->pos - 1] = id == kNoNode || !provenPathToSeed( g, reach, id ) ? 1 : 0;
    }
    // K5: a kept <d> row's same_as= names the row its text stands for — that row stays (to a fixpoint: a row kept here may name another)
    for( bool changed = true; changed; )
    {
        changed = false;
        for( const AnswerRow* kept : dRows )
        {
            const std::string_view sameAs = demote[kept->pos - 1] != 0 ? std::string_view() : attrOf( kept->attrs, "same_as" );
            for( const AnswerRow* r : picked )
            {
                if( !sameAs.empty() && demote[r->pos - 1] != 0 && attrOf( r->attrs, "n" ) == sameAs )
                {
                    demote[r->pos - 1] = 0;
                    changed = true;
                }
            }
        }
    }
    std::string out;
    std::size_t from = 0;
    for( const AnswerRow* r : picked )
    {
        if( demote[r->pos - 1] == 0 )
        {
            continue;
        }
        out.append( answer.substr( from, r->at - from ) );
        out += from == 0 ? kSiblingDemoteLegend : std::string_view();
        out += "<t p=\"";
        out += attrOf( r->attrs, "p" );
        out += "\" sym=\"";
        out += attrOf( r->attrs, "n" );
        out += "\"/>";
        from = r->end;
    }
    return from == 0 ? std::string() : out.append( answer.substr( from ) );
}
} // namespace demote_detail

// The <syms> block for one answer (forfilesyms.h renderForFileSyms), and in *a.answerOut the answer's own bytes after both post-passes —
// R-DEDUP's head-file tail cut, then SIBLING-DEMOTE — re-priced once ("" when neither changed a byte). CLI appendForFileSyms and MCP
// insertFileSyms both call this.
inline std::string renderForFileSymsAndDemote( const IngestResult& ing, const Graph& g, FileSymsArgs a )
{
    std::string* const answerOut = a.answerOut;
    const PricedRootInputs* const price = a.price;
    std::string cut;
    a.answerOut = answerOut != nullptr ? &cut : nullptr;
    a.price = nullptr; // priced once below, over both cuts
    std::string syms = renderForFileSyms( ing, g, a );
    if( answerOut == nullptr || a.answer.empty() )
    {
        return syms;
    }
    std::string demoted = a.held || !siblingDemoteOn() ? std::string() : demote_detail::demoteSiblingRows( ing, g, cut.empty() ? a.answer : std::string_view( cut ) );
    std::string& done = demoted.empty() ? cut : demoted;
    if( price != nullptr && !done.empty() ) // the cuts are priced markup: est_tokens= prices the bytes sent
    {
        repriceRootAfterCut( done, *price, a.answer.size() - done.size() );
    }
    *answerOut = std::move( done );
    return syms;
}
} // namespace rw
