#pragma once
// foronesidereach.h — ONE-SIDE-REACH (precision card, the BLIND form of its Stage 0): a --for question that names two endpoints
// ("how do A and B connect", "A + B", "pass a parameter into B from A") is answered by the rows ON the call paths between them. A
// printed row that reaches only one of the two is the wrapper above the root, the sibling branch, the caller of one sink: on the
// graded sets it was the largest class of picked decoys (30 items, 11 of them at rank 1). Such a row is printed in its place as a
// tail pointer `<t p="FILE" sym="NAME" r="RANK"/>` (still on screen, no longer an answer row).
//
// THE RULE, once per answer (every reach set below is computed once, never per row):
//   (E) the task spells exactly two identifier-syntax words (camelCase, snake_case, a qualified Owner::name / pkg.Name), each placing
//       1..kOneSideMaxEndpointDefs definitions (subjectanchor.h placeCandidates, its qualifier test): the endpoints A and B, every
//       definition a seed (the --impact reading of a name: TypeScript's createProgram is 14 definitions, overloads and .d.ts twins).
//       Any other count of names: the rule is off.
//   (M) ROOT/SINK when the index holds a call path A -> B (or B -> A) of at most kOneSideRootPathMaxHops edges (graph.h
//       shortestPathAny): R -> S. Otherwise TWO SINKS {A, B} (a common-caller question).
//   (S) the two sides of a row, from bounded walks of kOneSideReachHops calls over every edge (the --impact walk, graph.h
//       expandCallers, and its forward twin): two sinks — the row reaches A / the row reaches B; root/sink — R reaches the row / the
//       row reaches S. A row is resolved to every definition of its name in its file (an overload's declaration and its
//       implementation, line 1514 and 1515, are one row) and, for a C/C++ header declaration, the definitions whose file answers
//       that header (forfilesyms.h DeclHome).
//   (G) GATE: some printed row is on BOTH sides. Where the index lacks an edge of the true chain nothing is, the true common caller
//       looks one-sided, and the rule stays off (no answer byte changes).
//   (D) a <sigs> <d>, <callers> <s> or <syms> <y> row is demoted when it is on exactly one side (root/sink: it reaches S and R does
//       not reach it; a direct caller of S stays), and it is not an endpoint and not on a shortest path between them: two sinks —
//       every node of a shortest path from a both-sides row to A and to B (the first kOneSideMaxPathSources such rows); root/sink —
//       the nodes of the shortest R -> S path.
// The pointer keeps the row's file, name and r= bytes; a short legend comment rides before the first one. A token budget (CLI
// --token-budget / --max-tokens, MCP budget_tokens) leaves the answer as shaped. The <d>/<s> rows are priced markup, so the root's
// est_tokens= is re-priced over the rewritten bytes (serialize.h repriceRootAfterCut, signed); <syms> is outside the price.
// RIPWIRE_NO_ONE_SIDE_REACH=1 turns it off (byte identity and the gate's twins).
#include "forfilesyms.h" // filesyms_detail::FileLookup / DeclHome / leafName / unescapeXmlAttr / attrOf / bodylessHeaderDecl
#include "graph.h" // shortestPathAny, expandCallers
#include "lexical.h" // splitRouteWords, isRouteStopword, routeLower, detail::graphSubjectTrimWord
#include "model.h"
#include "subjectanchor.h" // subject_detail::hasNameSyntax / parseSpelling / placeCandidates

#include <algorithm>
#include <charconv>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
inline constexpr std::uint32_t kOneSideReachHops = 3; // (S): calls a side walk follows from an endpoint
inline constexpr std::size_t kOneSideRootPathMaxHops = 6; // (M): the longest A -> B path read as a root/sink question (two side walks)
inline constexpr std::size_t kOneSideMaxPathSources = 8; // (D): both-sides rows whose shortest paths to A and B are kept
inline constexpr std::size_t kOneSideMaxEndpointDefs = 32; // (E): definitions one endpoint name may place (more: a namesake flood, the rule is off)

inline constexpr std::string_view kOneSideReachLegend =
    "<!-- one-side: a <t> among sigs, callers or syms rows reaches only one of the two named endpoints within 3 calls and is on no shortest "
    "path between them, a pointer (p= file, sym= name, r= rank), not the answer -->";

inline bool oneSideReachOn()
{
    return std::getenv( "RIPWIRE_NO_ONE_SIDE_REACH" ) == nullptr;
}

namespace onesidereach_detail
{
inline constexpr std::uint32_t kUnreached = UINT32_MAX;

struct Endpoints
{
    std::vector<NodeId> a, b; // NodeId order
};
// (E): exactly two identifier-syntax words of the task, each placing 1..kOneSideMaxEndpointDefs definitions.
inline std::optional<Endpoints> twoNamedEndpoints( const IngestResult& ing, std::string_view task )
{
    std::vector<std::string_view> named;
    std::vector<subject_detail::Spelling> spelled;
    for( const std::string_view w : splitRouteWords( task ) )
    {
        const std::string_view t = detail::graphSubjectTrimWord( w ).text;
        if( isRouteStopword( routeLower( t ) ) || !subject_detail::hasNameSyntax( t ) || std::ranges::contains( named, t ) )
        {
            continue;
        }
        const subject_detail::Spelling sp = subject_detail::parseSpelling( t );
        if( !sp.valid || named.size() == 2 )
        {
            return std::nullopt; // a name the index cannot place by spelling, or a third name: not a two-endpoint question
        }
        named.push_back( t );
        spelled.push_back( sp );
    }
    if( named.size() != 2 )
    {
        return std::nullopt;
    }
    std::vector<std::vector<NodeId>> placed = subject_detail::placeCandidates( ing, spelled );
    for( const std::vector<NodeId>& defs : placed )
    {
        if( defs.empty() || defs.size() > kOneSideMaxEndpointDefs )
        {
            return std::nullopt;
        }
    }
    if( std::ranges::any_of( placed[0], [&]( NodeId id ) { return std::ranges::binary_search( placed[1], id ); } ) )
    {
        return std::nullopt; // one definition answers both names
    }
    return Endpoints { .a = std::move( placed[0] ), .b = std::move( placed[1] ) };
}

// Hop distance of every node from `seeds` within kOneSideReachHops calls (kUnreached past it): callers (`forward` false: who reaches a
// seed, the --impact walk, graph.h expandCallers one level at a time) or callees (`forward`: what a seed reaches).
inline std::vector<std::uint32_t> boundedReach( const Graph& g, std::span<const NodeId> seeds, bool forward )
{
    const std::size_t N = g.wOutDeg.size();
    std::vector<char> seen( N, 0 );
    std::vector<std::uint32_t> depth( N, 0 );
    std::vector<NodeId> q;
    enqueueUnseen( seeds, 0, seen, depth, q );
    for( std::size_t head = 0, level = 0; level < kOneSideReachHops && head < q.size(); ++level )
    {
        const std::size_t end = q.size();
        if( !forward )
        {
            head = expandCallers( g, q, head, end, seen, depth );
            continue;
        }
        for( ; head < end; ++head )
        {
            const NodeId u = q[head];
            for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
            {
                if( const NodeId v = g.outTargets[k]; v < N && !seen[v] )
                {
                    seen[v] = 1;
                    depth[v] = depth[u] + 1;
                    q.push_back( v );
                }
            }
        }
    }
    for( std::size_t n = 0; n < N; ++n )
    {
        depth[n] = seen[n] != 0 ? depth[n] : kUnreached;
    }
    return depth;
}

struct Row
{
    char tag = 0; // 'd' (<sigs>), 's' (<callers>) or 'y' (<syms>)
    bool inSyms = false; // the row's bytes are in the <syms> text, not the answer's
    std::size_t at = 0, end = 0; // the element's bytes (a <d> row through its </d>)
    std::string_view attrs; // the open tag's attribute run
    std::vector<NodeId> seeds; // every definition the row stands for (sorted)
};

inline bool tagIs( std::string_view rest, std::string_view name ) noexcept
{
    return rest.size() > name.size() + 1 && rest.substr( 1, name.size() ) == name
        && ( rest[name.size() + 1] == ' ' || rest[name.size() + 1] == '>' || rest[name.size() + 1] == '/' );
}
// The <d> rows inside <sigs>, the <s> rows inside <callers> and the <y> rows inside <syms> of `text`, outside comments and CDATA.
inline void scanRows( std::string_view text, bool inSyms, std::vector<Row>& out )
{
    char block = 0; // the open row block: 'd' in <sigs>, 's' in <callers>, 'y' in <syms>
    for( std::size_t i = text.find( '<' ); i != std::string_view::npos && i + 2 < text.size(); i = text.find( '<', i + 1 ) )
    {
        const std::string_view rest = text.substr( i );
        // comments, CDATA, and the graph-verb blocks appended after the priced answer (their path rows are the verb's, not the answer's)
        const std::string_view skipTo = rest.starts_with( "<!--" ) ? "-->" : rest.starts_with( "<![CDATA[" ) ? "]]>"
                                      : tagIs( rest, "graph_verb" ) ? "</graph_verb>" : tagIs( rest, "path_gap" ) ? "</path_gap>" : "";
        const std::size_t close = skipTo.empty() ? text.find( '>', i ) : text.find( skipTo, i );
        if( close == std::string_view::npos )
        {
            break;
        }
        const bool selfClosing = skipTo.empty() && text[close - 1] == '/';
        if( !skipTo.empty() )
        {
            i = close;
            continue;
        }
        if( rest.starts_with( "</sigs>" ) || rest.starts_with( "</callers>" ) || rest.starts_with( "</syms>" ) )
        {
            block = 0;
        }
        else if( !selfClosing && ( tagIs( rest, "sigs" ) || tagIs( rest, "callers" ) || tagIs( rest, "syms" ) ) )
        {
            block = rest[2] == 'i' ? 'd' : rest[2] == 'a' ? 's' : 'y';
        }
        else if( block != 0 && rest[1] == block && rest[2] == ' ' )
        {
            const std::size_t endTag = block == 'd' && !selfClosing ? text.find( "</d>", close ) : std::string_view::npos;
            out.push_back( Row { .tag = block, .inSyms = inSyms, .at = i, .end = endTag == std::string_view::npos ? close + 1 : endTag + 4,
                                 .attrs = text.substr( i + 2, close - i - 2 - ( selfClosing ? 1 : 0 ) ) } );
        }
        i = close;
    }
}

// Every definition each row stands for, in ONE pass over the symbols: the definitions of its leaf name in its file (the one at its line
// first fixes the scope: an overload's declaration and implementation, a member's in-class declaration and its definition), and for a
// C/C++ header declaration the same (scope, name) in each file that answers the header (DeclHome).
inline void resolveSeeds( const IngestResult& ing, const Graph& g, std::vector<Row>& rows )
{
    filesyms_detail::FileLookup files( ing );
    struct Want
    {
        std::uint32_t file = UINT32_MAX, line = 0;
        std::string leaf;
        NodeId atLine = kNoNode;
    };
    std::vector<Want> wants;
    for( const Row& r : rows )
    {
        Want w;
        std::string p = filesyms_detail::unescapeXmlAttr( filesyms_detail::attrOf( r.attrs, "p" ) );
        const std::string_view l = filesyms_detail::attrOf( r.attrs, "l" );
        std::from_chars( l.data(), l.data() + l.size(), w.line );
        if( const std::size_t colon = p.rfind( ':' ); colon != std::string::npos && colon + 1 < p.size()
            && std::ranges::all_of( std::string_view( p ).substr( colon + 1 ), []( char c ) { return c >= '0' && c <= '9'; } ) )
        {
            std::from_chars( p.data() + colon + 1, p.data() + p.size(), w.line );
            p.resize( colon );
        }
        w.file = p.empty() ? UINT32_MAX : files.of( p );
        w.leaf = std::string( filesyms_detail::leafName( filesyms_detail::unescapeXmlAttr( filesyms_detail::attrOf( r.attrs, "n" ) ) ) );
        wants.push_back( std::move( w ) );
    }
    std::vector<std::uint32_t> wantedFiles;
    for( const Want& w : wants )
    {
        wantedFiles.push_back( w.file );
    }
    std::ranges::sort( wantedFiles );
    std::vector<std::vector<NodeId>> sameName( rows.size() );
    for( const Symbol& s : ing.symbols )
    {
        if( !std::ranges::binary_search( wantedFiles, s.fileId ) )
        {
            continue;
        }
        for( std::size_t k = 0; k < wants.size(); ++k )
        {
            if( wants[k].file == s.fileId && s.name == wants[k].leaf )
            {
                sameName[k].push_back( s.id );
                wants[k].atLine = wants[k].atLine == kNoNode && s.line == wants[k].line ? s.id : wants[k].atLine;
            }
        }
    }
    std::vector<std::size_t> headerRows; // rows with a C/C++ header declaration among their seeds
    for( std::size_t k = 0; k < rows.size(); ++k )
    {
        const NodeId at = wants[k].atLine;
        for( const NodeId id : sameName[k] )
        {
            if( at == kNoNode || ing.symbols[id].scope == ing.symbols[at].scope )
            {
                rows[k].seeds.push_back( id );
            }
        }
        if( std::ranges::any_of( rows[k].seeds, [&]( NodeId id ) { return filesyms_detail::bodylessHeaderDecl( ing, ing.symbols[id] ); } ) )
        {
            headerRows.push_back( k );
        }
    }
    if( !headerRows.empty() )
    {
        filesyms_detail::DeclHome home( ing, g );
        for( const Symbol& s : ing.symbols )
        {
            for( const std::size_t k : headerRows )
            {
                const Symbol& decl = ing.symbols[rows[k].seeds.front()];
                if( s.name == wants[k].leaf && s.fileId != decl.fileId && s.scope == decl.scope && !filesyms_detail::bodylessSymbol( s )
                    && home.answers( s.fileId, decl.fileId ) )
                {
                    rows[k].seeds.push_back( s.id );
                }
            }
        }
    }
    for( Row& r : rows )
    {
        std::ranges::sort( r.seeds );
    }
}

// The per-answer reach facts (S) and the kept path nodes (D): computed once, read by every row.
struct Sides
{
    bool rootSink = false;
    std::vector<std::uint32_t> one, two; // two sinks: hops to A / to B; root/sink: hops from R / to S
    std::vector<NodeId> endpoints, onPath; // sorted
};
inline std::uint32_t minHops( const std::vector<std::uint32_t>& d, const Row& r )
{
    std::uint32_t best = kUnreached;
    for( const NodeId id : r.seeds )
    {
        best = std::min( best, d[id] );
    }
    return best;
}
inline bool onBothSides( const Sides& s, const Row& r )
{
    return minHops( s.one, r ) != kUnreached && minHops( s.two, r ) != kUnreached;
}
inline bool anySeedIn( const std::vector<NodeId>& sorted, const Row& r )
{
    return std::ranges::any_of( r.seeds, [&]( NodeId id ) { return std::ranges::binary_search( sorted, id ); } );
}

// Every node of a shortest path from `from` to the sink set whose hop distances are `toSink` (each step one hop nearer).
inline void addShortestPathNodes( const Graph& g, std::span<const NodeId> from, const std::vector<std::uint32_t>& toSink, std::vector<NodeId>& out )
{
    std::vector<NodeId> level;
    for( const NodeId id : from )
    {
        if( toSink[id] != kUnreached )
        {
            level.push_back( id );
        }
    }
    while( !level.empty() )
    {
        out.insert( out.end(), level.begin(), level.end() );
        std::vector<NodeId> next;
        for( const NodeId u : level )
        {
            for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1] && toSink[u] > 0; ++k )
            {
                if( const NodeId v = g.outTargets[k]; toSink[v] + 1 == toSink[u] && !std::ranges::contains( next, v ) )
                {
                    next.push_back( v );
                }
            }
        }
        level = std::move( next );
    }
}

// (M) + (S) + (G) + the path nodes of (D); nullopt when the gate keeps the rule off.
inline std::optional<Sides> computeSides( const Graph& g, const Endpoints& ep, const std::vector<Row>& rows )
{
    Sides s;
    s.endpoints = ep.a;
    s.endpoints.insert( s.endpoints.end(), ep.b.begin(), ep.b.end() );
    std::ranges::sort( s.endpoints );
    std::vector<NodeId> rootPath = shortestPathAny( g, ep.a, ep.b );
    bool aIsRoot = true;
    if( rootPath.empty() || rootPath.size() > kOneSideRootPathMaxHops + 1 )
    {
        rootPath = shortestPathAny( g, ep.b, ep.a );
        aIsRoot = false;
    }
    s.rootSink = !rootPath.empty() && rootPath.size() <= kOneSideRootPathMaxHops + 1;
    if( s.rootSink )
    {
        s.one = boundedReach( g, aIsRoot ? ep.a : ep.b, /*forward=*/true );
        s.two = boundedReach( g, aIsRoot ? ep.b : ep.a, /*forward=*/false );
        s.onPath = std::move( rootPath );
    }
    else
    {
        s.one = boundedReach( g, ep.a, /*forward=*/false );
        s.two = boundedReach( g, ep.b, /*forward=*/false );
    }
    std::size_t sources = 0; // printed rows on both sides
    for( const Row& r : rows )
    {
        if( !onBothSides( s, r ) )
        {
            continue;
        }
        if( !s.rootSink && sources < kOneSideMaxPathSources )
        {
            addShortestPathNodes( g, r.seeds, s.one, s.onPath );
            addShortestPathNodes( g, r.seeds, s.two, s.onPath );
        }
        ++sources;
    }
    if( sources == 0 )
    {
        return std::nullopt; // (G): no printed row reaches both endpoints
    }
    std::ranges::sort( s.onPath );
    return s;
}

// (D) for one row.
inline bool demoteRow( const Sides& s, const Row& r )
{
    if( r.seeds.empty() || anySeedIn( s.endpoints, r ) || anySeedIn( s.onPath, r ) )
    {
        return false;
    }
    const std::uint32_t one = minHops( s.one, r ), two = minHops( s.two, r );
    if( s.rootSink )
    {
        return one == kUnreached && two != kUnreached && two > 1; // reaches S from outside R's walk; a direct caller of S stays
    }
    return ( one == kUnreached ) != ( two == kUnreached );
}

// `text` with each demoted row of it rewritten in place as <t p= sym= r=/> (the legend before the first when `legend`); "" when none is.
inline std::string pointerText( std::string_view text, const std::vector<const Row*>& demoted, bool& legend )
{
    std::string out;
    std::size_t from = 0;
    for( const Row* r : demoted )
    {
        const std::string_view p = filesyms_detail::attrOf( r->attrs, "p" );
        const std::string_view rank = filesyms_detail::attrOf( r->attrs, "r" );
        const std::size_t colon = r->tag == 'd' ? std::string_view::npos : p.rfind( ':' ); // <s>/<y> p= is file:line; a pointer names the file
        out.append( text.substr( from, r->at - from ) );
        out += legend ? kOneSideReachLegend : std::string_view();
        legend = false;
        out += "<t p=\"";
        out += p.substr( 0, colon );
        out += "\" sym=\"";
        out += filesyms_detail::attrOf( r->attrs, "n" );
        out += rank.empty() ? std::string() : "\" r=\"" + std::string( rank );
        out += "\"/>";
        from = r->end;
    }
    return from == 0 ? std::string() : out.append( text.substr( from ) );
}
} // namespace onesidereach_detail

// The answer and its <syms> block after the demote pass: each "" when it is unchanged.
struct OneSideReachEdit
{
    std::string answer, syms;
};
inline OneSideReachEdit demoteOneSideRows( const IngestResult& ing, const Graph& g, std::string_view task, std::string_view answer, std::string_view syms )
{
    namespace od = onesidereach_detail;
    if( !oneSideReachOn() || answer.empty() )
    {
        return {};
    }
    const std::optional<od::Endpoints> ep = od::twoNamedEndpoints( ing, task );
    if( !ep )
    {
        return {};
    }
    std::vector<od::Row> rows;
    od::scanRows( answer, /*inSyms=*/false, rows );
    od::scanRows( syms, /*inSyms=*/true, rows );
    od::resolveSeeds( ing, g, rows );
    const std::optional<od::Sides> sides = od::computeSides( g, *ep, rows );
    if( !sides )
    {
        return {};
    }
    std::vector<const od::Row*> inAnswer, inSyms;
    for( const od::Row& r : rows )
    {
        if( od::demoteRow( *sides, r ) )
        {
            ( r.inSyms ? inSyms : inAnswer ).push_back( &r );
        }
    }
    bool legend = true;
    OneSideReachEdit out;
    out.answer = od::pointerText( answer, inAnswer, legend );
    out.syms = od::pointerText( syms, inSyms, legend );
    return out;
}
} // namespace rw
