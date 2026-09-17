#pragma once
#include "infra/emit.h"
#include "pathguard.h"
#include "embedded_skills.h"
#include "wrap.h"   // AgentTarget / agentTarget / kAgentTargets / AgentConfig / getAgentConfigs / resolveSkillsRoot —
                    // per-agent destinations and --all's presence detection are wrap.h's, not a second table here.

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <filesystem>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

// skillsinstall.h — `ripwire skills install`: extract the binary's embedded skills/hooks into a
// versioned, link-safe store, then symlink from there into an agent's skill directory. Replaces the
// checkout-symlink mechanism `skills/install.sh` used before embedding (redhat-et/ripwire#225) — see
// the design spec linked from that issue for the full reasoning; this file is the "how", not the "why".
//
// Windows: symlink-only for now. The copy-fallback for platforms without unprivileged symlink support
// is deferred until src/infra/os.h's POSIX seam lands — this file makes plain POSIX calls with no
// platform branches on purpose (CLAUDE.md: platform code belongs in that seam, not scattered #ifdefs).
// Every OS-differing call this file makes (symlink creation, rename, unlink) is grouped into its own
// small, POSIX-call-named function below (symlinkOrRefuse, renameAtomic) so that when os.h lands,
// converting these to rw::os::... is a mechanical rename with no logic change.

namespace rw::skillsinstall
{

struct Outcome
{
    bool ok = false;
    std::string error;
};

// A tiny RAII fd guard — every ::open() in this file goes through one of these so an early return
// can never leak a descriptor.
struct FdGuard
{
    int fd = -1;
    explicit FdGuard( int f ) noexcept : fd( f ) {}
    ~FdGuard() { if( fd >= 0 ) { ::close( fd ); } }
    FdGuard( const FdGuard& ) = delete;
    FdGuard& operator=( const FdGuard& ) = delete;
};

inline std::string envOr( const char* name, std::string fallback )
{
    const char* value = std::getenv( name );
    return ( value && *value ) ? std::string( value ) : std::move( fallback );
}

inline std::filesystem::path homeDir()
{
    return std::filesystem::path( envOr( "HOME", "/tmp" ) );
}

// ${RIPWIRE_DATA_HOME:-~/.local/share/ripwire} — same literal path the curl installer already
// stages skills under today (README.md:874,2215,2217); this just versions it.
inline std::filesystem::path dataHome()
{
    const char* override_ = std::getenv( "RIPWIRE_DATA_HOME" );
    if( override_ && *override_ ) { return std::filesystem::path( override_ ); }
    return homeDir() / ".local" / "share" / "ripwire";
}

inline std::filesystem::path skillsStoreDir() { return dataHome() / "skills" / std::string( embedded_skills::kStoreKey ); }
inline std::filesystem::path hooksStoreDir()  { return dataHome() / "hooks"  / std::string( embedded_skills::kStoreKey ); }

// ── the small POSIX-call-named group (Amendment 3): every OS-differing call in this file lives here,
//    so a later port to rw::os::... is a mechanical rename with no logic change. ──────────────────────

// ::rename() the temp extraction directory into its final store location. Returns false on failure;
// the caller decides whether a concurrent winner already occupies the target (see extractGroup).
inline bool renameAtomic( const std::filesystem::path& from, const std::filesystem::path& to )
{
    return ::rename( from.c_str(), to.c_str() ) == 0;
}

// ::symlink() storeFile -> destLink. Returns false on failure, with errno left intact for the caller.
inline bool symlinkOrRefuse( const std::filesystem::path& storeFile, const std::filesystem::path& destLink )
{
    return ::symlink( storeFile.c_str(), destLink.c_str() ) == 0;
}

// Write one embedded file's bytes to `dest`, refusing if anything at `dest` already exists as a
// symlink (never write through a planted link — reuses rw::pathguard::isSymlink, the shared predicate,
// rather than a second lstat/S_ISLNK check). O_EXCL means "fail if it exists at all" — combined with a
// fresh temp directory per extraction attempt (see ensureStoreExtracted), a partial write can never
// masquerade as a complete one. This is a genuinely different case from pathguard's
// openNoFollowTruncate (which TRUNCATES an existing regular file, sidecar-style): store extraction must
// never succeed against an already-existing file, since the store is immutable-by-hash and a fresh temp
// directory should never have pre-existing content.
inline Outcome writeStoreFile( const std::filesystem::path& dest, std::string_view bytes )
{
    if( rw::pathguard::isSymlink( dest.string() ) )
    {
        return { false, "refusing to write through existing symlink: " + dest.string() };
    }
    std::error_code mkdirEc;
    std::filesystem::create_directories( dest.parent_path(), mkdirEc );
    if( mkdirEc )
    {
        return { false, "create_directories failed for " + dest.parent_path().string() + ": " + mkdirEc.message() };
    }
    const int fd = ::open( dest.c_str(), O_CREAT | O_EXCL | O_NOFOLLOW | O_WRONLY, 0644 );
    if( fd < 0 )
    {
        return { false, "open(O_EXCL) failed for " + dest.string() + ": " + std::string( std::strerror( errno ) ) };
    }
    FdGuard guard( fd );
    std::size_t written = 0;
    while( written < bytes.size() )
    {
        const ssize_t n = ::write( fd, bytes.data() + written, bytes.size() - written );
        if( n < 0 )
        {
            if( errno == EINTR ) { continue; }
            return { false, "write failed for " + dest.string() + ": " + std::string( std::strerror( errno ) ) };
        }
        written += static_cast<std::size_t>( n );
    }
    return { true, {} };
}

// Extract every entry in `files` under `storeRoot`, via a fresh temp sibling directory that is
// atomic-renamed into place only once every file is written — a killed/interrupted run can never
// leave a directory with the final name that reads back as "already extracted, trust it".
template <std::size_t N>
inline Outcome extractGroup( const std::array<embedded_skills::EmbeddedFile, N>& files, const std::filesystem::path& storeRoot )
{
    std::error_code ec;
    if( std::filesystem::exists( storeRoot, ec ) ) { return { true, {} }; }   // immutable-by-hash: already extracted

    const std::filesystem::path tmp = storeRoot.parent_path() / ( ".tmp-" + std::to_string( ::getpid() ) + "-" + storeRoot.filename().string() );
    std::filesystem::remove_all( tmp, ec );
    for( const embedded_skills::EmbeddedFile& f : files )
    {
        const Outcome o = writeStoreFile( tmp / std::string( f.relativePath ), f.bytes );
        if( !o.ok )
        {
            std::filesystem::remove_all( tmp, ec );
            return o;
        }
    }
    std::filesystem::create_directories( storeRoot.parent_path(), ec );
    if( !renameAtomic( tmp, storeRoot ) )
    {
        // someone else extracted the same content concurrently and won the race — that's fine,
        // the store is immutable-by-hash, so whichever copy exists now is correct either way.
        std::filesystem::remove_all( tmp, ec );
        if( !std::filesystem::exists( storeRoot, ec ) )
        {
            return { false, "rename to store dir failed and the target still doesn't exist: " + storeRoot.string() };
        }
    }
    return { true, {} };
}

inline Outcome ensureStoreExtracted()
{
    if( embedded_skills::kSkillFileCount == 0 )
    {
        return { false, "embedded skill set is empty — this is a build defect, not a runtime condition" };
    }
    if( const Outcome o = extractGroup( embedded_skills::kSkillFiles, skillsStoreDir() ); !o.ok ) { return o; }
    return extractGroup( embedded_skills::kHookFiles, hooksStoreDir() );
}

// Symlink storeFile -> destLink. Refuses (does not overwrite) if destLink already exists and is NOT
// a symlink this subcommand itself would have created pointing at storeFile — see Task 6 for the
// "is it ours, and is it already correct" logic that wraps this.
inline Outcome linkOrRefuse( const std::filesystem::path& storeFile, const std::filesystem::path& destLink )
{
    std::error_code mkdirEc;
    std::filesystem::create_directories( destLink.parent_path(), mkdirEc );
    if( mkdirEc )
    {
        return { false, "create_directories failed for " + destLink.parent_path().string() + ": " + mkdirEc.message() };
    }
    if( symlinkOrRefuse( storeFile, destLink ) )
    {
        return { true, {} };
    }
    if( errno == EEXIST )
    {
        return { false, "already exists: " + destLink.string() };   // caller decides refuse-vs-already-correct
    }
    return { false, "symlink failed for " + destLink.string() + ": " + std::string( std::strerror( errno ) ) };
}

// Extract "<name>" out of an embedded skill's relativePath ("skills/<name>/SKILL.md", "skills/<name>/
// notes.md", ...) — the second path component, since every embedded skill path is rooted under a
// literal "skills/" group prefix (CMakeLists.txt's _ripwire_group_prefix). A path with fewer than two
// components is a build defect (every embedded skill file lives under skills/<name>/), so it is
// skipped rather than mis-linked.
inline std::string skillDirNameOf( std::string_view relativePath )
{
    const std::filesystem::path rel( relativePath );
    auto it = rel.begin();
    if( it == rel.end() ) { return {}; }
    ++it;
    if( it == rel.end() ) { return {}; }
    return it->string();
}

// True iff `skillDir`'s embedded SKILL.md declares "audience: contributor" in its own YAML front
// matter (the region between the file's opening "---" line and the next one). Scanning only that
// region — not the whole file — matters: the content here is embedded bytes, not a file on disk, so
// this can't be a grep over a path; and a plain substring scan over the WHOLE body would let a skill
// that merely MENTIONS "contributor" in its prose (ripwire-opt-remarks' own body does, among others)
// flip the gate. `ripwire-opt-remarks` is the one such skill in the embedded set today.
inline bool skillDirIsContributorOnly( std::string_view skillDir )
{
    for( const embedded_skills::EmbeddedFile& f : embedded_skills::kSkillFiles )
    {
        if( !f.relativePath.ends_with( "/SKILL.md" ) ) { continue; }
        if( skillDirNameOf( f.relativePath ) != std::string( skillDir ) ) { continue; }
        const std::string_view bytes = f.bytes;
        if( !bytes.starts_with( "---" ) ) { return false; }   // no front matter — nothing to gate on
        const std::size_t closing = bytes.find( "\n---", 3 );
        const std::string_view frontMatter = ( closing == std::string_view::npos ) ? bytes : bytes.substr( 0, closing );
        return frontMatter.find( "audience: contributor" ) != std::string_view::npos;
    }
    return false;   // no SKILL.md found for this dir — a build defect, treated as "not gated" not "gated"
}

// The `.ripwire-manifest-v2` sidecar this dispatch's gates check: which executable performed the
// install (`source=`), the manifest schema version, and — as of Task 6 — one `skill=<name>` line per
// currently-linked skill, so a later run can tell a renamed-away skill from one still current and
// prune only the former. Per-agent entries and tracked-hook bookkeeping remain Task 8's scope.
struct ManifestV2
{
    bool read = false;   // true only when a manifest actually opened and parsed — false is "no manifest yet"
    int version = 0;
    std::string source;
    std::vector<std::string> skills;
};

// Read back a manifest written by writeManifestV2 below. Goes through pathguard's openNoFollowRead
// (Amendment 2/3's read twin of the write side): never follows a symlink at the final component, and
// — like every other sidecar reader — stays silent on a plain "nothing there yet", which is the
// ordinary first-install case, not a failure.
inline ManifestV2 readManifestV2( const std::filesystem::path& manifestPath )
{
    ManifestV2 out;
    rw::pathguard::NoFollowRead in = rw::pathguard::openNoFollowRead( "the skills manifest", manifestPath.string() );
    if( !in.opened ) { return out; }
    out.read = true;
    std::string line;
    while( in.readLine( line ) )
    {
        if( line == "version=1" ) { out.version = 1; }
        else if( line == "version=2" ) { out.version = 2; }
        else if( line.rfind( "source=", 0 ) == 0 ) { out.source = line.substr( 7 ); }
        else if( line.rfind( "skill=", 0 ) == 0 ) { out.skills.push_back( line.substr( 6 ) ); }
    }
    return out;
}

// Write the sidecar: schema version, the executable that performed the install, and one `skill=`
// line per name in `skillNames`. Goes through pathguard's openNoFollowTruncate (Amendment 2/3): this
// sidecar is rewritten on every install, so it is a truncate-an-existing-file case, not an
// extraction-into-a-fresh-directory case.
inline bool writeManifestV2( const std::filesystem::path& skillsDest, std::string_view executablePath, const std::vector<std::string>& skillNames )
{
    const std::filesystem::path manifestPath = skillsDest / ".ripwire-manifest-v2";
    const rw::pathguard::OpenedFile opened = rw::pathguard::openNoFollowTruncate( "the skills manifest", manifestPath.string() );
    if( opened.fd < 0 ) { return false; }
    std::string body = "version=2\nsource=" + std::string( executablePath ) + "\n";
    for( const std::string& s : skillNames ) { body += "skill=" + s + "\n"; }
    return rw::pathguard::writeAllAndClose( opened.fd, body );
}

// Remove every destination entry the PREVIOUS manifest tracked that is no longer in
// `currentSkillNames` — a skill renamed or removed since the last install. ::unlink() itself never
// follows a symlink at the final path component (it removes the directory entry, never the target
// the entry points at), so this is link-safe by construction; no extra isSymlink guard is needed
// here the way one is needed before a CREATE or a READ. Returns the count removed.
inline int pruneStale( const std::filesystem::path& destDir, const ManifestV2& previous, const std::vector<std::string>& currentSkillNames )
{
    int removed = 0;
    for( const std::string& old : previous.skills )
    {
        // The name came straight out of a user-writable text file — refuse anything that could walk
        // `destDir / old` outside destDir (a bare "..", an embedded "/", ...) rather than unlink
        // wherever that resolves. A plain skill directory name never contains a slash.
        if( old.empty() || old == "." || old == ".." || old.find( '/' ) != std::string::npos ) { continue; }
        const bool stillPresent = std::find( currentSkillNames.begin(), currentSkillNames.end(), old ) != currentSkillNames.end();
        if( stillPresent ) { continue; }
        const std::filesystem::path entry = destDir / old;
        struct stat st{};
        if( ::lstat( entry.c_str(), &st ) != 0 ) { continue; }   // already gone — nothing to remove
        if( ::unlink( entry.c_str() ) == 0 ) { ++removed; }      // unlink, never follow — S_ISLNK or not
    }
    return removed;
}

// Everything one agent's install needs, for the caller to report (bare install, one line; `--all`,
// one line per agent) without re-deriving it.
struct InstallOutcome
{
    bool ok = false;
    std::string error;
    std::filesystem::path dest;
    int linked = 0;
    int pruned = 0;
};

// The per-agent core: resolve `agentName`'s skills destination via wrap.h's kAgentTargets (empty
// `agentName` means Claude, the installer default — same convention the bare `ripwire skills install`
// always had), extract the store if needed, link the current skill set (contributor-gated per
// skillDirIsContributorOnly), prune anything the previous manifest tracked that fell out of that set,
// and write the manifest back. `force`: re-link a destination entry only when it is ALREADY one of
// ours — a symlink pointing at our own store for this exact skill — never a foreign entry or a
// planted link; that is a stricter check than "does it exist", not a looser one, so it cannot regress
// the link-safety arms that never pass --force.
//
// `--codex-legacy` is NOT a fifth agent identity — skills/install.sh never treated it as one (its own
// `dst` switch has `codex) ... ;; codex-legacy) ...` as two DESTINATION cases sharing one hook branch,
// `codex|codex-legacy) install_codex_hook`). It is Codex's OLDER discovery root
// (`${CODEX_HOME:-$HOME/.codex}/skills`, distinct from the current `AGENTS_HOME/skills` `codex` uses),
// kept for back-compat. So it is not a `kAgentTargets` row: adding one would misrepresent it as a
// distinct agent when it shares "codex" identity for contributor filtering and (later) hook behavior —
// it is handled here, as a destination override, not in wrap.h's agent table.
inline InstallOutcome installForAgent( std::string_view agentName, bool contributor, bool force, std::string_view executablePath )
{
    const Outcome extracted = ensureStoreExtracted();
    if( !extracted.ok ) { return { false, extracted.error, {}, 0, 0 }; }

    const std::string effectiveAgent = agentName.empty() ? std::string( "claude" ) : std::string( agentName );
    const bool        isCodexLegacy  = ( effectiveAgent == "codex-legacy" );
    // codex-legacy shares codex's row for everything (contributor filtering, future hook behavior) —
    // only its resolved destination differs, so the table lookup below is by "codex" for that case.
    const rw::AgentTarget* row = rw::agentTarget( isCodexLegacy ? std::string_view( "codex" ) : std::string_view( effectiveAgent ) );
    if( row == nullptr || row->skillsRoot.empty() )
    {
        return { false, "no verified skills discovery path for '" + effectiveAgent + "'", {}, 0, 0 };
    }
    const std::filesystem::path skillsDest = isCodexLegacy
        ? ( std::filesystem::path( envOr( "CODEX_HOME", ( homeDir() / ".codex" ).string() ) ) / "skills" )
        : rw::resolveSkillsRoot( *row, homeDir().string() );
    if( skillsDest.empty() )
    {
        return { false, "could not resolve skills destination for '" + effectiveAgent + "'", {}, 0, 0 };
    }

    std::error_code mkdirEc;
    std::filesystem::create_directories( skillsDest, mkdirEc );
    if( mkdirEc )
    {
        return { false, "create_directories failed for " + skillsDest.string() + ": " + mkdirEc.message(), skillsDest, 0, 0 };
    }

    // Collect the current, deduped set of ripwire-* skill directory names up front: pruneStale needs
    // it to tell a still-current skill from a renamed-away one, and the previous manifest has to be
    // read before anything is linked so a rename is prunable in the very same run.
    std::vector<std::string> currentSkillNames;
    for( const embedded_skills::EmbeddedFile& f : embedded_skills::kSkillFiles )
    {
        const std::string skillDir = skillDirNameOf( f.relativePath );
        // Every agent — not just Claude — currently links only the flat "ripwire-*" set; this filter
        // does not vary by `agentName` today. skills/install.sh's Claude-mode loop
        // (`for d in "$src"/ripwire-*/`) only ever applied this same filter for Claude, and
        // skills/hermes/ is Hermes-native content install.sh links under --hermes specifically — but
        // that per-agent differentiation has NOT been ported here yet; it is later-task territory
        // (this task is agent DESTINATION selection, not agent-specific skill SELECTION). Until then,
        // `--hermes` links the identical "ripwire-*" set every other mode does.
        if( skillDir.empty() || skillDir.rfind( "ripwire-", 0 ) != 0 ) { continue; }
        if( std::find( currentSkillNames.begin(), currentSkillNames.end(), skillDir ) != currentSkillNames.end() ) { continue; }
        if( !contributor && skillDirIsContributorOnly( skillDir ) ) { continue; }   // --contributor gate
        currentSkillNames.push_back( skillDir );
    }

    const std::filesystem::path manifestPath = skillsDest / ".ripwire-manifest-v2";
    const ManifestV2 previous = readManifestV2( manifestPath );
    const int pruned = pruneStale( skillsDest, previous, currentSkillNames );

    int linked = 0;
    for( const std::string& skillDir : currentSkillNames )
    {
        const std::filesystem::path destLink = skillsDest / skillDir;
        const std::filesystem::path storeFile = skillsStoreDir() / "skills" / skillDir;
        std::error_code statusEc;
        const std::filesystem::file_status destStatus = std::filesystem::symlink_status( destLink, statusEc );
        // libc++ (unlike the letter of the standard) sets ec=ENOENT for a plain "nothing there" —
        // that is the ordinary first-install case, not a failure; any OTHER ec is a real one (a
        // symlinked parent directory that can't be traversed, permission denied, ...).
        if( statusEc && statusEc != std::errc::no_such_file_or_directory )
        {
            rw::emitTo( stderr, "ripwire skills install: could not check {}: {}\n", destLink.string(), statusEc.message() );
            continue;   // cannot verify the destination is safe to write — skip rather than risk it
        }
        if( std::filesystem::exists( destStatus ) )
        {
            if( !force ) { continue; }   // arm 3: never overwrite without --force
            std::error_code readEc;
            const std::filesystem::path currentTarget = std::filesystem::read_symlink( destLink, readEc );
            if( readEc || !std::filesystem::is_symlink( destStatus ) || currentTarget != storeFile )
            {
                continue;   // foreign entry or a planted link — --force refuses it exactly like the bare path does
            }
            std::error_code removeEc;
            std::filesystem::remove( destLink, removeEc );
            if( removeEc ) { continue; }
        }
        const Outcome linkResult = linkOrRefuse( storeFile, destLink );
        if( linkResult.ok ) { ++linked; }
    }

    if( !writeManifestV2( skillsDest, executablePath, currentSkillNames ) )
    {
        return { false, "could not write the skills manifest at " + manifestPath.string(), skillsDest, linked, pruned };
    }

    return { true, {}, skillsDest, linked, pruned };
}

// `--hook` merge lands in redhat-et/ripwire#225 task 12. This is deliberately not a stub that quietly
// reports success — CLAUDE.md's "do not add a surface that quietly rounds, guesses, or omits" applies
// to a CLI exit code exactly as much as to the XML map: an agent that installed with `--hook` and got
// rc=0 back would reasonably believe the hook is wired.
inline int mergeHookConfig( std::string_view agentName )
{
    rw::emitTo( stderr, "ripwire skills install --hook: hook merge for '{}' is not implemented yet (redhat-et/ripwire#225 task 12)\n", std::string( agentName ) );
    return 1;
}

inline int runSkillsInstall( int argc, char** argv, std::string_view executablePath )
{
    std::string_view agentArg;
    bool hook = false, contributor = false, force = false, all = false;
    for( int i = 3; i < argc; ++i )
    {
        const std::string_view a = argv[ i ];
        if( a == "--hook" )              { hook = true; }
        else if( a == "--contributor" )  { contributor = true; }
        else if( a == "--force" )        { force = true; }
        else if( a == "--all" )          { all = true; }
        else if( a.rfind( "--", 0 ) == 0 && a.size() > 2 ) { agentArg = a.substr( 2 ); }   // --codex -> "codex"
    }

    if( all )
    {
        const std::vector<rw::AgentConfig> agents = rw::getAgentConfigs();   // src/wrap.h — same detection `wrap --all` uses
        const std::string home = homeDir().string();
        std::vector<std::string> configuredDestPaths;   // dedup by resolved directory: codex and openclaw
                                                          // can share ~/.agents/skills, and counting that
                                                          // twice as "2 agents configured" would overstate
                                                          // distinct work done
        int skipped = 0;
        bool anyFailure = false;   // any per-agent install OR --hook merge failure — --all must not
                                    // exit 0 while quietly having failed one of its agents
        for( const rw::AgentConfig& ac : agents )
        {
            const rw::AgentTarget* row = rw::agentTarget( ac.name );
            if( row == nullptr || row->skillsRoot.empty() ) { continue; }   // no verified skills discovery path for this agent at all — out of scope for --all, not a "skip"

            const std::filesystem::path resolvedDest = rw::resolveSkillsRoot( *row, home );
            std::error_code presentEc;
            // "Configured" for --all means either wrap.h's own config-dir detector says so, OR this
            // agent's skills root itself already looks live (its parent directory exists) — the second
            // check matters because a fresh machine can have ~/.agents present (Codex/openclaw's shared
            // discovery root) without ~/.codex or ~/.openclaw existing yet.
            const bool rootLooksPresent = ac.isInstalled() || std::filesystem::exists( resolvedDest.parent_path(), presentEc );
            if( !rootLooksPresent )
            {
                rw::emitTo( stdout, "ripwire skills install --all: {} skipped (not detected)\n", std::string( ac.name ) );
                ++skipped;
                continue;
            }

            const InstallOutcome result = installForAgent( ac.name, contributor, force, executablePath );
            if( !result.ok )
            {
                rw::emitTo( stderr, "ripwire skills install --all: {}: {}\n", std::string( ac.name ), result.error );
                anyFailure = true;
                continue;
            }
            if( hook && mergeHookConfig( ac.name ) != 0 ) { anyFailure = true; }   // Task 12; today this reports "not implemented" and fails, on purpose — --all must surface that, not swallow it
            rw::emitTo( stdout, "ripwire skills install --all: {} configured ({} linked into {})\n",
                        std::string( ac.name ), result.linked, result.dest.string() );
            const std::string destStr = result.dest.string();
            if( std::find( configuredDestPaths.begin(), configuredDestPaths.end(), destStr ) == configuredDestPaths.end() )
            {
                configuredDestPaths.push_back( destStr );
            }
        }
        rw::emitTo( stdout, "ripwire skills install --all: {} agent(s) configured, {} skipped\n",
                    static_cast<int>( configuredDestPaths.size() ), skipped );
        return anyFailure ? 1 : 0;
    }

    const InstallOutcome result = installForAgent( agentArg, contributor, force, executablePath );
    if( !result.ok )
    {
        rw::emitTo( stderr, "ripwire skills install: {}\n", result.error );
        return 1;
    }
    if( hook )
    {
        return mergeHookConfig( agentArg.empty() ? std::string_view( "claude" ) : agentArg );
    }
    rw::emitTo( stdout, "ripwire skills install: {} skill(s) linked into {}, {} stale entr{} pruned\n",
                result.linked, result.dest.string(), result.pruned, result.pruned == 1 ? "y" : "ies" );
    return 0;
}

}   // namespace rw::skillsinstall
