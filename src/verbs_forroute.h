#pragma once
#if !defined( RIPWIRE_MAIN_TU )
#error "verbs_forroute.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

#include "forroute.h"      // rule E + rule R (lane P1, transcribed)
#include "forkeybody.h"    // KB1: the routed symbol's definition body rides the routed answer
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
// RT2 (results/RT2_ROUTE_1118, frozen in its PREREG.md): rule E2/R2 (forroute.h: a where-used kind → --uses; a plain word
// or a `name!` / `name()` span the verb resolves), and W2 (partialwarn.h rt2Evidence): a TEXT GAP — files that name the symbol
// as a whole word and no row lists — is FOLDED into the answer as <text_only n=><tx p=FILE:LINE/>…</text_only> right after
// <route>; the first --for page rides along only on a reason a fold cannot answer (warn="1" why=<residual>). F1 alone priced
// a text gap at a whole page (~16 KB) where its rows cost ~40 B each; on RT1's confirmation set the fold kept every text-gap
// cell's gold (results/RT2_ROUTE_1118/DEV.md).
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
        case rw::forroute::RouteKind::WhereUsed:    c.usesSym   = spelling; break;
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
            case rw::forroute::RouteKind::WhereUsed:    return runUses( vd ).value_or( 1 );
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

// W2 on the routed answer (F1 inside it); nullopt when an evidence render could not run (the caller falls back to the kind:
// P1's hybrid).
inline std::optional<rw::partialwarn::RouteEvidence> routeEvidence( const MainDispatch& d, rw::forroute::RouteKind kind, const std::string& spelling,
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
    gc.grepIn = "any";   // RT2: the exhaustive view — every tier, and the <unindexed> section — for the fold
    const MainDispatch ad      = routeDispatch( d, gc );
    const RouteRender  grepAny = renderRouteCaptured( [ & ] { return runGrep( ad ).value_or( 1 ); } );
    d.redactCounts = before;
    if( !defs.captured || !grep.captured || grep.rc != 0 || !grepAny.captured || grepAny.rc != 0 )
    {
        return std::nullopt;
    }
    using rw::forroute::RouteKind;
    const std::string_view verb = kind == RouteKind::WhoCalls ? "callers" : kind == RouteKind::Transitive ? "impact" : "uses";
    const std::vector<rw::partialwarn::CorpusHit> hits = routeCorpusHits( d, last );
    return rw::partialwarn::rt2Evidence( { .verb = verb, .answer = answer, .defs = defs.out, .grep = grep.out, .last = last, .hits = hits }, grepAny.out,
                                         kind == RouteKind::WhoCalls || kind == RouteKind::WhereUsed );
}

// The <text_only> fold: every text-only file up to kFoldCap, sorted by path ("" when there is none).
inline std::string foldElementXml( const rw::partialwarn::RouteEvidence& ev )
{
    if( ev.fold.empty() )
    {
        return {};
    }
    std::vector<char> esc;
    std::string       x = "<text_only n=\"" + std::to_string( ev.fold.size() ) + "\"";
    x += ev.fold.size() > rw::partialwarn::kFoldCap ? " capped=\"1\">" : ">";
    for( std::size_t i = 0; i < ev.fold.size() && i < rw::partialwarn::kFoldCap; ++i )
    {
        x += "<tx p=\"";
        x += rw::escapeXml( ev.fold[ i ].file, esc );
        x += ':' + std::to_string( ev.fold[ i ].line ) + "\"/>";
    }
    return x + "</text_only>";
}

// The <route …/> element.
inline std::string routeElementXml( const rw::Config& cfg, rw::forroute::RouteKind kind, const std::string& spelling,
                                    const std::optional<rw::partialwarn::RouteEvidence>& w, bool page1 )
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
    else if( !w->residual.empty() )
    {
        x += " warn=\"1\" why=\"";
        x += rw::escapeXml( w->residual, esc );
        x += '"';
    }
    x += page1 ? " page1=\"1\"" : "";
    x += rw::nextAttrXml( rw::nextFlag( "--for=", cfg.forTask ) + " --no-verb-route" );
    x += "/>";
    return x;
}

// The first row block of an answer-first --for document when it is a <callers by="subject"> block whose own counts prove it
// whole: shown= equals total=, capped="0", d2_capped absent or "0". nullopt otherwise.
struct LeadBlock
{
    std::size_t      index = 0;
    std::string_view block;
};
inline std::optional<LeadBlock> leadingProvenCallers( std::string_view doc )
{
    const std::optional<rw::forpages::detail::Stream> st = rw::forpages::detail::readStream( doc );
    if( !st )
    {
        return std::nullopt;
    }
    std::size_t lead = 0;
    while( lead < st->streamBlocks && st->blocks[ lead ].comment )
    {
        ++lead;
    }
    if( lead >= st->streamBlocks || st->blocks[ lead ].name != "callers" )
    {
        return std::nullopt;
    }
    const std::string_view block = doc.substr( st->blocks[ lead ].begin, st->blocks[ lead ].end - st->blocks[ lead ].begin );
    const std::string_view open  = block.substr( 0, block.find( '>' ) );
    using rw::partialwarn::detail::attrOf;
    const std::string_view d2cap = attrOf( open, "d2_capped" );
    if( attrOf( open, "by" ) != "subject" || attrOf( open, "shown" ) != attrOf( open, "total" ) || attrOf( open, "capped" ) != "0" || !( d2cap.empty() || d2cap == "0" ) )
    {
        return std::nullopt;
    }
    return LeadBlock{ lead, block };
}

// KB1: the stream block the early page ends at — the key-body group's <bodies> when it sits directly behind block `lead` (its legend
// comment glued in front of it), else `lead` itself.
inline std::size_t keyGroupEndBlock( std::string_view doc, std::size_t lead )
{
    const std::optional<rw::forpages::detail::Stream> st = rw::forpages::detail::readStream( doc );
    if( !st || st->keyEnd <= st->keyBegin || st->keyBegin != st->blocks[ lead ].end )
    {
        return lead;
    }
    const auto at = std::ranges::find_if( st->blocks, [ & ]( const rw::answerfirst::Block& b ) { return b.end == st->keyEnd; } );
    return at == st->blocks.end() ? lead : std::size_t( at - st->blocks.begin() );
}

// RT2 ES (results/RT2_ROUTE_1118/PREREG.md §ES; owner-approved 2026-11-18): the default page 1 of an unrouted --for answer ENDS
// EARLY when its first block is AF4 T-B's <callers by="subject" of=S> and that block PROVES itself complete: shown= equals total=,
// capped="0", d2_capped absent or "0", and W2 (rt2Evidence, the block's own rows read as a --callers answer) finds neither a
// residual reason nor a text-only file. Anything short of that is today's page. A spelled --page-bytes never ends early, which
// is what the early page's next= (the full page 1) relies on. Gate: test/forverbroutecheck.sh (ES arms).
std::optional<std::string> forEarlyStopPage( const MainDispatch& d, const std::string& doc )
{
    const rw::Config& cfg = d.cfg;
    if( cfg.forTask.empty() || d.multiRoot || cfg.roots.size() != 1 || !cfg.pageBytesSpec.empty() || cfg.forPage != 1 || cfg.tokenBudget != 0
        || cfg.maxTokens != 0 || !cfg.legendDefaulted || !forPagingApplies( cfg ) )
    {
        return std::nullopt;
    }
    const std::optional<LeadBlock> lead = leadingProvenCallers( doc );
    if( !lead )
    {
        return std::nullopt;
    }
    const std::string_view block = lead->block;
    const std::string_view open  = block.substr( 0, block.find( '>' ) );
    using rw::partialwarn::detail::attrOf;
    const std::string subject( attrOf( open, "of" ) );
    const RouteRender verb = subject.empty() ? RouteRender{} : renderRoutedVerb( d, rw::forroute::RouteKind::WhoCalls, subject );
    if( routedVerbRefused( verb ) )
    {
        return std::nullopt;
    }
    // the block's rows, read as a --callers answer: plus the verb's own <def> rows (V1), which name the definition's and tied
    // declarations' files — the block prints none, and a header prototype must not read as a text-only file
    std::string answer( block.substr( 0, block.rfind( "</" ) ) );
    for( const std::string_view def : rw::partialwarn::detail::tagSpans( rw::partialwarn::detail::stripComments( verb.out ), "<def " ) )
    {
        answer += "<def " + std::string( def ) + ">";
    }
    answer += "</callers>";
    const std::optional<rw::partialwarn::RouteEvidence> ev = routeEvidence( d, rw::forroute::RouteKind::WhoCalls, subject, answer );
    if( !ev || !ev->residual.empty() || !ev->fold.empty() )
    {
        return std::nullopt;
    }
    // the block's own clause, and the window-aware hand-off's beside it when the block carries windows= (verbs_for.h header rule)
    const std::string_view windowClause = attrOf( open, "windows" ) == "1" ? rw::kForCompactWindowHandoffLegend : std::string_view{};
    const std::string legend = "<!-- ripwire for schema=ripwire.for/v1 (page 1, early): task= the query, at= this commit"
                             + std::string( rw::kForCompactSubjectCallerHopLegend ) + std::string( windowClause ) + " -->";
    const std::string call = forUnbudgetedCall( cfg );
    return rw::forpages::earlyFirstPage( doc, { .pageBytes = cfg.forPageBytes, .page = 1, .call = call }, keyGroupEndBlock( doc, lead->index ), legend );
}

// The route decided and the verb answered: what runForVerbRoute (CLI) and mcpForVerbRoute (MCP `for`) both assemble from.
struct RoutedAnswer
{
    rw::forroute::RouteDecision                     rd;
    std::string                                     spelling;
    RouteRender                                     verb;
    std::optional<rw::partialwarn::RouteEvidence>   w;
    bool                                            wantPage = false;   // a residual reason (or no evidence run on a non-who-calls kind)
};

// Rule E2 + R2 on d.cfg.forTask, the verb (as typed, else its last segment: P1's spelling fallback) and W2. nullopt: not
// routed — no kind, no symbol, or neither spelling resolves (the caller serves its unrouted answer).
inline std::optional<RoutedAnswer> routeQuestion( const MainDispatch& d )
{
    RoutedAnswer ra{ .rd = rw::forroute::decide( d.cfg.forTask ) };
    if( ra.rd.kind == rw::forroute::RouteKind::None )
    {
        return std::nullopt;
    }
    ra.spelling = ra.rd.sym;
    ra.verb     = renderRoutedVerb( d, ra.rd.kind, ra.spelling );
    if( routedVerbRefused( ra.verb ) && rw::forroute::lastSegment( ra.rd.sym ) != ra.rd.sym )
    {
        ra.spelling = std::string( rw::forroute::lastSegment( ra.rd.sym ) );
        ra.verb     = renderRoutedVerb( d, ra.rd.kind, ra.spelling );
    }
    if( routedVerbRefused( ra.verb ) )
    {
        return std::nullopt;   // the verb's notices are dropped with its answer
    }
    ra.w        = routeEvidence( d, ra.rd.kind, ra.spelling, ra.verb.out );
    ra.wantPage = ra.w ? !ra.w->residual.empty() : ra.rd.kind != rw::forroute::RouteKind::WhoCalls;
    return ra;
}

// KB1: remove a --for page's key-body group (its legend comment and <bodies of="key">), when it has one.
inline void dropKeyGroup( std::string& page )
{
    std::size_t keyBegin = 0, keyEnd = 0;
    if( const std::optional<rw::forpages::detail::Stream> st = rw::forpages::detail::readStream( page ) )
    {
        keyBegin = st->keyBegin;
        keyEnd   = st->keyEnd;
    }
    page.erase( keyBegin, keyEnd - keyBegin );
}

// RT3-F1: a WINDOWED verb answer (its root says has_more="1" next_offset=K) continues ITSELF: the routed root's next= becomes
// `--for=Q --offset=K`, the call that routes the same question to the verb's window at K (runForVerbRoute). An unwindowed
// root keeps the verb's own next=, byte for byte.
inline void continueRootNext( std::string& doc, std::string_view task )
{
    const rw::CompactRootInfo root = rw::findCompactRoot( doc );
    if( root.tag.empty() )
    {
        return;
    }
    const std::string_view open = std::string_view( doc ).substr( root.openBegin, root.openEnd - root.openBegin );
    const std::string_view k    = rw::partialwarn::detail::attrOf( open, "next_offset" );
    if( rw::partialwarn::detail::attrOf( open, "has_more" ) != "1" || k.empty() )
    {
        return;
    }
    const std::string next = rw::nextAttrXml( rw::nextFlag( "--for=", task ) + " --offset=" + std::string( k ) );
    const std::size_t at   = open.find( " next=\"" );
    if( at == std::string_view::npos )
    {
        doc.insert( root.openEnd - ( open.ends_with( "/>" ) ? 2 : 1 ), next );
        return;
    }
    const std::size_t close = open.find( '"', at + 7 );
    doc.replace( root.openBegin + at, close + 1 - at, next );
}

// RT3-F1: `--for=Q --offset=K` on a question that routes, and otherwise the bare call: the offset K, else 0.
inline int routeContinueOffset( const MainDispatch& d )
{
    if( d.cfg.pageOffset <= 0 || d.cfg.pageLimit > 0 )
    {
        return 0;
    }
    rw::Config bare = d.cfg;
    bare.pageOffset = 0;
    return forVerbRouteApplies( routeDispatch( d, bare ) ) ? d.cfg.pageOffset : 0;
}

// The routed document: the verb's answer with <route> (page1="1" when `page` is carried) and the fold as the root's first
// children, compacted as the bare call is, and `page` (a ranked --for answer, "" = none) as the root's last child.
inline std::string assembleRouted( const MainDispatch& d, RoutedAnswer& ra, std::string_view page )
{
    while( !page.empty() && page.back() == '\n' )
    {
        page.remove_suffix( 1 );
    }
    std::string doc = std::move( ra.verb.out );
    continueRootNext( doc, d.cfg.forTask );
    const rw::CompactRootInfo root = rw::findCompactRoot( doc );
    doc.insert( root.openEnd, routeElementXml( d.cfg, ra.rd.kind, ra.spelling, ra.w, !page.empty() ) + ( ra.w ? foldElementXml( *ra.w ) : std::string() ) );
    // KB1 (forkeybody.h): the routed symbol's definition body (and a second named symbol's) after the verb's rows, before a carried page.
    // A carried --for page carries its own key group (the same spans, the same printer); it moves up here, so the answer holds it once.
    std::string carried( page );
    if( rw::keybody::keyBodyOn() )
    {
        const std::string_view          keyRoot = d.ing.realPaths.empty() && d.cfg.roots.size() == 1 ? d.cfg.roots[0] : std::string_view();
        const rw::keybody::KeyBodies    kb      = rw::keybody::keyBodies( d.ing, d.cfg.forTask, ra.spelling, keyRoot, d.redactPtr );
        doc.insert( doc.rfind( "</" ), kb.xml );
        if( !kb.xml.empty() )
        {
            dropKeyGroup( carried );
        }
    }
    (void)rw::applyCompactDialect( doc, ::compactLegendHint( d.cfg, doc ) );   // the bare call's dialect: main.cpp's layer skips --for
    if( !carried.empty() )
    {
        doc.insert( doc.rfind( "</" ), carried );
    }
    return doc;
}

// RT3-F1: the routed verb's window at `offset` — <route> (its verb= spells the offset) and the verb's rows, compacted as the
// bare call is. No evidence, fold, key body or carried page: those belong to the first window. nullopt: the question does not
// route, or the verb refuses both spellings (the caller serves the --for file page, as before).
inline std::optional<std::string> routedContinuation( const MainDispatch& d, int offset, RouteRender& verbOut )
{
    const rw::forroute::RouteDecision rd = rw::forroute::decide( d.cfg.forTask );
    if( rd.kind == rw::forroute::RouteKind::None )
    {
        return std::nullopt;
    }
    std::string spelling = rd.sym;
    verbOut = renderRoutedVerb( d, rd.kind, spelling );   // d.cfg carries --offset into the verb's own window
    if( routedVerbRefused( verbOut ) && rw::forroute::lastSegment( rd.sym ) != rd.sym )
    {
        spelling = std::string( rw::forroute::lastSegment( rd.sym ) );
        verbOut  = renderRoutedVerb( d, rd.kind, spelling );
    }
    if( routedVerbRefused( verbOut ) )
    {
        return std::nullopt;
    }
    std::string doc = std::move( verbOut.out );
    continueRootNext( doc, d.cfg.forTask );
    const rw::CompactRootInfo root = rw::findCompactRoot( doc );
    std::string route = routeElementXml( d.cfg, rd.kind, spelling, rw::partialwarn::RouteEvidence{}, false );
    route.insert( route.find( '"', route.find( " verb=\"" ) + 7 ), " --offset=" + std::to_string( offset ) );   // verb= spells the window
    doc.insert( root.openEnd, route );
    (void)rw::applyCompactDialect( doc, ::compactLegendHint( d.cfg, doc ) );
    return doc;
}

std::optional<int> runForVerbRoute( const MainDispatch& d )
{
    if( const int offset = routeContinueOffset( d ); offset > 0 )
    {
        RouteRender                      verb;
        const std::optional<std::string> doc = routedContinuation( d, offset, verb );
        if( !doc )
        {
            return std::nullopt;
        }
        std::fwrite( doc->data(), 1, doc->size(), stdout );
        std::fwrite( verb.err.data(), 1, verb.err.size(), stderr );
        return verb.rc;
    }
    if( !forVerbRouteApplies( d ) )
    {
        return std::nullopt;
    }
    std::optional<RoutedAnswer> ra = routeQuestion( d );
    if( !ra )
    {
        return std::nullopt;   // the --for answer, byte for byte
    }
    // the first --for page, rendered as the opted-out call would serve it
    RouteRender page;
    if( ra->wantPage )
    {
        // the FULL page 1, as the spelled default page serves it: the carried page never ends early (ES is page 1 of an UNROUTED answer)
        static_assert( rw::answerfirst::kAnswerPageBytesDefault == 12000, "the spelled default page below is the default page size" );
        rw::Config pc    = d.cfg;
        pc.pageBytesSpec = "12000";
        const MainDispatch pd = routeDispatch( d, pc );
        page = renderRouteCaptured( [ & ] { return runForLens( pd ).value_or( 1 ); } );
    }
    const bool        hasPage = ra->wantPage && page.captured && page.rc == 0 && rw::findCompactRoot( page.out ).tag == "ctx";
    const std::string doc     = assembleRouted( d, *ra, hasPage ? std::string_view( page.out ) : std::string_view{} );
    std::fwrite( doc.data(), 1, doc.size(), stdout );
    std::fwrite( ra->verb.err.data(), 1, ra->verb.err.size(), stderr );
    if( hasPage )
    {
        std::fwrite( page.err.data(), 1, page.err.size(), stderr );
    }
    return ra->verb.rc;
}

}   // namespace — verbs_forroute.h section of main.cpp

// RT2 MCP PARITY (coordinator 2026-11-19): MCP `for` routes by the SAME frozen rule. The server's warm index answers through
// the CLI's own route (routeQuestion / assembleRouted above) on a dispatch built the way a bare CLI --for run builds its own —
// fan-in from the in-edge CSR and computeQMetrics, nothing git-mined — so a routed MCP payload carries the CLI routed answer's
// rows. The carried page is `page()`: MCP's own `for` answer (MCP serves `for` unpaged). Declared in mcpverbs.h.
// Gate: test/mcpforroutecheck.sh.
namespace rw
{
// The dispatch a bare CLI --for run builds — fan-in from the in-edge CSR and computeQMetrics, nothing git-mined — over the
// server's warm index, handed to `use`. `offset` > 0: the run is `--for=Q --offset=K` (RT3-F1's continuation).
template <class Use>
std::optional<std::string> withMcpRouteDispatch( const IngestResult& ing, const Graph& g, const std::string& root, const std::string& task, int offset, Use&& use )
{
    Config cfg;
    cfg.roots           = { std::string_view( root ) };
    cfg.rootPath        = cfg.roots.front();
    cfg.forTask         = task;
    cfg.legendDefaulted = true;
    cfg.pageOffset      = offset;
    std::vector<std::uint32_t> fanIn( ing.symbols.size(), 0 );
    const auto* ro = g.inEdges.rowOffsets();
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        fanIn[ i ] = ro[ i + 1 ] - ro[ i ];
    }
    const QMetrics                     qmetrics = computeQMetrics( ing, g );
    const std::vector<WorkspaceRoot>   ws;
    std::vector<std::uint32_t>         forChurn;
    RedactCounts                       redactCounts;
    const MainDispatch d{ cfg, ing, g, root, false, ws, fanIn, &fanIn, qmetrics, nullptr, &qmetrics.cbo, &qmetrics.tested, &qmetrics.lcom4,
                          nullptr, forChurn, redactCounts, nullptr, nullptr, false, nullptr, true };
    return use( d );
}

std::optional<std::string> mcpForVerbRoute( const IngestResult& ing, const Graph& g, const std::string& root, const std::string& task,
                                            const std::function<std::optional<std::string>()>& page )
{
    return withMcpRouteDispatch( ing, g, root, task, 0, [ & ]( const MainDispatch& d ) -> std::optional<std::string>
    {
        std::optional<RoutedAnswer> ra = routeQuestion( d );
        if( !ra )
        {
            return std::nullopt;
        }
        std::optional<std::string> carried;
        if( ra->wantPage )
        {
            carried = page();
        }
        return assembleRouted( d, *ra, carried ? std::string_view( *carried ) : std::string_view{} );
    } );
}

// RT3-F1: MCP `for` with offset=K (and no limit=): the routed verb's window at K, as the CLI's `--for=Q --offset=K` serves it.
std::optional<std::string> mcpForVerbContinue( const IngestResult& ing, const Graph& g, const std::string& root, const std::string& task, int offset )
{
    return withMcpRouteDispatch( ing, g, root, task, offset, [ & ]( const MainDispatch& d )
    {
        RouteRender verb;
        return routedContinuation( d, offset, verb );
    } );
}
}   // namespace rw
