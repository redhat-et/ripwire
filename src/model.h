#pragma once

// model.h — the shared data model for ripwire: the contract between INGEST (tree-sitter)
// and the GRAPH / RANK / SERIALIZE stages. POD/DOD, ids not pointers, dense indices.
//
// Flow:  ingest() → IngestResult { files, symbols(defs), references(unresolved calls) }
//        → graph: resolve references to symbol ids, build the in-edge CSR + wOutDeg
//        → rank:  personalized PageRank over the CSR
//        → serialize: top-K symbols (by rank) → minified XML, grouped by file.

#include "smallvec.h"   // rw::SmallVec — THE ONE ALIAS; the per-key span lists and per-file id buckets below

#include <algorithm>   // std::sort — symbolsByFile below
#include <tuple>       // std::tie — lessUnindexedExt's mixed-direction compare
#include <array>       // Symbol::evWhy — the fixed-size ev_why tag counters
#include <cstdint>
#include <string>
#include <type_traits>   // std::is_trivially_copyable_v — the VarSpan layout pin below
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
// Toml is appended AFTER C for the SAME reason a FOURTH time: index 16 clamps into the identical
// Unknown-bucket headroom in serialize.h, zero renumbering of Cpp..C. Like Json it is a pure-data
// language — lang-incompatible with everything but itself, zero references, zero call edges.
// Yaml is appended AFTER Toml for the SAME reason a FIFTH time: index 17 clamps into the identical
// Unknown-bucket headroom in serialize.h, zero renumbering of Cpp..Toml. The third pure-data lane.
enum class Lang : std::uint8_t { Cpp, Python, TypeScript, Go, Rust, Swift, ObjC, Markdown, JavaScript, Bash, Java, Ruby, Unknown, Json, CSharp, C, Toml, Yaml };

// short lang label — the terse XML/JSON attribute (lang="cpp|py|ts|go|rs|swift|objc|js|sh|java|rb|md|json|cs|c|toml|yaml").
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
        case Lang::Toml:       return "toml";
        case Lang::Yaml:       return "yaml";
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
// Smallest int that fits (≤ 7 roles) → SoA-friendly. The role is ORTHOGONAL to the call graph: only
// Call refs become PageRank edges; Read/Write/Import/Extends/Type are recorded for the use-site index and
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
//   Type    — the name is a bare TYPE mention: SYM named as a type in a signature, a declaration or a template
//             argument (`Widget makeOne( Widget in )`, `std::vector<Widget>`, `const Widget* p`). Joins the
//             NEVER-in-the-CSR list above — a type mention is a dependency, not a call, so it must not touch
//             PageRank or the default ranked map. Before this role existed a type-ONLY dependent was invisible
//             to the whole use-site index: `--uses=IngestResult` reported 0 against 438 real mentions across
//             68 files, so the most-depended-upon data structure in this repo read as a graph isolate.
//             Distinct from Extends (a base clause) and from isCompose (a member variable's declared type) —
//             those two are SPECIFIC declaration forms and are unchanged; this is the general mention.
enum class RefRole : std::uint8_t { Call, Read, Write, Import, Extends, Macro, Type };
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
        case RefRole::Type:    return "type";
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
    // L8 IN-FILE TEST SCOPE: 1 ⇒ a syntactic in-file test convention encloses (or IS) this def — Rust
    // `#[cfg(test)] mod` / `#[test] fn`, Python `class Test*` / a module-level `def test_*`, a JS/TS
    // helper inside `describe(`/`it(`/`test(`, a C# `[Fact]`/`[Test]`/`[TestMethod]` member. Computed at
    // extraction by ingest.cpp::inFileTestScope (see its banner for what each rule deliberately does NOT
    // cover) and rides the per-file cache record, so kParserVer gates it like any other extracted fact.
    // 0 (the SAFE state) means "no in-file convention found", NEVER "this is production": the path
    // signal is the other half, and filter.h::isTestSymbol is the ONE predicate that ORs them — every
    // symbol-keyed consumer of the test partition must route through it so the two halves cannot drift.
    std::uint8_t  testScope     = 0;
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

// Essential-complexity coverage: 15 of 18 languages — every code language EXCEPT Bash
// (the essential-complexity design note, §3.2.8: `break N`/`continue N` take a numeric level count, `exit` and
// `trap` are process-level, and function boundaries are weak — not worth a wrong number). Markdown/Json/Toml/
// Yaml/Unknown never carry a cx row, so listing them here would be vacuous either way. ANY consumer asking
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
    std::uint32_t startByte  = 0;         // byte offset of the use site (RawRef's own, carried through for the
                                          //   block-span containment test in suppressShadowedReferences)
    Lang          lang       = Lang::Unknown;
    bool          isInherit  = false;     // true ⇒ a base-class/implements edge (derived → base), not a call
    bool          isDocLink  = false;     // true ⇒ a doc→code mention (backtick `ident` in markdown), not a call
    bool          isCompose  = false;     // true ⇒ a HAS-A member-variable type edge (S5-E); NEVER enters call graph / PageRank
    RefRole       role       = RefRole::Call;   // ABS-3 use-site role (call/read/write/import/extends/type); see RefRole.
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
//
// L3 var→FUNCTION extension (fn-pointer/callback bindings): the SAME record shape also carries
// `var = &foo` / `H h = someFunc` / `cb = <lambda>` facts, discriminated by `kind`, so a later call-shaped
// `fn()` can resolve to the bound function. Rule 2's exact capture discipline and tombstone semantics apply:
// a var assigned two DIFFERENT functions in one scope resolves to NOTHING (buildGraph tombstones it), and a
// var with ANY fn binding never falls back to the bare-name ladder (the binding proves the call goes through
// the variable, so a same-named global function would be a FALSE edge). Two sentinels ride typeName:
//   kFnBindLambdaTarget  — the RHS was a lambda: the binding EXISTS (blocks the name ladder, participates in
//                          tombstoning) but resolves to nothing extra — the lambda body is already attributed
//                          to the enclosing function.
//   kFnBindClobberTarget — an assignment whose RHS is NOT a recognizable single function (`fn = getHandler()`,
//                          `fn = nullptr`): forces the tombstone, so a stale earlier binding can never win.
enum class LocalBindKind : std::uint8_t
{
    Type,      // P2-D Rule 2: `var : typeName` (receiver-var narrowing fuel)
    FnDecl,    // L3: a DECLARATION binding `void (*fn)() = &foo;` / `H h = foo;` / `auto cb = [](){...};`
    FnAssign,  // L3: an ASSIGNMENT binding `fn = &foo;` (may target a FILE-scope var, so it also clobbers
               //     a same-named file-scope entry with a different target — see buildGraph's pass 2)
    VarDecl,   // r9 shadow suppression: a DECLARED variable NAME whose type Rule 2 could not (or need not)
               //     resolve (`int run = 0;`, a parameter, a range-for var) — typeName stays EMPTY. Evidence
               //     for suppressShadowedReferences below, NOTHING else: buildGraph's Rule-2 tables skip it
               //     (kind != Type) and the L3 fn tables skip it (typeName empty). APPENDED so no persisted
               //     kind value renumbers (RawBind rides kind through the cache as a u8).
};

inline constexpr const char* kFnBindLambdaTarget  = "(lambda)";    // parens are illegal in identifiers, so
inline constexpr const char* kFnBindClobberTarget = "(unknown)";   //   neither sentinel can match a real def

struct Binding
{
    NodeId        fromSymbol = kNoNode;   // enclosing function/method (the binding's scope); kNoNode if file-scope
    std::uint32_t fileId     = 0;
    LocalBindKind kind       = LocalBindKind::Type;
    std::uint32_t spanStart  = 0;         // kind==VarDecl only: the byte span the name shadows within — a block
    std::uint32_t spanEnd    = 0;         //   declaration runs from its DECLARATION POINT (end of the complete
                                          //   declarator, [basic.scope.pdecl]) to the block's end; a whole-scope
                                          //   shape (parameters, captures, range-for and control-statement header
                                          //   declarations) from its scope's start. See suppressShadowedReferences.
                                          //   {0,0} on every other kind and on a scope-less capture (contains nothing).
    std::string   var;                    // the declared variable identifier (`x`)
    std::string   typeName;               // kind==Type: the written type's final segment (`Foo`), resolved to a
                                          //   class in buildGraph. kind==FnDecl/FnAssign: the bound FUNCTION
                                          //   name as written minus `&` (`alpha`, `ns::alpha`), or a sentinel.
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

// §L1 — THE SKIP TAXONOMY. `oversize` above was the only drop reason the tool could NAME, so every
// other way a file left the corpus read as "nothing was dropped": --skipped reported oversize="0" on a
// tree where the crawl had passed over thousands of files, which is the honesty contract's own failure
// mode (a zero that means "none exists" rather than "none found"). These two classes complete it.
//
// `excluded` — matched a --exclude substring while carrying an INDEXABLE extension. Only files the walk
// actually enumerated appear: an --exclude that prunes a whole DIRECTORY stops the walk at the directory,
// so its contents are never seen and CANNOT be listed. Those prunes are counted separately
// (excludedDirs) and the verb says out loud that the file count under them is unknown, not zero.
//
// `unsupported` — a source/text-looking extension with no grammar and no doc handler. This is the class
// that hides a whole LANGUAGE: on facebook/infer (11 923 files, ~60% OCaml) the map header gave no
// indication that the repo's primary language contributed nothing to it.
struct SkippedFile
{
    std::string   path;
    std::uint64_t sizeBytes = 0;
    std::string   ext;        // lowercased, leading '.'; "" when the name carries no extension
};

// One unindexed extension and how many files wore it — the header's `unindexed=` roll-up, itemized.
struct UnindexedExt
{
    std::string   ext;
    std::uint64_t files = 0;
};

// The ONE ordering `unindexed=` is emitted in — most files first, extension name as the tiebreak. Shared
// (not re-spelled at each sort site) because it rides the DEFAULT map header from two different producers:
// the single-root crawl, and the multi-root merge that unions their histograms. An order that differed
// between those two, or that depended on hash-map iteration, would be a determinism bug.
inline bool lessUnindexedExt( const UnindexedExt& a, const UnindexedExt& b ) noexcept
{
    // MIXED-DIRECTION sort via one swapped std::tie: `files` compares with the operands reversed (so the
    // LARGER count sorts first) while `ext` compares in normal order (so the smaller name breaks the tie).
    // Written this way rather than as the two-branch comparator it replaces because that shape is one the
    // clone lens groups with every other two-field comparator in the tree — this tree already holds several.
    return std::tie( b.files, a.ext ) < std::tie( a.files, b.ext );
}

// The non-oversize crawl disclosures. Row vectors are CAPPED (kMaxSkipRowsPerClass) so a tree with a
// million unindexed files cannot be a memory hazard; the counts beside them are EXACT and the cap is
// disclosed on the emitted row set, never silent.
// Deliberately NOT merged into IngestResult::skippedOversize: that vector's SIZE is the map header's
// skipped_oversize= count, and one accounting number must keep one meaning (the "one source, never two
// counters" rule above).
struct CrawlSkips
{
    std::vector<SkippedFile>  excluded;             // capped rows, path-sorted
    std::vector<SkippedFile>  unsupported;          // capped rows, path-sorted
    std::uint64_t             excludedFiles   = 0;  // EXACT count (rows may be fewer)
    std::uint64_t             unsupportedFiles = 0; // EXACT count (rows may be fewer)
    std::uint64_t             excludedDirs    = 0;  // subtrees pruned by --exclude: contents NEVER enumerated
    // Subtrees pruned by BUILT-IN POLICY, not by anything the caller asked for: the committed denylist
    // (ingest.h kCrawlSkipDirs — node_modules/.git/build/…) and the CMakeCache.txt build-output sentinel.
    // Kept apart from excludedDirs on purpose. Both classes stop the walk at the directory, so both leave
    // the contents UNKNOWN rather than zero — but a reader debugging "why is my tree not in the map"
    // needs to tell "this build always skips that" from "you asked me to skip that", and one counter
    // cannot say both. Before this existed, all three prune paths converged on
    // disable_recursion_pending() and only the --exclude one incremented anything, so `--skipped` over a
    // tree with node_modules/ reported EVERY counter zero while whole subtrees had been dropped.
    std::uint64_t             prunedDirs      = 0;
    std::vector<UnindexedExt> unindexedExts;        // EXACT histogram, sorted files desc then ext asc
};

// §L1 — PARSE HEALTH: a per-indexed-file record of how much of the file the parser actually understood,
// and whether the file looks machine-written. Both classes are DISCLOSURE ONLY — the file stays indexed
// and every symbol it contributed stays in the map. The point is that a reader can tell the difference
// between "no symbols here" and "symbols we cannot vouch for".
//
// errNodes/errBytes are a PARSER-STATE fact, never a syntax verdict: tree-sitter error recovery fires on
// a valid file written in a dialect the vendored grammar predates just as it fires on a truncated one, and
// a reader needs to be told about BOTH. Hence the label "degraded-parse", not "invalid syntax".
//
// fileBytes == 0 is the NOT-MEASURED sentinel (an indexed file always has a size): the ingest never
// parsed that file — a doc-format file handled by the doc post-pass, a file the binary sniff or a nesting
// guard refused, or a read failure. The verb reports those as a separate count, never as zero findings.
// The doc post-pass is deliberately left on that side of the line: a notebook's EXTRACTED prose has no
// tree-sitter parse that could be degraded, and inventing a clean reading for it would be exactly the
// guess this lane exists to remove.
// Round-trips the incremental cache (ingest.cpp kCacheVersion 13): the auto-cache is the DEFAULT path, and
// a disclosure that evaporates on the warm run is worse than none.
struct FileHealth
{
    std::uint32_t errNodes  = 0;   // ERROR + MISSING nodes in the file's parse tree
    std::uint32_t errBytes  = 0;   // bytes covered by the TOP-MOST ERROR nodes (MISSING is zero-width)
    std::uint32_t fileBytes = 0;   // the parsed byte length; 0 ⇒ NOT MEASURED (see above)
    std::uint32_t wsBytes   = 0;   // whitespace bytes in the leading min(fileBytes, 4096) sample
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

    CrawlSkips              crawlSkips;   // §L1 skip taxonomy + unindexed-ext histogram — see CrawlSkips
    std::vector<FileHealth> fileHealth;   // §L1 parse health, parallel to `files` — see FileHealth

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

    // ── P1-15: how many files this run actually RE-EXTRACTED (cache miss / changed / new) rather than
    //    reusing from the content-hash cache — the number RIPWIRE_CACHE_STATS has always printed as
    //    `reparsed=`, promoted to a field so the MCP server can disclose an incremental pass's cost
    //    (`_reingest`) without the caller re-running the binary under an env observable. PROCESS HISTORY,
    //    not tree state: a cold run re-extracts everything and a warm one re-extracts the drift, so nothing
    //    that must be byte-identical warm-vs-cold may fold it in. Multi-root: the merge sums the per-root
    //    values, so one number describes the whole pass.
    std::size_t                reparsedFiles = 0;
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
// qualifier) whose name UNIQUELY names an indexed C-family `#define` (see the uniqueness guard in the
// function body) is re-tagged RefRole::Macro, so no surface labels such an expansion role="call". Runs
// over the ASSEMBLED corpus — a per-file parse (and
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

// The UNIQUENESS GUARD's evidence (verifier collision refutation, round A5 fix): per C-family symbol
// name, bit 1 = an indexed macro def carries it, bit 2 = a NON-macro def (a real function, method, class
// ctor, or a callable var) carries it too. Only a name whose flags are EXACTLY 1 is "uniquely a macro".
struct MacroNameScan
{
    HashMap<std::string, char> flags;
    bool                       anyMacro = false;
};

inline MacroNameScan scanMacroNames( const IngestResult& ing )
{
    MacroNameScan scan;
    for( const Symbol& s : ing.symbols )
    {
        if( macroRefLang( s.lang ) )
        {
            const char bit = ( s.kind == SymKind::Macro ) ? char( 1 ) : char( 2 );
            scan.flags[ s.name ] = char( scan.flags[ s.name ] | bit );
            scan.anyMacro = scan.anyMacro || bit == 1;
        }
    }
    return scan;
}

inline void retagMacroCallReferences( IngestResult& ing )
{
    // UNIQUENESS GUARD (verifier collision refutation, round A5 fix): the retag has NO visibility model —
    // it cannot know whether the #define is in scope at a given call site — so it may only fire when the
    // name is UNIQUELY a macro in the corpus (scanMacroNames above). A name ALSO carried by any non-macro
    // C-family definition is left role="call" and takes the ordinary resolution ladder: a real `check()`
    // in a translation unit with no macro in scope must never be re-labelled because an unrelated
    // `#define check(x)` exists somewhere else. Degrade, never guess — suppression can only under-tag
    // (a plain call is the disclosed floor), never mislabel.
    const MacroNameScan scan = scanMacroNames( ing );
    if( !scan.anyMacro )
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
        const auto it = scan.flags.find( r.calleeName );
        if( it != scan.flags.end() && it->second == 1 )   // uniquely a macro — never a shared name
        {
            r.role = RefRole::Macro;
        }
    }
}

// ── LOCAL-SHADOW SUPPRESSION (r9 loss bucket 2; block-span fix round A5) ─────────────────────────────
// A reference site to name N inside the BLOCK where a LOCAL declaration binds N as a variable is a use of
// the LOCAL, not of any indexed symbol named N — C++ name lookup finds the local for that scope. The
// measured failure is real: a local `int run = 0;` put every `run` read/write inside its function into
// --uses=run (13 false sites on one r9 query), and a callable local could mint a false call edge through
// the bare-name ladder. SCOPE: each VarDecl record carries the byte span the declared name shadows within,
// and only a site whose own byte offset falls INSIDE that span is suppressed — so `{ int run = 0; } run();`
// keeps the genuine post-block call. Two span shapes, because C++ has two:
//   * an ordinary BLOCK declaration runs from its DECLARATION POINT — the end byte of the complete
//     declarator, which is [basic.scope.pdecl] exactly (immediately after the complete declarator and
//     before its initializer; for a structured binding, after its identifier-list) — to the end of the
//     enclosing compound_statement. Iteration 2 started this span at the block's opening BRACE instead,
//     which silently ate a genuine call written ABOVE the local (`key(); int key = 0;`): a recall loss,
//     not the disclosed over-suppression, so the point is now modelled rather than approximated.
//   * a WHOLE-SCOPE shape runs from the start of its scope, because its name is in scope there: a
//     definition's or lambda's parameters and a lambda's captures/init-captures (the body span), a catch
//     parameter (the handler span), a range-for variable (the loop statement), and a control-statement
//     HEADER declaration (that statement — `for (int run = 0; ...)` never reaches past its own loop).
// The residual over-approximation is the disclosed floor of emitShadowVarDecls, not of the span: a
// declarator shape it refuses (the most-vexing `std::string key( tok );`) records no evidence at all.
// Three further guards keep this suppression-only, never a mislabel:
//   * evidence is a VarDecl binding — a DECLARATION's variable name (ingest captureBindings). An
//     assignment-derived Type binding (`x = Foo();` re-binding a possibly-GLOBAL x) is NOT a declaration
//     in C++ and never suppresses.
//   * a (scope, name) that ALSO carries an L3 fn binding (FnDecl/FnAssign) is a call THROUGH the variable:
//     those references stay, so the resolve loop's binding resolution (and its tombstone honesty) is
//     untouched — `void (*cb)() = &run; cb();` keeps its reference and resolves via the binding.
//   * only a name some indexed symbol actually carries is suppressed: with no same-named definition
//     anywhere there is NO false attribution to prevent, and --uses on a plain local/parameter name (the
//     external-answer feature the writetarget gate pins) keeps its sites.
// Runs at every ingest exit AND after the multi-root merge (workspace.h), exactly like the macro retag
// above — a def named N in ANOTHER root only becomes visible to the collision gate once roots merge.
// Idempotent, deterministic (erase_if preserves order; hash maps never drive output order; span lists are
// built in ing.bindings' total order). Runs AFTER retagMacroCallReferences so a role="macro" site
// (preprocessor evidence, textually stronger than any local) is never touched.
// the suppression pass's evidence tables and their "<fromSymbol>#<name>" key builder — see the contract
// comment above suppressShadowedReferences below.
// ONE declaring-block byte span. A 2-field POD and NOT `std::pair<uint32,uint32>`, because rw::svector
// requires a trivially-copyable element and a std::pair is not reliably one.
//
// THE PRECISE CLAIM, because the loose version of it is wrong in both directions. The standard does not
// REQUIRE std::pair to be trivially copyable, so the answer is implementation-defined: libc++ (this
// toolchain, 210106) says no, libstdc++ defaults the operators and says yes. Measured here, only the two
// ASSIGNMENT operators fail — both constructors and the destructor are trivial. Same portability class as
// infra/charconvcompat.h: a thing that happens to work on one standard library is not a thing you can build
// on.
//
// AND IT IS PERMANENT, so nobody should "fix" this back to a pair later expecting the library to have caught
// up. `pair::operator=` has to be hand-written to support REFERENCE members — `std::tie( a, b ) = f()` must
// assign THROUGH the references, and a defaulted operator would be deleted. More decisively, triviality is
// part of the ABI: a trivially-copyable type can be passed in registers and a non-trivially-copyable one
// goes by hidden reference, so making pair trivial would break every by-value pair parameter already
// compiled. libc++ ships in the macOS SDK under a hard ABI-stability commitment. `std::tuple` is the same
// story for the same reasons — treat it identically.
//
// The choice this drives, stated as a rule rather than a one-off: when a conversion candidate's element is a
// std:: composite that fails the trait, replace the ELEMENT with a named POD. Routing the structure to
// ankerl instead would forfeit the branch-free size() and the memcpy bulk moves over a library accident
// rather than a design reason; ankerl is for elements that are genuinely non-trivial (a real std::string, or
// a struct that owns something). The POD is byte-identical to the pair — 8 B, same field order — and
// structured-binding reads at the use site are unchanged.
struct VarSpan
{
    std::uint32_t startByte;
    std::uint32_t endByte;
};
static_assert( sizeof( VarSpan ) == 8, "the span pair is two 32-bit byte offsets — a layout change here resizes every varSpans entry" );
static_assert( std::is_trivially_copyable_v<VarSpan>, "the whole reason this is not std::pair — see the comment above. This assert is what explains the one above it." );

struct ShadowEvidence
{
    // (fromSymbol, var) → the declaring-block spans (VarDecl evidence) · the fn-binding veto set. The veto
    // stays UN-spanned on purpose: erring toward keeping a reference is the recall-safe side.
    //
    // N=1, measured, not guessed. Every key has at least one span (a key is only created by recording one),
    // and a SECOND span means the same variable name is declared twice in one function — 4.3% of keys on the
    // 43K-symbol validation corpus, 6.0% here. At an 8-byte element rw::svector<VarSpan,1> is 16 B and
    // <VarSpan,2> is 24 B, so N=1 is a THIRD smaller than the std::vector it replaces while still holding
    // 94-96% of the lists inline; N=2 would cost exactly what std::vector costs to reach 98%. The
    // free-N-is-2 rule that holds for 4-byte elements does NOT transfer here — see infra/svector.h's
    // layout pins.
    HashMap<std::string, rw::SmallVec<VarSpan, 1>> varSpans;
    HashMap<std::string, char>                     fnBindKeys;
    HashMap<std::string, char>                     defNames;
};

inline void buildShadowKey( std::string& key, std::uint32_t fromSymbol, std::string_view name )
{
    key.clear();
    char digits[ 10 ];
    int  digitCount = 0;
    do { digits[ digitCount++ ] = char( '0' + fromSymbol % 10u ); fromSymbol /= 10u; } while( fromSymbol != 0u );
    while( digitCount > 0 ) { key.push_back( digits[ --digitCount ] ); }
    key.push_back( '#' );
    key.append( name );
}

// the per-reference verdict: true ⇒ the site sits inside a block where a declared local shadows the name
// (and every guard in the contract above holds). `key` is the caller's reused buffer.
inline bool shadowSuppressedSite( const Reference& r, const ShadowEvidence& ev, std::string& key )
{
    if( r.fromSymbol == kNoNode || r.isInherit || r.isDocLink || r.isCompose )
    {
        return false;
    }
    if( r.role != RefRole::Call && r.role != RefRole::Read && r.role != RefRole::Write )
    {
        return false;   // import/extends sites are never local-variable uses; role=macro stays (see contract)
    }
    if( r.recv != RecvKind::None || !r.qualifier.empty() )
    {
        return false;   // a receiver- or scope-qualified name can never resolve to a plain local
    }
    if( ev.defNames.find( r.calleeName ) == ev.defNames.end() )
    {
        return false;   // no indexed symbol carries the name — nothing to falsely attribute to
    }
    buildShadowKey( key, r.fromSymbol, r.calleeName );
    const auto it = ev.varSpans.find( key );
    if( it == ev.varSpans.end() || ev.fnBindKeys.find( key ) != ev.fnBindKeys.end() )
    {
        return false;   // no declared local — or a fn-binding var, whose references must survive
    }
    for( const auto& [ spanStart, spanEnd ] : it->second )   // VarSpan is an aggregate — the binding reads as before
    {
        if( r.startByte >= spanStart && r.startByte < spanEnd )
        {
            return true;
        }
    }
    return false;
}

inline void suppressShadowedReferences( IngestResult& ing )
{
    ShadowEvidence ev;
    std::string    key;
    for( const Binding& b : ing.bindings )
    {
        if( b.fromSymbol == kNoNode || b.var.empty() )
        {
            continue;   // file-scope facts bind nothing here — suppression never reaches past a function
        }
        const bool isVar = ( b.kind == LocalBindKind::VarDecl );
        if( !isVar && b.kind != LocalBindKind::FnDecl && b.kind != LocalBindKind::FnAssign )
        {
            continue;   // Type bindings can come from plain assignments — declaration evidence only
        }
        buildShadowKey( key, b.fromSymbol, b.var );
        if( isVar )
        {
            // braced push_back, NOT emplace_back( a, b ): a PARENTHESIZED aggregate initialization needs
            // P0960, which Clang gained in 20 — CI's Xcode 15.4 toolchain would reject it. Same reason
            // ingest.cpp's LexPair rows are braced; see the note beside that push_back.
            ev.varSpans[ key ].push_back( VarSpan{ b.spanStart, b.spanEnd } );
        }
        else
        {
            ev.fnBindKeys.try_emplace( key, 1 );
        }
    }
    if( ev.varSpans.empty() )
    {
        return;   // VarDecl-free corpus (no captured C++/ObjC local declarations): byte-identical output
    }
    for( const Symbol& s : ing.symbols )   // the collision gate: some indexed symbol must carry the name
    {
        ev.defNames.try_emplace( s.name, 1 );
    }
    std::erase_if( ing.references, [ & ]( const Reference& r ) { return shadowSuppressedSite( r, ev, key ); } );
}

// ONE file's symbol-id bucket, and the whole index. Named so the ten independent reimplementations of this
// shape share ONE type rather than ten spellings of `std::vector<std::vector<NodeId>>`.
//
// N=8 IS A MEASURED KNEE, not p90. Per-bucket cardinality over the two census corpora (1 103 files here,
// 2 376 on the 43K-symbol validation corpus), as coverage of all buckets against the instance size
// rw::svector<NodeId,N> costs:
//
//     N :   1     2     4     6     8    12    16    24    32     bytes: 16 16 24 32 40 56 72 104 136
//   here: 17.3  35.9  54.4  66.7  76.4  84.6  88.0  93.9  96.4
//   cr48: 13.9  18.4  27.7  35.9  45.1  62.0  71.3  82.2  88.3
//
// Marginal coverage per byte of instance growth falls 2→4→6→8 as 2.31 / 1.54 / 1.21 here and 1.16 / 1.04 /
// 1.15 there, then collapses to 0.51 and 0.58 at the next step — the same cliff shape the census found for
// clones' type-3 buckets. N=8 is also the LARGEST N whose total footprint (this array + the heap blocks the
// spilled buckets still take + allocator per-block overhead) does not exceed what the plain
// std::vector<std::vector<NodeId>> costs today on EITHER corpus: ~75 KB vs ~80 KB here, ~276 KB vs ~265 KB
// there, where N=16 is ~100 KB and ~323 KB. p90 (18 here, 37 there) would have bought 3-9 more points of
// coverage for 2-3x the memory.
using FileSymbols   = rw::SmallVec<NodeId, 8>;
using SymbolsByFile = std::vector<FileSymbols>;

// THE per-file symbol index every span- or line-based lookup starts from: bucket the symbol ids by file, then
// sort each bucket. `keep` selects which symbols enter it and `less` orders each bucket, because those two are
// the ONLY things that differ between callers — flipimpact.h wants every symbol in line order (the host of a
// `#if` region), ensemble.h wants only body-carrying functions in byte order (the owner of a lint finding's
// span). Both were written independently and a --quality-delta pass found them as a 159-token clone pair,
// correctly: same shape, different filter and key. Parameterizing exactly those two is what makes this ONE
// function rather than a family of near-copies, and it lives here because `IngestResult` does.
// Deterministic by construction: file buckets are indexed, never hashed, and `symbols[i].id == i` so the
// pre-sort sequence in every bucket is ascending id regardless of which caller built it.
//
// ON `less` AND TOTAL ORDERS. Four of the callers folded in here (atoms.h's OwnerIndex, search.h's grep
// index, and main.cpp's --lint dedup and --match/--lint index) compare bare `sigStartByte` with no
// tie-break, which is NOT a total order: two symbols sharing a start offset in one file may land either
// way, and std::sort is not stable. That predates this consolidation and is deliberately NOT changed here —
// giving them a tie-break would reorder ties and move emitted bytes, which a container change must not do.
// Every such sort is still deterministic run-to-run: same input sequence, same comparator, same std::sort.
template<typename Keep, typename Less>
inline SymbolsByFile symbolsByFile( const IngestResult& ing, Keep keep, Less less )
{
    SymbolsByFile byFile( ing.files.size() );
    for( const Symbol& s : ing.symbols )
    {
        if( s.fileId < byFile.size() && keep( s ) )
        {
            byFile[ s.fileId ].push_back( s.id );
        }
    }
    for( FileSymbols& bucket : byFile )
    {
        std::sort( bucket.begin(), bucket.end(), less );
    }
    return byFile;
}

// The id-ordered form: every kept symbol, buckets left in ascending id order. `symbols[i].id == i` means the
// scan above already produces that order, so this spells "no reordering wanted" without paying a sort — the
// shape six of the ten folded-in call sites had written out by hand.
template<typename Keep>
inline SymbolsByFile symbolsByFileInIdOrder( const IngestResult& ing, Keep keep )
{
    SymbolsByFile byFile( ing.files.size() );
    for( const Symbol& s : ing.symbols )
    {
        if( s.fileId < byFile.size() && keep( s ) )
        {
            byFile[ s.fileId ].push_back( s.id );
        }
    }
    return byFile;
}

}   // namespace rw
