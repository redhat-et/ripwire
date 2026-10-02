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
// `nearestPackageManifests`'s own evidence has had its say: an authoritative-but-unrecognized `scripts.test`
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
// EVERY relative (`./`/`../`) static `import`/`export … from`/`require(...)` specifier resolves to a real
// file at EXACTLY that path. train20-cr C9 extends this from the test file's own specifiers to every local
// TypeScript module it reaches (a bounded walk, `tsModuleGraphLoadable`; a cut walk answers "no command"),
// and C10 refuses, on the same walk, syntax type stripping cannot erase (an `enum`, a namespace with runtime
// code, a parameter property, an import alias, a decorator). Anything else is `run_unknown="1"`: the bytes
// already prove the command would fail, so this is read off the parse, never guessed.
//
// F3 — the flag itself needs a Node new enough to accept it. `--experimental-strip-types` exists from
// Node 22.6 only; type stripping is ON BY DEFAULT (the flag becomes a harmless no-op) from 22.18 and from
// 23.6 — two separate release lines, not one continuous floor: 23.6 turned it on first, the 22.x line got
// it later by backport (22.18), and 23.0-23.5 do not have it. So a `.ts`/`.mts`/`.cts` command reads
// `engines.node` from the SAME nearest manifest (if any) and picks one of three answers, never a fourth
// guess: the bare form when every Node the range admits has stripping on by default; the flagged form when
// every one has the flag; and `run_unknown="1"` when the range admits a Node below 22.6 (`>=18`, `^20`,
// even a compound `>=24 || ^20`, whose `^20` alternative decides it) or cannot be read with confidence at
// all. Each `||` alternative is read for its floor AND its ceiling (`detail::engineClause`), because the
// version sets are not monotone: an unbounded `>=22.18` reaches the 23.0-23.5 gap and keeps the flag. An
// ABSENT `engines.node` is not "no constraint" here — it is read as the honest default assumption (a Node
// that strips types with the flag, the flagged form), documented as exactly that, never claimed to be
// foolproof. See `nodeTestVerb`, `tsModuleGraphLoadable` and `typeStrippingDecision` below.
//
// train20-cr C8 — the module KIND is a fourth way to fail, for `.js` as much as `.ts`: a file with a static
// ES `import`/`export` runs only where Node reads it as an ES module (`.mjs`/`.mts`, `"type": "module"` in
// its nearest package.json, or a Node with default module-syntax detection, 22.7+/20.19+, proven by
// `engines.node`). `moduleSyntaxLoadable` below.

#include "docparse.h"
#include "infra/Diagnostics.h" // ASSUME — the same raw-reparse contract pythonrunner.h's hasMainGuard uses
#include "infra/dirwalk.h"    // ascendToRoot — the ONE nearest-config walk, shared with pythonrunner.h
#include "infra/fieldid.h"    // fieldChild/NodeField — the ONE field-lookup pythonrunner.h/ingest_jsimports.h share
#include "infra/jsonesc.h"    // jsonStringEnd — the ONE escape-aware JSON string walk, applied inline below (see detail's banner)
#include "infra/jsontop.h"    // readQuoted / topLevelValueStart — the package.json top-level walk, shared with orientmap.h
#include "infra/namesplit.h"  // isIdentChar / containsWordBoundedBy — the shared ident-byte test and word-boundary scan
#include "infra/nodekind.h"   // kindIs — grammar-string compare without a libc call (per nodekind.h's own banner)
#include "infra/tschildren.h" // ChildCursor/appendChildren — the ONE DFS-stack child-walk shape (tschildren.h's own banner)
#include "pattern.h"          // pattern::stripQuotePair — the ONE quote-strip this and importSpecifierText both apply

#include <algorithm>
#include <filesystem>
#include <limits>
#include <optional>
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


// ObjSpan / topLevelObjectBody / topLevelStringValue — the package.json top-level object and string reads — live in
// infra/jsontop.h (rw::jsrunner::detail), shared with orientmap.h's entry-point detector so the one scan serves both.

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
/// pure marker (a bare `{"type":"commonjs"}`) with nothing to decide. `nearestPackageManifests` below needs to
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
/// train20-cr C8: the walk also keeps the NEAREST manifest whatever it decides (`nearest`), because Node reads
/// a `.js`/`.ts` file's module kind from the nearest package.json's `"type"` — its package scope — not from
/// whichever manifest named the runner.
struct PackageManifests
{
    std::string evidence;   // the deciding manifest, else the nearest one (the runner evidence)
    std::string nearest;    // the nearest non-empty package.json, decisive or not
};

inline PackageManifests nearestPackageManifests( const std::string& file, std::string_view root )
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
    PackageManifests out;
    out.nearest  = fallback;
    out.evidence = decisive.empty() ? std::move( fallback ) : std::move( decisive );
    return out;
}

/// train20-cr C8: the nearest package.json's top-level `"type"` (`"module"`, `"commonjs"`), or "" when it
/// has none or there is no manifest in the boundary.
inline std::string moduleTypeOf( const PackageManifests& manifests )
{
    return detail::topLevelStringValue( manifests.nearest, "type" );
}

// ---------------------------------------------------------------------------------------------------------
// #60 (train 20): the test file's OWN node:test import/require, consulted ONLY when nearestPackageManifests's
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

namespace detail
{

/// train20-cr C10: whether `stmt`, one statement directly inside a TS `namespace`/`module` body, is erased
/// whole by type stripping. Node's strip-only mode accepts a namespace that holds no runtime code and
/// refuses one that does (ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX), so a namespace is non-erasable exactly when
/// one of its statements is not type-only. A NESTED namespace counts as type-only here because the walk
/// reaches it too and judges its own body.
inline bool isTypeOnlyStatement( TSNode stmt ) noexcept
{
    const char* kind = ts_node_type( stmt );
    // NOT `ambient_declaration`: Node 26.9 refuses a namespace holding only `declare` statements (review R2).
    if( rw::kindIs( kind, "interface_declaration" ) || rw::kindIs( kind, "type_alias_declaration" ) || rw::kindIs( kind, "internal_module" )
        || rw::kindIs( kind, "comment" ) || rw::kindIs( kind, "empty_statement" ) )
    {
        return true;
    }
    if( rw::kindIs( kind, "export_statement" ) )
    {
        const TSNode decl = fieldChild( stmt, NodeField::Declaration );
        return !ts_node_is_null( decl ) && isTypeOnlyStatement( decl );
    }
    if( rw::kindIs( kind, "expression_statement" ) && ts_node_named_child_count( stmt ) == 1 )
    {
        const char* inner = ts_node_type( ts_node_named_child( stmt, 0 ) );
        return rw::kindIs( inner, "internal_module" ) || rw::kindIs( inner, "module" );   // `namespace X {}` parses as an expression statement
    }
    return false;
}

/// train20-cr C10: whether `node` (outside any `declare`) is TypeScript syntax that type stripping cannot
/// erase: Node's own list (an `enum`, a `namespace` with runtime code, a parameter property, an import alias
/// `import A = B.C` / `import x = require(…)`), plus what strip-only mode also rejects (review R2, each run under
/// Node 26.9): `export =`, an angle-bracket assertion `<T>x`, the legacy `module M {}` keyword even with a type-only
/// body, and a decorator (a parse error). Each fails before a single test runs, so a hit means the command would fail.
inline bool nodeIsNonErasable( TSNode node )   // not noexcept: firstChildOfKind's cursor allocates (tschildren.h A4-F25)
{
    const char* kind = ts_node_type( node );
    if( rw::kindIs( kind, "enum_declaration" ) || rw::kindIs( kind, "import_alias" ) || rw::kindIs( kind, "import_require_clause" )
        || rw::kindIs( kind, "decorator" ) || rw::kindIs( kind, "type_assertion" ) || rw::kindIs( kind, "module" ) )
    {
        return true;   // `module` is the legacy keyword; `declare module "x" {}` sits under an ambient_declaration, never reached here
    }
    if( rw::kindIs( kind, "export_statement" ) )
    {
        return !ts_node_is_null( rw::firstChildOfKind( node, /*namedOnly=*/false, { "=" } ) );   // `export = x` keeps its `=` token
    }
    if( rw::kindIs( kind, "internal_module" ) )
    {
        const TSNode body = fieldChild( node, NodeField::Body );
        if( ts_node_is_null( body ) )
        {
            return false;
        }
        bool            runtime = false;
        rw::ChildCursor cursor( body );
        rw::forEachNamedChild( body, cursor.cur, [ & ]( TSNode stmt ) { runtime = !isTypeOnlyStatement( stmt ); return !runtime; } );
        return runtime;
    }
    if( rw::kindIs( kind, "required_parameter" ) || rw::kindIs( kind, "optional_parameter" ) )
    {
        // a parameter property: TS rewrites it into a constructor assignment (`readonly` is an anonymous token, so all children)
        return !ts_node_is_null( rw::firstChildOfKind( node, /*namedOnly=*/false, { "accessibility_modifier", "override_modifier", "readonly" } ) );
    }
    return false;
}

/// What ONE parse of one module's bytes says — every fact nodeTestVerb reads off a file comes from this one
/// walk, so the test file is parsed once whatever path asked (#60's node:test evidence, F2's specifiers,
/// train20-cr C8's module syntax and C10's erasability).
struct ModuleScan
{
    bool                     parsed      = false;   // false: oversized, a scanner failure, or a syntax error anywhere — no evidence at all
    bool                     nodeTest    = false;   // an `import … from "node:test"` or `require("node:test")` (nodeIsNodeTestEvidence)
    bool                     esmSyntax   = false;   // a static `import`/`export` statement: the ES module syntax CommonJS cannot evaluate
    bool                     nonErasable = false;   // TS syntax strip-only mode rejects (nodeIsNonErasable), outside any `declare`
    std::vector<std::string> relativeSpecs;         // every `./`/`../` static specifier (collectRelativeSpecifiers)
};

/// Parse `source` with the grammar `path`'s extension selects and walk the WHOLE tree once (a DFS stack,
/// `infra/tschildren.h::appendChildren`'s own documented shape). Oversized input, a failed parse, or any
/// syntax error anywhere yields `parsed == false` and no facts: the same conservative read
/// pythonrunner::topLevelEvidence gives Python's main-guard scan. Everything below a `declare` is ambient
/// and erased whole, so the erasability check is not applied inside it.
inline ModuleScan scanModule( std::string_view source, std::string_view path )
{
    ModuleScan scan;
    if( source.size() > std::numeric_limits<std::uint32_t>::max() )
    {
        return scan;
    }
    TSParser* parser = ts_parser_new();
    ASSUME( parser != nullptr, "ts_parser_new: the default tree-sitter allocator aborts on failure" );
    const bool languageSet = ts_parser_set_language( parser, grammarForPath( path ) );
    ASSUME( languageSet, "the javascript/typescript/tsx grammars are linked into this binary at a supported ABI" );
    TSTree* tree = ts_parser_parse_string( parser, nullptr, source.data(), std::uint32_t( source.size() ) );
    ts_parser_delete( parser );
    if( tree == nullptr )
    {
        return scan;   // an external-scanner error on this text: no evidence, never a guessed runner
    }
    const TSNode root = ts_tree_root_node( tree );
    if( !ts_node_has_error( root ) )
    {
        scan.parsed = true;
        struct Pending
        {
            TSNode node;
            bool   ambient;
        };
        std::vector<Pending> pending{ { root, false } };
        std::vector<TSNode>  children;
        while( !pending.empty() )
        {
            const auto [ node, ambient ] = pending.back();
            pending.pop_back();
            const char* kind = ts_node_type( node );
            scan.nodeTest    = scan.nodeTest || nodeIsNodeTestEvidence( node, source );
            scan.esmSyntax   = scan.esmSyntax || rw::kindIs( kind, "import_statement" ) || rw::kindIs( kind, "export_statement" );
            scan.nonErasable = scan.nonErasable || ( !ambient && nodeIsNonErasable( node ) );
            collectRelativeSpecifiers( node, source, scan.relativeSpecs );
            const bool childAmbient = ambient || rw::kindIs( kind, "ambient_declaration" );
            children.clear();
            rw::ChildCursor cursor( node );
            rw::appendChildren( node, cursor.cur, children );
            for( const TSNode child : children )
            {
                pending.push_back( { child, childAmbient } );
            }
        }
    }
    ts_tree_delete( tree );
    ENSURES( scan.parsed || ( !scan.nodeTest && !scan.esmSyntax && !scan.nonErasable && scan.relativeSpecs.empty() ),
             "an unparsed module carries no facts" );
    return scan;
}

} // namespace detail

/// #60: whether `source` (the bytes of a TS/JS test file at `path`) itself imports or requires node's own
/// "node:test" module — a real parse (`detail::scanModule`), never a substring scan: a "node:test" mention
/// inside a comment or an unrelated string literal is not an import and must not count (the
/// negative-control gate arm pins this). A `require("node:test")` inside a function body counts too; an ES
/// `import` can only sit at top level anyway.
inline bool hasNodeTestImport( std::string_view source, std::string_view path )
{
    return detail::scanModule( source, path ).nodeTest;
}

// train20-cr C9: how many local TypeScript modules the reachability walk below reads, the test file
// included, before it stops. A cut walk proves nothing, so a cut answers "no command" — never a guess.
constexpr std::size_t kMaxTsModulesWalked = 64;   // past it the walk is cut and the answer is run_unknown="1", never a guessed command

inline bool isTsModulePath( std::string_view path ) noexcept
{
    return path.ends_with( ".ts" ) || path.ends_with( ".mts" ) || path.ends_with( ".cts" );
}

/// rv-nodetest-runner-60 F2: the file a relative specifier `spec`, written in a module in `dir`, loads under type
/// stripping — or nothing, when Node would not find it. Node's resolver there never probes an extension and never maps
/// a `.js` specifier onto a `.ts` source, so an extensionless specifier, or one whose exact spelled path is not a real
/// file, finds nothing.
inline std::optional<std::filesystem::path> resolveExactSpecifier( const std::filesystem::path& dir, std::string_view spec )
{
    const std::size_t      lastSlash = spec.rfind( '/' );
    const std::string_view lastSeg   = ( lastSlash == std::string_view::npos ) ? spec : spec.substr( lastSlash + 1 );
    if( lastSeg.find( '.' ) == std::string_view::npos )
    {
        return std::nullopt;   // extensionless: never probed for
    }
    std::filesystem::path target = ( dir / std::filesystem::path( std::string( spec ) ) ).lexically_normal();
    std::error_code       ec;
    if( !std::filesystem::is_regular_file( std::filesystem::status( target, ec ) ) )
    {
        return std::nullopt;   // the exact spelled path is not a real file — no probing, no .js -> .ts mapping
    }
    return target;
}

/// rv-nodetest-runner-60 F2, extended by train20-cr C9 and C10: whether Node, under type stripping, can
/// LOAD the test file (already scanned as `testScan`, on disk at `diskPath`) and every local TypeScript
/// module it reaches. Node's resolver under type stripping never probes an extension and never maps a `.js`
/// specifier onto a `.ts` source, so every relative (`./`/`../`) specifier must name a real file at exactly
/// that path, and every module must be free of syntax stripping cannot erase. The walk follows each specifier
/// that lands on a `.ts`/`.mts`/`.cts` file (a `.js` target is loaded as JavaScript and needs no stripping),
/// reads at most `kMaxTsModulesWalked` modules, and answers false when it is cut there, when any module does
/// not parse, or on the first failing specifier or non-erasable module. A module with no relative specifiers
/// is vacuously loadable. Type-only imports are followed too (a conservative read: stripping erases them, so
/// a failure found only through one may be a false "no command", never a false command).
inline bool tsModuleGraphLoadable( const detail::ModuleScan& testScan, std::string_view diskPath )
{
    namespace fs = std::filesystem;
    struct Module
    {
        fs::path           disk;
        detail::ModuleScan scan;
    };
    std::vector<std::string> visited{ fs::path( std::string( diskPath ) ).lexically_normal().string() };
    std::vector<Module>      pending;
    pending.push_back( { fs::path( std::string( diskPath ) ), testScan } );
    while( !pending.empty() )
    {
        const Module module = std::move( pending.back() );
        pending.pop_back();
        if( !module.scan.parsed || module.scan.nonErasable )
        {
            return false;   // no evidence either way, or syntax stripping rejects before any test runs
        }
        const fs::path dir = module.disk.parent_path();
        for( const std::string& spec : module.scan.relativeSpecs )
        {
            const std::optional<fs::path> target = resolveExactSpecifier( dir, spec );
            if( !target )
            {
                return false;   // Node's resolver under type stripping would not find it
            }
            const std::string key = target->string();
            if( !isTsModulePath( key ) || std::find( visited.begin(), visited.end(), key ) != visited.end() )
            {
                continue;
            }
            if( visited.size() >= kMaxTsModulesWalked )
            {
                return false;   // C9: the walk is cut, so the modules past the cut were never checked
            }
            visited.push_back( key );
            const std::optional<std::string> bytes = docparse::detail::readWholeFile( key );
            if( !VALIDATE( bytes.has_value(), "a local module the resolver just found on disk is readable" ) )
            {
                return false;   // unreadable: its imports and syntax are unknown, so the command is too
            }
            pending.push_back( { *target, detail::scanModule( *bytes, key ) } );
        }
    }
    ENSURES( visited.size() <= kMaxTsModulesWalked, "the walk never reads past its bound" );
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

// A Node version as `major*1000 + minor`, the unit every floor below is spelled in.
constexpr long long nodeVersion( long long major, long long minor ) noexcept
{
    return major * 1000 + minor;
}

constexpr long long kNoCeiling = std::numeric_limits<long long>::max();

/// What ONE `engines.node` alternative (the text between two `||`) admits, read as far as the decisions
/// below need it — NOT a semver engine. Both bounds are versions as `major*1000 + minor` (patch never changes a
/// decision below). `floor` is the LOWEST version it admits, from its FIRST major.minor pair (">=X.Y[.Z]",
/// "^X.Y[.Z]", "~X.Y[.Z]", a bare "X[.Y[.Z]]", ">X.Y[.Z]", the lower end of "A - B"); `0` when it asserts no lower
/// bound this reader can find — a `<`/`<=`-led clause or no version number at all — read as "admits anything",
/// never a guess in the other direction. `ceil` is the first version it can no longer reach (exclusive), or
/// `kNoCeiling`: `^X…` and a bare or `~` major (`X`, `X.x`, `~X`) stay in major X; a bare, `=` or `~` X.Y
/// (`X.Y`, `X.Y.Z`, `X.Y.x`, `~X.Y`) stays in minor X.Y; a hyphen range "A - B" ends at B inclusive (B's major
/// when B names no minor), never at A's major — train20-cr review R1: reading A as same-major collapsed
/// "16.17 - 18" to 16.x; and a later `<`/`<=` comparator lowers it further. The ceiling exists because the
/// version sets below are not monotone — `node --test` exists on 16.17+ and 18+ but not 17.x; default type
/// stripping on 22.18+ and 23.6+ but not 23.0-23.5; default module-syntax detection on 20.19+ and 22.7+ but not
/// 21.x — so a floor alone cannot say whether a range reaches a gap.
struct EngineClause
{
    long long floor = 0;
    long long ceil  = kNoCeiling;
};

/// Reads `major[.minor[.patch]]` at `p` (advancing it), `-1` for each part that has no digits.
inline void readVersion( std::string_view text, std::size_t& p, long long& major, long long& minor, long long& patch ) noexcept
{
    const auto readInt = [ & ]() -> long long
    {
        const std::size_t start = p;
        long long         v     = 0;
        while( p < text.size() && text[p] >= '0' && text[p] <= '9' && p - start < 6 )
        {
            v = v * 10 + ( text[p] - '0' );
            ++p;
        }
        return p == start ? -1 : v;
    };
    major = readInt();
    minor = -1;
    patch = -1;
    if( major >= 0 && p < text.size() && text[p] == '.' )
    {
        ++p;
        minor = readInt();
        if( minor >= 0 && p < text.size() && text[p] == '.' )
        {
            ++p;
            patch = readInt();
        }
    }
}

/// The first version an INCLUSIVE upper end `X[.Y[.Z]]` no longer reaches: past its minor, or past its major when
/// it names no minor (`<=18`, "A - 18" admit every 18.x).
constexpr long long inclusiveCeil( long long major, long long minor ) noexcept
{
    return minor < 0 ? nodeVersion( major + 1, 0 ) : nodeVersion( major, minor + 1 );
}

/// The ceiling an upper bound in `rest` (the clause text after its floor) sets, or `kNoCeiling`: `<X[.Y[.Z]]`
/// excludes X.Y unless a patch past zero lets it in, `<=X…` and a hyphen range's upper end (`A - B`) include it.
inline long long upperBoundCeil( std::string_view rest ) noexcept
{
    const std::size_t lt   = rest.find( '<' );
    const std::size_t dash = lt == std::string_view::npos ? rest.find( " - " ) : std::string_view::npos;
    if( lt == std::string_view::npos && dash == std::string_view::npos )
    {
        return kNoCeiling;
    }
    std::size_t q         = lt != std::string_view::npos ? lt + 1 : dash + 3;
    const bool  inclusive = lt == std::string_view::npos || ( q < rest.size() && rest[q] == '=' );
    while( q < rest.size() && !( rest[q] >= '0' && rest[q] <= '9' ) )
    {
        ++q;
    }
    long long major = -1, minor = -1, patch = -1;
    readVersion( rest, q, major, minor, patch );
    if( major < 0 )
    {
        return kNoCeiling;   // no version after the comparator: no bound this reader can use
    }
    if( inclusive || patch > 0 )
    {
        return inclusiveCeil( major, minor );
    }
    return nodeVersion( major, minor < 0 ? 0 : minor );
}

inline EngineClause engineClause( std::string_view clause ) noexcept
{
    std::size_t p = 0;
    while( p < clause.size() && ( clause[p] == ' ' || clause[p] == '\t' ) )
    {
        ++p;
    }
    if( p < clause.size() && clause[p] == '<' )
    {
        return {};   // an upper-bound-led clause asserts nothing about the floor: read as "admits anything"
    }
    const std::size_t opStart = p;
    while( p < clause.size() && !( clause[p] >= '0' && clause[p] <= '9' ) )   // skip '>=', '^', '~', '>', '=', 'v', or nothing
    {
        ++p;
    }
    const std::string_view op = clause.substr( opStart, p - opStart );
    long long major = -1, minor = -1, patch = -1;
    readVersion( clause, p, major, minor, patch );
    if( major < 0 )
    {
        return {};   // no version number found at all: unparseable, read as "admits anything"
    }
    const std::string_view rest   = clause.substr( p );
    const bool             hyphen = rest.find( " - " ) != std::string_view::npos;   // "A - B": B alone bounds it (R1)
    const bool             exact  = op.empty() || op == "=" || op == "v" || op == "=v" || op == "~";   // X, X.Y, X.Y.Z, X.x, ~X.Y
    long long              own    = kNoCeiling;                                                       // >=, >: open above
    if( !hyphen && exact )
    {
        own = inclusiveCeil( major, minor );   // stays within the minor it names, or the major when it names none
    }
    else if( !hyphen && op == "^" )
    {
        own = nodeVersion( major + 1, 0 );
    }
    EngineClause out;
    out.floor = nodeVersion( major, minor < 0 ? 0 : minor );
    out.ceil  = std::min( own, upperBoundCeil( rest ) );
    ENSURES( out.floor >= 0 && out.ceil > 0, "a floor is a version and a ceiling is past zero" );
    return out;
}

/// A set of Node versions as the decisions below need it: every version from `floor` on, plus an older release
/// line that got the feature by backport, from `backportFloor` up to (not including) `backportCeil` — minus a clause
/// CONFINED to [`gapFloor`, `gapCeil`), a hole the set tolerates inside an open range but not as the whole range.
struct VersionSet
{
    long long floor;
    long long backportFloor;
    long long backportCeil;
    long long gapFloor = 0;
    long long gapCeil  = 0;
};

// The version facts the decisions below read. `--test` (the CLI flag, not only the `node:test` module) was added in
// Node 18.1 and backported to 16.17; 17.x never had it, and 18.0 has the module but not the flag.
// `--experimental-strip-types` exists from 22.6 (an older Node refuses to start with it at all); stripping is on by
// default — the flag a harmless no-op — from 23.6, and on the 22.x line from its 22.18 backport, so 23.0-23.5 do not
// have it. Module-syntax detection (an ES-syntax file with no `"type"` runs as ESM) is on by default from 22.7,
// backported to 20.19; 21.x and 22.0-22.6 need a flag for it.
// kHasTestFlag's floor is 18.0, not 18.1, ON PURPOSE (owner, 2026-09-26): 18.0.0 is one April-2022 release that fails loudly
// ("bad option"), and refusing ">=18" -- the most common spelling -- would make run= useless on most projects; below 18 stays
// strict, and so does a range confined to 18.0.x (its gap), which admits nothing else.
constexpr VersionSet kHasTestFlag         { nodeVersion( 18, 0 ), nodeVersion( 16, 17 ), nodeVersion( 17, 0 ), nodeVersion( 18, 0 ), nodeVersion( 18, 1 ) };
constexpr VersionSet kHasStripFlag        { nodeVersion( 22, 6 ), nodeVersion( 22, 6 ), kNoCeiling };
constexpr VersionSet kStripsByDefault     { nodeVersion( 23, 6 ), nodeVersion( 22, 18 ), nodeVersion( 23, 0 ) };
constexpr VersionSet kDetectsModuleSyntax { nodeVersion( 22, 7 ), nodeVersion( 20, 19 ), nodeVersion( 21, 0 ) };

/// Whether every Node one `engines.node` alternative admits is in `set`.
constexpr bool clauseWithin( EngineClause c, VersionSet set ) noexcept
{
    const bool inSet    = c.floor >= set.floor || ( c.floor >= set.backportFloor && c.ceil <= set.backportCeil );
    const bool inTheGap = set.gapCeil > set.gapFloor && c.floor >= set.gapFloor && c.ceil <= set.gapCeil;
    return inSet && !inTheGap;
}

/// Whether every Node a non-empty `range` admits is in `set` — a compound range admits whichever alternative a
/// reader's Node satisfies, so each `||` alternative must pass on its own (`">=24 || ^20"` is decided by `^20`).
inline bool rangeWithin( std::string_view range, VersionSet set ) noexcept
{
    EXPECTS( !range.empty(), "an absent engines.node is each caller's own decision" );
    std::size_t start = 0;
    while( true )
    {
        const std::size_t      pos    = range.find( "||", start );
        const std::string_view clause = range.substr( start, pos == std::string_view::npos ? range.size() - start : pos - start );
        if( !clauseWithin( engineClause( clause ), set ) )
        {
            return false;
        }
        if( pos == std::string_view::npos )
        {
            return true;
        }
        start = pos + 2;
    }
}

} // namespace detail

/// rv-nodetest-runner-60 F3: the three-way answer an `engines.node` range gives for a `.ts`/`.mts`/`.cts`
/// command — bare (every Node the range admits strips types by default), flagged (every one has the flag,
/// not every one strips by default), or refused (some admitted Node lacks the flag, or an alternative could
/// not be read with confidence, which `engineClause` folds into "admits anything"). An EMPTY `range` (no
/// `engines.node` anywhere in the boundary) is read as the honest default assumption — a Node that strips
/// types with the flag — and gets the flagged form: stated, never proven.
enum class StripDecision : std::uint8_t { Bare, Flagged, Unknown };

inline StripDecision typeStrippingDecision( std::string_view range )
{
    if( range.empty() )
    {
        return StripDecision::Flagged;
    }
    if( !detail::rangeWithin( range, detail::kHasStripFlag ) )
    {
        return StripDecision::Unknown;   // admits a Node where the flag itself is a fatal "bad option"
    }
    return detail::rangeWithin( range, detail::kStripsByDefault ) ? StripDecision::Bare : StripDecision::Flagged;
}

/// train20-cr C8: whether Node will read the test file at `path` (scanned as `scan`) as the module kind its
/// own syntax needs. `.mjs`/`.mts` are always ES modules and `"type": "module"` in the NEAREST package.json
/// (`moduleType`, Node's own package scope) makes a `.js`/`.ts` one too. A file with no static
/// `import`/`export` runs either way. ES syntax in a `.cjs`/`.cts`, or under an explicit
/// `"type": "commonjs"`, fails before any test runs. ES syntax in a typeless `.js`/`.ts` runs only on a
/// Node with default module-syntax detection, so `range` must prove it; with no `engines.node` at all the
/// answer is `absentAssumed` — nodeTestVerb passes true for TypeScript, whose command already rests on the
/// stated assumption of a type-stripping Node (every one of which detects module syntax except 22.6.x), and
/// false for JavaScript, whose command otherwise rests on no assumption at all. A file whose syntax is
/// unknown (`!scan.parsed`) is loadable only where its syntax cannot matter.
/// Not covered: the mirror case — a CommonJS `require` in a file Node reads as an ES module — since an ES
/// module can define its own `require` (`createRequire`) and a call alone does not prove it fails.
inline bool moduleSyntaxLoadable( std::string_view path, const detail::ModuleScan& scan, std::string_view moduleType, std::string_view range,
                                  bool absentAssumed )
{
    const bool alwaysEsm = path.ends_with( ".mjs" ) || path.ends_with( ".mts" );
    const bool alwaysCjs = path.ends_with( ".cjs" ) || path.ends_with( ".cts" );
    if( alwaysEsm || ( !alwaysCjs && moduleType == "module" ) )
    {
        return true;
    }
    if( !scan.parsed )
    {
        return false;   // the file's module kind depends on syntax this parse could not read
    }
    if( !scan.esmSyntax )
    {
        return true;
    }
    if( alwaysCjs || moduleType == "commonjs" )
    {
        return false;   // ES syntax in a file Node must evaluate as CommonJS: an explicit type turns detection off
    }
    return range.empty() ? absentAssumed : detail::rangeWithin( range, detail::kDetectsModuleSyntax );
}

/// rv-nodetest-runner-60: the command for node's own built-in test runner at `path`, on disk at `diskPath`
/// with source bytes `source`, from the evidence manifest (`manifests.evidence`, for `engines.node`) and the nearest
/// package.json's `"type"` (`moduleTypeOf( manifests )`) — decided ENTIRELY from evidence this repo actually carries, never a guess at the
/// Node version or the module graph that will actually run it. Returns `nullptr` for `run_unknown="1"`, the
/// SAME "no command" contract every other evidence miss in this file already uses:
///  * F1 — `.tsx`/`.jsx` can never be spelled: type stripping does not cover `.tsx`, and plain `node`
///    cannot load `.jsx` at all, on ANY Node version.
///  * `engines.node` must not admit a Node without the `--test` flag (below 16.17, 17.x, 18.0); an absent
///    `engines.node` carries no such admission.
///  * train20-cr C8 — the file must load as the module kind its syntax needs (`moduleSyntaxLoadable`).
///  * F2 + C9 + C10 — a `.ts`/`.mts`/`.cts` test file and every local TypeScript module it reaches must
///    load under type stripping (`tsModuleGraphLoadable`).
///  * F3 — a `.ts`/`.mts`/`.cts` command's flag comes from `typeStrippingDecision` over `engines.node`.
/// The test file is parsed once (`detail::scanModule`), and every fact above that needs its bytes reads
/// that one scan.
inline const char* nodeTestVerb( std::string_view path, const PackageManifests& manifests, std::string_view source, std::string_view diskPath )
{
    const std::string_view packageJson = manifests.evidence;
    const std::string      moduleType  = moduleTypeOf( manifests );
    if( path.ends_with( ".tsx" ) || path.ends_with( ".jsx" ) )
    {
        return nullptr;   // F1: never runnable, with or without a flag, on any Node
    }
    const std::string range = enginesNode( packageJson );
    if( !range.empty() && !detail::rangeWithin( range, detail::kHasTestFlag ) )
    {
        return nullptr;   // admits a Node where `--test` itself is a fatal "bad option"
    }
    const bool               isTs = isTsModulePath( path );
    const detail::ModuleScan scan = detail::scanModule( source, path );
    if( !moduleSyntaxLoadable( path, scan, moduleType, range, isTs ) )
    {
        return nullptr;   // C8: Node would read this file as the other module kind
    }
    if( !isTs )
    {
        return "node --test";
    }
    if( !tsModuleGraphLoadable( scan, diskPath ) )
    {
        return nullptr;   // F2/C9/C10: a reachable module cannot load under type stripping
    }
    switch( typeStrippingDecision( range ) )
    {
        case StripDecision::Bare:    return "node --test";
        case StripDecision::Flagged: return "node --experimental-strip-types --test";
        case StripDecision::Unknown: default: return nullptr;
    }
}

} // namespace rw::jsrunner
