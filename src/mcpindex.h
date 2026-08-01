#pragma once

// mcpindex.h — the warm in-memory index for --mcp: parse-once/reuse-across-calls
// {ingest, graph, rank} keyed by root, its staleness machinery (mtime+size stat sweep, the
// kqueue FS-event watcher, content-hash stamp), the multi-root workspace registry, getIndex()
// (the warm-rebuild pipeline), and the stable content-handle system (lazy bodies). Extracted
// from mcp.h (the mcp.h/main.cpp concern-split). Includes mcpjson.h; included by mcpverbs.h,
// mcpedit.h, and mcp.h. Also carries the index-side mcpdetail helpers (mtime/stat/watcher/
// byte-hash/handle codec) — the JSON-side mcpdetail helpers live in mcpjson.h (same namespace).

#include "mcpjson.h"

#include "model.h"
#include "ingest.h"
#include "graph.h"
#include "serialize.h"
#include "search.h"
#include "gitmine.h"
#include "lexical.h"
#include "recall.h"
#include "situ.h"
#include "workspace.h"     // multi-root `paths` array (A11): root hygiene + labels + merge
#include "quality.h"        // computeSnapshot/computeDelta + writeBaseline + gitHeadSha/computeHeadSnapshot — the quality_delta/quality_baseline verbs reuse the exact CLI logic
#include "Diagnostics.h"   // DEGRADED_PATH_ALERT — no-op in release; the visible line on a watcher-degrade path
#include "hashutil.h"      // sanitizer-clean modulo-2^64 FNV multiplication

#include <sys/stat.h>
#include <sys/time.h>      // struct timespec for a non-blocking kevent poll
#include <fcntl.h>         // open() the watched dir fds + O_CREAT for the per-file edit lockfile
#include <unistd.h>        // close()
#include <sys/file.h>      // flock(LOCK_EX|LOCK_NB) — the ripwire-vs-ripwire edit serializer (F1); POSIX-wide, incl. glibc

// kqueue/kevent is a BSD interface: <sys/event.h> does not exist on Linux at all, which is where the first
// public CI run stopped ("fatal error: sys/event.h: No such file or directory", both ubuntu legs). It powers
// ONE optimisation — eliding the directory-mtime sweep on a settled tree — and the watcher already has a
// fully-specified degrade path for "kqueue unavailable" (see FsWatcher below): stay unhealthy, and getIndex()
// runs the full stat/mtime sweep on every request, i.e. the exact pre-Feature-1 behaviour. A platform without
// kqueue takes that same path, so the MCP staleness CONTRACT is unchanged — a stale index is still detected
// on request, by the per-file mtime+size loop that runs regardless of the watcher. FUTURE UPGRADE: inotify
// (Linux) / FSEvents would restore the elision; that is new code with its own event-semantics bug surface and
// is deliberately not attempted here, because the poll fallback is already correct.
//
// The `#ifndef` is a deliberate override seam, not decoration: `-DRIPWIRE_HAS_KQUEUE=0` compiles the Linux
// path on a Mac, so the fallback can be built and RUN here instead of being first discovered by a CI leg
// nobody can reproduce locally.
#ifndef RIPWIRE_HAS_KQUEUE
  #if defined( __APPLE__ ) || defined( __FreeBSD__ ) || defined( __OpenBSD__ ) || defined( __NetBSD__ ) || defined( __DragonFly__ )
    #define RIPWIRE_HAS_KQUEUE 1
  #else
    #define RIPWIRE_HAS_KQUEUE 0
  #endif
#endif
#if RIPWIRE_HAS_KQUEUE
#include <sys/event.h>     // kqueue / kevent — the FS-event freshness watcher (macOS/BSD; Feature-1 hot-reload)
#endif

#include <atomic>          // RIPWIRE_MCP_TIMINGS rebuild-count observable (env-gated stderr timing; off → untouched)
#include <cctype>
#include <cerrno>          // errno / EWOULDBLOCK — the edit-lock bounded-acquire loop (F1)
#include <chrono>          // RIPWIRE_MCP_TIMINGS per-request steady_clock wall (env-gated)
#include <ctime>           // nanosleep — the edit-lock bounded-acquire backoff (F1)
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <limits>
#include <string>
#include <string_view>
#include <thread>          // Phase-M: the DETACHED qsnap-prefetch worker
#include <utility>
#include <vector>

namespace rw
{

namespace mcpdetail
{
    // nanosecond mtime out of a filled `struct stat`. The sub-second field is spelled DIFFERENTLY per
    // platform — st_mtimespec on Darwin/BSD, st_mtim on Linux (POSIX.1-2008) — and neither name exists on
    // the other, so this is a compile error, not a portability nicety. Same ladder (and same whole-second
    // last resort) as ingest.cpp's statSizeMtime; kept local rather than shared because that one lives in a
    // .cpp and hoisting it would move ingest internals into a header for two call sites.
    inline long long mtimeNsOf( const struct stat& st ) noexcept
    {
#if defined( __APPLE__ ) || defined( __FreeBSD__ ) || defined( __OpenBSD__ ) || defined( __NetBSD__ )
        return (long long)st.st_mtimespec.tv_sec * 1000000000LL + st.st_mtimespec.tv_nsec;
#elif defined( __linux__ )
        return (long long)st.st_mtim.tv_sec * 1000000000LL + st.st_mtim.tv_nsec;
#else
        return (long long)st.st_mtime * 1000000000LL;   // whole-second fallback
#endif
    }

    // nanosecond mtime of a path, or -1 if it can't be stat'd. The staleness signal for the in-memory index.
    inline long long mtimeOf( const std::string& p )
    {
        struct stat st;
        if( ::stat( p.c_str(), &st ) != 0 ) return -1;
        return mtimeNsOf( st );
    }

    // (mtime-ns, size) of a path in ONE stat(), or (-1,-1) if it can't be stat'd. mcpStale() uses BOTH: a
    // size change is a free (no-read) staleness signal alongside mtime, so the content-hash fallback only
    // fires for the same-mtime AND same-size residual (the genuinely ambiguous case).
    inline std::pair<long long, long long> statOf( const std::string& p )
    {
        struct stat st;
        if( ::stat( p.c_str(), &st ) != 0 ) return { -1, -1 };
        return { mtimeNsOf( st ), (long long)st.st_size };
    }

    // ALL directories under root (root itself included) → their mtimes, pruning the same noise/vendor/build
    // subtrees the ingest crawl prunes (mirrors kSkipDirs in ingest.cpp collectSources — keep in sync).
    // This is the staleness watch-list: tracking every dir (not just parents of INGESTED files) means adding
    // the first source file to a previously file-less directory is detected — creating the file bumps its
    // own dir's mtime, and creating a brand-new subdir bumps its (already-tracked) parent's mtime, so every
    // add/delete bubbles into a watched dir. Errors degrade: an unreadable subtree is simply not watched.
    inline void collectDirMtimes( const std::string& root, HashMap<std::string, long long>& dirMtime )
    {
        namespace fs = std::filesystem;
        dirMtime.try_emplace( root, mtimeOf( root ) );

        std::error_code ec;
        fs::recursive_directory_iterator it( fs::path( root ), fs::directory_options::skip_permission_denied, ec );
        if( ec ) return;   // unreadable root — the root mtime alone still catches top-level changes

        const fs::recursive_directory_iterator end;
        for( ; it != end; it.increment( ec ) )
        {
            if( ec ) { ec.clear(); continue; }
            if( !it->is_directory( ec ) ) continue;

            // prune the ingest denylist subtrees — changes inside them never affect the index
            static constexpr std::string_view kSkipDirs[] = {
                ".git", ".claude", ".hg", ".svn", "node_modules", "vendor", "third_party",
                ".cache", "build", "dist", "out", "target", ".venv", "venv", "__pycache__",
                ".idea", ".vscode",
                "asan", "build_prof", "CMakeFiles" };
            const std::string dn = it->path().filename().string();
            bool skip = false;
            for( std::string_view s : kSkipDirs )
                if( dn == s ) { skip = true; break; }
            if( !skip && dn.size() > 12 && dn.compare( 0, 12, "cmake-build-" ) == 0 )
                skip = true;
            if( !skip )
            {
                const fs::path cacheSentinel = it->path() / "CMakeCache.txt";
                if( fs::exists( cacheSentinel, ec ) )
                    skip = true;
                ec.clear();
            }
            if( skip ) { it.disable_recursion_pending(); continue; }

            const std::string d = it->path().string();
            dirMtime.try_emplace( d, mtimeOf( d ) );
        }
    }

    // ─── Feature 1: FS-event freshness watcher (codanna hot-reload, adapted deterministically) ─────────
    //
    // WHY a watcher AT ALL, and what it is (and is NOT) allowed to change:
    //   The warm McpIndex answers every verb from an in-memory parse; the per-call staleness cost is mcpStale()'s
    //   stat-sweep — a stat() per watched DIRECTORY (adds/deletes/renames) plus a stat() per FILE (content edits
    //   via mtime+size). The directory portion scales with the tree's dir count and is pure overhead on the
    //   common no-change path. A kqueue watcher over the (denylist-pruned) directory set replaces that whole
    //   dir loop with ONE non-blocking kevent() poll when nothing structural changed: on a settled tree, the
    //   dir sweep is provably redundant because the watcher would have reported any add/delete/rename.
    //
    // DETERMINISM CONTRACT — the load-bearing invariant. The watcher affects ONLY *which redundant work is
    //   elided*, NEVER the bytes any verb returns for a given tree state:
    //     • The PER-FILE mtime+size loop (the S1 content-staleness authority — catches a content-only,
    //       mtime-preserved edit via the size discriminator; see mcpstalecheck) ALWAYS runs, watcher or not.
    //       So a given tree state always produces byte-identical answers, and two processes agree: neither the
    //       kqueue fd nor any timing leaks into one output byte.
    //     • The watcher can only make us skip work it has ITSELF covered (structural changes) — it never lets a
    //       real change go unseen. Unhealthy watcher OR any pending event → the FULL dir sweep runs (the exact
    //       pre-Feature-1 path). No TTL, no clock: the skip decision is a pure function of the event queue.
    //
    // WHY dir-watch, not file-watch:
    //   kqueue's EVFILT_VNODE needs one open fd PER watched node. Watching every FILE would exhaust the fd
    //   table on a large tree, so we watch DIRECTORIES only (bounded = dir count, small). A dir NOTE_WRITE fires
    //   on add / delete / rename inside it — but a CONTENT-ONLY edit to an existing file fires NO dir event
    //   (verified empirically). That is exactly why the per-file loop is NEVER gated by the watcher: the
    //   watcher covers structural changes, the always-run file loop covers content edits — together they are
    //   complete, and neither is timing-dependent.
    //
    // DEGRADE, never throw: if kqueue()/open() fail (fd pressure, an OS without kqueue), the watcher is simply
    //   marked unhealthy — getIndex() then always runs the full dir sweep, i.e. the exact pre-Feature-1 path.
    struct FsWatcher
    {
        int              kq       = -1;      // the kqueue fd, or -1 if unavailable (→ unhealthy → always sweep)
        std::vector<int> dirFds;             // one open fd per watched directory (registered EVFILT_VNODE)
        bool             healthy  = false;   // true only when kq is open AND every dir fd registered cleanly

        FsWatcher() = default;
        FsWatcher( const FsWatcher& ) = delete;
        FsWatcher& operator=( const FsWatcher& ) = delete;
        ~FsWatcher() { reset(); }

        // release every fd (symmetric teardown; called on rebuild before re-arming and at destruction).
        void reset() noexcept
        {
            for( int fd : dirFds ) if( fd >= 0 ) ::close( fd );
            dirFds.clear();
            if( kq >= 0 ) ::close( kq );
            kq = -1;
            healthy = false;
        }

        // arm the watcher over `dirs` (the McpIndex dirMtime key set). ALL-OR-NOTHING (A3-F4): `healthy`
        // becomes true ONLY when kqueue() succeeded AND every dir registered cleanly — the field's contract.
        // An unregistered dir produces NO events, so a partially-armed watcher that claimed health would let
        // getIndex() skip the dir-mtime sweep (the only detector of file ADDITIONS) for exactly the dirs it
        // cannot see: a permanent new-file blind spot, violating "the watcher can only make us skip work it
        // has ITSELF covered". One fd per dir with no cap means fd exhaustion past RLIMIT_NOFILE is the
        // COMMON failure past a few hundred dirs — on the FIRST failure, stop and release every watcher fd
        // (relieving the very pressure we created) and stay unhealthy: getIndex() then always runs the full
        // dir sweep (the exact pre-Feature-1 path). If kqueue() is unavailable, same degrade.
        void arm( const std::vector<std::string>& dirs )
        {
            reset();
#if !RIPWIRE_HAS_KQUEUE
            // No kqueue on this platform (Linux). This is the SAME degrade the kqueue()-failed branch below
            // takes — kq stays -1, healthy stays false, drainHadEvent() reports "assume changed", and
            // getIndex() runs the full dir sweep every request. Nothing about the answer changes, only how
            // much redundant stat()ing precedes it.
            (void) dirs;
            DEGRADED_PATH_ALERT( "mcp watcher: no kqueue on this platform — falling back to stat-sweep freshness" );
            return;
#else
            kq = ::kqueue();
            if( kq < 0 ) { DEGRADED_PATH_ALERT( "mcp watcher: kqueue() unavailable — falling back to stat-sweep freshness" ); return; }

            dirFds.reserve( dirs.size() );
            for( const std::string& d : dirs )
            {
                const int fd = ::open( d.c_str(), O_RDONLY | O_CLOEXEC );
                bool isRegistered = fd >= 0;
                if( isRegistered )
                {
                    struct kevent ev;
                    EV_SET( &ev, fd, EVFILT_VNODE, EV_ADD | EV_CLEAR,
                            NOTE_WRITE | NOTE_DELETE | NOTE_RENAME | NOTE_EXTEND, 0, nullptr );
                    struct timespec zero = { 0, 0 };
                    if( ::kevent( kq, &ev, 1, nullptr, 0, &zero ) < 0 ) { ::close( fd ); isRegistered = false; }
                }
                if( !isRegistered )                                     // fd limit / unopenable dir → degrade whole
                {
                    DEGRADED_PATH_ALERT( "mcp watcher: dir watch failed (fd limit or unopenable dir) — falling back to stat-sweep freshness" );
                    reset();
                    return;
                }
                dirFds.push_back( fd );
            }
            healthy = true;                                             // kq live AND every dir registered → the fast path is available
#endif
        }

        // drain all pending events (EV_CLEAR → edge-triggered, so this both reports AND resets them). Returns
        // true if ANY event was pending since the last poll (a structural change under a watched dir). A poll
        // failure degrades to `true` (assume changed → force a sweep — never skip on uncertainty).
        bool drainHadEvent() noexcept
        {
            if( kq < 0 ) return true;                                   // unhealthy (incl. every non-kqueue platform) → force the sweep
#if !RIPWIRE_HAS_KQUEUE
            return true;                                                // arm() never opens kq here, so the line above already returned
#else
            struct kevent out[ 32 ];
            struct timespec zero = { 0, 0 };
            bool any = false;
            for( ;; )
            {
                const int n = ::kevent( kq, nullptr, 0, out, 32, &zero );
                if( n < 0 )  return true;                               // poll error → conservative: assume changed
                if( n == 0 ) break;
                any = true;
                if( n < 32 ) break;                                     // fewer than the batch cap → queue drained
            }
            return any;
#endif
        }
    };

    // read a whole file into a string; empty string (and readOk=false) on any open/read failure — the caller
    // treats a read failure as "content unknown", which the edit verbs turn into a refusal (degrade, never
    // splice against bytes we couldn't verify). Separate readOk out-param so an empty FILE (0 bytes, a legal
    // state) is distinguishable from a missing/unreadable one.
    inline std::string readFileBytes( const std::string& path, bool& readOk )
    {
        readOk = false;
        std::FILE* in = std::fopen( path.c_str(), "rb" );
        if( !in ) return {};
        std::string s;
        char b[ 8192 ];
        std::size_t n;
        while( ( n = std::fread( b, 1, sizeof( b ), in ) ) > 0 ) s.append( b, n );
        const bool err = std::ferror( in ) != 0;
        std::fclose( in );
        if( err ) return {};
        readOk = true;
        return s;
    }

    // FNV-1a 64 over a byte range — the per-file content fingerprint the EDIT verbs verify against.
    inline std::uint64_t byteHash( const char* data, std::size_t n ) noexcept
    {
        std::uint64_t h = 14695981039346656037ull;
        for( std::size_t i = 0; i < n; ++i ) { h ^= static_cast<unsigned char>( data[i] ); h = hashutil::fnv1aMultiply( h ); }
        return h;
    }

    // FNV-1a 64 over a std::string — the same hash the handle system uses for the STABLE identity part.
    inline std::uint64_t str64( const std::string& s ) noexcept { return byteHash( s.data(), s.size() ); }

    // ─── T4: stable content-handle system (lazy bodies) ───────────────────────────────────────────
    //
    // A handle lets an agent reference a symbol's body instead of re-receiving it: the READ verbs surface a
    // `handle`, and the `fetch_body` verb returns the full def source ONLY when the agent asks. The contract
    // is "names/signatures by default, bodies by handle on request" — the default-lean posture (~90% token
    // cut measured when it was adopted) and the MCP-2026 stateless-HANDLE spec (`sym#<stableId>@<contentHash>`).
    //
    // Handle format:  sym#<canonIdHash>@<contentHash>   (both 16 lowercase hex = FNV-1a-64)
    //   • canonIdHash — FNV-1a-64 of the symbol's STABLE canonical id (below). MUST derive from canonId, NEVER
    //     from NodeId: NodeId is reassigned every run (warm==cold reassigns ids), so a NodeId handle is stale on
    //     the very next call (trap library: "NodeId is per-run, canonId is stable"). canonId is `path::scope::
    //     name` — a pure function of the source, byte-identical across two independent server processes and
    //     across warm/cold, so the SAME symbol at the SAME content yields the SAME handle everywhere.
    //   • contentHash — the FNV-1a-64 of the symbol's FILE bytes (the fileByteHash the index already computed
    //     for the edit verbs). It PINS the version: if the file's bytes change, a handle minted against the old
    //     bytes no longer matches → fetch_body detects the staleness for free and refuses (never serves a body
    //     against shifted offsets — mirrors the edit-verbs' fileByteHash discipline).
    //
    // The STABLE id source: canonicalId() returns the BARE NAME for a free function (empty scope), which is not
    // unique across files — two `helper()`s in two files would share a handle. So we fold the file PATH in for
    // the unscoped case: `path::name`. The path is run-stable (the file's spelling doesn't change run-to-run),
    // so the id stays stable while becoming unique-per-file. Scoped symbols already carry the path in canonId.
    inline std::string stableHandleId( const std::string& canonId, const std::string& path, const std::string& name )
    {
        // scoped canonId already includes the path ("path::scope::name") → unique + stable, use as-is.
        // free-function canonId is the bare name (resolve.h: empty scope → bare name) → fold the path in.
        if( canonId.find( "::" ) != std::string::npos ) return canonId;
        return path + "::" + name;                                          // unscoped: path-qualify for per-file uniqueness
    }

    // build the handle string for symbol `id`. canonId from g.canonId[id] (STABLE); contentHash = the file's
    // byteHash as of index build (fileByteHash[fileId]). Both parts are pure functions of the source → the
    // handle is deterministic and process-independent.
    inline std::string makeHandle( const std::string& canonId, const std::string& path, const std::string& name,
                                   std::uint64_t contentHash )
    {
        const std::uint64_t idHash = str64( stableHandleId( canonId, path, name ) );
        char buf[ 64 ];
        std::snprintf( buf, sizeof( buf ), "sym#%016llx@%016llx",
                       (unsigned long long)idHash, (unsigned long long)contentHash );
        return buf;
    }

    // parse a handle "sym#<16hex>@<16hex>" → (idHash, contentHash, ok). Strict: exact prefix, exactly 16 hex
    // per part, a single '@' separator, nothing trailing. A hand-mutated/garbage handle degrades to ok=false
    // (the fetch verb refuses) — never a silent mis-resolve.
    inline bool parseHandle( const std::string& h, std::uint64_t& idHash, std::uint64_t& contentHash )
    {
        idHash = 0; contentHash = 0;
        if( h.size() != 4 + 16 + 1 + 16 ) return false;                     // "sym#" + 16 + "@" + 16
        if( h.compare( 0, 4, "sym#" ) != 0 ) return false;
        if( h[ 20 ] != '@' ) return false;
        const auto hex16 = []( const std::string& s, std::size_t off, std::uint64_t& out ) -> bool
        {
            out = 0;
            for( std::size_t i = 0; i < 16; ++i )
            {
                const char c = s[ off + i ];
                std::uint64_t d;
                if(      c >= '0' && c <= '9' ) d = std::uint64_t( c - '0' );
                else if( c >= 'a' && c <= 'f' ) d = std::uint64_t( c - 'a' + 10 );
                else return false;                                          // uppercase / non-hex → reject (handles are always lowercase)
                out = ( out << 4 ) | d;
            }
            return true;
        };
        return hex16( h, 4, idHash ) && hex16( h, 21, contentHash );
    }

    // FNV-1a 64 over ing.files's (path, mtime, byteHash) tuples, in ing.files order. ingest() guarantees
    // files are sorted lexicographically (the determinism contract), so this is already a stable
    // iteration order; no per-call sort needed.
    //
    // We fold the per-file CONTENT hash (fileByteHash, computed at index build in getIndex) — NOT just
    // (path,mtime) — because the stamp must change whenever answers change. A content-changed-but-mtime-
    // preserved edit (the S1 hole) leaves (path,mtime) identical; folding byteHash means the stamp still
    // moves, so it never lies alongside the fixed mcpStale() staleness. The bytes were read anyway at build
    // (for the edit verbs), so this costs nothing extra. NUL-separated so "ab"+"c" and "a"+"bc" don't collide.
    inline std::uint64_t indexContentHash( const std::vector<std::string>&   files,
                                           const std::vector<long long>&      fileMtime,
                                           const std::vector<std::uint64_t>&  fileByteHash )
    {
        std::uint64_t h = 14695981039346656037ull;
        const auto mix = [ &h ]( const void* data, std::size_t n ) noexcept
        {
            const unsigned char* b = static_cast<const unsigned char*>( data );
            for( std::size_t i = 0; i < n; ++i ) { h ^= b[i]; h = hashutil::fnv1aMultiply( h ); }
        };
        for( std::size_t i = 0; i < files.size(); ++i )
        {
            mix( files[i].data(), files[i].size() );
            h ^= 0u; h = hashutil::fnv1aMultiply( h );                   // NUL separator
            const long long m = ( i < fileMtime.size() ) ? fileMtime[i] : -1;
            mix( &m, sizeof( m ) );
            const std::uint64_t bh = ( i < fileByteHash.size() ) ? fileByteHash[i] : 0;
            mix( &bh, sizeof( bh ) );                                    // content fingerprint → stamp moves on a mtime-preserved edit
        }
        return h;
    }
}   // namespace mcpdetail

// ---- persistent in-memory index (parse once, reuse across MCP calls) ----
// The MCP server is long-lived; previously every verb re-parsed the whole tree (~6.5 s each). This caches
// the assembled {ingest, graph, rank} keyed by root and reuses it INSTANTLY when nothing changed. Staleness
// = any source file's mtime OR the mtime of ANY directory under root (walked at index time with the same
// denylist pruning as ingest — not just parents of ingested files, so the first source file added to a
// previously file-less directory is caught too: the new file bumps its dir, a new subdir bumps its watched
// parent — modifications, additions, AND deletions all bubble into a watched dir). When stale, the rebuild
// is WARM — it goes through the file content-hash cache, so only changed files re-parse.
struct McpIndex
{
    std::string                       root;
    bool                              valid = false;
    IngestResult                      ing;
    Graph                             g;
    std::vector<float>                rank;
    std::vector<long long>            fileMtime;   // parallel to ing.files
    std::vector<long long>            fileSize;    // parallel to ing.files: st_size at index build (staleness fast-path discriminator,
                                                   //   free from the same stat() as mtime — a size change is caught without a read).
    std::vector<std::uint64_t>        fileByteHash;   // parallel to ing.files: FNV-1a of the file's BYTES at index build.
                                                      //   The EDIT verbs (replace/insert) compare a fresh read against this before
                                                      //   splicing — mtime alone can lie (same mtime, different content on a fast
                                                      //   restore/rewrite), and a byte hash is the only signal that proves the span
                                                      //   offsets the index computed still address the same source. S1 ALSO folds it into
                                                      //   the stamp (indexContentHash) so the `_index` stamp moves on ANY content change,
                                                      //   even a same-(mtime,size) edit the stat check misses.
    HashMap<std::string, long long>   dirMtime;    // ALL dirs under root (denylist-pruned), root included
    std::string                       cacheFile;   // file --cache backing cheap rebuilds
    std::uint64_t                     contentHash = 0;   // FNV-1a of sorted (path,mtime,byteHash) — the stamp payload (S1: content-folded)

    // Feature 1 (freshness): the FS-event watcher over dirMtime's dir set. It lets getIndex() SKIP the
    // directory-mtime portion of mcpStale() when no structural change occurred (see FsWatcher). Pure
    // WHEN-to-check state — it never enters an output byte, so RESULT bytes stay a function of tree state.
    mcpdetail::FsWatcher              watcher;

    // working-set personalization (feature 2, Cody-style): the uncommitted-diff mask `rank` was teleport-biased
    // toward, as of the LAST rebuild — kept so mcpStale() can detect "same tree, different diff" (see below).
    std::uint64_t                     workingSetHash = 0;   // FNV-1a of the changed-file id list used to build `rank`
};

// cache file path, deterministic per (user, root). A fixed world-writable /tmp path is a symlink/poisoning
// target on multi-user machines, so prefer per-user locations: $TMPDIR (per-user on macOS), else
// $XDG_CACHE_HOME/ripwire (created 0700), else fall back to the /tmp name.
inline std::string mcpCachePath( const std::string& root )
{
    std::uint64_t h = 1469598103934665603ULL;     // FNV-1a of the root → a stable per-root cache name
    for( char c : root ) { h ^= static_cast<unsigned char>( c ); h = hashutil::fnv1aMultiply( h ); }
    char name[ 64 ];
    std::snprintf( name, sizeof( name ), "ripwire-mcp-%016llx.cache", (unsigned long long)h );

    const char* tmpDir = std::getenv( "TMPDIR" );
    if( tmpDir && *tmpDir )
    {
        std::string d = tmpDir;
        if( d.back() != '/' ) d += '/';
        return d + name;
    }

    const char* xdgCache = std::getenv( "XDG_CACHE_HOME" );
    if( xdgCache && *xdgCache )
    {
        std::string d = std::string( xdgCache ) + "/ripwire";
        ::mkdir( d.c_str(), 0700 );               // EEXIST is fine; other failures degrade at cache-write time
        return d + "/" + name;
    }

    return std::string( "/tmp/" ) + name;
}

// working-set (Cody-style): FNV-1a-64 of the SORTED changed-file id list, so the hash is a pure
// function of the SET (git's --name-only order is not guaranteed stable) and empty/no-git both hash to the
// same "no working set" value — this collapses the "clean tree" and "not a git repo" cases into identical
// rank behavior (both must byte-match the pre-feature uniform-prior output), which is exactly what §GATE(d)
// requires: a clean tree's stamp/rank must equal a non-git root's.
inline std::uint64_t workingSetHashOf( const std::vector<char>& changed )
{
    std::uint64_t          h = 14695981039346656037ull;
    std::vector<std::uint32_t> ids;
    for( std::uint32_t f = 0; f < changed.size(); ++f ) if( changed[f] ) ids.push_back( f );
    for( std::uint32_t f : ids )
    {
        h ^= f;
        h = hashutil::fnv1aMultiply( h );
        h ^= ( f >> 8 );
        h = hashutil::fnv1aMultiply( h );
    }
    return h;
}

// mcpStale: what to re-check, and at what cost.
//
// mtimes (file + all watched dirs) are a stat() per entry — microseconds total, checked on EVERY MCP call
// regardless of verb (getIndex() is called by every verb handler).
//
// The working set (feature 2) adds a THIRD staleness source in principle — `git diff --name-only HEAD` can
// change independently of the tracked mtimes. Deliberately NOT stat-checked here; instead git diff is only
// ever re-run inside getIndex()'s rebuild path (below), which fires exactly when mcpStale() returns true.
// Why that composes correctly: every case that ADDS to or SHRINKS the working set through a normal edit
// (save/create/delete) touches that file's mtime or its directory's mtime — dirty files are, tautologically,
// files whose bytes changed since the last commit's checkout, and changing bytes changes mtime — so the
// mtime check below is a reliable trigger for "the diff set may have changed too", and git diff gets
// re-invoked as part of the SAME rebuild, not as a separate probe. The one gap: reverting a file
// (`git checkout -- file`, or a stash-pop that restores pre-edit bytes) can leave mtime bumped from the
// write while the diff itself shrinks back toward clean — that self-heals on the next edit (or the next
// `touch`-triggered getIndex() call) and meanwhile only costs a stale-but-not-wrong-forever rank bias
// (teleport mass lingers on a file that's no longer actually dirty; PageRank still converges, it just
// personalizes toward slightly the wrong set for one call).
//
// Cost tradeoff (measured — see report): `git diff --name-only` via popen() is ~10-20ms on this repo. Paying
// that on EVERY verb call (even when nothing changed) would erase most of the point of McpIndex (the
// ~6.5s→instant warm-path win) — so it must NOT be in this stat-only hot-path check. Tying it to the existing
// mtime-triggered rebuild means: unchanged tree → zero popen, pure stat() (no added per-call cost); any real
// edit → one rebuild that already pays for a fresh ingest, and one more popen is noise next to that.
//
// S1 — the mtime-equality staleness hole. mtime EQUALITY alone was serving
// STALE answers when a file's content changed but its mtime was preserved (`touch -r` after an edit, or an
// edit whose mtime was otherwise reset). The fix adds the file SIZE — captured for free from the SAME stat()
// that already reads mtime — as a second staleness discriminator, plus a content-hash fold into the stamp.
//
//   • mtime differs → stale. (unchanged behavior)
//   • SIZE differs → stale. (NEW) Every content edit that changes the byte length — which is essentially
//     every real edit: adding/removing/renaming a symbol, inserting a line, changing an identifier's length —
//     is now caught EVEN IF the mtime was restored. This is the audit's own reproduction (an edit that adds
//     or renames a symbol), and it is caught at zero read cost, one stat() per file.
//
// The residual (documented honestly — the honesty brand extends to this limit): a content change that
// preserves BOTH the mtime AND the exact byte length (a same-length identifier rename + `touch -r` to the
// original mtime, or two such edits inside one coarse-FS-granularity tick on FAT/SMB/NFS/Docker where the
// second write lands under the first write's already-recorded mtime AND happens not to change the size) is
// NOT caught by this stat-only check. Catching it is provably impossible without READING the file's bytes,
// and — because we cannot know WHICH file was touched without reading it — a fully-correct check would have
// to read+hash EVERY same-(mtime,size) file on EVERY verb call. On the common no-change path all files have
// an unchanged (mtime,size), so that is a whole-tree re-read per call: MEASURED at ~168 ms/call vs ~12.5
// ms/call on a 1320-file/38 MB tree (~13×), which destroys the ~10.5 ms stat-sweep design the audit measured
// and the whole point of the warm McpIndex. A proof-of-clean cache keyed on (mtime,size) can't help
// either — a `touch -r` reproduces that key exactly, re-opening the same hole. So the hard cost bound (a
// non-negotiable invariant of the warm-server design) rules out the whole-tree content hash, and we take the
// audit's explicitly-offered "minimally size+mtime" (§3b.1) instead: it closes the reproduced, realistic case
// (a length-changing content edit) at zero cost and leaves only the same-(mtime,size) corner. Two backstops
// already cover that corner in the paths that matter: (1) the EDIT verbs re-read + byte-hash the target file
// on every write, so a splice is NEVER applied against stale offsets regardless of this check (mcpeditcheck
// step 5); (2) any watched-directory mtime bump (a sibling add/delete, a re-save through most editors)
// triggers a full rebuild. `fileSize`/`fileByteHash` are retained on McpIndex for the edit verbs and the
// content-folded stamp below; the stamp now moves on ANY content change (even the residual), so a caller
// holding two results can still detect the state changed even when this staleness check is (by cost
// necessity) conservative.
// `skipDirSweep` — Feature 1 fast path: when the kqueue watcher has proven NO structural event fired since
// the last check, the directory-mtime loop (which catches adds/deletes/renames bubbling into a watched dir)
// is provably redundant and may be skipped. The PER-FILE mtime+size loop is ALWAYS run regardless: it is the
// S1 staleness authority (a content-only, mtime-preserved edit is caught by the size discriminator — see
// mcpstalecheck), and the watcher does NOT catch content-only edits, so skipping it would reopen the S1 hole
// AND make results timing-dependent. So the fast path only ever elides work the watcher has already covered;
// the answer for a given tree state is byte-identical whether or not the dir loop ran.
inline bool mcpStale( const McpIndex& ix, bool skipDirSweep = false )
{
    if( !ix.valid ) return true;

    // directory watch-list (catches adds/deletes/renames that bubble into a watched dir). Skipped ONLY when
    // the FS-event watcher has proven no structural change occurred (getIndex passes skipDirSweep in that case).
    if( !skipDirSweep )
        for( const auto& [d, m] : ix.dirMtime )
            if( mcpdetail::mtimeOf( d ) != m ) return true;

    // per-file mtime+size loop — ALWAYS run (the S1 content-staleness authority; never gated by the watcher).
    for( std::size_t i = 0; i < ix.ing.files.size(); ++i )
    {
        const auto [ mtime, size ] = mcpdetail::statOf( diskPath( ix.ing, std::uint32_t( i ) ) );   // one stat() → both signals
        const long long recMtime = ix.fileMtime[i];
        const long long recSize  = ( i < ix.fileSize.size() ) ? ix.fileSize[i] : -1;
        if( mtime != recMtime || size != recSize ) return true;              // mtime OR size moved → stale, no read
    }
    return false;
}

// the single process-wide cached index. File-scope (not a function-local static) so the EDIT verbs can flip
// its `valid` flag after a successful write, forcing the next verb to rebuild (belt-and-braces on top of the
// mtime watch — see invalidateMcpIndex / the edit handlers). inline → one definition across TUs.
inline McpIndex& mcpIndexSlot()
{
    static McpIndex ix;
    return ix;
}

// force the cached index stale — the next getIndex() call rebuilds from disk. Called after a successful edit
// so a follow-up verb never answers from an index that predates the write. Cheap: one bool flip.
inline void invalidateMcpIndex()
{
    mcpIndexSlot().valid = false;
}

// RIPWIRE_MCP_TIMINGS observable (MEASURE-FIRST, mirrors ingest.cpp's RIPWIRE_CACHE_STATS precedent): a
// monotone count of FULL getIndex() rebuilds (the staleness/edit path — NOT warm reuses). The spec_trace
// harness reads it before/after each request to attribute per-request wall time to "rebuilt" vs "warm".
// Relaxed: the only reader is the same-thread timing print in runMcp, ordered by the request it wraps.
inline std::atomic<std::uint64_t>& mcpRebuildCounter()
{
    static std::atomic<std::uint64_t> n{ 0 };
    return n;
}

// ── Multi-root workspaces over MCP (A11): the additive `paths` array. A request
// carrying 2+ paths resolves to a WORKSPACE KEY (the canonical, deduped, label-ordered realpath join) that
// stands in for `path` everywhere downstream; getIndex() recognizes a registered key and builds ONE merged
// index over the root set (per-root mcpCachePath blobs, id-offset merge — the same machinery as the CLI).
// Single `path` requests never touch any of this (`path` unchanged — back-compat).
inline HashMap<std::string, std::vector<WorkspaceRoot>>& mcpWorkspaceRegistry()
{
    static HashMap<std::string, std::vector<WorkspaceRoot>> reg;
    return reg;
}

// resolve a `paths` root list to its workspace key (registering the root set); "" + err on a hard error
// (nested roots / too many). Dedupe can collapse to ONE root — then the single path is returned as-is.
inline std::string mcpWorkspaceKey( const std::vector<std::string>& rootArgs, std::string& err )
{
    if( rootArgs.size() > kMaxWorkspaceRoots ) { err = "too many roots in `paths` (max 16)"; return {}; }
    std::vector<WorkspaceRoot> ws;
    if( !buildWorkspaceRoots( rootArgs, ws ) ) { err = "nested roots are not allowed in `paths` — pass disjoint roots"; return {}; }
    if( ws.size() == 1 ) return ws[0].arg;                       // dedupe collapsed to one → plain single-root path
    std::string key;
    for( const WorkspaceRoot& r : ws ) { key.append( r.real );  key.push_back( '\x1f' ); }
    mcpWorkspaceRegistry()[ key ] = std::move( ws );
    return key;
}

// ─── Phase-M: qsnap PREFETCH ──────────────────────────────────────────────────────────────────────────
//
// A FILE-CACHE WARMER, NOT an index mechanism — it never touches this McpIndex. When a request observes that
// git HEAD has MOVED since the last observation (a commit just landed), it kicks a DETACHED background thread
// that runs the SAME quality::computeHeadSnapshot path a lazy quality_delta would — warming the sha-keyed qsnap
// cache FILE so the NEXT quality_delta finds it warm instead of paying a cold HEAD ingest + clone pass (~14.5 s
// p95 quality_delta on a large private C++ corpus, §8; the prefetch hides the ~43 % HEAD-side share). Rules (§2b):
//   (1) atomic publish — computeHeadSnapshot now writes qsnap via tmp+rename (quality::atomicWriteQSnap).
//   (2) single-flight  — one atomic flag; a second HEAD-move while a worker runs is DROPPED (the next
//                        observation re-fires, so the newest sha is always eventually warmed).
//   (3) discard-on-error — any failure in the worker is swallowed (optional work; the lazy path still covers it).
//   (4) GO-at-scale — gated on a cheap file-count heuristic (default 500; §8 measured the win is corpus-
//                     dependent: NO-GO on small repos, GO on large) so a small repo never pays a useless
//                     ~700 ms background HEAD ingest per commit. Test override: RIPWIRE_QSNAP_PREFETCH_MIN_FILES.
// MONOTONE FRESHNESS: computeHeadSnapshot re-reads gitHeadSha at run time and keys the qsnap by THAT sha, so a
// prefetched blob is byte-identical to what lazy would compute for the same sha and can NEVER be served for a
// different (newer) HEAD — the filename key IS the sha. A prefetch that lost the HEAD race just leaves an
// unused older-sha file, LRU-evicted by the existing keep=2 family evictor.

// process-wide prefetch state: the single-flight guard, the last HEAD-token we acted on, and a spawn counter
// (observable under RIPWIRE_MCP_TIMINGS for the single-flight gate).
inline std::atomic<bool>&          mcpPrefetchInFlight()   { static std::atomic<bool>          f{ false }; return f; }
inline std::atomic<std::uint64_t>& mcpPrefetchLastToken() { static std::atomic<std::uint64_t> t{ 0 };     return t; }
inline std::atomic<std::uint64_t>& mcpPrefetchSpawnCount(){ static std::atomic<std::uint64_t> n{ 0 };     return n; }

// the file-count threshold below which prefetch never fires (§8: small repos have a cheap cold HEAD snapshot →
// no latency to hide, only a wasted background burn). RIPWIRE_QSNAP_PREFETCH_MIN_FILES overrides it (test
// surface — lets a small fixture repo exercise the mechanism). Parsed ONCE (static), so it is a fixed constant.
inline std::size_t mcpPrefetchMinFiles()
{
    static const std::size_t v = []() -> std::size_t
    {
        if( const char* e = std::getenv( "RIPWIRE_QSNAP_PREFETCH_MIN_FILES" ) )
        {
            char*                    end = nullptr;
            const unsigned long long n   = std::strtoull( e, &end, 10 );
            if( end != e ) return static_cast<std::size_t>( n );
        }
        return 500;
    }();
    return v;
}

// Cheap, popen-FREE "did HEAD move?" signal: a fold of the (mtime,size) of git's HEAD-tracking files. git
// appends to logs/HEAD on EVERY ref update to HEAD (commit/reset/checkout/merge — reflog is on by default for
// non-bare repos), rewrites HEAD on a branch switch, and rewrites the resolved branch ref on a commit — so the
// fold changes exactly when HEAD moves, WITHOUT the ~15 ms popen that gitHeadSha (and git diff) cost, keeping
// the observation off the warm hot path (the same mtime-staleness philosophy the whole McpIndex rests on).
// Returns 0 when git state is indeterminate (no .git, or an unresolvable worktree/submodule gitfile) → the
// caller then simply does not prefetch (honest degrade; the lazy path still warms on demand). NEVER a popen,
// NEVER reads tree source bytes.
inline std::uint64_t gitHeadMoveToken( const std::string& root )
{
    std::string gitDir = root + "/.git";
    struct stat st;
    if( ::stat( gitDir.c_str(), &st ) != 0 ) return 0;                   // not a git working tree we track
    if( ( st.st_mode & S_IFMT ) == S_IFREG )
    {
        // ".git" is a FILE ("gitdir: <path>") for worktrees / submodules — resolve one hop, cheaply.
        bool        ok = false;
        std::string s  = mcpdetail::readFileBytes( gitDir, ok );
        std::size_t p  = ok ? s.find( "gitdir:" ) : std::string::npos;
        if( p == std::string::npos ) return 0;                          // unresolvable → indeterminate
        p += 7;
        while( p < s.size() && ( s[p] == ' ' || s[p] == '\t' ) ) ++p;
        std::size_t e = p;
        while( e < s.size() && s[e] != '\n' && s[e] != '\r' ) ++e;
        std::string gd = s.substr( p, e - p );
        if( gd.empty() ) return 0;
        if( gd.front() != '/' ) gd = root + "/" + gd;                   // relative gitdir → resolve against root
        gitDir = gd;
    }

    std::uint64_t h = 14695981039346656037ull;
    const auto fold = [ &h ]( const std::string& path )
    {
        const auto [ m, sz ] = mcpdetail::statOf( path );
        h ^= static_cast<std::uint64_t>( m );
        h = hashutil::fnv1aMultiply( h );
        h ^= static_cast<std::uint64_t>( sz );
        h = hashutil::fnv1aMultiply( h );
    };
    fold( gitDir + "/logs/HEAD" );      // appended on every HEAD move (reflog; default-on for a working tree)
    fold( gitDir + "/HEAD" );           // rewritten on a branch switch (reflog-independent)
    fold( gitDir + "/packed-refs" );    // a commit may repack refs
    // resolve HEAD → its branch ref file (a commit rewrites that loose ref even when the reflog is disabled).
    bool        okH  = false;
    std::string head = mcpdetail::readFileBytes( gitDir + "/HEAD", okH );
    if( okH )
        if( std::size_t q = head.find( "ref:" ); q != std::string::npos )
        {
            q += 4;
            while( q < head.size() && ( head[q] == ' ' || head[q] == '\t' ) ) ++q;
            std::size_t e2 = q;
            while( e2 < head.size() && head[e2] != '\n' && head[e2] != '\r' ) ++e2;
            const std::string ref = head.substr( q, e2 - q );
            if( !ref.empty() ) fold( gitDir + "/" + ref );
        }
    if( h == 0 ) h = 1;                 // 0 is the "indeterminate" sentinel — a real token must never collide with it
    return h;
}

// Observe HEAD; on a move (and only above the size threshold) single-flight-spawn the DETACHED qsnap warmer.
// Called from getIndex() on EVERY request (warm reuse and rebuild) — the per-call cost is the cheap stat-fold
// above, gated first on the file count so a small repo does not even probe git.
inline void maybePrefetchHeadSnapshot( const std::string& root, std::size_t fileCount )
{
    if( fileCount < mcpPrefetchMinFiles() ) return;                     // (4) GO-at-scale: small repos never pay

    const std::uint64_t token = gitHeadMoveToken( root );
    if( token == 0 ) return;                                           // indeterminate git state → no prefetch

    std::uint64_t last = mcpPrefetchLastToken().load( std::memory_order_relaxed );
    if( last == 0 )                                                    // FIRST observation: seed, do NOT fire (§Open-q 2: no startup pre-warm)
    {
        mcpPrefetchLastToken().compare_exchange_strong( last, token, std::memory_order_relaxed );
        return;
    }
    if( token == last ) return;                                        // HEAD has not moved since we last acted

    // (2) single-flight: at most ONE worker. If one is already warming, DROP this trigger WITHOUT advancing
    //     lastToken, so the next observation re-fires once the worker finishes (newest sha eventually warmed).
    bool expected = false;
    if( !mcpPrefetchInFlight().compare_exchange_strong( expected, true, std::memory_order_acq_rel ) )
        return;

    mcpPrefetchLastToken().store( token, std::memory_order_relaxed );  // we won → this move is ours
    mcpPrefetchSpawnCount().fetch_add( 1, std::memory_order_relaxed );

    const bool timingsOn = std::getenv( "RIPWIRE_MCP_TIMINGS" ) != nullptr;
    if( timingsOn ) { std::fprintf( stderr, "ripwire-prefetch spawn root=%s\n", root.c_str() ); std::fflush( stderr ); }

    // DETACHED worker: copies `root` by value (no dangling), runs the SAME computeHeadSnapshot the lazy
    // quality_delta uses with the SAME default args (so it warms the IDENTICAL qsnap key), then clears the
    // in-flight flag via an RAII guard on EVERY exit path. (3) discard-on-error: a throw (OOM at operator new)
    // is swallowed; the flag is always cleared so the mechanism never wedges.
    std::thread( [ root, timingsOn ]()
    {
        struct FlagGuard { ~FlagGuard(){ mcpPrefetchInFlight().store( false, std::memory_order_release ); } } guard;
        try   { (void)rw::quality::computeHeadSnapshot( root ); }      // side effect: warm the sha-keyed qsnap (atomic publish)
        catch( ... ) { /* optional work — drop silently (§2b rule 3) */ }
        if( timingsOn ) { std::fprintf( stderr, "ripwire-prefetch done root=%s\n", root.c_str() ); std::fflush( stderr ); }
    } ).detach();
}

// the cached index for `root`, rebuilt only when stale (otherwise returned as-is, no parse, no graph rebuild).
inline const McpIndex& getIndex( const std::string& root )
{
    McpIndex& ix = mcpIndexSlot();

    // hot path. The FS-event watcher (Feature 1) lets us SKIP the directory-mtime sweep when it proves no
    // structural change occurred — a single kevent poll instead of a stat() per watched dir. The PER-FILE
    // mtime+size loop still runs (the S1 content-staleness authority, deterministic), so the answer for any
    // tree state is byte-identical to the pre-watcher server: the watcher only elides work it has itself
    // covered. If the watcher is unhealthy (kqueue unavailable) OR reports an event, the FULL sweep runs —
    // the exact pre-Feature-1 lazy path. drainHadEvent() degrades to "assume changed" on any poll error, so
    // uncertainty never skips the dir sweep.
    if( ix.valid && ix.root == root )
    {
        const bool watcherClean = ix.watcher.healthy && !ix.watcher.drainHadEvent();
        if( !mcpStale( ix, /*skipDirSweep=*/watcherClean ) )
        {
            maybePrefetchHeadSnapshot( root, ix.ing.files.size() );        // Phase-M: observe HEAD move on the warm path (a bare commit does not rebuild)
            return ix;                                                     // warm reuse (no rebuild, no popen)
        }
    }

    // Multi-root workspace key (A11): per-root ingest (each with ITS OWN mcpCachePath blob — an edit in
    // one root never reparses another) merged into one IngestResult; else the single-root path unchanged.
    const auto wsIt = mcpWorkspaceRegistry().find( root );
    const bool isWorkspace = wsIt != mcpWorkspaceRegistry().end() && wsIt->second.size() >= 2;
    {
        // Phase-M: serialize this rebuild's ingest against a concurrent qsnap-prefetch worker (ingest() writes
        // single-writer process-global query caches — §2b). Uncontended on the single request thread; only the
        // background warmer can contend, and then one waits. Reached ONLY on a real rebuild (warm reuse returns
        // above), so it never touches the hot path.
        std::lock_guard<std::mutex> ingestLk( rw::quality::headSnapshotIngestMutex() );
        if( isWorkspace )
        {
            const std::vector<WorkspaceRoot>& roots = wsIt->second;
            std::vector<IngestResult> parts;
            parts.reserve( roots.size() );
            for( const WorkspaceRoot& r : roots )
                parts.push_back( ingest( r.arg.c_str(), {}, mcpCachePath( r.arg ), kDefaultMaxFileBytes, true, r.label ) );
            ix.cacheFile = mcpCachePath( root );                      // key-derived (unused by the per-root ingests)
            ix.ing = mergeWorkspaceIngests( roots, parts );
        }
        else
        {
            ix.cacheFile = mcpCachePath( root );
            ix.ing  = ingest( root.c_str(), {}, ix.cacheFile );          // warm rebuild via content-hash cache
        }
    }
    ix.g    = buildGraph( ix.ing );

    // working-set personalization (Cody-style): teleport the PageRank prior toward files with uncommitted
    // changes, mirroring --map-diff's diffTeleport weighting (main.cpp) — β=0.7 of the mass on changed-file
    // symbols, the rest uniform, then rankGraphTeleport (which also applies the name-quality biasPrior
    // automatically, same as every other teleport-based rank mode). A clean tree or a non-git root both
    // degrade to an ALL-ZERO changed mask, and diffTeleport() itself returns the plain uniform prior when
    // changed==0 — so this is byte-identical to the pre-feature rankGraph(g) in both of those cases (§GATE-d).
    std::vector<char> changed( ix.ing.files.size(), 0 );
    if( isWorkspace )
    {
        // §5: the working set is the UNION of per-root diffs, each mined only against its own files.
        const std::vector<WorkspaceRoot>& roots = wsIt->second;
        for( std::uint32_t r = 0; r < roots.size(); ++r )
        {
            const auto [ mask, gitOk ] = gitDiffChangedMask( roots[r].arg, ix.ing, r );
            if( gitOk )
                for( std::size_t f = 0; f < changed.size() && f < mask.size(); ++f ) if( mask[f] ) changed[f] = 1;
        }
    }
    else
    {
        const auto [ mask, gitOk ] = gitDiffChangedMask( root, ix.ing );
        if( gitOk ) changed = mask;                                       // not a repo / git missing → stays all-zero
    }
    ix.workingSetHash = workingSetHashOf( changed );
    ix.rank = rankGraphTeleport( ix.g, diffTeleport( ix.ing, changed ) );

    ix.fileMtime.assign( ix.ing.files.size(), 0 );
    ix.fileSize.assign( ix.ing.files.size(), -1 );      // st_size parallel to files — the staleness fast-path discriminator (S1)
    ix.fileByteHash.assign( ix.ing.files.size(), 0 );   // per-file byte fingerprint for the edit verbs AND the content-folded stamp (S1)
    for( std::size_t i = 0; i < ix.ing.files.size(); ++i )
    {
        const auto [ mtime, size ] = mcpdetail::statOf( diskPath( ix.ing, std::uint32_t( i ) ) );
        ix.fileMtime[i] = mtime;
        ix.fileSize[i]  = size;
        bool readOk = false;
        const std::string bytes = mcpdetail::readFileBytes( diskPath( ix.ing, std::uint32_t( i ) ), readOk );
        ix.fileByteHash[i] = readOk ? mcpdetail::byteHash( bytes.data(), bytes.size() ) : 0;   // unreadable → 0 (edit verb refuses; mcpStale sees a mismatch)
    }
    ix.contentHash = mcpdetail::indexContentHash( ix.ing.files, ix.fileMtime, ix.fileByteHash );   // stamp, now content-folded (S1)

    // the staleness watch-list: every directory under root (denylist-pruned), so additions in previously
    // file-less dirs are detected too — see collectDirMtimes.
    ix.dirMtime.clear();
    if( isWorkspace )
        for( const WorkspaceRoot& r : wsIt->second ) mcpdetail::collectDirMtimes( r.arg, ix.dirMtime );
    else
        mcpdetail::collectDirMtimes( root, ix.dirMtime );

    // Feature 1: (re-)arm the FS-event watcher over the freshly-collected dir set. The rebuild we just did IS
    // the freshest possible read, so events queued against the old state are dropped with the old fds. If
    // kqueue is unavailable, arm() leaves the watcher unhealthy → getIndex() always runs the FULL dir sweep
    // (the pre-Feature-1 lazy path). Registration order can't reach output, so the dirMtime keys are taken
    // as-is (no sort needed).
    std::vector<std::string> watchDirs;
    watchDirs.reserve( ix.dirMtime.size() );
    for( const auto& [ d, m ] : ix.dirMtime ) watchDirs.push_back( d );
    ix.watcher.arm( watchDirs );

    ix.root  = root;
    ix.valid = true;
    mcpRebuildCounter().fetch_add( 1, std::memory_order_relaxed );   // MEASURE-FIRST: a real (cache-miss) rebuild just happened
    maybePrefetchHeadSnapshot( root, ix.ing.files.size() );          // Phase-M: seed the HEAD token on the first build; observe a move on later rebuilds
    return ix;
}

// ─── T4: handle helpers over a live McpIndex ─────────────────────────────────────────────────────
//
// handleFor(ix, id) — the stable content-handle for symbol `id`, from the STABLE canonId + the file's byte
// fingerprint (both already on the index). The READ verbs attach this so an agent knows what to ask for.
inline std::string handleFor( const McpIndex& ix, NodeId id )
{
    if( id >= ix.ing.symbols.size() ) return {};
    const Symbol&       s      = ix.ing.symbols[id];
    const std::string&  canon  = ( id < ix.g.canonId.size() ) ? ix.g.canonId[id] : ix.ing.symbols[id].name;
    const std::string&  path   = ix.ing.files[ s.fileId ];
    const std::uint64_t chash  = ( s.fileId < ix.fileByteHash.size() ) ? ix.fileByteHash[ s.fileId ] : 0;
    return mcpdetail::makeHandle( canon, path, s.name, chash );
}

// resolveHandle(ix, idHash) — the NodeId whose STABLE canonId hashes to idHash, or kNoNode. canonId can
// collide (free functions in the SAME file, overloads sharing scope::name); we pick the LOWEST id among the
// matches — deterministic. The lowest-id pick is a *valid fetch target only when the colliding symbols share
// one body* (e.g. a declaration + its definition); for same-scope OVERLOADS with DIFFERENT bodies it is one
// arbitrary body among several (F4). `resolveHandleAll` exposes the full colliding set so fetch_body can be
// HONEST about that ambiguity instead of silently serving the lowest-id body. The caller separately verifies
// the handle's contentHash against the file's CURRENT bytes (staleness).
inline NodeId resolveHandleAll( const McpIndex& ix, std::uint64_t idHash, std::vector< NodeId >& matches )
{
    const IngestResult& ing = ix.ing;
    matches.clear();
    NodeId best = kNoNode;
    for( NodeId id = 0; id < NodeId( ing.symbols.size() ); ++id )
    {
        const Symbol&      s     = ing.symbols[id];
        const std::string& canon = ( id < ix.g.canonId.size() ) ? ix.g.canonId[id] : s.name;
        const std::string& path  = ing.files[ s.fileId ];
        if( mcpdetail::str64( mcpdetail::stableHandleId( canon, path, s.name ) ) == idHash )
        {
            if( best == kNoNode ) best = id;   // ids ascend → first match is the lowest; deterministic
            matches.push_back( id );
        }
    }
    return best;
}

inline NodeId resolveHandle( const McpIndex& ix, std::uint64_t idHash )
{
    std::vector< NodeId > matches;
    return resolveHandleAll( ix, idHash, matches );
}

}   // namespace rw
