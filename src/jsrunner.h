#pragma once

// jsrunner.h — #323: TS/JS test-runner evidence. Before this file, testmap.h's TestRunnerIndex derived a
// runner for exactly two script kinds (bash .sh, python3/pytest .py) — no .ts/.js/.tsx/.jsx entry existed,
// so every TS/JS test row carried run_unknown="1" forever (testmap.h's own M21(b) disclosure), even after
// the suite had been run and passed. The reporter's own measurement: 154 of 154 --test-gate runs over three
// days on a vitest project hit this, because the gate exits 4 whenever the tests-to-run list is non-empty
// and no TS/JS row could ever clear it.
//
// EVIDENCE, NEVER A GUESS — same rule pythonrunner.h already applies to Python: a runner is derived ONLY
// from bytes actually present in the repo (here, the nearest package.json's own "scripts"/"dependencies"/
// "devDependencies"), and an absent or inconclusive manifest yields NO command, exactly like a Python test
// file with no main-guard and no pytest project — testmap.h's runHint family turns that "" into
// run_unknown="1", never a fabricated default. The three cases this derives are the three the issue names
// and nothing else: `vitest` or `jest` named as a scripts.test runner or a dependency/devDependency ⇒ the
// corresponding CLI invocation; a scripts.test that runs node's OWN built-in runner (`node --test`) names
// itself directly — there is no package to depend on for it.
//
// NEAREST MANIFEST, WALKING UP (mirrors pythonrunner::hasPytestProject exactly): monorepo/workspace layouts
// are common (the issue's own point 1), so the search starts at the test file's own directory and climbs to
// the crawl root, inclusive, stopping at the first package.json found. The command is still spelled ROOT-
// RELATIVE, same as every other run= this codebase emits (testmap.h::spellUncached) — a package.json found
// in a subdirectory is evidence of WHICH runner, not a cd target; running the emitted command may need the
// reader's own shell to be inside that subdirectory on a workspace where the runner is not hoisted to the
// crawl root's node_modules. That is a stated scope limit (see the fix report), not a silent one: it is the
// SAME limit testmap.h's Python branch already carries (a nested pyproject.toml is evidence, not a `cd`).
//
// LANGUAGE NEUTRALITY (BRIEF_COMMON, standing house rule): the mechanism — walk up from a test file to the
// nearest project manifest and read its OWN declared scripts/dependencies as evidence, never guess — is the
// same shape pythonrunner.h already uses for Python (nearest pytest config) and the one testmap.h's shell
// branch trivially satisfies (a runnable script IS its own runner, no manifest needed). It is NOT extended
// here to the other languages testmap.h indexes test files for (Kotlin, Java, Ruby, Go, Rust, Swift, C#,
// Bash beyond .sh): Bash's .sh case above already has a runner (verb="bash", no evidence needed beyond the
// extension); Kotlin/Java build their test command from Gradle/Maven, not a single JSON manifest this file's
// shape can read; Ruby's is a Gemfile plus a Rakefile, same shape gap; Go's `go test` needs no manifest
// evidence at all (there is only ever the one command, so `go.mod`'s presence would be sufficient, but no
// issue reports that gap and it is out of scope for #323, which is TS/JS only); Rust/Swift/C# were not
// reported and are not audited here. This is a stated scope limit, not a silent one — see the fix report.
//
// #60 (train 20): a repo can have NO package.json at all (the reporter's own repro: one source file, one
// node:test-based test file, nothing else) — in which case the walk above finds no manifest, decides
// nothing, and the row stayed run_unknown="1" forever, even though the test file names its own runner in
// its own bytes (`import test from "node:test"`, `require("node:test")`). That is evidence about the FILE,
// the same kind pythonrunner::hasMainGuard already reads for Python's main-guard case, so `hasNodeTestImport`
// below re-parses the test file with its own grammar (never a substring scan — a "node:test" mention inside
// a comment or an unrelated string literal is not a real import) and is consulted ONLY as a FALLBACK, after
// `nearestPackageJson`'s own evidence has had its say: an authoritative-but-unrecognized `scripts.test`
// (mocha, say) still wins and is never overridden by this weaker, file-local evidence (the same F2 rule
// `detectFramework` already applies one level up, restated at this new layer) — see resolveJsVerb's own
// caller comment in testmap.h.
//
// rv-nodetest-runner-60 fix round: a `run=` command that FAILS is worse than an honest `run_unknown="1"`
// (the owner's own rule for this re-sign) — the first cut of this file derived `node --test`/the flagged
// form too eagerly, in three shapes that fail on every Node the tool could possibly mean:
//
// F1 — `.tsx`/`.jsx` can never be spelled. Node's type stripping does not handle `.tsx` at all
// (`ERR_UNKNOWN_FILE_EXTENSION`), and plain `node` cannot LOAD a `.jsx` file either (same error, no
// flag fixes it). `nodeTestVerb` refuses both extensions outright — `run_unknown="1"`, the base
// behaviour, not a command that fails on every Node line.
//
// F2 — a TS test file's own relative imports can make even a syntactically fine command unrunnable.
// Node's module resolver (ESM under type stripping, and CJS `require` under it too) never probes an
// extension and never maps a `.js` specifier onto a `.ts` source — both are exactly how tsc-, tsx- and
// bundler-run TS code imports its own siblings. So a `.ts`/`.mts`/`.cts` command is derived only when
// EVERY relative (`./`/`../`) static `import`/`export … from`/`require(...)` specifier the test file's
// own bytes name resolves to a real file at EXACTLY that path — `relativeImportsResolvable` below, walking
// the same grammar `hasNodeTestImport` already re-parses with. Anything else (extensionless, or an
// extension that does not exist on disk) is `run_unknown="1"`: the file's own bytes already prove the
// command would fail, so this is read off the parse, never guessed.
//
// F3 — the flag itself needs a Node new enough to accept it. `--experimental-strip-types` exists from
// Node 22.6 only; type stripping is ON BY DEFAULT (the flag becomes a harmless no-op) from 22.18 and from
// 23.6 — two separate release lines, not one continuous floor: 23.6 turned it on first, the 22.x line got
// it later by backport (22.18), and 23.0-23.5 do not have it. So a `.ts`/`.mts`/`.cts` command reads
// `engines.node` from the SAME nearest manifest (if any) and picks one of three answers, never a fourth
// guess: the bare form when the floor
// proves every satisfying Node is new enough to have stripping on by default; the flagged form when the
// floor proves >= 22.6 but not provably default-on; and `run_unknown="1"` when the floor is below 22.6
// (an explicit `engines.node` that admits an older Node — `>=18`, `^20`, even a compound `>=24 || ^20`,
// whose LOWEST admitted version is what decides it) or when the range cannot be read with confidence at
// all. An ABSENT `engines.node` is not "no constraint" here — it is read as the honest default assumption
// (Node >= 22.6, the flagged form), documented as exactly that, never claimed to be foolproof. See
// `nodeTestVerb`, `relativeImportsResolvable` and `typeStrippingDecision` below.

#include "docparse.h"
#include "infra/Diagnostics.h" // ASSUME — the same raw-reparse contract pythonrunner.h's hasMainGuard uses
#include "infra/dirwalk.h"    // ascendToRoot — the ONE nearest-config walk, shared with pythonrunner.h
#include "infra/fieldid.h"    // fieldChild/NodeField — the ONE field-lookup pythonrunner.h/ingest_jsimports.h share
#include "infra/jsonesc.h"    // jsonStringEnd — the ONE escape-aware JSON string walk, applied inline below (see detail's banner)
#include "infra/namesplit.h"  // isIdentChar / containsWordBoundedBy — the shared ident-byte test and word-boundary scan
#include "infra/nodekind.h"   // kindIs — grammar-string compare without a libc call (per nodekind.h's own banner)
#include "infra/tschildren.h" // ChildCursor/appendChildren — the ONE DFS-stack child-walk shape (tschildren.h's own banner)
#include "pattern.h"          // pattern::stripQuotePair — the ONE quote-strip this and importSpecifierText both apply

#include <filesystem>
#include <limits>
#include <string>
#include <string_view>
#include <vector>

// #60: re-parsed here with the SAME raw-reparse contract pythonrunner.h's hasMainGuard already uses (a
// fresh TSParser over the file's own bytes, independent of the ingest walk that parsed it once already and
// keeps no tree around for a caller this late) — never a second, ingest.cpp-private grammar table. Declared
// extern "C" at file scope, matching pythonrunner.h's tree_sitter_python/tree_sitter_toml pair and
// verbs_doctor.h's identical trio for these three JS/TS/TSX grammars.
extern "C"
{
    const TSLanguage* tree_sitter_javascript( void );
    const TSLanguage* tree_sitter_typescript( void );
    const TSLanguage* tree_sitter_tsx( void );
}

namespace rw::jsrunner
{

namespace detail
{

// Every "advance p past this JSON string" site below (p at s[p]=='"', the caller's own guard) applies
// rw::jsonStringEnd (infra/jsonesc.h) — the canonical escape-aware JSON string scan eval.h and mcpjson.h
// already share — INLINE, as `p = ( close == npos ) ? s.size() : close + 1`: a byte after the closing
// quote, or the end when unterminated (the same "no more evidence" degrade an unparseable file already
// gets, never a crash). Not wrapped in a fourth named function: eval.h::minedjson::skipString and
// mcpjson.h::mcpdetail::stringEnd are the two existing thin wrappers around this same walk, one clamped
// to size() and one returning npos for a different caller's truncation check — a third wrapper with
// the SAME clamp-to-size() convention as the first duplicates it outright (measured: --quality-delta
// flagged exactly that pairing), so this file's three call sites apply the two-line clamp themselves.

// Read the JSON string starting at `p` (the opening quote) and advance `p` past its closing quote.
// Minimal unescaping (the same "keep the byte after a backslash" rule resolve.h::parseTsconfigPaths uses) —
// package.json keys and the evidence values this file compares are all plain ASCII in every real corpus.
inline std::string readQuoted( std::string_view s, std::size_t& p )
{
    std::string out;
    if( p >= s.size() || s[p] != '"' )
    {
        return out;
    }
    ++p;
    while( p < s.size() && s[p] != '"' )
    {
        if( s[p] == '\\' && p + 1 < s.size() )
        {
            out.push_back( s[p + 1] );
            p += 2;
            continue;
        }
        out.push_back( s[p] );
        ++p;
    }
    if( p < s.size() )
    {
        ++p;
    }
    return out;
}

// The byte range (begin,end) of the FIRST top-level `"key": { ... }` object VALUE in `json` — package.json's
// own top level ("scripts", "dependencies", "devDependencies" are SIBLINGS, never nested in one another), so
// only a depth-1 key is a match; a same-named key inside some other object (e.g. a "scripts" key nested
// inside an unrelated config blob) is not evidence. A non-object value (or an absent key) yields npos/npos.
struct ObjSpan
{
    std::size_t begin = std::string_view::npos;
    std::size_t end   = std::string_view::npos;
};

inline ObjSpan topLevelObjectBody( std::string_view json, std::string_view key )
{
    std::size_t p     = 0;
    int         depth = 0;
    while( p < json.size() )
    {
        const char c = json[p];
        if( c == '"' )
        {
            const std::string k = readQuoted( json, p );
            if( depth == 1 && k == key )
            {
                std::size_t colon = json.find( ':', p );
                if( colon == std::string_view::npos )
                {
                    return {};
                }
                std::size_t v = colon + 1;
                while( v < json.size() && ( json[v] == ' ' || json[v] == '\t' || json[v] == '\n' || json[v] == '\r' ) )
                {
                    ++v;
                }
                if( v >= json.size() || json[v] != '{' )
                {
                    return {};   // scripts/dependencies must be an object; anything else is not this shape
                }
                const std::size_t objStart = v + 1;
                int                d       = 0;
                for( ; v < json.size(); ++v )
                {
                    if( json[v] == '"' )
                    {
                        const std::size_t close = rw::jsonStringEnd( json, v );
                        v = ( close == std::string_view::npos ) ? json.size() : close + 1;
                        --v;   // the for-loop's ++v re-lands exactly past the string
                        continue;
                    }
                    if( json[v] == '{' )
                    {
                        ++d;
                    }
                    else if( json[v] == '}' )
                    {
                        --d;
                        if( d == 0 )
                        {
                            return { objStart, v };
                        }
                    }
                }
                return {};   // unterminated object: malformed input, no evidence
            }
            continue;   // p already advanced past this string by readQuoted
        }
        if( c == '{' || c == '[' )
        {
            ++depth;
        }
        else if( c == '}' || c == ']' )
        {
            --depth;
        }
        ++p;
    }
    return {};
}

// Whether `body` (an object's byte span, exclusive of its braces) declares `name` as one of its OWN keys.
// Values are skipped whole (string or otherwise) so a version specifier that happens to contain `name` as a
// substring (a scoped package, a git URL) is never mistaken for a key match.
inline bool hasKey( std::string_view body, std::string_view name )
{
    std::size_t p = 0;
    while( p < body.size() )
    {
        while( p < body.size() && ( body[p] == ' ' || body[p] == '\t' || body[p] == '\n' || body[p] == '\r' || body[p] == ',' ) )
        {
            ++p;
        }
        if( p >= body.size() || body[p] != '"' )
        {
            break;   // not a key-shaped byte: malformed or exhausted — no more evidence to read
        }
        const std::string key = readQuoted( body, p );
        const std::size_t colon = body.find( ':', p );
        if( colon == std::string_view::npos )
        {
            break;
        }
        p = colon + 1;
        while( p < body.size() && ( body[p] == ' ' || body[p] == '\t' ) )
        {
            ++p;
        }
        if( key == name )
        {
            return true;
        }
        if( p < body.size() && body[p] == '"' )
        {
            const std::size_t close = rw::jsonStringEnd( body, p );
            p = ( close == std::string_view::npos ) ? body.size() : close + 1;
        }
        else
        {
            while( p < body.size() && body[p] != ',' && body[p] != '}' )   // a non-string value: skip to its end
            {
                ++p;
            }
        }
    }
    return false;
}

// The string VALUE of `body`'s `key` entry, or "" when absent or not a string (an object/array/number test
// script is not a shape this tool spells, and "" is exactly the "no evidence" reading every other caller here
// already uses for an absent field).
inline std::string stringValue( std::string_view body, std::string_view key )
{
    std::size_t p = 0;
    while( p < body.size() )
    {
        while( p < body.size() && ( body[p] == ' ' || body[p] == '\t' || body[p] == '\n' || body[p] == '\r' || body[p] == ',' ) )
        {
            ++p;
        }
        if( p >= body.size() || body[p] != '"' )
        {
            break;
        }
        const std::string k     = readQuoted( body, p );
        const std::size_t colon = body.find( ':', p );
        if( colon == std::string_view::npos )
        {
            break;
        }
        p = colon + 1;
        while( p < body.size() && ( body[p] == ' ' || body[p] == '\t' ) )
        {
            ++p;
        }
        const bool isStr = p < body.size() && body[p] == '"';
        if( k == key )
        {
            return isStr ? readQuoted( body, p ) : std::string();
        }
        if( isStr )
        {
            const std::size_t close = rw::jsonStringEnd( body, p );
            p = ( close == std::string_view::npos ) ? body.size() : close + 1;
        }
        else
        {
            while( p < body.size() && body[p] != ',' && body[p] != '}' )
            {
                ++p;
            }
        }
    }
    return {};
}

// rv-test-gate-tsjs F2: a byte that can continue an identifier/path SEGMENT — used to bound a word match
// so "jest" inside "jest-report-cleaner.js" (a FILENAME) is not mistaken for a "run jest" command. Built
// on rw::namesplit::isIdentChar (the ONE ASCII identifier-byte test) plus '-', the one byte this caller
// needs beyond it: darkflags.h's own identByte (planlint.h's word-boundary user) does NOT count '-' as a
// word byte, which is the wrong reading here — a hyphenated CLI token is one word, not two.
inline bool isWordByte( char c ) noexcept
{
    return rw::namesplit::isIdentChar( c ) || c == '-';
}

/// Whether `word` occurs in `text` bounded on BOTH sides by a non-word byte or the string edge — "vitest"
/// matches in "npx vitest run" (space both sides) and in "node_modules/.bin/jest" (a path separator, then
/// the string end), never in "jest-report-cleaner.js" (a '-' immediately follows) or "myvitest" (a letter
/// immediately precedes). rv-test-gate-tsjs F2: a runner name matched as a SUBSTRING of an unrelated token
/// is not evidence the script text was ever ".find()"-shaped for before this fix. The scan itself is
/// rw::namesplit::containsWordBoundedBy — the SAME walk planlint.h::containsWholeWord already uses, over
/// this file's own boundary predicate (see isWordByte's own comment for why the two predicates differ).
inline bool matchesWord( std::string_view text, std::string_view word )
{
    return rw::namesplit::containsWordBoundedBy( text, word, isWordByte );
}

/// The string value of package.json's top-level `objectKey.fieldKey` (`"scripts"."test"`,
/// `"engines"."node"`) — the ONE "read a nested top-level field" shape `testScript` and `enginesNode` both
/// need, factored out once rather than each re-deriving it (measured: --quality-delta's duplication kind).
inline std::string nestedStringValue( std::string_view packageJson, std::string_view objectKey, std::string_view fieldKey )
{
    const ObjSpan obj = topLevelObjectBody( packageJson, objectKey );
    if( obj.begin == std::string_view::npos )
    {
        return {};
    }
    return stringValue( packageJson.substr( obj.begin, obj.end - obj.begin ), fieldKey );
}

} // namespace detail

/// Whether `dependencies` or `devDependencies` (either one — testmap.h's callers do not care which) names
/// `pkg` as a declared package. package.json bytes are external input; unparseable or absent input reads as
/// "no evidence", the same degrade the caller (detectFramework) already returns for every other miss.
inline bool hasDependency( std::string_view packageJson, std::string_view pkg )
{
    for( std::string_view key : { std::string_view( "dependencies" ), std::string_view( "devDependencies" ) } )
    {
        const detail::ObjSpan obj = detail::topLevelObjectBody( packageJson, key );
        if( obj.begin != std::string_view::npos && detail::hasKey( packageJson.substr( obj.begin, obj.end - obj.begin ), pkg ) )
        {
            return true;
        }
    }
    return false;
}

/// The literal `scripts.test` command string, or "" when package.json has no such field.
inline std::string testScript( std::string_view packageJson )
{
    return detail::nestedStringValue( packageJson, "scripts", "test" );
}

// The three runners #323 names, and nothing else — a fourth framework (mocha, ava, tap, jasmine…) is a
// bigger ask than "a package.json reader" and stays run_unknown="1" until its own issue asks for it (the
// issue's own wording: "any ONE of these would help", not "every framework").
enum class Framework : std::uint8_t { None, Vitest, Jest, NodeTest };

// npm's own generated placeholder (`npm init`'s default `scripts.test`) — present, but not really a script
// a human wrote, so it reads the same as "absent" for evidence purposes (rv-test-gate-tsjs F2). The named
// `marker` local (not a bare one-line `return x.find(y) != npos`) is deliberate: a bare return of that
// exact shape structurally matched three UNRELATED substring checks elsewhere in the tree
// (taskroute::has, verbs_for.h's forCoverageAttrPresent/forRouteAttrPresent) under --quality-delta's
// duplication kind — the same false-positive class infra/dirwalk.h's own banner already documents fixing
// for pythonrunner::hasPytestProject, not a real clone of any of those three unrelated checks.
inline bool isNpmPlaceholderScript( std::string_view script ) noexcept
{
    constexpr std::string_view marker = "Error: no test specified";
    return script.find( marker ) != std::string_view::npos;
}

/// rv-test-gate-tsjs G1: whether `packageJson` has a REAL `scripts.test` — non-empty, not npm's own
/// placeholder — regardless of whether that script names a runner this file recognizes. This is a
/// DIFFERENT question from `detectFramework(...) != Framework::None`: a manifest whose `scripts.test`
/// authoritatively runs mocha (unrecognized) and a manifest with NO `scripts.test` at all both return
/// `Framework::None`, but only the first has actually DECIDED anything for its subtree — the second is a
/// pure marker (a bare `{"type":"commonjs"}`) with nothing to decide. `nearestPackageJson` below needs to
/// tell those apart: the first must END the walk (its own unrecognized runner is the honest answer,
/// never overridable by a root manifest naming something else — F2's own rule, one level up), the second
/// must not (F5's whole point).
inline bool hasAuthoritativeScript( std::string_view packageJson )
{
    const std::string script  = testScript( packageJson );
    const bool        isEmpty = script.empty();
    if( isEmpty )
    {
        return false;   // no scripts.test at all: nothing here to be authoritative about
    }
    return !isNpmPlaceholderScript( script );
}

/// Evidence-only framework detection. rv-test-gate-tsjs F2: a NON-EMPTY, non-placeholder `scripts.test` is
/// AUTHORITATIVE — the script IS what a CI run of `npm test` executes, so once it names something, that
/// something (or nothing recognized) is the answer, and a same-named DEPENDENCY never overrides it (a repo
/// can depend on vitest for its config types while `scripts.test` runs mocha; a scripts.test that runs some
/// OTHER file whose path happens to contain "jest" is not a jest invocation either — matchesWord bounds
/// both). Dependencies are consulted ONLY when there is no real scripts.test to read: absent, empty, or
/// npm's own placeholder. node's OWN test runner has no package to depend on, so it is recognized ONLY by
/// its scripts.test spelling, inside the authoritative branch.
inline Framework detectFramework( std::string_view packageJson )
{
    const std::string script = testScript( packageJson );
    if( !script.empty() && !isNpmPlaceholderScript( script ) )
    {
        if( detail::matchesWord( script, "vitest" ) )
        {
            return Framework::Vitest;
        }
        if( detail::matchesWord( script, "jest" ) )
        {
            return Framework::Jest;
        }
        if( script.find( "node --test" ) != std::string::npos || script.find( "node --experimental-test-runner" ) != std::string::npos )
        {
            return Framework::NodeTest;
        }
        return Framework::None;   // scripts.test names something else entirely — never overridden by a dependency guess
    }
    if( hasDependency( packageJson, "vitest" ) )
    {
        return Framework::Vitest;
    }
    if( hasDependency( packageJson, "jest" ) )
    {
        return Framework::Jest;
    }
    return Framework::None;   // no scripts.test, no vitest/jest dependency: undecidable
}

/// Whether `path` matches vitest/jest's own default include-glob SHAPE — `.test.`/`.spec.` in the filename,
/// or a `__tests__/` directory segment — and never a bare `.d.ts` declaration file. rv-test-gate-tsjs F4:
/// isTestPath (filter.h) is deliberately BROADER (any file under a `test/`/`tests/` directory), which is
/// right for "code a test author wrote" but wrong for "a file vitest/jest itself would collect as a test
/// target" — a helper or a setup file living beside real tests matches isTestPath but not either runner's
/// own glob, so spelling `npx vitest run test/setup.ts` would fail with "no test files found" in CI.
///
/// rv-test-gate-tsjs G2 (delta review — fixed, not left as a follow-up): this function is only ever
/// CALLED on a path isTestPath already accepted (TestRunnerIndex's own candidate gate, testmap.h).
/// isTestPath (filter.h) now recognizes a bare `__tests__/` directory segment too (the SAME fix, applied
/// where every other verb reaches it, since isTestPath is the one shared test-path convention this whole
/// tool uses — not duplicated here), so the `__tests__/` branch below is reachable for a bare
/// `src/__tests__/foo.js` (jest's own default convention, no `.test.` in the name) exactly as it already
/// was for `src/__tests__/foo.test.ts`. jest's OTHER default pattern half — a bare `test.js`/`spec.js`
/// filename with no leading dot or underscore — is a narrower, separate gap neither isTestPath nor this
/// function closes; stated, not silent.
inline bool looksLikeJsTestFile( std::string_view path ) noexcept
{
    if( path.ends_with( ".d.ts" ) )
    {
        return false;   // a TypeScript declaration file — never test code, whatever the rest of its name is
    }
    const std::size_t slash = path.rfind( '/' );
    const std::string_view fn = ( slash == std::string_view::npos ) ? path : path.substr( slash + 1 );
    if( fn.find( ".test." ) != std::string_view::npos || fn.find( ".spec." ) != std::string_view::npos )
    {
        return true;
    }
    // a whole __tests__ directory SEGMENT, bounded by '/' or the path's own edges (never a substring hit
    // inside a longer directory name like "my__tests__stuff/")
    std::size_t pos = 0;
    while( ( pos = path.find( "__tests__/", pos ) ) != std::string_view::npos )
    {
        if( pos == 0 || path[pos - 1] == '/' )
        {
            return true;
        }
        ++pos;
    }
    return false;
}

/// The CLI verb for a detected framework, or nullptr for `Framework::None` — nullptr propagates to testmap.h
/// as "no runner", the same contract runnerVerb() already uses for an unrecognized extension. A table, not a
/// switch, matching testmap.h::runnerVerb's own kRunnerKinds shape (a small sorted-by-nothing row scan reads
/// identically to a switch but is a DIFFERENT shape than model.h::jsLitCtorName's enum switch beside it).
inline const char* verbFor( Framework fw ) noexcept
{
    struct FrameworkVerb { Framework fw; const char* verb; };
    static constexpr FrameworkVerb kFrameworkVerbs[] = {
        { Framework::Vitest,   "npx vitest run" },
        { Framework::Jest,     "npx jest" },
        { Framework::NodeTest, "node --test" },
    };
    for( const FrameworkVerb& fv : kFrameworkVerbs )
    {
        if( fv.fw == fw )
        {
            return fv.verb;
        }
    }
    return nullptr;   // Framework::None, or a byte past the enum: never a guessed verb
}

/// Search from `file`'s own directory through `root`, inclusive, for the nearest package.json that can
/// actually DECIDE a framework, and return its bytes — or, failing that, the nearest package.json found at
/// all (so a caller still reads its honest "names none of the three" rather than a silent miss), or "" when
/// none exists anywhere in the boundary. The walk is rw::dirwalk::ascendToRoot (shared with
/// pythonrunner::hasPytestProject — same boundary and symlink rules). Monorepo/workspace test files are
/// common (the issue's own point 1), so the search starts at the test file, not at the crawl root.
///
/// rv-test-gate-tsjs F5: a package.json with no scripts/dependencies evidence at all — a bare module-type
/// marker (`{"type":"commonjs"}`) is a real, common pattern in mixed-module repos — used to END the search
/// even though it decides nothing; the walk now keeps climbing past it toward a manifest that CAN decide
/// (a workspace root's runner is hoisted to every package under it anyway, so the root manifest is exactly
/// the right fallback).
///
/// rv-test-gate-tsjs G1 (a regression the F5 fix above introduced): "decides nothing" is NOT the same
/// test as `detectFramework(...) == Framework::None` — that also fires for a manifest whose OWN
/// `scripts.test` authoritatively names an unrecognized runner (mocha, say), and climbing past THAT one
/// let an unrelated root manifest's `jest`/`vitest` override a subtree that had already answered for
/// itself (F2's own rule, one level up the tree, is exactly what this fix restores). The walk now stops
/// at ANY manifest with a real `scripts.test` (`hasAuthoritativeScript`), recognized or not, and climbs
/// past only a manifest with neither a real script NOR a decisive dependency — a true marker.
///
/// The one case this file DOES treat as deciding, on purpose, pinned here rather than left implicit: a
/// manifest with NO `scripts.test` but a `vitest`/`jest` DEPENDENCY already makes `detectFramework`
/// return non-`None` (the dependency-fallback branch), so it already stops the walk under the plain
/// `decided` check below — a dependency with nothing wiring it into `scripts.test` is still read as this
/// package's own evidence, not deferred to a root manifest. `test/testgatecheck.sh` arm (p1)
/// (`fx/mochavitestdep`, mocha script + vitest dependency, single package) already pins the single-
/// package half of this; monorepo arm (u2) below pins that the SAME rule holds one level up a tree.
inline std::string nearestPackageJson( const std::string& file, std::string_view root )
{
    namespace fs = std::filesystem;
    std::string fallback;   // the NEAREST manifest found, even if it decides nothing (F5)
    std::string decisive;
    rw::dirwalk::ascendToRoot( file, root, [ & ]( const fs::path& dir )
    {
        std::error_code sec;
        const fs::path candidate = dir / "package.json";
        if( !fs::is_regular_file( fs::symlink_status( candidate, sec ) ) )   // never follow a manifest symlink out of the project
        {
            return false;
        }
        std::string bytes = docparse::detail::readWholeFile( candidate.string() ).value_or( "" );
        if( bytes.empty() )
        {
            return false;
        }
        if( fallback.empty() )
        {
            fallback = bytes;
        }
        const bool decided = detectFramework( bytes ) != Framework::None;
        if( !decided && !hasAuthoritativeScript( bytes ) )
        {
            return false;   // F5: a true marker (no script, no decisive dependency) decides nothing HERE
        }
        decisive = std::move( bytes );   // G1: an authoritative-but-unrecognized script also ends the walk
        return true;
    } );
    return decisive.empty() ? fallback : decisive;
}

// ---------------------------------------------------------------------------------------------------------
// #60 (train 20): the test file's OWN node:test import/require, consulted ONLY when nearestPackageJson's
// manifest evidence decided nothing for this file (see this section's own banner above, and resolveJsVerb's
// caller comment in testmap.h for the precedence wiring).
// ---------------------------------------------------------------------------------------------------------

namespace detail
{

/// The grammar `path`'s own extension selects, reduced to the three this file re-parses with (the same
/// ".ts"/".mts"/".cts" -> typescript, ".tsx" -> tsx, else javascript split ingest_crawl.h's kLangTable
/// uses for the full crawl — jsx parses natively under the plain javascript grammar, same as there).
inline const TSLanguage* grammarForPath( std::string_view path ) noexcept
{
    if( path.ends_with( ".tsx" ) )
    {
        return tree_sitter_tsx();
    }
    if( path.ends_with( ".ts" ) || path.ends_with( ".mts" ) || path.ends_with( ".cts" ) )
    {
        return tree_sitter_typescript();
    }
    return tree_sitter_javascript();   // .js/.jsx/.mjs/.cjs
}

/// The string VALUE of a `string` node (never a template string — a computed specifier proves nothing, the
/// same reading ingest_relations.h::jsModuleLoadTarget already gives it) — its one quote pair stripped,
/// single or double, either quote style. The stripping IS ingest_relations.h::importSpecifierText's own
/// two-line strip (that function is ingest.cpp-private and this file re-parses independently, so the two
/// cannot call one another directly) — factored out once, as `pattern::stripQuotePair`, rather than a
/// second hand-rolled copy (measured: --quality-delta's duplication kind). A template string (or any other
/// node kind) is never a static specifier and yields "".
inline std::string stringLiteralValue( TSNode node, std::string_view src ) noexcept
{
    if( !rw::kindIs( ts_node_type( node ), "string" ) )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( node ), b = ts_node_end_byte( node );
    if( a >= b || b > src.size() )
    {
        return {};
    }
    return std::string( pattern::stripQuotePair( src.substr( a, b - a ) ) );
}

/// Whether `node` is a `string` node whose value is exactly "node:test" — `isNodeTestStringLiteral` is
/// `stringLiteralValue`'s own null-and-non-string cases folded into ONE comparison, not a second hand-rolled
/// walk (measured: --quality-delta's duplication kind, the same reason `stringLiteralValue` itself factored
/// the quote-strip out of `nodeIsNodeTestEvidence` in the first place).
inline bool isNodeTestStringLiteral( TSNode node, std::string_view src ) noexcept
{
    return stringLiteralValue( node, src ) == "node:test";
}

/// Whether `node` is itself node:test EVIDENCE — an ES `import … from "node:test"` (any clause shape: the
/// source field alone decides it, never the imported names) or a CommonJS `require("node:test")` call
/// (bare `require` callee, exactly one argument, that argument a string — the same three conditions
/// ingest_relations.h::jsModuleLoadTarget applies to `require`/`import(...)` calls generally, narrowed here
/// to the one specifier this evidence cares about). A "node:test" byte sequence anywhere else — a comment,
/// an unrelated string, `"node:test/mock"` — is a DIFFERENT node kind or a different string value and never
/// matches either shape; this is the parse-based check the negative-control gate arm pins.
inline bool nodeIsNodeTestEvidence( TSNode node, std::string_view src ) noexcept
{
    if( rw::kindIs( ts_node_type( node ), "import_statement" ) )
    {
        const TSNode source = fieldChild( node, NodeField::Source );
        return !ts_node_is_null( source ) && isNodeTestStringLiteral( source, src );
    }
    if( rw::kindIs( ts_node_type( node ), "call_expression" ) )
    {
        const TSNode callee = fieldChild( node, NodeField::Function );
        if( ts_node_is_null( callee ) || !rw::kindIs( ts_node_type( callee ), "identifier" ) )
        {
            return false;
        }
        const std::uint32_t ca = ts_node_start_byte( callee ), cb = ts_node_end_byte( callee );
        if( ca >= cb || cb > src.size() || src.substr( ca, cb - ca ) != "require" )
        {
            return false;
        }
        const TSNode args = fieldChild( node, NodeField::Arguments );
        if( ts_node_is_null( args ) )
        {
            return false;
        }
        TSNode          only  = {};
        std::uint32_t   named = 0;
        rw::ChildCursor cursor( args );
        rw::forEachNamedChild( args, cursor.cur, [ & ]( TSNode c ) { only = c; ++named; return true; } );
        return named == 1 && isNodeTestStringLiteral( only, src );
    }
    return false;
}

/// rv-nodetest-runner-60 F2: append `node`'s own relative (`./`/`../`) STATIC specifier to `out`, if it has
/// one — an ES `import … from "…"` or `export … from "…"` (the source field alone decides it, same shape
/// `nodeIsNodeTestEvidence` already reads for `import_statement`, extended here to `export_statement`'s
/// re-export form) or a CommonJS `require("…")` call (the same bare-callee-plus-one-string-argument shape
/// `nodeIsNodeTestEvidence` already applies to `require`, not re-derived a second way). A non-relative
/// specifier (a bare package name, `"node:test"` itself, an alias) is not this function's concern —
/// resolveJsVerb never needs to resolve those on disk — so only `./`/`../`-prefixed text is collected.
/// A dynamic `import(...)` is deliberately NOT walked here: it is not a `call_expression` this function's
/// caller visits as import evidence at all (the SAME conservative miss `hasNodeTestImport`'s own banner
/// already accepts for a dynamic import as node:test evidence, restated here for the same node shape).
inline void collectRelativeSpecifiers( TSNode node, std::string_view src, std::vector<std::string>& out )
{
    const char* kind = ts_node_type( node );
    if( rw::kindIs( kind, "import_statement" ) || rw::kindIs( kind, "export_statement" ) )
    {
        const TSNode source = fieldChild( node, NodeField::Source );
        if( ts_node_is_null( source ) )
        {
            return;
        }
        std::string spec = stringLiteralValue( source, src );
        if( spec.starts_with( "./" ) || spec.starts_with( "../" ) )
        {
            out.push_back( std::move( spec ) );
        }
        return;
    }
    if( !rw::kindIs( kind, "call_expression" ) )
    {
        return;
    }
    const TSNode callee = fieldChild( node, NodeField::Function );
    if( ts_node_is_null( callee ) || !rw::kindIs( ts_node_type( callee ), "identifier" ) )
    {
        return;
    }
    const std::uint32_t ca = ts_node_start_byte( callee ), cb = ts_node_end_byte( callee );
    if( ca >= cb || cb > src.size() || src.substr( ca, cb - ca ) != "require" )
    {
        return;
    }
    const TSNode args = fieldChild( node, NodeField::Arguments );
    if( ts_node_is_null( args ) )
    {
        return;
    }
    TSNode          only  = {};
    std::uint32_t   named = 0;
    rw::ChildCursor cursor( args );
    rw::forEachNamedChild( args, cursor.cur, [ & ]( TSNode c ) { only = c; ++named; return true; } );
    if( named != 1 )
    {
        return;
    }
    std::string spec = stringLiteralValue( only, src );
    if( spec.starts_with( "./" ) || spec.starts_with( "../" ) )
    {
        out.push_back( std::move( spec ) );
    }
}

} // namespace detail

/// #60: whether `source` (the bytes of a TS/JS test file at `path`) itself imports or requires node's own
/// "node:test" module — checked by re-parsing `source` with the grammar `path`'s extension selects and
/// walking the WHOLE tree (a DFS stack, `infra/tschildren.h::appendChildren`'s own documented shape),
/// never a substring scan: a "node:test" mention inside a comment or an unrelated string literal is not an
/// import and must not count (the negative-control gate arm pins this). Oversized input, a failed parse, or
/// any syntax error anywhere in the file yields NO evidence — the same conservative read
/// pythonrunner::topLevelEvidence already applies to Python's main-guard scan, applied here to a whole-tree
/// walk instead of a top-level-only one (a `require("node:test")` can sit inside a function body, unlike an
/// ES `import`, which the grammar accepts only at top level regardless of source validity).
inline bool hasNodeTestImport( std::string_view source, std::string_view path )
{
    if( source.size() > std::numeric_limits<std::uint32_t>::max() )
    {
        return false;
    }
    TSParser* parser = ts_parser_new();
    ASSUME( parser != nullptr, "ts_parser_new: the default tree-sitter allocator aborts on failure" );
    const bool languageSet = ts_parser_set_language( parser, detail::grammarForPath( path ) );
    ASSUME( languageSet, "the javascript/typescript/tsx grammars are linked into this binary at a supported ABI" );
    TSTree* tree = ts_parser_parse_string( parser, nullptr, source.data(), std::uint32_t( source.size() ) );
    ts_parser_delete( parser );
    if( tree == nullptr )
    {
        return false;   // an external-scanner error on this text: no evidence, never a guessed runner
    }
    const TSNode root = ts_tree_root_node( tree );
    bool         found = false;
    if( !ts_node_has_error( root ) )
    {
        std::vector<TSNode> pending{ root };
        while( !pending.empty() )
        {
            const TSNode node = pending.back();
            pending.pop_back();
            if( detail::nodeIsNodeTestEvidence( node, source ) )
            {
                found = true;
                break;
            }
            rw::ChildCursor cursor( node );
            rw::appendChildren( node, cursor.cur, pending );
        }
    }
    ts_tree_delete( tree );
    return found;
}

/// rv-nodetest-runner-60 F2: whether EVERY relative (`./`/`../`) static specifier `source` (a TS test file
/// at `path`, on disk at `diskPath`) names resolves to a REAL file at EXACTLY that path — Node's module
/// resolver, under type stripping, never probes an extension and never maps a `.js` specifier onto a `.ts`
/// source, so an extensionless specifier (`"../src/bounded"`) or one whose exact extension does not exist
/// on disk (`"../src/bounded.js"` when only `bounded.ts` is there) is a command that fails outright before
/// a single test runs. This is read off the file's OWN bytes, the same re-parse `hasNodeTestImport` already
/// does (grammar by extension, whole-tree DFS, `ts_node_has_error`/oversized-input both answer "no
/// evidence") — extended here to collect specifiers instead of testing one fixed string. A file with NO
/// relative specifiers at all (every import is a bare package, or there are none) has nothing to fail on
/// and reads true — vacuously resolvable, not "no evidence".
///
/// Deliberately NOT recursive: only the test file's OWN specifiers are checked, never what `bounded.ts`
/// itself goes on to import — the same one-hop scope `nodeIsNodeTestEvidence` already keeps (the file's own
/// bytes are the evidence; a second file's bytes are a second file's problem, out of scope for this repro
/// and this fix — see the fix report).
inline bool relativeImportsResolvable( std::string_view source, std::string_view path, std::string_view diskPath )
{
    if( source.size() > std::numeric_limits<std::uint32_t>::max() )
    {
        return false;
    }
    TSParser* parser = ts_parser_new();
    ASSUME( parser != nullptr, "ts_parser_new: the default tree-sitter allocator aborts on failure" );
    const bool languageSet = ts_parser_set_language( parser, detail::grammarForPath( path ) );
    ASSUME( languageSet, "the javascript/typescript/tsx grammars are linked into this binary at a supported ABI" );
    TSTree* tree = ts_parser_parse_string( parser, nullptr, source.data(), std::uint32_t( source.size() ) );
    ts_parser_delete( parser );
    if( tree == nullptr )
    {
        return false;   // an external-scanner error on this text: no reliable evidence either way
    }
    const TSNode root = ts_tree_root_node( tree );
    if( ts_node_has_error( root ) )
    {
        ts_tree_delete( tree );
        return false;   // a syntax error anywhere: the same conservative "no evidence" hasNodeTestImport gives it
    }
    std::vector<std::string> specs;
    std::vector<TSNode>      pending{ root };
    while( !pending.empty() )
    {
        const TSNode node = pending.back();
        pending.pop_back();
        detail::collectRelativeSpecifiers( node, source, specs );
        rw::ChildCursor cursor( node );
        rw::appendChildren( node, cursor.cur, pending );
    }
    ts_tree_delete( tree );

    if( specs.empty() )
    {
        return true;   // nothing relative to resolve: vacuously fine, never a guess either way
    }
    namespace fs = std::filesystem;
    const fs::path dir = fs::path( std::string( diskPath ) ).parent_path();
    for( const std::string& spec : specs )
    {
        const std::size_t      lastSlash = spec.rfind( '/' );
        const std::string_view lastSeg = ( lastSlash == std::string::npos ) ? std::string_view( spec )
            : std::string_view( spec ).substr( lastSlash + 1 );
        if( lastSeg.find( '.' ) == std::string_view::npos )
        {
            return false;   // extensionless: Node's resolver under type stripping never probes for one
        }
        std::error_code ec;
        if( !fs::is_regular_file( fs::status( dir / spec, ec ) ) )
        {
            return false;   // the exact spelled path is not a real file — no probing, no .js -> .ts mapping
        }
    }
    return true;
}

/// The `engines.node` field's raw string value, or "" when absent — the same top-level-key + string-value
/// shape `testScript` already reads for "scripts"/"test", applied to "engines"/"node" instead. `packageJson`
/// may itself be "" (no manifest anywhere in the crawl boundary — the #60 repro exactly): topLevelObjectBody
/// on an empty string finds nothing, same as a manifest that simply omits the field.
inline std::string enginesNode( std::string_view packageJson )
{
    return detail::nestedStringValue( packageJson, "engines", "node" );
}

namespace detail
{

/// rv-nodetest-runner-60 F3: the FLOOR (as `major*1000 + minor`) a single, non-compound `engines.node`
/// range clause asserts, or `0` when this clause asserts NO usable lower bound at all — a `<`/`<=`-led
/// clause (asserts an UPPER bound only: the range could still admit an arbitrarily old Node, so treating it
/// as "no floor" rather than skipping it is what makes an alternative like `"<24"` alone correctly force
/// the conservative answer below, not silently pass through undecided) or a clause with no version number
/// this reader can find at all (unparseable ⇒ the SAME "admits anything" floor, never a guess in the other
/// direction). This is NOT a semver engine: it reads the FIRST major.minor pair as the floor, which is
/// exactly right for the shapes real package.json files use (">=X.Y[.Z]", "^X.Y[.Z]", "~X.Y[.Z]", a bare
/// "X.Y[.Z]", ">X.Y[.Z]" — patch-level exclusivity never changes a major.minor comparison).
inline long long engineFloorClause( std::string_view clause ) noexcept
{
    std::size_t p = 0;
    while( p < clause.size() && ( clause[p] == ' ' || clause[p] == '\t' ) )
    {
        ++p;
    }
    if( p < clause.size() && clause[p] == '<' )
    {
        return 0;   // an upper-bound-led clause asserts nothing about the floor: read as "admits anything"
    }
    while( p < clause.size() && !( clause[p] >= '0' && clause[p] <= '9' ) )   // skip '>=', '^', '~', '>', or nothing
    {
        ++p;
    }
    const auto readInt = [ & ]() -> long long
    {
        const std::size_t start = p;
        long long         v     = 0;
        while( p < clause.size() && clause[p] >= '0' && clause[p] <= '9' && p - start < 6 )
        {
            v = v * 10 + ( clause[p] - '0' );
            ++p;
        }
        return p == start ? -1 : v;
    };
    const long long major = readInt();
    if( major < 0 )
    {
        return 0;   // no version number found at all: unparseable, read as "admits anything"
    }
    long long minor = 0;
    if( p < clause.size() && clause[p] == '.' )
    {
        ++p;
        const long long m = readInt();
        minor = m < 0 ? 0 : m;
    }
    return major * 1000 + minor;
}

} // namespace detail

/// rv-nodetest-runner-60 F3: the LOWEST Node version `range` can possibly admit, as `major*1000 + minor` —
/// `-1` when `range` is empty (no `engines.node` field at all; the caller reads that differently from a
/// present-but-unbounded range, see `nodeTestVerb`). A compound range (`"a || b"`, npm's own OR syntax)
/// admits whichever alternative a reader's Node satisfies, so its floor is the MINIMUM over every `||`
/// alternative's own floor — "if the range can't be parsed confidently, fall back to run_unknown" (the
/// re-sign brief) falls out of this for free: an unparseable or upper-bound-only alternative reads as floor
/// `0` (`engineFloorClause`'s own contract), which pulls the whole compound range's minimum down to `0` —
/// exactly the "admits anything, including something ancient" answer that must refuse to derive.
inline long long enginesFloor( std::string_view range ) noexcept
{
    if( range.empty() )
    {
        return -1;
    }
    long long   floor = -1;
    std::size_t start = 0;
    while( true )
    {
        const std::size_t pos = range.find( "||", start );
        const std::string_view clause = range.substr( start, pos == std::string_view::npos ? range.size() - start : pos - start );
        const long long         f     = detail::engineFloorClause( clause );
        if( floor < 0 || f < floor )
        {
            floor = f;
        }
        if( pos == std::string_view::npos )
        {
            break;
        }
        start = pos + 2;
    }
    return floor;
}

// rv-nodetest-runner-60 F3: `--experimental-strip-types` exists from Node 22.6 only (an OLDER Node treats
// it as an unrecognized flag and refuses to start at all — the flag is not "sometimes unnecessary", it is
// sometimes a fatal error); type stripping is ON BY DEFAULT — the flag becomes a harmless no-op — from TWO
// separate floors, 22.18 and 23.6: 23.6 turned it on upstream first and the 22.x line got it later, by
// backport, in 22.18, so a bare 23.0-23.5 does NOT have it on by default even though it sorts after 22.18.
constexpr long long kFloor22_6  = 22 * 1000 + 6;
constexpr long long kFloor22_18 = 22 * 1000 + 18;
constexpr long long kFloor23_0  = 23 * 1000 + 0;
constexpr long long kFloor23_6  = 23 * 1000 + 6;
constexpr long long kFloor18_0  = 18 * 1000 + 0;   // node:test itself exists from Node 18 (plain JS floor)

/// rv-nodetest-runner-60 F3: the three-way answer an `engines.node` FLOOR gives for a `.ts`/`.mts`/`.cts`
/// command — bare (default-on stripping is guaranteed for every version the range admits), flagged
/// (>= 22.6 is guaranteed but default-on is not), or refused (the range admits something below 22.6, or
/// the floor could not be read with confidence at all, which `enginesFloor` already folds into the same
/// "admits anything" floor `0`). `floor == -1` is `enginesFloor`'s OWN sentinel for "no `engines.node`
/// field anywhere in the boundary" — distinct from a present-but-low floor — and is read as the honest
/// DEFAULT ASSUMPTION (Node >= 22.6), the flagged form, never proven and never claimed to be.
enum class StripDecision : std::uint8_t { Bare, Flagged, Unknown };

inline StripDecision typeStrippingDecision( long long floor ) noexcept
{
    if( floor >= 0 && floor < kFloor22_6 )
    {
        return StripDecision::Unknown;   // admits a Node where the flag itself is a fatal "bad option"
    }
    const bool bareOk = floor >= kFloor23_6 || ( floor >= kFloor22_18 && floor < kFloor23_0 );
    return bareOk ? StripDecision::Bare : StripDecision::Flagged;
}

/// rv-nodetest-runner-60: the command for node's own built-in test runner at `path`, on disk at `diskPath`
/// with source bytes `source` — decided ENTIRELY from evidence this repo actually carries, never a guess at
/// the Node version or the module graph that will actually run it. Returns `nullptr` for `run_unknown="1"`,
/// the SAME "no command" contract every other evidence miss in this file already uses:
///  * F1 — `.tsx`/`.jsx` can never be spelled: type stripping does not cover `.tsx`, and plain `node`
///    cannot load `.jsx` at all, on ANY Node version.
///  * F2 — a `.ts`/`.mts`/`.cts` file whose own relative imports/requires are not ALL resolvable exactly as
///    written (`relativeImportsResolvable`) is refused: the file's own bytes already prove the command
///    would fail before a single test runs.
///  * F3 — a `.ts`/`.mts`/`.cts` file's command additionally depends on `engines.node` (`enginesFloor` of
///    `enginesNode(packageJson)`): refused below a 22.6 floor, flagged in [22.6, 22.18) or [23.0, 23.6),
///    bare at >= 23.6 or in [22.18, 23.0). An ABSENT `engines.node` (`enginesFloor` returns `-1`, distinct
///    from a present-but-low floor) is read as the honest default assumption — Node >= 22.6 — and gets the
///    flagged form; this is documented as an assumption, not proven, because nothing in the repo says so.
///  * Plain `.js`/`.mjs`/`.cjs` never need type stripping, so `engines.node` only matters for the OTHER
///    direction: node:test itself exists from Node 18, so a range that admits something below 18 is
///    refused too; an absent `engines.node` carries no such admission and keeps the bare form.
inline const char* nodeTestVerb( std::string_view path, std::string_view packageJson, std::string_view source, std::string_view diskPath )
{
    if( path.ends_with( ".tsx" ) || path.ends_with( ".jsx" ) )
    {
        return nullptr;   // F1: never runnable, with or without a flag, on any Node
    }
    const bool isTs = path.ends_with( ".ts" ) || path.ends_with( ".mts" ) || path.ends_with( ".cts" );
    if( !isTs )
    {
        const long long floor = enginesFloor( enginesNode( packageJson ) );
        return ( floor >= 0 && floor < kFloor18_0 ) ? nullptr : "node --test";
    }
    if( !relativeImportsResolvable( source, path, diskPath ) )
    {
        return nullptr;   // F2: the file's own imports already prove this command would fail
    }
    switch( typeStrippingDecision( enginesFloor( enginesNode( packageJson ) ) ) )
    {
        case StripDecision::Bare:    return "node --test";
        case StripDecision::Flagged: return "node --experimental-strip-types --test";
        case StripDecision::Unknown: default: return nullptr;
    }
}

} // namespace rw::jsrunner
