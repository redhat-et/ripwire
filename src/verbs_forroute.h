#pragma once
#if !defined( RIPWIRE_MAIN_TU )
#error "verbs_forroute.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

#include "forroute.h"      // rule E + rule R (lane P1, transcribed)
#include "partialwarn.h"   // F1, the partial-answer evidence (lane W1, frozen)

// verbs_forroute.h — RT1 (owner decision 2026-11-18): a --for question that NAMES its symbol and asks a call-graph question is
// answered by the verb that answers it, ROUTED.
//
// THE ANSWER. The routed verb's own answer (--callers / --uses / --impact, its legend compacted as the bare call's is), with
// ONE element added as the root's FIRST child, ahead of V1's <def> rows:
//   <route from="for" kind= verb= task= complete="not-proven" [warn="1" why=] [page1="1"] next="--for='…' --no-verb-route"/>
// and, when F1 found evidence the verb may be partial (warn="1"), the FIRST PAGE of the --for answer as the root's LAST child
// (<ctx …>, its own legend inside, its own next= the second page). complete= is "not-proven" on every routed answer: nothing in
// a verb's bytes can prove completeness, and an absent warn= means no evidence was found, not that there is none.
//
// WHY THIS SHAPE (results/P1_VERBROUTE_1118 Addendum, results/W1_PARTIALWARN_1118). A replace-route lost a gold group on 11 of
// 21 routed cells; route + fallback lost none, and the verb alone was enough on the cells F1 does not warn on (6 of 6 losses
// warned, 2 of 15 complete cells falsely). Carrying the page INSIDE the answer is what makes a wrong stop safe: an agent that
// trusts a warned answer still reads the ranked --for rows. Pre-registered, priced and confirmed in results/RT1_ROUTE_1118.
//
// WHEN IT FIRES. A BARE `--for=Q` (no flag that shapes the --for answer: forUnbudgetedCall is the bare call, no page asked,
// no budget, XML, single root, the default legend posture) whose text rule E names a symbol and rule R reads a kind, and whose
// verb resolves that symbol — as typed, else its last segment (P1's spelling fallback). Anything else is the --for answer,
// byte for byte; so is --no-verb-route, the opt-out the route's own next= spells. A spelled --page-bytes never routes, which
// is what keeps every page's next= (`--for='…' --page-bytes=N:K`) a page of the --for answer.
// MCP `for` is UNCHANGED (AF1 left MCP unpaged, and the fallback contract here is "the first page + next="); an MCP client
// already holds find_referencing_symbols / uses / impact as tools of their own.
// Gate: test/forverbroutecheck.sh.

namespace
{

// The route applies to this run's --for answer at all (before reading its text).
inline bool forVerbRouteApplies( const MainDispatch& d )
{
    const rw::Config& cfg = d.cfg;
    return !cfg.forTask.empty() && !cfg.noVerbRoute && !d.multiRoot && cfg.roots.size() == 1 && cfg.pageBytesSpec.empty() && cfg.tokenBudget == 0
        && cfg.maxTokens == 0 && cfg.legendDefaulted && forPagingApplies( cfg ) && forUnbudgetedCall( cfg ) == rw::nextFlag( "--for=", cfg.forTask );
}

// One internal render: its stdout, stderr and exit code (`captured` false: no buffer could be set up, nothing ran).
struct RouteRender
{
    bool        captured = false;
    int         rc       = 0;
    std::string out, err;
};
template <class Run>
RouteRender renderRouteCaptured( Run&& run )
{
    RouteRender   r;
    StderrCapture err( true );
    StdoutCapture out( true );
    if( !out.active() )
    {
        return r;
    }
    r.rc = run();
    const std::optional<StdoutCaptured> o = out.finish();
    const std::optional<StdoutCaptured> e = err.finish();
    r.captured = capturedWhole( o );
    r.out      = o ? o->bytes : std::string();
    r.err      = e && e->restored ? e->bytes : std::string();
    return r;
}

// A MainDispatch over another Config (the same index and graph).
inline MainDispatch routeDispatch( const MainDispatch& d, const rw::Config& c )
{
    return MainDispatch{ c, d.ing, d.g, d.root, d.multiRoot, d.ws, d.fanIn, d.fanInPtr, d.qmetrics, d.ampPtr, d.cboPtr, d.testedPtr, d.lcom4Ptr,
                         d.impurePtr, d.forChurn, d.redactCounts, d.redactPtr, d.notesPtr, d.notesDegraded, nullptr, d.valueUses };
}

// The bare verb call for `kind` on `spelling`, rendered as its own run would (full dialect: compacted by the caller).
inline RouteRender renderRoutedVerb( const MainDispatch& d, rw::forroute::RouteKind kind, const std::string& spelling )
{
    rw::Config c = d.cfg;
    c.forTask    = {};
    switch( kind )
    {
        case rw::forroute::RouteKind::WhoCalls:     c.callers   = spelling; break;
        case rw::forroute::RouteKind::DirectRadius: c.usesSym   = spelling; break;
        case rw::forroute::RouteKind::Transitive:   c.impactSym = spelling; break;
        case rw::forroute::RouteKind::None:         return {};
    }
    const MainDispatch vd = routeDispatch( d, c );
    return renderRouteCaptured( [ & ]
    {
        switch( kind )
        {
            case rw::forroute::RouteKind::WhoCalls:     return runCallHierarchy( vd ).value_or( 1 );
            case rw::forroute::RouteKind::DirectRadius: return runUses( vd ).value_or( 1 );
            case rw::forroute::RouteKind::Transitive:   return runImpact( vd ).value_or( 1 );
            case rw::forroute::RouteKind::None:         break;
        }
        return 1;
    } );
}

// P1's refusal test: a non-zero exit, an empty answer, or a root that says found="0".
inline bool routedVerbRefused( const RouteRender& r )
{
    if( !r.captured || r.rc != 0 || r.out.empty() )
    {
        return true;
    }
    const rw::CompactRootInfo root = rw::findCompactRoot( r.out );
    return root.tag.empty() || rw::spanHasAttr( std::string_view( r.out ).substr( root.openBegin, root.openEnd - root.openBegin ), "found", "\"0\"" );
}

// Every whole-word line of `last` in the frozen corpus (partialwarn.h isCorpusPath), in (path, line) order.
inline std::vector<rw::partialwarn::CorpusHit> routeCorpusHits( const MainDispatch& d, std::string_view last )
{
    std::vector<rw::partialwarn::CorpusHit> hits;
    const std::string prefix = rw::sarif::rootPrefixOf( d.cfg.roots[ 0 ] );
    for( std::uint32_t f = 0; f < d.ing.files.size(); ++f )
    {
        const std::string_view rel = rw::sarif::rootRelativeUri( d.ing.files[ f ], prefix );
        if( !rw::partialwarn::isCorpusPath( rel ) )
        {
            continue;
        }
        const std::optional<std::string> text = rw::docparse::detail::readWholeFile( rw::diskPath( d.ing, f ) );
        if( text )   // an unreadable file contributes no hit: the warning reads less evidence, never invents one
        {
            rw::partialwarn::scanText( rel, *text, last, hits );
        }
    }
    std::ranges::sort( hits, []( const rw::partialwarn::CorpusHit& a, const rw::partialwarn::CorpusHit& b ) { return std::tie( a.file, a.line ) < std::tie( b.file, b.line ); } );
    return hits;
}

// F1 on the routed answer; nullopt when an evidence render could not run (the caller falls back to the kind: P1's hybrid).
inline std::optional<rw::partialwarn::Warn> routeEvidence( const MainDispatch& d, rw::forroute::RouteKind kind, const std::string& spelling,
                                                           const std::string& answer )
{
    const std::string last = rw::partialwarn::answerTarget( answer );
    if( last.empty() )
    {
        return std::nullopt;
    }
    const rw::RedactCounts before = d.redactCounts;   // the evidence renders are read, never printed: they count nothing
    rw::Config dc = d.cfg;
    dc.forTask    = {};
    dc.defsSpec   = spelling;
    const MainDispatch dd   = routeDispatch( d, dc );
    const RouteRender  defs = renderRouteCaptured( [ & ] { return runDefs( dd ).value_or( 1 ); } );
    rw::Config gc = d.cfg;
    gc.forTask    = {};
    gc.grep       = last;
    const MainDispatch gd   = routeDispatch( d, gc );
    const RouteRender  grep = renderRouteCaptured( [ & ] { return runGrep( gd ).value_or( 1 ); } );
    d.redactCounts = before;
    if( !defs.captured || !grep.captured || grep.rc != 0 )
    {
        return std::nullopt;
    }
    const std::string_view verb = kind == rw::forroute::RouteKind::WhoCalls ? "callers" : kind == rw::forroute::RouteKind::DirectRadius ? "uses" : "impact";
    const std::vector<rw::partialwarn::CorpusHit> hits = routeCorpusHits( d, last );
    return rw::partialwarn::frozenF1( { .verb = verb, .answer = answer, .defs = defs.out, .grep = grep.out, .last = last, .hits = hits } );
}

// The <route …/> element.
inline std::string routeElementXml( const rw::Config& cfg, rw::forroute::RouteKind kind, const std::string& spelling, const std::optional<rw::partialwarn::Warn>& w,
                                    bool page1 )
{
    std::vector<char> esc;
    std::string       x = "<route from=\"for\" kind=\"";
    x += rw::forroute::kindName( kind );
    x += "\" verb=\"";
    x += rw::escapeXml( rw::nextFlag( rw::forroute::verbFlag( kind ), spelling ), esc );
    x += "\" task=\"";
    x += rw::escapeXml( cfg.forTask, esc );
    x += "\" complete=\"not-proven\"";
    if( !w )   // F1 could not run: P1's hybrid — who-calls is served alone, the other kinds warn by kind
    {
        x += kind == rw::forroute::RouteKind::WhoCalls ? " why=\"unchecked\"" : " warn=\"1\" why=\"kind\"";
    }
    else if( w->warn )
    {
        x += " warn=\"1\" why=\"";
        x += rw::escapeXml( w->why, esc );
        x += '"';
    }
    x += page1 ? " page1=\"1\"" : "";
    x += rw::nextAttrXml( rw::nextFlag( "--for=", cfg.forTask ) + " --no-verb-route" );
    x += "/>";
    return x;
}

std::optional<int> runForVerbRoute( const MainDispatch& d )
{
    if( !forVerbRouteApplies( d ) )
    {
        return std::nullopt;
    }
    const rw::forroute::RouteDecision rd = rw::forroute::decide( d.cfg.forTask );
    if( rd.kind == rw::forroute::RouteKind::None )
    {
        return std::nullopt;
    }
    // the verb, as typed, else its last segment (P1's spelling fallback); a symbol neither spelling resolves is not routed
    std::string spelling = rd.sym;
    RouteRender verb     = renderRoutedVerb( d, rd.kind, spelling );
    if( routedVerbRefused( verb ) && rw::forroute::lastSegment( rd.sym ) != rd.sym )
    {
        spelling = std::string( rw::forroute::lastSegment( rd.sym ) );
        verb     = renderRoutedVerb( d, rd.kind, spelling );
    }
    if( routedVerbRefused( verb ) )
    {
        return std::nullopt;   // the --for answer, byte for byte (the verb's notices are dropped with its answer)
    }
    const std::optional<rw::partialwarn::Warn> w = routeEvidence( d, rd.kind, spelling, verb.out );
    const bool wantPage = w ? w->warn : rd.kind != rw::forroute::RouteKind::WhoCalls;

    // the first --for page, rendered as the opted-out call would serve it
    RouteRender page;
    if( wantPage )
    {
        page = renderRouteCaptured( [ & ] { return runForLens( d ).value_or( 1 ); } );
    }
    const bool hasPage = wantPage && page.captured && page.rc == 0 && rw::findCompactRoot( page.out ).tag == "ctx";

    std::string doc = std::move( verb.out );
    const rw::CompactRootInfo root = rw::findCompactRoot( doc );
    doc.insert( root.openEnd, routeElementXml( d.cfg, rd.kind, spelling, w, hasPage ) );
    (void)rw::applyCompactDialect( doc, ::compactLegendHint( d.cfg, doc ) );   // the bare call's dialect: main.cpp's layer skips --for
    if( hasPage )
    {
        const std::size_t close = doc.rfind( "</" );
        std::string_view  p     = page.out;
        while( !p.empty() && p.back() == '\n' )
        {
            p.remove_suffix( 1 );
        }
        doc.insert( close, p );
    }
    std::fwrite( doc.data(), 1, doc.size(), stdout );
    std::fwrite( verb.err.data(), 1, verb.err.size(), stderr );
    if( hasPage )
    {
        std::fwrite( page.err.data(), 1, page.err.size(), stderr );
    }
    return verb.rc;
}

}   // namespace — verbs_forroute.h section of main.cpp
