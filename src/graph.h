#pragma once

// graph.h — resolve references → graph, build the in-edge CSR for PageRank, and the
// resolved out-edges for serialization (SPEC §2a/§2b). Ranking lives in pagerank.cpp.

#include "model.h"
#include "filter.h"             // isTestPath — for the Q2 tested= post-pass
#include "lintrules.h"          // §P9.4: langOfPath / dependencyCapable — the file-language classification
                                // restrictDependencyHealth() needs (owns the extension table, kept in sync
                                // by hand with ingest.cpp's kLangTable per its own header comment)
#include "sparseCsr.h"          // first-party infra math (src/infra/)
#include "csrverify.h"          // SPEC §8 structural gate, VERIFY'd after every production CSR build
#include "pagerank.h"           // double-precision PageRank kernel over float CSR storage
#include "svector.h"            // ctx::svector — branch-free-size() small-vector for the byName id-lists
#include "resolve.h"            // P2-D one-hop type narrowing (Rule 1: class membership) — applied before §2a fallback
#include "scipoverlay.h"        // W4-#15 SCIP precision overlay (data struct only; parser lives in scip.h)
#include "sortutil.h"           // radix edge sorting for large integer-key graph edge lists
#include "profileScope.h"       // PROFILE_SCOPE self-profiling — gated by PROFILE_ENABLED (off unless -DCTXPACK_PROFILE=ON)

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace ctx
{

// ComposeEdge defined in model.h (so serialize.h can use it without including graph.h).

struct Graph
{
    sparseCsr<float>           inEdges;     // N×N, row = target's in-neighbours (for PageRank)
    std::vector<double>        wOutDeg;     // weighted out-degree per source (0 ⇒ dangling); double rank arithmetic
    std::vector<std::uint32_t> outOff;      // N+1 — resolved out-edges (CSR), for <c> children
    std::vector<NodeId>        outTargets;  // callee node ids, deduped, ascending within a source
    std::vector<float>         outVals;     // per-out-edge weight, parallel to outTargets (HITS hub step)
    std::vector<std::uint8_t>  outProv;     // W4-#15 per-out-edge provenance, parallel to outTargets:
                                            //   0 = name-based guess (the common case, absent from XML),
                                            //   1 = PRECISE (a SCIP index pinned this (from,to)) → serialize
                                            // emits prov="scip". Empty ⇒ no --scip run (all name-based).
    std::size_t                scipDocsSeen = 0;   // # SCIP documents consumed (0 unless --scip); honesty summary
    std::size_t                scipEdgesPinned = 0;   // # (from,to) edges the SCIP index pinned; honesty summary
    std::vector<std::vector<NodeId>> implementors;   // base-class id → derived class ids (inheritance/Lego view)
    std::vector<std::vector<NodeId>> mentions;       // code symbol id → markdown file-nodes that name it in a `backtick` (doc↔code)
    std::vector<std::uint32_t> ambOut;      // per-symbol: # outgoing calls that STILL resolved to MULTIPLE in-repo
                                            // defs AFTER canonical/narrow/locality resolution (the resolver could
                                            // not pin one) — a "fast can't be sure which target; verify in source"
                                            // honesty signal. A call pinned to a single def (qualified `A::b`,
                                            // `this->m()`, or a locality tie-break) is NOT counted (S6-C). Not
                                            // external calls (those are absent, not ambiguous), so it's low-noise.
    std::vector<std::uint32_t> unresolvedOut;  // honesty lever #2: per-symbol # outgoing calls to a name that IS
                                            // defined in-repo but whose EVERY def was dropped by the langCompatible
                                            // gate (graph.h §2a fallback) — a call the tool couldn't resolve yet a
                                            // same-name def exists in ANOTHER language. The high-signal "plausibly-
                                            // internal, cross-language-filtered" bucket: a cross-language-filtered /
                                            // mis-classified / macro-generated def lands here and would otherwise be
                                            // SILENTLY dropped as "external" (measured small+precise, though on a
                                            // polyglot corpus partly coincidental same-name overlaps — never claimed
                                            // as a definite miss; see DESIGN_resolutionCompleteness.md §A.4).
                                            // Surfaced as the global `unresolved=N` gauge next
                                            // to `ambiguous=N`. Deliberately CONSERVATIVE — a call to a name with NO
                                            // in-repo def at all (`it == byName.end()`, dominated by genuine
                                            // stdlib/third-party externals) is NOT counted: there is no cheap, sound
                                            // gate today separating a missed-internal from a real external, and an
                                            // over-counting gauge would itself be a silent-WRONG signal (the one bug
                                            // this lever exists to kill). Revisit that tier when partial-extraction
                                            // provenance lands. Like ambOut it never counts a resolved edge → low noise.
    std::vector<std::string>   canonId;     // per-symbol canonical SCIP-style id `path::scope::name` (S6-C); the
                                            // bare name when no scope is known. The resolution locality tie-break
                                            // and serialize's `id=` attribute both read this. Built in buildGraph.
    std::vector<ComposeEdge>   composeEdges;  // S5-E HAS-A edges (sorted by ownerSym, then typeSym) — OUTSIDE the
                                              // call graph; PageRank and the default map are UNCHANGED by these.
    std::vector<RouteEdge>     routeEdges;    // B6.3 HTTP-route USE→DEF edges (sorted by fromSym, toSym, path) —
                                              // OUTSIDE the call graph, same as composeEdges; empty on any corpus
                                              // with zero detected routes (byte-identical default output).
    std::vector<std::string>   bindLabel;      // A4-R5 per-symbol cross-language binding label — the JNI
                                               // decoded Java name (`pkg.Cls.method`) for a `Java_*` def; ""
                                               // for every other symbol. Rendered as bind="..." by serialize
                                               // (see serialize.h's `bind` param). Empty vector ⇒ no JNI defs
                                               // (byte-identical to pre-R5 output).
    std::vector<float>         priorWeight;   // W4-#1 per-symbol name-quality multiplier for the PageRank
                                              // personalization/teleport prior (aider-style repomap weights).
                                              // A PURE function of names + def-counts (byName), so it is
                                              // deterministic. Multiplied into WHATEVER teleport vector a rank
                                              // mode supplies (uniform default, churn, map-diff, eval seed) and
                                              // renormalized to Σ=1 in rankGraphTeleport — so every teleport-based
                                              // rank benefits and the default uniform prior becomes a weighted
                                              // prior. Empty ⇒ treated as all-1 (no bias). Never touches the
                                              // transition matrix (edges), only the prior — the nudge that lets
                                              // structure still dominate on toy graphs.
};

// ObjC/ObjC++ and C++ share ONE call namespace: a .mm calls C++ functions (declared in .h/.cpp)
// directly, by name — so an ObjC ref must be allowed to resolve to a C++ def and vice-versa. That is
// what forms the .mm→.h bridge edges (the whole point of indexing a "thin ObjC shell over C++"). Lang::C
// joins the same bridge (L3): `.h` is deliberately C++-owned (kLangTable, ingest.cpp), so a `.c`
// definition's own DECLARATION — and any `.c`-file-only helper actually DEFINED inline in a shared
// header — lives on the C++ side of the language split; without this bridge a vendored C library's
// `.c`/`.h` pair (or a C++ `extern "C"` caller of it) could never resolve a single call. All OTHER
// language pairs stay strictly separate (a Python `draw` never resolves to a C++ `draw`).
inline bool langCompatible( Lang a, Lang b ) noexcept
{
    if( a == b ) return true;
    const bool aCish = ( a == Lang::Cpp || a == Lang::ObjC || a == Lang::C );
    const bool bCish = ( b == Lang::Cpp || b == Lang::ObjC || b == Lang::C );
    return aCish && bCish;
}

// ---- W4-#1: aider-style name-quality prior weights ----------------------------------------------------
// Aider's battle-tuned repomap biases its PageRank *personalization* vector (never the transition matrix)
// by cheap name-quality signals: a name defined all over the repo is generic and gets damped; a private-
// convention (`_`-prefixed) name gets damped; a long, multi-word, specific identifier gets boosted. We
// mirror that here — applied to the PRIOR, so the nudge is gentle and graph structure (edges) still
// dominates. Multipliers COMPOSE multiplicatively.
//
// Aider's raw magnitudes are ×0.1 (common) / ×0.1 (private) / ×10 (specific). We keep aider's *directions*
// and *predicates* verbatim but SOFTEN the magnitudes, tuned against `--eval` (co-change recovery) on this
// repo: aider's ×10 boost pulls specific-but-co-change-irrelevant files into the top-20 and REGRESSED
// recall@20 (30.3% → 21.9%); the tail-safe magnitudes below (×0.5 / ×0.5 / ×1.7) are a strict Pareto win —
// recall@5 4.7%→6.0%, recall@10 13.4%→13.8%, recall@20 30.3%→30.4% (no metric regresses). The predicates
// (>5 defs, leading `_`, ≥8 chars ∧ ≥2 words) are aider's; only the strengths were fit to the evidence.
namespace priorwt
{
    // damp a name with MANY definitions of the same name across the repo (a generic/common name that
    // "appears everywhere" — `size`, `end`, `get`). defCount is byName[name].size() (reused, not rebuilt).
    // (aider: ×0.1; softened to ×0.5 — a stronger damp regressed recall@20 in --eval.)
    inline constexpr float   kCommonNameMul   = 0.5f;
    inline constexpr std::size_t kCommonNameDefThreshold = 5;   // >5 defs of the same name ⇒ common (aider's)
    // damp a private-convention (leading-underscore) name. (aider: ×0.1; softened to ×0.5, same reason.)
    inline constexpr float   kPrivateNameMul  = 0.5f;
    // boost a long, multi-word, specific identifier (the specificity prior). (aider: ×10; softened to ×1.7 —
    // ×10 pulled irrelevant specific files into top-20 and regressed recall@20; ×1.7 is the tail-safe boost.)
    inline constexpr float   kSpecificNameMul = 1.7f;
    inline constexpr std::size_t kSpecificMinLen   = 8;         // ≥8 chars …  (aider's)
    inline constexpr std::size_t kSpecificMinWords = 2;         // … AND ≥2 words (camelCase/snake split) (aider's)

    // number of word segments in an identifier by the SAME boundary rules as lexical.h subtokens():
    // split on camelCase transitions, digit/non-alnum separators, and snake_case '_'. Allocation-free,
    // constexpr-friendly (pure scan of the bytes). A run of ≥1 alnum char between boundaries is one word.
    inline constexpr std::size_t wordCount( std::string_view id ) noexcept
    {
        std::size_t words = 0;
        bool        inWord = false;
        char        prev   = 0;
        for( char c : id )
        {
            const bool upper = c >= 'A' && c <= 'Z';
            const bool lower = c >= 'a' && c <= 'z';
            const bool digit = c >= '0' && c <= '9';
            if( !upper && !lower && !digit ) { inWord = false; prev = c; continue; }   // separator (incl. '_')
            const bool camelBoundary = upper && inWord && !( prev >= 'A' && prev <= 'Z' );  // aB → new word
            if( !inWord || camelBoundary ) ++words;
            inWord = true;
            prev   = c;
        }
        return words;
    }

    // the composed multiplier for one symbol name. defCount = # of same-name definitions in the repo.
    inline constexpr float weight( std::string_view name, std::size_t defCount ) noexcept
    {
        float w = 1.0f;
        if( defCount > kCommonNameDefThreshold )                            w *= kCommonNameMul;    // common name
        if( !name.empty() && name.front() == '_' )                         w *= kPrivateNameMul;   // private convention
        if( name.size() >= kSpecificMinLen && wordCount( name ) >= kSpecificMinWords ) w *= kSpecificNameMul;   // specific
        return w;
    }
}   // namespace priorwt

// A4-R5 JNI: decode a mangled C export `Java_pkg_Cls_method[__argsig]` to the readable dotted Java name
// `pkg.Cls.method`. JNI mangling maps '.'/'/'→'_', a literal '_'→"_1", and appends "__<sig>" for overloads.
// We drop the "__sig" tail, map "_1"→'_' and a lone '_'→'.' . Package/class/method boundaries are NOT
// recoverable source-only (all become '_'), so the flat dotted form is the honest readable alias. Returns
// "" for a non-`Java_` name. Pure/deterministic.
inline std::string decodeJniName( std::string_view mangled )
{
    constexpr std::string_view kPre = "Java_";
    if( mangled.size() <= kPre.size() || mangled.substr( 0, kPre.size() ) != kPre ) return {};
    std::string_view body = mangled.substr( kPre.size() );
    if( const std::size_t dd = body.find( "__" ); dd != std::string_view::npos ) body = body.substr( 0, dd );
    std::string out;
    out.reserve( body.size() );
    for( std::size_t i = 0; i < body.size(); ++i )
    {
        if( body[i] != '_' ) { out.push_back( body[i] ); continue; }
        if( i + 1 < body.size() && body[i + 1] == '1' ) { out.push_back( '_' ); ++i; }   // "_1" → literal '_'
        else                                              out.push_back( '.' );          // '_'  → segment separator
    }
    return out;
}

// B6.3 HTTP-route path/method matching — CONSERVATIVE by construction (DESIGN_multiRoot.md's resolver-
// honesty posture, applied to routes): a DEF's template segment ({id} / :id / <int:id>) matches ANY USE
// segment at that position, but the segment COUNT must match exactly and every non-template segment must
// match byte-for-byte — no partial-prefix / fuzzy matching, so an ambiguous shape never silently "mostly
// matches". Trailing slashes are normalized away by the split (a run of empty segments collapses).
namespace routematch
{
    // split "/a/b/c/" into ["a","b","c"] — leading/trailing/duplicate slashes all collapse to nothing,
    // so "/x", "/x/", "//x" all normalize identically (the trailing-slash normalization the task calls for).
    inline std::vector<std::string_view> splitSegments( std::string_view path ) noexcept
    {
        std::vector<std::string_view> segs;
        std::size_t i = 0;
        while( i < path.size() )
        {
            while( i < path.size() && path[i] == '/' ) ++i;
            const std::size_t start = i;
            while( i < path.size() && path[i] != '/' ) ++i;
            if( i > start ) segs.push_back( path.substr( start, i - start ) );
        }
        return segs;
    }

    // a DEF segment is a TEMPLATE placeholder in one of the three frameworks' conventions this feature
    // detects: FastAPI `{id}`, Express `:id`, Flask `<int:id>` / `<id>`.
    inline bool isTemplateSegment( std::string_view seg ) noexcept
    {
        if( seg.empty() ) return false;
        if( seg.front() == ':' ) return true;
        if( seg.front() == '{' && seg.back() == '}' && seg.size() >= 2 ) return true;
        if( seg.front() == '<' && seg.back() == '>' && seg.size() >= 2 ) return true;
        return false;
    }

    // defPath (the registered route, template segments allowed) vs usePath (a client call's literal path).
    // Segment COUNT must match exactly (no prefix-only match); each DEF segment matches iff it is a
    // template placeholder OR byte-identical to the USE segment at that position.
    inline bool pathsMatch( std::string_view defPath, std::string_view usePath ) noexcept
    {
        const std::vector<std::string_view> defSegs = splitSegments( defPath );
        const std::vector<std::string_view> useSegs = splitSegments( usePath );
        if( defSegs.size() != useSegs.size() ) return false;
        for( std::size_t i = 0; i < defSegs.size(); ++i )
            if( !isTemplateSegment( defSegs[i] ) && defSegs[i] != useSegs[i] ) return false;
        return true;
    }

    // method matches iff EQUAL, or EITHER side is Unknown (an honest "could not determine the verb" never
    // blocks a match — the path match already IS the strong evidence; see model.h HttpMethod).
    inline bool methodsCompatible( HttpMethod defMethod, HttpMethod useMethod ) noexcept
    {
        return defMethod == HttpMethod::Unknown || useMethod == HttpMethod::Unknown || defMethod == useMethod;
    }
}   // namespace routematch

// RouteEdge defined in model.h (so serialize.h can use it without including graph.h — same reason as ComposeEdge).

// The Rust MODULE a file defines, by Rust's module-file rule — the same rule resolve.h::resolveRustImport
// consumes from the other direction (`mod x;` → `x.rs` OR `x/mod.rs`), read here from path to module name:
// `src/util.rs` → "util", `src/gadget/mod.rs` → "gadget". A crate root (`lib.rs`/`main.rs`) yields "" — its
// top-level items are members of NO named module, which is the whole point of the distinction below.
inline std::string_view rustFileModuleOf( std::string_view path ) noexcept
{
    const std::size_t slash = path.find_last_of( '/' );
    std::string_view  base  = ( slash == std::string_view::npos ) ? path : path.substr( slash + 1 );
    if( const std::size_t dot = base.find_last_of( '.' ); dot != std::string_view::npos ) base = base.substr( 0, dot );

    if( base != "mod" ) return ( base == "lib" || base == "main" ) ? std::string_view{} : base;
    if( slash == std::string_view::npos ) return {};                     // a bare `mod.rs` names no directory

    const std::string_view dir = path.substr( 0, slash );                // `x/mod.rs` → the DIRECTORY is the module
    const std::size_t      up  = dir.find_last_of( '/' );
    return ( up == std::string_view::npos ) ? dir : dir.substr( up + 1 );
}

// H4 W3 — the RUST qualified-call scope guard (PLAN_h4QualifiedCalls_2026-07-30.md §3.2).
//
// A Rust call written with an explicit `Scope::` path can ONLY mean a member of that scope: the language has
// no ADL and no using-directive, so `Vec::new()` can never denote `Widget::new()`. When the canonical tier
// MISSED (no def is keyed `qualifier::name`) the bare-name spray has just offered every same-named def in the
// tree — and for an EXTERNAL qualified call that is exactly how a false edge is born. W1-MEASURE named this
// case; it reproduces on test/rustqualfix, where `external_caller`'s `Vec::<u32>::new()` bound the local
// `Widget::new` before this guard existed.
//
// A qualified call names a MEMBER of the scope it spells, so a candidate survives on exactly three grounds:
//   * its `scope` IS the qualifier — an `impl`/`trait`/inline-`mod` member;
//   * it is a member of the FILE MODULE the qualifier names (see rustFileModuleOf) — a Rust module can be
//     spelled by the DIRECTORY LAYOUT (`src/gadget/mod.rs`, `src/util.rs`) with no AST node in the file
//     spelling it, so `crate::gadget::gadget_free()` reaches a def whose `scope` is legitimately empty;
//   * its scope IMPLEMENTS the qualifier as a TRAIT — `Shape::area(&w)` names the trait while the def lives
//     on the implementor, which is precisely the `impl Shape for Widget` edge chaUp holds. The ancestor walk
//     is transitive (a supertrait chain `trait Shape: Draw` is one more hop) and bounded like the CHA cones.
//
// V3 M-2 — WHY THE FILE-MODULE TEST AND NOT A BARE "keep scope-EMPTY defs". The first version of this guard
// kept every scope-less candidate, on the reasoning that a file module cannot be seen in the AST. But in Rust
// EVERY top-level `fn` in EVERY file has scope="", not just file-module members, so the keep-rule was far
// broader than its own comment claimed: with `pub fn new() {}` at the top of lib.rs, the external
// `Vec::<u32>::new()` bound it — count 0 -> 1, no `amb=`, `ambiguous=` unmoved. A confident false edge with
// zero disclosure: exactly the defect this plan exists to kill, reintroduced by its own fix. The file-module
// test is the precise version of the same idea and needs no new evidence — it is Rust's module-file rule,
// already implemented from the other direction in resolve.h::resolveRustImport. It separates the two cases
// the bare rule conflated: `gadget_free` in `src/gadget/mod.rs` IS a member of module `gadget` and survives;
// a top-level `new` in `src/lib.rs` is a member of no named module and cannot answer for `Vec::new()`.
//
// Returns false when NOTHING survives — the call is external in the only scope it could have meant, and the
// caller drops it the way site A drops any name with no in-repo def, WITHOUT touching `unresolved=`. That
// gauge means "defined in-repo but lang-filtered"; inflating it with genuine externals is the exact
// distortion honesty lever #2 exists to prevent. `cand` is left untouched when it returns false.
//
// The "does this guard apply at all" test lives HERE rather than at the call site on purpose: buildGraph is
// already the tree's highest-complexity function, and a six-operand `&&` chain in its body is exactly the
// kind of growth --quality-delta gates on. `alreadyPinned` = the site was resolved by SCIP / the canonical
// tier / Rule 1-2-3, in which case there is no bare-name spray to guard.
inline bool keepRustQualifiedCandidates( const IngestResult& ing, const HashMap<std::string, std::vector<std::string>>& chaUp,
                                         const Reference& r, bool alreadyPinned, std::vector<NodeId>& cand )
{
    if( alreadyPinned || r.lang != Lang::Rust || r.qualifier.empty() || cand.empty() ) return true;   // guard does not apply
    const std::string& qualifier = r.qualifier;

    std::vector<std::string> ancestors;                                  // transitive chaUp closure of one candidate scope
    const auto implementsQualifier = [ & ]( const std::string& scopeName ) -> bool
    {
        if( scopeName.empty() ) return false;
        ancestors.clear();
        ancestors.push_back( scopeName );
        for( std::size_t queueIndex = 0; queueIndex < ancestors.size() && ancestors.size() < 4096; ++queueIndex )
        {
            const std::string current = ancestors[ queueIndex ];         // COPIED — push_back may reallocate
            const auto        upIt    = chaUp.find( current );
            if( upIt == chaUp.end() ) continue;
            for( const std::string& up : upIt->second )
            {
                if( up == qualifier ) return true;
                if( std::find( ancestors.begin(), ancestors.end(), up ) == ancestors.end() ) ancestors.push_back( up );
            }
        }
        return false;
    };

    std::vector<NodeId> survivors;
    for( NodeId c : cand )
    {
        const Symbol&      cs        = ing.symbols[ c ];
        const std::string& candScope = cs.scope;
        // a scope-less def answers ONLY for the file module it actually lives in — never for any qualifier.
        const bool memberOfFileModule =    candScope.empty()
                                        && cs.fileId < ing.files.size()
                                        && rustFileModuleOf( ing.files[ cs.fileId ] ) == qualifier;
        if( candScope == qualifier || memberOfFileModule || implementsQualifier( candScope ) ) survivors.push_back( c );
    }
    if( survivors.empty() ) return false;
    cand.swap( survivors );
    return true;
}

// THE TIER-3 CANONICAL RESCUE (H4 V3 M-3) — why `canonical` sits beside `narrowed` in buildGraph's tier-3
// gate. Tier 3 is "a UNIQUE global, else DROP". A Rule-1 narrowed call has always been exempt, because it is
// pinned to ONE scope and is therefore resolved rather than guessed. A CANONICAL hit is pinned in exactly the
// same sense: `Thing::run()` whose key `Thing::run` matches K>1 defs has a genuine same-scope collision (two
// `impl Thing` blocks, an overload set), not a global ambiguity. But `canonical` was missing from the gate,
// so whenever those defs were neither same-file nor same-dir with the caller the whole call fell through to
// `continue` — no edge, no `amb=`, no `unresolved=` movement, map byte-identical. That is the exact silent
// death this plan exists to kill, surviving INSIDE the round's own fix; the lane's own gates missed it
// because §3 tested cross-directory with UNIQUE keys and §6 tested ambiguity SAME-FILE, and nothing tested
// their intersection.
//
// The class is LANGUAGE-AGNOSTIC — a property of this ladder, not of any grammar. Gated on the Rust shape
// (test/rustqualfix `crossdir_amb`); the C++ shape was measured on a scratch corpus (`ns::pick` defined twice
// in a/, caller in b/): 0 edges + ambiguous=0 before, 2 edges + ambiguous=1 after. A C++ fixture arm belongs
// in cppqualcheck, which another lane owns.
//
// Routing it to `tier = cand` hands it to the SAME ambiguity accounting every other multi-target case uses —
// `pickTargets > 1 ⇒ ++g.ambOut` with the 1/k weight split — so the collision is DISCLOSED instead of
// swallowed. It can never invent an edge: `cand` at that point holds only canonByName's `qualifier::name`
// definitions.
//
// Resolve each reference by the SPEC §2a ladder (same-file > same-dir > global, language-compatible;
// split weight 1/k on ambiguity; drop unresolved/self/file-scope), dedup+sum, cap at 8.
//
// W4-#15 SCIP overlay (optional, `scip`): where the index covers a call-site (from, calleeName), its
// PRECISE target(s) REPLACE the name-based candidate set for THAT site — the tier ladder is skipped (the
// index already resolved it), the call is NOT counted as ambiguous (it is pinned), and the resulting
// (from,to) out-edge(s) are stamped prov="scip". Name-based call-sites elsewhere are untouched. Passing
// nullptr (the default) yields byte-identical output to the pre-overlay build. Deterministic: the overlay
// is sorted, so candidate order and thus edge order are unchanged.
inline Graph buildGraph( const IngestResult& ing, const ScipOverlay* scip = nullptr )
{
    PROFILE_SCOPE_DESCRIBE( "buildGraph: resolve refs + build CSR" );
    const std::size_t N = ing.symbols.size();
    Graph g;
    g.wOutDeg.assign( N, 0.0 );
    g.ambOut.assign( N, 0u );   // counted in the resolve loop: calls that stay split across >1 def after narrowing
    g.unresolvedOut.assign( N, 0u );   // counted in the resolve loop: calls whose in-repo defs were all lang-filtered
    if( scip ) { g.scipDocsSeen = scip->documentsSeen; g.scipEdgesPinned = scip->edgesPinned; }

    // S6-C canonical ids: `path::scope::name` per symbol (bare name when no scope). Computed once here so the
    // resolution locality tie-break (below) and serialize's `id=` attribute share one definition. Deterministic.
    g.canonId.resize( N );
    for( const Symbol& s : ing.symbols )
        g.canonId[ s.id ] = canonicalId( ing.files[ s.fileId ], s.scope, s.name );

    // A4-R5 JNI: decode every `Java_pkg_Cls_method` C/C++ def to its readable dotted Java name and stash it as
    // the symbol's binding label. No ingest capture / cache change — it is a pure function of the def NAME. The
    // vector stays EMPTY (no allocation) when the tree holds no JNI export, so a JNI-free corpus is unaffected.
    for( const Symbol& s : ing.symbols )
    {
        if( ( s.lang != Lang::Cpp && s.lang != Lang::ObjC ) || s.name.size() <= 5 || s.name.compare( 0, 5, "Java_" ) != 0 ) continue;
        std::string readable = decodeJniName( s.name );
        if( readable.empty() ) continue;
        if( g.bindLabel.empty() ) g.bindLabel.assign( N, std::string() );
        g.bindLabel[ s.id ] = std::move( readable );
    }

    // ── Multi-root workspace (DESIGN_multiRoot.md §3): name-based resolution NEVER crosses roots. Every
    // name-tier candidate below (qualified canonical, Rule 1/2, the §2a byName fill, inheritance, doc
    // mentions, HAS-A) is filtered to the REFERENCE's own root; cross-root edges enter ONLY via evidence
    // (the path-resolved include set feeding Rule 3, and the FFI binding tables — both left unfiltered by
    // design). fileRoot is EMPTY on a single-root run, so sameRoot is constant-true and the resolved graph
    // is byte-identical to today (the G5 quarantine).
    const bool multiRoot = !ing.fileRoot.empty();
    const auto sameRoot = [ & ]( NodeId candSym, std::uint32_t refFileId ) noexcept -> bool
    {
        return !multiRoot || ing.fileRoot[ ing.symbols[ candSym ].fileId ] == ing.fileRoot[ refFileId ];
    };

    // file → directory id (path up to the last '/')
    HashMap<std::string, std::uint32_t> dirIds;
    std::vector<std::uint32_t>          fileDir( ing.files.size(), 0 );
    for( std::size_t f = 0; f < ing.files.size(); ++f )
    {
        std::string_view p     = ing.files[f];
        const std::size_t sl   = p.rfind( '/' );
        std::string       dir  = ( sl == std::string_view::npos ) ? std::string() : std::string( p.substr( 0, sl ) );
        fileDir[f] = dirIds.emplace( std::move( dir ), std::uint32_t( dirIds.size() ) ).first->second;
    }

    // name → candidate definition ids. ctx::svector<,2>: most names define 1-2 symbols, so the id-list is
    // inline (no per-name malloc) and size() is branch-free — the measured-best value type for this
    // write-once (here) / read-hot (resolve below) shape (see bench/bench_svector3.cpp). Iterates in
    // insertion order exactly like std::vector, so the resolved graph — and the output — is unchanged.
    HashMap<std::string, ctx::svector<NodeId, 2>> byName;
    byName.reserve( N );                          // ≤ one entry per symbol → skip the rehash cascade
    for( const Symbol& s : ing.symbols )
        byName[ s.name ].push_back( s.id );

    // decl/def collapse (adversarial-review #1): a C++ header decl + its .cpp def are TWO same-named
    // symbols. Left alone, that (a) makes tier-3 see cand.size()==2 and DROP every cross-dir call to the
    // function (the most common C++ layout → a disconnected graph), and (b) lets a bodyless local prototype
    // shadow the real def in the same-file/dir tiers, so rank flows to an empty decl. Fix once, here: if a
    // name has ≥1 real DEFINITION (body present: endByte > sigEndByte), keep only the definitions as
    // resolution targets — forward declarations of one function aren't an ambiguity and must not shadow or
    // block it. Names with no def anywhere (extern / pure-virtual only) keep their decls (best available).
    const auto hasBody = [ & ]( NodeId id ) noexcept { return ing.symbols[id].endByte > ing.symbols[id].sigEndByte; };
    for( auto& [ name, ids ] : byName )
    {
        if( !multiRoot )
        {
            bool anyDef = false;
            for( NodeId id : ids ) if( hasBody( id ) ) { anyDef = true; break; }
            if( !anyDef ) continue;
            ctx::svector<NodeId, 2> defs;
            for( NodeId id : ids ) if( hasBody( id ) ) defs.push_back( id );
            ids = std::move( defs );
        }
        else
        {
            // multi-root: collapse PER ROOT — root A's def must not evict root B's decl-only best-available
            // target (each root's solo resolution behavior is preserved exactly; lookups are root-filtered).
            bool anyRootCollapses = false;
            const auto rootHasDef = [ & ]( std::uint32_t r ) noexcept
            {
                for( NodeId id : ids )
                    if( ing.fileRoot[ ing.symbols[id].fileId ] == r && hasBody( id ) ) return true;
                return false;
            };
            for( NodeId id : ids )
                if( !hasBody( id ) && rootHasDef( ing.fileRoot[ ing.symbols[id].fileId ] ) ) { anyRootCollapses = true; break; }
            if( !anyRootCollapses ) continue;
            ctx::svector<NodeId, 2> kept;
            for( NodeId id : ids )
                if( hasBody( id ) || !rootHasDef( ing.fileRoot[ ing.symbols[id].fileId ] ) ) kept.push_back( id );
            ids = std::move( kept );
        }
    }

    // canonical scope::name → definition ids (E#4): lets a qualified call `A::b()` resolve to the `b` whose
    // enclosing scope is `A`, BEFORE the bare-name spray — the deterministic [AST] cut to call-graph
    // ambiguity. Definitions only (body present); the obj.method()/unqualified halves stay bare-name (and
    // keep their honest `amb`). C++ only (scope is populated for Lang::Cpp).
    HashMap<std::string, ctx::svector<NodeId, 2>> canonByName;
    canonByName.reserve( N );
    std::string canonKey;
    for( const Symbol& s : ing.symbols )
    {
        if( s.scope.empty() || !hasBody( s.id ) ) continue;
        canonKey.clear();
        canonKey.append( s.scope ).append( "::" ).append( s.name );
        canonByName[ canonKey ].push_back( s.id );
    }

    // P2-D Rule 2 binding table: per-scope `(fromSymbol, var) → type` from ingest's local var→type bindings,
    // for receiver-VARIABLE narrowing (`Foo x; x.m()` → `Foo::m`). CONSERVATIVE — a var bound to ≥2 DISTINCT
    // types in one scope (reassigned to a different type) is TOMBSTONED (value set to ""), so it never narrows;
    // only an unambiguous single-type binding is usable. A binding's `type` is matched as a SCOPE in canonByName
    // by Rule 2, so a type that names no class (e.g. inferred from a non-constructor `auto x = makeT()`) simply
    // never produces a `type::method` hit and degrades to §2a — the safety net for constructor-inferred types.
    // Deterministic: ing.bindings is in (file, byte, var) order; first binding wins, a later conflict tombstones.
    HashMap<std::string, std::string> varType;
    varType.reserve( ing.bindings.size() );
    {
        std::string key;   // reused key buffer — same "<fromSymbol>#var" bytes as before, one alloc amortized
        for( const Binding& b : ing.bindings )
        {
            if( b.fromSymbol == kNoNode || b.var.empty() || b.typeName.empty() ) continue;   // file-scope/empty → unusable
            key.clear();
            Narrower::appendUint( key, b.fromSymbol );
            key.push_back( '#' );
            key.append( b.var );
            const auto [ it, inserted ] = varType.try_emplace( key, b.typeName );
            if( !inserted && !it->second.empty() && it->second != b.typeName )
                it->second.clear();   // conflicting types for one var in one scope → tombstone (never narrow this var)
        }
    }

    // SameInclude table: caller fileId → the sorted, deduped set of fileIds it TRANSITIVELY #includes,
    // resolved PATH-PRECISELY (resolve.h::resolvePreciseInclude: a quote `"x.h"` resolved lexically
    // relative-to-includer, angle/unresolvable includes dropped) — NOT by basename. This is the sound
    // input the include narrow (rule3IncludeFile, unchanged) always needed: a candidate is "included"
    // iff its fileId is in the caller's precise transitive set, so a cross-directory basename collision
    // (Diagnostics.h / arch.h / a.h …) can no longer manufacture a wrong narrow. An include that cannot
    // be path-resolved contributes NOTHING (it is simply absent) → it can never CAUSE a narrow → the
    // resolver degrades to the §2a ladder + honest amb=. The caller's OWN file is excluded (f ∉ trans[f]).
    // Deterministic: a pure function of the sorted ing.files + ing.includes; each set is sorted+deduped
    // so rule3IncludeFile's binary-search membership is valid and order-stable (warm == cold). See
    // DESIGN_pathPreciseInclude.md §3.
    std::vector<std::vector<NodeId>> fileIncludes = transitiveIncludeSet( buildPreciseIncludeAdj( ing ) );
    // per-symbol fileId view for Rule 3 (group a candidate def by its file without passing the whole IngestResult).
    std::vector<std::uint32_t> symFileId( N );
    for( const Symbol& s : ing.symbols ) symFileId[ s.id ] = s.fileId;

    // ── A4-R5 cross-language FFI binding alias tables ────────────────────────────────────────────────
    // A pybind11 `m.def("name",&fn)` / extern-C decl / ctypes handle, captured syntactically at ingest,
    // becomes a FALLBACK alias edge consulted ONLY when the normal langCompatible ladder drops a call — so a
    // same-language local def ALWAYS wins (control-safe). All maps stay EMPTY on any binding-free corpus, so
    // the resolved graph — and the output — is byte-identical there. Targets are filtered to C-family defs
    // (the bound side is always C/C++). Deterministic: ing.bindingAliases is in a fixed total order.
    HashMap<std::string, std::vector<NodeId>> pybindAlias;    // Python-visible name → C/C++ def ids
    HashMap<std::string, std::vector<NodeId>> externCAlias;   // extern-C symbol name  → C/C++ def ids
    HashMap<std::string, char>                ctypesHandle;   // "<fileId>#<var>"      → a ctypes CDLL handle var
    if( !ing.bindingAliases.empty() )
    {
        std::string        sk;    // reused scope::name / "<fileId>#var" key buffer
        std::vector<NodeId> tgt;
        const auto pushCFamily = [ & ]( const ctx::svector<NodeId, 2>& srcIds )
        {
            for( NodeId c : srcIds )
                if( ing.symbols[c].lang == Lang::Cpp || ing.symbols[c].lang == Lang::ObjC ) tgt.push_back( c );
        };
        for( const BindingAlias& ba : ing.bindingAliases )
        {
            if( ba.kind == BindKind::CtypesHandle )
            {
                sk.clear();  Narrower::appendUint( sk, ba.fileId );  sk.push_back( '#' );  sk.append( ba.aliasName );
                ctypesHandle[ sk ] = 1;
                continue;
            }
            tgt.clear();
            if( !ba.targetScope.empty() )                        // prefer the scope::name canonical target
            {
                sk.clear();  sk.append( ba.targetScope ).append( "::" ).append( ba.targetName );
                const auto cit = canonByName.find( sk );
                if( cit != canonByName.end() ) pushCFamily( cit->second );
            }
            if( tgt.empty() )                                    // else the bare-name target
            {
                const auto bit = byName.find( ba.targetName );
                if( bit != byName.end() ) pushCFamily( bit->second );
            }
            if( tgt.empty() ) continue;                          // target not an in-repo C/C++ def → no alias edge
            std::vector<NodeId>& slot = ( ba.kind == BindKind::Pybind ) ? pybindAlias[ ba.aliasName ]
                                                                        : externCAlias[ ba.aliasName ];
            slot.insert( slot.end(), tgt.begin(), tgt.end() );
        }
        const auto dedup = [ & ]( HashMap<std::string, std::vector<NodeId>>& m )
        {
            for( auto& [ k, v ] : m ) { std::sort( v.begin(), v.end() ); v.erase( std::unique( v.begin(), v.end() ), v.end() ); }
        };
        dedup( pybindAlias );
        dedup( externCAlias );
    }
    const bool ffiActive = !pybindAlias.empty() || !externCAlias.empty();

    // P2-D one-hop type narrowing: reuses the canonical scope::name map above (no new pass). Rule 1 pins a
    // `this->m()` / `self.m()` call to the caller's enclosing class; Rule 2 pins an `x.m()` named-receiver call
    // to the variable's type; Rule 3 pins a call to the ONE file the caller includes that defines it — all
    // BEFORE the bare-name spray below. See resolve.h.
    const Narrower narrower( canonByName, varType, fileIncludes, symFileId );

    // accumulate per (from,to): summed per-ref confidence + an integer ref count (key = from<<32|to).
    // weight = (confSum/nref)·√nref = confidence·√num_refs — diminishing returns on repeat refs.
    struct EdgeAcc { float confSum = 0.f; std::uint32_t nref = 0; };
    HashMap<std::uint64_t, EdgeAcc> acc;
    acc.reserve( ing.references.size() );        // start past the 4-bucket / 0.8-load rehash cascade
    std::vector<NodeId>      cand, tier;
    std::vector<NodeId>      bindingTier;   // A4-R5 reused FFI-alias fallback candidate buffer
    std::string              bindKey;       // A4-R5 reused "<fileId>#var" key buffer for the ctypes-handle gate
    HashMap<std::uint64_t, char> bindingEdges;   // A4-R5 (from<<32|to) keys of edges resolved via an FFI alias —
                                                 // consumed below to stamp prov (outProv=2) + the amb honesty mark
    std::vector<NodeId>      rule3Out;   // reused Rule-3 output buffer (candidates from the single included file)
    std::string              qkey;       // reused "qualifier::name" buffer for the E#4 canonical lookup (no per-ref alloc)
    std::vector<std::size_t> locShare;   // reused per-candidate sharedLocality memo (computed once per tier, below)

    // ── B2.1 CHA-lite inheritance NAME graph (built once, consumed in the resolve loop below). A class is
    // keyed by its final-segment NAME, exactly like byName — so a same-name collision only ever ENLARGES a
    // type's cone, never shrinks it: CHA-lite can make a prune LESS precise but can NEVER drop the true
    // target (soundness). chaUp = className → its DIRECT base names; chaDown = className → its DIRECT derived
    // names. From the inherit refs (role Extends): the derived class is the enclosing class symbol (or, for a
    // Rust `impl Trait for T`, the type name stashed in `qualifier`); the base is the ref's calleeName.
    HashMap<std::string, std::vector<std::string>> chaUp, chaDown;
    {
        const auto isClassLikeK = []( SymKind k ) noexcept
        { return k == SymKind::Class || k == SymKind::Struct || k == SymKind::Interface; };
        for( const Reference& ir : ing.references )
        {
            if( !ir.isInherit ) continue;
            std::string_view derivedName;
            if( !ir.qualifier.empty() )                                   // Rust impl → derived type name in qualifier
                derivedName = ir.qualifier;
            else if( ir.fromSymbol != kNoNode && isClassLikeK( ing.symbols[ ir.fromSymbol ].kind ) )
                derivedName = ing.symbols[ ir.fromSymbol ].name;          // the ref sits inside the derived class header
            if( derivedName.empty() || ir.calleeName.empty() ) continue;
            chaUp  [ std::string( derivedName ) ].push_back( ir.calleeName );
            chaDown[ ir.calleeName ].push_back( std::string( derivedName ) );
        }
        // dedup each adjacency list — membership is order-independent, so this stays deterministic.
        for( auto& [ k, v ] : chaUp )   { std::sort( v.begin(), v.end() ); v.erase( std::unique( v.begin(), v.end() ), v.end() ); }
        for( auto& [ k, v ] : chaDown ) { std::sort( v.begin(), v.end() ); v.erase( std::unique( v.begin(), v.end() ), v.end() ); }
    }
    std::vector<std::string> chaAllowed;   // reused per-call cone (allowed class-name set) buffer
    std::vector<std::string> chaDesc;      // reused per-call descendants-closure scratch (kept separate from the
                                           //   ancestors walk so following one direction can never leak siblings)
    std::vector<NodeId>      filtScratch;  // reused per-call survivor buffer for CHA-lite / arity filtering

    for( const Reference& r : ing.references )
    {
        // file-scope / inheritance / doc-mention / HAS-A → not a call. ABS-3: read/write/import use-sites
        // (role != Call) are ALSO excluded here — they live only in the use-site index, NEVER in the call
        // graph CSR, so PageRank and the default ranked map are byte-for-byte unchanged (G5).
        if( r.fromSymbol == kNoNode || r.isInherit || r.isDocLink || r.isCompose || r.role != RefRole::Call ) continue;
        const auto it = byName.find( r.calleeName );

        cand.clear();
        tier.clear();
        float tierConf = 1.0f;                                 // tier 1: same file (default; overridden below)

        // W4-#15 SCIP overlay: if the index resolved THIS (fromSymbol, calleeName) call-site, its precise
        // target(s) REPLACE the name-based candidate set. The call is pinned (full confidence, NOT counted
        // ambiguous) and the whole §2a ladder / narrowing / locality below is skipped for this ref. Name-based
        // call-sites elsewhere are untouched. Deterministic: coveredFrom is sorted, targetsOf is a bounded scan.
        bool scipPinned = false;
        if( scip )
        {
            const auto [ cb, ce ] = scip->targetsOf( r.fromSymbol, r.calleeName );
            for( std::size_t i = cb; i < ce; ++i )
            {
                const NodeId to = scip->coveredFrom[ i ].to;
                if( to != r.fromSymbol && to < N ) tier.push_back( to );   // precise target (self-loops dropped, as §2a)
            }
            scipPinned = !tier.empty();
            // a covered site whose precise targets are all self / out-of-range yields no edge — treat as pinned
            // (the index HAS resolved it) so we do NOT fall back to a name-based guess for a site SCIP resolved.
            if( cb != ce ) scipPinned = true;
        }

        // ---- A4-R5 FFI binding fallback: compute cross-language alias candidates UP FRONT. Applied below ONLY
        // if the normal ladder finds no compatible local def (so a same-language local def always wins). Two
        // sound gates keep it silent on binding-free corpora: pybind fires only for a foreign-language caller of
        // a registered Python-visible name; ctypes fires only for a `lib.foo()` whose receiver `lib` is a known
        // ctypes CDLL handle in this file. Both are name-pattern crossings → tagged (amb + prov="binding").
        bindingTier.clear();
        bool bindingPinned  = false;
        bool bindingLowConf = false;
        if( ffiActive && !scipPinned )
        {
            if( !pybindAlias.empty()
                && ( r.lang == Lang::Python || r.lang == Lang::JavaScript || r.lang == Lang::TypeScript ) )
            {
                const auto pit = pybindAlias.find( r.calleeName );
                if( pit != pybindAlias.end() )
                    for( NodeId c : pit->second ) if( c != r.fromSymbol && c < N ) bindingTier.push_back( c );
            }
            if( bindingTier.empty() && !externCAlias.empty()
                && r.lang == Lang::Python && r.recv == RecvKind::NamedVar && !r.recvVar.empty() )
            {
                bindKey.clear();  Narrower::appendUint( bindKey, r.fileId );  bindKey.push_back( '#' );  bindKey.append( r.recvVar );
                if( ctypesHandle.find( bindKey ) != ctypesHandle.end() )
                {
                    const auto eit = externCAlias.find( r.calleeName );
                    if( eit != externCAlias.end() )
                    {
                        for( NodeId c : eit->second ) if( c != r.fromSymbol && c < N ) bindingTier.push_back( c );
                        bindingLowConf = !bindingTier.empty();
                    }
                }
            }
        }

        // ---- name-based resolution (§2a ladder + P2-D narrowing) — SKIPPED when the SCIP overlay pinned this site.
        bool canonical = false;
        if( !scipPinned && !r.qualifier.empty() )
        {
            qkey.clear();                                       // "qualifier::name" — reused buffer, identical bytes
            qkey.append( r.qualifier ).append( "::" ).append( r.calleeName );
            const auto cit = canonByName.find( qkey );
            if( cit != canonByName.end() )
                for( NodeId c : cit->second )
                    if( langCompatible( ing.symbols[c].lang, r.lang ) && sameRoot( c, r.fileId ) ) cand.push_back( c );
            canonical = !cand.empty();
        }
        // P2-D Rule 1 (class membership): a `this->m()` / `self.m()` call resolves to the caller's enclosing
        // class's own `m`, BEFORE the bare-name spray — the deterministic [TYPE] cut to method ambiguity. Only
        // when the receiver is this/self AND the enclosing class actually defines `m` (canonByName, defs only);
        // otherwise narrowed stays false and we fall through to the unchanged §2a ladder. Skipped when the call
        // was already pinned by an explicit `A::` qualifier (canonical) — that is the more specific signal.
        bool narrowed = false;
        if( !scipPinned && !canonical )
            if( const auto* hit = narrower.rule1ClassMember( r, ing.symbols[ r.fromSymbol ].scope ) )
            {
                for( NodeId c : *hit )
                    if( langCompatible( ing.symbols[c].lang, r.lang ) && sameRoot( c, r.fileId ) ) cand.push_back( c );
                narrowed = !cand.empty();
            }
        // P2-D Rule 2 (receiver-variable type): a named-receiver call `x.m()` / `x->m()` resolves to the method
        // on the VARIABLE's type (`Foo::m` for `Foo x;`), BEFORE the bare-name spray — the other half of the
        // [TYPE] cut. Only when the var has a single unambiguous in-scope binding AND that type defines `m`
        // (canonByName, defs only); otherwise narrowed stays false and we fall through to §2a. Skipped when the
        // call was already pinned canonically or by Rule 1 (those are the more specific / already-resolved signals).
        if( !scipPinned && !canonical && !narrowed )
            if( const auto* hit = narrower.rule2RecvVarType( r ) )
            {
                for( NodeId c : *hit )
                    if( langCompatible( ing.symbols[c].lang, r.lang ) && sameRoot( c, r.fileId ) ) cand.push_back( c );
                narrowed = !cand.empty();
            }
        // P2-D Rule 3 (import/include-based file narrow): when the name is ambiguous (K same-name defs) but the
        // caller's file #includes / imports EXACTLY ONE file that defines it, resolve to that file's def(s) and
        // DROP the rest — BEFORE the bare-name spray. Sound with no type info: it consumes only the file→file
        // include graph and keeps a SUBSET of the bare `byName` candidates, so it can never invent an edge. Fires
        // only on an unambiguous single-included-file match with NO same-file candidate (that is §2a's job);
        // otherwise degrades to §2a. Skipped when already pinned canonically / by Rule 1 / Rule 2 (more specific).
        if( !scipPinned && !canonical && !narrowed && it != byName.end() )
            if( narrower.rule3IncludeFile( it->second, r.fileId, rule3Out ) )
            {
                for( NodeId c : rule3Out )
                    if( langCompatible( ing.symbols[c].lang, r.lang ) ) cand.push_back( c );
                narrowed = !cand.empty();
            }
        if( !scipPinned && !canonical && !narrowed )
        {
            // Honesty lever #2 — site A: the name has NO in-repo def at all. This is dominated by genuine
            // externals (stdlib / third-party), so it is NOT counted into `unresolved=N`: no cheap, sound gate
            // separates a missed-internal def from a real external here, and a gauge that flagged `printf` /
            // `std::vector` as "missed internal" would be silently WRONG — the exact failure this lever kills. The
            // high-signal cross-language miss is counted at the `cand.empty()` site below instead.
            // A4-R5: keep going when an FFI alias offers a cross-language target (cand stays empty → the
            // binding fallback is taken in the tier block below). Otherwise unresolved-but-external → drop.
            if( it == byName.end() ) { if( bindingTier.empty() ) continue; }
            else
            {
                for( NodeId c : it->second )
                    if( langCompatible( ing.symbols[c].lang, r.lang ) && sameRoot( c, r.fileId ) ) cand.push_back( c );   // same lang, or ObjC↔C++ bridge; same ROOT (A10)
                // §3.1 cross-root EVIDENCE channel for a name with NO same-root def: admit another root's
                // def ONLY when the caller's file has a path-resolved (transitive) include/import reaching
                // that def's file — the SameInclude evidence tier, never a bare-name guess. (K≥2 mixed-root
                // names take the Rule-3 path above instead; this covers the unique-cross-root case Rule 3's
                // K≥2 gate cannot reach.) The tier ladder below still applies its unique-or-drop gate.
                if( multiRoot && cand.empty() )
                    for( NodeId c : it->second )
                    {
                        if( !langCompatible( ing.symbols[c].lang, r.lang ) || sameRoot( c, r.fileId ) ) continue;
                        if( r.fileId >= fileIncludes.size() ) continue;
                        const std::vector<NodeId>& inc = fileIncludes[ r.fileId ];
                        if( std::binary_search( inc.begin(), inc.end(), symFileId[ c ] ) ) cand.push_back( c );
                    }
            }
        }

        // ---- H4 W3: RUST qualified-call scope guard — see keepRustQualifiedCandidates ------------------
        const bool alreadyPinned = scipPinned || canonical || narrowed;
        if( !keepRustQualifiedCandidates( ing, chaUp, r, alreadyPinned, cand ) && bindingTier.empty() )
            continue;                                                           // qualified-external → no edge

        // ---- tier ladder (§2a) — SKIPPED when the SCIP overlay pinned this site (tier already holds the
        // precise target(s) at full confidence; the ladder would only re-derive a guess). -----------------
        if( !scipPinned )
        {
            if( cand.empty() )
            {
                // A4-R5: no compatible LOCAL def resolved. If an FFI alias offered a cross-language target, take
                // it now (pinned like SCIP, low confidence, provenance-tagged below). This is the ONLY place a
                // Python↔C++ / ctypes edge is admitted, and only because the same-language ladder produced nothing.
                if( !bindingTier.empty() ) { tier = bindingTier; bindingPinned = true; tierConf = bindingLowConf ? 0.1f : 0.2f; }
                else
                {
                    // Honesty lever #2 (the HIGH-signal unresolved bucket): reaching here with an empty candidate set
                    // means canonical/Rule-1/2/3 all found nothing AND the §2a fallback (above) ran. Since site A
                    // (`it == byName.end()`) already `continue`d, `it != byName.end()` here is guaranteed: the name IS
                    // defined in-repo, but EVERY def was filtered by langCompatible — a same-name def in another
                    // language. That is a call the tool would otherwise SILENTLY drop as "external" while a plausibly-
                    // internal (cross-language-filtered / mis-classified) def exists. Count it so `unresolved=N` sees
                    // it. The guard is defensive/self-documenting (it is invariant-true at this site).
                    if( it != byName.end() )
                    {
                        // multi-root: the per-root semantics of this gauge is "defined in THIS root but
                        // lang-filtered". A name whose defs all live in OTHER roots (no evidence) is an
                        // external for this root — counting it would RAISE unresolved vs the solo runs.
                        bool anySameRootDef = !multiRoot;
                        if( multiRoot )
                            for( NodeId c : it->second )
                                if( sameRoot( c, r.fileId ) ) { anySameRootDef = true; break; }
                        if( anySameRootDef ) ++g.unresolvedOut[ r.fromSymbol ];
                    }
                    continue;
                }
            }
            else
            {
            for( NodeId c : cand ) if( ing.symbols[c].fileId == r.fileId ) tier.push_back( c );   // tier 1: same file
            if( tier.empty() )                                     // tier 2: same directory
            {
                tierConf = 0.5f;
                const std::uint32_t rdir = fileDir[ r.fileId ];
                for( NodeId c : cand ) if( fileDir[ ing.symbols[c].fileId ] == rdir ) tier.push_back( c );
            }
            if( tier.empty() )                                     // tier 3: a UNIQUE global, else DROP (SPEC §2a)
            {
                // A Rule-1 narrowed call is already pinned to ONE scope (callerScope::name) — it is resolved, not a
                // global guess, so it must produce an edge even when the class's method lives cross-dir and is
                // overloaded (cand.size()>1). Without this, the tier-3 uniqueness gate would silently DROP a
                // correctly-narrowed edge — a regression. Bare-name (non-narrowed) calls keep the strict §2a gate.
                //
                // H4 V3 M-3: `canonical` belongs in the same rescue, for the same reason — see the note above
                // buildGraph ("the tier-3 canonical rescue").
                if( cand.size() == 1 || narrowed || canonical ) { tier = cand; tierConf = 0.2f; }
                else                                            continue;
            }
            }
        }
        if( tier.empty() ) continue;   // a covered-but-empty SCIP site (all self/out-of-range) yields no edge

        // ── B2.1 CHA-lite + B2.2 arity filter — two SOUND, deterministic prunes of a STILL-ambiguous tier, run
        // BEFORE the locality tie-break. Both only ever DROP candidates the true target is provably not among,
        // and both DEGRADE (leave the tier untouched) rather than empty it — so a wrong narrow is impossible.
        // Never on a SCIP-/binding-pinned site (already precise). ---------------------------------------------
        if( !scipPinned && !bindingPinned )
        {
            // B2.1 CHA-lite: when the receiver STATIC type is known (this/self ⇒ enclosing class; a named var ⇒
            // its single in-scope type binding) and the tier is still ambiguous, keep only candidates whose
            // enclosing class is in the receiver type's inheritance CONE — {type} ∪ transitive ancestors ∪
            // transitive descendants. A virtual call on static type T can only dispatch to T, a subtype (an
            // override), or the definition T inherits from an ancestor — so the cone NEVER excludes the true
            // target; it drops only same-name methods of UNRELATED classes. Empty intersection ⇒ degrade.
            if( tier.size() > 1 )
            {
                const std::string_view recvType = narrower.receiverStaticType( r, ing.symbols[ r.fromSymbol ].scope );
                if( !recvType.empty() )
                {
                    // Build the strict cone = {recvType} ∪ ANCESTORS ∪ DESCENDANTS via TWO fully-independent
                    // directional closures, each seeded ONLY at recvType. A value/pointer of static type T is
                    // dynamically T or a subtype, so its target is either an override in T / a subtype OR the
                    // definition T inherits from an ancestor — but NEVER a sibling's method (a T can never BE a
                    // sibling). Keeping the closures separate (never following chaDown out of an ancestor) is
                    // what excludes siblings/cousins for precision, while still never dropping a true target.
                    // Directional BFS into `out`, seeded at recvType. Index by a COPIED key — push_back may
                    // reallocate `out`, so a held reference would dangle.
                    const auto closure = [ & ]( const HashMap<std::string, std::vector<std::string>>& adj,
                                                std::vector<std::string>& out )
                    {
                        out.clear();
                        out.emplace_back( recvType );
                        for( std::size_t qi = 0; qi < out.size() && out.size() < 4096; ++qi )
                        {
                            const std::string cur = out[ qi ];
                            const auto it = adj.find( cur );
                            if( it == adj.end() ) continue;
                            for( const std::string& nm : it->second )
                                if( std::find( out.begin(), out.end(), nm ) == out.end() ) out.push_back( nm );
                        }
                    };
                    closure( chaUp,   chaAllowed );              // {recvType} ∪ ancestors
                    closure( chaDown, chaDesc );                 // {recvType} ∪ descendants
                    for( const std::string& nm : chaDesc )       // merge descendants into the allowed cone (dedup)
                        if( std::find( chaAllowed.begin(), chaAllowed.end(), nm ) == chaAllowed.end() )
                            chaAllowed.push_back( nm );
                    // keep only candidates whose enclosing class name is in the cone (a scope-less free function
                    // is not a member-call target ⇒ correctly excluded). Degrade if the intersection is empty.
                    filtScratch.clear();
                    for( NodeId c : tier )
                        if( std::find( chaAllowed.begin(), chaAllowed.end(), ing.symbols[ c ].scope ) != chaAllowed.end() )
                            filtScratch.push_back( c );
                    if( !filtScratch.empty() && filtScratch.size() < tier.size() ) tier.swap( filtScratch );
                }
            }

            // B2.2 arity filter: when the call site has a reliably-counted positional-argument list, drop any
            // same-name candidate whose declared parameter count is a FIXED, call-comparable arity (arityExact)
            // and cannot possibly accept that many args — a provably-wrong overload. Strictly conservative: a
            // variadic / default-argument / implicit-self candidate (arityExact==0) is NEVER dropped, nor is
            // any candidate when the call-site count is unknown. Degrade rather than empty the tier.
            //
            // AUDIT5 F1 (decided, PLAN_audit5Public2026.md X3): only `argCount > params` is provably wrong.
            // arityExact is computed from the DEFINITION node only (cc_paramArityExact); a C++ default argument
            // written ONLY on a separate header PROTOTYPE (`void f( int x = 5 );`) is invisible there, so an
            // out-of-line def whose default lives in the decl reads as a fixed arity==params. An
            // (params-1)-arg call against such a def is legal (the default fills the gap) but used to fail
            // `params != argCount` and get "provably" excluded — dropping the correct edge AND silently
            // suppressing the amb= honesty counter when a sibling overload happened to survive. No default
            // argument can ever rescue a call with MORE args than the def declares, so `argCount > params`
            // stays a sound exclusion in every language; `argCount < params` no longer excludes — the def
            // stays a candidate and correctly re-enters amb= when multiple defs still survive. Trades a little
            // precision for honesty (decided acceptance); the fuller decl/def arityExact merge is deferred.
            if( r.argCountKnown && tier.size() > 1 )
            {
                filtScratch.clear();
                for( NodeId c : tier )
                {
                    const Symbol& cs = ing.symbols[ c ];
                    const bool provablyWrong = ( cs.arityExact != 0 ) && ( r.argCount > cs.params );
                    if( !provablyWrong ) filtScratch.push_back( c );
                }
                if( !filtScratch.empty() && filtScratch.size() < tier.size() ) tier.swap( filtScratch );
            }
        }

        // S6-C locality tie-break: a still-ambiguous call (>1 candidate left in the tier) prefers the candidate(s)
        // whose canonical id shares the LONGEST whole-SEGMENT prefix with the CALLER's canonical id — same file >
        // same class/scope > same dir. `sharedLocality` compares on the `/`/`::` SEGMENTS (NOT raw bytes), so a
        // partial overlap *inside* a scope component (`Xenon` caller vs unrelated class `Xtra`) counts as ZERO and
        // can NOT manufacture a win (adversarial HIGH-1). This only re-WEIGHTS among already-resolved, tier-survivor
        // candidates (it never adds one the §2a ladder didn't reach, and never empties the tier), so it stays
        // conservative and deterministic. Skipped when the caller has no canonical scope (callerCanon == bare name)
        // — no locality to compare — leaving the honest split intact. When every survivor ties at the same locality
        // (e.g. all share only the path, none the scope), NO candidate is strictly more local → the tier is left
        // FULL → the call stays correctly ambiguous below.
        if( !scipPinned && !bindingPinned && tier.size() > 1 && !ing.symbols[ r.fromSymbol ].scope.empty() )
        {
            const std::string& callerCanon = g.canonId[ r.fromSymbol ];
            // memoize each survivor's shared-locality ONCE (was computed twice: once for bestShare, once inside the
            // stable_partition predicate). locShare[i] parallels tier[i]; the compaction below reads the memo.
            locShare.clear();
            std::size_t bestShare = 0;
            for( NodeId c : tier ) { const std::size_t sh = sharedLocality( callerCanon, g.canonId[c] ); locShare.push_back( sh ); if( sh > bestShare ) bestShare = sh; }
            if( bestShare > 0 )                                // keep only the maximal-locality candidates (id order preserved)
            {
                // stable in-place keep of the maximal-locality survivors — identical result to the old
                // stable_partition(winner) + erase(mid,end): the winners stay in their original relative order and the
                // strictly-less-local ones are dropped. The `kept != 0 && kept != tier.size()` guard reproduces the old
                // `mid != begin && mid != end` (a full tie — every survivor maximal — leaves the tier untouched).
                std::size_t kept = 0;
                for( std::size_t sh : locShare ) if( sh == bestShare ) ++kept;
                if( kept != 0 && kept != tier.size() )
                {
                    std::size_t w = 0;
                    for( std::size_t i = 0; i < tier.size(); ++i ) if( locShare[i] == bestShare ) tier[ w++ ] = tier[i];
                    tier.resize( w );
                }
            }
        }

        // ambiguity clue (S6-C): count when, AFTER all narrowing (canonical / Rule-1 / locality), the call STILL
        // resolves to >1 in-repo target — every one of which receives a 1/k-split edge below — excluding a
        // self-loop. HONESTY INVARIANT: the amb count must reflect EXACTLY the multi-way pick the edge emission
        // makes (the non-self tier survivors), never a SUBSET of it — else a genuine k-way guess reads as a
        // confident edge (a silent pick). byName collapses a header decl + its .cpp def already (defs kept, decls
        // dropped) whenever the name has ANY body, so for a name-with-bodies these survivors are all real
        // DEFINITIONS and this matches the historical `body-present` count. A name with NO body anywhere (extern /
        // pure-virtual only) legitimately keeps its DECLS as best-available targets; a call landing on ≥2 such
        // decls is ALSO a real multi-candidate pick and MUST carry amb — the old `endByte > sigEndByte` gate
        // SILENTLY excluded it (0 body-targets ⇒ no amb) while still emitting both edges (the resolver-honesty
        // audit's found silent-pick bug). A call pinned to ONE target — by a qualifier, `this->`, Rule 3's file
        // narrow, or the locality tie-break — is NOT flagged. Low-noise "resolver can't be sure which; read
        // source". This is where canonical resolution SUPPRESSES amb that the old pre-tier count raised.
        if( !scipPinned && !bindingPinned )   // a SCIP-pinned call is PRECISE — never an ambiguity clue (that is the whole point).
        {
            std::uint32_t pickTargets = 0;   // non-self tier survivors = EXACTLY the targets the 1/k edge split spans
            for( NodeId c : tier ) if( c != r.fromSymbol ) ++pickTargets;
            if( pickTargets > 1 ) ++g.ambOut[ r.fromSymbol ];
        }
        // A4-R5 provenance (visible today, no serialize change): a cross-language binding edge is resolved via a
        // name-pattern binding table, not direct name resolution — so it carries the existing amb= "verify in
        // source" honesty mark (and feeds the header `ambiguous=N`). Conservative: an FFI edge is NEVER a silent
        // confident edge. The precise prov="binding" label rides outProv=2 below (pending the serialize one-liner).
        if( bindingPinned ) ++g.ambOut[ r.fromSymbol ];

        // aider-style per-ref confidence: tier × deboosts. overcommon = name defined in ≥16 places
        // (definition fan-out proxy for "appears everywhere"); private = leading-underscore convention.
        float conf = tierConf;
        if( !scipPinned && !bindingPinned )   // a SCIP-pinned / FFI-binding edge keeps its own confidence (no name-quality deboost).
        {
            if( it != byName.end() && it->second.size() >= 16 )       conf *= 0.1f;   // overcommon
            if( !r.calleeName.empty() && r.calleeName.front() == '_' ) conf *= 0.1f;   // private name
        }

        // drop self-loops BEFORE the split so the confidence mass is conserved over real targets
        std::size_t nReal = 0;
        for( NodeId c : tier ) if( c != r.fromSymbol ) ++nReal;
        if( nReal == 0 ) continue;
        const float base = conf / float( nReal );              // split over real (non-self) targets
        for( NodeId to : tier )
        {
            if( to == r.fromSymbol ) continue;
            const std::uint64_t ekey = ( std::uint64_t( r.fromSymbol ) << 32 ) | to;
            EdgeAcc& e = acc[ ekey ];
            e.confSum += base;
            e.nref    += 1;
            if( bindingPinned ) bindingEdges[ ekey ] = 1;      // A4-R5: remember (from,to) for prov="binding"
        }
    }

    // flatten + cap + sort by (from, to) — deterministic regardless of map order
    struct E { NodeId from, to; float w; };
    std::vector<E> edges;
    edges.reserve( acc.size() );
    for( const auto& [ k, e ] : acc )
    {
        float w = ( e.confSum / float( e.nref ) ) * std::sqrt( float( e.nref ) );   // confidence·√num_refs
        if( w > 8.f ) w = 8.f;
        edges.push_back( { NodeId( k >> 32 ), NodeId( k & 0xffffffffu ), w } );
    }
    std::vector<E> edgeScratch;
    sortutil::radixSortByFromTo( edges, edgeScratch );

    // out-edges (by source) + weighted out-degree
    g.outOff.assign( N + 1, 0 );
    for( const E& e : edges ) ++g.outOff[ e.from + 1 ];
    for( std::size_t i = 0; i < N; ++i ) g.outOff[ i + 1 ] += g.outOff[ i ];
    g.outTargets.resize( edges.size() );
    g.outVals.resize( edges.size() );
    // W4-#15 provenance: allocate outProv ONLY when an overlay was supplied OR an A4-R5 binding edge exists —
    // the common run keeps it EMPTY so serialize emits no prov= (zero token cost, byte-identical to before).
    //   1 = PRECISE (SCIP-pinned) → prov="scip";  2 = A4-R5 cross-language FFI binding → prov="binding".
    if( scip || !bindingEdges.empty() ) g.outProv.assign( edges.size(), 0u );
    {
        std::vector<std::uint32_t> cur( g.outOff.begin(), g.outOff.begin() + N );
        for( const E& e : edges )
        {
            const std::uint32_t pos = cur[ e.from ]++;
            g.outTargets[ pos ] = e.to;
            g.outVals[ pos ]    = e.w;
            g.wOutDeg[ e.from ] += e.w;
            if( scip && scip->isPrecise( e.from, e.to ) ) g.outProv[ pos ] = 1u;   // (from,to) pinned by SCIP
            else if( !bindingEdges.empty()
                     && bindingEdges.find( ( std::uint64_t( e.from ) << 32 ) | e.to ) != bindingEdges.end() )
                g.outProv[ pos ] = 2u;                                             // (from,to) an FFI binding edge
        }
    }

    // in-edge CSR (row = target) for PageRank
    std::vector<std::uint32_t> inDeg( N, 0 );
    for( const E& e : edges ) ++inDeg[ e.to ];
    g.inEdges = sparseCsr<float>( N, N, edges.size() );
    {
        auto* ro = g.inEdges.rowOffsets();  auto* ci = g.inEdges.colIndices();  auto* val = g.inEdges.values();
        ro[0] = 0;
        for( std::size_t i = 0; i < N; ++i ) ro[ i + 1 ] = ro[ i ] + inDeg[ i ];
        std::vector<std::uint32_t> cur( ro, ro + N );
        for( const E& e : edges ) { const std::uint32_t pos = cur[ e.to ]++; ci[ pos ] = e.from; val[ pos ] = e.w; }
    }
    VERIFY( verifyCsr( g.inEdges, N ) );

    // inheritance edges (Lego view): isInherit refs (derived → base name) → implementors[base] += derived.
    // Resolve the base name to class-like symbols (any-file, by name); dedup. The socket→bricks relation.
    g.implementors.assign( N, {} );
    const auto isClassLike = []( SymKind k ) noexcept
    { return k == SymKind::Class || k == SymKind::Struct || k == SymKind::Interface; };
    for( const Reference& r : ing.references )
    {
        if( !r.isInherit ) continue;

        // The DERIVED symbol. Normal case (C++/TS/Java/Python/Swift): the ref sits inside the derived class
        // header, so byte-span attribution already set fromSymbol = the derived class — use it directly.
        // Rust case: `impl Trait for T` is a top-level sibling of `struct T`; the ref sits in the impl HEADER
        // (which is inside the impl body, NOT the struct span), so fromSymbol points at whatever def encloses
        // the impl (a method, or kNoNode) — NOT T. So the Rust pass stashes the derived type NAME in
        // `qualifier` (empty for every other lang's inherit ref); when present we resolve THAT by name here:
        // class-like + lang-compatible, lowest id on a tie. This keeps the C++/TS/Java path byte-identical.
        NodeId derived = r.fromSymbol;
        if( !r.qualifier.empty() )                      // Rust impl_item → resolve the derived type by name
        {
            derived = kNoNode;
            const auto dit = byName.find( r.qualifier );
            if( dit == byName.end() ) continue;
            for( NodeId cand : dit->second )
                if( isClassLike( ing.symbols[ cand ].kind ) && langCompatible( ing.symbols[ cand ].lang, r.lang )
                    && sameRoot( cand, r.fileId ) )
                { derived = cand; break; }              // ids are ascending → lowest-id match (deterministic)
        }
        if( derived == kNoNode ) continue;

        const auto it = byName.find( r.calleeName );
        if( it == byName.end() ) continue;
        for( NodeId baseId : it->second )
        {
            if( !isClassLike( ing.symbols[ baseId ].kind ) ) continue;
            if( !sameRoot( baseId, r.fileId ) ) continue;   // §3: an extends NAME never crosses roots
            // Lang guard (same as every call resolver above): a name resolves ACROSS files but only
            // WITHIN a compatible language (or the ObjC↔C++ bridge). Without it a mixed-lang tree merges
            // e.g. a TS `Animal` + a Java `Animal` into ONE interface with cross-language duplicate impls.
            if( !langCompatible( ing.symbols[ baseId ].lang, r.lang ) ) continue;
            if( baseId == derived ) continue;
            g.implementors[ baseId ].push_back( derived );
        }
    }
    for( std::vector<NodeId>& v : g.implementors )
    {
        std::sort( v.begin(), v.end() );
        v.erase( std::unique( v.begin(), v.end() ), v.end() );
    }

    // doc↔code edges: isDocLink refs (markdown `backtick` → code name) → mentions[codeDef] += docFileNode.
    // Resolve the name to real DEFINITIONS (body present), any file; stored OUT of the call graph so a doc
    // mentioning a symbol never inflates its PageRank / blast radius. "what docs discuss this symbol".
    g.mentions.assign( N, {} );
    for( const Reference& r : ing.references )
    {
        if( !r.isDocLink || r.fromSymbol == kNoNode ) continue;
        const auto it = byName.find( r.calleeName );
        if( it == byName.end() ) continue;
        for( NodeId def : it->second )
        {
            if( ing.symbols[ def ].endByte <= ing.symbols[ def ].sigEndByte ) continue;   // a real def, not a decl
            if( def == r.fromSymbol ) continue;
            if( !sameRoot( def, r.fileId ) ) continue;      // §3: a doc backtick-name never crosses roots
            g.mentions[ def ].push_back( r.fromSymbol );
        }
    }
    for( std::vector<NodeId>& v : g.mentions )
    {
        std::sort( v.begin(), v.end() );
        v.erase( std::unique( v.begin(), v.end() ), v.end() );
    }

    // S5-E HAS-A composition edges: isCompose refs (owner class → member type name) → composeEdges.
    // Resolve the type name to class/struct symbols (any-file, by name); store OUTSIDE the call graph so
    // PageRank, ranks, and the default map are UNCHANGED. Sorted (ownerSym, typeSym) for determinism.
    for( const Reference& r : ing.references )
    {
        if( !r.isCompose || r.fromSymbol == kNoNode ) continue;
        const auto it = byName.find( r.calleeName );
        if( it == byName.end() ) continue;
        for( NodeId typeId : it->second )
        {
            const SymKind k = ing.symbols[ typeId ].kind;
            if( k != SymKind::Class && k != SymKind::Struct ) continue;
            if( typeId == r.fromSymbol ) continue;
            if( !sameRoot( typeId, r.fileId ) ) continue;   // §3: a HAS-A type NAME never crosses roots
            ComposeEdge ce;
            ce.ownerSym  = r.fromSymbol;
            ce.typeSym   = typeId;
            ce.fieldName = r.fieldName;
            ce.typeName  = r.calleeName;
            ce.ownerName = ing.symbols[ r.fromSymbol ].name;
            ce.rel       = r.composeRel;
            g.composeEdges.push_back( std::move( ce ) );
        }
    }
    // sort by (ownerSym, typeSym, fieldName) for determinism; dedup on (ownerSym, fieldName) — the
    // type name is the primary identity (one field has exactly one declared type).
    std::sort( g.composeEdges.begin(), g.composeEdges.end(),
               []( const ComposeEdge& a, const ComposeEdge& b ) noexcept
               {
                   if( a.ownerSym != b.ownerSym ) return a.ownerSym < b.ownerSym;
                   if( a.typeSym  != b.typeSym  ) return a.typeSym  < b.typeSym;
                   return a.fieldName < b.fieldName;
               } );
    {
        const auto samePair = []( const ComposeEdge& a, const ComposeEdge& b ) noexcept
        { return a.ownerSym == b.ownerSym && a.fieldName == b.fieldName; };
        g.composeEdges.erase( std::unique( g.composeEdges.begin(), g.composeEdges.end(), samePair ), g.composeEdges.end() );
    }

    // B6.3 HTTP-route USE→DEF edges: match ing.routeUses against ing.routeDefs by (method, path) — see
    // routematch:: above for the CONSERVATIVE segment-count + literal/template matching rule. A DEF's
    // handler is resolved by NAME, restricted to the DEF's OWN FILE (a route decorator/registration always
    // sits beside its handler in every framework this feature detects — no cross-file guess). Cross-ROOT
    // matching between a USE and a DEF is INTENTIONAL — the (method,path) match itself IS the explicit
    // evidence DESIGN_multiRoot.md §3 requires, so this never applies the sameRoot() guard the call/HAS-A/
    // extends resolvers above use. Ambiguous USEs (matching ≥2 DISTINCT resolved handlers) and unresolved
    // USEs (matching zero) synthesize NO edge — never a guess (mirrors the amb=/unresolved= honesty posture).
    {
        const auto isFunctionLike = []( SymKind k ) noexcept { return k == SymKind::Function || k == SymKind::Method; };

        std::vector<NodeId> defHandler( ing.routeDefs.size(), kNoNode );   // per-DEF resolved handler symbol
        for( std::size_t d = 0; d < ing.routeDefs.size(); ++d )
        {
            const RouteDef& rd = ing.routeDefs[d];
            if( rd.handlerName.empty() ) continue;                         // inline/anonymous handler → stays unresolved
            const auto it = byName.find( rd.handlerName );
            if( it == byName.end() ) continue;
            for( NodeId cand : it->second )
                if( isFunctionLike( ing.symbols[ cand ].kind ) && ing.symbols[ cand ].fileId == rd.fileId )
                { defHandler[d] = cand; break; }                           // ids ascending → lowest-id match (deterministic)
        }

        std::vector<NodeId> distinctScratch;   // reused per USE — the "≥2 distinct handlers ⇒ ambiguous" set
        for( const RouteUse& ru : ing.routeUses )
        {
            distinctScratch.clear();
            NodeId      matchedHandler = kNoNode;
            HttpMethod  matchedMethod  = HttpMethod::Unknown;
            std::string matchedPath;
            for( std::size_t d = 0; d < ing.routeDefs.size(); ++d )
            {
                const RouteDef& rd = ing.routeDefs[d];
                if( defHandler[d] == kNoNode ) continue;                   // an unresolved match adds no distinctness
                if( !routematch::methodsCompatible( rd.method, ru.method ) ) continue;
                if( !routematch::pathsMatch( rd.path, ru.path ) ) continue;
                if( std::find( distinctScratch.begin(), distinctScratch.end(), defHandler[d] ) != distinctScratch.end() )
                    continue;                                              // same handler already counted (dup registration)
                distinctScratch.push_back( defHandler[d] );
                matchedHandler = defHandler[d];
                matchedMethod  = rd.method;
                matchedPath    = rd.path;
            }
            if( distinctScratch.size() != 1 ) continue;                    // 0 ⇒ unresolved, ≥2 ⇒ ambiguous — never guess
            RouteEdge re;
            re.fromSym  = ru.fromSymbol;
            re.toSym    = matchedHandler;
            re.method   = matchedMethod != HttpMethod::Unknown ? matchedMethod : ru.method;
            re.path     = std::move( matchedPath );
            re.fromName = ru.fromSymbol != kNoNode ? ing.symbols[ ru.fromSymbol ].name : std::string();
            re.toName   = ing.symbols[ matchedHandler ].name;
            g.routeEdges.push_back( std::move( re ) );
        }
        std::sort( g.routeEdges.begin(), g.routeEdges.end(),
                   []( const RouteEdge& a, const RouteEdge& b ) noexcept
                   {
                       if( a.fromSym != b.fromSym ) return a.fromSym < b.fromSym;
                       if( a.toSym   != b.toSym   ) return a.toSym   < b.toSym;
                       return a.path < b.path;
                   } );
        const auto sameRouteEdge = []( const RouteEdge& a, const RouteEdge& b ) noexcept
        { return a.fromSym == b.fromSym && a.toSym == b.toSym && a.path == b.path; };
        g.routeEdges.erase( std::unique( g.routeEdges.begin(), g.routeEdges.end(), sameRouteEdge ), g.routeEdges.end() );
    }

    // W4-#1: per-symbol name-quality prior weight (aider-style). REUSES the resolver's byName def-count
    // (byName[name].size() = # of same-name definitions across the repo — the "common name" signal) rather
    // than rebuilding it. Pure function of the name + that count ⇒ deterministic. Applied to the teleport
    // prior (never the edges) and renormalized in rankGraphTeleport. Every symbol whose name is missing from
    // byName (shouldn't happen — every symbol was inserted) safely defaults to defCount 0 ⇒ multiplier 1.
    g.priorWeight.resize( N, 1.f );
    for( const Symbol& s : ing.symbols )
    {
        const auto it = byName.find( s.name );
        const std::size_t defCount = ( it != byName.end() ) ? it->second.size() : 0;
        g.priorWeight[ s.id ] = priorwt::weight( s.name, defCount );
    }

    return g;
}

// W4-#1: bias a teleport/personalization prior by the per-symbol name-quality weights, then renormalize to
// Σ=1 (PageRank REQUIRES Σp=1 — it seeds r=p and the dangling/teleport term is (α·D+(1−α))·p[i]). This is
// the ONE place the aider-style weights meet a rank mode's prior, so EVERY teleport-based rank (the default
// uniform prior, churn, --map-diff, the eval seed) becomes a weighted prior with no per-call-site change.
// Pure & deterministic (weights are a pure function of names/def-counts). If the weighting collapses the
// prior to all-zero (pathological), fall back to the caller's prior UNCHANGED rather than emit a zero
// vector (which PageRank would spread as pure dangling mass). Empty priorWeight ⇒ no-op passthrough.
inline std::vector<float> biasPrior( const Graph& g, const std::vector<float>& p )
{
    const std::size_t N = p.size();
    if( g.priorWeight.size() != N ) return p;                 // no weights (e.g. empty graph) → unchanged
    std::vector<float> pw( N );
    double sum = 0.0;
    for( std::size_t i = 0; i < N; ++i ) { pw[i] = p[i] * g.priorWeight[i]; sum += pw[i]; }
    if( !( sum > 0.0 ) ) return p;                            // degenerate (all zero) → caller's prior intact
    const float inv = float( 1.0 / sum );
    for( float& v : pw ) v *= inv;                            // renormalize to Σ=1 (the PageRank invariant)
    return pw;
}

// PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased
// (W4-#1) here so all rank modes share one weighting seam; the transition matrix (edges) is untouched.
inline std::vector<float> rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    if( N )
    {
        double teleportMass = 0.0;
        for( const double value : teleport )
            teleportMass += value;
        if( teleportMass > 0.0 )
        {
            const double inverseMass = 1.0 / teleportMass;
            for( double& value : teleport )
                value *= inverseMass;
        }
        pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );
    }
    std::vector<float> r( N, 0.f );
    std::transform( rankDouble.begin(), rankDouble.end(), r.begin(), []( double value ) { return float( value ); } );
    return r;
}

// uniform-teleport PageRank (the default).
inline std::vector<float> rankGraph( const Graph& g, float alpha = 0.85f )
{
    const std::size_t N = g.wOutDeg.size();
    return rankGraphTeleport( g, std::vector<float>( N, N ? 1.0f / float( N ) : 0.f ), alpha );
}

// out-edge SpMV: h[j] = Σ_{j→i} w·a[i] (the HITS hub step; out-degree is capped, scalar is fine).
inline void applyOutInto( const Graph& g, const float* a, float* h ) noexcept
{
    const std::size_t N = g.wOutDeg.size();
    for( std::size_t j = 0; j < N; ++j )
    {
        float acc = 0.f;
        for( std::uint32_t k = g.outOff[j]; k < g.outOff[j + 1]; ++k )
            acc += g.outVals[k] * a[ g.outTargets[k] ];
        h[j] = acc;
    }
}

// HITS hubs & authorities (Kleinberg coupled iteration, L2-normalized, deterministic). Returns
// {authority, hub}: authority[i] high = called by many good hubs (core APIs/utilities);
// hub[j] high = calls many good authorities (entrypoints / orchestrators / harnesses). Seeded
// 1/√N (never random) → bit-stable. Runs ALONGSIDE PageRank — does not replace it.
inline std::pair<std::vector<float>, std::vector<float>> hits( const Graph& g, float tol = 1e-6f, unsigned maxIter = 100 )
{
    const std::size_t N = g.wOutDeg.size();
    std::vector<float> a( N, 0.f ), h( N, 0.f );
    if( N == 0 )
        return { a, h };

    const float seed = 1.0f / std::sqrt( float( N ) );
    std::fill( a.begin(), a.end(), seed );
    std::fill( h.begin(), h.end(), seed );
    std::vector<float> aPrev( N ), hPrev( N );

    for( unsigned it = 0; it < maxIter; ++it )
    {
        aPrev = a;  hPrev = h;

        g.inEdges.applyInto( h.data(), a.data() );                         // a[i] = Σ_{j→i} w·h[j]
        const float an = std::sqrt( csrdetail::blockReduceDot( a.data(), a.data(), N ) );
        if( an > 0.f ) for( float& v : a ) v /= an;

        applyOutInto( g, a.data(), h.data() );                             // h[j] = Σ_{j→i} w·a[i]
        const float hn = std::sqrt( csrdetail::blockReduceDot( h.data(), h.data(), N ) );
        if( hn > 0.f ) for( float& v : h ) v /= hn;

        float resid = 0.f;
        for( std::size_t i = 0; i < N; ++i ) resid += std::fabs( a[i] - aPrev[i] ) + std::fabs( h[i] - hPrev[i] );
        if( resid < tol ) break;
    }
    return { a, h };
}

// ---- query-scoped ego-graph (--around=SYMBOL): bounded k-hop neighbourhood -----------------
struct EgoGraph
{
    NodeId                    focus = kNoNode;
    std::vector<NodeId>       nodes;       // focus first, then by (hopDist, NodeId)
    std::vector<std::uint8_t> hopDist;     // parallel to nodes
    std::vector<std::int8_t>  direction;   // -1 caller-side, +1 callee-side, 0 focus
};

// §P8 seam 2: a pasted `p="path:line"` locator → the bare path. --hotspots/--clones/--grep/--lint/
// --quality-delta all emit `path:line` as their PRIMARY locator, so that is the spelling an agent has in
// hand when it wants to feed a row to a path-taking verb; before this, --affected/--situ/--test-gate and
// the file half of every "file:name" selector all rejected it. Strips exactly ONE trailing ":N" or ":N-M"
// (digits only, a lone interior '-'), and only when a non-empty path remains before it. Anything else —
// including a bare path, a Windows-style "C:" head, or a trailing ":abc" — is returned UNTOUCHED, so every
// existing caller is byte-identical.
inline std::string_view stripLineLocator( std::string_view path ) noexcept
{
    const std::size_t colon = path.rfind( ':' );
    if( colon == std::string_view::npos || colon == 0 ) return path;

    const std::string_view tail = path.substr( colon + 1 );
    bool                   sawDash = false;
    if( tail.empty() ) return path;
    for( std::size_t i = 0; i < tail.size(); ++i )
    {
        const char c = tail[i];
        if( c >= '0' && c <= '9' ) continue;
        if( c == '-' && i > 0 && !sawDash ) { sawDash = true;  continue; }
        return path;                                       // not a pure N / N-M locator — leave it alone
    }
    if( tail.back() == '-' ) return path;                  // "12-" is a truncated range, not a locator
    return path.substr( 0, colon );
}

// Does `haystack` (an ing.files entry) contain the user-typed path fragment `needle`? Plain substring,
// EXCEPT that a merged workspace path carries the `<label>/./<rel>` seam (workspace.h) — so the natural
// `<label>/<rel>` a reader would type must match too. The collapse only runs on a miss AND only when the
// haystack actually carries a "/./", so a single-root corpus never allocates and is byte-identical.
inline bool filePathContains( std::string_view haystack, std::string_view needle )
{
    if( haystack.find( needle ) != std::string_view::npos ) return true;
    if( haystack.find( "/./" ) == std::string_view::npos )  return false;

    std::string collapsed;
    collapsed.reserve( haystack.size() );
    for( std::size_t i = 0; i < haystack.size(); )
        if( haystack.substr( i, 3 ) == "/./" ) { collapsed.push_back( '/' );          i += 3; }
        else                                   { collapsed.push_back( haystack[i] );  ++i;    }
    return collapsed.find( needle ) != std::string::npos;
}

// shared "name" | "file:name" spec splitter (X9(b)) — the ONE disambiguation rule --around/--lego/
// --edit-check (via resolveFocus, single lowest-id pick) and --callers/--impact (via
// resolveAllByNameQualified, every match) now both route through, so a same-named-across-files symbol
// disambiguates identically everywhere instead of only some verbs supporting it. The LAST colon is the
// separator (a file path itself never contains the trailing "name" after it), so a bare name with no
// colon at all is untouched: file stays empty, name == spec.
//
// §P8 seam 2 (additive): the FILE half also accepts the `path:line` locator, so the row an agent actually
// holds — `p="./src/graph.h:1148"` from --callers/--hotspots — composes straight into `file:line:name`.
// Purely additive: a file half ending in ":<digits>" matched nothing before (no crawled path contains one).
inline void splitQualifiedSpec( std::string_view spec, std::string_view& file, std::string_view& name )
{
    file = {};
    name = spec;
    const std::size_t colon = spec.rfind( ':' );
    if( colon != std::string_view::npos ) { file = stripLineLocator( spec.substr( 0, colon ) );  name = spec.substr( colon + 1 ); }
}

// resolve a --around spec ("name" or "file:name") to the lowest-id matching symbol; kNoNode if none.
inline NodeId resolveFocus( const IngestResult& ing, std::string_view spec )
{
    std::string_view file, name;
    splitQualifiedSpec( spec, file, name );

    NodeId best = kNoNode;
    for( const Symbol& s : ing.symbols )
        if( s.name == name && ( file.empty() || filePathContains( ing.files[ s.fileId ], file ) ) )
            if( best == kNoNode || s.id < best ) best = s.id;
    return best;
}

// k-hop neighbourhood of `focus`, BOTH directions (callees via out-edges, callers via in-edges),
// fan-out-capped per node by (weight desc, NodeId asc). dist=min on first visit. Deterministic.
inline EgoGraph egoGraph( const Graph& g, NodeId focus, int depth = 2, int fanout = 32 )
{
    EgoGraph eg;
    const std::size_t N = g.wOutDeg.size();
    if( focus >= N ) return eg;
    eg.focus = focus;

    std::vector<int> dist( N, -1 );
    dist[ focus ] = 0;
    eg.nodes.push_back( focus );  eg.hopDist.push_back( 0 );  eg.direction.push_back( 0 );

    const auto* inRo = g.inEdges.rowOffsets();
    const auto* inCi = g.inEdges.colIndices();
    const auto* inV  = g.inEdges.values();

    struct Nb { NodeId v; float w; std::int8_t d; };
    std::vector<NodeId> frontier = { focus };
    for( int hop = 1; hop <= depth && !frontier.empty(); ++hop )
    {
        std::vector<NodeId> next;
        for( NodeId u : frontier )
        {
            std::vector<Nb> nbs;
            for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k ) nbs.push_back( { g.outTargets[k], g.outVals[k], +1 } );
            for( std::uint32_t k = inRo[u];     k < inRo[u + 1];     ++k ) nbs.push_back( { inCi[k],        inV[k],     -1 } );

            if( int( nbs.size() ) > fanout )                  // cap hub blast-radius: top `fanout` by (w desc, id asc)
            {
                std::partial_sort( nbs.begin(), nbs.begin() + fanout, nbs.end(),
                                   []( const Nb& a, const Nb& b ) { return a.w != b.w ? a.w > b.w : a.v < b.v; } );
                nbs.resize( fanout );
            }
            std::sort( nbs.begin(), nbs.end(), []( const Nb& a, const Nb& b ) { return a.v < b.v; } );   // stable visit order

            for( const Nb& nb : nbs )
                if( dist[ nb.v ] < 0 )
                {
                    dist[ nb.v ] = hop;
                    eg.nodes.push_back( nb.v );  eg.hopDist.push_back( std::uint8_t( hop ) );  eg.direction.push_back( nb.d );
                    next.push_back( nb.v );
                }
        }
        frontier = std::move( next );
    }
    return eg;
}

// Reciprocal Rank Fusion: fuse several score vectors into one. fused[i] = Σ_r 1/(k + rank_r(i)),
// rank_r(i) = i's 0-based position in ranking r (desc, id-tiebroken). Deterministic. (--rank-by=rrf)
inline std::vector<float> rrfFuse( std::initializer_list<const std::vector<float>*> rankings, float k = 60.f )
{
    std::size_t N = 0;
    for( const std::vector<float>* rv : rankings ) { N = rv->size(); break; }
    std::vector<float>         fused( N, 0.f );
    std::vector<std::uint32_t> order( N );
    for( const std::vector<float>* rv : rankings )
    {
        const std::vector<float>& r = *rv;
        for( std::uint32_t i = 0; i < N; ++i ) order[i] = i;
        sortutil::radixSortByScoreDescId( order, r );
        for( std::uint32_t pos = 0; pos < N; ++pos ) fused[ order[pos] ] += 1.0f / ( k + float( pos ) );
    }
    return fused;
}

// ---- LARGER-style lexically-anchored PPR (--for=TASK --anchor; AUDIT3 §D steal #1) --------------------
// The published --eval finding stands: IMPORTANCE-flavoured fusion hurts relatedness (RRF of global
// PageRank into lexical collapsed recall@5 from 40% to 7.7%). This is a DIFFERENT fusion: the PPR
// personalization vector is seeded FROM the lexical anchor hits (relatedness-seeded, not importance-
// seeded — SPEC §3: bias enters through `p`), so the random walk expands the LEXICAL neighbourhood to
// structurally-adjacent symbols the query's words never touch (a caller's helper, an interface's impl).
// And the blend is SCORE-space, not RANK-space: RRF hands PPR's near-zero tail a large reciprocal-rank
// weight (how the failed fusion drowned lexical); max-normalized score blending lets the graph term
// matter only where actual walk mass lands. Deterministic end-to-end (exact float compares with id
// tie-breaks; the PPR core already satisfies the det-gate; the blend is a single-threaded index-order pass).
namespace anchorcfg
{
    // top-N lexical hits seed the walk. 20 = half the default --for bundle (40): wide enough that one
    // false lexical hit holds only its proportional share of teleport mass, narrow enough that the walk
    // stays concentrated on the task neighbourhood (LARGER anchors are "a handful"; 20 symbols ≈ 5-8 files).
    inline constexpr std::size_t kAnchorCount = 20;
    // λ: final = (1−λ)·lex̂ + λ·pprˆ (both max-normalized). Lexical stays dominant — the eval says lexical
    // is the workhorse signal — while a zero-lexical, structurally-adjacent symbol can earn up to λ,
    // enough to outrank the lexical tail but never a strong direct hit.
    inline constexpr float kGraphBlend = 0.30f;
}

// blend two score vectors in SCORE space after max-normalizing each to [0,1]:
// out[i] = (1−λ)·a[i]/max(a) + λ·b[i]/max(b). Degrades to `a` when either vector is degenerate
// (empty / non-positive max) — never a zero vector. Single-threaded, index order ⇒ deterministic.
inline std::vector<float> blendMaxNorm( const std::vector<float>& a, const std::vector<float>& b, float lambda )
{
    if( a.size() != b.size() || a.empty() ) return a;
    float amax = 0.f, bmax = 0.f;
    for( float v : a ) if( v > amax ) amax = v;
    for( float v : b ) if( v > bmax ) bmax = v;
    if( !( amax > 0.f ) || !( bmax > 0.f ) ) return a;
    std::vector<float> out( a.size() );
    const float ia = ( 1.0f - lambda ) / amax, ib = lambda / bmax;
    for( std::size_t i = 0; i < a.size(); ++i ) out[i] = a[i] * ia + b[i] * ib;
    return out;
}

// anchored rank: pick the top-kAnchorCount symbols by lexical score (score desc, id asc — deterministic),
// seed the PPR personalization with each anchor's NORMALIZED lexical score (per-anchor confidence
// weighting: a marginal 20th anchor teleports proportionally little mass, so the anchor-count is not a
// cliff), run the EXISTING PPR machinery (rankGraphTeleport — the same biasPrior/det-gate seam every
// teleport mode uses), and blend lexical + anchored-PPR in score space (blendMaxNorm, λ above).
// No lexical signal at all (empty query / no match) ⇒ returns `lex` unchanged (anchoring degrades to
// plain lexical, never to noise).
inline std::vector<float> anchoredLexicalRank( const Graph& g, const std::vector<float>& lex )
{
    const std::size_t N = lex.size();
    if( N == 0 || g.wOutDeg.size() != N ) return lex;

    // top-K anchor candidates by (lex desc, id asc); positive scores only
    std::vector<NodeId> anchorIds( N );
    for( NodeId i = 0; i < N; ++i ) anchorIds[i] = NodeId( i );
    const std::size_t anchorCount = std::min( anchorcfg::kAnchorCount, N );
    std::partial_sort( anchorIds.begin(), anchorIds.begin() + anchorCount, anchorIds.end(),
                       [ & ]( NodeId a, NodeId b ) { return lex[a] != lex[b] ? lex[a] > lex[b] : a < b; } );
    anchorIds.resize( anchorCount );
    while( !anchorIds.empty() && !( lex[ anchorIds.back() ] > 0.f ) ) anchorIds.pop_back();
    if( anchorIds.empty() ) return lex;                       // no lexical signal → anchoring is a no-op

    // personalization ∝ per-anchor lexical confidence, Σp = 1 (the PageRank invariant)
    double confSum = 0.0;
    for( NodeId a : anchorIds ) confSum += lex[a];
    std::vector<float> p( N, 0.f );
    for( NodeId a : anchorIds ) p[a] = float( lex[a] / confSum );

    // bounded graph expansion from the anchors (existing PPR core), then the score-space blend
    const std::vector<float> ppr = rankGraphTeleport( g, p );
    return blendMaxNorm( lex, ppr, anchorcfg::kGraphBlend );
}

// all symbols whose final-segment name matches `name` (overloads + same-name across files), in id
// order — for --expand ("give me every def called X"), so nothing is silently missed.
// P2.4: per-symbol fan-in (= reuse count) straight off the already-built in-edge CSR — the same free graph
// query main.cpp runs for --metrics/--for, lives here so ANY bundle assembler can supply its own instead of
// emitting a fabricated in="0" when the call-site did not hand one in. Pure, O(symbols), no allocation beyond
// the result. rowOffsets() has symbolCount+1 entries, so [i+1] is always in range.
inline std::vector<std::uint32_t> fanInFromInEdges( const IngestResult& ing, const Graph& g )
{
    const std::size_t          symbolCount = ing.symbols.size();
    std::vector<std::uint32_t> fanIn( symbolCount, 0u );
    const auto*                ro = g.inEdges.rowOffsets();
    if( !ro ) { DEGRADED_PATH_ALERT( "bundle: in-edge CSR unavailable — in= omitted from the bundle rows" );  return {}; }
    for( std::size_t i = 0; i < symbolCount; ++i ) fanIn[i] = ro[i + 1] - ro[i];
    return fanIn;
}

// A canonical id (path::scope::name) resolves by RECOMPUTING each symbol's id with the very canonicalId()
// that emitted it, so producer and consumer cannot drift: whatever --for/--pack-task/the default map printed
// in id= is exactly what this accepts. Overloads share one canonical id by construction, so this returns
// EVERY match — the caller decides (--expand shows all, --around picks one), same as the bare-name path.
inline std::vector<NodeId> resolveAllByCanonicalId( const IngestResult& ing, std::string_view spec )
{
    std::vector<NodeId> out;
    for( const Symbol& s : ing.symbols )
        if( canonicalId( ing.files[ s.fileId ], s.scope, s.name ) == spec ) out.push_back( s.id );
    return out;
}

// Bare name, or a canonical id. The "::" probe runs FIRST and only when the spec carries one, then falls
// back to the name match — no indexed symbol NAME contains "::" in any grammar we parse, so this is purely
// additive: every previously-working query resolves byte-identically.
inline std::vector<NodeId> resolveAllByName( const IngestResult& ing, std::string_view name )
{
    if( name.find( "::" ) != std::string_view::npos )
    {
        std::vector<NodeId> byId = resolveAllByCanonicalId( ing, name );
        if( !byId.empty() ) return byId;
    }

    std::vector<NodeId> out;
    for( const Symbol& s : ing.symbols )
        if( s.name == name ) out.push_back( s.id );
    return out;
}

// X9(b): qualified "file:name" variant of resolveAllByName, for --callers/--callees/--impact — a same-
// named symbol living in more than one file (a common overload/shadow shape) previously had no way to
// disambiguate on these verbs even though --around/--lego/--edit-check already could (resolveFocus). Uses
// the SAME splitQualifiedSpec rule as resolveFocus, but returns EVERY match (not just the lowest-id pick)
// — --callers/--impact want the union across all matches (overloads share callers/impact by design),
// unlike --around's single-target ego-graph. A bare "name" (no colon) is BYTE-IDENTICAL to the existing
// resolveAllByName( ing, name ) — every symbol with that name, across every file — so this is purely
// additive: no existing unqualified query changes behavior.
inline std::vector<NodeId> resolveAllByNameQualified( const IngestResult& ing, std::string_view spec )
{
    // A canonical id first (see resolveAllByName): "path::scope::name" would otherwise be cut at its first
    // ':' by splitQualifiedSpec and refused, which made the id= these very verbs emit unusable as their own
    // input. Falls through to the file:name rule when the spec is not an id, so nothing existing changes.
    if( spec.find( "::" ) != std::string_view::npos )
    {
        std::vector<NodeId> byId = resolveAllByCanonicalId( ing, spec );
        if( !byId.empty() ) return byId;
    }

    std::string_view file, name;
    splitQualifiedSpec( spec, file, name );

    std::vector<NodeId> out;
    for( const Symbol& s : ing.symbols )
        if( s.name == name && ( file.empty() || filePathContains( ing.files[ s.fileId ], file ) ) )
            out.push_back( s.id );
    return out;
}

// clearly side-effecting C/C++ intrinsics (I/O, allocation, nondeterminism, process control). A
// function referencing one of these is impure at the source. Conservative-but-focused (clear cases
// only) so we DEMOTE, not over-demote — the goal is to strip false "pure" flags off const methods.
// A4-P8(2): O(1) avg hash-set lookup (was ~38 linear strcmps/Call-ref) — HashMap<> pattern (SPEC
// container rule), keyed by string_view so the std::string caller pays no extra allocation (implicit
// std::string→string_view conversion).
inline bool isImpureName( const std::string& n ) noexcept
{
    static const ankerl::unordered_dense::set<std::string_view> kImpure = {
        "printf", "fprintf", "sprintf", "snprintf", "vprintf", "vfprintf", "puts", "fputs", "putchar", "perror",
        "scanf", "fscanf", "sscanf", "gets", "fgets", "getchar", "fopen", "fclose", "fread", "fwrite", "fflush",
        "open", "close", "read", "write", "malloc", "calloc", "realloc", "free", "rand", "srand", "random",
        "time", "clock", "gettimeofday", "exit", "abort", "system", "getenv", "setenv" };
    return kImpure.contains( n );
}

// purity fixpoint: a symbol is impure if it references a side-effecting intrinsic OR (transitively)
// calls an impure symbol. Least fixpoint over the out-edge call graph, computed as the EXACT same
// least fixpoint but via worklist propagation over the in-edge CSR (A4-P8(1)) instead of rescanning
// all S symbols per round: g.inEdges row i lists i's in-neighbours (callers, buildGraph:528-538 —
// ci[pos]=e.from for edge e.from→e.to=i). The moment a symbol is marked impure, only ITS callers can
// newly become impure, so push them and stop when the worklist drains — same result (every symbol
// reachable backward from an impure seed ends up impure), touching only the edges that matter instead
// of an O(S) sweep per round.
inline std::vector<char> computeImpure( const IngestResult& ing, const Graph& g )
{
    PROFILE_SCOPE_DESCRIBE( "computeImpure: purity fixpoint (worklist over in-edge CSR)" );
    const std::size_t S = ing.symbols.size();
    std::vector<char> impure( S, 0 );
    std::vector<NodeId> worklist;                                       // seed: direct side-effecting calls
    for( const Reference& r : ing.references )
        if( r.role == RefRole::Call && r.fromSymbol != kNoNode && r.fromSymbol < S && isImpureName( r.calleeName ) )   // ABS-3: only CALL sites seed impurity (not a var read named "free")
            if( !impure[ r.fromSymbol ] ) { impure[ r.fromSymbol ] = 1; worklist.push_back( r.fromSymbol ); }

    const auto* inRo = g.inEdges.rowOffsets();
    const auto* inCi = g.inEdges.colIndices();
    const bool  haveCsr = g.inEdges.rows() == S;                        // degrade to a no-op propagate if shapes ever mismatch
    while( !worklist.empty() )                                         // propagate impurity callee → caller
    {
        const NodeId f = worklist.back();
        worklist.pop_back();
        if( !haveCsr ) continue;
        for( std::uint32_t e = inRo[f]; e < inRo[f + 1]; ++e )
        {
            const NodeId caller = inCi[e];
            if( caller < S && !impure[ caller ] ) { impure[ caller ] = 1; worklist.push_back( caller ); }
        }
    }
    return impure;
}

// ── Q-compute: evidence-validated per-symbol metrics, surfaced on --metrics ONLY (descriptive facts,
//    never gates — the steering thesis). All are DETERMINISTIC pure functions of the ingested tree + graph:
//    every input (out-edge CSR, composeEdges, references, files) is already in a fixed order, and the one
//    union-find (LCOM4) runs over id-SORTED methods, so run-to-run output is byte-stable.
//
//   cbo[i]    — Q5a per-symbol Coupling-Between-Objects: count of DISTINCT in-repo dependency targets =
//               distinct resolved callees (out-edge CSR is already deduped per source) + distinct composed
//               member TYPES (composeEdges, deduped by typeSym). The best-validated coupling form ctxpack
//               lacked (§1a: CBO is the #1 OO defect predictor, size-controlled). External/unresolved calls
//               are absent from the graph, so cbo counts only in-repo coupling — the honest, computable set.
//   tested[i] — Q2: 1 iff symbol i is referenced from ANY test-path file (filter.h isTestPath), across ALL
//               reference kinds (call/read/write/import/extends/compose/doc). The cheapest "a safety net
//               exists" signal; a deterministic post-pass over the reference set.
//   lcom4[i]  — Q4 class cohesion (LCOM4 = # connected components of the method graph, edge = two methods
//               CALL each other OR SHARE a field). Emitted ONLY for Class/Struct/Interface WITH ≥1 method
//               (kLcom4NA = "not applicable" for free functions / method-less types — we NEVER fabricate 1).
//               HONEST-SCOPE NOTE: the field set is the class's typed-class members from captureFields
//               (compose edges) — primitive fields (`double x`) are not in that set, so "shares field" is a
//               LOWER BOUND on cohesion edges → lcom4 may read HIGHER (less cohesive) than a full-field LCOM4.
//               method-calls-method uses the reliable call graph. C++-primary (captureFields is C++-only).
struct QMetrics
{
    std::vector<std::uint32_t> cbo;          // distinct in-repo dependency targets per symbol
    std::vector<std::uint8_t>  tested;       // 1 = referenced from a test-path file, else 0
    std::vector<std::uint32_t> lcom4;        // # connected components (class-kinds w/ methods); kLcom4NA otherwise
    std::vector<std::uint32_t> callerCount;  // |direct callers| (in-edge CSR) — the symbol-level half of change-amplification
};
inline constexpr std::uint32_t kLcom4NA = 0xFFFFFFFFu;   // LCOM4 not applicable (not a class-kind, or no methods)

// union-find (LCOM4 components). Deterministic: unions in a fixed order over id-sorted method slots.
struct UnionFind
{
    std::vector<std::uint32_t> parent;
    explicit UnionFind( std::size_t n ) : parent( n ) { for( std::uint32_t i = 0; i < n; ++i ) parent[i] = i; }
    std::uint32_t find( std::uint32_t x ) { while( parent[x] != x ) { parent[x] = parent[ parent[x] ]; x = parent[x]; } return x; }
    void unite( std::uint32_t a, std::uint32_t b ) { const std::uint32_t ra = find( a ), rb = find( b ); if( ra != rb ) parent[ ra < rb ? rb : ra ] = ( ra < rb ? ra : rb ); }
};

inline QMetrics computeQMetrics( const IngestResult& ing, const Graph& g )
{
    PROFILE_SCOPE_DESCRIBE( "computeQMetrics: cbo/tested/lcom4/callers" );
    const std::size_t S = ing.symbols.size();
    QMetrics q;
    q.cbo.assign( S, 0u );
    q.tested.assign( S, 0u );
    q.lcom4.assign( S, kLcom4NA );
    q.callerCount.assign( S, 0u );

    // ── caller count (amp half) + CBO callee half: both are direct reads of the CSRs (deduped by construction).
    const auto* inRo = g.inEdges.rowOffsets();
    for( std::size_t i = 0; i < S; ++i )
    {
        q.callerCount[i] = ( inRo ? inRo[i + 1] - inRo[i] : 0u );
        q.cbo[i]         = g.outOff[i + 1] - g.outOff[i];   // distinct resolved callees (CSR deduped per source)
    }
    // ── CBO composed-type half: distinct member TYPES per owner (composeEdges sorted by ownerSym, typeSym).
    for( std::size_t e = 0; e < g.composeEdges.size(); ++e )
    {
        const NodeId owner = g.composeEdges[e].ownerSym;
        const NodeId type  = g.composeEdges[e].typeSym;
        if( owner >= S ) continue;
        // count a composed type only if it isn't already a resolved callee target of the owner (avoid double
        // count) AND is distinct from the previous compose edge's type for this owner (edges are sorted).
        const bool dupOfPrev = ( e > 0 && g.composeEdges[e - 1].ownerSym == owner && g.composeEdges[e - 1].typeSym == type );
        if( dupOfPrev ) continue;
        bool isCallee = false;
        for( std::uint32_t k = g.outOff[owner]; k < g.outOff[owner + 1]; ++k )
            if( g.outTargets[k] == type ) { isCallee = true; break; }
        if( !isCallee ) ++q.cbo[ owner ];
    }

    // ── tested=: any reference (any role) FROM a test-path file marks the referenced symbol as tested. We
    //    resolve each ref's callee name to its definition(s) by name and, if the ref's file is a test path,
    //    flag those defs. Deterministic: references are in a fixed order; byName is insertion-order stable.
    std::vector<char> fileIsTest( ing.files.size(), 0 );
    for( std::size_t f = 0; f < ing.files.size(); ++f ) fileIsTest[f] = isTestPath( ing.files[f] ) ? 1 : 0;
    HashMap<std::string, std::vector<NodeId>> byNameDefs;
    byNameDefs.reserve( S );
    for( const Symbol& s : ing.symbols ) byNameDefs[ s.name ].push_back( s.id );
    for( const Reference& r : ing.references )
    {
        if( r.fileId >= fileIsTest.size() || !fileIsTest[ r.fileId ] ) continue;   // only refs living in a test file
        const auto it = byNameDefs.find( r.calleeName );
        if( it == byNameDefs.end() ) continue;
        for( NodeId def : it->second )
            if( !fileIsTest[ ing.symbols[def].fileId ] )   // a test referencing a PRODUCTION symbol = that symbol is tested
                q.tested[ def ] = 1u;
    }

    // ── LCOM4: per class-kind symbol, components of its method graph. Group methods by their enclosing class
    //    (method's scope == class name AND same file — scope is the class name, matched to a class symbol in
    //    the same file to avoid cross-file same-name collisions). Then union methods that call each other or
    //    share a declared (typed-class) field. #components after unions = LCOM4.
    // class symbol id → its method symbol ids (in ascending id order).
    HashMap<NodeId, std::vector<NodeId>> classMethods;
    // (fileId, className) → class symbol id, for method→class attribution.
    HashMap<std::string, NodeId>         classByFileScope;
    {
        std::string key;
        for( const Symbol& s : ing.symbols )
        {
            const bool isClassKind = ( s.kind == SymKind::Class || s.kind == SymKind::Struct || s.kind == SymKind::Interface );
            if( !isClassKind ) continue;
            key.clear(); key.append( ing.files[ s.fileId ] ); key.push_back( '\x1f' ); key.append( s.name );
            classByFileScope.emplace( key, s.id );   // first (lowest-id) class of that name/file wins
        }
        std::string mkey;
        for( const Symbol& s : ing.symbols )
        {
            if( s.kind != SymKind::Method || s.scope.empty() ) continue;
            mkey.clear(); mkey.append( ing.files[ s.fileId ] ); mkey.push_back( '\x1f' ); mkey.append( s.scope );
            const auto it = classByFileScope.find( mkey );
            if( it != classByFileScope.end() ) classMethods[ it->second ].push_back( s.id );
        }
    }
    if( !classMethods.empty() )
    {
        // declared (typed-class) field names per class, from compose edges (owner = the class symbol).
        HashMap<NodeId, std::vector<std::string>> classFields;
        for( const ComposeEdge& ce : g.composeEdges )
            classFields[ ce.ownerSym ].push_back( ce.fieldName );
        // per method: the set of field names it references (Read/Write/Call refs by name). Built once, filtered
        // to declared fields per class below.
        // methodRefs[methodId] = names referenced in that method (any role).
        HashMap<NodeId, std::vector<std::string>> methodRefNames;
        for( const Reference& r : ing.references )
            if( r.fromSymbol != kNoNode && r.fromSymbol < S && ing.symbols[ r.fromSymbol ].kind == SymKind::Method )
                methodRefNames[ r.fromSymbol ].push_back( r.calleeName );

        // deterministic iteration: sort the class ids before processing (HashMap order is unspecified).
        std::vector<NodeId> classIds;
        classIds.reserve( classMethods.size() );
        for( const auto& [ cid, methods ] : classMethods ) classIds.push_back( cid );
        std::sort( classIds.begin(), classIds.end() );

        for( NodeId cid : classIds )
        {
            std::vector<NodeId>& methods = classMethods[ cid ];
            std::sort( methods.begin(), methods.end() );                  // id-sorted → union-find is deterministic
            const std::size_t m = methods.size();
            if( m == 0 ) continue;
            // slot index of a method id within this class (for union-find over [0,m)).
            HashMap<NodeId, std::uint32_t> slot;
            for( std::uint32_t i = 0; i < m; ++i ) slot.emplace( methods[i], i );

            UnionFind uf( m );
            // (a) method-calls-method: an out-edge from one class method to another unites them.
            for( std::uint32_t i = 0; i < m; ++i )
            {
                const NodeId a = methods[i];
                for( std::uint32_t k = g.outOff[a]; k < g.outOff[a + 1]; ++k )
                {
                    const auto sit = slot.find( g.outTargets[k] );
                    if( sit != slot.end() ) uf.unite( i, sit->second );
                }
            }
            // (b) method-shares-field: two methods that both reference the SAME declared (typed-class) field.
            const auto fit = classFields.find( cid );
            if( fit != classFields.end() && !fit->second.empty() )
            {
                for( const std::string& fld : fit->second )
                {
                    // methods (in this class) that reference this field name — unite them all pairwise (chain).
                    std::uint32_t firstSlot = 0xFFFFFFFFu;
                    for( std::uint32_t i = 0; i < m; ++i )
                    {
                        const auto mit = methodRefNames.find( methods[i] );
                        if( mit == methodRefNames.end() ) continue;
                        bool touches = false;
                        for( const std::string& nm : mit->second ) if( nm == fld ) { touches = true; break; }
                        if( !touches ) continue;
                        if( firstSlot == 0xFFFFFFFFu ) firstSlot = i; else uf.unite( firstSlot, i );
                    }
                }
            }
            // component count = # distinct roots.
            std::uint32_t comps = 0;
            for( std::uint32_t i = 0; i < m; ++i ) if( uf.find( i ) == i ) ++comps;
            q.lcom4[ cid ] = comps;
        }
    }
    return q;
}

// resolve #include/import targets to repo file ids → the DIRECT (1-hop) file→file dependency graph
// (includer → included). Shared by --deps, --arch, cycle detection, the Lakos health metrics, gitmine
// and ccjson. PATH-PRECISE (not basename): each quote `#include "x.h"` is resolved LEXICALLY relative to
// the includer (resolve.h::resolvePreciseInclude), so a cross-directory basename collision (this repo's
// two svector.h: src/ vs third_party/) can no longer manufacture a WRONG file→file edge — it was
// the last silent-wrong-edge surface (the call-graph SameInclude tier already resolves precisely, see
// buildGraph's fileIncludes). An angle `<x.h>` or any unresolvable/ambiguous include contributes NOTHING
// (dropped, never basename-matched) — monotone: precise resolution can only REMOVE or REDIRECT a wrong
// edge, never manufacture one. `buildPreciseIncludeAdj` returns exactly this DIRECT adjacency (each
// per-file list sorted+deduped; downstream is order-independent + dedup-safe, see dsmPropagationCost).
// --deps stays DIRECT: sccCycles / dependencyHealth compute their own transitive closures over this 1-hop
// graph, so this must NOT be the transitive set (that is buildGraph's separate SameInclude table). It is
// UN-deduped (dedup=false): one entry per include OCCURRENCE, preserving the occurrence-count semantics the
// weakest-link cutrefs metric and afferent counts depend on — the ONLY change vs the old basename resolver
// is the string→fileId step (basename → precise), so those metrics stay byte-identical absent a collision.
inline std::vector<std::vector<std::uint32_t>> resolveIncludeAdj( const IngestResult& ing )
{
    return buildPreciseIncludeAdj( ing, /*dedup=*/false );
}

// Tarjan SCC on the file→file graph → cycles (SCCs with >1 node). Cyclic physical dependencies are
// Lakos's cardinal sin: a cycle must be compiled/tested/reused as one unit. Iterative (no stack risk).
inline std::vector<std::vector<std::uint32_t>> sccCycles( const std::vector<std::vector<std::uint32_t>>& adj )
{
    const std::uint32_t F = std::uint32_t( adj.size() );
    std::vector<std::int32_t>               idx( F, -1 ), low( F, 0 );
    std::vector<char>                       onStk( F, 0 );
    std::vector<std::uint32_t>              stk;
    std::vector<std::vector<std::uint32_t>> cycles;
    std::int32_t                            counter = 0;

    struct Frame { std::uint32_t v; std::size_t i; };
    std::vector<Frame> call;
    for( std::uint32_t s = 0; s < F; ++s )
    {
        if( idx[s] != -1 ) continue;
        call.push_back( { s, 0 } );
        while( !call.empty() )
        {
            Frame&              fr = call.back();
            const std::uint32_t v  = fr.v;
            if( fr.i == 0 ) { idx[v] = low[v] = counter++; stk.push_back( v ); onStk[v] = 1; }

            bool recursed = false;
            while( fr.i < adj[v].size() )
            {
                const std::uint32_t w = adj[v][ fr.i++ ];
                if( idx[w] == -1 )  { call.push_back( { w, 0 } ); recursed = true; break; }
                else if( onStk[w] ) low[v] = std::min( low[v], idx[w] );
            }
            if( recursed ) continue;

            if( low[v] == idx[v] )                                      // SCC root
            {
                std::vector<std::uint32_t> comp;
                for( ;; ) { const std::uint32_t w = stk.back(); stk.pop_back(); onStk[w] = 0; comp.push_back( w ); if( w == v ) break; }
                if( comp.size() > 1 ) cycles.push_back( std::move( comp ) );
            }
            call.pop_back();
            if( !call.empty() ) low[ call.back().v ] = std::min( low[ call.back().v ], low[v] );
        }
    }
    return cycles;
}

// Lakos Cumulative Component Dependency: per-file transitive include count (incl. self), then
// CCD = Σ, ACD = CCD/N, NCCD = CCD / (balanced-binary-tree CCD). NCCD < 1 = horizontal (flat/good),
// > 1 = vertical, > 2 ≈ contains cycles. The single number for whole-codebase dependency health.
// EVIDENCE NOTE: mechanistically plausible for build cost, but no independent outcome-based study
// validates NCCD as a defect/maintenance predictor — design heuristic, not proof (RESEARCH_agentQuality2026 §1a).
struct DepHealth { std::vector<std::uint32_t> transitive; std::uint64_t ccd = 0; double acd = 0, nccd = 0; };
inline DepHealth dependencyHealth( const std::vector<std::vector<std::uint32_t>>& adj )
{
    const std::uint32_t F = std::uint32_t( adj.size() );
    DepHealth h;
    h.transitive.assign( F, 0 );
    std::vector<std::uint32_t> seenEpoch( F, 0 );
    std::vector<std::uint32_t> stack;
    stack.reserve( F );
    std::uint32_t              epoch = 1;
    for( std::uint32_t s = 0; s < F; ++s )
    {
        stack.clear();  stack.push_back( s );  seenEpoch[s] = epoch;
        std::uint32_t reached = 0;
        while( !stack.empty() )
        {
            const std::uint32_t v = stack.back();  stack.pop_back();  ++reached;
            for( std::uint32_t w : adj[v] ) if( seenEpoch[w] != epoch ) { seenEpoch[w] = epoch; stack.push_back( w ); }
        }
        h.transitive[s] = reached;   // includes self (Lakos convention)
        h.ccd += reached;
        ++epoch;
    }
    h.acd  = F ? double( h.ccd ) / double( F ) : 0.0;
    const double btree = F > 1 ? ( double( F + 1 ) * std::log2( double( F + 1 ) ) - double( F ) ) : 1.0;
    h.nccd = btree > 0.0 ? double( h.ccd ) / btree : 0.0;
    return h;
}

// §P9.4: recompute CCD/ACD/NCCD restricted to DEPENDENCY-CAPABLE files (a file whose language has no
// #include/import syntax — see lintrules.h::dependencyCapable — can only ever be an isolated single-node
// component, so counting it in N drags NCCD toward 0 for a reason unrelated to actual coupling; measured on
// this repo: 385/760 files are .sh/.md, nccd=0.27 "horizontal" over all files vs ~1.1-1.25 restricted to
// C-family — the denominator was making the verdict). A file's OWN transitive-closure size doesn't depend
// on which OTHER files are capable, only on the graph edges — so dependencyHealth()'s unrestricted
// `transitive[]` is reused verbatim; this is a small post-pass over already-computed data, not a second
// BFS, kept as its own function so the hot traversal above stays untouched. `--deps <health>`'s dep_files=
// and `--arch`'s propagation_cost (arch.h::dsmPropagationCostCapable) both key off the same
// dependencyCapableMask(), so the two verbs' N is provably the same denominator.
struct RestrictedDepHealth { std::uint64_t ccd = 0; double acd = 0, nccd = 0; std::size_t depFileCount = 0; };
inline RestrictedDepHealth restrictDependencyHealth( const IngestResult& ing, const std::vector<std::uint32_t>& transitive )
{
    RestrictedDepHealth r;
    const std::size_t F = std::min( transitive.size(), ing.files.size() );
    for( std::size_t f = 0; f < F; ++f )
        if( dependencyCapable( langOfPath( ing.files[f] ) ) ) { r.ccd += transitive[f]; ++r.depFileCount; }
    const double N = double( r.depFileCount );
    r.acd  = r.depFileCount ? double( r.ccd ) / N : 0.0;
    const double btree = r.depFileCount > 1 ? ( ( N + 1.0 ) * std::log2( N + 1.0 ) - N ) : 1.0;
    r.nccd = btree > 0.0 ? double( r.ccd ) / btree : 0.0;
    return r;
}

// --map-diff teleport: β of the mass on symbols in changed files, (1−β) on the rest (SPEC §3).
inline std::vector<float> diffTeleport( const IngestResult& ing, const std::vector<char>& fileChanged, float beta = 0.7f )
{
    const std::size_t N = ing.symbols.size();
    std::vector<float> p( N, N ? 1.0f / float( N ) : 0.f );
    std::size_t changed = 0;
    for( const Symbol& s : ing.symbols ) if( fileChanged[ s.fileId ] ) ++changed;
    if( changed == 0 || changed == N ) return p;            // degenerate → uniform
    const float a = beta / float( changed ), b = ( 1.0f - beta ) / float( N - changed );
    for( const Symbol& s : ing.symbols ) p[ s.id ] = fileChanged[ s.fileId ] ? a : b;
    return p;
}

// ---- shortest directed call-path (--path=SRC,DST): BFS over out-edges; empty if unreachable -----------
// Deterministic: out-edges are stored ascending by target id within each source, so BFS expands in a fixed
// order. Returns the node sequence src..dst inclusive; {src} if src==dst; empty if dst is unreachable.
inline std::vector<NodeId> shortestPathAny( const Graph& g, const std::vector<NodeId>& srcs, const std::vector<NodeId>& dsts )
{
    const std::size_t N = g.wOutDeg.size();
    if( srcs.empty() || dsts.empty() ) return {};

    std::vector<NodeId> prev( N, kNoNode );
    std::vector<char>   seen( N, 0 ), isDst( N, 0 );
    for( NodeId d : dsts ) if( d < N ) isDst[d] = 1;

    std::vector<NodeId> q;  q.reserve( 64 );
    NodeId              hit = kNoNode;
    for( NodeId s : srcs )
        if( s < N && !seen[s] ) { seen[s] = 1;  q.push_back( s );  if( isDst[s] && hit == kNoNode ) hit = s; }

    for( std::size_t head = 0; head < q.size() && hit == kNoNode; ++head )
    {
        const NodeId u = q[ head ];
        for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
        {
            const NodeId v = g.outTargets[k];
            if( seen[v] ) continue;
            seen[v] = 1;  prev[v] = u;
            if( isDst[v] ) { hit = v; break; }
            q.push_back( v );
        }
    }
    if( hit == kNoNode ) return {};

    std::vector<NodeId> path;
    for( NodeId at = hit; at != kNoNode; at = prev[at] ) path.push_back( at );   // prev[seed] = kNoNode → stops
    std::reverse( path.begin(), path.end() );
    return path;
}

inline std::vector<NodeId> shortestPath( const Graph& g, NodeId src, NodeId dst )
{
    // The one-source/one-target case of shortestPathAny, delegated rather than re-implemented: the two
    // bodies were a 359-token near-duplicate BFS, and the tool's own --quality-delta flagged them. The
    // semantics coincide exactly — an out-of-range endpoint yields no path either way, and src == dst
    // returns { src } from the is-a-target check at seeding.
    return shortestPathAny( g, std::vector<NodeId>{ src }, std::vector<NodeId>{ dst } );
}


// ---- transitive reverse-reachability: every symbol that (transitively, via in-edges) reaches a seed — the
//      blast radius. Deterministic (in-edges are id-sorted; result sorted). Excludes the seeds themselves.
//      Powers --impact (one seed symbol) and --affected (all symbols in the changed files). -------------
inline std::vector<NodeId> transitiveCallers( const Graph& g, const std::vector<NodeId>& seeds )
{
    const std::size_t   N = g.wOutDeg.size();
    std::vector<char>   seen( N, 0 );
    std::vector<NodeId> q;
    for( NodeId s : seeds ) if( s < N && !seen[s] ) { seen[s] = 1; q.push_back( s ); }
    const std::size_t nSeed = q.size();
    const auto*       ro    = g.inEdges.rowOffsets();
    const auto*       ci    = g.inEdges.colIndices();
    for( std::size_t head = 0; head < q.size(); ++head )
    {
        const NodeId u = q[ head ];
        for( std::uint32_t k = ro[u]; k < ro[u + 1]; ++k )
        { const NodeId c = ci[k]; if( c < N && !seen[c] ) { seen[c] = 1; q.push_back( c ); } }
    }
    std::vector<NodeId> out( q.begin() + nSeed, q.end() );   // reached, minus the seeds
    std::sort( out.begin(), out.end() );
    return out;
}

// symbols transitively reachable FROM `seeds` via OUT-edges (everything the seeds call, transitively) — the
// forward dual of transitiveCallers. Returns a per-node mask (seeds included). Used by --seams as testReach:
// a cross-module edge u→v is exercised by a test iff testReach[u] (a test transitively reaches the caller).
inline std::vector<char> forwardReach( const Graph& g, const std::vector<NodeId>& seeds )
{
    const std::size_t   N = g.wOutDeg.size();
    std::vector<char>   seen( N, 0 );
    std::vector<NodeId> q;
    for( NodeId s : seeds ) if( s < N && !seen[s] ) { seen[s] = 1; q.push_back( s ); }
    for( std::size_t head = 0; head < q.size(); ++head )
    {
        const NodeId u = q[ head ];
        for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
        { const NodeId v = g.outTargets[k]; if( v < N && !seen[v] ) { seen[v] = 1; q.push_back( v ); } }
    }
    return seen;
}

// ---- minimal connecting subgraph (--connect=A,B,C): metric-closure 2-approx Steiner ------------------------
// DESIGN_connectSubgraph.md §2/§3, implemented verbatim. "My task touches these N symbols — how do they
// RELATE, and which intermediaries matter?" Search is UNDIRECTED (the shared-caller join `main → {A,B}` only
// exists on the undirected view — the whole point vs the directed --path), but every reported edge keeps its
// TRUE caller→callee direction from the CSR: direction is data on the edge, not a constraint on the search.
//
// Algorithm (§2): one bounded BFS per terminal over out-CSR + in-CSR (radius R hops), metric closure over the
// terminals, terminal-MST via Prim seeded at the lowest terminal id with the (dist, minId, maxId) tie-break,
// union of the MST edges' shortest paths (reconstructed from the lower-id endpoint's prev[]). Terminals whose
// pairwise distances are all ∞ within R form separate groups (§2.5) — singleton groups are the emitter's
// <unconnected> block; the output ALWAYS contains every terminal (honest partitions, never a silent empty).
//
// Determinism (§3, byte-identical by construction): BFS visits out-edges first then in-edges, each ascending
// by id (both CSRs are id-sorted), so prev[] is the first-discovered = lexicographically-smallest-by-id equal-
// length path; Prim ties break on (dist, minId, maxId); every emitted list is id-/(from,to)-sorted; truncation
// drops from a sorted order. Pure integer BFS/MST — no float, no clock, no I/O; exact, not tolerance-banded.
//
// Complexity (§6): T bounded BFS = O( T·(V+E) ) worst case over the two existing CSRs — T is capped at
// kMaxTerminals = 16 and R at kMaxRadius = 12, so in practice the radius-bounded frontier touches far less
// than V+E per terminal (16 × 140k edge-visits ≈ low single-digit ms on a 40k-symbol graph). The terminal MST
// is O( T³ ) over ≤16 terminals (noise); emission unions cover ≤ kMaxNodes nodes. Memory: T rows of
// dist(uint16) + prev(NodeId) + a via-out bit, reused nothing inside the BFS loop after the assigns.
namespace connectcfg
{
    inline constexpr std::size_t   kMaxTerminals  = 16;        // >16 is the CALLER's usage error; the core CLAMPS (never VERIFYs on hostile input)
    inline constexpr std::uint32_t kMaxNodes      = 96;        // total emitted node cap (§3 size caps)
    inline constexpr std::uint32_t kMaxEdges      = 256;       // total emitted edge cap
    inline constexpr std::uint32_t kMinRadius     = 1;         // --connect-radius clamp band (design §2.2)
    inline constexpr std::uint32_t kMaxRadius     = 12;
    inline constexpr std::uint32_t kDefaultRadius = 6;
    inline constexpr std::uint16_t kUnreachable   = 0xFFFFu;   // BFS "not reached within R" sentinel
}

// one reported call edge — ALWAYS true caller→callee direction, whichever way the undirected search walked it.
struct ConnectEdge { NodeId from = kNoNode, to = kNoNode; };

// one retained MST leg between two terminals (termA < termB by node id); dist = undirected hop count.
// This is the emitter's trim/truncation unit (§4: drop whole MST-paths longest-first under --max-tokens).
struct ConnectPath { NodeId termA = kNoNode, termB = kNoNode; std::uint32_t dist = 0; };

struct ConnectGroup
{
    std::vector<NodeId>      terminals;   // this group's terminals, id-ascending (size 1 ⇒ an <unconnected> group)
    std::vector<NodeId>      steiner;     // intermediaries the agent did NOT name, id-ascending (never a terminal)
    std::vector<ConnectEdge> edges;       // deduped, sorted (from,to); true caller→callee direction
    std::vector<ConnectPath> paths;       // the retained MST legs (dropped-by-truncation legs are absent)
};

struct ConnectResult
{
    std::vector<NodeId>        terminals;     // sanitized: in-range only, deduped, id-ascending, capped at kMaxTerminals
    std::vector<std::uint32_t> componentOf;   // parallel to `terminals`: index into `groups` (the <unconnected> assignment)
    std::vector<ConnectGroup>  groups;        // ordered by lowest terminal id (first-seen over the ascending terminal list)
    std::uint32_t              radius    = connectcfg::kDefaultRadius;   // the CLAMPED radius actually searched
    bool                       truncated = false;   // a size cap dropped ≥1 MST path (emitter stamps truncated="paths")
};

inline ConnectResult connectSubgraph( const Graph& g, const std::vector<NodeId>& terminalSpecs,
                                      std::uint32_t radius = connectcfg::kDefaultRadius )
{
    const std::size_t N = g.wOutDeg.size();
    ConnectResult res;
    res.radius = std::clamp( radius, connectcfg::kMinRadius, connectcfg::kMaxRadius );

    // sanitize terminals: drop out-of-range ids, dedup, ascending; CLAMP to the cap (lowest ids win — a
    // deterministic degrade, since hostile input must never trip a VERIFY; the CLI enforces the usage error).
    for( NodeId t : terminalSpecs ) if( t < N ) res.terminals.push_back( t );
    std::sort( res.terminals.begin(), res.terminals.end() );
    res.terminals.erase( std::unique( res.terminals.begin(), res.terminals.end() ), res.terminals.end() );
    if( res.terminals.size() > connectcfg::kMaxTerminals ) res.terminals.resize( connectcfg::kMaxTerminals );
    const std::size_t T = res.terminals.size();
    if( T == 0 ) return res;                                   // empty terminals → empty result (honest degrade)

    // ── §2.2: one bounded BFS per terminal on the UNDIRECTED view (out-CSR + in-CSR). Visit order at each
    //    node: out-edges first, then in-edges, each ascending by id — so prev[] is the deterministic first-
    //    discovered parent. prevViaOut records WHICH CSR discovered the node: 1 = the parent's out-edge
    //    (true direction parent→child), 0 = the parent's in-edge (true direction child→parent) — the exact
    //    CSR truth, recorded at discovery so no re-lookup (and no wrong guess) is needed at reconstruction.
    const auto* inRo   = g.inEdges.rowOffsets();
    const auto* inCi   = g.inEdges.colIndices();
    const bool  haveIn = g.inEdges.rows() == N;                // degrade to out-only if shapes ever mismatch

    std::vector<std::vector<std::uint16_t>> dist( T );
    std::vector<std::vector<NodeId>>        prev( T );
    std::vector<std::vector<std::uint8_t>>  prevViaOut( T );
    {
        std::vector<NodeId> q;
        q.reserve( 256 );
        for( std::size_t ti = 0; ti < T; ++ti )
        {
            dist[ti].assign( N, connectcfg::kUnreachable );
            prev[ti].assign( N, kNoNode );
            prevViaOut[ti].assign( N, 0u );
            const NodeId src = res.terminals[ ti ];
            dist[ti][ src ] = 0;
            q.clear();
            q.push_back( src );
            for( std::size_t head = 0; head < q.size(); ++head )
            {
                const NodeId        u  = q[ head ];
                const std::uint16_t du = dist[ti][ u ];
                if( du >= res.radius ) continue;               // radius bound: never expand past R undirected hops

                // out-edges first (ascending by construction — buildGraph stores targets ascending per source)
                for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
                {
                    const NodeId v = g.outTargets[ k ];
                    if( v >= N || dist[ti][v] != connectcfg::kUnreachable ) continue;
                    dist[ti][v] = std::uint16_t( du + 1 );  prev[ti][v] = u;  prevViaOut[ti][v] = 1u;
                    q.push_back( v );
                }
                // then in-edges (row u's callers, ascending — the in-CSR fill preserves (from,to) sort order)
                if( haveIn )
                    for( std::uint32_t k = inRo[u]; k < inRo[u + 1]; ++k )
                    {
                        const NodeId v = inCi[ k ];
                        if( v >= N || dist[ti][v] != connectcfg::kUnreachable ) continue;
                        dist[ti][v] = std::uint16_t( du + 1 );  prev[ti][v] = u;  prevViaOut[ti][v] = 0u;
                        q.push_back( v );
                    }
            }
        }
    }

    // ── §2.5: metric-closure components over the terminals (edge = finite pairwise dist within R). Terminal
    //    indices ascend with node ids (the list is sorted), so first-seen component ids are lowest-id ordered.
    UnionFind uf( T );
    for( std::size_t i = 0; i < T; ++i )
        for( std::size_t j = i + 1; j < T; ++j )
            if( dist[i][ res.terminals[j] ] != connectcfg::kUnreachable ) uf.unite( std::uint32_t( i ), std::uint32_t( j ) );

    res.componentOf.assign( T, 0u );
    std::vector<std::uint32_t> rootToComp( T, 0xFFFFFFFFu );
    std::uint32_t              compCount = 0;
    for( std::size_t ti = 0; ti < T; ++ti )
    {
        const std::uint32_t root = uf.find( std::uint32_t( ti ) );
        if( rootToComp[ root ] == 0xFFFFFFFFu ) rootToComp[ root ] = compCount++;
        res.componentOf[ ti ] = rootToComp[ root ];
    }

    // ── §2.3 + §2.4 per component: Prim terminal-MST (lowest-id seed, (dist, minId, maxId) tie-break), then
    //    reconstruct each MST leg from the LOWER-id endpoint's BFS prev[]. Kept per-leg so §3 truncation can
    //    drop whole MST-paths and the survivors' union is recomputable.
    struct PathBuild
    {
        ConnectPath              meta;
        std::vector<NodeId>      nodes;    // every node on the leg, terminals included
        std::vector<ConnectEdge> edges;    // the leg's call edges, true direction
        bool                     dropped = false;
    };
    std::vector<std::vector<std::size_t>> members( compCount );          // component → terminal indices, ascending
    for( std::size_t ti = 0; ti < T; ++ti ) members[ res.componentOf[ ti ] ].push_back( ti );
    std::vector<std::vector<PathBuild>> groupPaths( compCount );

    for( std::uint32_t c = 0; c < compCount; ++c )
    {
        const std::vector<std::size_t>& m = members[ c ];
        if( m.size() < 2 ) continue;                                      // a singleton group has no legs (— <unconnected>)

        // Prim over the metric closure, seeded at the component's lowest terminal id (m[0] — ids ascend with index).
        std::vector<char> inTree( m.size(), 0 );
        inTree[ 0 ] = 1;
        for( std::size_t added = 1; added < m.size(); ++added )
        {
            std::uint32_t bestDist = connectcfg::kUnreachable + 1u;       // strictly worse than any finite dist
            NodeId        bestMin = kNoNode, bestMax = kNoNode;
            std::size_t   bestJ = m.size();
            for( std::size_t i = 0; i < m.size(); ++i )
            {
                if( !inTree[ i ] ) continue;
                for( std::size_t j = 0; j < m.size(); ++j )
                {
                    if( inTree[ j ] ) continue;
                    const std::size_t   lo = ( m[i] < m[j] ) ? m[i] : m[j];   // BFS/dist row of the lower-id endpoint
                    const std::size_t   hi = ( m[i] < m[j] ) ? m[j] : m[i];
                    const std::uint32_t d  = dist[ lo ][ res.terminals[ hi ] ];
                    if( d == connectcfg::kUnreachable ) continue;             // finite by component membership eventually
                    const NodeId idMin = res.terminals[ lo ], idMax = res.terminals[ hi ];
                    const bool better = d != bestDist ? d < bestDist
                                      : idMin != bestMin ? idMin < bestMin
                                      : idMax < bestMax;                      // the §2.3 (dist, minId, maxId) tuple
                    if( better ) { bestDist = d;  bestMin = idMin;  bestMax = idMax;  bestJ = j; }
                }
            }
            if( bestJ == m.size() ) break;                                // defensive: no finite join left → stop (degrade, no spin)
            inTree[ bestJ ] = 1;

            // §2.4: reconstruct the leg from the LOWER-id endpoint's prev[] — walk from the higher-id terminal back.
            PathBuild pb;
            pb.meta = { bestMin, bestMax, bestDist };
            std::size_t loIdx = 0;
            for( std::size_t i = 0; i < m.size(); ++i ) if( res.terminals[ m[i] ] == bestMin ) { loIdx = m[i]; break; }
            NodeId cur = bestMax;
            pb.nodes.push_back( cur );
            while( cur != bestMin )
            {
                const NodeId p = prev[ loIdx ][ cur ];
                if( p == kNoNode ) break;                                  // defensive: broken chain → keep what we have
                // discovery channel = the CSR truth: via-out means p CALLS cur; via-in means cur CALLS p.
                if( prevViaOut[ loIdx ][ cur ] ) pb.edges.push_back( { p, cur } );
                else                              pb.edges.push_back( { cur, p } );
                pb.nodes.push_back( p );
                cur = p;
            }
            groupPaths[ c ].push_back( std::move( pb ) );
        }
    }

    // ── §3 size caps: total emitted nodes ≤ kMaxNodes, edges ≤ kMaxEdges. Drop whole MST-paths longest-first
    //    (ties: the higher terminal-pair (minId, maxId) is dropped LAST — i.e. the lower pair goes first);
    //    terminals are NEVER dropped. Recompute the sorted unions after each drop (tiny: ≤15 legs × ≤11 nodes).
    const auto edgeLess = []( const ConnectEdge& a, const ConnectEdge& b ) noexcept
    { return a.from != b.from ? a.from < b.from : a.to < b.to; };
    const auto edgeEq   = []( const ConnectEdge& a, const ConnectEdge& b ) noexcept
    { return a.from == b.from && a.to == b.to; };

    std::vector<NodeId>      nodeScratch;
    std::vector<ConnectEdge> edgeScratch;
    for( ;; )
    {
        std::uint32_t nodeTotal = 0, edgeTotal = 0;
        for( std::uint32_t c = 0; c < compCount; ++c )
        {
            nodeScratch.clear();
            edgeScratch.clear();
            for( std::size_t ti : members[ c ] ) nodeScratch.push_back( res.terminals[ ti ] );
            for( const PathBuild& pb : groupPaths[ c ] )
            {
                if( pb.dropped ) continue;
                nodeScratch.insert( nodeScratch.end(), pb.nodes.begin(), pb.nodes.end() );
                edgeScratch.insert( edgeScratch.end(), pb.edges.begin(), pb.edges.end() );
            }
            std::sort( nodeScratch.begin(), nodeScratch.end() );
            nodeScratch.erase( std::unique( nodeScratch.begin(), nodeScratch.end() ), nodeScratch.end() );
            std::sort( edgeScratch.begin(), edgeScratch.end(), edgeLess );
            edgeScratch.erase( std::unique( edgeScratch.begin(), edgeScratch.end(), edgeEq ), edgeScratch.end() );
            nodeTotal += std::uint32_t( nodeScratch.size() );
            edgeTotal += std::uint32_t( edgeScratch.size() );
        }
        if( nodeTotal <= connectcfg::kMaxNodes && edgeTotal <= connectcfg::kMaxEdges ) break;

        // drop victim: max (dist, then LOWEST (minId,maxId) first among equals) over every retained leg.
        PathBuild* victim = nullptr;
        for( std::uint32_t c = 0; c < compCount; ++c )
            for( PathBuild& pb : groupPaths[ c ] )
            {
                if( pb.dropped ) continue;
                bool wins;
                if( !victim )                                  wins = true;
                else if( pb.meta.dist  != victim->meta.dist  ) wins = pb.meta.dist  > victim->meta.dist;   // longest first
                else if( pb.meta.termA != victim->meta.termA ) wins = pb.meta.termA < victim->meta.termA;  // lower pair first
                else                                           wins = pb.meta.termB < victim->meta.termB;
                if( wins ) victim = &pb;
            }
        if( !victim ) break;                                              // nothing left to drop → emit what remains
        victim->dropped = true;
        res.truncated   = true;
    }

    // ── §3 emission order: groups by lowest terminal id (== component order), terminals ascending, steiner
    //    intermediaries ascending, edges sorted (from,to), retained paths in MST-build order.
    res.groups.resize( compCount );
    for( std::uint32_t c = 0; c < compCount; ++c )
    {
        ConnectGroup& grp = res.groups[ c ];
        for( std::size_t ti : members[ c ] ) grp.terminals.push_back( res.terminals[ ti ] );

        nodeScratch.clear();
        for( const PathBuild& pb : groupPaths[ c ] )
        {
            if( pb.dropped ) continue;
            grp.paths.push_back( pb.meta );
            nodeScratch.insert( nodeScratch.end(), pb.nodes.begin(), pb.nodes.end() );
            grp.edges.insert( grp.edges.end(), pb.edges.begin(), pb.edges.end() );
        }
        std::sort( nodeScratch.begin(), nodeScratch.end() );
        nodeScratch.erase( std::unique( nodeScratch.begin(), nodeScratch.end() ), nodeScratch.end() );
        for( NodeId v : nodeScratch )
            if( !std::binary_search( grp.terminals.begin(), grp.terminals.end(), v ) ) grp.steiner.push_back( v );
        std::sort( grp.edges.begin(), grp.edges.end(), edgeLess );
        grp.edges.erase( std::unique( grp.edges.begin(), grp.edges.end(), edgeEq ), grp.edges.end() );
    }
    return res;
}

// ---- community detection (--communities): one level of Louvain local-moving on the UNDIRECTED projection
//      of the call graph (unit edge weights). Deterministic: nodes processed in id order; on a (near-)tie
//      the move resolves to the LOWER community id; fixed pass cap; ankerl insertion-ordered maps. Returns
//      node→community with ids compacted to 0..count-1 in first-seen-by-node-id order. -------------------
struct Communities { std::vector<std::uint32_t> comm; std::uint32_t count = 0; };

// A weighted undirected neighbour: target node + edge weight. Self-loops are excluded by the builders.
struct WEdge { NodeId to; double w; };

// The deterministic Louvain local-moving core, shared by the symbol graph (unit weights, --communities) and
// every CONTRACTED super-node level (summed weights, --zoom). `adj[i]` = i's weighted neighbours (no self-
// loops; a neighbour may appear once, its w pre-summed). Returns node→community, ids compacted 0..K-1 in
// first-seen-by-node-id order. Determinism is identical at every level: nodes visited in id order, a
// (near-)tie resolves to the LOWER community id (so the result never depends on map iteration), the same
// fixed 16-pass cap, ankerl insertion-ordered maps. This is the ONE place the algorithm lives, so the
// single-level and multi-level paths cannot drift.
inline Communities louvainLocalMoving( const std::vector<std::vector<WEdge>>& adj )
{
    const std::uint32_t N = std::uint32_t( adj.size() );
    Communities out;
    out.comm.assign( N, 0 );
    if( N == 0 ) return out;

    std::vector<std::uint32_t> comm( N );
    std::vector<double>        deg( N ), commTot( N );
    double m2 = 0.0;
    for( NodeId i = 0; i < N; ++i )
    {
        comm[i] = i;
        double d = 0.0;
        for( const WEdge& e : adj[i] ) d += e.w;
        deg[i] = d;  commTot[i] = d;  m2 += d;
    }

    HashMap<std::uint32_t, double> linkTo;   // neighbour-community → summed edge weight from i (reused per node)
    for( int pass = 0; pass < 16 && m2 > 0.0; ++pass )
    {
        bool improved = false;
        for( NodeId i = 0; i < N; ++i )
        {
            if( adj[i].empty() ) continue;
            const std::uint32_t ci = comm[i];
            commTot[ ci ] -= deg[i];                                  // pull i out of its community
            linkTo.clear();
            for( const WEdge& e : adj[i] ) linkTo[ comm[ e.to ] ] += e.w;
            // Louvain gain (weighted), constants dropped:  k_iin(C) − deg[i]·Σtot(C)/m2 ; maximize.
            std::uint32_t best     = ci;
            double        bestGain = ( linkTo.contains( ci ) ? linkTo[ci] : 0.0 ) - deg[i] * commTot[ci] / m2;
            for( const auto& [ c, kin ] : linkTo )
            {
                const double gain = kin - deg[i] * commTot[c] / m2;
                if( gain > bestGain + 1e-9 )               { bestGain = gain; best = c; }   // strictly better
                else if( gain > bestGain - 1e-9 && c < best ) {              best = c; }     // tie → lower id
            }
            commTot[ best ] += deg[i];                                // place i in the chosen community
            comm[i] = best;
            if( best != ci ) improved = true;
        }
        if( !improved ) break;
    }

    // compact community ids to 0..K-1 in first-seen (node-id) order
    HashMap<std::uint32_t, std::uint32_t> remap;
    for( NodeId i = 0; i < N; ++i )
    {
        const auto it = remap.find( comm[i] );
        if( it == remap.end() ) { const std::uint32_t nid = std::uint32_t( remap.size() ); remap.emplace( comm[i], nid ); out.comm[i] = nid; }
        else                      out.comm[i] = it->second;
    }
    out.count = std::uint32_t( remap.size() );
    return out;
}

// the UNDIRECTED unit-weight adjacency of the symbol call graph (in+out edges, deduped, self-loops dropped) —
// the level-0 input for both --communities and --zoom. Each neighbour appears once with weight 1.
inline std::vector<std::vector<WEdge>> symbolAdjacency( const Graph& g )
{
    const std::uint32_t N    = std::uint32_t( g.wOutDeg.size() );
    const auto*         inRo = g.inEdges.rowOffsets();
    const auto*         inCi = g.inEdges.colIndices();
    std::vector<std::vector<WEdge>> adj( N );
    std::vector<NodeId>             nb;
    for( NodeId u = 0; u < N; ++u )
    {
        nb.clear();
        for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k ) if( g.outTargets[k] != u ) nb.push_back( g.outTargets[k] );
        for( std::uint32_t k = inRo[u];     k < inRo[u + 1];     ++k ) if( inCi[k] != u )           nb.push_back( inCi[k] );
        std::sort( nb.begin(), nb.end() );
        nb.erase( std::unique( nb.begin(), nb.end() ), nb.end() );
        adj[u].reserve( nb.size() );
        for( NodeId v : nb ) adj[u].push_back( { v, 1.0 } );
    }
    return adj;
}

inline Communities communities( const Graph& g )
{
    return louvainLocalMoving( symbolAdjacency( g ) );
}

// ---- multi-level community zoom (--zoom): iteratively CONTRACT each community into a super-node and re-run
//      Louvain on the contracted (weighted) graph, building a NESTED module hierarchy. Level 0 = the symbol
//      communities (identical to --communities). Each next level groups the level below until the top has
//      ≤ maxTop modules (or no further merge happens, or maxLevels is hit). Deterministic at every level:
//      the contracted graph's super-node ids are the level-below community ids (0..K-1, first-seen order),
//      its edges are the summed cross-community weights, and the local-moving core is the SAME one used for
//      level 0 — so the whole hierarchy is byte-identical run-to-run. ----------------------------------------
struct ZoomHierarchy
{
    // levels[0] = finest (symbol→community); levels.back() = coarsest (symbol→top module). Each levels[L] is
    // a symbol→group map with `counts[L]` groups, so every level is expressed directly over symbol ids and a
    // caller can read membership at any depth without re-walking parents.
    std::vector<std::vector<std::uint32_t>> levels;
    std::vector<std::uint32_t>              counts;
    // parentOf[L][child] = the level-(L+1) group that level-L group `child` belongs to (size counts[L]).
    // Empty for the top level. Lets the renderer nest a level directly under its parent with no recompute.
    std::vector<std::vector<std::uint32_t>> parentOf;
};

// contract a weighted graph `adj` (over `K` nodes) under a node→group map `comm` (`groups` groups): sum the
// weights of every edge whose endpoints fall in DISTINCT groups → the weighted super-node graph over `groups`
// nodes. Deterministic: accumulated by ordered (min,max) group pair, neighbours id-sorted. Self/intra-group
// edges fold into the super-node (dropped). Shared by every contraction step so the rule is in one place.
inline std::vector<std::vector<WEdge>> contractGraph( const std::vector<std::vector<WEdge>>& adj,
                                                      const std::vector<std::uint32_t>& comm, std::uint32_t groups )
{
    const std::uint32_t K = std::uint32_t( adj.size() );
    HashMap<std::uint64_t, double> sup;            // (a<<32|b), a<b → summed undirected weight between groups
    for( std::uint32_t u = 0; u < K; ++u )
    {
        const std::uint32_t cu = comm[u];
        for( const WEdge& e : adj[u] )
        {
            const std::uint32_t cv = comm[ e.to ];
            if( cu == cv ) continue;               // intra-group → folded into the super-node, not an edge
            if( cu < cv ) sup[ ( std::uint64_t( cu ) << 32 ) | cv ] += e.w;   // count each undirected pair once
        }
    }
    std::vector<std::vector<WEdge>> out( groups );
    for( const auto& [ key, w ] : sup )
    {
        const std::uint32_t a = std::uint32_t( key >> 32 ), b = std::uint32_t( key & 0xffffffffu );
        out[a].push_back( { b, w } );
        out[b].push_back( { a, w } );
    }
    for( std::vector<WEdge>& a : out )
        std::sort( a.begin(), a.end(), []( const WEdge& x, const WEdge& y ) { return x.to < y.to; } );
    return out;
}

inline ZoomHierarchy multiLevelCommunities( const Graph& g, std::uint32_t maxTop = 10, std::uint32_t maxLevels = 8 )
{
    ZoomHierarchy h;
    const std::uint32_t N = std::uint32_t( g.wOutDeg.size() );

    // level 0: the symbol communities (exactly --communities).
    const std::vector<std::vector<WEdge>> symAdj = symbolAdjacency( g );
    const Communities                     lvl0   = louvainLocalMoving( symAdj );
    h.levels.push_back( lvl0.comm );
    h.counts.push_back( lvl0.count );
    if( N == 0 ) return h;

    // INVARIANT held across the loop: `adj` is the weighted adjacency over the CURRENT super-node set
    // (`curCount` nodes), and `symToCur[symbolId]` is the current super-node each symbol maps into. We seed
    // `adj` by contracting the symbol graph under the level-0 communities, so the loop body is uniform (it
    // never touches the symbol graph again — it only ever coarsens the current super-node graph).
    std::vector<std::vector<WEdge>> adj      = contractGraph( symAdj, lvl0.comm, lvl0.count );
    std::vector<std::uint32_t>      symToCur = lvl0.comm;   // symbol → current super-node id
    std::uint32_t                   curCount = lvl0.count;  // number of current super-nodes (== adj.size())

    // contract until the top is small enough, nothing merges further, or we hit the level cap. Each step runs
    // one Louvain pass on `adj` (grouping the current super-nodes), records the lifted symbol→group map, then
    // coarsens `adj` under that grouping for the next step.
    for( std::uint32_t step = 0; step < maxLevels && curCount > maxTop && curCount > 1; ++step )
    {
        const Communities parent = louvainLocalMoving( adj );
        if( parent.count >= curCount ) break;              // no coarsening achieved → stop (avoid a no-op level)

        std::vector<std::uint32_t> symGroup( N );          // lift super-node→parent grouping back to symbol ids
        for( NodeId i = 0; i < N; ++i ) symGroup[i] = parent.comm[ symToCur[i] ];
        h.parentOf.push_back( parent.comm );               // this level's super-node → the coarser level's group
        h.levels.push_back( symGroup );
        h.counts.push_back( parent.count );

        adj = contractGraph( adj, parent.comm, parent.count );   // coarsen the current super-node graph one step
        for( NodeId i = 0; i < N; ++i ) symToCur[i] = parent.comm[ symToCur[i] ];
        curCount = parent.count;
    }
    return h;
}

}   // namespace ctx
