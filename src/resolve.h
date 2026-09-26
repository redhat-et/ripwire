#pragma once

// resolve.h — P2-D one-hop type narrowing. A deterministic, conservative refinement of the §2a
// name-based resolution ladder (graph.h::buildGraph): it pins a method call to its actual receiver
// TYPE *before* the ambiguous bare-name spray, so `this->process()` no longer splits 1/k across every
// in-repo `process` — it resolves to the caller's enclosing class only. Closes ~half the [TYPE] gap
// with zero deps and zero new graph passes (it consumes the canonical scope::name map buildGraph
// already builds for E#4 qualified-call resolution).
//
// CONTRACT (do not weaken — a WRONG narrow is worse than no narrow):
//   * The narrower NEVER invents a candidate the bare ladder couldn't also reach: every returned id is a
//     real same-name DEFINITION in the canonical scope map. If a rule can't apply, it returns {} and the
//     caller degrades to the unchanged §2a ladder. Determinism: candidates come out in the canonical map's
//     insertion order (symbol-id order), exactly like byName — so the resolved graph stays byte-identical
//     run-to-run, and PageRank/serialization are unperturbed beyond the corrected edges.
//   * Only DEFINITIONS (body present) are narrowing targets — a forward declaration is never a target
//     (matches buildGraph's decl/def collapse), so a narrow can't route rank into an empty prototype.
//
// RULES (§P2-D):
//   Rule 1 — class membership (IMPLEMENTED, the ~60% case): receiver is `this`/`self` → resolve the method
//            against the caller's enclosing class (fromSymbol.scope). C++ (`this->m()`) + Python (`self.m()`).
//   Rule 2 — receiver-VARIABLE type, one hop (IMPLEMENTED): `Foo x; x.m()` / `auto x = Foo(); x->m()` →
//            resolve `m` against the variable's TYPE (`Foo`). Ingest now captures local var→type bindings
//            (`Foo x;`, `Foo* x;`, `auto x = Foo()`, `x = Foo()` for C++/ObjC; `x = Foo()` for Python;
//            `const x = new Foo()` / `x: Foo` for TS) as IngestResult::bindings; buildGraph folds them into a
//            per-scope `(from,var) → type` map, TOMBSTONING any var bound to ≥2 distinct types (conservative —
//            an ambiguous var degrades to §2a). The bound type's `Foo::m` is resolved against canonByName
//            (defs only), so a narrow can never invent an edge the bare ladder couldn't reach.
//   Rule 2b — receiver-FIELD type (IMPLEMENTED, W1-P1-12): `struct A { Foo f; void g() { f.m(); } }` →
//            resolve `m` against the FIELD's declared type (`Foo`, from the S5-E HAS-A field capture),
//            walking direct-base names when `Foo` itself doesn't define `m`. Fires only when no local
//            binding of any kind shadows the field name and the class↔field↔type fact is unambiguous
//            corpus-wide (same-named classes with conflicting same-named fields are tombstoned). C++
//            evidence only; Python/TS field receivers are chained accesses (RecvKind::None) — unchanged.
//   Rule 3 — import/include-based file narrowing (IMPLEMENTED): when a call's name is ambiguous (K same-name
//            defs across the repo) but the CALLER's file `#include`s / imports EXACTLY ONE of the files that
//            defines it, resolve to that one file's def(s) and DROP the rest — a sound narrowing that needs no
//            type/receiver info, only the include/import edges ripwire already captures (IngestResult::includes,
//            resolved file→file by basename exactly like resolveIncludeAdj). Fires ONLY when precisely ONE
//            INCLUDED file holds a candidate def (0 or ≥2 → degrade to §2a unchanged), and NEVER when the
//            caller's OWN file also holds a candidate (that is the §2a same-file tier's job — Rule 3 is a
//            purely CROSS-FILE disambiguator, so it can never override or drop a same-file resolution). The
//            returned ids are always real defs the bare ladder could also reach (the byName candidate set,
//            filtered to the one included file) — Rule 3 just picks the include-correct file's def earlier.
//            Language-agnostic (C/C++/ObjC `#include`, Py/JS/TS `import`/`from…import`, Go/Rust/Swift import)
//            because it operates on the resolved file→file include graph, not on any language's name-lookup.

#include "model.h"
#include "arch.h"        // §B1.3: relForHash — the root-relative path segment canonicalIdRelTo keys on
#include "smallvec.h"
#include "infra/namesplit.h"   // stripTemplateArgs — a C++ template-id scope's family (appendTemplateFamilyKey), a `using Base<T>::m;` qualifier (buildUsingReexports)
#include "infra/sortutil.h"      // radixSortIdsAscending — the id-set sort buildGraph/2b below runs F times
#include "infra/profileScope.h"  // PROFILE_SCOPE self-profiling — gated by PROFILE_ENABLED (off unless -DRIPWIRE_PROFILE=ON)
#include "infra/Diagnostics.h"   // ASSUME — buildScopedRecvDecls' index-range precondition
#include "extentsuspect.h"       // extent::inSet with kHeadRuleLangs / kExtentClassKinds — class identity's C-family and class-kind tables

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>       // fopen/fread — workspace-only config-file evidence (go.mod / tsconfig.json), §3.2
#include <limits>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>
#include <vector>

namespace rw
{

// ── Path-precise #include resolution (a SOUND SameInclude tier) ─────────────────────────────────────
// The §2a resolver's file→file include graph was BASENAME-based: `#include "a.h"` matched EVERY `a.h`
// in the repo, so a cross-directory basename collision (this repo has Diagnostics.h / arch.h / a.h …)
// made the include narrow unsound (it could manufacture a confidently-wrong edge). The full written
// include path is already captured (Include::target) — path-precision UN-DISCARDS it.
//
// SOUNDNESS RULE (non-negotiable): narrow ONLY on a path-resolved fileId. A quote include `"x.h"` is
// resolved LEXICALLY relative to the includer's directory (pure string arithmetic on the SORTED,
// root-relative-or-verbatim `ing.files` paths — NO realpath, NO filesystem calls, matching
// arch.h::relForHash's determinism discipline). If a string cannot be resolved to EXACTLY ONE repo
// fileId, it contributes NOTHING to the include-set (returns kNoFile) — so it can never CAUSE a narrow.
// Angle includes `<x.h>` are external/unresolvable without compile_commands.json → left UNRESOLVED
// (never basename-matched). All functions here are PURE (deterministic; same inputs ⇒ same output).

inline constexpr std::uint32_t kNoFile = 0xFFFFFFFFu;   // "no repo file" sentinel for precise include resolution

// Collapse `.` and `..` path segments TEXTUALLY (a segment stack; `..` pops). Returns the normalized
// path, or the empty string when a `..` would escape ABOVE the path's own leading segments (an unsound
// escape → the caller treats an empty result as UNRESOLVED, never as the repo root). Lexical only: no
// realpath, no I/O — same determinism contract as relForHash. A leading '/' (absolute) is preserved;
// a trailing '/' is dropped. Empty segments (from `//` or a leading '/') and `.` segments are elided.
inline std::string lexicalNormalize( std::string_view path )
{
    // ONE allocation, the returned string, and it is reserved: the segment list this used to build
    // (`std::vector<std::string_view> segs; segs.reserve( 8 );`) was a second heap block on a function
    // probeUpward calls ~25 times PER INCLUDE — 714,000 times on a 4,923-file Ruby tree, where the include
    // adjacency was 87 ms of a 330 ms warm run (bench/PROFILE.md). Segments are appended to `out` directly
    // and a `..` truncates it back to the previous '/', which is the same pop the vector did: `segs` could
    // only ever hold real segments (`.`, `..` and empties take the other branches), so its
    // `segs.back() != ".."` guard was invariant-true and is gone with it. `rootLen` is the prefix a `..`
    // may never eat — 1 for an absolute path, 0 for a relative one — which is what makes the two degrade
    // rules ("no-op at the filesystem root" vs "escaping above the base is unsound") one comparison.
    const bool  isAbsolute = ( !path.empty() && path.front() == '/' );
    std::string out;
    out.reserve( path.size() );
    if( isAbsolute )
    {
        out.push_back( '/' );
    }
    const std::size_t rootLen = out.size();

    std::size_t i = 0;
    while( i < path.size() )
    {
        // consume one '/'-delimited segment [i, j)
        std::size_t j = i;
        while( j < path.size() && path[j] != '/' )
        {
            ++j;
        }
        const std::string_view seg = path.substr( i, j - i );

        if( seg.empty() || seg == "." )
        {
            // `//`, leading '/', trailing '/', or a `.` component → contributes nothing.
        }
        else if( seg == ".." )
        {
            if( out.size() > rootLen )
            {
                const std::size_t cut = out.rfind( '/' );                       // pop the previous real segment
                out.resize( ( cut == std::string::npos || cut < rootLen ) ? rootLen : cut );
            }
            else if( isAbsolute )                       { /* `..` at the filesystem root is a no-op */ }
            else
            {
                return {}; // relative `..` escaping above the base → unsound
            }
        }
        else
        {
            if( out.size() > rootLen )
            {
                out.push_back( '/' );
            }
            out.append( seg );
        }

        i = ( j < path.size() ) ? j + 1 : j;             // skip the '/'
    }
    return out;
}

// ── LEVER B: per-language import Step-A (string → fileId) ────────────────────────────────────────────
// The C-family SameInclude tier (below) generalizes VERBATIM to the import languages: Steps B/C
// (buildPreciseIncludeAdj / transitiveIncludeSet / rule3IncludeFile) are language-agnostic — they consume
// a resolved includer→fileId adjacency. ONLY Step-A (the string→fileId map) is language-specific, and it
// is selected by the INCLUDER's file extension via a declarative table (house-style, mirroring the
// extension→grammar and node-kind→tag tables). Each Step-A obeys the SAME soundness bar as the C tier:
// resolve to EXACTLY ONE repo fileId or degrade to kNoFile — NEVER basename-match, NEVER guess. Ambiguous
// or unresolvable → contributes nothing → the name-based §2a ladder + honest amb= still runs.
//
// SOUNDNESS VERDICT (§B.3): Python ✓, TS/JS ✓, Rust ✓ are v1-sound; Go
// (needs go.mod module-root) and Swift (whole-module, no path) are DEFERRED — their imports stay unresolved.

// The import dialect a file's imports resolve in, keyed off its extension. C-family covers the quote
// `#include`; Other (Swift/Java/C#/PHP/Markdown/…) never precise-resolves (deferred / no path in import).
// Bash/Ruby/Lua/Elixir joined at kParserVer 81 — see their Step-As below.
enum class IncludeLang : std::uint8_t { CFamily, Python, Ts, Rust, Go, Bash, Ruby, Lua, Elixir, Other };

// extension → dialect, a declarative constexpr table (NOT a scattered if-chain). Extension includes the
// leading dot; the classifier lowercases nothing (source extensions are lowercase by convention here).
inline IncludeLang includeLangOf( std::string_view path ) noexcept
{
    struct ExtLang { std::string_view ext; IncludeLang lang; };
    static constexpr ExtLang kExtLang[] =
    {
        { ".c",   IncludeLang::CFamily }, { ".cc",  IncludeLang::CFamily }, { ".cpp", IncludeLang::CFamily },
        { ".cxx", IncludeLang::CFamily }, { ".h",   IncludeLang::CFamily }, { ".hpp", IncludeLang::CFamily },
        { ".hh",  IncludeLang::CFamily }, { ".hxx", IncludeLang::CFamily }, { ".m",   IncludeLang::CFamily },
        { ".mm",  IncludeLang::CFamily },
        // The shader/CUDA trio the crawl indexes as C++ and the Python typing stub. Their files entered the
        // dependency denominator when langOfPath learned their extensions (lintrules.h), so their includer
        // dialect joins in the same change: a quote `#include "x.cuh"` is the C tier's exact relative-path
        // hit, and a stub's `import` is Python's Step-A. Without these rows they would be counted and never
        // resolve, which test/deplangscheck.sh arm (G) refuses. `.hxx` left this table with langOfPath's row while
        // the crawl admitted no `.hxx` file, and came back with it when the crawl did (A4, lane/small-fixes-0917).
        { ".metal", IncludeLang::CFamily }, { ".cu", IncludeLang::CFamily }, { ".cuh", IncludeLang::CFamily },
        { ".py",  IncludeLang::Python },    { ".pyi", IncludeLang::Python },
        { ".ts",  IncludeLang::Ts },      { ".tsx", IncludeLang::Ts },      { ".mts", IncludeLang::Ts },
        { ".cts", IncludeLang::Ts },      { ".js",  IncludeLang::Ts },      { ".jsx", IncludeLang::Ts },
        { ".mjs", IncludeLang::Ts },      { ".cjs", IncludeLang::Ts },
        // `.astro` joins for the SAME reason the shader/CUDA trio above did, in the same change that gave it a
        // langOfPath row (issue #67): it is Lang::TypeScript, so it is dependency-CAPABLE and enters the
        // dep_files= denominator — without this row it would be counted and never resolve, which
        // test/deplangscheck.sh arm (G) refuses. Its imports are ordinary relative TypeScript specifiers and
        // live in the `---` frontmatter, which is the only part of the file this build parses at all.
        { ".astro", IncludeLang::Ts },
        { ".rs",  IncludeLang::Rust },
        { ".go",  IncludeLang::Go },       // Go: single-root DEFERRED (kNoFile); cross-root via go.mod `replace` (§3.2)
        // kParserVer 81 — the four-language import round. Each has a SOUND Step-A below (unique-or-degrade,
        // never a basename fallback); none is deferred, because unlike a Go package path or a C# namespace,
        // each of these four names a FILE by a rule this tool can evaluate without a build system.
        { ".sh",  IncludeLang::Bash },    { ".bash", IncludeLang::Bash },  { ".zsh", IncludeLang::Bash },
        { ".rb",  IncludeLang::Ruby },
        { ".lua", IncludeLang::Lua },
        { ".ex",  IncludeLang::Elixir },  { ".exs", IncludeLang::Elixir },
        // B6.2: `.cs` has NO entry here — it falls through to IncludeLang::Other below, DEFERRED like
        // Java (also absent) and Swift/Go-single-root: a C# namespace does not map 1:1 onto a file (one
        // namespace spans many files, one file can hold several namespaces), so there is no sound
        // string→fileId rule to write — same conservative-fall-through posture Rule 3 already requires
        // for Java. `using Foo.Bar;` is still captured (ingest.cpp::captureIncludes) for --uses/--deps
        // visibility; it just never narrows an ambiguous call the way a C++ `#include`/Python `import` can.
    };
    const std::size_t dot = path.rfind( '.' );
    if( dot == std::string_view::npos )
    {
        return IncludeLang::Other;
    }
    const std::string_view ext = path.substr( dot );
    for( const ExtLang& e : kExtLang )
    {
        if( e.ext == ext )
        {
            return e.lang;
        }
    }
    return IncludeLang::Other;
}

// The includer's directory (everything before the last '/'; empty when the file sits at the crawl root).
inline std::string_view includerDir( std::string_view includerPath ) noexcept
{
    const std::size_t sl = includerPath.rfind( '/' );
    return ( sl == std::string_view::npos ) ? std::string_view{} : includerPath.substr( 0, sl );
}

// ── Multi-root workspace include context (§3.1) ──────────────────────────────────────────────────────
// Built by buildPreciseIncludeAdj when the IngestResult is a merged workspace (ing.fileRoot non-empty),
// nullptr otherwise (single root — every function below is then byte-identical to today). Carries:
//   * fileRoot     — fileId → root index (same-root soundness gate on labeled-index hits);
//   * absIndex     — lexicalNormalize(<root-realpath>/<rel>) → fileId: the DISK-shape probe for a quote
//                    include / relative import that lexically ESCAPES its own root (§3.1a). Unique by
//                    construction (roots are disjoint post-dedupe, nesting is a hard error);
//   * rootAbs/rootLabels — per-root realpath + label (abs-base reconstruction; angle probes §3.1b).
// One cross-root import alias mined from a config file (§3.2, decided 2026-07-11):
// a tsconfig.json `compilerOptions.paths` alias or a go.mod `replace` directive that points at a SIBLING
// workspace root. Same evidence-only posture as includes: a config alias only ever resolves to a file that
// PHYSICALLY EXISTS in the destination root (probed against absIndex, unique-or-degrade) — it can no more
// manufacture a wrong edge than the disk-shape include probe can, and it NEVER resolves by name. Only aliases
// whose destination ESCAPES their own root are kept (intra-root aliases stay external, exactly as a bare
// specifier is treated single-root — so a workspace only ever ADDS cross-root edges, never perturbs intra-root).
struct ConfigAlias
{
    std::uint32_t fromRoot = 0;      // the root whose config declared it — ONLY that root's imports consult it
    std::string   spec;              // the specifier prefix to match (TS `@svc/`, Go module path `example.com/svc`)
    std::string   absDest;           // the on-disk destination prefix the alias points at (lexically normalized)
    bool          wildcard = false;  // TS `@svc/*` / Go package prefix → the matched tail is appended to absDest
    bool          isGo     = false;  // Go: resolve to the single .go file in the dest package dir; TS: extension-probe a file
};

struct WsIncludeCtx
{
    const std::vector<std::uint32_t>*    fileRoot = nullptr;
    HashMap<std::string, std::uint32_t>  absIndex;
    std::vector<std::string>             rootAbs;
    std::vector<std::string>             rootLabels;
    std::vector<ConfigAlias>             configAliases;   // §3.2 tsconfig paths / go.mod replace evidence (empty ⇒ none)
};

// Join a base directory with a relative candidate, lexically normalize (`.`/`..` collapse; `..`-escape →
// empty), and look it up in fileIndex. Returns the fileId on an EXACT hit, else kNoFile. The C-family
// quote-include primitive, factored out so every language's Step-A shares one sound join+lookup.
//
// Multi-root (ws != nullptr): fileIndex keys are LABELED paths, so three rules apply (§3.1):
//   1. a labeled-index hit counts ONLY when it lands in the includer's OWN root — a hit in another root is
//      a label-shaped coincidence (`cli/src/../../svc/x.h` normalizing onto root svc's key), NOT evidence;
//   2. a root-RELATIVE probe (empty baseDir — Python absolute imports) is anchored at the includer's own
//      root by prefixing its label (labeled keys are never bare-relative);
//   3. on a same-root miss, the DISK-shape probe reconstructs the includer's absolute directory and
//      resolves the join against absIndex — the §3.1a evidence channel for an include that genuinely
//      escapes its root on disk (sibling checkouts). Roots are disjoint, so an abs hit is unique.
inline std::uint32_t joinNormalizeLookup( std::string_view baseDir, std::string_view rel,
                                          const HashMap<std::string, std::uint32_t>& fileIndex,
                                          const WsIncludeCtx* ws = nullptr, std::uint32_t includerFileId = kNoFile )
{
    // rule 2: anchor a root-relative probe at the includer's own root (labels are never empty).
    std::string      labelBase;
    std::string_view effBase = baseDir;
    const std::uint32_t incRoot = ( ws && includerFileId != kNoFile && includerFileId < ws->fileRoot->size() )
                                ? ( *ws->fileRoot )[ includerFileId ] : 0xFFFFFFFFu;
    if( ws && baseDir.empty() && incRoot != 0xFFFFFFFFu )
    {
        labelBase = ws->rootLabels[ incRoot ];
        effBase   = labelBase;
    }

    std::string joined;
    joined.reserve( effBase.size() + 1 + rel.size() );
    if( !effBase.empty() ) { joined.append( effBase ); joined.push_back( '/' ); }
    joined.append( rel );

    const std::string candidate = lexicalNormalize( joined );
    if( !candidate.empty() )
    {
        const auto it = fileIndex.find( candidate );
        if( it != fileIndex.end() )
        {
            if( !ws )
            {
                return it->second; // single root — unchanged
            }
            // rule 1: same-root hits are sound as today; a cross-root labeled hit is NOT evidence.
            if( incRoot != 0xFFFFFFFFu && ( *ws->fileRoot )[it->second] == incRoot )
            {
                return it->second;
            }
        }
        else if( !ws )
        {
            return kNoFile;
        }
    }
    if( !ws || incRoot == 0xFFFFFFFFu )
    {
        return kNoFile; // `..`-escape above the crawl root → unresolved (single root)
    }

    // rule 3 (§3.1a): the DISK-shape probe. Reconstruct the includer's absolute base directory from its
    // root realpath + its labeled dir minus the label, join, normalize, and look up the absolute index.
    const std::string& label = ws->rootLabels[ incRoot ];
    std::string_view   relBase = baseDir;
    if( relBase.size() >= label.size() && relBase.compare( 0, label.size(), label ) == 0 )
    {
        relBase.remove_prefix( label.size() );
        if( !relBase.empty() && relBase.front() == '/' )
        {
            relBase.remove_prefix( 1 );
        }
    }
    std::string absJoined;
    absJoined.reserve( ws->rootAbs[ incRoot ].size() + relBase.size() + rel.size() + 2 );
    absJoined.append( ws->rootAbs[ incRoot ] );
    if( !relBase.empty() ) { absJoined.push_back( '/' );  absJoined.append( relBase ); }
    absJoined.push_back( '/' );  absJoined.append( rel );

    const std::string absCandidate = lexicalNormalize( absJoined );
    if( absCandidate.empty() )
    {
        return kNoFile;
    }
    const auto ait = ws->absIndex.find( absCandidate );
    return ( ait == ws->absIndex.end() ) ? kNoFile : ait->second;
}

// ── Python Step-A — SOUND. `import a` / `import pkg.mod` / `from pkg.mod import Z` / `from .rel import Z`.
// The captured target is the CLEAN module path (B0): `a`, `pkg.mod`, or a relative `.`/`.rel`/`..up`.
// Rule: dots→slashes (leading relative dots handled as `.`/`..` path steps), then probe TWO candidate
// files in a FIXED order — `mod.py` then `mod/__init__.py` — resolved BOTH relative-to-file and
// relative-to-repo-root. Resolve IFF exactly ONE distinct fileId is hit across all probes; 0 or ≥2 → kNoFile
// (degrade, no guess). `mod.py` and `mod/__init__.py` are mutually exclusive for one module on disk, so the
// only ambiguity is file-relative vs root-relative naming the same-shaped path in two dirs → degrade.
inline std::uint32_t resolvePythonImport( std::string_view includerPath, std::string_view target,
                                          const HashMap<std::string, std::uint32_t>& fileIndex,
                                          const WsIncludeCtx* ws = nullptr, std::uint32_t includerFileId = kNoFile )
{
    if( target.empty() )
    {
        return kNoFile;
    }

    // Split leading dots (relative import): each leading '.' is a directory step. `.`  → this dir;
    // `..` → parent; `.rel` → this dir + `rel`. The remaining dotted tail maps '.'→'/'.
    std::size_t nDots = 0;
    while( nDots < target.size() && target[nDots] == '.' )
    {
        ++nDots;
    }
    const std::string_view tail = target.substr( nDots );   // dotted module tail after the leading dots

    // dotted tail → slash path (`pkg.mod` → `pkg/mod`). A trailing/empty tail (bare `from . import x`) is fine.
    std::string modPath;
    modPath.reserve( tail.size() );
    for( char c : tail )
    {
        modPath.push_back( c == '.' ? '/' : c );
    }

    // leading-dot prefix as path steps: `.`→"" (this dir), N dots → (N-1) × "../".
    std::string relPrefix;
    for( std::size_t k = 1; k < nDots; ++k )
    {
        relPrefix.append( "../" ); // first dot = current dir, rest = parents
    }

    const bool             isRelative = ( nDots > 0 );
    const std::string_view dir        = includerDir( includerPath );

    // probe the two candidate filenames in FIXED order for determinism (mutually exclusive on disk).
    std::string cand[ 2 ];
    cand[ 0 ] = relPrefix + modPath + ".py";
    cand[ 1 ] = relPrefix + modPath + ( modPath.empty() ? "__init__.py" : "/__init__.py" );

    std::uint32_t hit = kNoFile;
    const auto probe = [ & ]( std::string_view base, std::string_view rel )
    {
        if( rel.empty() )
        {
            return;
        }
        const std::uint32_t f = joinNormalizeLookup( base, rel, fileIndex, ws, includerFileId );
        if( f == kNoFile )
        {
            return;
        }
        if( hit == kNoFile )
        {
            hit = f; // first distinct hit
        }
        else if( f != hit )
        {
            hit = kNoFile - 1; // a SECOND distinct file → ambiguous marker (≠ any real id)
        }
    };
    for( const std::string& c : cand )
    {
        probe( dir, c );                                 // relative-to-file (always; the only mode for a relative import)
        if( !isRelative )
        {
            probe( std::string_view {}, c ); // relative-to-repo-root (absolute import only)
        }
    }
    return ( hit == kNoFile || hit == kNoFile - 1 ) ? kNoFile : hit;   // unique-or-degrade
}

// A relative JS/TS specifier may spell the RUNTIME file its source compiles to: TypeScript's node16/nodenext
// resolution requires `import './api.js'` for `api.ts`, and a `.mjs`/`.cjs` specifier names its `.mts`/`.cts`
// source. ONE table, read by the precise include tier (resolveTsImport below) and by graph.h's named-import binder
// (resolveJsNamedImportFile), so --deps and the call binder cannot disagree about which file a runtime spelling
// names. No directory-index row: TypeScript never maps `./lib.js` onto `lib/index.ts` (verified live, tsc 7.0.2
// --traceResolution, node16/nodenext/bundler identical: "was not resolved").
//
// Two tiers, source before declaration (same trace): a stray `.d.ts`/`.d.mts`/`.d.cts` is tried ONLY when
// `sources` answers NOTHING — `./d.js` with only `d.d.ts` on disk resolves to it, but `./both.js` with BOTH
// `both.ts` and `both.d.ts` resolves to `both.ts` and never even probes the declaration (source wins outright,
// not "first written"). `sources` itself keeps the existing unique-or-degrade discipline unchanged: if two
// SOURCE alternates both exist (e.g. a tree with both `tj.ts` and `tj.tsx` for one `./tj.js` specifier), tsc's
// real resolver breaks the tie by fixed order (`tj.ts` wins, not ambiguous) — this table does not implement
// that tie-break (matches the pre-existing `.js`->{ts,tsx} row's shipped behaviour, a deliberate conservative
// choice already documented above: two real candidates degrade to unresolved rather than guess). `decl` is
// UNAMBIGUOUS by construction — TypeScript declaration files never fork on tsx/jsx, so there is exactly one
// declaration spelling per runtime extension, never a pair to degrade between.
struct JsRuntimeSourceExt
{
    std::string_view runtime;        // the emitted spelling the specifier carries
    std::string_view sources[ 2 ];   // the source spellings it may name; an empty slot is unused
    std::string_view decl;           // declaration-only fallback, tried iff `sources` found nothing at all; empty = none
};

inline constexpr JsRuntimeSourceExt kJsRuntimeSourceExts[] = {
    { ".js",  { ".ts", ".tsx" }, ".d.ts"  },
    // .jsx before .js in iteration order doesn't matter here (`ends_with(".js")` is false on a ".jsx" specifier —
    // the two runtime spellings share no suffix), but jsRuntimeSourceExtOf takes the FIRST row whose runtime
    // suffix matches, so this row still owns every ".jsx" specifier outright. Source order .tsx-then-.ts matches
    // tsc live: `./jx.jsx`->jx.tsx (only .tsx present), `./jts.jsx`->jts.ts (only .ts present). The `.d.ts`
    // fallback for a bare `.jsx` specifier is not in the archived tsc trace (its probe list only carried .js/.jsx
    // rows that already had a source hit) — it is the same single declaration-file rule as `.js` because
    // TypeScript never emits a `.d.jsx`/`.d.tsx`; kept here for that reason, not because it was traced directly.
    { ".jsx", { ".tsx", ".ts" }, ".d.ts"  },
    { ".mjs", { ".mts", {} },    ".d.mts" },
    { ".cjs", { ".cts", {} },    ".d.cts" },
};

// The row a specifier's suffix selects, or nullptr when it carries no runtime extension.
inline const JsRuntimeSourceExt* jsRuntimeSourceExtOf( std::string_view specifier ) noexcept
{
    for( const JsRuntimeSourceExt& row : kJsRuntimeSourceExts )
    {
        if( specifier.size() > row.runtime.size() && specifier.ends_with( row.runtime ) )
        {
            return &row;
        }
    }
    return nullptr;
}

// The two-tier probe `kJsRuntimeSourceExts` exists for: `runtimeExt`'s SOURCE alternates first
// (unique-or-degrade among `sources`), then — ONLY when the source tier found NOTHING at all, never when
// it is ambiguous — its single DECLARATION fallback. `seedHit` folds in a caller's own already-resolved
// candidate (an exact/literal probe of the specifier itself) under the SAME unique-or-degrade rule, so a
// caller needs no separate merge step: the returned `fileId` already accounts for it. Shared by
// resolveTsImport (below) and graph.h's resolveJsNamedImportFile, so the two-tier precedence — source
// before declaration, tsc live-verified (see kJsRuntimeSourceExts above) — and the underlying lookup
// (joinNormalizeLookup) cannot drift between the include tier and the named-import binder.
//
// Returns { fileId, ambiguous }: fileId is kNoFile on EITHER "nothing answered" or "ambiguous" — ambiguous
// says which, the same two-outcome contract resolveJsNamedImportFile already promised its own callers.
inline std::pair<std::uint32_t, bool> probeJsRuntimeSourceExt( std::string_view dir, std::string_view target,
                                                                const JsRuntimeSourceExt& runtimeExt,
                                                                const HashMap<std::string, std::uint32_t>& fileIndex,
                                                                const WsIncludeCtx* ws, std::uint32_t includerFileId,
                                                                std::uint32_t seedHit = kNoFile )
{
    // `runtimeExt` must be the row `jsRuntimeSourceExtOf( target )` itself returned — its own size guard
    // (`specifier.size() > row.runtime.size()`, just above) is what makes forming `stem` safe below; this
    // function does not re-derive `runtimeExt` from `target`, so that contract is the CALLER's to keep.
    // `seedHit` must not already be the `kNoFile - 1` ambiguous marker: it is folded in as an ordinary
    // candidate, not as a pre-existing ambiguity, and no caller has a reason to pass that sentinel in.
    EXPECTS( target.size() > runtimeExt.runtime.size(), "caller must pass runtimeExt from jsRuntimeSourceExtOf( target )" );
    EXPECTS( seedHit != kNoFile - 1, "seedHit is an ordinary candidate, never the ambiguous marker" );
    const std::string stem( target.substr( 0, target.size() - runtimeExt.runtime.size() ) );
    std::uint32_t hit = seedHit;
    bool ambiguous = false;
    const auto probe = [ & ]( std::string_view extension )
    {
        const std::uint32_t candidate = joinNormalizeLookup( dir, stem + std::string( extension ), fileIndex, ws, includerFileId );
        if( candidate == kNoFile ) { return; }
        if( hit != kNoFile && hit != candidate ) { ambiguous = true; }
        hit = candidate;
    };
    for( const std::string_view source : runtimeExt.sources )
    {
        if( !source.empty() )
        {
            probe( source );
        }
    }
    if( !ambiguous && hit == kNoFile && !runtimeExt.decl.empty() )
    {
        probe( runtimeExt.decl );
    }
    return { ambiguous ? kNoFile : hit, ambiguous };
}

// ── Python Step-A, SUFFIX fallback (issue #287) — for an ABSOLUTE (non-relative) spec Step-A's two bases
// (relative-to-file, relative-to-crawl-root) both miss: `import target_mod` naming an indexed
// `pkg/target_mod.py` that lives under a package directory neither base probes (no sys.path modelling —
// same limit Step-A already has). Reuses `samePathTail` (arch.h) — the SAME whole-path-COMPONENT-boundary
// suffix test already used to match a canonical id's root-relative spelling (graph.h::canonicalIdMatches)
// and a git tree path against an ingest path (crossref.h::sameTreePath) — rather than a new, looser
// matcher: `target_mod.py` hits `pkg/target_mod.py` on a real path-component boundary, never
// `xtarget_mod.py` or a bare `.py`. `fileIndex` is the same ingest-root-relative universe Step-A probes;
// unique-or-degrade exactly like Step-A's own probe (0 or ≥2 distinct fileIds hit ⇒ kNoFile).
//
// NEVER applied to a relative spec — a leading `.` fixes the base to the includer's own file, so
// suffix-scanning it would be a real loosening (matching some unrelated same-named file elsewhere in the
// tree), not a mirror of Step-A. Guarded here too (kNoFile on a relative/empty target) so a future call
// site can't skip the gate silently.
//
// CodeRabbit PR #292 finding 4052087919: this scans the WHOLE `fileIndex`, which in a MERGED multi-root
// workspace (`ripwire dir1 dir2 …`) spans every labeled root, not just the importer's own. Without a
// same-root restriction, `import target_mod` in root A could bind to the only `target_mod.py` in an
// unrelated root B — a cross-root edge with no import path or workspace configuration connecting the two
// roots, the exact kind of evidence-free cross-root hit `sameRoot()` exists elsewhere in graph.h to
// refuse. `fileRoot`/`importerFileId` are optional (both default to "no restriction") so a single-root
// caller — `fileRoot` is empty there, same convention as graph.h's own `sameRoot` — pays nothing and
// changes nothing; a multi-root caller passes both and every candidate outside the importer's root is
// filtered OUT before the unique-or-degrade count, exactly as if it were never indexed (never counted as
// the ambiguity that makes a genuinely unique same-root hit degrade to kNoFile).
inline std::uint32_t resolvePythonModuleSuffix( std::string_view target, const HashMap<std::string, std::uint32_t>& fileIndex,
                                                 const std::vector<std::uint32_t>* fileRoot = nullptr, std::uint32_t importerFileId = kNoFile )
{
    if( target.empty() || target.front() == '.' )
    {
        return kNoFile;
    }
    const bool         rootScoped = fileRoot != nullptr && !fileRoot->empty() && importerFileId < fileRoot->size();
    const std::uint32_t importerRoot = rootScoped ? ( *fileRoot )[ importerFileId ] : 0u;
    std::string modPath;
    modPath.reserve( target.size() );
    for( const char c : target )
    {
        modPath.push_back( c == '.' ? '/' : c );
    }
    const std::string tailPy   = modPath + ".py";
    const std::string tailInit = modPath + "/__init__.py";

    std::uint32_t hit = kNoFile;
    for( const auto& kv : fileIndex )
    {
        if( samePathTail( kv.first, tailPy ) || samePathTail( kv.first, tailInit ) )
        {
            if( rootScoped && ( kv.second >= fileRoot->size() || ( *fileRoot )[ kv.second ] != importerRoot ) )
            {
                continue;   // a real path-tail hit, but in an unrelated labeled root — no import evidence connects them
            }
            if( hit == kNoFile )
            {
                hit = kv.second; // first distinct hit
            }
            else if( kv.second != hit )
            {
                return kNoFile; // a SECOND distinct file → ambiguous, never guess
            }
        }
    }
    return hit;
}

// ── TS/JS Step-A — SOUND (closest to C quote-includes). Relative specifier `./x` / `../a/b` → probe a
// FIXED extension list then index files, relative-to-includer; a BARE specifier (`react`, `lodash` — no
// leading dot) is node_modules/external → kNoFile (unresolved, never matched). Resolve IFF exactly ONE
// candidate hits; 0 or ≥2 → kNoFile (degrade).
inline std::uint32_t resolveTsImport( std::string_view includerPath, std::string_view target,
                                      const HashMap<std::string, std::uint32_t>& fileIndex,
                                      const WsIncludeCtx* ws = nullptr, std::uint32_t includerFileId = kNoFile )
{
    if( target.empty() )
    {
        return kNoFile;
    }

    static constexpr std::string_view kFileExt[]  = { ".ts", ".tsx", ".d.ts", ".js", ".jsx", ".mjs", ".cjs" };
    static constexpr std::string_view kIndexRel[] = { "/index.ts", "/index.tsx", "/index.js", "/index.jsx" };

    // bare specifier (not `.`/`./`/`../`) → external package → unresolved single-root (the angle-include analogue).
    // Multi-root (§3.2, decided 2026-07-11): a tsconfig.json `compilerOptions.paths` alias pointing at a SIBLING
    // root maps the bare specifier onto a real file in that root — probed against absIndex (disk-shape),
    // unique-or-degrade across every matching alias/extension. Never name-based; ≥2 distinct hits ⇒ kNoFile.
    if( target.front() != '.' )
    {
        if( !ws || ws->configAliases.empty() || includerFileId == kNoFile || includerFileId >= ws->fileRoot->size() )
        {
            return kNoFile;
        }
        const std::uint32_t incRoot = ( *ws->fileRoot )[ includerFileId ];
        std::uint32_t       hit     = kNoFile;
        const auto consider = [ & ]( std::uint32_t f )
        {
            if( f == kNoFile )
            {
                return;
            }
            if( hit == kNoFile )
            {
                hit = f;
            }
            else if( f != hit )
            {
                hit = kNoFile - 1; // a SECOND distinct file → ambiguous → degrade
            }
        };
        const auto probeAbs = [ & ]( const std::string& cand )
        {
            const std::string norm = lexicalNormalize( cand );
            if( norm.empty() )
            {
                return;
            }
            const auto it = ws->absIndex.find( norm );
            if( it != ws->absIndex.end() )
            {
                consider( it->second );
            }
        };
        for( const ConfigAlias& al : ws->configAliases )
        {
            if( al.isGo || al.fromRoot != incRoot )
            {
                continue;
            }
            std::string absBase;
            if( al.wildcard )
            {
                if( target.size() < al.spec.size() || target.compare( 0, al.spec.size(), al.spec ) != 0 )
                {
                    continue;
                }
                absBase = al.absDest + "/" + std::string( target.substr( al.spec.size() ) );
            }
            else
            {
                if( target != al.spec )
                {
                    continue;
                }
                absBase = al.absDest;
            }
            probeAbs( absBase );                                        // exact (specifier already carried an extension)
            for( std::string_view e : kFileExt )
            {
                probeAbs( absBase + std::string( e ) );
            }
            for( std::string_view e : kIndexRel )
            {
                probeAbs( absBase + std::string( e ) );
            }
        }
        return ( hit == kNoFile || hit == kNoFile - 1 ) ? kNoFile : hit;
    }

    const std::string_view dir = includerDir( includerPath );
    std::uint32_t hit = kNoFile;
    const auto probe = [ & ]( const std::string& rel )
    {
        const std::uint32_t f = joinNormalizeLookup( dir, rel, fileIndex, ws, includerFileId );
        if( f == kNoFile )
        {
            return;
        }
        if( hit == kNoFile )
        {
            hit = f;
        }
        else if( f != hit )
        {
            hit = kNoFile - 1; // second distinct file → ambiguous
        }
    };
    // FIRST an exact hit (specifier already has an extension, e.g. `./x.js`), then the source file a runtime spelling
    // names (kJsRuntimeSourceExts, both tiers — probeJsRuntimeSourceExt above), then extension-appended, then
    // index. One accumulator for all of them (probeJsRuntimeSourceExt is SEEDED with it and folds its own
    // result back in), so a tree holding BOTH api.js and api.ts leaves `./api.js` unresolved rather than
    // guessing which module was meant.
    probe( std::string( target ) );
    if( const JsRuntimeSourceExt* const runtimeExt = jsRuntimeSourceExtOf( target ) )
    {
        const auto [ extHit, extAmbiguous ] = probeJsRuntimeSourceExt( dir, target, *runtimeExt, fileIndex, ws, includerFileId, hit );
        hit = extAmbiguous ? ( kNoFile - 1 ) : extHit;
    }
    for( std::string_view e : kFileExt )
    {
        probe( std::string( target ) + std::string( e ) );
    }
    for( std::string_view e : kIndexRel )
    {
        probe( std::string( target ) + std::string( e ) );
    }
    return ( hit == kNoFile || hit == kNoFile - 1 ) ? kNoFile : hit;
}

// ── Rust Step-A — SOUND (mod x; sound; use crate::… sound-by-degrade). The captured target is either
// `mod:x` (a body-less `mod x;` declaration, B0) or a `use` path (`crate::a::b`, `super::x`, `self::y::Z`).
//   * `mod:x` → `x.rs` OR `x/mod.rs` RELATIVE to the includer's directory (Rust's module-file rule); exactly
//     one exists → unique or degrade. Fully sound.
//   * `use crate::a::b` → crate root (`src/`, from an `src/lib.rs`/`src/main.rs` presence) + `a/b` → probe
//     `src/a/b.rs`, `src/a/b/mod.rs`, `src/a.rs` (b as an item in module a). `super::`/`self::` resolve
//     relative-to-file. Resolve IFF exactly ONE hits, else degrade (which trailing segments are modules vs
//     items is not decidable source-only — degrade keeps it sound).
inline std::uint32_t resolveRustImport( std::string_view includerPath, std::string_view target,
                                        const HashMap<std::string, std::uint32_t>& fileIndex,
                                        std::string_view crateRootDir, bool hasCrateRoot,
                                        const WsIncludeCtx* ws = nullptr, std::uint32_t includerFileId = kNoFile )
{
    if( target.empty() )
    {
        return kNoFile;
    }
    const std::string_view dir = includerDir( includerPath );

    std::uint32_t hit = kNoFile;
    const auto probe = [ & ]( std::string_view base, const std::string& rel )
    {
        const std::uint32_t f = joinNormalizeLookup( base, rel, fileIndex, ws, includerFileId );
        if( f == kNoFile )
        {
            return;
        }
        if( hit == kNoFile )
        {
            hit = f;
        }
        else if( f != hit )
        {
            hit = kNoFile - 1;
        }
    };

    // `mod x;` (body-less module-file declaration) → `x.rs` / `x/mod.rs` relative-to-includer.
    if( target.rfind( "mod:", 0 ) == 0 )
    {
        const std::string_view mod = target.substr( 4 );
        if( mod.empty() || mod.find( ':' ) != std::string_view::npos )
        {
            return kNoFile;
        }
        probe( dir, std::string( mod ) + ".rs" );
        probe( dir, std::string( mod ) + "/mod.rs" );
        return ( hit == kNoFile || hit == kNoFile - 1 ) ? kNoFile : hit;
    }

    // `use …` — split the `::`-path into head + trailing segments. Only crate-anchored / relative uses
    // (`crate::`, `super::`, `self::`) map to a repo path; a bare `use std::…` / external crate does not.
    // A brace group (`crate::{a, b}`) never resolves to one file → degrade (the `{`/`,` guard).
    if( target.find_first_of( "{}, " ) != std::string_view::npos )
    {
        return kNoFile;
    }

    // split on `::` into segments.
    std::vector<std::string_view> seg;
    {
        std::size_t i = 0;
        while( i < target.size() )
        {
            std::size_t j = target.find( "::", i );
            if( j == std::string_view::npos )
            {
                j = target.size();
            }
            seg.push_back( target.substr( i, j - i ) );
            i = ( j < target.size() ) ? j + 2 : j;
        }
    }
    if( seg.empty() )
    {
        return kNoFile;
    }

    // Determine the anchor + the path segments AFTER it.
    std::string           base;      // directory to resolve relative to
    std::size_t           first = 0; // index of the first path segment after the anchor
    if( seg[0] == "crate" )
    {
        if( !hasCrateRoot )
        {
            return kNoFile; // workspace member w/o a locatable crate root → degrade
        }
        base  = std::string( crateRootDir );
        first = 1;
    }
    else if( seg[0] == "self" )  { base = std::string( dir ); first = 1; }
    else if( seg[0] == "super" ) { base = std::string( dir ) + "/.."; first = 1; }
    else
    {
        return kNoFile; // `std::…` / external crate / bare → external → unresolved
    }

    // path segments after the anchor (drop the final item candidate variants).
    std::vector<std::string_view> path( seg.begin() + std::ptrdiff_t( first ), seg.end() );
    if( path.empty() )
    {
        return kNoFile;
    }

    // build `a/b` from all-but-last, and `a` from all-but-two, for the module-vs-item degrade-safe probe.
    const auto joinSegs = [ & ]( std::size_t upto ) -> std::string
    {
        std::string p;
        for( std::size_t k = 0; k < upto; ++k )
        {
            if( k )
            {
                p.push_back( '/' );
            }
            p.append( path[k] );
        }
        return p;
    };

    // full path as a module: `a/b.rs`, `a/b/mod.rs` (last segment is a module); and `a.rs` with b an item.
    const std::string full = joinSegs( path.size() );                       // a/b
    probe( base, full + ".rs" );
    probe( base, full + "/mod.rs" );
    if( path.size() >= 2 )
    {
        const std::string parent = joinSegs( path.size() - 1 );             // a  (b is an item in module a)
        probe( base, parent + ".rs" );
        probe( base, parent + "/mod.rs" );
    }
    return ( hit == kNoFile || hit == kNoFile - 1 ) ? kNoFile : hit;
}

// ── Cross-root config-file import evidence (§3.2, decided 2026-07-11) ─────────────────────────────────
// tsconfig.json `compilerOptions.paths` aliases + go.mod `replace` directives that point at a SIBLING
// workspace root admit cross-root import resolution — the SAME evidence-only posture as includes
// (unique-or-degrade, never name-based). Config bytes are read (workspace-only, in canonical root order)
// by buildPreciseIncludeAdj; parsing is a PURE function of those bytes, so the merged graph stays
// deterministic (a warm==cold re-run reads identical config bytes ⇒ identical aliases ⇒ identical edges).
// On a single-root run NONE of this fires (buildPreciseIncludeAdj builds no WsIncludeCtx) — byte-identical.

// Read a config file's bytes (small text file; capped). Empty on any open/size/read failure — the caller
// treats an empty result as "no config" (no aliases contributed). Workspace-only; not on any hot path.
inline std::string readConfigBytes( const std::string& path )
{
    std::string out;
    std::FILE*  f = std::fopen( path.c_str(), "rb" );
    if( !f )
    {
        return out;
    }
    std::fseek( f, 0, SEEK_END );
    const long sz = std::ftell( f );
    if( sz > 0 && sz <= ( 1 << 20 ) )                                   // cap 1 MiB — config files are tiny; ignore junk
    {
        std::fseek( f, 0, SEEK_SET );
        out.resize( std::size_t( sz ) );
        const std::size_t n = std::fread( out.data(), 1, out.size(), f );
        out.resize( n );
    }
    std::fclose( f );
    return out;
}

// is `abs` inside (or equal to) `root`? Used to KEEP only aliases whose destination ESCAPES their own root
// (a cross-root alias) — an intra-root alias stays external exactly as a bare specifier is single-root.
inline bool pathIsUnder( std::string_view abs, std::string_view root ) noexcept
{
    if( abs == root )
    {
        return true;
    }
    return abs.size() > root.size() && abs.compare( 0, root.size(), root ) == 0 && abs[ root.size() ] == '/';
}

// trim ASCII whitespace from both ends of a view (no allocation).
inline std::string_view trimWs( std::string_view s ) noexcept
{
    while( !s.empty() && ( s.front() == ' ' || s.front() == '\t' || s.front() == '\r' ) )
    {
        s.remove_prefix( 1 );
    }
    while( !s.empty() && ( s.back() == ' ' || s.back() == '\t' || s.back() == '\r' ) )
    {
        s.remove_suffix( 1 );
    }
    return s;
}

// Parse go.mod `replace OLD [ver] => NEW [ver]` directives (both single-line and grouped `replace ( … )`).
// A filesystem NEW target (`./…`, `../…`, or absolute) is resolved relative to the go.mod's root dir; when it
// ESCAPES `rootReal` (points at a sibling root) we mint a Go alias: module-path `OLD` → the on-disk dir.
// Registry/version targets (a bare module path on the RHS) are NOT filesystem replaces → ignored.
inline void parseGoModReplaces( const std::string& bytes, std::uint32_t fromRoot, const std::string& rootReal,
                                std::vector<ConfigAlias>& out )
{
    const auto firstTok = []( std::string_view s ) noexcept
    {
        const std::size_t sp = s.find_first_of( " \t" );
        return sp == std::string_view::npos ? s : s.substr( 0, sp );
    };
    bool        inGroup = false;
    std::size_t i       = 0;
    while( i < bytes.size() )
    {
        std::size_t e = bytes.find( '\n', i );
        if( e == std::string::npos )
        {
            e = bytes.size();
        }
        std::string_view t = trimWs( std::string_view( bytes.data() + i, e - i ) );
        i = e + 1;
        if( t.empty() || t.substr( 0, 2 ) == "//" )
        {
            continue; // blank / comment
        }
        std::string_view body;
        if( inGroup )
        {
            if( t.front() == ')' ) { inGroup = false; continue; }
            body = t;
        }
        else if( t.substr( 0, 7 ) == "replace" )
        {
            std::string_view rest = trimWs( t.substr( 7 ) );
            if( rest.empty() )
            {
                continue;
            }
            if( rest.front() == '(' )
            {
                inGroup = true;
                rest = trimWs( rest.substr( 1 ) );
                if( rest.empty() )
                {
                    continue;
                }
            }
            body = rest;
        }
        else
        {
            continue;
        }

        const std::size_t arrow = body.find( "=>" );
        if( arrow == std::string_view::npos )
        {
            continue;
        }
        const std::string_view mod = firstTok( trimWs( body.substr( 0, arrow ) ) );
        const std::string_view tgt = firstTok( trimWs( body.substr( arrow + 2 ) ) );
        if( mod.empty() || tgt.empty() )
        {
            continue;
        }
        if( tgt.front() != '.' && tgt.front() != '/' )
        {
            continue; // not a filesystem replace → registry/version
        }
        std::string abs = ( tgt.front() == '/' ) ? std::string( tgt )
                                                  : lexicalNormalize( rootReal + "/" + std::string( tgt ) );
        if( abs.empty() || pathIsUnder( abs, rootReal ) )
        {
            continue; // must ESCAPE this root (cross-root only)
        }
        out.push_back( ConfigAlias{ fromRoot, std::string( mod ), std::move( abs ), true, true } );
    }
}

// Parse tsconfig.json `compilerOptions.paths` into aliases (a tolerant text scan — the coordinator-sanctioned
// line/text scanner, NOT a full JSON parser). Each `"alias/*": ["../dest/*"]` entry whose destination
// (resolved through `baseUrl`) ESCAPES `rootReal` mints a TS alias. A trailing `*` marks a wildcard (tail
// appended); the first array element is the destination. Only the FIRST tsconfig at the root is consulted.
inline void parseTsconfigPaths( const std::string& bytes, std::uint32_t fromRoot, const std::string& rootReal,
                                std::vector<ConfigAlias>& out )
{
    // read a JSON string whose opening quote is at bytes[q]; returns the (minimally-unescaped) content and
    // advances q past the closing quote.
    const auto readQuoted = [ & ]( std::size_t& q ) -> std::string
    {
        std::string s;
        ++q;                                                            // past the opening quote
        while( q < bytes.size() && bytes[ q ] != '"' )
        {
            if( bytes[ q ] == '\\' && q + 1 < bytes.size() ) { s.push_back( bytes[ q + 1 ] ); q += 2; continue; }
            s.push_back( bytes[ q ] );
            ++q;
        }
        if( q < bytes.size() )
        {
            ++q; // past the closing quote
        }
        return s;
    };

    // baseUrl (default "."), resolved to an absolute base the `paths` targets hang off.
    std::string baseUrl = ".";
    if( const std::size_t bp = bytes.find( "\"baseUrl\"" ); bp != std::string::npos )
    {
        if( const std::size_t c = bytes.find( ':', bp ); c != std::string::npos )
        {
            if( const std::size_t q = bytes.find( '"', c ); q != std::string::npos ) { std::size_t p = q; baseUrl = readQuoted( p ); }
        }
    }
    const std::string baseAbs = lexicalNormalize( rootReal + "/" + baseUrl );

    const std::size_t pp = bytes.find( "\"paths\"" );
    if( pp == std::string::npos )
    {
        return;
    }
    std::size_t p = bytes.find( '{', pp );
    if( p == std::string::npos )
    {
        return;
    }
    ++p;
    int depth = 1;
    while( p < bytes.size() && depth > 0 )
    {
        const char ch = bytes[ p ];
        if( ch == '{' )      { ++depth; ++p; continue; }
        if( ch == '}' )      { --depth; ++p; continue; }
        if( ch != '"' )      { ++p; continue; }

        std::size_t kp  = p;
        std::string key = readQuoted( kp );
        const std::size_t c = bytes.find( ':', kp );
        if( c == std::string::npos ) { p = kp; continue; }
        const std::size_t q = bytes.find( '"', c );                     // the first string in the value array
        if( q == std::string::npos ) { p = kp; continue; }
        std::size_t vp  = q;
        std::string val = readQuoted( vp );
        p = vp;

        bool wild = false;
        const auto stripStar = [ & ]( std::string& s ) { if( !s.empty() && s.back() == '*' ) { wild = true; s.pop_back(); } };
        stripStar( key );
        stripStar( val );
        if( key.empty() || val.empty() )
        {
            continue;
        }
        std::string abs = lexicalNormalize( baseAbs + "/" + val );
        while( !abs.empty() && abs.back() == '/' )
        {
            abs.pop_back();
        }
        if( abs.empty() || pathIsUnder( abs, rootReal ) )
        {
            continue; // cross-root only
        }
        out.push_back( ConfigAlias{ fromRoot, std::move( key ), std::move( abs ), wild, false } );
    }
}

// Resolve a Go `import "path"` to a concrete repo fileId via a go.mod `replace` alias (§3.2). Single-root /
// no-alias → kNoFile (DEFERRED, exactly as before). A matching alias maps the import path onto an on-disk
// PACKAGE directory in the destination root; the package resolves to a file only when that directory holds
// EXACTLY ONE `.go` file (unique-or-degrade — a package is a directory, so ≥2 files is honestly ambiguous).
inline std::uint32_t resolveGoImport( std::string_view target, const WsIncludeCtx* ws, std::uint32_t includerFileId )
{
    if( !ws || ws->configAliases.empty() || includerFileId == kNoFile || includerFileId >= ws->fileRoot->size() )
    {
        return kNoFile;
    }

    // the import path — the first quoted token (a single-line `import "x"`); grouped imports collapse to one
    // node upstream and are left unresolved (honest — no reliable per-spec split without a grammar change).
    std::string_view imp = target;
    if( const std::size_t q0 = imp.find( '"' ); q0 != std::string_view::npos )
    {
        const std::size_t q1 = imp.find( '"', q0 + 1 );
        if( q1 != std::string_view::npos )
        {
            imp = imp.substr( q0 + 1, q1 - q0 - 1 );
        }
        else
        {
            return kNoFile;
        }
    }
    if( imp.empty() )
    {
        return kNoFile;
    }

    const std::uint32_t incRoot = ( *ws->fileRoot )[ includerFileId ];
    std::uint32_t       hit     = kNoFile;
    const auto consider = [ & ]( std::uint32_t f )
    {
        if( f == kNoFile )
        {
            return;
        }
        if( hit == kNoFile )
        {
            hit = f;
        }
        else if( f != hit )
        {
            hit = kNoFile - 1; // second distinct file → ambiguous → degrade
        }
    };
    for( const ConfigAlias& al : ws->configAliases )
    {
        if( !al.isGo || al.fromRoot != incRoot )
        {
            continue;
        }
        std::string_view tail;
        if( imp == al.spec ) { /* the module root package */ }
        else if( imp.size() > al.spec.size() && imp.compare( 0, al.spec.size(), al.spec ) == 0 && imp[ al.spec.size() ] == '/' )
        {
            tail = imp.substr( al.spec.size() + 1 );
        }
        else
        {
            continue;
        }

        std::string dir = al.absDest;
        if( !tail.empty() ) { dir.push_back( '/' ); dir.append( tail ); }
        dir = lexicalNormalize( dir );
        if( dir.empty() )
        {
            continue;
        }

        // the single `.go` file DIRECTLY inside `dir` (a package = a directory). Counting distinct fileIds
        // is order-independent, so iterating the (unordered) absIndex still yields a deterministic result.
        const std::string prefix = dir + "/";
        for( const auto& [ apath, fid ] : ws->absIndex )
        {
            if( apath.size() <= prefix.size() || apath.compare( 0, prefix.size(), prefix ) != 0 )
            {
                continue;
            }
            if( apath.find( '/', prefix.size() ) != std::string::npos )
            {
                continue; // not a direct child (deeper package)
            }
            if( apath.size() < 3 || apath.compare( apath.size() - 3, 3, ".go" ) != 0 )
            {
                continue;
            }
            consider( fid );
        }
    }
    return ( hit == kNoFile || hit == kNoFile - 1 ) ? kNoFile : hit;
}

// ─── kParserVer 81 Step-As: Bash / Ruby / Lua / Elixir ───────────────────────────────────────────────
//
// One shared shape, the same one Python and TS already use: build a small FIXED list of candidate
// relative paths, probe each through joinNormalizeLookup, and resolve IFF exactly ONE distinct fileId
// comes back. Two or more ⇒ kNoFile (degrade, no guess); zero ⇒ kNoFile. Nothing here ever falls back to
// a basename or a path SUFFIX match, which is the one shortcut that would make all four of these look
// far better on a benchmark and be wrong in a way no user could see.

// The unique-or-degrade accumulator every Step-A below shares — `hit` holds the single fileId found so
// far, `kNoFile - 1` is the "a second, different file also answered" tombstone (≠ any real id), and the
// caller reads the result through `result()`.
struct UniqueProbe
{
    std::uint32_t hit = kNoFile;

    void consider( std::uint32_t f ) noexcept
    {
        if( f == kNoFile )      { return; }
        if( hit == kNoFile )    { hit = f; }
        else if( f != hit )     { hit = kNoFile - 1; }
    }
    [[nodiscard]] std::uint32_t result() const noexcept { return ( hit == kNoFile || hit == kNoFile - 1 ) ? kNoFile : hit; }
};

// Probe `rel` against the includer's own directory AND every ANCESTOR of it, unique-or-degrade.
//
// This is the answer to "the anchor is not knowable, so which base do I join against?" — the question a
// `. "$ROOT/scripts/x.sh"`, a Lua `require "pkg.mod"` and a Ruby load-path `require "lib/x"` all ask, and
// the three earlier Step-As (Python/TS/Rust) never had to, because their anchors are stated in the
// specifier. The first implementation of this probed the includer's dir plus an EMPTY base, on the
// reasoning that an empty base is "the crawl root". IT IS NOT, and the bug that exposed it is worth
// recording: `ing.files` carry the crawl root exactly as it was WRITTEN on the command line, so
// `ripwire .` stores `test/foo.sh` (empty base == the root, probe works) while `ripwire /abs/repo` stores
// `/abs/repo/test/foo.sh` (empty base matches nothing, probe silently inert). Measured on this repo:
// `ripwire .` resolved 26 of 29 `source` directives and `ripwire "$PWD"` resolved 13 — the SAME tree,
// the same files, a different spelling of the root. An MCP server always passes an absolute path, so the
// inert half would have been the half real users got.
//
// Walking ancestors fixes it without adding a crawl-root parameter and without moving any other language:
// the ancestor chain of an absolute includer reaches the absolute crawl root, the chain of a relative one
// reaches the empty base, and in both cases it stops finding matches exactly at the root because no
// fileIndex key lives above it. It is also the more honest rule on its own terms — an unknown `$VAR` is
// SOME directory, and the directories there is evidence for are the ones the file actually sits under.
// The depth cap is a hostile-input bound (a path cannot have 64 meaningful ancestors); exceeding it
// simply stops probing, which can only lose an edge, never invent one.
inline void probeUpward( std::string_view baseDir, std::string_view rel, UniqueProbe& p,
                         const HashMap<std::string, std::uint32_t>& fileIndex,
                         const WsIncludeCtx* ws, std::uint32_t includerFileId )
{
    std::string_view dir = baseDir;
    for( int guard = 0; guard < 64; ++guard )
    {
        p.consider( joinNormalizeLookup( dir, rel, fileIndex, ws, includerFileId ) );
        if( dir.empty() )
        {
            return;
        }
        const std::size_t slash = dir.rfind( '/' );
        dir = ( slash == std::string_view::npos ) ? std::string_view{} : dir.substr( 0, slash );
    }
}

// How far into `spec` the shell expansion that starts at `spec[i]` runs, or i when nothing starts there.
// Handles `$(cmd)` (paren-balanced, so `$(dirname "$0")` closes correctly), backtick substitution,
// `${VAR…}` (brace-balanced), and a bare `$NAME` / `$1` / `$@`. Pure, bounds-checked, no allocation.
inline std::size_t shellExpansionEnd( std::string_view spec, std::size_t i ) noexcept
{
    if( i >= spec.size() )
    {
        return i;
    }
    if( spec[i] == '`' )
    {
        const std::size_t close = spec.find( '`', i + 1 );
        return ( close == std::string_view::npos ) ? spec.size() : close + 1;
    }
    if( spec[i] != '$' || i + 1 >= spec.size() )
    {
        return i;
    }
    const char c = spec[ i + 1 ];
    if( c == '(' || c == '{' )
    {
        const char open = c, close = ( c == '(' ) ? ')' : '}';
        int depth = 0;
        for( std::size_t k = i + 1; k < spec.size(); ++k )
        {
            if( spec[k] == open )       { ++depth; }
            else if( spec[k] == close ) { if( --depth == 0 ) { return k + 1; } }
        }
        return spec.size();   // unterminated → the whole rest is expansion, so no literal tail survives
    }
    std::size_t k = i + 1;
    if( ( c >= 'A' && c <= 'Z' ) || ( c >= 'a' && c <= 'z' ) || c == '_' )
    {
        while( k < spec.size() && ( ( spec[k] >= 'A' && spec[k] <= 'Z' ) || ( spec[k] >= 'a' && spec[k] <= 'z' )
                                    || ( spec[k] >= '0' && spec[k] <= '9' ) || spec[k] == '_' ) )
        {
            ++k;
        }
        return k;
    }
    return k + 1;   // `$1`, `$@`, `$*`, `$?`, `$$` — one character
}

// ── Bash Step-A — SOUND, with an explicitly FLOORED case. `source FILE` / `. FILE`.
// The specifier is a written path, so there is no name→path convention at all; the whole difficulty is
// that the path is usually built out of a variable (`. "$ROOT/scripts/cxxstd.sh"` — 29 of 29 source lines
// in this repo's own test/ take that shape, so the expansion case IS the ordinary case).
//
// The rule: reduce the specifier to the LITERAL TAIL after its last expansion. If that tail begins with
// `/`, everything variable is confined to the DIRECTORY part and the remainder is a real relative path —
// probe it, both relative-to-includer and relative-to-crawl-root, unique-or-degrade. If it does not
// (`"$1"`, `"$dir/$name.sh"`, `"${p}.sh"`), the FILENAME itself is variable and nothing is knowable:
// return kNoFile. That is a FLOOR, not a zero — the directive is still captured and still shows in
// `--deps` as `<inc t="$1"/>` with no edge, the same disclosure an unresolvable `#include <vector>` gets.
// An absolute or `~`-rooted literal is outside the crawl by construction and also floors.
//
// Probing root-relative for a variable-anchored path is the same move Python's ABSOLUTE-import probe
// makes, and it is what makes `$ROOT/scripts/cxxstd.sh` land on `scripts/cxxstd.sh`: `$ROOT` is unknown,
// but the crawl root is the only anchor in evidence and unique-or-degrade catches it being the wrong one.
inline std::uint32_t resolveBashSource( std::string_view includerPath, std::string_view target,
                                        const HashMap<std::string, std::uint32_t>& fileIndex,
                                        const WsIncludeCtx* ws = nullptr, std::uint32_t includerFileId = kNoFile )
{
    if( target.empty() || target.front() == '~' )
    {
        return kNoFile;
    }
    std::size_t lastEnd = 0;
    for( std::size_t i = 0; i < target.size(); )
    {
        const std::size_t e = shellExpansionEnd( target, i );
        if( e > i ) { lastEnd = e;  i = e; }
        else        { ++i; }
    }
    std::string_view rel        = target;
    const bool       anchorKnown = ( lastEnd == 0 );
    if( !anchorKnown )
    {
        rel = target.substr( lastEnd );
        if( rel.empty() || rel.front() != '/' )
        {
            return kNoFile;   // the FILENAME is variable — floored, disclosed at the site
        }
        rel.remove_prefix( 1 );
    }
    if( rel.empty() || rel.front() == '/' )
    {
        return kNoFile;       // absolute literal → outside the crawl
    }

    UniqueProbe p;
    if( anchorKnown && rel.front() == '.' )
    {
        // `./x.sh` / `../x.sh` — the anchor IS stated, relative to the sourcing file. One probe, no walk.
        p.consider( joinNormalizeLookup( includerDir( includerPath ), rel, fileIndex, ws, includerFileId ) );
        return p.result();
    }
    probeUpward( includerDir( includerPath ), rel, p, fileIndex, ws, includerFileId );
    return p.result();
}

// ── Lua Step-A — SOUND. `require "a.b"` → package.path's dotted convention: dots become directory
// separators and the module is either `a/b.lua` or the package form `a/b/init.lua`. Probed relative to
// the requiring file AND against a small fixed list of source roots — "" (the crawl root), `src/` and
// `lua/`, the last because a Neovim plugin's `require("plug.mod")` lives at `lua/plug/mod.lua` and that
// is a large fraction of the Lua in the world. Unique-or-degrade across every probe, so a tree that
// answers one specifier from two roots resolves to NEITHER rather than to whichever was probed first.
// A specifier that names nothing in the tree (`require "socket"`, a C rock) is simply unresolved: no
// edge, and the directive is still visible in `--deps` as its own `<inc t="socket"/>` row.
inline std::uint32_t resolveLuaRequire( std::string_view includerPath, std::string_view target,
                                        const HashMap<std::string, std::uint32_t>& fileIndex,
                                        const WsIncludeCtx* ws = nullptr, std::uint32_t includerFileId = kNoFile )
{
    if( target.empty() )
    {
        return kNoFile;
    }
    std::string modPath;
    modPath.reserve( target.size() );
    for( const char c : target )
    {
        modPath.push_back( c == '.' ? '/' : c );
    }
    if( modPath.empty() || modPath.front() == '/' )
    {
        return kNoFile;
    }
    const std::string cand[ 2 ] = { modPath + ".lua", modPath + "/init.lua" };
    static constexpr std::string_view kRoots[] = { "", "src/", "lua/" };

    UniqueProbe p;
    const std::string_view dir = includerDir( includerPath );
    for( const std::string& c : cand )
    {
        for( const std::string_view r : kRoots )
        {
            probeUpward( dir, std::string( r ) + c, p, fileIndex, ws, includerFileId );
        }
    }
    return p.result();
}

// ── Ruby Step-A — SOUND. Two rules behind one spelling, told apart by a LEADING DOT (the extractor
// normalizes `require_relative "x"` to `./x`; see ingest_relations.h::rubyRequireTarget):
//   * a dotted specifier is relative to the requiring FILE — the exact analogue of a C quote-include;
//   * a bare specifier is searched on $LOAD_PATH, which this tool does not have. It probes the crawl root
//     plus the four directories that are on it in practice (`lib/` for every gem by RubyGems convention,
//     `app/`, `test/`, `spec/`), unique-or-degrade.
// `.rb` is appended when the specifier does not already carry it, and the verbatim spelling is probed
// first for the `require "x.rb"` form.
//
// A bare specifier that resolves to nothing — `require "json"`, `require "rails"` — is EXTERNAL, not
// unresolved: it names a gem outside the indexed tree, exactly as a bare TS specifier names a node_modules
// package. Both produce the same thing here (no edge), and the distinction is stated rather than encoded
// because this layer emits FILE edges only; the name-level census that spends `external=` vs `unresolved=`
// is graph.h's, and it is not fed by Ruby requires this round (see the ROUND FLOOR note in
// buildPreciseIncludeAdjWithContext).
inline std::uint32_t resolveRubyRequire( std::string_view includerPath, std::string_view target,
                                         const HashMap<std::string, std::uint32_t>& fileIndex,
                                         const WsIncludeCtx* ws = nullptr, std::uint32_t includerFileId = kNoFile )
{
    if( target.empty() )
    {
        return kNoFile;
    }
    const bool  hasRb = ( target.size() > 3 && target.substr( target.size() - 3 ) == ".rb" );
    std::string withRb( target );
    if( !hasRb ) { withRb += ".rb"; }

    UniqueProbe p;
    if( target.front() == '.' )                       // require_relative (and a dotted `require`) — file-relative
    {
        const std::string_view dir = includerDir( includerPath );
        p.consider( joinNormalizeLookup( dir, withRb, fileIndex, ws, includerFileId ) );
        if( hasRb )
        {
            p.consider( joinNormalizeLookup( dir, target, fileIndex, ws, includerFileId ) );
        }
        return p.result();
    }
    static constexpr std::string_view kLoadRoots[] = { "", "lib/", "app/", "test/", "spec/" };
    for( const std::string_view r : kLoadRoots )
    {
        probeUpward( includerDir( includerPath ), std::string( r ) + withRb, p, fileIndex, ws, includerFileId );
    }
    return p.result();
}

// ── Elixir Step-A — SOUND, and the only one of the four that uses EVIDENCE instead of a convention.
// `MyApp.Foo` conventionally lives at `lib/my_app/foo.ex`, and a path rule could be written for it
// (CamelCase → snake_case, `lib/` prefix). It is not written, because the corpus already STATES where
// each module lives: every Elixir file carries a `defmodule MyApp.Foo` whose captured symbol name is the
// full dotted module. The index built from those definitions resolves umbrella apps, `test/support/`,
// generated paths and any other layout the convention would have missed — and it can never invent a
// module that does not exist. Two files defining one module ⇒ ambiguous ⇒ kNoFile (the index stores the
// same `kNoFile - 1` tombstone every other Step-A uses).
// A module the index does not hold (`Logger`, `Ecto.Query`, `GenServer`) is outside the tree: no edge.
inline std::uint32_t resolveElixirModule( std::string_view target, const HashMap<std::string, std::uint32_t>* moduleIndex )
{
    if( target.empty() || moduleIndex == nullptr )
    {
        return kNoFile;
    }
    const auto it = moduleIndex->find( std::string( target ) );
    if( it == moduleIndex->end() || it->second == kNoFile - 1 )
    {
        return kNoFile;
    }
    return it->second;
}

// The Elixir module index (kParserVer 81): `defmodule MyApp.Foo` → the file that holds it. Built from the
// corpus's OWN definitions, never from a name→path convention — see resolveElixirModule for why. A module
// two files define is tombstoned `kNoFile - 1` (ambiguous ⇒ no edge), the same unique-or-degrade rule every
// other Step-A applies, applied at index-build time instead of probe time.
//
// Built ONLY when the corpus actually holds an Elixir directive, and EMPTY otherwise: on a tree with no
// `.ex`/`.exs` includer this is one pass over `ing.includes` that finds nothing and allocates nothing, so
// every other language's cost is unchanged. An empty result is the caller's signal to pass nullptr.
//
// Resolve Elixir file dependencies from declared module identities, independent of the file layout.
// Lexical aliases are already expanded at ingest. Function calls use ElixirResolver's separate
// module/name/arity index; this unique-module index serves --deps/--arch/--impact/--cochange.
inline HashMap<std::string, std::uint32_t> buildElixirModuleIndex( const IngestResult& ing )
{
    PROFILE_SCOPE_DESCRIBE( "resolve/elixir: module index" );
    HashMap<std::string, std::uint32_t> modules;
    const std::uint32_t F = std::uint32_t( ing.files.size() );
    bool anyElixirDirective = false;
    for( const Include& inc : ing.includes )
    {
        if( inc.fileId < F && includeLangOf( ing.files[ inc.fileId ] ) == IncludeLang::Elixir )
        {
            anyElixirDirective = true;
            break;
        }
    }
    if( !anyElixirDirective )
    {
        return modules;
    }
    modules.reserve( ing.files.size() );
    for( const Symbol& s : ing.symbols )
    {
        if( s.lang != Lang::Elixir || !s.scope.empty() || s.name.empty() || s.fileId >= F
            || ( s.kind != SymKind::Other && s.kind != SymKind::Class && s.kind != SymKind::Struct && s.kind != SymKind::Interface ) )
        {
            continue;   // only module/protocol/struct containers, never attributes or type declarations
        }
        const auto [ it, inserted ] = modules.try_emplace( s.name, s.fileId );
        if( !inserted && it->second != s.fileId )
        {
            it->second = kNoFile - 1;   // two files define this module → ambiguous, never choose one
        }
    }
    return modules;
}

// ─── Ruby constant index (parser version 82) ─────────────────────────────────────────────────────────────
// The Ruby twin of the Elixir defmodule index, for the spellings a Rails codebase actually depends through:
// `class X < Base`, `include M` / `extend M` / `prepend M`, and the path-less `autoload :Name` — captured
// as Include records with isSymbolic set (ingest_relations.h) and resolved HERE, never by a path probe.
// Two rules, both Ruby's own:
//   * DEFINERS. Every class/module OPEN the corpus holds (ing.constOpens, model.h) is given its fully-
//     qualified constant: an open's nesting is its enclosing opens by BYTE-SPAN containment (the same
//     containment that attributes a Reference to its def), `::X` is absolute, and a compact `class A::B`
//     nested in `module X` names X::A::B when the tree opens X::A anywhere, else ::A::B — Module.nesting
//     first, then Object, which is what Ruby does. An open whose body holds nothing but nested opens
//     (`namespaceOnly`) is a NAMESPACE WRAPPER: it nests, but it defines nothing and is not a definer.
//     A constant is then indexed to the SORTED set of files that give it a body. One file — the common
//     case, 2628 of 2633 constants on a 3532-file Rails app. Several — a genuine reopening (a monkey patch,
//     a decorator, a core_ext) — and a reference edges to EVERY one of them: change any and the constant
//     changes, which is what --deps measures. That is MULTIPLICITY (every answer is right), deliberately
//     distinct from the specifier AMBIGUITY every other Step-A degrades on (`require "shared"` answered by
//     two files: exactly one is right and this tool cannot tell which). Only the latter resolves to nothing.
//   * REFERENCES. A written constant `Name::Sub` at a site whose lexical nesting is [A, A::B] is looked
//     up as A::B::Name::Sub, then A::Name::Sub, then Name::Sub — innermost first, first hit wins. `::Name`
//     skips the nesting. The site's nesting comes from Include::byte by containment; a superclass carries
//     its CLASS's own start byte, which containment reads as outside that class — the superclass expression
//     is evaluated in the enclosing scope, exactly as Ruby does.
// FLOORS (test/rubyconstcheck.sh pins each): the ancestor half of Ruby lookup (a constant inherited from a
// superclass or an included module) is not walked; `Point = Struct.new(…)` aliases are not opens and are
// not indexed; `const_get` / string-built constants are never read.
// Built ONLY when the corpus holds a symbolic directive, EMPTY otherwise: on any non-Ruby tree this is one
// pass over ing.includes that finds nothing and allocates nothing.
struct RubyOpenRec
{
    std::uint32_t startByte     = 0;
    std::uint32_t endByte       = 0;
    std::uint32_t parent        = kNoFile;   // index into the same file's opens; kNoFile at top level
    bool          namespaceOnly = false;
    std::string   written;
    std::string   fqn;                       // the resolved fully-qualified constant
};

struct RubyConstantIndex
{
    std::vector<std::vector<RubyOpenRec>>                          opensByFile;   // per file, sorted by (startByte asc, endByte desc)
    HashMap<std::string, std::pair<std::uint32_t, std::uint32_t>>  spans;         // FQN → (offset, count) into `files` — SoA, one flat table
    std::vector<std::uint32_t>                                     files;         // definer fileIds, sorted inside each span
    bool empty() const noexcept { return spans.empty(); }
};

inline bool rubyConstIsAbsolute( std::string_view w ) noexcept
{
    return w.size() > 2 && w[0] == ':' && w[1] == ':';
}

// The innermost open of `opens` whose span contains `byte` STRICTLY after its start (kNoFile when none). The
// last open that starts at or before `byte` is found by binary search; when it has already closed, the
// containing open is on its parent chain (opens are properly nested), so the walk is ancestors only.
inline std::uint32_t rubyInnermostOpen( const std::vector<RubyOpenRec>& opens, std::uint32_t byte ) noexcept
{
    const auto it = std::upper_bound( opens.begin(), opens.end(), byte,
                                      []( std::uint32_t b, const RubyOpenRec& o ) noexcept { return b < o.startByte; } );
    if( it == opens.begin() )
    {
        return kNoFile;
    }
    std::uint32_t i = std::uint32_t( it - opens.begin() ) - 1u;
    while( i != kNoFile && !( opens[ i ].startByte < byte && byte < opens[ i ].endByte ) )
    {
        i = opens[ i ].parent;
    }
    return i;
}

inline RubyConstantIndex buildRubyConstantIndex( const IngestResult& ing )
{
    PROFILE_SCOPE_DESCRIBE( "resolve/ruby: constant index" );
    RubyConstantIndex ix;
    bool anySymbolic = false;
    for( const Include& inc : ing.includes )
    {
        if( inc.isSymbolic )
        {
            anySymbolic = true;
            break;
        }
    }
    if( !anySymbolic || ing.constOpens.empty() )
    {
        return ix;
    }
    const std::uint32_t F = std::uint32_t( ing.files.size() );
    ix.opensByFile.resize( F );
    for( const ConstOpen& co : ing.constOpens )
    {
        if( co.fileId < F )
        {
            ix.opensByFile[ co.fileId ].push_back( RubyOpenRec{ co.startByte, co.endByte, kNoFile, co.namespaceOnly, co.written, {} } );
        }
    }

    // Pass 1 — per file: canonical order, parent links by containment, and the NAIVE constant of every open
    // (nesting joined as written). The naive set is the existence oracle pass 2 consults.
    HashMap<std::string, char> naive;
    for( std::uint32_t f = 0; f < F; ++f )
    {
        std::vector<RubyOpenRec>& opens = ix.opensByFile[ f ];
        std::sort( opens.begin(), opens.end(), []( const RubyOpenRec& a, const RubyOpenRec& b ) noexcept
                   { return a.startByte != b.startByte ? a.startByte < b.startByte : a.endByte > b.endByte; } );
        std::vector<std::uint32_t> stack;
        for( std::uint32_t i = 0; i < opens.size(); ++i )
        {
            while( !stack.empty() && opens[ stack.back() ].endByte <= opens[ i ].startByte )
            {
                stack.pop_back();
            }
            opens[ i ].parent = stack.empty() ? kNoFile : stack.back();
            const std::string_view w = opens[ i ].written;
            if( rubyConstIsAbsolute( w ) )
            {
                opens[ i ].fqn.assign( w.substr( 2 ) );
            }
            else if( opens[ i ].parent == kNoFile )
            {
                opens[ i ].fqn.assign( w );
            }
            else
            {
                opens[ i ].fqn = opens[ opens[ i ].parent ].fqn; opens[ i ].fqn += "::"; opens[ i ].fqn += w;
            }
            naive.try_emplace( opens[ i ].fqn, 1 );
            stack.push_back( i );
        }
    }

    // Pass 2 — the FINAL constant, top-down (a parent precedes its children in start-byte order, so every
    // parent's fqn is final when a child reads it). Only a compact name nested in an open (`class A::B`
    // inside `module X`) differs from its naive form: its head `A` is looked up Module.nesting-first against
    // the naive set, then falls to Object (top level) — which is where Ruby's own lookup ends up.
    std::vector<std::pair<std::string, std::uint32_t>> definers;
    for( std::uint32_t f = 0; f < F; ++f )
    {
        std::vector<RubyOpenRec>& opens = ix.opensByFile[ f ];
        for( std::uint32_t i = 0; i < opens.size(); ++i )
        {
            RubyOpenRec&           o = opens[ i ];
            const std::string_view w = o.written;
            if( rubyConstIsAbsolute( w ) )
            {
                o.fqn.assign( w.substr( 2 ) );
            }
            else if( o.parent == kNoFile )
            {
                o.fqn.assign( w );
            }
            else if( const std::size_t sep = w.find( "::" ); sep == std::string_view::npos )
            {
                o.fqn = opens[ o.parent ].fqn; o.fqn += "::"; o.fqn += w;
            }
            else
            {
                const std::string_view head = w.substr( 0, sep );
                std::string            probe;
                bool                   found = false;
                for( std::uint32_t k = o.parent; k != kNoFile; k = opens[ k ].parent )
                {
                    probe = opens[ k ].fqn; probe += "::"; probe += head;
                    if( naive.find( probe ) != naive.end() )
                    {
                        o.fqn = opens[ k ].fqn; o.fqn += "::"; o.fqn += w;
                        found = true;
                        break;
                    }
                }
                if( !found )
                {
                    o.fqn.assign( w );   // Object-level: the tree opens no X::A on the chain, so `A::B` is ::A::B
                }
            }
            if( !o.namespaceOnly )
            {
                definers.emplace_back( o.fqn, f );
            }
        }
    }

    // The SoA span table: one flat, sorted list of definer fileIds; each constant owns a contiguous run.
    std::sort( definers.begin(), definers.end() );
    definers.erase( std::unique( definers.begin(), definers.end() ), definers.end() );
    ix.files.reserve( definers.size() );
    for( std::size_t i = 0; i < definers.size(); )
    {
        std::size_t j = i;
        while( j < definers.size() && definers[ j ].first == definers[ i ].first )
        {
            ix.files.push_back( definers[ j ].second );
            ++j;
        }
        ix.spans.emplace( definers[ i ].first, std::pair<std::uint32_t, std::uint32_t>{ std::uint32_t( i ), std::uint32_t( j - i ) } );
        i = j;
    }
    return ix;
}

// Resolve one symbolic Ruby directive to its (offset, count) run in `ix.files` — {0,0} when nothing in the
// tree defines it. `memo` is keyed by (the WHOLE nesting chain, written target): two sites with the same
// Module.nesting and spelling — the whole of a Rails controller's `include`s, every model's `< ApplicationRecord`
// — resolve once. The key must be the chain, not its innermost open: `module A; module B` and the compact
// `module A::B` share the innermost FQN A::B but look `Name` up along different chains (A::B::Name, A::Name,
// Name vs A::B::Name, Name), so keying on the innermost open alone let whichever site came first fix the other's
// answer — and cold and warm caches visit the sites in different orders (test/rubyconstcheck.sh pins both).
// Deterministic: a pure function of the index and the site.
inline std::pair<std::uint32_t, std::uint32_t> resolveRubyConstant( const RubyConstantIndex& ix,
                                                                    HashMap<std::string, std::pair<std::uint32_t, std::uint32_t>>& memo,
                                                                    std::uint32_t fileId, std::uint32_t byte, std::string_view written )
{
    static constexpr std::pair<std::uint32_t, std::uint32_t> kNone{ 0u, 0u };
    if( written.empty() || ix.empty() || fileId >= ix.opensByFile.size() )
    {
        return kNone;
    }
    const std::vector<RubyOpenRec>& opens = ix.opensByFile[ fileId ];
    const std::uint32_t             inner = rubyInnermostOpen( opens, byte );
    std::string key;
    for( std::uint32_t k = inner; k != kNoFile; k = opens[ k ].parent )
    {
        key += opens[ k ].fqn;
        key += '\x1e'; // one segment per open on the chain — the whole Module.nesting, innermost first
    }
    key += '\x1f';
    key += written;
    if( const auto hit = memo.find( key ); hit != memo.end() )
    {
        return hit->second;
    }
    std::pair<std::uint32_t, std::uint32_t> result = kNone;
    const auto lookup = [ &ix, &result ]( const std::string& fqn ) noexcept
    {
        const auto it = ix.spans.find( fqn );
        if( it == ix.spans.end() )
        {
            return false;
        }
        result = it->second;
        return true;
    };
    if( rubyConstIsAbsolute( written ) )
    {
        lookup( std::string( written.substr( 2 ) ) );
    }
    else
    {
        std::string cand;
        bool        found = false;
        for( std::uint32_t k = inner; k != kNoFile && !found; k = opens[ k ].parent )
        {
            cand = opens[ k ].fqn; cand += "::"; cand += written;
            found = lookup( cand );
        }
        if( !found )
        {
            lookup( std::string( written ) );
        }
    }
    memo.emplace( std::move( key ), result );
    return result;
}

// Resolve ONE #include / import target to a concrete repo fileId by LEXICAL path semantics, dispatched on
// the INCLUDER's language (its file extension). `fileIndex` maps each canonical `ing.files` path → its
// fileId. `crateRootDir`/`hasCrateRoot` carry the Rust crate root (empty/false for non-Rust);
// `moduleIndex` carries the Elixir defmodule index (nullptr for every other language and for callers that
// do not build one — an Elixir target then simply stays unresolved, never guessed). Returns the
// fileId on a UNIQUE precise hit, else kNoFile (unresolved → contributes nothing; NEVER a basename
// fallback, NEVER a guess).
//   * C-family quote `"x.h"` (isAngle==false): resolve relative-to-includer, collapse `.`/`..`, exact hit.
//   * C-family angle `<x.h>` (isAngle==true): external without a build system ⇒ kNoFile (never matched).
//   * Python / TS / Rust / Bash / Ruby / Lua / Elixir: their per-language Step-A above (unique-or-degrade).
//   * Go / Swift / Other: DEFERRED / no path ⇒ kNoFile (contributes nothing — honest).
inline std::uint32_t resolvePreciseInclude( std::string_view includerPath, std::string_view target, bool isAngle,
                                            const HashMap<std::string, std::uint32_t>& fileIndex,
                                            std::string_view crateRootDir = {}, bool hasCrateRoot = false,
                                            const WsIncludeCtx* ws = nullptr, std::uint32_t includerFileId = kNoFile,
                                            const HashMap<std::string, std::uint32_t>* moduleIndex = nullptr )
{
    if( target.empty() )
    {
        return kNoFile;
    }
    switch( includeLangOf( includerPath ) )
    {
        case IncludeLang::CFamily:
            if( isAngle )
            {
                // Single root: angle → external/unresolvable → contributes nothing (unchanged).
                // Multi-root (§3.1b): an angle/verbatim include probes each OTHER root's file set for an
                // EXACT path match, in TWO written forms — `<label>/<rel>` (the labeled key directly) and
                // `<rel>` (prefixed with each other root's label). Unique-or-degrade across the whole
                // workspace: ≥2 distinct hits ⇒ kNoFile. Never basename, never suffix-matching.
                if( !ws || includerFileId == kNoFile || includerFileId >= ws->fileRoot->size() )
                {
                    return kNoFile;
                }
                const std::uint32_t incRoot = ( *ws->fileRoot )[ includerFileId ];
                const std::string   norm    = lexicalNormalize( target );
                if( norm.empty() )
                {
                    return kNoFile;
                }
                std::uint32_t hit = kNoFile;
                const auto consider = [ & ]( std::uint32_t f )
                {
                    if( f == kNoFile || ( *ws->fileRoot )[f] == incRoot )
                    {
                        return; // other roots only
                    }
                    if( hit == kNoFile )
                    {
                        hit = f;
                    }
                    else if( f != hit )
                    {
                        hit = kNoFile - 1; // ambiguous → degrade
                    }
                };
                if( const auto it = fileIndex.find( norm ); it != fileIndex.end() )
                {
                    consider( it->second ); // `<label>/<rel>` form
                }
                for( std::uint32_t r = 0; r < ws->rootLabels.size(); ++r )                                    // `<rel>` form per other root
                {
                    if( r == incRoot )
                    {
                        continue;
                    }
                    const auto it = fileIndex.find( ws->rootLabels[ r ] + "/" + norm );
                    if( it != fileIndex.end() )
                    {
                        consider( it->second );
                    }
                }
                return ( hit == kNoFile || hit == kNoFile - 1 ) ? kNoFile : hit;
            }
            return joinNormalizeLookup( includerDir( includerPath ), target, fileIndex, ws, includerFileId );
        case IncludeLang::Python: return resolvePythonImport( includerPath, target, fileIndex, ws, includerFileId );
        case IncludeLang::Ts:     return resolveTsImport( includerPath, target, fileIndex, ws, includerFileId );
        case IncludeLang::Rust:   return resolveRustImport( includerPath, target, fileIndex, crateRootDir, hasCrateRoot, ws, includerFileId );
        case IncludeLang::Go:     return resolveGoImport( target, ws, includerFileId );   // single-root deferred; cross-root via go.mod replace (§3.2)
        case IncludeLang::Bash:   return resolveBashSource(  includerPath, target, fileIndex, ws, includerFileId );
        case IncludeLang::Ruby:   return resolveRubyRequire( includerPath, target, fileIndex, ws, includerFileId );
        case IncludeLang::Lua:    return resolveLuaRequire(  includerPath, target, fileIndex, ws, includerFileId );
        case IncludeLang::Elixir: return resolveElixirModule( target, moduleIndex );
        case IncludeLang::Other:  return kNoFile;        // Swift (no path in import) → deferred
    }
    return kNoFile;
}

// Build the PRECISE file→file include adjacency: includer fileId → its resolved-includee fileIds
// (unresolved includes dropped; self-includes dropped). Deterministic: a pure function of ing.includes
// (fixed order) + ing.files.
//   * dedup=true (default, the SameInclude call-graph tier): each per-file list is sorted+deduped, so a
//     downstream binary-search membership test is valid and order-stable regardless of hash iteration.
//   * dedup=false (the `--deps`/cycles/arch file→file graph, via resolveIncludeAdj): one entry per include
//     OCCURRENCE, in ing.includes order — the UN-deduped shape the old basename resolver produced, so the
//     weakest-link cutrefs metric (serialize.h: occurrence count = "how load-bearing is this dependency")
//     and afferent counts stay byte-identical to the pre-precise behavior. Downstream reachability walks
//     (sccCycles/dependencyHealth/dsmPropagationCost) are bitset-based → dedup-safe either way.
//
// One accepted (from,to) edge's contribution to the lazy-pair map — split out of buildPreciseIncludeAdj's
// main loop (kParserVer 72) so the bolted-on branch does not inflate that loop's own complexity. A pair
// starts true (lazy) on its first occurrence and is clobbered to false the moment ANY occurrence is a
// top-level (non-lazy) require — one strong edge is enough to make the whole (from,to) pair NOT lazy, since
// the file provably also depends on the target unconditionally.
inline void recordLazyPair( HashMap<std::uint64_t, char>& lazyPairs, std::uint32_t from, std::uint32_t to, bool isLazy )
{
    const std::uint64_t key = ( std::uint64_t( from ) << 32 ) | std::uint64_t( to );
    if( const auto it = lazyPairs.find( key ); it == lazyPairs.end() )
    {
        lazyPairs.emplace( key, isLazy ? 1 : 0 );
    }
    else if( !isLazy )
    {
        it->second = 0;
    }
}

// ── #220: TS/JS IMPORTS THROUGH A PROJECT'S OWN CONFIG — resolved when the config says where, counted when not ────────
// resolveTsImport leaves every bare (non-relative) specifier unresolved on a single root, and that is the sound
// answer for `react`. It is NOT a sound answer for a specifier the project's own config places in the tree: a
// tsconfig/jsconfig `compilerOptions.paths` alias (`@app/b`), a `baseUrl`-relative path (`lib/util` under
// `"baseUrl": "src"`), or a workspace member's package name (`@acme/lib`). Part 1 counted them so every answer built
// on the file graph could say it was a floor; part 2 (ImportResolver below) RESOLVES them the way TypeScript does, so
// they become real edges, and only what still cannot be resolved is counted.
//
// The order is tsc's (moduleResolution node10/node16/bundler agree on it for these three sources):
//   1. `paths` of the config that owns the importer — the nearest tsconfig.json (else jsconfig.json) walking up from
//      its directory. tsc's matchPatternOrExact picks ONE key: an exact key first, else the wildcard key with the
//      longest prefix. Its targets are tried IN ORDER from `baseUrl` when set, else from the directory of the config
//      that declared `paths`; the first target that names a file wins. A key with two `*` is not a pattern.
//   2. `<baseUrl>/<specifier>`, when `paths` did not answer.
//   3. a workspace package: members are the package.json files whose directory a `workspaces` glob (root
//      package.json: an array, or `{ "packages": [...] }`) or a pnpm-workspace.yaml `packages:` glob admits, relative to
//      the declaring file (`*`, `**`, `!` negation). Only an importer UNDER the declaring directory sees them (it is
//      that directory's node_modules the package manager links them into). The specifier's package name (`@s/n` or
//      `n`) picks the member; two members declaring one name are ambiguous and resolve to neither. Inside the member:
//      `exports` (the `.` entry or a subpath, exact key before the longest-prefix `*` pattern; conditions in the
//      object's own order, `import`+`default` and `require`+`default` both evaluated — two different files is
//      ambiguous; `types` never selected), else `module` then `main`, else the package's `index`. A target spelling
//      the package's EMITTED output (`./dist/index.js`) is mapped back to its source through that package's own
//      tsconfig `outDir` → `rootDir` first (tsc's tryLoadInputFileForPath), then tried as written.
// Each candidate path is probed in tsc's order with the house's unique-or-degrade discipline per tier: the exact
// spelling when it carries an extension, the source a runtime spelling names (`.js` → `.ts`/`.tsx`, kJsRuntimeSource
// Exts), `+.ts`/`+.tsx`; then the declaration (`+.d.ts`) ONLY when no source answered; then `/index.ts`/`/index.tsx`,
// then `/index.d.ts`; across every candidate of a `paths` entry the TypeScript tiers run before the JavaScript one
// (`.js .jsx .mjs .cjs /index.js /index.jsx`), tsc's priority/secondary split. Two files in one tier are ambiguous:
// no edge, counted — never a guess (tsc would prefer `.ts` over `.tsx`; the relative branch refuses, and so does this).
// An edge that lands only on a declaration file is a real dependency but not source; it is counted separately
// (imports_dts=) so the answer says so.
//
// What is COUNTED (imports_unresolved=): a specifier that matched a `paths` key with a NON-EMPTY literal prefix whose
// target stays in the tree, a visible workspace member's name, or any ambiguity above — and still has no edge. A
// catch-all key (`*`) or a baseUrl path that answers nothing is someone else's package and is never counted. A
// bare package that matches none of these (react, lodash/fp, node:fs) is External: no edge, no count, ever.
//
// `extends` is followed (cycle-safe, depth 16): a RELATIVE base must be a file the crawl indexed; a PACKAGE-form base
// (`@tsconfig/node20/tsconfig.json`, or a package whose package.json `tsconfig` field or tsconfig.json is meant) is
// read from the nearest `node_modules` at or above the config, inside the tree only. A child's key replaces the
// inherited one (tsc's rule). A base that is named but absent is DISCLOSED (tsconfig_unread=) when it could have
// changed an answer: a relative one could supply `paths` or `baseUrl`; a package-form one lives in node_modules, so
// its own `paths`/`baseUrl` could only point back into node_modules — except inherited `paths` under the child's
// own `baseUrl`.
// Only bytes the crawl admitted are read for the project's own configs (ing.files, so --exclude, gitignore and the
// 256 KB .json ceiling apply), through a JSONC reader: a commented-out `// "paths": …` is a comment, never a key (the
// multi-root text scan above reads it as live; this reader must not). A config that does not parse contributes
// nothing. All of it happens at GRAPH time, from the config bytes on disk: no ingested record changes.
namespace tsimport
{
// The JSON subset these three files use: strings, arrays, objects; every other scalar is Kind::Other. Keys keep
// source order; a later duplicate wins at lookup, as in JSON.parse.
struct JsonNode
{
    enum class Kind : std::uint8_t { Other, Str, Arr, Obj };
    Kind                     kind = Kind::Other;
    std::string              str;
    std::vector<std::string> keys;    // Obj
    std::vector<JsonNode>    vals;    // Obj (parallel to keys) or Arr

    const JsonNode* get( std::string_view key ) const noexcept
    {
        for( std::size_t i = keys.size(); i-- > 0; )
        {
            if( keys[i] == key )
            {
                return &vals[i];
            }
        }
        return nullptr;
    }
};

// JSONC (tsc's dialect): `//` and `/* */` comments and trailing commas are accepted. Depth-bounded, so a hostile
// file cannot recurse the stack (the crawl's jsonNestsTooDeep is the ingest-side guard; this is its own).
class JsoncReader
{
public:
    explicit JsoncReader( std::string_view s ) noexcept : s_( s ) {}

    bool parse( JsonNode& out )
    {
        skip();
        return value( out, 0 );
    }

private:
    static constexpr int kMaxDepth = 64;
    std::string_view     s_;
    std::size_t          p_ = 0;

    void skip() noexcept
    {
        while( p_ < s_.size() )
        {
            const char c = s_[p_];
            if( c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v' )
            {
                ++p_;
            }
            else if( c == '/' && p_ + 1 < s_.size() && s_[p_ + 1] == '/' )
            {
                const std::size_t e = s_.find( '\n', p_ );
                p_ = ( e == std::string_view::npos ) ? s_.size() : e + 1;
            }
            else if( c == '/' && p_ + 1 < s_.size() && s_[p_ + 1] == '*' )
            {
                const std::size_t e = s_.find( "*/", p_ + 2 );
                p_ = ( e == std::string_view::npos ) ? s_.size() : e + 2;
            }
            else
            {
                return;
            }
        }
    }

    // A JSON escape's character. \uXXXX reads as '?': no key or path this reader matches spells one.
    static char unescape( char e ) noexcept
    {
        constexpr std::string_view kEscaped = "ntrbfu", kMeant = "\n\t\r\b\f?";   // any other (\" \\ \/) is itself
        const std::size_t          k        = kEscaped.find( e );
        return k == std::string_view::npos ? e : kMeant[k];
    }

    bool string( std::string& out )
    {
        ++p_;   // the opening quote
        while( p_ < s_.size() && s_[p_] != '"' )
        {
            if( s_[p_] != '\\' || p_ + 1 >= s_.size() )
            {
                out.push_back( s_[p_++] );
                continue;
            }
            out.push_back( unescape( s_[p_ + 1] ) );
            p_ += s_[p_ + 1] == 'u' ? 6 : 2;   // an overshoot past the end is the unterminated case below
        }
        if( p_ >= s_.size() )
        {
            return false;
        }
        ++p_;   // the closing quote
        return true;
    }

    // An object member's `"key":`, leaving the reader at its value.
    bool key( JsonNode& n )
    {
        n.keys.emplace_back();
        if( s_[p_] != '"' || !string( n.keys.back() ) )
        {
            return false;
        }
        skip();
        if( p_ >= s_.size() || s_[p_] != ':' )
        {
            return false;
        }
        ++p_;
        skip();
        return true;
    }

    bool members( JsonNode& n, int depth, char close )
    {
        ++p_;   // '{' or '['
        for( ;; )
        {
            skip();
            if( p_ >= s_.size() )
            {
                return false;
            }
            if( s_[p_] == close )
            {
                ++p_;
                return true;   // also the trailing-comma case: `,` then the closer
            }
            if( close == '}' && !key( n ) )
            {
                return false;
            }
            n.vals.emplace_back();
            if( !value( n.vals.back(), depth + 1 ) )
            {
                return false;
            }
            skip();
            if( p_ < s_.size() && s_[p_] == ',' )
            {
                ++p_;
            }
            else if( p_ >= s_.size() || s_[p_] != close )
            {
                return false;
            }
        }
    }

    bool value( JsonNode& n, int depth )
    {
        if( depth > kMaxDepth || p_ >= s_.size() )
        {
            return false;
        }
        const char c = s_[p_];
        if( c == '{' || c == '[' )
        {
            n.kind = ( c == '{' ) ? JsonNode::Kind::Obj : JsonNode::Kind::Arr;
            return members( n, depth, c == '{' ? '}' : ']' );
        }
        if( c == '"' )
        {
            n.kind = JsonNode::Kind::Str;
            return string( n.str );
        }
        const std::size_t b = p_;   // a number, true/false/null: consumed, never read
        while( p_ < s_.size() && s_[p_] != ',' && s_[p_] != '}' && s_[p_] != ']' && s_[p_] != '/'
               && s_[p_] != ' ' && s_[p_] != '\t' && s_[p_] != '\n' && s_[p_] != '\r' )
        {
            ++p_;
        }
        return p_ > b;
    }
};

// `dir` + "/" + `rel`, lexically normalized; a root-level `dir` is the empty string. Empty on an escape.
inline std::string joinRel( std::string_view dir, std::string_view rel )
{
    std::string s( dir );
    if( !s.empty() )
    {
        s.push_back( '/' );
    }
    s.append( rel );
    return lexicalNormalize( s );
}

// Does root-relative `rel` name a file called `name` (at the root or in any directory)?
inline bool fileNamed( std::string_view rel, std::string_view name ) noexcept
{
    return rel.ends_with( name ) && ( rel.size() == name.size() || rel[ rel.size() - name.size() - 1 ] == '/' );
}

// One `paths` key: `prefix*suffix` when wild, else the exact `prefix`. Targets keep their order.
struct PathPattern
{
    std::string              prefix, suffix;
    bool                     wild = false;
    std::vector<std::string> targets;

    bool matches( std::string_view spec ) const noexcept
    {
        if( !wild )
        {
            return spec == prefix;
        }
        return spec.size() >= prefix.size() + suffix.size() && spec.starts_with( prefix ) && spec.ends_with( suffix );
    }
};

// The effective alias view of one config after its `extends` chain.
struct AliasScope
{
    std::vector<PathPattern> paths;
    std::string              pathsDir;   // the directory of the config that declared `paths`
    std::string              baseDir;    // `baseUrl`, resolved against the config that declared it
    std::string              outDir;     // part 2: `outDir`/`rootDir`, each resolved against its declaring config — a
    std::string              rootDir;    //   workspace package's emitted entry maps back to its source through them
    bool                     hasPaths   = false;
    bool                     hasBaseUrl = false;
    bool                     hasOutDir  = false;
    bool                     hasRootDir = false;
    bool                     unreadRelativeBase = false;   // a relative `extends` the crawl did not index
    bool                     unreadPackageBase  = false;   // a package-form `extends` not installed in the tree

    // What a base in the `extends` chain contributes: each key the base declared replaces the one inherited so far.
    void inherit( AliasScope&& base )
    {
        if( base.hasPaths )
        {
            paths    = std::move( base.paths );
            pathsDir = std::move( base.pathsDir );
            hasPaths = true;
        }
        if( base.hasBaseUrl )
        {
            baseDir    = std::move( base.baseDir );
            hasBaseUrl = true;
        }
        if( base.hasOutDir )
        {
            outDir    = std::move( base.outDir );
            hasOutDir = true;
        }
        if( base.hasRootDir )
        {
            rootDir    = std::move( base.rootDir );
            hasRootDir = true;
        }
        unreadRelativeBase = unreadRelativeBase || base.unreadRelativeBase;
        unreadPackageBase  = unreadPackageBase || base.unreadPackageBase;
    }

    // Could a base that was named but not read have changed what this scope resolves? A relative one could have
    // supplied `paths` or `baseUrl`. A package-form one sits in node_modules, so its own `paths`/`baseUrl` resolve
    // there; only its `paths` read under THIS chain's `baseUrl` could reach the tree.
    bool unreadMatters() const noexcept
    {
        return ( unreadRelativeBase && !( hasPaths && hasBaseUrl ) ) || ( unreadPackageBase && !hasPaths && hasBaseUrl );
    }
};

// A `paths` object's entries, in source order.
inline std::vector<PathPattern> readPathPatterns( const JsonNode& ps )
{
    std::vector<PathPattern> out;
    for( std::size_t i = 0; i < ps.keys.size(); ++i )
    {
        PathPattern       pp;
        const std::string& key  = ps.keys[i];
        const std::size_t  star = key.find( '*' );
        pp.wild   = star != std::string::npos;
        pp.prefix = pp.wild ? key.substr( 0, star ) : key;
        pp.suffix = pp.wild ? key.substr( star + 1 ) : std::string();
        for( const JsonNode& t : ps.vals[i].vals )   // an Arr's items; any other kind has none
        {
            if( t.kind == JsonNode::Kind::Str )
            {
                pp.targets.push_back( t.str );
            }
        }
        out.push_back( std::move( pp ) );
    }
    return out;
}

// A config's own `compilerOptions.baseUrl` / `.paths` / `.outDir` / `.rootDir`, over what it inherited (`dir` = the
// config's directory).
inline void applyCompilerOptions( const JsonNode& root, const std::string& dir, AliasScope& out )
{
    const JsonNode* co = root.get( "compilerOptions" );
    if( co == nullptr || co->kind != JsonNode::Kind::Obj )
    {
        return;
    }
    if( const JsonNode* bu = co->get( "baseUrl" ); bu != nullptr && bu->kind == JsonNode::Kind::Str )
    {
        out.baseDir    = joinRel( dir, bu->str );
        out.hasBaseUrl = true;
    }
    if( const JsonNode* ps = co->get( "paths" ); ps != nullptr && ps->kind == JsonNode::Kind::Obj )
    {
        out.paths    = readPathPatterns( *ps );   // a child's paths REPLACES the inherited one (tsc)
        out.pathsDir = dir;
        out.hasPaths = true;
    }
    if( const JsonNode* od = co->get( "outDir" ); od != nullptr && od->kind == JsonNode::Kind::Str )
    {
        out.outDir    = joinRel( dir, od->str );
        out.hasOutDir = true;
    }
    if( const JsonNode* rd = co->get( "rootDir" ); rd != nullptr && rd->kind == JsonNode::Kind::Str )
    {
        out.rootDir    = joinRel( dir, rd->str );
        out.hasRootDir = true;
    }
}

// A config's `extends` specifiers, in order (a string, or an array of them), relative and package-form alike.
inline std::vector<std::string_view> extendsSpecs( const JsonNode& root )
{
    std::vector<std::string_view> out;
    const JsonNode* ext = root.get( "extends" );
    if( ext == nullptr )
    {
        return out;
    }
    const auto take = [ & ]( const JsonNode& e )
    {
        if( e.kind == JsonNode::Kind::Str && !e.str.empty() )
        {
            out.push_back( e.str );
        }
    };
    if( ext->kind == JsonNode::Kind::Arr )
    {
        for( const JsonNode& e : ext->vals )
        {
            take( e );
        }
    }
    else
    {
        take( *ext );
    }
    return out;
}

// A whole glob (`packages/*`, `apps/**`, `libs/*-core`) against a directory's segments; `**` spans zero or more
// segments, and within one segment arch.h's wildcardMatch applies (a segment holds no '/').
inline bool globPath( std::span<const std::string_view> pat, std::span<const std::string_view> path ) noexcept
{
    if( pat.empty() )
    {
        return path.empty();
    }
    if( pat.front() == "**" )
    {
        for( std::size_t k = 0; k <= path.size(); ++k )
        {
            if( globPath( pat.subspan( 1 ), path.subspan( k ) ) )
            {
                return true;
            }
        }
        return false;
    }
    return !path.empty() && wildcardMatch( path.front(), pat.front() ) && globPath( pat.subspan( 1 ), path.subspan( 1 ) );
}

// One workspace declaration: the declaring file's directory and its globs, in order (a later `!glob` excludes).
struct WorkspaceDecl
{
    std::string              dir;
    std::vector<std::string> globs;

    bool admits( std::string_view memberDir ) const
    {
        if( !dir.empty() && !( memberDir.size() > dir.size() && memberDir.starts_with( dir ) && memberDir[ dir.size() ] == '/' ) )
        {
            return false;   // not under the declaring file's directory
        }
        const std::vector<std::string_view> segs = splitSegments( dir.empty() ? memberDir : memberDir.substr( dir.size() + 1 ) );
        bool                                in   = false;
        for( const std::string& g : globs )   // a later `!glob` excludes; a later positive glob re-admits
        {
            if( g.empty() )
            {
                continue;   // both producers drop empties today; an empty glob admits nothing and has no front()
            }
            const bool        neg  = g.front() == '!';
            const std::string norm = lexicalNormalize( std::string_view( g ).substr( neg ? 1 : 0 ) );   // `./packages/*`
            if( globPath( splitSegments( norm ), segs ) )
            {
                in = !neg;
            }
        }
        return in;
    }
};

// One YAML scalar as a glob: surrounding quotes (either style) dropped. Empty for an empty item.
inline std::string_view yamlGlobItem( std::string_view v ) noexcept
{
    v = trimWs( v );
    if( v.size() >= 2 && ( v.front() == '\'' || v.front() == '"' ) && v.back() == v.front() )
    {
        v = v.substr( 1, v.size() - 2 );
    }
    return v;
}

// pnpm-workspace.yaml's `packages:` key — the one key read — as a block list (`- 'glob'` items under it) or a flow
// list (`packages: ['a/*', "b/*"]`, which may span lines up to its `]`). An item holding a `,` or `]` inside quotes
// is not a glob pnpm documents and is split at it (an under-count, never a false member).
inline std::vector<std::string> pnpmWorkspaceGlobs( std::string_view y )
{
    std::vector<std::string> out;
    bool                     inList = false, inFlow = false;
    std::string              flow;   // a flow list's text so far, after its `[`
    const auto               takeFlow = [ & ]
    {
        for( const std::string_view item : splitSegments( std::string_view( flow ).substr( 0, flow.find( ']' ) ), ',' ) )
        {
            if( const std::string_view g = yamlGlobItem( item ); !g.empty() )
            {
                out.emplace_back( g );
            }
        }
        inFlow = false;
    };
    for( std::string_view line : splitSegments( y, '\n' ) )
    {
        line = trimWs( line.substr( 0, line.find( " #" ) ) );
        if( line.empty() || line.front() == '#' )
        {
            continue;
        }
        if( inFlow )
        {
            flow.append( "," ).append( line );
            if( flow.find( ']' ) != std::string::npos )
            {
                takeFlow();
            }
            continue;
        }
        if( line.starts_with( "packages:" ) || ( inList && line.front() == '[' ) )   // the flow list on its key's line, or the next
        {
            const std::string_view rest = line.front() == '[' ? line : trimWs( line.substr( 9 ) );
            inList                      = rest.empty();
            if( rest.starts_with( '[' ) )
            {
                flow.assign( rest.substr( 1 ) );
                inFlow = true;
                if( flow.find( ']' ) != std::string::npos )
                {
                    takeFlow();
                }
            }
            continue;
        }
        if( !inList || line.front() != '-' )
        {
            inList = false;   // any other key ends the block
            continue;
        }
        if( const std::string_view g = yamlGlobItem( line.substr( 1 ) ); !g.empty() )
        {
            out.emplace_back( g );
        }
    }
    return out;
}

// The package.json `workspaces` globs (an array, or yarn's `{ "packages": [...] }`); empty when it declares none.
inline std::vector<std::string> packageJsonWorkspaceGlobs( const JsonNode& pj )
{
    std::vector<std::string> out;
    const JsonNode*          ws = pj.get( "workspaces" );
    if( ws != nullptr && ws->kind == JsonNode::Kind::Obj )
    {
        ws = ws->get( "packages" );
    }
    if( ws != nullptr && ws->kind == JsonNode::Kind::Arr )
    {
        for( const JsonNode& g : ws->vals )
        {
            if( g.kind == JsonNode::Kind::Str && !g.str.empty() )
            {
                out.push_back( g.str );
            }
        }
    }
    return out;
}

// Inside the crawl root (joinRel refuses an escape) and not under node_modules, which the crawl never enters.
inline bool inTreeTarget( const std::string& at )
{
    const std::vector<std::string_view> segs = splitSegments( at );
    return !segs.empty() && std::find( segs.begin(), segs.end(), std::string_view( "node_modules" ) ) == segs.end();
}

// A path whose last segment carries a '.' (`x.ts`, `Foo.vue`, `api.client`): the one shape whose exact spelling is
// probed before an extension is appended.
inline bool lastSegmentHasDot( std::string_view p ) noexcept
{
    const std::size_t slash = p.rfind( '/' );
    return p.substr( slash == std::string_view::npos ? 0 : slash + 1 ).find( '.' ) != std::string_view::npos;
}

// A declaration file: an edge to it is an edge to types, not to source.
inline bool isDeclarationFile( std::string_view p ) noexcept
{
    return p.ends_with( ".d.ts" ) || p.ends_with( ".d.mts" ) || p.ends_with( ".d.cts" );
}

// A specifier whose last segment names a non-code asset by its extension (a stylesheet, an image, a font, media, a
// data or markup file, wasm), matched case-insensitively. Such an import names no module of the import graph: when
// the crawl indexed the file, the exact-spelling probe draws its edge like a relative import's; when no indexed file
// answers, the graph has no node it could have reached, so it is never counted as an in-repo import that drew no
// edge (ImportResolver::resolve). `.vue`/`.svelte` components are code, so they are not on the list.
inline bool isAssetSpecifier( std::string_view spec ) noexcept
{
    static constexpr std::string_view kAssetExts[] = {
        "css", "scss", "sass", "less", "styl", "pcss",                                           // stylesheets
        "svg", "png", "jpg", "jpeg", "gif", "webp", "avif", "ico", "bmp",                        // images
        "woff", "woff2", "ttf", "otf", "eot",                                                    // fonts
        "mp4", "webm", "mp3", "wav", "ogg",                                                      // media
        "json", "yaml", "yml", "toml", "csv", "txt", "md", "html", "xml", "graphql", "gql", "wasm" };
    const std::size_t      slash = spec.rfind( '/' );
    const std::string_view last  = spec.substr( slash == std::string_view::npos ? 0 : slash + 1 );
    const std::size_t      dot   = last.rfind( '.' );
    if( dot == std::string_view::npos || last.size() - dot - 1 > 8 )
    {
        return false;
    }
    char              lower[8] = {};
    const std::size_t n        = last.size() - dot - 1;
    for( std::size_t i = 0; i < n; ++i )
    {
        const char c = last[ dot + 1 + i ];
        lower[i]     = ( c >= 'A' && c <= 'Z' ) ? char( c - 'A' + 'a' ) : c;
    }
    const std::string_view ext( lower, n );
    return std::find( std::begin( kAssetExts ), std::end( kAssetExts ), ext ) != std::end( kAssetExts );
}

// npm's split of a bare specifier: the package name (`@scope/name`, else the first segment) and the rest as an
// `exports` key (`.` or `./sub`). The name is empty for a scope alone (`@scope`).
inline std::pair<std::string_view, std::string> splitPackageSpecifier( std::string_view spec )
{
    std::size_t cut = spec.find( '/' );
    if( spec.starts_with( '@' ) )
    {
        if( cut == std::string_view::npos )
        {
            return { {}, {} };
        }
        cut = spec.find( '/', cut + 1 );
    }
    if( cut == std::string_view::npos )
    {
        return { spec, "." };
    }
    return { spec.substr( 0, cut ), "." + std::string( spec.substr( cut ) ) };
}

// What one specifier came to. External: not this tree's (no edge, no count). Resolved / Declaration: an edge, to
// source / to a declaration file only. InRepoUnresolved: the config places it in the tree, yet no unique file answers.
enum class Verdict : std::uint8_t { External, Resolved, Declaration, InRepoUnresolved };
struct Outcome
{
    std::uint32_t file    = kNoFile;
    Verdict       verdict = Verdict::External;

    bool decided() const noexcept { return verdict != Verdict::External; }
};

// Node's resolvePackageTarget over one `exports` value: Found fills `out`; Null is an explicit null (the subpath is
// not exported, stop); Missing lets the enclosing array or object try its next entry. An object's keys are read in
// its own order and only the active `conds` are entered, so `types` (never active here) is skipped.
enum class ExportsHit : std::uint8_t { Missing, Null, Found };
inline ExportsHit exportsTarget( const JsonNode& n, std::span<const std::string_view> conds, std::string& out, int depth = 0 )
{
    if( depth > 16 || n.kind == JsonNode::Kind::Other )
    {
        return depth > 16 ? ExportsHit::Missing : ExportsHit::Null;
    }
    if( n.kind == JsonNode::Kind::Str )
    {
        out = n.str;
        return ExportsHit::Found;
    }
    for( std::size_t i = 0; i < n.vals.size(); ++i )   // an array's items in order, or an object's active conditions
    {
        if( n.kind == JsonNode::Kind::Obj && std::find( conds.begin(), conds.end(), n.keys[i] ) == conds.end() )
        {
            continue;
        }
        const ExportsHit h = exportsTarget( n.vals[i], conds, out, depth + 1 );
        if( h == ExportsHit::Null || ( h == ExportsHit::Found && ( n.kind == JsonNode::Kind::Obj || out.starts_with( "./" ) ) ) )
        {
            return h;   // an array skips an invalid (non-`./`) target and tries the next one
        }
    }
    return ExportsHit::Missing;
}

// The `exports` entry a subpath selects (Node's PACKAGE_EXPORTS_RESOLVE): the whole value when it is not a subpath map
// (only `.` is exported then), else the exact key, else the one-`*` key with the longest prefix (the longer key on a
// tie) whose capture is non-empty; `capture` receives what the `*` matched.
inline const JsonNode* exportsEntry( const JsonNode& ex, const std::string& sub, std::string& capture )
{
    if( ex.kind != JsonNode::Kind::Obj || ex.keys.empty() || !ex.keys.front().starts_with( '.' ) )
    {
        return sub == "." ? &ex : nullptr;
    }
    if( const JsonNode* exact = ex.get( sub ) )
    {
        return exact;
    }
    const JsonNode*   best    = nullptr;
    const std::string* bestKey = nullptr;
    for( std::size_t i = 0; i < ex.keys.size(); ++i )
    {
        const std::string& key  = ex.keys[i];
        const std::size_t  star = key.find( '*' );
        if( star == std::string::npos || key.find( '*', star + 1 ) != std::string::npos || sub.size() < key.size()
            || !sub.starts_with( std::string_view( key ).substr( 0, star ) ) || !sub.ends_with( std::string_view( key ).substr( star + 1 ) ) )
        {
            continue;
        }
        const std::size_t bestStar = bestKey != nullptr ? bestKey->find( '*' ) : 0;
        if( best == nullptr || star > bestStar || ( star == bestStar && key.size() > bestKey->size() ) )
        {
            best    = &ex.vals[i];
            bestKey = &key;
            capture = sub.substr( star, sub.size() - key.size() + 1 );
        }
    }
    return best;
}

// The resolver. One per adjacency build that met a bare TS/JS specifier its relative branch could not place; every
// memo lives here, and nothing in it depends on the order specifiers are asked in.
class ImportResolver
{
public:
    ImportResolver( const IngestResult& ing, const HashMap<std::string, std::uint32_t>& fileIndex )
        : ing_( ing ), fileIndex_( fileIndex )
    {
        collectWorkspaceMembers();
    }

    // `importer` is the importing file's normalized root-relative path, `spec` a bare specifier it wrote. A bundler's
    // `?query` suffix (`logo.svg?react`, `a.css?inline`) is not part of the path: the file it names is probed.
    Outcome resolve( std::string_view importer, std::string_view spec )
    {
        if( spec.find( ':' ) != std::string_view::npos )
        {
            return {};   // node:fs, https://…, data:… — a scheme, never a path in this tree
        }
        spec = spec.substr( 0, spec.find( '?' ) );
        const std::string dir( includerDir( importer ) );
        std::string       key = dir + '\x1f' + std::string( spec );
        if( const auto it = memo_.find( key ); it != memo_.end() )
        {
            return it->second;
        }
        Outcome o = spec.empty() ? Outcome{} : resolveUncached( dir, spec );
        if( o.verdict == Verdict::InRepoUnresolved && isAssetSpecifier( spec ) )
        {
            o = {};   // an asset no indexed file answers: the graph has no node for it (isAssetSpecifier)
        }
        memo_.emplace( std::move( key ), o );
        return o;
    }

    // How many configs that own an importer name an `extends` base that was not read and could have changed an answer.
    std::uint64_t extendsUnread() const noexcept { return unreadConfigs_.size(); }

private:
    struct Member
    {
        std::string              dir;
        std::size_t              manifest = 0;   // index into manifests_
        std::vector<std::string> declDirs;       // the directories of the workspace declarations that admit it
    };
    struct Hit
    {
        std::uint32_t file      = kNoFile;
        bool          ambiguous = false;
    };

    const IngestResult&                             ing_;
    const HashMap<std::string, std::uint32_t>&      fileIndex_;
    std::vector<JsonNode>                           manifests_;
    std::vector<Member>                             members_;
    HashMap<std::string, std::vector<std::size_t>>  membersByName_;
    HashMap<std::string, int>                       dirScope_;       // directory → index into scopes_, -1 = no config above it
    HashMap<std::string, int>                       cfgScope_;       // config path → index into scopes_
    std::vector<AliasScope>                         scopes_;
    std::vector<std::string>                        scopeConfig_;    // scopes_[i]'s config path
    HashMap<std::string, char>                      unreadConfigs_;
    HashMap<std::string, Outcome>                   memo_;

    static bool parseBytes( const std::string& bytes, JsonNode& out )
    {
        return !bytes.empty() && JsoncReader( bytes ).parse( out ) && out.kind == JsonNode::Kind::Obj;
    }

    Outcome resolveUncached( const std::string& dir, std::string_view spec )
    {
        bool      inRepo = false;   // a literal `paths` key placed it in the tree, whatever answers below
        const int si     = scopeForDir( dir );
        if( si >= 0 )
        {
            if( scopes_[ std::size_t( si ) ].unreadMatters() )
            {
                unreadConfigs_.emplace( scopeConfig_[ std::size_t( si ) ], 1 );
            }
            if( const Outcome o = throughPaths( std::size_t( si ), spec, inRepo ); o.decided() )
            {
                return o;
            }
            if( const AliasScope& sc = scopes_[ std::size_t( si ) ]; sc.hasBaseUrl )
            {
                if( const Outcome o = probeInOrder( candidateAt( sc.baseDir, spec ) ); o.decided() )
                {
                    return o;
                }
            }
        }
        if( const Outcome o = throughWorkspace( dir, spec ); o.decided() )
        {
            return o;
        }
        return { kNoFile, inRepo ? Verdict::InRepoUnresolved : Verdict::External };
    }

    static std::vector<std::string> candidateAt( std::string_view base, std::string_view rel )
    {
        std::string at = joinRel( base, rel );
        return inTreeTarget( at ) ? std::vector<std::string>{ std::move( at ) } : std::vector<std::string>{};
    }

    // tsc's matchPatternOrExact: an exact key, else the wildcard key with the longest prefix (the first on a tie).
    static const PathPattern* bestPathsKey( const std::vector<PathPattern>& paths, std::string_view spec )
    {
        const PathPattern* best = nullptr;
        for( const PathPattern& pp : paths )
        {
            if( !pp.wild && pp.prefix == spec )
            {
                return &pp;
            }
            if( pp.wild && pp.suffix.find( '*' ) == std::string::npos && pp.matches( spec ) && ( best == nullptr || pp.prefix.size() > best->prefix.size() ) )
            {
                best = &pp;
            }
        }
        return best;
    }

    // Rule 1: the one `paths` key tsc would pick, its targets in order. A literal key (non-empty prefix, or exact)
    // with a target that stays in the tree places the specifier here even when no target answers (`inRepo`); a
    // catch-all matches every package there is, so only an answer from it means anything.
    Outcome throughPaths( std::size_t si, std::string_view spec, bool& inRepo ) const
    {
        const AliasScope&  sc = scopes_[ si ];
        const PathPattern* pp = sc.hasPaths ? bestPathsKey( sc.paths, spec ) : nullptr;
        if( pp == nullptr )
        {
            return {};
        }
        const std::string_view base    = sc.hasBaseUrl ? std::string_view( sc.baseDir ) : std::string_view( sc.pathsDir );
        const std::string_view capture = pp->wild ? spec.substr( pp->prefix.size(), spec.size() - pp->prefix.size() - pp->suffix.size() ) : std::string_view();
        std::vector<std::string> cands;
        for( const std::string& t : pp->targets )
        {
            const std::size_t star = t.find( '*' );
            const std::string sub  = star == std::string::npos ? t : t.substr( 0, star ) + std::string( capture ) + t.substr( star + 1 );
            for( std::string& at : candidateAt( base, sub ) )
            {
                cands.push_back( std::move( at ) );
            }
        }
        inRepo = inRepo || ( ( !pp->prefix.empty() || !pp->wild ) && !cands.empty() );
        return probeInOrder( cands );
    }

    // One probe tier, unique-or-degrade: the one indexed file among `cands`, or ambiguous when two answer.
    Hit tier( const std::vector<std::string>& cands ) const
    {
        Hit h;
        for( const std::string& c : cands )
        {
            const auto it = fileIndex_.find( c );
            if( it == fileIndex_.end() )
            {
                continue;
            }
            h.ambiguous = h.ambiguous || ( h.file != kNoFile && h.file != it->second );
            h.file      = it->second;
        }
        return h;
    }

    Outcome decide( const Hit& h ) const
    {
        if( h.ambiguous )
        {
            return { kNoFile, Verdict::InRepoUnresolved };
        }
        if( h.file == kNoFile )
        {
            return {};
        }
        return { h.file, isDeclarationFile( rootRelPath( ing_, h.file ) ) ? Verdict::Declaration : Verdict::Resolved };
    }

    // The first tier that answers decides — a source beats its declaration outright, and an ambiguous tier stops.
    Outcome firstTier( std::initializer_list<std::vector<std::string>> tiers ) const
    {
        for( const std::vector<std::string>& t : tiers )
        {
            if( const Outcome o = decide( tier( t ) ); o.decided() )
            {
                return o;
            }
        }
        return {};
    }

    // The source a runtime spelling names (`x.js` → `x.ts`/`x.tsx`) and its declaration, appended to the two tiers.
    static void runtimeAlternates( const std::string& c, std::vector<std::string>& sources, std::vector<std::string>& decls )
    {
        if( const JsRuntimeSourceExt* rt = jsRuntimeSourceExtOf( c ) )
        {
            const std::string stem = c.substr( 0, c.size() - rt->runtime.size() );
            for( const std::string_view s : rt->sources )
            {
                if( !s.empty() )
                {
                    sources.push_back( stem + std::string( s ) );
                }
            }
            decls.push_back( stem + std::string( rt->decl ) );
        }
    }

    // One module path `c`, tsc's order: the file (the exact spelling when it has an extension, a runtime spelling's
    // source, `+.ts`/`+.tsx`), its declaration, the directory's index, the index's declaration. `js` asks the
    // JavaScript tier instead, which tsc tries only after every candidate's TypeScript tiers came up empty.
    Outcome probeModule( const std::string& c, bool js ) const
    {
        if( js )
        {
            return decide( tier( { c + ".js", c + ".jsx", c + ".mjs", c + ".cjs", c + "/index.js", c + "/index.jsx" } ) );
        }
        std::vector<std::string> sources, decls;
        if( lastSegmentHasDot( c ) )
        {
            sources.push_back( c );
        }
        runtimeAlternates( c, sources, decls );
        sources.push_back( c + ".ts" );
        sources.push_back( c + ".tsx" );
        decls.push_back( c + ".d.ts" );
        return firstTier( { sources, decls, { c + "/index.ts", c + "/index.tsx" }, { c + "/index.d.ts" } } );
    }

    // Several candidates in order (a `paths` entry's targets): every candidate's TypeScript tiers, then every
    // candidate's JavaScript tier; the first candidate that answers wins.
    Outcome probeInOrder( const std::vector<std::string>& cands ) const
    {
        for( const bool js : { false, true } )
        {
            for( const std::string& c : cands )
            {
                if( const Outcome o = probeModule( c, js ); o.decided() )
                {
                    return o;
                }
            }
        }
        return {};
    }

    // An `exports` target names a FILE: its exact spelling or the source a runtime spelling names, then that
    // spelling's declaration. No extension is appended and no index is read (Node's rule for exports).
    Outcome probeTarget( const std::string& c ) const
    {
        std::vector<std::string> sources{ c }, decls;
        runtimeAlternates( c, sources, decls );
        return firstTier( { sources, decls } );
    }

    // tsc's tryLoadInputFileForPath: an entry inside the package's `outDir` names the file its `rootDir` compiles
    // there. Both come from the config that owns the package directory; without both there is no mapping.
    std::string sourceOfEmitted( const std::string& pkgDir, const std::string& at )
    {
        const int si = scopeForDir( pkgDir );
        if( si < 0 )
        {
            return {};
        }
        const AliasScope& sc = scopes_[ std::size_t( si ) ];
        if( !sc.hasOutDir || !sc.hasRootDir || sc.outDir.empty() || sc.outDir == sc.rootDir || at.size() <= sc.outDir.size()
            || !at.starts_with( sc.outDir ) || at[ sc.outDir.size() ] != '/' )
        {
            return {};
        }
        return joinRel( sc.rootDir, std::string_view( at ).substr( sc.outDir.size() + 1 ) );
    }

    // A path the package names (an `exports` target, `module`/`main`, a subpath): inside the package only. Its source
    // through outDir → rootDir first, then as written; `exact` for an `exports` target, module probing otherwise.
    Outcome resolveEntry( const std::string& pkgDir, std::string_view rel, bool exact )
    {
        const std::string at = joinRel( pkgDir, rel );
        if( !inTreeTarget( at ) || !( pkgDir.empty() || at == pkgDir || ( at.starts_with( pkgDir ) && at[ pkgDir.size() ] == '/' ) ) )
        {
            return {};
        }
        std::vector<std::string> cands;
        if( std::string src = sourceOfEmitted( pkgDir, at ); !src.empty() )
        {
            cands.push_back( std::move( src ) );
        }
        cands.push_back( at );
        if( !exact )
        {
            return probeInOrder( cands );
        }
        for( const std::string& c : cands )
        {
            if( const Outcome o = probeTarget( c ); o.decided() )
            {
                return o;
            }
        }
        return {};
    }

    // `exports`: the entry the subpath selects, under both directive dialects. Two different files is ambiguous (the
    // directive's own syntax would choose, and the record does not keep it); one that names nothing here defers.
    Outcome throughExports( const std::string& pkgDir, const JsonNode& ex, const std::string& sub )
    {
        static constexpr std::string_view kImportConds[]  = { "import", "default" };
        static constexpr std::string_view kRequireConds[] = { "require", "default" };
        std::string                       capture;
        const JsonNode*                   entry = exportsEntry( ex, sub, capture );
        if( entry == nullptr )
        {
            return {};
        }
        Outcome agreed;
        for( const std::span<const std::string_view> conds : { std::span<const std::string_view>( kImportConds ), std::span<const std::string_view>( kRequireConds ) } )
        {
            std::string t;
            if( exportsTarget( *entry, conds, t ) != ExportsHit::Found || !t.starts_with( "./" ) )
            {
                continue;
            }
            for( std::size_t star = t.find( '*' ); !capture.empty() && star != std::string::npos; star = t.find( '*', star + capture.size() ) )
            {
                t.replace( star, 1, capture );   // Node substitutes every `*` of a pattern target
            }
            const Outcome o = resolveEntry( pkgDir, std::string_view( t ).substr( 2 ), /*exact=*/true );
            if( o.verdict == Verdict::InRepoUnresolved || ( o.decided() && agreed.decided() && o.file != agreed.file ) )
            {
                return { kNoFile, Verdict::InRepoUnresolved };
            }
            agreed = o.decided() ? o : agreed;
        }
        return agreed;
    }

    // Inside a member: `exports` when it declares one, else `module` then `main` (or the subpath under the package),
    // else its `index`.
    Outcome resolvePackage( const Member& m, const std::string& sub )
    {
        const JsonNode& pj = manifests_[ m.manifest ];
        if( const JsonNode* ex = pj.get( "exports" ); ex != nullptr && ex->kind != JsonNode::Kind::Other )
        {
            return throughExports( m.dir, *ex, sub );
        }
        if( sub != "." )
        {
            return resolveEntry( m.dir, std::string_view( sub ).substr( 2 ), /*exact=*/false );
        }
        for( const std::string_view field : { std::string_view( "module" ), std::string_view( "main" ) } )
        {
            const JsonNode* v = pj.get( field );
            if( v != nullptr && v->kind == JsonNode::Kind::Str && !v->str.empty() )
            {
                if( const Outcome o = resolveEntry( m.dir, v->str, /*exact=*/false ); o.decided() )
                {
                    return o;
                }
            }
        }
        return resolveEntry( m.dir, "index", /*exact=*/false );
    }

    static bool visibleFrom( const Member& m, const std::string& dir )
    {
        return std::any_of( m.declDirs.begin(), m.declDirs.end(), [ & ]( const std::string& d )
                            { return d.empty() || dir == d || ( dir.starts_with( d ) && dir[ d.size() ] == '/' ); } );
    }

    // Rule 3: the member the package name picks, among those the importer can see. Two members declaring one name
    // resolve to neither; a member that answers nothing is still this tree's, so it is counted.
    Outcome throughWorkspace( const std::string& dir, std::string_view spec )
    {
        const auto [ name, sub ] = splitPackageSpecifier( spec );
        const auto it            = name.empty() ? membersByName_.end() : membersByName_.find( std::string( name ) );
        if( it == membersByName_.end() )
        {
            return {};
        }
        const Member* only = nullptr;
        for( const std::size_t m : it->second )
        {
            if( !visibleFrom( members_[ m ], dir ) )
            {
                continue;
            }
            if( only != nullptr && only->dir != members_[ m ].dir )
            {
                return { kNoFile, Verdict::InRepoUnresolved };
            }
            only = &members_[ m ];
        }
        if( only == nullptr )
        {
            return {};
        }
        const Outcome o = resolvePackage( *only, sub );
        return o.decided() ? o : Outcome{ kNoFile, Verdict::InRepoUnresolved };
    }

    // Every indexed package.json whose directory a workspace glob admits, with its name and the declarations that
    // admit it. Files are visited in ing.files order (sorted), so member order — and every answer — is deterministic.
    void collectWorkspaceMembers()
    {
        std::vector<WorkspaceDecl>                    decls;
        std::vector<std::pair<std::string, JsonNode>> manifests;   // (directory, parsed package.json)
        for( std::uint32_t f = 0; f < ing_.files.size(); ++f )
        {
            const std::string rel = lexicalNormalize( rootRelPath( ing_, f ) );
            const std::string dir( includerDir( rel ) );
            JsonNode          pj;
            if( fileNamed( rel, "pnpm-workspace.yaml" ) )
            {
                decls.push_back( { dir, pnpmWorkspaceGlobs( readConfigBytes( diskPath( ing_, f ) ) ) } );
            }
            else if( fileNamed( rel, "package.json" ) && parseBytes( readConfigBytes( diskPath( ing_, f ) ), pj ) )
            {
                if( std::vector<std::string> globs = packageJsonWorkspaceGlobs( pj ); !globs.empty() )
                {
                    decls.push_back( { dir, std::move( globs ) } );
                }
                manifests.emplace_back( dir, std::move( pj ) );
            }
        }
        for( auto& [ dir, pj ] : manifests )
        {
            const JsonNode* name = pj.get( "name" );
            Member          m;
            m.dir = dir;
            for( const WorkspaceDecl& d : decls )
            {
                if( d.admits( dir ) )
                {
                    m.declDirs.push_back( d.dir );
                }
            }
            if( m.declDirs.empty() || name == nullptr || name->kind != JsonNode::Kind::Str || name->str.empty() )
            {
                continue;
            }
            m.manifest = manifests_.size();
            membersByName_[ name->str ].push_back( members_.size() );
            manifests_.push_back( std::move( pj ) );
            members_.push_back( std::move( m ) );
        }
    }

    // The config that owns `dir`: the nearest tsconfig.json, else jsconfig.json, walking up to the crawl root.
    int scopeForDir( const std::string& dir )
    {
        if( const auto it = dirScope_.find( dir ); it != dirScope_.end() )
        {
            return it->second;
        }
        int r = -1;
        for( const std::string_view name : { std::string_view( "tsconfig.json" ), std::string_view( "jsconfig.json" ) } )
        {
            if( const std::uint32_t cfg = joinNormalizeLookup( dir, name, fileIndex_ ); cfg != kNoFile )
            {
                r = scopeForConfig( joinRel( dir, name ), diskPath( ing_, cfg ) );
                break;
            }
        }
        if( r < 0 && !dir.empty() )
        {
            r = scopeForDir( std::string( includerDir( dir ) ) );
        }
        dirScope_.emplace( dir, r );
        return r;
    }

    int scopeForConfig( const std::string& rel, const std::string& disk )
    {
        if( const auto it = cfgScope_.find( rel ); it != cfgScope_.end() )
        {
            return it->second;
        }
        std::vector<std::string> chain;
        AliasScope               s = loadChain( rel, disk, chain );
        scopes_.push_back( std::move( s ) );
        scopeConfig_.push_back( rel );
        const int idx = int( scopes_.size() - 1 );
        cfgScope_.emplace( rel, idx );
        return idx;
    }

    // One config and what it extends, bases first so the child's own keys win; with an `extends` array the LAST base
    // that declares a key wins. `chain` is the path taken so far: a revisit stops there, and the depth is bounded.
    AliasScope loadChain( const std::string& rel, const std::string& disk, std::vector<std::string>& chain )
    {
        AliasScope out;
        JsonNode   root;
        if( chain.size() >= 16 || std::find( chain.begin(), chain.end(), rel ) != chain.end() || !parseBytes( readConfigBytes( disk ), root ) )
        {
            return out;
        }
        chain.push_back( rel );
        for( const std::string_view b : extendsSpecs( root ) )
        {
            std::string brel, bdisk;
            if( locateBase( rel, disk, b, brel, bdisk, out ) )
            {
                out.inherit( loadChain( brel, bdisk, chain ) );
            }
        }
        applyCompilerOptions( root, std::string( includerDir( rel ) ), out );
        chain.pop_back();
        return out;
    }

    // Where an `extends` names its base: (relative) the indexed file, with or without `.json` — or, for a config that
    // was itself read from node_modules, the file beside it on disk; (package form) the nearest `node_modules` at or
    // above the config, inside the tree: `<pkg>/<subpath>[.json]`, else the package.json `tsconfig` field, else
    // `tsconfig.json`. A base that is not there is flagged on `out`, never guessed at.
    bool locateBase( const std::string& rel, const std::string& disk, std::string_view b, std::string& brel, std::string& bdisk, AliasScope& out ) const
    {
        const std::string dir( includerDir( rel ) );
        const std::string diskDir   = includerDir( disk ).empty() ? std::string( "." ) : std::string( includerDir( disk ) );
        const bool        inPackage = !inTreeTarget( rel );
        if( b.starts_with( "./" ) || b.starts_with( "../" ) )
        {
            for( const std::string& cand : { std::string( b ), std::string( b ) + ".json" } )
            {
                const std::string r = joinRel( dir, cand );
                if( r.empty() )
                {
                    continue;
                }
                if( const auto it = inPackage ? fileIndex_.end() : fileIndex_.find( r ); it != fileIndex_.end() )
                {
                    brel  = r;
                    bdisk = diskPath( ing_, it->second );
                    return true;
                }
                if( std::string d = diskDir + "/" + cand; inPackage && !readConfigBytes( d ).empty() )
                {
                    brel  = r;
                    bdisk = std::move( d );
                    return true;
                }
            }
            ( inPackage ? out.unreadPackageBase : out.unreadRelativeBase ) = true;
            return false;
        }
        const auto [ name, sub ] = splitPackageSpecifier( b );
        std::string relDir = dir, up;
        for( bool more = !name.empty() && !b.starts_with( '/' ); more; more = !relDir.empty(), relDir = std::string( includerDir( relDir ) ), up += "/.." )
        {
            const std::string        nmRel  = joinRel( relDir, "node_modules/" + std::string( name ) );
            const std::string        nmDisk = diskDir + up + "/node_modules/" + std::string( name );
            std::vector<std::string> tries;   // relative to the package's directory
            if( sub != "." )
            {
                tries.push_back( sub.substr( 2 ) );
                tries.push_back( sub.substr( 2 ) + ".json" );
            }
            else
            {
                JsonNode pj;
                if( const JsonNode* t = parseBytes( readConfigBytes( nmDisk + "/package.json" ), pj ) ? pj.get( "tsconfig" ) : nullptr;
                    t != nullptr && t->kind == JsonNode::Kind::Str && !t->str.empty() )
                {
                    tries.push_back( t->str );
                }
                tries.push_back( "tsconfig.json" );
            }
            for( const std::string& t : tries )
            {
                if( std::string d = nmDisk + "/" + t; !nmRel.empty() && !readConfigBytes( d ).empty() )
                {
                    brel  = joinRel( nmRel, t );
                    bdisk = std::move( d );
                    return !brel.empty();
                }
            }
        }
        out.unreadPackageBase = true;
        return false;
    }
};

// Could a TS/JS import land on this file at all? Not on a file of another import dialect (C-family, Python, Rust,
// Go, shell, Ruby, Lua, Elixir): no module specifier resolves there. Everything else — TS/JS itself and the files
// with no import dialect here (json, a .vue component, …) — could be, so a count that concerns it is disclosed.
// --impact asks this of its def files, so a C++ symbol's import tier never pays for a TS alias elsewhere in the tree.
inline bool couldBeTsImportTarget( std::string_view path ) noexcept
{
    const IncludeLang l = includeLangOf( path );
    return l == IncludeLang::Ts || l == IncludeLang::Other;
}

// Is this include a counting candidate at all: a TS/JS importer's bare specifier (not `.`-relative, not absolute).
inline bool isBareTsSpecifier( std::string_view includerPath, std::string_view target ) noexcept
{
    return !target.empty() && target.front() != '.' && target.front() != '/' && includeLangOf( includerPath ) == IncludeLang::Ts;
}
} // namespace tsimport

// #220 part 2: the two disclosures the resolver adds beside imports_unresolved= (see buildPreciseIncludeAdjWithContext).
struct TsImportExtras
{
    std::uint64_t declarationOnly = 0;   // directives whose edge is to a .d.ts (imports_dts=)
    std::uint64_t extendsUnread   = 0;   // configs with an unread base that could have changed an answer (tsconfig_unread=)
};

// #220 part 2: one bare TS/JS specifier the relative branch left unresolved, through the project's own config
// (tsimport::ImportResolver, built here on first use). Returns the edge's target or kNoFile, and tallies the verdict.
// Multi-root: an answer in another root is not evidence (joinNormalizeLookup's rule 1), so it stays unresolved.
inline std::uint32_t resolveBareTsImport( const IngestResult& ing, const HashMap<std::string, std::uint32_t>& fileIndex,
                                          std::optional<tsimport::ImportResolver>& resolver, const WsIncludeCtx* ws,
                                          const Include& inc, std::uint64_t* unresolvedOut, TsImportExtras* extrasOut )
{
    if( !resolver )
    {
        resolver.emplace( ing, fileIndex );
    }
    tsimport::Outcome o = resolver->resolve( lexicalNormalize( rootRelPath( ing, inc.fileId ) ), inc.target );
    if( o.file != kNoFile && ws != nullptr && ( *ws->fileRoot )[ o.file ] != ( *ws->fileRoot )[ inc.fileId ] )
    {
        o = { kNoFile, tsimport::Verdict::InRepoUnresolved };
    }
    if( o.verdict == tsimport::Verdict::InRepoUnresolved && unresolvedOut != nullptr )
    {
        ++*unresolvedOut;
    }
    if( o.verdict == tsimport::Verdict::Declaration && extrasOut != nullptr )
    {
        ++extrasOut->declarationOnly;
    }
    return o.file;
}

// `lazyPairsOut` (kParserVer 72, fnbody-require lane): optional, default nullptr — purely additive, every
// existing call site is unaffected. When non-null, keyed by (fromFileId<<32 | toFileId), value = "every
// Include occurrence resolving to this edge so far was lazy" (Include::isLazy) — see recordLazyPair above.
// Independent of `dedup`: keyed by file-id PAIR, not by adj's post-sort indices, so it stays correct
// whichever adjacency shape the caller asked for.
// `forCallNarrow` (parser version 93): true ⇒ Include records read off a VALUE position (Include::isValueUse — a
// constant argument, a rescue class) are left out. Those are dependencies of the file and every dependency view
// keeps them, but they are not import evidence for a bare call: `notify(Dev::Config)` beside `record.update!` says
// nothing about `record`, and buildGraph's narrow bound 1,017 discourse call sites on that reading, 19 of 20
// sampled wrong (PR #139 review). Only buildGraph's fileIncludes passes true; the default keeps every consumer
// byte-identical.
// `importsUnresolvedOut` (#220 part 1): optional, default nullptr — when non-null it receives how many TS/JS bare
// import directives drew no edge although they name something in this tree (tsimport::ImportResolver's
// InRepoUnresolved verdict). Counted in DIRECTIVES, lazy ones included, so the dedup=true and dedup=false builds
// agree on it.
// #220 part 2: every caller now gets the EDGES — a bare TS/JS specifier the relative branch left unresolved is handed
// to tsimport::ImportResolver (built on the first such specifier, so a tree without one reads no config file), and
// what it resolves is an edge exactly like a relative import's. `extrasOut` (optional) receives its two disclosures:
// how many of those edges land only on a declaration file, and how many owning configs name an unread `extends` base.
inline std::pair<std::vector<std::vector<std::uint32_t>>, WsIncludeCtx> buildPreciseIncludeAdjWithContext( const IngestResult& ing, bool dedup = true,
                                                                       HashMap<std::uint64_t, char>* lazyPairsOut = nullptr,
                                                                       bool forCallNarrow = false,
                                                                       std::uint64_t* importsUnresolvedOut = nullptr,
                                                                       TsImportExtras* extrasOut = nullptr )
{
    PROFILE_SCOPE_DESCRIBE( "buildGraph/2a: precise include adjacency (resolve.h)" );
    const std::uint32_t F = std::uint32_t( ing.files.size() );
    std::vector<std::vector<std::uint32_t>> adj( F );
    if( importsUnresolvedOut != nullptr )
    {
        *importsUnresolvedOut = 0;
    }
    if( extrasOut != nullptr )
    {
        *extrasOut = {};
    }
    if( ing.includes.empty() )
    {
        return { std::move( adj ), {} };
    }

    // path → fileId over the canonical (sorted) file list. The KEY is the LEXICALLY-NORMALIZED ROOT-RELATIVE
    // path (rootRelPath, model.h), NOT the raw ing.files spelling, and every includer path handed to a Step-A
    // below is the same view. Two defects this closes, both of the "answer moves with how the root was typed"
    // kind (#228): a Python absolute import probes an EMPTY base, which named the crawl root only when the root
    // was typed `.`, so "$PWD" (and every MCP session, and the --quality-delta HEAD side) lost the edge; and a
    // root typed `../repo` stores `../repo/x.h`, which lexicalNormalize refuses as an escape — every key came
    // out empty and every include in the tree went unresolved. Relative to the root, both spellings are the
    // `.` spelling, and a `..` that climbs above the root is unresolved under all of them. Normalizing BOTH
    // sides through the same lexical rule still makes `./render/shader.h` and a resolved `render/shader.h`
    // agree. Pure + deterministic (no I/O). Multi-root keeps its labeled keys: rootRelPath is the identity there.
    HashMap<std::string, std::uint32_t> fileIndex;
    fileIndex.reserve( F );
    for( std::uint32_t f = 0; f < F; ++f )
    {
        fileIndex.emplace( lexicalNormalize( rootRelPath( ing, f ) ), f );
    }

    // ── Multi-root workspace context (§3.1): built ONLY for a merged workspace ingest — nullptr on every
    // single-root run, so the resolution below is byte-identical to today. Per-root pieces:
    //   * absIndex: lexicalNormalize(<root-realpath>/<rel>) → fileId (the disk-shape escape probe);
    //   * per-root Rust crate roots (a `use crate::…` must anchor in ITS OWN root, never another's).
    const bool  isWorkspace = !ing.fileRoot.empty() && !ing.rootLabels.empty();
    WsIncludeCtx wsCtx;
    const WsIncludeCtx* ws = nullptr;
    if( isWorkspace )
    {
        wsCtx.fileRoot   = &ing.fileRoot;
        wsCtx.rootAbs    = ing.rootReals;
        wsCtx.rootLabels = ing.rootLabels;
        wsCtx.absIndex.reserve( F );
        for( std::uint32_t f = 0; f < F; ++f )
        {
            const std::uint32_t     r     = ing.fileRoot[ f ];
            const std::string&      label = ing.rootLabels[ r ];
            std::string_view        rel   = ing.files[ f ];
            if( rel.size() >= label.size() && rel.compare( 0, label.size(), label ) == 0 )
            {
                rel.remove_prefix( label.size() );
                if( !rel.empty() && rel.front() == '/' )
                {
                    rel.remove_prefix( 1 );
                }
            }
            std::string abs = ing.rootReals[ r ];
            if( !rel.empty() ) { abs.push_back( '/' );  abs.append( rel ); }
            wsCtx.absIndex.emplace( lexicalNormalize( abs ), f );
        }

        // §3.2 cross-root config evidence: mine each root's go.mod `replace` + tsconfig.json `paths` (in
        // CANONICAL root order → deterministic alias order). Reads are workspace-only, off every hot path,
        // and parse to a pure function of the config bytes (warm==cold reads the same bytes ⇒ same aliases).
        for( std::uint32_t r = 0; r < ing.rootReals.size(); ++r )
        {
            if( const std::string gomod = readConfigBytes( ing.rootReals[ r ] + "/go.mod" ); !gomod.empty() )
            {
                parseGoModReplaces( gomod, r, ing.rootReals[ r ], wsCtx.configAliases );
            }
            if( const std::string tscfg = readConfigBytes( ing.rootReals[ r ] + "/tsconfig.json" ); !tscfg.empty() )
            {
                parseTsconfigPaths( tscfg, r, ing.rootReals[ r ], wsCtx.configAliases );
            }
        }
        ws = &wsCtx;
    }

    // Rust crate root: the directory holding `src/lib.rs` or `src/main.rs` (the `crate::` anchor). We take
    // the FIRST such file in the sorted list (deterministic); its dir is the crate root. Absent (workspace
    // member) ⇒ hasCrateRoot=false ⇒ `use crate::…` degrades. A pure scan of the sorted files (no I/O).
    // Multi-root: ONE crate root PER root — `crate::` must never anchor in another repo.
    std::string_view crateRootDir;
    bool             hasCrateRoot = false;
    std::vector<std::string_view> crateRootByRoot;
    std::vector<char>             hasCrateByRoot;
    if( isWorkspace )
    {
        crateRootByRoot.assign( ing.rootLabels.size(), {} );
        hasCrateByRoot.assign( ing.rootLabels.size(), 0 );
    }
    for( std::uint32_t f = 0; f < F; ++f )
    {
        const std::string_view p = rootRelPath( ing, f );
        const bool isLib  = ( p == "lib.rs"  || ( p.size() >= 7 && p.substr( p.size() - 7 ) == "/lib.rs"  ) );
        const bool isMain = ( p == "main.rs" || ( p.size() >= 8 && p.substr( p.size() - 8 ) == "/main.rs" ) );
        if( !( isLib || isMain ) )
        {
            continue;
        }
        if( isWorkspace )
        {
            const std::uint32_t r = ing.fileRoot[ f ];
            if( !hasCrateByRoot[ r ] ) { crateRootByRoot[ r ] = includerDir( p ); hasCrateByRoot[ r ] = 1; }
        }
        else if( !hasCrateRoot ) { crateRootDir = includerDir( p ); hasCrateRoot = true; }
    }

    const HashMap<std::string, std::uint32_t> elixirModules = buildElixirModuleIndex( ing );
    const HashMap<std::string, std::uint32_t>* moduleIndex = elixirModules.empty() ? nullptr : &elixirModules;
    const RubyConstantIndex                   rubyConsts    = buildRubyConstantIndex( ing );   // parser version 82; empty unless a symbolic directive exists
    HashMap<std::string, std::pair<std::uint32_t, std::uint32_t>> rubyMemo;

    std::vector<std::uint32_t> includeCountByFile( F, 0 );
    for( const Include& inc : ing.includes )
    {
        if( inc.fileId < F )
        {
            ++includeCountByFile[inc.fileId];
        }
    }
    for( std::uint32_t f = 0; f < F; ++f )
    {
        adj[ f ].reserve( includeCountByFile[ f ] );
    }

    std::optional<tsimport::ImportResolver> tsResolver;   // #220: built on the first bare TS/JS specifier that missed
    for( const Include& inc : ing.includes )
    {
        if( inc.fileId >= F )
        {
            continue;
        }
        if( inc.isSymbolic )
        {
            if( forCallNarrow && inc.isValueUse )
            {
                continue;   // a dependency, not import evidence — see the parameter note above
            }
            // A Ruby constant: index + lexical rule, and an edge to EVERY definer (multiplicity — see the
            // RubyConstantIndex note). Self-includes are dropped exactly as on the path branch below.
            const auto [ off, cnt ] = resolveRubyConstant( rubyConsts, rubyMemo, inc.fileId, inc.byte, inc.target );
            for( std::uint32_t k = 0; k < cnt; ++k )
            {
                const std::uint32_t to = rubyConsts.files[ off + k ];
                if( to == inc.fileId )
                {
                    continue;
                }
                adj[ inc.fileId ].push_back( to );
                if( lazyPairsOut != nullptr )
                {
                    recordLazyPair( *lazyPairsOut, inc.fileId, to, inc.isLazy );
                }
            }
            continue;
        }
        std::string_view crd    = crateRootDir;
        bool             hasCrd = hasCrateRoot;
        if( isWorkspace )
        {
            const std::uint32_t r = ing.fileRoot[ inc.fileId ];
            crd    = crateRootByRoot[ r ];
            hasCrd = hasCrateByRoot[ r ] != 0;
        }
        std::uint32_t to = resolvePreciseInclude( rootRelPath( ing, inc.fileId ), inc.target, inc.isAngle,
                                                   fileIndex, crd, hasCrd, ws, inc.fileId, moduleIndex );
        if( to == kNoFile && tsimport::isBareTsSpecifier( rootRelPath( ing, inc.fileId ), inc.target ) )
        {
            to = resolveBareTsImport( ing, fileIndex, tsResolver, ws, inc, importsUnresolvedOut, extrasOut );
        }
        if( to == kNoFile || to == inc.fileId )
        {
            continue; // unresolved or self-include → contributes nothing
        }
        adj[ inc.fileId ].push_back( to );
        if( lazyPairsOut != nullptr )
        {
            recordLazyPair( *lazyPairsOut, inc.fileId, to, inc.isLazy );
        }
    }
    if( extrasOut != nullptr )
    {
        *extrasOut = TsImportExtras{ extrasOut->declarationOnly, tsResolver ? tsResolver->extendsUnread() : 0 };
    }
    if( dedup )
    {
        for( std::vector<std::uint32_t>& v : adj )
        {
            std::sort( v.begin(), v.end() );
            v.erase( std::unique( v.begin(), v.end() ), v.end() );
        }
    }
    return { std::move( adj ), std::move( wsCtx ) };
}

inline std::vector<std::vector<std::uint32_t>> buildPreciseIncludeAdj( const IngestResult& ing, bool dedup = true,
                                                                       HashMap<std::uint64_t, char>* lazyPairsOut = nullptr,
                                                                       std::uint64_t* importsUnresolvedOut = nullptr,
                                                                       TsImportExtras* extrasOut = nullptr )
{
    auto built = buildPreciseIncludeAdjWithContext( ing, dedup, lazyPairsOut, /*forCallNarrow=*/false, importsUnresolvedOut, extrasOut );
    return std::move( built.first );   // the adjacency alone; the workspace context stays with the one caller that needs it
}

// Transitive include-set per file: for each file f, the sorted, duplicate-free set of fileIds reachable
// from f by ≥1 include hop (f itself EXCLUDED). Cycle-safe via a `seen` bitset (a file already visited is
// not re-pushed), so mutually-including headers (a↔b) simply each reach the other — the exact
// reachability walk shape as graph.h::dependencyHealth. Deterministic: `adj` is sorted and each result set
// is re-sorted, so it is a pure function of the adjacency regardless of visit order. Duplicate-free is a
// property of the epoch stamp, NOT of a dedup pass — there is no longer one to describe; see the NO DEDUP
// PASS note at the sort below, which is where the removed std::unique used to sit.
inline std::vector<std::vector<NodeId>> transitiveIncludeSet( const std::vector<std::vector<std::uint32_t>>& adj )
{
    PROFILE_SCOPE_DESCRIBE( "buildGraph/2b: transitive include closure (resolve.h)" );
    const std::uint32_t          F = std::uint32_t( adj.size() );
    std::vector<std::vector<NodeId>> trans( F );
    std::vector<std::uint32_t>   seenEpoch( F, 0 );
    std::vector<std::uint32_t>   stack;
    std::vector<NodeId>          sortScratch;   // radix ping-pong buffer, reused across all F closures
    stack.reserve( F );
    std::uint32_t                epoch = 1;
    for( std::uint32_t s = 0; s < F; ++s )
    {
        stack.clear();  stack.push_back( s );  seenEpoch[s] = epoch;     // seed with s so f never lands in its OWN set…
        while( !stack.empty() )
        {
            const std::uint32_t v = stack.back();  stack.pop_back();
            for( std::uint32_t w : adj[v] )
            {
                if( seenEpoch[w] != epoch )
                {
                    seenEpoch[w] = epoch;
                    stack.push_back( w );
                    trans[s].push_back( w );
                }
            }
        }
        // …trans[s] already excludes s (never pushed as a reachable target). Sorted for the binary_search
        // in rule3IncludeFile, and for the determinism contract in this function's header comment — the
        // walk's discovery order is deterministic but is NOT id order, so the sort is what makes the
        // result a pure function of `adj`. It stays; only its implementation changes.
        //
        // NO DEDUP PASS. `w` is appended in the same branch that stamps `seenEpoch[w] = epoch`, and
        // nothing clears that stamp before `++epoch` below, so a file can be appended to trans[s] at most
        // once per source — the set is duplicate-free BY CONSTRUCTION. The `std::unique` that used to sit
        // here removed 0 elements in 24,216 calls across six corpora (rails, go, django, rust-analyzer, a
        // private C++ tree, this repo) at a measured 0.99 ms on rails. Its sibling `ancestorsReach` in
        // graph.h has always relied on this same stamp without a dedup. The invariant is now asserted by
        // test/includeprecisecheck.sh — a diamond fixture (two distinct paths to one file) plus a 400-node
        // scrambled synthetic graph checked against an independent mark-sweep oracle — rather than paid
        // for on every call.
        rw::sortutil::radixSortIdsAscending( trans[s], sortScratch );
        ++epoch;
    }
    return trans;
}

// ── S6-C canonical SCIP-style symbol strings ───────────────────────────────────────────────────────
// A stable, cross-language identity for a definition: `path::scope::name` (e.g. `src/math/quat.cpp::quatf::
// normalize`, or for TS/Py the module path is the prefix: `src/utils/foo.ts::Bar::baz`). The enclosing
// `scope` (class/namespace) is already captured at ingest (Symbol::scope — C++ + Python methods); the file
// path is the module prefix. Two same-named methods on different classes — the #1 `amb` source — get DISTINCT
// canonical ids (`…::A::compute` vs `…::B::compute`), so `--callers`/`--callees` stop confusing them and the
// resolver can break a k-way tie by locality (longest shared canonical prefix with the caller — same dir/scope
// wins). Degrades to the bare name when no scope is known (free functions, langs without scope capture) — that
// is exactly the case where a canonical id would ADD NOTHING (`id == name`), so the caller skips emitting it.
//
// Deterministic + allocation-disciplined: a pure string function of (path, scope, name); no map, no state.
inline std::string canonicalId( std::string_view path, std::string_view scope, std::string_view name )
{
    if( scope.empty() )
    {
        return std::string( name ); // free function / no enclosing scope → bare name (id == name; not emitted)
    }
    std::string id;
    id.reserve( path.size() + scope.size() + name.size() + 4 );
    id.append( path ).append( "::" ).append( scope ).append( "::" ).append( name );
    return id;
}

// The S6-C tie-break's SCORING key (Graph::localityKey) — canonicalId's spelling for a scoped symbol, and
// `path::name` (never the bare name) for an unscoped one. canonicalId's bare-name degrade is right for an
// IDENTITY (id == name, nothing to emit) and wrong for a LOCALITY score: it gave a module-level function zero
// shared segments with every caller, so it could never survive the tie-break against a same-file class method
// (docs/EVALS.md "Phase 3b"/"Phase 4": 10 of 23 disconfirmed pins on astropy). Read by the S6-C block only;
// id=, note keys, baseline keys and selectors keep canonicalId.
inline std::string localityKeyOf( std::string_view path, std::string_view scope, std::string_view name )
{
    return scope.empty() ? std::string( path ).append( "::" ).append( name ) : canonicalId( path, scope, name );
}

// §B1.3: canonicalId over a symbol whose PATH SEGMENT is made relative to `root` — the one identity rule two
// unrelated subsystems both need. quality.h's baselineCanonId (a committed baseline must key the same way
// whether it was taken by `ripwire .` or `ripwire /abs/repo`) and serialize.h's field-note target (a note is
// stored under a root-relative id) each spelled it out separately; two subsystems that must AGREE on one
// identity while deriving it independently is how they drift. Pure string function of (path, root, scope,
// name), so both keep their determinism contract. Degrades exactly as canonicalId does: no scope ⇒ the bare
// name, and the root-relative path segment is then unused.
inline std::string canonicalIdRelTo( const IngestResult& ing, const Symbol& s, std::string_view root )
{
    return canonicalId( relForHash( ing.files[ s.fileId ], root ), s.scope, s.name );
}

// R-R (root-relative emission): the EMITTED canonical id — the `id=` attribute, its JSON twin, and the MCP
// content handle all key on this. Same rule as canonicalIdRelTo above, plus the empty-root degrade every
// emitter's `pathRel` lambda already applies to `p=`, so the two attributes of one row can never disagree
// about how a file is spelled.
//
// WHY THE DEGRADE IS NOT OPTIONAL. `root` is empty on exactly one path — a MULTI-ROOT run, where ing.files
// already hold the labeled `<label>/<root-relative-path>` identity and there is no single root to strip.
// Handing relForHash an empty root there would be actively wrong for an ABSOLUTE spelling: its residual
// leading-'/' normalization turns "/abs/x.h" into "abs/x.h", a path that resolves to nothing. So empty root
// ⇒ emit the stored spelling verbatim, which is already relative in the only case that reaches it.
//
// This is the emission side ONLY. It must never displace g.canonId (resolution, overload-set identity),
// quality's Regression::key, or any pathQualifiedKey — those are storage, and storage does not move here.
// It costs nothing on a relative-root run (relForHash strips a leading "./" the emitter would strip anyway)
// and, on an absolute-root run, removes the checkout prefix that every ranked row was paying per-row for a
// fact the envelope states once.
inline std::string canonicalIdForEmit( const IngestResult& ing, const Symbol& s, std::string_view root )
{
    return root.empty() ? canonicalId( ing.files[ s.fileId ], s.scope, s.name )
                        : canonicalIdRelTo( ing, s, root );
}

// The most shared-locality credit (sharedLocality below) the S6-C tie-break may give a candidate for this call: the whole
// canonical id, except for a NamedVar receiver whose type no receiver rule (2, 2c, 2b) established — an untyped local, a
// member Rule 2b cannot read, a typed variable whose type defines no such method. That receiver stops at the end of the
// caller's FILE segment, `path::` (`callerPath` is the path localityKeyOf built the caller's key from), so same-file and
// same-directory locality still count and the CLASS segment does not (2026-09-16, test/localitycheck.sh arms 5-9). The
// receiver names SOME object and nothing says it is one of the caller's class, so the caller's own class winning the
// scope credit is anti-evidence — the tie-break used to grant it on the premise "a typed var already narrowed above",
// and a receiver no rule typed never narrowed. Measured in isolation with --pin-census (before vs after): rocksdb 121
// call sites leave a locality decision for a split, a private C++ corpus 71, django 72, rails 145; this repo's src/,
// vue-core and go/net 0. Read samples: 14 of 14 rocksdb pins and 14 of 16 private ones were wrong, mostly delegation
// (`rep_->Name()` inside `Wrapper::Name`). Dropping the tie-break outright for these receivers moved no target on any of
// those seven corpora; it only relabelled the tiers whose one competitor is the caller itself (scored zero there) from
// `locality` to `unique`, losing their lpin= disclosure — so the file credit stays.
// STATED FLOOR, not closed here: the ladder's tier 1 still admits same-file candidates alone, so a delegation whose true
// target lives in another file lands on a same-file namesake before the tie-break runs.
inline std::size_t receiverLocalityCap( const Reference& r, bool receiverTypeNarrowed, std::string_view callerPath ) noexcept
{
    return ( r.recv == RecvKind::NamedVar && !receiverTypeNarrowed ) ? callerPath.size() + 2 : std::numeric_limits<std::size_t>::max();
}

// Shared-locality score of two canonical ids — counted in characters, but ONLY over WHOLE matching SEGMENTS.
// A canonical id is `path/to/file.ext::scope::name`, so its real structural boundaries are the `/` (directory)
// and `::` (scope/name) delimiters. The resolution tie-break wants "nearer" = same file > same class/scope >
// same directory; that is a comparison on those discrete SEGMENTS, NOT on raw bytes.
//
// A RAW byte prefix is wrong (adversarial HIGH-1): two unrelated classes that merely start with the same letter
// (`Xenon` caller vs class `Xtra`) share a longer leading byte-run *inside* one scope segment than the genuinely
// correct class (`Bravo`) — so a byte-prefix tie-break confidently picks the wrong target and reports it as
// unambiguous. A partial overlap WITHIN a segment is not locality, so it must count as ZERO.
//
// This returns the length of the longest common prefix that ENDS EXACTLY ON A SHARED SEGMENT BOUNDARY — i.e. the
// last `/`/`::` that both ids reached identically (or the whole string when both end together with the final
// segment fully matched). Bytes in a partially-matching segment past that boundary contribute nothing. So
// `Xenon`-caller vs `Xtra`/`Bravo` both score only their shared PATH (equal) → no winner → the call stays
// honestly ambiguous, instead of a spurious `Xenon`↔`Xtra` win. Deterministic; pure function of the two views.
inline std::size_t sharedLocality( std::string_view a, std::string_view b ) noexcept
{
    const std::size_t n   = a.size() < b.size() ? a.size() : b.size();
    std::size_t       cut = 0;   // last byte position where a confirmed shared SEGMENT boundary ended
    std::size_t       i   = 0;
    while( i < n && a[i] == b[i] )
    {
        if( a[i] == '/' )                                        // directory delimiter (1 char) → boundary after it
        {
            ++i;
            cut = i;
        }
        else if( a[i] == ':' && i + 1 < n && a[i + 1] == ':' && b[i + 1] == ':' )   // scope delimiter `::` → boundary after it
        {
            i  += 2;
            cut = i;
        }
        else
        {
            ++i;
        }
    }
    // both ids consumed entirely with every byte equal → the final segment matched too → the whole string counts.
    if( i == a.size() && i == b.size() )
    {
        cut = i;
    }
    return cut;
}

// Rule 2's qualifier guard (test/narrowcheck.sh arms 17-24): whether a declaration's written QUALIFIED type text
// (Binding::importedName, "" when unqualified) names namespace `std`. A recorded type is its final segment and class
// names carry no namespace, so `std::map<K, V> m; m.find( k )` narrowed to any in-repo class named `map`. `std` is
// reserved to the implementation ([namespace.std]: a program adds nothing to it but specializations), so no in-repo
// class IS the `std::` type — refusing costs nothing but the rare standard-library source tree's own narrows.
// EVERY OTHER QUALIFIER STILL NARROWS, measured: refusing them all refused 424 in-repo narrows on rocksdb
// (`ROCKSDB_NAMESPACE::Status s; s.ok()`), 11 on a private C++ corpus and 9 on src/, every sampled one correct,
// and fixed no wrong edge outside `std`. STATED FLOOR: a qualifier that is neither `std` nor the class's own
// namespace (an external or alias-template type whose final segment an in-repo class shares) still narrows on the
// name — closing it needs the namespace chain in Symbol::scope (arm 24 pins it). The text is ingest_binds.h
// qualifiedNameText's, which already dropped a leading global `::` (`::std::map` arrives as `std::map`).
// Readers: the lexical lookup (Narrower::recvVarTypeName) answers "" for such a declaration; buildGraph's flat varType
// table TOMBSTONES the variable rather than skipping the record, because it cannot tell which of a function's
// declarations of the name is in scope at a call site (six `std::map` locals narrowed wrong on a private C++ corpus).
inline bool namesStdType( std::string_view qualified ) noexcept
{
    return qualified.starts_with( "std::" );
}

// The same fact for a member FIELD (test/fieldnarrowcheck.sh arm q): a compose reference for `std::string name_;` carries the
// type's final segment as its name and the namespace the type was written in as its qualifier (ingest_relations.h
// writtenTypeNamespace). The capture reads only the two-segment spelling, so that qualifier is one written namespace — never
// a nested one, and never an inline ABI namespace, which no conforming program spells. graph.h's two readers of the capture
// refuse it: buildFieldNarrowTables records no type for it (a tombstone when a same-named class's same-named field has a real
// type — a skip would hand that type to this field's calls), and the HAS-A edges draw none.
inline bool fieldTypeWrittenInStd( const Reference& r ) noexcept
{
    return r.isCompose && r.qualifier == "std";
}

// A C/C++/ObjC TYPE ALIAS record (ingest_relations.h captureTypeAlias): `typedef llvm::IRBuilder<F, I> CGBuilderBaseTy;` rides the
// compose shape as recvVar CGBuilderBaseTy, calleeName IRBuilder, qualifier llvm — with an EMPTY fieldName, so buildFieldNarrowTables
// never reads it as a member, and composeRel "alias", which the HAS-A edges refuse. addTypeAliasBases is its one reader.
inline bool isTypeAliasRecord( const Reference& r ) noexcept
{
    return r.isCompose && r.fieldName.empty() && r.composeRel == "alias";
}

// The inheritance NAME graph's alias edges (graph.h chaUp): an alias NAME gains its target as a direct base, so a base walk that
// reaches the alias continues at the class it names — `class CGBuilderTy : public CGBuilderBaseTy` walks on to IRBuilder and
// IRBuilderBase (test/fieldnarrowcheck.sh arm t). chaUp ONLY: an alias is not a subclass, so no cone, --lego implementor or
// role="extends" use-site gains a member. Refused, as a written type is elsewhere: a target written in `std` (it names no in-repo
// class). NOT followed: an alias NAME that is also a real class somewhere in the corpus — a class-like symbol of that name at a
// line no alias record holds (a typedef is itself a Struct symbol at its name's line). The graph keys classes by bare name, so
// `using Base = Foo;` in one class would otherwise hand Foo's methods to every class that derives from an unrelated `Base`.
// Same-named aliases with different targets keep BOTH as bases: the walk's one-hit-per-level rule refuses a real tie.
inline void addTypeAliasBases( const IngestResult& ing, HashMap<std::string, std::vector<std::string>>& chaUp )
{
    const auto followable = []( const Reference& r ) noexcept
    {
        return isTypeAliasRecord( r ) && !fieldTypeWrittenInStd( r ) && !r.recvVar.empty() && !r.calleeName.empty();
    };
    const auto siteKey = []( std::string& key, std::uint32_t fileId, std::uint32_t line, std::string_view name )
    {
        key.assign( std::to_string( fileId ) ).push_back( ':' );
        key.append( std::to_string( line ) ).push_back( ':' );
        key.append( name );
    };
    std::vector<std::uint32_t> aliasRefs;
    HashMap<std::string, char> aliasSites;
    HashMap<std::string, char> aliasNames;
    std::string                key;
    for( std::uint32_t refIndex = 0; refIndex < ing.references.size(); ++refIndex )
    {
        if( const Reference& r = ing.references[ refIndex ]; followable( r ) )
        {
            aliasRefs.push_back( refIndex );
            siteKey( key, r.fileId, r.line, r.recvVar );
            aliasSites.try_emplace( key, '\0' );
            aliasNames.try_emplace( r.recvVar, '\0' );
        }
    }
    HashMap<std::string, char> realClassNames;   // alias names some class-like symbol at a non-alias site also carries
    for( const Symbol& s : ing.symbols )
    {
        const bool classLike = s.kind == SymKind::Class || s.kind == SymKind::Struct || s.kind == SymKind::Interface;
        if( classLike && aliasNames.find( s.name ) != aliasNames.end() )
        {
            siteKey( key, s.fileId, s.line, s.name );
            if( aliasSites.find( key ) == aliasSites.end() )
            {
                realClassNames.try_emplace( s.name, '\0' );
            }
        }
    }
    for( std::uint32_t refIndex : aliasRefs )
    {
        if( const Reference& r = ing.references[ refIndex ]; realClassNames.find( r.recvVar ) == realClassNames.end() )
        {
            chaUp[ r.recvVar ].push_back( r.calleeName );   // the caller sorts and dedups every adjacency list
        }
    }
}

// Every Class/Struct/Interface NAME in the corpus: Rule 2c's receiver-token test (Narrower::rule2cClassNameRecv) and the
// assignment guard below. Names carry no namespace, so this answers "some class is called that", never which one.
// A Ruby MODULE joins that set. It is a receiver of class methods exactly as a class is (`Util.format`, the service-object
// idiom), and `@definition.module` maps to SymKind::Other (ingest_crawl.h::defKind) for every language rather than to a
// kind of its own. Restricted to Ruby because there the implication runs both ways: queries/ruby/tags.scm emits class,
// module, method and constant, and the other three have kinds of their own, so a Ruby SymKind::Other symbol IS a module.
// test/rubyrecvnarrowcheck.sh.
inline HashMap<std::string, char> classNameSet( const IngestResult& ing )
{
    HashMap<std::string, char> classNames;
    classNames.reserve( ing.symbols.size() / 8 + 1 );
    for( const Symbol& s : ing.symbols )
    {
        const bool rubyModule = ( s.lang == Lang::Ruby && s.kind == SymKind::Other );
        if( s.kind == SymKind::Class || s.kind == SymKind::Struct || s.kind == SymKind::Interface || rubyModule )
        {
            classNames.try_emplace( s.name, '\0' );
        }
    }
    return classNames;
}

// Rule 2's assignment guard (test/narrowcheck.sh arms 44-51): whether a Type record a C++ ASSIGNMENT emitted names no class.
// `x = f( … )` records the callee's last name as x's type (ingest_binds.h assignedTypeOf), because a constructor call and
// a function call are one grammar node: `t = llvm::cast<Target>( y )` recorded `cast`, `t = makeTarget( y )` recorded
// `makeTarget`. An assignment declares nothing, so such a name is no fact about the variable, and every reader of the
// record drops it — buildGraph's flat varType table and collectFieldUseSites' table, where it tombstoned the declaration's
// written `Target* t` (a lost narrow, a lost field pin). The local-name set keeps it: localNameEvidence marks an assignment
// bound but not declared, so Rule 2b no longer reads a MEMBER assigned from a call as a local, while Rule 2c still reads the
// name as a variable (integration/train-5 joined the two). A DECLARATION's callee-read name is kept: that
// declaration exists with a type nothing recorded, and its conflict with a sibling declaration of the name is the tombstone
// that keeps one block's type off the other block's calls (arm 48). An assignment from a class keeps its record, conflict
// included (arm 47). The lexical table (buildScopedRecvDecls) never attaches an assignment's record: no declaration shares
// its byte.
inline bool assignmentNamesNoClass( const Binding& b, const HashMap<std::string, char>& classNames )
{
    return b.isFromAssignment && classNames.find( b.typeName ) == classNames.end();
}

// The VALUE of buildFieldNarrowTables' localNameSet (graph.h): the evidence one "<fromSymbol>#<var>" key holds, OR-ed over its
// binding records (test/fieldnarrowcheck.sh arm v). Its readers ask two different questions, and an assignment answers only
// one. Rule 2c and the Phase 5 external veto ask whether the name is a VARIABLE in that definition, and any record says so:
// `Widget = makePane();` proves `Widget` is no class. Rule 2b asks whether a LOCAL hides a member of the enclosing class, and
// only a declaration introduces one: `OutputFile = std::make_unique<ToolOutputFile>( … );` inside a method assigns the member,
// yet ingest records it — a Type record naming the callee (ingest_binds.h's assignment arm), an L3 FnAssign for `x = other`,
// a clobber tombstone for `x = nullptr` — and counting those refused the member's declared type. Every local-declaring shape
// emits VarDecl (a block or condition declaration, a parameter, a range-for variable, a structured binding, a catch parameter,
// a lambda parameter or capture) or ParamType, and FnDecl is a declaration too: the misparsed `void (*fn)() = &f;` has no VarDecl.
// One declaration still records none: a direct-initialised local whose arguments are plain names, `Foo x( a, b );`, which the
// grammar reads as a function declarator — a call inside its scope takes the member's type (fieldnarrowcheck arm v4, a floor).
inline constexpr char kLocalNameBound    = 1;   // some binding record names the variable
inline constexpr char kLocalNameDeclared = 2;   // a declaration record does

inline char localNameEvidence( LocalBindKind kind ) noexcept
{
    const bool declares = kind == LocalBindKind::VarDecl || kind == LocalBindKind::ParamType || kind == LocalBindKind::FnDecl;
    return declares ? char( kLocalNameBound | kLocalNameDeclared ) : kLocalNameBound;
}

// One entry of Rule 2's FLAT per-function type table (buildGraph's varType) and of Rule 2b's "Class#field" table
// (buildFieldNarrowTables): the declared type name — "" is a TOMBSTONE, an ambiguous or `std::`-typed name that never
// narrows — whether a declaration wrote that type QUALIFIED, the fact prov="final-segment" discloses
// (Narrower::finalSegmentTypeAt for a parameter or local, Narrower::fieldFinalSegmentAt for a field), and, for a field only,
// whether the type is the POINTEE of a std smart pointer member, which a call reaches through `->` alone (test/fieldnarrowcheck.sh
// arm p): `w_.reset()` on `std::unique_ptr<Widget> w_;` is the smart pointer's own member, never Widget::reset.
struct FlatRecvType
{
    std::string type;
    bool        writtenQualified = false;
    bool        arrowOnly        = false;
};

// fold one declared type into a flat table: the first type wins, a different later type tombstones, and an agreeing
// declaration that wrote it qualified marks the entry. `type` is "" for a refused (`std::`) type, which tombstones too. A type
// reached through `->` alone (`arrowOnly`) and the same type reached as the member itself are different facts, and tombstone too.
inline void recordFlatRecvTypeFact( HashMap<std::string, FlatRecvType>& table, const std::string& key, std::string_view type, bool writtenQualified,
                                    bool arrowOnly = false )
{
    const auto [ it, inserted ] = table.try_emplace( key );
    if( inserted )
    {
        it->second.type.assign( type );
        it->second.writtenQualified = writtenQualified;
        it->second.arrowOnly        = arrowOnly;
    }
    else if( !it->second.type.empty() && ( it->second.type != type || it->second.arrowOnly != arrowOnly ) )
    {
        it->second.type.clear();   // conflicting types for one name in one scope → tombstone (never narrow on it)
    }
    else
    {
        it->second.writtenQualified = it->second.writtenQualified || writtenQualified;
    }
}

// fold one Type binding into a flat table (buildGraph's varType; also collectFieldUseSites' Type+ParamType table): the first type wins, a different later type or a `std::` one tombstones
inline void recordFlatRecvType( HashMap<std::string, FlatRecvType>& table, const std::string& key, const Binding& b )
{
    recordFlatRecvTypeFact( table, key, namesStdType( b.importedName ) ? std::string_view{} : std::string_view( b.typeName ), !b.importedName.empty() );
}

// what Rule 2 and CHA-lite read for one named receiver at one site: its type name ("" = none), whether the declaration
// that decided it wrote the type QUALIFIED — a match on the final segment alone, whose qualifier nothing checked — and, for
// Rule 2's class identity, that declaration's typed record when the lexical table decided it (nullptr on the flat table)
struct RecvVarType
{
    std::string_view name;
    bool             writtenQualified = false;
    const Binding*   declared         = nullptr;
};

// The provenance value of one resolved edge (Graph::outProv; graph.h provLabel spells it) from the edge sets the resolve loop
// filled. The precedence is deliberate: scip PINS an edge (precise); binding and import NAME the mechanism that resolved it;
// split says the resolver could not choose; final-segment says it chose by a qualified written type's last name alone
// (test/narrowcheck.sh arm 25). prov= is single-valued and a symbol's amb= counts a split arm either way, so nothing is
// lost by the ordering. 0 = a uniquely resolved name-based edge, which no emitter writes.
struct EdgeProvenanceSets
{
    const HashMap<std::uint64_t, char>& binding;
    const HashMap<std::uint64_t, char>& import;
    const HashMap<std::uint64_t, char>& split;
    const HashMap<std::uint64_t, char>& finalSegment;
};
inline std::uint8_t edgeProvenance( bool scipPrecise, const EdgeProvenanceSets& sets, std::uint64_t edgeKey ) noexcept
{
    const auto holds = [ edgeKey ]( const HashMap<std::uint64_t, char>& set ) { return set.find( edgeKey ) != set.end(); };
    if( scipPrecise )
    {
        return 1u;
    }
    if( holds( sets.binding ) )
    {
        return 2u;
    }
    if( holds( sets.import ) )
    {
        return 4u;
    }
    if( holds( sets.split ) )
    {
        return 3u;
    }
    return holds( sets.finalSegment ) ? 5u : 0u;
}

// P2-D Rule 2, PARAMETER receivers (2026-09-16, test/narrowcheck.sh arms 7-18): one DECLARATION of a receiver
// name inside one definition — the scope its VarDecl record covers and the written type its Type/ParamType
// record carries, joined on the record position the two share (Binding::startByte).
// buildScopedRecvDecls (below) builds the table; Narrower::recvVarTypeName reads it.
struct ScopedRecvDecl
{
    std::uint32_t declByte;      // Binding::startByte of the declaration's records
    std::uint32_t spanStart;     // the VarDecl span: where the name denotes THIS declaration
    std::uint32_t spanEnd;
    std::uint32_t typeBinding;   // index into ing.bindings of the typed record, or one of the two sentinels below
};
static_assert( std::is_trivially_copyable_v<ScopedRecvDecl> && sizeof( ScopedRecvDecl ) == 16, "four u32 — an rw::svector element" );
inline constexpr std::uint32_t kRecvDeclUntyped    = 0xFFFFFFFFu;   // no typed record at this declaration (`auto`, a capture)
inline constexpr std::uint32_t kRecvDeclConflicted = 0xFFFFFFFEu;   // two typed records disagree — never narrows

// the lexical table and the bindings its typeBinding indices point into, held together so they cannot be paired wrong
struct ScopedRecvDecls
{
    // "<fromSymbol>#<var>" → that name's declarations in the definition, in declaration-byte order. Holds ONLY names
    // with at least one ParamType record; every other name keeps the flat varType table, byte-identical.
    HashMap<std::string, rw::SmallVec<ScopedRecvDecl, 1>> byName;
    const std::vector<Binding>*                           bindings = nullptr;
};

// ── P2-D Rule 2 PARAMETER receivers: building the lexical declaration table (2026-09-16, test/narrowcheck.sh arms 7-18) ──
// A ParamType record — a definition or lambda parameter, a typed range-for variable, a reference local — was read
// by the field use-site index alone, so `int Decoy::plainCaller( Target& other ) { return other.pick( 1 ); }` fell
// through Rule 2 and the S6-C locality tie-break handed the site to Decoy::pick: one precise wrong edge, no amb=.
// It cannot simply join the flat per-definition varType table: every one of those shapes is scoped narrower than
// the definition or can be hidden by a nested redeclaration, and the naive fold was MEASURED to mint three precise
// wrong edges on the gate fixture (arms 12-14: a range-for variable's type reaching a later `auto` loop of the same
// name, a same-named field read after the loop, and a parameter hidden by an untyped loop variable). So for every
// name with a ParamType record, this lists ALL its declarations in the definition — each VarDecl with its scope
// span — and attaches each Type/ParamType record to the declaration whose VarDecl shares its record position;
// Narrower::recvVarTypeName asks which one is innermost at the call site, and narrows on its type unless the type was
// written in namespace `std` — a written type is its final segment alone, and a parameter's is often a library container
// (`const std::map<K, V>&`) whose name an unrelated in-repo class shares (namesStdType above, arm 17; the qualified
// text rides Binding::importedName). A typed record with no VarDecl at its
// position (a shape the shadow capture refuses) types nothing: a lost narrow, never a wrong one. Names with no
// ParamType record are absent and keep the flat varType answer, byte-identically. Deterministic: ing.bindings is
// totally ordered, lists are appended in that order, and nothing iterates the map into output.
inline void attachRecvDeclType( ScopedRecvDecl& decl, std::uint32_t bindIndex, const std::vector<Binding>& bindings ) noexcept
{
    if( decl.typeBinding == kRecvDeclUntyped )
    {
        decl.typeBinding = bindIndex;
    }
    else if( decl.typeBinding != kRecvDeclConflicted && bindings[ decl.typeBinding ].typeName != bindings[ bindIndex ].typeName )
    {
        decl.typeBinding = kRecvDeclConflicted;   // one declaration, two written types — trust neither
    }
}

// a binding record the lexical table can key: attributed to a definition, naming a variable
inline bool isScopedBindRecord( const Binding& b ) noexcept
{
    return b.fromSymbol != kNoNode && !b.var.empty();
}

// the names the table covers: every "<fromSymbol>#<var>" with a ParamType record
inline void addParamTypedNames( const IngestResult& ing, ScopedRecvDecls& table, std::string& key )
{
    const auto isParamType = []( const Binding& b ) noexcept { return b.kind == LocalBindKind::ParamType && isScopedBindRecord( b ); };
    table.byName.reserve( std::size_t( std::ranges::count_if( ing.bindings, isParamType ) ) );
    for( const Binding& b : ing.bindings )
    {
        if( isParamType( b ) )
        {
            buildShadowKey( key, b.fromSymbol, b.var );
            table.byName.try_emplace( key );
        }
    }
}

// every declaration of those names: the VarDecl records, in (file, byte) order — an exact repeat of the previous one
// (the same declaration captured twice) is dropped, or it would tie with itself and refuse the site
inline void addRecvDeclScopes( const IngestResult& ing, ScopedRecvDecls& table, std::string& key )
{
    for( const Binding& b : ing.bindings )
    {
        if( b.kind != LocalBindKind::VarDecl || !isScopedBindRecord( b ) )
        {
            continue;
        }
        buildShadowKey( key, b.fromSymbol, b.var );
        const auto it = table.byName.find( key );
        if( it == table.byName.end() )
        {
            continue;
        }
        const ScopedRecvDecl decl{ b.startByte, b.spanStart, b.spanEnd, kRecvDeclUntyped };
        const bool repeat = !it->second.empty() && it->second.back().declByte == decl.declByte && it->second.back().spanStart == decl.spanStart
                         && it->second.back().spanEnd == decl.spanEnd;
        if( !repeat )
        {
            it->second.push_back( decl );
        }
    }
}

// each written type onto the declaration that shares its record position
inline void attachRecvDeclTypes( const IngestResult& ing, ScopedRecvDecls& table, std::string& key )
{
    for( std::uint32_t bindIndex = 0; bindIndex < std::uint32_t( ing.bindings.size() ); ++bindIndex )
    {
        const Binding& b = ing.bindings[ bindIndex ];
        if( ( b.kind != LocalBindKind::Type && b.kind != LocalBindKind::ParamType ) || !isScopedBindRecord( b ) || b.typeName.empty() )
        {
            continue;
        }
        buildShadowKey( key, b.fromSymbol, b.var );
        const auto it = table.byName.find( key );
        if( it == table.byName.end() )
        {
            continue;
        }
        for( ScopedRecvDecl& decl : it->second )
        {
            if( decl.declByte == b.startByte ) { attachRecvDeclType( decl, bindIndex, ing.bindings ); }
        }
    }
}

inline ScopedRecvDecls buildScopedRecvDecls( const IngestResult& ing )
{
    PROFILE_SCOPE_DESCRIBE( "buildGraph/2j: Rule-2 lexical receiver declarations" );
    ASSUME( ing.bindings.size() < kRecvDeclConflicted );   // typeBinding indices stay clear of the two sentinels
    ScopedRecvDecls table;
    table.bindings = &ing.bindings;
    std::string key;
    addParamTypedNames( ing, table, key );
    if( !table.byName.empty() )
    {
        addRecvDeclScopes( ing, table, key );
        attachRecvDeclTypes( ing, table, key );
    }
    return table;
}

// ── using-declaration re-exports — built once per buildGraph, consumed via Narrower::ownMethodSet (the type-side
// probe Rules 2b/2c and Rule 1's base walk share). "Class::m" → the sorted, deduped names of the classes a class-scope
// `using Base::m;` names for `m`. In C++ a class's own `m` HIDES every base `m`; the using-declaration puts the named
// base's members into the class's own scope (clang's CGNonTrivialStruct.cpp: `using StructVisitor<Derived>::asDerived;`
// in a class whose two bases both define asDerived). ownMethodSet reads it only for a class with no `m` of its own.
// The facts are the import refs the tags pass already mints (queries/cpp/tags.scm using_declaration → RefRole::Import): one whose enclosing symbol is a Class/Struct sits
// at class scope. The key is that class's NAME — the scope string its methods carry — so it is byte-identical to the
// canonByName key of the class's own `m`. The qualifier is the IMMEDIATE scope (ingest's re-split) and loses its
// template arguments here, where the 2-segment spelling `using Base<T>::m;` still carries them. An inheriting
// constructor `using Base::Base;` records nothing: no member call names it. RESOLVE-stage only — every input is a
// field the cache already stores. Deterministic: pure function of ing.references; each list sorted and deduped.
inline HashMap<std::string, std::vector<std::string>> buildUsingReexports( const IngestResult& ing )
{
    PROFILE_SCOPE_DESCRIBE( "buildGraph/2k: using-declaration re-exports" );
    HashMap<std::string, std::vector<std::string>> reexports;
    std::string                                    key;   // reused "Class::m" buffer
    for( const Reference& ur : ing.references )
    {
        if( ur.role != RefRole::Import || ur.fromSymbol == kNoNode || ur.qualifier.empty() || ( ur.lang != Lang::Cpp && ur.lang != Lang::ObjC ) )
        {
            continue;
        }
        const Symbol& cls = ing.symbols[ ur.fromSymbol ];
        const std::string_view base = namesplit::stripTemplateArgs( ur.qualifier );
        if( ( cls.kind != SymKind::Class && cls.kind != SymKind::Struct ) || base.empty() || base == ur.calleeName || base == cls.name )
        {
            continue;   // not at class scope, an inheriting constructor, or a class naming itself
        }
        key.clear();
        key.append( cls.name ).append( "::" ).append( ur.calleeName );
        reexports[ key ].emplace_back( base );
    }
    for( auto& [ k, bases ] : reexports )
    {
        std::sort( bases.begin(), bases.end() );
        bases.erase( std::unique( bases.begin(), bases.end() ), bases.end() );
    }
    return reexports;
}

// S6-C's ranking key for one candidate: sharedLocality doubled, plus one when a BARE or `this->` call's candidate is
// declared in the caller's OWN scope rather than in a scope nested inside it. Both share the caller's whole
// `path::Scope::` prefix, so counting segments ties `Outer::start` with `Outer::Inner::start` for a `start()` written in
// `Outer::operator=`; but a nested class's non-static member needs an object, so the bare call names Outer's. The
// bonus never separates candidates the segment count already ranks, never applies to an explicit receiver (whose
// type, not the enclosing scope, decides), and never fires when either id's NAME holds `::` (a conversion operator's
// type) — that case keeps the plain tie. test/cpptmplscopecheck.sh §6. `shareCap` is receiverLocalityCap's limit on the
// shared credit (an untyped NamedVar receiver stops at the caller's file segment); it binds only a receiver the bonus
// never applies to, so the two rules cannot meet on one call.
inline std::size_t localityRank( std::string_view caller, std::string_view cand, bool lexicalCall, std::size_t shareCap ) noexcept
{
    const std::size_t shared   = std::min( sharedLocality( caller, cand ), shareCap );
    const std::size_t scopeEnd = caller.rfind( "::" );
    const bool        ownScope = lexicalCall && scopeEnd != std::string_view::npos && shared == scopeEnd + 2
                              && cand.find( "::", shared ) == std::string_view::npos;
    return 2 * shared + ( ownScope ? 1u : 0u );
}

// The FAMILY key of a C++ template-id scope: `Traits<int>` + `encode` → "Traits::encode" written into `key`, true;
// false with `key` untouched for a scope that is not a template-id. Ingest keys a primary template's out-of-line
// member by the bare template name and a specialization by its canonical template-id (ingest_names.h), so the family
// of `Traits::encode` is the defs keyed by it plus every specialization def whose own family key it is.
inline bool appendTemplateFamilyKey( std::string& key, std::string_view scope, std::string_view name )
{
    if( scope.empty() || scope.back() != '>' )
    {
        return false;
    }
    const std::string_view family = namesplit::stripTemplateArgs( scope );
    if( family.empty() || family.size() == scope.size() )
    {
        return false;
    }
    key.clear();
    key.append( family ).append( "::" ).append( name );
    return true;
}

// ── P2-D Rule 2 CLASS IDENTITY (2026-09-16, test/narrowcheck.sh arms 25-34) ──────────────────────────────────────────
// Rule 2 keys a receiver's type by its final class-name segment, and a NESTED class keeps only that segment in its
// scope: `SkipList<Key, Comparator>::Iterator::key` and a namespace-level `Iterator`'s methods share the key
// `Iterator::key`. Measured on rocksdb @ 0e2801ac3: a call through `Iterator* it` — an abstract interface whose methods
// are pure-virtual DECLARATIONS, never in the definitions-only canonByName — narrowed onto the five unrelated nested
// `Iterator` classes in memtable/ that define `key`, and none was right. This index restores the class identity the key
// dropped, from facts ingest already has: byte spans (a class inside another class's span is nested in it), the scope a
// member names, the inherit references, the include targets and the namespace scopes of non-members. IdentityNarrower
// below reads it for Rule 2. C-family only (C, C++, ObjC): every other language keeps unknown owners and an unchanged answer.
// FLOORS, stated: namespaces are evidence, not a model (a same-named class in another namespace the caller also includes
// stays a candidate); a nested class's out-of-line member defined in a different FILE than the class has no known owner;
// a base the inherit reference records only by its final segment (`public Outer::Iterator`) is judged by nesting alone;
// a type alias is kept rather than read through.
using ChaUpNames = HashMap<std::string, std::vector<std::string>>;

struct ClassIdentity
{
    struct FlatQualifier
    {
        std::string text;             // the written type WHOLE when qualified, "" when written bare
        bool        conflicting = false;
    };
    const std::vector<Symbol>*                            symbols = nullptr;
    const std::vector<std::string>*                       files   = nullptr;
    std::vector<NodeId>                                   enclosingClass;   // class id → innermost enclosing class, kNoNode at namespace scope
    std::vector<NodeId>                                   ownerClass;       // member id → the class that owns it, kNoNode when unknown
    std::vector<std::uint8_t>                             ownerAmbiguous;   // 1: an out-of-line member whose file holds SEVERAL classes of its scope's name
    HashMap<std::string, rw::SmallVec<NodeId, 2>>         classesByName;    // C-family class DEFINITIONS by name, in id order
    HashMap<std::string, rw::SmallVec<NodeId, 2>>         nestedByName;     // the NESTED ones among them, by name
    HashMap<std::string, rw::SmallVec<NodeId, 4>>         realDown;         // base NAME → derived class ids, namesake edges excluded
    HashMap<NodeId, std::vector<std::string_view>>        realUp;           // derived class id → base names (views into ing.references)
    HashMap<std::string, char>                            declared;         // "Scope::name" of a C-family member DECLARATION (no body)
    HashMap<std::string, rw::SmallVec<NodeId, 2>>         specializationDefs; // "Template::name" → definitions scoped to a template-id of that class
    HashMap<std::string, char>                            fileNamespaces;   // "<fileId>#<ns>": the file defines a non-member under namespace scope ns
    std::vector<std::vector<std::string_view>>            namespacesOfFile; // the same evidence per file id (views into Symbol::scope)
    struct IncludeTarget
    {
        std::uint32_t    fileId;
        std::string_view target;   // as written (a view into ing.includes)
    };
    std::vector<IncludeTarget>                            includeTargets;   // every direct #include, ordered by including file
    HashMap<std::string, FlatQualifier>                   flatQualifier;    // "<fromSymbol>#var" → the flat-table records' written qualifier
};

// the positions of the last two top-level `::` separators of a qualified name; template arguments are skipped by bracket
// depth, so a `::` inside them (`Map<std::string>::Iterator`) is never a boundary. npos where there is none.
inline std::pair<std::size_t, std::size_t> lastTwoTopLevelSeparators( std::string_view qualified ) noexcept
{
    std::size_t prevSep = std::string_view::npos;
    std::size_t lastSep = std::string_view::npos;
    int         depth   = 0;
    for( std::size_t i = 0; i + 1 < qualified.size(); ++i )
    {
        const char c = qualified[ i ];
        depth += ( c == '<' ) ? 1 : ( ( c == '>' && depth > 0 ) ? -1 : 0 );
        if( depth == 0 && c == ':' && qualified[ i + 1 ] == ':' )
        {
            prevSep = lastSep;
            lastSep = i++;
        }
    }
    return { prevSep, lastSep };
}

// the class a written qualifier's LAST segment names: `Skip::Iterator` → `Skip`, `SkipList<Key, Comparator>::Iterator` →
// `SkipList`, `ns::Outer::Iterator` → `Outer`; "" for a bare name
inline std::string_view qualifierOuterName( std::string_view qualified ) noexcept
{
    const auto [ prevSep, lastSep ] = lastTwoTopLevelSeparators( qualified );
    if( lastSep == std::string_view::npos )
    {
        return {};
    }
    const std::size_t start = ( prevSep == std::string_view::npos ) ? 0 : prevSep + 2;
    const std::string_view outer = qualified.substr( start, lastSep - start );
    return trimWs( outer.substr( 0, std::min( outer.size(), outer.find( '<' ) ) ) );
}

// does class NAME `derived` reach class NAME `base` up the name-keyed chaUp graph? Bounded. A same-name collision only ever
// ENLARGES the answer, which on both callers is the conservative side (a class stays nameable, an edge stays a namesake).
inline bool derivesFromName( std::string_view derived, std::string_view base, const ChaUpNames& chaUp )
{
    std::vector<std::string_view> frontier{ derived };
    std::vector<std::string_view> next;
    for( int depth = 0; depth < 12 && !frontier.empty(); ++depth )
    {
        next.clear();
        for( std::string_view name : frontier )
        {
            const auto it = chaUp.find( std::string( name ) );
            if( it == chaUp.end() )
            {
                continue;
            }
            if( std::ranges::find( it->second, base ) != it->second.end() )
            {
                return true;
            }
            next.insert( next.end(), it->second.begin(), it->second.end() );
        }
        frontier.swap( next );
    }
    return false;
}

// a class DEFINITION only: a forward declaration (`class Iterator;`, five at rocksdb's namespace scope) names no class body,
// and counted as one it made every bare `Iterator` look like several namesakes
inline void addClassDefinitions( const IngestResult& ing, ClassIdentity& ids )
{
    for( const Symbol& s : ing.symbols )
    {
        if( extent::inSet( extent::kHeadRuleLangs, s.lang ) && extent::inSet( extent::kExtentClassKinds, s.kind ) && isDefinitionNotDeclaration( s ) )
        {
            ids.classesByName[ s.name ].push_back( s.id );
        }
    }
}

// the member DECLARATIONS ("Scope::name", bodiless) and each file's namespace evidence: a scope no class carries is a namespace
inline void addDeclarationsAndNamespaces( const IngestResult& ing, ClassIdentity& ids )
{
    std::string key;
    for( const Symbol& s : ing.symbols )
    {
        if( !extent::inSet( extent::kHeadRuleLangs, s.lang ) || extent::inSet( extent::kExtentClassKinds, s.kind ) || s.scope.empty() )
        {
            continue;
        }
        if( !isDefinitionNotDeclaration( s ) )
        {
            key.assign( s.scope ).append( "::" ).append( s.name );
            ids.declared.try_emplace( key, '\0' );
        }
        if( ids.classesByName.find( s.scope ) != ids.classesByName.end() )
        {
            continue;
        }
        buildShadowKey( key, s.fileId, s.scope );
        if( ids.fileNamespaces.try_emplace( key, '\0' ).second && s.fileId < ids.namespacesOfFile.size() )
        {
            ids.namespacesOfFile[ s.fileId ].push_back( s.scope );
        }
    }
}

// per file, the C-family symbols in (start, end descending, id) order — the order a containment sweep needs
inline SymbolsByFile cFamilySymbolsBySpan( const IngestResult& ing )
{
    SymbolsByFile perFile = symbolsByFileInIdOrder( ing, []( const Symbol& s ) { return extent::inSet( extent::kHeadRuleLangs, s.lang ); } );
    const auto spanOrder = [ & ]( NodeId a, NodeId b )
    {
        const Symbol& x = ing.symbols[ a ];
        const Symbol& y = ing.symbols[ b ];
        if( x.sigStartByte != y.sigStartByte ) { return x.sigStartByte < y.sigStartByte; }
        if( x.endByte != y.endByte )           { return x.endByte > y.endByte; }
        return a < b;
    };
    for( FileSymbols& list : perFile )
    {
        std::sort( list.begin(), list.end(), spanOrder );
    }
    return perFile;
}

// one file's containment sweep with a stack of open classes: every class gets its innermost enclosing class, every member
// the innermost enclosing class of its scope's name
inline void sweepFileNesting( const IngestResult& ing, const FileSymbols& list, ClassIdentity& ids )
{
    std::vector<NodeId> open;
    for( NodeId id : list )
    {
        const Symbol& s = ing.symbols[ id ];
        while( !open.empty() && ing.symbols[ open.back() ].endByte < s.endByte )
        {
            open.pop_back();   // the innermost open class ends before this symbol does: it cannot contain it
        }
        if( extent::inSet( extent::kExtentClassKinds, s.kind ) )
        {
            ids.enclosingClass[ id ] = open.empty() ? kNoNode : open.back();
            open.push_back( id );
        }
        else if( !s.scope.empty() )
        {
            const auto owner = std::find_if( open.rbegin(), open.rend(), [ & ]( NodeId c ) { return ing.symbols[ c ].name == s.scope; } );
            ids.ownerClass[ id ] = ( owner == open.rend() ) ? kNoNode : *owner;
        }
    }
}

// "<classId>#<member name>" for every bodiless member inside that class's span
inline HashMap<std::string, char> bodilessMembersByClass( const IngestResult& ing, const ClassIdentity& ids )
{
    HashMap<std::string, char> declaresMember;
    std::string                key;
    for( const Symbol& s : ing.symbols )
    {
        if( extent::inSet( extent::kHeadRuleLangs, s.lang ) && !extent::inSet( extent::kExtentClassKinds, s.kind ) && ids.ownerClass[ s.id ] != kNoNode && !isDefinitionNotDeclaration( s ) )
        {
            buildShadowKey( key, ids.ownerClass[ s.id ], s.name );
            declaresMember.try_emplace( key, '\0' );
        }
    }
    return declaresMember;
}

// one out-of-line member among the classes of its scope's name: the one in its file when there is one; among several there,
// the nearest PRECEDING one whose body DECLARES it (C++ defines a member out of line only after the class that declares it:
// `ListRep::Iterator` defines `key` inline, so the out-of-line `key` after `Skip::Iterator` is Skip's); still ambiguous when
// none decides
inline void assignOutOfLineOwner( const IngestResult& ing, const Symbol& s, const rw::SmallVec<NodeId, 2>& candidates,
                                  const HashMap<std::string, char>& declaresMember, ClassIdentity& ids )
{
    std::string   key;
    std::uint32_t sameFile = 0;
    NodeId        declarer = kNoNode;
    for( NodeId c : candidates )
    {
        const Symbol& cls = ing.symbols[ c ];
        if( cls.fileId != s.fileId )
        {
            continue;
        }
        ids.ownerClass[ s.id ] = ( sameFile++ == 0 ) ? c : ids.ownerClass[ s.id ];
        buildShadowKey( key, c, s.name );
        const bool precedesAndDeclares = cls.sigStartByte < s.sigStartByte && declaresMember.find( key ) != declaresMember.end();
        declarer = ( precedesAndDeclares && ( declarer == kNoNode || ing.symbols[ declarer ].sigStartByte < cls.sigStartByte ) ) ? c : declarer;
    }
    if( sameFile > 1 && declarer != kNoNode )
    {
        ids.ownerClass[ s.id ] = declarer;
        sameFile               = 1;
    }
    ids.ownerAmbiguous[ s.id ] = std::uint8_t( sameFile > 1 ? 1 : 0 );
}

// an out-of-line member (`inline int Skip::Iterator::key() const { … }`) sits in no class span; unknown when its file
// defines no class of its scope's name
inline void assignOutOfLineOwners( const IngestResult& ing, ClassIdentity& ids )
{
    const HashMap<std::string, char> declaresMember = bodilessMembersByClass( ing, ids );
    for( const Symbol& s : ing.symbols )
    {
        if( !extent::inSet( extent::kHeadRuleLangs, s.lang ) || s.scope.empty() || extent::inSet( extent::kExtentClassKinds, s.kind ) || ids.ownerClass[ s.id ] != kNoNode )
        {
            continue;
        }
        if( const auto it = ids.classesByName.find( s.scope ); it != ids.classesByName.end() )
        {
            assignOutOfLineOwner( ing, s, it->second, declaresMember, ids );
        }
    }
}

// a class template's SPECIALIZATION has no class symbol (`template <typename T> class TBase<T, true>`), so its members' scope
// `TBase<T, true>` names no class and a walk reaching TBase by name never sees them — llvm's SmallVectorTemplateBase<T, true>
// defines the push_back a pointer element type instantiates. Indexed by the template's name; a primary template's own
// out-of-line members spelled `TBase<T, B>::m` land here too, which is where their bodies are
inline void addSpecializationDefinitions( const IngestResult& ing, ClassIdentity& ids )
{
    std::string key;
    for( const Symbol& s : ing.symbols )
    {
        const std::size_t open = s.scope.find( '<' );
        if( open == std::string::npos || !extent::inSet( extent::kHeadRuleLangs, s.lang ) || extent::inSet( extent::kExtentClassKinds, s.kind ) || !isDefinitionNotDeclaration( s ) )
        {
            continue;
        }
        key.assign( trimWs( std::string_view( s.scope ).substr( 0, open ) ) );
        if( ids.classesByName.find( key ) != ids.classesByName.end() )
        {
            ids.specializationDefs[ key.append( "::" ).append( s.name ) ].push_back( s.id );
        }
    }
}

inline void addNestedByName( ClassIdentity& ids )
{
    for( const auto& [ name, classIds ] : ids.classesByName )
    {
        for( NodeId c : classIds )
        {
            if( ids.enclosingClass[ c ] != kNoNode )
            {
                ids.nestedByName[ name ].push_back( c );
            }
        }
    }
    for( auto& [ name, nestedIds ] : ids.nestedByName )
    {
        std::sort( nestedIds.begin(), nestedIds.end() );   // hash-map iteration filled it: restore id order for determinism
    }
}

// an include written against an include ROOT (`"LinearMath/btVector3.h"`) resolves to no file path-precisely; as a PATH
// SUFFIX it still says which file it names — a preference between namesakes, never a narrow on its own
inline void addIncludeTargets( const IngestResult& ing, ClassIdentity& ids )
{
    ids.includeTargets.resize( ing.includes.size() );
    std::ranges::transform( ing.includes, ids.includeTargets.begin(), []( const Include& inc ) { return ClassIdentity::IncludeTarget{ inc.fileId, inc.target }; } );
    std::ranges::stable_sort( ids.includeTargets, {}, &ClassIdentity::IncludeTarget::fileId );
}

// is `baseName`, written in derived class `derived`'s base clause, a NESTED class by C++ lookup — nested in a class that
// encloses `derived`, or inherited into one? `class Iterator : public MemTableRep::Iterator` inside SkipListRep (which
// derives from MemTableRep) is; `class DBIter : public Iterator` at namespace scope is not. `derived` itself never counts:
// a class cannot be its own base, so a bare self-name must mean some other class.
inline bool isNamesakeBaseEdge( const IngestResult& ing, const ClassIdentity& ids, NodeId derived, std::string_view baseName, const ChaUpNames& chaUp )
{
    const auto nested = ids.nestedByName.find( std::string( baseName ) );
    if( nested == ids.nestedByName.end() )
    {
        return false;
    }
    for( NodeId outer = ids.enclosingClass[ derived ]; outer != kNoNode; outer = ids.enclosingClass[ outer ] )
    {
        const std::string& outerName = ing.symbols[ outer ].name;
        const auto         inScope   = [ & ]( NodeId n )
        {
            const std::string& nOuter = ing.symbols[ ids.enclosingClass[ n ] ].name;
            return n != derived && ( nOuter == outerName || derivesFromName( outerName, nOuter, chaUp ) );
        };
        if( std::ranges::any_of( nested->second, inScope ) )
        {
            return true;
        }
    }
    return false;
}

// the inheritance graph with namesake edges removed: `realDown` by base NAME (the walk to subclasses), `realUp` by derived
// class id (the walk to ancestors)
inline void addRealInheritance( const IngestResult& ing, ClassIdentity& ids, const ChaUpNames& chaUp )
{
    for( const Reference& ir : ing.references )
    {
        if( !ir.isInherit || ir.fromSymbol == kNoNode || ir.calleeName.empty() || !ir.qualifier.empty() )
        {
            continue;
        }
        const Symbol& d = ing.symbols[ ir.fromSymbol ];
        if( !extent::inSet( extent::kHeadRuleLangs, d.lang ) || !extent::inSet( extent::kExtentClassKinds, d.kind ) || isNamesakeBaseEdge( ing, ids, d.id, ir.calleeName, chaUp ) )
        {
            continue;
        }
        rw::SmallVec<NodeId, 4>& down = ids.realDown[ ir.calleeName ];
        if( down.empty() || down.back() != d.id )
        {
            down.push_back( d.id );
        }
        std::vector<std::string_view>& up = ids.realUp[ d.id ];
        if( std::ranges::find( up, std::string_view( ir.calleeName ) ) == up.end() )
        {
            up.push_back( ir.calleeName );
        }
    }
}

// Rule 2's flat table (typed LOCALS) keeps only the final segment; the qualifier its records wrote is kept here, keyed like
// it, so class identity reads `Skip::Iterator it;` the way the lexical table reads a parameter. Two records of one variable
// writing different qualifiers are conflicting: identity then stays out and Rule 2 answers as before.
inline void addFlatQualifiers( const IngestResult& ing, ClassIdentity& ids )
{
    std::string key;
    for( const Binding& b : ing.bindings )
    {
        if( b.kind != LocalBindKind::Type || b.fromSymbol == kNoNode || b.var.empty() || b.typeName.empty() || !extent::inSet( extent::kHeadRuleLangs, ing.symbols[ b.fromSymbol ].lang ) )
        {
            continue;
        }
        buildShadowKey( key, b.fromSymbol, b.var );
        const auto [ it, inserted ] = ids.flatQualifier.try_emplace( key, ClassIdentity::FlatQualifier{ b.importedName, false } );
        if( !inserted && it->second.text != b.importedName )
        {
            it->second.conflicting = true;
        }
    }
}

inline ClassIdentity buildClassIdentity( const IngestResult& ing, const ChaUpNames& chaUp )
{
    PROFILE_SCOPE_DESCRIBE( "buildGraph/2k: Rule-2 class identity" );
    ClassIdentity ids;
    ids.symbols = &ing.symbols;
    ids.files   = &ing.files;
    addClassDefinitions( ing, ids );
    if( ids.classesByName.empty() )
    {
        return ids;   // no C-family class: Rule 2 reads nothing from the index and answers exactly as before
    }
    ids.enclosingClass.assign( ing.symbols.size(), kNoNode );
    ids.namespacesOfFile.assign( ing.files.size(), {} );
    ids.ownerClass.assign( ing.symbols.size(), kNoNode );
    ids.ownerAmbiguous.assign( ing.symbols.size(), std::uint8_t( 0 ) );
    addDeclarationsAndNamespaces( ing, ids );
    for( const FileSymbols& list : cFamilySymbolsBySpan( ing ) )
    {
        sweepFileNesting( ing, list, ids );
    }
    assignOutOfLineOwners( ing, ids );
    addSpecializationDefinitions( ing, ids );
    addNestedByName( ids );
    addIncludeTargets( ing, ids );
    addRealInheritance( ing, ids, chaUp );
    addFlatQualifiers( ing, ids );
    return ids;
}

// the receiver's WRITTEN type as Rule 2 recorded it: the final class-name segment it matches, and the declaration's
// qualifier text ("" when written bare)
struct WrittenType
{
    std::string_view name;
    std::string_view qualifier;
};

// Rule 2 through class identity — the narrowing half, owned by the Narrower and called from rule2RecvVarType. References
// buildGraph's tables plus reused scratch; one instance drives the single-threaded resolve loop.
//   (1) keep the final-segment hits whose owning class the written type NAMES (C++ lookup outward from the caller; a
//       qualifier naming the enclosing class) — every one kept returns `own` itself, byte-identical;
//   (2) with none left and one claimable class, the shallowest REAL ancestor level that defines the callee;
//   (3) with no body along the ancestry but a DECLARATION on it, the callee's definitions in the class's real subclasses:
//       the dispatch split a virtual call through an interface is.
// Steps 2-3 are CLAIMS, marked for claimFor so the ladder keeps them whole. Namesakes are told apart by evidence: a class
// visible from the file (the same file, a path-resolved include, a direct include read as a path suffix), else a shared
// namespace. EXPLAIN OR KEEP: identity replaces `own` only with an answer it can explain; a nested class visible through the
// caller's includes is never dropped (a type ALIAS the index does not see may name it: `using NodeSet =
// MachineGadgetGraph::NodeSet;`, measured on llvm); several claimable namesakes, or two same-named classes defining the
// callee at one ancestor level, leave `own` standing.
struct IdentityNarrower
{
    const HashMap<std::string, rw::SmallVec<NodeId, 2>>& canonByName;
    const std::vector<std::vector<NodeId>>&              fileIncludes;
    const std::vector<std::uint32_t>&                    symFileId;

    mutable std::string                                   keyScope;        // "Class::callee"
    mutable rw::SmallVec<NodeId, 2>                       hits;            // the answer, copied out by the caller at once
    mutable std::vector<NodeId>                           classWalk;       // nameable classes, then a walk frontier
    mutable std::vector<NodeId>                           classNext;
    mutable std::vector<NodeId>                           plausible;       // plausibleClasses' answer
    mutable std::vector<std::uint32_t>                    seenStamp;       // generation-stamped visited set, one u32 per symbol
    mutable std::uint32_t                                 seenGeneration = 0;
    mutable HashMap<std::string, rw::SmallVec<NodeId, 2>> subclassMemo;    // step 3 per (receiver class, callee)
    mutable const Reference*                              claimRef       = nullptr;
    mutable bool                                          lookupLexical  = false;   // classWalk came from an enclosing class or a class qualifier

    IdentityNarrower( const HashMap<std::string, rw::SmallVec<NodeId, 2>>& canon, const std::vector<std::vector<NodeId>>& incl,
                      const std::vector<std::uint32_t>& symFile ) noexcept
        : canonByName( canon ), fileIncludes( incl ), symFileId( symFile ) {}

    bool claimFor( const Reference& r ) const noexcept
    {
        return claimRef == &r;
    }

    bool forgetClaim() const noexcept
    {
        claimRef = nullptr;
        return false;
    }

    const rw::SmallVec<NodeId, 2>* narrow( const Reference& r, WrittenType type, const rw::SmallVec<NodeId, 2>* own, const ClassIdentity& ids,
                                           const ChaUpNames& chaUp ) const
    {
        claimRef = nullptr;
        nameableClasses( type, r, ids, chaUp, /*verifiedNamespace=*/ false );
        if( own != nullptr )
        {
            if( const rw::SmallVec<NodeId, 2>* const kept = keepNameableHits( r, *own, ids ); kept != nullptr )
            {
                return kept;
            }
        }
        return claimFromAncestry( r, type, own, ids, chaUp );
    }

    // step (1): `own` itself when every hit's owner is nameable — or when a nested namesake is in the caller's sight, which
    // a type alias may name — the nameable subset otherwise, nullptr when none is
    const rw::SmallVec<NodeId, 2>* keepNameableHits( const Reference& r, const rw::SmallVec<NodeId, 2>& own, const ClassIdentity& ids ) const
    {
        const std::uint32_t callerFile = symFileId[ r.fromSymbol ];
        if( !lookupLexical && std::ranges::any_of( own, [ & ]( NodeId h ) { return nestedNamesakeInSight( h, callerFile, ids ); } ) )
        {
            return &own;
        }
        hits.clear();
        for( NodeId h : own )
        {
            if( memberNameable( h, ids ) ) { hits.push_back( h ); }
        }
        if( hits.size() == own.size() )
        {
            return &own;
        }
        return hits.empty() ? nullptr : &hits;
    }

    // steps (2)-(3), from the one class a claim can stand on; `own` when there is none or the ancestry explains nothing
    const rw::SmallVec<NodeId, 2>* claimFromAncestry( const Reference& r, WrittenType type, const rw::SmallVec<NodeId, 2>* own,
                                                      const ClassIdentity& ids, const ChaUpNames& chaUp ) const
    {
        if( !type.qualifier.empty() )
        {
            nameableClasses( type, r, ids, chaUp, /*verifiedNamespace=*/ true );   // a claim needs evidence
        }
        const NodeId receiverClass = claimableClass( type.name, r, ids );
        if( receiverClass == kNoNode )
        {
            return own;
        }
        bool declaredAlong = false;
        bool ambiguous     = false;
        if( inheritedDefinitions( r, receiverClass, ids, declaredAlong, ambiguous )
         || ( !ambiguous && declaredAlong && subclassDefinitions( r, receiverClass, ids ) ) )
        {
            claimRef = &r;
            return &hits;
        }
        return own;
    }

    // the one class a claim stands on: the single plausible nameable class, unless another class of that name is in the
    // caller's sight and this one shows no sign of being meant; kNoNode otherwise
    NodeId claimableClass( std::string_view typeName, const Reference& r, const ClassIdentity& ids ) const
    {
        const std::uint32_t callerFile = symFileId[ r.fromSymbol ];
        plausibleClasses( classWalk, callerFile, ids );
        const auto sameName = ids.classesByName.find( std::string( typeName ) );
        if( plausible.size() != 1 || sameName == ids.classesByName.end() )
        {
            return kNoNode;
        }
        const NodeId claimed         = plausible.front();
        const bool   namesakeInSight = std::ranges::any_of( sameName->second, [ & ]( NodeId c )
        {
            return c != claimed && fileVisibleFrom( callerFile, fileOf( c, ids ), ids );
        } );
        return ( lookupLexical || !namesakeInSight || classEvidenced( claimed, callerFile, ids ) ) ? claimed : kNoNode;
    }

    static std::uint32_t fileOf( NodeId symbol, const ClassIdentity& ids ) noexcept
    {
        return ( *ids.symbols )[ symbol ].fileId;
    }

    static std::string_view outerNameOf( NodeId cls, const ClassIdentity& ids ) noexcept
    {
        const NodeId outer = ids.enclosingClass[ cls ];
        return ( outer == kNoNode ) ? std::string_view{} : std::string_view( ( *ids.symbols )[ outer ].name );
    }

    // the caller's own class: itself when it is a class, its owner otherwise (kNoNode when unknown or ambiguous)
    static NodeId callerClassOf( NodeId from, const ClassIdentity& ids ) noexcept
    {
        if( extent::inSet( extent::kExtentClassKinds, ( *ids.symbols )[ from ].kind ) )
        {
            return from;
        }
        return ( ids.ownerAmbiguous[ from ] != 0 ) ? kNoNode : ids.ownerClass[ from ];
    }

    static bool nestedInAncestorOf( NodeId cls, std::string_view className, const ClassIdentity& ids, const ChaUpNames& chaUp )
    {
        const std::string_view outer = outerNameOf( cls, ids );
        return !outer.empty() && derivesFromName( className, outer, chaUp );
    }

    bool collectIf( const rw::SmallVec<NodeId, 2>& named, const auto& pick ) const
    {
        for( NodeId c : named )
        {
            if( pick( c ) ) { classWalk.push_back( c ); }
        }
        return !classWalk.empty();
    }

    // the classes the written type NAMES at this call, into classWalk in id order: through a qualifier; bare, outward from the
    // caller's class — a class nested directly in an enclosing class wins, then one nested in that class's ancestors — then
    // from an unknown caller's written scope; past all of those the namespace-level classes of that name. `verifiedNamespace`
    // separates an EXCLUSION from a CLAIM: to drop a hit, a namespace qualifier names every namespace-level class of its name
    // (none is provably excluded); to claim, only those whose file shows it defines something in that namespace.
    void nameableClasses( WrittenType type, const Reference& r, const ClassIdentity& ids, const ChaUpNames& chaUp, bool verifiedNamespace ) const
    {
        classWalk.clear();
        lookupLexical    = false;
        const auto named = ids.classesByName.find( std::string( type.name ) );
        if( named == ids.classesByName.end() )
        {
            return;
        }
        if( !type.qualifier.empty() )
        {
            nameableThroughQualifier( named->second, type.qualifier, ids, verifiedNamespace );
            return;
        }
        if( nameableFromCallerClass( named->second, r, ids, chaUp ) )
        {
            lookupLexical = true;
            return;
        }
        if( !nameableFromCallerScope( named->second, type.name, r, ids, chaUp ) )
        {
            collectIf( named->second, [ & ]( NodeId c ) { return ids.enclosingClass[ c ] == kNoNode; } );
        }
    }

    void nameableThroughQualifier( const rw::SmallVec<NodeId, 2>& named, std::string_view qualifier, const ClassIdentity& ids, bool verifiedNamespace ) const
    {
        const std::string_view q = qualifierOuterName( qualifier );
        if( ids.classesByName.find( std::string( q ) ) != ids.classesByName.end() )
        {
            lookupLexical = collectIf( named, [ & ]( NodeId c ) { return outerNameOf( c, ids ) == q; } );
            return;
        }
        // `ns::T` names a namespace-level T; claimed only from a file showing it defines things in `ns` — an
        // `ankerl::unordered_dense::map` must not become amc's `map` (measured on a private corpus)
        std::string nsKey;
        collectIf( named, [ & ]( NodeId c )
        {
            buildShadowKey( nsKey, fileOf( c, ids ), q );
            return ids.enclosingClass[ c ] == kNoNode && ( !verifiedNamespace || ids.fileNamespaces.find( nsKey ) != ids.fileNamespaces.end() );
        } );
    }

    bool nameableFromCallerClass( const rw::SmallVec<NodeId, 2>& named, const Reference& r, const ClassIdentity& ids, const ChaUpNames& chaUp ) const
    {
        for( NodeId sc = callerClassOf( r.fromSymbol, ids ); sc != kNoNode; sc = ids.enclosingClass[ sc ] )
        {
            const std::string& scName = ( *ids.symbols )[ sc ].name;
            if( collectIf( named, [ & ]( NodeId c ) { return ids.enclosingClass[ c ] == sc; } )
             || collectIf( named, [ & ]( NodeId c ) { return nestedInAncestorOf( c, scName, ids, chaUp ); } ) )
            {
                return true;
            }
        }
        return false;
    }

    // an out-of-line caller of unknown class: its written scope's name is the only evidence of where it sits
    bool nameableFromCallerScope( const rw::SmallVec<NodeId, 2>& named, std::string_view typeName, const Reference& r, const ClassIdentity& ids,
                                  const ChaUpNames& chaUp ) const
    {
        const std::string& scope = ( *ids.symbols )[ r.fromSymbol ].scope;
        if( callerClassOf( r.fromSymbol, ids ) != kNoNode || scope.empty() || ids.classesByName.find( scope ) == ids.classesByName.end() )
        {
            return false;
        }
        if( scope == typeName )
        {
            return collectIf( named, []( NodeId ) { return true; } );   // a member of a class of that very name: any of them, as before
        }
        return collectIf( named, [ & ]( NodeId c ) { return outerNameOf( c, ids ) == scope; } )
            || collectIf( named, [ & ]( NodeId c ) { return nestedInAncestorOf( c, scope, ids, chaUp ); } );
    }

    // a hit owned by a NESTED class outside the nameable set whose file is visible from the caller
    bool nestedNamesakeInSight( NodeId hit, std::uint32_t callerFile, const ClassIdentity& ids ) const
    {
        const NodeId owner = ids.ownerClass[ hit ];
        return ids.ownerAmbiguous[ hit ] == 0 && owner != kNoNode && ids.enclosingClass[ owner ] != kNoNode
            && !std::binary_search( classWalk.begin(), classWalk.end(), owner ) && fileVisibleFrom( callerFile, fileOf( owner, ids ), ids );
    }

    // a hit's owning class among the nameable ones? An unknown owner keeps the hit; an ambiguous out-of-line owner is
    // nameable when any same-file class of its scope's name is
    bool memberNameable( NodeId member, const ClassIdentity& ids ) const
    {
        const NodeId owner = ids.ownerClass[ member ];
        if( owner == kNoNode )
        {
            return true;
        }
        if( ids.ownerAmbiguous[ member ] == 0 )
        {
            return std::binary_search( classWalk.begin(), classWalk.end(), owner );
        }
        const Symbol& m      = ( *ids.symbols )[ member ];
        const auto    scoped = ids.classesByName.find( m.scope );
        return scoped != ids.classesByName.end() && std::ranges::any_of( scoped->second, [ & ]( NodeId c )
        {
            return fileOf( c, ids ) == m.fileId && std::binary_search( classWalk.begin(), classWalk.end(), c );
        } );
    }

    // is `defFile` visible from `fromFile` — the same file, one it path-resolvably includes, or one a DIRECT include of it
    // names as a path suffix (an include-root spelling, `"clang/Interpreter/Value.h"`; a suffix, not a basename: three
    // `Value.h` headers hold three `Value` classes in llvm)?
    bool fileVisibleFrom( std::uint32_t fromFile, std::uint32_t defFile, const ClassIdentity& ids ) const
    {
        if( fromFile == defFile || ( fromFile < fileIncludes.size() && std::binary_search( fileIncludes[ fromFile ].begin(), fileIncludes[ fromFile ].end(), defFile ) ) )
        {
            return true;
        }
        if( ids.files == nullptr || defFile >= ids.files->size() )
        {
            return false;
        }
        const std::string_view path             = ( *ids.files )[ defFile ];
        const auto [ firstInclude, endInclude ] = std::ranges::equal_range( ids.includeTargets, fromFile, {}, &ClassIdentity::IncludeTarget::fileId );
        return std::any_of( firstInclude, endInclude, [ & ]( const ClassIdentity::IncludeTarget& include )
        {
            std::string_view target = include.target;
            while( target.starts_with( "./" ) )
            {
                target.remove_prefix( 2 );
            }
            return !target.empty() && path.ends_with( target ) && ( path.size() == target.size() || path[ path.size() - target.size() - 1 ] == '/' );
        } );
    }

    static bool filesShareNamespace( std::uint32_t a, std::uint32_t b, const ClassIdentity& ids ) noexcept
    {
        if( a >= ids.namespacesOfFile.size() || b >= ids.namespacesOfFile.size() )
        {
            return false;
        }
        return std::ranges::any_of( ids.namespacesOfFile[ a ], [ & ]( std::string_view x )
        {
            return std::ranges::find( ids.namespacesOfFile[ b ], x ) != ids.namespacesOfFile[ b ].end();
        } );
    }

    // does a use in file `fromFile` have EVIDENCE it means class `cls` — visible from it, or a namespace in common?
    bool classEvidenced( NodeId cls, std::uint32_t fromFile, const ClassIdentity& ids ) const
    {
        return fileVisibleFrom( fromFile, fileOf( cls, ids ), ids ) || filesShareNamespace( fromFile, fileOf( cls, ids ), ids );
    }

    // among same-named classes, the ones a use in file `fromFile` most plausibly means: those visible from it, else those
    // sharing a namespace with it, else all — a preference that orders namesakes, never one that removes the last candidate
    void plausibleClasses( std::span<const NodeId> named, std::uint32_t fromFile, const ClassIdentity& ids ) const
    {
        plausible.clear();
        for( NodeId c : named )
        {
            if( named.size() == 1 || fileVisibleFrom( fromFile, fileOf( c, ids ), ids ) ) { plausible.push_back( c ); }
        }
        for( NodeId c : ( plausible.empty() ? named : std::span<const NodeId>{} ) )
        {
            if( filesShareNamespace( fromFile, fileOf( c, ids ), ids ) ) { plausible.push_back( c ); }
        }
        if( plausible.empty() )
        {
            plausible.assign( named.begin(), named.end() );
        }
    }

    // the definitions under keyScope ("Class::callee") owned by class `cls` — or, when their owner is ambiguous or unknown,
    // plausibly it — appended to hits
    void appendOwnedDefinitions( NodeId cls, const ClassIdentity& ids ) const
    {
        const auto it    = canonByName.find( keyScope );
        const auto named = ids.classesByName.find( ( *ids.symbols )[ cls ].name );
        if( it == canonByName.end() )
        {
            return;
        }
        for( NodeId d : it->second )
        {
            if( ownedBy( d, cls, named == ids.classesByName.end() ? nullptr : &named->second, ids ) && markSeen( d ) )
            {
                hits.push_back( d );   // a definition plausible for two same-named classes of one walk is appended once
            }
        }
    }

    bool ownedBy( NodeId def, NodeId cls, const rw::SmallVec<NodeId, 2>* sameNamed, const ClassIdentity& ids ) const
    {
        const NodeId owner = ids.ownerClass[ def ];
        if( owner == cls )
        {
            return true;
        }
        if( ids.ownerAmbiguous[ def ] != 0 )
        {
            return fileOf( def, ids ) == fileOf( cls, ids );   // one of several same-file classes of the name
        }
        if( owner != kNoNode || sameNamed == nullptr )
        {
            return false;
        }
        plausibleClasses( std::span<const NodeId>( sameNamed->data(), sameNamed->size() ), fileOf( def, ids ), ids );   // defined out of line in another file
        return std::ranges::find( plausible, cls ) != plausible.end();
    }

    // a fresh visited generation over the symbol ids (the stamp vector is sized once, never cleared)
    void nextSeenGeneration( const ClassIdentity& ids ) const
    {
        if( seenStamp.size() != ids.symbols->size() || seenGeneration == 0xFFFFFFFFu )
        {
            seenStamp.assign( ids.symbols->size(), 0u );
            seenGeneration = 0;
        }
        ++seenGeneration;
    }

    bool markSeen( NodeId id ) const noexcept
    {
        const bool fresh = seenStamp[ id ] != seenGeneration;
        seenStamp[ id ] = seenGeneration;
        return fresh;
    }

    // two KNOWN, distinct owning classes that share a name among the definitions — a union of namesakes, not one type's answer
    // (an unknown owner was admitted only as plausibly the walked class, so it never counts against it)
    static bool definedBySameNamedClasses( const rw::SmallVec<NodeId, 2>& defs, const ClassIdentity& ids ) noexcept
    {
        for( std::size_t a = 0; a < defs.size(); ++a )
        {
            const NodeId oa         = ids.ownerClass[ defs[ a ] ];
            const auto   namesakeOf = [ & ]( NodeId d )
            {
                const NodeId ob = ids.ownerClass[ d ];
                return ob != kNoNode && ob != oa && ( *ids.symbols )[ oa ].name == ( *ids.symbols )[ ob ].name;
            };
            if( oa != kNoNode && std::any_of( defs.begin() + a + 1, defs.end(), namesakeOf ) )
            {
                return true;
            }
        }
        return false;
    }

    // step (2): from the receiver class up the REAL inheritance level by level; the shallowest level whose classes define the
    // callee answers into hits (several defining classes at one level: their union, an honest split — unless two of them are
    // namesakes, then `ambiguous`). `declaredAlong` reports a bodiless declaration of the callee on any class visited.
    bool inheritedDefinitions( const Reference& r, NodeId receiverClass, const ClassIdentity& ids, bool& declaredAlong, bool& ambiguous ) const
    {
        nextSeenGeneration( ids );
        markSeen( receiverClass );
        classWalk.assign( 1, receiverClass );
        for( int depth = 0; depth < 16 && !classWalk.empty(); ++depth )
        {
            hits.clear();
            classNext.clear();
            for( NodeId c : classWalk )
            {
                declaredAlong = visitAncestor( r, c, depth > 0, ids ) || declaredAlong;
            }
            if( !hits.empty() )
            {
                std::sort( hits.begin(), hits.end() );   // each definition appended once (markSeen): the id order own's hits have
                ambiguous = definedBySameNamedClasses( hits, ids );
                return !ambiguous;
            }
            classWalk.swap( classNext );
        }
        return false;
    }

    // the definitions under keyScope that the template's specializations hold (ClassIdentity::specializationDefs), when the
    // specialization's file sees the class's: the family split one instantiation picks from
    void appendSpecializationDefinitions( NodeId cls, const ClassIdentity& ids ) const
    {
        const auto it = ids.specializationDefs.find( keyScope );
        if( it == ids.specializationDefs.end() )
        {
            return;
        }
        const std::uint32_t classFile = fileOf( cls, ids );
        for( NodeId d : it->second )
        {
            const std::uint32_t defFile = fileOf( d, ids );
            if( ( defFile == classFile || fileVisibleFrom( defFile, classFile, ids ) ) && markSeen( d ) )
            {
                hits.push_back( d );
            }
        }
    }

    // one class of the ancestor walk: whether it DECLARES the callee; its definitions appended (not at the receiver's own
    // level, which step 1 judged); its plausible direct bases queued
    bool visitAncestor( const Reference& r, NodeId c, bool appendDefinitions, const ClassIdentity& ids ) const
    {
        keyScope.assign( ( *ids.symbols )[ c ].name ).append( "::" ).append( r.calleeName );
        const bool declares = ids.declared.find( keyScope ) != ids.declared.end();
        if( appendDefinitions )
        {
            appendOwnedDefinitions( c, ids );
            appendSpecializationDefinitions( c, ids );
        }
        const auto up = ids.realUp.find( c );
        for( std::string_view base : ( up == ids.realUp.end() ) ? std::span<const std::string_view>{} : std::span<const std::string_view>( up->second ) )
        {
            const auto bases = ids.classesByName.find( std::string( base ) );
            if( bases == ids.classesByName.end() )
            {
                continue;
            }
            plausibleClasses( std::span<const NodeId>( bases->second.data(), bases->second.size() ), fileOf( c, ids ), ids );
            for( NodeId b : plausible )
            {
                if( markSeen( b ) ) { classNext.push_back( b ); }
            }
        }
        return declares;
    }

    // step (3): the callee's definitions in the REAL subclasses of the receiver class, transitively — every runtime target of a
    // virtual call on a type whose ancestry declares the callee but defines it nowhere. Memoised per (class, callee).
    bool subclassDefinitions( const Reference& r, NodeId receiverClass, const ClassIdentity& ids ) const
    {
        std::string memoKey = std::to_string( receiverClass ).append( "#" ).append( r.calleeName );
        if( const auto hit = subclassMemo.find( memoKey ); hit != subclassMemo.end() )
        {
            hits = hit->second;
            return !hits.empty();
        }
        hits.clear();
        nextSeenGeneration( ids );
        classWalk.assign( 1, receiverClass );
        for( int depth = 0; depth < 32 && !classWalk.empty(); ++depth )
        {
            classNext.clear();
            for( NodeId c : classWalk )
            {
                visitSubclassesOf( r, c, ids );
            }
            classWalk.swap( classNext );
        }
        std::sort( hits.begin(), hits.end() );   // each definition appended once (markSeen)
        subclassMemo.emplace( std::move( memoKey ), hits );
        return !hits.empty();
    }

    // the real subclasses of `c` whose base clause, read from their own file, plausibly means `c`: their definitions of the
    // callee appended, each queued once
    void visitSubclassesOf( const Reference& r, NodeId c, const ClassIdentity& ids ) const
    {
        const std::string& cname = ( *ids.symbols )[ c ].name;
        const auto         down  = ids.realDown.find( cname );
        const auto         named = ids.classesByName.find( cname );
        if( down == ids.realDown.end() || named == ids.classesByName.end() )
        {
            return;
        }
        for( NodeId d : down->second )
        {
            plausibleClasses( std::span<const NodeId>( named->second.data(), named->second.size() ), fileOf( d, ids ), ids );
            if( std::ranges::find( plausible, c ) == plausible.end() || !markSeen( d ) )
            {
                continue;   // d derives from another class of that name, or was reached already
            }
            keyScope.assign( ( *ids.symbols )[ d ].name ).append( "::" ).append( r.calleeName );
            appendOwnedDefinitions( d, ids );
            classNext.push_back( d );
        }
    }
};

// One-hop receiver narrowing over the canonical scope::name → definition-ids map (built once by buildGraph).
// Holds only const references to maps buildGraph owns — no state, no allocation, no copy of the symbol table.
struct Narrower
{
    const HashMap<std::string, rw::SmallVec<NodeId, 2>>& canonByName;   // "Scope::name" → def ids (defs only)
    // P2-D Rule 2 binding table: "<fromSymbolId>#<var>" → the variable's resolved TYPE name (a class/struct in
    // canonByName), or the empty string as a TOMBSTONE marking an AMBIGUOUS var (bound to ≥2 distinct types in
    // one scope) — looked up but never narrowed. buildGraph builds it from IngestResult::bindings. Empty when
    // there are no bindings, so Rule 2 simply never fires (degrades to the unchanged ladder).
    const HashMap<std::string, FlatRecvType>&            varType;
    // Rule 2's LEXICAL table for names with a ParamType declaration (see ScopedRecvDecl above). A name found here is
    // answered here ONLY — varType is not consulted.
    const ScopedRecvDecls&                               scopedDecls;
    // P2-D Rule 3 include table: caller fileId → the sorted, deduped set of fileIds it #includes / imports
    // (resolved file→file by basename, exactly like graph.h::resolveIncludeAdj; the caller's own file is NEVER
    // in its own set). buildGraph builds it once from IngestResult::includes. Empty when the repo has no
    // include/import edges, so Rule 3 simply never fires (degrades to the unchanged ladder). A `std::span`
    // seam: buildGraph owns the storage (a `std::vector<std::vector<NodeId>>`), the Narrower only reads it.
    const std::vector<std::vector<NodeId>>&              fileIncludes;
    // per-symbol fileId (view into ing.symbols' fileIds), so Rule 3 can group candidate defs by their file
    // without a reference to the whole IngestResult. buildGraph owns the backing vector.
    const std::vector<std::uint32_t>&                    symFileId;
    // "Class::m" → the classes a class-scope `using Base::m;` re-exports `m` from (buildUsingReexports above). Read by
    // ownMethodSet only; empty on a corpus without one, where every probe is the plain canonByName hit it always was.
    const HashMap<std::string, std::vector<std::string>>& usingReexports;

    // reused key-assembly buffers — one `Narrower` drives the whole (single-threaded) resolve loop, so the
    // `scope::name` / `<fromSymbol>#var` lookup keys are built IN PLACE (clear()+append(), capacity kept) into
    // these instead of a fresh std::string per reference. The BYTES are identical to the old `+` concats, so the
    // map lookups — and the resolved graph — are byte-for-byte unchanged; only the per-ref malloc churn is gone.
    mutable std::string keyScope;   // "Scope::name" for canonByName lookups (Rule 1 + Rule 2's type::method)
    mutable std::string keyBind;    // "<fromSymbolId>#var" for the varType binding lookup (Rule 2 + L3)
    mutable std::vector<std::string_view> fieldWalk;   // Rule 2b reused base-walk frontier (views into chaUp's stored strings)
    mutable rw::SmallVec<NodeId, 2>       walkUnion;   // Phase 5: the union of a multi-base hit level (super() only) — an honest split
    IdentityNarrower identity;   // Rule 2 through class identity: its scratch, memo and claim flag live there
    mutable rw::SmallVec<NodeId, 2>       reexportUnion;   // what a type's `using Base::m;` declarations reach when it defines no `m` itself

    explicit Narrower( const HashMap<std::string, rw::SmallVec<NodeId, 2>>& canon,
                       const HashMap<std::string, FlatRecvType>&            vt,
                       const ScopedRecvDecls&                               scoped,
                       const std::vector<std::vector<NodeId>>&              incl,
                       const std::vector<std::uint32_t>&                    symFile,
                       const HashMap<std::string, std::vector<std::string>>& reexports ) noexcept
        : canonByName( canon ), varType( vt ), scopedDecls( scoped ), fileIncludes( incl ), symFileId( symFile ), usingReexports( reexports ),
          identity( canon, incl, symFile ) {}

    // append base-10 `n` to `dst` without an intermediate std::to_string allocation (matches to_string bytes).
    static void appendUint( std::string& dst, std::uint32_t n )
    {
        char  buf[10];
        char* p = buf + sizeof( buf );
        do { *--p = char( '0' + n % 10 ); n /= 10; } while( n != 0 );
        dst.append( p, std::size_t( buf + sizeof( buf ) - p ) );
    }

    // Rule 1 — class-membership narrow. Returns the enclosing scope's same-named definition(s) when the call
    // is a *member-scope* call inside a known class/namespace; nullptr ⇒ the caller falls through to the
    // unchanged §2a ladder. Deterministic (canonical-map insertion order = symbol-id order).
    //
    // When does a call resolve to the caller's enclosing scope? Per real name-lookup semantics:
    //   * receiver is `this` (C++) / `self` (Python) — always a member call (both languages).
    //   * C++/ObjC ALSO: a BARE unqualified call `m()` inside a member function (recv==None, no `A::`
    //     qualifier) — C++ unqualified lookup searches the CLASS scope (and enclosing namespace) before
    //     the global namespace, so `m()` inside `A::run()` binds to `A::m` when `A` defines it. This is the
    //     common idiom (explicit `this->` is rare), and where the bulk of the ambiguity actually lives.
    //   * Python does NOT do this — a bare `m()` never reaches a method (you must write `self.m()`), so a
    //     bare Python call is left to §2a. Restricting the bare case to C-family is the conservative cut.
    // In every case the narrow only fires when `callerScope::calleeName` is a real DEFINITION in canonByName,
    // so it can never invent a target the bare ladder couldn't reach — it only PICKS the right one earlier.
    const rw::SmallVec<NodeId, 2>* rule1ClassMember( const Reference& r, const std::string& callerScope ) const
    {
        if( callerScope.empty() )
        {
            return nullptr; // caller's enclosing class/namespace unknown → no narrow
        }
        if( !r.qualifier.empty() )
        {
            return nullptr; // an explicit `A::m()` is handled by E#4 canonical resolve, not here
        }

        const bool isThisSelf = ( r.recv == RecvKind::ThisObj );
        // Ruby rides the bare arm too: a receiver-less `m(args)` inside a method is an implicit-self send —
        // the language has no other reading of it (a bare `m` with neither receiver nor parens is a local
        // read and is never captured; queries/ruby/tags.scm). test/rubyscopecheck.sh, Rule 1 arms.
        const bool isCish      = ( r.lang == Lang::Cpp || r.lang == Lang::ObjC || r.lang == Lang::Ruby );
        const bool bareCish    = isCish && ( r.recv == RecvKind::None );   // C++ unqualified member-or-namespace lookup; Ruby implicit self
        if( !isThisSelf && !bareCish )
        {
            return nullptr; // `x.m()` (NamedVar) is Rule 2 territory (deferred) → §2a
        }

        // resolve against the enclosing scope. canonByName holds DEFS only, so a hit is a real same-scope
        // definition — resolve straight to it, skipping the cross-class/cross-file ambiguity. Key built in
        // the reused buffer (identical bytes to `callerScope + "::" + r.calleeName`).
        keyScope.clear();
        keyScope.append( callerScope ).append( "::" ).append( r.calleeName );
        const auto it = canonByName.find( keyScope );
        if( it == canonByName.end() || it->second.size() == 0 )
        {
            return nullptr;
        }
        return &it->second;   // 1+ defs in the enclosing scope (overloads stay split 1/k, but only within the scope)
    }

    // Rule 2 — receiver-VARIABLE type narrow (the deferred one-hop). For a member call `x.m()` / `x->m()`
    // (recv==NamedVar, recvVar="x") inside def `from`: look up the in-scope binding `x : Foo` and resolve `m`
    // against `Foo`'s own method set (canonByName["Foo::m"]). nullptr ⇒ fall through to the unchanged §2a ladder.
    //
    // Airtight "no wrong narrow" (the contract): it narrows ONLY when ALL hold — (1) the call has a named
    // receiver variable; (2) that var has EXACTLY ONE type binding in this scope (an ambiguous var is tombstoned
    // by buildGraph → empty type → no narrow) — or, for a name with a PARAMETER-typed declaration, the declaration
    // in scope AT THE SITE has a written type (recvVarTypeName); (3) the bound type defines `m` (canonByName, DEFS only). So the
    // returned ids are always real `Foo::m` definitions the bare ladder could also reach — Rule 2 just picks the
    // type-correct one earlier. Any uncertainty (no binding, conflicting bindings, type has no such method) →
    // honest ambiguity via §2a, never a guess. Deterministic: canonByName insertion order = symbol-id order.
    const rw::SmallVec<NodeId, 2>* rule2RecvVarType( const Reference& r, const ClassIdentity& ids, const ChaUpNames& chaUp ) const
    {
        identity.forgetClaim();
        if( r.recv != RecvKind::NamedVar || r.recvVar.empty() )
        {
            return nullptr; // not a named-receiver call
        }
        if( !r.qualifier.empty() )
        {
            return nullptr; // explicit `A::m()` → E#4 canonical, not here
        }
        if( r.fromSymbol == kNoNode )
        {
            return nullptr; // file-scope call: no per-def binding scope
        }

        // the var's type at THIS site. Empty = unbound, tombstoned, or an untyped declaration in scope → no narrow.
        const RecvVarType bound = recvVarType( r );
        if( bound.name.empty() )
        {
            return nullptr;
        }
        const auto [ qualifierKnown, qualifier ] = writtenQualifier( bound, ids );

        // resolve `m` against the bound type's own methods (defs only). Reused buffer, identical bytes to
        // `bound.name + "::" + r.calleeName`.
        keyScope.clear();
        keyScope.append( bound.name ).append( "::" ).append( r.calleeName );
        const auto it = canonByName.find( keyScope );
        const rw::SmallVec<NodeId, 2>* const own = ( it == canonByName.end() || it->second.size() == 0 ) ? nullptr : &it->second;
        if( ids.classesByName.empty() || !extent::inSet( extent::kHeadRuleLangs, r.lang ) || !qualifierKnown )
        {
            return own;   // no class identity to consult: the final-segment answer — overloads split 1/k within the type
        }
        return identity.narrow( r, WrittenType{ bound.name, qualifier }, own, ids, chaUp );
    }

    // true iff THIS reference's Rule 2 answer was a class-identity CLAIM (an inherited body or an interface dispatch split)
    // that survived the caller's language/root filter — a type fact, which the ladder keeps whole instead of trimming it by
    // file locality. forgetClaim: the caller's filter emptied Rule 2's answer; false, to close `narrowed = narrowTo( … ) || …`.
    bool identityClaimFor( const Reference& r ) const noexcept
    {
        return identity.claimFor( r );
    }

    bool forgetClaim() const noexcept
    {
        return identity.forgetClaim();
    }

    // Rule 2b's member evidence, bundled so its signatures read as its conditions: `types` = "<Class>#<field>" → the declared type
    // (graph.h buildFieldNarrowTables, from the HAS-A compose captures), `declared` = every C/C++ member "<Owner>#<field>"
    // (memberFieldNames), typed or not, and `chaUp` = class name → its direct base names, the graph both walks read. No copy.
    struct FieldRecvTables
    {
        const HashMap<std::string, FlatRecvType>&             types;
        const HashMap<std::string, char>&                     declared;
        const HashMap<std::string, std::vector<std::string>>& chaUp;
    };

    // Rule 2b — receiver-FIELD type narrow (W1-P1-12). For a member call `f.m()` / `f->m()` (recv==NamedVar,
    // recvVar="f") inside a METHOD whose enclosing class declares a FIELD named `f` with a known type
    // (the S5-E HAS-A capture): resolve `m` against that declared type's own method set, walking DIRECT-base
    // names (chaUp) level by level when the type itself does not define `m` — the bare-field member call is
    // the idiomatic C++ shape Rule 2's local-binding table can never see. nullptr ⇒ the unchanged §2a ladder.
    //
    // Airtight "no wrong narrow" (Rule 2's contract, extended): it narrows ONLY when ALL hold —
    //   (1) named-receiver call, no explicit qualifier, from a known def in a known class scope, C-family
    //       (the field table is built from C++ field captures; Python/TS field receivers are chained
    //       accesses ingest classifies RecvKind::None, so they never even reach this rule — disclosed limit);
    //   (2) NO local DECLARATION exists for (fromSymbol, recvVar) — a parameter or declared local SHADOWS a
    //       same-named field in real C++ lookup, so declaration evidence vetoes the narrow; an assignment
    //       names the field itself and does not (`localNames`' kLocalNameDeclared bit, localNameEvidence);
    //   (3) the enclosing class declares that field with EXACTLY ONE type corpus-wide — or, when the class declares
    //       no member of that name, the ONE base declaring it at the shallowest level of a bounded breadth-first
    //       walk over chaUp does (fieldEntryAt, arm w). Same-NAMED classes
    //       collapse to one scope string here (namespaces are dropped from Symbol::scope), so a same-named
    //       field bound to two DIFFERENT types is TOMBSTONED at build ("" value) and never narrows;
    //   (4) the field's type — or exactly ONE base name at the shallowest hit level of a bounded, breadth-
    //       first walk over chaUp — actually DEFINES `m` (canonByName, DEFS only). Two distinct bases
    //       defining `m` at the same level is an honest ambiguity → refuse. So the returned ids are always
    //       real `Type::m` definitions the bare ladder could also reach — Rule 2b just picks the
    //       type-correct one earlier; any uncertainty degrades to §2a and the honest amb= split.
    // Deterministic: chaUp lists are sorted+deduped, the frontier is expanded in stored order with a fixed
    // visit cap, and canonByName insertion order = symbol-id order.
    const rw::SmallVec<NodeId, 2>* rule2bFieldRecvType( const Reference& r, const std::string& callerScope, const FieldRecvTables& fields,
                                                        const HashMap<std::string, char>& localNames ) const
    {
        if( r.recv != RecvKind::NamedVar || r.recvVar.empty() || !r.qualifier.empty() || r.fromSymbol == kNoNode )
        {
            return nullptr; // not a bare named-receiver call from a known def
        }
        if( r.lang != Lang::Cpp && r.lang != Lang::ObjC )
        {
            return nullptr; // (1) the field-type table is C++-evidence only — other languages stay on their unchanged ladder
        }
        if( callerScope.empty() || fields.types.empty() )
        {
            return nullptr; // free function (no enclosing class), or a field-capture-free corpus
        }

        // (2) local-shadow veto: a DECLARATION of (fromSymbol, recvVar) makes the name a LOCAL; assigning it does not.
        keyBind.clear();
        appendUint( keyBind, r.fromSymbol );
        keyBind.push_back( '#' );
        keyBind.append( r.recvVar );
        if( const auto lit = localNames.find( keyBind ); lit != localNames.end() && ( lit->second & kLocalNameDeclared ) != 0 )
        {
            return nullptr;
        }

        // (3) the field entry of the enclosing class or the one base declaring it (fieldEntryAt), "" = tombstone.
        const FlatRecvType* field = fieldEntryAt( r, callerScope, fields );
        if( field == nullptr || field->type.empty() )
        {
            return nullptr;
        }
        if( field->arrowOnly && !r.viaArrow )
        {
            return nullptr; // a std smart pointer's pointee: `.` names the smart pointer's own member (arm p)
        }

        // (4) the declared type's own method set, then its bases — shared with Rule 2c below.
        return methodOnTypeOrBases( field->type, r, fields.chaUp );
    }

    // The type-side probe Rules 2b and 2c share: `type::callee` in the type's OWN method set first (ownMethodSet: its
    // definitions plus what its using-declarations re-export), then a bounded breadth-first DIRECT-base walk (frontier
    // levels over chaUp). The SHALLOWEST level with a hit decides: exactly one hitting base name → those
    // definitions; two or more at one level → nullptr (honest ambiguity, the caller's ladder stays unchanged).
    // Deterministic: chaUp lists are sorted+deduped, the frontier is expanded in stored order with a fixed visit cap,
    // and canonByName insertion order = symbol-id order.
    // One level of the base walk: probe `name::callee` for every frontier name from `lvlEnd` on. Returns the
    // single hitting definition list and whether a SECOND base hit at this level (`multi`); every hit's
    // definitions are also appended to `walkUnion`, which the caller returns when it asked for the union.
    std::pair<const rw::SmallVec<NodeId, 2>*, bool> probeWalkLevel( std::size_t lvlEnd, std::string_view callee ) const
    {
        const rw::SmallVec<NodeId, 2>* found = nullptr;
        bool                           multi = false;
        walkUnion.clear();
        for( std::size_t i = lvlEnd; i < fieldWalk.size(); ++i )
        {
            keyScope.clear();
            keyScope.append( fieldWalk[ i ] ).append( "::" ).append( callee );
            const auto it = canonByName.find( keyScope );
            if( it == canonByName.end() || it->second.size() == 0 )
            {
                continue;
            }
            multi = multi || ( found != nullptr );
            found = &it->second;
            for( NodeId c : it->second )
            {
                walkUnion.push_back( c );
            }
        }
        return { found, multi };
    }

    // TRUE when `base` is in `typeName`'s base closure over chaUp: a direct base, a base's base, and so on. The walk is
    // expandWalkLevel's, so a closure the name cap truncates answers false — the caller treats that as "not a base".
    bool inBaseClosure( std::string_view typeName, std::string_view base, const HashMap<std::string, std::vector<std::string>>& chaUp ) const
    {
        fieldWalk.clear();
        fieldWalk.push_back( typeName );
        std::size_t lvlBegin = 0;
        while( lvlBegin < fieldWalk.size() )
        {
            const std::size_t lvlEnd = fieldWalk.size();
            expandWalkLevel( lvlBegin, lvlEnd, chaUp );
            if( std::find( fieldWalk.begin() + std::ptrdiff_t( lvlEnd ), fieldWalk.end(), base ) != fieldWalk.end() )
            {
                return true;
            }
            lvlBegin = lvlEnd;
        }
        return false;
    }

    // `name::callee`'s definitions (canonByName, DEFS only), or nullptr when the scope defines none.
    const rw::SmallVec<NodeId, 2>* definitionsIn( std::string_view scope, std::string_view callee ) const
    {
        keyScope.clear();
        keyScope.append( scope ).append( "::" ).append( callee );
        const auto it = canonByName.find( keyScope );
        return ( it != canonByName.end() && it->second.size() != 0 ) ? &it->second : nullptr;
    }

    // The type's OWN method set for the callee: its own definitions — or, when it defines none, the base members a
    // class-scope `using Base::callee;` names (usingReexports). C++ lookup stops at the first class that declares the
    // name, and a using-declaration declares it in the class itself, so `using B1::m;` in `D : B1, B2` answers B1::m
    // where the base walk refuses the two-base tie, and reaches a base the walk cannot name. A re-exported base is
    // probed by name, its own definitions else its base walk, ONE level deep: that base's own using-declarations are
    // not followed. Several using-declarations for one name answer the union of what they reach (an honest split); one
    // naming nothing the index reaches (a base outside the tree, an alias the resolver cannot follow) adds nothing, and
    // the unchanged walk runs. So does one naming a class OUTSIDE the class's base closure (inBaseClosure): C++ requires a
    // base there, so `using NotABase::m;` is mid-refactor or partial input, and trusting it pinned NotABase::m alone over
    // the real bases' tie (fieldnarrowcheck (u8); a grand-base is honoured, (u9)).
    // STATED FLOOR, decided by measurement: a class that DEFINES the callee answers its own definitions alone, even
    // when it also re-exports base overloads — which C++ puts in the same overload set. The union was built and graded
    // net-WORSE (2026-09-17, --pin-census rocksdb 0e2801ac3 + llvm-project 4d5358b1d, the 17 sites it moved, blinded
    // against source: 5 better, 4 same, 8 worse). With no parameter types the ladder cannot drop a re-exported base
    // overload the class OVERRIDES (rocksdb WriteBatch::Put's WriteBatchBase overloads) or one the arguments rule out
    // by count (the arity filter drops only too-many-arguments), and a split whose base half shares the caller's file
    // is cut to that half by the ladder's same-file tier. A call that selects the re-exported overload stays on the
    // class's own — fieldnarrowcheck (u1) pins that floor.
    // Returns canonByName storage for the class's own definitions, else `reexportUnion` (sorted by id, deduped).
    const rw::SmallVec<NodeId, 2>* ownMethodSet( std::string_view typeName, const Reference& r,
                                                  const HashMap<std::string, std::vector<std::string>>& chaUp ) const
    {
        const rw::SmallVec<NodeId, 2>* own = definitionsIn( typeName, r.calleeName );
        if( own != nullptr || usingReexports.empty() || ( r.lang != Lang::Cpp && r.lang != Lang::ObjC ) )
        {
            return own;   // the facts are C-family: a same-named Python/Ruby class keeps its own walk
        }
        const auto rit = usingReexports.find( keyScope );   // definitionsIn left `typeName::callee` in keyScope
        if( rit == usingReexports.end() )
        {
            return nullptr;
        }
        reexportUnion.clear();
        for( const std::string& base : rit->second )
        {
            if( !inBaseClosure( typeName, base, chaUp ) )
            {
                continue;   // not a base of the class: ill-formed or partial input, and the walk below decides as it always did
            }
            const rw::SmallVec<NodeId, 2>* baseDefs = definitionsIn( base, r.calleeName );
            if( baseDefs == nullptr )
            {
                baseDefs = methodOnTypeOrBases( base, r, chaUp, /*skipSelf=*/ true );   // the walk alone: canonByName storage or nullptr, never a buffer
            }
            if( baseDefs != nullptr )
            {
                reexportUnion.insert( reexportUnion.end(), baseDefs->begin(), baseDefs->end() );
            }
        }
        std::sort( reexportUnion.begin(), reexportUnion.end() );
        reexportUnion.erase( std::unique( reexportUnion.begin(), reexportUnion.end() ), reexportUnion.end() );
        return reexportUnion.empty() ? nullptr : &reexportUnion;
    }

    // `skipSelf` (Phase 5): start at the BASES — the type's own method set is not probed. The `super()`
    // receiver needs exactly that: `super().m()` inside class C names the first `m` in C's MRO AFTER C.
    // `unionOnMulti` (Phase 5): when two or more bases at the shallowest hit level define the callee, return the
    // UNION of their definitions instead of refusing — the `super()` walk needs it: a multi-base tie is an in-repo
    // ambiguity (Python's C3 order is not modelled), NOT a sign the MRO left the tree, and the caller's veto
    // must not fire on it. The union reaches the ladder as a narrowed multi-candidate set → an honest split.
    // A class that defines no `m` answers what its `using Base::m;` names (ownMethodSet), so `using B1::m;` in
    // `D : B1, B2` settles the two-base tie a walk would refuse. Only the type itself is read that way: a base the
    // walk reaches is probed for its own definitions, and that base's using-declarations are not read.
    const rw::SmallVec<NodeId, 2>* methodOnTypeOrBases( std::string_view typeName, const Reference& r,
                                                         const HashMap<std::string, std::vector<std::string>>& chaUp,
                                                         bool skipSelf = false, bool unionOnMulti = false ) const
    {
        if( !skipSelf )
        {
            if( const rw::SmallVec<NodeId, 2>* own = ownMethodSet( typeName, r, chaUp ) )
            {
                return own;
            }
        }

        fieldWalk.clear();
        fieldWalk.push_back( typeName );
        std::size_t lvlBegin = 0;
        while( lvlBegin < fieldWalk.size() )
        {
            const std::size_t lvlEnd = fieldWalk.size();
            // expand this level's bases into the next level (dedup against every visited name — cycles too). A walk the cap
            // stopped still probes the names it visited: this probe's policy, unlike fieldEntryAt's.
            expandWalkLevel( lvlBegin, lvlEnd, chaUp );
            // probe the NEW level's names; the shallowest level with any hit decides
            const auto [ found, multi ] = probeWalkLevel( lvlEnd, r.calleeName );
            if( multi )
            {
                return unionOnMulti ? &walkUnion : nullptr; // two distinct bases define the method at the same level → honest ambiguity
            }
            if( found != nullptr )
            {
                return found;
            }
            lvlBegin = lvlEnd;
        }
        return nullptr;
    }

    // Rule 1, the BASE WALK (docs/EVALS.md "Phase 5", mechanism 2 — the `IERS_B.open()` base walk applied to the
    // caller's OWN class). The same three shapes Rule 1 owns — `this->m()` / `self.m()`, a bare C-family `m()`
    // inside a member function — when the enclosing class defines NO `m`: walk its direct bases level by level
    // (methodOnTypeOrBases, Rules 2b/2c's discipline: the shallowest level with exactly one hitting base decides,
    // two at one level refuse). Plus the fourth shape this phase adds, `super().m()` (RecvKind::SuperObj), which
    // walks the bases ONLY — `super()` never names the class itself. A miss returns nullptr: for this/self/bare
    // the ladder is unchanged (a `self.m()` may dispatch DOWNWARD to a subclass override; the cone filter owns
    // that), for `super()` the CALLER applies the `@external` veto (the MRO left the indexed tree). Never invents:
    // every id returned is a real `Base::m` definition in canonByName.
    // `chaUpDeclared` = the direct bases in DECLARATION order (graph.h): for `super()` the FIRST declared base
    // that defines the callee wins (Python's MRO puts the first base's chain first — the mixin-before-base
    // idiom `class FlatLambdaCDM(FlatFLRWMixin, LambdaCDM)`); only when no direct base defines it does the
    // breadth-first walk continue into the deeper levels, returning the union of a multi-base level as an
    // honest split (C3 beyond the direct level is not modelled — disclosed).
    const rw::SmallVec<NodeId, 2>* rule1BaseWalk( const Reference& r, const std::string& callerScope,
                                                  const HashMap<std::string, std::vector<std::string>>& chaUp,
                                                  const HashMap<std::string, std::vector<std::string>>& chaUpDeclared ) const
    {
        if( callerScope.empty() || !r.qualifier.empty() )
        {
            return nullptr;   // no enclosing class to walk from / an explicit `A::m()` is canonical territory
        }
        const bool isSuper    = ( r.recv == RecvKind::SuperObj );
        const bool isThisSelf = ( r.recv == RecvKind::ThisObj );
        const bool bareCish   = ( r.recv == RecvKind::None ) && ( r.lang == Lang::Cpp || r.lang == Lang::ObjC || r.lang == Lang::Ruby );   // Ruby: implicit self (see rule1ClassMember)
        if( !isSuper && !isThisSelf && !bareCish )
        {
            return nullptr;
        }
        if( isSuper )
        {
            if( const auto dit = chaUpDeclared.find( callerScope ); dit != chaUpDeclared.end() )
            {
                for( const std::string& base : dit->second )
                {
                    keyScope.clear();
                    keyScope.append( base ).append( "::" ).append( r.calleeName );
                    if( const auto it = canonByName.find( keyScope ); it != canonByName.end() && it->second.size() != 0 )
                    {
                        return &it->second;   // the first DECLARED direct base defining the callee — MRO order
                    }
                }
            }
        }
        return methodOnTypeOrBases( callerScope, r, chaUp, /*skipSelf=*/ isSuper, /*unionOnMulti=*/ isSuper );
    }

    static constexpr std::size_t kFieldWalkCap = 16;   // total visited names — bounds depth and width together (methodOnTypeOrBases, memberFieldHides and fieldEntryAt)

    // Rule 2c's member-field veto set: "<Owner>#<field>" for every C/C++ member in the field side table (IngestResult::fields). That
    // table, not Rule 2b's fieldTypeByClass, because it holds EVERY declarator shape: the S5-E compose capture records no type for
    // `std::unique_ptr<Widget> Reader;`, the llvm shape this veto exists for. Owner is the scope's final segment — the keying of
    // Symbol::scope and chaUp — so same-named classes pool their members: a collision can only add a refusal, never a narrow. Python
    // attributes stay out: a Python method reaches one only through `self.`, so a bare `Interval.validate()` always names the class.
    static HashMap<std::string, char> memberFieldNames( const IngestResult& ing )
    {
        HashMap<std::string, char> names;
        names.reserve( ing.fields.size() );
        std::string key;
        for( const Symbol& f : ing.fields )
        {
            if( ( f.lang != Lang::Cpp && f.lang != Lang::C ) || f.scope.empty() || f.name.empty() )
            {
                continue;
            }
            std::string_view owner( f.scope );
            if( const std::size_t cut = owner.rfind( "::" ); cut != std::string_view::npos )
            {
                owner.remove_prefix( cut + 2 );
            }
            key.assign( owner ).push_back( '#' );
            key.append( f.name );
            names.try_emplace( key, '\0' );
        }
        return names;
    }

    // True ⇒ `name` is a member field of `callerScope`'s class or of a class up its chaUp bases, breadth-first. C++ lookup inside a
    // member function finds a member of the class or a base before any namespace-scope class, so such a token is the member and
    // never the class it is spelled like. A walk stopped by the cap with a base unvisited answers true as well: a narrow that cannot
    // prove the name unshadowed is withheld, never guessed. Reuses fieldWalk / keyScope / keyBind — it returns before the caller's
    // methodOnTypeOrBases clears them.
    bool memberFieldHides( std::string_view callerScope, std::string_view name, const HashMap<std::string, char>& memberFields,
                           const HashMap<std::string, std::vector<std::string>>& chaUp ) const
    {
        if( const std::size_t cut = callerScope.rfind( "::" ); cut != std::string_view::npos )
        {
            callerScope.remove_prefix( cut + 2 );
        }
        fieldWalk.clear();
        fieldWalk.push_back( callerScope );
        for( std::size_t walkIndex = 0; walkIndex < fieldWalk.size(); ++walkIndex )
        {
            keyBind.assign( fieldWalk[ walkIndex ] ).push_back( '#' );
            keyBind.append( name );
            if( memberFields.find( keyBind ) != memberFields.end() )
            {
                return true;
            }
            keyScope.assign( fieldWalk[ walkIndex ] );
            const auto uit = chaUp.find( keyScope );
            if( uit == chaUp.end() )
            {
                continue;
            }
            for( const std::string& base : uit->second )
            {
                if( std::find( fieldWalk.begin(), fieldWalk.end(), std::string_view( base ) ) != fieldWalk.end() )
                {
                    continue;
                }
                if( fieldWalk.size() >= kFieldWalkCap )
                {
                    return true;   // an unvisited base could declare the member — refuse rather than guess
                }
                fieldWalk.push_back( base );
            }
        }
        return false;
    }

    // Rule 2c — CLASS-NAME receiver (docs/EVALS.md "Phase 4b"). `Cls.m(…)`, a static / classmethod call THROUGH
    // THE CLASS NAME, reaches the ladder as a named-receiver call with no local binding, so Rule 2 cannot fire
    // and the S6-C prior then hands the win to the CALLER's own class by the scope segment (astropy:
    // `_Interval.validate(v)` pinned to `ModelBoundingBox::validate`). The receiver token IS the type: resolve
    // the callee against it, then its direct bases (`IERS_B.open()` → `IERS::open`). Narrows ONLY when ALL hold:
    // (1) bare named-receiver call from a known def; (2) NO local binding of any kind for (fromSymbol, recvVar)
    // — a parameter/local named like the class shadows it, and an assignment to the name proves a variable just as
    // well (every record in Rule 2b's veto set, not only the declarations Rule 2b reads); (2m) for a C++/ObjC caller, NO
    // member field of that name in the caller's class or its bases (memberFieldHides: `Reader->read()` beside
    // `std::unique_ptr<SampleProfileReader> Reader;` is the member — test/clsrecvcheck.sh arms H-N); (3) recvVar
    // names an in-repo class-like definition (`classNames`: SymKind Class/Struct/Interface); (4) the class — or
    // exactly one base at the shallowest hit level — DEFINES the callee. Two same-named classes both defining it
    // keep BOTH candidates (an honest split). Any miss ⇒ nullptr. C++'s `Cls::m()` never arrives here (a qualifier).
    // Rule 2c's name evidence, bundled so the rule's signature reads as its conditions: every class-like definition NAME (3), every
    // local binding "<fromSymbol>#var" (2), every C/C++ member "<Owner>#field" (2m, memberFieldNames). Built per call from graph.h's
    // tables — three references, no copy.
    struct ClassNameRecvNames
    {
        const HashMap<std::string, char>& classNames;
        const HashMap<std::string, char>& localNames;
        const HashMap<std::string, char>& memberFields;
    };
    const rw::SmallVec<NodeId, 2>* rule2cClassNameRecv( const Reference& r, const std::string& callerScope, const ClassNameRecvNames& names,
                                                        const HashMap<std::string, std::vector<std::string>>& chaUp ) const
    {
        if( r.recv != RecvKind::NamedVar || r.recvVar.empty() || !r.qualifier.empty() || r.fromSymbol == kNoNode )
        {
            return nullptr; // (1) not a bare named-receiver call from a known def
        }
        if( names.classNames.find( r.recvVar ) == names.classNames.end() )
        {
            return nullptr; // (3) the receiver token names no class-like definition anywhere in the corpus
        }
        keyBind.clear();
        appendUint( keyBind, r.fromSymbol );
        keyBind.push_back( '#' );
        keyBind.append( r.recvVar );
        if( names.localNames.find( keyBind ) != names.localNames.end() )
        {
            return nullptr; // (2) a local / parameter of that name shadows the class
        }
        if( ( r.lang == Lang::Cpp || r.lang == Lang::ObjC ) && !callerScope.empty() && memberFieldHides( callerScope, r.recvVar, names.memberFields, chaUp ) )
        {
            return nullptr; // (2m) a member field of the caller's class or a base hides the class
        }
        return methodOnTypeOrBases( r.recvVar, r, chaUp );   // (4)
    }

    // L3 — the fn-pointer/callback binding visible at a bare call site `fn()`. The two tables are passed
    // per call (they live in buildGraph's FnPtrBindTables; keeping them out of the ctor keeps the Narrower
    // contract unchanged): varFn = "<fromSymbolId>#var" LOCAL bindings, varFnFile = "<fileId>#var"
    // file-scope bindings, "" = tombstone in both. Returns {bindingExists, target}: target == nullptr while
    // bindingExists ⇒ the binding is tombstoned (two different functions), lambda-bound, clobbered, or a
    // local-vs-file disagreement — the call is KNOWN-indirect and must resolve to NOTHING (the caller never
    // falls back to the bare-name ladder: a same-named global function would be a FALSE edge, because the
    // binding proves the call goes through the variable). Local scope is consulted first, then the
    // file-scope table; both bound but disagreeing → nullptr — the same "any two distinct reaching targets
    // → refuse" discipline Rule 2's type tombstone implements. A5 escape guard: a var whose ADDRESS is
    // taken (`indirect_mutate(&fn)` can retarget it invisibly) or that is REFERENCE-bound (`H& r = fn;`)
    // arrives here already tombstoned by ingest's clobber records — see buildFnPtrBindTables (graph.h).
    std::pair<bool, const std::string*> fnPtrBindingTarget( const Reference&                          r,
                                                            const HashMap<std::string, std::string>& varFn,
                                                            const HashMap<std::string, std::string>& varFnFile ) const
    {
        const std::string* localT = nullptr;
        const std::string* fileT  = nullptr;
        keyBind.clear();
        appendUint( keyBind, r.fromSymbol );
        keyBind.push_back( '#' );
        keyBind.append( r.calleeName );
        if( const auto lit = varFn.find( keyBind ); lit != varFn.end() )
        {
            localT = &lit->second;
        }
        keyBind.clear();
        appendUint( keyBind, r.fileId );
        keyBind.push_back( '#' );
        keyBind.append( r.calleeName );
        if( const auto fit = varFnFile.find( keyBind ); fit != varFnFile.end() )
        {
            fileT = &fit->second;
        }
        if( localT == nullptr && fileT == nullptr )
        {
            return { false, nullptr };
        }
        const std::string* tgt = ( localT != nullptr && fileT != nullptr )
                                     ? ( ( *localT == *fileT ) ? localT : nullptr )
                                     : ( localT != nullptr ? localT : fileT );
        if( tgt == nullptr || tgt->empty() || *tgt == kFnBindLambdaTarget )
        {
            return { true, nullptr };   // kFnBindClobberTarget never appears as a VALUE (mapped to "" at build)
        }
        return { true, tgt };
    }

    // B2.1 CHA-lite input: the call's receiver STATIC TYPE name, when it is KNOWN by the same conservative
    // signals Rule 1/Rule 2 consume — `this`/`self` (⇒ the caller's enclosing class = callerScope) or a
    // named receiver `x` with EXACTLY ONE non-tombstoned in-scope type binding (`x : Foo` ⇒ "Foo"). Returns
    // "" for every other shape (bare call, chained/complex receiver, ambiguous/unbound var) → the caller does
    // NOT run CHA-lite. Read-only over the same maps Rule 1/2 use; NEVER a guess (a tombstoned var ⇒ "").
    std::string_view receiverStaticType( const Reference& r, const std::string& callerScope ) const
    {
        if( !r.qualifier.empty() )
        {
            return {}; // explicit `A::m()` → canonical, not a receiver-typed call
        }
        if( r.recv == RecvKind::ThisObj )
        { // `this`/`self` → the enclosing class is the static type
            return callerScope.empty() ? std::string_view{} : std::string_view( callerScope );
        }
        if( r.recv == RecvKind::NamedVar && !r.recvVar.empty() && r.fromSymbol != kNoNode )
        {
            return recvVarTypeName( r );   // unbound, tombstoned or untyped-in-scope → "" → no CHA-lite
        }
        return {};
    }

    // Rule 2's receiver-VARIABLE type at one call site — the ONE lookup Rule 2 and CHA-lite share, so they can never
    // disagree about a receiver. A name with a ParamType declaration in this definition is answered LEXICALLY: the
    // innermost declaration whose scope covers the site decides, and only its own written type counts — a
    // parameter shadowed by an `auto` loop variable, a range-for variable read after its loop, and two declarations
    // with one scope all answer "" — and so does a type written in namespace `std` (`const std::map<K, V>&`, see
    // namesStdType). Every other name reads the flat varType table, where buildGraph tombstones a `std::` type the
    // same way ("" = tombstone).
    // KNOWN FLOOR, the span model's own: a range-for variable's span is the whole loop statement, so a same-named
    // outer variable used inside the loop's own range expression reads as the loop variable.
    std::string_view recvVarTypeName( const Reference& r ) const
    {
        return recvVarType( r ).name;
    }

    // prov="final-segment" for a FIELD (test/fieldnarrowcheck.sh arm r): whether the field Rule 2b narrowed on was declared
    // QUALIFIED. `store::Text body_; body_.size()` matched `Text` alone, exactly the guess finalSegmentTypeAt discloses for a
    // parameter or a local, so the edge must not read as uniquely resolved. Asked only for a site Rule 2b decided.
    bool fieldFinalSegmentAt( const Reference& r, const std::string& callerScope, const FieldRecvTables& fields ) const
    {
        const FlatRecvType* field = fieldEntryAt( r, callerScope, fields );
        return field != nullptr && field->writtenQualified && !field->type.empty();
    }

    // Rule 2b's "Class#field" entry for a named receiver, or nullptr: keyed by the caller scope's FINAL segment (Symbol::scope
    // is the bare class name for methods; a nested scope's last segment is the innermost class). Shared by the narrow and its
    // prov="final-segment" question, so the two cannot read different entries.
    // A class that declares no member of that name reads it from its bases (test/fieldnarrowcheck.sh arm w): C++ lookup of a bare
    // name inside a member function finds the class's own member first, then the bases'. The walk is breadth-first over chaUp
    // (final-segment names, like methodOnTypeOrBases), and the SHALLOWEST level with a base DECLARING the member decides: exactly
    // one such base, whose entry is returned. A member counts as declared when it is typed OR only in the field side table, so a
    // member whose type was not captured — in the class itself or at a level before the hit — hides the bases behind it and
    // answers nullptr, never a deeper base's type. Two declaring bases at one level (an ambiguous lookup) and a walk the cap
    // stopped with a base unvisited answer nullptr too: neither proves which member the name reaches.
    const FlatRecvType* fieldEntryAt( const Reference& r, const std::string& callerScope, const FieldRecvTables& fields ) const
    {
        std::string_view className( callerScope );
        if( const std::size_t cut = className.rfind( "::" ); cut != std::string_view::npos )
        {
            className.remove_prefix( cut + 2 );
        }
        if( const auto [ own, ownDeclared ] = declaredFieldAt( className, r.recvVar, fields ); ownDeclared )
        {
            return own;   // the class's own member hides every base's — nullptr when its type was not captured
        }
        fieldWalk.clear();
        fieldWalk.push_back( className );
        for( std::size_t lvlBegin = 0; lvlBegin < fieldWalk.size(); )
        {
            const std::size_t lvlEnd = fieldWalk.size();
            if( !expandWalkLevel( lvlBegin, lvlEnd, fields.chaUp ) )
            {
                return nullptr;   // the cap left a base unvisited: this level may be incomplete, and deeper ones are unread
            }
            if( const auto [ hit, declaring ] = declaringBasesAt( lvlEnd, r.recvVar, fields ); declaring != 0 )
            {
                return declaring == 1 ? hit : nullptr;   // two bases declaring it at one level → an ambiguous lookup
            }
            lvlBegin = lvlEnd;
        }
        return nullptr;
    }

    // One level of fieldEntryAt's walk: how many of fieldWalk[ lvlEnd, end ) declare member `name`, and the last one's typed entry.
    std::pair<const FlatRecvType*, std::size_t> declaringBasesAt( std::size_t lvlEnd, std::string_view name, const FieldRecvTables& fields ) const
    {
        const FlatRecvType* hit       = nullptr;
        std::size_t         declaring = 0;
        for( std::size_t i = lvlEnd; i < fieldWalk.size(); ++i )
        {
            if( const auto [ entry, declared ] = declaredFieldAt( fieldWalk[ i ], name, fields ); declared )
            {
                ++declaring;
                hit = entry;
            }
        }
        return { hit, declaring };
    }

    // Whether `className` declares a member `name`, and its typed "Class#field" entry when it has one (nullptr when the member's
    // type was not captured). Reuses keyBind.
    std::pair<const FlatRecvType*, bool> declaredFieldAt( std::string_view className, std::string_view name, const FieldRecvTables& fields ) const
    {
        keyBind.assign( className ).push_back( '#' );
        keyBind.append( name );
        if( const auto fit = fields.types.find( keyBind ); fit != fields.types.end() )
        {
            return { &fit->second, true };
        }
        return { nullptr, fields.declared.find( keyBind ) != fields.declared.end() };
    }

    // Append the direct bases of fieldWalk[ lvlBegin, lvlEnd ) that the walk has not visited. False when the kFieldWalkCap-name cap
    // left one out. Reuses keyScope.
    bool expandWalkLevel( std::size_t lvlBegin, std::size_t lvlEnd, const HashMap<std::string, std::vector<std::string>>& chaUp ) const
    {
        for( std::size_t i = lvlBegin; i < lvlEnd; ++i )
        {
            keyScope.assign( fieldWalk[ i ] );
            const auto uit = chaUp.find( keyScope );
            if( uit == chaUp.end() )
            {
                continue;
            }
            for( const std::string& base : uit->second )
            {
                if( std::find( fieldWalk.begin(), fieldWalk.end(), std::string_view( base ) ) != fieldWalk.end() )
                {
                    continue;
                }
                if( fieldWalk.size() >= kFieldWalkCap )
                {
                    return false;
                }
                fieldWalk.push_back( base );
            }
        }
        return true;
    }

    // prov="final-segment" (test/narrowcheck.sh arm 25): whether a named receiver's type at this site — the one Rule 2 narrows
    // on and CHA-lite prunes by — was written QUALIFIED. Such a narrow matched the type's final segment alone and never
    // checked its qualifier against the class's namespace (arm 24's wrong edge is exactly that), so the edge must not read
    // as uniquely resolved. `this`, a field, a bare call or an explicit `A::m()` answer false.
    bool finalSegmentTypeAt( const Reference& r ) const
    {
        if( r.recv != RecvKind::NamedVar || r.recvVar.empty() || !r.qualifier.empty() || r.fromSymbol == kNoNode )
        {
            return false;
        }
        const RecvVarType t = recvVarType( r );
        return t.writtenQualified && !t.name.empty();
    }

    RecvVarType recvVarType( const Reference& r ) const
    {
        // key built in the reused buffer (identical bytes to `std::to_string( r.fromSymbol ) + "#" + r.recvVar`)
        keyBind.clear();
        appendUint( keyBind, r.fromSymbol );
        keyBind.push_back( '#' );
        keyBind.append( r.recvVar );
        if( const auto sit = scopedDecls.byName.find( keyBind ); sit != scopedDecls.byName.end() )
        {
            const ScopedRecvDecl* const innermost = innermostCoveringDecl( sit->second, r.startByte );
            if( innermost == nullptr || innermost->typeBinding >= kRecvDeclConflicted )
            {
                return RecvVarType{};   // no declaration in scope (a field or global of the name), a tie, or untyped/conflicted
            }
            const Binding& declared = ( *scopedDecls.bindings )[ innermost->typeBinding ];
            return namesStdType( declared.importedName ) ? RecvVarType{} : RecvVarType{ declared.typeName, !declared.importedName.empty(), &declared };
        }
        const auto vit = varType.find( keyBind );
        return ( vit == varType.end() ) ? RecvVarType{} : RecvVarType{ vit->second.type, vit->second.writtenQualified, nullptr };
    }

    // the qualifier the receiver's declaration wrote — the lexical record's own, else the flat table's kept one (read while
    // keyBind still holds this site's key) — and false when the flat table's records disagree: identity then stays out
    std::pair<bool, std::string_view> writtenQualifier( const RecvVarType& bound, const ClassIdentity& ids ) const
    {
        if( bound.declared != nullptr )
        {
            return { true, bound.declared->importedName };
        }
        const auto flat = ids.flatQualifier.find( keyBind );
        if( flat == ids.flatQualifier.end() )
        {
            return { true, std::string_view{} };
        }
        return { !flat->second.conflicting, flat->second.text };
    }

    // the innermost declaration whose span covers `siteByte`, or nullptr when none does or two declarations share
    // the innermost span (one scope cannot declare a name twice, so a tie is evidence we mis-read — refuse). Spans
    // inside one definition nest, so the innermost covering span is the one that starts LAST.
    static const ScopedRecvDecl* innermostCoveringDecl( std::span<const ScopedRecvDecl> decls, std::uint32_t siteByte ) noexcept
    {
        const ScopedRecvDecl* best = nullptr;
        bool                  tied = false;
        for( const ScopedRecvDecl& d : decls )
        {
            if( siteByte < d.spanStart || siteByte >= d.spanEnd )
            {
                continue;
            }
            if( best == nullptr || d.spanStart > best->spanStart || ( d.spanStart == best->spanStart && d.spanEnd < best->spanEnd ) )
            {
                best = &d;
                tied = false;
            }
            else if( d.spanStart == best->spanStart && d.spanEnd == best->spanEnd )
            {
                tied = true;
            }
        }
        return tied ? nullptr : best;
    }

    // Rule 3 — import/include-based FILE narrow. Given the bare-name candidate defs `cands` for a call inside
    // caller file `callerFileId`, keep the candidates that live in the ONE file the caller #includes / imports —
    // BUT ONLY when that is unambiguous. Writes the surviving ids into `out` and returns true iff it narrowed;
    // returns false (and leaves `out` untouched) ⇒ the caller falls through to the unchanged §2a ladder.
    //
    // Airtight "no wrong narrow" (the contract). Rule 3 fires ONLY when ALL hold:
    //   (1) the caller's file has ≥1 include/import edge (fileIncludes non-empty for callerFileId);
    //   (2) NO candidate lives in the caller's OWN file — a same-file def is the §2a same-file tier's job; letting
    //       Rule 3 override it could DROP the correct same-file target, so we bail and leave it to §2a;
    //   (3) EXACTLY ONE distinct INCLUDED file holds ≥1 candidate. 0 included files with a candidate → nothing to
    //       narrow to; ≥2 → the include set does NOT disambiguate (an honest split) → both bail to §2a.
    // When it fires, `out` holds exactly the candidates from that single included file — every one a real def the
    // bare ladder could also reach (a subset of `cands`); Rule 3 only PICKS the include-correct file's def earlier.
    // It can never invent a target, never empty a resolvable call, and never make a same-file call worse.
    //
    // Deterministic: `cands` is in symbol-id order (byName insertion order) and `fileIncludes[callerFileId]` is a
    // sorted id set, so the "which single file" decision and the emitted `out` are a pure function of the inputs.
    bool rule3IncludeFile( const rw::SmallVec<NodeId, 2>& cands, std::uint32_t callerFileId,
                           std::vector<NodeId>& out ) const
    {
        if( callerFileId >= fileIncludes.size() )
        {
            return false; // no per-file include set → no narrow
        }
        const std::vector<NodeId>& inc = fileIncludes[ callerFileId ];
        if( inc.empty() )
        {
            return false; // caller includes nothing → no narrow
        }
        if( cands.size() < 2 )
        {
            return false; // already unambiguous → nothing for Rule 3 to do
        }

        // included-file membership test: `inc` is sorted+deduped, so a binary search is the deterministic O(log)
        // check (no allocation, no state). A candidate in the caller's OWN file short-circuits the whole rule.
        const auto includes = [ & ]( std::uint32_t f ) noexcept
        {
            std::size_t lo = 0, hi = inc.size();
            while( lo < hi )
            {
                const std::size_t mid = ( lo + hi ) >> 1;
                if( inc[mid] < f ) { lo = mid + 1; }
                else
                {
                    hi = mid;
                }
            }
            return lo < inc.size() && inc[ lo ] == f;
        };

        std::uint32_t chosenFile = 0xFFFFFFFFu;   // the single included file that holds candidate(s), or sentinel
        bool          multiFile  = false;         // ≥2 distinct included files hold candidates → ambiguous → bail
        for( NodeId c : cands )
        {
            if( c >= symFileId.size() )
            {
                continue;
            }
            const std::uint32_t cf = symFileId[ c ];
            if( cf == callerFileId )
            {
                return false; // (2) same-file candidate → leave to §2a
            }
            if( !includes( cf ) )
            {
                continue; // candidate not in an included file → ignore
            }
            if( chosenFile == 0xFFFFFFFFu )
            {
                chosenFile = cf; // first included file with a candidate
            }
            else if( cf != chosenFile )        { multiFile = true; }        // a SECOND distinct included file → ambiguous
        }
        if( multiFile || chosenFile == 0xFFFFFFFFu )
        {
            return false; // (3) 0 or ≥2 included files → degrade to §2a
        }

        // narrow: keep exactly the candidates from the one chosen included file (id order preserved from `cands`).
        out.clear();
        for( NodeId c : cands )
        {
            if( c < symFileId.size() && symFileId[c] == chosenFile )
            {
                out.push_back( c );
            }
        }
        return !out.empty();
    }
};

// ── C++ template families: the canonical tier's fallback when a template-id qualifier keys no definition ──────────
// Ingest keys a primary template's out-of-line member by the bare template name and a specialization by its canonical
// template-id (ingest_names.h); a specialization header's base clause arrives as an inherit ref whose derived name is
// that template-id, so buildGraph's chaUp holds `Info<char>` → its bases too. What a call through `F<args>::name`
// can reach, when no definition is keyed `F<args>::name`, is decided here and nowhere else.

// Index one symbol into buildGraph's two canonical maps: a DEFINITION under "scope::name" (byScope) and, when its
// scope is a template-id, again under its template's family key (byFamily). Any symbol scoped by a template-id —
// a declaration too — also marks that specialization as EXISTING, under the scope text prefixed with '\x01' (a byte
// no scope or family key can hold): a call through an existing specialization that does not itself define the name
// must never fall back to its siblings.
inline void indexCanonicalScope( HashMap<std::string, rw::SmallVec<NodeId, 2>>& byScope, HashMap<std::string, rw::SmallVec<NodeId, 2>>& byFamily,
                                 std::string& key, const Symbol& s )
{
    if( s.scope.empty() )
    {
        return;
    }
    if( s.scope.back() == '>' )
    {
        key.assign( 1, '\x01' ).append( s.scope );
        byFamily[ key ];
    }
    if( !isDefinitionNotDeclaration( s ) )
    {
        return;
    }
    key.clear();
    key.append( s.scope ).append( "::" ).append( s.name );
    byScope[ key ].push_back( s.id );
    if( appendTemplateFamilyKey( key, s.scope, s.name ) )
    {
        byFamily[ key ].push_back( s.id );
    }
}

// The template-id class names chaUp holds — specializations with a base clause — byte-sorted, so the specializations
// of one template are one contiguous range (specializationsOf).
inline std::vector<std::string> sortedSpecializationNames( const HashMap<std::string, std::vector<std::string>>& chaUp )
{
    std::vector<std::string> names;
    for( const auto& [ derived, bases ] : chaUp )
    {
        if( !derived.empty() && derived.back() == '>' )
        {
            names.push_back( derived );
        }
    }
    std::sort( names.begin(), names.end() );
    return names;
}

// Everything the family fallback reads, owned by buildGraph.
struct CanonicalScopes
{
    const HashMap<std::string, rw::SmallVec<NodeId, 2>>&  byScope;
    const HashMap<std::string, rw::SmallVec<NodeId, 2>>&  byFamily;
    const std::vector<std::string>&                       specializationsWithBases;   // sortedSpecializationNames( chaUp )
    const Narrower&                                       narrower;                   // methodOnTypeOrBases — the CHA base walk
    const HashMap<std::string, std::vector<std::string>>& chaUp;
    const std::vector<Symbol>&                            symbols;                    // a candidate's scope, to widen it to its family
};

// Appends candidate ids to `cand` once each, past `before`, when `admit` accepts them.
template< class Admit >
struct CandidateSink
{
    std::vector<NodeId>& cand;
    std::size_t          before;
    Admit&               admit;

    void add( const rw::SmallVec<NodeId, 2>* ids )
    {
        for( std::size_t i = 0; ids != nullptr && i < ids->size(); ++i )
        {
            const NodeId c = ( *ids )[ i ];
            if( admit( c ) && std::find( cand.begin() + std::ptrdiff_t( before ), cand.end(), c ) == cand.end() )
            {
                cand.push_back( c );
            }
        }
    }
};

// The members of template `family` that supply `r.calleeName` beyond its primary: every specialization that defines it
// (byFamily) and every specialization with a base clause, through its own member or its bases.
template< class Admit >
inline void appendSpecializationMembers( CandidateSink<Admit>& sink, std::string& key, std::string_view family, const Reference& r,
                                         const CanonicalScopes& scopes )
{
    key.assign( family ).append( "::" ).append( r.calleeName );
    if( const auto it = scopes.byFamily.find( key ); it != scopes.byFamily.end() )
    {
        sink.add( &it->second );
    }
    key.assign( family ).push_back( '<' );
    const auto& specs = scopes.specializationsWithBases;
    for( auto it = std::lower_bound( specs.begin(), specs.end(), key ); it != specs.end() && it->starts_with( key ); ++it )
    {
        sink.add( scopes.narrower.methodOnTypeOrBases( *it, r, scopes.chaUp, /*skipSelf=*/false, /*unionOnMulti=*/true ) );
    }
}

// A member reached through a BASE may belong to a template family itself — `ImutContainerInfo<T>` inherits
// `ImutProfileInfo<T>::Profile`, and `ImutProfileInfo` has specializations — so each candidate a primary contributed is
// widened ONCE to its own template's specializations. The widening adds specialization members only, which a second
// pass would not widen again, so one pass is the fixpoint.
template< class Admit >
inline void widenToTemplateFamilies( CandidateSink<Admit>& sink, std::string& key, const Reference& r, const CanonicalScopes& scopes )
{
    const std::size_t assembled = sink.cand.size();
    for( std::size_t i = sink.before; i < assembled; ++i )
    {
        const std::string& scope = scopes.symbols[ sink.cand[ i ] ].scope;
        if( !scope.empty() && scope.back() != '>' )
        {
            appendSpecializationMembers( sink, key, scope, r, scopes );
        }
    }
}

// E#4's canonical tier: the defs keyed `qualifier::name` that `admit` (the caller's language/root filter) accepts,
// appended to `cand`. A C++ template-id qualifier that keys none is answered from its template's family, and only when
// the answer cannot be missing a body the call may reach:
//   * the written id names an EXISTING specialization (a member or a base clause says so) that does not define the
//     name → what that specialization inherits; if it inherits nothing, no answer;
//   * otherwise every specialization's own or inherited member joins what the PRIMARY supplies, itself or through its
//     bases. When the primary supplies nothing visible, the specializations alone answer only as a SPLIT of two or
//     more: a traits template whose primary defines no member (`DenseMapInfo<T>::getHashValue`) is answered by its
//     specializations, but a lone specialization beside a primary whose members are not visible — declared only, or
//     mis-scoped like llvm's `list_storage` — is no answer, because that primary may be the one the call reaches;
//   * either way a member reached through a base is widened to that base template's specializations.
// "No answer" leaves `cand` untouched, so the bare-name ladder decides exactly as it did before this fallback existed.
// More than one candidate is a split the caller discloses with amb=; a call through a template-id never lands on a
// same-named definition outside the template. `key` is the caller's reused buffer.
template< class Admit >
inline void appendCanonicalCandidates( std::vector<NodeId>& cand, std::string& key, const Reference& r, const CanonicalScopes& scopes, Admit&& admit )
{
    CandidateSink<Admit> sink { cand, cand.size(), admit };
    key.clear();
    key.append( r.qualifier ).append( "::" ).append( r.calleeName );
    if( const auto it = scopes.byScope.find( key ); it != scopes.byScope.end() )
    {
        sink.add( &it->second );
    }
    if( cand.size() != sink.before || !appendTemplateFamilyKey( key, r.qualifier, r.calleeName ) )
    {
        return;
    }
    key.assign( 1, '\x01' ).append( r.qualifier );
    const bool existingSpecialization = scopes.byFamily.find( key ) != scopes.byFamily.end() || scopes.chaUp.find( r.qualifier ) != scopes.chaUp.end();
    const std::string_view family = existingSpecialization ? std::string_view( r.qualifier ) : namesplit::stripTemplateArgs( r.qualifier );
    sink.add( scopes.narrower.methodOnTypeOrBases( family, r, scopes.chaUp, /*skipSelf=*/existingSpecialization, /*unionOnMulti=*/true ) );
    const bool primarySupplies = cand.size() != sink.before;
    if( existingSpecialization && !primarySupplies )
    {
        return;
    }
    if( !existingSpecialization )
    {
        appendSpecializationMembers( sink, key, family, r, scopes );
    }
    if( !primarySupplies && cand.size() < sink.before + 2 )
    {
        cand.resize( sink.before );   // a lone specialization with no visible primary member is no answer (see above)
        return;
    }
    widenToTemplateFamilies( sink, key, r, scopes );
}

}   // namespace rw
