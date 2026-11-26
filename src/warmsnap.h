#pragma once
// warmsnap.h — the warm snapshot: one file in ripwire's own cache directory, derived from a parse cache blob.
//
// WHAT IT HOLDS. Three sections, each the stored OUTCOME of a deterministic stage a warm run otherwise repeats:
//   TREE   the crawl's answer (files, the oversize drops, the skip taxonomy) and the stat signature of every directory
//          and entry the walk looked at, plus the inputs of git's ignore answer. A run whose every signature still
//          matches REPLAYS the crawl: no directory is read and no git child is started.
//   MODEL  the assembled IngestResult for the flagless map (warmsnap_model.h).
//   GRAPH  the resolved Graph (warmsnap_graph.h): every field buildGraph computes, and the files it read to do so.
//
// WHERE IT LIVES, AND WHY NOWHERE ELSE (owner ruling 2026-11-15, superseding this lane's two earlier placements).
// The snapshot is `<cacheDir>/ripwire-warmsnap-<rootKey>-<optionsKey>-<blobIdentity>.bin`, in the per-user cache
// directory every other derived cache of this tool already uses (quality::cacheDirLadder) — not beside the blob,
// and not inside it. Both of those were tried and both broke a contract this project gates:
//   * BESIDE IT (`<cache>.snap`) breaks test/cacheidentitycheck.sh arm (D3): `--cache=PATH` writes exactly the file
//     the user named, and nothing whose name starts with it. That artifact is often a committed `--index-out` a CI
//     job consumes by its exact name.
//   * INSIDE IT (a blob section) breaks test/portablecachecheck.sh arm (a): a committed blob is read-shared by many
//     checkouts, and a consuming run must not mutate the artifact another checkout owns. It also reintroduced #334's
//     thrash in a new place — `optionsKey` below folds in the root spelling, its realpath and the cwd, so two
//     checkouts of one committed blob can never agree on one section and would refuse and rewrite each other's on
//     every run.
// The cache directory has neither problem, and it is already swept (quality::evictOldCacheFamily) and already in
// `--doctor`'s cache-dir accounting. What the two rejected placements bought was a STRUCTURAL binding to the records
// the model was assembled from; the name buys the same thing. `blobIdentity` is the blob's own trailer digest
// (ingest_cache.h cacheBlobIdentity), so a blob that is rewritten, replaced or deleted names a different snapshot
// or none, and no stored field has to be right about it. A missing or refused snapshot is exactly today's run.
//
// THE NAME'S THREE FIELDS are ordered the way every other family here orders its own (quality::shaKeyedCachePath),
// and for the same two reasons. `rootKey` (quality::cacheRootKeyHex — the same 16 hex the root's own lean and rich
// blobs carry) is FIRST because the byte-budget sweep pins one root's whole family by reading that field off a
// single filename, so a snapshot is pinned and evicted ALONGSIDE the blob it belongs to and never against it
// (test/evictioncheck.sh arms (k)/(l)). `rootKey`-`optionsKey` is then the eviction GROUP (keep 1): one
// configuration keeps one snapshot, and two configurations never meet at one path, which is what makes the thrash
// above impossible rather than merely unlikely.
//
// WHEN IT IS SERVED — the whole contract. A stale parse cache costs time; a stale snapshot is a wrong answer at exit 0.
// So invalidation is strictly coarser than the blob's:
//   * the header carries this build's SOURCE IDENTITY (quality::producerIdentity: the SHA-256 of src/ and queries/), the
//     format version, the ABI, and a digest of every option, path spelling and environment variable the crawl, the
//     ingest or the resolver reads. Any difference refuses the whole file.
//   * one checksum covers every byte of the file. A flipped bit anywhere refuses the whole file.
//   * GRAPH and MODEL are keyed on the TREE KEY: a digest of every crawled file's root-relative path and content hash,
//     in crawl order. One changed, added or removed file moves it and refuses both.
//   * GRAPH also lists every file the resolver read outside the parse cache (infra/depwatch.h); each read is repeated
//     and compared before the graph is served.
//   * TREE is trusted only while every recorded signature — (device, inode, size, mtime, ctime) — still matches, and
//     is never recorded while any of them is younger than two seconds before the recording crawl began (the racy rule:
//     a change inside the timestamp granule of the recording could otherwise hide behind an equal signature).
//
// A refusal changes cost, never content: the run walks, decodes and resolves as it always did, then records again.
#include "model.h"
#include "infra/depwatch.h"
#include "infra/os.h"
#include "infra/statclock.h"   // saturatingNanoseconds
#include "infra/Diagnostics.h"
#include "infra/profileScope.h"
#include "pathguard.h"
#include "quality.h"   // producerIdentity, atomicWriteFile, cacheDirLadder / resolveCacheBlobPath / evictOldCacheFamily
#include "infra/jsonesc.h"   // rw::shSingleQuote
#include "infra/sortutil.h"  // svLess: string_view order without libstdc++'s length subtraction
#include "gitcmd.h"    // rw::gitCmd — the hardened git prefix, for the one config listing a recording run asks for

#include <atomic>
#include <cstdint>
#include <cstring>
#include <format>      // the snapshot's name: its options key and the blob identity it is derived from
#include <optional>    // readRegularFileNoFollow's answer: the file's bytes, or "there is none"
#include <span>
#include <string>
#include <string_view>
#include <thread>
#include <type_traits>
#include <vector>


namespace rw::warmsnap
{

inline constexpr std::uint64_t kMagic   = 0x0150'414e'5357'52ull;   // "RWSNAP\x01"
inline constexpr std::uint32_t kVersion = 7;                        // bump on ANY layout change in the three sections
                                                                    // 7: lane deps-reread — each GRAPH dependency row carries its file's settled StatSig
                                                                    // 6: lane theta11c — CrawlSkips gains the extensionless rows + count (θ11's grep population)
                                                                    // 5: lane m1b-tracked-dirs — CrawlSkips gains the untracked-build rows + count (TREE and MODEL)
                                                                    // 4: lane qd-tangle — SymRow's two pad bytes carry Symbol::steer and ::dispatchShare (3 is held by in-flight lanes)
                                                                    // 3: the GRAPH section carries Graph::provenSites (PROVEN-SITE-KEEPS-NAMESAKES)
                                                                    // 2: the MODEL section dropped its stored stat signature of the blob — the
                                                                    //    blob's identity is in this file's NAME, so that binding is structural
                                                                    //    and there is no field left to be wrong about it (see the note above).
                                                                    // 1: the `<cache>.snap` sidecar's layout.
inline constexpr std::size_t   kHeaderBytes = 112;
inline constexpr long long     kRacySlackNs = 2'000'000'000ll;      // FAT keeps 2 s timestamps; nothing coarser is in use

// Why the best fast path was not taken: one word on the snapshot-stats line.
enum class Why : std::uint8_t
{
    Ok, Off, Absent, Version, Producer, Options, Checksum, NoSection, Racy, TreeMoved, GitMoved, Stale, Dep, Count
};
inline constexpr const char* kWhyNames[] = { "ok", "off", "absent", "version", "producer", "options", "checksum", "no-section", "racy",
                                             "tree-moved", "git-moved", "stale", "dep" };
static_assert( std::size( kWhyNames ) == std::size_t( Why::Count ), "every Why needs its name on the snapshot-stats line" );

// ── bytes out / bytes in ────────────────────────────────────────────────────────────────────────────────────────────
// Arrays are written as raw rows behind a u64 count; a row type must be trivially copyable with no padding byte, so the
// file's bytes are a function of the values alone (the determinism contract) and a read is one memcpy.
template <class T>
concept RawRow = std::is_trivially_copyable_v<T> && ( std::has_unique_object_representations_v<T> || std::is_floating_point_v<T> );   // a float row is its computed bit pattern

struct Out
{
    std::string bytes;
    // `n` rows as their object bytes: the one append every writer below goes through
    template <RawRow T> void put( const T* p, std::size_t n ) { bytes.append( reinterpret_cast<const char*>( p ), n * sizeof( T ) ); }
    template <RawRow T> void pod( const T& v ) { put( &v, 1 ); }
    void u64( std::uint64_t v ) { pod( v ); }
    void u32( std::uint32_t v ) { pod( v ); }
    void u8( std::uint8_t v ) { pod( v ); }
    template <class Count, RawRow T> void counted( std::span<const T> all ) { pod( Count( all.size() ) ); put( all.data(), all.size() ); }
    void str( std::string_view s ) { counted<std::uint32_t, char>( s ); }
    template <RawRow T> void rows( const T* p, std::size_t n ) { counted<std::uint64_t, T>( { p, n } ); }
    template <RawRow T> void vec( const std::vector<T>& v ) { rows( v.data(), v.size() ); }
    // a counted family of records with no raw layout: the count, then `one( record )` for each
    template <class Range, class Fn> void each( const Range& records, Fn&& one )
    {
        pod( std::uint64_t( std::ranges::size( records ) ) );
        std::ranges::for_each( records, one );
    }
    void strs( const std::vector<std::string>& v ) { each( v, [ this ]( const std::string& s ) { str( s ); } ); }
};

// Every read is bounds-checked against the section; one failure latches `ok` false and every later read answers empty,
// so a reader checks once, at the end, and a short or misshapen section is refused whole.
struct In
{
    const char* p  = nullptr;
    const char* e  = nullptr;
    bool        ok = true;
    explicit In( std::string_view s ) noexcept : p( s.data() ), e( s.data() + s.size() ) {}
    const char* take( std::size_t n ) noexcept
    {
        if( !ok || !VALIDATE( std::size_t( e - p ) >= n, "warmsnap: a section ends inside a field" ) )
        {
            ok = false;
            return nullptr;
        }
        const char* const at = p;
        p += n;
        return at;
    }
    template <RawRow T> T pod() noexcept
    {
        T v{};
        if( const char* at = take( sizeof( T ) ) ) { std::memcpy( &v, at, sizeof( T ) ); }
        return v;
    }
    std::uint64_t u64() noexcept { return pod<std::uint64_t>(); }
    std::uint32_t u32() noexcept { return pod<std::uint32_t>(); }
    std::uint8_t  u8() noexcept { return pod<std::uint8_t>(); }
    std::string_view view() noexcept
    {
        const std::uint32_t n  = u32();
        const char* const   at = take( n );
        return at != nullptr ? std::string_view( at, n ) : std::string_view{};
    }
    std::string str() { return std::string( view() ); }
    // the row count of an array whose rows are `rowBytes` each: refused when the section cannot hold that many
    std::size_t count( std::size_t rowBytes ) noexcept
    {
        const std::uint64_t n = u64();
        if( !ok || !VALIDATE( n <= std::uint64_t( e - p ) / std::max<std::size_t>( rowBytes, 1 ), "warmsnap: an array claims more rows than its section holds" ) )
        {
            ok = false;
            return 0;
        }
        return std::size_t( n );
    }
    template <RawRow T> void vec( std::vector<T>& v )
    {
        const std::size_t n = count( sizeof( T ) );
        v.resize( n );
        if( const char* at = take( n * sizeof( T ) ); at != nullptr && n != 0 ) { std::memcpy( static_cast<void*>( v.data() ), at, n * sizeof( T ) ); }
    }
    std::size_t left() const noexcept { return std::size_t( e - p ); }   // bytes not yet read: no array holds more rows than that
    void strs( std::vector<std::string>& v )
    {
        const std::size_t n = count( sizeof( std::uint32_t ) );
        v.clear();
        if( n > left() ) { ok = false; return; }   // count() already held n to the bytes left: said again where the allocation is
        v.reserve( n );
        for( std::size_t i = 0; i < n && ok; ++i ) { v.emplace_back( view() ); }
    }
};

// A list of paths in walk or sorted order, front-coded: each is the bytes it shares with the one before it (a count) and
// its own tail. A crawl's paths repeat their directory, so the list stores about a quarter of its characters.
inline void writePaths( Out& o, std::size_t n, const auto& pathAt )
{
    o.u64( n );
    std::string_view prev;
    for( std::size_t i = 0; i < n; ++i )
    {
        const std::string_view path = pathAt( i );
        const std::size_t shared = std::min<std::size_t>( std::size_t( std::ranges::mismatch( prev, path ).in1 - prev.begin() ), 0xFFFFu );
        o.pod( std::uint16_t( shared ) );
        o.str( path.substr( shared ) );
        prev = path;
    }
}
inline void readPaths( In& in, std::vector<std::string>& paths )
{
    const std::size_t n = in.count( 6 );
    paths.clear();
    if( n > in.left() ) { in.ok = false; return; }   // count() already held n to the bytes left: said again where the allocation is
    paths.reserve( n );
    for( std::size_t i = 0; i < n && in.ok; ++i )
    {
        const std::size_t      shared = in.pod<std::uint16_t>();
        const std::string_view tail   = in.view();
        if( !VALIDATE( i == 0 ? shared == 0 : shared <= paths.back().size(), "warmsnap: a front-coded path shares more than the path before it holds" ) )
        {
            in.ok = false;
            return;
        }
        std::string path;
        path.reserve( shared + tail.size() );
        if( i != 0 ) { path.assign( paths.back(), 0, shared ); }
        path.append( tail );
        paths.push_back( std::move( path ) );
    }
}

// ── stat signatures ─────────────────────────────────────────────────────────────────────────────────────────────────
struct StatSig
{
    std::int64_t  size    = -1;   // all -1: the path could not be stat'd (which is itself a signature: it must still fail)
    std::int64_t  mtimeNs = -1;
    std::int64_t  ctimeNs = -1;
    std::uint64_t inode   = 0;
    std::uint64_t device  = 0;
    bool operator==( const StatSig& ) const noexcept = default;
};
static_assert( RawRow<StatSig> && sizeof( StatSig ) == 40, "StatSig is a raw 40 B row of the TREE section" );

inline StatSig statSig( const char* path, bool follow ) noexcept
{
    os::stat_t st;
    StatSig    sig;
    if( ( follow ? os::stat( path, &st ) : os::lstat( path, &st ) ) != 0 )
    {
        return sig;
    }
    sig.size    = std::int64_t( st.st_size );
    sig.mtimeNs = saturatingNanoseconds( os::st_mtim( st ) );
    sig.ctimeNs = saturatingNanoseconds( os::st_ctim( st ) );
    sig.inode   = std::uint64_t( st.st_ino );
    sig.device  = std::uint64_t( st.st_dev );
    return sig;
}

// One path the crawl looked at. `follow` 0: lstat (a directory, or a symlink's own entry); 1: stat (what a file entry
// resolves to — the object the crawl sized and the parse pool read).
struct WatchedPath
{
    std::string  path;
    std::uint8_t follow = 0;
};

// fn( i ) for every i in [0, n), on up to hardware_concurrency threads; fn must touch only slot i and shared atomics.
template <class Fn>
inline void parallelFor( std::size_t n, Fn&& fn )
{
    const std::size_t workers = std::min<std::size_t>( std::max<unsigned>( std::thread::hardware_concurrency(), 1u ), ( n + 2047 ) / 2048 );
    if( workers <= 1 )
    {
        for( std::size_t i = 0; i < n; ++i ) { fn( i ); }
        return;
    }
    std::atomic<std::size_t> next{ 0 };
    const auto body = [ & ]() noexcept
    {
        for( std::size_t at = next.fetch_add( 256, std::memory_order_relaxed ); at < n; at = next.fetch_add( 256, std::memory_order_relaxed ) )
        {
            for( std::size_t i = at; i < std::min( n, at + 256 ); ++i ) { fn( i ); }
        }
    };
    std::vector<std::thread> pool;
    pool.reserve( workers - 1 );
    for( std::size_t t = 1; t < workers; ++t ) { pool.emplace_back( body ); }
    body();
    for( std::thread& th : pool ) { th.join(); }
}

// ── what the crawl hands over while it walks (ingest_crawl.h collectSources) ────────────────────────────────────────
struct TreeCapture
{
    std::vector<WatchedPath> watched;        // every directory (lstat) and every other entry (stat) the walk met, walk order
    std::vector<std::string> ignoredDirs;    // the directories pruned ONLY because git's answer listed them
    bool                     on     = false; // false: nobody is recording, and every call below is one test and a return
    bool                     usable = true;  // false: the walk hit something a replay cannot stand for (a memory stop, an unreadable level)
    bool                     readGitIndex = false;   // M1: the walk asked git what it tracks, so the INDEX is one of its inputs

    void unreplayable() noexcept { usable = false; }
    // M1: the tracked-build-dir probe ran (ingest_crawl.h CrawlNamePrune). Under --no-ignore no ignore probe ran, so without
    // this recordTree would leave the index unwatched and replay a crawl a `git add` had changed.
    void gitIndexRead() noexcept { readGitIndex = true; }
    // the root itself, through any link that names it
    void root( const std::string& path )
    {
        if( on ) { watched.push_back( { path, 1 } ); }
    }
    // One entry of a walked directory, twice when it is a link. A DIRECTORY entry is watched as itself (lstat, `follow` 0) and,
    // through a link — never entered, but probed for its sentinels — as what it names. Any OTHER entry is watched as what it
    // resolves to (stat, `follow` 1: the object the crawl sized and the parse pool read) and, when a link, as the link too.
    // `pathOf` is the walk's lazy full-path builder, called only when recording.
    template <class Entry, class PathOf> void entry( const Entry& dirent, PathOf&& pathOf, std::uint8_t follow )
    {
        if( !on ) { return; }
        std::error_code ec;
        watched.push_back( { pathOf(), follow } );
        if( dirent.is_symlink( ec ) ) { watched.push_back( { pathOf(), std::uint8_t( 1 - follow ) } ); }
    }
    // a directory pruned only by git's verdict: watched in depth, since that verdict depends on what is inside it
    template <class PathOf> void ignoredDir( bool prunedByIgnore, PathOf&& pathOf )
    {
        if( on && prunedByIgnore ) { ignoredDirs.push_back( pathOf() ); }
    }
};

// ── the crawl's answer, as stored ───────────────────────────────────────────────────────────────────────────────────
inline void writeSkipRows( Out& o, const std::vector<SkippedFile>& rows )
{
    o.each( rows, [ & ]( const SkippedFile& r ) { o.str( r.path ); o.u64( r.sizeBytes ); o.str( r.ext ); } );
}
inline void readSkipRows( In& in, std::vector<SkippedFile>& rows )
{
    const std::size_t n = in.count( 16 );
    rows.clear();
    if( n > in.left() ) { in.ok = false; return; }
    rows.reserve( n );
    for( std::size_t i = 0; i < n && in.ok; ++i )
    {
        SkippedFile r;
        r.path      = in.str();
        r.sizeBytes = in.u64();
        r.ext       = in.str();
        rows.push_back( std::move( r ) );
    }
}
inline void writeCrawlSkips( Out& o, const CrawlSkips& s )
{
    writeSkipRows( o, s.excluded );  writeSkipRows( o, s.unsupported );  writeSkipRows( o, s.prunedDirRows );  writeSkipRows( o, s.prunedPackageRows );
    writeSkipRows( o, s.ignored );   writeSkipRows( o, s.ignoredDirRows ); writeSkipRows( o, s.nestRefused );  writeSkipRows( o, s.extractPartial );
    writeSkipRows( o, s.escaped );   writeSkipRows( o, s.untrackedBuild );  writeSkipRows( o, s.extensionless );
    for( const std::uint64_t n : { s.excludedFiles, s.unsupportedFiles, s.excludedDirs, s.prunedDirs, s.prunedPackages, s.ignoredFiles, s.ignoredDirs,
                                   s.nestRefusedFiles, s.extractPartialFiles, s.escapedFiles, s.untrackedBuildFiles, s.extensionlessFiles } )
    {
        o.u64( n );
    }
    o.u8( std::uint8_t( s.ignoreMode ) );
    o.each( s.unindexedExts, [ & ]( const UnindexedExt& u ) { o.str( u.ext ); o.u64( u.files ); } );
}
inline void readCrawlSkips( In& in, CrawlSkips& s )
{
    readSkipRows( in, s.excluded );  readSkipRows( in, s.unsupported );  readSkipRows( in, s.prunedDirRows );  readSkipRows( in, s.prunedPackageRows );
    readSkipRows( in, s.ignored );   readSkipRows( in, s.ignoredDirRows ); readSkipRows( in, s.nestRefused );  readSkipRows( in, s.extractPartial );
    readSkipRows( in, s.escaped );   readSkipRows( in, s.untrackedBuild );  readSkipRows( in, s.extensionless );
    for( std::uint64_t* n : { &s.excludedFiles, &s.unsupportedFiles, &s.excludedDirs, &s.prunedDirs, &s.prunedPackages, &s.ignoredFiles, &s.ignoredDirs,
                              &s.nestRefusedFiles, &s.extractPartialFiles, &s.escapedFiles, &s.untrackedBuildFiles, &s.extensionlessFiles } )
    {
        *n = in.u64();
    }
    const std::uint8_t mode = in.u8();
    if( !VALIDATE( mode <= std::uint8_t( IgnoreMode::RootIgnored ), "warmsnap: an ignore mode this build does not know" ) ) { in.ok = false; }
    s.ignoreMode = IgnoreMode( mode );
    const std::size_t n = in.count( 12 );
    s.unindexedExts.clear();
    if( n > in.left() ) { in.ok = false; return; }
    s.unindexedExts.reserve( n );
    for( std::size_t i = 0; i < n && in.ok; ++i )
    {
        UnindexedExt u;
        u.ext   = in.str();
        u.files = in.u64();
        s.unindexedExts.push_back( std::move( u ) );
    }
}

// ── git's ignore answer: its inputs outside the walked tree ─────────────────────────────────────────────────────────
// `git ls-files --others --ignored --exclude-standard --directory` is a function of (1) the rule files, (2) the index
// (a tracked path is never "other"), (3) which untracked paths exist, and (4) git's configuration. (3) and the in-tree
// rule files are watched paths of the TREE section. This is the rest: every config file git says it read, HEAD (an
// includeIf may key on the branch), info/exclude, the excludes file, the index's signature — and the fact that the
// standard config files which do NOT exist still do not.
struct GitInputs
{
    std::vector<depwatch::Dep> files;       // Seam::WholeFile content digests and Seam::StatExists presence rows
    std::string                indexPath;   // "" when the root is under no git work tree
    StatSig                    indexSig;
    bool                       usable = true;
};

inline std::uint64_t answerOf( const depwatch::Dep& d )
{
    switch( d.seam )
    {
        case depwatch::Seam::WholeFile:
        {
            const std::optional<std::string> bytes = pathguard::readRegularFileNoFollow( d.path );
            return bytes ? depwatch::digest64( *bytes ) : depwatch::kAbsent;
        }
        case depwatch::Seam::StatExists:
        {
            os::stat_t st;
            return os::stat( d.path.c_str(), &st ) == 0 ? depwatch::kPresent : depwatch::kAbsent;
        }
        default:
        {
            return 0;   // no git input uses the other seams: an unknown row never matches
        }
    }
}

inline void watchContent( GitInputs& g, std::string path )
{
    depwatch::Dep d{ std::move( path ), depwatch::Seam::WholeFile, 0 };
    d.answer = answerOf( d );
    g.files.push_back( std::move( d ) );
}
// One shell child, on a recording run only: where the git directory is, and every configuration file git read with the
// excludes file it names. Anything unexpected makes the inputs unusable, and the TREE section is then not written.
inline GitInputs collectGitInputs( const std::string& rootReal )
{
    PROFILE_SCOPE_DESCRIBE( "warmsnap: git ignore inputs (one git child, recording runs only)" );
    GitInputs g;
    // the `.git` that bounds the root, exactly as ingest_crawl.h underGitRoot looks for it: absent at every level below
    std::string dir = rootReal;
    bool        underGit = false;
    for( ;; )
    {
        os::stat_t st;
        const bool here = os::stat( ( dir + "/.git" ).c_str(), &st ) == 0;
        g.files.push_back( { dir + "/.git", depwatch::Seam::StatExists, here ? depwatch::kPresent : depwatch::kAbsent } );
        const std::size_t slash = dir.find_last_of( '/' );
        if( here || slash == std::string::npos || slash == 0 )
        {
            underGit = here;
            break;
        }
        dir.resize( slash );
    }
    if( !underGit )
    {
        return g;   // no git child was started by the crawl either: the presence rows above are the whole input
    }
    const std::string cmd = gitCmd( " -C " ) + shSingleQuote( rootReal ) + " rev-parse --absolute-git-dir --git-common-dir 2>/dev/null && "
                          + gitCmd( " -C " ) + shSingleQuote( rootReal ) + " config --list --show-origin -z 2>/dev/null";
    std::FILE* pipe = os::popen( cmd.c_str(), "r" );
    std::string bytes;
    if( pipe != nullptr )
    {
        char chunk[ 8192 ];
        for( std::size_t n = std::fread( chunk, 1, sizeof( chunk ), pipe ); n > 0 && bytes.size() < ( 4u << 20 ); n = std::fread( chunk, 1, sizeof( chunk ), pipe ) )
        {
            bytes.append( chunk, n );
        }
    }
    const int rc = pipe != nullptr ? os::pclose( pipe ) : -1;
    if( rc != 0 || bytes.size() >= ( 4u << 20 ) )
    {
        g.usable = false;
        return g;
    }
    const std::size_t nl1 = bytes.find( '\n' );
    const std::size_t nl2 = nl1 == std::string::npos ? nl1 : bytes.find( '\n', nl1 + 1 );
    if( nl2 == std::string::npos )
    {
        g.usable = false;
        return g;
    }
    const std::string gitDir = bytes.substr( 0, nl1 );
    std::string       common = bytes.substr( nl1 + 1, nl2 - nl1 - 1 );
    if( common.empty() || common.front() != '/' )
    {
        common = rootReal + "/" + common;   // --git-common-dir answers relative to -C when it is not absolute
    }
    // config --list --show-origin -z: "<origin>\0<key>\n<value>\0" per entry; origin is "file:<path>" for a file
    std::string excludesFile;
    bool        excludesSet = false;
    for( std::size_t at = nl2 + 1; at < bytes.size(); )
    {
        const std::size_t originEnd = bytes.find( '\0', at );
        const std::size_t entryEnd  = originEnd == std::string::npos ? originEnd : bytes.find( '\0', originEnd + 1 );
        if( entryEnd == std::string::npos )
        {
            g.usable = false;
            return g;
        }
        const std::string_view origin( bytes.data() + at, originEnd - at );
        const std::string_view entry( bytes.data() + originEnd + 1, entryEnd - originEnd - 1 );
        if( origin.starts_with( "file:" ) )
        {
            std::string path( origin.substr( 5 ) );
            if( path.empty() || path.front() != '/' )
            {
                path.insert( 0, 1, '/' );   // rootReal + "/" + path, built in place
                path.insert( 0, rootReal );
            }
            if( std::ranges::none_of( g.files, [ & ]( const depwatch::Dep& d ) { return d.seam == depwatch::Seam::WholeFile && d.path == path; } ) )
            {
                watchContent( g, std::move( path ) );
            }
        }
        else if( !origin.starts_with( "command line:" ) )
        {
            g.usable = false;   // a blob: or standard-input origin: configuration this file cannot watch
            return g;
        }
        if( entry.starts_with( "core.excludesfile\n" ) )
        {
            excludesFile = std::string( entry.substr( entry.find( '\n' ) + 1 ) );
            excludesSet  = true;
        }
        at = entryEnd + 1;
    }
    const char* const home = std::getenv( "HOME" );
    const char* const xdg  = std::getenv( "XDG_CONFIG_HOME" );
    const std::string homeDir( home != nullptr ? home : "" );
    const std::string xdgDir = xdg != nullptr && *xdg != '\0' ? std::string( xdg ) : homeDir + "/.config";
    if( excludesSet )
    {
        if( excludesFile.starts_with( "~/" ) )
        {
            excludesFile = homeDir + excludesFile.substr( 1 );
        }
        if( excludesFile.empty() || excludesFile.front() != '/' )
        {
            g.usable = false;   // a relative or ~user excludes file: resolved by rules this file does not reproduce
            return g;
        }
        watchContent( g, std::move( excludesFile ) );
    }
    watchContent( g, xdgDir + "/git/ignore" );      // the default excludes file (read when core.excludesFile is unset; watched either way)
    watchContent( g, xdgDir + "/git/config" );      // the standard config files, present or not: one appearing is a change
    watchContent( g, homeDir + "/.gitconfig" );
    watchContent( g, "/etc/gitconfig" );
    if( const std::string git = os::which( "git" ); !git.empty() )
    {
        char real[ PATH_MAX ];
        if( os::realpath( git.c_str(), real ) != nullptr )
        {
            std::string prefix( real );
            for( int up = 0; up < 2 && prefix.find_last_of( '/' ) != std::string::npos; ++up ) { prefix.resize( prefix.find_last_of( '/' ) ); }
            watchContent( g, prefix + "/etc/gitconfig" );   // <prefix>/bin/git reads <prefix>/etc/gitconfig as its system file
        }
    }
    watchContent( g, gitDir + "/HEAD" );
    watchContent( g, common + "/config" );
    watchContent( g, gitDir + "/config.worktree" );
    watchContent( g, common + "/info/exclude" );
    g.indexPath = gitDir + "/index";
    g.indexSig  = statSig( g.indexPath.c_str(), true );
    return g;
}

// The directories and rule files under each directory git reported ignored as a WHOLE. git collapses a directory to one
// line both when a rule names it and when every file under it is ignored by file rules; the second kind stops being
// ignored when a new file appears deep inside, which moves only that inner directory's mtime. So every directory below
// is watched, and every `.gitignore` among them. `cap` bounds the cost: past it the tree is not recorded at all.
inline bool watchIgnoredSubtrees( const std::vector<std::string>& roots, std::size_t cap, std::vector<WatchedPath>& watched )
{
    PROFILE_SCOPE_DESCRIBE( "warmsnap: walk git-ignored subtrees (directories + .gitignore, recording runs only)" );
    namespace fs = std::filesystem;
    std::size_t added = 0;
    for( const std::string& root : roots )
    {
        std::error_code ec;
        for( fs::recursive_directory_iterator it( fs::path( root ), fs::directory_options::skip_permission_denied, ec ), end; !ec && it != end; it.increment( ec ) )
        {
            std::error_code tec;
            const bool      isDir = it->is_directory( tec ) && !it->is_symlink( tec );
            if( isDir )
            {
                watched.push_back( { os::program_path( it->path() ), 0 } );
            }
            else if( it->path().filename() == ".gitignore" )
            {
                watched.push_back( { os::program_path( it->path() ), 1 } );
            }
            else
            {
                continue;
            }
            if( ++added > cap )
            {
                return false;
            }
        }
        if( ec )
        {
            return false;   // a level that could not be read: what is under it is unknown, so nothing is recorded
        }
    }
    return true;
}
inline constexpr std::size_t kIgnoredSubtreeCap = 50'000;

// ── the session: one per process, owned by main(), armed around the primary ingest ─────────────────────────────────
struct Session
{
    // identity of this run
    std::string   blobPath;             // the parse cache blob this snapshot is derived from; empty: the snapshot is off for this run
    std::string   path;                 // the snapshot itself, named by that blob's identity (snapshotPath); empty while no blob has one
    std::string   rootKey;              // quality::cacheRootKeyHex of this run's root: the field the sweep pins a family by
    std::uint64_t optionsKey = 0;
    long long     startNs    = 0;       // wall clock before the crawl: the racy rule's reference

    // the file as read
    std::string      file;
    bool             fileOk = false;
    std::uint64_t    fileTreeKey = 0;
    std::string_view treeSection, modelSection, graphSection;

    // what this run did
    Why  why           = Why::Off;   // the FIRST guard that refused anything this run
    Why  graphWhy      = Why::Off;   // the guard that refused the GRAPH section (Ok: it was served)
    Why  modelWhy      = Why::Off;   // ...and the MODEL section
    bool treeReplayed  = false;
    bool modelLoaded   = false;
    bool graphLoaded   = false;
    bool saved         = false;

    // what this run learned, to store
    TreeCapture   capture;
    bool          treeSectionFresh = false;   // capture was turned into treeOut
    std::string   treeOut, modelOut, graphOut;
    std::uint64_t treeKey      = 0;
    bool          treeKeyValid = false;       // false: some file's content is not pinned by a hash, so nothing keyed on it is stored or served

    bool on() const noexcept { return !blobPath.empty(); }
    void refuse( Why w ) noexcept
    {
        if( why == Why::Ok ) { why = w; }
    }
};

inline thread_local Session* tlSession = nullptr;

class Armed
{
public:
    explicit Armed( Session* s ) noexcept { tlSession = s; }
    ~Armed() { tlSession = nullptr; }
    Armed( const Armed& )            = delete;
    Armed& operator=( const Armed& ) = delete;
};

inline std::uint64_t layoutKey() noexcept
{
    const std::uint64_t parts[] = { sizeof( Symbol ), sizeof( IngestResult ), sizeof( std::string ), sizeof( void* ), sizeof( StatSig ),
                                    std::uint64_t( std::endian::native == std::endian::little ) };
    return depwatch::digest64( std::string_view( reinterpret_cast<const char*>( parts ), sizeof( parts ) ) );
}

// Every input of the crawl, the ingest and the resolver that is not a file's content: the options, both spellings of
// the root, where the process stands, and the environment those stages read. Environment: every RIPWIRE_* variable but
// the pure observers (so a test seam or a kill switch never meets a snapshot recorded without it), every GIT_* one, and
// the four that decide which git runs and which configuration it reads.
inline std::uint64_t optionsKeyOf( std::string_view rootDir, const std::vector<std::string>& excludes, std::size_t maxFileBytes, bool captureValueUses,
                                   std::string_view excludeLabel, bool respectGitignore, std::uint32_t extractionStamp, bool wantConstructHits,
                                   bool crawlTreeAllTracked )
{
    Out o;
    o.str( rootDir );
    char real[ PATH_MAX ];
    o.str( os::realpath( std::string( rootDir.empty() ? std::string_view( "." ) : rootDir ).c_str(), real ) != nullptr ? real : "?" );
    char cwd[ PATH_MAX ];
    o.str( os::getcwd( cwd, sizeof( cwd ) ) != nullptr ? cwd : "?" );
    o.strs( excludes );
    o.u64( maxFileBytes );
    o.u8( captureValueUses ? 1 : 0 );
    o.str( excludeLabel );
    o.u8( respectGitignore ? 1 : 0 );
    o.u32( extractionStamp );
    o.u8( wantConstructHits ? 1 : 0 );
    o.u8( crawlTreeAllTracked ? 1 : 0 );   // M1: a materialized commit tree crawls build-output names the working tree may prune
    static constexpr std::string_view kObservers[] = { "RIPWIRE_CACHE_STATS=", "RIPWIRE_SNAPSHOT_STATS=", "RIPWIRE_STATS=", "RIPWIRE_BIN=", "RIPWIRE_PROFILE" };
    static constexpr std::string_view kExact[]     = { "HOME=", "PATH=", "PWD=", "XDG_CONFIG_HOME=" };
    std::vector<std::string_view> read;
    for( char** env = os::environment(); env != nullptr && *env != nullptr; ++env )
    {
        const std::string_view var = *env;
        const bool observer = std::ranges::any_of( kObservers, [ & ]( std::string_view p ) { return var.starts_with( p ); } );
        const bool keyed    = var.starts_with( "RIPWIRE_" ) || var.starts_with( "GIT_" ) || std::ranges::any_of( kExact, [ & ]( std::string_view p ) { return var.starts_with( p ); } );
        if( keyed && !observer )
        {
            read.push_back( var );
        }
    }
    std::ranges::sort( read, rw::sortutil::svLess );   // the block's order is the parent shell's business (zsh and bash differ): the key is of the SET
    for( const std::string_view var : read )
    {
        o.str( var );
    }
    return depwatch::digest64( o.bytes );
}

// The eviction group: every snapshot of one root under one configuration. The blob identity is what varies inside it.
inline std::string snapshotFamilyPrefix( std::string_view rootKey, std::uint64_t optionsKey )
{
    return std::format( "ripwire-warmsnap-{}-{:016x}-", rootKey, optionsKey );
}

// Where this run's snapshot lives, resolved through the same shard-aware choke point every other cache family uses.
// The field order is the one every family shares, and the note at the top of this file says why each field is where
// it is.
inline std::string snapshotPath( std::string_view rootKey, std::uint64_t optionsKey, std::uint64_t blobIdentity )
{
    return quality::resolveCacheBlobPath( quality::cacheDirLadder(),
                                          std::format( "{}{:016x}.bin", snapshotFamilyPrefix( rootKey, optionsKey ), blobIdentity ) );
}

// The checksum's subject: the header up to the checksum field, then everything after the header.
inline std::uint64_t sectionSum( std::string_view payload ) noexcept
{
    const std::uint64_t head = depwatch::digest64( payload.substr( 0, kHeaderBytes - 8 ) );
    const std::uint64_t body = depwatch::digest64( payload.substr( kHeaderBytes ) );
    return head ^ hashutil::multiplyModulo64( body, 0x9e37'79b9'7f4a'7c15ull );
}

// Read and validate the snapshot at `s.path` (empty: this run's blob has no identity, so there is none to read).
// After this, `fileOk` says whether ANY section may be considered.
inline void openSnapshot( Session& s )
{
    PROFILE_SCOPE_DESCRIBE( "warmsnap: read + validate the snapshot file" );
    s.why = Why::Ok;
    std::optional<std::string> bytes = s.path.empty() ? std::nullopt : pathguard::readRegularFileNoFollow( s.path );
    if( !bytes )
    {
        s.refuse( Why::Absent );
        return;
    }
    s.file = std::move( *bytes );
    In in{ std::string_view( s.file ) };
    const std::uint64_t magic    = in.u64();
    const std::uint32_t version  = in.u32();
    in.u32();
    const std::uint64_t producer = in.u64();
    const std::uint64_t layout   = in.u64();
    const std::uint64_t options  = in.u64();
    in.u64();                                   // the write stamp: diagnostic
    const std::uint64_t treeKey  = in.u64();
    std::uint64_t span[ 6 ];
    for( std::uint64_t& v : span ) { v = in.u64(); }
    const std::uint64_t sum      = in.u64();
    if( !VALIDATE( in.ok && magic == kMagic, "warmsnap: not a snapshot file" ) )
    {
        s.refuse( Why::Checksum );
        return;
    }
    if( !VALIDATE( version == kVersion, "warmsnap: another format version" ) )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "a snapshot of another format version is not read; the run walks, decodes and resolves as without one" );
        s.refuse( Why::Version );
        return;
    }
    if( !VALIDATE( sum == sectionSum( s.file ), "warmsnap: checksum mismatch" ) )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "a snapshot whose checksum fails is not read; the run walks, decodes and resolves as without one" );
        s.refuse( Why::Checksum );
        return;
    }
    if( !VALIDATE( producer == quality::producerIdentityHash() && layout == layoutKey(), "warmsnap: written by another build" ) )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "a snapshot another build wrote is not read; the run walks, decodes and resolves as without one" );
        s.refuse( Why::Producer );
        return;
    }
    if( !VALIDATE( options == s.optionsKey, "warmsnap: recorded under other options" ) )
    {
        s.refuse( Why::Options );
        return;
    }
    std::string_view* const sections[] = { &s.treeSection, &s.modelSection, &s.graphSection };
    for( std::size_t i = 0; i < 3; ++i )
    {
        const std::uint64_t off = span[ 2 * i ], len = span[ 2 * i + 1 ];
        if( !VALIDATE( off <= s.file.size() && len <= s.file.size() - off, "warmsnap: a section lies outside the file" ) )
        {
            s.refuse( Why::Checksum );
            return;
        }
        *sections[ i ] = std::string_view( s.file ).substr( off, len );
    }
    s.fileTreeKey = treeKey;
    s.fileOk      = true;
}

// ── TREE: record ────────────────────────────────────────────────────────────────────────────────────────────────────
// Turn the walk's capture into the TREE section, or leave treeOut empty when the tree cannot be vouched for.
inline void recordTree( Session& s, const IngestResult& crawl, const std::string& rootReal, bool respectGitignore )
{
    PROFILE_SCOPE_DESCRIBE( "warmsnap: record the tree (stat every watched path)" );
    s.treeOut.clear();
    s.treeSectionFresh = false;
    if( !s.capture.usable || crawl.memoryStop.isSet() )
    {
        return;
    }
    std::vector<WatchedPath>& watched = s.capture.watched;
    if( !watchIgnoredSubtrees( s.capture.ignoredDirs, kIgnoredSubtreeCap, watched ) )
    {
        return;
    }
    std::vector<StatSig> sigs( watched.size() );
    std::atomic<bool>    racy{ false };
    const long long      racyFrom = s.startNs - kRacySlackNs;
    parallelFor( watched.size(), [ & ]( std::size_t i ) noexcept
    {
        sigs[ i ] = statSig( watched[ i ].path.c_str(), watched[ i ].follow != 0 );
        if( sigs[ i ].mtimeNs >= racyFrom || sigs[ i ].ctimeNs >= racyFrom )
        {
            racy.store( true, std::memory_order_relaxed );
        }
    } );
    if( racy.load() )
    {
        return;   // the racy rule: some signature is too young to tell a later same-granule change from no change
    }
    const GitInputs git = respectGitignore || s.capture.readGitIndex ? collectGitInputs( rootReal ) : GitInputs{};   // M1: see gitIndexRead
    if( !git.usable || ( !git.indexPath.empty() && ( git.indexSig.mtimeNs >= racyFrom || git.indexSig.ctimeNs >= racyFrom ) ) )
    {
        return;
    }
    Out o;
    writePaths( o, crawl.files.size(), [ & ]( std::size_t i ) -> std::string_view { return crawl.files[ i ]; } );
    o.str( crawl.crawlRoot );
    o.strs( crawl.crawlRootPrefixes );
    o.each( crawl.skippedOversize, [ & ]( const SkippedOversize& r ) { o.str( r.path ); o.u64( r.sizeBytes ); o.u64( r.limitBytes ); } );
    writeCrawlSkips( o, crawl.crawlSkips );
    writePaths( o, watched.size(), [ & ]( std::size_t i ) -> std::string_view { return watched[ i ].path; } );
    {
        std::vector<std::uint8_t> follow( watched.size() );
        std::ranges::transform( watched, follow.begin(), []( const WatchedPath& w ) { return w.follow; } );
        o.vec( follow );
    }
    o.vec( sigs );
    o.each( git.files, [ & ]( const depwatch::Dep& d ) { o.str( d.path ); o.u8( std::uint8_t( d.seam ) ); o.u64( d.answer ); } );
    o.str( git.indexPath );
    o.pod( git.indexSig );
    s.treeOut          = std::move( o.bytes );
    s.treeSectionFresh = true;
}

// ── TREE: replay ────────────────────────────────────────────────────────────────────────────────────────────────────
// True when every recorded signature and git input still matches; `out` then holds the crawl's answer.
inline bool replayTree( Session& s, IngestResult& out )
{
    PROFILE_SCOPE_DESCRIBE( "warmsnap: replay the crawl (stat every watched path, no directory read, no git child)" );
    if( !s.fileOk || s.treeSection.empty() )
    {
        s.refuse( s.fileOk ? Why::NoSection : s.why );
        return false;
    }
    In in{ s.treeSection };
    IngestResult got;
    readPaths( in, got.files );
    got.crawlRoot = in.str();
    in.strs( got.crawlRootPrefixes );
    const std::size_t oversize = in.count( 20 );
    if( oversize > in.left() )
    {
        s.refuse( Why::Checksum );
        return false;
    }
    got.skippedOversize.reserve( oversize );
    for( std::size_t i = 0; i < oversize && in.ok; ++i )
    {
        SkippedOversize r;
        r.path       = in.str();
        r.sizeBytes  = in.u64();
        r.limitBytes = in.u64();
        got.skippedOversize.push_back( std::move( r ) );
    }
    readCrawlSkips( in, got.crawlSkips );
    std::vector<std::string>  paths;
    std::vector<std::uint8_t> follow;
    std::vector<StatSig>      sigs;
    readPaths( in, paths );
    in.vec( follow );
    in.vec( sigs );
    const std::size_t watchedCount = paths.size();
    const std::size_t gitCount = in.count( 13 );
    std::vector<depwatch::Dep> gitFiles;
    if( gitCount > in.left() )
    {
        s.refuse( Why::Checksum );
        return false;
    }
    gitFiles.reserve( gitCount );
    for( std::size_t i = 0; i < gitCount && in.ok; ++i )
    {
        depwatch::Dep d;
        d.path   = in.str();
        d.seam   = depwatch::Seam( in.u8() );
        d.answer = in.u64();
        gitFiles.push_back( std::move( d ) );
    }
    const std::string indexPath = in.str();
    const StatSig     indexSig  = in.pod<StatSig>();
    if( !VALIDATE( in.ok && sigs.size() == watchedCount && follow.size() == watchedCount, "warmsnap: the TREE section does not parse" ) )
    {
        s.refuse( Why::Checksum );
        return false;
    }
    for( const depwatch::Dep& d : gitFiles )
    {
        if( answerOf( d ) != d.answer )
        {
            s.refuse( Why::GitMoved );
            return false;
        }
    }
    if( !indexPath.empty() && !( statSig( indexPath.c_str(), true ) == indexSig ) )
    {
        s.refuse( Why::GitMoved );
        return false;
    }
    std::atomic<bool> moved{ false };
    parallelFor( watchedCount, [ & ]( std::size_t i ) noexcept
    {
        if( !( statSig( paths[ i ].c_str(), follow[ i ] != 0 ) == sigs[ i ] ) )
        {
            moved.store( true, std::memory_order_relaxed );
        }
    } );
    if( moved.load() )
    {
        s.refuse( Why::TreeMoved );
        return false;
    }
    out.files             = std::move( got.files );
    out.crawlRoot         = std::move( got.crawlRoot );
    out.crawlRootPrefixes = std::move( got.crawlRootPrefixes );
    out.skippedOversize   = std::move( got.skippedOversize );
    out.crawlSkips        = std::move( got.crawlSkips );
    s.treeReplayed        = true;
    return true;
}

// ── the tree key ────────────────────────────────────────────────────────────────────────────────────────────────────
// `hashes[f]` is file f's content hash as the parse pool pinned it (0: not pinned). `extra` carries what the ingest read
// beside the parse cache: each document file's bytes digest and extracted text digest, in file order.
inline void setTreeKey( Session& s, const std::vector<std::string>& files, std::string_view rootDir, const std::vector<std::uint64_t>& hashes,
                        const std::vector<std::uint64_t>& extra, bool everyFilePinned )
{
    Out o;
    o.u64( files.size() );
    for( std::size_t f = 0; f < files.size(); ++f )
    {
        o.str( relForHash( files[ f ], rootDir ) );
        o.u64( hashes[ f ] );
    }
    o.vec( extra );
    s.treeKey      = depwatch::digest64( o.bytes );
    s.treeKeyValid = everyFilePinned;
}

// ── write ───────────────────────────────────────────────────────────────────────────────────────────────────────────
// Sections this run did not produce are carried over from the file it read, when that file is still the same tree's.
//
// `s.path` is named after the blob AS IT STANDS AT THE END OF THE RUN (ingest() re-reads its identity once the parse
// pool has published it), so a run that re-parsed stores under the blob it left behind, not the one it opened — and
// the next run finds it. Empty means this run's blob has no identity to name a snapshot with: nothing is written.
inline void saveSnapshot( Session& s )
{
    PROFILE_SCOPE_DESCRIBE( "warmsnap: write the snapshot file (tmp, then rename)" );
    if( !s.on() || s.path.empty() )
    {
        return;
    }
    const bool sameTree = s.fileOk && s.treeKeyValid && s.fileTreeKey == s.treeKey;
    const std::string_view tree  = s.treeSectionFresh ? std::string_view( s.treeOut ) : s.treeReplayed ? s.treeSection : std::string_view{};
    const std::string_view model = !s.treeKeyValid ? std::string_view{} : !s.modelOut.empty() ? std::string_view( s.modelOut ) : sameTree ? s.modelSection : std::string_view{};
    const std::string_view graph = !s.treeKeyValid ? std::string_view{} : !s.graphOut.empty() ? std::string_view( s.graphOut ) : sameTree ? s.graphSection : std::string_view{};
    const bool unchanged = s.fileOk && sameTree && !s.treeSectionFresh && s.modelOut.empty() && s.graphOut.empty() && tree.size() == s.treeSection.size();
    if( unchanged || ( tree.empty() && model.empty() && graph.empty() ) )
    {
        return;   // the file on disk already says everything this run knows, or this run knows nothing worth a file
    }
    Out o;
    o.bytes.reserve( kHeaderBytes + tree.size() + model.size() + graph.size() + 24 );
    o.u64( kMagic );
    o.u32( kVersion );
    o.u32( 0 );
    o.u64( quality::producerIdentityHash() );
    o.u64( layoutKey() );
    o.u64( s.optionsKey );
    o.u64( std::uint64_t( s.startNs ) );
    o.u64( s.treeKeyValid ? s.treeKey : 0 );
    std::uint64_t at = kHeaderBytes;
    for( const std::string_view sec : { tree, model, graph } )
    {
        o.u64( at );
        o.u64( sec.size() );
        at += ( sec.size() + 7 ) & ~std::uint64_t( 7 );
    }
    o.u64( 0 );   // the checksum, patched below
    ENSURES( o.bytes.size() == kHeaderBytes, "the header is the fixed 112 bytes the reader skips" );
    for( const std::string_view sec : { tree, model, graph } )
    {
        o.bytes.append( sec );
        o.bytes.append( ( 8 - sec.size() % 8 ) % 8, '\0' );
    }
    const std::uint64_t sum = sectionSum( o.bytes );
    std::memcpy( o.bytes.data() + kHeaderBytes - 8, &sum, 8 );
    if( !quality::atomicWriteFile( s.path, o.bytes ) )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "this run's answer is already computed; only the next run's snapshot is not there, and it walks and resolves as before" );
        return;
    }
    s.saved = true;
    // One snapshot per (root, configuration): the blob identity in the name moves on every rewrite of the blob, so an
    // edit loop would otherwise leave one orphan per edit, each the size of a stored model and graph. The file just
    // written is the one kept — another checkout's (another options key, see optionsKeyOf) is a different group and is
    // never touched, which is what keeps #334's thrash impossible here rather than merely unlikely.
    quality::evictOldCacheFamily( quality::cacheDirLadder(), snapshotFamilyPrefix( s.rootKey, s.optionsKey ), s.path, 1 );
}

}   // namespace rw::warmsnap
