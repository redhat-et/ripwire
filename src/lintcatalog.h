#pragma once

// lintcatalog.h — L7: the machine-readable REGISTRY for every built-in `--lint` rule.
//
// `--lint` has always emitted a bare `<rule name="X" count="N"/>` — no severity, no category, no
// rationale, and no disclosure of which grammars a rule's query can even fire on. A rule with
// count="0" on a Go tree reads exactly like "checked, found nothing" whether the rule is a real,
// applicable, zero-findings measurement (redundant-parens on a clean C++ file) or a rule that is
// STRUCTURALLY INERT on this corpus (self-assign's query needs an assignment_EXPRESSION node, which
// Go's grammar does not have — Go assignment is a statement). The house rule is that a zero must never
// be confusable with "none exists"; this header is what makes that distinction machine-readable for
// `--lint`'s own tally, and gives `--lint-catalog` something to print.
//
// Every langMask below was DERIVED, not guessed, one of two ways:
//   (a) three packs already gate themselves to C/C++/ObjC in source — atoms.h::isCFamilyPath,
//       cachelint.h (same predicate), and lintSymbolLevelChecks' own `isCFamily` extension allowlist
//       (main.cpp) which is narrower still: C/C++ only, ObjC EXCLUDED ("Only check C/C++ functions —
//       Python/Go/Rust have different idioms" — its own comment). Those rows just mirror the gate.
//   (b) the eleven base [AST]-only checks and unreachable-code are NOT source-gated to a language list
//       at all — astQuery compiles each query against every linked grammar and only fires where it
//       succeeds, so their true reach was measured empirically: a small per-language fixture tree run
//       through `--lint`, recording which built-in queries produced a finding on which language. Several
//       bare-looking node-type names turned out to be spelled — or field-shaped — differently across
//       grammars: `number_literal` exists ONLY in the C-family grammars linked here (JS/TS/Python/Go/
//       Rust/Java/C#/Ruby/Swift all have numeric literals, just under a different node name), so
//       magic-number never fires outside C/C++/ObjC despite looking like a universal check; Swift's
//       `do_statement` is its do/catch block (not a loop) — do-while's query still matches it, just not
//       for the reason its name suggests, which the row's rationale says plainly rather than hiding.
//
// naming-* is the one family that is genuinely universal: it reads Symbol name/kind, which every
// indexed language produces, and nothing in naminglens.h gates it to a language subset.

#include "clones.h"       // rw::langBit — the ONE Lang→bitmask primitive, reused here instead of a second copy
#include "didyoumean.h"   // boundedEditDistance — the ONE near-miss primitive; reused here for rule names
#include "lintrules.h"    // langOfPath — the house file-language predicate --lint-rules already uses
#include "model.h"        // Lang, IngestResult

#include <algorithm>
#include <array>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw::lintcatalog
{

// The catalog's language vocabulary is exactly the token set --lint-rules' own `language:` field
// already accepts (lintrules.h::langFromToken) — one language spelling for the whole lint subsystem,
// so a catalog row's lang= list is round-trippable straight into a user rule's language: field.
inline constexpr std::array<Lang, 15> kCatalogLangs = { {
    Lang::Cpp, Lang::C, Lang::ObjC, Lang::Python, Lang::TypeScript, Lang::JavaScript,
    Lang::Go, Lang::Rust, Lang::Swift, Lang::Java, Lang::CSharp, Lang::Ruby, Lang::Bash,
    // Php/Lua join the vocabulary, but ONLY the language-agnostic naming family (kAllCatalogLangs)
    // actually fires on them: every AST-shaped built-in below names its node kinds explicitly, and none
    // of those kinds exists in either grammar, so their masks are unchanged by this append. What the two
    // entries buy is the round-trip — `language: php` in a user AST rule now resolves, and a catalog row
    // that claims to cover php/lua is backed by langOfPath knowing .php/.lua (lintrules.h).
    Lang::Php, Lang::Lua,
} };

// Lang→bitmask itself is rw::langBit (src/clones.h) — reused, not redefined.

// The three languages every AST-shaped pack (atoms, cache) gates itself to in source — named once so a
// row below is one constant, not three ORed bits repeated 15 times.
inline constexpr std::uint32_t kCFamily = langBit( Lang::Cpp ) | langBit( Lang::C ) | langBit( Lang::ObjC );

// lintSymbolLevelChecks' OWN extension allowlist (main.cpp) is narrower than kCFamily: C/C++ only, ObjC
// deliberately excluded ("Only check C/C++ functions... Python/Go/Rust have different idioms").
inline constexpr std::uint32_t kCppOnly = langBit( Lang::Cpp ) | langBit( Lang::C );

// unreachable-code's block-node allowlist (ur_isBlockNode, main.cpp): compound_statement (C/C++/ObjC),
// block (Python/Java/Go/C#), statement_block (JS/TS) — measured, not the same set as either constant above.
inline constexpr std::uint32_t kUnreachableLangs = kCFamily | langBit( Lang::Python ) | langBit( Lang::Java )
                                                  | langBit( Lang::Go ) | langBit( Lang::CSharp )
                                                  | langBit( Lang::JavaScript ) | langBit( Lang::TypeScript );

inline constexpr std::uint32_t allCatalogLangsInit() noexcept
{
    std::uint32_t m = 0;
    for( Lang l : kCatalogLangs )
    {
        m |= langBit( l );
    }
    return m;
}
inline constexpr std::uint32_t kAllCatalogLangs = allCatalogLangsInit();  // every language --lint-select= can ever apply to

struct LintCatalogRow
{
    std::string_view name;
    std::string_view severity;    // info | warn | error — the same closed set lintrules.h::kLintSeverities validates
    std::string_view category;
    std::string_view rationale;   // one line, no trailing period
    std::uint32_t     langMask;   // bitmask over kCatalogLangs — which grammars can ever satisfy this rule's query/scan
    std::string_view since;       // the ripwire release the rule first shipped in (git archaeology on the literal, not a guess)
};

// Declaration order here IS the order `--lint`'s tally and `--lint-catalog`'s listing both use — the
// same 24 base names main.cpp's allRuleNames builds, then the atoms pack's 7, then the cache pack's 8.
inline constexpr std::array<LintCatalogRow, 39> kLintCatalog = { {
    // ── base [AST]-only checks (main.cpp `checks` table) ────────────────────────────────────────────
    { "c-style-cast", "warn", "style",
      "a C-style cast — cppcoreguidelines-pro-type-cstyle-cast prefers the explicit static_cast/const_cast/reinterpret_cast",
      kCFamily | langBit( Lang::Java ) | langBit( Lang::CSharp ), "v0.1.0" },
    { "goto", "warn", "control-flow", "a goto statement — cppcoreguidelines-avoid-goto",
      kCFamily | langBit( Lang::Go ) | langBit( Lang::CSharp ), "v0.1.0" },
    { "do-while", "info", "style",
      "a do/while loop shape (on Swift, its do/catch block shares the same grammar node and also matches)",
      kCFamily | langBit( Lang::TypeScript ) | langBit( Lang::JavaScript ) | langBit( Lang::Swift )
          | langBit( Lang::Java ) | langBit( Lang::CSharp ), "v0.1.0" },
    { "unsafe-c-fn", "error", "security", "a call to an unbounded C string function (strcpy/strcat/sprintf/gets)",
      kCFamily | langBit( Lang::Go ) | langBit( Lang::JavaScript ) | langBit( Lang::Rust ) | langBit( Lang::TypeScript ), "v0.1.0" },
    { "weak-crypto", "error", "security", "a call to a broken hash or cipher (MD5/SHA1/MD4/RC4)",
      kCFamily | langBit( Lang::Go ) | langBit( Lang::JavaScript ) | langBit( Lang::Rust ) | langBit( Lang::TypeScript ), "v0.1.0" },
    { "redundant-parens", "info", "style", "a doubly-parenthesized expression — readability-redundant-parentheses",
      kCFamily | langBit( Lang::Go ) | langBit( Lang::Java ) | langBit( Lang::JavaScript ) | langBit( Lang::Python )
          | langBit( Lang::Rust ) | langBit( Lang::TypeScript ) | langBit( Lang::CSharp ), "v0.1.0" },
    { "suspicious-semicolon", "warn", "correctness", "an if-body that is just `;` — bugprone-suspicious-semicolon",
      kCFamily, "v0.1.0" },
    { "typedef-over-using", "info", "style", "a C-style typedef struct/union where `using` is preferred",
      kCFamily, "v0.1.0" },
    { "magic-number", "info", "maintainability",
      "a non-trivial numeric literal inside a function body, outside a const/constexpr init",
      kCFamily, "v0.1.0" },
    { "empty-catch", "warn", "error-masking", "a catch block with an empty body", kCFamily, "v0.1.0" },
    { "self-assign", "warn", "correctness", "x = x — almost always a copy-paste bug",
      kCFamily | langBit( Lang::Java ) | langBit( Lang::JavaScript ) | langBit( Lang::Rust ) | langBit( Lang::TypeScript )
          | langBit( Lang::CSharp ), "v0.1.0" },

    // ── symbol-level checks (lintSymbolLevelChecks, main.cpp) — C/C++ only, ObjC deliberately excluded ──
    { "large-function", "info", "maintainability", "a function body over 80 lines", kCppOnly, "v0.1.0" },
    { "deep-nesting", "info", "maintainability", "brace nesting depth over 4 inside a function body", kCppOnly, "v0.1.0" },
    { "inconsistent-return", "info", "maintainability",
      "a bare `return;` mixed with a value-returning return in the same function", kCppOnly, "v0.1.0" },
    { "unreachable-code", "warn", "correctness",
      "a statement after an unconditional return/break/continue/throw/raise in the same block",
      kUnreachableLangs, "v0.1.0" },

    // ── naming-* (naminglens.h) — reads Symbol name/kind, gated to no language subset ──────────────────
    { "naming-short", "info", "naming",
      "a 1-2 letter Function/Method/Var name — visible far beyond any tiny scope [Beniamini/Hofmeister]",
      kAllCatalogLangs, "v0.2.2" },
    { "naming-wordy", "info", "naming", "more than 5 split tokens in one name [Butler; AlSuhaibani]",
      kAllCatalogLangs, "v0.2.2" },
    { "naming-series", "info", "naming",
      "foo1/foo2/... digit-suffix siblings sharing a base name in one scope [Butler]", kAllCatalogLangs, "v0.2.2" },
    { "naming-underscore", "info", "naming",
      "internal consecutive underscores, or a C-family reserved __x/_X form [Butler]", kAllCatalogLangs, "v0.2.2" },
    { "naming-case", "info", "naming", "snake_case and camelCase mixed inside one name [Butler]",
      kAllCatalogLangs, "v0.2.2" },
    { "naming-predicate", "info", "naming",
      "an is/has/can/should/was-prefixed name whose KNOWN return type is not bool-like [LAPD A2]",
      kAllCatalogLangs, "v0.2.2" },
    { "naming-setter", "info", "naming", "a set-prefixed name whose KNOWN return type is not void-like [LAPD A3]",
      kAllCatalogLangs, "v0.2.2" },
    { "naming-confusable", "info", "naming",
      "a co-visible pair within edit distance <=2, reordered tokens, or a bare/digit-suffixed twin [Namesake]",
      kAllCatalogLangs, "v0.2.2" },
    { "naming-uninformative", "info", "naming",
      "every split subtoken is corpus-ubiquitous (BM25 idf) on a body past the size floor — fires only at the low end [Sparck Jones 1972]",
      kAllCatalogLangs, "v0.2.2" },

    // ── atoms-of-confusion (atoms.h) — isCFamilyPath-gated, Gopstein ESEC/FSE 2017 ────────────────────
    { "atom-comma-operator", "info", "readability",
      "the comma operator inside an expression (never a for-header comma) [Gopstein FSE 2017]", kCFamily, "v0.2.2" },
    { "atom-embedded-crement", "info", "readability",
      "++/-- evaluated inside a larger expression (never a whole statement) [Gopstein FSE 2017]", kCFamily, "v0.2.2" },
    { "atom-assign-as-value", "info", "readability",
      "an assignment whose VALUE is consumed (a condition, an argument, ...) [Gopstein FSE 2017]", kCFamily, "v0.2.2" },
    { "atom-nested-ternary", "info", "readability",
      "a conditional expression inside a conditional expression [Gopstein FSE 2017]", kCFamily, "v0.2.2" },
    { "atom-implicit-predicate", "info", "readability",
      "arithmetic (or a non-0/1 integer literal) used where a truth value is expected [Gopstein FSE 2017]", kCFamily, "v0.2.2" },
    { "atom-octal-literal", "info", "readability",
      "a leading-zero integer literal — 0755 is 493, not 755 [Gopstein FSE 2017]", kCFamily, "v0.2.2" },
    { "atom-reversed-subscript", "info", "readability",
      "1[arr] — legal C, almost never intended [Gopstein FSE 2017]", kCFamily, "v0.2.2" },

    // ── cache-friendliness (cachelint.h) — isCFamilyPath-gated ──────────────────────────────────────
    { "cache-node-container", "info", "performance",
      "a node-based std container (map/list/set/...) — one heap node per element, a dependent pointer chase per traversal step",
      kCFamily, "v0.2.2" },
    { "cache-vector-of-raw-ptr", "info", "performance",
      "vector<T*> — contiguous handles, scattered payloads", kCFamily, "v0.2.2" },
    { "cache-vector-of-indirect", "info", "performance",
      "vector<unique_ptr/shared_ptr/vector<...>> — an indirection per element", kCFamily, "v0.2.2" },
    { "cache-heap-alloc-in-loop", "info", "performance",
      "new/malloc/calloc/realloc/strdup inside a loop body — per-iteration allocation scatters the loop's output across the heap",
      kCFamily, "v0.2.2" },
    { "cache-pointer-chase-loop", "info", "performance",
      "p = p->next inside a loop — a serial dependent-load chain the prefetcher cannot predict", kCFamily, "v0.2.2" },
    { "cache-gather-subscript", "info", "performance",
      "a[b[i]] inside a loop — gather/scatter, random access by construction", kCFamily, "v0.2.2" },
    { "cache-shared-ptr-by-value", "info", "performance",
      "a by-value shared_ptr parameter — atomic refcount traffic per call", kCFamily, "v0.2.2" },
    { "cache-manual-prefetch", "info", "performance",
      "an existing _mm_prefetch/__builtin_prefetch call, flagged for re-measurement (2007-era wins are often a wash today)",
      kCFamily, "v0.2.2" },
} };

inline const LintCatalogRow* lintCatalogFind( std::string_view name ) noexcept
{
    const auto it = std::find_if( kLintCatalog.begin(), kLintCatalog.end(),
                                  [ name ]( const LintCatalogRow& r ) { return r.name == name; } );
    return it == kLintCatalog.end() ? nullptr : &*it;
}

// Comma-joined language tokens, in kCatalogLangs' declared order — deterministic, and the SAME token
// spelling langFromToken accepts (langTag(), model.h), so a catalog row's lang= is round-trippable
// straight into a user rule's language: field.
inline std::string lintCatalogLangList( std::uint32_t mask )
{
    std::string out;
    for( Lang l : kCatalogLangs )
    {
        if( mask & langBit( l ) )
        {
            if( !out.empty() )
            {
                out.push_back( ',' );
            }
            out += langTag( l );
        }
    }
    return out;
}

// The corpus' own language mask — which of kCatalogLangs at least one indexed file actually is. One
// pass, shared by every row's applicability check instead of a per-rule rescan of ing.files.
inline std::uint32_t corpusLangMask( const IngestResult& ing )
{
    std::uint32_t mask = 0;
    for( const std::string& f : ing.files )
    {
        const Lang l = langOfPath( f );
        for( Lang c : kCatalogLangs )
        {
            if( c == l )
            {
                mask |= langBit( c );
                break;
            }
        }
        if( mask == kAllCatalogLangs )
        {
            break;   // every language this catalog knows is already present — nothing left to learn
        }
    }
    return mask;
}

// ── --lint-select / --lint-ignore: PREFIX semantics over the rule-name space ───────────────────────
//
// "*" is the one reserved sentinel (never a real rule-name prefix, since no built-in or YAML-loaded
// rule id is spelled "*") meaning "every rule" — the mechanism `--lint-ignore=*` needs to mean "ignore
// everything" without the caller having to spell out all 39+ names by hand.
struct LintSelection
{
    std::vector<std::string> selectPrefixes;   // empty ⇒ --lint-select absent (behaves as "select everything")
    std::vector<std::string> ignorePrefixes;   // empty ⇒ --lint-ignore absent
    bool                     active        = false;   // either flag was given — gates the root's selected= disclosure
    std::size_t              selectedCount = 0;        // names in the resolution pool this run keeps
    std::size_t              totalCount    = 0;        // the resolution pool's own size (built-ins + loaded user rules)
};

inline bool lintPrefixMatches( std::string_view prefix, std::string_view name ) noexcept
{
    return prefix == "*" || name.substr( 0, prefix.size() ) == prefix;
}

inline bool lintSelectionKeeps( const LintSelection& sel, std::string_view name ) noexcept
{
    bool keep = sel.selectPrefixes.empty();
    for( const std::string& p : sel.selectPrefixes )
    {
        if( lintPrefixMatches( p, name ) )
        {
            keep = true;
            break;
        }
    }
    if( !keep )
    {
        return false;
    }
    for( const std::string& p : sel.ignorePrefixes )
    {
        if( lintPrefixMatches( p, name ) )
        {
            return false;
        }
    }
    return true;
}

// Split "a,b,c" on commas, trimming ASCII space/tab around each token. Returns false on a malformed
// list (an empty token — a stray leading/trailing/doubled comma) rather than silently dropping it; an
// empty `raw` yields an empty `out` and true (nothing to split is not malformed).
inline bool splitLintPrefixList( std::string_view raw, std::vector<std::string>& out )
{
    out.clear();
    if( raw.empty() )
    {
        return true;
    }
    std::size_t start = 0;
    for( ;; )
    {
        const std::size_t comma = raw.find( ',', start );
        std::string_view  tok   = raw.substr( start, ( comma == std::string_view::npos ? raw.size() : comma ) - start );
        while( !tok.empty() && ( tok.front() == ' ' || tok.front() == '\t' ) )
        {
            tok.remove_prefix( 1 );
        }
        while( !tok.empty() && ( tok.back() == ' ' || tok.back() == '\t' ) )
        {
            tok.remove_suffix( 1 );
        }
        if( tok.empty() )
        {
            return false;
        }
        out.emplace_back( tok );
        if( comma == std::string_view::npos )
        {
            return true;
        }
        start = comma + 1;
    }
}

// "did you mean" over a RULE-NAME pool (the static catalog ∪ whatever user rule ids --lint-rules just
// loaded) — src/didyoumean.h's nearestNameByEditDistance() (the SAME bounded-edit-distance + tie-break
// core didYouMean() uses for symbol lookups), just pointed at a different pool via an identity nameOf.
// The three multi-rule family stems (atom-/cache-/naming-) ride in the pool alongside full rule names so
// a truncated-prefix typo ("cach-") lands on the family it meant instead of an arbitrarily-chosen member.
inline std::string lintNameNearMiss( const std::vector<std::string_view>& pool, std::string_view typed )
{
    constexpr int           kMaxEditDistance = 3;
    const std::string_view  best = nearestNameByEditDistance( pool.begin(), pool.end(), typed, kMaxEditDistance,
                                                               []( std::string_view n ) { return n; } );
    return std::string( best );
}

// The three repeated hyphenated family stems in kLintCatalog — read off the registry itself (every name
// starting with one of these has ≥2 members), not a second, independently-typed list.
inline constexpr std::array<std::string_view, 3> kLintFamilyStems = { { "atom-", "cache-", "naming-" } };

}   // namespace rw::lintcatalog
