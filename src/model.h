#pragma once

// model.h — the shared data model for ripwire: the contract between INGEST (tree-sitter)
// and the GRAPH / RANK / SERIALIZE stages. POD/DOD, ids not pointers, dense indices.
//
// Flow:  ingest() → IngestResult { files, symbols(defs), references(unresolved calls) }
//        → graph: resolve references to symbol ids, build the in-edge CSR + wOutDeg
//        → rank:  personalized PageRank over the CSR
//        → serialize: top-K symbols (by rank) → minified XML, grouped by file.

#include <algorithm>   // std::sort — symbolsByFile below
#include <array>       // Symbol::evWhy — the fixed-size ev_why tag counters
#include <cstdint>
#include <string>
#include <vector>

#if defined( CTX_USE_STD_MAP )
    #include <unordered_map>
#else
    #include "unordered_dense.h"   // ankerl flat hash map — far faster than std::unordered_map
#endif

namespace rw
{

// project-wide fast map alias — use HashMap<>, never std::unordered_map (flat, cache-friendly).
#if defined( CTX_USE_STD_MAP )
template<class K, class V> using HashMap = std::unordered_map<K, V>;
#else
template<class K, class V> using HashMap = ankerl::unordered_dense::map<K, V>;
#endif

using NodeId = std::uint32_t;
inline constexpr NodeId kNoNode = 0xFFFFFFFFu;

// symbol kind → the terse XML attribute (t="fn|method|cls|struct|iface|var|sec|macro").
// Macro (the macro-edges round) is APPENDED before Other so no existing kind renumbers: a preprocessor
// `#define` definition (@definition.macro — C/C++ preproc_def/preproc_function_def, Rust macro_definition).
// Previously the C/Rust captures mapped to Function, which read as a lie on every t= surface; the kind now
// says what the thing IS. A macro symbol is DISCLOSED-DEGRADED by construction: its body is unparsed
// replacement text (edges out of it come from a lexical scan, see ingest.cpp captureMacroBodyCalls), and a
// call-shaped invocation of its name is a role="macro" edge, never role="call" (RefRole::Macro below).
enum class SymKind : std::uint8_t { Function, Method, Class, Struct, Interface, Var, Section, Macro, Other };

inline const char* symTag( SymKind k ) noexcept
{
    switch( k )
    {
        case SymKind::Function:  return "fn";
        case SymKind::Method:    return "method";
        case SymKind::Class:     return "cls";
        case SymKind::Struct:    return "struct";
        case SymKind::Interface: return "iface";
        case SymKind::Var:       return "var";
        case SymKind::Section:   return "sec";    // markdown heading (doc structure; isolated in the graph)
        case SymKind::Macro:     return "macro";  // #define (disclosed-degraded: replacement text, not a parsed body)
        default:                 return "other";
    }
}

// NOTE: Json sits AFTER Unknown deliberately. serialize.h pins `static_assert( int(Lang::Unknown)==12 )`
// and sizes contentBytesByLang[13] on it (clamping any lang index >= 13 into the Unknown token-calib
// bucket — its own designed headroom). Keeping Unknown at 12 lets JSON (a pure-data language with no
// call graph) land at 13 without disturbing that file. Json is lang-incompatible with everything but
// itself via langCompatible (graph.h) and emits ZERO references, so it never forms cross-language edges.
// CSharp is appended AFTER Json for the SAME reason (B6.2): it reuses Json's headroom — index 14 also
// clamps into the Unknown bucket in serialize.h's contentBytesByLang[13] loop (harmless, additive,
// zero renumbering of any existing Lang value) — while `bytesPerTokenFor` (a linear scan, not an
// array index) still picks up its own kTokenCalib entry everywhere else. C is appended AFTER CSharp
// (L3) for the SAME reason again: index 15 clamps into the identical Unknown-bucket headroom, zero
// renumbering of Cpp..CSharp. `.h` stays C++-owned (ingest.cpp's kLangTable) — a C header parses
// acceptably under the C++ grammar and ownership of `.h` between C/C++/ObjC is inherently ambiguous
// without a project-config signal this tool doesn't have; graph.h's langCompatible bridges Cpp<->C
// (like the existing Cpp<->ObjC bridge) so a .c definition still resolves against its .h declaration.
enum class Lang : std::uint8_t { Cpp, Python, TypeScript, Go, Rust, Swift, ObjC, Markdown, JavaScript, Bash, Java, Ruby, Unknown, Json, CSharp, C };

// short lang label — the terse XML/JSON attribute (lang="cpp|py|ts|go|rs|swift|objc|js|sh|java|rb|md|json|cs|c").
// The canonical home for this switch: previously duplicated privately in htmlexport.h, moved here so a THIRD
// caller (naming-consistency's per-language vote groups) reuses it instead of growing a second copy.
inline const char* langTag( Lang l ) noexcept
{
    switch( l )
    {
        case Lang::Cpp:        return "cpp";
        case Lang::Python:     return "py";
        case Lang::TypeScript: return "ts";
        case Lang::Go:         return "go";
        case Lang::Rust:       return "rs";
        case Lang::Swift:      return "swift";
        case Lang::ObjC:       return "objc";
        case Lang::JavaScript: return "js";
        case Lang::Bash:       return "sh";
        case Lang::Java:       return "java";
        case Lang::Ruby:       return "rb";
        case Lang::Markdown:   return "md";
        case Lang::Json:       return "json";
        case Lang::CSharp:     return "cs";
        case Lang::C:          return "c";
        default:               return "?";
    }
}

// Call-site RECEIVER classification (P2-D one-hop type narrowing). Captured at ingest from the AST shape
// of `recv.method()` / `recv->method()` so resolve.h can narrow BEFORE the ambiguous §2a name spray:
//   None    — a bare call `f()` or a qualified `A::f()` (no receiver expr) → §2a ladder, unchanged.
//   ThisObj — receiver is `this` (C++) / `self` (Python): the enclosing class is definitive → Rule 1.
//   NamedVar— receiver is a plain local variable `x` (`x->m()` / `x.m()`): the var's TYPE pins the method
//             (Rule 2, one-hop return-type — captured here so the rule is a later drop-in; see resolve.h).
enum class RecvKind : std::uint8_t { None, ThisObj, NamedVar };

// ABS-3 reference / use-site ROLE: WHAT a reference does at the use site, captured at ingest so a
// use-site index (`--uses=SYM`) can report the resolvable places a name is referenced, not just calls.
// §H4: "complete" is what this comment used to claim, and it is not true of any static name-based
// extractor — the index is a FLOOR, disclosed as counts_floor= (src/graphlegend.h).
// Smallest int that fits (≤ 6 roles) → SoA-friendly. The role is ORTHOGONAL to the call graph: only
// Call refs become PageRank edges; Read/Write/Import/Extends are recorded for the use-site index and
// NEVER enter the CSR (so the default ranked map is unchanged — G5).
//   Call    — the name is in function/callee position `f(...)` / `x.m(...)` (the existing call edges).
//   Read    — the name is referenced as a VALUE / operand (`y = x + 1`, `return foo`, `f(bar)` arg).
//   Write   — the name is the LHS of an assignment / a `++`/`--`/compound-assign target (`x = …`, `x++`).
//   Import  — the name appears in an import / #include / using directive (cross-module surface).
//   Extends — the name is a base class / implemented interface (derived → base; was `isInherit`).
//   Macro   — the macro-edges round: a call-SHAPED site whose name is an indexed C-family `#define`
//             (SymKind::Macro). NEVER emitted as role="call" — call-edge honesty: the site is an expansion,
//             not a plain call, and expansion semantics (stringize/paste/conditional arms) are unmodeled.
//             Unlike Read/Write/Import/Extends it DOES enter the call graph CSR (graph.h admits Call+Macro),
//             because the edge is the feature: the graph connects THROUGH the macro symbol. Ingest always
//             records the site as Call (a per-file parse cannot know another file's #defines); the retag to
//             Macro is the corpus-wide post-pass retagMacroCallReferences below, run at every ingest exit —
//             so a cached role=Call round-trips and is re-judged fresh each run.
enum class RefRole : std::uint8_t { Call, Read, Write, Import, Extends, Macro };
static_assert( sizeof( RefRole ) == 1, "RefRole must be a single byte (SoA-friendly, smallest int that fits)" );

// the terse `role=` attribute string for the use-site index (declarative table, not a switch chain).
inline const char* refRoleTag( RefRole r ) noexcept
{
    switch( r )
    {
        case RefRole::Call:    return "call";
        case RefRole::Read:    return "read";
        case RefRole::Write:   return "write";
        case RefRole::Import:  return "import";
        case RefRole::Extends: return "extends";
        case RefRole::Macro:   return "macro";
        default:               return "read";
    }
}

// Essential-complexity ev_why= reason vocabulary (the essential-complexity design note, §5.1). PUBLIC the
// moment it ships (test/attrvocabcheck.sh's standing posture; test/essentialcxcheck.sh pins the spellings):
// adding a tag later is a compatible extension, renaming one is not. Declaration order MUST track the
// EvWhyTag indices ingest.cpp writes — the table is the single source both emitters read.
inline constexpr std::size_t kEvWhyTagCount = 8;
inline constexpr const char* kEvWhyTagTable[ kEvWhyTagCount ] = {
    "guard-return",     // return/throw whose escape crosses at least one construct (incl. §1.3's guard clause)
    "loop-escape",      // break/continue out of a loop from under an intervening construct
    "switch-escape",    // break (or Java yield) out of a switch from under an intervening construct
    "goto",             // goto across a construct boundary (incl. C# goto case/default)
    "labelled-jump",    // labelled break/continue (Go/JS/TS/Java/Rust/Swift)
    "back-edge",        // Ruby redo/retry — a hand-rolled back edge outside every prime
    "fallthrough",      // Go fallthrough — an explicit intra-switch goto
    "multi-entry",      // a case label displaced into a loop/branch (Duff's device; §2.6)
};

// A definition = one node in the graph. symbols[i].id == i (dense, deterministic order).
struct Symbol
{
    NodeId        id     = kNoNode;
    SymKind       kind   = SymKind::Other;
    Lang          lang   = Lang::Unknown;
    std::uint16_t ppAlt  = 0;          // ppalt disclosure — full doc below, next to the other Q4 metric scalars.
                                       // DECLARED here, not there: the two pad bytes between `lang` (u8 x2) and
                                       // `fileId` (u32) are the struct's only remaining hole, so this u16 is free
                                       // here and +8 bytes there (measured by the static_assert below firing
                                       // 104 == 96 on the grouped placement — not hand-arithmetic).
    std::uint32_t fileId = 0;          // index into IngestResult::files
    std::uint32_t line   = 0;          // 1-based, for reference
    std::uint32_t sigStartByte = 0;    // signature span [sigStartByte, sigEndByte) in the file —
    std::uint32_t sigEndByte   = 0;    //   def start .. body start, for --pack-signatures
    std::uint32_t endByte      = 0;    // full def end (body-inclusive); [sigStartByte, endByte) = whole def, for --expand
    std::uint32_t cx           = 0;    // cyclomatic complexity (1 + decision points in the def); --metrics
    std::uint32_t ccx          = 0;    // cognitive complexity (nesting-weighted; SonarSource-style); --metrics, hotspots
    // Q4 size smells (SIZE is the master variable — §1d): computed at ingest from the def's AST/span.
    // ALL descriptive facts on --metrics ONLY, never a gate. `params`/`maxNest` are meaningful for
    // functions/methods; 0 for other kinds. `loc` is the def's physical line span (body-inclusive).
    std::uint32_t loc          = 0;    // physical lines the def spans = 1-based end line − start line + 1; --metrics loc=
    // local-variable-indexing plan, Phase 1 (2026-08-06 evening, PLAN.md): a FLOOR count of the def's own
    // local-variable DECLARATORS, populated by the SAME fused-DFS complexity walk that computes cx/ccx/
    // maxNest (ingest.cpp complexityOf/cc_walk) — zero new tree-sitter queries. MVP scope is C/C++ only
    // (see localsCountedLang below); meaningful for fns/methods only (0 for other kinds, same convention
    // as params/maxNest). Counts every `declarator`-fielded child of a `declaration` node whose PARENT is
    // the enclosing `compound_statement` (a direct block-statement local) — this naturally excludes
    // if-init/switch-condition/for-init/catch-clause declarators (their parent is the control-structure
    // node, not compound_statement) without any per-shape special case. L3 fix (2026-08-08): a
    // comma-separated statement (`int a=1,b=2,c=3;`) is ONE `declaration` node but THREE declarators, so
    // it counts as 3, not 1 (cc_countLocalDeclarators, ingest.cpp) — counting the statement instead of the
    // declarator undercounted on the exact axis the structured-binding exclusion below exists to avoid. A
    // structured-binding declarator (`auto [a,b] = …`) is still explicitly excluded (one declaration,
    // ambiguous per-declarator name count — see cc_walk's locals-counting block); a type-only declaration
    // with no declarator (a local forward decl, e.g. `struct Foo;`) now correctly counts as 0 rather than
    // the pre-fix "1". `--metrics` emits it as locals="N" locals_floor="1" (never a bare 0 for an
    // uncovered language — see localsCountedLang).
    std::uint32_t locals       = 0;
    // PPALT DISCLOSURE — count of ALTERNATIVE-introducing preprocessor nodes (`#else`/`#elif`/`#elifdef`)
    // inside the def, filled by the SAME fused cc_walk DFS that computes cx/ccx/maxNest/locals (zero new
    // tree-sitter queries). When > 0 the body carries branches that never coexist at compile time, so every
    // summed structural metric on this row (cx/ccx/nest/loc/locals) over-counts vs any single build —
    // measured ~2x on bullet's btMatrix3x3.h::getRotation (`#if BT_USE_SSE … #else … #endif`
    // implementations of the same function). ripwire does NOT guess which branch a build takes (which arm
    // compiles depends on flags it never sees — doctrine: never quietly guess); it keeps the deterministic
    // sum and DISCLOSES the alternative count so metric consumers can discount. A bare `#if…#endif` with no
    // `#else` introduces no mutually-exclusive alternative and does not count. C-family + C# by grammar
    // construction (only those grammars have preproc nodes) — no language predicate needed, unlike
    // `locals`. Meaningful for fns/methods only (0 otherwise, same convention as params/maxNest); emitted
    // as ppalt="N" on --metrics, ABSENT when 0. Saturates at 65535. See test/ppaltcheck.sh.
    // (The `ppAlt` field itself is declared UP TOP, in the pad hole after `lang` — see its own comment.)
    // NESTING-DEPTH PROFILE — what `maxNest` alone cannot say. maxNest is a MAX: one line at depth 9 and a
    // thousand lines at depth 9 report the same number, so a long BLOCKED-SEQUENTIAL function (a run of
    // shallow scoped steps, the max set by one inner loop) is indistinguishable from a TANGLED one that
    // holds depth across hundreds of lines. Every consumer of nest= inherits that blindness: the quality
    // panel's structural family, --readability's rank, the ensemble join. Two facts fix it, both filled by
    // the SAME fused cc_walk DFS (no new tree-sitter queries) and both keyed to the EXISTING structural bar
    // quality::kNestBar — no new magic number. Language-agnostic, unlike `locals`: cc_walk computes nesting
    // for every grammar. See test/nestprofilecheck.sh; `humps` is CodeScene's "bumpy road" factor.
    //
    // humps  — count of MAXIMAL control-nesting regions that reach the bar (CodeScene's "bumpy road": a rise
    //          above the threshold then a fall). One deep tangle is 1; repeated missing abstractions are
    //          many. EXACT, not a floor: each region has exactly one first-crossing node in the walk, and a
    //          region nested inside an already-deep one cannot cross again. Saturates at 65535 — a def with
    //          more humps than that is past every triage threshold and the exact number buys nothing.
    // deepLoc — physical lines lying inside those regions; deepLoc/loc is the fraction the max throws away.
    //          A FLOOR (emitted as deep_floor="1"), because the clamp that stops two humps sharing a line
    //          from billing it twice can only ever subtract. Saturates at 65535 for the same reason.
    //          deepLoc COUNTS LINES AND humps COUNTS REGIONS, so `deep < humps` is legal output and not a
    //          defect: two sibling regions genuinely share a line when both are written on it (see
    //          test/nestprofilecheck.sh arm 11's negative control), or anywhere in minified source. Three
    //          separate validators have read that shape as a bug, so the metrics legend says it out loud
    //          and arm 11 pins it as correct — alongside the case that WAS a defect, distinct-line regions
    //          collapsing because the deepEnd clamp was fed regions out of document order (nestcal r1,
    //          kParserVer 44, removed the only out-of-order call site with the clause-noting quirk itself).
    // Both are 0 exactly when maxNest < quality::kNestBar, so serialize.h omits them there rather than
    // writing a bare 0 — lossless, because `nest=` is already on the row (test/nestprofilecheck.sh arm 5
    // pins that equivalence in both directions).
    std::uint16_t humps        = 0;
    std::uint16_t deepLoc      = 0;
    // ESSENTIAL COMPLEXITY ev(G) (McCabe 1976; NIST SP 500-235) — what remains after every structured
    // region collapses. Computed SYNTACTICALLY inside the same fused cc_walk DFS (single-entry is
    // guaranteed by the grammar; only single-EXIT can fail, via jump nodes), per
    // the essential-complexity design note §2: a jump marks irreducible every construct strictly between it
    // and its target, irreducibility propagates outward to the function root (stopping at closure/
    // nested-fn boundaries), and a marked switch head contributes every arm. ev = 1 + Σ marked
    // constructs' own cx decision weights, so ev <= cx is STRUCTURAL, not hoped for. 1 = fully
    // structured (any contiguous region extracts mechanically); >= 2 = some region has a second exit
    // and extract-method on it is a rewrite, not a refactor. A FLOOR (ev_floor=): noreturn CALLS,
    // macro-hidden returns and unresolvable goto targets are invisible to a syntactic walk and can only
    // RAISE the true value — an unrecognised jump marks NOTHING, never speculatively. Strict single-exit
    // McCabe counts a guard clause (§10.1 Option A, the owner's call); evWhy is what keeps that honest —
    // the guard-return share is visible and subtractable per row. Convention note, reconciled against an
    // independent CFG reduction (test/essentialcxcheck.sh header): arm weights mirror cx exactly, so a
    // marked switch whose arms include `default:` charges every arm where a residue's E-N+2 charges
    // arms-1 — the same convention on both sides of ev <= cx, disclosed rather than special-cased.
    // 0 for non-function kinds and for languages evCountedLang excludes (Bash); saturates at 65535 with
    // humps' justification. Emitted iff ev >= 2 (absent on a cx row means EXACTLY 1 — never a bare "1").
    std::uint16_t ev           = 0;
    // evWhy[t] = how many jumps contributed under kEvWhyTagTable[t] (a jump contributes when its
    // strictly-between chain is non-empty — a tail return or an arm-tail break contributes nothing).
    // Saturates at 255 per tag: a def past that is beyond every triage threshold (humps' rule).
    std::array<std::uint8_t, kEvWhyTagCount> evWhy{};
    std::uint16_t params        = 0;   // parameter count from the def's parameter-list child; --metrics params= (NUMBER only — no 7±2)
    std::uint8_t  maxNest       = 0;   // max control-structure nesting depth reached inside the def; --metrics nest=
    std::uint8_t  arityExact    = 0;   // B2.2: 1 ⇒ `params` is a FIXED, call-comparable arity (no variadic / default
                                       // args, and NOT an implicit-`self` method) → a same-name candidate whose
                                       // params ≠ the call-site arg count is provably wrong and may be dropped.
                                       // 0 (default, the SAFE state) ⇒ never arity-filter this def. See ingest.cpp.
    std::string   name;                // final identifier segment
    std::string   scope;               // enclosing class/namespace name (C++), for canonical scope::name resolution; "" if none
};

// SoA-minded tripwire: keep Symbol tight (smallest types, grouped) so the symbols[] array stays cache-dense.
// Two std::string members dominate; the scalars pack into what their alignment leaves. If this fires after a
// field add, re-check you used the smallest type and grouped it — don't just bump N (a size regression is a
// real signal here). libc++/libstdc++ std::string is 24 B (3 words); adjust N per-toolchain if it ever differs.
// `locals` (Phase 1 local-variable-indexing, PLAN.md 2026-08-06 evening) added as a uint32_t grouped with
// the other Q4 size-smell scalars, right before `loc`/`params`/`maxNest`/`arityExact` — measured (not
// assumed): sizeof(Symbol) is UNCHANGED at 48 + 2*sizeof(std::string). The scalar run before the two
// std::string members already carried 4 B of trailing alignment padding (std::string needs 8-B alignment
// on a 64-bit ABI); the new uint32_t landed in that padding for FREE — the best possible SoA outcome, not
// a coincidence worth losing: re-measure with a fresh `static_assert` fire (don't hand-arithmetic) if this
// ever needs to change again. `ppAlt` (uint16_t, ppalt disclosure) could NOT repeat the trick — `locals`
// had consumed the tail padding entirely (this assert fired 104 == 96 on that placement) — so it sits in
// the struct's one remaining hole instead, the 2 pad bytes between `lang` and `fileId` up top; sizeof
// unchanged, measured by this assert, not hand-arithmetic.
//
// `humps`/`deepLoc` (the nesting-depth profile) then cost the first real growth: 48 → 56 + 2*string,
// MEASURED with a standalone sizeof probe after this assert fired, not derived on paper. The step is
// unavoidable rather than sloppy — `locals` had spent the last of the trailing padding, so the scalar run
// ended exactly on an 8-B boundary, and Symbol's alignment is 8 (the std::string members), so ANY further
// field rounds the object up by a full 8 B no matter how small its type. Two uint16_t is therefore not a
// compromise but the whole point: it spends 4 B of that unavoidable 8 and leaves 4 B of live padding for
// the NEXT field to land in free, exactly as `locals` did. A smaller type here would buy nothing and cost
// range (both saturate at 65535 — see the fields' own comment); a uint32_t pair would have cost 16.
//
// `ev`/`evWhy` (essential complexity) then cost the second step: 56 -> 64 + 2*string, MEASURED with the
// standalone sizeof probe after this assert fired (the design predicted UNCHANGED because it budgeted the
// uint16_t alone; the eight evWhy tag counters are what force the step). The uint16_t ev spends 2 of the
// 4 B of live padding the humps/deepLoc step left; the 8×uint8_t evWhy run then crosses the 8-B boundary
// once (+8), landing with 2 B of live padding for the NEXT field. The alternative — packing evWhy into
// one uint32_t at 4 bits per tag — was rejected because a 4-bit counter saturates at 15, and printing
// "guard-return:15" for a function with 20 guard returns is a wrong count, not a floor (honesty rule #3);
// uint8_t saturating at 255 inherits humps' justification instead.
static_assert( sizeof( Symbol ) == 64 + 2 * sizeof( std::string ),
               "Symbol size changed — verify the new field uses the smallest type + is grouped (SoA); see model.h" );

// local-variable-indexing plan Phase 1 MVP scope (PLAN.md 2026-08-06 evening): C/C++ only — highest
// locals/function ratio in the survey (5-15/fn vs 3:1 Python, 0.2-0.8 Go/Rust) and `locals` is threaded
// through ingest.cpp's ALREADY C-family-only large-function/deep-nesting complexity walk, so this extends
// shipped code rather than building a new cross-language subsystem. ObjC/ObjC++ is a named fast-follow
// (ObjC's declaration-statement grammar differs enough to want its own fixture pass), not MVP. ANY caller
// that needs to know whether `locals`/`locals_floor` can be trusted for a given Symbol — serialize.h's
// --metrics emitter, naminglens.h's Phase-2 local-name walk gate — MUST route through this ONE predicate,
// so the covered-language set can never drift between the two call sites.
inline bool localsCountedLang( Lang lang ) noexcept
{
    return lang == Lang::Cpp || lang == Lang::C;
}

// Essential-complexity coverage: 15 of 16 languages — every code language EXCEPT Bash
// (the essential-complexity design note, §3.2.8: `break N`/`continue N` take a numeric level count, `exit` and
// `trap` are process-level, and function boundaries are weak — not worth a wrong number). Markdown/Json/
// Unknown never carry a cx row, so listing them here would be vacuous either way. ANY consumer asking
// whether Symbol::ev/evWhy can be trusted for a def — serialize.h's two emitters, ensemble.h's
// annotation — MUST route through this ONE predicate, for localsCountedLang's reason: the covered set
// must never drift between the emitter and any future consumer.
inline bool evCountedLang( Lang lang ) noexcept
{
    return    lang == Lang::Cpp  || lang == Lang::C     || lang == Lang::ObjC || lang == Lang::Python
           || lang == Lang::TypeScript || lang == Lang::JavaScript || lang == Lang::Go || lang == Lang::Rust
           || lang == Lang::Swift || lang == Lang::Java || lang == Lang::Ruby || lang == Lang::CSharp;
}

// local-variable-indexing plan Phase 2 (PLAN.md 2026-08-06 evening): one CAPTURED local-variable NAME,
// from the on-demand re-parse ingest.cpp's collectGatedLocalNames runs ONLY for a function that already
// cleared BOTH the existing size/complexity gate AND locals>=kNamingLocalsGateFloor (naminglens.h) — never
// promoted to a Symbol/NodeId, never entering the call graph, never cached (recomputed fresh every time a
// caller asks, since asking is rare by construction). `name` is OWNED (not the plan's literal
// "non-owning string_view"): the file bytes the re-parse reads live only as long as naminglens.h's local
// getBytes() cache for ONE lint pass, so a view into them would dangle the moment that pass's caller
// tries to hold a LocalNameFact any longer — a real lifetime constraint the plan's wording didn't have in
// view (its own self-correcting "Grounding note" already flagged that its citations needed a refresh
// pass; this is the same class of correction). `declDepth`: 1 = a direct statement in the function's OWN
// outermost block; 2+ = at least one control-structure block deeper — see checkLocalNameShape's own
// declDepth>=2 gate on naming-short.
struct LocalNameFact
{
    std::string   name;
    std::uint32_t line      = 0;   // 1-based, absolute file line (not the re-parsed substring's own row)
    std::uint8_t  declDepth = 0;
};

// An unresolved reference (call/usage). Resolved into an edge in the graph stage.
struct Reference
{
    NodeId        fromSymbol = kNoNode;   // enclosing symbol (caller); kNoNode if file-scope
    std::uint32_t fileId     = 0;
    std::uint32_t line       = 0;         // 1-based line of the use site (ABS-3: for `--uses` p="file:line")
    Lang          lang       = Lang::Unknown;
    bool          isInherit  = false;     // true ⇒ a base-class/implements edge (derived → base), not a call
    bool          isDocLink  = false;     // true ⇒ a doc→code mention (backtick `ident` in markdown), not a call
    bool          isCompose  = false;     // true ⇒ a HAS-A member-variable type edge (S5-E); NEVER enters call graph / PageRank
    RefRole       role       = RefRole::Call;   // ABS-3 use-site role (call/read/write/import/extends); see RefRole.
                                                //   Only Call enters the call graph; the rest power --uses only.
    RecvKind      recv       = RecvKind::None;  // call-site receiver shape (P2-D narrowing); see RecvKind
    std::uint16_t argCount   = 0;         // B2.2: number of positional args at the call site when countable; 0 otherwise
    bool          argCountKnown = false;  // B2.2: true ⇒ the call-site argument list was reliably counted (no spread /
                                          //   splat / apply) → arity-filter candidates against argCount; false ⇒ never filter
    std::string   calleeName;             // referenced name (final identifier segment)
    std::string   qualifier;              // explicit scope at the call site (`A` in `A::b()`); "" if bare/method — for canonical resolve
    std::string   recvVar;                // receiver variable identifier when recv==NamedVar (`x` in `x->m()`); "" otherwise — for Rule 2
    std::string   fieldName;              // member variable name when isCompose (e.g. "m_pool"); "" otherwise
    std::string   composeRel;             // "creates" (value/inline) or "uses" (reference/pointer) when isCompose; "" otherwise
};

// A physical dependency: one #include / import directive (file → target). The target is the raw
// include path / module name (resolved to a file id later, for the file→file dependency graph).
struct Include
{
    std::uint32_t fileId  = 0;      // the including file
    bool          isAngle = false;  // C/C++/ObjC: true ⇒ angle include `<x.h>` (external, unresolvable
                                    //   without a build system); false ⇒ quote include `"x.h"` (resolved
                                    //   relative-to-includer) OR a non-C import. Path-precise resolution
                                    //   (resolve.h::resolvePreciseInclude) uses this to leave angle
                                    //   includes UNRESOLVED rather than basename-matching them.
    std::string   target;           // raw include path ("foo.h", <vector>) or module name
};

// P2-D Rule 2 LOCAL-VARIABLE TYPE BINDING (`var : typeName`) captured at ingest. One record per
// `Foo x;` / `Foo* x;` / `auto x = Foo()` / `x = Foo()` (C++) or `x = Foo()` (Python) inside a function
// body — the variable→type fact that lets resolve.h narrow a later `x.m()` / `x->m()` to `typeName::m`.
// Attributed to its enclosing definition (the function the binding lives in) by byte-span containment,
// exactly like a Reference, so the scope of a binding is the same scope a call's recvVar is looked up in.
// CONSERVATIVE: only an UNAMBIGUOUS binding narrows — buildGraph drops `(fromSymbol, var)` if the same var
// is bound to two DIFFERENT types in one scope (a reassignment to another type), so a wrong narrow is
// impossible. typeName is the WRITTEN type's final segment (`A::Foo` → `Foo`), matched against class names.
struct Binding
{
    NodeId        fromSymbol = kNoNode;   // enclosing function/method (the binding's scope); kNoNode if file-scope
    std::uint32_t fileId     = 0;
    std::string   var;                    // the declared variable identifier (`x`)
    std::string   typeName;               // the written type's final segment (`Foo`) — resolved to a class in buildGraph
};

// R5 cross-language FFI binding alias. A language-binding DECLARATION found in a C/C++ file (or a
// ctypes-handle assignment in a Python file) that makes a C/C++ definition reachable under a DIFFERENT
// language's name — so the call graph stops truncating at the language border. Captured PURELY
// syntactically at ingest; buildGraph turns each into a provenance-tagged FALLBACK alias edge, consulted
// ONLY when the normal langCompatible ladder drops a call (so a same-language local def ALWAYS wins).
//   Pybind       — `m.def("alias", &Scope::target)` / `.def("alias", &target)`: aliasName is the
//                  Python-visible name, targetName/targetScope the bound C++ symbol. Sound (explicit).
//   ExternC      — a function declared inside `extern "C"`: aliasName==targetName==the C symbol name,
//                  reachable from ctypes/cffi/cgo by that bare name. LOW-confidence (name-pattern).
//   CtypesHandle — a Python `lib = CDLL(...)`/`ctypes.CDLL(...)`/`cdll.LoadLibrary(...)`/`ffi.dlopen(...)`:
//                  aliasName is the handle VARIABLE; it gates ExternC resolution of a `lib.foo()` call so
//                  a bare `x.foo()` never manufactures an FFI edge. (Not itself an alias edge.)
//   Jni          — decoded in buildGraph from a `Java_pkg_Cls_method` def name (no ingest capture); not
//                  stored here.
enum class BindKind : std::uint8_t { Pybind, ExternC, CtypesHandle };

struct BindingAlias
{
    std::uint32_t fileId  = 0;                  // the file the binding declaration lives in (restamped on cache load)
    BindKind      kind    = BindKind::Pybind;
    bool          lowConf = false;              // a name-pattern guess (ExternC/ctypes) → honesty flag on the edge
    std::string   aliasName;                    // foreign-visible name (pybind "name"); or the ctypes handle var
    std::string   targetName;                   // C/C++ symbol final-segment name (`cpp_fn`, `method`); "" for CtypesHandle
    std::string   targetScope;                  // C/C++ symbol scope (`T` for `&T::method`); "" if none
};

// S5-E HAS-A composition edge (owner class → member type): one record per member-variable
// declaration whose type resolved to a known class/struct. Stored OUTSIDE the call graph so
// PageRank, ranks, and the default map are UNCHANGED. Emitted only in --for and --around.
struct ComposeEdge
{
    NodeId      ownerSym  = kNoNode;   // the enclosing class symbol (fromSymbol of the RawRef)
    NodeId      typeSym   = kNoNode;   // the member type symbol (resolved by name, any-file)
    std::string fieldName;             // the member variable name (e.g. "m_pool")
    std::string typeName;              // the type name as written (e.g. "SpherePool")
    std::string ownerName;             // the owner class name (redundant but handy for serializer)
    std::string rel;                   // "creates" (value) or "uses" (reference/pointer)
};

// B6.3 HTTP-route cross-service edge kind. A route DEF is a server-side registration (Express/Fastify
// `app.get('/path', handler)`, FastAPI/Flask `@app.get("/path") def handler(): ...`); a route USE is a
// client-side call (`fetch('/path')`, `axios.get('/path')`, `requests.get('/path')`). Both are captured
// PURELY syntactically at ingest (table-driven, see ingest.cpp captureRoutes) — same posture as
// BindingAlias above: names/paths are recorded here, resolved to NodeIds later in buildGraph (graph.h),
// which matches USE→DEF by (method, path) and stores the synthesized result OUTSIDE the call graph
// (Graph::routeEdges) so PageRank and the default map are byte-identical on any route-free corpus.
// Cross-root matching is INTENTIONAL: a (method,path) match between a client
// root and a server root IS explicit evidence, unlike a bare same-name guess.
enum class HttpMethod : std::uint8_t { Get, Post, Put, Patch, Delete, Unknown };

// ordinal-indexed table (declaration order MUST track the enum above) — the `method=` XML attribute.
// Unknown ⇒ "" (omitted attribute value, matches EITHER side per routematch::methodsCompatible).
inline constexpr const char* kHttpMethodTagTable[] = { "GET", "POST", "PUT", "PATCH", "DELETE", "" };

inline const char* httpMethodTag( HttpMethod m ) noexcept
{
    const auto idx = static_cast<std::size_t>( m );
    return idx < ( sizeof( kHttpMethodTagTable ) / sizeof( kHttpMethodTagTable[0] ) ) ? kHttpMethodTagTable[ idx ] : "";
}

// declarative name→method table (house style: table over switch), shared by every detector: Python
// decorator attribute names (`app.get`), JS/TS registrar + axios methods (`app.post`/`axios.post`), and
// Python `requests.VERB`. httpMethodFromName (graph-independent, pure) lives beside it.
inline constexpr struct { const char* name; HttpMethod method; } kHttpMethodTable[] = {
    { "get",    HttpMethod::Get    },
    { "post",   HttpMethod::Post   },
    { "put",    HttpMethod::Put    },
    { "patch",  HttpMethod::Patch  },
    { "delete", HttpMethod::Delete },
};

inline HttpMethod httpMethodFromName( std::string_view name ) noexcept
{
    for( const auto& e : kHttpMethodTable )
    {
        if( name == e.name )
        {
            return e.method;
        }
    }
    return HttpMethod::Unknown;
}

struct RouteDef      // server-side route registration — one record per recognized app.VERB(...)/@app.VERB(...)
{
    std::uint32_t fileId      = 0;                  // restamped on cache load, like BindingAlias.fileId
    std::uint32_t line        = 0;                   // 1-based, the registration/decorator line
    HttpMethod    method      = HttpMethod::Unknown;
    std::string   path;                              // AS WRITTEN — template segments verbatim ("/users/{id}", "/users/:id")
    std::string   handlerName;                       // final identifier segment of the handler; "" ⇒ inline/anonymous
                                                      // (unresolved — buildGraph can never attach an edge to it)
};

struct RouteUse       // client-side HTTP call — one record per recognized fetch/axios/requests call
{
    std::uint32_t fileId      = 0;
    std::uint32_t line        = 0;
    NodeId        fromSymbol  = kNoNode;             // enclosing function/method making the call; kNoNode if file-scope
    HttpMethod    method      = HttpMethod::Unknown;
    std::string   path;
};

// B6.3 synthesized route USE→DEF edge — OUTSIDE the call graph (PageRank/default map unchanged, exactly
// like ComposeEdge above). Populated in buildGraph (graph.h) by matching RouteUse against RouteDef on
// (method, path); emitted only via serialize.h::packRoutes (--for / --around), gated on non-empty so a
// route-free corpus stays byte-identical to pre-B6.3 output.
struct RouteEdge
{
    NodeId        fromSym  = kNoNode;              // the USE's enclosing symbol; kNoNode if file-scope
    NodeId        toSym    = kNoNode;              // the DEF's handler symbol — ALWAYS resolved (unresolved-handler
                                                   // DEFs are excluded before an edge is ever created; see buildGraph)
    HttpMethod    method   = HttpMethod::Unknown;  // the matched DEF's method (concrete when the DEF named one)
    std::string   path;                            // the DEF's path, as written (template form)
    std::string   fromName;                        // redundant, for the serializer (see ComposeEdge precedent); "" if fromSym==kNoNode
    std::string   toName;                          // the handler symbol's name
};

// One otherwise-indexable file the crawl DROPPED for exceeding a size ceiling — the skipped_oversize=
// population, itemized (the count alone said the corpus was truncated without naming what was absent).
// `path` is the CRAWL spelling, the same vocabulary result.files uses, so a row joins the map's p=
// values; the multi-root merge relabels it to `<label>/./<rel>` exactly like files. `limitBytes` is the
// ceiling that dropped the file (--max-file-size's value, or kMaxJsonConfigBytes for the .json lane),
// so sizeBytes > limitBytes is self-evident in the row.
struct SkippedOversize
{
    std::string   path;
    std::uint64_t sizeBytes  = 0;
    std::uint64_t limitBytes = 0;
};

// Output of ingestion. Deterministic: files sorted lexicographically, symbol ids assigned
// in (file, line, name) order so the whole pipeline is reproducible run-to-run.
struct IngestResult
{
    std::vector<std::string> files;

    // §P0.4/§P0.5d: the otherwise-indexable files the crawl DROPPED for exceeding a per-file size
    // ceiling (--max-file-size / kDefaultMaxFileBytes, OR the .json lane's fixed kMaxJsonConfigBytes — §B13.1;
    // the two are mutually exclusive per file, so nothing is counted twice). `--max-file-size=8K` silently
    // dropped ~296 of ~759 files and the header reported files=463 as if that were the corpus. Empty on every
    // default run of a tree with nothing oversized; the header count is surfaced only when non-zero — absent
    // means nothing was skipped. The invariant a reader may rely on: files= + skipped_oversize= = the
    // population the crawl considered, at EVERY --max-file-size setting. The header emits size() as
    // skipped_oversize=; --skipped itemizes the rows (one source, never two counters). Sorted by path.
    std::vector<SkippedOversize> skippedOversize;

    std::vector<Symbol>      symbols;      // definitions
    std::vector<Reference>   references;   // unresolved calls
    std::vector<Include>     includes;     // #include / import directives (physical dependencies)
    std::vector<Binding>     bindings;     // P2-D Rule 2: local var→type bindings (`Foo x;`), for receiver-var narrowing
    std::vector<BindingAlias> bindingAliases;  // R5: cross-language FFI binding declarations (pybind/extern-C/ctypes)
    std::vector<RouteDef>    routeDefs;     // B6.3: HTTP server-side route registrations (unresolved handler names)
    std::vector<RouteUse>    routeUses;     // B6.3: HTTP client-side calls (fromSymbol resolved by byte-span, like Reference)

    // Doc-ingest override (P1-B): for a document file (notebook/html/csv/…) this holds its EXTRACTED text,
    // keyed by fileId. lexical.h / recall.h index + emit this instead of the raw bytes, so a notebook is
    // retrieved by its prose, not its JSON. Empty for code/markdown files (they read straight from disk).
    HashMap<std::uint32_t, std::string> docText;

    // ── B0.2 persisted subtoken statistics (lexindex.h; RICH ingests only — hasLexStats gates use).
    //    Per-symbol CSR over (subtokenHash, weighted tf) pairs for the doc-comment+body BM25F fields,
    //    plus each symbol's weighted doc/body token count and a per-file 512-bit pre-filter signature
    //    (B0.1). Built at parse time / restored from the rich cache, in symbol-id order → deterministic.
    //    lexical.h Pass 2 consumes these instead of re-reading + re-tokenizing every file per query;
    //    when hasLexStats is false (lean ingest, multi-root merge, stub) the scan path runs unchanged.
    bool                       hasLexStats = false;
    std::vector<std::uint32_t> lexTokenRowOffsets;   // size symbols.size()+1 — CSR row bounds (32-bit ids)
    std::vector<std::uint64_t> lexTokenHashes;       // sorted ascending within each symbol's row
    std::vector<std::uint32_t> lexTokenTfs;          // weighted tf, parallel to lexTokenHashes
    std::vector<std::uint32_t> lexDocBodyDl;         // size symbols.size() — weighted doc+body token count
    std::vector<std::uint64_t> lexFileSig;           // size files.size()×kLexFileSigWords — B0.1 file Bloom

    // ── Multi-root workspace identity — ALL EMPTY on a single-root run (the
    //    byte-identity quarantine: every consumer guards on emptiness). Populated ONLY by
    //    workspace.h::mergeWorkspaceIngests when 2+ roots survive dedupe. When populated, ing.files hold
    //    the LABELED spelling `<label>/<root-relative-path>` (the identity every surface emits) and
    //    realPaths hold the on-disk crawl spelling (what any fopen/stat must use — see diskPath below).
    std::vector<std::string>   realPaths;    // fileId → on-disk path (empty ⇒ ing.files ARE the disk paths)
    std::vector<std::uint32_t> fileRoot;     // fileId → root index (canonical label order)
    std::vector<std::string>   rootLabels;   // root index → label (shortest unique whole-segment suffix)
    std::vector<std::string>   rootPaths;    // root index → the root path as passed (post-dedupe)
    std::vector<std::string>   rootReals;    // root index → realpath (cross-root include probes, git -C)
};

// multi-root workspace cap: a sane bound on N crawl roots — an agent joining a
// handful of checkouts is the use case; hundreds of roots is a mis-glued path list, refused loudly.
inline constexpr std::size_t kMaxWorkspaceRoots = 16;

// The ONE disk-path seam: every file read/stat must go through this instead of ing.files[fileId] directly.
// Single-root (realPaths empty): returns ing.files[fileId] — byte-identical behavior, zero cost.
// Multi-root: returns the on-disk spelling behind the labeled identity path.
inline const std::string& diskPath( const IngestResult& ing, std::uint32_t fileId ) noexcept
{
    return ing.realPaths.empty() ? ing.files[ fileId ] : ing.realPaths[ fileId ];
}

// The macro-edges round's honesty post-pass: a call-SHAPED reference (bare name, no receiver, no explicit
// qualifier) whose name is defined by an indexed C-family `#define` is re-tagged RefRole::Macro, so no
// surface can ever label an expansion role="call". Runs over the ASSEMBLED corpus — a per-file parse (and
// therefore the per-file cache record, which stores role=Call) cannot know another file's #defines — at
// BOTH ingest exits: the end of ingest() and the end of mergeWorkspaceIngests (a macro defined in one root,
// invoked from another). Idempotent and deterministic (one ordered pass, membership in a name set built
// from ing.symbols in id order). Restricted to C-family on BOTH sides: only C-family grammars have
// `#define`, and a same-named Python/JS call must not inherit a macro tag it cannot mean.
inline bool macroRefLang( Lang lang ) noexcept
{
    switch( lang )
    {
        case Lang::Cpp:
        case Lang::C:
        case Lang::ObjC:
        {
            return true;   // the grammars that have `#define` (ingest.cpp constCaptureNeedsScreamingGate's shape)
        }
        default:
        {
            return false;
        }
    }
}

inline void retagMacroCallReferences( IngestResult& ing )
{
    HashMap<std::string, char> macroNames;
    for( const Symbol& s : ing.symbols )
    {
        if( s.kind == SymKind::Macro && macroRefLang( s.lang ) )
        {
            macroNames.emplace( s.name, 1 );
        }
    }
    if( macroNames.empty() )
    {
        return;   // macro-free corpus: byte-identical output, zero cost beyond the symbol scan
    }
    for( Reference& r : ing.references )
    {
        if( r.role != RefRole::Call || r.isInherit || r.isDocLink || r.isCompose )
        {
            continue;
        }
        if( r.recv != RecvKind::None || !r.qualifier.empty() || !macroRefLang( r.lang ) )
        {
            continue;   // a receiver-qualified or scope-qualified call cannot be a macro invocation
        }
        if( macroNames.contains( r.calleeName ) )
        {
            r.role = RefRole::Macro;
        }
    }
}

// THE per-file symbol index every span- or line-based lookup starts from: bucket the symbol ids by file, then
// sort each bucket. `keep` selects which symbols enter it and `less` orders each bucket, because those two are
// the ONLY things that differ between callers — flipimpact.h wants every symbol in line order (the host of a
// `#if` region), ensemble.h wants only body-carrying functions in byte order (the owner of a lint finding's
// span). Both were written independently and a --quality-delta pass found them as a 159-token clone pair,
// correctly: same shape, different filter and key. Parameterizing exactly those two is what makes this ONE
// function rather than a family of near-copies, and it lives here because `IngestResult` does.
// Deterministic by construction: the caller's `less` must be a total order (both current ones tie-break on a
// unique per-symbol field), and file buckets are indexed, never hashed.
template<typename Keep, typename Less>
inline std::vector<std::vector<NodeId>> symbolsByFile( const IngestResult& ing, Keep keep, Less less )
{
    std::vector<std::vector<NodeId>> byFile( ing.files.size() );
    for( const Symbol& s : ing.symbols )
    {
        if( s.fileId < byFile.size() && keep( s ) )
        {
            byFile[ s.fileId ].push_back( s.id );
        }
    }
    for( std::vector<NodeId>& bucket : byFile )
    {
        std::sort( bucket.begin(), bucket.end(), less );
    }
    return byFile;
}

}   // namespace rw
