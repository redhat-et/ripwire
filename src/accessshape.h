#pragma once

// accessshape.h — Phase A of the access-shape / chase-pointer colocation design (PLAN.md, "2026-08-06
// (evening, cont.) — access-shape / chase-pointer colocation plan, orchestrated"). Consumed ONLY by
// `--field-affinity` (src/fieldaffinity.h): classifies each `for`-loop's UPDATE clause as `index` (bare
// pointer/counter arithmetic advance) / `chase` (advance by reading the loop variable's own field, the
// classic `p = p->next` traversal shape) / `mixed` (both signals in the SAME loop) / `unknown` (neither —
// the fails-closed default, including every STL-iterator loop, per the plan's Open Question 2), then
// rolls the CHASE-shaped loops up into a per-FIELD tally so `--field-affinity` can flag which declared
// field is the traversal's chase pointer.
//
// THE QUESTION THIS ANSWERS, AND THE ONE IT DOES NOT. This does not run anything and does not resolve
// what a pointer points at — it is a purely SYNTACTIC classification of ONE shape: "does this loop's own
// UPDATE clause advance by pointer/counter arithmetic, or by dereferencing a field of the loop variable
// itself?" It answers that question ONLY for C-style `for(init;cond;update)` loops; range-for, while-loops
// and hand-written recursion are OUT OF SCOPE for v1 and always read `unknown` (see "NOT HANDLED" below) —
// disclosed, not silently absent.
//
// ── THE MECHANISM: the codebase's EXISTING AST re-query pass, not a byte scanner ───────────────────────
// Every signal below is a declarative TSQuery pattern run through `astQuery()` (ingest.cpp:7175) — the
// SAME shared engine `--lint`, the atoms-of-confusion pack (atoms.h) and `--nonlocal-state`'s cell
// discovery already run. This is deliberately NOT a hand-rolled byte scanner (contrast
// `fieldaffinity.h::scanMemberAccesses`, which is one, for a narrower and already-disclosed reason) and
// deliberately NOT a reuse of a retained parse tree: `ingest.cpp` calls `ts_tree_delete` at EVERY parse
// site in the file (astQuery's own worker loop, ingest.cpp ~7310-7356, is one of them) — no tree survives
// a call to be reused here, so this pays its own re-parse, exactly like `--lint` and `--match` do.
//
// ── THE FIVE QUERIES, and why five single-purpose ones instead of one with many captures ───────────────
// astQuery pushes EVERY capture in a matched pattern to its output, all tagged with the SPEC's tag (not
// per-capture) — so a query with N named captures becomes N output rows under one tag, and the caller
// cannot tell which row was which capture without inspecting content. The house pattern for this
// (atoms.h's candidate/exclusion span algebra) is: keep each query's OUTPUT-RELEVANT shape to what its
// tag alone can disambiguate, and correlate multiple signals in C++ by BYTE-SPAN CONTAINMENT, never by
// assuming capture order survives the flattening. Five tags:
//   as-loop    (for_statement) @c                          — every for-loop's own span (the unit).
//   as-update  (for_statement update: (_) @c)               — every for-loop's update-clause span alone,
//                                                              generic over plain/compound/comma-expression
//                                                              updates — the SCOPING WINDOW every signal
//                                                              below must fall inside, so a chase-shaped
//                                                              assignment in the LOOP BODY (a real and
//                                                              likely pattern: a traversal that also
//                                                              chases an unrelated pointer inside) can
//                                                              never be misread as this loop's advance.
//                                                              Verified against exactly that trap in this
//                                                              session (t2.cpp fixture, see PLAN.md).
//   as-ptrvar  for_statement initializer: … pointer_declarator … (identifier) @c
//                                                            — a loop variable declared with an EXPLICIT
//                                                              pointer type (`Node* p = …`). This is the
//                                                              type-visibility gate that keeps a bare STL
//                                                              iterator loop (`auto it = v.begin()`) from
//                                                              ever being read as `index`: `auto` has no
//                                                              pointer_declarator, so it can never satisfy
//                                                              this query, matching the plan's Open
//                                                              Question 2 default (unknown, fails closed).
//   as-crement (update_expression argument: (identifier) @c) — unary ++/-- on an identifier, repo-wide;
//                                                              scoped down to "inside THIS loop's update
//                                                              clause, on a name this SAME loop declared
//                                                              as a pointer" by the C++ correlation below.
//   as-chase   assignment_expression left: (identifier) @v right: (field_expression argument: (identifier)
//              @o field: (field_identifier)) @rhs (#eq? @v @o)
//                                                            — `IDENT = IDENT->field` / `IDENT = IDENT.field`,
//                                                              repo-wide; the #eq? is load-bearing — without
//                                                              it, `q = p->next` (advancing a DIFFERENT
//                                                              variable than the one being tested) would
//                                                              misread as a chase advance. `@rhs`'s own text
//                                                              (e.g. "p->next") is how the field NAME is
//                                                              recovered — parsed from the captured text
//                                                              after the last "->"/"." (see chaseFieldOf),
//                                                              never by trusting capture order.
//
// C-FAMILY ONLY, ENFORCED — same reason atoms.h states for its own queries: `update_expression`,
// `assignment_expression`, `field_expression` and `pointer_declarator` spellings compile against other
// grammars astQuery also indexes (some of the five patterns are C/C++-grammar-only by node-type spelling
// alone and simply never compile elsewhere; the rest are filtered post-hoc against layout::isCFamilyPath,
// the same predicate fieldaffinity.h already uses for the aggregate model this feeds).
//
// ── THE FOUR DISCRIMINATING TRAPS THIS DESIGN MUST GET RIGHT (test/accessshapecheck.sh pins all four) ──
//   for(Node* p=first; p!=first+n; ++p) p->touch();      -> index  (advance is pointer arithmetic on p;
//                                                                    the `->` in the BODY, a method CALL,
//                                                                    never enters an as-chase match at all)
//   for(Node* p=head; p; p=p->next) p->touch();          -> chase  (advance reads p's own `next` field)
//   for(auto it=v.begin(); it!=v.end(); ++it) …          -> unknown (no pointer_declarator on `it` — Open
//                                                                    Question 2's fails-closed default)
//   for(Node* p=head,*idx=first; p; p=p->next,++idx) …   -> mixed  (ONE loop, both signals, via the
//                                                                    comma-expression update clause)
//
// ── SELF-REFERENTIAL CHASE-FIELD CONFIDENCE — HANDLED, and explicitly NOT (honest limits) ───────────────
// The plan's original ambition names SEVEN self-reference shapes (typedef aliases, templates, smart-
// pointer unwrapping, cross-aggregate multi-hop links among them). Shipping all seven unverified would be
// exactly the overclaim SCOPE DISCIPLINE forbids. What ships now, real and gated:
//   HANDLED   — the field's AS-WRITTEN declared type (layout.h's FieldRow::type, e.g. "Node**" for a
//               `Node*` field per layout.h's own pointer-marker convention) contains the enclosing
//               aggregate's own indexed name as a WHOLE WORD (docdrift.h::hasWholeWord — the same
//               whole-word predicate the naming/doc-drift lenses already use, so "NodeExtra" cannot
//               satisfy "Node"). An EXACT match — the word appears and the type, punctuation stripped, is
//               otherwise just the aggregate name plus pointer/reference/array markers — is "self-ref".
//               The name appearing anywhere else in the spelling (inside `<…>` template arguments, after
//               `::`, etc.) is the weaker "tmpl-approx" bucket, named for the plan's own worked example
//               (`Node<Key>* cachedLookup`, an UNRELATED field that still contains "Node" as a whole word)
//               — disclosed as approximate, never silently promoted to "self-ref".
//   NOT HANDLED (falls to "" — no confidence, never guessed) — a typedef/using alias whose OWN spelling
//               does not textually contain the aggregate's name (`using NodePtr = Node*; NodePtr next;`
//               — layout.h does not expand typedefs into FieldRow::type, so "NodePtr" cannot be matched
//               against "Node" without a false-substring risk this file refuses to take); a smart pointer
//               whose template argument is itself an unexpanded alias; and any multi-hop chain through an
//               intermediate, differently-named type. All three are real gaps in the ORIGINAL plan's
//               ambition, not silently dropped — a field this pass cannot confirm contributes its chase
//               classification (report-only, see below) but never a shape_conf attribute.
// A chase field name declared by 2+ modeled aggregates (fieldaffinity.h's own FieldOwners ambiguity) is
// REFUSED by the caller (fieldaffinity.h checks ownership before calling chaseFieldConfidence at all) —
// this file has no aggregate index of its own and never guesses one. Two more caller-side refusals close
// the name-only attribution gap the same way: a chase field name declared by ZERO modeled aggregates
// (the traversal runs through a forward-declared / vendored / over-cap type — nothing to attach to), and
// a SOLE-owner candidate whose declared type carries no pointer/reference marker at all (a raw-pointer
// chase advance `p = p->f` cannot target an `int f` — attaching it would be a provably wrong guess;
// chaseTypeCanPoint below is the predicate). Both are tallied, disclosed floors, never silent drops.
//
// ── REPORT-ONLY, BY DESIGN, UNTIL A REAL VALIDATION SESSION RUNS ─────────────────────────────────────
// The plan requires >=85% precision on the shape_conf="self-ref" flagged set, measured against THREE real
// corpora with BLIND human review, before Phase B (fieldaffinity.h's sepCost boost) may consume this for
// anything ranking-affecting. That session has NOT run — it cannot be completed honestly in one sitting —
// so fieldaffinity.h applies this classification as a DISCLOSED, NON-RANKING attribute only
// (`chase="1" shape_conf="…"` on qualifying `<f>` rows) and its sepCost boost multiplier is a documented
// 1.0 (a no-op) until that session runs and clears the floor. See docs/FIELDAFFINITY.md §8.
//
// Determinism: loops are walked in (fileId, startByte) order, every rollup is a gtl::btree_map (sorted
// iteration, house rule: never std::map/std::unordered_map), and no wall clock is read.

#include "ingest.h"       // AstQuerySpec / AstMatch / astQuery
#include "layout.h"       // isCFamilyPath
#include "docdrift.h"     // hasWholeWord — the house whole-word predicate
#include "Diagnostics.h"  // VERIFY / DEGRADED_PATH_ALERT

#include "btree.hpp"       // gtl::btree_map — sorted iteration (house rule: never std::map)

#include <algorithm>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
namespace accessshape
{

// ── tuning ────────────────────────────────────────────────────────────────────────────────────────────

// SHARED astQuery budget (astQuery truncates the deterministically-sorted match list to this TOTAL, across
// all five tags together — not per tag). MEASURED against ripwire's own src/ (2026-08-06, warm, this
// session): as-loop=1209 as-update=1128 as-ptrvar=2 as-crement=1710 as-chase=0 hits — ~4000 total on a
// ~120-file, ~1500-symbol C++23 corpus. 50000 leaves >12x headroom over that measured total before the
// budget truncates anything (queryBudgetSaturated below discloses it if a corpus ever does saturate,
// making EVERY shape count a floor at once — astQuery's post-sort truncation is tag-blind).
inline constexpr std::size_t kQueryBudget = 50000;

// Cost ceiling on the CORRELATION pass (span-containment over the astQuery output), mirroring
// fieldaffinity.h's kMaxAggsModeled refusal-with-disclosure pattern. MEASURED, this session, warm,
// `time ./build/ripwire src --no-cache --field-affinity`, Apple M5 Pro: 0.14s wall with
// classifyAccessShapes() stubbed to a no-op vs 0.34-0.35s with it wired in — a real ~0.20s marginal cost
// (~2.4x baseline --field-affinity time) for 1209 real for-loops on ripwire's own ~120-file C++23 src/.
// 20000 is >16x that measured loop count, with headroom for a corpus an order of magnitude larger,
// refused-and-disclosed (loopsCapped) rather than silently truncated past it.
inline constexpr std::size_t kMaxLoopsModeled = 20000;

// ── the result model ─────────────────────────────────────────────────────────────────────────────────

enum class LoopShape : std::uint8_t
{
    Unknown = 0,
    Index   = 1,
    Chase   = 2,
    Mixed   = 3,
};

inline const char* shapeName( LoopShape s ) noexcept
{
    switch( s )
    {
        case LoopShape::Index: return "index";
        case LoopShape::Chase: return "chase";
        case LoopShape::Mixed: return "mixed";
        default:           return "unknown";
    }
}

// A byte-half-open span within one file, shared shape for every correlation step below.
struct Span
{
    std::uint32_t fileId = 0;
    std::uint32_t start  = 0;
    std::uint32_t end    = 0;
    std::uint32_t line   = 0;
};

inline bool contains( const Span& outer, const Span& inner ) noexcept
{
    return outer.fileId == inner.fileId && outer.start <= inner.start && inner.end <= outer.end;
}

// One classified `for`-loop.
struct LoopClassification
{
    Span          loop;
    Span          updateClause;          // zero-length end==start when the loop had no update: field
    LoopShape     shape       = LoopShape::Unknown;
    std::string   chaseField;            // "" unless shape is Chase or Mixed — the field name after -> / .
};

struct ShapeResult
{
    std::vector<LoopClassification> loops;
    std::size_t                     filesScanned = 0;
    std::size_t                     forLoops     = 0;     // as-loop rows, before kMaxLoopsModeled
    std::size_t                     loopsCapped  = 0;      // dropped by kMaxLoopsModeled — disclosed FLOOR
    std::size_t                     indexLoops   = 0, chaseLoops = 0, mixedLoops = 0, unknownLoops = 0;
    bool                            queryBudgetSaturated = false;   // astQuery returned exactly its budget — its
                                                                     // tag-blind post-sort truncation may have
                                                                     // dropped matches, so EVERY count above is a
                                                                     // floor at once (disclosed, never silent)
    std::vector<std::string>        uncompiledQueries;     // spec queries that compiled for NO grammar — those
                                                            // signals are entirely ABSENT (not truncated), so a
                                                            // classification relying on them degrades to unknown;
                                                            // should never fire for the five C/C++ patterns above

    // Chase-field rollup: declared field name -> distinct loops observed advancing via it (a FLOOR, same
    // convention as fieldaffinity.h's fns= — the number of DISTINCT loop sites, not a dynamic count).
    gtl::btree_map<std::string, std::uint32_t> chaseFieldLoops;
};

// ── query specs ──────────────────────────────────────────────────────────────────────────────────────

inline const char* kTagLoop    = "as-loop";
inline const char* kTagUpdate  = "as-update";
inline const char* kTagPtrVar  = "as-ptrvar";
inline const char* kTagCrement = "as-crement";
inline const char* kTagChase   = "as-chase";

inline std::vector<AstQuerySpec> accessShapeSpecs()
{
    std::vector<AstQuerySpec> specs;
    specs.push_back( { "(for_statement) @c", kTagLoop } );
    specs.push_back( { "(for_statement update: (_) @c)", kTagUpdate } );
    specs.push_back( { "(for_statement initializer: (declaration declarator: (init_declarator declarator: "
                       "(pointer_declarator declarator: (identifier) @c))))", kTagPtrVar } );
    specs.push_back( { "(update_expression argument: (identifier) @c)", kTagCrement } );
    specs.push_back( { "(assignment_expression left: (identifier) @v right: (field_expression argument: "
                       "(identifier) @o field: (field_identifier)) @rhs (#eq? @v @o))", kTagChase } );
    return specs;
}

// ── correlation helpers ──────────────────────────────────────────────────────────────────────────────

inline Span spanOf( const AstMatch& m ) noexcept
{
    return Span{ m.fileId, m.startByte, m.endByte, m.line };
}

// The chase field's name, parsed from an `as-chase` @rhs row's OWN text (e.g. "p->next" or "p.next") —
// never assumed from capture order, since astQuery flattens all three of a match's captures (@v, @o,
// @rhs) under the ONE "as-chase" tag. A row belongs to @rhs, not @v/@o, iff its text contains the
// operator: @v and @o are bare identifiers (#eq?-forced equal to each other) and never contain "->" or
// ".", so this filter is exact, not a heuristic.
inline bool isChaseRhsRow( const AstMatch& m ) noexcept
{
    return m.text.find( "->" ) != std::string::npos || m.text.find( '.' ) != std::string::npos;
}

inline std::string chaseFieldOf( const std::string& rhsText )
{
    std::size_t at = rhsText.rfind( "->" );
    std::size_t skip = 2;
    if( at == std::string::npos )
    {
        at   = rhsText.rfind( '.' );
        skip = 1;
    }
    if( at == std::string::npos )
    {
        return {};   // DEGRADE, never guess: an @rhs row that matched the query but has neither is a
                     // grammar surprise, not a field name — chaseFieldOf's caller drops the signal.
    }
    std::string field = rhsText.substr( at + skip );
    while( !field.empty() && ( field.front() == ' ' || field.front() == '\t' ) )
    {
        field.erase( field.begin() );
    }
    while( !field.empty() && ( field.back() == ' ' || field.back() == '\t' ) )
    {
        field.pop_back();
    }
    return field;
}

// WHY "first containing match" is always the CORRECT (innermost) one below, not a coincidence that
// happens to work on today's fixtures: astQuery's own output is sorted (fileId, startByte, endByte —
// ingest.cpp's astQuery sort comparator), and every per-tag vector built below is a straight filter of
// that sorted sequence, so entries sharing a fileId stay in ascending startByte order. A for-loop's OWN
// update clause always starts BEFORE any loop nested in its BODY (the body opens strictly after the
// header closes), so when a search below asks "which update-clause span does THIS loop's search find
// first", the first candidate whose span it contains is necessarily the earliest-starting one — which is
// this loop's own, never an inner loop's. An update clause cannot itself contain a nested for_statement
// either (expressions cannot embed statements in standard C/C++), so there is only ever one genuine
// candidate for that correlation regardless. No "tightest of several overlapping containers" algorithm is
// needed anywhere in this file; an earlier draft carried one unused and it was removed rather than kept
// as unexercised complexity (see `--quality-delta`'s dead-code kind, the reason this comment exists).

// ── the pass ─────────────────────────────────────────────────────────────────────────────────────────

inline ShapeResult classifyAccessShapes( const IngestResult& ing, std::size_t queryBudget = kQueryBudget )
{
    ShapeResult res;

    std::vector<std::string> uncompiled;
    const std::vector<AstMatch> ms = astQuery( ing, accessShapeSpecs(), queryBudget, &uncompiled );
    res.uncompiledQueries = uncompiled;
    // astQuery truncates its deterministically-sorted output to the budget AFTER collection, tag-blind —
    // a full return is the only observable saturation signal it exposes, so exactly-at-budget is disclosed
    // as "may have been truncated" (a floor marker), never read as a lucky exact fit.
    res.queryBudgetSaturated = ( ms.size() >= queryBudget );

    // C-FAMILY ONLY, ENFORCED (see file header) — same isCFamilyPath predicate fieldaffinity.h's own
    // aggregate model already uses, so "which files count" agrees between Phase A and the struct model
    // Phase B will index it against.
    auto keep = [ & ]( const AstMatch& m ) noexcept
    {
        return m.fileId < ing.files.size() && layout::isCFamilyPath( ing.files[ m.fileId ] );
    };

    gtl::btree_map<std::uint32_t, bool> seenFile;
    std::vector<Span> loopSpans, updateSpans, ptrVarSpans, crementSpans, chaseRhsSpans;
    std::vector<std::string> ptrVarNames, crementNames;   // parallel to ptrVarSpans / crementSpans
    std::vector<std::string> chaseFields;                 // parallel to chaseRhsSpans

    for( const AstMatch& m : ms )
    {
        if( !keep( m ) )
        {
            continue;
        }
        if( seenFile.find( m.fileId ) == seenFile.end() )
        {
            seenFile.emplace( m.fileId, true );
            ++res.filesScanned;
        }
        if( m.tag == kTagLoop )
        {
            loopSpans.push_back( spanOf( m ) );
        }
        else if( m.tag == kTagUpdate )
        {
            updateSpans.push_back( spanOf( m ) );
        }
        else if( m.tag == kTagPtrVar )
        {
            ptrVarSpans.push_back( spanOf( m ) );
            ptrVarNames.push_back( m.text );
        }
        else if( m.tag == kTagCrement )
        {
            crementSpans.push_back( spanOf( m ) );
            crementNames.push_back( m.text );
        }
        else if( m.tag == kTagChase && isChaseRhsRow( m ) )
        {
            chaseRhsSpans.push_back( spanOf( m ) );
            chaseFields.push_back( chaseFieldOf( m.text ) );
        }
    }

    res.forLoops = loopSpans.size();
    // Deterministic total order: (fileId, start) — astQuery's own worker threads already interleave by
    // completion, not source order, so every downstream pass in this file that depends on ORDER (the
    // display walk, the chaseFieldLoops rollup) needs one canonical sort, done exactly once, here.
    std::sort( loopSpans.begin(), loopSpans.end(),
              []( const Span& a, const Span& b ) noexcept
              {
                  if( a.fileId != b.fileId ) { return a.fileId < b.fileId; }
                  return a.start < b.start;
              } );
    if( loopSpans.size() > kMaxLoopsModeled )
    {
        res.loopsCapped = loopSpans.size() - kMaxLoopsModeled;
        loopSpans.resize( kMaxLoopsModeled );   // disclosed in the header as loops_capped= — silence would
                                                 // read as "no more loops exist", never true of a real repo
    }

    res.loops.reserve( loopSpans.size() );
    for( const Span& loop : loopSpans )
    {
        LoopClassification lc;
        lc.loop = loop;

        // The update clause: unambiguous — a for-loop's update field cannot itself contain a nested
        // for_statement, so ANY updateSpans row this loop's span contains is THE update clause (there is
        // at most one per for_statement by grammar construction).
        for( const Span& u : updateSpans )
        {
            if( contains( loop, u ) )
            {
                lc.updateClause = u;
                break;
            }
        }
        const bool hasUpdate = lc.updateClause.end > lc.updateClause.start;

        // chase signal: an as-chase @rhs row inside THIS loop's update clause specifically (never the
        // body — see the t2.cpp trap in the file header).
        if( hasUpdate )
        {
            for( std::size_t i = 0; i < chaseRhsSpans.size(); ++i )
            {
                if( contains( lc.updateClause, chaseRhsSpans[i] ) && !chaseFields[i].empty() )
                {
                    lc.chaseField = chaseFields[i];
                    break;
                }
            }
        }
        const bool chase = !lc.chaseField.empty();

        // index signal: a pointer-declared variable of THIS loop (as-ptrvar, scoped to the loop's own
        // span — the initializer clause) that is ALSO the operand of an as-crement row inside THIS loop's
        // update clause, matched by NAME (the two queries cannot share a capture, so identity is
        // established by comparing text, exactly like fieldaffinity.h's FieldOwners resolves names it
        // cannot structurally link).
        bool index = false;
        if( hasUpdate )
        {
            std::vector<std::string_view> ptrNamesHere;
            for( std::size_t i = 0; i < ptrVarSpans.size(); ++i )
            {
                if( contains( loop, ptrVarSpans[i] ) )
                {
                    ptrNamesHere.push_back( ptrVarNames[i] );
                }
            }
            if( !ptrNamesHere.empty() )
            {
                for( std::size_t i = 0; i < crementSpans.size() && !index; ++i )
                {
                    if( !contains( lc.updateClause, crementSpans[i] ) )
                    {
                        continue;
                    }
                    for( std::string_view pv : ptrNamesHere )
                    {
                        if( pv == crementNames[i] )
                        {
                            index = true;
                            break;
                        }
                    }
                }
            }
        }

        if( chase && index )      { lc.shape = LoopShape::Mixed;   ++res.mixedLoops;   }
        else if( chase )          { lc.shape = LoopShape::Chase;   ++res.chaseLoops;   }
        else if( index )          { lc.shape = LoopShape::Index;   ++res.indexLoops;   }
        else                      { lc.shape = LoopShape::Unknown; ++res.unknownLoops; }

        if( chase )
        {
            std::uint32_t& n = res.chaseFieldLoops[ lc.chaseField ];
            ++n;
        }

        res.loops.push_back( std::move( lc ) );
    }

    return res;
}

// ── Phase B's field-confidence lookup — see "SELF-REFERENTIAL CHASE-FIELD CONFIDENCE" above ────────────

enum class ChaseConfidence : std::uint8_t
{
    None       = 0,   // not confirmed — never guessed; the caller must not attach a shape_conf attribute
    TmplApprox = 1,   // the aggregate's name appears in the spelling, but not as a clean base-type match
    SelfRef    = 2,   // the field's declared type IS the enclosing aggregate (plus pointer/ref/array marks)
};

inline const char* confidenceName( ChaseConfidence c ) noexcept
{
    switch( c )
    {
        case ChaseConfidence::SelfRef:    return "self-ref";
        case ChaseConfidence::TmplApprox: return "tmpl-approx";
        default:                          return "";
    }
}

// Can a declared field of this AS-WRITTEN type spelling be the target of a raw-pointer chase advance at
// all? `p = p->f` requires `f` to be pointer-shaped; a spelling with no '*'/'&' marker anywhere (layout.h
// appends the declarator's own marker to FieldRow::type, so a genuine pointer field always carries one)
// provably cannot be, so a name-only sole-owner attribution to such a field is REFUSED, not guessed. The
// deliberate cost, same NOT-HANDLED axis as the typedef gap above: a smart-pointer field
// (`std::shared_ptr<Node> next`) has no marker either and is refused with it — a disclosed undercount
// (floor), which this file's contract prefers over a wrong attribution.
inline bool chaseTypeCanPoint( std::string_view fieldType ) noexcept
{
    return fieldType.find( '*' ) != std::string_view::npos || fieldType.find( '&' ) != std::string_view::npos;
}

// `fieldType` is layout.h's FieldRow::type — the AS-WRITTEN spelling (e.g. "Node**" for a `Node*` field,
// per layout.h's own pointer-marker convention; template/const/volatile spelling otherwise untouched).
// `aggName` is the enclosing aggregate's own indexed name. See the file header for exactly which of the
// plan's seven self-reference shapes this covers and which it honestly does not.
inline ChaseConfidence chaseFieldConfidence( std::string_view fieldType, std::string_view aggName ) noexcept
{
    if( fieldType.empty() || aggName.empty() )
    {
        return ChaseConfidence::None;
    }
    if( !docdrift::hasWholeWord( fieldType, aggName ) )
    {
        return ChaseConfidence::None;   // NOT HANDLED (typedef alias / unresolved multi-hop) — refuse, don't guess
    }
    // "Clean base match": strip a single run of trailing '*'/'&'/whitespace/array brackets and see if
    // what remains IS the aggregate name exactly — that is the ordinary `Node*`/`Node&`/`Node[]` case
    // layout.h itself models. Anything else that still contains the name (template args, `::` qualifiers,
    // an unrelated field like the plan's own `Node<Key>* cachedLookup` example) is the weaker bucket.
    std::string_view stripped = fieldType;
    while( !stripped.empty() &&
          ( stripped.back() == '*' || stripped.back() == '&' || stripped.back() == ' ' ||
            stripped.back() == '[' || stripped.back() == ']' ) )
    {
        stripped.remove_suffix( 1 );
    }
    return ( stripped == aggName ) ? ChaseConfidence::SelfRef : ChaseConfidence::TmplApprox;
}

}   // namespace accessshape
}   // namespace rw
