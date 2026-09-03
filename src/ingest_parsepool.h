#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_parsepool.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_parsepool.h — the parallel parse pool, moved VERBATIM out of ingest() in the 2026-08-30
// decomposition: the per-thread raw-fact accumulators (one RawFacts each), the cold-path reserve
// calibration, the lock-free work-stealing worker (cache-hit reuse, hostile-input guards, the
// pending-parsed-tree queue that overlaps parsing with the async query compile), the single
// install/gate-open moment, the deterministic per-thread merge, and the dirty-gated saveCache.
// runParsePool is the phase contract ingest() calls; ParsePoolShared is the one named view of the
// state a worker touches. Same contract as every ingest_*.h: reopens `namespace rw` and the unnamed
// namespace inside it — one TU, one unnamed namespace, internal linkage unchanged, zero new API
// surface — under the RIPWIRE_INGEST_TU guard.

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

namespace
{

// One thread's (and, merged, the whole pool's) raw extraction output — the seven fact families the
// model-build tail consumes. Also the per-thread accumulator shape, so the merge is family-wise moves.
struct RawFacts
{
    std::vector<RawDef>       defs;
    std::vector<RawRef>       refs;
    std::vector<Include>      incs;
    std::vector<RawBind>      binds;       // P2-D Rule 2: local var→type bindings
    std::vector<BindingAlias> ffis;        // A4-R5: cross-language FFI binding declarations
    std::vector<RouteDef>     routeDefs;   // B6.3: HTTP server-side route registrations
    std::vector<RawRouteUse>  routeUses;   // B6.3: HTTP client-side calls (pre fromSymbol attribution)
};

// A parsed-but-unqueried file waiting for the tags-query gate: owns its bytes and its TSTree until
// the flush hands them to captureTagsFacts (move-only; the tree is freed on destruction if unflushed).
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

// an unchanged file's cached facts, re-labelled with today's fileId and appended to the worker's
// accumulators — the warm path's whole per-file cost (health is a cached FACT, not a re-derivation).
inline void appendCacheHitFacts( FileFacts& hit, std::uint32_t fileId, IngestFileScan& scan, RawFacts& out )
{
    scan.health[ fileId ] = hit.health;   // §L1
    for( RawDef& d : hit.defs )
    {
        d.fileId = fileId;
        out.defs.push_back( std::move( d ) );
    }
    for( RawRef& rr : hit.refs )
    {
        rr.fileId = fileId;
        out.refs.push_back( std::move( rr ) );
    }
    for( Include& in : hit.incs )
    {
        in.fileId = fileId;
        out.incs.push_back( std::move( in ) );
    }
    for( RawBind& b : hit.binds )
    {
        b.fileId = fileId;
        out.binds.push_back( std::move( b ) );
    }
    for( BindingAlias& a : hit.ffis )
    {
        a.fileId = fileId;
        out.ffis.push_back( std::move( a ) );
    }
    for( RouteDef& rd : hit.routeDefs )        // B6.3
    {
        rd.fileId = fileId;
        out.routeDefs.push_back( std::move( rd ) );
    }
    for( RawRouteUse& ru : hit.routeUses )     // B6.3
    {
        ru.fileId = fileId;
        out.routeUses.push_back( std::move( ru ) );
    }
}

// Everything one parse worker touches, by reference, under one name — the worker function's whole
// contract. Lifetimes: all referents live in runParsePool's frame, which joins the pool before returning.
struct ParsePoolShared
{
    const std::vector<std::string>&  files;                 // the fileId space (result.files)
    HashMap<std::string, FileFacts>& cache;
    IngestFileScan&                  scan;                  // lang/hash/stat/health per fileId
    QueryPrewarm&                    prewarm;               // .ready gates compiledQueryCache() reads
    const QueryReadyGate&            gate;                  // the cv wait bundle over prewarm's members
    const std::vector<FileFacts*>&   cacheCandidateFacts;   // path present in cache (hash not yet compared)
    const std::vector<FileFacts*>&   cacheHitFacts;         // hash-verified hits (prewarm-confirmed)
    std::vector<RawFacts>&           tFacts;                // per-thread accumulators, slot t owned by worker t
    const std::vector<std::size_t>&  parseOrder;            // optional work order (empty ⇒ natural order)
    std::atomic<std::size_t>&        nextFile;              // lock-free work queue cursor
    std::atomic<bool>&               dirty;                 // any file re-parsed ⇒ cache must be re-saved
    std::atomic<std::size_t>&        reparsedCount;         // A1 drift observable
    std::size_t                      nfiles;
    bool                             needsCacheHash;
    bool                             captureValueUses;
};

// one worker's whole life: grab files off the shared cursor, reuse cache hits, parse+capture misses,
// queueing parsed trees while the tags queries still compile. Body moved verbatim from the lambda in
// ingest() (accumulators renamed tDefs[t]→out.defs etc., shared state reached through `sh`).
inline void runParseWorker( ParsePoolShared& sh, unsigned t )
{
    IngestFileScan& scan = sh.scan;
    RawFacts&       out  = sh.tFacts[ t ];

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
    if( sh.captureValueUses )
    {
        lexScratch.reserve( 1024 );
    }
    const auto buildLexForNewDefs = [ & ]( std::vector<RawDef>& defs, std::size_t firstNewDefIndex, const std::string& fileBytes )
    {
        if( !sh.captureValueUses )
        {
            return;
        }
        for( std::size_t defIndex = firstNewDefIndex; defIndex < defs.size(); ++defIndex )
        {
            buildDefLexStats( fileBytes, defs[ defIndex ].startByte, defs[ defIndex ].endByte, lexScratch, defs[ defIndex ].lex );
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
            waitForQueryPrewarm( &sh.gate );
            for( PendingParsedFile& pending : pendingParsed )
            {
                if( pending.le == nullptr || pending.tree == nullptr )
                {
                    continue;
                }
                const TSNode root = ts_tree_root_node( pending.tree );
                const std::size_t firstNewDefIndex = out.defs.size();
                captureTagsFacts( cursor, *pending.le, pending.fileId, pending.bytes, root, out.defs, out.refs );
                buildLexForNewDefs( out.defs, firstNewDefIndex, pending.bytes );   // B0.2: bytes still in memory
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
        if( sh.prewarm.ready.load( std::memory_order_acquire ) && !pendingParsed.empty() )
        {
            flushPendingParsed();
        }

        const std::size_t orderIndex = sh.nextFile.fetch_add( 1, std::memory_order_relaxed );
        if( orderIndex >= sh.nfiles )
        {
            break;
        }
        const std::size_t fileId = sh.parseOrder.empty() ? orderIndex : sh.parseOrder[ orderIndex ];
        // per-file try/catch: a throw (bad_alloc, filesystem_error, …) escaping a
        // std::thread entry would std::terminate the whole process. Degrade per file,
        // honouring the "never throws" contract (the worse-than-v1 parallel hazard).
        try
        {
            const std::string& path = sh.files[ fileId ];

            const LangEntry* le = scan.lang[ fileId ];
            if( le == nullptr )
            {
                continue; // defensive (filtered in crawl)
            }

            // If the prewarm miss-detection pass already read+hashed this file, the hash
            // is already in scan.hash[fileId] — skip the re-read for the hash check.
            // We still need `bytes` for actual parsing, so the fast path (cache hit) avoids readFile entirely.
            std::uint64_t h = scan.hash[ fileId ];
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
                if( sh.needsCacheHash )
                {
                    h = contentHash64( bytes );
                    scan.hash[ fileId ] = h;
                    // A4-P7: capture (size,mtime) at hash time so saveCache can persist a stat-gate
                    // record for this file (cold run / new file / prewarm-skipped path).
                    const StatInfo si = statSizeTimes( path );
                    scan.statSize[ fileId ]  = si.sizeBytes >= 0 ? si.sizeBytes : (long long)bytes.size();
                    scan.statMtime[ fileId ] = si.mtimeNs;
                    scan.statCtime[ fileId ] = si.ctimeNs;
                }
                bytesLoaded = true;
            }

            if( !sh.cache.empty() )
            {
                FileFacts* hit = sh.cacheHitFacts[ fileId ];
                if( hit == nullptr )
                {
                    FileFacts* candidate = sh.cacheCandidateFacts[ fileId ];
                    if( candidate != nullptr && candidate->hash == h )
                    {
                        hit = candidate;
                    }
                }
                if( hit != nullptr )   // unchanged → reuse cached facts, skip parse
                {
                    appendCacheHitFacts( *hit, std::uint32_t( fileId ), scan, out );
                    continue;
                }
            }

            // cache miss (new file or hash changed) → need to actually parse
            sh.dirty.store( true, std::memory_order_relaxed );
            sh.reparsedCount.fetch_add( 1, std::memory_order_relaxed );   // A1: drift-proportional observable

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
                scan.health[ fileId ] = measureFileHealth( ts_tree_root_node( mdTree.get() ), bytes );
                const std::string stem = fs::path( path ).stem().string();
                const std::size_t firstNewDefIndex = out.defs.size();
                extractMarkdown( static_cast<std::uint32_t>( fileId ), bytes, stem, ts_tree_root_node( mdTree.get() ), out.defs, out.refs );
                buildLexForNewDefs( out.defs, firstNewDefIndex, bytes );   // B0.2: md sections/file nodes get stats too
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
                scan.health[ fileId ] = measureFileHealth( root, bytes );   // §L1 — before `bytes` can be moved below
                captureSideFacts( *le, static_cast<std::uint32_t>( fileId ), bytes, root, out.refs, out.incs, out.binds, out.ffis, out.routeDefs, out.routeUses, sh.captureValueUses );

                const bool canQueueParsed = !sh.prewarm.ready.load( std::memory_order_acquire )
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
                    waitForQueryPrewarm( &sh.gate );
                }
                const std::size_t firstNewDefIndex = out.defs.size();
                captureTagsFacts( cursor, *le, static_cast<std::uint32_t>( fileId ), bytes, root, out.defs, out.refs );
                buildLexForNewDefs( out.defs, firstNewDefIndex, bytes );   // B0.2: bytes still in memory
            }
        }
        catch( ... )
        {
            DEGRADED_PATH_ALERT( "ingest: worker exception on a file — skipped" );
        }
    }
    flushPendingParsed();
    ts_query_cursor_delete( cursor );
}

// merge per-thread results into one RawFacts (cross-thread order is irrelevant — everything is
// re-sorted by the model-build tail), reserving each family's exact total first.
inline RawFacts mergeThreadFacts( std::vector<RawFacts>& tFacts )
{
    RawFacts raw;
    std::size_t totDefs = 0, totRefs = 0, totIncs = 0, totBinds = 0, totFfis = 0, totRouteDefs = 0, totRouteUses = 0;
    for( const RawFacts& tf : tFacts )
    {
        totDefs  += tf.defs.size();
        totRefs  += tf.refs.size();
        totIncs  += tf.incs.size();
        totBinds += tf.binds.size();
        totFfis  += tf.ffis.size();
        totRouteDefs += tf.routeDefs.size();
        totRouteUses += tf.routeUses.size();
    }
    raw.defs.reserve( totDefs );
    raw.refs.reserve( totRefs );
    raw.incs.reserve( totIncs );
    raw.binds.reserve( totBinds );
    raw.ffis.reserve( totFfis );
    raw.routeDefs.reserve( totRouteDefs );
    raw.routeUses.reserve( totRouteUses );
    for( RawFacts& tf : tFacts )
    {
        for( RawDef& d : tf.defs )
        {
            raw.defs.push_back( std::move( d ) );
        }
        for( RawRef& r : tf.refs )
        {
            raw.refs.push_back( std::move( r ) );
        }
        for( Include& in : tf.incs )
        {
            raw.incs.push_back( std::move( in ) );
        }
        for( RawBind& b : tf.binds )
        {
            raw.binds.push_back( std::move( b ) );
        }
        for( BindingAlias& a : tf.ffis )
        {
            raw.ffis.push_back( std::move( a ) );
        }
        for( RouteDef& rd : tf.routeDefs )
        {
            raw.routeDefs.push_back( std::move( rd ) );
        }
        for( RawRouteUse& ru : tf.routeUses )
        {
            raw.routeUses.push_back( std::move( ru ) );
        }
    }
    return raw;
}

// 2) parse every file IN PARALLEL — one TSParser per worker thread (parsers aren't thread-safe),
//    per-thread raw lists merged after. Determinism is preserved: defs/refs are re-sorted by the
//    model-build tail, so collection order is irrelevant. Also owns the two flags that ride the
//    pool (the Win-2 dirty flag and the A1 reparsed counter), the install/gate-open moment, and
//    the dirty-gated saveCache — everything between the prewarm launch and the doc post-pass.
inline RawFacts runParsePool( IngestResult& result, const char* rootDir, std::string_view cacheFile, bool captureValueUses,
                              HashMap<std::string, FileFacts>& cache, IngestFileScan& scan, QueryPrewarm& prewarm )
{
    RawFacts raw;
    const bool needsCacheHash = !cacheFile.empty();
    QueryReadyGate queryReadyGate{ &prewarm.ready, &prewarm.mutex, &prewarm.cv };

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
        // scan.hash is already pre-sized to nfiles (done by makeFileScan, before the prewarm).
        // Entries pre-filled by the prewarm miss-detection pass (cache-present files that were read+hashed
        // there) stay as-is. Workers fill the remaining 0-valued entries for files they process.
        VERIFY( scan.hash.size() == nfiles );
        unsigned hw = std::thread::hardware_concurrency();
        if( hw == 0 )
        {
            hw = 1;
        }
        const unsigned nthreads = static_cast<unsigned>( std::min<std::size_t>( hw, nfiles ) );

        std::vector<RawFacts>   tFacts( nthreads );
        std::vector<FileFacts*> cacheCandidateFacts( nfiles, nullptr );
        std::vector<FileFacts*> cacheHitFacts( nfiles, nullptr );

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
                const std::uint64_t h = scan.hash[ fileId ];
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
                tFacts[ t ].defs.reserve( defsPerThread );
                tFacts[ t ].refs.reserve( refsPerThread );
                tFacts[ t ].incs.reserve( incsPerThread );
                tFacts[ t ].binds.reserve( bindsPerThread );
            }
        }
        else
        {
            // Cold: no cache to size from, so size the accumulators from the crawl's parseable byte
            // count. coldParseReserve() carries the calibration and the reasoning behind the numbers.
            PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: prepare cold reserve" );

            ensureFileByteSize();
            const ColdParseReserve cold = coldParseReserve( scan.lang, fileByteSize, nthreads );
            for( unsigned t = 0; t < nthreads; ++t )
            {
                tFacts[ t ].defs.reserve( cold.defs );
                tFacts[ t ].refs.reserve( cold.refs );
                tFacts[ t ].incs.reserve( cold.incs );
                tFacts[ t ].binds.reserve( cold.binds );
            }
        }
        std::vector<std::thread>          pool;
        pool.reserve( nthreads );
        std::vector<std::size_t>          parseOrder;
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: build work order" );

            if( !prewarm.ready.load( std::memory_order_acquire ) )
            {
                parseOrder.resize( nfiles );
                std::iota( parseOrder.begin(), parseOrder.end(), std::size_t( 0 ) );

                ensureFileByteSize();   // already filled by the cold-path reserve above; a no-op there

                const auto parsePriority = [ & ]( std::size_t fileId ) noexcept
                {
                    const LangEntry* le = scan.lang[ fileId ];
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

        ParsePoolShared shared{ result.files, cache, scan, prewarm, queryReadyGate, cacheCandidateFacts, cacheHitFacts,
                                tFacts, parseOrder, nextFile, dirty, reparsedCount, nfiles, needsCacheHash, captureValueUses };

        for( unsigned t = 0; t < nthreads; ++t )
        {
            pool.emplace_back( [ &shared, t ]() { runParseWorker( shared, t ); } );
        }

        installCompiledQueriesAndOpenGate( prewarm );   // join async compiles, publish, open the gate (ingest_prewarm.h)

        for( std::thread& th : pool )
        {
            th.join();
        }

        raw = mergeThreadFacts( tFacts );

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
            saveCache( std::string( cacheFile ), rootDir, result.files, scan.hash, scan.statSize, scan.statMtime, scan.statCtime, scan.health, raw.defs, raw.refs, raw.incs, raw.binds, raw.ffis, raw.routeDefs, raw.routeUses, captureValueUses );
        }
    }
    return raw;
}

}   // namespace

}   // namespace rw
