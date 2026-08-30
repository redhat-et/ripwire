// ingest.cpp — Phase 2 INGEST. Deterministic crawl + tree-sitter tags-query extraction.
//
// Pipeline:
//   crawl -> skip-filter -> SORT paths (byte order) -> per-file parse + ONE tags query ->
//   collect raw defs/refs -> assign Symbol ids in (file,line,name) order ->
//   attribute each Reference to its enclosing definition by byte-span containment.
//
// Single-threaded (v1). Never throws: every recoverable problem degrades + DEGRADED_PATH_ALERT.

#include "ingest.h"
#include "docparse.h"          // P1-B: non-code document ingest (notebooks/html/csv + markitdown bridge)
#include "arch.h"              // T5: relForHash — root-relative path key, reused for cache portability
#include "quality.h"           // A5: cacheDirLadder + sweepStaleCacheBlobsOnce — the cache-dir hygiene hook (saveCache)
#include "embedded_queries.h"  // configure-generated constexpr tags.scm table; no runtime source-tree dependency
#include "infra/hashutil.h"    // sanitizer-clean modulo-2^64 FNV multiplication
#include "infra/namesplit.h"   // H4: stripTemplateArgs for the C++ qualified-call re-split (shared with tracelocus.h)
#include "infra/fixedStr.h"    // rw::findByte — the NEON/SSE2 byte scan buildNewlineOffsets rides
#include "lexindex.h"          // B0.1/B0.2: shared subtoken state machine + per-def lexical statistics builder
#include "didyoumean.h"        // octocode F3: boundedEditDistance/nearestNameByEditDistance — the ONE near-miss
                                // primitive, reused for a --match query's node-kind tokens (see nearestNodeKindHint)
#include "pattern.h"           // R2: the pattern surface's compiler + matcher — AstWalk::Pattern rides the shared file walk

#include "infra/Diagnostics.h"
#include "infra/profileScope.h"  // PROFILE_SCOPE self-profiling — gated by PROFILE_ENABLED (off unless -DRIPWIRE_PROFILE=ON)

#include <tree_sitter/api.h>

#include <algorithm>
#include <array>
#include <bit>                 // std::bit_floor — the cold-path reserve rounds to a power of two
#include <cctype>
#include <chrono>              // A4-P7: wall-clock cache-write timestamp for the racy-git rule
#include <cstdio>
#include <cstdlib>             // std::getenv — RIPWIRE_CACHE_STATS drift observable
#include <cstring>
#include <sys/stat.h>          // A4-P7: stat() for the (size,mtime) warm-run shortcut
#include <unistd.h>            // getpid — unique per-process cache temp name
#include <filesystem>
#include <fstream>
#include <limits>
#include <condition_variable>
#include <mutex>
#include <numeric>
#include <string>
#include <span>
#include <string_view>
#include <atomic>
#include <regex>
#include <thread>
#include <type_traits>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

#ifdef RIPWIRE_FUSE_PROBE
// ── Side-capture walk probe (compile-time opt-in; absent from every shipped build) ────────────────────
// The instrument behind the walk fusion in captureSideFacts. It separates the two things that "one more
// pass" can mean, because only one of them is what the fusion removes:
//   * STREAM POPS  — frames popped off a walk stack. One per node PER WALK, so N back-to-back walks over
//                    the same tree cost N x. This is the tree-streaming cost the fusion attacks.
//   * VISITOR CALLS — per-node matching work for one pass. Fusion does NOT reduce these; a pass still
//                    inspects every node it used to. If these move, a fact was dropped or double-counted.
// Compiled out entirely unless -DRIPWIRE_FUSE_PROBE is on the command line, so the plain/asan/profile
// builds are unaffected. Everything lands on STDERR — stdout is the XML map under a byte-identity gate.
//
//    cmake -S . -B build_probe -DCMAKE_CXX_FLAGS=-DRIPWIRE_FUSE_PROBE && cmake --build build_probe -j
//    TMPDIR=$(mktemp -d) ./build_probe/ripwire <corpus> >/dev/null      # TMPDIR forces a cold parse
namespace fuseprobe
{
enum PassId : int { kInc = 0, kFfi = 1, kRoutes = 2, kRustImpls = 3, kBinds = 4, kUses = 5, kPassCount = 6 };
inline const char* const kPassName[ kPassCount ] = { "captureIncludes", "captureFfi", "captureRoutes", "captureRustImpls", "captureBindings", "captureUses" };

inline thread_local std::uint64_t tlNodes[ kPassCount ] = {};   // visitor calls, this thread, cumulative
inline std::atomic<std::uint64_t> gNodes[ kPassCount ];         // visitor calls per pass, corpus-wide
inline std::atomic<std::uint64_t> gFiles[ kPassCount ];         // files on which the pass saw >=1 node
inline std::atomic<std::uint64_t> gHist[ kPassCount + 1 ];      // files by count of passes that saw a node
inline std::atomic<std::uint64_t> gFilesTotal { 0 };
inline std::atomic<std::uint64_t> gNodesMaxPass { 0 };          // sum of the per-file LARGEST pass = AST-size proxy
inline std::atomic<std::uint64_t> gStreamPops { 0 };            // THE fusion metric: frames popped, all walks

inline void bump( int pass ) noexcept { ++tlNodes[ pass ]; }
inline void pop() noexcept { gStreamPops.fetch_add( 1, std::memory_order_relaxed ); }

struct Dump
{
    ~Dump()
    {
        const std::uint64_t files = gFilesTotal.load();
        std::uint64_t       calls = 0;
        for( int p = 0; p < kPassCount; ++p )
        {
            calls += gNodes[ p ].load();
        }
        std::fprintf( stderr, "\n[fuseprobe] files_with_a_parsed_tree=%llu\n", (unsigned long long) files );
        std::fprintf( stderr, "[fuseprobe] %-18s %13s %10s %8s\n", "pass", "visitor_calls", "files", "%files" );
        for( int p = 0; p < kPassCount; ++p )
        {
            const std::uint64_t f = gFiles[ p ].load();
            std::fprintf( stderr, "[fuseprobe] %-18s %13llu %10llu %7.1f%%\n", kPassName[ p ], (unsigned long long) gNodes[ p ].load(),
                          (unsigned long long) f, files ? 100.0 * double( f ) / double( files ) : 0.0 );
        }
        const std::uint64_t astProxy = gNodesMaxPass.load();
        const std::uint64_t pops     = gStreamPops.load();
        std::fprintf( stderr, "[fuseprobe] visitor_calls=%llu  ast_size_proxy(sum of per-file max pass)=%llu\n",
                      (unsigned long long) calls, (unsigned long long) astProxy );
        std::fprintf( stderr, "[fuseprobe] STREAM_POPS=%llu  streams_per_node=%.2fx  <-- the number fusion moves\n",
                      (unsigned long long) pops, astProxy ? double( pops ) / double( astProxy ) : 0.0 );
        std::fprintf( stderr, "[fuseprobe] files by number of passes that SAW a node:\n" );
        for( int k = 0; k <= kPassCount; ++k )
        {
            const std::uint64_t f = gHist[ k ].load();
            if( f != 0 )
            {
                std::fprintf( stderr, "[fuseprobe]   %d pass%s : %10llu files (%5.1f%%)\n", k, k == 1 ? " " : "es", (unsigned long long) f,
                              files ? 100.0 * double( f ) / double( files ) : 0.0 );
            }
        }
        std::fflush( stderr );
    }
};
inline Dump gDump;
}   // namespace fuseprobe
    #define FUSEPROBE_BUMP( p ) ::fuseprobe::bump( ::fuseprobe::p )
    #define FUSEPROBE_POP()     ::fuseprobe::pop()
#else
    #define FUSEPROBE_BUMP( p ) ( (void) 0 )
    #define FUSEPROBE_POP()     ( (void) 0 )
#endif

// ---- tree-sitter grammar entry points (each grammar's OBJECT lib exports one) ----
extern "C"
{
    const TSLanguage* tree_sitter_cpp( void );
    const TSLanguage* tree_sitter_python( void );
    const TSLanguage* tree_sitter_go( void );
    const TSLanguage* tree_sitter_rust( void );
    const TSLanguage* tree_sitter_typescript( void );
    const TSLanguage* tree_sitter_tsx( void );
    const TSLanguage* tree_sitter_swift( void );
    const TSLanguage* tree_sitter_objc( void );
    const TSLanguage* tree_sitter_javascript( void );
    const TSLanguage* tree_sitter_bash( void );
    const TSLanguage* tree_sitter_java( void );
    const TSLanguage* tree_sitter_ruby( void );
    const TSLanguage* tree_sitter_json( void );
    const TSLanguage* tree_sitter_toml( void );
    const TSLanguage* tree_sitter_yaml( void );
    const TSLanguage* tree_sitter_c_sharp( void );
    const TSLanguage* tree_sitter_c( void );
    const TSLanguage* tree_sitter_cuda( void );
    const TSLanguage* tree_sitter_markdown( void );
    const TSLanguage* tree_sitter_php( void );
    const TSLanguage* tree_sitter_lua( void );
}

// ── the ingest-family sections (2026-08-29 split) ────────────────────────────────────────────────────
// Each ingest_*.h below is a SECTION of this translation unit, not a library header: it reopens
// `namespace rw` AND the unnamed namespace inside it (one TU, one unnamed namespace), sees every
// #include and grammar entry point above, and is included exactly once, right here — the same
// mechanism as main.cpp's verb-family split, with RIPWIRE_INGEST_TU as the enforcement: any other
// includer is a compile error. Order matters — a later section may call an earlier one (the
// side-capture section calls the metrics section's complexityOf; everything may call the crawl
// section's language table). The --match/--lint tail (ingest_astquery.h) is rw-level rather than
// unnamed and is included at the very END of this file, exactly where its content sat before the
// split.
#define RIPWIRE_INGEST_TU 1
#include "ingest_crawl.h"
#include "ingest_cache.h"
#include "ingest_metrics.h"
#include "ingest_relations.h"
#include "ingest_docs.h"
#include "ingest_names.h"
#include "ingest_binds.h"
#include "ingest_sidecap.h"
#include "ingest_docpass.h"
#include "ingest_model.h"


namespace rw
{


// Per-worker capacity floor for the COLD parse pool, sized from the crawl's parseable byte count.
//
// WHY THIS EXISTS. The warm reserve sums cached FileFacts, so it only runs when a cache is loaded; a cold
// run reserved nothing and every accumulator doubled up from zero — ~500 whole-vector reallocations per
// run, on the one path where all workers hammer the allocator at once.
//
// WHAT IT IS WORTH, MEASURED, so nobody re-litigates it from the plausible-sounding story. Against pristine
// HEAD on three cold corpora (this repo at ~1.1k files, plus a 2.4k-file and a 0.7k-file ObjC++/C++ tree),
// --no-cache on both sides, 9 reps: heap allocations about -505 / -465 / -420, which is only -0.29% /
// -0.06% / -0.12% of each run's total. Peak live bytes is a WASH — repeat measurements of the very same
// binaries move it between -0.6 and +2.0 MB, i.e. the sign is not stable, so the "stranded buffers" story
// does not survive contact with an allocator that reuses them. Parse-pool wall clock is a NULL RESULT: two
// independent 15-pair interleaved runs disagreed in SIGN on two of the three corpora, so machine drift
// exceeds the effect. This removes real work; it does not make the tool measurably faster, and it does not
// measurably shrink it either. Not a speedup — do not cite it as one.
//
// BYTES, NOT FILE COUNT, IS THE PREDICTOR. Over ten corpora spanning C/C++, ObjC++, Rust, Swift, Python/TS
// and generated C, refs-per-FILE spans 190x (10.6 … 2017.6) while refs-per-BYTE spans 11x; binds-per-file
// spans 1325x against 432x per byte. A file count cannot size the two families that hold the memory. Each
// divisor is the bytes-per-element of roughly the LEAST dense corpus measured, so the estimate is a floor,
// not a forecast, and lands under the real total nearly everywhere.
//
// WHY THE CAP, which is the part that is easy to get wrong. Allocations saved grow like log2( reserve )
// while the memory risked grows like the reserve itself, so the efficient point is small: measured, a
// 256-element cap keeps 84-94% of the allocations an uncapped mean-sized reserve saves, bounded by
// 256 * ( 168 + 144 + 32 + 72 ) B * nthreads ~= 1.9 MB in the worst case where every worker finishes under
// it. Reserving each worker the corpus MEAN is worse than it looks: work is uneven (the busiest worker
// holds 1.3-5.2x the mean, median ~1.9x), so a mean-sized reserve over-allocates the below-mean majority
// to suit one worker — that variant measured 1-2.5 MB of extra peak live bytes for ~60 more allocations.
//
// ROUNDED DOWN TO A POWER OF TWO. An empty vector grows 1, 2, 4, 8, … so its final capacity for n elements
// is exactly the next power of two; starting from 2^j the ladder is 2^j, 2^(j+1), … — a SUBSEQUENCE of the
// same powers. Seeding with a power of two therefore lands on the identical final capacity for any worker
// that reaches it, and can only remove growth steps. An arbitrary seed cannot say that: a vector reserved
// to R that needs R+1 doubles to 2R and can finish above where it would have landed alone.
//
// FFI and route accumulators get nothing on purpose: across the same ten corpora they total 0-363 entries
// and are non-empty on only 0-11 of 18 workers, so a reserve there would be pure waste.
struct ColdParseReserve
{
    std::size_t defs;
    std::size_t refs;
    std::size_t incs;
    std::size_t binds;
};

// fileLang and fileByteSize are the crawl's two parallel per-file arrays; a file counts toward the estimate
// only when it has a grammar, which is the same predicate the divisors were calibrated under. Keeping the
// predicate next to the constants is deliberate: change one and the other stops being calibrated.
inline ColdParseReserve coldParseReserve( std::span<const LangEntry* const> fileLang,
                                          std::span<const std::uintmax_t> fileByteSize,
                                          unsigned nthreads ) noexcept
{
    VERIFY( nthreads >= 1 );   // caller derives it from min( hardware_concurrency, nfiles ) with nfiles >= 1
    VERIFY( fileLang.size() == fileByteSize.size() );

    std::size_t parseableBytes = 0;
    for( std::size_t fileId = 0; fileId < fileLang.size(); ++fileId )
    {
        const LangEntry* le = fileLang[ fileId ];
        if( le != nullptr && le->grammar != nullptr )
        {
            parseableBytes += static_cast<std::size_t>( fileByteSize[ fileId ] );
        }
    }

    // bytes per element, calibrated 2026-08-10 against the ten-corpus census described above
    constexpr std::size_t kBytesPerDef  =  2400;
    constexpr std::size_t kBytesPerRef  =   800;
    constexpr std::size_t kBytesPerInc  = 20000;
    constexpr std::size_t kBytesPerBind =  4000;
    constexpr std::size_t kCapPerThread =   256;

    // Integer division throughout: no float, and no overflow — parseableBytes is a byte count, every divisor
    // is a nonzero constant, and nthreads is at least 1. An all-documentation tree yields 0 for every family,
    // and reserve( 0 ) is a no-op.
    const auto perThread = [ parseableBytes, nthreads, cap = kCapPerThread ]( std::size_t bytesPerElem ) noexcept
    {
        return std::min( std::bit_floor( parseableBytes / bytesPerElem / nthreads ), cap );
    };

    const ColdParseReserve r{ perThread( kBytesPerDef ), perThread( kBytesPerRef ),
                              perThread( kBytesPerInc ), perThread( kBytesPerBind ) };

    // The two properties the whole argument above rests on: every value is a power of two (so the doubling
    // ladder is unchanged) and none exceeds the cap (so the waste stays bounded).
    VERIFY( r.defs  <= kCapPerThread && ( r.defs  == 0 || std::has_single_bit( r.defs  ) ) );
    VERIFY( r.refs  <= kCapPerThread && ( r.refs  == 0 || std::has_single_bit( r.refs  ) ) );
    VERIFY( r.incs  <= kCapPerThread && ( r.incs  == 0 || std::has_single_bit( r.incs  ) ) );
    VERIFY( r.binds <= kCapPerThread && ( r.binds == 0 || std::has_single_bit( r.binds ) ) );
    return r;
}

IngestResult ingest( const char* rootDir, const std::vector<std::string>& excludeSubstr, std::string_view cacheFile,
                     std::size_t maxFileBytes, bool captureValueUses, std::string_view excludeLabel )
{
    PROFILE_SCOPE_DESCRIBE( "ingest: total (crawl + parse + model)" );
    // Cheap (a handful of bytes serialized twice) and runs once per invocation — catches a
    // writeDef/writeRef field added without updating kMinDefRecordBytesLean/kMinRefRecordBytes immediately
    // in any debug/ASan run, before it can silently weaken the cache record-count bounds check.
    verifyCacheRecordMinimaTripwire();

    IngestResult result;
    // A4-F17: rootDir is a runtime-falsifiable input (caller/CLI-supplied), so degrade — never VERIFY here.
    // In release VERIFY becomes __builtin_assume, which would delete the very guard below (the CLAUDE.md trap).
    if( rootDir == nullptr )
    {
        DEGRADED_PATH_ALERT( "ingest: null root directory — empty result" );
        return result;
    }

    // a zero/absurd ceiling would silently crawl nothing — clamp to the default (degrade, never trap).
    if( maxFileBytes == 0 )
    {
        maxFileBytes = kDefaultMaxFileBytes;
    }

    // 1) deterministic crawl -> sorted file list (this list IS result.files / the fileId space)
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: crawl (collectSources)" );
        auto [ crawledPaths, oversizeSkipped, taxonomySkips ] = collectSources( rootDir, excludeSubstr, maxFileBytes, excludeLabel );
        result.files           = std::move( crawledPaths );
        result.skippedOversize = std::move( oversizeSkipped );
        result.crawlSkips      = std::move( taxonomySkips );   // §L1: excluded / unsupported-ext / unindexed exts
    }

    // 2) parse every file IN PARALLEL — one TSParser per worker thread (parsers aren't
    //    thread-safe), per-thread raw lists merged after. Determinism is preserved: defs/refs
    //    are re-sorted below, so collection order is irrelevant.
    std::vector<RawDef>  rawDefs;
    std::vector<RawRef>  rawRefs;
    std::vector<Include> rawIncs;
    std::vector<RawBind> rawBinds;   // P2-D Rule 2: local var→type bindings
    std::vector<BindingAlias> rawFfis;   // A4-R5: cross-language FFI binding declarations
    std::vector<RouteDef>     rawRouteDefs;   // B6.3: HTTP server-side route registrations
    std::vector<RawRouteUse>  rawRouteUses;   // B6.3: HTTP client-side calls (pre fromSymbol attribution)

    // Win 1 (PERF.md P1) — lazy grammar compilation: load the cache FIRST, then compile only the
    // grammars needed by cache-miss files (new or hash-changed). On a fully-warm zero-change run,
    // zero grammars need compiling → ~70ms saved (72% of warm canyon). On a partial-change run,
    // only the grammars touched by changed files are compiled (typically 1 for a single .cpp edit).
    //
    // Implementation: a pre-pass reads+hashes each file and checks against the loaded cache;
    // misses mark their grammar. Hashes are stored so the parse pool reuses them (no double-read).
    // The constraint: compiledQueryCache() is single-writer and worker reads happen only after the ready gate
    // opens. Cold query compilation is launched before the parse pool; the main thread installs the shared
    // cache and notifies workers while they are already doing parse-side work.

    // incremental: load the content-hash cache BEFORE the prewarm. Empty cacheFile ⇒ full parse.
    // fileHash: pre-sized to nfiles here (0 = not yet hashed); the prewarm miss-detection pass
    // populates entries for files it reads; the parse pool fills the rest during normal processing.
    // A4-P7: cacheWriteNs is the loaded blob's write timestamp — the racy-rule reference for the warm-run
    // stat-gate. -1 (no/rejected cache) makes every stat check see a racy entry → always read+hash (safe).
    long long cacheWriteNs = -1;
    HashMap<std::string, FileFacts> cache =
        cacheFile.empty() ? HashMap<std::string, FileFacts>{} : loadCache( std::string( cacheFile ), rootDir, captureValueUses, cacheWriteNs );
    const std::size_t nfilesEarly = result.files.size();
    const bool needsCacheHash = !cacheFile.empty();
    std::vector<std::uint64_t> fileHash( nfilesEarly, 0 );
    // A4-P7 stat-gate: (size,mtime) observed for each file at the run that hashes it — persisted by saveCache
    // so a future warm run can trust an unchanged file without reading it. -1 ⇒ not captured (never trusted).
    std::vector<long long> fileStatSize( nfilesEarly, -1 );
    std::vector<long long> fileStatMtime( nfilesEarly, -1 );
    std::vector<FileHealth> fileHealth( nfilesEarly );   // §L1: one slot per fileId, one WRITER per slot
    std::vector<const LangEntry*> fileLang( nfilesEarly, nullptr );
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: classify file languages" );
        for( std::size_t fileId = 0; fileId < nfilesEarly; ++fileId )
        {
            const std::string ext = lowerExtensionOf( result.files[ fileId ] );
            fileLang[ fileId ] = lookupLang( ext );
        }
    }

    std::vector<const LangEntry*> toCompile;
    std::vector<TSQuery*>         compiledQueries;
    std::vector<std::thread>      queryCompilePool;
    std::atomic<bool>             queryPrewarmReady{ true };
    std::mutex                    queryPrewarmMutex;
    std::condition_variable       queryPrewarmCv;
    QueryReadyGate                queryReadyGate{ &queryPrewarmReady, &queryPrewarmMutex, &queryPrewarmCv };

    // pre-warm the per-language tags.scm cache single-threaded; workers then only READ it.
    // LAZY: compile ONLY grammars needed by changed/uncached files (the miss set).
    // The grammar set must be a SUPERSET of every grammar any worker will touch:
    //   - a cache miss → grammar guaranteed needed → mark it
    //   - a cache hit (hash-match) → worker skips parse → grammar NOT needed (safe to omit)
    //   - a .h miss that looks Objective-C → marks objc instead of cpp (same looksObjC re-route as parse pool)
    //   - an unreadable .h miss → conservatively marks both cpp and objc, matching the old safety fallback
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: compile queries (tags.scm prewarm)" );
        std::array<bool, kLangTable.size()> present {};
        bool anyUnknownHeaderMiss = false;

        // The miss-detection pass reads + FNV-hashes every cache-present code file to decide which grammars a
        // worker will actually need. That I/O + hashing was serial (~61ms on canyon warm). It is READ-ONLY and
        // a pure function of each file's bytes, so parallelize it — but keep the RESULT deterministic: every
        // thread writes ONLY its own per-index slots (fileHash[fi], isMiss[fi]); nothing is
        // push_back'd from a worker. The grammar-mark reduction that follows is a serial pass over those slots,
        // so the compiled-grammar set (and thus everything downstream) is independent of thread scheduling.
        // The 204bb02 constraint still holds: compiledQueryCache() is populated single-threaded after the
        // async compile join, and workers wait on queryPrewarmReady before reading it. fileHash is pre-filled
        // so the pool skips the re-read on a cache hit.
        std::vector<char> isMiss( nfilesEarly, 0 );              // 1 ⇒ this file's grammar is needed (cache miss/new)
        std::vector<char> isObjCHeaderMiss( nfilesEarly, 0 );    // 1 ⇒ missed .h should reroute to ObjC grammar
        std::vector<char> isUnknownHeaderMiss( nfilesEarly, 0 ); // 1 ⇒ missed .h could not be sniffed; compile fallback

        if( cache.empty() )
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: mark no-cache grammars" );

            for( std::size_t fi = 0; fi < nfilesEarly; ++fi )
            {
                const LangEntry* le = fileLang[ fi ];
                if( le == nullptr || le->grammar == nullptr )
                {
                    continue;   // doc extensions / markdown — no grammar needed
                }

                present[ static_cast<std::size_t>( le - kLangTable.data() ) ] = true;
                if( le->ext == ".h" )
                {
                    // With no cache, every header is a parse miss. Mark ObjC too so a header that reroutes
                    // after the parse pool's content sniff never blocks on an uncompiled query.
                    if( const LangEntry* objcLe = lookupLang( ".m" ) )
                    {
                        present[ static_cast<std::size_t>( objcLe - kLangTable.data() ) ] = true;
                    }
                }
            }
        }
        else
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: detect cache misses" );

            unsigned hwHash = std::thread::hardware_concurrency();
            if( hwHash == 0 )
            {
                hwHash = 1;
            }
            const unsigned nHashThreads = static_cast<unsigned>( std::min<std::size_t>( hwHash, std::max<std::size_t>( nfilesEarly, 1 ) ) );
            std::atomic<std::size_t> nextIdx{ 0 };
            std::vector<std::thread> hashPool;
            hashPool.reserve( nHashThreads );

            for( unsigned t = 0; t < nHashThreads; ++t )
            {
                hashPool.emplace_back( [ & ]()
                {
                    std::string bytes;
                    std::string headerPrefix;
                    for( ;; )
                    {
                        const std::size_t fi = nextIdx.fetch_add( 1, std::memory_order_relaxed );
                        if( fi >= nfilesEarly )
                        {
                            break;
                        }
                        try   // per-file degrade — a throw escaping a worker thread would std::terminate
                        {
                            const std::string& f = result.files[ fi ];
                            const LangEntry* le = fileLang[ fi ];
                            if( le == nullptr )
                            {
                                continue;   // doc extensions — never cached (the doc post-pass re-extracts)
                            }
                            // B0: grammar-less languages (markdown) still flow through the cache stat-gate /
                            // read+hash below so an UNCHANGED .md warm-hits without any read (previously the
                            // early grammar skip left fileHash=0 and the parse pool re-read every .md every
                            // run — the last per-run file-read the postings path had left). They only skip
                            // the grammar-miss bookkeeping at the bottom (nothing to compile for them).

                            bool hasFullBytes = false;

                            // path absent from cache ⇒ definitely a miss (no read needed). Present ⇒ try the
                            // A4-P7 stat-gate first, else read+hash.
                            if( !cache.empty() )
                            {
                                const auto cit = cache.find( f );
                                if( cit != cache.end() )
                                {
                                    const FileFacts& ff = cit->second;

                                    // A4-P7 STAT-GATE: trust the cached parse WITHOUT reading/hashing when the
                                    // current size+mtime still match the cache AND the entry is not racy (its
                                    // mtime is strictly older than the blob's own write time — a same-granule
                                    // post-hash edit could otherwise slip through undetected). Content hash stays
                                    // the authority: any mismatch, an unstatable file, or a racy entry falls
                                    // through to the read+hash path below.
                                    const StatInfo si = statSizeMtime( f );
                                    const bool statMatches = si.mtimeNs >= 0 && ff.mtimeNs >= 0
                                                          && si.sizeBytes == ff.sizeBytes
                                                          && si.mtimeNs   == ff.mtimeNs;
                                    const bool notRacy = cacheWriteNs >= 0 && ff.mtimeNs < cacheWriteNs;
                                    if( statMatches && notRacy )
                                    {
                                        fileHash[ fi ]      = ff.hash;        // parse pool sees a cache hit → never reads
                                        fileStatSize[ fi ]  = si.sizeBytes;   // carry stat forward into the re-saved blob
                                        fileStatMtime[ fi ] = si.mtimeNs;
                                        continue;   // provably unchanged — grammar NOT needed for this file
                                    }

                                    if( !readFile( f, bytes ) )
                                    {
                                        continue;   // unreadable — worker will skip it too (not a miss to compile for)
                                    }
                                    hasFullBytes = true;
                                    const std::uint64_t h = contentHash64( bytes );
                                    fileHash[ fi ] = h;   // pre-fill so the parse pool can skip the re-read on a cache hit
                                    // capture the stat observed at hash time so this file stays stat-gate-eligible next run
                                    fileStatSize[ fi ]  = si.sizeBytes >= 0 ? si.sizeBytes : (long long)bytes.size();
                                    fileStatMtime[ fi ] = si.mtimeNs;
                                    if( ff.hash == h )
                                    {
                                        continue;   // cache hit — parse skipped → grammar NOT needed for this file
                                    }
                                }
                                // else: path not in cache → miss (fall through)
                            }

                            if( le->grammar == nullptr )
                            {
                                continue;   // markdown: hash prefill only — no grammar to compile, no miss to mark
                            }

                            if( le->ext == ".h" )
                            {
                                std::string_view headerBytes;
                                if( hasFullBytes )
                                {
                                    headerBytes = bytes;
                                }
                                else if( readFilePrefix( f, headerPrefix, 8192 ) )
                                {
                                    headerBytes = headerPrefix;
                                }
                                else
                                {
                                    isUnknownHeaderMiss[ fi ] = 1;
                                }
                                if( !headerBytes.empty() && looksObjC( headerBytes ) )
                                {
                                    isObjCHeaderMiss[ fi ] = 1;
                                }
                            }
                            isMiss[ fi ] = 1;   // cache empty, path-absent, or hash-changed → grammar needed
                        }
                        catch( ... )
                        {
                            DEGRADED_PATH_ALERT( "ingest: prewarm hash worker exception on a file — treated as no-miss" );
                        }
                    }
                } );
            }
            for( std::thread& th : hashPool )
            {
                th.join();
            }
            // serial grammar-mark reduction over the per-index results (order-independent: pure boolean OR).
            {
                PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: reduce grammar set" );

                for( std::size_t fi = 0; fi < nfilesEarly; ++fi )
                {
                    if( !isMiss[fi] )
                    {
                        continue;
                    }
                    const LangEntry* le = fileLang[ fi ];
                    if( le == nullptr )
                    {
                        continue; // defensive (isMiss only set for grammar-bearing files)
                    }
                    if( le->ext == ".h" )
                    {
                        if( isObjCHeaderMiss[ fi ] )
                        {
                            if( const LangEntry* objcLe = lookupLang( ".m" ) )
                            {
                                present[ static_cast<std::size_t>( objcLe - kLangTable.data() ) ] = true;
                            }
                        }
                        else
                        {
                            present[ static_cast<std::size_t>( le - kLangTable.data() ) ] = true;
                            if( isUnknownHeaderMiss[ fi ] )
                            {
                                anyUnknownHeaderMiss = true;
                            }
                        }
                        continue;
                    }
                    present[ static_cast<std::size_t>( le - kLangTable.data() ) ] = true;
                }
                if( anyUnknownHeaderMiss )
                {
                    if( const LangEntry* objcLe = lookupLang( ".m" ) )
                    {
                        present[ static_cast<std::size_t>( objcLe - kLangTable.data() ) ] = true;
                    }
                }
            }
        }

        // distinct grammars needed by cache-miss files (several extensions share one grammar)
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: unique grammars" );

            for( std::size_t i = 0; i < kLangTable.size(); ++i )
            {
                const LangEntry& e = kLangTable[ i ];
                if( e.grammar == nullptr || e.querySub.empty() || !present[ i ] )
                {
                    continue;   // querySub "" = markdown: a grammar with NO tags.scm (custom walk) — nothing to compile
                }
                const TSLanguage* lang = e.grammar();
                bool seen = false;
                for( const LangEntry* c : toCompile )
                {
                    if( c->grammar() == lang )
                    {
                        seen = true;
                        break;
                    }
                }
                if( !seen )
                {
                    toCompile.push_back( &e );
                }
            }
        }

        // Compile distinct grammars IN PARALLEL (ts_query_new is compute-bound — PMC IPC 4.0) and install
        // into the shared cache single-threaded after the join. Query sources are immutable embedded views.
        compiledQueries.assign( toCompile.size(), nullptr );
        queryCompilePool.reserve( toCompile.size() );
        queryPrewarmReady.store( toCompile.empty(), std::memory_order_release );
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: launch ts_query_new async" );

            for( std::size_t i = 0; i < toCompile.size(); ++i )
            {
                queryCompilePool.emplace_back( [ &compiledQueries, &toCompile, i ]() { compiledQueries[ i ] = compileQueryStandalone( *toCompile[ i ] ); } );
            }
        }
    }

    // Win 2 (PERF.md P2) — dirty flag: skip saveCache when nothing changed.
    // Set by any worker that re-parses a file (cache miss or new file). On a zero-change run,
    // dirty stays false and the 7 MB re-serialization + write is skipped entirely (~11ms on full repo).
    std::atomic<bool> dirty{ false };

    // A1 (team-index) — drift-proportional observable: count files that actually RE-PARSED (cache miss /
    // changed / new). Emitted to stderr only when RIPWIRE_CACHE_STATS is set (off by default → zero
    // perturbation to any output/determinism gate), so a test can assert "restore cost is proportional to
    // drift" (modify N of F files → reparsed=N) as an executable fact, not just prose. Relaxed: a monotone
    // counter whose only reader is the post-join print, ordered by the pool join below.
    std::atomic<std::size_t> reparsedCount{ 0 };

    const std::size_t nfiles = result.files.size();
    if( nfiles )
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: parse pool (tree-sitter, parallel)" );
        // fileHash is already pre-sized to nfiles (done before the prewarm block above).
        // Entries pre-filled by the prewarm miss-detection pass (cache-present files that were read+hashed
        // there) stay as-is. Workers fill the remaining 0-valued entries for files they process.
        VERIFY( fileHash.size() == nfiles );
        unsigned hw = std::thread::hardware_concurrency();
        if( hw == 0 )
        {
            hw = 1;
        }
        const unsigned nthreads = static_cast<unsigned>( std::min<std::size_t>( hw, nfiles ) );

        std::vector<std::vector<RawDef>>  tDefs( nthreads );
        std::vector<std::vector<RawRef>>  tRefs( nthreads );
        std::vector<std::vector<Include>> tIncs( nthreads );
        std::vector<std::vector<RawBind>> tBinds( nthreads );
        std::vector<std::vector<BindingAlias>> tFfis( nthreads );
        std::vector<std::vector<RouteDef>>     tRouteDefs( nthreads );   // B6.3
        std::vector<std::vector<RawRouteUse>>  tRouteUses( nthreads );   // B6.3
        std::vector<FileFacts*>           cacheCandidateFacts( nfiles, nullptr );
        std::vector<FileFacts*>           cacheHitFacts( nfiles, nullptr );

        // Per-file byte sizes are wanted in two places below — the cold-path reserve, and the
        // longest-file-first work order. Fill at most once, on demand, so a warm run that also skips
        // the work order still performs no stat pass at all (exactly as before this was hoisted).
        std::vector<std::uintmax_t> fileByteSize;
        const auto ensureFileByteSize = [ & ]()
        {
            if( !fileByteSize.empty() )
            {
                return;
            }
            fileByteSize.assign( nfiles, 0 );
            std::error_code ec;
            for( std::size_t fileId = 0; fileId < nfiles; ++fileId )
            {
                ec.clear();
                fileByteSize[ fileId ] = fs::file_size( result.files[ fileId ], ec );
                if( ec )
                {
                    fileByteSize[ fileId ] = 0;
                }
            }
        };

        if( !cache.empty() )
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: prepare cache-hit reuse" );

            std::size_t hitDefs = 0, hitRefs = 0, hitIncs = 0, hitBinds = 0;
            for( std::size_t fileId = 0; fileId < nfiles; ++fileId )
            {
                const std::uint64_t h = fileHash[ fileId ];
                const auto it = cache.find( result.files[ fileId ] );
                if( it == cache.end() )
                {
                    continue;
                }
                cacheCandidateFacts[ fileId ] = &it->second;
                if( it->second.hash != h )
                {
                    continue;
                }
                cacheHitFacts[ fileId ] = &it->second;
                hitDefs  += it->second.defs.size();
                hitRefs  += it->second.refs.size();
                hitIncs  += it->second.incs.size();
                hitBinds += it->second.binds.size();
            }
            const auto perThreadReserve = [ nthreads ]( std::size_t total ) noexcept
            {
                return ( total + std::size_t( nthreads ) - 1 ) / std::size_t( nthreads );
            };
            const std::size_t defsPerThread  = perThreadReserve( hitDefs );
            const std::size_t refsPerThread  = perThreadReserve( hitRefs );
            const std::size_t incsPerThread  = perThreadReserve( hitIncs );
            const std::size_t bindsPerThread = perThreadReserve( hitBinds );
            for( unsigned t = 0; t < nthreads; ++t )
            {
                tDefs[ t ].reserve( defsPerThread );
                tRefs[ t ].reserve( refsPerThread );
                tIncs[ t ].reserve( incsPerThread );
                tBinds[ t ].reserve( bindsPerThread );
            }
        }
        else
        {
            // Cold: no cache to size from, so size the accumulators from the crawl's parseable byte
            // count. coldParseReserve() carries the calibration and the reasoning behind the numbers.
            PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: prepare cold reserve" );

            ensureFileByteSize();
            const ColdParseReserve cold = coldParseReserve( fileLang, fileByteSize, nthreads );
            for( unsigned t = 0; t < nthreads; ++t )
            {
                tDefs[ t ].reserve( cold.defs );
                tRefs[ t ].reserve( cold.refs );
                tIncs[ t ].reserve( cold.incs );
                tBinds[ t ].reserve( cold.binds );
            }
        }
        std::vector<std::thread>          pool;
        pool.reserve( nthreads );
        std::vector<std::size_t>          parseOrder;
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: build work order" );

            if( !queryPrewarmReady.load( std::memory_order_acquire ) )
            {
                parseOrder.resize( nfiles );
                std::iota( parseOrder.begin(), parseOrder.end(), std::size_t( 0 ) );

                ensureFileByteSize();   // already filled by the cold-path reserve above; a no-op there

                const auto parsePriority = [ & ]( std::size_t fileId ) noexcept
                {
                    const LangEntry* le = fileLang[ fileId ];
                    if( le == nullptr || le->grammar == nullptr )
                    {
                        return 0;   // docs/markdown and unknowns do not consume the tags-query barrier
                    }
                    if( !cache.empty() && cacheHitFacts[ fileId ] != nullptr )
                    {
                        return 1;   // warm cache hit: cheap copy, no parse/query work
                    }
                    return 2;       // cache miss/no-cache: full parse + tags query
                };
                std::stable_sort( parseOrder.begin(), parseOrder.end(),
                                  [ & ]( std::size_t a, std::size_t b ) noexcept
                                  {
                                      const int pa = parsePriority( a );
                                      const int pb = parsePriority( b );
                                      if( pa != pb )
                                      {
                                          return pa > pb;
                                      }
                                      if( fileByteSize[a] != fileByteSize[b] )
                                      {
                                          return fileByteSize[a] > fileByteSize[b];
                                      }
                                      return a < b;
                                  } );
            }
        }
        std::atomic<std::size_t>          nextFile{ 0 };   // lock-free work queue: threads fetch_add for the next parseOrder slot

        for( unsigned t = 0; t < nthreads; ++t )
        {
            pool.emplace_back( [ &, t ]()
            {
                ParserGuard pg;
                if( pg.p == nullptr )
                {
                    DEGRADED_PATH_ALERT( "ingest: ts_parser_new failed on a worker — its files skipped" );
                    return;
                }
                TSQueryCursor* cursor = ts_query_cursor_new();
                if( cursor == nullptr )
                {
                    DEGRADED_PATH_ALERT( "ingest: ts_query_cursor_new failed on a worker — its files skipped" );
                    return;
                }

                // B0.2: per-worker subtoken-stats builder — after a file's defs are extracted (and the file's
                // bytes are STILL in memory), tokenize each new def's doc/body spans ONCE into its persisted
                // stats (lexindex.h). Rich ingests only; a def's stats ride the RawDef through dedup/sort/cache
                // so alignment with the eventual Symbol is free. scratch is reused across defs (no rehash churn).
                HashMap<std::uint64_t, std::uint32_t> lexScratch;
                if( captureValueUses )
                {
                    lexScratch.reserve( 1024 );
                }
                const auto buildLexForNewDefs = [ & ]( std::vector<RawDef>& defs, std::size_t firstNewDefIndex, const std::string& fileBytes )
                {
                    if( !captureValueUses )
                    {
                        return;
                    }
                    for( std::size_t defIndex = firstNewDefIndex; defIndex < defs.size(); ++defIndex )
                    {
                        buildDefLexStats( fileBytes, defs[ defIndex ].startByte, defs[ defIndex ].endByte, lexScratch, defs[ defIndex ].lex );
                    }
                };

                struct PendingParsedFile
                {
                    std::uint32_t   fileId = 0;
                    const LangEntry* le    = nullptr;
                    std::string     bytes;
                    TSTree*         tree   = nullptr;

                    PendingParsedFile( std::uint32_t fileIdIn, const LangEntry* leIn, std::string&& bytesIn, TSTree* treeIn )
                        : fileId( fileIdIn ), le( leIn ), bytes( std::move( bytesIn ) ), tree( treeIn )
                    {
                    }
                    PendingParsedFile( const PendingParsedFile& ) = delete;
                    PendingParsedFile& operator=( const PendingParsedFile& ) = delete;
                    PendingParsedFile( PendingParsedFile&& other ) noexcept
                        : fileId( other.fileId ), le( other.le ), bytes( std::move( other.bytes ) ), tree( other.tree )
                    {
                        other.tree = nullptr;
                    }
                    PendingParsedFile& operator=( PendingParsedFile&& other ) noexcept
                    {
                        if( this != &other )
                        {
                            if( tree != nullptr )
                            {
                                ts_tree_delete( tree );
                            }
                            fileId = other.fileId;
                            le     = other.le;
                            bytes  = std::move( other.bytes );
                            tree   = other.tree;
                            other.tree = nullptr;
                        }
                        return *this;
                    }
                    ~PendingParsedFile()
                    {
                        if( tree != nullptr )
                        {
                            ts_tree_delete( tree );
                        }
                    }
                };

                constexpr std::size_t kMaxPendingParsedFiles = 4;
                constexpr std::size_t kMaxPendingParsedBytes = 8u * 1024u * 1024u;
                std::vector<PendingParsedFile> pendingParsed;
                pendingParsed.reserve( kMaxPendingParsedFiles );
                std::size_t pendingParsedBytes = 0;
                const auto flushPendingParsed = [ & ]()
                {
                    if( pendingParsed.empty() )
                    {
                        return;
                    }

                    {
                        PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: flush pending parsed tags" );
                        waitForQueryPrewarm( &queryReadyGate );
                        for( PendingParsedFile& pending : pendingParsed )
                        {
                            if( pending.le == nullptr || pending.tree == nullptr )
                            {
                                continue;
                            }
                            const TSNode root = ts_tree_root_node( pending.tree );
                            const std::size_t firstNewDefIndex = tDefs[ t ].size();
                            captureTagsFacts( cursor, *pending.le, pending.fileId, pending.bytes, root, tDefs[ t ], tRefs[ t ] );
                            buildLexForNewDefs( tDefs[ t ], firstNewDefIndex, pending.bytes );   // B0.2: bytes still in memory
                            ts_tree_delete( pending.tree );
                            pending.tree = nullptr;
                        }
                    }
                    pendingParsed.clear();
                    pendingParsedBytes = 0;
                };

                std::string bytes;
                for( ;; )   // lock-free work-stealing: grab the next file via the atomic counter (balances the big-file tail)
                {
                    if( queryPrewarmReady.load( std::memory_order_acquire ) && !pendingParsed.empty() )
                    {
                        flushPendingParsed();
                    }

                    const std::size_t orderIndex = nextFile.fetch_add( 1, std::memory_order_relaxed );
                    if( orderIndex >= nfiles )
                    {
                        break;
                    }
                    const std::size_t fileId = parseOrder.empty() ? orderIndex : parseOrder[ orderIndex ];
                    // per-file try/catch: a throw (bad_alloc, filesystem_error, …) escaping a
                    // std::thread entry would std::terminate the whole process. Degrade per file,
                    // honouring the "never throws" contract (the worse-than-v1 parallel hazard).
                    try
                    {
                        const std::string& path = result.files[ fileId ];

                        const LangEntry* le = fileLang[ fileId ];
                        if( le == nullptr )
                        {
                            continue; // defensive (filtered in crawl)
                        }

                        // If the prewarm miss-detection pass already read+hashed this file, the hash
                        // is already in fileHash[fileId] — skip the re-read for the hash check.
                        // We still need `bytes` for actual parsing, so the fast path (cache hit) avoids readFile entirely.
                        std::uint64_t h = fileHash[ fileId ];
                        bool bytesLoaded = false;
                        if( h == 0 )
                        {
                            // Not pre-hashed: read the file now (first time we see it in the pool)
                            if( !readFile( path, bytes ) )
                            {
                                continue;
                            }
                            if( looksBinary( bytes ) )
                            {
                                continue;
                            }
                            if( le->ext == ".h" && looksObjC( bytes ) )
                            {
                                if( const LangEntry* objcLe = lookupLang( ".m" ) )
                                {
                                    le = objcLe;
                                }
                            }
                            if( needsCacheHash )
                            {
                                h = contentHash64( bytes );
                                fileHash[ fileId ] = h;
                                // A4-P7: capture (size,mtime) at hash time so saveCache can persist a stat-gate
                                // record for this file (cold run / new file / prewarm-skipped path).
                                const StatInfo si = statSizeMtime( path );
                                fileStatSize[ fileId ]  = si.sizeBytes >= 0 ? si.sizeBytes : (long long)bytes.size();
                                fileStatMtime[ fileId ] = si.mtimeNs;
                            }
                            bytesLoaded = true;
                        }

                        if( !cache.empty() )
                        {
                            FileFacts* hit = cacheHitFacts[ fileId ];
                            if( hit == nullptr )
                            {
                                FileFacts* candidate = cacheCandidateFacts[ fileId ];
                                if( candidate != nullptr && candidate->hash == h )
                                {
                                    hit = candidate;
                                }
                            }
                            if( hit != nullptr )   // unchanged → reuse cached facts, skip parse
                            {
                                fileHealth[ fileId ] = hit->health;   // §L1: health is a cached FACT, not a re-derivation
                                for( RawDef& d : hit->defs )
                                {
                                    d.fileId = std::uint32_t( fileId );
                                    tDefs[ t ].push_back( std::move( d ) );
                                }
                                for( RawRef& rr : hit->refs )
                                {
                                    rr.fileId = std::uint32_t( fileId );
                                    tRefs[ t ].push_back( std::move( rr ) );
                                }
                                for( Include& in : hit->incs )
                                {
                                    in.fileId = std::uint32_t( fileId );
                                    tIncs[ t ].push_back( std::move( in ) );
                                }
                                for( RawBind& b : hit->binds )
                                {
                                    b.fileId = std::uint32_t( fileId );
                                    tBinds[ t ].push_back( std::move( b ) );
                                }
                                for( BindingAlias& a : hit->ffis )
                                {
                                    a.fileId = std::uint32_t( fileId );
                                    tFfis[ t ].push_back( std::move( a ) );
                                }
                                for( RouteDef& rd : hit->routeDefs )        // B6.3
                                {
                                    rd.fileId = std::uint32_t( fileId );
                                    tRouteDefs[ t ].push_back( std::move( rd ) );
                                }
                                for( RawRouteUse& ru : hit->routeUses )     // B6.3
                                {
                                    ru.fileId = std::uint32_t( fileId );
                                    tRouteUses[ t ].push_back( std::move( ru ) );
                                }
                                continue;
                            }
                        }

                        // cache miss (new file or hash changed) → need to actually parse
                        dirty.store( true, std::memory_order_relaxed );
                        reparsedCount.fetch_add( 1, std::memory_order_relaxed );   // A1: drift-proportional observable

                        // ensure bytes are loaded (may have been pre-hashed without loading the body)
                        if( !bytesLoaded )
                        {
                            if( !readFile( path, bytes ) )
                            {
                                continue;
                            }
                            if( looksBinary( bytes ) )
                            {
                                continue;
                            }
                            if( le->ext == ".h" && looksObjC( bytes ) )
                            {
                                if( const LangEntry* objcLe = lookupLang( ".m" ) )
                                {
                                    le = objcLe;
                                }
                            }
                        }

                        // hostile/degenerate JSON guard — must run BEFORE the parse (that is the whole point);
                        // the skip is a degrade with a one-line stderr note, matching the house skip style.
                        if( le->lang == Lang::Json && jsonNestsTooDeep( bytes ) )
                        {
                            std::fprintf( stderr, "[ripwire] %s: json nesting > %u levels — treated as data, not config (skipped)\n",
                                          path.c_str(), kMaxJsonNestDepth );
                            continue;
                        }

                        // hostile/degenerate YAML guard — MEMORY-SAFETY load-bearing, not just a perf guard:
                        // tree-sitter-yaml's scanner serialize() corrupts memory past ~253 block indent levels
                        // (see kMaxYamlNestDepth in ingest.h; the vendored scanner also carries the bounds fix
                        // under third_party/patches/yaml/, so this is the FIRST of two independent layers).
                        // Same house skip style as the JSON guard above: refuse BEFORE the parse, one stderr line.
                        if( le->lang == Lang::Yaml && yamlNestsTooDeep( bytes ) )
                        {
                            std::fprintf( stderr, "[ripwire] %s: yaml nesting > %u levels — treated as data, not config (skipped)\n",
                                          path.c_str(), kMaxYamlNestDepth );
                            continue;
                        }

                        if( le->lang == Lang::Markdown )
                        {
                            // hostile/degenerate markdown guard — MEMORY-SAFETY load-bearing, the yaml pair's
                            // twin: tree-sitter-markdown's scanner serialize() memcpys its open-blocks stack
                            // with NO bounds check (OOB at ~255 nested blockquote/list markers; see
                            // kMaxMdBlockDepth in ingest.h). The vendored scanner also carries the clamp under
                            // third_party/patches/markdown/, so this is the FIRST of two independent layers.
                            if( mdNestsTooDeep( bytes ) )
                            {
                                std::fprintf( stderr, "[ripwire] %s: markdown blockquote/list nesting > %u levels — treated as data, not a doc (skipped)\n",
                                              path.c_str(), kMaxMdBlockDepth );
                                continue;
                            }
                            if( !prepareParserFor( pg.p, *le ) )
                            {
                                continue;
                            }
                            TreeGuard mdTree( parseTree( pg.p, bytes ) );
                            if( mdTree.get() == nullptr )
                            {
                                continue;
                            }
                            fileHealth[ fileId ] = measureFileHealth( ts_tree_root_node( mdTree.get() ), bytes );
                            const std::string stem = fs::path( path ).stem().string();
                            const std::size_t firstNewDefIndex = tDefs[ t ].size();
                            extractMarkdown( static_cast<std::uint32_t>( fileId ), bytes, stem, ts_tree_root_node( mdTree.get() ), tDefs[ t ], tRefs[ t ] );
                            buildLexForNewDefs( tDefs[ t ], firstNewDefIndex, bytes );   // B0.2: md sections/file nodes get stats too
                        }
                        else
                        {
                            if( !prepareParserFor( pg.p, *le ) )
                            {
                                continue;
                            }

                            TreeGuard tree( parseTree( pg.p, bytes ) );
                            if( tree.get() == nullptr )
                            {
                                continue;
                            }

                            const TSNode root = ts_tree_root_node( tree.get() );
                            fileHealth[ fileId ] = measureFileHealth( root, bytes );   // §L1 — before `bytes` can be moved below
                            captureSideFacts( *le, static_cast<std::uint32_t>( fileId ), bytes, root, tRefs[ t ], tIncs[ t ], tBinds[ t ], tFfis[ t ], tRouteDefs[ t ], tRouteUses[ t ], captureValueUses );

                            const bool canQueueParsed = !queryPrewarmReady.load( std::memory_order_acquire )
                                                     && pendingParsed.size() < kMaxPendingParsedFiles
                                                     && pendingParsedBytes + bytes.size() <= kMaxPendingParsedBytes;
                            if( canQueueParsed )
                            {
                                pendingParsedBytes += bytes.size();
                                pendingParsed.emplace_back( static_cast<std::uint32_t>( fileId ), le, std::move( bytes ), tree.release() );
                                continue;
                            }

                            {
                                PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: wait query prewarm" );
                                waitForQueryPrewarm( &queryReadyGate );
                            }
                            const std::size_t firstNewDefIndex = tDefs[ t ].size();
                            captureTagsFacts( cursor, *le, static_cast<std::uint32_t>( fileId ), bytes, root, tDefs[ t ], tRefs[ t ] );
                            buildLexForNewDefs( tDefs[ t ], firstNewDefIndex, bytes );   // B0.2: bytes still in memory
                        }
                    }
                    catch( ... )
                    {
                        DEGRADED_PATH_ALERT( "ingest: worker exception on a file — skipped" );
                    }
                }
                flushPendingParsed();
                ts_query_cursor_delete( cursor );
            } );
        }

        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: wait/install async" );

            for( std::thread& th : queryCompilePool )
            {
                th.join();
            }
            // Install compiled queries single-threaded (workers are still gated). Installing TRANSFERS
            // ownership to CompiledQueryCache, which frees whatever is still resident at process teardown
            // (N2). A652: on an in-process re-ingest (long-lived MCP server) the same grammar can already
            // own a cached query, and overwriting drops the only pointer to it — delete the displaced entry
            // here or it leaks one TSQuery per grammar per re-ingest (A4-F16).
            HashMap<const TSLanguage*, TSQuery*>& cache = compiledQueryCache();
            for( std::size_t i = 0; i < toCompile.size(); ++i )
            {
                const TSLanguage* grammar = toCompile[ i ]->grammar();
                if( auto it = cache.find( grammar ); it != cache.end() && it->second != nullptr && it->second != compiledQueries[ i ] )
                {
                    ts_query_delete( it->second );
                }
                cache[ grammar ] = compiledQueries[ i ];
            }
            // A4-F1: publish readiness UNDER queryPrewarmMutex, then notify. Workers wait via
            // cv.wait(lock, pred); a lock-free store+notify here can slip between a worker's predicate check
            // and its block → lost wakeup → the worker sleeps forever and the main th.join() hangs.
            {
                std::lock_guard<std::mutex> lk( queryPrewarmMutex );
                queryPrewarmReady.store( true, std::memory_order_release );
            }
        }
        queryPrewarmCv.notify_all();

        for( std::thread& th : pool )
        {
            th.join();
        }

        // merge per-thread results (cross-thread order is irrelevant — sorted below)
        std::size_t totDefs = 0, totRefs = 0, totIncs = 0, totBinds = 0, totFfis = 0, totRouteDefs = 0, totRouteUses = 0;
        for( unsigned t = 0; t < nthreads; ++t )
        {
            totDefs  += tDefs[ t ].size();
            totRefs  += tRefs[ t ].size();
            totIncs  += tIncs[ t ].size();
            totBinds += tBinds[ t ].size();
            totFfis  += tFfis[ t ].size();
            totRouteDefs += tRouteDefs[ t ].size();
            totRouteUses += tRouteUses[ t ].size();
        }
        rawDefs.reserve( totDefs );
        rawRefs.reserve( totRefs );
        rawIncs.reserve( totIncs );
        rawBinds.reserve( totBinds );
        rawFfis.reserve( totFfis );
        rawRouteDefs.reserve( totRouteDefs );
        rawRouteUses.reserve( totRouteUses );
        for( unsigned t = 0; t < nthreads; ++t )
        {
            for( RawDef& d : tDefs[t] )
            {
                rawDefs.push_back( std::move( d ) );
            }
            for( RawRef& r : tRefs[t] )
            {
                rawRefs.push_back( std::move( r ) );
            }
            for( Include& in : tIncs[t] )
            {
                rawIncs.push_back( std::move( in ) );
            }
            for( RawBind& b : tBinds[t] )
            {
                rawBinds.push_back( std::move( b ) );
            }
            for( BindingAlias& a : tFfis[t] )
            {
                rawFfis.push_back( std::move( a ) );
            }
            for( RouteDef& rd : tRouteDefs[t] )
            {
                rawRouteDefs.push_back( std::move( rd ) );
            }
            for( RawRouteUse& ru : tRouteUses[t] )
            {
                rawRouteUses.push_back( std::move( ru ) );
            }
        }

        // P1-15: the SAME drift count, carried out of the function instead of only to stderr. The MCP
        // server discloses it per incremental pass (`_reingest`), which it could not do from an env-gated
        // print. Read once here, after the pool join that orders every worker's increment.
        result.reparsedFiles = reparsedCount.load( std::memory_order_relaxed );

        // A1 (team-index) — drift-proportional observable: report how many files re-parsed vs reused,
        // ONLY when RIPWIRE_CACHE_STATS is set (off by default → no stdout/stderr perturbation on any
        // normal run or gate). A warm restore over a tree with N-of-F files changed prints reparsed=N,
        // making the "restore cost is proportional to drift, not tree size" claim executable.
        if( std::getenv( "RIPWIRE_CACHE_STATS" ) != nullptr )
        {
            const std::size_t reparsed = reparsedCount.load( std::memory_order_relaxed );
            std::fprintf( stderr, "ripwire: cache-stats reparsed=%zu reused=%zu files=%zu\n",
                          reparsed, ( nfiles >= reparsed ? nfiles - reparsed : std::size_t( 0 ) ), nfiles );
        }

        // Win 2: rewrite cache only when at least one file changed (dirty flag set by workers above).
        // Skips the ~11ms / 7 MB serialization+write on a no-change warm run.
        if( !cacheFile.empty() && dirty.load() )
        {
            saveCache( std::string( cacheFile ), rootDir, result.files, fileHash, fileStatSize, fileStatMtime, fileHealth, rawDefs, rawRefs, rawIncs, rawBinds, rawFfis, rawRouteDefs, rawRouteUses, captureValueUses );
        }
    }

    result.fileHealth = std::move( fileHealth );   // §L1: after saveCache, before the (unmeasured) doc pass

    // ── doc post-pass (P1-B): every collected document file (notebook/html/csv/…) becomes a docText
    //    override + one whole-file Section node — parallel extract, deterministic ascending-fileId merge
    //    (ingest_docpass.h, with the markitdown-bridge byte cache).
    runDocPostPass( result, rawDefs, !cacheFile.empty(), captureValueUses );

    PROFILE_SCOPE_DESCRIBE( "ingest: build model (dedup + symbols/refs)" );

    // 3a) dedup definitions — overlapping tags patterns collapse to one node per real symbol (ingest_model.h)
    dedupRawDefs( rawDefs );

    // 3a-bis) same-FILE decl/def collapse (ObjC only) — @interface decl vs @implementation def (ingest_model.h)
    collapseObjCDeclDefs( rawDefs );

    // 3b) assign Symbol ids in (fileId, line, name) order + the rich-ingest lex-stats CSR (ingest_model.h)
    assignSymbols( result, rawDefs, captureValueUses );

    // 4) attribute each reference to its enclosing definition (innermost span containing it) — the
    //    per-file DefSpanIndex + DefSweep cursor every fact family below shares (ingest_model.h).
    const DefSpanIndex spanIndex = buildDefSpanIndex( result, rawDefs );

    // references: order a uint32 index permutation (radix by startByte), then MOVE each RawRef's strings
    // into its Reference while the shared sweep attributes fromSymbol (ingest_model.h).
    const std::vector<std::uint32_t> refOrder = orderReferences( rawRefs, result.files.size() );
    emitReferences( result, rawRefs, refOrder, spanIndex );

    // P2-D Rule 2 bindings, A4-R5 FFI aliases, B6.3 route defs/uses — each in its deterministic total
    // order, span-attributed families over the same DefSpanIndex (ingest_model.h).
    emitBindings( result, rawBinds, spanIndex );

    result.includes = std::move( rawIncs );   // physical dependencies (#include / import), for --deps

    emitBindingAliases( result, rawFfis );
    emitRouteDefs( result, rawRouteDefs );
    emitRouteUses( result, rawRouteUses, spanIndex );

    // macro-edges round: the corpus-wide role="macro" retag (model.h). AFTER the model is assembled and
    // AFTER saveCache (which stores the per-file truth, role=Call) — a #define added in one file must
    // re-judge every OTHER file's cached call sites on the next run, so the retag can never be persisted.
    retagMacroCallReferences( result );

    // r9 shadow suppression (model.h): a reference inside a function whose LOCAL declarations bind the same
    // name as a variable belongs to the local, not to any same-named indexed symbol — erase it here, the one
    // choke point BOTH consumers sit downstream of (--uses reads result.references; buildGraph resolves call
    // edges from them), so the false --uses rows and the false call edge die in the same pass. AFTER the
    // macro retag (role="macro" is preprocessor evidence and stays) and AFTER saveCache (per-file truth is
    // persisted unsuppressed; the collision gate depends on the whole corpus' symbols, so the judgment can
    // never be cached per-file — same reasoning as the retag above).
    suppressShadowedReferences( result );

    return result;
}
}   // namespace rw

// The --match/--lint tail: rw-level query services, a SECTION of this same TU (see the split note
// at the top). Included last, exactly where its content sat before the 2026-08-29 split.
#include "ingest_astquery.h"
