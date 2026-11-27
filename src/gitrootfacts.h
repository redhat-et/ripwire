#pragma once

// gitrootfacts.h — what git's repository DISCOVERY could find from a root, read by stat alone, on every call.
//
// Git finds a repository by walking up from its working directory (the real path `git -C <root>` changes into) and
// stopping at the first level that holds a `.git` entry (a directory, or a `gitdir:` file) or is itself shaped like a
// bare repository (it holds a `HEAD`), unless GIT_DIR names the repository outright (setup.c,
// setup_git_directory_gently_1). GIT_CEILING_DIRECTORIES, the one-filesystem rule and safe.directory only make git find
// LESS. So a root whose real path holds neither entry at any level, with GIT_DIR unset, is PROVABLY no repository: every
// git command that needs one fails there, and asking git is a subprocess that can only answer "not a git repository".
//
// MEASURED, which is why this exists (MEASURE-M5, 2026-11-26): an MCP edit on a non-git root started 8 git children on
// its first call and 4 on every later one, each failing, about a third of a 265-314 ms APPLY. gitDiffChangedMaskNumstat
// and gitRepoHasHistory now return their non-repo answer from this proof instead (test/norepogitcheck.sh).
//
// NEVER STALE, BY CONSTRUCTION. The proof is not remembered: it is re-read on every call (one realpath plus two stats
// per level, microseconds), so a long-lived MCP or LSP session notices `git init`, a new `.git`, a removed one, a moved
// root and a changed GIT_DIR on its very next call. What IS remembered elsewhere (gitRepoToplevel's per-directory
// toplevel) keeps a GitDiscoveryView beside its answer and re-asks git whenever the view it was computed under no
// longer matches — a `.git` appearing or disappearing at any level, a `.git` replaced or rewritten (inode, size, mtime),
// or a changed GIT_DIR / GIT_WORK_TREE / GIT_COMMON_DIR.
//
// NOT CACHED: "a repository with no HEAD yet". Its first commit changes no stat this view reads reliably (a loose ref
// is written under .git/refs, a reftable under .git/reftable, a gitfile's repository somewhere else entirely), so that
// fact stays one `rev-parse --verify HEAD` per ask (gitRepoHasHistory), exactly as before.
//
// The proof is CONSERVATIVE: a stray file named HEAD, a `.git` on another filesystem or above a ceiling, an
// unresolvable root, or a walk deeper than kGitDiscoveryMaxLevels all make it decline, and the caller asks git as it
// always did. A declined proof never changes an answer; only a granted one skips git.

#include "infra/os.h"   // rw::os::realpath / stat / st_mtim

#include <algorithm>    // std::ranges::any_of
#include <climits>      // PATH_MAX
#include <ctime>        // timespec
#include <cstdint>
#include <cstdlib>      // std::getenv
#include <string>
#include <vector>

namespace rw
{

// The walk-up bound (any real path is far shallower; the bound is a hostile-symlink guard — hasEnclosingGitRepo's).
inline constexpr int kGitDiscoveryMaxLevels = 64;

// One entry git's discovery would stop at, and enough of its identity to notice it was replaced or rewritten.
struct GitDiscoveryMark
{
    std::uint16_t level  = 0;       // 0 = the root's own real path, 1 = its parent, …
    bool          isHead = false;   // false: `<dir>/.git`; true: `<dir>/HEAD` (a bare-repository-shaped dir)
    std::uint64_t dev    = 0;
    std::uint64_t ino    = 0;
    std::int64_t  size   = 0;
    std::int64_t  mtimeS = 0;
    std::int64_t  mtimeN = 0;

    friend bool operator==( const GitDiscoveryMark&, const GitDiscoveryMark& ) = default;
};

// Everything git's discovery reads from `root`, by stat and getenv. Equal views ⇒ git discovers the same repository.
struct GitDiscoveryView
{
    bool                          resolved  = false;   // realpath( root ) succeeded
    bool                          complete  = false;   // the walk reached "/" inside kGitDiscoveryMaxLevels
    bool                          gitDirSet = false;   // GIT_DIR is in the environment at all (even empty): discovery is bypassed
    std::string                   envKey;              // GIT_DIR, GIT_WORK_TREE, GIT_COMMON_DIR values, each NUL-terminated ("\1" = unset)
    std::vector<GitDiscoveryMark> marks;               // nearest level first

    friend bool operator==( const GitDiscoveryView&, const GitDiscoveryView& ) = default;

    // No repository can be found from this root: git need not be asked.
    [[nodiscard]] bool provesNoRepo() const noexcept { return resolved && complete && !gitDirSet && marks.empty(); }
    // Some level of the root's real path holds a `.git` entry (hasEnclosingGitRepo's question).
    [[nodiscard]] bool hasDotGit() const noexcept
    {
        return std::ranges::any_of( marks, []( const GitDiscoveryMark& m ) { return !m.isHead; } );
    }
};

// The environment half of the view: the variables that choose the repository outright or move its work tree.
inline std::string gitDiscoveryEnvKey()
{
    std::string key;
    for( const char* name : { "GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR" } )
    {
        const char* value = std::getenv( name );
        key += value != nullptr ? value : "\1";
        key += '\0';
    }
    return key;
}

// The entries git's discovery would stop at in ONE directory of the walk: `<dir>/.git`, then `<dir>/HEAD`.
inline void appendGitDiscoveryMarks( const std::string& dir, int levelIndex, std::vector<GitDiscoveryMark>& marks )
{
    const std::string base = dir == "/" ? dir : dir + "/";
    for( const bool isHead : { false, true } )
    {
        os::stat_t st;
        if( os::stat( ( base + ( isHead ? "HEAD" : ".git" ) ).c_str(), &st ) != 0 )
        {
            continue;
        }
        const ::timespec mtime = os::st_mtim( st );
        marks.push_back( GitDiscoveryMark{ static_cast<std::uint16_t>( levelIndex ), isHead, static_cast<std::uint64_t>( st.st_dev ),
                                           static_cast<std::uint64_t>( st.st_ino ), static_cast<std::int64_t>( st.st_size ),
                                           static_cast<std::int64_t>( mtime.tv_sec ), static_cast<std::int64_t>( mtime.tv_nsec ) } );
    }
}

inline GitDiscoveryView gitDiscoveryView( const std::string& root )
{
    GitDiscoveryView view;
    view.envKey    = gitDiscoveryEnvKey();
    view.gitDirSet = std::getenv( "GIT_DIR" ) != nullptr;

    char resolved[ PATH_MAX ];
    if( !os::realpath( root.c_str(), resolved ) )
    {
        return view;   // unresolvable: git -C fails there too, but the proof declines and git answers as it always did
    }
    view.resolved = true;
    std::string dir{ resolved };   // brace-init: dir( resolved ) parses as a function declarator (vexing-parse lookalike)
    for( int levelIndex = 0; levelIndex < kGitDiscoveryMaxLevels && !dir.empty(); ++levelIndex )
    {
        appendGitDiscoveryMarks( dir, levelIndex, view.marks );
        const std::size_t slash = dir.rfind( '/' );
        if( dir == "/" || slash == std::string::npos )
        {
            view.complete = dir == "/";
            break;
        }
        dir.resize( slash == 0 ? 1 : slash );   // parent dir; "/" is its own parent → loop exit above
    }
    return view;
}

// The zero-subprocess non-repo answer: true only when git provably cannot find a repository from `root`.
inline bool gitRootProvablyNoRepo( const std::string& root )
{
    return gitDiscoveryView( root ).provesNoRepo();
}

}   // namespace rw
