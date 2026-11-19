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
// definition; capped="1" with next= the first one not shown when more than kKeyBodyMax were keyed. A body the page already carries is
// not repeated.
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

// At most this many key bodies on one answer (the question names one or two symbols; a third is a list, not a key).
inline constexpr std::size_t kKeyBodyMax = 2;
static_assert( kHopBodyCapBytes == 4000 && kKeyBodyMax == 2, "the key-body legend spells both bounds: re-word it with the knobs" );

// The block's own legend comment (the house convention: it travels with its block, foranswerfirst.h declaredBlock). No "--".
inline constexpr std::string_view kKeyBodyLegend =
    "<!-- bodies of=key: the definition body of each symbol the question names in backticks (at most 2), b t= l= p= n= as expand "
    "prints it, no callee rows, whole up to 4000 B (a longer one is cut: truncated=1 lines= next=); shown= of total= definitions, "
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
    std::vector<NodeId> out;
    for( const NodeId id : subject_detail::placeCandidates( ing, { sp } ).front() )
    {
        const Symbol& s = ing.symbols[ id ];
        if( s.kind != SymKind::ModuleScope && s.endByte > s.sigEndByte && subject_detail::sourceClassDef( ing, id ) )
        {
            out.push_back( id );
        }
    }
    return out.size() <= kSubjectMaxDefs ? out : std::vector<NodeId>{};
}

// Does `served` (bytes of the answer) already hold a <b> of this definition: same p= and l=?
inline bool bodyServed( std::string_view served, std::string_view path, std::size_t line )
{
    const std::string p = " p=\"" + std::string( path ) + "\"";
    const std::string l = " l=\"" + std::to_string( line ) + "\"";
    for( std::size_t at = served.find( "<b " ); at != std::string_view::npos; at = served.find( "<b ", at + 3 ) )
    {
        const std::string_view tag = served.substr( at, served.find( '>', at ) - at );
        if( tag.find( p ) != std::string_view::npos && tag.find( l ) != std::string_view::npos )
        {
            return true;
        }
    }
    return false;
}

struct KeyBodies
{
    std::string xml;            // <bodies of="key" …>…</bodies>; empty when no key span is keyed or none rendered
    std::size_t shown = 0;
};

// Per key span: its definitions not already in `served`, a multi-line body ahead of a one-line one (a Python @overload stub `...`, a
// declaration-shaped one-liner), NodeId order within each — so the slot goes to the body that does the work.
inline std::vector<std::vector<NodeId>> keyCandidates( const IngestResult& ing, std::string_view task, std::string_view first, std::string_view served,
                                                       std::string_view rootArg )
{
    std::vector<std::vector<NodeId>> perSpan;
    for( const std::string& span : keySpans( task, first ) )
    {
        std::vector<NodeId> defs;
        for( const NodeId id : keyDefs( ing, span ) )
        {
            const Symbol&     s    = ing.symbols[ id ];
            const std::string path = rootArg.empty() ? std::string( ing.files[ s.fileId ] )
                                                     : std::string( sarif::rootRelativeUri( ing.files[ s.fileId ], sarif::rootPrefixOf( rootArg ) ) );
            if( !bodyServed( served, path, s.line ) )
            {
                defs.push_back( id );
            }
        }
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

// The key-body element for `task`. `first`: the routed spelling ("" on an unrouted answer). `served`: bytes the page already carries
// (a body there is not repeated). `rootArg`: the single root the answer's paths are relative to ("" otherwise), as every --for body.
inline KeyBodies keyBodies( const IngestResult& ing, std::string_view task, std::string_view first, std::string_view served, std::string_view rootArg )
{
    const std::vector<RouteBody> want = roundRobin( keyCandidates( ing, task, first, served, rootArg ) );
    if( want.empty() )
    {
        return {};
    }
    const RouteBodiesXml r = routeBodiesXml( ing, want, "key", {}, kKeyBodyMax, rootArg );
    return { r.xml, r.ids.size() };
}

// THE UNROUTED ANSWER: insert the key block (its legend comment, then the element) right after the first top-level row block of a
// finished answer-first --for document, when that block ends inside the default page. est_tokens= is re-priced: the element at the body
// rate and the legend as markup, exactly through `ledger` when it converged, else at the densest markup rate (an upper bound). Returns
// whether the document changed.
inline bool insertKeyBodies( std::string& doc, const IngestResult& ing, std::string_view task, std::string_view rootArg, const ForAnswerLedger* ledger )
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
    const KeyBodies kb = keyBodies( ing, task, {}, view.substr( 0, std::min( view.size(), answerfirst::kAnswerPageBytesDefault ) ), rootArg );
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
