#pragma once
#include "infra/emit.h"   // house rule: every header that may grow an emitter includes the emit seam
// handoffwindow.h — WINDOW-AWARE HAND-OFF: a --for answer that hands off to --callers or --impact counts that verb's rows FIRST, and
// when the verb's default call would window it appends no page: it states the total and names the one call that lists every row.
//
// WHY. What an agent spends is set by whether one call sufficed, not by the size of the answer. Measured (m5 results
// ROUTING_TOKEN_SAVINGS_1117.md, re-run for this lane on 5139f7840): of 78 --callers / --impact cells over 39 symbols of five
// corpora, 42 window; completing them costs a median 292,807 B through the two-call chain the tool directs (the default page, then
// --offset=<next_offset> --limit=<total>) against 2-4 KB for an answer that fits one call. The window is a function of a row total
// and a cap, and both verbs hold the total before they page, so it is known exactly before a hand-off is made (0 false positives
// and 0 false negatives on those 78). Knowing it does not remove it; it lets the hand-off name the cheapest COMPLETE call instead
// of a first page of 40: the same rows as --format=columnar at --limit=<total>, 71.3 % of the two-call chain's bytes pooled (n=42,
// the ( path, name, line ) rows identical in set, count and order on 42 of 42).
//
// WHAT. Three hand-offs read this header: <graph_verb verb="--callers=X"> (forgraphverb.h; the verb ran, so the window is read off
// its own root), <callers [by=] of=X next="--impact=X"> (forcallerhop.h; impactRowTotal below) and <reask next=…/> (verbs_for.h).
// A windowing hand-off carries windows="1", next_total=N and next="--VERB=X --format=columnar --limit=N"; the legend beside it says
// no page was appended. A hand-off whose verb does not window is byte for byte what it was (RIPWIRE_NO_WINDOW_HANDOFF=1 is the
// whole lane off: the A/B handle, the RIPWIRE_NO_CALLER_HOP precedent).
//
// WHAT IT DOES NOT DO, each for a measured reason:
//   * No proxy. In-degree alone misses 16 of 32 windowed impact cells, the lethal shape among them (cpython
//     _format_call_signature: 2 callers, a reach of 34,876). The total is the verb's own count over the definitions the verb's own
//     resolver binds to the spelling the hand-off names: a total over another definition set is a wrong number in a precise format
//     (24 of the 39 names have more than one definition).
//   * No byte estimate. A constant bytes-per-row lands within 25 % on 11 of 32 impact cells; rows are exact, so rows are stated.
//   * Not --uses, not --grep: 16 of their 38 windows have no graph signature (their totals come from the scan the verb is).
//   * No choice between grains. The complete call is another ENCODING of the rows the hand-off already pointed at, never a cheaper
//     verb: --callers is not offered where --impact was asked because it is smaller.
#include "compactlegend.h"   // spanHasAttr — the ONE attribute-at-a-tag-boundary test
#include "contractseed.h"    // widenContractSeeds — the impact verb's own seed set
#include "graph.h"           // resolveAllByNameQualified — the impact verb's own resolver
#include "infra/tablelookup.h"   // envChoice — the test hook's one-of-N switch
#include "model.h"
#include "nextverb.h"        // nextFlag / nextAttrXml
#include "packtask.h"        // findSectionOpenTag — an element's open tag, comments skipped
#include "pageview.h"        // kCallHierarchyRowCap — the impact page's own default
#include "typeuse.h"         // typeUseTier / impactReachWithTypes — the impact verb's own walk

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
// The A/B switch: the hand-offs are window-aware unless RIPWIRE_NO_WINDOW_HANDOFF is set (any value).
inline bool handoffWindowOn()
{
    return std::getenv( "RIPWIRE_NO_WINDOW_HANDOFF" ) == nullptr;
}

// Test hook (test/handoffwindowcheck.sh, its registered mutation controls): RIPWIRE_TEST_HANDOFF_MUTANT names ONE deliberate defect,
// so the gate shows on the real binary that each of its arms can fail. Unset (every ordinary run): None.
enum class HandoffMutant : std::uint8_t
{
    None,
    Threshold4,    // the impact cap read as 4: a complete small answer is called windowed
    FirstDef,      // the total walked from the first definition only
    LimitMinus1,   // the named call's --limit is one row short
    InDegree,      // the total replaced by the in-degree proxy (the depth-1 count)
    AllNextAlways, // BAND DC: a direct root that does not window carries all_next= all the same (a false positive)
};
inline constexpr std::string_view kHandoffMutantNames[] = { "threshold4", "firstdef", "limitminus1", "indegree", "allnextalways" };   // the enum's order after None
inline HandoffMutant handoffMutant() { return HandoffMutant( envChoice( "RIPWIRE_TEST_HANDOFF_MUTANT", kHandoffMutantNames ) ); }

// What a hand-off knows about the verb it points at: `windows` = the verb's DEFAULT call lists a first page only; `total` = the rows
// the verb holds (meaningful when windows). Default-constructed: not windowing, or not known — either way the hand-off is unchanged.
struct HandoffWindow
{
    std::size_t total   = 0;
    bool        windows = false;
};

// The rows `--impact=<spelling>` holds: the verb's own resolver, contract widening, type tier and walk (verbs_navigate.h runImpact's
// first four calls, in its order), so the count is over the definition set that call answers about. nullopt: the spelling binds
// nothing (the verb refuses, or answers a file path) and the hand-off says nothing about a window.
inline std::optional<std::size_t> impactRowTotal( const IngestResult& ing, const Graph& g, std::string_view spelling )
{
    std::vector<NodeId> matches = resolveAllByNameQualified( ing, spelling );
    if( matches.empty() )
    {
        return std::nullopt;
    }
    const HandoffMutant mutant = handoffMutant();
    if( mutant == HandoffMutant::FirstDef )
    {
        matches.resize( 1 );
    }
    const ContractSeeds contract = widenContractSeeds( ing, g, std::move( matches ) );
    const ImpactReach   walk     = impactReachWithTypes( g, contract.seeds, typeUseTier( ing, contract.seeds ) );
    if( mutant == HandoffMutant::InDegree )
    {
        return std::size_t( std::ranges::count_if( walk.reach, [ & ]( NodeId n ) { return walk.depth[ n ] == 1; } ) );
    }
    return walk.reach.size();
}

// --impact pages its reach at kCallHierarchyRowCap rows, with no band: it windows exactly when it holds more.
inline HandoffWindow impactHandoffWindow( const IngestResult& ing, const Graph& g, std::string_view spelling )
{
    const std::optional<std::size_t> total = handoffWindowOn() ? impactRowTotal( ing, g, spelling ) : std::nullopt;
    const std::size_t                cap   = handoffMutant() == HandoffMutant::Threshold4 ? 4 : std::size_t( kCallHierarchyRowCap );
    return total && *total > cap ? HandoffWindow{ *total, true } : HandoffWindow{};
}

// The value of attribute `name` in one printed tag or row (its escaped bytes; "" when absent).
inline std::string_view printedAttrOf( std::string_view row, std::string_view name )
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

// --callers decides its own window (the 1.25x row band, then the 16,000 B byte band over every row it would print: pageview.h), so a
// hand-off reads it off the root of the verb's captured DEFAULT answer rather than re-deriving the band: has_more="1" and total=.
// `element` is the root's open ("<callers "). A document with no such root, or a root that does not window → not windowing.
inline HandoffWindow handoffWindowOfVerbDoc( std::string_view doc, std::string_view element )
{
    const SectionOpenTag tag = findSectionOpenTag( doc, element );
    if( !handoffWindowOn() || tag.start == std::string::npos )
    {
        return {};
    }
    const std::string_view root = doc.substr( tag.start, tag.end - tag.start );
    if( !spanHasAttr( root, "has_more", "\"1\"" ) )
    {
        return {};
    }
    std::size_t total = 0;
    for( const char c : printedAttrOf( root, "total" ) )
    {
        if( c < '0' || c > '9' )
        {
            return {};   // a total that is not a number is not a total: the hand-off stays as it was
        }
        total = total * 10 + std::size_t( c - '0' );
    }
    return total > 0 ? HandoffWindow{ total, true } : HandoffWindow{};
}

// The one call that lists every row of a windowing verb: the same rows in columnar form, at the limit that is their count.
inline std::string completeCallInvocation( std::string_view flag, std::string_view selector, std::size_t total )
{
    const std::size_t limit = handoffMutant() == HandoffMutant::LimitMinus1 ? total - 1 : total;
    return nextFlag( flag, selector ) + " --format=columnar --limit=" + std::to_string( limit );
}

// ── BAND DC (docs/EVALS.md, pre-registration 2026-11-17 amendment 10): the DIRECT roots ─────────────────────────────────────────────
// The three hand-offs above point a --for reader at the complete call. An agent that calls --callers or --impact itself got a
// first page whose next= names the next page of 40 (callers) or another verb (impact), and no pointer to the one call that lists
// every row. A root that windows now says it: all_next="--VERB=X --format=columnar --limit=N" (verbs_navigate.h, the MCP twins).
// NO PREDICTION is made here: `windows` is the page window the verb has just computed for the answer it is printing, so the
// attribute rides exactly the roots that carry has_more="1" (0 false positives and 0 false negatives by construction;
// test/dccolumnarcheck.sh P1 counts both). N is the row total, the hand-offs' own rule. NOT the larger of the rows and the
// declined call sites (registered, measured, withdrawn: amendment 10b): --limit sizes the declined-site cut too, and a limit
// that cleared it listed 61,381 more hedge rows on 12 of the 32 windowed impact cells of the registered population — 99 rows
// and 4,005 declined sites on one — taking the median bytes to a complete answer from 77,821 to 145,532. The named call
// therefore lists every ROW; where it holds more declined sites it says so (shown_dc=) and dc_next= names the call that
// lists them all, in the same form. "" when the page is the whole answer, or the lane is off.
inline std::string directRootAllNext( std::string_view flag, std::string_view selector, bool windows, std::size_t rowTotal )
{
    const bool on = handoffWindowOn() && ( windows || handoffMutant() == HandoffMutant::AllNextAlways );
    return on ? completeCallInvocation( flag, selector, rowTotal ) : std::string();
}

// Its clause, exactly beside the attribute (`allNext` is directRootAllNext's value). A trailing space: it joins a clause run.
inline constexpr std::string_view kAllNextLegend =
    "all_next=: the ONE call that lists every row of total=, the same rows in columnar form (a page at next_offset= lists only the "
    "next shown=). ";
inline std::string_view allNextLegend( std::string_view allNext ) noexcept
{
    return allNext.empty() ? std::string_view() : kAllNextLegend;
}

// ` windows="1" next_total="N" next="--VERB=X --format=columnar --limit=N"` for a windowing hand-off; the plain ` next="--VERB=X"`
// otherwise (the bytes a hand-off printed before this lane).
inline std::string handoffNextAttrsXml( std::string_view flag, std::string_view selector, const HandoffWindow& w )
{
    if( !w.windows )
    {
        return nextAttrXml( nextFlag( flag, selector ) );
    }
    return " windows=\"1\" next_total=\"" + std::to_string( w.total ) + "\"" + nextAttrXml( completeCallInvocation( flag, selector, w.total ) );
}

// The clauses, present only beside a windowing hand-off. No "--": they ride inside an XML comment.
// The <callers> hop's (its next= is the impact verb): appended to the hop's own clause in the --for header.
inline constexpr std::string_view kForWindowHandoffLegend =
    "; windows=1 on callers: the radius call next= used to name lists only a first page (40 rows) of next_total= rows, so NO page of it "
    "is pointed at: next= is the one call that lists every row, the same rows in columnar form at that limit; next_total= is the impact "
    "verb's own count for the definitions next= binds, a floor like every count here";
inline constexpr std::string_view kForCompactWindowHandoffLegend =
    "; windows=1: the radius call lists only a first page of next_total= rows (the impact verb's own count, a floor), so no page is "
    "pointed at: next= lists them all, columnar";
// A windowing <graph_verb> / <reask>: appended inside that block's own comment.
inline constexpr std::string_view kWindowHandoffBlockLegend =
    "; windows=\"1\": the verb's default call lists only a first page of next_total= rows, so NO page is appended here (rows withheld and "
    "said so, not absent): next= is the one call that lists every row, the same rows in columnar form at that limit; next_total= is the "
    "verb's own count over the definitions it binds to this spelling, a floor (counts_floor=\"1\": resolved calls only)";
}   // namespace rw
