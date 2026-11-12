#pragma once
// forsiblingdemote.h — SIBLING-DEMOTE (precision card P1, variant b): a ranked <sigs> <d> row that is a lower sibling of a file the answer
// already shows, deep in the answer, is printed as a tail pointer `<t p="FILE" sym="NAME"/>` in its place (still printed, no longer an
// answer row). On the graded sets these rows are where most picked decoys sit (a same-file neighbour of the right row, median <d> rank 16),
// beside a right item that is already printed.
//
// THE RULE, read off the answer's own bytes (every block before <syms>, as the CLI and MCP `for` emit them — one renderer, both surfaces):
// a <d> row inside <sigs> is demoted when ALL hold
//   (r) its <d> rank (place among the answer's <d> rows) is past kDemoteMinRank (10). Its answer-row position (the <d>, <y>, <s> and
//       non-`used` <u> rows in output order) is then past 10 too, so the first 10 answer rows are never touched and nothing moves up
//       into them (PRECISION-LAB 11-10: a demote at <d> rank 6-10 pulled deeper rows into the top 10 and raised its Wrong count, and
//       cleared no picked row the rank > 10 rule does not),
//   (f) a higher <d> row shows the same file,
// and no keep guard holds:
//   (K1) TYPE-WITH-MEMBERS: the row carries mem= (a type with its member list is a definition the reader follows, not a sibling decoy);
//   (K2) HOP-CALLEE: its name, or its last segment, is a callee <c n=> under a <h> hop row of the answer;
//   (K3) OWNER-NEAR: it is Owner.member / Owner::member and one of the kOwnerNearRows <d> rows right above it is named exactly Owner;
//   (K4) CALL-PATH: the index holds a call path of at most two PROVEN edges (a call: not bound by name alone, not a link) between it and
//        one of the first kCallPathSeeds resolved answer rows, either way round (ROW-FEATURES-2: a tail rule lost credited call-site
//        rows that are proven callers of the head);
//   (K5) a kept <d> row's same_as= names it (its doc+signature text is the one that row points to);
//   (K6) NOTED: the row carries a <note> (a gotcha someone saved with --note-add on that symbol: a pointer would drop it);
//   (K7) SLOT-FACT: the row carries slot_by= / slot_fields= (FN-VALUED-SLOT's cross-file call facts ride on the row, not the pointer);
//   (K8) TERM-HIT, under a token budget only (DemoteRegime::Budgeted): a word K4's seeds read (taskNames) is a whole identifier of
//        the row's n=, its sc= or its printed signature (B26-FIX: a budgeted answer pointed rows whose text carried a gold item's terms).
// K4's seeds are the first kCallPathSeeds resolved answer rows AND every answer row the task names (an identifier-syntax word of
// the task spelled as the row's last segment): a proven caller or callee of the symbol a `who calls X` task names is its answer.
// The pointer keeps the row's p=, n= (as sym=) and r= bytes; a short legend comment rides before the first one. Under a token budget (CLI --token-budget,
// MCP budget_tokens; a bare --max-tokens is not read by --for) and in --json the rule runs too (DEMOTE-ALL-DIALECTS, fordemoteall.h:
// on <sigs> before the rows settle, so the bytes it frees buy rows). The demoted bytes are priced markup, so the root's est_tokens= is
// re-priced once over the post-passes (R-DEDUP's tail cut, ONE-SIDE-REACH, then this one: serialize.h repriceRootAfterCut) — the net change is
// signed: on short rows the legend and pointers can ADD bytes, and est_tokens= then goes up.
// RIPWIRE_NO_SIBLING_DEMOTE=1 turns it off (byte identity and the gate's twins).
#include "darkflags.h" // darkflags::containsWord, the whole-identifier test (K8)
#include "forfilesyms.h" // filesyms_detail::FileLookup / leafName / unescapeXmlAttr
#include "graph.h" // Graph::outOff / outTargets / outNameOnly / inEdges, edgeIndex, edgeKindByte
#include "lexical.h" // splitRouteWords, isRouteStopword, routeLower, detail::graphSubjectTrimWord
#include "model.h"
#include "serialize.h" // attrOf
#include "subjectanchor.h" // subject_detail::hasNameSyntax

#include <algorithm>
#include <array>
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
inline constexpr std::size_t kDemoteMinRank = 10; // (r): rows past the 10th <d> row (so past the first 10 answer rows)
inline constexpr std::size_t kOwnerNearRows = 4; // (K3): the <d> rows right above that may name the owner
inline constexpr std::size_t kCallPathSeeds = 3; // (K4): the first resolved answer rows a call path may reach

inline constexpr std::string_view kSiblingDemoteLegend =
    "<!-- demote: a <t> in sigs is a lower same-file sibling past answer row 10, a pointer (p= file, sym= name, r= rank), not the answer -->";

// Which answer the rule reads: the default (no budget) answer, or a budgeted one, where K8 also keeps a row a task term hits.
enum class DemoteRegime : bool
{
    Default,
    Budgeted,
};

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
    bool noted = false; // (K6): a <note> rides inside the row
    std::string_view section; // the element right under the root that holds the row (sigs, callers, syms, ...): ROW-FEATURE-DUMP's row source
};
struct AnswerScan
{
    std::vector<AnswerRow> rows; // the answer rows in output order
    std::vector<std::string> callees; // n= of every <c> under a <h> hop row, unescaped
    std::vector<AnswerRow> tails; // with scanAnswer's withTails only: every <t> (a tail entry, or a pointer that keeps its r=), in output order
};

using filesyms_detail::tagIs;

using OpenElements = std::vector<std::pair<std::string_view, std::string_view>>; // (element name, its p=) of the open elements
inline void closeElement( OpenElements& open, std::string_view name )
{
    const auto at = std::ranges::find( open | std::views::reverse, name, &std::pair<std::string_view, std::string_view>::first );
    open.erase( at == open.rend() ? open.end() : std::prev( at.base() ), open.end() );
}
inline std::string_view nearestP( const OpenElements& open )
{
    const auto withP = std::ranges::find_if( open | std::views::reverse, []( const auto& e ) { return !e.second.empty(); } );
    return withP == open.rend() ? std::string_view() : withP->second;
}

// The element right under the root among the open ones ("" outside any).
inline std::string_view sectionOf( const OpenElements& open )
{
    return open.size() > 1 ? open[1].first : std::string_view();
}

// One walk over the answer's tags outside comments and CDATA. withTails: the <t> rows too (ROW-FEATURE-DUMP reads pointers and tails).
inline AnswerScan scanAnswer( std::string_view text, bool withTails = false )
{
    AnswerScan out;
    bool inSigs = false, inHop = false;
    std::size_t dRows = 0;
    OpenElements open;
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
            closeElement( open, name );
            continue;
        }
        const bool selfClosing = text[close - 1] == '/';
        const std::size_t nameEnd = std::min( text.find_first_of( " />", i + 1 ), close );
        const std::string_view attrs = text.substr( nameEnd, close - nameEnd - ( selfClosing ? 1 : 0 ) );
        const std::string_view parentP = nearestP( open );
        const std::string_view section = sectionOf( open ); // read before this element opens, like parentP
        if( !selfClosing && rest[1] != '?' && rest[1] != '!' )
        {
            open.emplace_back( text.substr( i + 1, nameEnd - i - 1 ), attrOf( attrs, "p" ) );
        }
        if( tagIs( rest, "sigs" ) )
        {
            inSigs = !selfClosing;
        }
        else if( tagIs( rest, "h" ) )
        {
            inHop = !selfClosing;
        }
        else if( inHop && rest[1] == 'c' && rest[2] == ' ' )
        {
            out.callees.push_back( filesyms_detail::unescapeXmlAttr( attrOf( attrs, "n" ) ) );
        }
        else if( const char k = rest[1]; ( k == 'd' || k == 'y' || k == 's' || k == 'u' ) && rest[2] == ' ' && !( k == 'u' && attrOf( attrs, "v" ) == "used" ) )
        {
            AnswerRow r { .tag = k, .at = i, .end = close + 1, .attrs = attrs, .parentP = parentP, .pos = out.rows.size() + 1, .inSigs = inSigs, .section = section };
            if( k == 'd' )
            {
                r.dpos = ++dRows;
                const std::size_t endTag = selfClosing ? std::string_view::npos : text.find( "</d>", close );
                r.end = endTag == std::string_view::npos ? r.end : endTag + 4;
                r.noted = text.substr( close, r.end - close ).contains( "<note " );
            }
            out.rows.push_back( r );
        }
        else if( withTails && rest[1] == 't' && rest[2] == ' ' )
        {
            out.tails.push_back( AnswerRow { .tag = 't', .at = i, .end = close + 1, .attrs = attrs, .parentP = parentP, .inSigs = inSigs, .section = section } );
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
// K1 mem= (a type with its member list) and K7 slot_by= / slot_fields= (FN-VALUED-SLOT's call facts): a row carrying one stays a row.
inline constexpr std::array<std::string_view, 3> kKeepRowAttrs = { " mem=\"", " slot_by=\"", " slot_fields=\"" };
// The identifier-syntax words of the task (camelCase, snake_case, Owner::name / pkg.Name) as spelled, trimmed, stopwords left out.
inline std::vector<std::string_view> taskNameWords( std::string_view task )
{
    std::vector<std::string_view> words;
    for( const std::string_view w : splitRouteWords( task ) )
    {
        const std::string_view t = detail::graphSubjectTrimWord( w ).text;
        if( !isRouteStopword( routeLower( t ) ) && subject_detail::hasNameSyntax( t ) )
        {
            words.push_back( t );
        }
    }
    return words;
}
// Those words' last segments (the member after `.`, `::` or `#`).
inline std::vector<std::string_view> taskNames( std::string_view task )
{
    std::vector<std::string_view> names = taskNameWords( task );
    std::ranges::transform( names, names.begin(), filesyms_detail::leafName );
    return names;
}
inline bool hopCallee( const AnswerScan& scan, std::string_view name )
{
    const std::string_view last = filesyms_detail::leafName( name ); // the member after `.`, `::` or `#`, as <syms> reads a head row
    return std::ranges::any_of( scan.callees, [&]( const std::string& c )
                                { return c == name || c == last; } );
}
inline bool ownerNear( const std::vector<const AnswerRow*>& dRows, const AnswerRow& r, std::string_view name )
{
    const std::size_t ownerEnd = std::min( name.find( '.' ), name.find( "::" ) ); // Owner.member / Owner::member: Owner
    if( ownerEnd == std::string_view::npos || ownerEnd == 0 )
    {
        return false;
    }
    const std::string_view owner = name.substr( 0, ownerEnd );
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
// Out-neighbours (forward) or in-neighbours (!forward) of `u`, itself left out; provenOnly: over proven edges only.
template<class F>
inline void forNeighbours( const Graph& g, NodeId u, bool forward, bool provenOnly, F&& visit )
{
    if( forward )
    {
        for( std::uint32_t k = std::size_t( u ) + 1 < g.outOff.size() ? g.outOff[u] : 0; std::size_t( u ) + 1 < g.outOff.size() && k < g.outOff[u + 1]; ++k )
        {
            if( g.outTargets[k] != u && ( !provenOnly || provenEdge( g, k ) ) )
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
        if( ci[k] != u && ( !provenOnly || provenEdge( g, edgeIndex( g, ci[k], u ) ) ) )
        {
            visit( NodeId( ci[k] ) );
        }
    }
}
// Proven out-neighbours (forward) or in-neighbours (!forward) of `u`, itself left out.
template<class F>
inline void forProvenNeighbours( const Graph& g, NodeId u, bool forward, F&& visit )
{
    forNeighbours( g, u, forward, /*provenOnly=*/true, visit );
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

// Why a <d> row stays a row, or that it goes (ROW-FEATURE-DUMP prints it per row): the rule's checks in the order it reads them.
enum class DemoteVerdict : std::uint8_t
{
    NotInSigs, // not a <sigs> row
    TopRank, // (r): <d> rank <= kDemoteMinRank
    Noted, // (K6)
    TypeWithMembers, // (K1) mem=
    SlotFact, // (K7) slot_by= / slot_fields=
    NoSameFileAbove, // (f) fails
    HopCallee, // (K2)
    OwnerNear, // (K3)
    Picked, // (r) and (f) hold and no byte guard keeps it: K4 and K5 decide
    CallPath, // (K4)
    SameAs, // (K5)
    TermHit, // (K8): a task term hits the row's text, under a budget
    Demoted, // printed as a tail pointer
};
inline constexpr std::array<std::string_view, 13> kDemoteVerdictNames = { "not_sigs", "top_rank", "K6_noted", "K1_mem", "K7_slot", "no_same_file",
                                                                          "K2_hop_callee", "K3_owner_near", "picked", "K4_call_path", "K5_same_as",
                                                                          "K8_term_hit", "demoted" };
static_assert( kDemoteVerdictNames.size() == std::size_t( DemoteVerdict::Demoted ) + 1, "one name per verdict" );

// The verdict the answer's own bytes give a <d> row: (r), (f), K1-K3, K6 and K7; Picked leaves K4 and K5 to the graph.
inline DemoteVerdict verdictByBytes( const AnswerScan& scan, const std::vector<const AnswerRow*>& dRows, const AnswerRow& r )
{
    const auto carries = [&]( std::string_view attr ) { return r.attrs.contains( attr ); };
    if( !r.inSigs || r.dpos <= kDemoteMinRank || r.noted )
    {
        return !r.inSigs ? DemoteVerdict::NotInSigs : r.dpos <= kDemoteMinRank ? DemoteVerdict::TopRank : DemoteVerdict::Noted;
    }
    if( std::ranges::any_of( kKeepRowAttrs, carries ) )
    {
        return carries( kKeepRowAttrs[0] ) ? DemoteVerdict::TypeWithMembers : DemoteVerdict::SlotFact;
    }
    const std::string_view file = fileOf( r );
    const std::string name = filesyms_detail::unescapeXmlAttr( attrOf( r.attrs, "n" ) );
    if( !std::any_of( dRows.begin(), dRows.begin() + std::ptrdiff_t( r.dpos - 1 ), [&]( const AnswerRow* x ) { return fileOf( *x ) == file; } ) )
    {
        return DemoteVerdict::NoSameFileAbove;
    }
    return hopCallee( scan, name ) ? DemoteVerdict::HopCallee : ownerNear( dRows, r, name ) ? DemoteVerdict::OwnerNear : DemoteVerdict::Picked;
}

// The <d> rows (r) and (f) pick that K1-K3, K6 and K7 (the answer's own bytes) do not keep, in answer order.
inline std::vector<const AnswerRow*> pickByBytes( const AnswerScan& scan, const std::vector<const AnswerRow*>& dRows )
{
    std::vector<const AnswerRow*> picked;
    for( const AnswerRow* r : dRows )
    {
        if( verdictByBytes( scan, dRows, *r ) == DemoteVerdict::Picked )
        {
            picked.push_back( r );
        }
    }
    return picked;
}
// K4: demote[pos - 1] = 1 for each picked row with no proven <= 2-hop path to a seed. Every answer row is resolved in one pass; the
// seeds are the first kCallPathSeeds distinct resolved ones, then every resolved row the task names.
inline void markWithoutCallPath( const IngestResult& ing, const Graph& g, std::string_view task, const AnswerScan& scan,
                                 const std::vector<const AnswerRow*>& picked, std::vector<char>& demote )
{
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
    const std::vector<std::string_view> named = taskNames( task );
    for( const RowWant& w : wants )
    {
        if( w.id != kNoNode && std::ranges::contains( named, std::string_view( w.leaf ) ) && !std::ranges::contains( seeds, w.id ) )
        {
            seeds.push_back( w.id );
        }
    }
    const SeedReach reach = seedReach( g, std::move( seeds ) );
    for( const AnswerRow* r : picked )
    {
        const NodeId id = wants[r->pos - 1].id;
        demote[r->pos - 1] = id == kNoNode || !provenPathToSeed( g, reach, id ) ? 1 : 0;
    }
}
// K5: a kept <d> row's same_as= names the row its text stands for — that row stays (to a fixpoint: a row kept here may name another).
inline void keepSameAsTargets( const std::vector<const AnswerRow*>& dRows, const std::vector<const AnswerRow*>& picked, std::vector<char>& demote )
{
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
}
// The answer with each demoted row rewritten in place as <t p= sym= r=/> (the row's own bytes; r= keeps its rank readable: a budgeted
// answer's rows stay a rank prefix of this one's), the legend comment before the first; "" when none is.
inline std::string pointerAnswer( std::string_view answer, const std::vector<const AnswerRow*>& picked, const std::vector<char>& demote )
{
    std::vector<filesyms_detail::TailPointerSpan> spans;
    for( const AnswerRow* r : picked )
    {
        if( demote[r->pos - 1] != 0 )
        {
            spans.push_back( { .at = r->at, .end = r->end, .p = attrOf( r->attrs, "p" ), .sym = attrOf( r->attrs, "n" ), .rank = attrOf( r->attrs, "r" ) } );
        }
    }
    return filesyms_detail::tailPointerText( answer, spans, kSiblingDemoteLegend );
}

// K8: a task word (K4's taskNames) is a whole identifier of the row's n=, sc= or printed text (its signature, between the open tag
// and </d>).
inline bool termHitsRow( std::string_view answer, const AnswerRow& r, const std::vector<std::string_view>& terms )
{
    const std::string name = filesyms_detail::unescapeXmlAttr( attrOf( r.attrs, "n" ) );
    const std::string_view scope = attrOf( r.attrs, "sc" );
    const std::size_t open = answer.find( '>', r.at );
    const std::string_view text = open < r.end ? answer.substr( open + 1, r.end - open - 1 ) : std::string_view();
    return std::ranges::any_of( terms, [&]( std::string_view t )
                                { return !t.empty() && ( darkflags::containsWord( name, t ) || darkflags::containsWord( scope, t ) || darkflags::containsWord( text, t ) ); } );
}

// ROW-FEATURE-DUMP (src/forrowfeatures.h): one <d> row's verdict, keyed by the row's p=, n= and r= bytes (a pointer keeps all three).
struct DemoteVerdictRow
{
    std::string p, n, r;
    DemoteVerdict verdict = DemoteVerdict::NotInSigs;
};
// Where demoteSiblingRows records its verdicts: null on every run but a RIPWIRE_ROW_FEATURES one, which records nothing.
inline std::vector<DemoteVerdictRow>*& demoteVerdictSink() noexcept
{
    static std::vector<DemoteVerdictRow>* sink = nullptr;
    return sink;
}
// Every <d> row's verdict into `sink`. afterK4 / demote: the demote marks after K4 and after K5 (null: nothing was picked).
inline void recordDemoteVerdicts( std::vector<DemoteVerdictRow>& sink, const AnswerScan& scan, const std::vector<const AnswerRow*>& dRows,
                                  const std::vector<char>* afterK4, const std::vector<char>* demote )
{
    for( const AnswerRow* r : dRows )
    {
        DemoteVerdict v = verdictByBytes( scan, dRows, *r );
        if( v == DemoteVerdict::Picked && afterK4 != nullptr && demote != nullptr )
        {
            v = ( *demote )[r->pos - 1] != 0 ? DemoteVerdict::Demoted : ( *afterK4 )[r->pos - 1] != 0 ? DemoteVerdict::SameAs : DemoteVerdict::CallPath;
        }
        sink.push_back( { std::string( attrOf( r->attrs, "p" ) ), std::string( attrOf( r->attrs, "n" ) ), std::string( attrOf( r->attrs, "r" ) ), v } );
    }
}

// (K8) the verdict of each row K8 kept whole (recordDemoteVerdicts read it as a picked row K4 kept).
inline void markTermKept( std::vector<DemoteVerdictRow>& sink, const std::vector<const AnswerRow*>& termKept )
{
    for( const AnswerRow* r : termKept )
    {
        for( DemoteVerdictRow& v : sink )
        {
            if( v.p == attrOf( r->attrs, "p" ) && v.n == attrOf( r->attrs, "n" ) && v.r == attrOf( r->attrs, "r" ) )
            {
                v.verdict = DemoteVerdict::TermHit;
            }
        }
    }
}

// The answer with the demoted rows rewritten as tail pointers, read as `regime` says (Budgeted: K8 holds too); "" when none is.
inline std::string demoteSiblingRowsAs( const IngestResult& ing, const Graph& g, std::string_view task, std::string_view answer, DemoteRegime regime )
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
    std::vector<const AnswerRow*> picked = pickByBytes( scan, dRows );
    std::vector<const AnswerRow*> termKept; // (K8): picked rows a task term hits, kept whole under a budget
    if( regime == DemoteRegime::Budgeted )
    {
        const std::vector<std::string_view> terms = taskNames( task );
        std::erase_if( picked, [&]( const AnswerRow* r ) { return termHitsRow( answer, *r, terms ) && ( termKept.push_back( r ), true ); } );
    }
    std::vector<DemoteVerdictRow>* const sink = demoteVerdictSink();
    if( picked.empty() )
    {
        if( sink != nullptr )
        {
            recordDemoteVerdicts( *sink, scan, dRows, nullptr, nullptr );
            markTermKept( *sink, termKept );
        }
        return {};
    }
    std::vector<char> demote( scan.rows.size(), 0 );
    markWithoutCallPath( ing, g, task, scan, picked, demote );
    const std::vector<char> afterK4 = sink != nullptr ? demote : std::vector<char>();
    keepSameAsTargets( dRows, picked, demote );
    if( sink != nullptr )
    {
        recordDemoteVerdicts( *sink, scan, dRows, &afterK4, &demote );
        markTermKept( *sink, termKept );
    }
    return pointerAnswer( answer, picked, demote );
}
} // namespace demote_detail
} // namespace rw
