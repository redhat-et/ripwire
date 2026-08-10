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

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdio>       // fopen/fread — workspace-only config-file evidence (go.mod / tsconfig.json), §3.2
#include <string>
#include <string_view>
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
    const bool                     isAbsolute = ( !path.empty() && path.front() == '/' );
    std::vector<std::string_view>  segs;                 // the surviving path components, in order
    segs.reserve( 8 );

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
            if( !segs.empty() && segs.back() != ".." )
            {
                segs.pop_back(); // pop the previous real segment
            }
            else if( isAbsolute )                       { /* `..` at the filesystem root is a no-op */ }
            else
            {
                return {}; // relative `..` escaping above the base → unsound
            }
        }
        else
        {
            segs.push_back( seg );
        }

        i = ( j < path.size() ) ? j + 1 : j;             // skip the '/'
    }

    // reassemble
    std::string out;
    if( isAbsolute )
    {
        out.push_back( '/' );
    }
    for( std::size_t k = 0; k < segs.size(); ++k )
    {
        if( k )
        {
            out.push_back( '/' );
        }
        out.append( segs[k] );
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
// `#include`; Other (Go/Swift/Markdown/…) never precise-resolves (deferred / no path in import).
enum class IncludeLang : std::uint8_t { CFamily, Python, Ts, Rust, Go, Other };

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
        { ".py",  IncludeLang::Python },
        { ".ts",  IncludeLang::Ts },      { ".tsx", IncludeLang::Ts },      { ".mts", IncludeLang::Ts },
        { ".cts", IncludeLang::Ts },      { ".js",  IncludeLang::Ts },      { ".jsx", IncludeLang::Ts },
        { ".mjs", IncludeLang::Ts },      { ".cjs", IncludeLang::Ts },
        { ".rs",  IncludeLang::Rust },
        { ".go",  IncludeLang::Go },       // Go: single-root DEFERRED (kNoFile); cross-root via go.mod `replace` (§3.2)
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
    // FIRST an exact hit (specifier already has an extension, e.g. `./x.js`), then extension-appended, then index.
    probe( std::string( target ) );
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

// Resolve ONE #include / import target to a concrete repo fileId by LEXICAL path semantics, dispatched on
// the INCLUDER's language (its file extension). `fileIndex` maps each canonical `ing.files` path → its
// fileId. `crateRootDir`/`hasCrateRoot` carry the Rust crate root (empty/false for non-Rust). Returns the
// fileId on a UNIQUE precise hit, else kNoFile (unresolved → contributes nothing; NEVER a basename
// fallback, NEVER a guess).
//   * C-family quote `"x.h"` (isAngle==false): resolve relative-to-includer, collapse `.`/`..`, exact hit.
//   * C-family angle `<x.h>` (isAngle==true): external without a build system ⇒ kNoFile (never matched).
//   * Python / TS / Rust: their per-language Step-A above (unique-or-degrade).
//   * Go / Swift / Other: DEFERRED / no path ⇒ kNoFile (contributes nothing — honest).
inline std::uint32_t resolvePreciseInclude( std::string_view includerPath, std::string_view target, bool isAngle,
                                            const HashMap<std::string, std::uint32_t>& fileIndex,
                                            std::string_view crateRootDir = {}, bool hasCrateRoot = false,
                                            const WsIncludeCtx* ws = nullptr, std::uint32_t includerFileId = kNoFile )
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
inline std::vector<std::vector<std::uint32_t>> buildPreciseIncludeAdj( const IngestResult& ing, bool dedup = true )
{
    const std::uint32_t F = std::uint32_t( ing.files.size() );
    std::vector<std::vector<std::uint32_t>> adj( F );
    if( ing.includes.empty() )
    {
        return adj;
    }

    // path → fileId over the canonical (sorted) file list. The KEY is the LEXICALLY-NORMALIZED file path,
    // NOT the raw ing.files spelling: a crawl rooted at `.` stores paths with a leading `./` (`./test/main.cpp`),
    // but a resolved include candidate is always `lexicalNormalize`d — which strips `.`/`./` segments — so the
    // candidate `render/shader.h` would NOT byte-match a raw key `./render/shader.h` and the edge would be
    // silently DROPPED (a false negative under a `.` root). Normalizing BOTH sides through the same lexical
    // rule makes them agree with no re-rooting. Pure + deterministic (lexicalNormalize is I/O-free).
    HashMap<std::string, std::uint32_t> fileIndex;
    fileIndex.reserve( F );
    for( std::uint32_t f = 0; f < F; ++f )
    {
        fileIndex.emplace( lexicalNormalize( ing.files[f] ), f );
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
        const std::string_view p = ing.files[f];
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

    for( const Include& inc : ing.includes )
    {
        if( inc.fileId >= F )
        {
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
        const std::uint32_t to = resolvePreciseInclude( ing.files[ inc.fileId ], inc.target, inc.isAngle,
                                                         fileIndex, crd, hasCrd, ws, inc.fileId );
        if( to == kNoFile || to == inc.fileId )
        {
            continue; // unresolved or self-include → contributes nothing
        }
        adj[ inc.fileId ].push_back( to );
    }
    if( dedup )
    {
        for( std::vector<std::uint32_t>& v : adj )
        {
            std::sort( v.begin(), v.end() );
            v.erase( std::unique( v.begin(), v.end() ), v.end() );
        }
    }
    return adj;
}

// Transitive include-set per file: for each file f, the sorted, deduped set of fileIds reachable from
// f by ≥1 include hop (f itself EXCLUDED). Cycle-safe via a `seen` bitset (a file already visited is
// not re-pushed), so mutually-including headers (a↔b) simply each reach the other — the exact
// reachability walk shape as graph.h::dependencyHealth. Deterministic: `adj` is sorted, each result
// set is re-sorted+deduped, so it is a pure function of the adjacency regardless of visit order.
inline std::vector<std::vector<NodeId>> transitiveIncludeSet( const std::vector<std::vector<std::uint32_t>>& adj )
{
    const std::uint32_t          F = std::uint32_t( adj.size() );
    std::vector<std::vector<NodeId>> trans( F );
    std::vector<std::uint32_t>   seenEpoch( F, 0 );
    std::vector<std::uint32_t>   stack;
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
        // …trans[s] already excludes s (never pushed as a reachable target). Sort+dedup for binary search.
        std::sort( trans[s].begin(), trans[s].end() );
        trans[s].erase( std::unique( trans[s].begin(), trans[s].end() ), trans[s].end() );
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

// One-hop receiver narrowing over the canonical scope::name → definition-ids map (built once by buildGraph).
// Holds only const references to maps buildGraph owns — no state, no allocation, no copy of the symbol table.
struct Narrower
{
    const HashMap<std::string, rw::SmallVec<NodeId, 2>>& canonByName;   // "Scope::name" → def ids (defs only)
    // P2-D Rule 2 binding table: "<fromSymbolId>#<var>" → the variable's resolved TYPE name (a class/struct in
    // canonByName), or the empty string as a TOMBSTONE marking an AMBIGUOUS var (bound to ≥2 distinct types in
    // one scope) — looked up but never narrowed. buildGraph builds it from IngestResult::bindings. Empty when
    // there are no bindings, so Rule 2 simply never fires (degrades to the unchanged ladder).
    const HashMap<std::string, std::string>&             varType;
    // P2-D Rule 3 include table: caller fileId → the sorted, deduped set of fileIds it #includes / imports
    // (resolved file→file by basename, exactly like graph.h::resolveIncludeAdj; the caller's own file is NEVER
    // in its own set). buildGraph builds it once from IngestResult::includes. Empty when the repo has no
    // include/import edges, so Rule 3 simply never fires (degrades to the unchanged ladder). A `std::span`
    // seam: buildGraph owns the storage (a `std::vector<std::vector<NodeId>>`), the Narrower only reads it.
    const std::vector<std::vector<NodeId>>&              fileIncludes;
    // per-symbol fileId (view into ing.symbols' fileIds), so Rule 3 can group candidate defs by their file
    // without a reference to the whole IngestResult. buildGraph owns the backing vector.
    const std::vector<std::uint32_t>&                    symFileId;

    // reused key-assembly buffers — one `Narrower` drives the whole (single-threaded) resolve loop, so the
    // `scope::name` / `<fromSymbol>#var` lookup keys are built IN PLACE (clear()+append(), capacity kept) into
    // these instead of a fresh std::string per reference. The BYTES are identical to the old `+` concats, so the
    // map lookups — and the resolved graph — are byte-for-byte unchanged; only the per-ref malloc churn is gone.
    mutable std::string keyScope;   // "Scope::name" for canonByName lookups (Rule 1 + Rule 2's type::method)
    mutable std::string keyBind;    // "<fromSymbolId>#var" for the varType binding lookup (Rule 2 + L3)

    explicit Narrower( const HashMap<std::string, rw::SmallVec<NodeId, 2>>& canon,
                       const HashMap<std::string, std::string>&             vt,
                       const std::vector<std::vector<NodeId>>&              incl,
                       const std::vector<std::uint32_t>&                    symFile ) noexcept
        : canonByName( canon ), varType( vt ), fileIncludes( incl ), symFileId( symFile ) {}

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
        const bool isCish      = ( r.lang == Lang::Cpp || r.lang == Lang::ObjC );
        const bool bareCish    = isCish && ( r.recv == RecvKind::None );   // C++ unqualified member-or-namespace lookup
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
    // by buildGraph → empty type → no narrow); (3) the bound type defines `m` (canonByName, DEFS only). So the
    // returned ids are always real `Foo::m` definitions the bare ladder could also reach — Rule 2 just picks the
    // type-correct one earlier. Any uncertainty (no binding, conflicting bindings, type has no such method) →
    // honest ambiguity via §2a, never a guess. Deterministic: canonByName insertion order = symbol-id order.
    const rw::SmallVec<NodeId, 2>* rule2RecvVarType( const Reference& r ) const
    {
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

        // the var's resolved type in THIS scope. Empty value = tombstone (ambiguous var) → no narrow. Key built
        // in the reused buffer (identical bytes to `std::to_string( r.fromSymbol ) + "#" + r.recvVar`).
        keyBind.clear();
        appendUint( keyBind, r.fromSymbol );
        keyBind.push_back( '#' );
        keyBind.append( r.recvVar );
        const auto vit = varType.find( keyBind );
        if( vit == varType.end() || vit->second.empty() )
        {
            return nullptr;
        }

        // resolve `m` against the bound type's own methods (defs only). Miss ⇒ degrade to §2a. Reused buffer,
        // identical bytes to `vit->second + "::" + r.calleeName`.
        keyScope.clear();
        keyScope.append( vit->second ).append( "::" ).append( r.calleeName );
        const auto it = canonByName.find( keyScope );
        if( it == canonByName.end() || it->second.size() == 0 )
        {
            return nullptr;
        }
        return &it->second;   // real `Foo::m` definition(s) — overloads stay split 1/k, but only within the type
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
            keyBind.clear();
            appendUint( keyBind, r.fromSymbol );
            keyBind.push_back( '#' );
            keyBind.append( r.recvVar );
            const auto vit = varType.find( keyBind );
            if( vit == varType.end() || vit->second.empty() )
            {
                return {}; // unbound or tombstoned (ambiguous) → no type
            }
            return std::string_view( vit->second );
        }
        return {};
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

}   // namespace rw
