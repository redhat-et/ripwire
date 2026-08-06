#pragma once

// fieldaffinity.h — `--field-affinity[=STRUCT]`, the CACHE-LOCALITY lens.
//
// THE QUESTION. Every shipping struct-layout tool answers "where are the holes?" — pahole's padding
// report, clang-analyzer's optin.performance.Padding, PVS-Studio V802, Go's fieldalignment, -Wpadded.
// None answers the other one: "which fields are READ TOGETHER but declared far apart?" This lens does
// exactly that and nothing more — it diffs a statically inferred field CO-ACCESS graph against the
// DECLARED field order and 64-byte cache-line geometry, and reports the pairs that can never share a
// line. It advises; it never transforms (see THE GRAVEYARD below for why that distinction is the whole
// design).
//
// ── PRIOR ART: none of the ideas below are new, and this header claims none of them ──────────────────
// Chilimbi, Davidson & Larus, "Cache-Conscious Structure Definition", PLDI 1999 (the `bbcache` tool) is
// the origin of essentially every piece of the static half:
//   * an AST toolkit that STATICALLY ENUMERATES every field-access site, approximating a structure
//     instance as a <function, struct type> pair EXPLICITLY WITHOUT POINTER ANALYSIS — the authors
//     concede the approximation. That is the same approximation `attributeAccesses` below makes.
//   * a FIELD AFFINITY GRAPH (nodes = fields, edges = co-access).
//   * and the separation weight this file computes verbatim:
//         wt(fi,fj) = ( cache_block_size - dist(fi,fj) ) / cache_block_size
//     with dist = bytes between field starts. See `separationWeight` — the formula is CITED there, not
//     invented there.
//   * validated on UltraSPARC HARDWARE COUNTERS. Hardware-counter validation of layout work is 1999.
// Hundt, Mannarswamy & Chakrabarti, "Practical Structure Layout Optimization and Advice", CGO 2006
// (HP's SYZYGY compiler, HP-UX Itanium) went further and is the closest ancestor of BOTH halves: it has
// an explicit ADVICE MODE that reports instead of transforming, prints a field affinity graph and
// read/write dominance, supports STATIC (Wu-Larus style) as well as profile weighting, and reports
// PER-FIELD D-CACHE MISS COUNTS obtained by correlating Itanium PMU sampling back to individual field
// accesses. Ye, Lis & Fedorova's D-SAG (MEMSYS 2019) is its modern heir; Rohwedder et al.'s RebaseDL
// (CC 2024) is the purely-static LLVM argument that profiling is not required.
//
// WHAT IS ACTUALLY NEW HERE IS NARROW AND IS ENGINEERING, NOT SCIENCE: a SOURCE-LEVEL, CROSS-LANGUAGE-
// CAPABLE, NO-DEBUG-INFO, WHOLE-REPO-RANKING implementation. pahole needs DWARF; Hundt's ran inside one
// proprietary compiler on a dead architecture; D-SAG needs its own toolchain; RebaseDL is LLVM-internal;
// lshaz (the one adjacent shipping tool) is Linux-x86-only, needs compile_commands.json plus LLVM dev
// libraries, and answers the INVERSE question — which fields to SEPARATE to avoid false sharing. Nothing
// ranks a whole repository from source bytes alone. That, and only that, is the contribution.
//
// ── THE GRAVEYARD, and why this is ADVICE ONLY ───────────────────────────────────────────────────────
// Five serious compiler attempts at automatic field layout are dead: GCC's -fipa-struct-reorg (shipped
// 4.3-4.6, REMOVED in 4.7 — "did not always work correctly, nor did they work with LTO"), LLVM's
// GlobalOpt heap SRA (removed 2021, PR50027 "could crash or miscompile"), EfficiencySanitizer's
// cache-fragmentation tool (removed 2019), StructFieldCacheAnalysis (never landed), and Qualcomm's 2024
// AoS->SoA RFC (dead: C type info is unreliable under pointer casts and type punning). Every one that
// died on SOUNDNESS died because a COMPILER must prove a pointer really points at a pool of that struct.
// A tool that only advises cannot miscompile, so it is not exposed to that failure mode at all. This
// lens therefore emits findings and never a transformation: `--field-affinity` has no rewrite mode.
//
// ── THE TWO HONEST LIMITS, both disclosed IN THE OUTPUT (non-negotiable #3) ──────────────────────────
// (1) STATIC ACCESS COUNTS ARE NOT DYNAMIC FREQUENCY. One field touched inside a hot loop beats fifty
//     touched on cold paths, and no static analysis can tell them apart. Pair counts here are a FLOOR
//     (counts_floor="1"): the number of DISTINCT INDEXED FUNCTIONS that co-access the pair, never a
//     dynamic count. The one weighting available without running anything is call-graph reachability,
//     so `w=` is sum over co-accessing functions of ( 1 + fan-in ) — a static PROXY for hotness,
//     labelled weighting="fanin-floor" in the header and never presented as a frequency.
// (2) TRUE sizeof/alignment IS UNKNOWABLE FROM SOURCE under templates, virtuals, base classes and a
//     target ABI this process cannot see. All offset arithmetic is layout.h's LP64 standard-layout MODEL
//     and inherits its refusals verbatim: a definition that layout.h marks modeled="0" contributes NO
//     geometry finding here, only its co-access graph. Every geometry number carries model="lp64-approx".
//
// ── WHICH WAY IS BAD (the filter that has caught three bad metrics in this design already) ───────────
// The Go team excludes its OWN fieldalignment analyzer from vet and gopls because "the diagnostics
// produced by fieldanalyzer very rarely indicate a significant problem", and because "the most compact
// order is not always the most efficient" — tight packing co-locates independently-updated fields and
// can INDUCE FALSE SHARING. This axis is not monotonic, so this lens fires ONLY on the two shapes whose
// direction is defensible in one sentence:
//   split-line — two fields co-accessed by >= kMinCoAccessFns distinct functions whose byte distance is
//                >= 64, i.e. wt == 0.00. NO field order can put them on one line as declared; the
//                direction is "these two can never share a line", which is a fact, not a preference.
//   straddle   — one co-accessed field whose own [off, off+size) crosses a 64-byte boundary, so every
//                access to that ONE field touches TWO lines. Direction: strictly worse than not
//                crossing, at equal size.
// DELIBERATELY NOT EMITTED: "sort fields by decreasing size", "pack tighter", "remove padding". Those
// are the universal shipped advice AND the non-monotonic move the Go caution is about. This lens has no
// opinion on them.
//
// ── THE VALIDATION HOOK (half two) ───────────────────────────────────────────────────────────────────
// `perf c2c` resolves a miss to a cache line AND an offset within it, but deliberately never names a
// struct FIELD — you are expected to map offset->field yourself with pahole and DWARF. This lens closes
// the other half of that path from source: field -> offset -> the FUNCTIONS that co-access it -> the
// PROFILE_SCOPE those functions sit inside. `<validate>` names the instrumented scope whose counters
// would confirm or refute the hypothesis, computed by locating the enclosing PROFILE_SCOPE_DESCRIBE of
// each co-accessing function — not written down by hand. ripwire already owns the counter side
// (src/infra/profilePmc.h: kpep on macOS, perf_event_open on Linux), so this composes with the existing
// PMC backend instead of duplicating it. bench/bench_field_ab.cpp is the worked example that closes the
// loop end to end; docs/FIELDAFFINITY.md records the measured result.
//
// Determinism: aggregates are walked in symbol-id order, every emitted list is explicitly sorted by a
// total order ending in a name or an index, name->id maps are gtl::btree_map, and no wall clock is read.
//
// ── PHASE A/B ADDENDUM — access-shape classification and chase-pointer colocation ───────────────────────
// src/accessshape.h (read its own file header first) classifies each `for`-loop's advance as index/chase/
// mixed/unknown via the codebase's existing astQuery/TSQuery re-query mechanism, then rolls CHASE-shaped
// loops up into a per-field tally. This file consumes that tally in exactly two ways, both DISCLOSED, not
// silent: (1) `<f chase="1" loops="N" shape_conf="…">` reports which declared field a real traversal
// advances through and how confidently its declared type self-references the enclosing aggregate — never
// for a field name owned by 2+ modeled aggregates (refused, counted in `as_stem_ambiguous=`, the same
// "refuse rather than guess" convention `amb_skipped=` already uses above). (2) `kChaseSepCostBoostApplied`
// is wired inline at the EXACT sepCost accumulation point a chase-target pair would be boosted at, and is
// pinned at 1.0 (a documented no-op) — PLAN.md's shipping floor for anything RANKING-affecting is >=85%
// precision on the shape_conf="self-ref" set, measured against real corpora with BLIND human review, which
// has not run. See docs/FIELDAFFINITY.md §8 and src/accessshape.h's own header for the full accounting.

#include "model.h"
#include "graph.h"
#include "layout.h"       // the offset model + ModelCtx/modelDef/findDefBody — reused verbatim, not re-derived
#include "serialize.h"    // escapeXml
#include "mention.h"      // isIdentChar
#include "accessshape.h"  // Phase A — access-shape classification, consumed report-only (see addendum above)
#include "Diagnostics.h"  // VERIFY / DEGRADED_PATH_ALERT

#include "btree.hpp"      // gtl::btree_map — sorted iteration (house rule: never std::map)

#include <algorithm>
#include <cstdio>
#include <functional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
namespace fieldaffinity
{

// ── tuning constants ─────────────────────────────────────────────────────────────────────────────────

// Chilimbi's `cache_block_size`. 64 B is the line on every architecture ripwire is built for (Apple
// arm64, x86-64, and the 64 B L1/L2 line of every current server part); it is a NAMED assumption, echoed
// in the header as block="64" so a reader on a 128 B-line machine knows to discount the geometry half.
constexpr std::uint32_t kCacheBlockBytes  = 64;

constexpr std::uint32_t kMinCoAccessFns   = 2;      // a pair must be co-accessed by >= this many DISTINCT functions to FIRE
constexpr std::size_t   kMaxStructsShown  = 20;     // whole-repo form: the ranked head, `capped="1"` past it
constexpr std::size_t   kMaxPairsShown    = 12;     // per struct
constexpr std::size_t   kMaxFnsShown      = 8;      // per struct
constexpr std::size_t   kMaxFieldsShown   = 32;     // per struct (touched fields only)
constexpr std::size_t   kMaxAggsModeled   = 8000;   // refusal bound on the whole-repo modelling pass
constexpr std::size_t   kMaxScopeChars    = 120;    // displayed prefix of a PROFILE_SCOPE description

// Phase B — the chase-pointer sepCost boost. TWO constants, deliberately: kChaseSepCostBoostMeasured is
// the REAL number bench/bench_chase_ab.cpp produced on this machine (see docs/FIELDAFFINITY.md §8 for the
// exact run); kChaseSepCostBoostApplied is what buildStructRow ACTUALLY multiplies by, pinned at 1.0 (a
// provable no-op) until the plan's required real-corpus, blind-reviewed precision floor
// (shape_conf="self-ref" >= 85%) clears. Wiring the measured constant into the arithmetic before that
// floor clears would be exactly the unearned promotion PLAN.md's Phase B section forbids ("no silent
// promotion past a floor nobody checked"). Keep these separate; do not fold one into the other.
// MEASURED (2026-08-06, this session, Apple M5 Pro, unprivileged — counters UNAVAILABLE, same disclosed
// gap bench_field_ab.cpp's own §5.1 has without root): bench/bench_chase_ab.cpp, a shuffled 64 MB /
// 256 Ki-node pointer chase, ratio=split/packed over 5 repeats: 1.00 1.04 1.04 1.01 1.02 — mostly NULL,
// weakly and inconsistently positive, NOT a confident confirmation at this working-set/shuffle regime.
// That is itself an honest result (see docs/FIELDAFFINITY.md §8), and a second, independent reason
// (beyond the unmet validation floor) this constant is NOT wired into the arithmetic below.
constexpr double         kChaseSepCostBoostMeasured = 1.02;   // median of the 5 repeats above — NOT applied
constexpr double         kChaseSepCostBoostApplied  = 1.00;   // LOCKED at 1.0 — report-only, see file header

// ── the result model ─────────────────────────────────────────────────────────────────────────────────

// One declared field, carrying the layout model's geometry plus this lens's access tally.
struct AffField
{
    std::string   name;
    std::uint32_t offset   = 0;
    std::uint32_t size     = 0;
    bool          placed   = false;   // layout.h knew where it starts (false once an earlier field went unsized)
    bool          sized    = false;
    std::uint32_t accesses = 0;       // FLOOR: member-access sites attributed to this field
    std::uint32_t fns      = 0;       // distinct indexed functions that touch it

    // Phase A/B disclosure (report-only — see the file header addendum and src/accessshape.h). chaseLoops
    // is a FLOOR: the number of DISTINCT for-loop sites accessshape.h observed advancing THROUGH this
    // field (`p = p->thisField`), 0 when never observed as a chase-advance field or when the field name
    // was refused as ambiguous (owned by 2+ modeled aggregates — see as_stem_ambiguous= in the header).
    std::uint32_t                chaseLoops = 0;
    accessshape::ChaseConfidence chaseConf  = accessshape::ChaseConfidence::None;
};

// An edge of the field affinity graph (Chilimbi PLDI 1999), scored with his separation weight.
struct AffPair
{
    std::uint32_t a = 0, b = 0;       // indices into AffStruct::fields, a < b
    std::uint32_t fns = 0;            // FLOOR: distinct functions co-accessing the pair
    std::uint64_t weight = 0;         // sum over those functions of ( 1 + fan-in ) — the static hotness PROXY
    std::uint32_t dist = 0;           // |off_a - off_b| in bytes; meaningful only when both are placed
    double        wt = 0.0;           // ( 64 - dist ) / 64, clamped at 0
    bool          measured = false;   // both endpoints placed, so dist/wt mean something
};

// One co-accessing function, and the instrumented scope it sits inside (the static->PMC bridge).
struct AffFn
{
    std::string   name;
    std::string   path;
    std::uint32_t line     = 0;
    std::uint32_t fanIn    = 0;
    std::uint32_t touched  = 0;
    std::string   fields;             // comma-joined touched field names, in declaration order
    std::string   profileScope;       // the enclosing PROFILE_SCOPE_DESCRIBE text; "" when the function is not instrumented
};

// A finding. `kind` is one of exactly two strings — see "WHICH WAY IS BAD" in the file header.
struct AffFinding
{
    const char*   kind = "split-line";
    std::string   a, b;               // the two field names (b empty for straddle)
    std::uint32_t dist   = 0;
    std::uint32_t offset = 0;         // straddle: the field's own offset
    std::uint32_t size   = 0;         // straddle: the field's own size
    std::uint32_t fns    = 0;
    std::uint64_t weight = 0;
};

struct AffStruct
{
    std::string   name;
    std::string   path;
    std::uint32_t line       = 0;
    const char*   aggregate  = "struct";
    std::uint32_t size       = 0;
    std::uint32_t align      = 1;
    bool          modeled    = false;  // layout.h could compute the geometry; false ⇒ affinity only, no findings
    std::size_t   declared   = 0;      // declared field count (before the touched-only display filter)
    std::uint32_t touchedFns = 0;
    double        sepCost    = 0.0;    // sum over measured pairs of fns * ( 1 - wt ) — the ranking key
    std::vector<AffField>   fields;
    std::vector<AffPair>    pairs;
    std::vector<AffFn>      fns;
    std::vector<AffFinding> findings;
    std::vector<std::string> scopes;   // distinct PROFILE_SCOPE descriptions across `fns`, sorted
    std::size_t   pairsTotal = 0, fnsTotal = 0, fieldsTotal = 0;
};

struct AffResult
{
    std::string              sym;                 // the --field-affinity=STRUCT filter; "" for the whole-repo form
    bool                     filtered = false;
    std::vector<AffStruct>   rows;
    std::size_t              aggregates   = 0;    // C-family aggregates the layout model could locate a body for
    std::size_t              aggsCapped   = 0;    // aggregates dropped by kMaxAggsModeled
    std::size_t              filesScanned = 0;
    std::size_t              fnsScanned   = 0;
    std::size_t              accesses     = 0;    // attributed member-access sites (FLOOR)
    std::size_t              ambSkipped   = 0;    // sites refused because >1 aggregate declares that field name
    std::size_t              structsTotal = 0;    // structs with >= 1 attributed access, before the display cap
    std::size_t              findings     = 0;

    // Phase A repo-wide rollup (report-only — see the file header addendum). Independent of `filtered`:
    // access-shape classification is corpus-wide for the same reason the aggregate ambiguity universe is
    // (a filter narrows what's SHOWN, never what's true about the rest of the corpus).
    std::size_t               asForLoops      = 0;   // as-loop rows classifyAccessShapes found, before its cap
    std::size_t               asLoopsCapped   = 0;    // dropped by accessshape::kMaxLoopsModeled — a disclosed FLOOR
    std::size_t               asIndexLoops    = 0, asChaseLoops = 0, asMixedLoops = 0, asUnknownLoops = 0;
    std::size_t               asStemAmbiguous = 0;    // chase field names refused: owned by 2+ modeled aggregates
    std::vector<std::string>  asSaturatedTags;        // astQuery tags whose count= is itself a floor (rare)
};

// ── Chilimbi's separation weight, PLDI 1999 §4 ───────────────────────────────────────────────────────
// wt(fi,fj) = ( cache_block_size - dist(fi,fj) ) / cache_block_size, dist = bytes between field starts.
// Clamped at zero: past one block the pair simply cannot share a line and the linear form would go
// negative. This is a CITED formula, reproduced — not a ripwire invention. Do not "improve" it without
// saying so in the output, because the number is comparable to a published one only while it is his.
inline double separationWeight( std::uint32_t distBytes ) noexcept
{
    if( distBytes >= kCacheBlockBytes )
    {
        return 0.0;
    }
    return double( kCacheBlockBytes - distBytes ) / double( kCacheBlockBytes );
}

// A field straddles a line when its first and last byte fall in different 64 B blocks. A field LARGER
// than a block always spans two and is not a defect — it cannot do otherwise — so it is excluded.
inline bool straddlesLine( std::uint32_t offset, std::uint32_t size ) noexcept
{
    if( size == 0 || size > kCacheBlockBytes )
    {
        return false;
    }
    return ( offset / kCacheBlockBytes ) != ( ( offset + size - 1 ) / kCacheBlockBytes );
}

// ── stage 1: model every C-family aggregate in the corpus ────────────────────────────────────────────

// One modelled aggregate, kept alongside the identity the report prints.
struct ModeledAgg
{
    std::string       name;
    std::string       path;
    std::uint32_t     line = 0;
    layout::LayoutDef def;
};

// The inverse cut of `--layout`'s "every def of THIS name": every modelable def in the whole index,
// deduped by (fileId, braceStart) exactly as abicheck.h's buildCandidates does — that dedupe is what
// drops a `typedef struct X {…} X;`'s alias twin, which would otherwise become a phantom second struct
// with an identical field set and double every count.
inline std::vector<ModeledAgg> modelAllAggregates( layout::ModelCtx& ctx, std::string_view filterName,
                                                   std::size_t& filesScanned, std::size_t& capped )
{
    std::vector<ModeledAgg>              out;
    gtl::btree_map<std::uint64_t, bool>  seenSite;
    gtl::btree_map<std::uint32_t, bool>  seenFile;

    for( const Symbol& s : ctx.ing.symbols )
    {
        if( s.kind != SymKind::Struct && s.kind != SymKind::Class && s.kind != SymKind::Interface )
        {
            continue;
        }
        if( !filterName.empty() && s.name != filterName )
        {
            continue;
        }
        if( !layout::isCFamilyPath( ctx.ing.files[ s.fileId ] ) )
        {
            continue;
        }

        const std::string& src = layout::fileBytes( ctx, s.fileId );
        if( seenFile.find( s.fileId ) == seenFile.end() )
        {
            seenFile.emplace( s.fileId, true );
            ++filesScanned;
        }
        if( src.empty() )
        {
            continue;
        }

        layout::DefSite site;
        if( !layout::findDefBody( src, s.name, s.sigStartByte, site ) )
        {
            continue;   // a forward declaration, a typedef alias, or an enum — never an aggregate body
        }
        site.fileId = s.fileId;

        const std::uint64_t key = ( std::uint64_t( s.fileId ) << 32 ) | std::uint64_t( site.braceStart & 0xFFFFFFFFull );
        if( seenSite.find( key ) != seenSite.end() )
        {
            continue;
        }
        seenSite.emplace( key, true );

        if( out.size() >= kMaxAggsModeled )
        {
            ++capped;   // disclosed in the header as aggs_capped=; silence here would read as "none exists"
            continue;
        }

        ModeledAgg m;
        m.name = s.name;
        m.path = ctx.ing.files[ s.fileId ];
        m.line = s.line;
        m.def  = layout::modelDef( ctx, s.fileId, site, s.name );
        out.push_back( std::move( m ) );
    }
    return out;
}

// ── stage 2: the field-access enumeration (Chilimbi's <function, struct type>, WITHOUT points-to) ─────

// One function's co-access observation over one aggregate: the DISTINCT fields it touched. Only the
// distinct set matters — the affinity edge is "these two were touched by the same function", and a
// function that reads `p->x` five times has not observed anything five times. Per-field access COUNTS
// live in AggAccum::accesses, where they are a separate, separately-labelled floor.
struct FnTouch
{
    std::uint32_t aggIndex = 0;
    std::uint32_t fnSym    = 0;
    std::vector<std::uint32_t> fieldIdx;   // sorted, unique
};

// Field name -> the modelled aggregates declaring it. A name declared by exactly ONE aggregate is the
// only case this lens will attribute: with two or more, telling which one `q->slot` meant needs the
// pointer analysis Chilimbi explicitly did not have and ripwire does not either. He approximated;
// ripwire REFUSES and counts the refusal, so the report under-counts rather than mis-attributes.
using FieldOwners = gtl::btree_map<std::string, std::vector<std::uint32_t>>;

inline FieldOwners buildFieldOwners( const std::vector<ModeledAgg>& aggs )
{
    FieldOwners owners;
    for( std::size_t i = 0; i < aggs.size(); ++i )
    {
        for( const layout::FieldRow& f : aggs[i].def.fields )
        {
            std::vector<std::uint32_t>& v = owners[ f.name ];
            if( v.empty() || v.back() != std::uint32_t( i ) )
            {
                v.push_back( std::uint32_t( i ) );
            }
        }
    }
    return owners;
}

inline bool isDigitByte( char c ) noexcept { return c >= '0' && c <= '9'; }

// The MEMBER-ACCESS token scan. Deliberately syntactic and deliberately narrow: only `.name` and
// `->name` count. A BARE `name` inside a method of the owning class is NOT counted even though it is a
// real field access, because a local variable, a parameter, or a same-named free function shadows it
// indistinguishably at this level — counting it would trade a disclosed under-count for a silent
// mis-attribution. That is the access floor this report discloses as counts_floor="1".
inline void scanMemberAccesses( std::string_view body, const std::function<void( std::string_view )>& onHit )
{
    for( std::size_t i = 0; i + 1 < body.size(); ++i )
    {
        std::size_t nameAt = 0;
        if( body[i] == '-' && body[i + 1] == '>' )
        {
            nameAt = i + 2;
        }
        else if( body[i] == '.' && !( i > 0 && ( isDigitByte( body[i - 1] ) || body[i - 1] == '.' ) ) && body[i + 1] != '.' )
        {
            nameAt = i + 1;
        }
        else
        {
            continue;
        }

        while( nameAt < body.size() && ( body[ nameAt ] == ' ' || body[ nameAt ] == '\n' || body[ nameAt ] == '\t' || body[ nameAt ] == '\r' ) )
        {
            ++nameAt;
        }
        if( nameAt >= body.size() || !( mention_detail::isIdentChar( body[ nameAt ] ) ) || isDigitByte( body[ nameAt ] ) )
        {
            continue;
        }
        std::size_t end = nameAt;
        while( end < body.size() && mention_detail::isIdentChar( body[ end ] ) )
        {
            ++end;
        }
        // A CALL is not a field access: `p->step()` names a method. Skip when the next non-space is '('.
        std::size_t after = end;
        while( after < body.size() && ( body[ after ] == ' ' || body[ after ] == '\n' || body[ after ] == '\t' || body[ after ] == '\r' ) )
        {
            ++after;
        }
        if( after < body.size() && body[ after ] == '(' )
        {
            i = end - 1;
            continue;
        }
        onHit( body.substr( nameAt, end - nameAt ) );
        i = end - 1;
    }
}

// ── stage 4: the PROFILE_SCOPE bridge (half two of the design) ───────────────────────────────────────
// The enclosing instrumented scope of a function body, if any: the LAST PROFILE_SCOPE_DESCRIBE( "…" )
// that opens inside the body. Computed, never hand-written — a hypothesis that names its own validation
// target is the point of the exercise; a hand-maintained table would drift the first time a scope moved.
inline std::string enclosingProfileScope( std::string_view body )
{
    static constexpr std::string_view kMarkers[] = { "PROFILE_SCOPE_DESCRIBE(", "PROFILE_SCOPE(" };
    std::string best;
    for( std::string_view marker : kMarkers )
    {
        std::size_t at = body.find( marker );
        while( at != std::string_view::npos )
        {
            const std::size_t q1 = body.find( '"', at + marker.size() );
            if( q1 == std::string_view::npos )
            {
                break;
            }
            const std::size_t q2 = body.find( '"', q1 + 1 );
            if( q2 == std::string_view::npos )
            {
                break;
            }
            best.assign( body.substr( q1 + 1, q2 - q1 - 1 ) );
            if( best.size() > kMaxScopeChars )
            {
                best.resize( kMaxScopeChars );
            }
            at = body.find( marker, q2 + 1 );
        }
        if( !best.empty() )
        {
            return best;
        }
    }
    return best;
}

// ── stage 3: the affinity graph, the geometry diff, and the ranking ──────────────────────────────────

// Per-aggregate accumulation while the function walk runs. Kept out of AffStruct because the report only
// ever shows TOUCHED fields, while the graph has to index by DECLARED position.
struct AggAccum
{
    std::vector<std::uint32_t> accesses;   // declared-field index -> attributed sites
    std::vector<std::uint32_t> fnCount;    // declared-field index -> distinct functions
    std::vector<FnTouch>       touches;    // one per function that touched >= 1 field
};

// The pair key for a (small) dense triangular accumulation. Field counts per struct are small (the model
// caps at what a source aggregate actually declares), so a flat vector<AffPair> plus a btree index by
// packed (a,b) is both deterministic and cheaper than a hash of pairs.
inline std::uint64_t pairKey( std::uint32_t a, std::uint32_t b ) noexcept
{
    return ( std::uint64_t( a ) << 32 ) | std::uint64_t( b );
}

// ONE function body = ONE co-access observation, in Chilimbi's <function, struct type> sense. Everything
// this touches is an accumulator; the affinity graph itself is built later, per aggregate.
inline void accumulateFunction( layout::ModelCtx& ctx, const Symbol& s, const std::vector<ModeledAgg>& aggs,
                                const FieldOwners& owners, std::vector<AggAccum>& accum, AffResult& res )
{
    // Slice the def out of the RAW bytes (its span is in raw coordinates), THEN strip the comments from
    // that slice — never the other way round. layout::withoutComments collapses each comment to a single
    // space, so it does NOT preserve byte offsets, and indexing the whole stripped file with a raw
    // sigStartByte silently reads someone else's function. (Found by running the fixture, not by
    // inspection: it credited one function with three others' field accesses.)
    const std::string& raw = layout::fileBytes( ctx, s.fileId );
    if( raw.empty() || s.sigStartByte >= raw.size() )
    {
        return;
    }
    const std::size_t bodyEnd = std::min( std::size_t( s.endByte ), raw.size() );
    if( bodyEnd <= std::size_t( s.sigStartByte ) )
    {
        return;
    }
    ++res.fnsScanned;

    const std::string body = layout::withoutComments( std::string_view( raw.data() + s.sigStartByte, bodyEnd - s.sigStartByte ) );

    // agg index -> the fields this ONE function touched (sorted, unique), built per function.
    gtl::btree_map<std::uint32_t, std::vector<std::uint32_t>> hitsByAgg;

    scanMemberAccesses( body,
                        [ & ]( std::string_view fieldName )
                        {
                            const auto it = owners.find( std::string( fieldName ) );
                            if( it == owners.end() )
                            {
                                return;   // not a field of any modelled aggregate — some other type's member
                            }
                            if( it->second.size() != 1 )
                            {
                                ++res.ambSkipped;   // >1 owner: refuse rather than guess (see FieldOwners)
                                return;
                            }
                            const std::uint32_t      ai  = it->second.front();
                            const layout::LayoutDef& def = aggs[ ai ].def;
                            for( std::size_t fi = 0; fi < def.fields.size(); ++fi )
                            {
                                if( def.fields[ fi ].name != fieldName )
                                {
                                    continue;
                                }
                                ++accum[ ai ].accesses[ fi ];
                                ++res.accesses;
                                std::vector<std::uint32_t>& v = hitsByAgg[ ai ];
                                if( std::find( v.begin(), v.end(), std::uint32_t( fi ) ) == v.end() )
                                {
                                    v.push_back( std::uint32_t( fi ) );
                                }
                                break;
                            }
                        } );

    for( auto& [ ai, fields ] : hitsByAgg )
    {
        std::sort( fields.begin(), fields.end() );
        FnTouch t;
        t.aggIndex = ai;
        t.fnSym    = s.id;
        t.fieldIdx = fields;
        for( const std::uint32_t fi : fields )
        {
            ++accum[ ai ].fnCount[ fi ];
        }
        accum[ ai ].touches.push_back( std::move( t ) );
    }
}

// Display ordering + caps for ONE row, applied AFTER the ranking so the head is chosen on the full graph.
// Every comparator ends in an index or a name, so the order is total and two runs cannot differ.
inline void applyDisplayOrder( AffStruct& row )
{
    std::sort( row.pairs.begin(), row.pairs.end(),
               []( const AffPair& x, const AffPair& y ) noexcept
               {
                   if( x.fns != y.fns )   { return x.fns > y.fns; }
                   if( x.dist != y.dist ) { return x.dist > y.dist; }
                   if( x.a != y.a )       { return x.a < y.a; }
                   return x.b < y.b;
               } );
    if( row.pairs.size() > kMaxPairsShown )
    {
        row.pairs.resize( kMaxPairsShown );
    }
    std::sort( row.fns.begin(), row.fns.end(),
               []( const AffFn& x, const AffFn& y ) noexcept
               {
                   if( x.touched != y.touched ) { return x.touched > y.touched; }
                   if( x.fanIn != y.fanIn )     { return x.fanIn > y.fanIn; }
                   if( x.path != y.path )       { return x.path < y.path; }
                   return x.line < y.line;
               } );
    if( row.fns.size() > kMaxFnsShown )
    {
        row.fns.resize( kMaxFnsShown );
    }
    std::sort( row.fields.begin(), row.fields.end(),
               []( const AffField& x, const AffField& y ) noexcept
               {
                   if( x.placed != y.placed ) { return x.placed; }
                   if( x.offset != y.offset ) { return x.offset < y.offset; }
                   return x.name < y.name;
               } );
    if( row.fields.size() > kMaxFieldsShown )
    {
        row.fields.resize( kMaxFieldsShown );
    }
    std::sort( row.findings.begin(), row.findings.end(),
               []( const AffFinding& x, const AffFinding& y ) noexcept
               {
                   const int kx = ( std::string_view( x.kind ) == "split-line" ) ? 0 : 1;
                   const int ky = ( std::string_view( y.kind ) == "split-line" ) ? 0 : 1;
                   if( kx != ky )       { return kx < ky; }
                   if( x.fns != y.fns ) { return x.fns > y.fns; }
                   if( x.a != y.a )     { return x.a < y.a; }
                   return x.b < y.b;
               } );
}

// ── Phase A/B bridge: which declared field (if any) is THIS aggregate's confirmed chase pointer ────────
// See the file header addendum and src/accessshape.h. Resolved once per aggregate, BEFORE buildStructRow,
// so both halves of Phase B (the disclosure attribute on the field AND the sepCost boost's accumulation
// point) read the SAME resolution rather than two call sites drifting apart.
struct ChaseFieldInfo
{
    bool                          found  = false;
    std::size_t                   declIdx = 0;    // index into agg.def.fields
    std::uint32_t                 loops   = 0;
    accessshape::ChaseConfidence  conf    = accessshape::ChaseConfidence::None;
};

inline ChaseFieldInfo resolveChaseField( const ModeledAgg& agg, std::uint32_t aggIndex, const FieldOwners& owners,
                                         const accessshape::ShapeResult& shapeRes )
{
    ChaseFieldInfo info;
    for( std::size_t fi = 0; fi < agg.def.fields.size(); ++fi )
    {
        const std::string& name = agg.def.fields[ fi ].name;
        const auto          cIt = shapeRes.chaseFieldLoops.find( name );
        if( cIt == shapeRes.chaseFieldLoops.end() )
        {
            continue;
        }
        const auto oIt = owners.find( name );
        if( oIt == owners.end() || oIt->second.size() != 1 || oIt->second.front() != aggIndex )
        {
            continue;   // ambiguous (2+ aggregates declare this name) or not THIS struct's own field —
                        // refused, not guessed; the caller tallies this in asStemAmbiguous.
        }
        info.found   = true;
        info.declIdx = fi;
        info.loops   = cIt->second;
        info.conf    = accessshape::chaseFieldConfidence( agg.def.fields[ fi ].type, agg.name );
        break;      // a struct declares a given field name at most once
    }
    return info;
}

// One aggregate's affinity graph, geometry diff and findings, from its accumulated touches.
inline AffStruct buildStructRow( layout::ModelCtx& ctx, const ModeledAgg& agg, const AggAccum& acc,
                                 const std::vector<std::uint32_t>& fanIn, const ChaseFieldInfo& chaseInfo )
{
    const layout::LayoutDef& def = agg.def;

    AffStruct row;
    row.name       = agg.name;
    row.path       = agg.path;
    row.line       = agg.line;
    row.aggregate  = def.aggregate;
    row.modeled    = def.modeled;
    row.size       = def.size;
    row.align      = def.align;
    row.declared   = def.fields.size();
    row.touchedFns = std::uint32_t( acc.touches.size() );

    // fields (touched only — an untouched field has no affinity evidence and no finding can cite it)
    std::vector<std::uint32_t> declToRow( def.fields.size(), 0xFFFFFFFFu );
    for( std::size_t fi = 0; fi < def.fields.size(); ++fi )
    {
        if( acc.accesses[ fi ] == 0 )
        {
            continue;
        }
        AffField f;
        f.name     = def.fields[ fi ].name;
        f.offset   = def.fields[ fi ].offset;
        f.size     = def.fields[ fi ].size;
        f.placed   = def.modeled && def.fields[ fi ].placed;
        f.sized    = def.fields[ fi ].sized;
        f.accesses = acc.accesses[ fi ];
        f.fns      = acc.fnCount[ fi ];
        if( chaseInfo.found && chaseInfo.declIdx == fi )
        {
            f.chaseLoops = chaseInfo.loops;
            f.chaseConf  = chaseInfo.conf;
        }
        declToRow[ fi ] = std::uint32_t( row.fields.size() );
        row.fields.push_back( std::move( f ) );
    }
    row.fieldsTotal = row.fields.size();

    // pairs — every unordered pair of DISTINCT fields a function touched (Chilimbi's affinity edge,
    // with the function body standing in for his 100 ms trace window; see the file header).
    gtl::btree_map<std::uint64_t, std::size_t> pairAt;
    for( const FnTouch& t : acc.touches )
    {
        const std::uint64_t w = 1ull + std::uint64_t( t.fnSym < fanIn.size() ? fanIn[ t.fnSym ] : 0u );
        for( std::size_t i = 0; i + 1 < t.fieldIdx.size(); ++i )
        {
            for( std::size_t j = i + 1; j < t.fieldIdx.size(); ++j )
            {
                const std::uint32_t da = t.fieldIdx[i], db = t.fieldIdx[j];
                if( declToRow[ da ] == 0xFFFFFFFFu || declToRow[ db ] == 0xFFFFFFFFu )
                {
                    continue;
                }
                const std::uint64_t key = pairKey( da, db );
                auto                it  = pairAt.find( key );
                if( it == pairAt.end() )
                {
                    AffPair p;
                    p.a = declToRow[ da ];
                    p.b = declToRow[ db ];
                    it  = pairAt.emplace( key, row.pairs.size() ).first;
                    row.pairs.push_back( p );
                }
                AffPair& p = row.pairs[ it->second ];
                ++p.fns;
                p.weight += w;
            }
        }
    }

    // geometry — ONLY where layout.h placed both endpoints. A modeled="0" definition contributes its
    // affinity graph and NO geometry: dist/wt would be arithmetic on offsets the model refused to give.
    for( AffPair& p : row.pairs )
    {
        const AffField& fa = row.fields[ p.a ];
        const AffField& fb = row.fields[ p.b ];
        if( !fa.placed || !fb.placed )
        {
            continue;
        }
        p.measured = true;
        p.dist     = ( fa.offset > fb.offset ) ? ( fa.offset - fb.offset ) : ( fb.offset - fa.offset );
        p.wt       = separationWeight( p.dist );
        // Phase B's boost, applied at the EXACT accumulation point, BEFORE the sepCost-desc sort below —
        // stated explicitly so this can never silently break the file's determinism contract (PLAN.md).
        // kChaseSepCostBoostApplied is LOCKED at 1.0 (a provable no-op): see the tuning-constants comment
        // and the file header addendum for why the measured value is not wired in yet.
        const double boost = ( fa.chaseLoops > 0 || fb.chaseLoops > 0 ) ? kChaseSepCostBoostApplied : 1.0;
        row.sepCost += double( p.fns ) * ( 1.0 - p.wt ) * boost;
    }

    // findings — the two shapes whose direction is defensible. Nothing else fires, ever.
    for( const AffPair& p : row.pairs )
    {
        if( !p.measured || p.fns < kMinCoAccessFns || p.wt > 0.0 )
        {
            continue;
        }
        AffFinding f;
        f.kind   = "split-line";
        f.a      = row.fields[ p.a ].name;
        f.b      = row.fields[ p.b ].name;
        f.dist   = p.dist;
        f.fns    = p.fns;
        f.weight = p.weight;
        row.findings.push_back( std::move( f ) );
    }
    for( const AffField& f : row.fields )
    {
        if( !f.placed || !straddlesLine( f.offset, f.size ) )
        {
            continue;
        }
        AffFinding fd;
        fd.kind   = "straddle";
        fd.a      = f.name;
        fd.offset = f.offset;
        fd.size   = f.size;
        fd.fns    = f.fns;
        row.findings.push_back( std::move( fd ) );
    }

    // co-accessing functions + the PROFILE_SCOPE bridge
    for( const FnTouch& t : acc.touches )
    {
        const Symbol& fs = ctx.ing.symbols[ t.fnSym ];
        AffFn fn;
        fn.name    = fs.name;
        fn.path    = ctx.ing.files[ fs.fileId ];
        fn.line    = fs.line;
        fn.fanIn   = ( t.fnSym < fanIn.size() ) ? fanIn[ t.fnSym ] : 0u;
        fn.touched = std::uint32_t( t.fieldIdx.size() );
        for( const std::uint32_t fi : t.fieldIdx )
        {
            if( !fn.fields.empty() )
            {
                fn.fields += ',';
            }
            fn.fields += def.fields[ fi ].name;
        }
        const std::string& raw = layout::fileBytes( ctx, fs.fileId );
        if( !raw.empty() && fs.sigStartByte < raw.size() )
        {
            const std::size_t e = std::min( std::size_t( fs.endByte ), raw.size() );
            if( e > std::size_t( fs.sigStartByte ) )
            {
                fn.profileScope = enclosingProfileScope( std::string_view( raw.data() + fs.sigStartByte, e - fs.sigStartByte ) );
            }
        }
        row.fns.push_back( std::move( fn ) );
    }
    row.fnsTotal   = row.fns.size();
    row.pairsTotal = row.pairs.size();

    for( const AffFn& fn : row.fns )
    {
        if( !fn.profileScope.empty() && std::find( row.scopes.begin(), row.scopes.end(), fn.profileScope ) == row.scopes.end() )
        {
            row.scopes.push_back( fn.profileScope );
        }
    }
    std::sort( row.scopes.begin(), row.scopes.end() );

    return row;
}

inline AffResult computeFieldAffinity( const IngestResult& ing, const std::vector<std::uint32_t>& fanIn,
                                       std::string_view filterName )
{
    AffResult res;
    res.sym      = std::string( filterName );
    res.filtered = !filterName.empty();

    const layout::AggIndex byName = layout::buildAggIndex( ing );
    layout::ModelCtx       ctx( ing, byName );

    // The filter narrows WHICH struct is reported, not which field names are ambiguous: an aggregate the
    // reader did not ask about still owns its field names, and pretending otherwise would turn a refused
    // ambiguous access into a confident wrong attribution the moment a filter was passed. So the ambiguity
    // universe is always the whole corpus.
    const std::vector<ModeledAgg> aggs = modelAllAggregates( ctx, std::string_view{}, res.filesScanned, res.aggsCapped );
    res.aggregates                     = aggs.size();
    const FieldOwners owners           = buildFieldOwners( aggs );

    // Phase A — corpus-wide, same reason the ambiguity universe above is corpus-wide: which loops advance
    // via a chase-shaped update is a fact about the WHOLE repo, not about whichever struct a filter named.
    const accessshape::ShapeResult shapeRes = accessshape::classifyAccessShapes( ing );
    res.asForLoops      = shapeRes.forLoops;
    res.asLoopsCapped   = shapeRes.loopsCapped;
    res.asIndexLoops    = shapeRes.indexLoops;
    res.asChaseLoops    = shapeRes.chaseLoops;
    res.asMixedLoops    = shapeRes.mixedLoops;
    res.asUnknownLoops  = shapeRes.unknownLoops;
    res.asSaturatedTags = shapeRes.saturatedTags;
    for( const auto& [ name, loops ] : shapeRes.chaseFieldLoops )
    {
        const auto oIt = owners.find( name );
        if( oIt == owners.end() || oIt->second.size() != 1 )
        {
            ++res.asStemAmbiguous;   // refused: 2+ modeled aggregates declare this field name
        }
    }

    std::vector<AggAccum> accum( aggs.size() );
    for( std::size_t i = 0; i < aggs.size(); ++i )
    {
        accum[i].accesses.assign( aggs[i].def.fields.size(), 0 );
        accum[i].fnCount.assign( aggs[i].def.fields.size(), 0 );
    }

    for( const Symbol& s : ing.symbols )
    {
        if( s.kind != SymKind::Function && s.kind != SymKind::Method )
        {
            continue;
        }
        if( !layout::isCFamilyPath( ing.files[ s.fileId ] ) )
        {
            continue;
        }
        accumulateFunction( ctx, s, aggs, owners, accum, res );
    }

    for( std::size_t ai = 0; ai < aggs.size(); ++ai )
    {
        if( accum[ ai ].touches.empty() )
        {
            continue;   // no attributed access: no affinity evidence, so no row
        }
        if( res.filtered && aggs[ ai ].name != filterName )
        {
            continue;
        }
        ++res.structsTotal;
        const ChaseFieldInfo chaseInfo = resolveChaseField( aggs[ ai ], std::uint32_t( ai ), owners, shapeRes );
        AffStruct row = buildStructRow( ctx, aggs[ ai ], accum[ ai ], fanIn, chaseInfo );
        res.findings += row.findings.size();
        res.rows.push_back( std::move( row ) );
    }

    // Ranking: most separation cost first. Ties broken by finding count, then name, then path — a total
    // order, so two runs over the same corpus emit byte-identical output.
    std::sort( res.rows.begin(), res.rows.end(),
               []( const AffStruct& a, const AffStruct& b ) noexcept
               {
                   if( a.sepCost != b.sepCost )                 { return a.sepCost > b.sepCost; }
                   if( a.findings.size() != b.findings.size() ) { return a.findings.size() > b.findings.size(); }
                   if( a.name != b.name )                       { return a.name < b.name; }
                   return a.path < b.path;
               } );
    if( res.rows.size() > kMaxStructsShown )
    {
        res.rows.resize( kMaxStructsShown );
    }
    for( AffStruct& row : res.rows )
    {
        applyDisplayOrder( row );
    }
    return res;
}

// ── XML emission (G4: minified, xmllint-clean; no newline outside CDATA, no double hyphen in a comment) ──

inline void writeFieldAffinity( std::FILE* out, const AffResult& res )
{
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };

    // G4: an XML comment may not contain a double hyphen, so flags are named WITHOUT their leading
    // dashes. Keep it that way when editing.
    std::fprintf( out,
        "<!-- ripwire field-affinity: which fields are READ TOGETHER but declared far apart, diffed against 64-byte "
        "cache-line geometry. PRIOR ART, claimed by NOBODY here as new: the field affinity graph, the static "
        "field-access enumeration without pointer analysis, and the separation weight wt(fi,fj) = (block - dist)/block "
        "are Chilimbi, Davidson and Larus, Cache-Conscious Structure Definition, PLDI 1999 (bbcache), which also "
        "validated against UltraSPARC hardware counters; the advice-instead-of-transform posture and per-field counter "
        "attribution are Hundt, Mannarswamy and Chakrabarti, CGO 2006. What is new here is only the delivery: source "
        "level, no debug info, whole repo, ranked. TWO HONEST LIMITS. (1) Static access counts are NOT dynamic "
        "frequency: one field in a hot loop beats fifty on cold paths and nothing static can tell them apart, so fns= "
        "is a FLOOR of DISTINCT INDEXED FUNCTIONS and w= is a call-graph reachability PROXY (sum of 1 + fan-in), never "
        "a measured frequency. Only member-access syntax (dot and arrow) is counted; a bare field name inside its own "
        "method is not, because a local of the same name is indistinguishable here. (2) True sizeof and alignment are "
        "unknowable from source under templates, virtuals, bases and the target ABI: all geometry is the layout verb's "
        "LP64 standard-layout MODEL, model=\"lp64-approx\", and a definition it refused (modeled=\"0\") contributes its "
        "affinity graph and NO geometry finding. Exactly two findings fire, both with a defensible direction: "
        "split-line (co-accessed by 2+ functions at wt 0.00, so no field order can share a line) and straddle (one "
        "co-accessed field crossing a line boundary). Pack-tighter and sort-by-size advice is deliberately ABSENT: "
        "tight packing can induce false sharing, which is why the Go team keeps fieldalignment out of vet and gopls. "
        "ADVICE ONLY, never a transformation. validate= names the instrumented PROFILE_SCOPE whose counters would "
        "confirm the hypothesis; see docs/FIELDAFFINITY.md. PHASE A/B (report-only): as_* counts a corpus-wide, "
        "purely static for-loop advance-shape classification (index/chase/mixed/unknown, via astQuery TSQuery "
        "patterns, never execution); a chase-shaped field is disclosed on its <f> row as chase=\"1\" loops=\"N\", "
        "with shape_conf=\"self-ref\"/\"tmpl-approx\" only when the field's OWN declared type textually "
        "self-references its aggregate. NEVER ranking-affecting yet: the required real-corpus, blind-reviewed "
        "precision floor has not run, so sepcost= is IDENTICAL with or without this disclosure. See "
        "src/accessshape.h and docs/FIELDAFFINITY.md sec 8. -->" );

    std::fprintf( out, "<fieldaffinity block=\"%u\" model=\"lp64-approx\" counts_floor=\"1\" weighting=\"fanin-floor\""
                       " aggregates=\"%zu\" files=\"%zu\" fns_scanned=\"%zu\" accesses=\"%zu\" amb_skipped=\"%zu\""
                       " structs=\"%zu\" shown=\"%zu\" capped=\"%d\" findings=\"%zu\" min_fns=\"%u\""
                       " as_loops=\"%zu\" as_index=\"%zu\" as_chase=\"%zu\" as_mixed=\"%zu\" as_unknown=\"%zu\"",
                  kCacheBlockBytes, res.aggregates, res.filesScanned, res.fnsScanned, res.accesses,
                  res.ambSkipped, res.structsTotal, res.rows.size(),
                  ( res.structsTotal > res.rows.size() ) ? 1 : 0, res.findings, kMinCoAccessFns,
                  res.asForLoops, res.asIndexLoops, res.asChaseLoops, res.asMixedLoops, res.asUnknownLoops );
    if( res.filtered )
    {
        std::fprintf( out, " sym=\"%s\"", ex( res.sym ).c_str() );
    }
    if( res.aggsCapped > 0 )
    {
        std::fprintf( out, " aggs_capped=\"%zu\"", res.aggsCapped );
    }
    if( res.asLoopsCapped > 0 )
    {
        std::fprintf( out, " as_loops_capped=\"%zu\"", res.asLoopsCapped );
    }
    if( res.asStemAmbiguous > 0 )
    {
        std::fprintf( out, " as_stem_ambiguous=\"%zu\"", res.asStemAmbiguous );
    }
    if( !res.asSaturatedTags.empty() )
    {
        std::fprintf( out, " as_saturated=\"%zu\"", res.asSaturatedTags.size() );
    }
    std::fprintf( out, ">" );

    for( const AffStruct& s : res.rows )
    {
        std::fprintf( out, "<s n=\"%s\" p=\"%s\" l=\"%u\" agg=\"%s\" modeled=\"%d\" fields=\"%zu\" touched=\"%zu\""
                           " fns=\"%u\" pairs=\"%zu\" sepcost=\"%.2f\" findings=\"%zu\"",
                      ex( s.name ).c_str(), ex( s.path ).c_str(), s.line, s.aggregate, s.modeled ? 1 : 0,
                      s.declared, s.fieldsTotal, s.touchedFns, s.pairsTotal, s.sepCost, s.findings.size() );
        if( s.modeled )
        {
            std::fprintf( out, " size=\"%u\" align=\"%u\" lines=\"%u\"",
                          s.size, s.align, ( s.size + kCacheBlockBytes - 1 ) / kCacheBlockBytes );
        }
        std::fprintf( out, ">" );

        for( const AffField& f : s.fields )
        {
            std::fprintf( out, "<f n=\"%s\" acc=\"%u\" fns=\"%u\"", ex( f.name ).c_str(), f.accesses, f.fns );
            if( f.sized )
            {
                std::fprintf( out, " sz=\"%u\"", f.size );
            }
            if( f.placed )
            {
                std::fprintf( out, " off=\"%u\" ln=\"%u\"", f.offset, f.offset / kCacheBlockBytes );
            }
            else
            {
                std::fprintf( out, " placed=\"0\"" );
            }
            if( f.chaseLoops > 0 )
            {
                std::fprintf( out, " chase=\"1\" loops=\"%u\"", f.chaseLoops );
                if( f.chaseConf != accessshape::ChaseConfidence::None )
                {
                    std::fprintf( out, " shape_conf=\"%s\"", accessshape::confidenceName( f.chaseConf ) );
                }
            }
            std::fprintf( out, "/>" );
        }
        for( const AffPair& p : s.pairs )
        {
            std::fprintf( out, "<pair a=\"%s\" b=\"%s\" fns=\"%u\" w=\"%llu\"",
                          ex( s.fields[ p.a ].name ).c_str(), ex( s.fields[ p.b ].name ).c_str(),
                          p.fns, static_cast<unsigned long long>( p.weight ) );
            if( p.measured )
            {
                std::fprintf( out, " dist=\"%u\" wt=\"%.2f\"", p.dist, p.wt );
            }
            else
            {
                std::fprintf( out, " measured=\"0\"" );
            }
            std::fprintf( out, "/>" );
        }
        for( const AffFinding& f : s.findings )
        {
            std::fprintf( out, "<finding k=\"%s\" f=\"%s\"", f.kind, ex( f.a ).c_str() );
            if( !f.b.empty() )
            {
                std::fprintf( out, " g=\"%s\" dist=\"%u\" wt=\"0.00\"", ex( f.b ).c_str(), f.dist );
            }
            else
            {
                std::fprintf( out, " off=\"%u\" sz=\"%u\" crosses=\"%u\"",
                              f.offset, f.size, ( f.offset + f.size - 1 ) / kCacheBlockBytes );
            }
            std::fprintf( out, " fns=\"%u\"", f.fns );
            if( f.weight > 0 )
            {
                std::fprintf( out, " w=\"%llu\"", static_cast<unsigned long long>( f.weight ) );
            }
            std::fprintf( out, "/>" );
        }
        for( const AffFn& fn : s.fns )
        {
            std::fprintf( out, "<fn n=\"%s\" p=\"%s\" l=\"%u\" fanin=\"%u\" touched=\"%u\" f=\"%s\"",
                          ex( fn.name ).c_str(), ex( fn.path ).c_str(), fn.line, fn.fanIn, fn.touched,
                          ex( fn.fields ).c_str() );
            if( !fn.profileScope.empty() )
            {
                std::fprintf( out, " scope=\"%s\"", ex( fn.profileScope ).c_str() );
            }
            std::fprintf( out, "/>" );
        }

        // The static->PMC bridge. `scopes` is COMPUTED from the co-accessing functions' own
        // PROFILE_SCOPE_DESCRIBE text; zero of them is reported as such, never as silence, because "this
        // hypothesis has no instrumented witness yet" is the actionable half of the answer.
        std::fprintf( out, "<validate scopes=\"%zu\"", s.scopes.size() );
        if( s.scopes.empty() )
        {
            std::fprintf( out, " status=\"uninstrumented\" hint=\"add PROFILE_SCOPE_DESCRIBE to a co-accessing "
                               "function, rebuild with RIPWIRE_PROFILE=ON, and compare l1d-ms across the two layouts\"" );
        }
        else
        {
            std::fprintf( out, " status=\"instrumented\" counter=\"l1d-cache-misses\"" );
        }
        std::fprintf( out, ">" );
        for( const std::string& sc : s.scopes )
        {
            std::fprintf( out, "<scope n=\"%s\"/>", ex( sc ).c_str() );
        }
        std::fprintf( out, "</validate>" );

        std::fprintf( out, "</s>" );
    }
    std::fprintf( out, "</fieldaffinity>" );
}

}   // namespace fieldaffinity
}   // namespace rw
