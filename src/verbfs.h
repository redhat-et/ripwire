#pragma once
// verbfs.h — VERB-FS: the file-system work a served run repeated on every call, kept per index (lane 5b, 2026-11-25).
//
// WHY. A served warm --for on llvm-project took 5.54 s of wall with sys 19.9 s against user 4.1 s (A1, main fec2ab27c).
// Three passes inside runForLensPass re-read the disk on every call, though the index they answer for had not moved:
//   (1) the literal scan (search.h grepCollectEach) read every indexed file to look for the task's literals;
//   (2) the exact clone pass (clones.h findClones) re-read every file holding a shared clone key to verify the groups;
//   (3) the manifest probe (formanifest.h) symlink_status'd three unindexed manifest names in every directory.
// Each now consults a record in the per-user cache directory, `ripwire-verbfs-<part>-<rootKey>.bin`, and does the old
// work only for what the record cannot vouch for. Every answer is byte-identical to the pass it replaces, because the
// record is only ever used where it PROVES the pass would have found what it says.
//
// THE ONE IDENTITY RULE, shared by all three parts and by the parse cache's stat gate (ingest_prewarm.h): a stored fact
// about a file system object is current while the object's stat signature (device, inode, size, mtime, ctime —
// warmsnap::StatSig) is unchanged, and a signature is only recorded once it is SETTLED: mtime and ctime both older than
// two seconds before the pass that observed it began (warmsnap::kRacySlackNs, the racy rule). Why that is enough: a pass
// starts at S, reads at R >= S, and stats at A >= R. If the signature at A is settled, no write touched the object after
// S - 2 s (a write moves ctime to its own time, and no filesystem in use keeps a coarser granule than 2 s), so the bytes
// or entries read at R are the ones that signature names. A later run that sees the same signature sees the same object:
// ctime cannot be set back by an unprivileged writer (`touch -r` and `cp -p` restore mtime and move ctime), and a
// replaced object carries another inode. What is outside it is what is outside the parse cache's gate too: a clock moved
// backward, raw block-device writes, a filesystem with no distinct ctime.
//
// THE THREE PARTS.
//   (1) GREP. Per indexed file: its root-relative path, its signature, and a Bloom filter of the file's distinct byte
//       TRIGRAMS (kTrigramBitsPerEntry bits per trigram, kTrigramProbes probes each, sized to the file). The scan is a
//       case-sensitive byte substring search (search.h grepScanText: std::string::find), so a pattern P of 3 or more bytes
//       that occurs in a file has every trigram of P among the file's trigrams; a filter answering "absent" for any one
//       of them proves P has no site in the file (a Bloom filter has false positives, never a false negative), and a
//       word-bounded scan keeps a subset of those sites, so it has none either. That holds for any bytes — case, spaces,
//       punctuation, non-ASCII, a newline — because the trigrams ARE the bytes. A file is skipped only when that proof
//       holds for EVERY pattern of the scan and its signature still matches; anything else is read, as before. Patterns
//       shorter than 3 bytes (no trigram) and --regex scans take the full scan for the whole call (why=short / why=regex
//       on the stats line, never in the answer). Off-index files: grepCollectEach reads none (the unsupported-extension
//       pass, grepCollectAux, has its own population and is not filtered). A file the scan reads without a usable filter
//       gets one, from the bytes it just read, once its signature is settled.
//   (2) CLONES. Per (minTokens, input digest): the groups findClones returned, and every file the computation read with
//       its settled signature. The digest covers every input the pass takes from the model (clones.h cloneInputDigest:
//       each candidate body's id, line, span, comment rule and stored key, each holding file's path, the threshold); the
//       files cover every byte it took from the disk. Equal digest and equal signatures = the same computation on the
//       same inputs, so the same groups. Anything else recomputes, exactly as before, and offers its result.
//   (3) DIRS. Per probed directory (root-relative): its own lstat signature and the kind of each unindexed manifest name
//       in it. A name cannot appear, vanish, or change between a regular file, a directory and a link without an entry
//       of its directory being created, removed or renamed, and each of those moves the directory's mtime and ctime
//       (POSIX: open(O_CREAT), unlink, rename, symlink, mkdir all mark the parent). A replaced ancestor shows as another
//       inode. A LINK is never stored: its target can change without its directory noticing, so it is always probed live.
//       The manifest's CONTENT is never stored either: a regular file is read as before.
//
// WHERE IT LIVES, AND WHY NOT IN THE WARM SNAPSHOT. The snapshot (warmsnap.h) is written before the verbs run (main.cpp
// finishWarmSnapshot), and it is read whole and checksummed on EVERY warm run, the flagless map included. On llvm the grep
// filters alone are ~60 MB beside a 1.0 GB snapshot: a section would tax the map for a --for-only lookup. So each part is
// its own file, read only by the verb that needs it, and validated per entry rather than by the snapshot's tree key —
// which also means a single edited file costs one file's re-read, not the whole record.
//
// ARMED only for the primary ingest of a cached single-root run (ingest() arms it exactly where it arms the warm snapshot,
// so --no-cache, multi-root, --scip, --pin-census, --max-memory and RIPWIRE_NO_WARMSNAP runs never touch a record), and
// only for an IngestResult of that same root. RIPWIRE_NO_VERBFS=1 is the kill switch: no record is read or written.
//
// FORMAT. A 40-byte header — magic, kVersion, the part, a layout key, the payload's length, the payload's digest — then
// the payload. Any mismatch refuses the whole file (why= on the stats line) and the run does the old work, then writes a
// fresh record. An old, foreign or damaged record is never misread.
//
// STATS (RIPWIRE_STATS=1, stderr only): one `[verbfs] <part> …` line per use. `files=`/`opened=`/`skipped=` on the grep line
// are counts of this call, not estimates.

#include "verbfs_seam.h"
#include "clones.h"            // CloneGroup — the stored groups are the pass's own type
#include "buildkey.h"          // kBuildKey — the compilation that wrote a record, in the layout key
#include "warmsnap.h"          // StatSig / statSig, Out / In, writePaths / readPaths, parallelFor, kRacySlackNs — reused, not re-rolled
#include "quality.h"           // cacheDirLadder / resolveCacheBlobPath / atomicWriteFile — the cache directory every family shares
#include "pathguard.h"         // readRegularFileNoFollow — a record is read only as a regular file, never through a link
#include "memstats.h"          // memstats::enabled — the RIPWIRE_STATS gate
#include "model.h"
#include "infra/depwatch.h"    // digest64 — the payload checksum and the path digests
#include "infra/Diagnostics.h"
#include "infra/emit.h"
#include "infra/hashutil.h"    // hashMix — the trigram probes
#include "infra/statclock.h"   // saturatingNanoseconds — now, in the units st_mtime and st_ctime are read in

#include <algorithm>
#include <atomic>
#include <ctime>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <format>
#include <memory>
#include <mutex>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw::verbfs
{

// ── the record file ─────────────────────────────────────────────────────────────────────────────────────────────────
inline constexpr std::uint64_t kMagic       = 0x0001'5346'4256'5752ull;   // "RWVBFS\x01\0", little-endian
inline constexpr std::uint32_t kVersion     = 1;                          // bump on ANY payload layout change of any part
inline constexpr std::size_t   kHeaderBytes = 40;

enum class Part : std::uint32_t
{
    Grep   = 1,
    Clones = 2,
    Dirs   = 3,
};
inline constexpr std::string_view kPartNames[] = { "", "grep", "clones", "dirs", "regindex", "slotjoin" };   // SLOTREG-PERSIST registers its two parts here (src/verbfs_slotreg.h finds them by name)

// Why a record was not used: one word on the stats line.
enum class Why : std::uint8_t
{
    Ok,
    Absent,
    Version,
    Shape,
    Checksum,
    Count
};
inline constexpr const char* kWhyNames[] = { "ok", "absent", "version", "shape", "checksum" };
static_assert( std::size( kWhyNames ) == std::size_t( Why::Count ), "every Why needs its name on the stats line" );

// The trigram filter's shape: part of the layout key, so a record built with other constants is refused, never misread.
inline constexpr std::uint32_t kTrigramBitsPerEntry = 6;   // bits per distinct trigram: ~6 % false positives per absent trigram at 3 probes
inline constexpr std::uint32_t kTrigramProbes       = 3;

inline std::uint64_t layoutKey()
{
    // producer: the sources that wrote the record, as warmsnap keys its own (quality::producerIdentityHash). A stored clone group
    // or manifest kind is the OUTPUT of this build's code, so another build's record is refused, never served as current.
    // build: which COMPILATION of those sources (buildkey.h kBuildKey), as warmsnap's own layoutKey folds it: a dev and a
    // Release build of one tree share the producer, and neither serves the other's record (refused as why=shape).
    return depwatch::digest64( std::format( "verbfs statsig={} little={} tri_bits={} tri_probes={} float={} producer={} build={}", sizeof( warmsnap::StatSig ),
                                            std::endian::native == std::endian::little ? 1 : 0, kTrigramBitsPerEntry, kTrigramProbes, sizeof( float ),
                                            quality::producerIdentityHash(), depwatch::digest64( kBuildKey ) ) );
}

// ── arming ──────────────────────────────────────────────────────────────────────────────────────────────────────────
struct ArmedRoot
{
    std::string rootDir;   // the root as the primary ingest was given it: ing.crawlRoot of every IngestResult of that root
    std::string rootKey;   // quality::cacheRootKeyHex( rootDir ): the field the cache-dir sweep pins a root's family by
    bool        on = false;
};

inline ArmedRoot& armedRoot() noexcept
{
    static ArmedRoot root;
    return root;
}

inline bool killSwitchOn() noexcept
{
    return std::getenv( "RIPWIRE_NO_VERBFS" ) != nullptr;
}

// The armed root when `ing` is an index of it (single-root, same root spelling), else null.
inline const ArmedRoot* armedFor( const IngestResult& ing ) noexcept
{
    const ArmedRoot& a = armedRoot();
    return a.on && ing.realPaths.empty() && !ing.crawlRoot.empty() && ing.crawlRoot == a.rootDir ? &a : nullptr;
}

// `ripwire-verbfs-<rootKey>-<part>-<hex>.bin` through the family-path helper every root-keyed cache shares: the root key is the
// first 16-hex field, so the cache-dir sweep pins a root's records with its blobs.
inline std::string recordPath( Part part, std::string_view rootKey )
{
    return quality::shaKeyedCachePath( "verbfs", std::string( rootKey ), std::string( kPartNames[ std::size_t( part ) ] ), "" );
}

struct RecordFile
{
    std::string bytes;
    Why         why = Why::Absent;
    std::string_view payload() const noexcept { return std::string_view( bytes ).substr( std::min( bytes.size(), kHeaderBytes ) ); }
};

inline RecordFile readRecord( Part part, std::string_view rootKey )
{
    RecordFile                 out;
    std::optional<std::string> file = pathguard::readRegularFileNoFollow( recordPath( part, rootKey ) );
    if( !file )
    {
        return out;   // Absent: the ordinary first run
    }
    out.bytes = std::move( *file );
    warmsnap::In        in{ std::string_view( out.bytes ) };
    const std::uint64_t magic   = in.u64();
    const std::uint32_t version = in.u32();
    const std::uint32_t partNo  = in.u32();
    const std::uint64_t layout  = in.u64();
    const std::uint64_t length  = in.u64();
    const std::uint64_t sum     = in.u64();
    if( !VALIDATE( in.ok && magic == kMagic, "verbfs: not a record file" ) )
    {
        out.why = Why::Shape;
    }
    else if( !VALIDATE( version == kVersion, "verbfs: a record of another format version" ) )
    {
        out.why = Why::Version;
    }
    else if( !VALIDATE( partNo == std::uint32_t( part ) && layout == layoutKey(), "verbfs: a record of another part or layout" ) )
    {
        out.why = Why::Shape;
    }
    else if( !VALIDATE( length == out.bytes.size() - kHeaderBytes && depwatch::digest64( out.payload() ) == sum, "verbfs: a record whose checksum fails" ) )
    {
        out.why = Why::Checksum;
    }
    else
    {
        out.why = Why::Ok;
        return out;
    }
    DISCLOSE( Diagnostics::answerUnchanged, "a VERB-FS record that is refused is not read: the pass does its full work, and the run writes a fresh record" );
    out.bytes.clear();
    return out;
}

// A payload is written behind a header placeholder, then the header is patched in place: no copy of a ~60 MB payload.
inline warmsnap::Out beginRecord()
{
    warmsnap::Out o;
    o.bytes.assign( kHeaderBytes, '\0' );
    return o;
}

inline bool commitRecord( Part part, std::string_view rootKey, warmsnap::Out& o )
{
    EXPECTS( o.bytes.size() >= kHeaderBytes, "the payload was written behind beginRecord's header" );
    const std::string_view payload = std::string_view( o.bytes ).substr( kHeaderBytes );
    warmsnap::Out          head;
    head.u64( kMagic );
    head.u32( kVersion );
    head.u32( std::uint32_t( part ) );
    head.u64( layoutKey() );
    head.u64( payload.size() );
    head.u64( depwatch::digest64( payload ) );
    ENSURES( head.bytes.size() == kHeaderBytes, "the header is the fixed 40 bytes readRecord takes" );
    std::memcpy( o.bytes.data(), head.bytes.data(), kHeaderBytes );
    if( !quality::atomicWriteFile( recordPath( part, rootKey ), o.bytes ) )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "this run's answer is already computed; only the next run's VERB-FS record is not there, and it does the full pass" );
        return false;
    }
    return true;
}

// Wall-clock now as a file timestamp is spelled: ns since the Unix epoch through the same saturating conversion st_mtim takes.
inline long long nowNs() noexcept
{
    std::timespec now{};
    return std::timespec_get( &now, TIME_UTC ) == TIME_UTC ? saturatingNanoseconds( now ) : 0;   // 0: every signature reads young, nothing is stored
}

// The settle rule (see the note at the top): the signature names the bytes a pass that began at `startNs` read.
inline bool settled( const warmsnap::StatSig& sig, long long startNs ) noexcept
{
    const long long from = startNs - warmsnap::kRacySlackNs;
    return sig.size >= 0 && sig.mtimeNs < from && sig.ctimeNs < from;
}

// A record is rewritten when this call learned at least 1/32 of what it covers: an edit loop re-reads its few edited files
// live (cheap and exact) instead of rewriting a corpus-sized record on every call.
inline bool worthWriting( std::size_t learned, std::size_t covered ) noexcept
{
    return learned > 0 && learned * 32 >= covered;
}

// The fault switches of the mutation arms (test/verbfscheck.sh; constexpr false under NDEBUG).
struct FaultGrepSkipAll;
struct FaultGrepNoStat;
struct FaultCloneAnyDigest;
struct FaultDirsNoStat;
struct FaultDirsLinks;
inline const char* grepFaultName() noexcept
{
    return rw::faultSwitchOnOnce<FaultGrepSkipAll>( "RIPWIRE_FAULT_VERBFS_GREP_SKIPALL" ) ? "skipall"
         : rw::faultSwitchOnOnce<FaultGrepNoStat>( "RIPWIRE_FAULT_VERBFS_GREP_NOSTAT" )   ? "nostat"
                                                                                           : nullptr;
}

// The record a part was loaded with, once per process: the file is read on first use and the in-memory copy is replaced
// when this process writes a newer one. Shared, not copied, by the passes that use it.
template<class Rec>
struct LoadedRecord
{
    std::mutex                 guard;
    bool                       loaded = false;
    Why                        why    = Why::Absent;
    std::shared_ptr<const Rec> record;
};

template<class Rec, class Parse>
inline std::shared_ptr<const Rec> loadOnce( LoadedRecord<Rec>& slot, Part part, std::string_view rootKey, Parse&& parse, Why& why )
{
    const std::lock_guard<std::mutex> hold( slot.guard );
    if( !slot.loaded )
    {
        slot.loaded           = true;
        const RecordFile file = readRecord( part, rootKey );
        slot.why              = file.why;
        if( file.why == Why::Ok )
        {
            auto rec = std::make_shared<Rec>();
            if( parse( file.payload(), *rec ) )
            {
                slot.record = std::move( rec );
            }
            else
            {
                DISCLOSE( Diagnostics::answerUnchanged, "a VERB-FS record whose payload does not parse is not read: the pass does its full work" );
                slot.why = Why::Shape;
            }
        }
    }
    why = slot.why;
    return slot.record;
}

template<class Rec>
inline void replaceLoaded( LoadedRecord<Rec>& slot, std::shared_ptr<const Rec> rec )
{
    const std::lock_guard<std::mutex> hold( slot.guard );
    slot.loaded = true;
    slot.why    = Why::Ok;
    slot.record = std::move( rec );
}

// ═══ (1) GREP ════════════════════════════════════════════════════════════════════════════════════════════════════════
inline constexpr std::uint32_t kNoFilter = 0xFFFF'FFFFu;   // an entry's bit count when no filter is stored for it

// The probe slices of one trigram: kTrigramProbes 32-bit values, each mapped onto a filter by multiply-shift.
struct TrigramProbe
{
    std::uint32_t slice[ kTrigramProbes ];
};

inline TrigramProbe trigramProbe( std::uint32_t trigram ) noexcept
{
    const std::uint64_t h  = hashutil::hashMix( trigram );
    const std::uint64_t h2 = hashutil::hashMix( h ^ 0x9e37'79b9'7f4a'7c15ull );
    return { { std::uint32_t( h & 0xFFFF'FFFFu ), std::uint32_t( h >> 32 ), std::uint32_t( h2 & 0xFFFF'FFFFu ) } };
}

// slice < 2^32 and bitCount < 2^32: the product fits 64 bits, the result is in [0, bitCount)
inline std::uint64_t filterBitOf( std::uint32_t slice, std::uint32_t bitCount ) noexcept
{
    return ( std::uint64_t( slice ) * std::uint64_t( bitCount ) ) >> 32;
}

inline std::uint32_t trigramAt( std::string_view s, std::size_t i ) noexcept
{
    return ( std::uint32_t( hashutil::toByte( s[ i ] ) ) << 16 ) | ( std::uint32_t( hashutil::toByte( s[ i + 1 ] ) ) << 8 ) | std::uint32_t( hashutil::toByte( s[ i + 2 ] ) );
}

// The distinct trigrams of a pattern, as probes. Empty for a pattern shorter than 3 bytes (it has none).
inline std::vector<TrigramProbe> patternProbes( std::string_view pat )
{
    std::vector<std::uint32_t> tris;
    for( std::size_t i = 0; i + 2 < pat.size(); ++i )
    {
        tris.push_back( trigramAt( pat, i ) );
    }
    sortutil::sortUnique( tris );
    std::vector<TrigramProbe> probes;
    probes.reserve( tris.size() );
    for( const std::uint32_t t : tris )
    {
        probes.push_back( trigramProbe( t ) );
    }
    return probes;
}

// Can a pattern with these probes occur in the file whose filter is words[0 .. bitCount/64)? false PROVES it cannot.
inline bool filterMayHold( const std::uint64_t* words, std::uint32_t bitCount, std::span<const TrigramProbe> probes ) noexcept
{
    EXPECTS( !probes.empty(), "only a pattern with a trigram is filtered" );
    if( bitCount == 0 )
    {
        return false;   // the file holds no trigram at all (fewer than 3 bytes): no pattern of 3 or more bytes occurs in it
    }
    for( const TrigramProbe& probe : probes )
    {
        for( const std::uint32_t slice : probe.slice )
        {
            const std::uint64_t bit = filterBitOf( slice, bitCount );
            if( ( ( words[ bit >> 6 ] >> ( bit & 63 ) ) & 1u ) == 0 )
            {
                return false;
            }
        }
    }
    return true;
}

// Per-thread scratch for building filters: a 2^24-bit "seen" map (2 MiB, allocated on first use) and the distinct list.
class TrigramScratch
{
public:
    // The filter of `bytes` into `words`; returns its bit count (kTrigramBitsPerEntry per distinct trigram, whole words; 0: no trigram).
    std::uint32_t build( std::string_view bytes, std::vector<std::uint64_t>& words )
    {
        if( seen_.empty() )
        {
            seen_.assign( std::size_t( 1 ) << 18, 0 );
        }
        distinct_.clear();
        for( std::size_t i = 0; i + 2 < bytes.size(); ++i )
        {
            const std::uint32_t t   = trigramAt( bytes, i );
            std::uint64_t&      w   = seen_[ t >> 6 ];
            const std::uint64_t bit = std::uint64_t( 1 ) << ( t & 63 );
            if( ( w & bit ) == 0 )
            {
                w |= bit;
                distinct_.push_back( t );
            }
        }
        for( const std::uint32_t t : distinct_ )
        {
            seen_[ t >> 6 ] = 0;   // every set bit of that word is some distinct_ entry's: the map is clean again
        }
        words.clear();
        if( distinct_.empty() )
        {
            return 0;
        }
        ASSUME( distinct_.size() <= ( std::size_t( 1 ) << 24 ), "a trigram is 24 bits: at most 2^24 distinct" );
        const std::uint64_t bits64   = ( std::uint64_t( distinct_.size() ) * kTrigramBitsPerEntry + 63 ) / 64 * 64;
        const std::uint32_t bitCount = std::uint32_t( bits64 );   // <= 6 * 2^24 + 63 < 2^32
        words.assign( bitCount / 64, 0 );
        for( const std::uint32_t t : distinct_ )
        {
            const TrigramProbe probe = trigramProbe( t );
            for( const std::uint32_t slice : probe.slice )
            {
                const std::uint64_t bit = filterBitOf( slice, bitCount );
                words[ bit >> 6 ] |= std::uint64_t( 1 ) << ( bit & 63 );
            }
        }
        return bitCount;
    }

private:
    std::vector<std::uint64_t> seen_;
    std::vector<std::uint32_t> distinct_;
};

// The grep record: one entry per file of the index that wrote it, in that index's file order.
struct GrepRecord
{
    std::vector<std::string>        rel;      // root-relative path
    std::vector<warmsnap::StatSig>  sig;      // the settled signature the filter was built under
    std::vector<std::uint32_t>      bits;     // the filter's bit count; kNoFilter: none stored
    std::vector<std::uint64_t>      wordAt;   // the filter's first word in `words`
    std::vector<std::uint64_t>      words;
};

inline void writeGrepRecord( warmsnap::Out& o, const GrepRecord& r )
{
    warmsnap::writePaths( o, r.rel.size(), [ & ]( std::size_t i ) -> std::string_view { return r.rel[ i ]; } );
    o.vec( r.sig );
    o.vec( r.bits );
    o.vec( r.wordAt );
    o.vec( r.words );
}

inline bool readGrepRecord( std::string_view payload, GrepRecord& r )
{
    warmsnap::In in{ payload };
    warmsnap::readPaths( in, r.rel );
    in.vec( r.sig );
    in.vec( r.bits );
    in.vec( r.wordAt );
    in.vec( r.words );
    const std::size_t n = r.rel.size();
    if( !VALIDATE( in.ok && in.left() == 0 && r.sig.size() == n && r.bits.size() == n && r.wordAt.size() == n, "verbfs: the grep record's arrays disagree" ) )
    {
        return false;
    }
    for( std::size_t e = 0; e < n; ++e )
    {
        if( r.bits[ e ] == kNoFilter )
        {
            continue;
        }
        const std::uint64_t wordCount = r.bits[ e ] / 64;
        if( !VALIDATE( r.bits[ e ] % 64 == 0 && r.wordAt[ e ] <= r.words.size() && wordCount <= r.words.size() - r.wordAt[ e ], "verbfs: a grep filter lies outside its record" ) )
        {
            return false;
        }
    }
    return true;
}

inline LoadedRecord<GrepRecord>& grepLoaded() noexcept
{
    static LoadedRecord<GrepRecord> slot;
    return slot;
}

class RecordedGrepSieve final : public GrepSieve
{
public:
    RecordedGrepSieve( const IngestResult& ing, const ArmedRoot& armed, std::span<const std::string> pats, bool regex, bool noPrefilter )
        : ing_( ing ), armed_( armed ), startNs_( nowNs() ), fault_( grepFaultName() )
    {
        const std::size_t files = ing.files.size();
        record_                 = loadOnce( grepLoaded(), Part::Grep, armed.rootKey, readGrepRecord, recordWhy_ );
        entryOf_.assign( files, UINT32_MAX );
        stale_.assign( files, 0 );
        fresh_.resize( files );
        if( record_ != nullptr )
        {
            mapEntries();
        }
        // which pre-filter this scan gets: none for a --regex (its own trigram query lives in search.h), the oracle, or a pattern
        // with no trigram; else the record's, when there is one
        off_ = regex ? "regex" : noPrefilter ? "noprefilter" : nullptr;
        for( std::size_t k = 0; off_ == nullptr && k < pats.size(); ++k )
        {
            if( pats[ k ].size() < 3 )
            {
                off_ = "short";
            }
        }
        if( off_ == nullptr && record_ == nullptr )
        {
            off_ = kWhyNames[ std::size_t( recordWhy_ ) ];
        }
        if( off_ == nullptr )
        {
            probes_.reserve( pats.size() );
            for( const std::string& p : pats )
            {
                probes_.push_back( patternProbes( p ) );
            }
        }
    }

    bool skip( std::uint32_t f ) noexcept override
    {
        if( off_ != nullptr || f >= entryOf_.size() || entryOf_[ f ] == UINT32_MAX )
        {
            return false;
        }
        const std::uint32_t e    = entryOf_[ f ];
        const std::uint32_t bits = record_->bits[ e ];
        if( bits == kNoFilter )
        {
            return false;
        }
        if( fault_ == nullptr || std::string_view( fault_ ) != "skipall" )
        {
            const std::uint64_t* words = record_->words.data() + record_->wordAt[ e ];
            for( const std::vector<TrigramProbe>& probes : probes_ )
            {
                if( filterMayHold( words, bits, probes ) )
                {
                    return false;   // this pattern may have a site here: the file is read
                }
            }
            // no pattern can occur in the file the filter describes: is it still that file?
            if( fault_ == nullptr && !( warmsnap::statSig( diskPath( ing_, f ).c_str(), true ) == record_->sig[ e ] ) )
            {
                stale_[ f ] = 1;
                return false;
            }
        }
        skipped_.fetch_add( 1, std::memory_order_relaxed );
        return true;
    }

    void noteRead( std::uint32_t f, const std::optional<std::string>& bytes ) noexcept override
    {
        opened_.fetch_add( 1, std::memory_order_relaxed );
        if( !bytes || f >= fresh_.size() || !needsFilter( f ) )
        {
            return;
        }
        const warmsnap::StatSig after = warmsnap::statSig( diskPath( ing_, f ).c_str(), true );
        if( !settled( after, startNs_ ) || after.size != std::int64_t( bytes->size() ) )
        {
            return;   // too young to vouch for (the racy rule), or it moved while read: read again next time
        }
        try
        {
            static thread_local TrigramScratch scratch;
            Fresh& slot = fresh_[ f ];
            slot.bits   = scratch.build( *bytes, slot.words );
            slot.sig    = after;
            learned_.fetch_add( 1, std::memory_order_relaxed );
        }
        catch( ... )   // an allocation: this file stays unfiltered, its scan is unchanged
        {
            fresh_[ f ] = Fresh{};
            DISCLOSE( Diagnostics::answerUnchanged, "a grep filter that could not be built is not stored: the file is read on the next scan, as today" );
        }
    }

    void finish() noexcept override
    {
        bool wrote = false;
        try
        {
            if( worthWriting( learned_.load(), ing_.files.size() ) )
            {
                wrote = writeMerged();
            }
        }
        catch( ... )
        {
            DISCLOSE( Diagnostics::answerUnchanged, "a grep record that could not be assembled is not written: the next scan reads the corpus, as today" );
        }
        if( memstats::enabled() )
        {
            rw::emitTo( stderr, "[verbfs] grep files={} opened={} skipped={} learned={} prefilter={} why={} wrote={}{}{}\n", ing_.files.size(), opened_.load(), skipped_.load(),
                        learned_.load(), off_ == nullptr ? "on" : "off", off_ == nullptr ? "ok" : off_, wrote ? 1 : 0, fault_ != nullptr ? " fault=" : "", fault_ != nullptr ? fault_ : "" );
        }
    }

private:
    struct Fresh
    {
        warmsnap::StatSig          sig;
        std::uint32_t              bits = kNoFilter;
        std::vector<std::uint64_t> words;
    };

    // file id -> record entry, by root-relative path: an index of the same files in the same order maps by position
    void mapEntries()
    {
        const std::size_t files = ing_.files.size();
        bool              same  = record_->rel.size() == files;
        for( std::uint32_t f = 0; same && f < files; ++f )
        {
            same = rootRelPath( ing_, f ) == record_->rel[ f ];
        }
        if( same )
        {
            for( std::uint32_t f = 0; f < files; ++f )
            {
                entryOf_[ f ] = f;
            }
            return;
        }
        HashMap<std::string_view, std::uint32_t> byRel;
        byRel.reserve( record_->rel.size() );
        for( std::uint32_t e = 0; e < std::uint32_t( record_->rel.size() ); ++e )
        {
            byRel.emplace( record_->rel[ e ], e );
        }
        for( std::uint32_t f = 0; f < files; ++f )
        {
            const auto it = byRel.find( rootRelPath( ing_, f ) );
            entryOf_[ f ] = it != byRel.end() ? it->second : UINT32_MAX;
        }
    }

    // a file the record holds no usable filter for: none stored, or one whose signature skip() saw move
    bool needsFilter( std::uint32_t f ) const noexcept
    {
        return entryOf_[ f ] == UINT32_MAX || record_->bits[ entryOf_[ f ] ] == kNoFilter || stale_[ f ] != 0;
    }

    // every file of this index: the filter learned now, else the record's (unless skip() saw it go stale), else none
    bool writeMerged()
    {
        auto              merged = std::make_shared<GrepRecord>();
        const std::size_t files  = ing_.files.size();
        merged->rel.reserve( files );
        merged->sig.resize( files );
        merged->bits.assign( files, kNoFilter );
        merged->wordAt.assign( files, 0 );
        for( std::uint32_t f = 0; f < files; ++f )
        {
            merged->rel.emplace_back( rootRelPath( ing_, f ) );
            merged->wordAt[ f ] = merged->words.size();
            if( fresh_[ f ].bits != kNoFilter )
            {
                merged->sig[ f ]  = fresh_[ f ].sig;
                merged->bits[ f ] = fresh_[ f ].bits;
                merged->words.insert( merged->words.end(), fresh_[ f ].words.begin(), fresh_[ f ].words.end() );
            }
            else if( !needsFilter( f ) )
            {
                const std::uint32_t e = entryOf_[ f ];
                merged->sig[ f ]      = record_->sig[ e ];
                merged->bits[ f ]     = record_->bits[ e ];
                const auto first      = record_->words.begin() + std::ptrdiff_t( record_->wordAt[ e ] );
                merged->words.insert( merged->words.end(), first, first + std::ptrdiff_t( record_->bits[ e ] / 64 ) );
            }
        }
        warmsnap::Out o = beginRecord();
        o.bytes.reserve( kHeaderBytes + merged->words.size() * 8 + files * 64 );
        writeGrepRecord( o, *merged );
        if( !commitRecord( Part::Grep, armed_.rootKey, o ) )
        {
            return false;
        }
        replaceLoaded( grepLoaded(), std::shared_ptr<const GrepRecord>( std::move( merged ) ) );
        return true;
    }

    const IngestResult&                         ing_;
    const ArmedRoot&                            armed_;
    const long long                             startNs_;
    const char* const                           fault_;
    std::shared_ptr<const GrepRecord>           record_;
    Why                                         recordWhy_ = Why::Absent;
    const char*                                 off_       = nullptr;   // why this scan is not filtered (null: it is)
    std::vector<std::vector<TrigramProbe>>      probes_;                // per pattern
    std::vector<std::uint32_t>                  entryOf_;               // per file: its record entry, or UINT32_MAX
    std::vector<std::uint8_t>                   stale_;                 // per file: skip() saw its signature move (written by its one worker)
    std::vector<Fresh>                          fresh_;                 // per file: a filter learned by this scan (written by its one worker)
    std::atomic<std::uint32_t>                  opened_{ 0 }, skipped_{ 0 }, learned_{ 0 };
};

inline std::unique_ptr<GrepSieve> openGrepSieve( const IngestResult& ing, std::span<const std::string> pats, bool regex, bool noPrefilter )
{
    const ArmedRoot* const armed = armedFor( ing );
    if( armed == nullptr || ing.files.empty() )
    {
        return nullptr;
    }
    return std::make_unique<RecordedGrepSieve>( ing, *armed, pats, regex, noPrefilter );
}

// ═══ (2) CLONES ══════════════════════════════════════════════════════════════════════════════════════════════════════
inline constexpr std::size_t kCloneEntriesKept = 4;   // one per (threshold, index) a root's callers alternate between

struct CloneEntry
{
    std::uint64_t                  digest    = 0;
    std::int32_t                   minTokens = 0;
    std::vector<std::uint32_t>     readFiles;   // file ids, ascending (stable under an equal digest: it covers the paths)
    std::vector<warmsnap::StatSig> readSigs;
    std::vector<CloneGroup>        groups;
};

struct CloneRecord
{
    std::vector<CloneEntry> entries;   // most recent first
};

inline void writeCloneRecord( warmsnap::Out& o, const CloneRecord& r )
{
    o.u64( r.entries.size() );
    for( const CloneEntry& e : r.entries )
    {
        o.u64( e.digest );
        o.u32( std::uint32_t( e.minTokens ) );
        o.vec( e.readFiles );
        o.vec( e.readSigs );
        o.u64( e.groups.size() );
        for( const CloneGroup& g : e.groups )
        {
            o.u32( g.tokens );
            o.u8( g.type );
            o.pod( g.similarity );
            o.vec( g.members );
        }
    }
}

inline bool readCloneRecord( std::string_view payload, CloneRecord& r )
{
    warmsnap::In      in{ payload };
    const std::size_t n = in.count( 36 );   // the fixed part of an entry
    for( std::size_t i = 0; i < n && in.ok; ++i )
    {
        CloneEntry e;
        e.digest    = in.u64();
        e.minTokens = std::int32_t( in.u32() );
        in.vec( e.readFiles );
        in.vec( e.readSigs );
        const std::size_t groups = in.count( 17 );   // the fixed part of a group
        if( groups > in.left() )   // count() already held groups to the bytes left: said again where the allocation is
        {
            in.ok = false;
            break;
        }
        e.groups.reserve( groups );
        for( std::size_t g = 0; g < groups && in.ok; ++g )
        {
            CloneGroup group;
            group.tokens     = in.u32();
            group.type       = in.u8();
            group.similarity = in.pod<float>();
            in.vec( group.members );
            e.groups.push_back( std::move( group ) );
        }
        if( !VALIDATE( e.readFiles.size() == e.readSigs.size(), "verbfs: a clone entry's reads and signatures disagree" ) )
        {
            return false;
        }
        r.entries.push_back( std::move( e ) );
    }
    return VALIDATE( in.ok && in.left() == 0, "verbfs: the clone record does not parse" );
}

inline LoadedRecord<CloneRecord>& clonesLoaded() noexcept
{
    static LoadedRecord<CloneRecord> slot;
    return slot;
}

// Every stored signature still matches its file (parallel above 2048 files; `fn` touches only its slot and the flag).
inline bool signaturesHold( const IngestResult& ing, std::span<const std::uint32_t> files, std::span<const warmsnap::StatSig> sigs )
{
    std::atomic<bool> moved{ false };
    warmsnap::parallelFor( files.size(), [ & ]( std::size_t i ) noexcept
    {
        if( files[ i ] >= ing.files.size() || !( warmsnap::statSig( diskPath( ing, files[ i ] ).c_str(), true ) == sigs[ i ] ) )
        {
            moved.store( true, std::memory_order_relaxed );
        }
    } );
    return !moved.load();
}

inline CloneServe serveClones( const IngestResult& ing, int minTokens, std::uint64_t inputDigest, std::vector<CloneGroup>& out )
{
    CloneServe             r{ false, nowNs() };
    const ArmedRoot* const armed = armedFor( ing );
    if( armed == nullptr )
    {
        return r;
    }
    const bool        anyDigest = rw::faultSwitchOnOnce<FaultCloneAnyDigest>( "RIPWIRE_FAULT_VERBFS_CLONE_ANYDIGEST" );
    Why               why       = Why::Absent;
    const auto        record    = loadOnce( clonesLoaded(), Part::Clones, armed->rootKey, readCloneRecord, why );
    const char*       miss      = record == nullptr ? kWhyNames[ std::size_t( why ) ] : "digest";
    const CloneEntry* hit       = nullptr;
    for( std::size_t i = 0; record != nullptr && hit == nullptr && i < record->entries.size(); ++i )
    {
        const CloneEntry& e = record->entries[ i ];
        if( e.minTokens == minTokens && ( e.digest == inputDigest || anyDigest ) )
        {
            hit = &e;
        }
    }
    if( hit != nullptr && !anyDigest && !signaturesHold( ing, hit->readFiles, hit->readSigs ) )
    {
        hit  = nullptr;
        miss = "stat";
    }
    if( hit != nullptr )
    {
        const auto inRange = [ & ]( const CloneGroup& g ) { return std::ranges::all_of( g.members, [ & ]( NodeId m ) { return m < ing.symbols.size(); } ); };
        if( !VALIDATE( anyDigest || std::ranges::all_of( hit->groups, inRange ), "verbfs: a stored clone group names a symbol this index does not hold" ) )
        {
            hit  = nullptr;
            miss = "shape";
        }
    }
    if( hit != nullptr )
    {
        out      = hit->groups;
        r.served = true;
    }
    if( memstats::enabled() )
    {
        if( r.served )
        {
            rw::emitTo( stderr, "[verbfs] clones served=1 why=ok min_tokens={} files_statted={} groups={}{}\n", minTokens, hit->readFiles.size(), out.size(),
                        anyDigest ? " fault=anydigest" : "" );
        }
        else
        {
            rw::emitTo( stderr, "[verbfs] clones served=0 why={} min_tokens={}{}\n", miss, minTokens, anyDigest ? " fault=anydigest" : "" );
        }
    }
    return r;
}

inline void keepClones( const IngestResult& ing, int minTokens, std::uint64_t inputDigest, const std::vector<CloneGroup>& groups, std::span<const std::uint32_t> readFileIds,
                        long long startNs )
{
    const ArmedRoot* const armed = armedFor( ing );
    if( armed == nullptr )
    {
        return;
    }
    CloneEntry fresh;
    fresh.digest    = inputDigest;
    fresh.minTokens = minTokens;
    fresh.readFiles.assign( readFileIds.begin(), readFileIds.end() );
    fresh.readSigs.resize( fresh.readFiles.size() );
    std::atomic<bool> young{ false };
    warmsnap::parallelFor( fresh.readFiles.size(), [ & ]( std::size_t i ) noexcept
    {
        fresh.readSigs[ i ] = warmsnap::statSig( diskPath( ing, fresh.readFiles[ i ] ).c_str(), true );
        if( !settled( fresh.readSigs[ i ], startNs ) )
        {
            young.store( true, std::memory_order_relaxed );
        }
    } );
    bool wrote = false;
    if( !young.load() )
    {
        fresh.groups = groups;
        Why  why     = Why::Absent;
        auto merged  = std::make_shared<CloneRecord>();
        merged->entries.push_back( std::move( fresh ) );
        if( const auto old = loadOnce( clonesLoaded(), Part::Clones, armed->rootKey, readCloneRecord, why ) )
        {
            for( const CloneEntry& e : old->entries )
            {
                if( merged->entries.size() < kCloneEntriesKept && !( e.digest == inputDigest && e.minTokens == minTokens ) )
                {
                    merged->entries.push_back( e );
                }
            }
        }
        warmsnap::Out o = beginRecord();
        writeCloneRecord( o, *merged );
        wrote = commitRecord( Part::Clones, armed->rootKey, o );
        if( wrote )
        {
            replaceLoaded( clonesLoaded(), std::shared_ptr<const CloneRecord>( std::move( merged ) ) );
        }
    }
    if( memstats::enabled() )
    {
        rw::emitTo( stderr, "[verbfs] clones kept={} files_read={} settled={} wrote={}\n", groups.size(), readFileIds.size(), young.load() ? 0 : 1, wrote ? 1 : 0 );
    }
}

// ═══ (3) DIRS ════════════════════════════════════════════════════════════════════════════════════════════════════════
struct DirsRecord
{
    std::vector<std::string>       names;   // the probed names, in probe order: a record of another name list is not used
    std::vector<std::string>       dirs;    // root-relative, sorted as readManifests sorts them (svLess), unique
    std::vector<warmsnap::StatSig> sigs;    // each directory's own lstat signature, settled
    std::vector<std::uint8_t>      kinds;   // dirs × names, dir-major: an EntryKind
};

inline void writeDirsRecord( warmsnap::Out& o, const DirsRecord& r )
{
    o.strs( r.names );
    warmsnap::writePaths( o, r.dirs.size(), [ & ]( std::size_t i ) -> std::string_view { return r.dirs[ i ]; } );
    o.vec( r.sigs );
    o.vec( r.kinds );
}

inline bool readDirsRecord( std::string_view payload, DirsRecord& r )
{
    warmsnap::In in{ payload };
    in.strs( r.names );
    warmsnap::readPaths( in, r.dirs );
    in.vec( r.sigs );
    in.vec( r.kinds );
    if( !VALIDATE( in.ok && in.left() == 0 && r.sigs.size() == r.dirs.size() && r.kinds.size() == r.dirs.size() * r.names.size(), "verbfs: the dirs record's arrays disagree" ) )
    {
        return false;
    }
    return VALIDATE( std::ranges::all_of( r.kinds, []( std::uint8_t k ) { return k <= std::uint8_t( EntryKind::Live ); } ), "verbfs: a stored entry kind is out of range" );
}

inline LoadedRecord<DirsRecord>& dirsLoaded() noexcept
{
    static LoadedRecord<DirsRecord> slot;
    return slot;
}

// The kind formanifest.h's probedManifestReadable reads first: a link is Live (it is followed there, every time).
inline EntryKind entryKindNow( const std::string& disk, bool storeLinkTarget ) noexcept
{
    std::error_code                    ec;
    const std::filesystem::file_status st = std::filesystem::symlink_status( disk, ec );
    if( std::filesystem::is_symlink( st ) )
    {
        if( storeLinkTarget )   // the RIPWIRE_FAULT_VERBFS_DIRS_LINKS mutant: what the link resolves to, as if it could not change
        {
            std::error_code fec;
            return std::filesystem::is_regular_file( disk, fec ) ? EntryKind::Regular : EntryKind::NotRegular;
        }
        return EntryKind::Live;
    }
    return std::filesystem::is_regular_file( st ) ? EntryKind::Regular : EntryKind::NotRegular;
}

// What one call learned about its probed directories: the kind of each (dir, name), and per directory where that came from.
struct DirProbes
{
    enum class From : std::uint8_t
    {
        Young,    // probed now, its signature not settled yet: probed again next time
        Record,   // its signature is unchanged: the record's kinds
        Now,      // probed now and settled: a fact to store
    };
    std::vector<EntryKind>         kinds;      // dirs × names, dir-major
    std::vector<warmsnap::StatSig> freshSig;   // per directory, for From::Now
    std::vector<From>              from;
};

// Each probed directory's record entry, or UINT32_MAX: both lists are sorted by the same order (svLess), so one merge walk pairs them.
inline std::vector<std::uint32_t> dirEntriesOf( const DirsRecord& record, std::span<const std::string_view> dirs )
{
    std::vector<std::uint32_t> entryOf( dirs.size(), UINT32_MAX );
    std::size_t                e = 0;
    for( std::size_t i = 0; i < dirs.size(); ++i )
    {
        while( e < record.dirs.size() && sortutil::svLess( record.dirs[ e ], dirs[ i ] ) )
        {
            ++e;
        }
        if( e < record.dirs.size() && record.dirs[ e ] == dirs[ i ] )
        {
            entryOf[ i ] = std::uint32_t( e );
        }
    }
    return entryOf;
}

// What every directory of one call is probed against.
struct DirProbeRun
{
    std::string_view                  rootPrefix;
    std::span<const std::string_view> names;
    const DirsRecord*                 record    = nullptr;   // null: nothing stored for these names
    long long                         startNs   = 0;
    bool                              noStat    = false;     // RIPWIRE_FAULT_VERBFS_DIRS_NOSTAT
    bool                              linkKinds = false;     // RIPWIRE_FAULT_VERBFS_DIRS_LINKS
};

// One directory: the record's kinds when its own signature is unchanged, else every name probed now (the spelling formanifest.h joins:
// <rootPrefix><dir>/<name>, the root's names bare) and the directory's signature read after the probes, for the settle rule.
inline void probeDirInto( DirProbes& out, std::size_t i, std::string_view dir, std::uint32_t entry, const DirProbeRun& run )
{
    const std::string_view                  rootPrefix = run.rootPrefix;
    const std::span<const std::string_view> names      = run.names;
    const DirsRecord* const                 record     = run.record;
    const std::size_t                       nameCount  = names.size();
    const std::string dirDisk   = dir.empty() ? ( rootPrefix.empty() ? std::string( "." ) : std::string( rootPrefix ) ) : std::string( rootPrefix ) + std::string( dir );
    if( record != nullptr && entry != UINT32_MAX && ( run.noStat || warmsnap::statSig( dirDisk.c_str(), false ) == record->sigs[ entry ] ) )
    {
        for( std::size_t n = 0; n < nameCount; ++n )
        {
            out.kinds[ i * nameCount + n ] = EntryKind( record->kinds[ std::size_t( entry ) * nameCount + n ] );
        }
        out.from[ i ] = DirProbes::From::Record;
        return;
    }
    for( std::size_t n = 0; n < nameCount; ++n )
    {
        const std::string rel          = dir.empty() ? std::string( names[ n ] ) : std::string( dir ) + "/" + std::string( names[ n ] );
        out.kinds[ i * nameCount + n ] = entryKindNow( std::string( rootPrefix ) + rel, run.linkKinds );
    }
    out.freshSig[ i ] = warmsnap::statSig( dirDisk.c_str(), false );
    out.from[ i ]     = settled( out.freshSig[ i ], run.startNs ) ? DirProbes::From::Now : DirProbes::From::Young;
}

// The record this call can stand behind: every directory served or settled now; a young one is left out (probed live next time).
inline bool writeDirsMerged( const ArmedRoot& armed, std::span<const std::string_view> dirs, std::span<const std::string_view> names, const DirProbes& probes,
                             const DirsRecord* record, const std::vector<std::uint32_t>& entryOf )
{
    auto merged = std::make_shared<DirsRecord>();
    merged->names.assign( names.begin(), names.end() );
    for( std::size_t i = 0; i < dirs.size(); ++i )
    {
        if( probes.from[ i ] == DirProbes::From::Young )
        {
            continue;
        }
        merged->dirs.emplace_back( dirs[ i ] );
        merged->sigs.push_back( probes.from[ i ] == DirProbes::From::Now ? probes.freshSig[ i ] : record->sigs[ entryOf[ i ] ] );
        for( std::size_t n = 0; n < names.size(); ++n )
        {
            merged->kinds.push_back( std::uint8_t( probes.kinds[ i * names.size() + n ] ) );
        }
    }
    warmsnap::Out o = beginRecord();
    writeDirsRecord( o, *merged );
    if( !commitRecord( Part::Dirs, armed.rootKey, o ) )
    {
        return false;
    }
    replaceLoaded( dirsLoaded(), std::shared_ptr<const DirsRecord>( std::move( merged ) ) );
    return true;
}

inline std::vector<EntryKind> entryKindsOf( const IngestResult& ing, std::string_view rootPrefix, std::span<const std::string_view> dirs, std::span<const std::string_view> names )
{
    const ArmedRoot* const armed = armedFor( ing );
    if( armed == nullptr || names.empty() )
    {
        return {};
    }
    const bool      noStat    = rw::faultSwitchOnOnce<FaultDirsNoStat>( "RIPWIRE_FAULT_VERBFS_DIRS_NOSTAT" );
    const bool      linkKinds = rw::faultSwitchOnOnce<FaultDirsLinks>( "RIPWIRE_FAULT_VERBFS_DIRS_LINKS" );
    const long long startNs   = nowNs();
    Why             why       = Why::Absent;
    const auto      loaded    = loadOnce( dirsLoaded(), Part::Dirs, armed->rootKey, readDirsRecord, why );
    const bool      sameNames = loaded != nullptr && std::ranges::equal( loaded->names, names, []( const std::string& a, std::string_view b ) { return a == b; } );
    const DirsRecord* const          record  = sameNames ? loaded.get() : nullptr;
    const std::vector<std::uint32_t> entryOf = record != nullptr ? dirEntriesOf( *record, dirs ) : std::vector<std::uint32_t>( dirs.size(), UINT32_MAX );

    DirProbes probes{ std::vector<EntryKind>( dirs.size() * names.size(), EntryKind::Live ), std::vector<warmsnap::StatSig>( dirs.size() ),
                      std::vector<DirProbes::From>( dirs.size(), DirProbes::From::Young ) };
    const DirProbeRun run{ rootPrefix, names, record, startNs, noStat, linkKinds };
    warmsnap::parallelFor( dirs.size(), [ & ]( std::size_t i ) noexcept
    {
        probeDirInto( probes, i, dirs[ i ], entryOf[ i ], run );
    } );

    const std::size_t learned    = std::size_t( std::ranges::count( probes.from, DirProbes::From::Now ) );
    std::size_t       fromRecord = 0;   // names answered from the record with no syscall
    for( std::size_t at = 0; at < probes.kinds.size(); ++at )
    {
        fromRecord += probes.from[ at / names.size() ] == DirProbes::From::Record && probes.kinds[ at ] != EntryKind::Live ? 1 : 0;
    }
    bool wrote = false;
    try
    {
        wrote = worthWriting( learned, dirs.size() ) && writeDirsMerged( *armed, dirs, names, probes, record, entryOf );
    }
    catch( ... )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "a dirs record that could not be assembled is not written: the next probe is live, as today" );
    }
    if( memstats::enabled() )
    {
        rw::emitTo( stderr, "[verbfs] dirs dirs={} probes={} served={} live={} learned={} why={} wrote={}{}\n", dirs.size(), probes.kinds.size(), fromRecord,
                    probes.kinds.size() - fromRecord, learned, loaded == nullptr ? kWhyNames[ std::size_t( why ) ] : sameNames ? "ok" : "names", wrote ? 1 : 0,
                    noStat ? " fault=nostat" : linkKinds ? " fault=links" : "" );
    }
    return std::move( probes.kinds );
}

// ── arming ──────────────────────────────────────────────────────────────────────────────────────────────────────────
// Called by ingest() for the primary ingest of a cached single-root run (where it arms the warm snapshot), on the main
// thread before any verb runs. Installs every seam this file implements; RIPWIRE_NO_VERBFS=1 leaves them null.
inline void arm( std::string_view rootDir, const std::string& rootKey )
{
    if( killSwitchOn() || rootKey.empty() || rootDir.empty() )
    {
        return;
    }
    ArmedRoot& a = armedRoot();
    a.rootDir    = std::string( rootDir );
    a.rootKey    = rootKey;
    a.on         = true;
    Seams& s     = seams();
    s.grepSieve  = &openGrepSieve;
    s.cloneServe = &serveClones;
    s.cloneKeep  = &keepClones;
    s.entryKinds = &entryKindsOf;
}

}   // namespace rw::verbfs
