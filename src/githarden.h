#pragma once

// githarden.h — the git-config trust boundary (harvest round 2026-09-09).
//
// ripwire shells out to READ-ONLY git inside the analysed checkout: `status --porcelain` for the +dirty stamp
// (gitstamp.h), `ls-files --others --ignored` for the crawl's ignore set (ingest_crawl.h), `log`, `diff --numstat`,
// `archive`, `rev-parse` — 82 calls across a 13-verb sweep, logged through a PATH shim. Git honours the checkout's
// OWN .git/config, and one key there turns a read-only call into arbitrary code: a HOOK-form `core.fsmonitor` — any
// value that is not a boolean is a COMMAND git runs on every status / diff / ls-files. Measured 2026-09-09
// (test/githardencheck.sh arms A/B): a fixture hook fired three times per --situ and once per default map.
// `git clone` never copies .git/config, so a fresh clone is safe; a tarball-delivered tree, a copied worktree or a
// shared checkout is not — and ripwire runs unattended inside agent loops over directories nobody inspected.
//
// The mitigation is ONE site, applied once at process start, BEFORE any thread exists (setenv is not thread-safe)
// and before the first git child: probe each crawl root's core.fsmonitor with `git config --get` (measured inert —
// it runs no hook on the very fixture whose hook fires under `git status`); if any root configures the HOOK form,
// append `core.fsmonitor=false` to git's GIT_CONFIG_COUNT / GIT_CONFIG_KEY_n / GIT_CONFIG_VALUE_n environment
// override, which every git child inherits, and DISCLOSE it: one stderr line per root carrying
// git_harden=fsmonitor-hook, and --doctor's git-config-trust row. The environment override is scoped to the hook
// form, and a caller's own GIT_CONFIG_COUNT block is preserved; ours is appended after it, never in place of it.
//
// DETECTION IS THE DISCLOSURE; THE BOUNDARY IS THE COMMAND LINE. The neutralisation itself is the prefix every
// git child now carries (gitcmd.h: --no-optional-locks -c core.fsmonitor=false, for every form of the key, in
// every directory). What this header does is TELL the user when a root they pointed at carries the hook form,
// and keep the env override as a second layer there. Because the governing config need not sit in `root/.git`
// — it can live up the parent chain, or in a per-worktree gitdir plus a shared commondir — the cheap tier scans
// every config file git's own discovery COULD pick for the root (`discoveryConfigSuperset`: every ancestor's
// `.git` dir or `gitdir:` file, every ancestor that is itself a gitdir, and each one's `commondir`), so the probe
// and disclosure run for the governing repo whatever its depth, with no git child unless a file could carry the
// key. Where the filesystem cannot speak for git (GIT_DIR/GIT_COMMON_DIR/GIT_WORK_TREE set, a root that does not
// canonicalise, a pointer file behind a symlink or holding a NUL), `gitResolvedConfigDirs` asks git itself
// (`rev-parse --absolute-git-dir --git-common-dir`, the hook disabled on that probe's OWN command line).
//
// The trust decision is PER PROCESS: a long-lived --mcp server probes its roots once at start. A config edited
// under a running server is not re-read — the same freshness contract every other startup-only fact has here.
//
// FILTER DRIVERS (2026-10-15). ripwire also neutralises repository-configured filter and diff programs for its own
// git children. `filter.<name>.clean/smudge/process` drivers are named by the repository, so no fixed -c key covers
// them: hardenFilterDriversFor() asks git which drivers the local/worktree scopes define (cheap-tier gated on the
// same candidate files: "filter" or "include"; a candidate that exists but cannot be read as a plain file is always
// probed) and pins each to an empty command on every later git child (gitcmd.h FILTER DRIVERS), disclosing
// git_harden=filter-driver. A server that meets a root only in a request (MCP/LSP) probes it before that request is
// dispatched (hardenLateRoot, once per root, from the MCP dispatch and from getIndex). Diff programs
// (diff.external, diff.<driver>.command/textconv) are refused at the call site instead, with --no-ext-diff
// --no-textconv; submodule repositories are not entered (--ignore-submodules=dirty).
//
// NOT covered, and measured NOT to fire here: a `post-index-change` hook under `git status --porcelain` (git 2.50.1,
// the same fixture). Hooks are the same trust class as config, but an arm that cannot be observed to fire is not
// asserted (CONTRIBUTING §2) — so nothing is claimed for hooks. Revisit when a git version is shown to run one on
// a read-only call. The `ext::` transport is already refused at the one place a URL reaches git (main.cpp's clone).

#include "infra/strkern.h"   // strkern::lowerFoldedEquals — the house A-Z case fold (reused, not re-rolled)
#include "pathguard.h"       // pathguard::readRegularFileNoFollow — config candidates are read non-blocking and regular-file-only
#include "gitmine.h"         // rw::popenTrimmed — the one popen-and-trim shape in the tree (never a second)
#include "infra/emit.h"      // rw::emitTo — the house emitter; no new printf-family site
#include "infra/os.h"   // rw::os::setenv — the GIT_CONFIG_* pins
#include "gitcmd.h"         // rw::gitCmd — every git child starts with --no-optional-locks -c core.fsmonitor=false
#include "infra/jsonesc.h"   // rw::shSingleQuote

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <mutex>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <system_error>   // std::errc — discoveryConfigSuperset tells "absent" from a stat it cannot judge
#include <utility>
#include <vector>

namespace rw::githarden
{

// ── the four things core.fsmonitor can be ───────────────────────────────────────────────────────────────

enum class FsmonitorForm : std::uint8_t { Unset, Builtin, Off, Hook };

inline const char* fsmonitorFormName( FsmonitorForm form ) noexcept
{
    switch( form )
    {
        case FsmonitorForm::Unset:   { return "unset"; }
        case FsmonitorForm::Builtin: { return "builtin"; }
        case FsmonitorForm::Off:     { return "off"; }
        case FsmonitorForm::Hook:    { return "hook"; }
    }
    return "unset";
}

// git-config(1) "boolean": true/yes/on/1 and false/no/off/0, case-insensitive; a bare key (empty value) is true.
// Every other string is the hook COMMAND form. ciEqualAscii lowercases the VALUE against these lowercase spellings.
inline FsmonitorForm classifyFsmonitorValue( std::string_view value ) noexcept
{
    if( value.empty() )
    {
        return FsmonitorForm::Builtin;
    }
    for( std::string_view t : { "true", "yes", "on", "1" } )
    {
        if( strkern::lowerFoldedEquals( value, t ) ) { return FsmonitorForm::Builtin; }
    }
    for( std::string_view f : { "false", "no", "off", "0" } )
    {
        if( strkern::lowerFoldedEquals( value, f ) ) { return FsmonitorForm::Off; }
    }
    return FsmonitorForm::Hook;
}

// ── the probe ────────────────────────────────────────────────────────────────────────────────────────────
//
// `git config --get` reads config only (an include is a file read) and runs no hook — measured inert. The exit code
// travels in-band because popenTrimmed drops it, and "unset" (rc 1, empty) must be told apart from "a bare key"
// (rc 0, empty). Any failure to run git at all reads as Unset: nothing to neutralise, nothing to claim.
inline FsmonitorForm probeFsmonitorForm( const std::string& root )
{
    const std::string out  = popenTrimmed( "git -C " + shSingleQuote( root ) + " config --get core.fsmonitor 2>/dev/null; printf '\\nrc=%s' \"$?\"" );
    const std::size_t rcAt = out.rfind( "rc=" );
    if( rcAt == std::string::npos )
    {
        return FsmonitorForm::Unset;
    }
    if( std::string_view( out ).substr( rcAt + 3 ) != "0" )
    {
        return FsmonitorForm::Unset;
    }
    std::string_view value = std::string_view( out ).substr( 0, rcAt );
    while( !value.empty() && ( value.back() == '\n' || value.back() == '\r' || value.back() == ' ' ) )
    {
        value.remove_suffix( 1 );
    }
    return classifyFsmonitorValue( value );
}

// ── the cheap tier: could a LOCAL config file even carry the key? ────────────────────────────────────────────
//
// git's startup is ~10 ms on macOS (measured 2026-09-09: `git config --get` 9.9 ms median against a 68.5 ms warm
// default map — a 14% tax on the one path this tool exists to keep cheap). So the subprocess runs only when a local
// config file could possibly carry the key: the checkout's own config — `.git/config` (or, when `.git` is a FILE,
// the `gitdir:` it names, its `config.worktree`, and the `commondir` config a linked worktree shares) — contains
// the bytes "fsmonitor" or "include", case-insensitively (config keys are). A hostile value must spell the key in
// one of those files or reach it through an include/includeIf, so this is a SOUND gate on the subprocess, not a
// substitute for it: the authoritative answer is still git's (test/githardencheck.sh arms H and I pin the include
// and the worktree shapes). A global or system config is the user's own writing and is not scanned.
inline std::string trimmedFirstLine( std::string_view text )
{
    const std::size_t nl = text.find( '\n' );
    std::string_view  line = nl == std::string_view::npos ? text : text.substr( 0, nl );
    while( !line.empty() && ( line.front() == ' ' || line.front() == '\t' ) ) { line.remove_prefix( 1 ); }
    while( !line.empty() && ( line.back() == ' ' || line.back() == '\t' || line.back() == '\r' ) ) { line.remove_suffix( 1 ); }
    return std::string( line );
}

// The prefix every PROBE git call carries. The two startup probes (governing-gitdir resolution and the
// authoritative value read) run BEFORE the environment override below is installed, so each one disables
// the hook form on its OWN command line — `-c core.fsmonitor=false` — and the resolution therefore cannot
// itself trigger the very hook it is looking for. `git config --get core.fsmonitor` is the one exception:
// it must NOT carry the flag, because a command-line `-c core.fsmonitor=false` would BE the value it read
// back and mask the real one — and a plain `git config --get` refreshes no index, so it runs no hook.
inline std::string hardenedGitPrefix( const std::string& root )
{
    return gitCmd( " -C " ) + shSingleQuote( root );
}

// Resolve the GOVERNING git directory for any crawl root by asking git itself, with the hook neutralised on
// the probe's own command line, so the disclosure names the repository that actually governs the root
// whatever its depth. `--absolute-git-dir` yields the per-worktree gitdir; `--git-common-dir` yields the
// shared dir a linked worktree's config lives beside. Both are canonicalised against `root` (git's CWD) when
// git prints a relative form. The hand-rolled `root/.git` inspection below is a git-absent fallback for the
// repo-root and worktree-root shapes. Empty ⇒ not a repository, or git could not answer — nothing to probe.
//
// Git discovers a repository by walking up from its CWD to the first `.git` entry, or takes GIT_DIR from the
// environment. A root with neither has no repository to govern it, so the probe spawns no git child for it:
// a non-git tree stays git-free (test/nongitqmetricscheck.sh).
inline bool gitMayGovernRoot( const std::string& root )
{
    if( const char* gitDir = std::getenv( "GIT_DIR" ); gitDir != nullptr && *gitDir != '\0' )
    {
        return true;
    }
    std::error_code       ec;
    std::filesystem::path dir = std::filesystem::absolute( std::filesystem::path( root ), ec );
    if( ec )
    {
        return true;   // cannot tell from here; let git answer
    }
    for( ;; )
    {
        if( std::filesystem::exists( std::filesystem::symlink_status( dir / ".git", ec ) ) )
        {
            return true;
        }
        ec.clear();
        const std::filesystem::path parent = dir.parent_path();
        if( parent == dir )
        {
            return false;
        }
        dir = parent;
    }
}

inline std::vector<std::filesystem::path> gitResolvedConfigDirs( const std::string& root )
{
    std::vector<std::filesystem::path> dirs;
    if( !gitMayGovernRoot( root ) )
    {
        return dirs;
    }
    const std::string out = popenTrimmed( hardenedGitPrefix( root )
                                          + " rev-parse --absolute-git-dir --git-common-dir 2>/dev/null" );
    if( out.empty() )
    {
        return dirs;
    }
    std::error_code       ec;
    const std::filesystem::path rootPath( root );
    std::size_t                 start = 0;
    while( start <= out.size() )
    {
        const std::size_t nl   = out.find( '\n', start );
        const std::size_t stop = nl == std::string::npos ? out.size() : nl;
        std::string_view  line = std::string_view( out ).substr( start, stop - start );
        while( !line.empty() && ( line.back() == '\r' || line.back() == ' ' ) ) { line.remove_suffix( 1 ); }
        if( !line.empty() )
        {
            std::filesystem::path dir( line );
            if( dir.is_relative() ) { dir = rootPath / dir; }                       // git printed it relative to its -C CWD
            dir = std::filesystem::weakly_canonical( dir, ec );
            if( ec ) { dir = std::filesystem::path( line ); ec.clear(); }
            if( std::find( dirs.begin(), dirs.end(), dir ) == dirs.end() ) { dirs.push_back( dir ); }
        }
        if( nl == std::string::npos ) { break; }
        start = nl + 1;
    }
    return dirs;
}

// ── the filesystem superset: every config file git's discovery could govern the root with, no git child ──────
//
// The `rev-parse` above is one git child per crawl root per process — on the critical path of EVERY call, and the
// answer it gives is a fact about the filesystem. With no GIT_DIR / GIT_COMMON_DIR / GIT_WORK_TREE in the
// environment, git (setup.c, 2.50.1) finds the governing gitdir by walking up from the PHYSICAL cwd: at each
// directory D it takes D/.git when that is a directory git accepts as a repository, or the path a `gitdir: X` FILE
// at D/.git names, or D itself when D is a gitdir (a bare repository, or a cwd inside .git — which needs a D/HEAD);
// a `.git` directory git rejects is skipped and the walk goes on up. The gitdir's `commondir` file, when present,
// names the dir whose `config` is shared (a linked worktree; git honours it in ANY gitdir). Local config is then
// gitdir/config, gitdir/config.worktree and commondir/config (+ includes, which the byte scan below reaches through
// the word "include"). So the union over EVERY ancestor-or-self D of those candidates — never stopping at the first
// `.git`, never judging which one git accepts — is a SUPERSET of the files git can read as local config. A superset
// is the safe direction: an extra candidate can only trigger the authoritative `git config --get` probe, never hide
// a value. Pointer files are read both as git reads them (the rest of the file, trailing CR/LF dropped, relative
// to D or to the gitdir) and as the first line trimmed of blanks; where the two differ both are kept.
// nullopt = the filesystem cannot speak for git here, and the caller asks git (gitResolvedConfigDirs) as before:
// an environment-named repository, a root that does not canonicalise, a stat that fails other than "absent", a
// pointer file (.git, commondir) that is a symlink — git reads through it, the no-follow reader does not — or a
// pointer file with a NUL byte in it (git cuts the path there).
// test/githardencheck.sh (O) pins the shapes (an invalid .git skipped, a planted commondir, a bare root, a
// symlinked root) and (P) counts the git children: none for a root whose config cannot carry the key.
inline bool gitDiscoveryNamedByEnvironment() noexcept
{
    for( const char* name : { "GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE" } )
    {
        if( const char* value = std::getenv( name ); value != nullptr && *value != '\0' )
        {
            return true;
        }
    }
    return false;
}

inline void addUniquePath( std::vector<std::filesystem::path>& out, const std::filesystem::path& p )
{
    if( std::find( out.begin(), out.end(), p ) == out.end() )
    {
        out.push_back( p );
    }
}

// Both readings of a pointer file's path, each made absolute against `base`, appended to `out` once each.
inline void addPointerReadings( std::string_view exactRest, std::string_view looseRest, const std::filesystem::path& base,
                                std::vector<std::filesystem::path>& out )
{
    while( !exactRest.empty() && ( exactRest.back() == '\n' || exactRest.back() == '\r' ) )
    {
        exactRest.remove_suffix( 1 );
    }
    const std::string loose = trimmedFirstLine( looseRest );
    for( const std::string_view reading : { exactRest, std::string_view( loose ) } )
    {
        if( reading.empty() )
        {
            continue;
        }
        std::filesystem::path p( reading );
        if( p.is_relative() )
        {
            p = base / p;
        }
        addUniquePath( out, p );
    }
}

// true = absent (or not a directory on the way); false = a stat error git could see differently — doubt.
inline bool statAbsentOrOk( const std::error_code& ec ) noexcept
{
    return !ec || ec == std::errc::no_such_file_or_directory || ec == std::errc::not_a_directory;
}

// The target(s) a `.git` file at `dir` names with `gitdir:`. false = doubt (a `.git` that is a symlink to something
// the no-follow reader cannot open, or a file holding a NUL: git reads the path as a C string, cut at the first NUL).
inline bool addGitFileTargets( const std::filesystem::path& dir, const std::filesystem::path& dotGit,
                               std::vector<std::filesystem::path>& gitDirs )
{
    const std::optional<std::string> head = pathguard::readRegularFileNoFollow( dotGit.string() );
    if( !head )
    {
        return !pathguard::isSymlink( dotGit.string() );
    }
    if( head->find( '\0' ) != std::string::npos )
    {
        return false;
    }
    if( head->starts_with( "gitdir:" ) )
    {
        const std::string_view text( *head );
        addPointerReadings( text.substr( text.starts_with( "gitdir: " ) ? 8 : 7 ), text.substr( 7 ), dir, gitDirs );
    }
    return true;
}

// One level of git's discovery walk: the gitdirs directory `dir` could contribute — its `.git` directory, the
// target(s) of a `.git` gitdir: file, and `dir` itself when it holds a HEAD. false = doubt (a stat error that is not
// "absent", or a `.git` file addGitFileTargets cannot speak for).
inline bool addGitDirsAt( const std::filesystem::path& dir, std::vector<std::filesystem::path>& gitDirs )
{
    std::error_code                    ec;
    const std::filesystem::path        dotGit = dir / ".git";
    const std::filesystem::file_status st     = std::filesystem::status( dotGit, ec );   // follows a link, as git's stat does
    if( !statAbsentOrOk( ec ) )
    {
        return false;
    }
    ec.clear();
    if( std::filesystem::is_directory( st ) )
    {
        addUniquePath( gitDirs, dotGit );
    }
    else if( std::filesystem::exists( std::filesystem::symlink_status( dotGit, ec ) ) && !addGitFileTargets( dir, dotGit, gitDirs ) )
    {
        return false;
    }
    ec.clear();
    if( std::filesystem::exists( std::filesystem::symlink_status( dir / "HEAD", ec ) ) )
    {
        addUniquePath( gitDirs, dir );   // a bare repository, or a directory inside a gitdir
    }
    return true;
}

// The local config files one gitdir could govern with: its config and config.worktree, and the same pair in every
// reading of its `commondir`. false = doubt (a commondir behind a symlink, which git reads through, or one holding a NUL).
inline bool addGitDirConfigFiles( const std::filesystem::path& gitDir, std::vector<std::filesystem::path>& files )
{
    files.push_back( gitDir / "config" );
    files.push_back( gitDir / "config.worktree" );
    const std::string                commondirFile = ( gitDir / "commondir" ).string();
    const std::optional<std::string> common        = pathguard::readRegularFileNoFollow( commondirFile );
    if( !common )
    {
        return !pathguard::isSymlink( commondirFile );
    }
    if( common->find( '\0' ) != std::string::npos )
    {
        return false;   // as for a `.git` file: git cuts the path at the NUL — let git answer
    }
    std::vector<std::filesystem::path> commonDirs;
    addPointerReadings( *common, *common, gitDir, commonDirs );
    for( const std::filesystem::path& commonDir : commonDirs )
    {
        files.push_back( commonDir / "config" );
        files.push_back( commonDir / "config.worktree" );
    }
    return true;
}

inline std::optional<std::vector<std::filesystem::path>> discoveryConfigSuperset( const std::string& root )
{
    if( gitDiscoveryNamedByEnvironment() )
    {
        return std::nullopt;
    }
    std::error_code       ec;
    std::filesystem::path dir = std::filesystem::canonical( std::filesystem::path( root ), ec );   // git walks the physical cwd
    if( ec || dir.empty() )
    {
        return std::nullopt;
    }
    std::vector<std::filesystem::path> gitDirs;
    for( ;; )   // every ancestor-or-self: never stop at the first `.git`, never judge which one git accepts
    {
        if( !addGitDirsAt( dir, gitDirs ) )
        {
            return std::nullopt;
        }
        const std::filesystem::path parent = dir.parent_path();
        if( parent == dir || parent.empty() )
        {
            break;
        }
        dir = parent;
    }
    std::vector<std::filesystem::path> files;
    files.reserve( gitDirs.size() * 4 );
    for( const std::filesystem::path& gitDir : gitDirs )
    {
        if( !addGitDirConfigFiles( gitDir, files ) )
        {
            return std::nullopt;
        }
    }
    ENSURES( files.size() >= gitDirs.size() * 2, "two candidates per gitdir, plus its commondir's" );
    return files;
}

inline std::vector<std::filesystem::path> localConfigCandidates( const std::filesystem::path& root )
{
    if( std::optional<std::vector<std::filesystem::path>> superset = discoveryConfigSuperset( root.string() ) )
    {
        return std::move( *superset );   // may be empty: no `.git` and no gitdir anywhere above — nothing git could read
    }
    DISCLOSE( Diagnostics::answerUnchanged, "githarden: the filesystem cannot speak for git's discovery at this root, so git names the governing dirs (one more git child); the scan and the authoritative probe after it are unchanged" );
    std::vector<std::filesystem::path> out;

    // Authoritative here: git resolves the governing gitdir/commondir for ANY root, subdirectory and
    // worktree and GIT_DIR included. Its config, its per-worktree config.worktree, and the shared common
    // config are the files a hook value could be spelled in (directly or through an include the cheap scan
    // also catches).
    for( const std::filesystem::path& dir : gitResolvedConfigDirs( root.string() ) )
    {
        out.push_back( dir / "config" );
        out.push_back( dir / "config.worktree" );
    }
    if( !out.empty() )
    {
        return out;
    }

    // Fallback for a tree git cannot speak for (git absent, or an unreadable repo): the original root/.git
    // inspection. It handles the repo-root and worktree-root shapes only — which is why the git resolution
    // above leads, and this remains just so a git-less environment still degrades sanely.
    const std::filesystem::path        dotGit = root / ".git";
    std::error_code                    ec;
    if( std::filesystem::is_directory( dotGit, ec ) && !ec )
    {
        out.push_back( dotGit / "config" );
        out.push_back( dotGit / "config.worktree" );
        return out;
    }
    const std::string head = pathguard::readRegularFileNoFollow( dotGit.string() ).value_or( std::string() );
    if( !head.starts_with( "gitdir:" ) )
    {
        return out;   // not a repository at all — nothing for git to read, nothing to probe
    }
    std::filesystem::path gitDir = trimmedFirstLine( std::string_view( head ).substr( 7 ) );
    if( gitDir.is_relative() )
    {
        gitDir = root / gitDir;
    }
    out.push_back( gitDir / "config" );
    out.push_back( gitDir / "config.worktree" );
    if( const std::optional<std::string> common = pathguard::readRegularFileNoFollow( ( gitDir / "commondir" ).string() ) )
    {
        std::filesystem::path commonDir = trimmedFirstLine( *common );
        if( commonDir.is_relative() )
        {
            commonDir = gitDir / commonDir;
        }
        out.push_back( commonDir / "config" );
    }
    return out;
}

// One read of the local config candidates, two questions: could a file carry core.fsmonitor, and could one carry a
// filter driver? "include" answers yes to both — an include can bring in either key. Same soundness argument as above:
// a key git honours must be spelled in one of these files or reached through an include they name.
//
// The scan reads each candidate without following a final symlink (pathguard), but git DOES follow one when it reads
// its config. So a candidate that exists yet cannot be read here as a plain file — a symlink, a non-regular file, an
// unreadable one — answers "could carry either key": the cheap tier may only skip the probe for bytes it has actually
// read, and git's own probe then decides.
struct LocalConfigNeedles
{
    bool fsmonitor = false;
    bool filter    = false;
};

inline LocalConfigNeedles localConfigNeedles( const std::string& root )
{
    LocalConfigNeedles found;
    for( const std::filesystem::path& candidate : localConfigCandidates( root ) )
    {
        std::optional<std::string> bytes = pathguard::readRegularFileNoFollow( candidate.string() );
        if( !bytes )
        {
            // git reads a config file THROUGH a symlink; the no-follow reader does not. A candidate that exists yet
            // cannot be read here as a plain file (a symlink — arm (O) symlinked config — a non-regular or unreadable
            // file) is therefore unknown, not clean: git's own probe decides, never the shortcut.
            std::error_code ec;
            if( std::filesystem::exists( std::filesystem::symlink_status( candidate, ec ) ) )
            {
                found.fsmonitor = true;
                found.filter    = true;
            }
            continue;
        }
        for( char& c : *bytes )
        {
            if( c >= 'A' && c <= 'Z' ) { c = static_cast<char>( c + ( 'a' - 'A' ) ); }
        }
        const bool include = bytes->find( "include" ) != std::string::npos;
        found.fsmonitor    = found.fsmonitor || include || bytes->find( "fsmonitor" ) != std::string::npos;
        found.filter       = found.filter || include || bytes->find( "filter" ) != std::string::npos;
    }
    return found;
}

// ── filter drivers the REPOSITORY's own config names (gitcmd.h FILTER DRIVERS) ─────────────────────────────
//
// `git config --show-scope -z --get-regexp` lists every filter.<name>.clean/smudge/process with the scope it came
// from; an include is reported with the scope of the file that included it. Only `local` and `worktree` are the
// repository's own writing: `global`/`system` are the user's and the machine's (git-lfs installs its driver
// there), and `command` is this process's own -c pins and the caller's GIT_CONFIG_* block. The read is a config
// read — it refreshes no index and starts no program. -z keeps a name with any byte but NUL/newline intact:
// each entry is "scope\0key\nvalue\0".
//
// A git older than 2.26 has no --show-scope and rejects the option (exit 129). The fallback reads the same
// entries WITHOUT scope and pins every one of them, the user's global drivers included: over-neutralising is the
// safe direction, and the disclosure says scope="all" so the difference is visible.
struct FilterDriverProbe
{
    std::vector<std::string> names;          // distinct driver names, in the order git listed them
    bool                     allScopes = false;   // the pre-2.26 fallback: scope could not be read, every scope pinned
};

inline bool readConfigListing( const std::string& root, bool withScope, std::string& body )
{
    const std::string out = popenTrimmed( hardenedGitPrefix( root ) + " config" + ( withScope ? " --show-scope" : "" )
                                          + " -z --get-regexp '^filter\\..*\\.(clean|smudge|process)$' 2>/dev/null; printf '\\nrc=%s' \"$?\"" );
    const std::size_t rcAt = out.rfind( "\nrc=" );
    if( rcAt == std::string::npos )
    {
        return false;
    }
    const std::string_view rc = std::string_view( out ).substr( rcAt + 4 );
    if( rc != "0" && rc != "1" )
    {
        return false;   // 1 is "no match"; anything else is git refusing the command line or the config
    }
    body = out.substr( 0, rcAt );
    return true;
}

// "filter.<name>.<var>\n<value>" → <name>. The name is everything between the section's dot and the LAST dot, so a
// name holding dots survives; nullopt for anything that is not a filter driver key.
inline std::optional<std::string> filterDriverNameOf( std::string_view entry )
{
    entry                               = entry.substr( 0, entry.find( '\n' ) );   // the key; the value follows the newline
    constexpr std::string_view kSection = "filter.";
    const std::size_t          lastDot  = entry.rfind( '.' );
    if( !entry.starts_with( kSection ) || lastDot == std::string_view::npos || lastDot < kSection.size() )
    {
        return std::nullopt;
    }
    return std::string( entry.substr( kSection.size(), lastDot - kSection.size() ) );
}

inline FilterDriverProbe probeLocalFilterDrivers( const std::string& root )
{
    FilterDriverProbe probe;
    std::string       body;
    bool              withScope = true;
    if( !readConfigListing( root, true, body ) )
    {
        withScope = false;
        if( !readConfigListing( root, false, body ) )
        {
            return probe;   // git cannot read this config at all — then no git command here gets as far as a filter
        }
        probe.allScopes = true;
    }
    std::vector<std::string_view> fields;
    for( std::size_t start = 0; start < body.size(); )
    {
        const std::size_t nul  = body.find( '\0', start );
        const std::size_t stop = nul == std::string::npos ? body.size() : nul;
        fields.push_back( std::string_view( body ).substr( start, stop - start ) );
        start = stop + 1;
    }
    const std::size_t stride = withScope ? 2 : 1;
    for( std::size_t i = 0; i + stride <= fields.size(); i += stride )
    {
        if( withScope && fields[i] != "local" && fields[i] != "worktree" )
        {
            continue;
        }
        std::optional<std::string> name = filterDriverNameOf( fields[i + stride - 1] );
        if( name && std::find( probe.names.begin(), probe.names.end(), *name ) == probe.names.end() )
        {
            probe.names.push_back( std::move( *name ) );
        }
    }
    return probe;
}

// What one root's filter-driver probe found and did — kept for --doctor's git-config-trust row (the startup roots).
struct FilterDriverOutcome
{
    std::size_t drivers   = 0;       // distinct driver names the probe found (0: none, or the cheap tier saw no candidate)
    bool        allScopes = false;   // the pre-2.26 fallback: every scope was pinned
    bool        refused   = false;   // a name -c cannot spell: every later git child is refused instead
};

// Probe one root's filter drivers, pin them (gitcmd.h), and disclose on stderr. The names are the repository's
// text and are never printed — only their count. Safe to call from a server thread: the pins are mutex-guarded.
inline FilterDriverOutcome hardenFilterDriversFor( const std::string& root )
{
    const FilterDriverProbe probe = probeLocalFilterDrivers( root );
    FilterDriverOutcome     outcome{ probe.names.size(), probe.allScopes, false };
    if( probe.names.empty() )
    {
        return outcome;
    }
    if( pinGitFilterDrivers( probe.names ).unpinnable )
    {
        outcome.refused = true;
        emitTo( stderr, "ripwire: git: {} configures a filter driver whose name git's -c option cannot spell — every git call this run is refused instead (git_harden=filter-driver-refused): history, churn and the dirty stamp are unavailable\n", root );
        return outcome;
    }
    emitTo( stderr, "ripwire: git: {} configures {} filter driver(s) in {} — neutralised for this run (git_harden=filter-driver): every git call ripwire makes runs them with an empty clean/smudge/process command, so no configured filter program starts\n",
            root, probe.names.size(), probe.allScopes ? "its config (scope=all: this git cannot report scope, so the user's own drivers are neutralised too)" : "the repository's own config" );
    return outcome;
}

// Roots a server meets only in a REQUEST (an MCP or LSP server, with or without a startup root): the startup pass
// never saw them, so the request that names one probes it here before it is dispatched. One probe per distinct
// spelling; the startup roots are recorded too, so they are not probed twice.
namespace detail
{
struct ProbedRoots
{
    std::mutex               lock;
    std::vector<std::string> roots;
};
inline ProbedRoots& probedRoots()
{
    static ProbedRoots probed;
    return probed;
}
inline bool firstSighting( const std::string& root )
{
    ProbedRoots&                      probed = probedRoots();
    const std::lock_guard<std::mutex> guard( probed.lock );
    if( std::ranges::contains( probed.roots, root ) )
    {
        return false;
    }
    probed.roots.push_back( root );
    return true;
}
}   // namespace detail

// The lock is held ACROSS the probe, and the root is recorded only once its pins are registered: a second caller for
// the same root waits until the pins exist instead of returning early and starting git before them, and a probe
// interrupted by an exception leaves the root unrecorded, so the next caller probes it again. A root that is not a
// directory (yet) is not recorded either. Callers for different roots serialise too; a probe is two short git reads.
inline void hardenLateRoot( const std::string& root )
{
    if( root.empty() )
    {
        return;
    }
    detail::ProbedRoots&              probed = detail::probedRoots();
    const std::lock_guard<std::mutex> guard( probed.lock );
    if( std::ranges::contains( probed.roots, root ) )
    {
        return;
    }
    std::error_code ec;
    if( !std::filesystem::is_directory( std::filesystem::path( root ), ec ) || ec )
    {
        return;
    }
    if( localConfigNeedles( root ).filter )
    {
        hardenFilterDriversFor( root );
    }
    probed.roots.push_back( root );
}

// ── the environment override block (git's own mechanism, git-config(1) ENVIRONMENT) ───────────────────────

inline unsigned long gitConfigCount() noexcept
{
    const char* raw = std::getenv( "GIT_CONFIG_COUNT" );
    if( raw == nullptr || *raw == '\0' )
    {
        return 0;
    }
    unsigned long n = 0;
    for( const char* p = raw; *p != '\0'; ++p )
    {
        if( *p < '0' || *p > '9' )
        {
            return 0;   // git itself rejects a non-numeric count; we then start our own block at 0 rather than guess
        }
        n = n * 10 + static_cast<unsigned long>( *p - '0' );
    }
    return n;
}

// Append one key=value AFTER whatever block the caller already set. Returns false only if setenv itself failed.
inline bool appendGitConfigOverride( const char* key, const char* value )
{
    const unsigned long n     = gitConfigCount();
    const std::string   keyN  = "GIT_CONFIG_KEY_" + std::to_string( n );
    const std::string   valN  = "GIT_CONFIG_VALUE_" + std::to_string( n );
    const std::string   count = std::to_string( n + 1 );
    return os::setenv( keyN.c_str(), key, 1 ) == 0 && os::setenv( valN.c_str(), value, 1 ) == 0 && os::setenv( "GIT_CONFIG_COUNT", count.c_str(), 1 ) == 0;
}

// ── the startup record, kept so --doctor reports the SAME probe main() acted on ─────────────────────────────
//
// --doctor cannot re-probe: once the override is in the environment, `git config --get` returns "false" for the very
// root whose file says hook — the override is designed to win. So the form seen BEFORE the override is recorded here,
// per root, and doctor reads it. One write, at startup, before any thread.
struct Report
{
    std::vector<std::pair<std::string, FsmonitorForm>>       forms;      // every directory root probed, in argv order
    std::vector<std::pair<std::string, FilterDriverOutcome>> filters;    // the same roots' filter-driver probes
    bool                                                     applied = false;
};

inline Report g_startup;

// One root's startup record from either list; the value-initialised record (Unset / no drivers) for a root not probed.
template<class Record>
Record startupRecordFor( const std::vector<std::pair<std::string, Record>>& records, std::string_view root ) noexcept
{
    const auto it = std::ranges::find( records, root, &std::pair<std::string, Record>::first );
    return it == records.end() ? Record{} : it->second;
}

inline FsmonitorForm startupFormFor( std::string_view root ) noexcept
{
    return startupRecordFor( g_startup.forms, root );
}

inline FilterDriverOutcome startupFiltersFor( std::string_view root ) noexcept
{
    return startupRecordFor( g_startup.filters, root );
}

// Call ONCE from main(), after parseArgs and before any thread or git subprocess. A root that is not a directory
// (a git URL, which git itself clones fresh — its config is never hostile) is skipped.
inline const Report& hardenForRoots( std::span<const std::string_view> roots )
{
    PROFILE_SCOPE_DESCRIBE( "githarden: hardenForRoots (startup trust probe, per crawl root)" );
    Report& r = g_startup;
    r.forms.clear();
    r.filters.clear();
    r.applied = false;
    bool anyHook = false;
    for( std::string_view root : roots )
    {
        std::error_code ec;
        if( root.empty() || !std::filesystem::is_directory( std::filesystem::path( root ), ec ) || ec )
        {
            continue;
        }
        const std::string        rootStr = std::string( root );
        const LocalConfigNeedles needles = localConfigNeedles( rootStr );
        const FsmonitorForm      form    = needles.fsmonitor ? probeFsmonitorForm( rootStr ) : FsmonitorForm::Unset;
        r.forms.emplace_back( rootStr, form );
        anyHook = anyHook || form == FsmonitorForm::Hook;
        detail::firstSighting( rootStr );
        r.filters.emplace_back( rootStr, needles.filter ? hardenFilterDriversFor( rootStr ) : FilterDriverOutcome{} );
    }
    if( !anyHook )
    {
        return r;
    }
    r.applied = appendGitConfigOverride( "core.fsmonitor", "false" );
    for( const auto& [ root, form ] : r.forms )
    {
        if( form == FsmonitorForm::Hook )
        {
            emitTo( stderr, "ripwire: git: {} configures core.fsmonitor as a hook COMMAND — neutralised for this run (git_harden=fsmonitor-hook): ripwire's git calls are read-only, and every one runs with core.fsmonitor=false\n", root );
        }
    }
    return r;
}

}   // namespace rw::githarden
