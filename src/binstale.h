#pragma once

// binstale.h — tracked-binary staleness (field note, IDEAS_fieldNotes_2026-07-24.md §Smaller): flag a
// COMMITTED binary that is older than the tracked source it depends on — the motivating incident was a
// sweep that committed rebuilt test binaries blind, alongside a source edit the binary no longer reflects.
//
// Lives behind --doctor (main.cpp's runDoctor): doctor already runs BEFORE the heavy tree-sitter ingest,
// against nothing but `cfg.rootPath` + git plumbing (check "git" already probes the same root's git health),
// so a repo-content hygiene check fits its existing shape — one more <c> row, same "facts, not a rebuild"
// posture as the rest of the verb. It does NOT belong in --lint (AST-only, single-capture queries over
// PARSED source — a binary has no AST) or --flags (compile-time dark-content gates, a different question).
//
// DETERMINISM (the hard constraint): mtimes are NOT reproducible across clones/checkouts — a fresh `git
// clone` stamps every file with the clone's wall-clock time, so filesystem mtime comparison would flag
// EVERY tracked binary as "just as old as everything else" or nondeterministically stale depending on
// checkout order. This check uses git COMMIT ORDERING instead: the last commit that touched the binary vs
// the last commit that touched each candidate dependent source, compared via `git merge-base
// --is-ancestor` (quality::gitIsAncestor) — a pure function of the commit graph, unaffected by clone time.
//
// HONEST LIMITS (ripwire sees no build system — no Makefile/CMakeLists/link graph parsing, ever):
//   - "binary" is a CONTENT heuristic: a NUL byte in the first 8000 bytes of the WORKING-TREE file (git's
//     own `buffer_is_binary` heuristic, the same one `git diff` uses to print "Binary files differ"). Read
//     from disk, not from a git blob — this check asks "is what's checked out right now stale", and doctor
//     already operates on a real checkout, not a bare ref.
//   - "dependent sources" is a NAMING heuristic, not a build-graph fact: a tracked, non-binary file in the
//     SAME DIRECTORY whose filename's stem (mention.h's stripExt — the part before its LAST '.') matches the
//     binary's own stem — e.g. `test_agentAutopilot` (no extension) pairs with `test_agentAutopilot.cpp`.
//     This catches exactly the motivating "compiled test binary sits next to its source" shape and NOTHING
//     else: a binary built from a differently-named source, from sources in another directory, or via a
//     multi-file link step is invisible to this check (neither flagged nor cleared — silently out of scope).
//   - git-history-blind causes (a compiler/flag change with no source edit, a submodule bump) are equally
//     invisible — the check can only see SOURCE TEXT commits, never why a binary needed rebuilding.
//   - Only commits reachable from HEAD in a straight ancestor/descendant relationship trigger a flag;
//     divergent history (the binary's and the source's last touches sit on unrelated branches merged later)
//     degrades to "not provably stale" rather than guess — false negatives over false positives.

#include "quality.h"    // gitRepoHasHistory / gitOneLine / gitIsAncestor / popenTrimmed — the shared git plumbing
#include "jsonesc.h"    // shSingleQuote
#include "resolve.h"    // includerDir — the SAME "directory of a path" primitive the include resolver already reuses at 4+ sites; not reimplemented here
#include "mention.h"    // mention_detail::baseNameOf — the SAME "basename of a path" primitive doc-mention matching already reuses
#include "btree.hpp"    // gtl::btree_map — sorted-by-directory grouping (house rule: never std::map)

#include <algorithm>
#include <cstddef>
#include <fstream>
#include <string>
#include <string_view>
#include <vector>

namespace ctx
{
namespace binstale
{

// Repos with pathologically many tracked files degrade to "not scanned" rather than spend doctor's fast-
// diagnostic budget on a `git log` per candidate pair — the same "count it, don't silently cap it" honesty
// as crossref's kMaxRefs. Comfortably above any repo this feature was built against; --doctor still reports
// the true tracked-file count either way.
inline constexpr std::size_t kMaxTrackedFiles = 20000;

// git's own binary-detection heuristic (buffer_is_binary): a NUL byte within the first 8000 bytes marks the
// content binary. Reads the WORKING-TREE copy at root/path (never a git blob — see the file header). A
// missing/unreadable file degrades to "not binary" (false, never crashes) — doctor's job is to report, not
// to require every tracked path to be present.
inline bool looksBinary( const std::string& absPath )
{
    std::ifstream f( absPath, std::ios::binary );
    if( !f ) return false;
    char buf[ 8000 ];
    f.read( buf, sizeof( buf ) );
    const std::streamsize n = f.gcount();
    for( std::streamsize i = 0; i < n; ++i ) if( buf[ i ] == '\0' ) return true;
    return false;
}

// "directory of a path", "basename of a path", and "a filename's stem sans extension" are NOT reimplemented
// here — resolve.h::ctx::includerDir (found via ordinary enclosing-namespace lookup: binstale nests inside
// ctx, same as includerDir itself) and mention.h::ctx::mention_detail::{baseNameOf,stripExt} are the
// existing, already-reused primitives for exactly these questions (the house rule: reuse before you rewrite
// a one-liner; the docdrift.h/flipimpact.h precedent for pulling a sibling-namespace helper in by name).
// stripExt strips the LAST '.' (not the first), same as every other stemming call site in the repo — a
// versioned/multi-dot binary name ("libfoo.so.1") narrows to "libfoo.so", not "libfoo", so it will not pair
// with "libfoo.cpp"; the motivating single-extension case ("tool" <-> "tool.cpp") is unaffected either way.
using mention_detail::baseNameOf;
using mention_detail::stripExt;

// the naming heuristic behind "dependent source" (see file header): a binary's stem, for pairing against a
// same-directory source's stem below.
inline std::string_view stemOf( std::string_view filename ) { return stripExt( filename ); }

// one confirmed-stale (binary, dependent source) pair.
struct StaleBinary
{
    std::string path;        // the tracked binary, root-relative
    std::string binCommit;   // its last-touching commit (full sha) — the binary predates the source edit
    std::string srcPath;     // the same-directory, same-stem source that moved after it
    std::string srcCommit;   // that source's last-touching commit (full sha)
};

struct BinaryStaleResult
{
    bool                     nonGitRoot    = false;   // no git history — the check has nothing to compare
    bool                     truncated     = false;   // tracked-file count exceeded kMaxTrackedFiles — not scanned
    std::size_t              trackedCount  = 0;       // `git ls-files` count (reported even when truncated)
    std::size_t              binariesFound = 0;       // tracked paths that sniffed as binary content
    std::vector<StaleBinary> stale;                   // every stale pair found, sorted (path, srcPath)
};

// the full sha of the commit that most recently touched `path` in `root`'s history, or "" on any failure
// (no history for that path, git error) — a hard "don't know" that skips the pair rather than guess.
inline std::string lastTouchingCommit( const std::string& root, const std::string& path )
{
    return quality::gitOneLine( root, "log -1 --format=%H -- " + shSingleQuote( path ) + " 2>/dev/null" );
}

inline BinaryStaleResult computeBinaryStaleness( const std::string& root )
{
    BinaryStaleResult result;
    if( !quality::gitRepoHasHistory( root ) ) { result.nonGitRoot = true; return result; }

    const std::string lsOut = quality::popenTrimmed(
        "git -c core.quotepath=false -C " + shSingleQuote( root ) + " ls-files 2>/dev/null" );
    if( lsOut.empty() ) return result;   // nothing tracked — degrade quietly, not a failure

    std::vector<std::string> paths;
    {
        std::size_t i = 0;
        while( i < lsOut.size() )
        {
            std::size_t j = lsOut.find( '\n', i );
            if( j == std::string::npos ) j = lsOut.size();
            if( j > i ) paths.push_back( lsOut.substr( i, j - i ) );
            i = j + 1;
        }
    }
    result.trackedCount = paths.size();
    if( paths.size() > kMaxTrackedFiles ) { result.truncated = true; return result; }

    const auto absOf = [ & ]( const std::string& p )
    {
        std::string a = root;
        if( !a.empty() && a.back() != '/' ) a += '/';
        a += p;
        return a;
    };

    // group tracked paths by directory (deterministic iteration — gtl::btree_map, never std::map) so each
    // binary's candidate dependents are a cheap same-directory lookup rather than an O(n^2) full scan.
    gtl::btree_map<std::string, std::vector<std::string>> byDir;
    std::vector<std::string>                              binaries;
    for( const std::string& p : paths )
    {
        byDir[ std::string( includerDir( p ) ) ].push_back( p );
        if( looksBinary( absOf( p ) ) ) binaries.push_back( p );
    }
    result.binariesFound = binaries.size();

    for( const std::string& bin : binaries )
    {
        const std::string_view dir  = includerDir( bin );
        const std::string_view stem = stemOf( baseNameOf( bin ) );
        const std::string      binCommit = lastTouchingCommit( root, bin );
        if( binCommit.empty() ) continue;   // history lookup failed — degrade, skip rather than guess

        const auto it = byDir.find( std::string( dir ) );
        if( it == byDir.end() ) continue;
        for( const std::string& cand : it->second )
        {
            if( cand == bin ) continue;
            if( stemOf( baseNameOf( cand ) ) != stem ) continue;
            if( looksBinary( absOf( cand ) ) ) continue;   // a same-stem binary sibling (foo.o/foo.a) — not a "source", cannot order meaningfully

            const std::string srcCommit = lastTouchingCommit( root, cand );
            if( srcCommit.empty() || srcCommit == binCommit ) continue;

            // STALE iff the binary's last commit is a STRICT ancestor of the source's last commit — the
            // source moved at/after a point the binary predates, and nothing recommitted the binary since.
            if( quality::gitIsAncestor( root, binCommit, srcCommit ) )
                result.stale.push_back( StaleBinary{ bin, binCommit, cand, srcCommit } );
        }
    }

    std::sort( result.stale.begin(), result.stale.end(), []( const StaleBinary& a, const StaleBinary& b )
    {
        if( a.path != b.path ) return a.path < b.path;
        return a.srcPath < b.srcPath;
    } );
    return result;
}

}   // namespace binstale
}   // namespace ctx
