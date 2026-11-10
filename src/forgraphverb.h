#pragma once
// forgraphverb.h — FOR-ROUTE-DECLINED: a --for task SPELLED as a graph question (`path from A to B`, `callers of X`,
// `common callers of A and B`) gets the graph verb it names appended after its ordinary answer, run on the
// already-built index (CLI src/verbs_for.h appendSubjectGraphVerbBlock, MCP `for` src/mcpverbs.h forTaskText — one wrapper).
//
// WHY. The ranked --for bundle answers these by subtoken overlap and misses the chain between the two names; the
// verb answers them from the call graph. Measured (ORCH reports/for-route-s0.md, train-39 binary, LARGE-DEV): appending
// the verb's DEFAULT-cap answer flips 7 rows a tier (5 to complete), recovers 13 of 15 missing chain items and loses
// none, at +1.2-4.9 KB per fired row; the parser fires on 0 of 258 non-graph subjects.
//
// WHAT. lexical.h parseGraphSubject reads the endpoints from the task's words (no plain-word fallback but `main`);
// chooseGraphSubjectArgs below tries at most kGraphSubjectAttempts candidate combinations in preference order and
// keeps the first whose every endpoint the verb's own resolver finds (the verb then never refuses). The ordinary
// answer is never replaced: the block rides after it, inside <graph_verb endpoints="subject">, whose legend says the
// endpoints were read from prose (a name match, hedged), and the verb's default caps and next= paging bound it.
// Nothing resolves → nothing is appended (byte-identical to the answer without this lane).
#include "compactlegend.h"   // spanHasAttr — the ONE attribute-at-a-tag-boundary test
#include "filter.h"      // pathTierOf — name_test_hops=: the verb's own test/fixture path classifier
#include "graph.h"       // resolveAllByNameQualified / resolveFocus — the callers / connect resolvers
#include "lexical.h"     // parseGraphSubject — the subject-only half
#include "nextverb.h"    // nextFlag / nextAttrXml — verb= is a pasteable invocation
#include "packtask.h"    // findSectionOpenTag — an element's open tag, comments skipped
#include "pathgaps.h"    // resolvePathEndpoint — the --path resolver
#include "pathpairs.h"   // pathDefInTests — the --defs class="test" rule (M1)
#include "defattrib.h"   // endpointDefinitionCount — from= binds one definition (M3)
#include "backhops.h"    // DeclinedCrossRule — a builtin-spelled declined call is no crossing (M3)
#include "infra/emit.h"  // emitTo — the met_bridge disclosure's stderr line
#include "serialize.h"   // escapeXml

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <format>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
inline constexpr std::size_t kGraphSubjectAttempts = 4;   // candidate combinations tried (Stage 0: <= 4)
inline constexpr std::size_t kGraphSubjectSlotCands = 3;  // per-slot candidates in a two-endpoint form (3 x 3, best 4)

struct GraphSubjectArgs
{
    GraphSubjectForm         form = GraphSubjectForm::Path;
    std::vector<std::string> endpoints;   // the resolved spellings, slot order
    std::vector<std::string> spans;       // the words each slot was read from
    std::size_t              tried = 0;   // combinations tried before this one resolved (1 = the first)
    std::vector<std::string> unresolved;  // the spellings the resolver did NOT find on the way (tried > 1 only), first-tried first
    std::vector<std::string> narrowed;    // GV-ASSEMBLY M1: the task spellings refused over several definitions that bound their ONE source definition
};

// The spelling that binds definition `pick` alone: its file:name, else its @file:line seed, each re-resolved to prove it (any other
// match must be a bodyless declaration of it, never a second definition); nullopt when neither does. M1 and M3 name a definition by it.
inline std::optional<std::string> soleDefinitionSpelling( const IngestResult& ing, NodeId pick )
{
    if( pick >= ing.symbols.size() )
    {
        return std::nullopt;
    }
    const Symbol&     s = ing.symbols[ pick ];
    const std::string file( rootRelPath( ing, s.fileId ) );
    const auto alone = [ & ]( const std::string& spell )
    {
        const std::vector<NodeId> got = resolveAllByNameQualified( ing, spell );
        return std::ranges::find( got, pick ) != got.end()
               && std::ranges::all_of( got, [ & ]( NodeId n ) { return n == pick || !isDefinitionNotDeclaration( ing.symbols[ n ] ); } );
    };
    for( std::string spell : { file + ":" + s.name, "@" + file + ":" + std::to_string( s.line ) } )
    {
        if( alone( spell ) )
        {
            return spell;
        }
    }
    return std::nullopt;
}

// GV-ASSEMBLY M1 ESRC (endpoint source-prefer; ORCH reports/s0-xh-1110.md, rule frozen there). A task spelling the resolver REFUSES
// because several definitions fit it (`ApplicationRef.tick` on angular: the source method plus two bodyless mocks under a tests/
// tree) leaves the graph question unasked, though only one of them is code the task can mean. On that refusal only, the fitting
// definitions in a test or fixture path (pathDefInTests, the --defs class="test" rule) and the bodyless ones (no body: the --defs
// decl_only="1" rule) are dropped; when exactly ONE remains, the answer is the spelling that binds it alone: its file:name, else
// its @file:line seed (re-resolved here to prove it). No score and no row feature: the two labels are the parser's. Two or more
// left, none left, or a fitting definition the resolver could not place (an unplaced candidate is never listed) → nullopt: refused
// as before. The block discloses the narrowing (narrowed= on the open tag), so verb= is the one call that ran.
inline std::optional<std::string> sourceOnlyPickSpelling( const IngestResult& ing, std::string_view spec )
{
    std::size_t         fitted = 0;
    std::vector<NodeId> fits;
    (void)resolveAllByWrittenSpelling( ing, spec, {}, &fitted, &fits );
    if( fitted < 2 || fits.size() != fitted )
    {
        return std::nullopt;
    }
    std::vector<NodeId> kept;
    for( const NodeId id : fits )
    {
        if( id < ing.symbols.size() && isDefinitionNotDeclaration( ing.symbols[ id ] ) && !pathDefInTests( ing, id ) && !isDocUnit( ing.symbols[ id ] ) )
        {
            kept.push_back( id );
        }
    }
    if( kept.size() != 1 )
    {
        return std::nullopt;
    }
    return soleDefinitionSpelling( ing, kept.front() );
}

// How a block is opened (FOR-ROUTE fix1): `jsonDialect` = the body is the MCP callers twin's JSON in a CDATA section (S1);
// `held` = a token budget is set, so the verb did NOT run here and the tag is self-closed with the verb= handle only (S2);
// `nameTestHops` = path rows matched by name alone whose p= is a test or fixture path (S5), 0 = attribute absent.
struct GraphSubjectOpen
{
    bool        jsonDialect  = false;
    bool        held         = false;
    std::size_t nameTestHops = 0;
};

// The candidate combinations, in the order they are tried (at most kGraphSubjectAttempts). A two-endpoint form ranks (a,b) by
// index sum, then a's index (parse.py).
inline std::vector<std::vector<std::string>> graphSubjectCombinations( const GraphSubject& gs )
{
    std::vector<std::vector<std::string>> combos;
    if( gs.slots.size() == 1 )
    {
        for( std::size_t a = 0; a < gs.slots[0].size() && combos.size() < kGraphSubjectAttempts; ++a )
        {
            combos.push_back( { gs.slots[0][a] } );
        }
        return combos;
    }
    const std::size_t na = std::min( gs.slots[0].size(), kGraphSubjectSlotCands );
    const std::size_t nb = std::min( gs.slots[1].size(), kGraphSubjectSlotCands );
    for( std::size_t sum = 0; sum + 2 <= na + nb && combos.size() < kGraphSubjectAttempts; ++sum )
    {
        for( std::size_t a = 0; a < na && a <= sum && combos.size() < kGraphSubjectAttempts; ++a )
        {
            if( sum - a < nb )
            {
                combos.push_back( { gs.slots[0][a], gs.slots[1][sum - a] } );
            }
        }
    }
    return combos;
}

// Each task spelling resolved ONCE, however many combinations hold it: the spelling the verb runs with is the task's own when the
// form's resolver finds it, else (M1) the one source definition's own spelling (sourceOnlyPickSpelling); "" = neither.
class GraphSubjectSpellings
{
public:
    struct Resolved
    {
        std::string spelling;   // the task's
        std::string bound;      // what the verb runs with ("" = not resolved)
    };
    GraphSubjectSpellings( const IngestResult& ing, GraphSubjectForm form ) : m_ing( ing ), m_form( form ) {}

    const std::string& boundOf( const std::string& spec )
    {
        for( const Resolved& r : m_memo )
        {
            if( r.spelling == spec ) { return r.bound; }
        }
        m_memo.push_back( { spec, bind( spec ) } );
        return m_memo.back().bound;
    }
    const std::vector<Resolved>& tried() const noexcept { return m_memo; }

private:
    bool resolvesAsIs( const std::string& spec ) const
    {
        std::size_t unproven = 0;
        bool        glob     = false;
        switch( m_form )
        {
            case GraphSubjectForm::Path: return !resolvePathEndpoint( m_ing, spec, &unproven, &glob ).empty();
            case GraphSubjectForm::Callers: return !resolveAllByNameQualified( m_ing, spec, &unproven ).empty();
            case GraphSubjectForm::Common: return resolveFocus( m_ing, spec, &unproven ) != kNoNode;
        }
        return false;
    }
    std::string bind( const std::string& spec ) const
    {
        if( resolvesAsIs( spec ) )
        {
            return spec;
        }
        const std::optional<std::string> pick = sourceOnlyPickSpelling( m_ing, spec );
        return pick && resolvesAsIs( *pick ) ? *pick : std::string();
    }
    const IngestResult&   m_ing;
    GraphSubjectForm      m_form;
    std::vector<Resolved> m_memo;
};

// The first candidate combination whose every endpoint the verb's own resolver finds; nullopt when the task is not
// a graph question or no combination resolves.
inline std::optional<GraphSubjectArgs> chooseGraphSubjectArgs( const IngestResult& ing, std::string_view task )
{
    const std::optional<GraphSubject> gs = parseGraphSubject( task );
    if( !gs )
    {
        return std::nullopt;
    }
    GraphSubjectSpellings                       names( ing, gs->form );
    const std::vector<std::vector<std::string>> combos = graphSubjectCombinations( *gs );
    for( std::size_t k = 0; k < combos.size(); ++k )
    {
        const bool all = std::ranges::all_of( combos[k], [ & ]( const std::string& e ) { return !names.boundOf( e ).empty(); } );
        if( all )
        {
            GraphSubjectArgs a{ gs->form, {}, gs->spans, k + 1, {}, {} };
            for( const std::string& e : combos[k] )
            {
                a.endpoints.push_back( names.boundOf( e ) );
                if( a.endpoints.back() != e ) { a.narrowed.push_back( e ); }
            }
            for( const GraphSubjectSpellings::Resolved& r : names.tried() )
            {
                if( r.bound.empty() ) { a.unresolved.push_back( r.spelling ); }
            }
            return a;
        }
    }
    return std::nullopt;
}

// the verb's flag and its value, as the CLI spells them
inline std::pair<std::string_view, std::string> graphSubjectVerbFlag( const GraphSubjectArgs& a )
{
    std::string v = a.endpoints.empty() ? std::string() : a.endpoints[0];
    for( std::size_t k = 1; k < a.endpoints.size(); ++k )
    {
        v += "," + a.endpoints[k];
    }
    switch( a.form )
    {
        case GraphSubjectForm::Path: return { "--path=", v };
        case GraphSubjectForm::Callers: return { "--callers=", v };
        case GraphSubjectForm::Common: return { "--connect=", v };
    }
    return { "--path=", v };
}

// Path rows (`<s t= n= p="file:line" [via="name"]/>`) matched by NAME ALONE whose p= is a test or fixture path (pathTierOf, the
// classifier the verb's own from_test= uses). A text read of the verb's printed rows, so it only HEDGES: zed-03's chain crosses
// `Markdown::new(` bound by name to a test constructor, an intermediate hop the endpoint-only from_test=/to_test= cannot see.
inline std::size_t graphSubjectNameTestHops( std::string_view doc )
{
    std::size_t n = 0;
    for( std::size_t at = doc.find( "<s " ); at != std::string_view::npos; at = doc.find( "<s ", at + 3 ) )
    {
        const std::size_t end = doc.find( "/>", at );
        if( end == std::string_view::npos ) { break; }
        const std::string_view row = doc.substr( at, end - at );
        const std::size_t      p   = row.find( " p=\"" );
        if( p == std::string_view::npos || row.find( " via=\"name\"" ) == std::string_view::npos ) { continue; }
        std::string_view path = row.substr( p + 4 );
        path                  = path.substr( 0, path.find( '"' ) );
        path                  = path.substr( 0, path.rfind( ':' ) );
        n += pathTierOf( path ) == PathTier::TestOrBench ? 1 : 0;
    }
    return n;
}

// ` from_span="…" to_span="…"` | ` of_span="…" [and_span="…"]`
inline std::string graphSubjectSpanAttrs( const GraphSubjectArgs& a )
{
    static constexpr std::string_view kPathSpans[]   = { "from_span", "to_span" };
    static constexpr std::string_view kCommonSpans[] = { "of_span", "and_span" };
    std::string       out;
    std::vector<char> esc;
    for( std::size_t k = 0; k < a.spans.size() && k < 2; ++k )
    {
        const std::string_view name = a.form == GraphSubjectForm::Path ? kPathSpans[k] : a.form == GraphSubjectForm::Common ? kCommonSpans[k] : "of_span";
        out += " " + std::string( name ) + "=\"" + std::string( escapeXml( a.spans[k], esc ) ) + "\"";
    }
    return out;
}

// ` tried="N" unresolved="a b"` — only when an earlier combination did not resolve
inline std::string graphSubjectTriedAttrs( const GraphSubjectArgs& a )
{
    if( a.tried <= 1 )
    {
        return {};
    }
    std::string       out = " tried=\"" + std::to_string( a.tried ) + "\"";
    std::string       names;
    std::vector<char> esc;
    for( const std::string& u : a.unresolved ) { names += ( names.empty() ? "" : " " ) + u; }
    return out + ( names.empty() ? "" : " unresolved=\"" + std::string( escapeXml( names, esc ) ) + "\"" );
}

// The opening of the block: its own legend (present only with the block; no `--` inside the comment), then
// <graph_verb endpoints="subject" verb=… from_span=/to_span= | of_span= [| and_span=] [tried= unresolved=] [dialect=] [held=] [name_test_hops=]>.
// tried=/unresolved= are present only when an earlier combination did not resolve; every other clause only with its attribute.
inline std::string graphSubjectOpenXml( const GraphSubjectArgs& a, const GraphSubjectOpen& o = {} )
{
    std::string out = "<!-- ripwire for graph_verb: the task is spelled as a graph question, so the verb it names ran too, on the built "
                      "index with its default caps; endpoints=\"subject\": its endpoints were READ FROM THE TASK WORDS (the *_span= "
                      "attributes, cut at the first for/with/via/in/on/when/using/during/at/near, sentence end, comma or clause word "
                      "such as and/then/how/which), matched by name, not chosen "
                      "from the graph: check they are the symbols meant; verb= is the same call to paste";
    out += a.tried > 1 ? "; tried= combinations of the words were tried, the first that resolves ran; unresolved= names the spellings that did not resolve" : "";
    out += o.jsonDialect ? "; dialect=\"json\": this surface answers the verb as JSON, carried as CDATA text, not as XML rows" : "";
    out += o.nameTestHops > 0 ? "; name_test_hops=N: N path hops were matched by name alone to a definition in a test or fixture path, so they may not be the call the source makes" : "";
    out += a.narrowed.empty() ? "" : "; narrowed= names the task spellings several definitions fit (refused as written): the ones in a test or fixture path "
                                     "and the bodyless ones were dropped, and verb= names the ONE source definition left by its own spelling";
    out += o.held ? "; held=\"budget\": a token budget is set, so the verb did NOT run here: verb= is the one call to run; the answer above is unchanged --><graph_verb endpoints=\"subject\""
                  : "; the verb's own legend follows; the answer above is unchanged, and these bytes are not in est_tokens --><graph_verb endpoints=\"subject\"";
    const auto [ flag, value ] = graphSubjectVerbFlag( a );
    out += nextAttrXml( nextFlag( flag, value ), "verb" );
    out += graphSubjectSpanAttrs( a ) + graphSubjectTriedAttrs( a );
    out += o.jsonDialect ? " dialect=\"json\"" : "";
    out += o.held ? " held=\"budget\"" : "";
    out += o.nameTestHops > 0 ? " name_test_hops=\"" + std::to_string( o.nameTestHops ) + "\"" : "";
    if( !a.narrowed.empty() )
    {
        std::string       names;
        std::vector<char> esc;
        for( const std::string& n : a.narrowed ) { names += ( names.empty() ? "" : " " ) + n; }
        out += " narrowed=\"" + std::string( escapeXml( names, esc ) ) + "\"";
    }
    out += o.held ? "/>" : ">";
    return out;
}

// PATH-FROM-UPSTREAM (PY-MOD-CALL-SITES fix 1): in a task that asks `path from A to B` (parseGraphSubjectPathFrom: a path question,
// not one that also asks for callers), a caller of A is UPSTREAM of the asked path — the question starts at A. Such a row may still
// rank, but never ahead of the path's own rows: every ranked caller of A (a resolved call edge, not a by-name one) that A does not itself
// reach is scored below every other positive score, its own order kept. "Reach" is A's whole forward closure over resolved edges, up
// to kPathFromReachMaxNodes: any row on a path out of A is in it, so a chain row that calls back to A (recursion, an eval loop, a
// tree walker) at any depth stays (rv-py-mod2 MF6). B itself never moves, wherever it sits (it is asked for even when no resolved edge
// joins it to A). So a new call edge INTO A (a module-level `management.execute_from_command_line()` bound for the first time) cannot
// push a hop under A past the ranked head's cap. A is read as the FROM slot's first candidate the qualified resolver finds, B likewise
// (B need not name a symbol); no parse, no candidate, or no caller ranked → nothing moves (byte-identical). Returns how many rows moved,
// or kPathFromReachCapped when A's reach passed kPathFromReachMaxNodes (nothing moved, path_from_capped=1 in the note); the caller
// discloses either.
inline constexpr std::size_t kPathFromReachMaxNodes = 4096;   // runaway guard on A's forward walk; past it every caller of A stays where it ranked
inline constexpr std::uint32_t kPathFromReachCapped = UINT32_MAX;   // applyPathFromUpstreamCut's answer when that guard stopped the walk
inline std::uint32_t applyPathFromUpstreamCut( const IngestResult& ing, const Graph& g, std::string_view task, std::vector<float>& lensRank )
{
    std::vector<std::string>       toCands;
    const std::vector<std::string> fromCands = parseGraphSubjectPathFrom( task, &toCands );
    const std::size_t              n         = ing.symbols.size();
    if( fromCands.empty() || lensRank.size() != n || g.outOff.size() != n + 1 )
    {
        return 0;
    }
    std::vector<NodeId> from;
    for( const std::string& cand : fromCands )
    {
        from = resolveAllByNameQualified( ing, cand );
        if( !from.empty() )
        {
            break;
        }
    }
    if( from.empty() )
    {
        return 0;
    }
    std::ranges::sort( from );   // binary_search below
    std::vector<NodeId> to;
    for( const std::string& cand : toCands )
    {
        to = resolveAllByNameQualified( ing, cand );
        if( !to.empty() )
        {
            break;
        }
    }
    const auto proven = [ & ]( std::size_t e ) { return g.outNameOnly.empty() || g.outNameOnly[ e ] == 0; };
    // A's forward reach (A included): a caller of A inside it is on a cycle through A, so on the path; B is marked as if reached
    std::vector<char>   reach( n, 0 );
    std::vector<NodeId> frontier = from;
    std::size_t         seen     = 0;
    for( NodeId f : from )
    {
        reach[ f ] = 1;
        ++seen;
    }
    while( !frontier.empty() )
    {
        const NodeId u = frontier.back();
        frontier.pop_back();
        for( std::size_t e = g.outOff[ u ]; e < g.outOff[ u + 1 ]; ++e )
        {
            const NodeId v = g.outTargets[ e ];
            if( v < n && reach[ v ] == 0 && proven( e ) )
            {
                if( ++seen > kPathFromReachMaxNodes )
                {
                    return kPathFromReachCapped;   // too wide to tell on-path from upstream: nothing moves, and the note says so
                }
                reach[ v ] = 1;
                frontier.push_back( v );
            }
        }
    }
    for( NodeId b : to )
    {
        if( b < n )
        {
            reach[ b ] = 1;   // B is asked for: never moved, even when no resolved edge joins it to A
        }
    }
    std::vector<NodeId> upstream;
    float               floorScore = 0.0f;   // the lowest positive score of every row that stays
    for( NodeId u = 0; u < n; ++u )
    {
        if( !( lensRank[ u ] > 0.0f ) )
        {
            continue;
        }
        bool callsFrom = false;
        if( reach[ u ] == 0 )
        {
            for( std::size_t e = g.outOff[ u ]; e < g.outOff[ u + 1 ] && !callsFrom; ++e )
            {
                callsFrom = proven( e ) && std::ranges::binary_search( from, g.outTargets[ e ] );
            }
        }
        if( callsFrom )
        {
            upstream.push_back( u );
        }
        else if( floorScore == 0.0f || lensRank[ u ] < floorScore )
        {
            floorScore = lensRank[ u ];
        }
    }
    if( upstream.empty() || floorScore == 0.0f )
    {
        return 0;
    }
    float top = 0.0f;
    for( NodeId u : upstream )
    {
        top = std::max( top, lensRank[ u ] );
    }
    // scaled into (0, floorScore / 2]: below every staying row, their own order kept
    for( NodeId u : upstream )
    {
        lensRank[ u ] = floorScore * 0.5f * ( lensRank[ u ] / top );
    }
    return std::uint32_t( upstream.size() );
}

// the header note applyPathFromUpstreamCut's count rides in (the CLI --for and the MCP `for` twin print the same words)
inline std::string pathFromUpstreamNote( std::uint32_t moved )
{
    if( moved == kPathFromReachCapped )
    {
        return std::format( " [path from: the from endpoint reaches over {} symbols, path_from_capped=1: its callers were not moved]", kPathFromReachMaxNodes );
    }
    return std::format( " [path from: {} caller{} of the from endpoint scored below the path's own rows]", moved, moved == 1 ? "" : "s" );
}

inline constexpr std::string_view kGraphSubjectCloseXml = "</graph_verb>";

// GRAPH-FORM-ENDPOINTS: did the path verb's printed answer find NO directed path? Read off its open tag (`<path … reachable="0"`), the
// one attribute every no-path answer carries in every legend (the legend comment before it is skipped); a doc with no <path> tag (a
// refusal) is not a gap.
inline bool graphSubjectPathReachableIs( std::string_view doc, std::string_view quoted )
{
    const SectionOpenTag tag = findSectionOpenTag( doc, "<path " );
    return tag.start != std::string::npos && spanHasAttr( doc.substr( tag.start, tag.end - tag.start ), "reachable", quoted );
}
inline bool graphSubjectPathUnreachable( std::string_view doc )
{
    return graphSubjectPathReachableIs( doc, "\"0\"" );
}

// The rows each side of a <path_gap> shows: the plain --callees / --callers answer at --limit=10, its count= the total and its next= the
// page after. Set from the 7 in-sample fires (reports/graph-form-endpoints.md FIN): the two rows that gained an item held 7 and 3 callees,
// the five that did not held 3 to 51 callees and 5 to 43 callers, so the uncapped sides (up to 40 rows, a 16 KB callers band) were mostly filler.
inline constexpr int kPathGapSideRows = 10;   // rows per side of a <path_gap>; the rest is count= and next=

// <path_gap from= to= reachable="0" [missing=]>: reachable="0" restates on the block itself that no path from= to to= was printed (none was
// found, or a route_hedged="not-proven" refusal withheld the one found; why the rows follow); then its own legend, from='s --callees and to='s --callers answers. missing=from|to|from,to names a side whose answer could
// not be captured (not printed, never "none").
inline std::string pathGapOpenXml( const GraphSubjectArgs& a, bool fromMissing, bool toMissing )
{
    std::vector<char> esc;
    std::string out = "<!-- ripwire for path_gap: the path verb above printed NO directed call path (reachable=\"0\": none was found, or route_hedged=\"not-proven\" "
                      "refused the one it found; its searched= and gaps= say whether that search was complete), so the two sides a missing hop would "
                      "join follow (reachable=\"0\" on path_gap restates it): "
                      "from='s callees (what it calls, one hop) and to='s callers (who calls it, one hop), each the bare callees / callers verb "
                      "answer cut at ";
    out += std::to_string( kPathGapSideRows );
    out += " rows (its count= is the total, its next= the page after) with its own legend. A name in both lists, or a callee of from= that "
           "calls a caller of to=, is a CANDIDATE link to read, not a proven path";
    out += fromMissing || toMissing ? "; missing= names a side whose answer could not be captured: it is not shown, which is not the same as empty" : "";
    out += " --><path_gap from=\"" + std::string( escapeXml( a.endpoints[0], esc ) ) + "\"";
    out += " to=\"" + std::string( escapeXml( a.endpoints[1], esc ) ) + "\" reachable=\"0\"";
    if( fromMissing || toMissing )
    {
        out += std::string( " missing=\"" ) + ( fromMissing ? "from" : "" ) + ( fromMissing && toMissing ? "," : "" ) + ( toMissing ? "to" : "" ) + "\"";
    }
    return out + ">";
}
inline constexpr std::string_view kPathGapCloseXml = "</path_gap>";

// GV-ASSEMBLY M3 MET-BRIDGE (ORCH reports/s0-xh-1110.md, rule frozen there). A reachable="0" path answer whose <near_sink> row for a
// to= definition (d="0") carries met="1" says the forward search REACHED in=, whose call at site= could have meant to= and was not
// followed: envoy's ConnectionImpl::onFileEvent reaches FilterManagerImpl::onContinueReading in 4 proven hops, and its virtual
// `filter->onData( … )` is the hop the graph holds no edge for. The answer printed only the gap rows, never that proven prefix.
// The plan below names the bridge, every fact checked BY ID in the index, never by a printed name: from= binds ONE definition (a
// 79-definition `main` reaches in= from whichever `main` it was, so a bridge from it names a start the task may not mean: envoy-03);
// the row's p= is a definition to= resolves to; the site is a DECLINED call record (the graph's own: several in-tree candidates,
// none chosen, not a builtin-spelled one) made by a definition named in=, and that record's candidate list holds that very to=
// definition. The caller then prints the path verb's own answer from= -> in= (proven, reachable="1", or nothing) and that one call
// as a hedged crossing row. Anything else, a name-key site included → nullopt: nothing printed, byte-identical.
struct MetBridgePlan
{
    NodeId        in    = kNoNode;   // the reached caller (the declined record's caller)
    NodeId        to    = kNoNode;   // the to= definition its candidate list holds
    std::string   inSel;             // the spelling that binds `in` alone (the path verb's to= for the proven prefix)
    std::string   toP;               // the row's p= and site= as the path verb printed them (attribute bytes, already escaped)
    std::string   site;
    std::uint32_t cands = 0;         // the declined call's candidate count
};

namespace metbridge_detail
{
// the value of attribute `name` in one printed row (its escaped bytes; "" when absent)
inline std::string_view attrOf( std::string_view row, std::string_view name )
{
    const std::string key = " " + std::string( name ) + "=\"";
    const std::size_t at  = row.find( key );
    if( at == std::string_view::npos )
    {
        return {};
    }
    const std::string_view v = row.substr( at + key.size() );
    return v.substr( 0, v.find( '"' ) );
}
// a printed `file:line` names file `fileId` at `line`: the path is the root-relative one, or the tail of the stored one
inline bool namesPlace( const IngestResult& ing, std::string_view printed, std::uint32_t fileId, std::uint32_t line )
{
    const std::size_t colon = printed.rfind( ':' );
    if( colon == std::string_view::npos || printed.substr( colon + 1 ) != std::to_string( line ) )
    {
        return false;
    }
    const std::string_view path = printed.substr( 0, colon );
    const std::string_view full = ing.files[ fileId ];
    return !path.empty() && ( rootRelPath( ing, fileId ) == path || ( full.size() > path.size() && full.ends_with( path ) && full[ full.size() - path.size() - 1 ] == '/' ) );
}
}   // namespace metbridge_detail

namespace metbridge_detail
{
// the first <near_sink> row for a to= definition (d="0") the forward search met (met="1"; the served order puts met first) that names
// a reached in=; a name-key site (via=) has no declined record, so it is not one. "" when none.
inline std::string_view metRowOf( std::string_view doc )
{
    const std::size_t nsAt  = doc.find( "<near_sink " );
    const std::size_t nsEnd = nsAt == std::string_view::npos ? nsAt : doc.find( "</near_sink>", nsAt );
    if( nsEnd == std::string_view::npos )
    {
        return {};
    }
    const std::string_view block = doc.substr( nsAt, nsEnd - nsAt );
    for( std::size_t at = block.find( "<ns " ); at != std::string_view::npos; at = block.find( "<ns ", at + 4 ) )
    {
        const std::size_t      end = block.find( "/>", at );
        const std::string_view r   = block.substr( at, end == std::string_view::npos ? std::string_view::npos : end - at );
        if( attrOf( r, "d" ) == "0" && attrOf( r, "met" ) == "1" && attrOf( r, "via" ).empty() && !attrOf( r, "in" ).empty() )
        {
            return r;
        }
    }
    return {};
}
// the declined call record at the printed site= made by a definition named `inName` (escaped bytes) whose candidate list holds `to`
// and that is not builtin-spelled: sets plan.in and plan.cands, or leaves plan.in kNoNode
inline void bindDeclinedSite( const IngestResult& ing, const Graph& g, std::string_view inName, MetBridgePlan& plan )
{
    const DeclinedCrossRule rule( ing, g );
    std::vector<char>       esc;
    for( std::uint32_t k = 0; k < g.declinedSiteList.size() && plan.in == kNoNode; ++k )
    {
        const std::uint32_t list = g.declinedSiteList[k];
        const Reference&    ref  = ing.references[ g.declinedSiteRef[k] ];
        const NodeId        by   = g.declinedSiteCaller[k];
        if( list == kNoDeclinedList || list + 1 >= g.declinedListOff.size() || by >= ing.symbols.size() || by == plan.to
            || !namesPlace( ing, plan.site, ref.fileId, ref.line ) || escapeXml( ing.symbols[ by ].name, esc ) != inName )
        {
            continue;
        }
        const auto first = g.declinedListCand.begin() + std::ptrdiff_t( g.declinedListOff[ list ] );
        const auto last  = g.declinedListCand.begin() + std::ptrdiff_t( g.declinedListOff[ list + 1 ] );
        if( std::find( first, last, plan.to ) != last && !rule.builtinSpelled( k ) )
        {
            plan.in    = by;
            plan.cands = std::uint32_t( last - first );
        }
    }
}
}   // namespace metbridge_detail

inline std::optional<MetBridgePlan> metBridgePlan( const IngestResult& ing, const Graph& g, const GraphSubjectArgs& a, std::string_view doc )
{
    using metbridge_detail::attrOf;
    if( a.form != GraphSubjectForm::Path || a.endpoints.size() != 2 || !graphSubjectPathUnreachable( doc ) )
    {
        return std::nullopt;
    }
    const std::string_view row = metbridge_detail::metRowOf( doc );
    if( row.empty() )
    {
        return std::nullopt;
    }
    std::size_t unproven = 0;
    bool        glob     = false;
    const std::vector<NodeId> src = resolvePathEndpoint( ing, a.endpoints[0], &unproven, &glob );
    const std::vector<NodeId> dst = resolvePathEndpoint( ing, a.endpoints[1], &unproven, &glob );
    if( glob || endpointDefinitionCount( ing, src ) != 1 )
    {
        return std::nullopt;   // from= names several definitions: a reached in= says nothing about the one the task means
    }
    MetBridgePlan plan;
    plan.toP  = std::string( attrOf( row, "p" ) );
    plan.site = std::string( attrOf( row, "site" ) );
    const auto at = std::ranges::find_if( dst, [ & ]( NodeId t ) { return metbridge_detail::namesPlace( ing, plan.toP, ing.symbols[ t ].fileId, ing.symbols[ t ].line ); } );
    plan.to = at != dst.end() ? *at : kNoNode;
    if( plan.to != kNoNode )
    {
        metbridge_detail::bindDeclinedSite( ing, g, attrOf( row, "in" ), plan );
    }
    std::optional<std::string> sel = plan.in != kNoNode ? soleDefinitionSpelling( ing, plan.in ) : std::nullopt;
    if( !sel )
    {
        return std::nullopt;
    }
    plan.inSel = std::move( *sel );
    return plan;
}

// The proven prefix is the path verb's own answer; it counts only when that answer found its path (reachable="1").
inline bool graphSubjectPathReached( std::string_view doc )
{
    return graphSubjectPathReachableIs( doc, "\"1\"" );
}

// A bridge whose prefix answer could not be captured is still the crossing the index proves, printed with missing="prefix"
// (never shown as an empty prefix) and said on stderr.
struct MetBridgeShown
{
    enum class DisclosureWhy : std::uint8_t
    {
        PrefixUncaptured,   // no capture buffer for the from= -> in= path answer: it is not shown, which is not the same as empty
    };
    bool prefixMissing = false;
    void disclose( DisclosureWhy ) noexcept
    {
        prefixMissing = true;
        rw::emitTo( stderr, "ripwire: --for: no capture buffer for the met_bridge proven prefix — it is not shown (missing=\"prefix\"), which is not empty\n" );
    }
};

inline std::string metBridgeOpenXml( const IngestResult& ing, const MetBridgePlan& p, bool prefixMissing = false )
{
    std::vector<char> esc;
    std::string out = "<!-- ripwire for met_bridge: the path verb above printed NO directed path, but its forward search REACHED in= (its near_sink "
                      "met=\"1\" row), whose call at site= is a declined call (several in-tree candidates, none chosen; cands= counts them) whose "
                      "candidate list holds to='s definition, all checked by id in the index, from= binding one definition. So the proven path "
                      "from= to in= follows (the path verb's own answer, with its own legend), then that one call as a crossing row <s via=\"declined\" "
                      "t= n= p= site= in= cands=>. A BRIDGE, not a path: the crossing is a hedge, not a proven call; reachable=\"0\" stands and no "
                      "count includes it";
    out += prefixMissing ? "; missing=\"prefix\": the proven path answer could not be captured, so it is not shown, which is not the same as empty" : "";
    out += " --><met_bridge reachable=\"0\" in=\"";
    out += std::string( escapeXml( ing.symbols[ p.in ].name, esc ) ) + "\" site=\"";
    out += p.site + "\" via=\"declined\" cands=\"" + std::to_string( p.cands ) + "\"" + ( prefixMissing ? " missing=\"prefix\">" : ">" );
    return out;
}
// the crossing: in='s declined call at site= into the to= definition
inline std::string metBridgeCrossingXml( const IngestResult& ing, const MetBridgePlan& p )
{
    std::vector<char> esc;
    const Symbol&     t = ing.symbols[ p.to ];
    std::string out = "<s via=\"declined\" t=\"" + std::string( symTag( t.kind ) ) + "\" n=\"" + std::string( escapeXml( t.name, esc ) ) + "\" p=\"";
    out += p.toP + "\" site=\"" + p.site + "\" in=\"";
    out += std::string( escapeXml( ing.symbols[ p.in ].name, esc ) ) + "\" cands=\"" + std::to_string( p.cands ) + "\"/>";
    return out;
}
inline constexpr std::string_view kMetBridgeCloseXml = "</met_bridge>";
}   // namespace rw
