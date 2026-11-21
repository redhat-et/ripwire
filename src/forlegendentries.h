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

// The text of a present-only legend BETWEEN two of its erasable clauses (an empty name = the legend's start or end).
// An emitter that erases a clause its rows do not carry (rw::eraseAbsentClause) prints the base minus that clause, which
// is no single constant — but it is always a run of these pieces and the clauses kept, each an entry of its own.
constexpr std::string_view piece( std::string_view whole, std::string_view after, std::string_view before ) noexcept
{
    const std::size_t from = after.empty() ? 0 : whole.find( after ) + after.size();
    const std::size_t to   = before.empty() ? whole.size() : whole.find( before );
    return whole.substr( from, to - from );
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
    piece( rw::kForCompactBodyFoldLegend, {}, rw::kForCompactBodyFoldMembersClause ),
    piece( rw::kForCompactBodyFoldLegend, rw::kForCompactBodyFoldMembersClause, {} ),
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
    commentBody( piece( rw::kForCompactLiteralLegend, {}, rw::kForCompactLiteralBodyClause ) ),
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
    commentBody( piece( rw::kForFileSymsLegendCompact, {}, rw::kForFileSymsTestClauseCompact ) ),
    piece( rw::kForFileSymsLegendCompact, rw::kForFileSymsTestClauseCompact, rw::kForFileSymsReadClauseCompact ),
    commentBody( piece( rw::kForFileSymsLegendCompact, rw::kForFileSymsReadClauseCompact, {} ) ),
    rw::kForFileSymsTestClauseCompact,
    rw::kForFileSymsReadClauseCompact,
    commentBody( rw::kForFileSymsHeldLegend ),
    commentBody( piece( rw::kForDocBodyLegend, {}, rw::kForDocBodyHeldClause ) ),
    commentBody( piece( rw::kForDocBodyLegend, rw::kForDocBodyHeldClause, {} ) ),
    rw::kForDocBodyHeldClause,
    commentBody( piece( rw::kForDottedStringsLegend, {}, rw::kForDottedSinkClause ) ),
    commentBody( piece( rw::kForDottedStringsLegend, rw::kForDottedTemplateClause, {} ) ),
    rw::kForDottedSinkClause,
    rw::kForDottedLoaderClause,
    rw::kForDottedTemplateClause,
    commentBody( rw::kReaderCallersLegend ),
    commentBody( piece( rw::kForExemplarFamilyCompactLegend, {}, rw::kExemplarCompactScanSkipClause ) ),
    piece( rw::kForExemplarFamilyCompactLegend, rw::kExemplarCompactScanSkipClause, rw::kExemplarCompactDirTouchClause ),
    piece( rw::kForExemplarFamilyCompactLegend, rw::kExemplarCompactDirTouchClause, rw::kExemplarCompactContractClause ),
    rw::kExemplarCompactScanSkipClause,
    rw::kExemplarCompactDirTouchClause,
    rw::kExemplarCompactContractClause,
    rw::kExemplarCompactContractUnreadClause,
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
    // verbs_for.h — the est_tokens= sentence, by the ceilings the root names
    kForEstTokensNote,
    kForEstTokensBudgetCeilingNote,
    kForEstTokensBudgetNote,
    kForEstTokensCeilingNote,
    // forpages.h — the page clause, at the default page size
    commentBody( kForDocPageClause ),
    // forrowlines.h (FMT2) — the two clauses of the row-line form; appended, so no earlier entry id moves
    commentBody( rw::rowlines::kRankSeqClause ),
    commentBody( rw::rowlines::kRowLinesClause ),
    // SM1 (2026-11-21): three block-local notes written AFTER this table was, so no FILE could leave one out and a session
    // with the legend-seen hook ON re-received each whole. MEASURED on GA1 DEV's 89 as 11 one-repo sessions, 229 non-first
    // calls: the sigx note 77 verbatim repeats (14,476 B), the unread-language hops note 18 (3,150 B), the key-body note 5
    // (1,940 B) — 19,566 of the 23,807 B of non-disclosure comment bytes still repeating verbatim. Each is ONE constant printed whole
    // (no eraseAbsentClause cuts it), so one row each. NOT added, and why: the reexports and shortkey legends are cut per
    // answer by present-only clauses (7 and 4 of them), so they need the piece() split kForFileSymsLegendCompact has, for
    // 3,564 B on the same population. Gate: test/legendseenblockcheck.sh. Appended: no existing entry id moves.
    commentBody( rw::sigx::kSigxLegend ),
    commentBody( rw::kForHopValueRefsUnreadClause ),
    commentBody( rw::keybody::kKeyBodyLegend ),
};

}   // namespace — forlegendentries.h section of main.cpp

// The static extent is the count check: a table one row short or long does not compile.
const std::span<const std::string_view, rw::legenddict::kForDocCount> rw::legenddict::kForDocEntries{ kForDocList };
