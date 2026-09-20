#pragma once
#include "infra/emit.h"
#include "infra/jsonesc.h"  // rw::shSingleQuote — the canonical shell single-quoting helper (see its own header comment)
#include "pathguard.h"
#include "embedded_skills.h"
#include "wrap.h"   // AgentTarget / agentTarget / kAgentTargets / AgentConfig / getAgentConfigs / resolveSkillsRoot —
                    // per-agent destinations and --all's presence detection are wrap.h's, not a second table here.

#include "infra/envutil.h"   // rw::envOr
#include "infra/os.h"

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <string_view>
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
    ~FdGuard() { if( fd >= 0 ) { os::close( fd ); } }
    FdGuard( const FdGuard& ) = delete;
    FdGuard& operator=( const FdGuard& ) = delete;
};

using rw::envOr;

// HOME, verbatim — empty when unset, NEVER a default. A silent fallback (this used to be "/tmp") would
// write real files somewhere the operator never chose; every caller below refuses instead.
inline std::filesystem::path homeDir()
{
    return std::filesystem::path( envOr( "HOME", "" ) );
}

// ${ENV_VAR:-$HOME/suffix} — the shape every one of this file's agent/data-home overrides uses
// (RIPWIRE_DATA_HOME, CLAUDE_CONFIG_DIR, CODEX_HOME). Empty on failure: ENV_VAR is set but not
// absolute, or ENV_VAR is unset and HOME is empty/relative — never resolves against the process's cwd.
inline std::filesystem::path agentHomeOr( const char* envVar, std::string_view homeSuffix )
{
    const std::string override_ = envOr( envVar, "" );
    if( !override_.empty() )
    {
        const std::filesystem::path p( override_ );
        if( VALIDATE( p.is_absolute() ) ) { return p; }
        return {};
    }
    const std::filesystem::path home = homeDir();
    if( home.empty() || !VALIDATE( home.is_absolute() ) ) { return {}; }
    return home / homeSuffix;
}

// ${RIPWIRE_DATA_HOME:-~/.local/share/ripwire} — same literal path the curl installer already
// stages skills under today (README.md:874,2215,2217); this just versions it.
inline std::filesystem::path dataHome()
{
    return agentHomeOr( "RIPWIRE_DATA_HOME", ".local/share/ripwire" );
}

// Empty when dataHome() failed — never a path built on cwd via an empty prefix.
inline std::filesystem::path skillsStoreDir()
{
    const std::filesystem::path home = dataHome();
    return home.empty() ? std::filesystem::path{} : home / "skills" / std::string( embedded_skills::kStoreKey );
}
inline std::filesystem::path hooksStoreDir()
{
    const std::filesystem::path home = dataHome();
    return home.empty() ? std::filesystem::path{} : home / "hooks" / std::string( embedded_skills::kStoreKey );
}

// ── the small POSIX-call-named group (Amendment 3): every OS-differing call in this file lives here,
//    so a later port to rw::os::... is a mechanical rename with no logic change. ──────────────────────

// ::rename() the temp extraction directory into its final store location. Returns false on failure;
// the caller decides whether a concurrent winner already occupies the target (see extractGroup).
inline bool renameAtomic( const std::filesystem::path& from, const std::filesystem::path& to )
{
    return os::rename( from.c_str(), to.c_str() ) == 0;
}

// ::symlink() storeFile -> destLink. Returns false on failure, with errno left intact for the caller.
inline bool symlinkOrRefuse( const std::filesystem::path& storeFile, const std::filesystem::path& destLink )
{
    return os::symlink( storeFile.c_str(), destLink.c_str() ) == 0;
}

// Write one embedded file's bytes to `dest`, refusing if anything at `dest` already exists as a
// symlink (never write through a planted link — reuses rw::pathguard::isSymlink, the shared predicate,
// rather than a second lstat/S_ISLNK check). O_EXCL means "fail if it exists at all" — combined with a
// fresh temp directory per extraction attempt (see ensureStoreExtracted), a partial write can never
// masquerade as a complete one. This is a genuinely different case from pathguard's
// openNoFollowTruncate (which TRUNCATES an existing regular file, sidecar-style): store extraction must
// never succeed against an already-existing file, since the store is immutable-by-hash and a fresh temp
// directory should never have pre-existing content.
inline Outcome writeStoreFile( const std::filesystem::path& dest, std::string_view bytes, os::mode_t mode )
{
    EXPECTS( !dest.empty() && !bytes.empty(), "writeStoreFile: an embedded skill/hook file is baked in at build "
                                               "time and is never empty by construction" );
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
    const int fd = os::open( dest.c_str(), O_CREAT | O_EXCL | O_NOFOLLOW | O_WRONLY, mode );
    if( fd < 0 )
    {
        return { false, "open(O_EXCL) failed for " + dest.string() + ": " + std::string( std::strerror( errno ) ) };
    }
    FdGuard guard( fd );
    std::size_t written = 0;
    while( written < bytes.size() )
    {
        const os::ssize_t n = os::write( fd, bytes.data() + written, bytes.size() - written );
        if( n < 0 )
        {
            if( errno == EINTR ) { continue; }
            return { false, "write failed for " + dest.string() + ": " + std::string( std::strerror( errno ) ) };
        }
        written += static_cast<std::size_t>( n );
    }
    return { true, {} };
}

// True iff every embedded file in `files` exists under `storeRoot` with byte-identical content — the
// only way `storeRoot`'s NAME (a content-hash key) can be trusted without opening what it names. Opened
// O_NOFOLLOW (never follow a symlink planted at a store file's name) and compared by size then bytes;
// the reference bytes are already resident in the binary, so this costs one read per file, not a hash.
template <std::size_t N>
inline bool storeContentsMatch( const std::array<embedded_skills::EmbeddedFile, N>& files, const std::filesystem::path& storeRoot )
{
    for( const embedded_skills::EmbeddedFile& f : files )
    {
        const std::filesystem::path path = storeRoot / std::string( f.relativePath );
        const int fd = os::open( path.c_str(), O_RDONLY | O_NOFOLLOW );
        if( fd < 0 ) { return false; }
        FdGuard guard( fd );
        os::stat_t st{};
        if( os::fstat( fd, &st ) != 0 || !S_ISREG( st.st_mode ) ) { return false; }
        if( static_cast<std::uintmax_t>( st.st_size ) != f.bytes.size() ) { return false; }
        std::string buf( f.bytes.size(), '\0' );
        std::size_t readSoFar = 0;
        while( readSoFar < buf.size() )
        {
            const os::ssize_t n = os::read( fd, buf.data() + readSoFar, buf.size() - readSoFar );
            if( n < 0 ) { if( errno == EINTR ) { continue; } return false; }
            if( n == 0 ) { return false; }   // short read: truncated/corrupted, never matches
            readSoFar += static_cast<std::size_t>( n );
        }
        if( buf != f.bytes ) { return false; }
    }
    return true;
}

// Extract every entry in `files` under `storeRoot`, via a fresh temp sibling directory that is
// atomic-renamed into place only once every file is written — a killed/interrupted run can never
// leave a directory with the final name that reads back as "already extracted, trust it".
template <std::size_t N>
inline Outcome extractGroup( const std::array<embedded_skills::EmbeddedFile, N>& files, const std::filesystem::path& storeRoot, os::mode_t mode )
{
    std::error_code ec;
    // immutable-by-hash: already extracted AND verified. `mode` is not part of `kStoreKey`, so an
    // existing store's file modes are never re-verified/updated here — a store extracted before a
    // `mode` change stays on its old modes until removed and re-extracted. A name match alone is not
    // trusted: `storeRoot` must be a real directory (not a symlink someone planted at that name) whose
    // contents are byte-identical to the binary's own embedded copy; anything else — missing, a link,
    // a partial extraction a killed run left behind, tampering — is re-extracted from scratch below.
    os::stat_t rootSt{};
    const bool rootIsRealDir = os::lstat( storeRoot.c_str(), &rootSt ) == 0 && S_ISDIR( rootSt.st_mode );
    if( rootIsRealDir && storeContentsMatch( files, storeRoot ) ) { return { true, {} }; }
    if( rootIsRealDir ) { std::filesystem::remove_all( storeRoot, ec ); }   // stale/corrupted — clear it; a symlink at this name is removed as itself, never followed

    const std::filesystem::path tmp = storeRoot.parent_path() / ( ".tmp-" + std::to_string( os::getpid() ) + "-" + storeRoot.filename().string() );
    std::filesystem::remove_all( tmp, ec );
    for( const embedded_skills::EmbeddedFile& f : files )
    {
        const Outcome o = writeStoreFile( tmp / std::string( f.relativePath ), f.bytes, mode );
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
    const std::filesystem::path skillsRoot = skillsStoreDir();
    const std::filesystem::path hooksRoot  = hooksStoreDir();
    if( skillsRoot.empty() || hooksRoot.empty() )
    {
        return { false, "could not resolve a data home for the skills store: set RIPWIRE_DATA_HOME to an "
                         "absolute path, or HOME to an absolute path" };
    }
    // Skill files are markdown — never executable. Hook scripts (hooks/*.sh) are tracked at 0755 in
    // the repo and must stay executable: settings.json's --hook registration (mergeHookConfig below)
    // writes the extracted path as a bare `command`, which the shell execs directly — 0644 would make
    // every installed hook silently unrunnable (verified: `sh -c "<0644 path>"` fails, Permission
    // denied, exit 126). The group-level split is sufficient: no file in either group mixes with the
    // other today.
    if( const Outcome o = extractGroup( embedded_skills::kSkillFiles, skillsRoot, 0644 ); !o.ok ) { return o; }
    return extractGroup( embedded_skills::kHookFiles, hooksRoot, 0755 );
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

// True iff a SKILL.md's own bytes declare "audience: contributor" in its YAML front matter (the
// region between the opening "---" line and the next one). Scanning only that region — not the whole
// file — matters: a plain substring scan over the WHOLE body would let a skill that merely MENTIONS
// "contributor" in its prose (ripwire-opt-remarks' own body does, among others) flip the gate.
inline bool isContributorOnlyFrontMatter( std::string_view bytes )
{
    if( !bytes.starts_with( "---" ) ) { return false; }   // no front matter — nothing to gate on
    const std::size_t closing = bytes.find( "\n---", 3 );
    const std::string_view frontMatter = ( closing == std::string_view::npos ) ? bytes : bytes.substr( 0, closing );
    return frontMatter.find( "audience: contributor" ) != std::string_view::npos;
}

// True iff `skillDir`'s embedded SKILL.md is contributor-only. `ripwire-opt-remarks` is the one such
// skill in the embedded set today.
inline bool skillDirIsContributorOnly( std::string_view skillDir )
{
    for( const embedded_skills::EmbeddedFile& f : embedded_skills::kSkillFiles )
    {
        if( !f.relativePath.ends_with( "/SKILL.md" ) ) { continue; }
        if( skillDirNameOf( f.relativePath ) != std::string( skillDir ) ) { continue; }
        return isContributorOnlyFrontMatter( f.bytes );
    }
    return false;   // no SKILL.md found for this dir — a build defect, treated as "not gated" not "gated"
}

// Extract "<name>" out of a Hermes-native embedded skill's relativePath ("skills/hermes/<name>/
// SKILL.md", ...) — the third path component. Returns empty for anything not under skills/hermes/.
inline std::string hermesSkillDirNameOf( std::string_view relativePath )
{
    const std::filesystem::path rel( relativePath );
    auto it = rel.begin();
    if( it == rel.end() || *it != "skills" ) { return {}; }
    ++it;
    if( it == rel.end() || *it != "hermes" ) { return {}; }
    ++it;
    if( it == rel.end() ) { return {}; }
    return it->string();
}

// Every `skill=<name>` line the PREVIOUS run's manifest recorded — this installer's own name for "I
// created this entry", independent of where it currently points (a manifest-tracked name is prunable
// by pruneStale below regardless of target; an untracked one needs pruneTargetIsOurs). Empty (not an
// error) when there is no manifest yet, matches every other "nothing there yet" sidecar reader.
inline std::vector<std::string> readManifestSkillNames( const std::filesystem::path& skillsDest )
{
    std::vector<std::string> names;
    rw::pathguard::NoFollowRead in = rw::pathguard::openNoFollowRead( "the skills manifest", ( skillsDest / ".ripwire-manifest-v2" ).string() );
    if( !in.opened ) { return names; }
    std::string line;
    while( in.readLine( line ) )
    {
        if( line.rfind( "skill=", 0 ) != 0 ) { continue; }
        const std::string name = line.substr( 6 );
        // The manifest is external input (on-disk, hand-editable) — VALIDATE, not ASSUME. Nothing here
        // refuses on a false result: pruneStale's own `ripwire-*` directory-entry filter is the actual
        // gate a malformed name would have to pass, so a bad line here is a trace, not a silent trust.
        if( !VALIDATE( !name.empty() && name.rfind( "ripwire-", 0 ) == 0 ) ) { continue; }
        names.push_back( name );
    }
    return names;
}

// Write the sidecar: schema version, the embedded store's content-hash key (`source=`), and one
// `skill=` line per name in `skillNames`. Goes through pathguard's createExclTempFile/commit — a
// temp built beside the sidecar, then renamed over it — so a crash mid-write, or a symlink planted at
// the final name, can never leave a truncated or link-followed manifest.
//
// `source=` MUST be `embedded_skills::kStoreKey` (a `<version>-<hash8>` string) — codexdoctor.h's
// `skillsCheck` compares this same field against that exact value to decide `stale`. It was
// previously the resolved BINARY PATH, which can never equal a version-hash string, so `stale` was
// `true` on every real install, forever; see the "fresh real install must not read stale"
// end-to-end arm in test/skillsinstallcheck.sh, and test/doctorstalecheck.sh's own hand-constructed
// fixtures for the reader side of this contract.
inline bool writeManifestV2( const std::filesystem::path& skillsDest, const std::vector<std::string>& skillNames )
{
    const std::filesystem::path manifestPath = skillsDest / ".ripwire-manifest-v2";
    std::string body = "version=2\nsource=" + std::string( embedded_skills::kStoreKey ) + "\n";
    for( const std::string& s : skillNames ) { body += "skill=" + s + "\n"; }
    rw::pathguard::ExclTempFile temp = rw::pathguard::createExclTempFile( manifestPath.string() + ".tmp.", "", 0666 );
    if( !temp.ok() || !temp.write( body ) ) { return false; }
    return temp.commit( manifestPath.string() );
}

// True iff `entry` is safe to prune: EITHER its target is dangling (nothing of the user's is there to
// lose — the same C1 reasoning linkOrRefuse's dangling-repair case uses), OR its target resolves under
// `ourStoreRoot` (this installer's own store, any version key — an orphaned symlink from a superseded
// version is still ours). A LIVE symlink pointing anywhere else is a user's own asset that merely
// happens to be named `ripwire-<something>`, and a name match alone is not ownership.
inline bool pruneTargetIsOurs( const std::filesystem::path& entry, const std::filesystem::path& ourStoreRoot )
{
    std::error_code readEc;
    const std::filesystem::path target = std::filesystem::read_symlink( entry, readEc );
    if( readEc ) { return false; }   // could not even read the link — leave it alone
    const std::filesystem::path resolved = target.is_absolute() ? target : ( entry.parent_path() / target );
    std::error_code existsEc;
    if( !std::filesystem::exists( resolved, existsEc ) ) { return true; }   // dangling: safe regardless of where it pointed
    const std::string resolvedStr = resolved.lexically_normal().string();
    const std::string rootStr     = ourStoreRoot.lexically_normal().string();
    return resolvedStr.compare( 0, rootStr.size(), rootStr ) == 0;
}

// Remove every `ripwire-*` symlink actually sitting in `destDir` that is no longer in
// `currentSkillNames`. Scans the directory itself, not just the previous manifest's `skill=` lines: a
// stray entry the manifest never tracked (hand-planted, left by an older installer, ...) is exactly as
// stale, and manifest-only pruning leaves it forever (I7's ripwire-* filter still applies, so a
// non-skill entry is never touched). A name the previous manifest DID track is prunable regardless of
// its current target — this installer's own record that it created that entry is ownership proof on
// its own (the manifest might record a name whose target a user later hand-edited; that is still this
// installer's slot to reclaim). An UNTRACKED name additionally needs pruneTargetIsOurs, so a user's
// own symlink that merely happens to be named `ripwire-<something>` is left alone — a name match alone
// is not ownership.
inline int pruneStale( const std::filesystem::path& destDir, const std::vector<std::string>& currentSkillNames )
{
    const std::vector<std::string> previousManifestNames = readManifestSkillNames( destDir );
    const std::filesystem::path ourStoreRoot = dataHome() / "skills";
    int removed = 0;
    std::error_code ec;
    for( std::filesystem::directory_iterator it( destDir, ec ), end; !ec && it != end; it.increment( ec ) )
    {
        if( ec ) { break; }
        const std::string name = it->path().filename().string();
        if( name.rfind( "ripwire-", 0 ) != 0 ) { continue; }
        if( std::find( currentSkillNames.begin(), currentSkillNames.end(), name ) != currentSkillNames.end() ) { continue; }
        if( !rw::pathguard::isSymlink( it->path().string() ) ) { continue; }
        const bool manifestTracked = std::find( previousManifestNames.begin(), previousManifestNames.end(), name ) != previousManifestNames.end();
        if( !manifestTracked && !pruneTargetIsOurs( it->path(), ourStoreRoot ) ) { continue; }
        if( os::unlink( it->path().c_str() ) == 0 ) { ++removed; }
    }
    return removed;
}

// Everything one agent's install needs, for the caller to report (bare install, one line; `--all`,
// one line per agent) without re-deriving it. `linked` counts every skill whose destination ends the
// run pointing at this store's file — newly created, repaired, or already correct — NOT "how many
// symlink() calls this run made"; `failed` counts entries that did NOT reach that state (a real
// failure, not the ordinary "already exists, no --force" skip — see installForAgent's own comment).
// `ok=false` is reserved for "could not even attempt the install" (bad destination, extraction
// failure, ...); a partial in-loop failure is reported through `failed`, not by flipping `ok`, so the
// caller can tell "nothing was attempted" from "most of it worked, N entries did not" — collapsing
// those into one bit was the C2 finding (a permission-denied install exited 0 with a manifest that
// claimed full success).
struct InstallOutcome
{
    bool ok = false;
    std::string error;
    std::filesystem::path dest;
    int linked = 0;
    int pruned = 0;
    int failed = 0;
    // A foreign-but-live entry refused because --force was not given (I1, round-2 review) —
    // distinct from `failed`, which is an attempted-and-failed link.
    int foreignSkipped = 0;
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
// `explicitDest`, when non-empty, is the CLI surface's DEST_PATH form
// ([--claude|--codex|--codex-legacy|--hermes|--openclaw|--all|DEST_PATH]) — mirrors skills/install.sh's
// own pre-#225 `mode="path"` branch (`dst="$explicitPath"`): the path IS the skills root itself, used
// verbatim, with no agent lookup at all. `agentName` is then irrelevant to destination resolution (it
// still selects nothing here — contributor filtering below is agent-independent) and is ignored.
// A skill to link: `name` is the destination symlink's own name, `storeSub` is its path fragment
// under skillsStoreDir()/"skills" (equal to `name` for a flat skill, "hermes/<name>" for a
// Hermes-native one).
struct SkillEntry
{
    std::string name;
    std::string storeSub;
};

// The current, deduped set of skills `effectiveAgent` should link, contributor-gated. Every agent
// links the flat "ripwire-*" set; --hermes additionally links skills/hermes/ripwire-*/ (Hermes-native
// content, e.g. ripwire-repo-map), skipped when the flat set already ships a same-named entry (mirrors
// skills/install.sh's pre-#225 Hermes loop: one link wins, and a non-"ripwire-*" entry under hermes/ is
// never this installer's to touch).
inline std::vector<SkillEntry> collectCurrentSkills( std::string_view effectiveAgent, bool contributor )
{
    std::vector<SkillEntry> currentSkills;
    for( const embedded_skills::EmbeddedFile& f : embedded_skills::kSkillFiles )
    {
        const std::string skillDir = skillDirNameOf( f.relativePath );
        if( skillDir.empty() || skillDir.rfind( "ripwire-", 0 ) != 0 ) { continue; }
        if( std::any_of( currentSkills.begin(), currentSkills.end(), [ & ]( const SkillEntry& e ) { return e.name == skillDir; } ) ) { continue; }
        if( !contributor && skillDirIsContributorOnly( skillDir ) ) { continue; }   // --contributor gate
        currentSkills.push_back( { skillDir, skillDir } );
    }
    if( effectiveAgent == "hermes" )
    {
        for( const embedded_skills::EmbeddedFile& f : embedded_skills::kSkillFiles )
        {
            if( !f.relativePath.ends_with( "/SKILL.md" ) ) { continue; }
            const std::string hermesDir = hermesSkillDirNameOf( f.relativePath );
            if( hermesDir.empty() || hermesDir.rfind( "ripwire-", 0 ) != 0 ) { continue; }
            if( std::any_of( currentSkills.begin(), currentSkills.end(), [ & ]( const SkillEntry& e ) { return e.name == hermesDir; } ) ) { continue; }
            if( !contributor && isContributorOnlyFrontMatter( f.bytes ) ) { continue; }   // --contributor gate
            currentSkills.push_back( { hermesDir, "hermes/" + hermesDir } );
        }
    }
    return currentSkills;
}

inline InstallOutcome installForAgent( std::string_view agentName, bool contributor, bool force,
                                        const std::filesystem::path& explicitDest = {} )
{
    const Outcome extracted = ensureStoreExtracted();
    if( !extracted.ok ) { return { false, extracted.error, {}, 0, 0 }; }

    std::filesystem::path skillsDest;
    if( !explicitDest.empty() )
    {
        skillsDest = explicitDest;
    }
    else
    {
        const std::string effectiveAgent = agentName.empty() ? std::string( "claude" ) : std::string( agentName );
        const bool        isCodexLegacy  = ( effectiveAgent == "codex-legacy" );
        // codex-legacy shares codex's row for everything (contributor filtering, future hook behavior) —
        // only its resolved destination differs, so the table lookup below is by "codex" for that case.
        const rw::AgentTarget* row = rw::agentTarget( isCodexLegacy ? std::string_view( "codex" ) : std::string_view( effectiveAgent ) );
        if( row == nullptr || row->skillsRoot.empty() )
        {
            return { false, "no verified skills discovery path for '" + effectiveAgent + "'", {}, 0, 0 };
        }
        if( isCodexLegacy )
        {
            const std::filesystem::path codexHome = agentHomeOr( "CODEX_HOME", ".codex" );
            skillsDest = codexHome.empty() ? std::filesystem::path{} : ( codexHome / "skills" );
        }
        else
        {
            skillsDest = rw::resolveSkillsRoot( *row, homeDir().string() );
        }
        if( skillsDest.empty() )
        {
            return { false, "could not resolve skills destination for '" + effectiveAgent + "'", {}, 0, 0 };
        }
    }

    std::error_code mkdirEc;
    std::filesystem::create_directories( skillsDest, mkdirEc );
    if( mkdirEc )
    {
        return { false, "create_directories failed for " + skillsDest.string() + ": " + mkdirEc.message(), skillsDest, 0, 0 };
    }

    const std::string effectiveAgentForSkills = agentName.empty() ? std::string( "claude" ) : std::string( agentName );
    const std::vector<SkillEntry> currentSkills = collectCurrentSkills( effectiveAgentForSkills, contributor );
    std::vector<std::string> currentSkillNames;
    for( const SkillEntry& e : currentSkills ) { currentSkillNames.push_back( e.name ); }

    const std::filesystem::path manifestPath = skillsDest / ".ripwire-manifest-v2";
    const int pruned = pruneStale( skillsDest, currentSkillNames );

    // C1/C2 (2026-09-18 review round 1): `linkedNames` is what actually ends the run pointing at THIS
    // store's file — not "every name we attempted", which is what `currentSkillNames` is and what the
    // manifest wrote unconditionally before this fix. A run that fails half its links must not claim
    // the other half in the manifest; a later prune reading that manifest would then unlink entries
    // that were never actually placed.
    std::vector<std::string> linkedNames;
    int failed = 0;
    int foreignSkipped = 0;
    const auto reportFailed = [ & ]( const std::string& msg )
    {
        rw::emitTo( stderr, "ripwire skills install: {}\n", msg );
        ++failed;
    };
    for( const SkillEntry& entry : currentSkills )
    {
        const std::string& skillDir = entry.name;
        const std::filesystem::path destLink = skillsDest / skillDir;
        const std::filesystem::path storeFile = skillsStoreDir() / "skills" / entry.storeSub;
        std::error_code statusEc;
        const std::filesystem::file_status destStatus = std::filesystem::symlink_status( destLink, statusEc );
        // libc++ (unlike the letter of the standard) sets ec=ENOENT for a plain "nothing there" —
        // that is the ordinary first-install case, not a failure; any OTHER ec is a real one (a
        // symlinked parent directory that can't be traversed, permission denied, ...).
        if( statusEc && statusEc != std::errc::no_such_file_or_directory )
        {
            reportFailed( "could not check " + destLink.string() + ": " + statusEc.message() );
            continue;   // cannot verify the destination is safe to write — skip rather than risk it
        }
        // `std::filesystem::exists( file_status )` is true for a SYMLINK regardless of whether its
        // target resolves — symlink_status reports the link itself (type()==symlink), never the
        // dangling-ness of what it points at. Before this fix that made EVERY entry here (v1 checkout
        // symlinks included) read as "already exists" and get skipped forever, even when the target no
        // longer existed (redhat-et/ripwire#225 review round 1, C1) — `--force` could not repair it
        // either, since its own check below only ever matched a link already pointing at THIS store.
        if( std::filesystem::exists( destStatus ) && std::filesystem::is_symlink( destStatus ) )
        {
            std::error_code readEc;
            const std::filesystem::path currentTarget = std::filesystem::read_symlink( destLink, readEc );
            if( readEc )
            {
                reportFailed( "could not read the symlink at " + destLink.string() + ": " + readEc.message() );
                continue;
            }
            if( currentTarget == storeFile )
            {
                linkedNames.push_back( skillDir );   // already correct — nothing to write, still counts as linked
                continue;
            }
            // Points somewhere ELSE. Two sub-cases, deliberately treated differently:
            //   - the target does not exist at all (a dangling symlink: a v1 checkout that moved or was
            //     deleted, or a store extracted under an old, now-gone RIPWIRE_DATA_HOME) — nothing of
            //     the user's is there to lose, so this is repaired unconditionally, `--force` or not.
            //     This is the C1 fix: the exact v1-manifest-upgrade repro this task names.
            //   - the target DOES exist (a foreign symlink, or a still-live old checkout) — `--force`
            //     is required, same as it always was for anything not already ours; this is what
            //     test/skillsinstallcheck.sh arm 3 (a planted symlink into a real, live directory)
            //     pins, and that contract is intentionally NOT loosened by this fix.
            std::error_code existsFollowEc;
            const bool danglingTarget = !std::filesystem::exists( destLink, existsFollowEc );   // follows the link
            if( !danglingTarget && !force )
            {
                ++foreignSkipped;
                continue;   // foreign, live entry, no --force: refused exactly like the bare-path case (arm 3)
            }
            std::error_code removeEc;
            std::filesystem::remove( destLink, removeEc );
            if( removeEc )
            {
                reportFailed( "could not remove the stale link at " + destLink.string() + ": " + removeEc.message() );
                continue;
            }
        }
        else if( std::filesystem::exists( destStatus ) )
        {
            // A real file or directory sits at this name — never ours to replace, `--force` or not;
            // `--force` licenses relinking a symlink that is stale/foreign, never clobbering real
            // content (that was already the rule; this branch just now REPORTS the refusal instead of
            // silently `continue`-ing past it, per C2).
            if( force )
            {
                reportFailed( "refusing to replace non-symlink content at " + destLink.string() + " even with --force" );
            }
            else
            {
                ++foreignSkipped;
            }
            continue;
        }
        const Outcome linkResult = linkOrRefuse( storeFile, destLink );
        if( linkResult.ok )
        {
            linkedNames.push_back( skillDir );
        }
        else
        {
            reportFailed( linkResult.error );
        }
    }

    // C2: the manifest records what actually linked, not what was attempted — writing
    // `currentSkillNames` here unconditionally is exactly the "intent, not outcome" bug (a failed
    // entry would be declared present, and a later prune reading that manifest would then treat a
    // never-linked name as "still current" instead of pruning it).
    if( !writeManifestV2( skillsDest, linkedNames ) )
    {
        return { false, "could not write the skills manifest at " + manifestPath.string(), skillsDest,
                 static_cast<int>( linkedNames.size() ), pruned, failed, foreignSkipped };
    }

    return { failed == 0, {}, skillsDest, static_cast<int>( linkedNames.size() ), pruned, failed, foreignSkipped };
}

// ── the jq-based settings.json merge (Task 10) ──────────────────────────────────────────────────────
//
// Ported from skills/install.sh's install_claude_hook — that script is still the shipping mechanism
// for a source checkout, so its merge is the reference this has to agree with byte-for-byte in shape.
// The write is the same `mktemp` + rename shape install.sh's own `mv` uses, via
// rw::pathguard::createExclTempFile/ExclTempFile::commit: the temp is created exclusively beside the
// target, and commit()'s rename replaces whatever directory entry sits at the final name — including a
// symlink there, which rename(2) never follows — atomically, with no truncate-then-write window a
// crash mid-write could catch settings.json in.
//
// jq itself still does the actual JSON surgery — reimplementing a JSON merge in C++ to avoid a
// dependency that G3 already tolerates (jq is invoked, not linked; its absence degrades to an
// actionable message, never a crash) would be a second point of truth for a filter this file has to
// keep in lockstep with install.sh's anyway.
//
// runCommandCapture (src/verbs_change.h) is NOT reused here, even though its signature would fit, because
// it is textually unreachable from this file: verbs_change.h opens with
// `#if !defined( RIPWIRE_MAIN_TU ) #error ...`, and RIPWIRE_MAIN_TU is only #defined at main.cpp:529 —
// 477 lines AFTER main.cpp:52's `#include "skillsinstall.h"`. Moving this header's own #include down past
// that point to dodge the guard would put `rw::skillsinstall` inside main.cpp's verb-dispatch anonymous
// namespace instead, a different and equally real problem: `runSkillsInstall` is called elsewhere in
// main.cpp as `rw::skillsinstall::runSkillsInstall` (main.cpp:3485, outside that namespace), so anything
// this header defines from inside it would live in a distinct, unreachable namespace. Its 8 MB head/tail
// capture cap is also sized for build logs, not a settings.json this call then writes back whole. A
// small, local popen() reader — in the same "one small POSIX-call-named function" spirit as
// symlinkOrRefuse/renameAtomic above — is the correctly-scoped tool, not a second general-purpose
// mechanism.

// Run `cmd` through /bin/sh -c via popen(), capturing stdout only (the jq command below redirects its
// own stderr to /dev/null so a parse error never lands in the JSON this writes back). Returns false if
// the shell could not even be started; `exitedNormally`/`exitCode` decode pclose()'s status the same
// way runCommandCapture decodes waitpid's, so a caller can tell "jq is missing" (exit 127) from
// "jq ran and rejected the input" (any other nonzero).
struct ShellCaptureResult
{
    bool        spawned         = false;
    bool        exitedNormally  = false;
    int         exitCode        = -1;
    std::string output;
};

inline ShellCaptureResult runShellCapture( const std::string& cmd )
{
    ShellCaptureResult result;
    FILE* pipe = os::popen( cmd.c_str(), "r" );
    if( pipe == nullptr ) { return result; }
    result.spawned = true;
    char buf[ 4096 ];
    std::size_t n;
    while( ( n = std::fread( buf, 1, sizeof( buf ), pipe ) ) > 0 )
    {
        result.output.append( buf, n );
    }
    const int status = os::pclose( pipe );
    if( status >= 0 && WIFEXITED( status ) )
    {
        result.exitedNormally = true;
        result.exitCode = WEXITSTATUS( status );
    }
    return result;
}

// matcher string is LOAD-BEARING (skills/install.sh:16-33, `hookMatcher`): Claude Code reads a matcher
// made only of letters, digits, `_`, `-`, spaces, `,` and `|` as a literal LIST of exact tool names —
// any other character (the `.*` here) puts it on the regex path instead, where `^(...)$` anchors it to
// a whole-name match. Copied verbatim; do not rederive it.
inline constexpr std::string_view kClaudeHookMatcher = "^(Read|Glob|Grep|Bash|Edit|Write|MultiEdit|NotebookEdit|mcp__ripwire__.*)$";
inline constexpr std::string_view kCodexHookMatcher  = "^(Bash|Read|Glob|Grep|Edit|Write|MultiEdit|NotebookEdit|mcp__ripwire__.*)$";

// `jq --arg NAME VALUE ... PROGRAM FILE`, each token individually single-quoted for the shell via
// rw::shSingleQuote (src/infra/jsonesc.h).
inline void appendJqArg( std::string& out, const std::string& name, const std::string& value )
{
    out += " --arg ";
    out += rw::shSingleQuote( name );
    out += ' ';
    out += rw::shSingleQuote( value );
}

// Runs a jq FILTER (already carrying its own --arg tokens) against `file`, validates the result the
// way skills/install.sh's own `[ -s "$tmp" ] && mv` chain did (an empty or non-zero-exit result never
// overwrites the existing file — a jq failure, e.g. malformed input JSON, is reported, never applied),
// and on success writes the merged JSON back through pathguard. Returns 0 on success, else a message
// already emitted to stderr and the same exit code skills/install.sh used for each case (1 for a
// missing jq / a merge failure / a write failure).
inline int runJqMergeFile( const std::filesystem::path& file, const std::string& jqArgsAndProgram, std::string_view missingJqAdvice )
{
    std::string cmd = "jq";
    cmd += jqArgsAndProgram;
    cmd += ' ';
    cmd += rw::shSingleQuote( file.string() );

    const ShellCaptureResult result = runShellCapture( cmd );
    if( !result.spawned )
    {
        rw::emitTo( stderr, "ripwire skills install: could not start a shell to run jq\n" );
        return 1;
    }
    if( result.exitedNormally && result.exitCode == 127 )
    {
        rw::emitTo( stderr, "ripwire skills install: --hook needs jq on PATH to safely merge {} (not found).\n{}",
                    file.string(), missingJqAdvice );
        return 1;
    }
    if( !result.exitedNormally || result.exitCode != 0 || result.output.empty() )
    {
        rw::emitTo( stderr, "ripwire skills install: --hook merge failed (is {} valid JSON?); nothing changed\n", file.string() );
        return 1;
    }
    rw::pathguard::ExclTempFile temp = rw::pathguard::createExclTempFile( file.string() + ".tmp.", "", 0666 );
    if( !temp.ok() || !temp.write( result.output ) || !temp.commit( file.string() ) )
    {
        rw::emitTo( stderr, "ripwire skills install: could not write the merged hook config to {}\n", file.string() );
        return 1;
    }
    return 0;
}

// True iff `file` already carries an entry under `hooksField` whose command names `scriptName`
// (matched by basename, like `jqIsScript` — skills/install.sh:35-49). A plain boolean `jq -e` probe,
// run before the mutating merge, so the caller can print the right banner (first-registration's full
// disclosure vs. a refresh's one-line notice) BEFORE changing anything, exactly as skills/install.sh
// echoes its banner ahead of the jq call it describes.
inline bool jqScriptAlreadyRegistered( const std::filesystem::path& file, std::string_view hooksField, const std::string& scriptName )
{
    std::string cmd = "jq -e";
    appendJqArg( cmd, "n", scriptName );
    cmd += " 'def isScript($n): (.command // \"\") | split(\" \")[0] | endswith(\"/hooks/\" + $n); any((.hooks.";
    cmd += std::string( hooksField );
    cmd += " // [])[]?.hooks[]?; isScript($n))' ";
    cmd += rw::shSingleQuote( file.string() );
    cmd += " >/dev/null 2>&1";
    return os::system( cmd.c_str() ) == 0;
}

// `--hook` router half: merge/refresh hooks/ripwire-claude-route.sh (the UserPromptSubmit prompt
// router) into `settingsPath`, identified by script basename like the nudge merge above. Ported from
// skills/install.sh's install_claude_route — called unconditionally after the nudge merge, first-time
// or refresh, exactly as that function was called from both of its caller's branches.
inline int mergeClaudeRoute( const std::filesystem::path& settingsPath )
{
    const std::filesystem::path routeScript = hooksStoreDir() / "hooks" / "ripwire-claude-route.sh";
    const bool already = jqScriptAlreadyRegistered( settingsPath, "UserPromptSubmit", "ripwire-claude-route.sh" );

    std::string jqArgs;
    appendJqArg( jqArgs, "cmd", routeScript.string() );
    appendJqArg( jqArgs, "n",   "ripwire-claude-route.sh" );
    std::string jqProgram =
        "def isScript($n): (.command // \"\") | split(\" \")[0] | endswith(\"/hooks/\" + $n);";
    if( already )
    {
        jqProgram += ".hooks.UserPromptSubmit |= map( .hooks |= map( if isScript($n) then .command = $cmd else . end ) )";
    }
    else
    {
        rw::emitTo( stdout,
                    "ripwire skills install --hook will add this OPT-IN, advisory-only entry to {}:\n"
                    "  hooks.UserPromptSubmit += [{{ matcher: \"*\", hooks: [{{ type: \"command\", command: \"{}\" }}] }}]\n"
                    "  behavior: asks ripwire --help-task before the first tool is chosen and, ONLY at high\n"
                    "            confidence, adds one paste-ready command as context. It never blocks a prompt.\n"
                    "  counting: appends one row per prompt to ~/.ripwire/routing.jsonl carrying a CHECKSUM and\n"
                    "            byte length of the prompt and a hashed session id — never the prompt text.\n"
                    "            RIPWIRE_ROUTE_METER=0 opts out of that without disabling routing.\n",
                    settingsPath.string(), routeScript.string() );
        jqArgs += " --argjson tmo 8";
        jqProgram +=
            ".hooks //= {} | .hooks.UserPromptSubmit //= [] | "
            ".hooks.UserPromptSubmit += [{\"matcher\": \"*\", \"hooks\": [{\"type\": \"command\", \"command\": $cmd, \"timeout\": $tmo}]}]";
    }
    jqArgs += ' ';
    jqArgs += rw::shSingleQuote( jqProgram );

    const int rc = runJqMergeFile( settingsPath, jqArgs, "" );
    if( rc == 0 )
    {
        if( already )
        {
            rw::emitTo( stdout, "ripwire UserPromptSubmit router already registered in {} — command refreshed to {}.\n",
                        settingsPath.string(), routeScript.string() );
        }
        else
        {
            rw::emitTo( stdout, "done. Registered ripwire's UserPromptSubmit prompt router in {}.\n", settingsPath.string() );
        }
    }
    return rc;
}

// `--hook`: merge ripwire's PreToolUse (+ SessionStart, on first registration) entries into an agent's
// settings file, identifying any EXISTING registration by the hook script's basename (skills/install.sh's
// `jqIsScript`) rather than by exact path — a machine that has ripwire installed from more than one
// location (a package copy and a git checkout, say) must recognise its own prior registration and
// refresh it in place, never append a second one that doubles every counted call.
inline int mergeClaudeHook( const std::filesystem::path& settingsPath )
{
    const std::filesystem::path nudgeScript = hooksStoreDir() / "hooks" / "ripwire-nudge.sh";   // relativePath is "hooks/<name>" (CMake's group prefix)
    const bool already = jqScriptAlreadyRegistered( settingsPath, "PreToolUse", "ripwire-nudge.sh" );

    // jqIsScript identifies an existing registration by SCRIPT BASENAME, not exact path (skills/
    // install.sh:35-49) — any prior copy's registration is recognised and refreshed, never duplicated.
    // The first-registration branch adds both PreToolUse and SessionStart, exactly as
    // install_claude_hook's "not yet registered" path does; the refresh branch touches only PreToolUse
    // (matcher + command), matching refresh_hook_matcher.
    const std::string jqProgram =
        "def isScript($n): (.command // \"\") | split(\" \")[0] | endswith(\"/hooks/\" + $n);"
        "if any((.hooks.PreToolUse // [])[]?.hooks[]?; isScript($n)) then "
        "  .hooks.PreToolUse |= map( if any(.hooks[]?; isScript($n)) "
        "    then .matcher = $m | .hooks |= map( if isScript($n) then .command = $cmd else . end ) "
        "    else . end ) "
        "else "
        "  .hooks //= {} | "
        "  .hooks.PreToolUse //= [] | "
        "  .hooks.PreToolUse += [{\"matcher\": $m, \"hooks\": [{\"type\": \"command\", \"command\": $cmd}]}] | "
        "  .hooks.SessionStart //= [] | "
        "  .hooks.SessionStart += [{\"matcher\": \"startup|resume|clear\", \"hooks\": [{\"type\": \"command\", \"command\": $scmd}]}] "
        "end";

    if( already )
    {
        rw::emitTo( stdout, "ripwire PreToolUse hook already registered in {} ({}) — refreshing its matcher.\n",
                    settingsPath.string(), nudgeScript.string() );
    }
    else
    {
        // Read and Glob are in the matcher deliberately: the whole-file read is the largest token sink
        // in an agent loop and the one default a skill description cannot intercept. mcp__ripwire__.*
        // is in the matcher for the substitution meter: it counts ripwire's own calls as the
        // numerator, and an agent that prefers the MCP server to the CLI would otherwise be a pure
        // undercount (docs/SUBSTITUTION_METER.md). Ported verbatim from skills/install.sh's own banner
        // (the D2 fix — a shorter wording read as anonymous counts/metadata and was not honest about
        // what the meter actually captures).
        rw::emitTo( stdout,
                    "ripwire skills install --hook will add these OPT-IN, advisory-only entries to {}:\n"
                    "  hooks.PreToolUse  += [{{ matcher: \"{}\", hooks: [{{ type: \"command\", command: \"{}\" }}] }}]\n"
                    "  hooks.SessionStart += [{{ matcher: \"startup|resume|clear\", hooks: [{{ type: \"command\", command: \"{} --session-start\" }}] }}]\n"
                    "  behavior: never blocks/denies/rewrites a tool call, and since 2026-09-02 never speaks on it\n"
                    "            either — the advisory nudge was measured inert and retired (docs/EVALS.md §4).\n"
                    "            What remains on PreToolUse is the substitution meter and the router's adoption\n"
                    "            observation. The SessionStart entry still injects the use-when guidance.\n"
                    "  counting: appends one JSONL row per observed call to ~/.ripwire/substitution.jsonl, and that row\n"
                    "            carries the RAW file path (Read, and the Edit/Write/MultiEdit/NotebookEdit target), RAW\n"
                    "            grep/glob pattern, the first 200 B of the RAW command (Bash), or an MCP verb's symbol/file\n"
                    "            arguments you just passed, plus the absolute repo path and session id — in cleartext.\n"
                    "            Local-only: this file is never transmitted anywhere, but it has no automatic retention\n"
                    "            limit and grows for as long as counting stays on. RIPWIRE_METER=0 opts out of counting\n"
                    "            (the nudge itself keeps working). Details: docs/SUBSTITUTION_METER.md.\n"
                    "  remove:   delete those two entries from {} (or re-run with the entries already absent).\n",
                    settingsPath.string(), kClaudeHookMatcher, nudgeScript.string(), nudgeScript.string(), settingsPath.string() );
    }

    std::string jqArgs;
    appendJqArg( jqArgs, "cmd",  nudgeScript.string() );
    appendJqArg( jqArgs, "scmd", nudgeScript.string() + " --session-start" );
    appendJqArg( jqArgs, "m",    std::string( kClaudeHookMatcher ) );
    appendJqArg( jqArgs, "n",    "ripwire-nudge.sh" );
    jqArgs += ' ';
    jqArgs += rw::shSingleQuote( jqProgram );

    const std::string missingJqAdvice = std::format(
        "Add these by hand instead:\n"
        "  hooks.PreToolUse   += [{{\"matcher\":\"{}\",\"hooks\":[{{\"type\":\"command\",\"command\":\"{}\"}}]}}]\n"
        "  hooks.SessionStart += [{{\"matcher\":\"startup|resume|clear\",\"hooks\":[{{\"type\":\"command\",\"command\":\"{} --session-start\"}}]}}]\n",
        kClaudeHookMatcher, nudgeScript.string(), nudgeScript.string() );
    const int rc = runJqMergeFile( settingsPath, jqArgs, missingJqAdvice );
    if( rc != 0 ) { return rc; }
    rw::emitTo( stdout, "done. Registered ripwire's PreToolUse meter + SessionStart primer hooks in {}.\n", settingsPath.string() );
    return mergeClaudeRoute( settingsPath );
}

// `--codex --hook`: merge Codex's prompt router (UserPromptSubmit), PreToolUse nudge and SessionStart
// primer into Codex's own hooks.json schema, in one jq call. Ported from skills/install.sh's
// install_codex_hook — that merge identifies an existing entry by EXACT command match, not by script
// basename (unlike the Claude merge above): Codex has exactly one supported install channel today (no
// package-manager copy to reconcile with a checkout the way Claude's does), so the simpler exact match
// is what the reference implementation used and this keeps agreeing with it byte-for-byte.
inline int mergeCodexHook( const std::filesystem::path& settingsPath )
{
    const std::filesystem::path hookScript  = hooksStoreDir() / "hooks" / "ripwire-codex-nudge.sh";
    const std::filesystem::path routeScript = hooksStoreDir() / "hooks" / "ripwire-codex-route.sh";

    const std::string jqProgram =
        "$cmd as $cmd | $scmd as $scmd | $rcmd as $rcmd | "
        ".hooks //= {} | .hooks.PreToolUse //= [] | .hooks.SessionStart //= [] | .hooks.UserPromptSubmit //= [] | "
        "if any(.hooks.PreToolUse[]?.hooks[]?; .command == $cmd) then "
        "  .hooks.PreToolUse |= map(if any(.hooks[]?; .command == $cmd) then .matcher = $m else . end) "
        "else "
        "  .hooks.PreToolUse += [{\"matcher\": $m, \"hooks\": [{\"type\": \"command\", \"command\": $cmd, "
        "    \"timeout\": 3, \"statusMessage\": \"Checking for a cheaper Ripwire CLI query\"}]}] "
        "end | "
        "if any(.hooks.SessionStart[]?.hooks[]?; .command == $scmd) then "
        "  .hooks.SessionStart |= map(if any(.hooks[]?; .command == $scmd) then .matcher = \"^(startup|resume|clear|compact)$\" else . end) "
        "else "
        "  .hooks.SessionStart += [{\"matcher\": \"^(startup|resume|clear|compact)$\", \"hooks\": [{\"type\": \"command\", "
        "    \"command\": $scmd, \"timeout\": 3, \"statusMessage\": \"Loading Ripwire CLI-first guidance\", "
        "    \"additionalContextLimit\": 2000}]}] "
        "end | "
        "if any(.hooks.UserPromptSubmit[]?.hooks[]?; .command == $rcmd) then "
        "  .hooks.UserPromptSubmit |= map(if any(.hooks[]?; .command == $rcmd) then .matcher = \".*\" else . end) "
        "else "
        "  .hooks.UserPromptSubmit += [{\"matcher\": \".*\", \"hooks\": [{\"type\": \"command\", \"command\": $rcmd, "
        "    \"timeout\": 6, \"statusMessage\": \"Selecting a focused Ripwire CLI route\", "
        "    \"additionalContextLimit\": 3000}]}] "
        "end";

    rw::emitTo( stdout, "ripwire skills install --codex --hook will add or refresh advisory-only entries in {}.\n", settingsPath.string() );

    std::string jqArgs;
    appendJqArg( jqArgs, "cmd",  hookScript.string() );
    appendJqArg( jqArgs, "scmd", hookScript.string() + " --session-start" );
    appendJqArg( jqArgs, "rcmd", routeScript.string() );
    appendJqArg( jqArgs, "m",    std::string( kCodexHookMatcher ) );
    jqArgs += ' ';
    jqArgs += rw::shSingleQuote( jqProgram );

    const int rc = runJqMergeFile( settingsPath, jqArgs, "" );
    if( rc != 0 ) { return rc; }
    rw::emitTo( stdout, "done. Registered Ripwire's Codex prompt router + PreToolUse nudge + SessionStart primer in {}.\n"
                        "Open /hooks in Codex to review and trust the installed command hooks.\n", settingsPath.string() );
    return 0;
}

inline int mergeHookConfig( std::string_view agentName )
{
    const std::string effectiveAgent = agentName.empty() ? std::string( "claude" ) : std::string( agentName );
    const rw::AgentTarget* row = rw::agentTarget( effectiveAgent );
    if( row == nullptr || !row->hookSlot )
    {
        rw::emitTo( stderr, "ripwire skills install: --hook is not supported for {} yet\n", effectiveAgent );
        return 2;
    }

    const std::filesystem::path agentHome = ( effectiveAgent == "claude" )
        ? agentHomeOr( "CLAUDE_CONFIG_DIR", ".claude" )
        : agentHomeOr( "CODEX_HOME", ".codex" );
    if( agentHome.empty() )
    {
        rw::emitTo( stderr, "ripwire skills install: could not resolve a home for {} — set {} to an absolute "
                             "path, or HOME to an absolute path\n",
                    effectiveAgent, ( effectiveAgent == "claude" ) ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME" );
        return 1;
    }
    const std::filesystem::path settingsPath = ( effectiveAgent == "claude" )
        ? ( agentHome / "settings.json" )
        : ( agentHome / "hooks.json" );
    std::error_code mkdirEc;
    std::filesystem::create_directories( settingsPath.parent_path(), mkdirEc );
    if( mkdirEc )
    {
        rw::emitTo( stderr, "ripwire skills install: could not create {}: {}\n", settingsPath.parent_path().string(), mkdirEc.message() );
        return 1;
    }
    std::error_code existsEc;
    if( !std::filesystem::exists( settingsPath, existsEc ) )
    {
        const rw::pathguard::OpenedFile opened = rw::pathguard::openNoFollowTruncate( "the agent settings file", settingsPath.string() );
        if( opened.fd < 0 ) { return 1; }   // openNoFollowTruncate already emitted the reason
        if( !rw::pathguard::writeAllAndClose( opened.fd, "{}\n" ) )
        {
            rw::emitTo( stderr, "ripwire skills install: could not initialize {}\n", settingsPath.string() );
            return 1;
        }
    }

    return ( effectiveAgent == "claude" ) ? mergeClaudeHook( settingsPath ) : mergeCodexHook( settingsPath );
}

// Accepts ONE bare positional token as the DEST_PATH form of the CLI surface
// ([--claude|--codex|--codex-legacy|--hermes|--openclaw|--all|DEST_PATH]) — mirrors skills/install.sh's
// own pre-#225 `mode="path"` branch. Returns 2 (refusal already emitted to stderr) for an empty token
// or a second one; otherwise records it into `dest`/`given` and returns 0. Split out of
// runSkillsInstall's argv loop so that loop's own five flag checks and this token's own two-way
// refusal stay two small functions instead of one that braids both kinds of branching together.
inline int acceptPositionalDest( std::string_view a, std::string& dest, bool& given )
{
    // An empty token is not a path — refuse it rather than let `installForAgent`'s
    // `!explicitDest.empty()` override fall through silently to the default agent home (the exact
    // silent-misdirection bug this function exists to close).
    if( a.empty() )
    {
        rw::emitTo( stderr, "ripwire skills install: an empty destination path is not a path\n" );
        return 2;
    }
    // Mirrors skills/install.sh's own "only one destination path is allowed" refusal — a second bare
    // token is a mistake to report, never a silent overwrite of the first.
    if( given )
    {
        rw::emitTo( stderr, "ripwire skills install: only one destination path is allowed (already have '{}', got '{}')\n",
                    dest, std::string( a ) );
        return 2;
    }
    dest = std::string( a );
    given = true;
    return 0;
}

// `executablePath` is no longer forwarded into the manifest (writeManifestV2 now writes
// `embedded_skills::kStoreKey` directly — see its own comment) but stays in this signature because
// main.cpp:3485 calls this as `runSkillsInstall( argc, argv, selfExecutablePath( argv[0] ) )`; changing
// that call site is out of scope for this fix.
inline int runSkillsInstall( int argc, char** argv, [[maybe_unused]] std::string_view executablePath )
{
    std::string_view agentArg;
    bool hook = false, contributor = false, force = false, all = false;
    std::string explicitDest;
    bool destGiven = false;
    for( int i = 3; i < argc; ++i )
    {
        const std::string_view a = argv[ i ];
        if( a == "--hook" )              { hook = true; }
        else if( a == "--contributor" )  { contributor = true; }
        else if( a == "--force" )        { force = true; }
        else if( a == "--all" )          { all = true; }
        else if( a.rfind( "--", 0 ) == 0 && a.size() > 2 )
        {
            // M2 (2026-09-18 review round 1): a typo'd or unknown `--flag` used to become `agentArg`
            // silently — it eventually failed, but only downstream in installForAgent, with a message
            // that reads as "no such agent" rather than "no such flag". Refuse it here instead, against
            // the same set wrap.h's own kAgentTargets names plus codex-legacy (a destination override,
            // not a kAgentTargets row — see installForAgent's own comment on it).
            const std::string_view candidate = a.substr( 2 );
            if( rw::agentTarget( candidate ) == nullptr && candidate != "codex-legacy" )
            {
                rw::emitTo( stderr, "ripwire skills install: unknown flag {}\n", std::string( a ) );
                return 2;
            }
            agentArg = candidate;   // --codex -> "codex"
        }
        else
        {
            const int rc = acceptPositionalDest( a, explicitDest, destGiven );
            if( rc != 0 ) { return rc; }
        }
    }

    if( destGiven && hook )
    {
        // Mirrors skills/install.sh's `path) echo "...--hook needs --claude or --codex, not an
        // explicit skill path" ;;` verbatim: an explicit DEST_PATH has no agent identity to register
        // a hook under, so this is refused rather than guessing one.
        rw::emitTo( stderr, "ripwire skills install: --hook needs --claude or --codex, not an explicit skill path\n" );
        return 2;
    }
    if( destGiven && all )
    {
        rw::emitTo( stderr, "ripwire skills install: --all installs to every detected agent's own destination; an explicit path is not supported with --all\n" );
        return 2;
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

            const InstallOutcome result = installForAgent( ac.name, contributor, force );
            if( !result.ok )
            {
                // `result.error` is set only for a could-not-even-attempt failure (bad destination,
                // extraction failure, ...); a per-entry link-loop failure instead leaves it empty and
                // reports through `result.failed` — the per-entry messages already went to stderr as
                // they happened (installForAgent's own reportFailed), this line just states the count
                // so `--all`'s own summary line cannot omit it (C2: a run with any refusal must not
                // read as quiet success).
                rw::emitTo( stderr, "ripwire skills install --all: {}: {}\n", std::string( ac.name ),
                            result.error.empty() ? ( std::to_string( result.failed ) + " skill(s) failed to link" ) : result.error );
                anyFailure = true;
                continue;
            }
            if( hook && mergeHookConfig( ac.name ) != 0 ) { anyFailure = true; }   // Task 12; today this reports "not implemented" and fails, on purpose — --all must surface that, not swallow it
            const std::string allSkippedSuffix = result.foreignSkipped > 0
                ? ( ", " + std::to_string( result.foreignSkipped ) + " skipped (run --force to relink foreign entries)" )
                : std::string{};
            rw::emitTo( stdout, "ripwire skills install --all: {} configured ({} linked into {}{})\n",
                        std::string( ac.name ), result.linked, result.dest.string(), allSkippedSuffix );
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

    const InstallOutcome result = installForAgent( agentArg, contributor, force,
                                                    destGiven ? std::filesystem::path( explicitDest ) : std::filesystem::path{} );
    if( !result.ok )
    {
        // Same split as the --all branch above: an empty `result.error` means the run got as far as
        // attempting links and some of them failed (each already reported to stderr as it happened) —
        // print the count rather than an empty line, and still exit non-zero (C2: a run with any
        // refusal must not exit 0).
        rw::emitTo( stderr, "ripwire skills install: {}\n",
                    result.error.empty() ? ( std::to_string( result.failed ) + " skill(s) failed to link into " + result.dest.string() ) : result.error );
        return 1;
    }
    if( hook )   // destGiven && hook was already refused above, so this is always the agent-flag form here
    {
        return mergeHookConfig( agentArg.empty() ? std::string_view( "claude" ) : agentArg );
    }
    const std::string skippedSuffix = result.foreignSkipped > 0
        ? ( ", " + std::to_string( result.foreignSkipped ) + " skipped (run --force to relink foreign entries)" )
        : std::string{};
    rw::emitTo( stdout, "ripwire skills install: {} skill(s) linked into {}, {} stale entr{} pruned{}\n",
                result.linked, result.dest.string(), result.pruned, result.pruned == 1 ? "y" : "ies", skippedSuffix );
    return 0;
}

}   // namespace rw::skillsinstall
