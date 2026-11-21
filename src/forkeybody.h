#pragma once
// forkeybody.h — KB1, THE KEY-SYMBOL BODY ON PAGE 1 (lane KB1, results/KB1_ACTREADY_1119/PREREG.md): the first page of a --for answer
// carries the definition body of the symbol the question names, right after the block that answers it.
//
// WHY. Answer-first paging (AF1) moved bodies past page 1. In the compare-table turn model (CT2 TABLE_DRAFT §8) complete answers
// that carry the question's key-symbol BODY fell from 17 of 45 (published) to 2 of 36 (the answer-first rehearsal), and in the PG6
// agent sessions the next action after a ripwire call was a Read of a file the answer named 18 of 28 times: the agent opens the
// file to see the code the answer pointed at. A body on page 1 makes the answer one an agent can act on without that turn.
//
// THE KEY SYMBOLS of a question: its backtick spans that spell an identifier path (`a`, `a.b`, `a::b`, `a#b`; a trailing `()` or `!`
// dropped — forroute.h's own span reader), rule E2's symbol first (the routed verb's spelling when a route answered), then the
// others in question order, each once. A span is KEYED when it places 1..kSubjectMaxDefs bodied SOURCE definitions (subjectanchor.h
// placeCandidates / sourceClassDef: never a test, tool, vendored or non-source file, never a bodyless declaration or a module scope);
// a span that places none, or a namesake flood, has no body here. At most kKeyBodyMax bodies ride: round robin over the key spans (each
// symbol's first body before any symbol's second), within a span a multi-line body before a one-line one (an @overload stub), then NodeId.
//
// THE BLOCK. ONE <bodies of="key" shown= total= capped= [next=]> through the ONE route-body printer (hopbody.h routeBodiesXml: each
// <b t= l= p= n=> is the --expand body element, no callee rows, no file context, whole up to kHopBodyCapBytes; a longer one is cut at a
// line end and says so on the element: truncated="1" lines="1-K/T" next= the --expand of the lines not shown). total= counts every keyed
// definition; capped="1" with next= the first one not shown when more than kKeyBodyMax were keyed. THE GROUP CARRIES ITS OWN BODY:
// a body served elsewhere on the same page does not satisfy this contract, so the same (p=, l=) appearing both here and in a row
// section or the fold is correct and is pinned by forkeybodycheck K12 (owner ruling 87, 2026-11-20). It replaces the earlier rule
// that a body the page already carried was not repeated — see the note on the removal of the `served` argument below.
//
// WHERE IT GOES.
//   * a ROUTED answer (verbs_forroute.h assembleRouted — the CLI's and MCP `for`'s, so both surfaces carry it): the root's child
//     right after the verb's own rows and the fold, before a carried --for page. A routed answer is one call, never paged.
//   * the unrouted answer-first --for answer (verbs_for.h runForLens, after the permutation and SIGX, before ES and paging): directly
//     after the FIRST top-level row block (the leading <callers by="subject"> when T-B leads it, else whatever answer-first put first),
//     glued behind its own legend comment. Only when that block ends inside the default page (answerfirst::kAnswerPageBytesDefault):
//     a body that could not be on page 1 is not added. PAGE 1 DOES NOT COUNT IT: forpages.h measures the page the key group starts on
//     (page 1 at the default size) without it, so that page ends at the same row it ended at without it, the group is never split,
//     and every other page is the same rows — no row is pushed off page 1 by a body (zero flips by construction). ES (RT2's early page 1) carries it when it directly follows the proven leading block.
//   Not under --legend=first, a token budget (the fit priced the bytes), --signatures-only, or a non-XML format.
// est_tokens= is re-priced over the added bytes (the block at the body rate, exactly through the render's ledger when it converged).
// RIPWIRE_NO_KEY_BODY (any value) turns it off — the A/B handle, the RIPWIRE_NO_BODY_FOLD precedent.
//
// SUBSUMES TL1 M3 (d12a7b1ca, "a late asked <bodies> leads the tail"): M3 moved a whole late <bodies> ahead of the tail and FAILED its
// T5e confirmation because the moved body still did not fit page 1 (he-fastify-01). Here the body is bounded, placed after the answer,
// and page 1 is measured without it, so it is always on page 1; M3 is reverted.

#include "foranswerfirst.h"   // rootBody, topLevelBlocks, kAnswerPageBytesDefault
#include "compactlegend.h"    // repriceEstTokensIn — the added-bytes reprice without a ledger
#include "forbudgetfit.h"     // ForAnswerLedger
#include "forpages.h"         // kKeyBodyLegendLead — page 1 does not count the group it opens
#include "forroute.h"         // forEachBacktickSpan, trimCallSuffix, isIdentPath, extractSymbol — rule E's span reader
#include "hopbody.h"          // routeBodiesXml, RouteBody, kHopBodyCapBytes — the one body printer
#include "model.h"
#include "serialize.h"        // repriceRootAfterCut, tokensForEmittedBytes, kBytesPerTokenBody
#include "subjectanchor.h"    // subject_detail::parseSpelling, placeCandidates, sourceClassDef, kSubjectMaxDefs

#include <algorithm>
#include <cstddef>
#include <cstdlib>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace rw::keybody
{

// At most this many key bodies on one answer. CB1 raised this from 2, and the number is DERIVED, not picked:
// on GA1's DEV half (89 tasks, MEASURED) the gold functions per task run median 1, q75 3, p90 5, max 12, so a
// cap of 2 could satisfy only 71.9% of tasks while 5 satisfies 94.4%. The guard therefore sits at the
// distribution's p90, where it is not the binding constraint for 19 tasks in 20, and the BYTE BUDGET is what
// actually bounds the block (the brief's rule: the budget is the cap, not a count).
// HONESTY ABOUT THE PREMISE. The case for lifting this cap was "the median task has 3 gold files, so 2 cannot
// satisfy it". On GA1 that premise does NOT hold: its DEV median is 1 gold file and 1 gold function per task,
// and only 28.1% of tasks need 3 or more functions. So this raise helps a real minority, not a majority, and
// CB1's readout says so rather than inheriting the stronger claim.
inline constexpr std::size_t kKeyBodyMax = 5;   // key bodies one answer carries; past it the block says capped="1" and next= the first not shown
static_assert( kHopBodyCapBytes == 4000 && kKeyBodyMax == 5 && kCappedBodyLines == 120,
               "the key-body legend spells all three bounds: re-word it with the knobs" );

// The block's own legend comment (the house convention: it travels with its block, foranswerfirst.h declaredBlock). No "--".
inline constexpr std::string_view kKeyBodyLegend =
    "<!-- bodies of=key: the definition body of each symbol the question names in backticks (at most 5), b t= l= p= n= as expand "
    "prints it, no callee rows, whole up to 120 lines and 4000 B (a longer one is cut: truncated=1 lines= next=, and cap_lines=120 "
    "when the LINE cap is what cut it); shown= of total= definitions, "
    "capped=1 next= the first not shown; page 1 does not count these bytes -->";

static_assert( kKeyBodyLegend.starts_with( forpages::detail::kKeyBodyLegendLead ), "forpages.h finds the key group by its legend's lead" );

inline bool keyBodyOn() noexcept { return std::getenv( "RIPWIRE_NO_KEY_BODY" ) == nullptr; }

// The key spans of `task`: `first` (the routed spelling, or rule E2's symbol) then every other identifier-path span in order, each once.
inline std::vector<std::string> keySpans( std::string_view task, std::string_view first )
{
    std::vector<std::string> out;
    const auto add = [ & ]( std::string_view s )
    {
        if( !s.empty() && std::ranges::find( out, s ) == out.end() )
        {
            out.emplace_back( s );
        }
    };
    add( first.empty() ? std::string_view( forroute::extractSymbol( task ) ) : first );
    forroute::detail::forEachBacktickSpan( task, [ & ]( std::string_view raw )
    {
        const std::string_view span = forroute::detail::trimCallSuffix( raw );
        if( forroute::detail::isIdentPath( span ) )
        {
            add( span );
        }
    } );
    return out;
}

// The bodied source definitions one span places, NodeId order; empty when it places none or a namesake flood (> kSubjectMaxDefs).
inline std::vector<NodeId> keyDefs( const IngestResult& ing, std::string_view span )
{
    std::string spelled( span );
    std::ranges::replace( spelled, '#', '.' );   // Ruby's Class#method reads as a qualified spelling
    const subject_detail::Spelling sp = subject_detail::parseSpelling( spelled );
    if( !sp.valid )
    {
        return {};
    }
    std::vector<NodeId>                    out;
    const std::vector<std::vector<NodeId>> placed = subject_detail::placeCandidates( ing, { sp } );   // named: a range-for over a temporary's element dangles on GCC 13/14
    for( const NodeId id : placed.front() )
    {
        const Symbol& s = ing.symbols[ id ];
        if( s.kind != SymKind::ModuleScope && s.endByte > s.sigEndByte && subject_detail::sourceClassDef( ing, id ) )
        {
            out.push_back( id );
        }
    }
    return out.size() <= kSubjectMaxDefs ? out : std::vector<NodeId>{};
}

// OWNER RULING 87 (2026-11-20) removed `bodyServed( served, path, line )` and the `served` argument that fed it from here.
// It answered "does the answer's first page already hold a <b> of this definition, same p= and l=?", and keyCandidates dropped
// every definition for which it said yes. The ruling is that the key group must carry its OWN body and that a body served
// elsewhere on the same page does not satisfy the contract, so that question has no remaining customer: a definition the question
// names in backticks rides whatever else the page serves. The suppression was one argument wide and only ONE of the three call
// sites ever supplied it (insertKeyBodies, the unrouted path) — the routed path and the --pack-task twin always passed {}, so the
// contract was already honoured there and the two paths now agree. Keeping the parameter unused would have left a dead predicate
// that a later call site could re-arm by accident; it is gone instead, which makes the contract structural.
// What this costs is a deliberate duplicate on one page, measured in results/K87_CONTRACT_1120/READOUT.md §5.

struct KeyBodies
{
    std::string xml;            // <bodies of="key" …>…</bodies>; empty when no key span is keyed or none rendered
    std::size_t shown = 0;
};

// Per key span: EVERY definition it places (ruling 87 — what the rest of the page serves is not consulted), a multi-line body ahead
// of a one-line one (a Python @overload stub `...`, a declaration-shaped one-liner), NodeId order within each — so the slot goes to
// the body that does the work.
// `rootArg` went with `served`: the root-relative path was built here only to ask bodyServed about it. The printer still needs it
// and keyBodies still passes it there.
inline std::vector<std::vector<NodeId>> keyCandidates( const IngestResult& ing, std::string_view task, std::string_view first )
{
    std::vector<std::vector<NodeId>> perSpan;
    for( const std::string& span : keySpans( task, first ) )
    {
        std::vector<NodeId> defs = keyDefs( ing, span );
        std::ranges::stable_partition( defs, [ & ]( NodeId id ) { return ing.symbols[ id ].loc > 1; } );
        perSpan.push_back( std::move( defs ) );
    }
    return perSpan;
}

// Round robin over the spans (each named symbol's first body before any symbol's second), key order within a round, each id once.
inline std::vector<RouteBody> roundRobin( const std::vector<std::vector<NodeId>>& perSpan )
{
    std::vector<RouteBody> want;
    std::size_t            longest = 0;
    for( const std::vector<NodeId>& defs : perSpan )
    {
        longest = std::max( longest, defs.size() );
    }
    for( std::size_t round = 0; round < longest; ++round )
    {
        for( const std::vector<NodeId>& defs : perSpan )
        {
            if( round < defs.size() && std::ranges::find( want, defs[ round ], &RouteBody::id ) == want.end() )
            {
                want.push_back( { defs[ round ], {} } );
            }
        }
    }
    return want;
}

// The key-body element for `task`. `first`: the routed spelling ("" on an unrouted answer). `rootArg`: the single root the answer's
// paths are relative to ("" otherwise), as every --for body. What the rest of the page serves is not an input (ruling 87).
// `redact`: the run's redaction tally (nullptr: --no-redact), as every served body takes it (hopbody.h REDACT-TOUCH). The key group
// was written on a line that predates that rule and passed none, so its bodies would have been the one unredacted body path left.
// The 0.7.0 / main merge (2026-11-21) threads it. UNTESTED at the merge: both callers insert the group into a FINISHED document,
// so whether a redaction made here is inside the run's reportRedactions tally depends on where that report ran — the body is
// redacted either way, the count may be short.
inline KeyBodies keyBodies( const IngestResult& ing, std::string_view task, std::string_view first, std::string_view rootArg, RedactCounts* redact )
{
    const std::vector<RouteBody> want = roundRobin( keyCandidates( ing, task, first ) );
    if( want.empty() )
    {
        return {};
    }
    // CB1: the "key" group is the ONE routeBodiesXml caller that opts into the monotone line cap. The hops and
    // route groups keep bodyLineCap=0 and are byte-identical, which is how this change is provable rather than
    // inspected: a cap wired into the shared printer itself would have moved bytes on three other groups.
    const RouteBodiesXml r = routeBodiesXml( ing, want, "key", {}, kKeyBodyMax, rootArg, redact, kCappedBodyLines );
    return { r.xml, r.ids.size() };
}

// PB1: the --pack-task twin's ONE key body — the first definition keyBodies would serve (round robin over the spans takes the first
// span's first definition first), or kNoNode when no span places one or RIPWIRE_NO_KEY_BODY is set. The bundle (packtask.h) falls
// back to its top positive-score head; it cannot include this header, so its callers resolve the pick and hand it in.
// `rootArg` went unused when ruling 87 took the path/`served` comparison out of keyCandidates. The signature is kept so the two
// callers (verbs_for.h, mcpverbs.h) stay the one identical call, and because this pick is root-relative the moment anything here
// needs a path again; it is marked rather than silently dead.
inline NodeId keyBodyFor( const IngestResult& ing, std::string_view task, [[maybe_unused]] std::string_view rootArg )
{
    if( !keyBodyOn() )
    {
        return kNoNode;
    }
    for( const std::vector<NodeId>& defs : keyCandidates( ing, task, {} ) )
    {
        if( !defs.empty() )
        {
            return defs.front();
        }
    }
    return kNoNode;
}

// THE UNROUTED ANSWER: insert the key block (its legend comment, then the element) right after the first top-level row block of a
// finished answer-first --for document, when that block ends inside the default page. est_tokens= is re-priced: the element at the body
// rate and the legend as markup, exactly through `ledger` when it converged, else at the densest markup rate (an upper bound). Returns
// whether the document changed.
inline bool insertKeyBodies( std::string& doc, const IngestResult& ing, std::string_view task, std::string_view rootArg, RedactCounts* redact,
                             const ForAnswerLedger* ledger )
{
    const std::string_view                       view = doc;
    const std::optional<answerfirst::RootBody>   rb   = answerfirst::rootBody( view );
    if( !rb )
    {
        return false;
    }
    const std::vector<answerfirst::Block> blocks = answerfirst::topLevelBlocks( view, rb->openEnd + 1, rb->closeAt );
    const auto first = std::ranges::find_if( blocks, []( const answerfirst::Block& b ) { return !b.comment; } );
    if( first == blocks.end() || first->end > answerfirst::kAnswerPageBytesDefault )
    {
        return false;
    }
    // RULING 87, and this is the line the ruling is about. It used to hand keyBodies the first kAnswerPageBytesDefault bytes of
    // this document as `served`, and keyCandidates dropped every definition whose <b> was already in there — so a fold or row
    // section promoted onto page 1 silently took the key group's own copy away, and which definition it took depended on what the
    // body selector happened to promote. The key group does not consult the page any more: it carries its own body.
    const KeyBodies kb = keyBodies( ing, task, {}, rootArg, redact );
    if( kb.xml.empty() )
    {
        return false;
    }
    const std::size_t pricedBytes = doc.size();
    std::string       out;
    out.reserve( doc.size() + kKeyBodyLegend.size() + kb.xml.size() );
    out.append( view.substr( 0, first->end ) ).append( kKeyBodyLegend ).append( kb.xml ).append( view.substr( first->end ) );
    if( ledger != nullptr && ledger->priced )
    {
        repriceRootAfterCut( out, PricedRootInputs{ ledger->markupBytes, ledger->bodyTokens + tokensForEmittedBytes( kb.xml.size(), kBytesPerTokenBody ) },
                             pricedBytes + kb.xml.size() );
    }
    else
    {
        (void)repriceEstTokensIn( out, 0, out.find( '>', out.find( "<ctx" ) ), pricedBytes, out.size() );
    }
    doc.swap( out );
    return true;
}

}   // namespace rw::keybody
