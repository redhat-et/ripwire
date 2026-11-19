// forlegendentries.h — the CLI `--for` document legend as LEGEND-DICTIONARY ENTRIES (lane LS1, 2026-11-18).
//
// A SECTION of main.cpp, included once, right after verbs_for.h (RIPWIRE_MAIN_TU): most of these clauses are
// constants of that section's unnamed namespace, and legenddict.h cannot include it (legenddict.h's kForDocEntries
// says why). Each row is the constant ITSELF, never a copy of its text, so a reworded clause moves its entry and
// dictv= with it and cannot drift away from what the answer says.
//
// WHICH CLAUSES. The ones measured riding a default --for page 1 (results/LS1_LEGENDSEEN_1118/constscan.py on a dev
// set of 10 answers on 6 corpora, none of them the measured sessions: 36.9 KB of 41.4 KB of comment bytes) plus the
// rest of the compact dialect's present-only clauses, which ride only when their rows do. A clause left out of this
// table costs bytes, never a reading: legendseen.h removes only text that IS an entry, so an unlisted clause simply
// stays in every answer. Clauses that already were entries (the MCP `for` dialect's kForClauseEntries: the route
// codes, the root-relative prose, the budget/docs/sigs notes) are not listed twice.
//
// ORDER IS THE ID ORDER, and the ids are part of nothing a caller holds (a caller holds HASHES of the lines,
// legendseen.h), but they decide the dictionary's line order and so dictv=. Append; do not reorder without reason.
#pragma once

#ifndef RIPWIRE_MAIN_TU
#error "forlegendentries.h is a section of main.cpp (it reads verbs_for.h's unnamed-namespace constants)"
#endif

#include <string>
#include <string_view>

#include "forpages.h"   // pageClause, kForPageBytesDefault
#include "legenddict.h"

namespace
{

// A legend constant spelled as a WHOLE comment ("<!-- demote: … -->"): its entry is the text between the markers, the
// bytes legendseen.h finds inside the comment.
constexpr std::string_view commentBody( std::string_view whole ) noexcept
{
    constexpr std::string_view kOpen = "<!-- ";
    constexpr std::string_view kClose = " -->";
    if( whole.starts_with( kOpen ) ) { whole.remove_prefix( kOpen.size() ); }
    if( whole.ends_with( kClose ) ) { whole.remove_suffix( kClose.size() ); }
    return whole;
}

// The page clause at the DEFAULT page size: its text carries the size, so a caller paging at another size meets a
// clause that is no entry and keeps it inline — a missed saving, never a wrong reading.
const std::string kForDocPageClause = rw::forpages::detail::pageClause( rw::forpages::kForPageBytesDefault );

const std::string_view kForDocList[] =
{
    // verbs_for.h — the compact dialect's spine, in the order appendCompactForLegend writes it
    commentBody( kForCompactLegendRoot ),
    commentBody( kForCompactLegendRows ),
    commentBody( kForCompactLegendRowsNoScope ),
    commentBody( kForCompactLegendFacts ),
    commentBody( kForCompactLegendConfidence ),
    commentBody( kForCompactLegendHops ),
    commentBody( kForCompactLegendBodies ),
    commentBody( kForCompactLegendOwner ),
    commentBody( kForCompactLegendBodySlot ),
    commentBody( kForCompactHopsCallsNextClause ),
    commentBody( kForCompactLegendTail ),
    commentBody( kForCompactLegendTailCodeFirst ),
    commentBody( kForCompactLegendTailWide ),
    commentBody( kForCompactLegendHdr ),
    commentBody( kForCompactLegendCompose ),
    commentBody( kForCompactLegendLego ),
    commentBody( kForCompactLegendLayer ),
    // the present-only riders from the for*.h headers
    commentBody( rw::kForCompactCoverageClause ),
    commentBody( rw::kForCompactMemberNamesLegend ),
    commentBody( rw::kForCompactBodyFoldLegend ),
    commentBody( rw::kForCompactBodyFoldMembersClause ),
    commentBody( rw::kForCompactFoldFollowLegend ),
    commentBody( rw::kForCompactCtorHopLegend ),
    commentBody( rw::kForCompactSlotJoinLegend ),
    commentBody( rw::kForCompactSlotNameLegend ),
    commentBody( rw::kForCompactInitSlotsLegend ),
    commentBody( rw::kForCompactFileTailTermsLegend ),
    commentBody( rw::kForCompactFileTailFoldedLegend ),
    commentBody( rw::kForCompactSameAsLegend ),
    commentBody( rw::kForCompactEndLineLegend ),
    commentBody( rw::kForCompactViaNameClause ),
    commentBody( rw::kForCompactModScopeClause ),
    commentBody( rw::kForCompactSplitClause ),
    commentBody( rw::kForHopValueRefsClause ),
    commentBody( rw::kForCompactUnusedLegend ),
    commentBody( rw::kForCompactListedInLegend ),
    commentBody( rw::kForCompactEpManifestLegend ),
    commentBody( rw::kForCompactRegLegend ),
    commentBody( rw::kForCompactFilePageLegend ),
    commentBody( rw::kForCompactDispatchHopLegend ),
    commentBody( rw::kForCompactCallerHopLegend ),
    commentBody( rw::kForCompactRankedCallerHopLegend ),
    commentBody( rw::kForCompactSubjectCallerHopLegend ),
    commentBody( rw::kForCompactLiteralLegend ),
    commentBody( rw::kForCompactLiteralCutLegend ),
    commentBody( rw::kForCompactLiteralBodyClause ),
    commentBody( rw::kForCompactSelfHookLegend ),
    commentBody( rw::kForCompactWindowHandoffLegend ),
    // the notes the root-relative comment carries, and the two whole-comment legends
    commentBody( rw::kForBudgetBytesTargetNote ),
    commentBody( rw::kForPastTargetNote ),
    commentBody( rw::kForFilesFirstNote ),
    commentBody( rw::kForDocsAfterCodeNote ),
    commentBody( rw::kForSigsNextNote ),
    commentBody( rw::kForFoldSigsNextNote ),
    commentBody( rw::kForSectionStubLegend ),
    commentBody( rw::kSiblingDemoteLegend ),
    commentBody( rw::kDeclTwinLegend ),
    // the BLOCK-LOCAL legends: a --for section carries its own "<!-- ripwire for X …" with it (AF1-fix), so a held one
    // must be left out where it stands — on page 1 or on the later page its block lands on
    commentBody( rw::kForDeclLegend ),
    commentBody( rw::kForFileSymsLegend ),
    commentBody( rw::kForFileSymsHeldLegend ),
    commentBody( rw::kForDocBodyLegend ),
    commentBody( rw::kForDottedStringsLegend ),
    commentBody( rw::kReaderCallersLegend ),
    commentBody( rw::kForExemplarFamilyCompactLegend ),
    commentBody( rw::kForExemplarNoFamilyLegend ),
    commentBody( rw::kForManifestRowsCompactLegend ),
    commentBody( rw::kForLiteralKeyLegend ),
    commentBody( rw::kForLiteralCapLegend ),
    commentBody( rw::kForLiteralTableLegend ),
    commentBody( rw::kForLiteralStrongLegend ),
    commentBody( rw::kForLiteralFlagLegend ),
    commentBody( rw::kForLiteralFlagTryLegend ),
    commentBody( rw::kForLiteralArmLegend ),
    commentBody( rw::kForLiteralTailLegend ),
    commentBody( rw::kForLiteralSubscriptLegend ),
    commentBody( kReaskLegend ),
    commentBody( kReaskImpactLegend ),
    // forpages.h — the page clause, at the default page size
    commentBody( kForDocPageClause ),
};

}   // namespace — forlegendentries.h section of main.cpp

// The static extent is the count check: a table one row short or long does not compile.
const std::span<const std::string_view, rw::legenddict::kForDocCount> rw::legenddict::kForDocEntries{ kForDocList };
