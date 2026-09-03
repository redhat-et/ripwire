#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_prewarm.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_prewarm.h — the lazy tags.scm prewarm (PERF.md Win 1), moved VERBATIM out of ingest() in
// the 2026-08-30 decomposition: the parallel cache-miss detection pass (which doubles as the A4-P7
// stat-gate hash prefill), the serial grammar-mark reduction, the distinct-grammar set, the async
// ts_query_new launch, and — called later, from inside the parse pool — the single-threaded
// install + gate-open that releases the workers. The shared compile/ready state the two moments
// hand across ingest() lives in QueryPrewarm, one named object instead of six loose locals. Same
// contract as every ingest_*.h: reopens `namespace rw` and the unnamed namespace inside it — one
// TU, one unnamed namespace, internal linkage unchanged, zero new API surface — under the
// RIPWIRE_INGEST_TU guard.

namespace rw
{

namespace
{

// The per-fileId parallel arrays every ingest phase after the crawl shares: language classification,
// the content-hash / stat-gate capture the prewarm and parse pool fill co-operatively, and the §L1
// per-file health slots (one WRITER per slot). One named bundle so the phase contracts stay short.
struct IngestFileScan
{
    std::vector<const LangEntry*> lang;        // grammar table entry per fileId (nullptr = doc/unknown ext)
    std::vector<std::uint64_t>    hash;        // content hash (0 = not yet hashed)
    std::vector<long long>        statSize;    // A4-P7 + v14: (size,mtime,ctime) observed at hash time (-1 = not captured)
    std::vector<long long>        statMtime;
    std::vector<long long>        statCtime;
    std::vector<FileHealth>       health;      // §L1: one slot per fileId, one writer per slot
};

// size the per-file arrays and classify each file's language — the fileId space is the crawl's sorted list.
inline IngestFileScan makeFileScan( const std::vector<std::string>& files )
{
    const std::size_t nfilesEarly = files.size();
    IngestFileScan scan;
    scan.lang.assign( nfilesEarly, nullptr );
    scan.hash.assign( nfilesEarly, 0 );
    scan.statSize.assign( nfilesEarly, -1 );
    scan.statMtime.assign( nfilesEarly, -1 );
    scan.statCtime.assign( nfilesEarly, -1 );
    scan.health.resize( nfilesEarly );
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: classify file languages" );
        for( std::size_t fileId = 0; fileId < nfilesEarly; ++fileId )
        {
            const std::string ext = lowerExtensionOf( files[ fileId ] );
            scan.lang[ fileId ] = lookupLang( ext );
        }
    }
    return scan;
}

// The compile/ready state the prewarm launch hands to the parse pool's install moment. Non-movable on
// purpose (atomic + mutex + cv): constructed once in ingest(), passed by reference to both phases; the
// async compile threads capture it and are joined by installCompiledQueriesAndOpenGate before it dies.
struct QueryPrewarm
{
    std::vector<const LangEntry*> toCompile;         // distinct grammars the miss set needs
    std::vector<TSQuery*>         compiledQueries;   // 1:1 with toCompile — filled by the async pool
    std::vector<std::thread>      compilePool;       // the ts_query_new workers
    std::atomic<bool>             ready{ true };     // true ⇒ compiledQueryCache() is safe to read
    std::mutex                    mutex;
    std::condition_variable       cv;
};

// pre-warm the per-language tags.scm cache single-threaded; workers then only READ it.
// LAZY: compile ONLY grammars needed by changed/uncached files (the miss set).
// The grammar set must be a SUPERSET of every grammar any worker will touch:
//   - a cache miss → grammar guaranteed needed → mark it
//   - a cache hit (hash-match) → worker skips parse → grammar NOT needed (safe to omit)
//   - a .h miss that looks Objective-C → marks objc instead of cpp (same looksObjC re-route as parse pool)
//   - an unreadable .h miss → conservatively marks both cpp and objc, matching the old safety fallback
inline void prewarmTagsQueries( const std::vector<std::string>& files, const HashMap<std::string, FileFacts>& cache,
                                long long cacheWriteNs, IngestFileScan& scan, QueryPrewarm& prewarm )
{
    PROFILE_SCOPE_DESCRIBE( "ingest: compile queries (tags.scm prewarm)" );
    const std::size_t nfilesEarly = files.size();
    std::array<bool, kLangTable.size()> present {};
    bool anyUnknownHeaderMiss = false;

    // The miss-detection pass reads + FNV-hashes every cache-present code file to decide which grammars a
    // worker will actually need. That I/O + hashing was serial (~61ms on canyon warm). It is READ-ONLY and
    // a pure function of each file's bytes, so parallelize it — but keep the RESULT deterministic: every
    // thread writes ONLY its own per-index slots (scan.hash[fi], isMiss[fi]); nothing is
    // push_back'd from a worker. The grammar-mark reduction that follows is a serial pass over those slots,
    // so the compiled-grammar set (and thus everything downstream) is independent of thread scheduling.
    // The 204bb02 constraint still holds: compiledQueryCache() is populated single-threaded after the
    // async compile join, and workers wait on prewarm.ready before reading it. scan.hash is pre-filled
    // so the pool skips the re-read on a cache hit.
    std::vector<char> isMiss( nfilesEarly, 0 );              // 1 ⇒ this file's grammar is needed (cache miss/new)
    std::vector<char> isObjCHeaderMiss( nfilesEarly, 0 );    // 1 ⇒ missed .h should reroute to ObjC grammar
    std::vector<char> isUnknownHeaderMiss( nfilesEarly, 0 ); // 1 ⇒ missed .h could not be sniffed; compile fallback

    if( cache.empty() )
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: mark no-cache grammars" );

        for( std::size_t fi = 0; fi < nfilesEarly; ++fi )
        {
            const LangEntry* le = scan.lang[ fi ];
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
                        const std::string& f = files[ fi ];
                        const LangEntry* le = scan.lang[ fi ];
                        if( le == nullptr )
                        {
                            continue;   // doc extensions — never cached (the doc post-pass re-extracts)
                        }
                        // B0: grammar-less languages (markdown) still flow through the cache stat-gate /
                        // read+hash below so an UNCHANGED .md warm-hits without any read (previously the
                        // early grammar skip left scan.hash=0 and the parse pool re-read every .md every
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
                                // current size+mtime+ctime all still match the cache AND the entry is not
                                // racy (its mtime is strictly older than the blob's own write time — a
                                // same-granule post-hash edit could otherwise slip through undetected).
                                // Content hash stays the authority: any mismatch, an unstatable file, or a
                                // racy entry falls through to the read+hash path below.
                                //
                                // ctimeNs is the third discriminator and the one that closes the
                                // same-(mtime,size) residual: mtime can be restored by any unprivileged
                                // writer (`touch -r`, `cp -p`, an editor preserving it, a checkout of an
                                // older revision) and the byte length can survive an edit, but the utimes()
                                // that performs the restore is itself an inode change and moves ctime
                                // forward. It is free — this ::stat already returned it. See
                                // ingest_crawl.h statSizeTimes for what is still outside it (a clock moved
                                // backward, raw device writes, a ctime-less filesystem), which is why the
                                // racy rule below is kept rather than replaced.
                                const StatInfo si = statSizeTimes( f );
                                const bool sizeMtimeMatch = si.mtimeNs >= 0 && ff.mtimeNs >= 0
                                                         && si.sizeBytes == ff.sizeBytes
                                                         && si.mtimeNs   == ff.mtimeNs;
                                const bool statMatches = sizeMtimeMatch
                                                      && si.ctimeNs >= 0 && ff.ctimeNs >= 0
                                                      && si.ctimeNs == ff.ctimeNs;
                                const bool notRacy = cacheWriteNs >= 0 && ff.mtimeNs < cacheWriteNs;
                                if( statMatches && notRacy )
                                {
                                    scan.hash[ fi ]      = ff.hash;        // parse pool sees a cache hit → never reads
                                    scan.statSize[ fi ]  = si.sizeBytes;   // carry stat forward into the re-saved blob
                                    scan.statMtime[ fi ] = si.mtimeNs;
                                    scan.statCtime[ fi ] = si.ctimeNs;
                                    continue;   // provably unchanged — grammar NOT needed for this file
                                }

                                if( !readFile( f, bytes ) )
                                {
                                    // THE COST SIDE OF THE ctime DISCRIMINATOR, and the one place it needs a
                                    // degrade. ctime moves on chmod/chown/xattr/rename as well as on a write,
                                    // so those all land here — correctly, and cheaply, since the re-hash then
                                    // agrees with the record. But when the metadata change is what made the
                                    // file UNREADABLE, this read fails, and dropping the file would turn a
                                    // `chmod 000` into a silently partial index (caught by postingscheck (d),
                                    // pinned by statgatecheck (e)).
                                    //
                                    // So: an unreadable file whose (size, mtime) still match a non-racy record
                                    // KEEPS its cached parse. A ctime that moved on its own is a metadata
                                    // change, not evidence of a content change, and serving the last-known
                                    // parse of a file we were unable to look at beats deleting it from the
                                    // answer. Disclosed exposure: a same-(mtime,size) edit hidden behind a
                                    // chmod-to-unreadable is served stale — no cache-free run can do better
                                    // (--no-cache cannot read it either), and the MCP edit verbs re-read and
                                    // byte-hash their target regardless. An unreadable file whose size or
                                    // mtime DID move keeps the pre-existing behaviour: it is dropped.
                                    if( sizeMtimeMatch && notRacy )
                                    {
                                        scan.hash[ fi ]      = ff.hash;
                                        scan.statSize[ fi ]  = si.sizeBytes;
                                        scan.statMtime[ fi ] = si.mtimeNs;
                                        scan.statCtime[ fi ] = si.ctimeNs;   // absorb the metadata move: next run stat-hits again
                                    }
                                    continue;   // unreadable — worker will skip it too (not a miss to compile for)
                                }
                                hasFullBytes = true;
                                const std::uint64_t h = contentHash64( bytes );
                                scan.hash[ fi ] = h;   // pre-fill so the parse pool can skip the re-read on a cache hit
                                // capture the stat observed at hash time so this file stays stat-gate-eligible next run
                                scan.statSize[ fi ]  = si.sizeBytes >= 0 ? si.sizeBytes : (long long)bytes.size();
                                scan.statMtime[ fi ] = si.mtimeNs;
                                scan.statCtime[ fi ] = si.ctimeNs;
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
                const LangEntry* le = scan.lang[ fi ];
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
            for( const LangEntry* c : prewarm.toCompile )
            {
                if( c->grammar() == lang )
                {
                    seen = true;
                    break;
                }
            }
            if( !seen )
            {
                prewarm.toCompile.push_back( &e );
            }
        }
    }

    // Compile distinct grammars IN PARALLEL (ts_query_new is compute-bound — PMC IPC 4.0) and install
    // into the shared cache single-threaded after the join. Query sources are immutable embedded views.
    prewarm.compiledQueries.assign( prewarm.toCompile.size(), nullptr );
    prewarm.compilePool.reserve( prewarm.toCompile.size() );
    prewarm.ready.store( prewarm.toCompile.empty(), std::memory_order_release );
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: launch ts_query_new async" );

        for( std::size_t i = 0; i < prewarm.toCompile.size(); ++i )
        {
            prewarm.compilePool.emplace_back( [ &prewarm, i ]() { prewarm.compiledQueries[ i ] = compileQueryStandalone( *prewarm.toCompile[ i ] ); } );
        }
    }
}

// The install moment: called from the parse pool AFTER the workers are launched (they are doing parse-side
// work or blocked on the gate) — join the async compiles, publish the queries into the shared cache
// single-threaded, then open the gate under the mutex and notify.
inline void installCompiledQueriesAndOpenGate( QueryPrewarm& prewarm )
{
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: wait/install async" );

        for( std::thread& th : prewarm.compilePool )
        {
            th.join();
        }
        // Install compiled queries single-threaded (workers are still gated). Installing TRANSFERS
        // ownership to CompiledQueryCache, which frees whatever is still resident at process teardown
        // (N2). A652: on an in-process re-ingest (long-lived MCP server) the same grammar can already
        // own a cached query, and overwriting drops the only pointer to it — delete the displaced entry
        // here or it leaks one TSQuery per grammar per re-ingest (A4-F16).
        HashMap<const TSLanguage*, TSQuery*>& cache = compiledQueryCache();
        for( std::size_t i = 0; i < prewarm.toCompile.size(); ++i )
        {
            const TSLanguage* grammar = prewarm.toCompile[ i ]->grammar();
            if( auto it = cache.find( grammar ); it != cache.end() && it->second != nullptr && it->second != prewarm.compiledQueries[ i ] )
            {
                ts_query_delete( it->second );
            }
            cache[ grammar ] = prewarm.compiledQueries[ i ];
        }
        // A4-F1: publish readiness UNDER the mutex, then notify. Workers wait via
        // cv.wait(lock, pred); a lock-free store+notify here can slip between a worker's predicate check
        // and its block → lost wakeup → the worker sleeps forever and the main th.join() hangs.
        {
            std::lock_guard<std::mutex> lk( prewarm.mutex );
            prewarm.ready.store( true, std::memory_order_release );
        }
    }
    prewarm.cv.notify_all();
}

}   // namespace

}   // namespace rw
