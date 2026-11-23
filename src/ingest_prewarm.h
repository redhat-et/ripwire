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
// The construct tables (ingest_astquery.h, below in the TU): compiles the tables of the flagged kLangTable rows now, before
// any parse worker runs, and records the footprint they added (constructTablesFootprint).
void warmConstructTables( const std::array<bool, kLangTable.size()>& rows );

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
    std::vector<std::uint32_t>    nestRefusedBytes;   // the Kotlin nesting guard: the refused file's size, 0 = not refused (one writer per slot)
    std::vector<std::uint8_t>     extractPartial;     // 1 = the file's facts are PARTIAL (an ExtractShortfall, or a throw mid-file) (one writer per slot)
    std::vector<std::uint32_t>    extractPartialBytes;   // its size as observed at hash time, 0 = not captured (the row's bytes=)
    // QD-CONSTRUCTS-AT-INGEST (lazy): does this ingest find construct hits (ingest.h tlIngestWantsConstructHits, read once
    // by runParsePool), and per fileId, are its hits KNOWN — found by this parse, or carried by a record that had them.
    // 0 only for a code file parsed without the pass or carried from a record that lacked it; saveCache writes the
    // record "constructs absent" then. One writer per slot.
    bool                          wantConstructHits = false;
    std::vector<std::uint8_t>     constructsKnown;

    // `knownBytes` is the file's size where the caller holds its bytes; otherwise the stat taken at hash time, which is
    // read HERE, before the save path may forget it for the cache. 0 = neither was captured.
    void markExtractPartial( std::size_t fileId, std::size_t knownBytes = 0 ) noexcept
    {
        extractPartial[ fileId ]      = 1;
        const long long size          = knownBytes > 0 ? static_cast<long long>( knownBytes ) : statSize[ fileId ];
        extractPartialBytes[ fileId ] = size > 0 ? static_cast<std::uint32_t>( std::min<long long>( size, UINT32_MAX ) ) : 0u;
    }
};

// The DISCLOSE sink for a file whose extraction THREW part-way: the facts gathered before the throw are kept, so the
// file is marked partial — its --skipped row (why="extract-partial") and a cache record written UNKNOWN say so.
struct FileExtractThrew
{
    enum class DisclosureWhy : std::uint8_t
    {
        WorkerThrew,
    };
    IngestFileScan& scan;
    std::size_t     fileId;
    void disclose( DisclosureWhy ) noexcept
    {
        scan.markExtractPartial( fileId );
        // QD-CONSTRUCTS-AT-INGEST: a throw may have cut the file's construct pass, so its hits are not KNOWN: the ingest claims
        // no carried hits, and --quality-delta re-parses (CodeRabbit 4572576449 on #655). Every slot starts at 1 (known-empty).
        if( fileId < scan.constructsKnown.size() )
        {
            scan.constructsKnown[ fileId ] = 0;
        }
    }
};

// Record a pass's shortfall on the file's slot (plumbing: the DISCLOSE already happened inside the pass).
inline void notePartialExtract( IngestFileScan& scan, std::size_t fileId, const ExtractShortfall& shortfall, std::size_t fileBytes ) noexcept
{
    if( shortfall.isShort )
    {
        scan.markExtractPartial( fileId, fileBytes );
    }
}

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
    scan.nestRefusedBytes.assign( nfilesEarly, 0u );
    scan.extractPartial.assign( nfilesEarly, 0u );
    scan.extractPartialBytes.assign( nfilesEarly, 0u );
    scan.constructsKnown.assign( nfilesEarly, 1u );   // known-empty until a parse without the pass says otherwise
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: classify file languages" );
        for( std::size_t fileId = 0; fileId < nfilesEarly; ++fileId )
        {
            const std::string ext = lowerExtensionOf( files[ fileId ] );
            scan.lang[ fileId ] = lookupLangOfCrawledFile( ext );
        }
    }
    return scan;
}

// One per-file slot array → one --skipped class: serial and in ascending fileId, so the rows are path-sorted like every
// other drop list; capped at kMaxSkipRowsPerClass, with the exact count kept beside them.
template<class IsIn, class BytesOf>
inline void collectSkipClass( const IngestResult& result, std::size_t slotCount, IsIn isIn, BytesOf bytesOf,
                              std::vector<SkippedFile>& rows, std::uint64_t& count )
{
    for( std::size_t fileId = 0; fileId < slotCount && fileId < result.files.size(); ++fileId )
    {
        if( !isIn( fileId ) )
        {
            continue;
        }
        ++count;
        if( rows.size() < kMaxSkipRowsPerClass )
        {
            rows.push_back( SkippedFile{ result.files[ fileId ], bytesOf( fileId ), lowerExtensionOf( result.files[ fileId ] ) } );
        }
    }
}

// The Kotlin nesting guard's refusals, as --skipped rows (why="nest-refused"). Serial and in ascending fileId, so the rows
// are path-sorted like every other drop list; capped at kMaxSkipRowsPerClass like them, with the exact count kept beside.
// A refused file never reaches the cache (no facts were extracted), so every run — cold or warm — re-reads it, re-refuses
// it, and rebuilds this list: the rows cannot go stale.
inline void collectNestRefusals( const IngestFileScan& scan, IngestResult& result )
{
    collectSkipClass( result, scan.nestRefusedBytes.size(), [ & ]( std::size_t f ) { return scan.nestRefusedBytes[ f ] != 0; },
                      [ & ]( std::size_t f ) { return std::uint64_t( scan.nestRefusedBytes[ f ] ); },
                      result.crawlSkips.nestRefused, result.crawlSkips.nestRefusedFiles );
}

// The files whose facts are PARTIAL, as --skipped rows (why="extract-partial"), collectNestRefusals' shape: serial, ascending
// fileId, capped rows beside an exact count. bytes= is the size observed at hash time (0 when none was captured).
// NOT written to the cache as whole (forgetNestRefusalsForCache also forgets these), so the rows cannot go stale either.
inline void collectExtractPartials( const IngestFileScan& scan, IngestResult& result )
{
    collectSkipClass( result, scan.extractPartial.size(), [ & ]( std::size_t f ) { return scan.extractPartial[ f ] != 0; },
                      [ & ]( std::size_t f ) { return std::uint64_t( scan.extractPartialBytes[ f ] ); },
                      result.crawlSkips.extractPartial, result.crawlSkips.extractPartialFiles );
}

// A file the nesting guard refused yielded NO facts, so the cache record saveCache writes for every crawled file would
// read, on the next warm run, as "parsed, nothing there": a stat-gate or hash hit that never reaches the prescan, so the
// refusal — its stderr note and its --skipped row — vanished from every warm run (kotlincheck §12's warm arm caught it).
// The record is written as UNKNOWN instead: hash 0 and the stat gate's own -1 "not captured" triple, so the next run
// re-reads the file, re-refuses it and re-rows it. Called on the save path only, after the pool has joined; nothing
// reads these slots afterwards. The price is a re-read and re-refusal on each warm run, not a cache rewrite: the parse pool
// leaves the blob clean when it already holds this UNKNOWN record (ingest_parsepool.h noteFactlessMiss).
inline void forgetNestRefusalsForCache( IngestFileScan& scan ) noexcept
{
    for( std::size_t fileId = 0; fileId < scan.nestRefusedBytes.size(); ++fileId )
    {
        // a PARTIAL extraction is forgotten the same way: its record would otherwise read, warm, as the whole answer
        if( scan.nestRefusedBytes[ fileId ] == 0 && ( fileId >= scan.extractPartial.size() || scan.extractPartial[ fileId ] == 0 ) )
        {
            continue;
        }
        scan.hash[ fileId ]      = 0;
        scan.statSize[ fileId ]  = -1;
        scan.statMtime[ fileId ] = -1;
        scan.statCtime[ fileId ] = -1;
    }
}

// #157: generalized from the Kotlin-only guard this struct used to name alone. PROCESS-SURVIVAL /
// MEMORY-SAFETY load-bearing for all four cases refuseNesting below switches on (see ingest.h for each
// ceiling's own defect arithmetic). A refusal here is ITEMIZED — its size lands in scan.nestRefusedBytes,
// which collectNestRefusals turns into --skipped rows — because a refused file takes real content out of
// the map and the reader must be told which file and why, not just counted into unmeasured=.
// The DISCLOSE sink for one refusal: recording the refused file's size in its scan slot IS the disclosure —
// collectNestRefusals turns the slot into the --skipped row (why="nest-refused") and nest_refused=, in every
// build flavour, whichever LANGUAGE's guard fired.
struct NestRefusal
{
    enum class DisclosureWhy : std::uint8_t
    {
        JsonNesting,
        YamlNesting,
        MarkdownBlockNesting,
        KotlinStringTemplates,
    };
    IngestFileScan& scan;
    std::size_t     fileId;
    std::uint32_t   bytes;
    void disclose( DisclosureWhy ) noexcept   // every reason records the same fact
    {
        scan.nestRefusedBytes[ fileId ] = bytes;
    }
};

// The one call site every corpus-file parse uses (#157), generalized from the Kotlin-only
// refuseKotlinNesting this replaces. Before it, JSON/YAML/Markdown were three hand-copied `if` blocks
// with no --skipped row and no warm-cache forgetting, and Kotlin was a fourth, separately-itemized one;
// the fact that three of the four were forgotten is exactly what a second hand-copied site risks doing
// again. Deliberately NOT a runtime table of function pointers: `&jsonNestsTooDeep` etc. taken as data
// left every prescan with ZERO call-graph edges into it (ripwire's own resolver tracks AST call
// expressions, not values read out of an aggregate — `--callers=jsonNestsTooDeep` measured count="0" on a
// function four verbs actually call), so quality-delta's own dead-code check gated on FOUR bogus findings
// against this very diff. A `switch` keeps every prescan a textually direct call, at the cost of the
// per-case repetition the table used to buy — the DISCLOSE call needed a compile-time-literal `why` at
// each site regardless (RW_DISCLOSE_SINK_ binds it to a `constexpr` local), so this is one switch doing
// the job two used to.
inline bool refuseNesting( const LangEntry& le, std::string_view bytes, const char* path, std::size_t fileId, IngestFileScan& scan )
{
    // EXPECTS, not VALIDATE: fileId is not external input here — it is the parse worker's own loop index into
    // the SAME scan the crawl sized (makeFileScan assigns every per-file array, nestRefusedBytes included, to
    // exactly files.size() before the pool starts). A violation would be a caller bug, not a hostile corpus.
    EXPECTS( fileId < scan.nestRefusedBytes.size(), "refuseNesting: fileId must index the scan the crawl already sized" );
    switch( le.lang )
    {
        case Lang::Json:
        {
            if( !jsonNestsTooDeep( bytes ) )
            {
                return false;
            }
            NestRefusal refusal{ scan, fileId, static_cast<std::uint32_t>( std::min<std::size_t>( bytes.size(), UINT32_MAX ) ) };
            DISCLOSE( refusal, NestRefusal::DisclosureWhy::JsonNesting,
                      "ingest: a .json file nests brackets/braces past kMaxJsonNestDepth — refused before the parse (--skipped why=nest-refused)" );
            rw::emitTo( stderr, "[ripwire] {}: json nesting > {} levels — treated as data, not config (skipped)\n", path, kMaxJsonNestDepth );
            return true;
        }
        case Lang::Yaml:
        {
            if( !yamlNestsTooDeep( bytes ) )
            {
                return false;
            }
            NestRefusal refusal{ scan, fileId, static_cast<std::uint32_t>( std::min<std::size_t>( bytes.size(), UINT32_MAX ) ) };
            DISCLOSE( refusal, NestRefusal::DisclosureWhy::YamlNesting,
                      "ingest: a .yml/.yaml file nests blocks past kMaxYamlNestDepth — refused before the parse (--skipped why=nest-refused)" );
            rw::emitTo( stderr, "[ripwire] {}: yaml nesting > {} levels — treated as data, not config (skipped)\n", path, kMaxYamlNestDepth );
            return true;
        }
        case Lang::Markdown:
        {
            if( !mdNestsTooDeep( bytes ) )
            {
                return false;
            }
            NestRefusal refusal{ scan, fileId, static_cast<std::uint32_t>( std::min<std::size_t>( bytes.size(), UINT32_MAX ) ) };
            DISCLOSE( refusal, NestRefusal::DisclosureWhy::MarkdownBlockNesting,
                      "ingest: a markdown file nests blockquotes/lists past kMaxMdBlockDepth — refused before the parse (--skipped why=nest-refused)" );
            rw::emitTo( stderr, "[ripwire] {}: markdown blockquote/list nesting > {} levels — treated as data, not a doc (skipped)\n", path, kMaxMdBlockDepth );
            return true;
        }
        case Lang::Kotlin:
        {
            if( !kotlinStringsNestTooDeep( bytes ) )
            {
                return false;
            }
            NestRefusal refusal{ scan, fileId, static_cast<std::uint32_t>( std::min<std::size_t>( bytes.size(), UINT32_MAX ) ) };
            DISCLOSE( refusal, NestRefusal::DisclosureWhy::KotlinStringTemplates,
                      "ingest: a .kt file nests string templates past kMaxKotlinStringNestDepth — refused before the parse (--skipped why=nest-refused)" );
            rw::emitTo( stderr, "[ripwire] {}: kotlin string-template nesting > {} levels — refused before the parse (skipped)\n", path, kMaxKotlinStringNestDepth );
            return true;
        }
        default:
            return false;   // no nesting guard applies to this language
    }
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

// One bool per kLangTable row: the grammars a prewarm step marks as needed.
using LangRowSet = std::array<bool, kLangTable.size()>;

// The kLangTable row of a grammar table entry.
inline std::size_t langRowOf( const LangEntry* le ) noexcept
{
    return static_cast<std::size_t>( le - kLangTable.data() );
}

// The rows whose construct tables this ingest's parse will use: each parsed file's row (no cache, a miss, or the ObjC row of
// a missed .h that sniffs ObjC), and a hit whose record lacks its hits (the pool parses it for them alone). A .h hit that
// sniffs ObjC there, or a hit whose record fails late, compiles its table in the worker as before, unmeasured: the
// projection then counts those bytes as growth, the cautious side.
inline LangRowSet constructRowsNeeded( const CacheRecords& cache, const IngestFileScan& scan, const std::vector<char>& isMiss,
                                       const std::vector<char>& isObjCHeaderMiss )
{
    LangRowSet rows {};
    const LangEntry* objcLe = lookupLang( ".m" );
    for( std::size_t fi = 0; fi < scan.lang.size(); ++fi )
    {
        const LangEntry* le = scan.lang[ fi ];
        if( le == nullptr || le->grammar == nullptr )
        {
            continue;
        }
        const CachedRecordHead* head = cache.empty() ? nullptr : cache.headOf( fi );
        if( !cache.empty() && !isMiss[ fi ] && ( head == nullptr || !head->constructsAbsent ) )
        {
            continue;   // a hit that carries its hits (or a file no worker parses): no table
        }
        if( isObjCHeaderMiss[ fi ] && objcLe != nullptr )
        {
            le = objcLe;
        }
        rows[ langRowOf( le ) ] = true;
    }
    return rows;
}

// With no cache every code file is a parse miss: mark each one's grammar, and ObjC's beside every header's, so a header
// that reroutes after the parse pool's content sniff never blocks on an uncompiled query.
inline LangRowSet markNoCacheGrammars( const IngestFileScan& scan, std::size_t nfiles )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: mark no-cache grammars" );

    LangRowSet       present {};
    const LangEntry* objcLe = lookupLang( ".m" );
    for( std::size_t fi = 0; fi < nfiles; ++fi )
    {
        const LangEntry* le = scan.lang[ fi ];
        if( le == nullptr || le->grammar == nullptr )
        {
            continue;   // doc extensions / markdown — no grammar needed
        }
        present[ langRowOf( le ) ] = true;
        if( le->ext == ".h" && objcLe != nullptr )
        {
            present[ langRowOf( objcLe ) ] = true;
        }
    }
    return present;
}

// Per-index results of the miss-detection pass. Every hash worker writes ONLY file fi's slots (and scan's); nothing is
// push_back'd from a worker, so the grammar set reduced from these serially is independent of thread scheduling.
struct PrewarmMissSlots
{
    std::vector<char> isMiss;                // 1 ⇒ this file's grammar is needed (cache miss/new)
    std::vector<char> isObjCHeaderMiss;      // 1 ⇒ missed .h should reroute to ObjC grammar
    std::vector<char> isUnknownHeaderMiss;   // 1 ⇒ missed .h could not be sniffed; compile fallback

    explicit PrewarmMissSlots( std::size_t nfiles ) : isMiss( nfiles, 0 ), isObjCHeaderMiss( nfiles, 0 ), isUnknownHeaderMiss( nfiles, 0 ) {}
};

// What the miss-detection pass shares across its hash workers: read-only inputs, and the per-index slots each worker
// writes for its own files only. Built only when the cache holds records.
struct PrewarmMissPass
{
    const std::vector<std::string>& files;
    const CacheRecords&             cache;
    long long                       cacheWriteNs;   // the cache blob's own write time: the stat-gate's racy-entry bound
    IngestFileScan&                 scan;
    PrewarmMissSlots&               slots;
};

// One hash worker's read buffers, reused across its files (readFile / readFilePrefix keep their capacity).
struct PrewarmReadBuffers
{
    std::string bytes;          // a whole file, read to re-hash it
    std::string headerPrefix;   // the first 8 KiB of a missed .h the stat-gate skipped reading, for the ObjC sniff
};

// The verdict on one file the cache holds a record for.
enum class CachedRecordVerdict : std::uint8_t
{
    kept,      // no parse needs its grammar: the record still holds (stat-gate or matching re-hash), or the file is unreadable
    changed,   // its bytes, now in the worker's buffer, hash differently from the record: a miss
};

// Record a file's content hash and the stat observed now in its scan slots: the parse pool reads `hash` (equal to the
// record's ⇒ a hit, no re-read) and the re-saved blob keeps the (size, mtime, ctime) so the file stays stat-gate-eligible.
inline void captureHashAndStat( IngestFileScan& scan, std::size_t fi, std::uint64_t hash, long long sizeBytes, const StatInfo& si ) noexcept
{
    scan.hash[ fi ]      = hash;
    scan.statSize[ fi ]  = sizeBytes;
    scan.statMtime[ fi ] = si.mtimeNs;
    scan.statCtime[ fi ] = si.ctimeNs;
}

// Does file fi's cached record still hold? The A4-P7 stat-gate first (no read), else read + hash (the bytes stay in
// `bytes` for the caller's header sniff).
inline CachedRecordVerdict probeCachedRecord( const PrewarmMissPass& pass, std::size_t fi, const CachedRecordHead& record, std::string& bytes )
{
    // A4-P7 STAT-GATE: trust the cached parse WITHOUT reading/hashing when the current size+mtime+ctime all still match the
    // cache AND the entry is not racy (its mtime is strictly older than the blob's own write time — a same-granule post-hash
    // edit could otherwise slip through undetected). Content hash stays the authority: any mismatch, an unstatable file, or
    // a racy entry falls through to the read+hash path below.
    //
    // ctimeNs is the third discriminator and the one that closes the same-(mtime,size) residual: mtime can be restored by
    // any unprivileged writer (`touch -r`, `cp -p`, an editor preserving it, a checkout of an older revision) and the byte
    // length can survive an edit, but the utimes() that performs the restore is itself an inode change and moves ctime
    // forward. It is free — this ::stat already returned it. See ingest_crawl.h statSizeTimes for what is still outside it
    // (a clock moved backward, raw device writes, a ctime-less filesystem), which is why the racy rule below is kept rather
    // than replaced.
    const std::string& path           = pass.files[ fi ];
    const StatInfo     si             = statSizeTimes( path );
    const bool         sizeMtimeMatch = si.mtimeNs >= 0 && record.mtimeNs >= 0 && si.sizeBytes == record.sizeBytes && si.mtimeNs == record.mtimeNs;
    const bool         statMatches    = sizeMtimeMatch && si.ctimeNs >= 0 && record.ctimeNs >= 0 && si.ctimeNs == record.ctimeNs;
    const bool         notRacy        = pass.cacheWriteNs >= 0 && record.mtimeNs < pass.cacheWriteNs;
    if( statMatches && notRacy )
    {
        captureHashAndStat( pass.scan, fi, record.hash, si.sizeBytes, si );   // parse pool sees a cache hit → never reads
        return CachedRecordVerdict::kept;                                     // provably unchanged — grammar NOT needed
    }

    if( !readFile( path, bytes ) )
    {
        // THE COST SIDE OF THE ctime DISCRIMINATOR, and the one place it needs a degrade. ctime moves on
        // chmod/chown/xattr/rename as well as on a write, so those all land here — correctly, and cheaply, since the re-hash
        // then agrees with the record. But when the metadata change is what made the file UNREADABLE, this read fails, and
        // dropping the file would turn a `chmod 000` into a silently partial index (caught by postingscheck (d), pinned by
        // statgatecheck (e)).
        //
        // So: an unreadable file whose (size, mtime) still match a non-racy record KEEPS its cached parse. A ctime that moved
        // on its own is a metadata change, not evidence of a content change, and serving the last-known parse of a file we
        // were unable to look at beats deleting it from the answer. Disclosed exposure: a same-(mtime,size) edit hidden
        // behind a chmod-to-unreadable is served stale — no cache-free run can do better (--no-cache cannot read it either),
        // and the MCP edit verbs re-read and byte-hash their target regardless. An unreadable file whose size or mtime DID
        // move keeps the pre-existing behaviour: it is dropped.
        if( sizeMtimeMatch && notRacy )
        {
            captureHashAndStat( pass.scan, fi, record.hash, si.sizeBytes, si );   // absorb the metadata move: next run stat-hits again
        }
        return CachedRecordVerdict::kept;   // unreadable — worker will skip it too (not a miss to compile for)
    }

    // pre-fill the hash so the parse pool can skip the re-read on a cache hit, with the stat observed at hash time
    const std::uint64_t h = contentHash64( bytes );
    captureHashAndStat( pass.scan, fi, h, si.sizeBytes >= 0 ? si.sizeBytes : static_cast<long long>( bytes.size() ), si );
    return record.hash == h ? CachedRecordVerdict::kept : CachedRecordVerdict::changed;
}

// A missed .h: does its content look Objective-C (the parse pool then re-routes it to the ObjC grammar)? `fullBytes` is
// the whole file when the probe read it; otherwise its first 8 KiB are read here. A header that cannot be read at all is
// marked unknown: the reduction then compiles ObjC as well as its own grammar.
inline void sniffMissedHeader( const PrewarmMissPass& pass, std::size_t fi, const std::string* fullBytes, std::string& headerPrefix )
{
    std::string_view headerBytes;
    if( fullBytes != nullptr )
    {
        headerBytes = *fullBytes;
    }
    else if( readFilePrefix( pass.files[ fi ], headerPrefix, 8192 ) )
    {
        headerBytes = headerPrefix;
    }
    else
    {
        pass.slots.isUnknownHeaderMiss[ fi ] = 1;
    }
    if( !headerBytes.empty() && looksObjC( headerBytes ) )
    {
        pass.slots.isObjCHeaderMiss[ fi ] = 1;
    }
}

// One file of the miss-detection pass: does its cached parse still hold, and if not, which grammar will its parse need?
// Writes ONLY file fi's slots.
inline void detectFileCacheMiss( const PrewarmMissPass& pass, std::size_t fi, PrewarmReadBuffers& buffers )
{
    const LangEntry* le = pass.scan.lang[ fi ];
    if( le == nullptr )
    {
        return;   // doc extensions — never cached (the doc post-pass re-extracts)
    }
    // B0: grammar-less languages (markdown) still flow through the cache stat-gate / read+hash so an UNCHANGED .md
    // warm-hits without any read (previously the early grammar skip left scan.hash=0 and the parse pool re-read every .md
    // every run — the last per-run file-read the postings path had left). They only skip the grammar-miss bookkeeping at
    // the bottom (nothing to compile for them).

    // path absent from cache ⇒ definitely a miss (no read needed). Present ⇒ the record probe decides.
    bool hasFullBytes = false;
    if( const CachedRecordHead* head = pass.cache.headOf( fi ) )
    {
        if( probeCachedRecord( pass, fi, *head, buffers.bytes ) == CachedRecordVerdict::kept )
        {
            return;   // cache hit or unreadable — parse skipped → grammar NOT needed for this file
        }
        hasFullBytes = true;
    }

    if( le->grammar == nullptr )
    {
        return;   // markdown: hash prefill only — no grammar to compile, no miss to mark
    }
    if( le->ext == ".h" )
    {
        sniffMissedHeader( pass, fi, hasFullBytes ? &buffers.bytes : nullptr, buffers.headerPrefix );
    }
    pass.slots.isMiss[ fi ] = 1;   // path-absent or hash-changed → grammar needed
}

// The miss-detection pass reads + FNV-hashes every cache-present code file to decide which grammars a worker will actually
// need. That I/O + hashing was serial (~61ms on canyon warm). It is READ-ONLY and a pure function of each file's bytes, so
// it runs on a pool — every thread claims files by index and writes only their slots (detectFileCacheMiss). scan.hash is
// pre-filled so the parse pool skips the re-read on a cache hit. Returns after the pool joins.
inline void runPrewarmHashPool( const PrewarmMissPass& pass )
{
    const std::size_t nfiles = pass.files.size();
    unsigned          hwHash = std::thread::hardware_concurrency();
    if( hwHash == 0 )
    {
        hwHash = 1;
    }
    const unsigned           nHashThreads = static_cast<unsigned>( std::min<std::size_t>( hwHash, std::max<std::size_t>( nfiles, 1 ) ) );
    std::atomic<std::size_t> nextIdx{ 0 };
    std::vector<std::thread> hashPool;
    hashPool.reserve( nHashThreads );
    for( unsigned t = 0; t < nHashThreads; ++t )
    {
        hashPool.emplace_back( [ &pass, &nextIdx, nfiles ]() noexcept
        {
            PrewarmReadBuffers buffers;
            for( std::size_t fi = nextIdx.fetch_add( 1, std::memory_order_relaxed ); fi < nfiles; fi = nextIdx.fetch_add( 1, std::memory_order_relaxed ) )
            {
                try   // per-file degrade — a throw escaping a worker thread would std::terminate
                {
                    detectFileCacheMiss( pass, fi, buffers );
                }
                catch( ... )
                {
                    DISCLOSE( Diagnostics::answerUnchanged,
                              "a missed prewarm only defers a grammar's query: a file then left without it discloses extract-partial itself",
                              "ingest: prewarm hash worker exception on a file — treated as no-miss" );
                }
            }
        } );
    }
    for( std::thread& th : hashPool )
    {
        th.join();
    }
}

// The serial grammar-mark reduction over the pass's per-index slots (order-independent: a pure boolean OR). A missed .h
// marks ObjC when it sniffed ObjC, else its own grammar — plus ObjC, once, when any header could not be sniffed at all
// (the conservative fallback).
inline LangRowSet reduceMissedGrammars( const IngestFileScan& scan, const PrewarmMissSlots& slots )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: reduce grammar set" );

    LangRowSet       present {};
    const LangEntry* objcLe               = lookupLang( ".m" );
    bool             anyUnknownHeaderMiss = false;
    for( std::size_t fi = 0; fi < slots.isMiss.size(); ++fi )
    {
        const LangEntry* le = scan.lang[ fi ];
        if( !slots.isMiss[ fi ] || le == nullptr )
        {
            continue;   // le == nullptr is defensive: isMiss is only set for grammar-bearing files
        }
        if( le->ext != ".h" )
        {
            present[ langRowOf( le ) ] = true;
            continue;
        }
        if( slots.isObjCHeaderMiss[ fi ] )
        {
            if( objcLe != nullptr )
            {
                present[ langRowOf( objcLe ) ] = true;
            }
            continue;
        }
        present[ langRowOf( le ) ] = true;
        if( slots.isUnknownHeaderMiss[ fi ] )
        {
            anyUnknownHeaderMiss = true;
        }
    }
    if( anyUnknownHeaderMiss && objcLe != nullptr )
    {
        present[ langRowOf( objcLe ) ] = true;
    }
    return present;
}

// With a cache: find the files whose record no longer holds (in parallel), then mark the grammars their parses need.
inline LangRowSet markCacheMissGrammars( const PrewarmMissPass& pass )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: detect cache misses" );

    runPrewarmHashPool( pass );
    return reduceMissedGrammars( pass.scan, pass.slots );
}

// The distinct grammars the marked rows need (several extensions share one grammar), first row first.
inline void collectGrammarsToCompile( const LangRowSet& present, QueryPrewarm& prewarm )
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
        if( std::ranges::none_of( prewarm.toCompile, [ lang ]( const LangEntry* c ) { return c->grammar() == lang; } ) )
        {
            prewarm.toCompile.push_back( &e );
        }
    }
}

// Compile distinct grammars IN PARALLEL (ts_query_new is compute-bound — PMC IPC 4.0); installCompiledQueriesAndOpenGate
// installs them into the shared cache single-threaded after the join. Query sources are immutable embedded views.
inline void launchQueryCompiles( QueryPrewarm& prewarm )
{
    prewarm.compiledQueries.assign( prewarm.toCompile.size(), nullptr );
    prewarm.compilePool.reserve( prewarm.toCompile.size() );
    prewarm.ready.store( prewarm.toCompile.empty(), std::memory_order_release );
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: launch ts_query_new async" );

        for( std::size_t i = 0; i < prewarm.toCompile.size(); ++i )
        {
            // A throw escaping a std::thread entry is std::terminate (CONTRIBUTING.md §3), and compileQueryStandalone builds
            // a std::string. A query that did not compile is already a degrade its consumer handles: it stays nullptr, and
            // captureTagsFacts discloses each file that needed it (ingest_astquery.h).
            prewarm.compilePool.emplace_back( [ &prewarm, i ]() noexcept
            {
                try
                {
                    prewarm.compiledQueries[ i ] = compileQueryStandalone( *prewarm.toCompile[ i ] );
                }
                catch( ... )
                {
                    DISCLOSE( Diagnostics::answerUnchanged,
                              "a query left uncompiled stays absent, and captureTagsFacts discloses each file that needed it as extract-partial",
                              "ingest: prewarm query compile worker exception — that grammar's query stays absent" );
                }
            } );
        }
    }
}

// pre-warm the per-language tags.scm cache single-threaded; workers then only READ it.
// LAZY: compile ONLY grammars needed by changed/uncached files (the miss set).
// The grammar set must be a SUPERSET of every grammar any worker will touch:
//   - a cache miss → grammar guaranteed needed → mark it
//   - a cache hit (hash-match) → worker skips parse → grammar NOT needed (safe to omit)
//   - a .h miss that looks Objective-C → marks objc instead of cpp (same looksObjC re-route as parse pool)
//   - an unreadable .h miss → conservatively marks both cpp and objc, matching the old safety fallback
// The 204bb02 constraint holds: compiledQueryCache() is populated single-threaded after the async compile join, and
// workers wait on prewarm.ready before reading it.
inline void prewarmTagsQueries( const std::vector<std::string>& files, const CacheRecords& cache,
                                long long cacheWriteNs, IngestFileScan& scan, QueryPrewarm& prewarm )
{
    PROFILE_SCOPE_DESCRIBE( "ingest: compile queries (tags.scm prewarm)" );

    PrewarmMissSlots missSlots( files.size() );
    const LangRowSet present = cache.empty() ? markNoCacheGrammars( scan, files.size() )
                                             : markCacheMissGrammars( PrewarmMissPass{ files, cache, cacheWriteNs, scan, missSlots } );
    collectGrammarsToCompile( present, prewarm );

    // QD-PROJECTION-FIXED: the construct tables, before the tags compiles launch — no other thread of this ingest runs here
    // (the hash pool has joined), so the footprint they add is theirs alone.
    if( scan.wantConstructHits )
    {
        warmConstructTables( constructRowsNeeded( cache, scan, missSlots.isMiss, missSlots.isObjCHeaderMiss ) );
    }
    launchQueryCompiles( prewarm );
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

// WARM-DIRECT: compile and install the tags query of each grammar in `grammars` the cache does not hold yet — for the
// parse pool's late misses (a cached record that failed in a worker after the prewarm counted it a hit). Called after
// the pool join, so this thread is the cache's only writer, as installCompiledQueriesAndOpenGate is above.
inline void installLateQueries( const std::vector<const LangEntry*>& grammars )
{
    HashMap<const TSLanguage*, TSQuery*>& cache = compiledQueryCache();
    for( const LangEntry* le : grammars )
    {
        if( le->grammar != nullptr && !cache.contains( le->grammar() ) )
        {
            cache[ le->grammar() ] = compileQueryStandalone( *le );
        }
    }
}

}   // namespace

}   // namespace rw
