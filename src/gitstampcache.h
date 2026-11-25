#pragma once

// gitstampcache.h — C1-STAMP: the STAMP record, one small file that lets a served --for skip six git children.
//
// WHAT IT HOLDS. The answers gitstampstore.h collects — HEAD's sha, HEAD's committer time, the 18-month window's boundary
// commit, the repository top level and the shallow bit — each under the exact command line that asked it, together with
// the CONTENT of every file those answers are a function of. A run whose every such file still reads the same is handed
// the stored answers; any other run asks git, exactly as before, and records again.
//
// WHAT THE ANSWERS DEPEND ON, and so what the record keys (each one is a whole-file digest or a presence row, never a
// timestamp — a ref rewritten within one timestamp granule cannot hide behind an equal signature):
//   * discovery — `.git` at every level from the root up to the one that bounds it (present or absent), the `.git` FILE's
//     own bytes when it is a file (a worktree or a submodule: its `gitdir:` line), and the gitdir's `commondir` file;
//   * HEAD — the gitdir's HEAD; when it names a branch, that branch's loose ref file (present or absent) and
//     `packed-refs`; a detached HEAD is its own content;
//   * history — `shallow`, `info/grafts` and `objects/info/alternates`; `refs/replace` and `reftable` must be ABSENT
//     (replace refs and the reftable backend move answers through files this record does not read, so either one
//     present means no record);
//   * configuration — every config file git itself says it read (warmsnap.h collectGitInputs: the repo's config, the
//     worktree's config.worktree, the global and system files, the standard ones that do not exist yet); any of them
//     that mentions `include` means no record, since an include can name a file that does not exist yet;
//   * the environment — HOME, XDG_CONFIG_HOME, PATH, DEVELOPER_DIR and which git PATH finds; the process uid and the
//     owners of the top level and the gitdir (git's safe.directory check). Any GIT_* variable but GIT_TRACE* means the
//     record is neither read nor written: GIT_DIR, GIT_CEILING_DIRECTORIES and their kin redirect discovery itself.
// The command line is the rest of the key: the hardened prefix, the filter pins, the root's spelling, the resolved window
// and the walk budget are all in it (gitstampstore.h), so a question asked differently is a different question.
//
// WHEN IT IS WRITTEN. Only a run that had to ask git, and only when the files above read the same AFTER the run as they
// did before its first git question — the before set is taken before any thread exists, so no answer can predate it.
// Anything unexpected — a file that is a symlink, unreadable or over 64 MiB, a HEAD that is neither a branch nor a sha —
// is doubt, and doubt records nothing.
//
// WHERE IT LIVES. `<cacheDir>/ripwire-qstamp-<rootKey>--<key>.bin` through quality::shaKeyedCachePath, the family shape
// the qchurn walk's own record uses: in the per-user cache directory, swept and pinned with the root's other blobs, never
// beside a --cache file and never inside the tree. It is not a warmsnap section on purpose: a snapshot is rewritten only
// when the tree is, and a commit moves HEAD without touching the tree, so a section there would go stale at the first
// commit and stay stale (served never, re-asked every call) until some file changed. Its own magic and version, a
// checksum over every byte, and an exact root comparison make an old, foreign or torn file a clean miss.
//
// WHO ARMS IT. main.cpp, for a one-shot --for over one git root, after githarden (whose verdict is a filesystem read here:
// it starts no git child on these roots, and a trust decision is not something to replay from a file). Never under
// --no-cache, never for the MCP or LSP servers, and never with RIPWIRE_NO_GITSTAMP_CACHE set.
//
// Gate: test/c1stampcheck.sh.

#include "gitstampstore.h"
#include "quality.h"    // shaKeyedCachePath / cacheRootKeyHex / readQSnapBlob / atomicWriteFile / isBareCommitSha
#include "warmsnap.h"   // collectGitInputs (the config files git read), Out / In (the byte layout), depwatch digests
#include "pathguard.h"
#include "infra/os.h"
#include "infra/Diagnostics.h"
#include "infra/profileScope.h"
#include "infra/tablelookup.h"   // envChoice — the test hook's one-of-N switch

#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw::gitstampcache
{

inline constexpr std::uint64_t kMagic   = 0x0150'4d54'5357'52ull;   // "RWSTMP\x01"
inline constexpr std::uint32_t kVersion = 1;                        // the record's own layout; bump on any change
inline constexpr std::uint64_t kDoubt   = 0x646f'7562'7400'0001ull; // a dependency read that cannot vouch for anything
inline constexpr std::int64_t  kMaxDepBytes = std::int64_t( 64 ) << 20;

// One dependency's reading: a whole file's digest, kAbsent when there is no entry at all, or kDoubt (a symlink, a
// directory, an unreadable or oversized file) — a StatExists row is the plain presence probe warmsnap uses.
inline std::uint64_t readDep( const depwatch::Dep& d )
{
    if( d.seam != depwatch::Seam::WholeFile )
    {
        return warmsnap::answerOf( d );
    }
    os::stat_t st;
    if( os::lstat( d.path.c_str(), &st ) != 0 )
    {
        return ( errno == ENOENT || errno == ENOTDIR ) ? depwatch::kAbsent : kDoubt;
    }
    if( !S_ISREG( st.st_mode ) || std::int64_t( st.st_size ) > kMaxDepBytes )
    {
        return kDoubt;
    }
    const std::optional<std::string> bytes = pathguard::readRegularFileNoFollow( d.path );
    return bytes ? depwatch::digest64( *bytes ) : kDoubt;
}

// The dependency set re-read now; false when any row cannot vouch (kDoubt) or a row's reading moved.
inline bool depsStillRead( const std::vector<depwatch::Dep>& deps )
{
    return std::ranges::all_of( deps, []( const depwatch::Dep& d ) { const std::uint64_t now = readDep( d ); return now != kDoubt && now == d.answer; } );
}

// Test hook (test/c1stampcheck.sh, its mutation controls): RIPWIRE_TEST_GITSTAMP_MUTANT names ONE deliberate defect, so the
// gate shows on the real binary that each invalidation arm can fail. Unset (every ordinary run): None.
enum class StampMutant : std::uint8_t
{
    None,
    Trust,     // a record is served without re-reading its dependencies or its environment key
    GitEnv,    // the GIT_* bypass is skipped: a record is read and written under GIT_DIR, GIT_CEILING_DIRECTORIES and kin
};
inline constexpr std::string_view kStampMutantNames[] = { "trust", "gitenv" };   // the enum's order after None
inline StampMutant stampMutant() { return StampMutant( envChoice( "RIPWIRE_TEST_GITSTAMP_MUTANT", kStampMutantNames ) ); }

// Any GIT_* variable but the trace family redirects git's discovery or configuration: no record is read or written.
inline bool isBypassedByEnvironment()
{
    if( std::getenv( "RIPWIRE_NO_GITSTAMP_CACHE" ) != nullptr )
    {
        return true;
    }
    if( stampMutant() == StampMutant::GitEnv )
    {
        return false;
    }
    for( char** env = os::environment(); env != nullptr && *env != nullptr; ++env )
    {
        const std::string_view var = *env;
        if( var.starts_with( "GIT_" ) && !var.starts_with( "GIT_TRACE" ) )
        {
            return true;
        }
    }
    return false;
}

// The process half of the key: who asks, which git, and where its global configuration lives.
inline std::uint64_t environmentKey( const std::string& topDir, const std::string& gitDir )
{
    warmsnap::Out o;
    o.u32( kVersion );
    o.u64( std::uint64_t( os::getuid() ) );
    for( const char* name : { "HOME", "XDG_CONFIG_HOME", "PATH", "DEVELOPER_DIR" } )
    {
        const char* const value = std::getenv( name );
        o.u8( value != nullptr ? 1 : 0 );
        o.str( value != nullptr ? std::string_view( value ) : std::string_view() );
    }
    const std::string git = os::which( "git" );
    char              real[ PATH_MAX ];
    o.str( !git.empty() && os::realpath( git.c_str(), real ) != nullptr ? std::string_view( real ) : std::string_view( git ) );
    for( const std::string* owned : { &topDir, &gitDir } )
    {
        os::stat_t st;
        o.u64( os::stat( owned->c_str(), &st ) == 0 ? std::uint64_t( st.st_uid ) : ~std::uint64_t( 0 ) );
    }
    return depwatch::digest64( o.bytes );
}

struct Record
{
    std::uint64_t                      envKey = 0;
    std::string                        root;
    std::string                        rootReal;
    std::string                        topDir;
    std::string                        gitDir;
    std::vector<depwatch::Dep>         deps;
    std::vector<gitstampstore::Answer> answers;
};

// ── the dependency set, collected on a recording run ───────────────────────────────────────────────────────────────
namespace detail
{
inline void addWhole( std::vector<depwatch::Dep>& deps, std::string path )
{
    deps.push_back( depwatch::Dep{ std::move( path ), depwatch::Seam::WholeFile, 0 } );
}

inline std::string trimmedLine( std::string_view s )
{
    return std::string( lintdetail::rtrim( s ) );   // git's own rtrim of a pointer or HEAD file
}

inline bool isConfigFile( std::string_view path )
{
    return path.ends_with( "config" ) || path.ends_with( "config.worktree" );
}

// The work tree whose `.git` the presence rows found (the last present row), or "".
inline std::string topDirOf( const std::vector<depwatch::Dep>& rows )
{
    std::string top;
    for( const depwatch::Dep& d : rows )
    {
        if( d.seam == depwatch::Seam::StatExists && d.answer == depwatch::kPresent && d.path.ends_with( "/.git" ) )
        {
            top = d.path.substr( 0, d.path.size() - 5 );
        }
    }
    return top;
}

// Discovery: a `.git` FILE is a pointer whose bytes choose the gitdir, and the gitdir's `commondir` chooses where the refs
// live. Adds both rows; answers the common dir, or nullopt on doubt.
inline std::optional<std::string> addDiscoveryDeps( std::vector<depwatch::Dep>& deps, const std::string& topDir, const std::string& gitDir )
{
    os::stat_t dotGit;
    if( os::lstat( ( topDir + "/.git" ).c_str(), &dotGit ) == 0 && S_ISREG( dotGit.st_mode ) )
    {
        addWhole( deps, topDir + "/.git" );
    }
    addWhole( deps, gitDir + "/commondir" );
    const std::optional<std::string> pointer = pathguard::readRegularFileNoFollow( gitDir + "/commondir" );
    if( !pointer )
    {
        return gitDir;
    }
    const std::string rel     = trimmedLine( *pointer );
    const bool        isPlain = !rel.empty() && !rel.contains( '\0' );
    if( !VALIDATE( isPlain, "gitstampcache: an empty or binary commondir file" ) )
    {
        return std::nullopt;
    }
    return rel.front() == '/' ? rel : gitDir + "/" + rel;
}

// HEAD: a branch names one loose ref (packed-refs is a history row); a detached HEAD is its own content (already a row of
// collectGitInputs); anything else is doubt.
inline bool addHeadDeps( std::vector<depwatch::Dep>& deps, const std::string& gitDir, const std::string& common )
{
    const std::optional<std::string> headBytes = pathguard::readRegularFileNoFollow( gitDir + "/HEAD" );
    if( !VALIDATE( headBytes.has_value(), "gitstampcache: HEAD is not a readable regular file" ) )
    {
        return false;
    }
    const std::string head = trimmedLine( *headBytes );
    if( !head.starts_with( "ref: refs/heads/" ) )
    {
        const bool isDetached = isBareCommitSha( head );
        return VALIDATE( isDetached, "gitstampcache: HEAD is neither a branch nor a commit sha" );
    }
    const std::string_view ref        = std::string_view( head ).substr( 5 );
    const bool             isPlainRef = !ref.contains( ".." ) && !ref.contains( '\0' );
    if( !VALIDATE( isPlainRef, "gitstampcache: a HEAD ref name this record will not follow" ) )
    {
        return false;
    }
    addWhole( deps, common + "/" + std::string( ref ) );
    return true;
}

// History: the files that move what `log` and `rev-parse` see from an unchanged HEAD. Replace refs and the reftable
// backend move answers through files this record does not read, so either one present is doubt (false).
inline bool addHistoryDeps( std::vector<depwatch::Dep>& deps, const std::string& common )
{
    for( const char* tail : { "/packed-refs", "/shallow", "/info/grafts", "/objects/info/alternates" } )
    {
        addWhole( deps, common + tail );
    }
    for( const char* tail : { "/refs/replace", "/reftable" } )
    {
        depwatch::Dep d{ common + tail, depwatch::Seam::StatExists, 0 };
        d.answer = warmsnap::answerOf( d );
        if( d.answer != depwatch::kAbsent )
        {
            return false;
        }
        deps.push_back( std::move( d ) );
    }
    return true;
}

// Every row read by THIS record's rules (collectGitInputs read its own without the symlink refusal); false on doubt, and on
// any configuration that mentions `include`, which can name a file that does not exist yet.
inline bool readAllDeps( std::vector<depwatch::Dep>& deps )
{
    for( depwatch::Dep& d : deps )
    {
        d.answer = readDep( d );
        if( d.answer == kDoubt )
        {
            return false;
        }
        if( d.seam == depwatch::Seam::WholeFile && d.answer != depwatch::kAbsent && isConfigFile( d.path ) )
        {
            const std::optional<std::string> bytes = pathguard::readRegularFileNoFollow( d.path );
            if( !bytes || mention_detail::asciiLower( *bytes ).contains( "include" ) )
            {
                return false;
            }
        }
    }
    return true;
}
}   // namespace detail

// One git child (collectGitInputs: the gitdir, the common dir and every config file git read), then the files above.
// nullopt is doubt: no record this run.
inline std::optional<Record> collectRecord( const std::string& root, const std::string& rootReal )
{
    PROFILE_SCOPE_DESCRIBE( "gitstampcache: collect the STAMP dependencies (one git child, recording runs only)" );
    const warmsnap::GitInputs g = warmsnap::collectGitInputs( rootReal );
    constexpr std::string_view kIndex = "/index";
    if( !g.usable || !g.indexPath.ends_with( kIndex ) )
    {
        return std::nullopt;
    }
    Record rec;
    rec.root     = root;
    rec.rootReal = rootReal;
    rec.gitDir   = g.indexPath.substr( 0, g.indexPath.size() - kIndex.size() );
    rec.topDir   = detail::topDirOf( g.files );
    rec.deps     = g.files;
    if( rec.topDir.empty() )
    {
        return std::nullopt;
    }
    const std::optional<std::string> common = detail::addDiscoveryDeps( rec.deps, rec.topDir, rec.gitDir );
    if( !common || !detail::addHeadDeps( rec.deps, rec.gitDir, *common ) || !detail::addHistoryDeps( rec.deps, *common ) || !detail::readAllDeps( rec.deps ) )
    {
        return std::nullopt;
    }
    rec.envKey = environmentKey( rec.topDir, rec.gitDir );
    return rec;
}

// ── bytes out / bytes in ────────────────────────────────────────────────────────────────────────────────────────────
inline std::string serialize( const Record& rec )
{
    warmsnap::Out o;
    o.u64( kMagic );
    o.u32( kVersion );
    o.u64( rec.envKey );
    for( const std::string* s : { &rec.root, &rec.rootReal, &rec.topDir, &rec.gitDir } )
    {
        o.str( *s );
    }
    o.u64( rec.deps.size() );
    for( const depwatch::Dep& d : rec.deps )
    {
        o.str( d.path );
        o.u8( std::uint8_t( d.seam ) );
        o.u64( d.answer );
    }
    o.u64( rec.answers.size() );
    for( const gitstampstore::Answer& a : rec.answers )
    {
        o.str( a.cmd );
        o.u32( std::uint32_t( a.status ) );
        o.u64( a.lines.size() );
        for( const std::string& line : a.lines )
        {
            o.str( line );
        }
    }
    o.u64( depwatch::digest64( o.bytes ) );
    return std::move( o.bytes );
}

inline constexpr std::uint64_t kMaxRows = 4096;

namespace detail
{
// A u64 row count (refused past kMaxRows), then `readRow( in )` per row into `rows`; false once the input ran out or a row
// was refused.
template <class Row, class ReadRow>
inline bool readRows( warmsnap::In& in, std::vector<Row>& rows, ReadRow&& readRow )
{
    const std::uint64_t count = in.u64();
    if( !VALIDATE( in.ok && count <= kMaxRows, "gitstampcache: a record claiming more rows than it may hold" ) )
    {
        return false;
    }
    for( std::uint64_t i = 0; i < count && in.ok; ++i )
    {
        std::optional<Row> row = readRow( in );
        if( !row )
        {
            return false;
        }
        rows.push_back( std::move( *row ) );
    }
    return in.ok;
}

inline std::optional<depwatch::Dep> readDepRow( warmsnap::In& in )
{
    depwatch::Dep d;
    d.path                  = in.str();
    const std::uint8_t seam = in.u8();
    d.answer                = in.u64();
    if( !VALIDATE( seam < std::uint8_t( depwatch::Seam::Count ), "gitstampcache: a dependency row of no known kind" ) )
    {
        return std::nullopt;
    }
    d.seam = depwatch::Seam( seam );
    return d;
}

inline std::optional<gitstampstore::Answer> readAnswerRow( warmsnap::In& in )
{
    gitstampstore::Answer a;
    a.cmd    = in.str();
    a.status = int( in.u32() );
    if( !readRows( in, a.lines, []( warmsnap::In& at ) { return std::optional<std::string>( at.str() ); } ) )
    {
        return std::nullopt;
    }
    return a;
}
}   // namespace detail

inline std::optional<Record> deserialize( std::string_view bytes )
{
    if( !VALIDATE( bytes.size() > 8, "gitstampcache: a record too short to hold its checksum" ) )
    {
        return std::nullopt;
    }
    const std::string_view body = bytes.substr( 0, bytes.size() - 8 );
    warmsnap::In           tail( bytes.substr( body.size() ) );
    const std::uint64_t    stored = tail.u64();
    if( !VALIDATE( stored == depwatch::digest64( body ), "gitstampcache: a record whose checksum fails" ) )
    {
        return std::nullopt;
    }
    warmsnap::In        in( body );
    const std::uint64_t magic   = in.u64();
    const std::uint32_t version = in.u32();
    if( !VALIDATE( magic == kMagic && version == kVersion, "gitstampcache: not a STAMP record of this version" ) )
    {
        return std::nullopt;
    }
    Record rec;
    rec.envKey = in.u64();
    for( std::string* s : { &rec.root, &rec.rootReal, &rec.topDir, &rec.gitDir } )
    {
        *s = in.str();
    }
    const bool isWhole = detail::readRows( in, rec.deps, detail::readDepRow ) && detail::readRows( in, rec.answers, detail::readAnswerRow ) && in.p == in.e;
    if( !VALIDATE( isWhole, "gitstampcache: a record with a bad row or trailing bytes" ) )
    {
        return std::nullopt;
    }
    return rec;
}

// ── the session main.cpp holds for one --for ────────────────────────────────────────────────────────────────────────
// arm() loads and checks the record (serving its answers) or collects a fresh dependency set (recording); the destructor
// records what the run asked git, when the dependencies still read as they did at arm().
class Session
{
public:
    Session() = default;
    Session( const Session& )            = delete;
    Session& operator=( const Session& ) = delete;
    ~Session() { finish(); }

    void arm( const std::string& root, bool isWanted )
    {
        if( !isWanted || isBypassedByEnvironment() || !hasEnclosingGitRepo( root ) )
        {
            return;
        }
        char real[ PATH_MAX ];
        if( os::realpath( root.c_str(), real ) == nullptr )
        {
            return;
        }
        const std::string rootReal( real );
        path_ = quality::shaKeyedCachePath( "qstamp", quality::cacheRootKeyHex( root ), std::string{}, root + '\x1f' + rootReal );
        std::optional<Record> loaded;
        if( const std::optional<std::string> bytes = quality::readQSnapBlob( path_ ) )
        {
            loaded = deserialize( *bytes );
        }
        const bool isTrusted = stampMutant() == StampMutant::Trust;   // c1stampcheck's control: a record served unchecked
        const bool isServed  = loaded && loaded->root == root && loaded->rootReal == rootReal
                            && ( isTrusted || ( loaded->envKey == environmentKey( loaded->topDir, loaded->gitDir ) && depsStillRead( loaded->deps ) ) );
        if( isServed )
        {
            rec_ = std::move( *loaded );
        }
        else if( std::optional<Record> fresh = collectRecord( root, rootReal ) )
        {
            rec_ = std::move( *fresh );
        }
        else
        {
            DISCLOSE( Diagnostics::answerUnchanged, "no STAMP record this run: every small git question is asked, as without one" );
            return;
        }
        gitstampstore::Table&             t = gitstampstore::table();
        const std::lock_guard<std::mutex> guard( t.lock );
        t.root     = root;
        t.rootReal = rootReal;
        t.served   = isServed ? rec_.answers : std::vector<gitstampstore::Answer>{};
        t.offered.clear();
        isArmed_ = true;
    }

private:
    void finish() noexcept
    {
        if( !isArmed_ )
        {
            return;
        }
        isArmed_ = false;
        try
        {
            std::vector<gitstampstore::Answer> offered;
            {
                gitstampstore::Table&             t = gitstampstore::table();
                const std::lock_guard<std::mutex> guard( t.lock );
                offered = std::move( t.offered );
                t.root.clear();
                t.rootReal.clear();
                t.served.clear();
                t.offered.clear();
            }
            if( offered.empty() )
            {
                return;   // every answer was served: the record on disk already holds them
            }
            // the bracket: what git said this run is recorded only if nothing it depends on moved since arm()
            if( rec_.envKey != environmentKey( rec_.topDir, rec_.gitDir ) || !depsStillRead( rec_.deps ) )
            {
                DISCLOSE( Diagnostics::answerUnchanged, "a dependency moved during the run: nothing is recorded, the next run asks git again" );
                return;
            }
            for( gitstampstore::Answer& a : offered )
            {
                rec_.answers.push_back( std::move( a ) );
            }
            std::ranges::sort( rec_.answers, []( const gitstampstore::Answer& a, const gitstampstore::Answer& b ) { return a.cmd < b.cmd; } );
            if( !quality::atomicWriteFile( path_, serialize( rec_ ) ) )
            {
                DISCLOSE( Diagnostics::answerUnchanged, "the STAMP record could not be written: the next run asks git again" );
            }
        }
        catch( ... )   // a destructor must not throw; a record not written only makes the next run ask git
        {
            DISCLOSE( Diagnostics::answerUnchanged, "recording the STAMP record failed: the next run asks git again" );
        }
    }

    std::string path_;
    Record      rec_;
    bool        isArmed_ = false;
};

}   // namespace rw::gitstampcache
