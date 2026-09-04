#pragma once

// pageview.h — §P8 ("Contract-level" bullets 1+2): the ONE paging window
// and the ONE root-element disclosure every high-cardinality verb shares, so the vocabulary cannot drift
// between them and a single parser reads them all.
//
// A separate header (not folded into serialize.h, which another wave owns, and not left in main.cpp, whose
// verbs are only two of the three callers) for the same reason ownersview.h exists: presentation-layer logic
// that more than one serializer needs lives one file away from all of them. Callers: main.cpp
// (--hotspots/--clones/--cochange/--owners/--communities/--grep/--match/--tree/--callers/--callees/--lint/
// --impact/--uses), serialize.h (--deps), crossref.h (--whereis) and docdrift.h (--doc-drift).
//
// It is the ONLY paging vocabulary. A second one DID grow beside it — main.cpp's pageAttr() emitted a bare
// ` offset= limit=` for --callers/--callees/--tree, and packDeps() hand-rolled the same two attributes for
// --deps. Those four CUT their rows correctly but disclosed no total/has_more/next_offset, so they carried
// bug 1's real damage (a loop that cannot terminate) while looking paginated. pageAttr() is deleted rather
// than deprecated: a helper that emits a strict subset of this one is indistinguishable from a bug at the
// call site, and leaving it reachable is how the fork happened the first time.
//
// THE TWO BUGS THIS CLOSES
//   1. --limit/--offset accepted and IGNORED by ~10 verbs. `--cochange --limit=3` emitted 30 rows, so a
//      paging loop over it re-served page 0 forever — it never terminated and never errored.
//   2. Silent caps. --hotspots said ranked="185" and printed 40; --cochange pairs="363" → 30; --whereis
//      hits="2560" → 60; --clones groups="36" type3="108" while 76 <group> rows followed, so NEITHER
//      attribute was the row count. The caps themselves are sane defaults and stay — they are now raisable
//      with the newly-honored --limit, and they always say what they dropped.

#include <algorithm>
#include <cstddef>
#include <cstdio>
#include <string>

// ============================================================================================================
// THE TRUNCATION VOCABULARY — normative. §P8 ("Vocabulary" bullet 1) counted SIX spellings for "this report
// dropped rows"; a parser that reads one verb could not read the next. This block is the ONE statement of the
// convention. Every emitter that can truncate references it BY NAME ("see pageview.h, THE TRUNCATION
// VOCABULARY") instead of restating it, so the wording cannot fork again. Gate: test/truncvocabcheck.sh.
//
//   1. shown="S"            the rows this run actually PRINTED. A report with several INDEPENDENT listings
//                           uses the noun-prefixed form shown_<noun>="S", one per listing (--communities'
//                           shown_modules= / shown_bridges=).
//
//   2. the TOTAL            total="T" where the report has no other name for it (the paging half below,
//                           --recall); otherwise the report's own count attribute — hits=, modules=,
//                           bridges=, reaches=, seam_pairs=, names=, count=, rows=. Row-count SPELLINGS are
//                           deliberately not unified here (§P8's separate "~25 spellings" bullet); what is
//                           unified is that every one of them has a shown=/capped= companion pair.
//
//   3. capped="0|1"         the truncation bit for the shown= in the SAME element: 1 ⇔ rows were dropped
//                           (S < T), 0 ⇔ the listing is complete. Noun-prefixed listings use
//                           <noun>_capped="0|1". It is ALWAYS emitted when its shown= is emitted — a caller
//                           never has to read a MISSING attribute as "nothing was capped". It is a BOOLEAN,
//                           never a count (--abi used to print the dropped-row COUNT under this name; that
//                           count is `dropped=` now). If a verb emits no shown=, it emits no capped= either
//                           (--skill-scan emits the pair only on a capped scan; that is conformant).
//                           M2 (capture-audit 2026-09-04): capped="1" ⇒ the paging half (rule 6) is on the
//                           SAME element, HOWEVER the window was set — a default display cap included. The
//                           audited binary printed `shown="40" capped="1"` and nothing else on a bare
//                           --impact, so an agent could not page from the answer it was handed; the quintet
//                           appeared only once it re-issued the call with a --limit it had to invent. Now a
//                           cut listing always says total=, has_more=, next_offset= (and limit="0", rule 7).
//                           On a page PAST THE END (offset ≥ total) shown="0" capped="1" has_more="0": the
//                           bit compares the page to the total, nothing was cut — the offset skipped it all.
//
//   4. <noun>_capped="1"    with NO shown_<noun>= in the element: the TOTAL ITSELF is a floor — the scan or
//      (floor marker)       budget stopped before it could finish counting, so <noun>= is a lower bound.
//                           hits_capped= (--grep/--match/--pattern), findings_capped= (--lint/--ensemble/
//                           --quality-panel), count_capped= (a --lint <rule> row). "1" ⇒ floor; "0" or
//                           ABSENT ⇒ the total is exact (--lint's §P0.2 legend: "Absent = nothing was
//                           capped and every count= is a total").
//                           H8 (capture-audit 2026-09-04): a fired marker is a COLLECTION cut, and the paging
//                           half must not contradict it. The audited binary printed `hits_capped="1"` beside
//                           `capped="0" has_more="0" total="5000"` — the complete-last-page lie an agent's
//                           has_more loop believes. So whenever the marker fires, the same root ALSO carries
//                           counts_floor="1" (every count on this element is a floor; the cause is the
//                           marker beside it — the same attribute the graph verbs use for the same reading,
//                           see graphlegend.h) and capped="1" (rows exist that no page holds; has_more= keeps
//                           its window meaning, so a loop still terminates). pageDisclosure's
//                           `collectionCapped` argument is the one place that rule is implemented; every
//                           emitter of a rule-4 marker passes its cap there under the /*collectionCapped=*/
//                           annotation (test/collectioncapcheck.sh arm (D) reads src/ for exactly that).
//
//   5. capped="1" on a      a payload trimmed by a BYTE budget rather than a row cap, on the trimmed element
//      byte-trimmed element itself, WITH shown=/total= (capture-audit 2026-09-04): --for's <sigs shown="S"
//                           total="T" capped="1"> (the rank-adaptive ladder) — T rows handed to the ladder, S
//                           printed; S == T means every row survived but was shrunk. Absent ⇒ untrimmed.
//                           This replaced payload="capped", a string enum only string-matching could read,
//                           and then a BARE capped="1" that said "trimmed" without saying how much — the
//                           one element in the tool whose capped= rode without its pair (truncvocabcheck (F)).
//
//   6. the paging half      (below) always describes the report's PRIMARY, --limit/--offset-windowed
//                           listing. A secondary listing in the same report never gets paging attributes —
//                           it discloses through its own shown_<noun>=/<noun>_capped= pair.
//
//   7. limit="0" on OUTPUT  (§B12.4) the defined sentinel for "no explicit --limit was given": the verb's
//                           own default page size shaped the window (--offset alone, or — M2 — a bare run
//                           whose default cap cut rows). It is never a zero-row page — the INPUT flag refuses
//                           --limit=0 — and both dialects share it (the two PageSyntax tables print the same
//                           value). Documented user-side in --help's --limit paragraph and, IN BAND, in
//                           kPageRaiseCapClause below. Before M2 the bare run never emitted it, so three
//                           legends described an attribute no bare document carried.
// ============================================================================================================

namespace rw
{

// The "you can page this" sentence a capping verb's own legend prints, so rule 7 above is defined on the
// FIRST SCREEN of the output and not only in --help and this header. §B12.4 defined limit="0" in both of
// those places but nowhere a reader of the XML could see it, and it is the one paging attribute whose value
// looks like a bug (a zero-row page) when it is in fact "no explicit limit was given".
//
// Adopted by the two most-walked paging verbs, --grep and --impact, which had two copies of the clause
// between them; the other ~12 legends still carry their own literal copy of the first sentence, so this is a
// fragment two verbs SHARE rather than one every verb reads. Anything adopting it gets rule 7 for free.
// Trailing space-free and punctuation-free so a caller decides whether ". " or " " follows.
inline constexpr const char* kPageRaiseCapClause =
    "raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a "
    "paging loop can continue from it); on the root, limit=\"0\" means no explicit limit was given and the verb's "
    "own default page size shaped the window — never a zero-row page";

// The window over an ALREADY-SORTED result of `total` rows. Half-open [begin,end). Default (limit<=0) is the
// whole thing from `off`, so an un-paginated caller is byte-unchanged. Deterministic: because the row list is
// sorted, --offset=N is the exact continuation of the previous --limit=N page — no row is dropped or
// duplicated across the seam. offset past the end → an empty page (begin==end==total), never out of range.
struct PageWindow { std::size_t begin, end; };

inline PageWindow pageWindow( std::size_t total, int limit, int offset ) noexcept
{
    const std::size_t off = offset > 0 ? std::min<std::size_t>( std::size_t( offset ), total ) : 0;
    if( limit <= 0 )
    {
        return { off, total }; // unbounded from `off` (offset alone still applies)
    }
    const std::size_t end = std::min<std::size_t>( off + std::size_t( limit ), total );
    return { off, end };
}

// The row cap a paging verb actually applies: an explicit --limit always beats the verb's historic display
// default (40 hotspot files, 30 co-change pairs, 60 whereis hits, 100 grep hits, 30 communities …). One
// place, so "does --limit override the default cap?" has exactly one answer across the tool.
inline int effectiveRowCap( int pageLimit, int historicCap ) noexcept
{
    return pageLimit > 0 ? pageLimit : historicCap;
}

// ── LB-G (r10 GitNexus round) — the NEIGHBOUR family's two display caps ──────────────────────────────────
// --callers/--callees/--impact/--uses answer one question ("what touches this symbol") and had two
// different postures: --impact capped at a bare literal 40, the other three at nothing at all.
// `--callers=bulk_create` on django was 175 rows / 17,694 B — the largest single answer of that round's
// 48-query sweep — and 171 of the 175 rows were `tests/`. Named here rather than left as literals at four
// call sites so the family cannot drift apart again, and split in TWO because the halves count different
// things:
//
//   * kCallHierarchyRowCap — SYMBOL rows (--callers/--callees/--impact). 40 is --impact's own number since
//     §P8; adopting it is what makes this one family rather than three verbs that happen to agree today.
//   * kUseSiteRowCap — use SITES (--uses). A site is a reference, several per symbol, which is the unit
//     --grep counts, so it takes --grep's 100 rather than the symbol cap. A symbol-sized cap on a
//     site-sized listing would cut a 40-symbol answer down to about a dozen symbols' worth of sites.
//
// Both are DEFAULTS, never ceilings: effectiveRowCap above lets --limit=N beat either, and every capped
// answer discloses shown=/capped= plus has_more=/next_offset= so a paging loop terminates.
inline constexpr int kCallHierarchyRowCap = 40;
inline constexpr int kUseSiteRowCap       = 100;

// ── LB-H (r10 GitNexus round) — the display cap on --impact's SECONDARY import tier ──────────────────────
// Deliberately the SAME 40 as the symbol rows above rather than a third number: it counts a comparable
// unit (one row per file, one row per symbol) on the same screen, and a second calibration nobody could
// re-derive is how this family drifted apart the first time. It is NOT raisable by --limit — rule 6 above
// reserves the paging half for the PRIMARY listing, so a secondary one discloses through
// shown_importers=/importers_capped= and nothing else. Nothing is hidden by that: importers= on the root
// is always the full count, and --uses=SYM lists the import SITES under its own, separate cap.
inline constexpr int kImportReachRowCap   = 40;

// The values pageDisclosure() renders under EVERY PageSyntax (XML attrs and §A3a/§A4c JSON keys) — hoisted
// so every format's rendering shares the ONE isCapped/hasMore/paging decision instead of re-deriving it
// (a real duplicate found by --quality-delta when a separate JSON mirror briefly landed next to this: same
// branches, same arithmetic, different snprintf format string — the PageSyntax table replaced it). `active`
// is false only for the "!paging && !discloseCap" no-op case, in which nothing is emitted.
struct PageDisclosureValues
{
    bool        active;
    unsigned    capped;
    bool        paging;
    unsigned    hasMore;
    std::size_t nextOrTotal;    // next_offset when hasMore, else rowTotal (pageDisclosure's existing convention)
    int         offsetOut;
    int         limitOut;
    bool        floor;          // H8: a collection cap fired — counts_floor rides after the paging half
};

inline PageDisclosureValues computePageDisclosure( std::size_t rowsShown, std::size_t rowTotal, std::size_t windowEnd,
                                                    int limit, int offset, bool discloseCap, bool collectionCapped = false ) noexcept
{
    const bool explicitWindow = limit > 0 || offset > 0;
    if( !explicitWindow && !discloseCap && !collectionCapped )
    {
        return { false, 0, false, 0, 0, 0, 0, false };
    }

    // M2 (capture-audit 2026-09-04, rule 3): the paging half rides whenever the listing was CUT, not only
    // when the caller spelled a window — a default display cap is a window too, and the agent holding
    // that answer needs next_offset= exactly as much. `paging` therefore means "emit the paging half".
    // H8 (rule 4): a fired COLLECTION cap is a cut too — rows exist that no page holds — so capped="1"
    // is forced and the floor marker rides; has_more= keeps its window meaning (a loop still terminates).
    const unsigned capped  = ( rowsShown < rowTotal || collectionCapped ) ? 1u : 0u;
    const bool     paging  = explicitWindow || capped != 0u;
    const unsigned hasMore = paging && windowEnd < rowTotal ? 1u : 0u;
    return { true, capped, paging, hasMore, hasMore ? windowEnd : rowTotal,
             offset > 0 ? offset : 0, limit > 0 ? limit : 0, collectionCapped };
}

// The root-element disclosure, in two independent halves emitted in ONE call so the attribute ORDER is fixed
// tool-wide (THE TRUNCATION VOCABULARY above, rules 1-3 and 6). Writes into `buf` (caller-owned), returns it.
//
//   cap half — ` shown="S" capped="0|1"`, emitted whenever `discloseCap`, --limit or no --limit:
//       S = the rows this run actually printed; capped="1" ⇔ S < the true row total. This is bug 2's fix,
//       and it is the ONE deliberate break in a capping verb's pre-§P8 un-paginated byte shape. Pass
//       `discloseCap=false` on a verb that never capped, to keep its opening tag byte-identical.
//
//   paging half — ` total="T" has_more="0|1" next_offset="N" offset="M" limit="L"`, emitted when
//       --limit/--offset is active (and then the cap half is forced on too, so `shown=` is never missing
//       from a page) AND — M2 — whenever the cap half says capped="1", so a default-window answer that cut
//       rows is pageable without a second guessed call (limit="0" then, rule 7). This is the six-attribute
//       vocabulary --lint established. has_more/next_offset are what let a paging loop TERMINATE.
//
// `windowEnd` is the half-open end of the emitted window (pageWindow().end), so next_offset is the exact
// offset of the next unseen row; with nothing left it reports the total (--lint's convention).
//
// §A4c: the SAME seven facts also have to reach the --json siblings, and the way NOT to do that is a second
// copy of the body below with the quotes moved around — a --quality-delta pass flags exactly that as a new
// clone of a reused helper, and a cloned emitter is how the XML and JSON vocabularies would drift apart one
// round from now (which is the whole failure this file exists to prevent). So the SPELLING is a declarative
// two-row table and the LOGIC is one function: which fields, in which order, on which condition is stated
// once, and each surface supplies only its own punctuation.
struct PageSyntax
{
    const char* capOnly;      // printf: rowsShown, cappedLiteral
    const char* full;         // printf: rowsShown, cappedLiteral, rowTotal, hasMoreLiteral, nextOffset, offset, limit
    const char* pagingOnly;   // printf: rowTotal, hasMoreLiteral, nextOffset, offset, limit — rule 1's noun-prefixed
                              // exception (pagingDisclosure below), where the caller spelled its own shown_<noun>= pair
    const char* yes;          // how this surface spells a true boolean
    const char* no;
    const char* floor;        // H8: the floor marker appended when a COLLECTION cap fired — the same spelling
                              // graphlegend.h's kGraphCountFloorAttrXml/Json use (one attribute, one reading:
                              // "every count on this element is a floor"; the cause is the sibling marker)
};
inline constexpr PageSyntax kXmlPageSyntax
{
    " shown=\"%zu\" capped=\"%s\"",
    " shown=\"%zu\" capped=\"%s\" total=\"%zu\" has_more=\"%s\" next_offset=\"%zu\" offset=\"%d\" limit=\"%d\"",
    " total=\"%zu\" has_more=\"%s\" next_offset=\"%zu\" offset=\"%d\" limit=\"%d\"",
    "1", "0",
    " counts_floor=\"1\""
};
inline constexpr PageSyntax kJsonPageSyntax
{
    ",\"shown\":%zu,\"capped\":%s",
    ",\"shown\":%zu,\"capped\":%s,\"total\":%zu,\"has_more\":%s,\"next_offset\":%zu,\"offset\":%d,\"limit\":%d",
    ",\"total\":%zu,\"has_more\":%s,\"next_offset\":%zu,\"offset\":%d,\"limit\":%d",
    "true", "false",         // JSON spells its booleans as booleans; a leading comma splices after the caller's own keys
    ",\"counts_floor\":true"
};

// ONE function, table-selected — not an XML body plus a JSON body that happen to agree today, and not two
// one-line wrappers either (a --quality-delta pass reads even those as a clone pair, and it is right to:
// two entry points is one more than the vocabulary needs). A JSON caller passes kJsonPageSyntax; every XML
// caller keeps the byte-identical default and never mentions the table at all.
// `collectionCapped` (H8): true when the verb's OWN collection cap fired (the rule-4 marker it emits beside
// this block — hits_capped=/findings_capped=). Callers pass it under a /*collectionCapped=*/ annotation so
// test/collectioncapcheck.sh arm (D) can read, from src/ alone, that every rule-4 emitter feeds it.
inline const char* pageDisclosure( char* buf, std::size_t bufCap, std::size_t rowsShown, std::size_t rowTotal,
                                   std::size_t windowEnd, int limit, int offset, bool discloseCap,
                                   const PageSyntax& syn = kXmlPageSyntax, bool collectionCapped = false ) noexcept
{
    const PageDisclosureValues v = computePageDisclosure( rowsShown, rowTotal, windowEnd, limit, offset, discloseCap, collectionCapped );
    if( !v.active ) { buf[0] = '\0';  return buf; }

    const char* isCapped = v.capped ? syn.yes : syn.no;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-nonliteral"
    int written = 0;
    if( !v.paging )
    {
        written = std::snprintf( buf, bufCap, syn.capOnly, rowsShown, isCapped );
    }
    else
    {
        written = std::snprintf( buf, bufCap, syn.full, rowsShown, isCapped, rowTotal, v.hasMore ? syn.yes : syn.no,
                                 v.nextOrTotal, v.offsetOut, v.limitOut );
    }
    if( v.floor && written > 0 && std::size_t( written ) < bufCap )
    {
        std::snprintf( buf + written, bufCap - std::size_t( written ), "%s", syn.floor );
    }
#pragma clang diagnostic pop
    return buf;
}

// The PAGING HALF ALONE — rule 1's noun-prefixed exception, and the ONLY sanctioned way to emit a page
// without a bare shown=. A report with several INDEPENDENT listings already spells its primary listing's
// row count as shown_<noun>=/<noun>_capped= (--communities' shown_modules=/modules_capped=, which stay
// correct under --limit because they are computed from the SAME window). Adding pageDisclosure's bare pair
// there stated one fact twice under two names — always equal, so a parser had to know they were the same
// listing to avoid double-counting it. §P8/N4 dropped the bare pair, and this variant is what makes that
// safe: the page still discloses its rows, just under the noun-prefixed name rule 1 already required.
//
// So bug 1's promise is unchanged in substance — a page NEVER lacks a row count — and its exact wording is
// now: every page carries shown= OR the shown_<noun>= of the listing being windowed, never neither.
// Signature mirrors pageDisclosure minus `rowsShown`/`discloseCap`, which are precisely what the caller's
// own noun-prefixed pair already carries. Emits nothing when paging is inactive (byte-identical un-paged).
//
// §B7.1: table-selected like pageDisclosure above, for the same reason — --test-gate's JSON twin needs these
// five facts too, and a second body with the quotes moved around is exactly the clone that lets the two
// dialects drift. XML callers keep the default and are byte-identical (syn.yes/no are "1"/"0", which is what
// the old "%u" printed).
inline const char* pagingDisclosure( char* buf, std::size_t bufCap, std::size_t rowTotal,
                                     std::size_t windowEnd, int limit, int offset,
                                     const PageSyntax& syn = kXmlPageSyntax ) noexcept
{
    // M2: a CUT primary listing (windowEnd < rowTotal — the caller's own <noun>_capped="1") carries the
    // paging half on a bare run too, for the same reason pageDisclosure's cap half now does.
    const bool hasMore = windowEnd < rowTotal;
    if( limit <= 0 && offset <= 0 && !hasMore ) { buf[0] = '\0';  return buf; }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-nonliteral"
    std::snprintf( buf, bufCap, syn.pagingOnly, rowTotal, hasMore ? syn.yes : syn.no,
                   hasMore ? windowEnd : rowTotal, offset > 0 ? offset : 0, limit > 0 ? limit : 0 );
#pragma clang diagnostic pop
    return buf;
}

// Sized for the widest disclosure above: 3 × 20-digit size_t + 2 × 11-char int + the attribute/key names
// + the H8 floor marker.
inline constexpr std::size_t kPageDisclosureCap = 224;

}   // namespace rw
