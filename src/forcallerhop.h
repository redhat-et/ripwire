#pragma once
// forcallerhop.h — THE CALLER HOP of a name-exact --for answer (lane mf1-nx): when the route names ONE function, its callers.
//
// WHY. A --for question whose subject is a bare function name routes name-exact and serves that function: its signature row,
// its body and the body's callee signatures (<calls>). A change-propagation question ("if X gains a parameter, which functions
// must change?") needs the other direction, and the answer stopped at the definition: on the MF1-DEV rows the name-exact
// change-propagation answers held 3 of 16 required items, while the callers verb on the same symbol reached them. Measured
// offline before this code (reports/mf1-nx.md Stage 0): appending the callers verb's rows lifted 4 of the 7 name-exact
// function rows by >= 1 required item under Rule C, and none of the 163 non-sealed round-5 rows routes name-exact at all.
//
// WHAT. <callers of= shown= total= capped= d2= d2_shown= next=> after the file tail and before the bodies (a prefix-budgeted
// reader meets the callers before the body CDATA): the function's 1-hop callers — the callers verb's own rows
// (callhierarchy.h oneHopCallerRows: every definition's in-edges, tier/path order, ranked before the cap), each <s t= n= sc=
// p=file:line> with its call sites (sites_at=, the callers verb's CALLSITE-AT pass) and via="name" when the edge was matched by
// name alone — then the callers of the SHOWN callers as d="2" rows (the same helper one hop further, by rank, at most
// kForCallerHopDepth2Rows). shown=/total= count the first hop, d2_shown=/d2= the second; capped="1" when either was cut, and
// next= is the whole caller radius (--impact) either way. Counts are floors: resolved call edges only, as the callers verb says.
//
// WHEN. The name-exact route, the auto <bodies> bundle, and the callers verb's OWN resolution of the name is ONE function: its
// definitions (a C++ declaration and its out-of-line definition are one) fall in one def group, all functions or methods of one
// kind, nothing unproven (forCallerHopTargets); a bodyless declaration group the verb lists (a <def> table) but no row ties to is
// not a second function, and its rows then carry no of_def= here (they would all read of_def="1"). A C++ overload set, a same-named static in two files, a function beside a
// same-named struct and a name in two classes carry no block: the callers verb splits or hedges them (of_def=, cross_kind=), and
// this element prints exactly what `--callers=NAME` prints or nothing. The second hop's rows carry the by-name hedge the callers
// verb prints for them (via="name"). The DEFAULT regime and the XML dialect only, as the body fold: an explicit --token-budget,
// --json, --signatures-only, --detail=N and every other route carry none (byte-identical to before). MCP for is not changed.
// RIPWIRE_NO_CALLER_HOP (any value) turns it off — the A/B handle, the RIPWIRE_NO_BODY_FOLD precedent.

#include "clones.h"          // scanCodeTokens / CodeScanOptions — the ranked seed reads a body's string literals
#include "callhierarchy.h"   // oneHopCallerRows — the callers verb's rows; rowCallSites / callSitesAttrXml via editcheck.h
#include "defattrib.h"       // attributeOneHopAnswer — via="name" on a row, as the callers verb decides it
#include "docparse.h"        // detail::readWholeFile — the ranked seed reads the candidate's file
#include "filter.h"          // pathTierOf — the ranked seed's noise gate (every first-hop caller a test or bench path)
#include "graph.h"           // viaNameAttr
#include "infra/namesplit.h"   // isIdentChar — the ranked seed's task-word fold
#include "lexical.h"         // splitRouteWords — the ranked seed's task words
#include "memberowner.h"     // MemberOwners / qualifiedMemberName — n= as the callers verb prints it (QUALNAME-1, train 33)
#include "model.h"
#include "nextverb.h"        // nextFlag / nextAttrXml
#include "receiverevidence.h"   // ReceiverEvidence::callableKind — the one function-or-method test
#include "sarif.h"           // rootRelativeUri
#include "serialize.h"       // escapeXml
#include "valuerefs.h"       // VrRender

#include <algorithm>
#include <cstddef>
#include <cstdlib>
#include <iterator>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// The first hop's shown rows: a runaway guard over a fan-in, not a size target — every row it leaves out is counted (total=,
// capped="1") and next= serves them. 16 rows of ~60-110 B: a change-propagation answer lists every caller in the common case.
inline constexpr std::size_t kForCallerHopRows = 16;
// The second hop's shown rows (callers of the shown callers, by rank): measured on Stage 0, the rows that carried a required item
// (the entry point two hops up) were within the first four.
inline constexpr std::size_t kForCallerHopDepth2Rows = 4;

// The A/B switch: the hop rides unless RIPWIRE_NO_CALLER_HOP is set. The caller adds the posture (name-exact route, XML, default regime).
inline bool forCallerHopOn()
{
    return std::getenv( "RIPWIRE_NO_CALLER_HOP" ) == nullptr;
}

// The function the hop is about. Two readings must agree, and the hop fires only when both say ONE function:
//   * the body candidates (verbs_for.h computeAutoBodyCandidateIds, the anchor-restricted auto-body head): non-empty, every one a
//     function or method with the first one's name AND scope — a name-exact answer bodying two different symbols, a class, a
//     variable or a doc section carries no hop;
//   * THE CALLERS VERB'S OWN RESOLUTION of that selector, `--callers=Scope::name` (callhierarchy.h callHierarchyRows: resolveAllByNameQualified, crossKindValue,
//     defGroupsOf, attributeOneHopAnswer's silent-group drop): every definition the verb would union — not only the anchor's — is a function or method, none differs in kind
//     (no cross_kind=), the resolver left no unproven residue, and they fall in exactly ONE def group (a definition with its tied
//     declarations; the verb prints no <def> table and no of_def=). An overload set, two same-named statics in two files, a function
//     beside a same-named struct, a name in two classes: the verb splits or hedges them, so the hop prints no row (fix round 1,
//     rv-mf1-nx B1/B2: exact or no row).
// The targets ARE the verb's matches, so total= and every row equal what `--callers=NAME` prints.
inline std::vector<NodeId> forCallerHopTargets( const IngestResult& ing, const Graph& g, std::span<const NodeId> bodyCandidates )
{
    if( bodyCandidates.empty() )
    {
        return {};
    }
    const Symbol& first = ing.symbols[ bodyCandidates.front() ];
    for( const NodeId id : bodyCandidates )
    {
        const Symbol& s = ing.symbols[id];
        if( !ReceiverEvidence::callableKind( s.kind ) || s.name != first.name || s.scope != first.scope )
        {
            return {};
        }
    }
    std::size_t         unproven = 0;
    // the selector the element names (of=, next=) — what `--callers=SELECTOR` resolves: scope::name, the bare name when unscoped
    const std::string   sel      = first.scope.empty() ? first.name : first.scope + "::" + first.name;
    std::vector<NodeId> matches  = resolveAllByNameQualified( ing, sel, &unproven );
    if( matches.empty() || unproven != 0 || !crossKindValue( ing, matches ).empty() )
    {
        return {};
    }
    for( const NodeId id : matches )
    {
        if( !ReceiverEvidence::callableKind( ing.symbols[id].kind ) )
        {
            return {};
        }
    }
    for( const NodeId id : bodyCandidates )   // the anchor's own definitions are among the verb's (the hop is about THIS function)
    {
        if( std::find( matches.begin(), matches.end(), id ) == matches.end() )
        {
            return {};
        }
    }
    // the verb's groups AFTER its silent-group drop (attributeOneHopAnswer): ONE function means the verb groups the rows under one
    // definition. A bodyless declaration group that no row ties to (an in-class declaration the fold could not pair with its
    // out-of-line definition, ninja's DepsLog::Recompact: the verb prints a <def> table whose every row says of_def="1") does not
    // make a second function; a second BODIED group, a row tied to a bodyless group, or a split-labelled tie does.
    const std::vector<NodeId>     rows = oneHopCallerRows( ing, g, matches );
    const OneHopAttribution       attr = attributeOneHopAnswer( ing, g, matches, rows, /*towardMatches=*/true );
    std::size_t                   bodied = 0;
    for( std::size_t k = 0; k < attr.groups.size(); ++k )
    {
        bodied += attr.groups.bodyless[k] ? 0 : 1;
    }
    if( attr.groups.size() == 1 )
    {
        return matches;
    }
    if( bodied != 1 )
    {
        return {};
    }
    for( const std::uint32_t tok : attr.tokens.tok )
    {
        if( attr.groups.bodyless[ tok >> 2 ] || ( tok & 3u ) == std::uint32_t( DefMark::Split ) )
        {
            return {};
        }
    }
    return matches;
}

// UPWARD-2HOP — THE RANKED SEED (the ranked routes, subtoken+body): a task that names an ERROR (an error string, "X fails") but no
// function still often ranks the function that raises or detects it near the head, and when that function is a narrow funnel (one
// to three callers) the answer needs the chain above it: its callers and their callers — who reaches the error. Measured
// (ORCH reports/upward-2hop.md Stage 0): cockroach-01 execStmtInAbortedState (r=3) -> execStmt, ninja-06 VerifyDAG (r=2) ->
// RecomputeNodeDirty -> RecomputeDirty; on the 60 S1 --for questions the same seed without the error gate fired on 35 rows, mostly
// on a narrow-funnel row the question was not about (noise), so the task gate is part of the rule, not a tuning.
// The seed is one of the rows <sigs> emitted at r=1..kForRankedHopHeadRows that is ONE function by the callers verb's own
// resolution (forCallerHopTargets, the same exact-or-no-row rule) with 1..kForRankedHopMaxCallers 1-hop caller rows; the element is
// renderForCallerHop's, marked by="rank". NOISE GATES: no element when every first-hop caller is a test or bench path (the chain
// already ends there), or when every first-hop caller was matched by name alone (a Go interface method, a duck-typed Python call:
// the second hop would inherit an unproven receiver unhedged). WHICH eligible row: the first whose own body holds a string literal
// with >= 2 of the task's words (the function that raises the message, fix-1 F5); with none, the first eligible row, for a
// statement only — a question ("Where is X raised?") with no message-bearing row gets no element.
inline constexpr std::size_t kForRankedHopHeadRows  = 3;   // r=1..3: the emitted head the seed is read from
inline constexpr std::size_t kForRankedHopMaxCallers = 3;  // the narrow-funnel bar: a wider fan-in is the callers verb's page, not a chain
// The ranked legends below state both bars as text ("r=1..3", "1 to 3 callers", "1-3 callers"): a constant edited alone would
// leave the clause stale with no gate noticing, so the text and the constants are tied here (edit both, or neither).
static_assert( kForRankedHopHeadRows == 3 && kForRankedHopMaxCallers == 3,
               "kForRankedCallerHopLegend / kForCompactRankedCallerHopLegend state r=1..3 and 1 to 3 callers — edit the clauses with the constants" );

// The task names an error or a failure, in any language's vocabulary, as a WHOLE WORD (ASCII case-folded; "failover" is not "fail",
// "terror" is not an error): error(s)/errored, exception(s), panic(s)/panicked, Traceback, raise(s)/raised, throw(s)/threw/thrown,
// segfault, crash(es)/crashed, fail(s)/failed/failing/failure(s) — or an error TYPE written as one identifier whose last subtoken
// is error/exception (DependencyCycleError, dependency_cycle_error, ValueError, IOException). The words are lowercased AFTER the
// identifier split, so a CamelCase tail is not lost. Not on an EXPLANATION question ("How does X turn an error into a response?"):
// that asks for a mechanism, not for who reaches one error (measured: koa-12, starlette-12). Inflections the table does not list
// (`errored out`, `Err`, `returns nil`) are a floor, in the safe direction: no element.
inline constexpr std::string_view kForErrorWords[] = {
    "error", "errors", "errored", "exception", "exceptions", "panic", "panics", "panicked", "traceback", "raise", "raises", "raised",
    "throw", "throws", "threw", "thrown", "segfault", "segfaults", "crash", "crashes", "crashed", "fail", "fails", "failed", "failing",
    "failure", "failures" };

// The task's ident-run words in order, case kept (camel tails are the error-type test's input): every non-identifier byte is a space.
inline std::vector<std::string> forTaskIdentWords( std::string_view task )
{
    std::string folded( task );
    for( char& c : folded )
    {
        c = namesplit::isIdentChar( c ) ? c : ' ';
    }
    std::vector<std::string> out;
    for( const std::string_view w : splitRouteWords( folded ) )
    {
        out.emplace_back( w );
    }
    return out;
}

// "How does …", "Explain …", "Describe …": a question about a mechanism (the first word, case-folded).
inline bool forTaskExplains( std::string_view task )
{
    const std::vector<std::string> w = forTaskIdentWords( task );
    if( w.empty() )
    {
        return false;
    }
    const std::string first = routeLower( w.front() );
    return first == "how" || first == "explain" || first == "describe";
}

// Any question: a `?`, or a question-opening first word. The seed fallback (no message-bearing row) is for statements only.
inline bool forTaskIsQuestion( std::string_view task )
{
    if( task.find( '?' ) != std::string_view::npos )
    {
        return true;
    }
    const std::vector<std::string> w = forTaskIdentWords( task );
    if( w.empty() )
    {
        return false;
    }
    const std::string first = routeLower( w.front() );
    static constexpr std::string_view kOpeners[] = { "how", "what", "why", "where", "which", "when", "who", "explain", "describe", "does", "do", "is", "are", "can",
        "did", "could", "should", "would", "will", "was", "were", "has", "have" };   // yes/no questions carry no `?` at times
    return std::ranges::find( kOpeners, std::string_view( first ) ) != std::end( kOpeners );
}

inline bool forRankedCallerHopTask( std::string_view task )
{
    if( forTaskExplains( task ) )
    {
        return false;
    }
    std::vector<std::string> parts;
    for( const std::string& w : forTaskIdentWords( task ) )
    {
        const std::string lower = routeLower( w );
        if( std::ranges::find( kForErrorWords, std::string_view( lower ) ) != std::end( kForErrorWords ) )
        {
            return true;
        }
        parts.clear();
        subtokens( w, parts );   // DependencyCycleError / dependency_cycle_error -> [dependency, cycle, error]
        if( parts.size() >= 2 && ( parts.back() == "error" || parts.back() == "exception" ) )
        {
            return true;
        }
    }
    return false;
}

// UPWARD-2HOP F5 — THE MESSAGE-ANCHORED SEED. The task's content words: the lowercased subtokens of its identifier runs, two bytes
// or more, no route stopword, no plain English function word, not error/errors (every task here has one). Distinct.
inline std::vector<std::string> forTaskContentWords( std::string_view task )
{
    static constexpr std::string_view kPlain[] = { "and", "or", "be", "it", "as", "at", "by", "from", "that", "this", "was", "has", "have",
                                                   "into", "when", "why", "who", "can", "error", "errors" };
    std::vector<std::string> out;
    std::vector<std::string> parts;
    for( const std::string& w : forTaskIdentWords( task ) )
    {
        parts.clear();
        subtokens( w, parts );
        for( std::string& p : parts )
        {
            if( !isRouteStopword( p ) && std::ranges::find( kPlain, std::string_view( p ) ) == std::end( kPlain )
                && std::ranges::find( out, p ) == out.end() )
            {
                out.push_back( std::move( p ) );
            }
        }
    }
    return out;
}

inline constexpr std::size_t kForRankedMessageWords = 2;   // task content words ONE string literal of the seed's own body must hold

// Does ONE string-literal token hold >= kForRankedMessageWords distinct task content words (identifier runs split into subtokens)?
inline bool forLiteralHoldsTaskWords( std::string_view token, const std::vector<std::string>& words )
{
    std::vector<std::string> parts;
    std::vector<char>        hit( words.size(), 0 );
    std::size_t              distinct = 0;
    for( const std::string& run : forTaskIdentWords( token ) )   // the same ident-run split the task's words come through
    {
        parts.clear();
        subtokens( run, parts );
        for( const std::string& p : parts )
        {
            const auto ix = std::size_t( std::ranges::find( words, p ) - words.begin() );
            if( ix < words.size() && hit[ix] == 0 )
            {
                hit[ix] = 1;
                if( ++distinct >= kForRankedMessageWords )
                {
                    return true;
                }
            }
        }
    }
    return false;
}

// Does [sigStartByte, endByte) of `s` in `src` hold such a literal? Read with THE one code scanner (clones.h scanCodeTokens: comments
// dropped, per-language quote rules); a backtick raw string is not read (a floor: such a seed falls to the statement-only fallback).
inline bool forBodyHoldsTaskMessage( const std::string& src, const Symbol& s, const std::vector<std::string>& words )
{
    bool found = false;
    scanCodeTokens( src, s.sigStartByte, s.endByte, stringAwareScanOptions( s.lang, /*munchMultiByteOperators=*/false ),
                    [ & ]( std::string_view token, CodeTokenKind kind )
                    { found = found || ( kind == CodeTokenKind::String && forLiteralHoldsTaskWords( token, words ) ); } );
    return found;
}

// The files the seed's bodies are read from: each file once (at most kForRankedHopHeadRows), "" when unreadable (no message found there).
struct ForRankedSources
{
    std::vector<std::pair<std::uint32_t, std::string>> files;

    const std::string& of( const IngestResult& ing, std::uint32_t fileId )
    {
        auto f = std::ranges::find( files, fileId, &std::pair<std::uint32_t, std::string>::first );
        if( f == files.end() )
        {
            files.emplace_back( fileId, docparse::detail::readWholeFile( diskPath( ing, fileId ) ).value_or( std::string() ) );
            f = std::prev( files.end() );
        }
        return f->second;
    }
};

// One r=1..3 head row as a seed: the row's targets (ONE function by the callers verb's own resolution) when it has 1..kForRankedHopMaxCallers
// first-hop rows, not every one a test or bench path (the chain already ends there), not every one matched by name alone (F2: the d=2 rows
// would inherit an unproven receiver — a Go interface method, a duck-typed Python call); else empty.
inline std::vector<NodeId> forRankedSeedAt( const IngestResult& ing, const Graph& g, NodeId id )
{
    if( id >= ing.symbols.size() || !ReceiverEvidence::callableKind( ing.symbols[id].kind ) )
    {
        return {};
    }
    const NodeId              one[]   = { id };
    std::vector<NodeId>       targets = forCallerHopTargets( ing, g, one );
    if( targets.empty() )
    {
        return {};
    }
    const std::vector<NodeId> first = oneHopCallerRows( ing, g, targets );
    if( first.empty() || first.size() > kForRankedHopMaxCallers )
    {
        return {};
    }
    const bool allTests = std::all_of( first.begin(), first.end(), [ & ]( NodeId c )
                                       { return pathTierOf( rootRelPath( ing, ing.symbols[c].fileId ) ) == PathTier::TestOrBench; } );
    if( allTests )
    {
        return {};
    }
    const OneHopAttribution attr = attributeOneHopAnswer( ing, g, targets, first, /*towardMatches=*/true );
    for( std::size_t k = 0; k < first.size(); ++k )
    {
        if( !attr.nameOnly( k ) )
        {
            return targets;
        }
    }
    return {};
}

// The seed: among the eligible rows (forRankedSeedAt) of the rows <sigs> emitted at r=1..kForRankedHopHeadRows, the first whose own
// body holds a string literal with >= 2 task words (F5: the function that raises the message); with none, the first eligible row,
// but only for a statement, never a question.
inline std::vector<NodeId> forRankedCallerHopTargets( const IngestResult& ing, const Graph& g, std::span<const NodeId> rankedHead,
                                                      std::string_view task )
{
    const std::vector<std::string> words = forTaskContentWords( task );
    std::vector<NodeId>            fallback;
    ForRankedSources               sources;
    for( std::size_t i = 0; i < rankedHead.size() && i < kForRankedHopHeadRows; ++i )
    {
        std::vector<NodeId> targets = forRankedSeedAt( ing, g, rankedHead[i] );
        if( targets.empty() )
        {
            continue;
        }
        const bool holds = words.size() >= kForRankedMessageWords
                        && std::ranges::any_of( targets, [ & ]( NodeId t )
                                                { return forBodyHoldsTaskMessage( sources.of( ing, ing.symbols[t].fileId ), ing.symbols[t], words ); } );
        if( holds )
        {
            return targets;
        }
        if( fallback.empty() )
        {
            fallback = std::move( targets );
        }
    }
    return forTaskIsQuestion( task ) ? std::vector<NodeId>{} : fallback;
}

// The hop's legend clauses, present-only beside the element: the full dialect's and the compact dialect's. No "--": they ride
// inside an XML comment.
inline constexpr std::string_view kForCallerHopLegend =
    "; callers of=: the route named one function, so its callers follow its definition: s t= n= sc= p=file:line rows are its "
    "1-hop callers (n=Owner.name with no sc= on a member whose owner the index defines, as the callers verb prints it; sites_at= their calls of it as file:line, sites_total= when that list was cut; via=name: matched by name "
    "alone, the receiver unproven), shown= of total=; then d=2 rows, callers of the shown callers by rank, d2_shown= of d2=; "
    "capped=1 when either hop was cut; counts are floors (resolved calls only); next= lists the whole caller radius";
inline constexpr std::string_view kForCompactCallerHopLegend =
    "; callers of=: the one function's 1-hop callers, s t= n= sc= p=file:line (n=Owner.name folds sc= on a member; sites_at= its call sites, sites_total= if cut; "
    "via=name by name only), shown= of total=; d=2 rows: their callers, d2_shown= of d2=; capped=1 if cut; floors; next= the radius";

// UPWARD-2HOP: the ranked seed's clauses (by="rank" on the element). Self-contained — the named-route clause never rides with them.
inline constexpr std::string_view kForRankedCallerHopLegend =
    "; callers by=rank of=: the task names an error, not a function, so of= is an r=1..3 row that is one function with 1 to "
    "3 callers (the first whose body holds the task's words in one string, else the first; found by rank, a lead to check), and the chain above it follows: s t= n= sc= p=file:line rows are its 1-hop callers "
    "(n=Owner.name with no sc= on a member whose owner the index defines; sites_at= their calls of it as file:line, sites_total= when "
    "that list was cut; via=name: matched by name alone, the receiver unproven), shown= of total=; then d=2 rows, callers of the "
    "shown callers by rank, d2_shown= of d2=; capped=1 when either hop was cut; counts are floors (resolved calls only); next= lists "
    "the whole caller radius";
inline constexpr std::string_view kForCompactRankedCallerHopLegend =
    "; callers by=rank of=: an error task's r=1..3 row that is one function with 1-3 callers (the first with the task's words in a body string, else the first; a lead by rank): its callers, s t= n= "
    "sc= p=file:line (n=Owner.name folds sc= on a member; sites_at= its call sites, sites_total= if cut; via=name by name only), "
    "shown= of total=; d=2 rows: their callers, d2_shown= of d2=; capped=1 if cut; floors; next= the radius";

struct CallerHopRender
{
    std::string xml;   // <callers …>…</callers>; empty when there is no target or the render failed
};

// The rows' shared rendering inputs: the index, the single-root run's own root (empty: p= keeps ingest's spelling) and the escape buffer.
struct CallerHopRowCtx
{
    const IngestResult& ing;
    const MemberOwners& owners;   // QUALNAME-1: one owner pass per answer, the rule --callers prints n= by
    std::string_view    rootArg;
    std::vector<char>&  esc;
};

// One <s> row: kind, name, scope (when it has one), the root-relative definition site, then the row's extra attributes. A member
// whose owner the index defines prints n="Owner<sep>name" exactly as the callers verb does and folds sc= into it (serialize.h
// sigRowHead's rule); every other scoped row keeps n= bare and sc=.
inline void appendCallerHopRow( std::string& x, const CallerHopRowCtx& c, NodeId id, std::string_view extra )
{
    const IngestResult&    ing = c.ing;
    std::vector<char>&     esc = c.esc;
    const Symbol&          s   = ing.symbols[id];
    const std::string_view rp  = c.rootArg.empty() ? std::string_view( ing.files[ s.fileId ] ) : sarif::rootRelativeUri( ing.files[ s.fileId ], c.rootArg );
    x += "<s t=\"";
    x += symTag( s.kind );
    const std::string_view owner = c.owners.ownerOf( s );
    x += "\" n=\"";
    x += escapeXml( qualifiedMemberName( owner, s ), esc );
    if( owner.empty() && !s.scope.empty() )
    {
        x += "\" sc=\"";
        x += escapeXml( s.scope, esc );
    }
    x += "\" p=\"";
    x += escapeXml( rp, esc );
    x += ':';
    x += std::to_string( s.line );
    x += '"';
    x += extra;
    x += "/>";
}

// The second hop: the callers of the shown first-hop rows that are neither a target nor a first-hop row, in oneHopCallerRows'
// order (tier, path, rank before the cap). Every first-hop row is excluded, shown or not: it is already counted in total=.
inline std::vector<NodeId> callerHopSecondRows( const IngestResult& ing, const Graph& g, std::span<const NodeId> targets,
                                                std::span<const NodeId> firstAll, std::span<const NodeId> firstShown )
{
    std::vector<char> known( ing.symbols.size(), 0 );
    for( const NodeId id : targets )
    {
        known[id] = 1;
    }
    for( const NodeId id : firstAll )
    {
        known[id] = 1;
    }
    std::vector<NodeId> out;
    for( const NodeId id : oneHopCallerRows( ing, g, firstShown ) )
    {
        if( !known[id] )
        {
            out.push_back( id );
        }
    }
    return out;
}

// The element. `rootArg` is the single-root run's own root (empty under multi-root: p= keeps ingest's spelling), as every --for row.
// `ranked` (UPWARD-2HOP): the seed came from forRankedCallerHopTargets, and the element says so (by="rank", its own clause).
inline CallerHopRender renderForCallerHop( const IngestResult& ing, const Graph& g, std::span<const NodeId> targets, std::string_view rootArg,
                                           bool ranked = false )
{
    CallerHopRender out;
    if( targets.empty() )
    {
        return out;
    }
    const std::vector<NodeId>     first      = oneHopCallerRows( ing, g, targets );
    const std::size_t             firstShown = std::min( first.size(), kForCallerHopRows );
    const std::span<const NodeId> shown      = std::span<const NodeId>( first ).first( firstShown );
    const std::vector<NodeId>     second     = callerHopSecondRows( ing, g, targets, first, shown );
    const std::size_t             secondShown = std::min( second.size(), kForCallerHopDepth2Rows );

    // the callers verb's per-row readings over the shown rows: the call sites (CALLSITE-AT) and the by-name hedge (FE-B)
    const RowCallSites       sites = rowCallSites( ing, targets, shown, VrRender{ !rootArg.empty(), rootArg }, g.keptForwards );
    const OneHopAttribution  attr  = attributeOneHopAnswer( ing, g, targets, shown, /*towardMatches=*/true );
    // the second hop's by-name hedge, as the callers verb on the shown callers prints it (rv-mf1-nx B3): a d=2 row whose every edge
    // into the shown callers is by name alone is receiver-unproven — via="name", exactly the row `--callers=<that caller>` carries
    const std::span<const NodeId> secondShownRows = std::span<const NodeId>( second ).first( secondShown );
    const OneHopAttribution       attr2 = secondShown == 0 ? OneHopAttribution{} : attributeOneHopAnswer( ing, g, shown, secondShownRows, /*towardMatches=*/true );

    const Symbol&     t   = ing.symbols[ targets.front() ];
    const std::string sel = t.scope.empty() ? t.name : t.scope + "::" + t.name;   // the callers verb's own qualified selector
    std::vector<char>     esc;
    const MemberOwners    owners( ing );
    const CallerHopRowCtx rc{ ing, owners, rootArg, esc };
    std::string&          x = out.xml;
    x.reserve( 160 + ( firstShown + secondShown ) * 112 );
    x += ranked ? "<callers by=\"rank\" of=\"" : "<callers of=\"";
    x += escapeXml( sel, esc );
    x += "\" shown=\"" + std::to_string( firstShown ) + "\" total=\"" + std::to_string( first.size() ) + "\" capped=\"";
    x += ( firstShown < first.size() || secondShown < second.size() ) ? "1" : "0";
    x += "\"";
    if( !second.empty() )
    {
        x += " d2=\"" + std::to_string( second.size() ) + "\" d2_shown=\"" + std::to_string( secondShown ) + "\"";
    }
    x += nextAttrXml( nextFlag( "--impact=", sel ) );
    x += '>';
    for( std::size_t i = 0; i < firstShown; ++i )
    {
        const std::string extra = std::string( viaNameAttr( attr.nameOnly( i ) ) ) + callSitesAttrXml( sites.tokens[i], sites.totals[i] );
        appendCallerHopRow( x, rc, shown[i], extra );
    }
    for( std::size_t i = 0; i < secondShown; ++i )
    {
        appendCallerHopRow( x, rc, second[i], std::string( " d=\"2\"" ) + viaNameAttr( attr2.nameOnly( i ) ) );
    }
    x += "</callers>";
    return out;
}

}   // namespace rw
