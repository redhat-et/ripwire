#pragma once
#include "infra/emit.h"
#include "pathguard.h"
#include "embedded_skills.h"

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

// Write the minimal `.ripwire-manifest-v2` sidecar this dispatch's arm 1 gate checks for: which
// executable performed the install (`source=`), and the manifest schema version. The richer manifest
// (per-agent entries, prune inventory, tracked-link bookkeeping) is Task 8's scope — this is only the
// two fields a fresh install already needs to record honestly. Goes through pathguard's
// openNoFollowTruncate (Amendment 2/3): this sidecar is rewritten on every install, so it is a
// truncate-an-existing-file case, not an extraction-into-a-fresh-directory case.
inline bool writeManifestV2( const std::filesystem::path& skillsDest, std::string_view executablePath )
{
    const std::filesystem::path manifestPath = skillsDest / ".ripwire-manifest-v2";
    const rw::pathguard::OpenedFile opened = rw::pathguard::openNoFollowTruncate( "the skills manifest", manifestPath.string() );
    if( opened.fd < 0 ) { return false; }
    const std::string body = "version=2\nsource=" + std::string( executablePath ) + "\n";
    return rw::pathguard::writeAllAndClose( opened.fd, body );
}

inline int runSkillsInstall( int /*argc*/, char** /*argv*/, std::string_view executablePath )
{
    const Outcome extracted = ensureStoreExtracted();
    if( !extracted.ok )
    {
        rw::emitTo( stderr, "ripwire skills install: {}\n", extracted.error );
        return 1;
    }

    const std::filesystem::path dest = envOr( "CLAUDE_CONFIG_DIR", ( homeDir() / ".claude" ).string() );
    const std::filesystem::path skillsDest = std::filesystem::path( dest ) / "skills";
    std::error_code mkdirEc;
    std::filesystem::create_directories( skillsDest, mkdirEc );
    if( mkdirEc )
    {
        rw::emitTo( stderr, "ripwire skills install: create_directories failed for {}: {}\n", skillsDest.string(), mkdirEc.message() );
        return 1;
    }

    std::vector<std::string> seen;
    int linked = 0;
    for( const embedded_skills::EmbeddedFile& f : embedded_skills::kSkillFiles )
    {
        const std::string skillDir = skillDirNameOf( f.relativePath );
        // Claude-default mode links only the flat "ripwire-*" set, matching skills/install.sh's own
        // Claude-mode loop (`for d in "$src"/ripwire-*/`) — skills/hermes/ is Hermes-native content
        // that install.sh only links under --hermes, and never under the bare "hermes" name.
        if( skillDir.empty() || skillDir.rfind( "ripwire-", 0 ) != 0 ) { continue; }
        bool already = false;
        for( const std::string& name : seen )
        {
            if( name == skillDir ) { already = true; break; }
        }
        if( already ) { continue; }
        seen.push_back( skillDir );

        const std::filesystem::path destLink = skillsDest / skillDir;
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
        if( std::filesystem::exists( destStatus ) ) { continue; }   // arm 3: never overwrite
        const Outcome linkResult = linkOrRefuse( skillsStoreDir() / "skills" / skillDir, destLink );
        if( linkResult.ok ) { ++linked; }
    }

    if( !writeManifestV2( skillsDest, executablePath ) )
    {
        rw::emitTo( stderr, "ripwire skills install: could not write the skills manifest at {}\n", ( skillsDest / ".ripwire-manifest-v2" ).string() );
        return 1;
    }

    rw::emitTo( stdout, "ripwire skills install: {} skill(s) linked into {}\n", linked, skillsDest.string() );
    return 0;
}

}   // namespace rw::skillsinstall
