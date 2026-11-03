#pragma once
// declinedsites.h — the <dc> rows: the call SITES the resolver declined to bind, named. One row builder and its three
// spellings (XML, the CLI's --json, the MCP twins' JSON), shared by --callers/--callees (callhierarchy.h selects the
// records once for both surfaces) and --safe-delete.
//
// THE GAP IT CLOSES. A declined call (tier 3, the builtin-method and standard-member name gates, Ruby's side cut and
// `new`) gets no edge, and declined_calls= counted it without naming it: "what does doPackage call" missed
// `pkg.Package( info, f )` through an interface value, "who calls TaskManager#define_task" missed every test that calls
// it on an untyped receiver. buildGraph now keeps one record per declined call (graph.h Graph::declinedSite*), and these
// rows read it back.
//
// WHAT A ROW IS, AND IS NOT. The call site — its enclosing definition, file:line and the CALLED name — is a fact. Its
// link to any definition is not: cands=K counts the in-tree definitions the call could have meant (K may be 1), the
// resolver proved none, and the call may reach none of them (an out-of-tree, builtin or standard-library method). So a
// row is its own element, never an <s> row, never inside count=, hop_tested=/hop_untested=, the rank or any reach;
// via="declined" rides every row so a row read without its legend (a graded packet, a columnar or MCP answer) still
// says so. Candidates are named (cand=) only on --legend=full.
//
// WHICH ROWS. Callees form: the records the selector's definitions MADE (graph.h declinedSitesMadeBy). Callers and
// safe-delete form: the records whose stored candidate LIST holds one of the selector's definitions (declinedSitesNaming)
// — membership, never the called name: the language and root filters split one name into several lists, and a Ruby
// `new` declines with `initialize` candidates. Either way the rows are exactly the calls the answer's declined_calls=
// counts, so uncut, the row count equals it.
//
// CAPPED AND COUNTED. kDeclinedSiteCap rows by default (a raisable default: --limit=N lifts it, as every primary row cap
// does); past it the root says dc_shown= (rows printed) and dc_next= (the same question with --limit raised to list every
// site). The callers form is cut FILE-FIRST — each calling file's first site, in path order, before any file's second —
// so a cut still names every file it can; the callees form reads in file then line order, as the body does.

#include "cli.h"         // kPageValueMax — dc_next='s --limit saturates at the flag's own ceiling
#include "defattrib.h"   // DefGroups — of_def on a multi-definition answer
#include "filter.h"      // pathTierIndexOver / compareTierThenPath — the served order's tier-then-path file key
#include "graph.h"       // Graph::declinedSite*, DeclinedSiteKind, kNoDeclinedList
#include "model.h"
#include "nextverb.h"    // nextFlag — dc_next= pastes as one argv element
#include "valuerefs.h"   // VrRender / vrPath — the rows' path spelling; escapeXml / jsonStr through serialize.h

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <numeric>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

inline constexpr std::size_t kDeclinedSiteCap     = 16;   // <dc> rows per answer by default; --limit=N raises it (dc_next= does)
inline constexpr std::size_t kDeclinedSiteCandCap = 8;    // cand= entries per row on --legend=full; cand_more= counts the rest

// gate= on a row: which name gate (or Ruby's side cut) declined the call — "iface" (lane L6) the receiver's interface type, its
// candidates that type's implementors' methods; nothing for the ladder's own tier-3 decline and for Ruby's `new` (its
// candidates are `initialize`, the row's n= is the called `new`).
// Indexed by DeclinedSiteKind, in its declaration order (Ladder, Builtin, Std, RubySide, RubyNew, Iface).
inline constexpr const char* kDeclinedSiteGateNames[] = { nullptr, "builtin", "std", "side", nullptr, "iface" };
static_assert( std::size( kDeclinedSiteGateNames ) == std::size_t( DeclinedSiteKind::Iface ) + 1, "one gate= spelling per DeclinedSiteKind" );
inline const char* declinedSiteGate( DeclinedSiteKind kind ) noexcept
{
    const auto k = std::size_t( kind );
    return k < std::size( kDeclinedSiteGateNames ) ? kDeclinedSiteGateNames[ k ] : nullptr;
}

// The served order, in place. Every form first sorts by the call's file — its path TIER first (filter.h pathTierOf: source,
// then test/bench, then docs — the key the callers and uses rows already sort by), then path — then line, then record
// (resolve order: two calls on one line keep their source order). Lane ix2-slice (IX-4): the plain path order put hono's
// `src/helper/css/index.test.tsx` among the source sites of `--callers=src/router.ts:match`; a test site now follows them.
// The callers form is then interleaved FILE-FIRST: a stable sort on each site's rank within its file, so rank 0 of every
// file (in tier-then-path order) precedes rank 1 of any.
inline void orderDeclinedSites( const IngestResult& ing, const Graph& g, std::vector<std::uint32_t>& sites, bool fileFirst )
{
    const auto refOf = [ & ]( std::uint32_t site ) -> const Reference& { return ing.references[ g.declinedSiteRef[ site ] ]; };
    for( const std::uint32_t site : sites )
    {
        EXPECTS( site < g.declinedSiteRef.size() && g.declinedSiteRef[ site ] < ing.references.size(),
                 "the records and the references come from the same build (an edit preview rebuilds both)" );
    }
    const std::vector<std::uint8_t> tierOfFile = pathTierIndexOver( ing, sites, [ & ]( std::uint32_t site ) { return refOf( site ).fileId; } );
    std::sort( sites.begin(), sites.end(), [ & ]( std::uint32_t a, std::uint32_t b )
    {
        const Reference& ra = refOf( a );
        const Reference& rb = refOf( b );
        if( const int c = compareTierThenPath( ing, tierOfFile, ra.fileId, rb.fileId ); c != 0 )
        {
            return c < 0;
        }
        return ra.line != rb.line ? ra.line < rb.line : a < b;
    } );
    if( !fileFirst || sites.size() < 2 )
    {
        return;
    }
    std::vector<std::uint32_t> rankInFile( sites.size(), 0 );
    for( std::size_t i = 1; i < sites.size(); ++i )
    {
        rankInFile[i] = refOf( sites[i] ).fileId == refOf( sites[i - 1] ).fileId ? rankInFile[i - 1] + 1 : 0;
    }
    std::vector<std::uint32_t> order( sites.size() );
    std::iota( order.begin(), order.end(), 0u );
    std::stable_sort( order.begin(), order.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return rankInFile[a] < rankInFile[b]; } );
    std::vector<std::uint32_t> interleaved;
    interleaved.reserve( sites.size() );
    for( const std::uint32_t i : order )
    {
        interleaved.push_back( sites[i] );
    }
    sites.swap( interleaved );
}

// One 1-hop answer's declined_calls= and the records behind it, in served order: callers (declinedCallsNaming) the declined
// calls whose lists hold a match, file-first; callees (declinedCallsMadeBy) the declines the matches made, file and line.
inline std::pair<std::size_t, std::vector<std::uint32_t>> declinedCallsAndSites( const IngestResult& ing, const Graph& g, std::span<const NodeId> matches,
                                                                                bool wantCallers )
{
    const std::size_t          calls = wantCallers ? declinedCallsNaming( g, matches ) : declinedCallsMadeBy( g, matches );
    std::vector<std::uint32_t> sites = wantCallers ? declinedSitesNaming( g, matches ) : declinedSitesMadeBy( g, matches );
    orderDeclinedSites( ing, g, sites, /*fileFirst=*/wantCallers );
    // callees: an inert quoted site (#380) is counted with no record (graph.h inertDeclinedCaller), so it has no row
    ENSURES( sites.size() + ( wantCallers ? 0u : inertDeclinedMadeBy( g, matches ) ) == calls,
             "a <dc> row per declined call the answer counts, but an inert quoted site" );
    return { calls, std::move( sites ) };
}

// lane L6: the generic bound record `site` was typed through (Graph::declinedSiteBound, record order), "" when none
inline std::string_view declinedSiteBoundOf( const Graph& g, std::uint32_t site )
{
    const auto it = std::lower_bound( g.declinedSiteBound.begin(), g.declinedSiteBound.end(), site,
                                      []( const std::pair<std::uint32_t, std::string>& b, std::uint32_t k ) { return b.first < k; } );
    return it != g.declinedSiteBound.end() && it->first == site ? std::string_view( it->second ) : std::string_view();
}

// One row's facts, surface-neutral: every dialect below spells these and nothing else.
struct DeclinedSiteView
{
    std::string_view         name;        // the CALLED name (the reference's own; never a candidate's)
    std::uint32_t            line = 0;    // the call's line
    std::string              file;        // the call's file (root-relative on one root)
    std::string_view         caller;      // the enclosing definition's name
    std::size_t              cands = 0;   // the candidate list's size
    bool                     candsKnown = false;   // false only for a list internDeclinedList could not store
    const char*              gate = nullptr;
    std::string_view         bound;       // lane L6: a gate="iface" row typed through a generic bound (`R: Renderer`), "" otherwise
    std::vector<std::string> ofDef;       // callees: {"K"}, the definition making the call; callers: {"K~d", ...}
    std::vector<std::string> cand;        // --legend=full: the candidates as file:line, at most kDeclinedSiteCandCap
    std::size_t              candMore = 0;
};

// The rows of one answer: `shown` (served order, already cut) as views. `matches`/`groups` give the multi-definition
// labels (of_def; none on a one-group answer, nor on a definition table cut past its cap, whose numbers would name groups
// the table does not list).
inline std::vector<DeclinedSiteView> declinedSiteViews( const IngestResult& ing, const Graph& g, std::span<const std::uint32_t> shown, bool callersForm,
                                                        std::span<const NodeId> matches, const DefGroups& groups, const VrRender& vr, bool candidates )
{
    std::vector<DeclinedSiteView> out;
    out.reserve( shown.size() );
    // match → its group, sorted by node once per answer (a row looks its caller or candidates up by binary search)
    std::vector<std::pair<NodeId, std::uint32_t>> groupOf;
    const bool labelled = groups.multi() && !defTableCapped( groups ) && groups.ofMatch.size() == matches.size();
    if( labelled )
    {
        for( std::size_t i = 0; i < matches.size(); ++i )
        {
            if( groups.ofMatch[i] < groups.size() )
            {
                groupOf.emplace_back( matches[i], groups.ofMatch[i] );
            }
        }
        std::sort( groupOf.begin(), groupOf.end() );
    }
    const auto groupOfNode = [ & ]( NodeId n ) -> std::uint32_t
    {
        const auto it = std::lower_bound( groupOf.begin(), groupOf.end(), std::pair<NodeId, std::uint32_t>( n, 0u ) );
        return it != groupOf.end() && it->first == n ? it->second : UINT32_MAX;
    };
    std::vector<char> groupHit( groups.size(), 0 );
    for( const std::uint32_t site : shown )
    {
        const Reference& r = ing.references[ g.declinedSiteRef[ site ] ];
        DeclinedSiteView v;
        v.name   = r.calleeName;
        v.line   = r.line;
        v.file   = vrPath( ing, r.fileId, vr );
        v.caller = ing.symbols[ g.declinedSiteCaller[ site ] ].name;
        v.gate   = declinedSiteGate( g.declinedSiteKind[ site ] );
        v.bound  = declinedSiteBoundOf( g, site );
        const std::uint32_t list = g.declinedSiteList[ site ];
        std::span<const NodeId> cand;
        if( list != kNoDeclinedList )
        {
            EXPECTS( list + 1 < g.declinedListOff.size(), "a stored list has its closing offset" );
            cand = std::span<const NodeId>( g.declinedListCand.data() + g.declinedListOff[ list ], g.declinedListOff[ list + 1 ] - g.declinedListOff[ list ] );
            v.cands      = cand.size();
            v.candsKnown = true;
        }
        if( labelled && !callersForm )
        {
            if( const std::uint32_t grp = groupOfNode( g.declinedSiteCaller[ site ] ); grp != UINT32_MAX )
            {
                v.ofDef.push_back( std::to_string( grp + 1 ) );
            }
        }
        else if( labelled )
        {
            std::fill( groupHit.begin(), groupHit.end(), 0 );
            for( const NodeId c : cand )
            {
                if( const std::uint32_t grp = groupOfNode( c ); grp != UINT32_MAX )
                {
                    groupHit[ grp ] = 1;
                }
            }
            for( std::size_t k = 0; k < groupHit.size(); ++k )
            {
                if( groupHit[k] )
                {
                    v.ofDef.push_back( std::to_string( k + 1 ) + "~d" );   // hedged: its candidates include group K, never "it calls K"
                }
            }
        }
        if( candidates )
        {
            for( const NodeId c : cand )
            {
                if( v.cand.size() == kDeclinedSiteCandCap )
                {
                    ++v.candMore;
                    continue;
                }
                const Symbol& cs = ing.symbols[c];
                v.cand.push_back( vrPath( ing, cs.fileId, vr ) + ":" + std::to_string( cs.line ) );
            }
        }
        out.push_back( std::move( v ) );
    }
    return out;
}

// XML: <dc n= l= …/> (callees) or <dc in= p= …/> (callers, safe-delete), in the views' order; "" when there is none.
inline std::string declinedSitesXml( std::span<const DeclinedSiteView> views, bool callersForm )
{
    std::string       out;
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };
    for( const DeclinedSiteView& v : views )
    {
        out += callersForm ? "<dc in=\"" + ex( v.caller ) + "\" p=\"" + ex( v.file ) + ":" + std::to_string( v.line ) + "\""
                           : "<dc n=\"" + ex( v.name ) + "\" l=\"" + std::to_string( v.line ) + "\"";
        if( v.candsKnown )
        {
            out += " cands=\"" + std::to_string( v.cands ) + "\"";
        }
        out += " via=\"declined\"";
        if( v.gate != nullptr )
        {
            out += std::string( " gate=\"" ) + v.gate + "\"";
        }
        if( !v.bound.empty() )
        {
            out += " bound=\"" + ex( v.bound ) + "\"";
        }
        for( std::size_t i = 0; i < v.ofDef.size(); ++i )
        {
            out += ( i == 0 ? " of_def=\"" : " " ) + v.ofDef[i] + ( i + 1 == v.ofDef.size() ? "\"" : "" );
        }
        for( std::size_t i = 0; i < v.cand.size(); ++i )
        {
            out += ( i == 0 ? " cand=\"" : " " ) + ex( v.cand[i] ) + ( i + 1 == v.cand.size() ? "\"" : "" );
        }
        if( v.candMore > 0 )
        {
            out += " cand_more=\"" + std::to_string( v.candMore ) + "\"";
        }
        out += "/>";
    }
    return out;
}

// JSON, one array: the CLI --json `"dc"` (the XML attribute names as keys) or the MCP twins' `"declined_sites"`
// (name/line or in/file/line, candidates). "" when there is none, so an answer without a decline keeps its bytes.
inline std::string declinedSitesJson( std::span<const DeclinedSiteView> views, bool callersForm, bool mcp )
{
    if( views.empty() )
    {
        return {};
    }
    std::string out = mcp ? ",\"declined_sites\":[" : ",\"dc\":[";
    const auto  list = [ & ]( std::string_view key, const std::vector<std::string>& items )
    {
        out += ",\"" + std::string( key ) + "\":[";
        for( std::size_t i = 0; i < items.size(); ++i )
        {
            out += ( i == 0 ? "\"" : ",\"" ) + jsonStr( items[i] ) + "\"";
        }
        out += "]";
    };
    for( std::size_t i = 0; i < views.size(); ++i )
    {
        const DeclinedSiteView& v = views[i];
        out += i == 0 ? "{" : ",{";
        if( callersForm )
        {
            out += mcp ? "\"in\":\"" + jsonStr( v.caller ) + "\",\"file\":\"" + jsonStr( v.file ) + "\",\"line\":" + std::to_string( v.line )
                       : "\"in\":\"" + jsonStr( v.caller ) + "\",\"p\":\"" + jsonStr( v.file ) + ":" + std::to_string( v.line ) + "\"";
        }
        else
        {
            out += std::string( mcp ? "\"name\":\"" : "\"n\":\"" ) + jsonStr( v.name ) + ( mcp ? "\",\"line\":" : "\",\"l\":" ) + std::to_string( v.line );
        }
        if( v.candsKnown )
        {
            out += ",\"cands\":" + std::to_string( v.cands );
        }
        out += ",\"via\":\"declined\"";
        if( v.gate != nullptr )
        {
            out += std::string( ",\"gate\":\"" ) + v.gate + "\"";
        }
        if( !v.bound.empty() )
        {
            out += ",\"bound\":\"" + jsonStr( v.bound ) + "\"";
        }
        if( !v.ofDef.empty() )
        {
            list( "of_def", v.ofDef );
        }
        if( !v.cand.empty() )
        {
            list( mcp ? "candidates" : "cand", v.cand );
        }
        if( v.candMore > 0 )
        {
            out += ",\"cand_more\":" + std::to_string( v.candMore );
        }
        out += "}";
    }
    out += "]";
    return out;
}

// The cut: how many rows print (the default cap, or --limit=N) and, past it, the call that lists every site — the same
// question with --limit raised to the total (never below the answer's own row window, so the <s> rows it pages do not shrink).
struct DeclinedSiteCut
{
    std::size_t shown = 0;
    std::string next;   // "" when nothing was cut
};
inline DeclinedSiteCut declinedSiteCut( std::size_t total, int pageLimit, std::string_view verbFlag, std::string_view selector, std::size_t rowWindow )
{
    DeclinedSiteCut cut;
    const std::size_t cap = pageLimit > 0 ? std::size_t( pageLimit ) : kDeclinedSiteCap;
    cut.shown = std::min( total, cap );
    if( cut.shown < total )
    {
        // saturated at --limit's own ceiling, so the call it names is one the parser accepts (a billion sites is past any tree)
        const std::size_t limit = std::min( std::max( total, rowWindow ), std::size_t( kPageValueMax ) );
        cut.next = nextFlag( verbFlag, selector ) + " --limit=" + std::to_string( limit );
    }
    ENSURES( cut.shown <= total && ( cut.shown == total ) == cut.next.empty() );
    return cut;
}
inline std::string declinedSiteCutAttrXml( const DeclinedSiteCut& cut )
{
    if( cut.next.empty() )
    {
        return {};
    }
    std::vector<char> esc;
    return " dc_shown=\"" + std::to_string( cut.shown ) + "\" dc_next=\"" + std::string( escapeXml( cut.next, esc ) ) + "\"";
}
// The JSON twin of the two root attributes, the same names on the CLI --json and the MCP twins (the attribute-parity rule).
// A cut prints at least one row (the cap and --limit are >= 1), so dc_shown is never the 0 countFieldOrEmpty leaves out.
inline std::string declinedSiteCutKeyJson( const DeclinedSiteCut& cut )
{
    return countFieldOrEmpty( "dc_shown", cut.next.empty() ? 0 : cut.shown, /*json=*/true ) + nextFieldJson( cut.next, "dc_next" );
}

// What the legend must define, read off the rows an answer prints (graphlegend.h declinedSitesLegend).
inline DeclinedSitesLegendFlags declinedSitesLegendFlags( std::span<const DeclinedSiteView> views, bool callersForm, const DeclinedSiteCut& cut )
{
    DeclinedSitesLegendFlags f;
    f.any         = !views.empty();
    f.callersForm = callersForm;
    f.cut         = !cut.next.empty();
    for( const DeclinedSiteView& v : views )
    {
        const std::string_view gate = v.gate != nullptr ? std::string_view( v.gate ) : std::string_view();
        f.side     = f.side || gate == "side";
        f.nameGate = f.nameGate || gate == "builtin" || gate == "std";
        f.iface    = f.iface || gate == "iface";
        f.bound    = f.bound || !v.bound.empty();
        f.ofDef    = f.ofDef || !v.ofDef.empty();
        f.cand     = f.cand || !v.cand.empty();
    }
    return f;
}

// ── lane ix2-slice (IX-4): the --impact answer's <dc> rows ──────────────────────────────────────────────────────────────
// --impact counted declined_calls= (the declines that could have reached SYM or a symbol in its radius) and named none of
// them: hono's `--impact=match` gave only counts, while the declined call in src/helper/dev/index.ts that could mean
// Router.match sat behind the callers verb. The impact answer (CLI XML, --json, columnar and the MCP twin) now prints the
// callers-form rows of exactly those calls — the same records, order and cut as --callers, spelled as --callers spells them
// except of_def= (DefGroups{} below: the radius has no definition table) — so uncut the row count equals declined_calls=. `targets` is the answer's decline set (SYM's definitions and its radius), `calls` its count.
struct ImpactDeclinedRows
{
    DeclinedSiteCut               cut;
    std::vector<DeclinedSiteView> views;
};
inline ImpactDeclinedRows impactDeclinedRows( const IngestResult& ing, const Graph& g, std::span<const NodeId> targets, std::size_t calls,
                                              int pageLimit, std::string_view sym, std::size_t rowWindow, const VrRender& vr, bool candidates )
{
    auto [ named, sites ] = declinedCallsAndSites( ing, g, targets, /*wantCallers=*/true );
    EXPECTS( named == calls, "the impact answer's declined_calls= counts the same set (graph.h declinedCallsNaming)" );
    ImpactDeclinedRows out;
    out.cut   = declinedSiteCut( sites.size(), pageLimit, "--impact=", sym, rowWindow );
    out.views = declinedSiteViews( ing, g, std::span<const std::uint32_t>( sites ).first( out.cut.shown ), /*callersForm=*/true, targets, DefGroups{}, vr,
                                   candidates );
    return out;
}

}   // namespace rw
