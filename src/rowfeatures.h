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
//
// NEW EVIDENCE (ROW-FEATURES-2, 15 more columns after route): cov_name cov_doc cov_body cov_any terms_hit terms_q quote_lits
// quote_hit cp_head cp_top3 cp_seed cp_dir cp_prov ans_file_rank file_top10_share
//   cov_*       coverage='s IDF share (forpage.h termShareWithin, whole percent) of the question's subtokens in the row's name
//               (the pass-1 name mask), doc comment and body (re-tokenized here, for the printed rows only, with the BM25 pass's
//               own subtoken walker and exact term match: a stem/variant fold is not re-applied), and any field (coverage= itself)
//   terms_hit   distinct question subtokens the row carries in any field; terms_q = the question's unique subtokens
//   quote_lits  balanced quoted spans in the question (taskroute firstQuotedLiteral's rule); quote_hit = how many of them the
//               row's doc+signature+body bytes contain verbatim
//   cp_head     directed hops (0 = self, 1, 2; -1 = none) between the row and the head over PROVEN edges (a call: no via=name,
//               no link), either way round; cp_top3 = the same to the nearest of the first three resolved rows other than itself,
//               cp_seed its 1-based place among them, cp_dir out (row reaches it) | in (it reaches the row), cp_prov the path's
//               edge provenance (res scip binding split import lastseg impl, joined by +)
//   ans_file_rank  the row's file's 1-based place among the answer's files in first-appearance order; file_top10_share = the
//               share of the first 10 answer rows in that file
#include "rowfeatstate.h"
#include "model.h"
#include "graph.h"
#include "filter.h"
#include "listedin.h"
#include "infra/hashutil.h"
#include "infra/namesplit.h"
#include "infra/ownedfile.h"
#include "siblift.h"
#include "forpage.h"        // termShareWithin / forCoveragePct — coverage='s one share
#include "forfilesyms.h"    // unescapeXmlAttr — an n= like &lt;file-scope&gt;
#include "taskroute.h"      // firstQuotedLiteral — the one quoted-literal rule

#include <algorithm>
#include <bit>
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

// ── ROW-FEATURES-2: new evidence for the printed rows only (no whole-repo pass beyond the hop CSR emitRows already builds) ──

// (a) coverage split by field, the distinct-term count, and the question's quoted literals in the row's own bytes.
struct CoverageCols
{
    int         name = -1, doc = -1, body = -1, any = -1, termsHit = -1;
    std::size_t quoteHit = 0;
};

// The question's balanced quoted spans, in order, deduplicated (taskroute::firstQuotedLiteral's rule, walked to the end).
inline std::vector<std::string> taskQuotedLiterals( std::string_view task )
{
    std::vector<std::string> lits;
    for( std::string_view rest = task; !rest.empty(); )
    {
        std::string lit = taskroute::firstQuotedLiteral( rest );
        if( lit.empty() )
        {
            break;
        }
        const std::size_t at = rest.find( lit );
        rest                 = rest.substr( std::min( rest.size(), at + lit.size() + 1 ) );
        if( lit.size() >= 2 && std::ranges::find( lits, lit ) == lits.end() )
        {
            lits.push_back( std::move( lit ) );
        }
    }
    return lits;
}

// Bit u of `mask` set for every token of `text` that is exactly the question's term u (the BM25 pass's subtoken walker, lowercased).
inline void markTerms( std::string_view text, const HashMap<std::string_view, std::uint32_t>& termIx, std::uint64_t* mask )
{
    std::string tok;
    forEachLexSubtoken( text, [ & ]( std::size_t b, std::size_t e )
    {
        if( e - b < 2 )
        {
            return;
        }
        tok.assign( text.substr( b, e - b ) );
        for( char& c : tok )
        {
            c = char( lexLowerByte( static_cast<unsigned char>( c ) ) );
        }
        if( const auto it = termIx.find( std::string_view( tok ) ); it != termIx.end() )
        {
            mask[ it->second / 64 ] |= std::uint64_t( 1 ) << ( it->second % 64 );
        }
    } );
}

inline std::vector<CoverageCols> coverageOfRows( const std::vector<NodeId>& ids, const LexTermEvidence& ev, const std::vector<std::string>& lits,
                                                 const IngestResult& ing )
{
    std::vector<CoverageCols> out( ids.size() );
    const std::size_t         n     = ing.symbols.size();
    const std::size_t         words = ev.maskWords;
    const bool measured = words > 0 && ev.symbolCount == n && ev.nameMask.size() == n * words && ev.anyMask.size() == n * words;
    HashMap<std::string_view, std::uint32_t> termIx;
    for( std::uint32_t u = 0; measured && u < ev.terms.size(); ++u )
    {
        termIx.emplace( std::string_view( ev.terms[u] ), u );
    }
    // one read per distinct file among the resolved rows, in first-appearance order
    std::vector<std::size_t> order;
    for( std::size_t k = 0; k < ids.size(); ++k )
    {
        if( ids[k] < n )
        {
            order.push_back( k );
        }
    }
    std::ranges::stable_sort( order, {}, [ & ]( std::size_t k ) { return ing.symbols[ ids[k] ].fileId; } );
    std::string       scratch;
    const std::string* src  = nullptr;
    std::uint32_t      have = UINT32_MAX;
    std::vector<std::uint64_t> docMask( words ), bodyMask( words );
    for( const std::size_t k : order )
    {
        const NodeId  id = ids[k];
        const Symbol& s  = ing.symbols[id];
        if( s.fileId != have )
        {
            have = s.fileId;
            src  = lexicalScanText( ing, s.fileId, scratch );
        }
        const std::string_view sv        = src ? std::string_view( *src ) : std::string_view();
        const std::size_t      bodyStart = std::min<std::size_t>( s.sigStartByte, sv.size() );
        const std::size_t      end       = std::max( bodyStart, std::min<std::size_t>( s.endByte, sv.size() ) );
        const std::size_t      docStart  = src ? docCommentStart( *src, bodyStart ) : bodyStart;
        CoverageCols&          c         = out[k];
        for( const std::string& lit : lits )
        {
            c.quoteHit += sv.substr( docStart, end - docStart ).find( lit ) != std::string_view::npos ? 1u : 0u;
        }
        if( !measured )
        {
            continue;
        }
        std::ranges::fill( docMask, 0u );
        std::ranges::fill( bodyMask, 0u );
        markTerms( sv.substr( docStart, bodyStart - docStart ), termIx, docMask.data() );
        markTerms( sv.substr( bodyStart, end - bodyStart ), termIx, bodyMask.data() );
        c.name     = termShareWithin( ev, ev.nameMask.data() + id * words );
        c.doc      = termShareWithin( ev, docMask.data() );
        c.body     = termShareWithin( ev, bodyMask.data() );
        c.any      = forCoveragePct( ev, id );
        c.termsHit = 0;
        for( std::size_t w = 0; w < words; ++w )
        {
            c.termsHit += std::popcount( ev.anyMaskOf( id )[w] );
        }
    }
    return out;
}

// (b) call-path agreement: directed reach within 2 hops over proven (call-kind) edges between a row and a seed row.
inline constexpr int kCallPathMaxHops = 2;
struct PathReach
{
    std::int8_t hops = -1;
    std::string prov;
};
inline std::string_view provName( const Graph& g, std::size_t edge )
{
    static constexpr std::array<std::string_view, 7> kProv{ "res", "scip", "binding", "split", "import", "lastseg", "impl" };
    const std::uint8_t p = edge < g.outProv.size() ? g.outProv[edge] : 0;
    return p < kProv.size() ? kProv[p] : std::string_view( "other" );
}
inline bool provenEdge( const Graph& g, std::size_t edge )
{
    return g.outNameOnly.empty() || ( edge < g.outNameOnly.size() && edgeKindByte( g.outNameOnly[edge] ) == 0 );
}
// Nodes `seed` reaches (forward) or that reach it (!forward) within kCallPathMaxHops proven edges, with the first path's provenance.
inline HashMap<NodeId, PathReach> reachWithin2( const Graph& g, const std::vector<std::uint32_t>& inOff, const std::vector<NodeId>& inSrc, NodeId seed, bool forward )
{
    HashMap<NodeId, PathReach> seen;
    seen[seed] = PathReach{ 0, {} };
    std::vector<NodeId> frontier{ seed };
    for( int hop = 1; hop <= kCallPathMaxHops && !frontier.empty(); ++hop )
    {
        std::vector<NodeId> next;
        for( const NodeId u : frontier )
        {
            const std::string base = seen[u].prov;
            const auto        step = [ & ]( NodeId v, std::size_t edge )
            {
                if( edge == SIZE_MAX || !provenEdge( g, edge ) || seen.contains( v ) )
                {
                    return;
                }
                seen[v] = PathReach{ std::int8_t( hop ), base.empty() ? std::string( provName( g, edge ) ) : base + "+" + std::string( provName( g, edge ) ) };
                next.push_back( v );
            };
            if( forward && u + 1 < g.outOff.size() )
            {
                for( std::uint32_t k = g.outOff[u]; k < g.outOff[ u + 1 ]; ++k ) { step( g.outTargets[k], k ); }
            }
            if( !forward && u + 1 < inOff.size() )
            {
                for( std::uint32_t k = inOff[u]; k < inOff[ u + 1 ]; ++k ) { step( inSrc[k], edgeIndex( g, inSrc[k], u ) ); }
            }
        }
        frontier.swap( next );
    }
    return seen;
}

struct PathCols
{
    int         head = -1, top3 = -1, seed = 0;
    std::string dir = "-", prov;
};
inline std::vector<PathCols> callPathOfRows( const std::vector<NodeId>& ids, const Graph& g, const std::vector<std::uint32_t>& inOff, const std::vector<NodeId>& inSrc,
                                             std::size_t n )
{
    std::vector<NodeId> seeds;
    for( const NodeId id : ids )
    {
        if( id < n && seeds.size() < 3 && std::ranges::find( seeds, id ) == seeds.end() )
        {
            seeds.push_back( id );
        }
    }
    std::vector<std::array<HashMap<NodeId, PathReach>, 2>> reach;   // [seed][0 = the seed reaches the row (in), 1 = the row reaches the seed (out)]
    for( const NodeId s : seeds )
    {
        reach.push_back( { reachWithin2( g, inOff, inSrc, s, true ), reachWithin2( g, inOff, inSrc, s, false ) } );
    }
    std::vector<PathCols> out( ids.size() );
    for( std::size_t k = 0; k < ids.size(); ++k )
    {
        const NodeId id = ids[k];
        if( id >= n )
        {
            continue;
        }
        PathCols& c = out[k];
        for( std::size_t si = 0; si < seeds.size(); ++si )
        {
            for( int dirIx = 0; dirIx < 2; ++dirIx )
            {
                const auto it = reach[si][dirIx].find( id );
                if( it == reach[si][dirIx].end() )
                {
                    continue;
                }
                const int h = it->second.hops;
                if( si == 0 && ( c.head < 0 || h < c.head ) )
                {
                    c.head = h;
                }
                if( seeds[si] != id && ( c.top3 < 0 || h < c.top3 ) )
                {
                    c.top3 = h;
                    c.seed = int( si + 1 );
                    c.dir  = dirIx == 0 ? "in" : "out";
                    c.prov = it->second.prov;
                }
            }
        }
    }
    return out;
}

// (c) the row's file among the answer's files: first-appearance place, and its share of the first 10 answer rows.
struct FileCols
{
    std::size_t rank = 0;
    double      top10Share = 0.0;
};
inline std::vector<FileCols> fileShareOfRows( const std::vector<std::string>& fileKey )
{
    std::vector<FileCols>              out( fileKey.size() );
    HashMap<std::string_view, std::size_t> rankOf, top10;
    const std::size_t                  firstN = std::min<std::size_t>( 10, fileKey.size() );
    for( std::size_t k = 0; k < fileKey.size(); ++k )
    {
        rankOf.emplace( std::string_view( fileKey[k] ), rankOf.size() + 1 );
        top10[ std::string_view( fileKey[k] ) ] += k < firstN ? 1u : 0u;
    }
    for( std::size_t k = 0; k < fileKey.size(); ++k )
    {
        out[k] = FileCols{ rankOf[ std::string_view( fileKey[k] ) ], firstN ? double( top10[ std::string_view( fileKey[k] ) ] ) / double( firstN ) : 0.0 };
    }
    return out;
}

// The 15 new columns of every row, each string tab-led (unresolved rows read empty in the per-symbol ones).
inline std::vector<std::string> newEvidenceColumns( const std::vector<PrintedRow>& rows, const std::vector<NodeId>& ids, std::string_view task, const IngestResult& ing,
                                                    const Graph& g, const std::vector<std::uint32_t>& inOff, const std::vector<NodeId>& inSrc )
{
    const std::size_t              n    = ing.symbols.size();
    const LexTermEvidence&         ev   = state().evidence;
    const std::vector<std::string> lits = taskQuotedLiterals( task );
    const std::vector<CoverageCols> cov = coverageOfRows( ids, ev, lits, ing );
    const std::vector<PathCols>    path = callPathOfRows( ids, g, inOff, inSrc, n );
    std::vector<std::string>       fileKey( rows.size() );
    for( std::size_t k = 0; k < rows.size(); ++k )
    {
        std::string_view p = attrOf( rows[k].attrs, "p" );
        p                  = p.empty() ? rows[k].parentP : p.substr( 0, p.rfind( ':' ) == std::string_view::npos ? p.size() : p.rfind( ':' ) );
        fileKey[k]         = ids[k] < n ? std::string( rootRelPath( ing, ing.symbols[ ids[k] ].fileId ) ) : std::string( p );
    }
    const std::vector<FileCols> files = fileShareOfRows( fileKey );
    const auto                  num   = []( int v ) { return v < 0 ? std::string() : std::to_string( v ); };
    std::vector<std::string>    out( rows.size() );
    for( std::size_t k = 0; k < rows.size(); ++k )
    {
        const bool resolved = ids[k] < n;
        const CoverageCols& c = cov[k];
        const PathCols&     q = path[k];
        out[k] = std::format( "\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{:.4g}", num( c.name ), num( c.doc ), num( c.body ), num( c.any ), num( c.termsHit ),
                              ev.maskWords > 0 ? std::to_string( ev.terms.size() ) : std::string(), lits.size(), resolved ? std::to_string( c.quoteHit ) : std::string(),
                              resolved ? std::to_string( q.head ) : std::string(), resolved ? std::to_string( q.top3 ) : std::string(), q.seed, q.dir, q.prov,
                              files[k].rank, files[k].top10Share );
    }
    return out;
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
        const std::string nmPlain = nm.find( '&' ) == std::string_view::npos ? std::string() : filesyms_detail::unescapeXmlAttr( nm );   // &lt;file-scope&gt;
        if( !nmPlain.empty() ) { nm = nmPlain; }
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
               "\ttest_path\tgenerated\tvendored\troute"
               "\tcov_name\tcov_doc\tcov_body\tcov_any\tterms_hit\tterms_q\tquote_lits\tquote_hit\tcp_head\tcp_top3\tcp_seed\tcp_dir\tcp_prov"
               "\tans_file_rank\tfile_top10_share\n";
    }
    const std::vector<std::string> extra = newEvidenceColumns( rows, ids, task, ing, g, inOff, inSrc );   // ROW-FEATURES-2
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
            out += extra[k];
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
        std::format_to( std::back_inserter( out ), "\t{}\t{:.6g}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}{}\n",
                        id < rankOf.size() ? rankOf[id] : 0u, top > 0.0f ? at( fin, id ) / top : 0.0f,
                        id < st.fanIn.size() ? std::to_string( st.fanIn[id] ) : std::string(), id < st.tested.size() ? std::to_string( st.tested[id] ) : std::string(),
                        s.ccx, s.loc, int( hopsHead[id] ), int( hopsAnchor[id] ), edge, head != kNoNode && ing.symbols[head].fileId == s.fileId ? 1 : 0,
                        head != kNoNode && siblift_detail::dirOf( headRel ) == siblift_detail::dirOf( rel ) ? 1 : 0, st.sigsRR ? 1 : 0, rrLift, preRank,
                        tsvClean( attrOf( r.attrs, "r" ) ), isTestPath( rel ) ? 1 : 0, isDemoOrGeneratedPath( rel ) ? 1 : 0,
                        listeddetail::isVendoredDir( siblift_detail::dirOf( rel ) ) ? 1 : 0, st.route, extra[k] );
    }
    if( std::fwrite( out.data(), 1, out.size(), f.file ) != out.size() || !f.close() )
    {
        std::fputs( "ripwire: RIPWIRE_ROW_FEATURES: short write to the TSV\n", stderr );
    }
}
}   // namespace rw::rowfeat
