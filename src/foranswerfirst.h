// foranswerfirst.h — ITEM R: a finished `--for` answer serves its ANSWER first.
//
// Two moves on a buffered document, and nothing else:
//   1. every top-level legend comment goes AFTER the rows, keeping its relative order;
//   2. a RESOLVED routed section goes ahead of <sigs>.
//
// It is a PERMUTATION. The same top-level blocks, byte for byte, in a different order — so no row is
// removed, no payload byte changes, and no gold can be lost by construction. That property is the whole
// reason this exists: four pre-registered attempts to make a --for answer shorter by CUTTING failed their
// own zero-gold-loss rules (item K's fixed tail cap, K1's height of 64, item C collapsing the tail on
// routed-element PRESENCE, item C' on routed-verb RESOLUTION), and unconditional tail removal costs 92
// anchors across 63 of 275 graded cells. A permutation cannot reach that bar.
//
// MEASURED BEFORE THIS WAS WRITTEN, as offline permutations of all 216 recorded --for cells: gold items
// found at a 2 KB budget 0.4 % -> 54.8 %, at 4 KB 19.3 % -> 70.6 %, at 8 KB 69.5 % -> 84.1 %; median
// bytes-to-complete 10,279 -> 5,541; ZERO of 212 cells worse; 27 of 27 repos improved. On the 13 cells
// carrying <path reachable="1"> or <met_bridge>, bytes-to-complete falls from a median 37,125 B (92.9 % of
// the answer's depth) to 3,377 B (8.0 %). Registered as docs/EVALS.md amendment 8.
//
// WHY THE LEGEND MAY MOVE. G4 constrains the legend's COUNT — "the legend is emitted once per answer on the
// CLI" — not its position, and its next clause already describes an answer that "ends with" its legend
// material. The legend STAYS IN THE ANSWER, so the ~80 gates that assert "this attribute is defined in this
// answer" still pass: this is the ref posture's move WITHOUT the ref posture's drop, which legenddict.h
// already documents as "rows first … legend comment … moved after the rows". It therefore does not wait on
// the dictionary-backed coverage contract.
//
// RESOLVED IS DELIBERATELY NARROW. Three separate bands this round mistook element PRESENCE for resolution,
// and the cost is measurable: <lego> and <compose> ship as `shown="0" capped="1"` STUBS when nothing
// resolved, and <graph_verb> is frequently an unresolved `reachable="0"` fallback cascade. Promoting any
// <graph_verb> has a worst case of +17,479 B — one cell put a 14.8 KB block ahead of <sigs> of which the
// answering path was 1,348 B. So a section is RESOLVED only when:
//     <reexports> carries BOTH a <def> row and at least one <rx> row, or
//     <graph_verb> carries <path … reachable="1"> or <met_bridge>.
// Measured marginal effect once the comments are at the end: reexports 14 better / 0 worse; graph_verb
// 8 better / 5 worse with a worst case of +2,192 B. Every other candidate measured net-worse or a wash when
// promoted — <callers> (12/5, ~1 KB either way), selfhooks (4/4), lit, shortkey, dotted_strings,
// exemplar_family — and none of them moves.
//
// <sigs> STAYS FIRST among the generic sections. A fitted full-section order (every section sorted by
// gold-per-byte) FAILED a held-out split, worse in more cells than better in both folds. And <tail> does NOT
// move: whole-tail-last took median bytes-to-complete 10,279 -> 11,487. Those two nulls are registered so
// this file cannot be widened into them without new evidence.
//
// R1b (2026-11-20) ADDED A SECOND PROMOTION CLASS BELOW RES, and this is that "new evidence" clause being used, so it says
// what the evidence is and what it does NOT cover. <tail> still does not move: it stays in place as a block, rows
// 1..kGuardTailRows never move, and the guard still refuses a promotion that would push tail row 24 past the stop (for the
// BODY class that bar is tail row kGuardTailRowsBody since ruling 120 — see the G/TL3 clause in the order spec below). What
// changed is that promoteGuarded now has an explicit PRIORITY ORDER instead of a single walk in emitter order:
// kPromotable (AF2's frozen ten, unchanged) has the first claim on the guard's headroom and kPromotableBody takes only what
// is left. Lane R1 had instead widened kPromotable itself and MEASURED the defect that motivates this ordering — a body won
// a promotion slot by its POSITION and silently un-promoted <lit>, turning legendseencheck green->red
// (results/R1_BODIESFIRST_1119/READOUT.md §8). R1's body rung moved one-directionally on its population (+31 anchors,
// 12 cells up, 0 down) and its file rung FELL in 9 of 123 cells, of which 8 were displaced deep tail rows and 1 was that
// crowding-out. **This ordering closes the crowding-out channel only.** The deep-tail-vs-body trade is not a priority
// question — it is a zero-sum trade between more file pointers and one body, and nothing in this file decides it; see
// results/R1B_PRIORITY_RULE_1120/READOUT.md §7 before widening further.
//
// THE STATED COST, which belongs in the open rather than in a footnote: a truncating consumer previously
// lost ROWS and now loses DEFINITIONS, so a hedge like `cands="133"` can be read without its reading. That
// is the strongest argument against this change (registered as band R5).
#pragma once

#include <algorithm>
#include <charconv>
#include <cstddef>
#include <cstdlib>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

#include "infra/sortutil.h"   // svLess — the one string_view order (portablebuildcheck #6b)
#include "serialize.h"   // attrOf — the one reader of a printed tag's attribute value
#include "infra/Diagnostics.h"
#include "infra/emit.h"

namespace rw::answerfirst
{

// The DISCLOSE SINK for this pass's two fallbacks. A one-argument DISCLOSE( msg ) is trace-only and compiles
// away under NDEBUG (Diagnostics.h RW_DISCLOSE_1), so a RELEASE user learns nothing when the permutation
// declines to run — test/selfcheckcheck.sh (R) ratchets on exactly that count, and it caught these two.
//
// Both fallbacks serve a COMPLETE answer: only the reordering is missed, which is why each message says so.
// A reader who cannot tell a degraded answer from a whole one is the failure this sink exists to prevent.
struct AnswerFirstFallback
{
    enum class DisclosureWhy : std::uint8_t
    {
        SizeChanged,      // the permutation changed the document's size — a block was dropped or duplicated
        NoWholeCapture,   // the answer could not be buffered whole, so it is served in the default order
    };
    void disclose( DisclosureWhy why ) noexcept
    {
        rw::emitTo( stderr, "ripwire: --legend=last: {}\n",
                    why == DisclosureWhy::SizeChanged
                        ? "the permuted answer changed size, so the original order is served — the answer is complete either way"
                        : "the answer did not buffer whole, so it is served in the default order — the answer is complete either way" );
    }
};

// One top-level child of the root: its exact byte span, and what it is.
struct Block
{
    std::size_t      begin   = 0;
    std::size_t      end     = 0;
    bool             comment = false;
    std::string_view name;   // empty for a comment
};

// ITEM R IS OPT-IN (--legend=last). The decision belongs to the caller, which holds the Config; this header used to
// read RIPWIRE_FOR_LEGACY_ORDER itself, which made the ordering depend on the environment rather than on argv and
// left no user-facing way to ask for it. answerFirst() is now unconditional: call it only when the posture asked.
// The name characters an XML element name is made of. A set lookup rather than a hand-rolled scan loop:
// quality-delta scored the loop form as a 79-token duplicate of src/query.h's Eval::ident, which is the
// repo's identifier scanner and has no business being reimplemented here.
inline constexpr std::string_view kNameChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-";

[[nodiscard]] inline std::string_view elementName( std::string_view doc, std::size_t i, std::size_t j ) noexcept
{
    const std::size_t stop = doc.find_first_not_of( kNameChars, i + 1 );
    return doc.substr( i + 1, ( stop == std::string_view::npos ? j : std::min( stop, j ) ) - ( i + 1 ) );
}

// Scan the root's top-level children between [bodyBegin, bodyEnd).
//
// Hand-rolled, and it must stay that way: --for answers carry ripwire's own C++ inside CDATA, and that
// source contains BOTH comment-shaped and tag-shaped text (`<!--" + add + "-->` and `<std::string>` are real
// strings in it). 228 of 295 recorded answers carry CDATA, and an unmasked scan cost another instrument this
// round an entire 16.9 KB section. A regex here is a defect, not a shortcut.
// A bracketed span the scanner must step over whole rather than parse: a comment or a CDATA section.
// Returns the byte just past its terminator, or npos when it is unterminated inside the body.
[[nodiscard]] inline std::size_t skipBracketed( std::string_view doc, std::size_t i, std::size_t end,
                                                std::string_view open, std::string_view close ) noexcept
{
    if( doc.compare( i, open.size(), open ) != 0 )
    {
        return i;   // not this kind of span: the caller tries the next shape
    }
    const std::size_t j = doc.find( close, i );
    return ( j == std::string_view::npos || j + close.size() > end ) ? std::string_view::npos : j + close.size();
}

// Scan the root's top-level children between [bodyBegin, bodyEnd). Empty means "a shape this pass does not
// understand", and the caller then serves the answer unchanged.
//
// Hand-rolled, and it must stay that way: --for answers carry ripwire's own C++ inside CDATA, and that
// source contains BOTH comment-shaped and tag-shaped text (`<!--" + add + "-->` and `<std::string>` are real
// strings in it). 228 of 295 recorded answers carry CDATA, and an unmasked scan cost another instrument this
// round an entire 16.9 KB section. A regex here is a defect, not a shortcut.
[[nodiscard]] inline std::vector<Block> topLevelBlocks( std::string_view doc, std::size_t bodyBegin, std::size_t bodyEnd )
{
    std::vector<Block> out;
    std::size_t        i = bodyBegin, depth = 0, start = 0;
    std::string_view   name;
    while( i < bodyEnd )
    {
        const std::size_t afterComment = skipBracketed( doc, i, bodyEnd, "<!--", "-->" );
        if( afterComment == std::string_view::npos ) { return {}; }
        if( afterComment != i )
        {
            if( depth == 0 ) { out.push_back( { i, afterComment, true, {} } ); }
            i = afterComment;
            continue;
        }
        const std::size_t afterCdata = skipBracketed( doc, i, bodyEnd, "<![CDATA[", "]]>" );
        if( afterCdata == std::string_view::npos ) { return {}; }
        if( afterCdata != i ) { i = afterCdata; continue; }
        if( doc[ i ] != '<' ) { ++i; continue; }   // inter-tag text: minified output has none

        const std::size_t j = doc.find( '>', i );
        if( j == std::string_view::npos || j >= bodyEnd ) { return {}; }
        if( doc[ i + 1 ] == '/' )
        {
            if( depth == 0 ) { return {}; }
            if( --depth == 0 ) { out.push_back( { start, j + 1, false, name } ); }
            i = j + 1;
            continue;
        }
        const bool selfClosing = j > i && doc[ j - 1 ] == '/';
        if( depth == 0 )
        {
            if( selfClosing ) { out.push_back( { i, j + 1, false, elementName( doc, i, j ) } ); }
            else              { start = i; name = elementName( doc, i, j ); }
        }
        if( !selfClosing ) { ++depth; }
        i = j + 1;
    }
    return depth == 0 ? out : std::vector<Block>{};
}

// RESOLVED, by the narrow definition in the header. Read from the block's own structure — never from any
// ranking, score or gold.
[[nodiscard]] inline bool resolvedRouted( std::string_view block, std::string_view name ) noexcept
{
    if( name == "reexports" )
    {
        return block.find( "<def" ) != std::string_view::npos && block.find( "<rx" ) != std::string_view::npos;
    }
    if( name == "graph_verb" )
    {
        return block.find( "reachable=\"1\"" ) != std::string_view::npos || block.find( "<met_bridge" ) != std::string_view::npos;
    }
    return false;
}

// Would the permutation actually move anything? A comment before a row block, or a resolved routed section
// sitting behind <sigs>. Separated so answerFirst stays one job: assemble.
[[nodiscard]] inline bool permutationWouldMove( std::string_view view, const std::vector<Block>& blocks ) noexcept
{
    std::size_t sigsAt = blocks.size();
    for( std::size_t k = 0; k < blocks.size(); ++k )
    {
        if( !blocks[ k ].comment && blocks[ k ].name == "sigs" ) { sigsAt = k; break; }
    }
    for( std::size_t k = 0; k < blocks.size(); ++k )
    {
        const Block& b = blocks[ k ];
        if( b.comment ) { if( k + 1 < blocks.size() ) { return true; } continue; }
        if( k > sigsAt && resolvedRouted( view.substr( b.begin, b.end - b.begin ), b.name ) ) { return true; }
    }
    return false;
}

// The FIRST WORD of a comment: `syms` in `<!-- syms t= n= …`. This is what separates the two kinds of
// comment a --for answer carries. The DOCUMENT legend opens with the verb or the root (`<!-- ripwire for …`,
// `<!-- root …`) and documents the answer as a whole; a BLOCK-LOCAL legend NAMES ITS OWN ELEMENT. Measured on
// a --detail=5 answer: `ripwire`→<sigs> and `root`→<sigs> do not match, `syms`→<syms> does.
//
// AF1-fix (2026-11-18): a block-local legend has TWO spellings in src/, and both name their element: `<!-- syms: …` and
// `<!-- ripwire for X: …` (doc_body, dotted_strings, exemplar_family, lit, manifest_rows, decl_rows, graph_verb, met_bridge,
// path_gap, reask, syms). Reading only the first word sent every `ripwire for X:` legend to the trailing DOCUMENT legend, away
// from its block — against the convention below and AF1's registered layout ("block-local legend comments stay in the stream,
// glued to the block they declare"): fordocbodycheck (f1), forexemplarcheck and formanifestcheck (a1) read the block from its
// legend and found nothing after it. So `ripwire for X` reads as X, whatever follows X (`ripwire for doc_body held="budget":`,
// `ripwire for lit callers:` are block legends too); declaredBlock still requires the next block to BE an <X>. The document
// legend's own `ripwire for schema=…` names no element the answer opens, so it stays where it is.
[[nodiscard]] inline std::string_view commentWordAt( std::string_view doc, std::size_t from, std::size_t end ) noexcept
{
    if( from == std::string_view::npos || from >= end ) { return {}; }
    const std::size_t stop = doc.find_first_not_of( kNameChars, from );
    return doc.substr( from, ( stop == std::string_view::npos ? end : std::min( stop, end ) ) - from );
}
[[nodiscard]] inline std::string_view commentFirstWord( std::string_view doc, const Block& b ) noexcept
{
    const std::string_view first = commentWordAt( doc, doc.find_first_of( kNameChars, b.begin + 4 ), b.end );   // past the "<!--"
    constexpr std::string_view kVerbLead = "ripwire for ";
    const std::size_t          at        = first.empty() ? std::string_view::npos : static_cast<std::size_t>( first.data() - doc.data() );
    if( first != "ripwire" || doc.compare( at, kVerbLead.size(), kVerbLead ) != 0 ) { return first; }
    const std::string_view named = commentWordAt( doc, at + kVerbLead.size(), b.end );
    return named.empty() ? first : named;
}

// Which row block does this comment DECLARE, if any? The house convention is that a block's own legend sits
// in the comment IMMEDIATELY before its open tag, so the block can be switched off without moving a byte in
// front of it and a reader meets the definition where the block begins. Such a comment must therefore TRAVEL
// WITH its block rather than join the document legend at the tail.
//
// Why this matters beyond tidiness: formaxtokenscheck's judge strips one self-declaring trailing block before
// pricing, and its pattern requires comment-then-block. With the comment relocated, 1,447 B stopped being
// stripped and est_tokens looked as though it under-charged by exactly 579 tokens — a phantom accounting
// defect whose only cause was this adjacency. test/foranswerfirstcheck.sh (R8) pins it.
[[nodiscard]] inline std::size_t declaredBlock( std::string_view doc, const std::vector<Block>& blocks, std::size_t k ) noexcept
{
    if( !blocks[ k ].comment ) { return std::string_view::npos; }
    for( std::size_t j = k + 1; j < blocks.size(); ++j )
    {
        if( blocks[ j ].comment ) { continue; }   // several comments may queue in front of one block
        return commentFirstWord( doc, blocks[ k ] ) == blocks[ j ].name ? j : std::string_view::npos;
    }
    return std::string_view::npos;   // nothing follows it: the document legend, by position as well as by name
}

// ── AF2's order spec (results/AF2_FIRST12K_1118/READOUT.md §SPEC, frozen 2026-11-18 after meeting its pre-registered bar:
// within 12 KB, design 70→75 of 99, held-out 32→33 of 39, 0 flips). Three moves on top of the two above, all of them still
// a reordering of the same bytes:
//   A  — every comment that is a DIRECT CHILD of a top-level section (the <graph_verb>/<reexports>/<fold> notes) joins the
//        document legend, relative order kept; in <sigs>, the demote:/decl-twin:/one-side: notes the spec lists (since AF4 T-C,
//        which put the pointer kind on the row as ptr=; see blockTextHoisting). Not moved either: a section's own
//        lead comment (declaredBlock — it travels with its block, R8), the <bodies> section's per-answer body-omitted note,
//        and comments nested inside a row. A zero-row self-closing <lego/> or <compose/> stub between <sigs> and <tail> goes
//        directly after </tail>.
//   E1 — inside <graph_verb>, <met_bridge> ahead of <path_gap> (an emitter swap in verbs_for.h appendSubjectGraphVerbBlock).
//   G  — GUARDED promotion: a RES section after </tail> moves directly ahead of <tail> ONLY IF the tail has more than
//        kGuardTailRows rows, </tail> ends past the page stop, and tail row kGuardTailRows still ends within the stop with it
//        and every section already moved in place. The stop is the DEFAULT PAGE SIZE (kAnswerPageBytesDefault, which forpages.h
//        kForPageBytesDefault IS), never a separate 12,000 — so it follows the owner if the default page becomes 6 KB. The
//        unguarded variant is an owner call and is NOT built.
//   G/R1b — G's walk became TWO CLASS-ORDERED PASSES over the same list against the same headroom: kPromotable first
//        (unchanged, so pass 1 is AF2's G exactly), then kPromotableBody from the headroom that remains, emitted behind
//        the promoted RES sections so their byte offsets do not move. Same guard, same stop, same emit order within a class.
//   G/TL2 — the SIZE precondition ("</tail> ends past the stop") scopes PASS 1 alone: it was never a guard, only a test on the
//        tail's own size, and it made a tail that FITS page 1 untouchable (owner ruling 112).
//   G/TL3 — the two classes carry TWO guarantees (owner ruling 120). PASS 1 is AF2's G on every input, unchanged, including its
//        eligibility test: more than kGuardTailRows rows and an overflowing tail. PASS 2's guarantee is kGuardTailRowsBody, and
//        its fit test is floored PER CANDIDATE by postPageOneFloors so that no section page 1 already delivers behind </tail>
//        loses its place (a RES section keeps every delivered byte; any section keeps its page-1 presence). A tail of
//        kGuardTailRowsBody+1..kGuardTailRows rows, which AF2's G refused outright, is a body candidate from here on.
inline constexpr std::size_t      kAnswerPageBytesDefault = 12000;   // the default page size: forpages.h kForPageBytesDefault IS this
inline constexpr std::size_t      kGuardTailRows          = 24;
// RULING 120 (2026-11-20): the BODY class's OWN guarantee. Lane TL2 measured the guarantee, not its cap, as the lever that
// funds page-1 bodies (results/TL2_TAIL_CAP_1120/READOUT.md §6b/§12.4) and handed the default back for the owner's word, which
// ruling 120 gave. It lands as a SECOND constant rather than as a lower kGuardTailRows, and the reason is MEASURED, not
// stylistic: lowering the one constant to 12 raises PASS 1's headroom as well, which promotes a kPromotable section ahead of
// <tail> in four GA1 DEV cells AF2's frozen G left alone and DEFERS the <fold> the parent's page 1 delivered in a fifth
// (ga-libzmq-08) — 7 of 89 cells fail B-NO-CROWDOUT v3 there, five of them on v2's own frozen conjuncts
// (results/TL3_GUARD12_1120/READOUT.md §3). So AF2's RES guarantee stays at 24 — pass 1 is unchanged, and with it
// tailSameDirFirst's partition point and the legend clause that discloses it — and only R1b's BODY class is funded from row 12.
inline constexpr std::size_t      kGuardTailRowsBody      = 12;
inline constexpr std::string_view kPromotable[] = { "lit", "dotted_strings", "graph_verb", "callers", "selfhooks", "manifest_rows",
                                                    "listed", "ep", "reexports", "exemplar_family" };
// R1b's SECOND, LOWER-PRIORITY class (results/R1B_PRIORITY_RULE_1120/PREREG_R1B_1120.md §1, frozen before this was written).
// The BODY-bearing sections. They are what a how-it-works question needs — a `catch`/`instanceof`, a `.bind()`, an `nbf` guard
// is a STATEMENT INSIDE a body, so no ranking signal surfaces it and no signature row carries it (EB1's diagnosis,
// results/EB1_ERRORBRANCH_1119/READOUT.md §3; AF2's own cause table names "a <fold> body" as the last-gold carrier in 4 of its
// 29 design late cells and never tried them). They are NOT members of kPromotable: AF2 froze that set with its measurement, and
// a body joining it wins a promotion slot by its POSITION in the emitter rather than by its value — measured by lane R1, which
// un-promoted <lit> on the legendseencheck probe and turned a green gate red (results/R1_BODIESFIRST_1119/READOUT.md §8).
inline constexpr std::string_view kPromotableBody[] = { "fold", "bodies" };

// AF4 T-C: the <sigs> notes that define their pointer rows by ATTRIBUTE (ptr=), so A may lift them: the first word of each.
inline constexpr std::string_view kSigsAttributeNotes[] = { "demote", "decl-twin", "one-side" };

// One row block as it will be emitted: its own bytes minus the direct-child comments A hoists, which go to `hoisted`.
[[nodiscard]] inline std::string blockTextHoisting( std::string_view view, const Block& b, std::vector<std::string_view>& hoisted )
{
    const std::string_view text = view.substr( b.begin, b.end - b.begin );
    const std::size_t      open = view.find( '>', b.begin ) + 1;
    // <sigs> (AF4 T-C, closing AF1's deviation from the frozen spec, results/AF1_ANSWERFIRST_1118/READOUT.md §6): its
    // demote:/decl-twin:/one-side: notes used to be POSITIONAL — each labelled the <t> pointer rows that followed it, so lifted
    // they made every <t> read as every kind. The kind is now on the row (forfilesyms.h TailPointerSpan::kind: ptr=twin,
    // ptr=side, none for demote) and the notes define by attribute, so these three join the legend like any section's readings.
    // Any OTHER comment in <sigs> stays where it is: only a note known to define by attribute may leave its rows.
    if( b.comment || b.name == "bodies" || view[ open - 2 ] == '/' ) { return std::string( text ); }
    const std::size_t        close = view.rfind( "</", b.end - 1 );
    const std::vector<Block> kids  = close > open ? topLevelBlocks( view, open, close ) : std::vector<Block>{};
    const auto               lifts = [ & ]( const Block& k )
    {
        return b.name != "sigs" || std::ranges::find( kSigsAttributeNotes, commentFirstWord( view, k ) ) != std::ranges::end( kSigsAttributeNotes );
    };
    std::string out;
    std::size_t copied = b.begin;
    for( const Block& k : kids )
    {
        if( !k.comment || !lifts( k ) ) { continue; }
        out.append( view.substr( copied, k.begin - copied ) );
        hoisted.push_back( view.substr( k.begin, k.end - k.begin ) );
        copied = k.end;
    }
    out.append( view.substr( copied, b.end - copied ) );
    return out;
}

// ── AF4 T-B, CALLERS FIRST UNDER A CALLERS CUE (the P1 verb-route spec, section 2 (local results, not shipped); pre-registered in
// results/AF4_TOPLOAD_1118/PREREG.md). A who-calls question ("which functions call `f` directly?") is answered by the
// <callers by="subject"> block, which the assembly emits after <sigs>; on P1's three such held-out cells, emitted first it moved
// bytes-to-all-gold 5,387→726, 6,629→935 and 11,112→743 with the same bytes and groups. The CUE is the caller's to read
// (subjectanchor.h subjectCallersCueLeads, from the task): a change or blast-radius question must NOT lead with the one-hop
// callers (P1's change-risk cell got worse, 5,965→6,451). Order only: the block, with any lead comment of its own, becomes the
// first row block; no byte is added (P1's `lead=` disclosure attribute is deliberately not built: it would break the permutation
// contract answerFirst ENSURES). G runs on the order this produces, so its guard counts the block's bytes.
inline constexpr std::string_view kSubjectCallersOpen = "<callers by=\"subject\"";

// The top-level <callers by="subject"> block among `blocks`, or npos.
[[nodiscard]] inline std::size_t subjectCallersBlock( std::string_view view, const std::vector<Block>& blocks ) noexcept
{
    for( std::size_t j = 0; j < blocks.size(); ++j )
    {
        if( !blocks[ j ].comment && blocks[ j ].name == "callers" && view.substr( blocks[ j ].begin ).starts_with( kSubjectCallersOpen ) ) { return j; }
    }
    return std::string_view::npos;
}

// T-B: `order` with block `lead` moved to the front, every other block's relative order kept (npos: unchanged).
[[nodiscard]] inline std::vector<std::size_t> leadWith( std::vector<std::size_t> order, std::size_t lead )
{
    const auto at = std::ranges::find( order, lead );
    if( at != order.end() ) { std::rotate( order.begin(), at, at + 1 ); }
    return order;
}

// The answer-first order of the row blocks before G: resolved routed sections, then every other row block in place, a
// zero-row lego/compose stub that sits between <sigs> and <tail> moved to just after </tail>.
[[nodiscard]] inline std::vector<std::size_t> rowBlockOrder( std::string_view view, const std::vector<Block>& blocks )
{
    std::vector<std::size_t> routed, rest, stubs;
    bool sawSigs = false, sawTail = false;
    for( std::size_t j = 0; j < blocks.size(); ++j )
    {
        const Block& b = blocks[ j ];
        if( b.comment ) { continue; }
        const std::string_view text = view.substr( b.begin, b.end - b.begin );
        const bool isStub = ( b.name == "lego" || b.name == "compose" ) && text.ends_with( "/>" ) && text.find( '>' ) + 1 == text.size();
        if( resolvedRouted( text, b.name ) )                { routed.push_back( j ); }
        else if( isStub && sawSigs && !sawTail )            { stubs.push_back( j ); }
        else                                                { rest.push_back( j ); }
        if( b.name == "tail" ) { sawTail = true; rest.insert( rest.end(), stubs.begin(), stubs.end() ); stubs.clear(); }
        sawSigs = sawSigs || b.name == "sigs";
    }
    rest.insert( rest.end(), stubs.begin(), stubs.end() );   // no <tail> after them: they stay, in order, at the end
    routed.insert( routed.end(), rest.begin(), rest.end() );
    return routed;
}

// The answer as A will emit it: each block's lead comments (ownerOf), its text with the direct-child comments lifted out, its
// emitted size with those lead comments (`sized`), and the lifted comments in document order.
struct Layout
{
    std::vector<std::size_t>      ownerOf;
    std::vector<std::string>      text;
    std::vector<std::size_t>      sized;
    std::vector<std::string_view> hoisted;
};
[[nodiscard]] inline Layout layoutBlocks( std::string_view view, const std::vector<Block>& blocks )
{
    Layout l{ .ownerOf = std::vector<std::size_t>( blocks.size(), std::string_view::npos ), .text = std::vector<std::string>( blocks.size() ),
              .sized = std::vector<std::size_t>( blocks.size(), 0 ), .hoisted = {} };
    for( std::size_t k = 0; k < blocks.size(); ++k )
    {
        l.ownerOf[ k ] = declaredBlock( view, blocks, k );
        if( !blocks[ k ].comment ) { l.text[ k ] = blockTextHoisting( view, blocks[ k ], l.hoisted ); l.sized[ k ] += l.text[ k ].size(); }
    }
    for( std::size_t k = 0; k < blocks.size(); ++k )
    {
        if( l.ownerOf[ k ] != std::string_view::npos ) { l.sized[ l.ownerOf[ k ] ] += blocks[ k ].end - blocks[ k ].begin; }
    }
    return l;
}

// The direct-child row blocks of block `b` (its open tag to its close tag); empty for a self-closing block.
[[nodiscard]] inline std::vector<Block> childBlocks( std::string_view text, std::size_t begin, std::size_t end )
{
    const std::size_t open  = text.find( '>', begin ) + 1;
    const std::size_t close = text.rfind( "</", end - 1 );
    return open >= 2 && text[ open - 2 ] != '/' && close > open && close != std::string_view::npos ? topLevelBlocks( text, open, close ) : std::vector<Block>{};
}

// ONE SECTION'S ROW BLOCKS: its direct children with the comment blocks dropped — a comment inside <tail> is not a row.
// childBlocks (below) already owns the open/close arithmetic and the self-closing guard; this adds only the comment drop,
// so promoteGuarded reads the rows out of `view` and out of the EMITTED text through the same two lines.
[[nodiscard]] inline std::vector<Block> rowChildren( std::string_view text, std::size_t begin, std::size_t end )
{
    std::vector<Block> rows = childBlocks( text, begin, end );
    std::erase_if( rows, []( const Block& r ) { return r.comment; } );
    return rows;
}

// ONE PROMOTION CLASS'S SWEEP over the sections that follow </tail>, in emit order (R1b's priority rule, src/foranswerfirst.h
// kPromotable / kPromotableBody): the indices this class wins, with `taken` marking them and `used` advanced by their emitted
// sizes — so a LATER class sees only the headroom this one left. The classes are swept highest priority first, which is what
// makes crowding-out structurally impossible rather than a matter of emitter position.
// `floor` is PER CANDIDATE — floor[i] is the byte page 1 must still reach if post[i] is the section that moves — because
// promoting post[i] shifts only the sections AHEAD of it in emit order (the ones behind it keep their offsets: the promoted
// section leaves its own slot by exactly its own size). A class with one guarantee for every candidate passes the same value
// in every element; postPageOneFloors builds the body class's.
[[nodiscard]] inline std::vector<std::size_t> promoteClassSweep( const std::vector<Block>& blocks, const std::vector<std::size_t>& sized,
                                                                 const std::vector<std::size_t>& post, std::span<const std::string_view> cls,
                                                                 std::span<const std::size_t> floor, std::size_t stop, std::vector<char>& taken, std::size_t& used )
{
    std::vector<std::size_t> won;
    for( std::size_t i = 0; i < post.size(); ++i )
    {
        if( taken[ i ] != 0 || std::ranges::find( cls, blocks[ post[ i ] ].name ) == std::ranges::end( cls ) ) { continue; }
        if( floor[ i ] + used + sized[ post[ i ] ] > stop ) { continue; }
        taken[ i ] = 1;
        used += sized[ post[ i ] ];
        won.push_back( post[ i ] );
    }
    return won;
}

// THE PAGE-1 FLOOR the body class owes everything already BEHIND </tail>, per candidate: floors[i] is the byte page 1 must
// still reach if post[i] moves ahead of <tail>, read off the sections AHEAD of post[i] alone, since those are the only ones its
// promotion shifts. Two things are owed, at two different granularities, and the difference between them is not cosmetic:
//   * R1b's PRIORITY RULE — a kPromotable RES section keeps EVERY byte page 1 delivered, so it contributes its END. This is
//     TL2's own postResReach, which this generalises; without it, MEASURED on GA1 DEV, <callers> left page 1 in ga-jq-05 and
//     ga-jq-08 (results/TL2_TAIL_CAP_1120/READOUT.md §6).
//   * RULING 115's conjunct (iv) — ANY section keeps its page-1 PRESENCE, so every section contributes its START (+1, so the
//     start stays strictly inside the stop). Presence is exactly what the product's own deferred= reports (forpages.h
//     sectionAttrs: a section is deferred iff it STARTS at or after the cut) and exactly what B-NO-CROWDOUT v3 grades.
//     Without it, MEASURED, <hops> left page 1 in ga-jq-01 and ga-jq-09 — TL2 reported that and declined to narrow the bar.
// Reading presence as a START and RES completeness as an END is what keeps the gain: in ga-bash-it-06 the parent's own page 1
// already cuts <fold> mid-section, so an END-based floor over all sections would refuse the one promotion that cell is the
// +1 BODY cell of. `at` is where </tail> ends; when the tail OVERFLOWS the stop every post-tail section starts past it, so
// every floor is `rowEnd` and the walk is provably a no-op — which is why pass 1 can share this list unchanged.
[[nodiscard]] inline std::vector<std::size_t> postPageOneFloors( const std::vector<Block>& blocks, const std::vector<std::size_t>& sized,
                                                                 const std::vector<std::size_t>& post, std::size_t at, std::size_t stop,
                                                                 std::size_t rowEnd )
{
    std::vector<std::size_t> floors( post.size(), rowEnd );
    std::size_t              reach = rowEnd;
    for( std::size_t i = 0; i < post.size(); ++i )
    {
        floors[ i ]              = reach;   // the sections ahead of post[ i ], never post[ i ] itself nor anything behind it
        const std::size_t begins = at;
        at += sized[ post[ i ] ];
        if( begins < stop ) { reach = std::max( reach, begins + 1 ); }
        if( at <= stop && std::ranges::find( kPromotable, blocks[ post[ i ] ].name ) != std::ranges::end( kPromotable ) ) { reach = std::max( reach, at ); }
    }
    return floors;
}

// G, the GUARDED promotion, on the emitted sizes. The bytes ahead of the first row block are the root open tag; the stop is the
// DEFAULT page size, one constant, so every page size windows the same document. Returns the order with the promoted RES
// sections directly ahead of <tail>.
[[nodiscard]] inline std::vector<std::size_t> promoteGuarded( std::string_view view, const std::vector<Block>& blocks, std::vector<std::size_t> order,
                                                              const Layout& layout )
{
    const std::vector<std::size_t>& sized  = layout.sized;
    const std::size_t               prefix = blocks.empty() ? 0 : blocks.front().begin;
    const std::size_t               stop   = kAnswerPageBytesDefault;
    const auto tailIt = std::ranges::find_if( order, [ & ]( std::size_t j ) { return blocks[ j ].name == "tail"; } );
    if( tailIt == order.end() ) { return order; }
    const Block&             tail = blocks[ *tailIt ];
    const std::vector<Block> rows = rowChildren( view, tail.begin, tail.end );
    std::size_t before = prefix;
    for( auto it = order.begin(); it != tailIt; ++it ) { before += sized[ *it ]; }
    // THE SAME ROWS IN THE EMITTED TEXT. `rows` are read out of `view`, where the tail still carries the direct-child
    // comments A hoists into the document legend, so a row's `view` offset is NOT its offset in the answer. AF2's guard
    // corrected for that by subtracting EVERY hoisted byte, which is exact only while all of them precede row k — and
    // MEASURED on GA1 DEV they do not: in ga-bash-it-06 the tail's hoisted clauses run past row 12, so AF2's
    // `sized - elemLen` is a NEGATIVE std::size_t, the floor WRAPPED to an astronomical value and the promotion ruling 120
    // priced was refused in silence. At 24 rows the wrap does not fire on this population, which is why it has never been
    // seen. `layout.text` is the tail exactly as it will be emitted, so rows read out of it need no correction at all and
    // the only subtraction left is the tail's own owned-comment bytes, which cannot be negative.
    const std::string&       emitted = layout.text[ *tailIt ];
    const std::vector<Block> erows   = rowChildren( emitted, 0, emitted.size() );
    if( rows.size() <= kGuardTailRowsBody || erows.size() <= kGuardTailRowsBody ) { return order; }
    // TL2's CAP (owner ruling 112, results/TL2_TAIL_CAP_1120/READOUT.md §3): the tail's page-1 presence is a GUARANTEE of its
    // first kGuardTailRows rows, not of the whole tail. AF2's G asked a second question before promoting anything — does
    // </tail> itself end past the stop — and that is a precondition on the tail's own SIZE, not a guard: it made a tail that
    // FITS page 1 untouchable, so the <fold> behind such a tail was never promoted and page 1 ended on file-grain pointer rows
    // while the body the question was about started after the cut. The rows past the guarantee carry no rank (MEASURED: 0 of
    // 88 GA1 DEV page-1 tails carry a single r= row) and are what funds the body. Nothing is removed — the tail keeps every
    // row, in order — so this is still the permutation test/foranswerfirstcheck.sh (R1)/(R4) pin, not item K's tail cut.
    // The size precondition therefore scopes PASS 1 ALONE: on a fitting tail the RES class is AF2's frozen behaviour byte for
    // byte (no RES section moves), and the BODY class may be funded from the unguaranteed rows, floored by postPageOneFloors so
    // that nothing page 1 already delivers behind </tail> loses it. (G8)/(G9)/(G10) pin all three halves.
    // RULING 120: the two classes now carry TWO guarantees. Pass 1 keeps AF2's 24 rows AND AF2's own eligibility test
    // (more than kGuardTailRows rows, and an overflowing tail), so it promotes exactly what the parent promotes on every
    // input — by construction, not by measurement. Pass 2 is guaranteed kGuardTailRowsBody rows, which is what funds the
    // bodies ruling 120 priced; a tail of 13..24 rows, which the parent refused outright, is now a body candidate too.
    const bool        overflows = before + sized[ *tailIt ] > stop;
    // TWO expressions for "where the guaranteed row ends", deliberately. PASS 1's must be AF2's arithmetic VALUE for value,
    // because pass 1 being the parent's on every input is what makes B-NO-CROWDOUT v2's frozen conjuncts pass by
    // construction rather than by measurement; `resRowEnd` is therefore AF2's expression with the wrap above replaced by an
    // explicit refusal, which changes no decision — a wrapped floor exceeded the stop and could only ever refuse — and
    // leaves no unsigned overflow for -fsanitize=integer to find. PASS 2's is new code and is simply correct.
    const std::size_t elemLen = tail.end - tail.begin;
    const std::size_t hoisted = elemLen > sized[ *tailIt ] ? elemLen - sized[ *tailIt ] : 0;
    const std::size_t owned   = sized[ *tailIt ] > elemLen ? sized[ *tailIt ] - elemLen : 0;
    const auto        resRowEnd = [ & ]( std::size_t k )
    {
        const std::size_t off = ( rows[ k - 1 ].end - tail.begin ) + owned;
        return off >= hoisted ? before + off - hoisted : stop + 1;
    };
    const auto bodyRowEnd = [ & ]( std::size_t k ) { return before + ( sized[ *tailIt ] - emitted.size() ) + erows[ k - 1 ].end; };
    // R1b's PRIORITY RULE: two class-ordered passes over the SAME post-tail list, in the SAME emit order, against the SAME
    // single headroom accumulator. Pass 1 is the parent's own walk over kPromotable with `used` starting at 0, and a section of
    // no promotable class never consumed headroom in the parent either — so pass 1 promotes exactly what AF2's frozen G
    // promotes, in that order, and (because pass 2's sections are appended BEHIND pass 1's) at the same byte offsets. Pass 2
    // then takes only the headroom pass 1 left. Crowding-out is therefore removed BY CONSTRUCTION, not by a threshold: there is
    // no input for which a body can take a RES section's slot. If pass 1 exhausts the headroom, no body moves and the answer is
    // the parent's, byte for byte.
    const std::vector<std::size_t> post( tailIt + 1, order.end() );
    std::vector<char>              taken( post.size(), 0 );
    std::size_t                    used    = 0;
    const bool                     resPass = overflows && rows.size() > kGuardTailRows;   // AF2's eligibility test, verbatim
    const std::vector<std::size_t> resFloor( post.size(), resPass ? resRowEnd( kGuardTailRows ) : 0 );
    const std::vector<std::size_t> movedRes = resPass ? promoteClassSweep( blocks, sized, post, kPromotable, resFloor, stop, taken, used )
                                                      : std::vector<std::size_t>{};                                                // pass 1
    const std::vector<std::size_t> bodyFloor = postPageOneFloors( blocks, sized, post, before + sized[ *tailIt ], stop, bodyRowEnd( kGuardTailRowsBody ) );
    const std::vector<std::size_t> movedBody = promoteClassSweep( blocks, sized, post, kPromotableBody, bodyFloor, stop, taken, used );   // pass 2
    std::vector<std::size_t>       out( order.begin(), tailIt );
    out.insert( out.end(), movedRes.begin(), movedRes.end() );
    out.insert( out.end(), movedBody.begin(), movedBody.end() );
    out.push_back( *tailIt );
    for( std::size_t i = 0; i < post.size(); ++i )
    {
        if( taken[ i ] == 0 ) { out.push_back( post[ i ] ); }
    }
    return out;
}

// Append the blocks in ANSWER-FIRST order: the row blocks (each preceded by its own block-local legend, so the convention's
// adjacency survives), then the DOCUMENT legend, then the comments A lifted out of the sections. Every byte of the answer is
// copied once; only the order moves. `lead` (T-B): the block that goes first, before G reads the order; npos for none.
inline void appendAnswerFirst( std::string_view view, const std::vector<Block>& blocks, std::string& out, std::size_t lead )
{
    const Layout l   = layoutBlocks( view, blocks );
    const auto   put = [ & ]( std::size_t k ) { out.append( view.substr( blocks[ k ].begin, blocks[ k ].end - blocks[ k ].begin ) ); };
    for( const std::size_t j : promoteGuarded( view, blocks, leadWith( rowBlockOrder( view, blocks ), lead ), l ) )
    {
        for( std::size_t k = 0; k < blocks.size(); ++k )
        {
            if( l.ownerOf[ k ] == j ) { put( k ); }
        }
        out += l.text[ j ];
    }
    for( std::size_t k = 0; k < blocks.size(); ++k )   // the DOCUMENT legend, last, relative order kept
    {
        if( blocks[ k ].comment && l.ownerOf[ k ] == std::string_view::npos ) { put( k ); }
    }
    for( const std::string_view c : l.hoisted ) { out.append( c ); }
}

// The root's body: [after the <ctx …> open tag, at </ctx>), or nullopt when the document is not one <ctx> root.
struct RootBody
{
    std::size_t openEnd = 0;   // the open tag's '>'
    std::size_t closeAt = 0;   // the "</ctx>"
};
[[nodiscard]] inline std::optional<RootBody> rootBody( std::string_view view ) noexcept
{
    const std::size_t openAt = view.find( "<ctx" );
    if( openAt == std::string_view::npos ) { return std::nullopt; }
    const std::size_t openEnd = view.find( '>', openAt );
    const std::size_t closeAt = view.rfind( "</ctx>" );
    if( openEnd == std::string_view::npos || closeAt == std::string_view::npos || closeAt <= openEnd ) { return std::nullopt; }
    return RootBody{ openEnd, closeAt };
}

// ── TL1 M2, SAME-DIRECTORY TAIL LEAD (results/F1_TAILRANK_1118/READOUT.md §3, the one post-hoc lead with zero flips on both design
// halves; pre-registered FRESH as lane TL1's PREREG M2, confirmed once on T5e). Inside the top-level <tail>, rows 1..kGuardTailRows
// keep their place — they are the rows G's guard protects and on F1's design set every in-12 KB tail-only group sat at row <= 27 — and
// rows past it are stably partitioned: a row whose p= file sits in the DIRECTORY of a top-kSameDirHeadRank <sigs> <d> row first, then
// every other row, each part in its own order. F1's measure of that signal (P1t): 2.29x the needed-row base rate pooled, covering
// 36-56 % of the needed tail rows; the broad signals that also reorder rows 1-24 (P1, R1, F1) flipped cells out of 12 KB, which is why
// the first 24 rows are fixed. Order only: the tail's rows are permuted inside its own text, so its size, G's guard (it reads tail
// row kGuardTailRows) and the tail's size are unchanged. The tail's own legend says how its rows were collected, so the reorder rides
// with a clause that states it (kTailSameDirClause, below): the emitter writes it into the answer-first document legend and this pass reorders only where it
// is, so the legend and the order cannot disagree. RIPWIRE_NO_TAIL_SAMEDIR (any value) turns both off.
inline constexpr std::size_t kSameDirHeadRank = 5;
[[nodiscard]] inline bool tailSameDirOn() noexcept { return std::getenv( "RIPWIRE_NO_TAIL_SAMEDIR" ) == nullptr; }

// The directory of a printed path: everything before its last '/', "" for a root-level file; a trailing :line (:line-line,
// :line:col) suffix is not part of the path.
[[nodiscard]] inline std::string_view pathDirOf( std::string_view p ) noexcept
{
    const std::size_t slash = p.rfind( '/' );
    const std::size_t colon = p.find( ':', slash == std::string_view::npos ? 0 : slash );
    if( colon != std::string_view::npos && p.find_first_not_of( "0123456789:-", colon ) == std::string_view::npos ) { p = p.substr( 0, colon ); }
    const std::size_t cut = p.rfind( '/' );
    return cut == std::string_view::npos ? std::string_view() : p.substr( 0, cut );
}

// The directories of the <sigs> <d> rows ranked r <= kSameDirHeadRank (sorted, unique), read off the block's own rows.
[[nodiscard]] inline std::vector<std::string_view> headRowDirs( std::string_view view, const Block& sigs )
{
    std::vector<std::string_view> dirs;
    for( const Block& k : childBlocks( view, sigs.begin, sigs.end ) )
    {
        const std::string_view tag  = k.comment || k.name != "d" ? std::string_view() : view.substr( k.begin, view.find( '>', k.begin ) + 1 - k.begin );
        const std::string_view r    = attrOf( tag, "r" );
        const std::string_view p    = attrOf( tag, "p" );
        std::size_t            rv   = 0;
        const auto [ end, ec ]      = std::from_chars( r.data(), r.data() + r.size(), rv );
        const bool             rank = !r.empty() && ec == std::errc() && end == r.data() + r.size() && rv <= kSameDirHeadRank;
        if( rank && !p.empty() ) { dirs.push_back( pathDirOf( p ) ); }
    }
    std::ranges::sort( dirs, rw::sortutil::svLess );
    dirs.erase( std::ranges::unique( dirs ).begin(), dirs.end() );
    return dirs;
}

// The <tail> block's text with rows past kGuardTailRows partitioned same-directory first (unchanged when nothing qualifies, the tail
// has kGuardTailRows rows or fewer, or its rows are not one contiguous run of elements).
[[nodiscard]] inline std::string tailSameDirFirst( const std::string& tail, const std::vector<std::string_view>& dirs )
{
    const std::vector<Block> rows = childBlocks( tail, 0, tail.size() );
    const bool contiguous = std::ranges::adjacent_find( rows, []( const Block& a, const Block& b ) { return a.end != b.begin || a.comment || b.comment; } ) == rows.end();
    if( dirs.empty() || rows.size() <= kGuardTailRows || !contiguous ) { return tail; }
    const std::string_view view = tail;
    const auto near = [ & ]( const Block& r )
    {
        const std::string_view p = attrOf( view.substr( r.begin, view.find( '>', r.begin ) + 1 - r.begin ), "p" );
        return !p.empty() && std::ranges::binary_search( dirs, pathDirOf( p ), rw::sortutil::svLess );
    };
    std::string out( view.substr( 0, rows[ kGuardTailRows ].begin ) );
    for( const bool pass : { true, false } )
    {
        for( std::size_t i = kGuardTailRows; i < rows.size(); ++i )
        {
            if( near( rows[ i ] ) == pass ) { out.append( view.substr( rows[ i ].begin, rows[ i ].end - rows[ i ].begin ) ); }
        }
    }
    out.append( view.substr( rows.back().end ) );
    return out;
}

// M2 on an assembled answer-first document: its top-level <tail> rewritten in place (same bytes, so every offset outside it holds).
// The clause that states M2's order. The emitter puts it in the answer-first document legend, right after the tail clauses, exactly
// where this pass will run (verbs_for.h tailSameDirLegend: the answer-first posture, the A/B handle unset, a tail that walks past page
// 0); this pass reorders a tail ONLY when the document legend carries it, so an order is never served without the sentence that
// states it, and --legend=first / --json / the MCP twin keep both their rank order and their wording.
inline constexpr std::string_view kTailSameDirClause =
    "; t order past row 24: files in the directory of a sigs row with r<=5 first, then the rest, each part in the order above";
static_assert( !kTailSameDirClause.contains( "--" ), "a legend clause rides inside an XML comment: no double hyphen (G4)" );

// Does the document legend (the comments after the last row block; a CDATA body can spell the same text) state M2's order?
[[nodiscard]] inline bool legendStatesTailSameDir( std::string_view doc, const std::vector<Block>& bl ) noexcept
{
    const auto last = std::ranges::find_if( bl.rbegin(), bl.rend(), []( const Block& b ) { return !b.comment; } );
    const std::size_t from = last == bl.rend() ? 0 : last->end;
    return std::any_of( bl.begin(), bl.end(), [ & ]( const Block& b )
                        { return b.comment && b.begin >= from && doc.substr( b.begin, b.end - b.begin ).contains( kTailSameDirClause ); } );
}

// Returns whether the tail's order changed (never without the legend clause that states it).
inline bool tailSameDirInPlace( std::string& doc )
{
    const std::optional<RootBody> rb = rootBody( doc );
    const std::vector<Block>      bl = rb ? topLevelBlocks( doc, rb->openEnd + 1, rb->closeAt ) : std::vector<Block>{};
    if( !legendStatesTailSameDir( doc, bl ) ) { return false; }
    const auto named = [ & ]( std::string_view n ) { return std::ranges::find_if( bl, [ & ]( const Block& b ) { return !b.comment && b.name == n; } ); };
    const auto tail = named( "tail" ), sigs = named( "sigs" );
    if( tail == bl.end() || sigs == bl.end() ) { return false; }
    const std::string permuted = tailSameDirFirst( doc.substr( tail->begin, tail->end - tail->begin ), headRowDirs( doc, *sigs ) );
    ENSURES( permuted.size() == tail->end - tail->begin, "tailSameDirFirst permutes the tail's rows: its size cannot move" );
    if( doc.compare( tail->begin, permuted.size(), permuted ) == 0 ) { return false; }
    doc.replace( tail->begin, permuted.size(), permuted );
    return true;
}

// The order knobs a caller hands answerFirst (each read from argv or the A/B environment by the caller, never here).
struct AnswerFirstAsk
{
    bool callersLead = false;   // T-B: the task asks who calls the <callers by="subject"> block's subject
    bool tailSameDir = false;   // TL1 M2 (only where the document legend states it: tailSameDirInPlace)
};

// T-B: the of= of the answer's top-level <callers by="subject"> block, still XML-escaped as the answer prints it; "" when there is
// none. Read from the TOP-LEVEL scan, never a text search: a CDATA body can spell the same open tag.
[[nodiscard]] inline std::string_view subjectCallersOf( std::string_view doc )
{
    const std::optional<RootBody> rb = rootBody( doc );
    if( !rb ) { return {}; }
    const std::vector<Block> blocks = topLevelBlocks( doc, rb->openEnd + 1, rb->closeAt );
    const std::size_t        j      = subjectCallersBlock( doc, blocks );
    if( j == std::string_view::npos ) { return {}; }
    const std::string_view open = doc.substr( blocks[ j ].begin, doc.find( '>', blocks[ j ].begin ) - blocks[ j ].begin );
    const std::size_t      at   = open.find( " of=\"" );
    if( at == std::string_view::npos ) { return {}; }
    const std::size_t from = at + 5, to = open.find( '"', from );
    return to == std::string_view::npos ? std::string_view() : open.substr( from, to - from );
}

// Permute one finished --for answer in place. Returns whether it was rewritten. `ask.callersLead` (T-B): the task asks who calls the
// subject the <callers by="subject"> block answers, so that block leads; `ask.tailSameDir` (TL1 M2): the tail's same-directory lead.
//
// Every byte of every block is copied unchanged; only their order moves. The ENSURES below is the contract:
// a permutation that changed the document's size would be a different change wearing this one's name.
inline bool answerFirst( std::string& doc, const AnswerFirstAsk& ask = {} )
{
    const std::string_view        view = doc;
    const std::optional<RootBody> rb   = rootBody( view );
    if( !rb ) { return false; }
    const std::size_t openEnd = rb->openEnd, closeAt = rb->closeAt;

    const std::vector<Block> blocks = topLevelBlocks( view, openEnd + 1, closeAt );
    if( blocks.empty() ) { return false; }   // not a shape this pass understands: served unchanged

    const std::size_t lead = ask.callersLead ? subjectCallersBlock( view, blocks ) : std::string_view::npos;
    if( lead == std::string_view::npos && !ask.tailSameDir && !permutationWouldMove( view, blocks ) ) { return false; }

    std::string out;
    out.reserve( doc.size() );
    out.append( view.substr( 0, openEnd + 1 ) );

    appendAnswerFirst( view, blocks, out, lead );
    out.append( view.substr( closeAt ) );
    if( ask.tailSameDir ) { (void)tailSameDirInPlace( out ); }   // TL1 M2, on the assembled document (its root closed)

    // THE PERMUTATION CONTRACT. Not an assertion of taste: if this ever fails, the pass has dropped or
    // duplicated a block, and the band's whole safety argument — no row removed, so no gold lost — is void.
    // DISCLOSE rather than a trapping self-check: Release deletes the fallback behind a trap, and this IS the
    // fallback. (test/selfcheckcheck.sh (A) refuses the retired macro spellings anywhere outside its own
    // history list, so this note names the mechanism instead of the old names; Diagnostics.h:545 holds the
    // rename record, and the code is the authority over any document.)
    if( out.size() != doc.size() )
    {
        AnswerFirstFallback sink;
        DISCLOSE( sink, AnswerFirstFallback::DisclosureWhy::SizeChanged,
                  "foranswerfirst: the permuted answer changed size — serving the original, unpermuted" );
        return false;
    }
    if( out == doc ) { return false; }   // nothing moved (an ask that found nothing to reorder)
    doc.swap( out );
    return true;
}

}   // namespace rw::answerfirst
