#pragma once
// ROW-FEATURE-DUMP, the emit half (dev-only; the capture half is rowfeatstate.h). RIPWIRE_ROW_FEATURES=<path>: after a --for
// answer is complete (CLI runForLens, MCP forTaskText), append ONE TSV line per printed answer row, in output order, to <path>.
// The answer's bytes are never touched: the CLI writes the answer it captured, unchanged, and this reads the same bytes.
//
// WHAT A ROW IS: the grader's reading (tmp grader arows): an opening <d|y|s|u …> tag after XML comments are masked, a
// <u v="used"> excluded. A row is resolved to its symbol by n= (the last ::/. segment, the qualifier preferring a matching
// scope), its file (p=, else the nearest enclosing element's p=) and its line (l=, else p=:LINE). Unresolved rows keep
// their printed columns and read -1 / "" in the ranker's.
//
// COLUMNS (tab-separated; a file opened empty gets one '#' header line naming them): qhash pos tag n p src via sym kind line
// score lex tier d_anchor d_mention d_pathcut d_exp d_cochange d_docmention score_rank score_ratio fanin tested ccx loc
// hops_head hops_anchor edge_head same_file same_dir rr_on rr_lift pre_rank r test_path generated vendored route
//   qhash       FNV-1a 64 of the --for question text (hex)
//   src / via   the row's enclosing element (sigs, callers, f, syms, ctx, …) and its by= / via= attribute
//   score       the final lens rank; lex = the base ranker's score with the tier multiplier divided back out; tier = that
//               multiplier; d_* = what each later lift stage added (rowfeatstate.h Stage)
//   score_rank  1-based place in (score desc, id asc) among positive scores (0 = not positive); score_ratio = score / top
//   hops_head   undirected call-graph hops from the head (the first resolved row), capped at kMaxHops (-1 = farther or none)
//   hops_anchor the same from the route's anchor definitions (-1 = none)
//   edge_head   self | out:call|out:name|out:link|out:import (row → head) | in:… (head → row) | member | owner | sibling | none
//   rr_*        the <sigs> head round-robin: on for this render, whether it moved this row up, and the row's score-order r=
#include "rowfeatstate.h"
#include "model.h"
#include "graph.h"
#include "filter.h"
#include "listedin.h"
#include "infra/hashutil.h"
#include "infra/namesplit.h"
#include "infra/ownedfile.h"
#include "siblift.h"

#include <algorithm>
#include <cctype>
#include <charconv>
#include <cstdio>
#include <format>
#include <iterator>
#include <string>
#include <string_view>
#include <vector>

namespace rw::rowfeat
{
inline constexpr int kMaxHops = 6;

struct PrintedRow
{
    char             tag = 'd';
    std::string_view attrs;   // the raw attribute run of the opening tag
    std::string_view parent;  // enclosing element name ("-" at the top)
    std::string_view parentP; // nearest enclosing element's p= ("" if none)
};

inline std::string_view attrOf( std::string_view attrs, std::string_view key )
{
    for( std::size_t at = 0; ( at = attrs.find( key, at ) ) != std::string_view::npos; at += key.size() )
    {
        const bool boundary = at == 0 || attrs[ at - 1 ] == ' ' || attrs[ at - 1 ] == '\t' || attrs[ at - 1 ] == '\n';
        if( boundary && at + key.size() + 1 < attrs.size() && attrs[ at + key.size() ] == '=' && attrs[ at + key.size() + 1 ] == '"' )
        {
            const std::size_t v = at + key.size() + 2;
            const std::size_t e = attrs.find( '"', v );
            return e == std::string_view::npos ? std::string_view() : attrs.substr( v, e - v );
        }
    }
    return {};
}

// The regex's [\w:-], on the ASCII bytes the answer's attribute and element names use (\s is std::isspace).
inline constexpr auto kAttrNameByte = []( char c ) noexcept { return namesplit::isIdentChar( c ) || c == ':' || c == '-'; };
inline constexpr auto kSpaceByte    = []( char c ) noexcept { return std::isspace( static_cast<unsigned char>( c ) ) != 0; };
// The grader's row regex <(d|y|s|u)((?:\s+[\w:-]+="[^"]*")*)\s*(/?)> at `at`: the end of the match, or npos.
inline std::size_t matchTagAt( std::string_view t, std::size_t at, std::string_view& attrsOut )
{
    std::size_t i = at + 2;
    for( ;; )
    {
        std::size_t j = i;
        while( j < t.size() && kSpaceByte( t[j] ) ) { ++j; }
        if( j == i ) { break; }
        std::size_t k = j;
        while( k < t.size() && kAttrNameByte( t[k] ) ) { ++k; }
        if( k == j || k + 1 >= t.size() || t[k] != '=' || t[ k + 1 ] != '"' ) { break; }
        const std::size_t q = t.find( '"', k + 2 );
        if( q == std::string_view::npos ) { break; }
        i = q + 1;
    }
    const std::size_t attrEnd = i;
    while( i < t.size() && kSpaceByte( t[i] ) ) { ++i; }
    if( i < t.size() && t[i] == '/' ) { ++i; }
    if( i < t.size() && t[i] == '>' )
    {
        attrsOut = t.substr( at + 2, attrEnd - ( at + 2 ) );
        return i + 1;
    }
    return std::string_view::npos;
}

// The answer rows, in output order, with each row's enclosing element. `masked` is the answer with comments blanked.
inline std::vector<PrintedRow> printedRows( std::string_view masked )
{
    struct Open
    {
        std::string_view name, p;
    };
    std::vector<Open>       stack;
    std::vector<PrintedRow> rows;
    bool                    inCdata = false;
    for( std::size_t i = 0; i < masked.size(); )
    {
        if( inCdata )
        {
            const std::size_t e = masked.find( "]]>", i );
            const std::size_t r = masked.find( '<', i );
            if( r == std::string_view::npos || ( e != std::string_view::npos && e < r ) )
            {
                inCdata = e == std::string_view::npos ? true : false;
                i       = e == std::string_view::npos ? masked.size() : e + 3;
                continue;
            }
            i = r;
        }
        else
        {
            const std::size_t r = masked.find( '<', i );
            if( r == std::string_view::npos ) { break; }
            i = r;
        }
        if( !inCdata && masked.substr( i ).starts_with( "<![CDATA[" ) )
        {
            inCdata = true;
            i += 9;
            continue;
        }
        const char c = i + 1 < masked.size() ? masked[ i + 1 ] : '\0';
        if( c == 'd' || c == 'y' || c == 's' || c == 'u' )
        {
            std::string_view  attrs;
            const std::size_t end = matchTagAt( masked, i, attrs );
            if( end != std::string_view::npos )
            {
                if( !( c == 'u' && attrOf( attrs, "v" ) == "used" ) )
                {
                    PrintedRow row{ c, attrs, inCdata ? std::string_view( "cdata" ) : stack.empty() ? std::string_view( "-" ) : stack.back().name, {} };
                    for( auto it = stack.rbegin(); it != stack.rend(); ++it )
                    {
                        if( !it->p.empty() ) { row.parentP = it->p; break; }
                    }
                    rows.push_back( row );
                }
                if( !inCdata && masked[ end - 2 ] != '/' )
                {
                    stack.push_back( Open{ masked.substr( i + 1, 1 ), attrOf( attrs, "p" ) } );
                }
                i = end;
                continue;
            }
        }
        if( inCdata )
        {
            ++i;
            continue;
        }
        // any other tag: track the element stack (the row's src= is its enclosing element)
        const bool        closing = c == '/';
        const std::size_t ns      = i + ( closing ? 2 : 1 );
        std::size_t       ne      = ns;
        while( ne < masked.size() && ( kAttrNameByte( masked[ne] ) ) ) { ++ne; }
        const std::size_t gt = masked.find( '>', ne );
        if( ne == ns || gt == std::string_view::npos )
        {
            ++i;
            continue;
        }
        const std::string_view name = masked.substr( ns, ne - ns );
        if( closing )
        {
            while( !stack.empty() && stack.back().name != name ) { stack.pop_back(); }
            if( !stack.empty() ) { stack.pop_back(); }
        }
        else if( masked[ gt - 1 ] != '/' )
        {
            stack.push_back( Open{ name, attrOf( masked.substr( ne, gt - ne ), "p" ) } );
        }
        i = gt + 1;
    }
    return rows;
}

// The answer with each XML comment (an unclosed one runs to the end) replaced by as many spaces: offsets stay the answer's.
inline std::string maskComments( std::string_view t )
{
    std::string masked;
    masked.reserve( t.size() );
    std::size_t from = 0;
    while( from < t.size() )
    {
        const std::size_t open = t.find( "<!--", from );
        masked.append( t.substr( from, open == std::string_view::npos ? std::string_view::npos : open - from ) );
        if( open == std::string_view::npos )
        {
            break;
        }
        const std::size_t close = t.find( "-->", open + 4 );
        const std::size_t past  = close == std::string_view::npos ? t.size() : close + 3;
        masked.append( past - open, ' ' );
        from = past;
    }
    return masked;
}

inline std::string tsvClean( std::string_view v )
{
    std::string s( v );
    std::replace_if( s.begin(), s.end(), []( char c ) { return c == '\t' || c == '\n' || c == '\r'; }, ' ' );
    return s;
}

// Undirected BFS from `seeds` over the resolved call edges (out CSR + its reverse), to kMaxHops; -1 = not reached.
inline std::vector<std::int8_t> hopsFrom( const Graph& g, const std::vector<std::uint32_t>& inOff, const std::vector<NodeId>& inSrc,
                                          const std::vector<NodeId>& seeds, std::size_t n )
{
    std::vector<std::int8_t> d( n, -1 );
    std::vector<NodeId>      frontier;
    for( const NodeId s : seeds )
    {
        if( s < n && d[s] < 0 ) { d[s] = 0; frontier.push_back( s ); }
    }
    for( int hop = 1; hop <= kMaxHops && !frontier.empty(); ++hop )
    {
        std::vector<NodeId> next;
        const auto          visit = [ & ]( NodeId v )
        {
            if( v < n && d[v] < 0 ) { d[v] = std::int8_t( hop ); next.push_back( v ); }
        };
        for( const NodeId u : frontier )
        {
            if( u + 1 < g.outOff.size() )
            {
                for( std::uint32_t k = g.outOff[u]; k < g.outOff[ u + 1 ]; ++k ) { visit( g.outTargets[k] ); }
            }
            if( u + 1 < inOff.size() )
            {
                for( std::uint32_t k = inOff[u]; k < inOff[ u + 1 ]; ++k ) { visit( inSrc[k] ); }
            }
        }
        frontier.swap( next );
    }
    return d;
}

inline std::string edgeKindOf( const Graph& g, NodeId from, NodeId to )
{
    if( from + 1 >= g.outOff.size() ) { return {}; }
    const auto b  = g.outTargets.begin() + std::ptrdiff_t( g.outOff[from] );
    const auto e  = g.outTargets.begin() + std::ptrdiff_t( g.outOff[ from + 1 ] );
    const auto it = std::lower_bound( b, e, to );
    if( it == e || *it != to ) { return {}; }
    const std::size_t k = std::size_t( it - g.outTargets.begin() );
    if( k < g.outProv.size() && g.outProv[k] == 4 ) { return "import"; }
    const std::uint8_t kind = k < g.outNameOnly.size() ? std::uint8_t( g.outNameOnly[k] & 0x7f ) : 0;
    return kind == 1 ? "name" : kind == 2 ? "link" : "call";
}

// Append the TSV lines for `answer`. Never throws past here into the answer: every failure is one stderr line.
inline void emitRows( std::string_view answer, std::string_view task, const IngestResult& ing, const Graph& g )
{
    const char* path = outPath();
    if( path == nullptr ) { return; }
    State&            st = state();
    const std::size_t n  = ing.symbols.size();
    // final rank and the stage snapshots (a stage never run reads as the one before it)
    std::array<const std::vector<float>*, kStages> stg{};
    const std::vector<float>*                      prev = nullptr;
    for( std::size_t k = 0; k < kStages; ++k )
    {
        prev   = st.stage[k].size() == n ? &st.stage[k] : prev;
        stg[k] = prev;
    }
    const std::vector<float>* fin = stg[ kStages - 1 ];
    const auto                at  = []( const std::vector<float>* v, NodeId i ) { return v != nullptr && i < v->size() ? ( *v )[i] : 0.0f; };

    HashMap<std::string_view, std::vector<NodeId>> byName;
    HashMap<std::string_view, std::uint32_t>       fileOfRel;
    byName.reserve( n );
    for( NodeId i = 0; i < n; ++i ) { byName[ std::string_view( ing.symbols[i].name ) ].push_back( i ); }
    for( std::uint32_t f = 0; f < ing.files.size(); ++f ) { fileOfRel.emplace( rootRelPath( ing, f ), f ); }

    const std::string             masked = maskComments( answer );
    const std::vector<PrintedRow> rows   = printedRows( masked );

    const auto resolve = [ & ]( const PrintedRow& r ) -> NodeId
    {
        std::string_view nm = attrOf( r.attrs, "n" );
        if( nm.empty() ) { nm = attrOf( r.attrs, "sym" ); }
        std::string_view p    = attrOf( r.attrs, "p" );
        std::uint32_t    line = 0;
        if( const std::string_view l = attrOf( r.attrs, "l" ); !l.empty() ) { std::from_chars( l.data(), l.data() + l.size(), line ); }
        if( const std::size_t c = p.rfind( ':' ); c != std::string_view::npos && c + 1 < p.size()
            && std::all_of( p.begin() + std::ptrdiff_t( c + 1 ), p.end(), []( char ch ) { return ch >= '0' && ch <= '9'; } ) )
        {
            if( line == 0 ) { std::from_chars( p.data() + c + 1, p.data() + p.size(), line ); }
            p = p.substr( 0, c );
        }
        if( p.empty() ) { p = r.parentP; }
        if( const std::size_t c = p.rfind( ':' ); c != std::string_view::npos ) { if( !fileOfRel.contains( p ) ) { p = p.substr( 0, c ); } }
        std::string_view bare = nm, qual;
        if( const std::size_t c = nm.rfind( "::" ); c != std::string_view::npos ) { bare = nm.substr( c + 2 ); qual = nm.substr( 0, c ); }
        else if( const std::size_t d = nm.rfind( '.' ); d != std::string_view::npos && d > 0 ) { bare = nm.substr( d + 1 ); qual = nm.substr( 0, d ); }
        auto it = byName.find( bare );
        if( it == byName.end() && bare != nm ) { it = byName.find( nm ); qual = {}; }
        if( it == byName.end() ) { return kNoNode; }
        const auto fileIt = p.empty() ? fileOfRel.end() : fileOfRel.find( p );
        NodeId     best = kNoNode;
        int        bestKey = -1;
        float      bestScore = 0.0f;
        for( const NodeId i : it->second )
        {
            const Symbol& s   = ing.symbols[i];
            int           key = 0;
            if( fileIt != fileOfRel.end() ) { if( s.fileId != fileIt->second ) { continue; } key += 4; }
            if( line != 0 && s.line == line ) { key += 2; }
            if( const std::string_view sc = attrOf( r.attrs, "sc" ); !sc.empty() && s.scope == sc ) { key += 1; }
            if( !qual.empty() && s.scope.ends_with( qual.substr( qual.find_last_of( ":." ) == std::string_view::npos ? 0 : qual.find_last_of( ":." ) + 1 ) ) ) { key += 1; }
            const float sc = at( fin, i );
            if( key > bestKey || ( key == bestKey && sc > bestScore ) ) { best = i; bestKey = key; bestScore = sc; }
        }
        return best;
    };
    // The <sigs> rows are read off the render's own written order when it lines up (a same-name same-line pair — a C typedef
    // and its struct — is two symbols no attribute set tells apart); every other row resolves by its attributes.
    const std::size_t sigRows = std::size_t( std::count_if( rows.begin(), rows.end(), []( const PrintedRow& r ) { return r.tag == 'd' && r.parent == "sigs"; } ) );
    const bool        bySigs  = sigRows == st.sigsShown.size();
    std::size_t       sigAt   = 0;
    std::vector<NodeId> ids;
    ids.reserve( rows.size() );
    for( const PrintedRow& r : rows )
    {
        const bool sigRow = r.tag == 'd' && r.parent == "sigs";
        const NodeId id   = sigRow && bySigs && st.sigsShown[ sigAt ] < n && attrOf( r.attrs, "n" ).ends_with( ing.symbols[ st.sigsShown[ sigAt ] ].name )
                                ? st.sigsShown[ sigAt ] : resolve( r );
        sigAt += sigRow ? 1u : 0u;
        ids.push_back( id );
    }

    // score order (score desc, id asc) over the positive scores, for score_rank
    std::vector<std::uint32_t> rankOf( fin ? n : 0, 0 );
    float                      top = 0.0f;
    if( fin )
    {
        std::vector<NodeId> pos;
        for( NodeId i = 0; i < n; ++i ) { if( ( *fin )[i] > 0.0f ) { pos.push_back( i ); } }
        std::sort( pos.begin(), pos.end(), [ & ]( NodeId a, NodeId b ) { return ( *fin )[a] != ( *fin )[b] ? ( *fin )[a] > ( *fin )[b] : a < b; } );
        for( std::size_t k = 0; k < pos.size(); ++k ) { rankOf[ pos[k] ] = std::uint32_t( k + 1 ); }
        top = pos.empty() ? 0.0f : ( *fin )[ pos.front() ];
    }
    // reverse CSR for the undirected hop counts
    std::vector<std::uint32_t> inOff( n + 1, 0 );
    std::vector<NodeId>        inSrc( g.outTargets.size() );
    for( NodeId u = 0; u + 1 < g.outOff.size() && u < n; ++u )
    {
        for( std::uint32_t k = g.outOff[u]; k < g.outOff[ u + 1 ]; ++k ) { if( g.outTargets[k] < n ) { ++inOff[ g.outTargets[k] + 1 ]; } }
    }
    for( std::size_t v = 0; v < n; ++v ) { inOff[ v + 1 ] += inOff[v]; }
    {
        std::vector<std::uint32_t> fill( inOff.begin(), inOff.end() - 1 );
        for( NodeId u = 0; u + 1 < g.outOff.size() && u < n; ++u )
        {
            for( std::uint32_t k = g.outOff[u]; k < g.outOff[ u + 1 ]; ++k ) { if( g.outTargets[k] < n ) { inSrc[ fill[ g.outTargets[k] ]++ ] = u; } }
        }
    }
    const auto   headIt = std::find_if( ids.begin(), ids.end(), []( NodeId i ) { return i != kNoNode; } );
    const NodeId head   = headIt == ids.end() ? kNoNode : *headIt;
    const std::vector<std::int8_t> hopsHead = head == kNoNode ? std::vector<std::int8_t>( n, -1 ) : hopsFrom( g, inOff, inSrc, { head }, n );
    std::vector<NodeId>            anchorIds;
    for( const auto& [ lower, fileId ] : st.anchors )
    {
        for( NodeId i = 0; i < n; ++i )
        {
            const Symbol& s = ing.symbols[i];
            if( s.fileId == fileId && s.name.size() == lower.size()
                && std::equal( s.name.begin(), s.name.end(), lower.begin(), []( char a, char b ) { return char( std::tolower( (unsigned char) a ) ) == b; } ) )
            {
                anchorIds.push_back( i );
            }
        }
    }
    const std::vector<std::int8_t> hopsAnchor = anchorIds.empty() ? std::vector<std::int8_t>( n, -1 ) : hopsFrom( g, inOff, inSrc, anchorIds, n );

    std::uint64_t qh = 0xcbf29ce484222325ull;
    for( const char c : task ) { qh = hashutil::fnv1aAbsorb( qh, c ); }

    std::string out;
    OwnedFile   f = openOwnedFile( path, "ab" );
    if( !f )
    {
        std::fputs( "ripwire: RIPWIRE_ROW_FEATURES: cannot open the TSV for append; no rows written\n", stderr );
        return;
    }
    if( std::ftell( f.file ) == 0 )
    {
        out += "#qhash\tpos\ttag\tn\tp\tsrc\tvia\tsym\tkind\tline\tscore\tlex\ttier\td_anchor\td_mention\td_pathcut\td_exp\td_cochange\td_docmention"
               "\tscore_rank\tscore_ratio\tfanin\ttested\tccx\tloc\thops_head\thops_anchor\tedge_head\tsame_file\tsame_dir\trr_on\trr_lift\tpre_rank\tr"
               "\ttest_path\tgenerated\tvendored\troute\n";
    }
    for( std::size_t k = 0; k < rows.size(); ++k )
    {
        const PrintedRow& r  = rows[k];
        const NodeId      id = ids[k];
        std::string_view  via = attrOf( r.attrs, "by" );
        if( via.empty() ) { via = attrOf( r.attrs, "via" ); }
        std::format_to( std::back_inserter( out ), "{:016x}\t{}\t{}\t{}\t{}\t{}\t{}\t", qh, k + 1, r.tag, tsvClean( attrOf( r.attrs, "n" ) ),
                        tsvClean( attrOf( r.attrs, "p" ) ), r.parent, tsvClean( via ) );
        if( id == kNoNode )
        {
            out += "-1\t\t0";
            for( int c = 0; c < 28; ++c ) { out += '\t'; }
            out += st.route;
            out += '\n';
            continue;
        }
        const Symbol&          s   = ing.symbols[id];
        const std::string_view rel = rootRelPath( ing, s.fileId );
        const float            tm  = id < st.tier.size() ? st.tier[id] : 1.0f;
        const float            lex = at( stg[0], id );
        std::format_to( std::back_inserter( out ), "{}\t{}\t{}\t{:.6g}\t{:.6g}\t{:.6g}", id, symTag( s.kind ), s.line, at( fin, id ), tm > 0.0f ? lex / tm : lex, tm );
        for( std::size_t sg = 1; sg < kStages; ++sg ) { std::format_to( std::back_inserter( out ), "\t{:.6g}", at( stg[sg], id ) - at( stg[ sg - 1 ], id ) ); }
        std::string edge = "none";
        if( head != kNoNode )
        {
            const Symbol& h = ing.symbols[head];
            if( id == head ) { edge = "self"; }
            else if( std::string e = edgeKindOf( g, id, head ); !e.empty() ) { edge = "out:" + e; }
            else if( std::string e2 = edgeKindOf( g, head, id ); !e2.empty() ) { edge = "in:" + e2; }
            else if( !s.scope.empty() && s.scope == h.name ) { edge = "member"; }
            else if( !h.scope.empty() && h.scope == s.name ) { edge = "owner"; }
            else if( !s.scope.empty() && s.scope == h.scope && s.fileId == h.fileId ) { edge = "sibling"; }
        }
        const std::string_view headRel = head == kNoNode ? std::string_view() : rootRelPath( ing, ing.symbols[head].fileId );
        // the head round-robin's reading of this row (the <sigs> rows only)
        std::string rrLift, preRank;
        if( r.tag == 'd' && r.parent == "sigs" )
        {
            const auto b = std::find( st.sigsBefore.begin(), st.sigsBefore.end(), id );
            const auto a = std::find( st.sigsAfterRR.begin(), st.sigsAfterRR.end(), id );
            if( b != st.sigsBefore.end() )
            {
                const std::size_t bi = std::size_t( b - st.sigsBefore.begin() );
                preRank = std::to_string( bi < st.sigsPreRank.size() ? st.sigsPreRank[bi] : 0 );
                rrLift  = ( a != st.sigsAfterRR.end() && std::size_t( a - st.sigsAfterRR.begin() ) < bi ) ? "1" : "0";
            }
        }
        std::format_to( std::back_inserter( out ), "\t{}\t{:.6g}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
                        id < rankOf.size() ? rankOf[id] : 0u, top > 0.0f ? at( fin, id ) / top : 0.0f,
                        id < st.fanIn.size() ? std::to_string( st.fanIn[id] ) : std::string(), id < st.tested.size() ? std::to_string( st.tested[id] ) : std::string(),
                        s.ccx, s.loc, int( hopsHead[id] ), int( hopsAnchor[id] ), edge, head != kNoNode && ing.symbols[head].fileId == s.fileId ? 1 : 0,
                        head != kNoNode && siblift_detail::dirOf( headRel ) == siblift_detail::dirOf( rel ) ? 1 : 0, st.sigsRR ? 1 : 0, rrLift, preRank,
                        tsvClean( attrOf( r.attrs, "r" ) ), isTestPath( rel ) ? 1 : 0, isDemoOrGeneratedPath( rel ) ? 1 : 0,
                        listeddetail::isVendoredDir( siblift_detail::dirOf( rel ) ) ? 1 : 0, st.route );
    }
    if( std::fwrite( out.data(), 1, out.size(), f.file ) != out.size() || !f.close() )
    {
        std::fputs( "ripwire: RIPWIRE_ROW_FEATURES: short write to the TSV\n", stderr );
    }
}
}   // namespace rw::rowfeat
