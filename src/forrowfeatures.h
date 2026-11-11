#pragma once
// forrowfeatures.h — ROW-FEATURE-DUMP (precision tool, dev only): RIPWIRE_ROW_FEATURES=<path> makes --for append one TSV line per
// row it ranked or printed to <path>, with the ranker's internals beside the answer's own placement of the row. The answer is
// byte-identical with and without the variable (stdout, stderr and rc), and unset it costs one getenv per --for call.
//
// WHICH ROWS: every answer row (the <d>, <y>, <s> and non-`used` <u> rows in output order: grader_fix_1107's answer rows), every
// tail pointer that kept its r= (a ranked row SIBLING-DEMOTE or a later pass turned into a <t>), then the ranked candidate set
// (lensSurfaceIds: the top forTopN by score) and the kBeyondRows next ones by score, printed or not; a node listed once, at its first.
// THE FILE: a new or empty file gets two header lines, `# ripwire.row_features/v1 columns=N` and the column names; every call then
// appends its lines (the task is the first column, so one file can hold many calls).
// HOOKS (the answer is never read for anything but placement): armRowFeatures (runForLens), the score after the lexical pass and
// after each lift pass (computeLensRanking), the candidate set (runForLensPass, once lensSurfaceIds is cut), SIBLING-DEMOTE's verdicts
// (forsiblingdemote.h demoteVerdictSink), and the final answer bytes (appendForFileSyms) where the file is written.
// CLI --for in the captured XML posture only (no --json / --format / --limit page / multi-root): any other posture says so on stderr
// and writes nothing. A path that is not a usable file, or a write that fails, is disclosed on stderr; the answer is never touched.
#include "forsiblingdemote.h" // demote_detail::scanAnswer / rowWant / resolveWants / DemoteVerdictRow, kHeadRoundRobinRows (serialize.h)
#include "graph.h" // Graph CSR + per-edge bytes, declined sites, definitionCountOfName
#include "infra/Diagnostics.h"
#include "infra/emit.h"
#include "infra/sortutil.h"
#include "lexical.h" // LexTermEvidence, RouteAnchorDef, routeLower
#include "model.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <filesystem>
#include <format>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>
#include <vector>

namespace rw
{
inline constexpr std::string_view kRowFeaturesSchema = "ripwire.row_features/v1";
inline constexpr std::size_t kRowFeaturesBeyondRows = 20; // ranked candidates past the cut, listed so a near miss has a line
inline constexpr std::uint8_t kRowFeaturesMaxHops = 4; // graph distance is walked this far (undirected); further reads -1
inline constexpr std::size_t kRowFeaturesMaxVisit = 2'000'000; // a walk stops after this many nodes (a hub on a huge graph)
inline constexpr std::size_t kRowFeaturesMaxPath = 4096;

// The lift passes computeLensRanking runs after the lexical score, in order; each one's d_<name> column is its score change.
enum class RowStage : std::uint8_t
{
    Anchor,
    Mention,
    FileSubject,
    PathUpstream,
    SibLift,
    Pool,
    Expand,
    CoChange,
    DocMention,
    Count
};
inline constexpr std::array<std::string_view, std::size_t( RowStage::Count )> kRowStageColumns = {
    "d_anchor", "d_mention", "d_file_subject", "d_path_upstream", "d_siblift", "d_pool", "d_expand", "d_cochange", "d_doc_mention" };
// The source label a lift adds to a row it moved (the RIPWIRE_NO_<NAME> switch that turns it off, where one does).
inline constexpr std::array<std::string_view, std::size_t( RowStage::Count )> kRowStageSources = {
    "ANCHOR", "MENTION", "MENTION_FILE", "PATH_UPSTREAM", "SIBLIFT", "POOL", "EXPAND", "COCHANGE", "DOC_MENTION" };

inline constexpr std::array<std::string_view, 15> kRowFeatureLeadColumns = { "task", "node", "name", "scope", "file", "line", "kind", "printed", "ans_pos",
                                                                             "ans_tag", "section", "d_pos", "r", "lens_rank", "cand" };
inline constexpr std::array<std::string_view, 3> kRowFeatureScoreColumns = { "score", "lex", "tier" };
inline constexpr std::array<std::string_view, 18> kRowFeatureTrailColumns = { "head_dist", "anchor_dist", "head_edge", "head_prov", "reach_prov", "same_file",
                                                                              "same_dir", "file_rank", "name_terms", "any_terms", "name_idf", "any_idf",
                                                                              "path_terms", "terms", "def_count", "demote", "row_source", "head_rr" };

// What the passes between arming and the answer leave for the writer. One per process: the CLI runs one --for.
struct RowFeatureRecorder
{
    bool armed = false;
    std::string path;
    std::vector<float> lex, tier, finalRank;
    std::array<std::vector<float>, std::size_t( RowStage::Count )> after; // the score after each pass; empty: the pass moved nothing
    std::vector<NodeId> surface;
    const LexTermEvidence* evidence = nullptr; // runForLensPass's LensRanking, alive until the answer is written
    std::vector<RouteAnchorDef> anchors;
    std::string rootArg;
    std::vector<demote_detail::DemoteVerdictRow> demotes;
};
inline RowFeatureRecorder& rowFeatures() noexcept
{
    static RowFeatureRecorder rec;
    return rec;
}

namespace rowfeat_detail
{
inline void notice( std::string_view what )
{
    rw::emitTo( stderr, "ripwire: RIPWIRE_ROW_FEATURES: {} (the answer is unchanged)\n", what );
}
// The last recorded score vector before `s` (the lexical score when no earlier pass moved one).
inline const std::vector<float>& before( const RowFeatureRecorder& rec, std::size_t s )
{
    for( std::size_t k = s; k > 0; --k )
    {
        if( !rec.after[k - 1].empty() )
        {
            return rec.after[k - 1];
        }
    }
    return rec.lex;
}
} // namespace rowfeat_detail

// Read the variable once per --for call. `captured`: the posture prints the XML answer through appendForFileSyms's capture.
inline void armRowFeatures( bool captured )
{
    RowFeatureRecorder& rec = rowFeatures();
    rec = RowFeatureRecorder {};
    demote_detail::demoteVerdictSink() = nullptr;
    const char* const env = std::getenv( "RIPWIRE_ROW_FEATURES" );
    if( env == nullptr )
    {
        return;
    }
    const std::string_view path( env );
    if( !VALIDATE( !path.empty() && path.size() <= kRowFeaturesMaxPath && !path.contains( '\n' ), "RIPWIRE_ROW_FEATURES is one file path" ) )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "the dump is a side file; the answer never reads it", "RIPWIRE_ROW_FEATURES: not a path" );
        rowfeat_detail::notice( "the value is not a file path (empty, over 4096 bytes, or multi-line): nothing written" );
        return;
    }
    std::error_code ec;
    if( std::filesystem::is_directory( std::filesystem::path( path ), ec ) )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "the dump is a side file; the answer never reads it", "RIPWIRE_ROW_FEATURES: a directory" );
        rowfeat_detail::notice( "the path is a directory: nothing written" );
        return;
    }
    if( !captured )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "the dump is a side file; the answer never reads it", "RIPWIRE_ROW_FEATURES: posture not captured" );
        rowfeat_detail::notice( "this --for posture (--json, --format=, a --limit/--offset page or several roots) is not dumped: nothing written" );
        return;
    }
    rec.armed = true;
    rec.path = path;
    demote_detail::demoteVerdictSink() = &rec.demotes;
}

// The score after the lexical pass (the tier multiplier folded in) and that multiplier.
inline void rowFeaturesLexical( const std::vector<float>& rank, const std::vector<float>& tierMul )
{
    if( RowFeatureRecorder& rec = rowFeatures(); rec.armed )
    {
        rec.lex = rank;
        rec.tier = tierMul;
    }
}
// The score after pass `s`; kept only when the pass moved it.
inline void rowFeaturesStage( RowStage s, const std::vector<float>& rank )
{
    RowFeatureRecorder& rec = rowFeatures();
    if( !rec.armed )
    {
        return;
    }
    if( rank != rowfeat_detail::before( rec, std::size_t( s ) ) )
    {
        rec.after[std::size_t( s )] = rank;
    }
}
// The final score, the ranked candidate set and what the writer reads beside them.
struct RowFeatureSurface
{
    const std::vector<float>& rank;
    const std::vector<NodeId>& surface;
    const LexTermEvidence& evidence;
    const std::vector<RouteAnchorDef>& anchors;
    std::string_view rootArg;
};
inline void rowFeaturesSurface( const RowFeatureSurface& s )
{
    if( RowFeatureRecorder& rec = rowFeatures(); rec.armed )
    {
        rec.finalRank = s.rank;
        rec.surface = s.surface;
        rec.evidence = &s.evidence;
        rec.anchors = s.anchors;
        rec.rootArg = std::string( s.rootArg );
    }
}

namespace rowfeat_detail
{
using demote_detail::AnswerRow;

// How a row is joined to another node, best first: a proven call, a call bound by name alone, one arm of a split the resolver could
// not choose, a call the resolver declined (its candidate list holds the node), a markdown link; none.
enum class Prov : std::uint8_t
{
    None,
    Link,
    Declined,
    Ambiguous,
    NameResolved,
    Resolved
};
inline constexpr std::array<std::string_view, 6> kProvNames = { "none", "link", "declined", "ambiguous", "name-resolved", "resolved" };

inline Prov edgeProv( const Graph& g, std::size_t edge ) noexcept
{
    if( edge == SIZE_MAX )
    {
        return Prov::None;
    }
    const std::uint8_t kind = edge < g.outNameOnly.size() ? edgeKindByte( g.outNameOnly[edge] ) : 0;
    const std::uint8_t prov = edge < g.outProv.size() ? g.outProv[edge] : 0;
    return kind == kEdgeLink ? Prov::Link : prov == 3 ? Prov::Ambiguous : kind != 0 ? Prov::NameResolved : Prov::Resolved;
}

// Everything one call's lines read, built once.
struct Context
{
    const IngestResult& ing;
    const Graph& g;
    const RowFeatureRecorder& rec;
    std::vector<std::uint32_t> lensPos; // 1-based place in the (score desc, id asc) order; 0: score <= 0
    std::vector<std::uint32_t> fileRank; // 1-based place of the file by its best score; 0: no positive score
    std::vector<std::uint8_t> headDist, anchorDist; // kRowFeaturesMaxHops + 1: not reached
    std::vector<std::pair<NodeId, NodeId>> declined; // (lo, hi) node pairs a declined call joins, sorted
    NodeId head = kNoNode;
    bool anchored = false;
    std::vector<std::pair<std::string, std::size_t>> defCounts; // definitionCountOfName by bare name, memoized
};

inline float at( const std::vector<float>& v, NodeId id ) noexcept
{
    return id < v.size() ? v[id] : 0.0f;
}

// Undirected breadth-first distances from `seeds`, at most kRowFeaturesMaxHops (kRowFeaturesMaxHops + 1 = not reached).
inline std::vector<std::uint8_t> hopDistances( const Graph& g, std::size_t n, const std::vector<NodeId>& seeds )
{
    std::vector<std::uint8_t> dist( n, std::uint8_t( kRowFeaturesMaxHops + 1 ) );
    std::deque<NodeId> queue;
    for( const NodeId s : seeds )
    {
        if( s < n && dist[s] != 0 )
        {
            dist[s] = 0;
            queue.push_back( s );
        }
    }
    const std::uint32_t* ro = g.inEdges.rowOffsets();
    const std::uint32_t* ci = g.inEdges.colIndices();
    std::size_t visited = 0;
    while( !queue.empty() && visited++ < kRowFeaturesMaxVisit )
    {
        const NodeId u = queue.front();
        queue.pop_front();
        if( dist[u] >= kRowFeaturesMaxHops )
        {
            continue;
        }
        const auto reach = [&]( NodeId v )
        {
            if( v < n && dist[v] > dist[u] + 1 )
            {
                dist[v] = std::uint8_t( dist[u] + 1 );
                queue.push_back( v );
            }
        };
        for( std::uint32_t k = std::size_t( u ) + 1 < g.outOff.size() ? g.outOff[u] : 0; std::size_t( u ) + 1 < g.outOff.size() && k < g.outOff[u + 1]; ++k )
        {
            reach( g.outTargets[k] );
        }
        for( std::uint32_t k = ro != nullptr && ci != nullptr && std::size_t( u ) < g.inEdges.rows() ? ro[u] : 0;
             ro != nullptr && ci != nullptr && std::size_t( u ) < g.inEdges.rows() && k < ro[u + 1]; ++k )
        {
            reach( NodeId( ci[k] ) );
        }
    }
    return dist;
}

// The (lo, hi) pairs of `nodes` that a declined call joins (the caller one, a candidate the other).
inline std::vector<std::pair<NodeId, NodeId>> declinedPairs( const Graph& g, std::vector<NodeId> nodes )
{
    std::ranges::sort( nodes );
    std::vector<std::pair<NodeId, NodeId>> out;
    for( std::size_t site = 0; site < g.declinedSiteCaller.size() && site < g.declinedSiteList.size(); ++site )
    {
        const NodeId caller = g.declinedSiteCaller[site];
        const std::uint32_t list = g.declinedSiteList[site];
        if( list == kNoDeclinedList || std::size_t( list ) + 1 >= g.declinedListOff.size() || !std::ranges::binary_search( nodes, caller ) )
        {
            continue;
        }
        for( std::uint32_t k = g.declinedListOff[list]; k < g.declinedListOff[list + 1] && k < g.declinedListCand.size(); ++k )
        {
            const NodeId cand = g.declinedListCand[k];
            if( cand != caller && std::ranges::binary_search( nodes, cand ) )
            {
                out.emplace_back( std::min( caller, cand ), std::max( caller, cand ) );
            }
        }
    }
    std::ranges::sort( out );
    out.erase( std::unique( out.begin(), out.end() ), out.end() );
    return out;
}

inline Prov pairProv( const Context& c, NodeId a, NodeId b )
{
    if( a == kNoNode || b == kNoNode || a == b )
    {
        return Prov::None;
    }
    const Prov direct = std::max( edgeProv( c.g, edgeIndex( c.g, a, b ) ), edgeProv( c.g, edgeIndex( c.g, b, a ) ) );
    const bool declined = std::ranges::binary_search( c.declined, std::pair<NodeId, NodeId>( std::min( a, b ), std::max( a, b ) ) );
    return std::max( direct, declined ? Prov::Declined : Prov::None );
}

inline std::vector<std::uint32_t> lensPositions( const std::vector<float>& rank )
{
    std::vector<NodeId> order( rank.size() );
    for( NodeId i = 0; i < order.size(); ++i )
    {
        order[i] = i;
    }
    rw::sortutil::radixSortByScoreDescId( order, rank );
    std::vector<std::uint32_t> pos( rank.size(), 0 );
    for( std::size_t k = 0; k < order.size() && rank[order[k]] > 0.0f; ++k )
    {
        pos[order[k]] = std::uint32_t( k + 1 );
    }
    return pos;
}
inline std::vector<std::uint32_t> fileRanks( const IngestResult& ing, const std::vector<float>& rank )
{
    std::vector<float> best( ing.files.size(), 0.0f );
    for( std::size_t i = 0; i < ing.symbols.size() && i < rank.size(); ++i )
    {
        const std::uint32_t f = ing.symbols[i].fileId;
        best[f] = f < best.size() ? std::max( best[f], rank[i] ) : 0.0f;
    }
    std::vector<std::uint32_t> files( best.size() );
    for( std::uint32_t f = 0; f < files.size(); ++f )
    {
        files[f] = f;
    }
    rw::sortutil::radixSortByScoreDescId( files, best );
    std::vector<std::uint32_t> out( best.size(), 0 );
    for( std::size_t k = 0; k < files.size() && best[files[k]] > 0.0f; ++k )
    {
        out[files[k]] = std::uint32_t( k + 1 );
    }
    return out;
}
// The anchors a name-exact route resolved, as nodes: each one's first definition of that name in its file.
inline std::vector<NodeId> anchorNodes( const IngestResult& ing, const std::vector<RouteAnchorDef>& anchors )
{
    std::vector<NodeId> out;
    for( const RouteAnchorDef& a : anchors )
    {
        const auto hit = std::ranges::find_if( ing.symbols, [&]( const Symbol& s ) { return s.fileId == a.fileId && routeLower( s.name ) == a.lowerName; } );
        if( hit != ing.symbols.end() )
        {
            out.push_back( hit->id );
        }
    }
    return out;
}

inline std::size_t defCount( Context& c, NodeId id )
{
    const std::string& name = c.ing.symbols[id].name;
    const auto memo = std::ranges::find( c.defCounts, name, &std::pair<std::string, std::size_t>::first );
    if( memo != c.defCounts.end() )
    {
        return memo->second;
    }
    const std::size_t n = definitionCountOfName( c.ing, id );
    c.defCounts.emplace_back( name, n );
    return n;
}

// One line: the node (kNoNode when the printed row resolved to none) and where the answer placed it.
struct Line
{
    NodeId id = kNoNode;
    const AnswerRow* row = nullptr; // an answer row
    const AnswerRow* pointer = nullptr; // a <t> that kept its r=
    std::string_view printed = "none"; // row | pointer | tail | none
    bool headRR = false; // a <sigs> <d> row placed above its score order inside the round-robin head
};

// TSV-safe: a tab, CR or LF in a value becomes a space; an absent value is "-".
inline void field( std::string& out, std::string_view v )
{
    out += '\t';
    if( v.empty() )
    {
        out += '-';
        return;
    }
    for( const char ch : v )
    {
        out += ( ch == '\t' || ch == '\n' || ch == '\r' ) ? ' ' : ch;
    }
}
inline void number( std::string& out, double v )
{
    out += std::format( "\t{:.6g}", v );
}
inline void count( std::string& out, long long v )
{
    out += std::format( "\t{}", v );
}

// The section a printed row sits in, as the RIPWIRE_NO_<NAME> switch of the path that printed it (reports/ablation-top10.md).
inline std::string sectionSource( std::string_view section )
{
    static constexpr std::array<std::pair<std::string_view, std::string_view>, 22> kSections = { {
        { "sigs", "CORE" }, { "callers", "CALLER_HOP" }, { "dispatch", "DISPATCH_HOP" }, { "syms", "FILE_SYMS" }, { "hops", "OWNER_HOP" },
        { "bodies", "BODY_SLOT" }, { "fold", "BODY_FOLD" }, { "lit", "LITERAL_ANCHOR" }, { "lit_capped", "LITERAL_ANCHOR" },
        { "selfhooks", "SELF_HOOK" }, { "listed", "LISTED_IN" }, { "ep", "EP_MANIFEST" }, { "reexports", "REEXPORT_HOPS" },
        { "shortkey", "SHORT_KEY" }, { "aliases", "ALIAS_HOP" }, { "dotted_strings", "DOTTED_STRINGS" }, { "unused_in_file", "UNUSED_TABLE" },
        { "reg", "REG_ROWS" }, { "named-file", "FILE_PAGE" }, { "doc_body", "FOR_DOC_BODY" }, { "graph_verb", "ROUTE_DECLINED" }, { "hdr", "HDR_ROWS" },
    } };
    const auto hit = std::ranges::find( kSections, section, &std::pair<std::string_view, std::string_view>::first );
    return hit != kSections.end() ? std::string( hit->second ) : "SECTION:" + std::string( section.empty() ? "root" : section );
}

inline std::string_view demoteVerdictOf( const RowFeatureRecorder& rec, const AnswerRow* r )
{
    if( r == nullptr )
    {
        return {};
    }
    const std::string_view p = attrOf( r->attrs, "p" ), n = attrOf( r->attrs, r->tag == 't' ? "sym" : "n" ), rank = attrOf( r->attrs, "r" );
    const auto hit = std::ranges::find_if( rec.demotes, [&]( const demote_detail::DemoteVerdictRow& v ) { return v.p == p && v.n == n && v.r == rank; } );
    return hit != rec.demotes.end() ? demote_detail::kDemoteVerdictNames[std::size_t( hit->verdict )] : std::string_view();
}

// The query-term evidence of one node: name-field matches, any-field matches, their idf sums, path matches.
struct TermHits
{
    long long name = 0, any = 0, path = 0;
    double nameIdf = 0.0, anyIdf = 0.0;
};
inline TermHits termHits( const Context& c, NodeId id )
{
    TermHits h;
    const LexTermEvidence* ev = c.rec.evidence;
    if( ev == nullptr || ev->maskWords == 0 || id >= ev->symbolCount )
    {
        return h;
    }
    const std::size_t w = ev->maskWords;
    const bool hasName = ev->nameMask.size() >= ( std::size_t( id ) + 1 ) * w;
    const bool hasAny = ev->anyMask.size() >= ( std::size_t( id ) + 1 ) * w;
    const std::string path = routeLower( rootRelPath( c.ing, c.ing.symbols[id].fileId ) );
    for( std::size_t u = 0; u < ev->terms.size() && u < w * 64; ++u )
    {
        const bool inName = hasName && LexTermEvidence::hasBit( ev->nameMask.data() + std::size_t( id ) * w, u );
        const bool inAny = hasAny && LexTermEvidence::hasBit( ev->anyMaskOf( id ), u );
        const double idf = u < ev->df.size() ? ev->idf( u ) : 0.0;
        h.name += inName ? 1 : 0;
        h.any += inAny ? 1 : 0;
        h.nameIdf += inName ? idf : 0.0;
        h.anyIdf += inAny ? idf : 0.0;
        h.path += !ev->terms[u].empty() && path.contains( ev->terms[u] ) ? 1 : 0;
    }
    return h;
}

inline std::string_view headEdge( const Context& c, NodeId id )
{
    if( id == kNoNode || c.head == kNoNode )
    {
        return {};
    }
    if( id == c.head )
    {
        return "self";
    }
    const bool rowToHead = edgeIndex( c.g, id, c.head ) != SIZE_MAX, headToRow = edgeIndex( c.g, c.head, id ) != SIZE_MAX;
    return rowToHead && headToRow ? "both" : rowToHead ? "row_to_head" : headToRow ? "head_to_row" : "none";
}

inline long long hops( const std::vector<std::uint8_t>& dist, NodeId id ) noexcept
{
    return id < dist.size() && dist[id] <= kRowFeaturesMaxHops ? dist[id] : -1;
}

// The best join from `id` to an answer row printed above it (every answer row, for a node the answer does not print as a row).
inline Prov reachProv( const Context& c, const std::vector<Line>& lines, std::size_t self )
{
    Prov best = Prov::None;
    const std::size_t limit = lines[self].row != nullptr ? self : lines.size();
    for( std::size_t k = 0; k < limit; ++k )
    {
        if( lines[k].row != nullptr && k != self )
        {
            best = std::max( best, pairProv( c, lines[self].id, lines[k].id ) );
        }
    }
    return best;
}

inline std::string rowSource( const Context& c, const Line& l )
{
    std::string src = l.row != nullptr ? sectionSource( l.row->section ) : "CORE";
    for( std::size_t s = 0; l.id != kNoNode && s < std::size_t( RowStage::Count ); ++s )
    {
        const std::vector<float>& after = c.rec.after[s];
        if( !after.empty() && at( after, l.id ) != at( before( c.rec, s ), l.id ) )
        {
            src += "+";
            src += kRowStageSources[s];
        }
    }
    src += l.headRR ? "+HEAD_RR" : "";
    return src;
}

inline std::string renderLine( Context& c, std::string_view task, const std::vector<Line>& lines, std::size_t k )
{
    const Line& l = lines[k];
    const AnswerRow* placed = l.row != nullptr ? l.row : l.pointer;
    const bool known = l.id != kNoNode && l.id < c.ing.symbols.size();
    const Symbol* s = known ? &c.ing.symbols[l.id] : nullptr;
    std::string out;
    out.reserve( 512 );
    field( out, task );
    out.erase( 0, 1 ); // the first column has no leading tab
    count( out, known ? (long long)l.id : -1 );
    const std::string printedName = placed != nullptr ? filesyms_detail::unescapeXmlAttr( attrOf( placed->attrs, placed->tag == 't' ? "sym" : "n" ) ) : std::string();
    field( out, !printedName.empty() ? std::string_view( printedName ) : s != nullptr ? std::string_view( s->name ) : std::string_view() );
    field( out, s != nullptr ? std::string_view( s->scope ) : std::string_view() );
    const std::string file = s != nullptr ? lensRowPath( c.ing, s->fileId, c.rec.rootArg )
                                          : placed != nullptr ? filesyms_detail::unescapeXmlAttr( demote_detail::fileOf( *placed ) ) : std::string();
    field( out, file );
    count( out, s != nullptr ? (long long)s->line : 0 );
    field( out, s != nullptr ? std::string_view( symTag( s->kind ) ) : std::string_view() );
    field( out, l.printed );
    count( out, l.row != nullptr ? (long long)l.row->pos : 0 );
    field( out, l.row != nullptr ? std::string_view( &l.row->tag, 1 ) : std::string_view() );
    field( out, placed != nullptr ? placed->section : std::string_view() );
    count( out, l.row != nullptr ? (long long)l.row->dpos : 0 );
    field( out, placed != nullptr ? attrOf( placed->attrs, "r" ) : std::string_view() );
    const std::uint32_t lensPos = known && l.id < c.lensPos.size() ? c.lensPos[l.id] : 0;
    count( out, lensPos );
    count( out, lensPos != 0 && lensPos <= c.rec.surface.size() ? 1 : 0 );
    number( out, known ? at( c.rec.finalRank, l.id ) : 0.0 );
    number( out, known ? at( c.rec.lex, l.id ) : 0.0 );
    number( out, known && l.id < c.rec.tier.size() ? c.rec.tier[l.id] : 1.0 );
    for( std::size_t st = 0; st < std::size_t( RowStage::Count ); ++st )
    {
        const std::vector<float>& after = c.rec.after[st];
        number( out, known && !after.empty() ? double( at( after, l.id ) ) - double( at( before( c.rec, st ), l.id ) ) : 0.0 );
    }
    count( out, known ? hops( c.headDist, l.id ) : -1 );
    count( out, known && c.anchored ? hops( c.anchorDist, l.id ) : -1 );
    field( out, headEdge( c, l.id ) );
    field( out, known && c.head != kNoNode && l.id != c.head ? kProvNames[std::size_t( pairProv( c, l.id, c.head ) )] : std::string_view() );
    field( out, known ? kProvNames[std::size_t( reachProv( c, lines, k ) )] : std::string_view() );
    const bool headKnown = known && c.head != kNoNode;
    const std::string_view headPath = headKnown ? rootRelPath( c.ing, c.ing.symbols[c.head].fileId ) : std::string_view();
    const std::string_view rowPath = known ? rootRelPath( c.ing, s->fileId ) : std::string_view();
    count( out, headKnown && s->fileId == c.ing.symbols[c.head].fileId ? 1 : 0 );
    count( out, headKnown && headPath.substr( 0, headPath.rfind( '/' ) + 1 ) == rowPath.substr( 0, rowPath.rfind( '/' ) + 1 ) ? 1 : 0 );
    count( out, known && s->fileId < c.fileRank.size() ? c.fileRank[s->fileId] : 0 );
    const TermHits t = known ? termHits( c, l.id ) : TermHits {};
    count( out, t.name );
    count( out, t.any );
    number( out, t.nameIdf );
    number( out, t.anyIdf );
    count( out, t.path );
    count( out, c.rec.evidence != nullptr ? (long long)c.rec.evidence->terms.size() : 0 );
    count( out, known ? (long long)defCount( c, l.id ) : 0 );
    field( out, demoteVerdictOf( c.rec, l.row != nullptr && l.row->tag == 'd' ? l.row : l.pointer ) );
    field( out, rowSource( c, l ) );
    count( out, l.headRR ? 1 : 0 );
    out += '\n';
    return out;
}

// The lines in output order: answer rows, pointers, then the ranked candidates (and kRowFeaturesBeyondRows more) not listed yet.
inline std::vector<Line> collectLines( const IngestResult& ing, const RowFeatureRecorder& rec, const demote_detail::AnswerScan& scan,
                                       const std::vector<std::uint32_t>& lensPos )
{
    filesyms_detail::FileLookup files( ing );
    std::vector<demote_detail::RowWant> wants;
    std::vector<const AnswerRow*> pointers;
    for( const AnswerRow& r : scan.rows )
    {
        wants.push_back( demote_detail::rowWant( files, r ) );
    }
    std::vector<std::pair<std::uint32_t, std::string>> tailed; // (file, leaf) of every plain <t> entry
    for( const AnswerRow& t : scan.tails )
    {
        const std::uint32_t f = files.of( filesyms_detail::unescapeXmlAttr( demote_detail::fileOf( t ) ) );
        const std::string syms = filesyms_detail::unescapeXmlAttr( attrOf( t.attrs, "sym" ) );
        if( !attrOf( t.attrs, "r" ).empty() )
        {
            pointers.push_back( &t );
            wants.push_back( demote_detail::RowWant { .file = f, .leaf = std::string( filesyms_detail::leafName( syms ) ) } );
            continue;
        }
        for( std::size_t from = 0; from <= syms.size(); )
        {
            const std::size_t comma = std::min( syms.find( ',', from ), syms.size() );
            tailed.emplace_back( f, std::string( filesyms_detail::leafName( std::string_view( syms ).substr( from, comma - from ) ) ) );
            from = comma + 1;
        }
    }
    demote_detail::resolveWants( ing, wants );
    std::ranges::sort( tailed );
    std::vector<Line> lines;
    std::vector<NodeId> listed;
    for( std::size_t k = 0; k < scan.rows.size(); ++k )
    {
        lines.push_back( Line { .id = wants[k].id, .row = &scan.rows[k], .printed = "row" } );
        listed.push_back( wants[k].id );
    }
    const auto unlisted = [&]( NodeId id ) { return id != kNoNode && !std::ranges::contains( listed, id ); };
    for( std::size_t k = 0; k < pointers.size(); ++k )
    {
        const NodeId id = wants[scan.rows.size() + k].id;
        if( unlisted( id ) || id == kNoNode )
        {
            lines.push_back( Line { .id = id, .pointer = pointers[k], .printed = "pointer" } );
            listed.push_back( id );
        }
    }
    std::vector<NodeId> ranked = rec.surface;
    for( NodeId id = 0; id < lensPos.size(); ++id )
    {
        if( lensPos[id] > rec.surface.size() && lensPos[id] <= rec.surface.size() + kRowFeaturesBeyondRows )
        {
            ranked.push_back( id );
        }
    }
    std::sort( ranked.begin() + std::ptrdiff_t( rec.surface.size() ), ranked.end(), [&]( NodeId a, NodeId b ) { return lensPos[a] < lensPos[b]; } );
    for( const NodeId id : ranked )
    {
        if( unlisted( id ) && id < ing.symbols.size() )
        {
            const Symbol& s = ing.symbols[id];
            const bool tail = std::ranges::binary_search( tailed, std::pair<std::uint32_t, std::string>( s.fileId, s.name ) );
            lines.push_back( Line { .id = id, .printed = tail ? "tail" : "none" } );
            listed.push_back( id );
        }
    }
    return lines;
}

// HEAD_RR (serialize.h reorderHeadRoundRobin): a <sigs> <d> row inside the round-robin head printed above where its score puts it
// among the printed <sigs> <d> rows.
inline void markHeadRR( std::vector<Line>& lines, const std::vector<std::uint32_t>& lensPos )
{
    std::vector<std::size_t> sigs;
    for( std::size_t k = 0; k < lines.size(); ++k )
    {
        if( lines[k].row != nullptr && lines[k].row->tag == 'd' && lines[k].row->inSigs && lines[k].id != kNoNode && lines[k].id < lensPos.size() )
        {
            sigs.push_back( k );
        }
    }
    std::vector<std::size_t> byScore = sigs;
    std::ranges::stable_sort( byScore, {}, [&]( std::size_t k ) { return lensPos[lines[k].id] == 0 ? UINT32_MAX : lensPos[lines[k].id]; } );
    for( std::size_t printedAt = 0; printedAt < sigs.size() && printedAt < kHeadRoundRobinRows; ++printedAt )
    {
        const std::size_t scoreAt = std::size_t( std::ranges::find( byScore, sigs[printedAt] ) - byScore.begin() );
        lines[sigs[printedAt]].headRR = printedAt < scoreAt;
    }
}

inline std::string headerText()
{
    std::string cols;
    const auto add = [&]( std::string_view c ) { cols += cols.empty() ? "" : "\t"; cols += c; };
    std::ranges::for_each( kRowFeatureLeadColumns, add );
    std::ranges::for_each( kRowFeatureScoreColumns, add );
    std::ranges::for_each( kRowStageColumns, add );
    std::ranges::for_each( kRowFeatureTrailColumns, add );
    const std::size_t n = kRowFeatureLeadColumns.size() + kRowFeatureScoreColumns.size() + kRowStageColumns.size() + kRowFeatureTrailColumns.size();
    return std::format( "# {} columns={}\n{}\n", kRowFeaturesSchema, n, cols );
}

// Append `text` to `path` (the two header lines first when the file is new or empty); false when any step failed.
inline bool appendFile( const std::string& path, const std::string& text )
{
    std::FILE* f = std::fopen( path.c_str(), "ab" );
    if( f == nullptr )
    {
        return false;
    }
    const bool fresh = std::fseek( f, 0, SEEK_END ) == 0 && std::ftell( f ) == 0;
    const std::string head = fresh ? headerText() : std::string();
    const bool wrote = std::fwrite( head.data(), 1, head.size(), f ) == head.size() && std::fwrite( text.data(), 1, text.size(), f ) == text.size();
    const bool flushed = std::fflush( f ) == 0 && std::ferror( f ) == 0;
    return std::fclose( f ) == 0 && wrote && flushed;
}
} // namespace rowfeat_detail

// The final answer's bytes (everything the run printed inside the root): place every line and write the file. Disarms.
inline void rowFeaturesFinish( const IngestResult& ing, const Graph& g, std::string_view task, std::string_view answer )
{
    RowFeatureRecorder& rec = rowFeatures();
    if( !rec.armed )
    {
        return;
    }
    rec.armed = false;
    demote_detail::demoteVerdictSink() = nullptr;
    using namespace rowfeat_detail;
    const demote_detail::AnswerScan scan = demote_detail::scanAnswer( answer, /*withTails=*/true );
    Context c { .ing = ing, .g = g, .rec = rec, .lensPos = lensPositions( rec.finalRank ), .fileRank = fileRanks( ing, rec.finalRank ) };
    std::vector<Line> lines = collectLines( ing, rec, scan, c.lensPos );
    markHeadRR( lines, c.lensPos );
    const auto firstRow = std::ranges::find_if( lines, []( const Line& l ) { return l.row != nullptr && l.id != kNoNode; } );
    c.head = firstRow != lines.end() ? firstRow->id : !rec.surface.empty() ? rec.surface.front() : kNoNode;
    std::vector<NodeId> nodes;
    for( const Line& l : lines )
    {
        if( l.id != kNoNode )
        {
            nodes.push_back( l.id );
        }
    }
    c.declined = declinedPairs( g, nodes );
    c.headDist = hopDistances( g, ing.symbols.size(), c.head != kNoNode ? std::vector<NodeId> { c.head } : std::vector<NodeId> {} );
    const std::vector<NodeId> anchors = anchorNodes( ing, rec.anchors );
    c.anchored = !anchors.empty();
    c.anchorDist = c.anchored ? hopDistances( g, ing.symbols.size(), anchors ) : std::vector<std::uint8_t> {};
    std::string text;
    for( std::size_t k = 0; k < lines.size(); ++k )
    {
        text += renderLine( c, task, lines, k );
    }
    if( !appendFile( rec.path, text ) )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "the dump is a side file written after the answer; the answer never reads it", "RIPWIRE_ROW_FEATURES: write failed" );
        notice( "could not write the file (open, write, flush or close failed): the rows of this call are not in it" );
    }
}
} // namespace rw
