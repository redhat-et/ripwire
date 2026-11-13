#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_parsepool.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

#include "clones.h"     // cloneBodyKey — CLONES-PERSIST: the per-def clone key the cache carries
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings
#include "memstats.h" // M0 MEM-STATS: RIPWIRE_STATS footprint readings at the pool join and after the cache write

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

// QD-CONSTRUCTS-AT-INGEST (defined in the ingest_astquery.h section, below): one file's --quality-delta construct hits,
// from the tree the worker just built.
void collectConstructHits( const LangEntry& le, std::uint32_t fileId, std::string_view bytes, TSNode root, TSQueryCursor* cur,
                           std::vector<ConstructHit>& out );

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
    ASSUME( nthreads >= 1 );   // caller derives it from min( hardware_concurrency, nfiles ) with nfiles >= 1
    ASSUME( fileLang.size() == fileByteSize.size() );

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
    ASSUME( r.defs  <= kCapPerThread && ( r.defs  == 0 || std::has_single_bit( r.defs  ) ) );
    ASSUME( r.refs  <= kCapPerThread && ( r.refs  == 0 || std::has_single_bit( r.refs  ) ) );
    ASSUME( r.incs  <= kCapPerThread && ( r.incs  == 0 || std::has_single_bit( r.incs  ) ) );
    ASSUME( r.binds <= kCapPerThread && ( r.binds == 0 || std::has_single_bit( r.binds ) ) );
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
    std::vector<ConstOpen>    constOpens;  // parser version 82: Ruby class/module opens (model.h ConstOpen)
    std::vector<ConstructHit> constructs;  // QD-CONSTRUCTS-AT-INGEST: --quality-delta construct hits (collectConstructHits)
};

// A parsed-but-unqueried file waiting for the tags-query gate: owns its bytes and its TSTree until
// the flush hands them to captureTagsFacts (move-only; the tree is freed on destruction if unflushed).
// It also owns the file's decided-dead byte ranges (#72 follow-up): those are walked ONCE, beside the
// side captures, and the tags pass that consumes them can run several files later — so they ride here
// rather than being re-derived at the flush, which would pay preprocdead.h's walk twice on every
// C-family file that owns an include guard (the shape whose cost audit P1-0 measured at 56.67% of busy
// leaf samples before the cursor fix).
struct PendingParsedFile
{
    std::uint32_t   fileId = 0;
    const LangEntry* le    = nullptr;
    std::string     bytes;
    TSTree*         tree   = nullptr;
    std::vector<PreprocDeadRange> ppDead;

    PendingParsedFile( std::uint32_t fileIdIn, const LangEntry* leIn, std::string&& bytesIn, TSTree* treeIn, std::vector<PreprocDeadRange>&& ppDeadIn )
        : fileId( fileIdIn ), le( leIn ), bytes( std::move( bytesIn ) ), tree( treeIn ), ppDead( std::move( ppDeadIn ) )
    {
    }
    PendingParsedFile( const PendingParsedFile& ) = delete;
    PendingParsedFile& operator=( const PendingParsedFile& ) = delete;
    PendingParsedFile( PendingParsedFile&& other ) noexcept
        : fileId( other.fileId ), le( other.le ), bytes( std::move( other.bytes ) ), tree( other.tree ), ppDead( std::move( other.ppDead ) )
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
            ppDead = std::move( other.ppDead );
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
// P1-11 (2026-09-10 full audit) — THE WARM-PATH GROWTH OBSERVABLE. §4e of that audit read ~30% of a warm
// llvm `--grep` as un-reserved vector growth on the cache path (RawRef/RawDef/RawBind push_back 21.7% of
// busy + 8.4% memmove). Two of the three suspects were already exact — loadCache reserves each per-file
// family from the record's own count, and mergeThreadFacts reserves each family's exact total — so the
// only accumulator that could still reallocate is THIS one, the per-thread warm-hit accumulator. Counting
// is what settles it: `growths` is incremented once per family per file when the append is about to cross
// capacity, and runParsePool publishes the total as `warm_growths=` on the RIPWIRE_CACHE_STATS line. That
// makes "the warm path does not reallocate" an executable fact instead of a profile reading — the same
// posture `reparsed=`/`cached_records=` already take for their claims. One capacity() compare per family
// per file; nothing in the per-element loops changes.
// One family of a cache hit: re-stamp today's fileId on every row and move it into the worker's accumulator.
template <typename Row>
inline void appendRelabelled( std::vector<Row>& rows, std::uint32_t fileId, std::vector<Row>& dst )
{
    for( Row& row : rows )
    {
        row.fileId = fileId;
        dst.push_back( std::move( row ) );
    }
}

inline std::size_t appendCacheHitFacts( FileFacts& hit, std::uint32_t fileId, IngestFileScan& scan, RawFacts& out )
{
    const auto willGrow = []( const auto& dst, std::size_t need ) noexcept
    {
        return std::size_t( need > dst.capacity() - dst.size() );
    };
    const std::size_t growths = willGrow( out.defs, hit.defs.size() )
                              + willGrow( out.refs, hit.refs.size() )
                              + willGrow( out.incs, hit.incs.size() )
                              + willGrow( out.binds, hit.binds.size() )
                              + willGrow( out.ffis, hit.ffis.size() )
                              + willGrow( out.routeDefs, hit.routeDefs.size() )
                              + willGrow( out.routeUses, hit.routeUses.size() )
                              + willGrow( out.constOpens, hit.constOpens.size() )
                              + willGrow( out.constructs, hit.constructs.size() );

    scan.health[ fileId ]          = hit.health;   // §L1
    scan.constructsKnown[ fileId ] = hit.constructsAbsent ? 0 : 1;   // QD-CONSTRUCTS-AT-INGEST: the record says whether it has them
    appendRelabelled( hit.defs, fileId, out.defs );
    appendRelabelled( hit.refs, fileId, out.refs );
    appendRelabelled( hit.incs, fileId, out.incs );
    appendRelabelled( hit.binds, fileId, out.binds );
    appendRelabelled( hit.ffis, fileId, out.ffis );
    appendRelabelled( hit.routeDefs, fileId, out.routeDefs );     // B6.3
    appendRelabelled( hit.routeUses, fileId, out.routeUses );     // B6.3
    appendRelabelled( hit.constOpens, fileId, out.constOpens );   // parser version 82
    appendRelabelled( hit.constructs, fileId, out.constructs );   // QD-CONSTRUCTS-AT-INGEST
    return growths;
}

// P1-11 — the warm accumulators' EXACT sizing material: every cache hit's per-family fact count, summed.
// Four of these (defs/refs/incs/binds) were already summed inline in runParsePool; the other four were not,
// so ffis/routeDefs/routeUses/constOpens doubled up from zero on every warm run. The cold path skips those
// four ON PURPOSE (coldParseReserve's closing note: it has only a bytes-based ESTIMATE, and estimating a
// family that is empty on most workers is pure waste) — but this path is not estimating. The cached
// FileFacts carry the exact counts, summing them is one more add in a loop that already runs, and
// reserve( 0 ) is a no-op, so an empty family costs nothing and a non-empty one stops reallocating.
struct WarmHitTotals
{
    std::size_t defs = 0, refs = 0, incs = 0, binds = 0;
    std::size_t ffis = 0, routeDefs = 0, routeUses = 0, constOpens = 0, constructs = 0;
};

// One pass over the fileId space: fill `candidates` (a record head present in the blob, hash not yet compared) and `hits`
// (hash-verified), and total the hits' eight families on the way through. WARM-DIRECT: the totals come from the v49 head
// counts, so the reserve stays exact although no record body has been decoded yet.
inline WarmHitTotals markCacheHits( const CacheRecords& cache, const IngestFileScan& scan,
                                    std::vector<const CachedRecordHead*>& candidates, std::vector<const CachedRecordHead*>& hits )
{
    ASSUME_NO_ALIAS( candidates, hits );
    WarmHitTotals tot;
    for( std::size_t fileId = 0; fileId < candidates.size(); ++fileId )
    {
        const CachedRecordHead* head = cache.headOf( fileId );
        if( head == nullptr )
        {
            continue;
        }
        candidates[ fileId ] = head;
        if( head->hash != scan.hash[ fileId ] )
        {
            continue;
        }
        hits[ fileId ]   = head;
        tot.defs        += head->counts.defs;
        tot.refs        += head->counts.refs;
        tot.incs        += head->counts.incs;
        tot.binds       += head->counts.binds;
        tot.ffis        += head->counts.ffis;
        tot.routeDefs   += head->counts.routeDefs;
        tot.routeUses   += head->counts.routeUses;
        tot.constOpens  += head->counts.constOpens;
        tot.constructs  += head->counts.constructs;
    }
    return tot;
}

// Each worker gets its 1/nthreads share of every family. Exact when the pool runs one thread; on more, a
// worker that draws more than its share off the lock-free queue still reallocates, which is what
// `warm_growths=` on the RIPWIRE_CACHE_STATS line measures (golang/go, 11,003 files warm on 18 threads:
// 29-36 across 8 families x 18 workers). Ceiling division, so a family with fewer entries than threads
// still gets 1 apiece rather than 0.
inline void reserveWarmFamilies( std::vector<RawFacts>& tFacts, const WarmHitTotals& tot, unsigned nthreads )
{
    const auto share = [ nthreads ]( std::size_t total ) noexcept
    {
        return ( total + std::size_t( nthreads ) - 1 ) / std::size_t( nthreads );
    };
    for( RawFacts& tf : tFacts )
    {
        tf.defs.reserve( share( tot.defs ) );
        tf.refs.reserve( share( tot.refs ) );
        tf.incs.reserve( share( tot.incs ) );
        tf.binds.reserve( share( tot.binds ) );
        tf.ffis.reserve( share( tot.ffis ) );
        tf.routeDefs.reserve( share( tot.routeDefs ) );
        tf.routeUses.reserve( share( tot.routeUses ) );
        tf.constOpens.reserve( share( tot.constOpens ) );
        tf.constructs.reserve( share( tot.constructs ) );
    }
}

// Everything one parse worker touches, by reference, under one name — the worker function's whole
// contract. Lifetimes: all referents live in runParsePool's frame, which joins the pool before returning.
struct ParsePoolShared
{
    const std::vector<std::string>&  files;                 // the fileId space (result.files)
    const CacheRecords&              cache;                 // the warm plan: per-fileId record heads + the open blob
    IngestFileScan&                  scan;                  // lang/hash/stat/health per fileId
    QueryPrewarm&                    prewarm;               // .ready gates compiledQueryCache() reads
    const QueryReadyGate&            gate;                  // the cv wait bundle over prewarm's members
    const std::vector<const CachedRecordHead*>& cacheCandidateFacts;   // record head present in the blob (hash not yet compared)
    const std::vector<const CachedRecordHead*>& cacheHitFacts;         // hash-verified hits (prewarm-confirmed)
    std::vector<std::uint8_t>&       lateMiss;              // 1 ⇒ this hit's record failed in the worker; parsed after the join
    std::vector<RawFacts>&           tFacts;                // per-thread accumulators, slot t owned by worker t
    const std::vector<std::size_t>&  parseOrder;            // optional work order (empty ⇒ natural order)
    std::atomic<std::size_t>&        nextFile;              // lock-free work queue cursor
    std::atomic<bool>&               dirty;                 // any file re-parsed ⇒ cache must be re-saved
    std::atomic<std::size_t>&        reparsedCount;         // A1 drift observable
    std::atomic<std::size_t>&        warmGrowths;           // P1-11: warm-hit accumulator reallocations (RIPWIRE_CACHE_STATS)
    std::size_t                      nfiles;
    bool                             needsCacheHash;
    bool                             captureValueUses;
    memguard::Watch*                 memWatch;              // #350: null = unguarded; else checked before each claim
};

// WARM-REWRITE: true when the blob's record for a file is exactly the record saveCache would write for it now —
// `expect` carries that record's key (hash, stat triple, health) and no facts, so the record must hold none in any
// of the eight families (WARM-DIRECT: the v49 head counts say so without decoding the body).
inline bool blobHoldsFactlessRecord( const CachedRecordHead* rec, const CachedRecordHead& expect ) noexcept
{
    return rec != nullptr && rec->hash == expect.hash && rec->sizeBytes == expect.sizeBytes && rec->mtimeNs == expect.mtimeNs
        && rec->ctimeNs == expect.ctimeNs && rec->health == expect.health && rec->counts.none() && !rec->constructsAbsent;
}

// A cache miss is about to change the blob: mark it dirty and count the file as drift (RIPWIRE_CACHE_STATS reparsed=).
inline void markMissDirty( ParsePoolShared& sh ) noexcept
{
    sh.dirty.store( true, std::memory_order_relaxed );
    sh.reparsedCount.fetch_add( 1, std::memory_order_relaxed );   // A1: drift-proportional observable
}

// WARM-REWRITE (reports/graph-efficiency-ideas.md #5): a cache miss that ends BEFORE the parse — unreadable,
// binary-sniffed, or nest-refused — extracts no facts, so the record saveCache writes for it is its hash, stat
// triple and health alone, and a refused file's hash and stat are forgotten to UNKNOWN (0, -1, -1, -1:
// forgetNestRefusalsForCache), which is what makes every warm run re-read and re-refuse it. When the blob already
// holds exactly that record, re-serializing the whole blob changes nothing: envoy rewrote its 146 MB cache on
// every warm run (a full re-serialize and write of the cache) for one refused deep_recursion.json. So such a miss dirties the
// blob only when the record differs: a path the blob lacks, a file that just became refused or binary, a record
// that held facts, a hash or stat that moved. A file that stops being refused reaches the parse, which dirties.
inline void noteFactlessMiss( ParsePoolShared& sh, std::size_t fileId, bool nestRefused ) noexcept
{
    const IngestFileScan& scan = sh.scan;
    CachedRecordHead      expect;
    expect.health = scan.health[ fileId ];
    if( !nestRefused )   // a refused file keeps the default UNKNOWN key (0, -1, -1, -1), as forgetNestRefusalsForCache writes it
    {
        expect.hash      = scan.hash[ fileId ];
        expect.sizeBytes = scan.statSize[ fileId ];
        expect.mtimeNs   = scan.statMtime[ fileId ];
        expect.ctimeNs   = scan.statCtime[ fileId ];
    }
    const bool same = blobHoldsFactlessRecord( sh.cacheCandidateFacts[ fileId ], expect );
    if( !same )
    {
        markMissDirty( sh );
    }
}

// One worker's cache-record scratch, reused across its hits.
struct RecordScratch
{
    std::string                bytes;   // one cache record's bytes
    std::vector<std::uint64_t> dict;    //   its subtoken dictionary (rich only)
    FileFacts                  facts;   //   its decoded facts; moved into the worker's arrays, capacity kept for the next hit
};

// CacheRecords::decode, with a throw (bad_alloc on the record buffer or a fact array) reported as the failure it is: the
// caller then schedules the file as a late miss and reparses it after the join, instead of the worker's catch-all
// marking it extract-partial with its facts missing.
inline bool decodeCachedRecordNoThrow( const CacheRecords& cache, std::size_t fileId, const std::string& path, RecordScratch& rec )
{
    try
    {
        return cache.decode( fileId, path, rec.bytes, rec.dict, rec.facts );
    }
    catch( ... )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "the affected files are reparsed from source: the answer is byte-identical, only slower",
                  "ingest: cache record decode threw — that file is reparsed" );
        return false;
    }
}

// one worker's whole life: grab files off the shared cursor, reuse cache hits, parse+capture misses,
// queueing parsed trees while the tags queries still compile. Body moved verbatim from the lambda in
// ingest() (accumulators renamed tDefs[t]→out.defs etc., shared state reached through `sh`).
// CLONES-PERSIST: a new def's clone key, from the span assignSymbols will give its Symbol (ingest_model.h: sigEndByte =
// bodyByte > startByte ? bodyByte : endByte) — so it hashes exactly the [sigEndByte, endByte) findClones compares.
// kCloneKeyNone for a def findClones never compares (not a Function/Method, or no body region).
inline std::uint64_t rawDefCloneKey( const std::string& fileBytes, const RawDef& d )
{
    const std::uint32_t sigEnd = d.bodyByte > d.startByte ? d.bodyByte : d.endByte;
    if( ( ( kCloneKeyKindBits >> unsigned( d.kind ) ) & 1u ) == 0 || d.endByte <= sigEnd )
    {
        return kCloneKeyNone;
    }
    return cloneBodyKey( fileBytes, sigEnd, d.endByte, usesHashLineComments( d.lang ) );
}

// QD-CONSTRUCTS-AT-INGEST (lazy): a cache hit whose record was written by an ingest that ran no construct pass, in an
// ingest that wants the hits. Its facts came from the record; only the hits are missing, so the file is parsed for them
// alone — the tree the cold worker builds before its first use (the .h -> ObjC switch, the .astro frontmatter
// restriction), with no extraction — and the blob is marked dirty so the record is rewritten with them. A file that can
// no longer be read keeps "absent": the ingest then claims no hits, and --quality-delta re-parses (lintrules.h). A hit
// is never a nest-refused file (a refusal is written with an UNKNOWN hash, which never hits), so no refusal check here.
inline void fillAbsentConstructHits( ParsePoolShared& sh, std::size_t fileId, const std::string& path, const LangEntry* le, std::string& bytes,
                                     bool bytesLoaded, TSParser* parser, TSQueryCursor* constructCursor, RawFacts& out )
{
    if( !bytesLoaded && ( !readFile( path, bytes ) || looksBinary( bytes ) ) )
    {
        return;
    }
    if( !bytesLoaded && le->ext == ".h" && looksObjC( bytes ) )
    {
        if( const LangEntry* objcLe = lookupLang( ".m" ) )
        {
            le = objcLe;
        }
    }
    markMissDirty( sh );   // the record is rewritten with its hits (RIPWIRE_CACHE_STATS reparsed= counts this file)
    sh.scan.constructsKnown[ fileId ] = 1;
    if( !prepareParserFor( parser, *le ) )
    {
        return;   // the cold worker parses nothing here either: known, no hits
    }
    IncludedRangeGuard rangeGuard;
    if( restrictAstroToFrontmatter( parser, *le, bytes, rangeGuard ) != AstroFrontmatter::Ok )
    {
        return;   // the cold worker extracts nothing from such an .astro either: known, no hits
    }
    TreeGuard tree( underExtractScope<ExtractPhase::Parse>( le->lang, [ & ] { return parseTree( parser, bytes ); } ) );
    if( tree.get() != nullptr )
    {
        collectConstructHits( *le, static_cast<std::uint32_t>( fileId ), bytes, ts_tree_root_node( tree.get() ), constructCursor, out.constructs );
    }
}

inline void runParseWorker( ParsePoolShared& sh, unsigned t )
{
    IngestFileScan& scan = sh.scan;
    RawFacts&       out  = sh.tFacts[ t ];
    std::size_t     warmGrowths = 0;   // P1-11: thread-local, folded into sh.warmGrowths once at the end (never an atomic in the loop)

    // Neither allocation can come back null: tree-sitter's allocator aborts rather than return null (third_party/deps/tree_sitter/lib/src/alloc.c), and no ripwire code calls ts_set_allocator — so there is no degrade here to disclose.
    ParserGuard pg;
    ASSUME( pg.p != nullptr, "ts_parser_new: the default tree-sitter allocator aborts on failure" );
    TSQueryCursor* cursor = ts_query_cursor_new();
    ASSUME( cursor != nullptr, "ts_query_cursor_new: the default tree-sitter allocator aborts on failure" );
    // QD-CONSTRUCTS-AT-INGEST: its own cursor, never configured, like astQueryGrouped's — the tags cursor above carries
    // whatever the tags capture set on it.
    TSQueryCursor* constructCursor = ts_query_cursor_new();
    ASSUME( constructCursor != nullptr, "ts_query_cursor_new: the default tree-sitter allocator aborts on failure" );

    // B0.2: per-worker subtoken-stats builder — after a file's defs are extracted (and the file's
    // bytes are STILL in memory), tokenize each new def's doc/body spans ONCE into its persisted
    // stats (lexindex.h). Rich ingests only; a def's stats ride the RawDef through dedup/sort/cache
    // so alignment with the eventual Symbol is free. scratch is reused across defs (no rehash churn).
    HashMap<std::uint64_t, std::uint32_t> lexScratch;
    if( sh.captureValueUses )
    {
        lexScratch.reserve( 1024 );
    }
    MemberMacroReparse macroWork;                        // member-macro re-parse (src/macroreparse.h): per-worker scratch
    RecordScratch              record;                   // WARM-DIRECT: one cache record's bytes, dictionary and decoded facts, reused across hits
    macroWork.captureValueUses = sh.captureValueUses;
    // CLONES-PERSIST: every family keys each new Function/Method body for findClones (rawDefCloneKey) from
    // the same in-memory bytes, so the key rides the cache record and a warm clone pass reads no file to group.
    const auto finishNewDefs = [ & ]( std::vector<RawDef>& defs, std::size_t firstNewDefIndex, const std::string& fileBytes )
    {
        for( std::size_t defIndex = firstNewDefIndex; defIndex < defs.size(); ++defIndex )
        {
            RawDef& d  = defs[ defIndex ];
            d.cloneKey = rawDefCloneKey( fileBytes, d );
        }
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
                ExtractShortfall  tagsShortfall;
                underExtractScope<ExtractPhase::TagsFacts>( pending.le->lang, [ & ]
                {
                    captureTagsFacts( cursor, *pending.le, pending.fileId, pending.bytes, root, out.defs, out.refs, out.binds, out.incs, pending.ppDead, tagsShortfall,
                                      TagsCapture::Full, cjsExportStem( pending.le->lang, sh.files[ pending.fileId ] ) );
                } );
                notePartialExtract( scan, pending.fileId, tagsShortfall, pending.bytes.size() );
                finishNewDefs( out.defs, firstNewDefIndex, pending.bytes );   // B0.2: bytes still in memory
                ts_tree_delete( pending.tree );
                pending.tree = nullptr;
            }
        }
        pendingParsed.clear();
        pendingParsedBytes = 0;
    };

    std::string bytes;
    bool        claimedAny = false;   // #350: the file this worker claimed last has finished by the loop's top
    for( ;; )   // lock-free work-stealing: grab the next file via the atomic counter (balances the big-file tail)
    {
        if( sh.prewarm.ready.load( std::memory_order_acquire ) && !pendingParsed.empty() )
        {
            flushPendingParsed();
        }

        // #350: the memory guard. The previous file is done (every path through the body below ends its iteration),
        // so report it; then look at the stop flag BEFORE claiming, which is what keeps the finished set an unbroken
        // prefix of the work order — a file once claimed is always completed.
        if( sh.memWatch != nullptr )
        {
            if( claimedAny )
            {
                sh.memWatch->parseFileDone();
            }
            if( sh.memWatch->isStopped() )
            {
                break;
            }
        }

        const std::size_t orderIndex = sh.nextFile.fetch_add( 1, std::memory_order_relaxed );
        if( orderIndex >= sh.nfiles )
        {
            break;
        }
        // #350, the parse seam (parse:N): the claim of work-order slot N and later is abandoned unparsed and trips the
        // stop, so exactly the first N files of the parse order are parsed (applyMemoryParseCut counts them the same way)
        if( sh.memWatch != nullptr && orderIndex >= sh.memWatch->seamParseCutoff() )
        {
            sh.memWatch->tripParseSeam();
            break;
        }
        claimedAny = true;
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
                const CachedRecordHead* hit = sh.cacheHitFacts[ fileId ];
                if( hit == nullptr )
                {
                    const CachedRecordHead* candidate = sh.cacheCandidateFacts[ fileId ];
                    if( candidate != nullptr && candidate->hash == h )
                    {
                        hit = candidate;
                    }
                }
                if( hit != nullptr )   // unchanged → decode its record straight into this worker's arrays, skip parse
                {
                    if( decodeCachedRecordNoThrow( sh.cache, fileId, path, record ) )
                    {
                        const bool hitsAbsent = record.facts.constructsAbsent;
                        warmGrowths += appendCacheHitFacts( record.facts, std::uint32_t( fileId ), scan, out );
                        if( hitsAbsent && scan.wantConstructHits )
                        {
                            fillAbsentConstructHits( sh, fileId, path, le, bytes, bytesLoaded, pg.p, constructCursor, out );
                        }
                    }
                    else
                    {
                        sh.lateMiss[ fileId ] = 1;   // its grammar may not be compiled: runParsePool parses it after the join
                    }
                    continue;
                }
            }

            // cache miss (new file or hash changed) → need to actually parse. The blob is marked dirty once the
            // outcome is known: below, at the parse, or in noteFactlessMiss for a file that ends before it.

            // ensure bytes are loaded (may have been pre-hashed without loading the body)
            if( !bytesLoaded )
            {
                if( !readFile( path, bytes ) )
                {
                    noteFactlessMiss( sh, fileId, false );
                    continue;
                }
                if( looksBinary( bytes ) )
                {
                    noteFactlessMiss( sh, fileId, false );
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

            // hostile/degenerate nesting guard — MUST run BEFORE the parse (that is the whole point). #157:
            // one call (ingest_prewarm.h refuseNesting), covering json/yaml/markdown/kotlin — json is a
            // performance guard, the other three are MEMORY-SAFETY / PROCESS-SURVIVAL load-bearing (see
            // ingest.h's per-ceiling comments for each defect's arithmetic; the vendored scanner patches
            // under third_party/patches/ are the SECOND, independent layer for those three).
            // Itemized in --skipped (why="nest-refused") for every language now, not just Kotlin.
            // A reST file takes no grammar, so the guard has nothing to protect: ingest_rest.h's scan is flat and bounds itself.
            const std::string restExt = lowerExtensionOf( path );
            const bool        isRest  = docparse::isRestExtension( restExt );
            if( !isRest && refuseNesting( *le, bytes, path.c_str(), fileId, scan ) )
            {
                noteFactlessMiss( sh, fileId, true );
                continue;
            }
            markMissDirty( sh );   // this file's facts are re-extracted below: the blob's record for it is rewritten

            if( isRest )
            {
                const std::string stem             = fs::path( path ).stem().string();
                const std::size_t firstNewDefIndex = out.defs.size();
                ExtractShortfall  restShort;
                extractRest( static_cast<std::uint32_t>( fileId ), bytes, stem, restExt, out.defs, out.refs, restShort );
                finishNewDefs( out.defs, firstNewDefIndex, bytes );
                notePartialExtract( scan, fileId, restShort, bytes.size() );
            }
            else if( isDocLang( le->lang ) )
            {
                if( !prepareParserFor( pg.p, *le ) )
                {
                    continue;
                }
                TreeGuard mdTree( underExtractScope<ExtractPhase::Parse>( le->lang, [ & ] { return parseTree( pg.p, bytes ); } ) );
                if( mdTree.get() == nullptr )
                {
                    continue;
                }
                scan.health[ fileId ] = measureFileHealth( ts_tree_root_node( mdTree.get() ), bytes );
                const std::string stem = fs::path( path ).stem().string();
                const std::size_t firstNewDefIndex = out.defs.size();
                extractMarkdown( static_cast<std::uint32_t>( fileId ), bytes, stem, ts_tree_root_node( mdTree.get() ), out.defs, out.refs );
                finishNewDefs( out.defs, firstNewDefIndex, bytes );   // B0.2: md sections/file nodes get stats too
            }
            else
            {
                if( !prepareParserFor( pg.p, *le ) )
                {
                    continue;
                }

                // .astro: restrict the parse to the `---` frontmatter. The guard lifts the restriction on
                // EVERY exit from this scope, including the queued-tags `continue` below — pg.p is reused.
                IncludedRangeGuard rangeGuard;
                const AstroFrontmatter astro = restrictAstroToFrontmatter( pg.p, *le, bytes, rangeGuard );
                if( astro != AstroFrontmatter::Ok )
                {
                    // A template-only .astro is ordinary and says nothing. An UNTERMINATED fence is a file whose
                    // frontmatter we can see the start of and cannot extract — a silent zero unless disclosed, so
                    // it rides the existing extract-partial channel and lands in --skipped rather than vanishing.
                    if( astro == AstroFrontmatter::Unterminated )
                    {
                        ExtractShortfall astroShort;
                        DISCLOSE( astroShort, ExtractShortfall::DisclosureWhy::AstroFrontmatterUnterminated,
                                  "ingest: an .astro opened a `---` fence and never closed it — frontmatter not extracted (--skipped why=extract-partial)" );
                        notePartialExtract( scan, fileId, astroShort, bytes.size() );
                    }
                    continue;
                }

                TreeGuard tree( underExtractScope<ExtractPhase::Parse>( le->lang, [ & ] { return parseTree( pg.p, bytes ); } ) );
                if( tree.get() == nullptr )
                {
                    continue;
                }
                // QD-CONSTRUCTS-AT-INGEST: from THIS tree, before the member-macro re-parse below can swap it — the tree
                // findQualityConstructs' own parse would build (ingest_astquery.h collectConstructHits says why).
                // Only an ingest that wants them runs the pass (ingest.h WantConstructHits); otherwise the record says absent.
                if( scan.wantConstructHits )
                {
                    collectConstructHits( *le, static_cast<std::uint32_t>( fileId ), bytes, ts_tree_root_node( tree.get() ), constructCursor, out.constructs );
                }
                else
                {
                    scan.constructsKnown[ fileId ] = 0;
                }

                // §L1 — before `bytes` can be moved below. May swap `tree` for the member-macro re-parse (macroreparse.h).
                scan.health[ fileId ] = measureHealthAdoptingMemberMacroReparse( pg.p, le->lang, bytes, tree, macroWork );
                const TSNode root = ts_tree_root_node( tree.get() );
                // #72 follow-up: ONE preprocdead.h walk per file, shared by both capture drivers. It must
                // be taken from the ADOPTED tree (the member-macro re-parse may have swapped it just
                // above), which is why it is computed here and not inside either driver.
                std::vector<PreprocDeadRange> ppDead = preprocDeadRangesFor( *le, root, bytes );
                ExtractShortfall shortfall;   // every pass's disclosure for THIS file; noted on its slot once both have run
                underExtractScope<ExtractPhase::SideFacts>( le->lang, [ & ]
                {
                    captureSideFacts( *le, static_cast<std::uint32_t>( fileId ), bytes, root, out.refs, out.incs, out.binds, out.ffis, out.routeDefs, out.routeUses, out.constOpens, sh.captureValueUses, ppDead, shortfall );
                } );
                notePartialExtract( scan, fileId, shortfall, bytes.size() );   // before a queued file's tags pass, which notes its own
                appendBlankedMacroUses( macroWork, le->lang, static_cast<std::uint32_t>( fileId ), bytes, out.refs, ppDead );

                const bool canQueueParsed = !sh.prewarm.ready.load( std::memory_order_acquire )
                                         && pendingParsed.size() < kMaxPendingParsedFiles
                                         && pendingParsedBytes + bytes.size() <= kMaxPendingParsedBytes;
                if( canQueueParsed )
                {
                    pendingParsedBytes += bytes.size();
                    pendingParsed.emplace_back( static_cast<std::uint32_t>( fileId ), le, std::move( bytes ), tree.release(), std::move( ppDead ) );
                    bytes.clear();   // moved-from is "valid but unspecified": make it empty. Every path refills it (readFile) before a read
                    continue;
                }

                {
                    PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: wait query prewarm" );
                    waitForQueryPrewarm( &sh.gate );
                }
                const std::size_t firstNewDefIndex = out.defs.size();
                underExtractScope<ExtractPhase::TagsFacts>( le->lang, [ & ]
                {
                    captureTagsFacts( cursor, *le, static_cast<std::uint32_t>( fileId ), bytes, root, out.defs, out.refs, out.binds, out.incs, ppDead, shortfall,
                                      TagsCapture::Full, cjsExportStem( le->lang, path ) );
                } );
                notePartialExtract( scan, fileId, shortfall, bytes.size() );
                finishNewDefs( out.defs, firstNewDefIndex, bytes );   // B0.2: bytes still in memory
            }
        }
        catch( ... )
        {
            // the facts gathered before the throw are KEPT, so this is a partial file, not a skipped one
            DISCLOSE( ( FileExtractThrew{ scan, fileId } ), FileExtractThrew::DisclosureWhy::WorkerThrew,
                      "ingest: worker exception on a file — its facts so far are kept and it is marked extract-partial" );
        }
    }
    flushPendingParsed();
    ts_query_cursor_delete( cursor );
    ts_query_cursor_delete( constructCursor );
    sh.warmGrowths.fetch_add( warmGrowths, std::memory_order_relaxed );   // P1-11: one relaxed add per worker, ordered by the pool join
}

// One fact family of the merge: reserve its exact total, move every thread's rows in, and free each thread's array as soon
// as its rows have moved. WARM-DIRECT: the merge used to reserve all eight families up front and free the per-thread
// arrays only after the last one, so the join held two full sets of fact arrays (the merged one and the moved-from
// per-thread ones). Family by family, it holds one set plus the family being moved. The freed arrays are large blocks,
// which src/largealloc.cpp hands back to the OS on macOS.
template <typename Row>
inline void mergeFamily( std::vector<RawFacts>& tFacts, std::vector<Row> RawFacts::*family, std::vector<Row>& dst )
{
    std::size_t total = 0;
    for( const RawFacts& tf : tFacts )
    {
        total += ( tf.*family ).size();
    }
    dst.reserve( total );
    for( RawFacts& tf : tFacts )
    {
        std::vector<Row>& src = tf.*family;
        dst.insert( dst.end(), std::make_move_iterator( src.begin() ), std::make_move_iterator( src.end() ) );
        std::vector<Row>().swap( src );   // the moved-from rows and their array, released now
    }
}

// merge per-thread results into one RawFacts (cross-thread order is irrelevant — everything is
// re-sorted by the model-build tail), one family at a time (mergeFamily).
inline RawFacts mergeThreadFacts( std::vector<RawFacts>& tFacts )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: merge per-thread facts" );
    RawFacts raw;
    mergeFamily( tFacts, &RawFacts::refs, raw.refs );
    mergeFamily( tFacts, &RawFacts::defs, raw.defs );
    mergeFamily( tFacts, &RawFacts::binds, raw.binds );
    mergeFamily( tFacts, &RawFacts::incs, raw.incs );
    mergeFamily( tFacts, &RawFacts::ffis, raw.ffis );
    mergeFamily( tFacts, &RawFacts::routeDefs, raw.routeDefs );
    mergeFamily( tFacts, &RawFacts::routeUses, raw.routeUses );
    mergeFamily( tFacts, &RawFacts::constOpens, raw.constOpens );
    mergeFamily( tFacts, &RawFacts::constructs, raw.constructs );
    return raw;
}

// 2) parse every file IN PARALLEL — one TSParser per worker thread (parsers aren't thread-safe),
//    per-thread raw lists merged after. Determinism is preserved: defs/refs are re-sorted by the
//    model-build tail, so collection order is irrelevant. Also owns the two flags that ride the
//    pool (the Win-2 dirty flag and the A1 reparsed counter), the install/gate-open moment, and
//    the dirty-gated saveCache — everything between the prewarm launch and the doc post-pass.
// WARM-DIRECT: after the pool join, parse the hits whose cached record failed in a worker (CacheRecords::decode: a short
// read, a torn record, a corrupt body, a key that moved). The prewarm counted them as hits, so their grammar may not be
// compiled; the pool is joined, so installing it here is the single-writer moment compiledQueryCache() needs. They run
// on this thread, through the worker body itself (slot 0's accumulators), as ordinary misses: their scan hash is
// cleared so the file is read and hashed again, and the blob is dirtied so the record is rewritten. Unguarded by the
// memory watch: these files were claimed by the parse already, and leaving them empty would be a silent hole.
inline std::size_t parseLateMisses( const ParsePoolShared& pool, std::vector<const CachedRecordHead*>& candidates,
                                    std::vector<const CachedRecordHead*>& hits, const std::vector<std::uint8_t>& lateMiss )
{
    std::vector<std::size_t> late;
    for( std::size_t fileId = 0; fileId < lateMiss.size(); ++fileId )
    {
        if( lateMiss[ fileId ] != 0 )
        {
            late.push_back( fileId );
        }
    }
    if( late.empty() )
    {
        return 0;
    }
    PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: late misses (cached record failed)" );
    std::vector<const LangEntry*> grammars;
    for( const std::size_t fileId : late )
    {
        candidates[ fileId ]     = nullptr;
        hits[ fileId ]           = nullptr;
        pool.scan.hash[ fileId ] = 0;
        if( const LangEntry* le = pool.scan.lang[ fileId ] )
        {
            grammars.push_back( le );
            if( le->ext == ".h" )
            {
                if( const LangEntry* objcLe = lookupLang( ".m" ) )
                {
                    grammars.push_back( objcLe );   // the worker's content sniff may reroute the header
                }
            }
        }
    }
    installLateQueries( grammars );
    std::atomic<std::size_t>  next{ 0 };
    std::vector<std::uint8_t> noLateMiss;   // never written: no file of this pass is a hit
    ParsePoolShared           shared{ pool.files, pool.cache, pool.scan, pool.prewarm, pool.gate, candidates, hits, noLateMiss,
                                      pool.tFacts, late, next, pool.dirty, pool.reparsedCount, pool.warmGrowths, late.size(),
                                      pool.needsCacheHash, pool.captureValueUses, nullptr };
    runParseWorker( shared, 0 );
    return late.size();
}

// #350: after the pool join, a memory-guard stop while files remained. Workers look at the stop flag BEFORE claiming a
// file, so every claimed file completed and the parsed set is the first K entries of the parse ORDER (cache misses,
// then cache hits, then grammarless files, each largest first, then fileId — or plain fileId order when the query
// prewarm was already ready, i.e. no grammar-bearing file needed a fresh parse (every one an ingest-cache hit, so the
// prewarm had nothing to compile: ingest_prewarm.h builds toCompile from cache-miss files only); deterministic
// for a given tree and cache), which is what memory_parsed=K counts (claimed slots: one may reuse cached facts or fail
// to read); a partial answer therefore repeats for a given K. Under the parse seam an abandoned claim at slot N or later
// is not a parse, hence the min with the seam's cutoff. A stop after the last claim cut nothing. Returns whether cut.
inline bool applyMemoryParseCut( IngestResult& result, memguard::Watch* memWatch, std::size_t claimedSlots, std::size_t nfiles )
{
    const std::size_t parsed = std::min( { claimedSlots, nfiles, memWatch != nullptr ? memWatch->seamParseCutoff() : nfiles } );
    if( memWatch == nullptr || !memWatch->tripped() || parsed >= nfiles )
    {
        return false;
    }
    result.memoryStop.limitBytes  = memWatch->hardBytes();
    result.memoryStop.parsedFiles = static_cast<std::uint32_t>( parsed );
    if( memWatch->trippedByPressure() )
    {
        DISCLOSE( result.memoryStop, MemoryStop::DisclosureWhy::ParseUnderPressure, "ingest: the memory guard stopped the parse pool — the files after the parsed prefix of the parse order carry no facts" );
    }
    else
    {
        DISCLOSE( result.memoryStop, MemoryStop::DisclosureWhy::ParseOverLimit, "ingest: the memory guard stopped the parse pool — the files after the parsed prefix of the parse order carry no facts" );
    }
    return true;
}

inline RawFacts runParsePool( IngestResult& result, const char* rootDir, std::string_view cacheFile, bool captureValueUses,
                              CacheRecords& cache, const CacheLoadStats& cacheStats,
                              IngestFileScan& scan, QueryPrewarm& prewarm, memguard::Watch* memWatch = nullptr )
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

    // P1-11: how many times a warm-hit append had to reallocate its accumulator. Zero is the contract on a
    // fully warm single-threaded run; a non-zero number on a multi-threaded one is the work-queue's own
    // skew (a worker that draws more than its 1/nthreads share), not a missing reserve. Reported only under
    // RIPWIRE_CACHE_STATS, like reparsed=/cached_records= beside it.
    std::atomic<std::size_t> warmGrowths{ 0 };

    const std::size_t nfiles = result.files.size();
    if( nfiles )
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: parse pool (tree-sitter, parallel)" );
        // scan.hash is already pre-sized to nfiles (done by makeFileScan, before the prewarm).
        // Entries pre-filled by the prewarm miss-detection pass (cache-present files that were read+hashed
        // there) stay as-is. Workers fill the remaining 0-valued entries for files they process.
        ASSUME( scan.hash.size() == nfiles );
        unsigned hw = std::thread::hardware_concurrency();
        if( hw == 0 )
        {
            hw = 1;
        }
        const unsigned nthreads = static_cast<unsigned>( std::min<std::size_t>( hw, nfiles ) );

        std::vector<RawFacts>   tFacts( nthreads );
        std::vector<const CachedRecordHead*> cacheCandidateFacts( nfiles, nullptr );
        std::vector<const CachedRecordHead*> cacheHitFacts( nfiles, nullptr );
        std::vector<std::uint8_t>            lateMiss( nfiles, 0 );   // WARM-DIRECT: hits whose record failed in a worker

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

            reserveWarmFamilies( tFacts, markCacheHits( cache, scan, cacheCandidateFacts, cacheHitFacts ), nthreads );
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

        ParsePoolShared shared{ result.files, cache, scan, prewarm, queryReadyGate, cacheCandidateFacts, cacheHitFacts, lateMiss,
                                tFacts, parseOrder, nextFile, dirty, reparsedCount, warmGrowths, nfiles, needsCacheHash, captureValueUses,
                                memWatch };

        for( unsigned t = 0; t < nthreads; ++t )
        {
            pool.emplace_back( [ &shared, t ]() noexcept { runParseWorker( shared, t ); } );
        }

        installCompiledQueriesAndOpenGate( prewarm );   // join async compiles, publish, open the gate (ingest_prewarm.h)

        {
            PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: workers run + join" );
        for( std::thread& th : pool )
        {
            th.join();
        }
        }

        // WARM-DIRECT: a hit whose record failed in the worker (read, checksum, decode, key) is parsed now, with its
        // grammar installed, so the answer is the cold one. Then the blob closes and its per-file table is freed.
        const std::size_t lateMisses = parseLateMisses( shared, cacheCandidateFacts, cacheHitFacts, lateMiss );
        cache.release();

        raw = mergeThreadFacts( tFacts );

        const bool parseCut = applyMemoryParseCut( result, memWatch, nextFile.load( std::memory_order_relaxed ), nfiles );   // #350

        // The aggregate owns the moved fact payloads now. Release the per-thread vector storage before the
        // cache write and before returning to the model-build tail; keeping these empty-but-capacious vectors
        // alive needlessly raises the cold-run peak on large trees.
        std::vector<RawFacts>().swap( tFacts );
        memstats::mark( "pool-join" );   // M0 MEM-STATS: the merged families, per-thread storage released (src/memstats.h)

        // P1-15: the SAME drift count, carried out of the function instead of only to stderr. The MCP
        // server discloses it per incremental pass (`_reingest`), which it could not do from an env-gated
        // print. Read once here, after the pool join that orders every worker's increment.
        result.reparsedFiles = reparsedCount.load( std::memory_order_relaxed );

        // A1 (team-index) — drift-proportional observable: report how many files re-parsed vs reused,
        // ONLY when RIPWIRE_CACHE_STATS is set (off by default → no stdout/stderr perturbation on any
        // normal run or gate). A warm restore over a tree with N-of-F files changed prints reparsed=N,
        // making the "restore cost is proportional to drift, not tree size" claim executable.
        // v15 adds the two OFFSET-TABLE observables next to them, and they are the ones that make "a
        // subset configuration reads only its own records" an executable fact rather than a wall-clock
        // claim: blob_entries is how many files the shared superset blob holds, cached_records is how
        // many of them this configuration actually deserialised (test/cacheoffsetcheck.sh band (2)).
        if( std::getenv( "RIPWIRE_CACHE_STATS" ) != nullptr )
        {
            const std::size_t reparsed = reparsedCount.load( std::memory_order_relaxed );
            rw::emitTo( stderr, "ripwire: cache-stats reparsed={} reused={} files={} cached_records={} blob_entries={} warm_growths={}\n",
                          reparsed, ( nfiles >= reparsed ? nfiles - reparsed : std::size_t( 0 ) ), nfiles,
                          cacheStats.recordsRead - std::min( lateMisses, cacheStats.recordsRead ), cacheStats.blobEntries,
                          warmGrowths.load( std::memory_order_relaxed ) );
        }

        // Win 2: rewrite cache only when at least one file changed (dirty flag set by workers above).
        // Skips the ~11ms / 7 MB serialization+write on a no-change warm run.
        if( parseCut && !cacheFile.empty() && dirty.load() )
        {
            DISCLOSE( Diagnostics::answerUnchanged, "ingest: a memory-guard partial parse is not written to the cache — the next run re-parses instead of serving the gap as empty files" );
        }
        if( !parseCut && !cacheFile.empty() && dirty.load() )
        {
            forgetNestRefusalsForCache( scan );   // a refused file is written UNKNOWN, so a warm run re-refuses it (ingest_prewarm.h)
            saveCache( std::string( cacheFile ), rootDir, result.files, scan.hash, scan.statSize, scan.statMtime, scan.statCtime, scan.health, raw.defs, raw.refs, raw.incs, raw.binds, raw.ffis, raw.routeDefs, raw.routeUses, raw.constOpens, raw.constructs, scan.constructsKnown, captureValueUses );
            memstats::mark( "save-cache" );   // M0: peak_mib holds the cache blob's own peak (card C1)
        }
    }
    return raw;
}

}   // namespace

}   // namespace rw
