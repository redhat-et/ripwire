#pragma once
// verbfs_qmetrics.h — VERB-FS QMETRICS: the two whole-index derived results a served run recomputed after every snapshot load,
// kept per index (lane QMETRICS-PERSIST, 2026-11-25).
//
// WHY. A served warm --for on llvm-project spent 235.5 ms of main-thread wall in computeQMetrics and 75.6 ms in computeImpure
// (results/PHASESPLIT_1125 §2, the B1 timer build), on every call, though both are pure functions of the index and the graph
// and the index had not moved. Each now consults a record in the per-user cache directory, beside lane 5b's grep, clones and
// dirs parts (src/verbfs.h): `ripwire-verbfs-<rootKey>-qmetrics-….bin` and `ripwire-verbfs-<rootKey>-impure-….bin`.
//
// THE IDENTITY RULE. A stored answer is used only where its KEY equals the key of the current inputs, and the key digests
// EVERY input the computation reads — enumerated by reading the function and everything it calls (graph.h), the model on
// 5b's clone part (clones.h cloneInputDigest). Nothing comes from outside the model and the graph: neither computation reads
// a file, git, the clock, the environment or a flag (amp='s co-change half and churn= are computed outside them, in main.cpp,
// live on every run). The code itself IS an input, so the record's layout key carries this build's producer identity
// (quality::producerIdentityHash, the SHA-256 of src/ and queries/): a record another build wrote is refused (why=shape).
//
//   qmetrics — the DERIVED columns only (graph.h fillQMetricsTested, fillQMetricsLcom4). The direct columns (callerCount,
//   cbo: CSR row lengths and one pass over composeEdges) are filled live on every run, as before, from the same code.
//     shape    S = ing.symbols.size(); ing.files.size(); g.wOutDeg.size() (forwardReach's N)
//     files    ing.crawlRoot and every ing.files[ f ] text (isTestSymbol -> isTestPath( rootRelPath ); LCOM4's class key)
//     symbols  per symbol: id, fileId, kind, testScope, name, scope (isTestSymbol; LCOM4's class / method attribution)
//     refs     per reference whose fromSymbol is a Method of this index and that is not an IX-1 slot record (exactly the
//              references LCOM4's methodRefNames collects): the MULTISET of ( fromSymbol, calleeName TEXT ) pairs. A multiset
//              is the whole dependency: LCOM4 reads a method's names only through "does it name this field" (graph.h, the
//              `nm == fld` test), which no order and no other reference can change — so an edit that only adds, removes or
//              reorders references LCOM4 never collects keeps the key
//     graph    g.outOff and g.outTargets (forwardReach, method-calls-method); per compose edge ownerSym and fieldName
//              (LCOM4's declared fields), in order
//   impure — the whole mask (graph.h computeImpure = propagateImpure over the seed sites).
//     shape    S; g.inEdges.rows()
//     refs     the seed sites: the MULTISET of fromSymbol over every reference isImpureSeed admits (a CALL of a side-effecting
//              name from a symbol of this index) — the only thing the propagation reads from the references, and through
//              a set only (the mask is the backward closure of the seeds; worklist order decides the walk, never the mask)
//     graph    g.inEdges' row offsets and column indices
//   A text is digested by its bytes, never by its pool id (an id's value depends on thread timing: internedtext.h).
//
// THE CORRECTNESS ARGUMENT. Both computations are deterministic functions of the inputs listed (their own comments say so:
// every input is in a fixed order and the one hash-map walk is sorted first). Equal key = equal inputs, up to a 64-bit
// collision per component, the same standard as the clone part: so the stored answer is the one the computation would
// produce. An ordered component is digested in fixed blocks of rows, each block's digest folded in block order; a multiset
// component is the modular sum of its items' digests (with their count). Either is a function of the items alone — never of
// the thread count or timing. Anything else recomputes, exactly as before (the miss path IS
// computeQMetricsComputed / computeImpureComputed, unchanged), and offers its result.
//
// THE KEY IS KEPT AS NAMED COMPONENTS so a miss names the first input that moved (why=shape|files|symbols|refs|graph), and each
// mutation arm of test/qmetricscheck.sh blinds exactly one of them (RIPWIRE_FAULT_VERBFS_QMETRICS_*; constexpr false under
// NDEBUG).
//
// ARMED exactly where 5b's parts are: verbfs::armQMetrics installs the seams only when verbfs::arm armed the root (the primary
// ingest of a cached single-root run; never under --no-cache, multi-root, --scip, --pin-census, --max-memory, RIPWIRE_NO_WARMSNAP
// or the kill switch RIPWIRE_NO_VERBFS=1), and a seam serves only an IngestResult of that root (verbfs::armedFor).
//
// FORMAT. 5b's 40-byte header — magic, version, part, layout key, payload length, payload digest — with this file's own version
// and part numbers (outside verbfs::Part's, so neither family can misread the other). Any mismatch refuses the whole file
// (why=version|shape|checksum), the run computes, and writes a fresh record. Every array is read through warmsnap::In::vec,
// which holds its count to the bytes left before it allocates.
//
// STATS (RIPWIRE_STATS=1, stderr only): one `[verbfs] qmetrics …` / `[verbfs] impure …` line per use: served=, why=, wrote=.

#include "verbfs.h"   // armedRoot / armedFor, kMagic, kHeaderBytes, layoutKey, Why + kWhyNames, RecordFile, LoadedRecord — the family this part joins
#include "graph.h"    // QMetrics and the halves of computeQMetricsComputed / computeImpureComputed the record stands for
#include "infra/hashutil.h"       // hashMix, packPair — the digest's mix
#include "infra/internedtext.h"   // TextPool::hashOf — a text digested by its bytes
#include "infra/platform.h"       // addWithCarry64 — the multiset sum, modulo 2^64 without a wrap the sanitizer reports

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <format>
#include <functional>   // std::greater_equal — the stored lcom4 rows are strictly ascending
#include <memory>
#include <mutex>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace rw::verbfs
{

// ── the record file ─────────────────────────────────────────────────────────────────────────────────────────────────
inline constexpr std::uint32_t kQmRecordVersion = 1;      // bump on ANY payload layout change of either part below
inline constexpr std::uint32_t kPartQMetrics    = 0x51;   // 'Q': outside verbfs::Part (1..), so no other part's reader takes it
inline constexpr std::uint32_t kPartImpure      = 0x49;   // 'I'

// The key's components, in the order a miss reports the first that moved.
enum class QmKey : std::uint8_t
{
    Shape,
    Files,
    Symbols,
    Refs,
    Graph,
    Count
};
inline constexpr const char* kQmKeyNames[] = { "shape", "files", "symbols", "refs", "graph" };
static_assert( std::size( kQmKeyNames ) == std::size_t( QmKey::Count ), "every key component needs its name on the stats line" );

enum class ImKey : std::uint8_t
{
    Shape,
    Refs,
    Graph,
    Count
};
inline constexpr const char* kImKeyNames[] = { "shape", "refs", "graph" };
static_assert( std::size( kImKeyNames ) == std::size_t( ImKey::Count ), "every key component needs its name on the stats line" );

// The code is an input: a record another build (other source, other layout) wrote is refused, never misread.
inline std::uint64_t qmLayoutKey()
{
    return depwatch::digest64( std::format( "verbfs-qmetrics v={} producer={:016x} base={:016x} nodeid={} lcom4na={:08x}", kQmRecordVersion,
                                            quality::producerIdentityHash(), layoutKey(), sizeof( NodeId ), kLcom4NA ) );
}

inline std::string qmRecordPath( std::string_view partName, std::string_view rootKey )
{
    return quality::shaKeyedCachePath( "verbfs", std::string( rootKey ), std::string( partName ), "" );
}

// 5b's readRecord, for a part number outside verbfs::Part (verbfs.h's readRecord / commitRecord take that closed enum).
// `noSum`: the RIPWIRE_FAULT_VERBFS_QMETRICS_NOSUM mutant, which trusts a payload whose checksum fails.
inline RecordFile readQmRecord( std::uint32_t partNo, std::string_view partName, std::string_view rootKey, bool noSum )
{
    RecordFile                 out;
    std::optional<std::string> file = pathguard::readRegularFileNoFollow( qmRecordPath( partName, rootKey ) );
    if( !file )
    {
        return out;   // Absent: the ordinary first run
    }
    out.bytes = std::move( *file );
    warmsnap::In        in{ std::string_view( out.bytes ) };
    const std::uint64_t magic   = in.u64();
    const std::uint32_t version = in.u32();
    const std::uint32_t part    = in.u32();
    const std::uint64_t layout  = in.u64();
    const std::uint64_t length  = in.u64();
    const std::uint64_t sum     = in.u64();
    if( !VALIDATE( in.ok && magic == kMagic, "verbfs qmetrics: not a record file" ) )
    {
        out.why = Why::Shape;
    }
    else if( !VALIDATE( version == kQmRecordVersion, "verbfs qmetrics: a record of another format version" ) )
    {
        out.why = Why::Version;
    }
    else if( !VALIDATE( part == partNo && layout == qmLayoutKey(), "verbfs qmetrics: a record of another part, layout or build" ) )
    {
        out.why = Why::Shape;
    }
    else if( !VALIDATE( length == out.bytes.size() - kHeaderBytes && ( noSum || depwatch::digest64( out.payload() ) == sum ), "verbfs qmetrics: a record whose checksum fails" ) )
    {
        out.why = Why::Checksum;
    }
    else
    {
        out.why = Why::Ok;
        return out;
    }
    DISCLOSE( Diagnostics::answerUnchanged, "a VERB-FS QMETRICS record that is refused is not read: the computation runs in full, and the run writes a fresh record" );
    out.bytes.clear();
    return out;
}

// 5b's commitRecord, for the same reason.
inline bool commitQmRecord( std::uint32_t partNo, std::string_view partName, std::string_view rootKey, warmsnap::Out& o )
{
    EXPECTS( o.bytes.size() >= kHeaderBytes, "the payload was written behind beginRecord's header" );
    const std::string_view payload = std::string_view( o.bytes ).substr( kHeaderBytes );
    warmsnap::Out          head;
    head.u64( kMagic );
    head.u32( kQmRecordVersion );
    head.u32( partNo );
    head.u64( qmLayoutKey() );
    head.u64( payload.size() );
    head.u64( depwatch::digest64( payload ) );
    ENSURES( head.bytes.size() == kHeaderBytes, "the header is the fixed 40 bytes readQmRecord takes" );
    std::memcpy( o.bytes.data(), head.bytes.data(), kHeaderBytes );
    if( !quality::atomicWriteFile( qmRecordPath( partName, rootKey ), o.bytes ) )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "this run's answer is already computed; only the next run's VERB-FS QMETRICS record is not there, and it computes in full" );
        return false;
    }
    return true;
}

// ── the fault switches of the mutation arms (test/qmetricscheck.sh; constexpr false under NDEBUG) ────────────────────
struct FaultQmAnyDigest;
struct FaultQmNoGraph;
struct FaultQmNoRefs;
struct FaultQmNoFiles;
struct FaultQmNoSyms;
struct FaultQmNoSum;
struct QmFaults
{
    bool anyDigest = false;   // serve whatever is stored, fitted to this index's symbol count
    bool noGraph   = false;   // a key that differs only in the graph component still serves
    bool noRefs    = false;   // ... only in the refs component
    bool noFiles   = false;   // ... only in the files component
    bool noSyms    = false;   // ... only in the symbols component
    bool noSum     = false;   // a payload whose checksum fails is read
    const char* name() const noexcept
    {
        return anyDigest ? "anydigest" : noGraph ? "nograph" : noRefs ? "norefs" : noFiles ? "nofiles" : noSyms ? "nosyms" : noSum ? "nosum" : nullptr;
    }
    bool blinds( std::string_view component ) const noexcept
    {
        return ( noGraph && component == "graph" ) || ( noRefs && component == "refs" ) || ( noFiles && component == "files" ) || ( noSyms && component == "symbols" );
    }
};
inline QmFaults qmFaults() noexcept
{
    return { rw::faultSwitchOnOnce<FaultQmAnyDigest>( "RIPWIRE_FAULT_VERBFS_QMETRICS_ANYDIGEST" ), rw::faultSwitchOnOnce<FaultQmNoGraph>( "RIPWIRE_FAULT_VERBFS_QMETRICS_NOGRAPH" ),
             rw::faultSwitchOnOnce<FaultQmNoRefs>( "RIPWIRE_FAULT_VERBFS_QMETRICS_NOREFS" ), rw::faultSwitchOnOnce<FaultQmNoFiles>( "RIPWIRE_FAULT_VERBFS_QMETRICS_NOFILES" ),
             rw::faultSwitchOnOnce<FaultQmNoSyms>( "RIPWIRE_FAULT_VERBFS_QMETRICS_NOSYMS" ),
             rw::faultSwitchOnOnce<FaultQmNoSum>( "RIPWIRE_FAULT_VERBFS_QMETRICS_NOSUM" ) };
}

// ── the digest: fixed blocks, folded in block order ──────────────────────────────────────────────────────────────────
inline constexpr std::size_t kDigestItemsPerBlock = std::size_t( 1 ) << 14;   // rows per block: the partition is the items', not the threads'
inline constexpr std::size_t kDigestBytesPerBlock = std::size_t( 1 ) << 20;   // bytes per block of a raw array
inline constexpr std::size_t kDigestThreadCap     = 16;

// fn( b ) for every block b in [0, blockCount), on up to kDigestThreadCap threads; fn touches only block b's slot.
template <class Fn>
inline void forEachDigestBlock( std::size_t blockCount, Fn&& fn )
{
    const std::size_t workers = std::min( { std::size_t( std::max( std::thread::hardware_concurrency(), 1u ) ), blockCount, kDigestThreadCap } );
    std::atomic<std::size_t> next{ 0 };
    const auto body = [ & ]() noexcept
    {
        for( std::size_t b = next.fetch_add( 1, std::memory_order_relaxed ); b < blockCount; b = next.fetch_add( 1, std::memory_order_relaxed ) )
        {
            fn( b );
        }
    };
    if( workers <= 1 )
    {
        body();
        return;
    }
    std::vector<std::thread> pool;
    pool.reserve( workers - 1 );
    for( std::size_t t = 1; t < workers; ++t )
    {
        pool.emplace_back( body );
    }
    body();
    for( std::thread& th : pool )
    {
        th.join();
    }
}

// The digest of rows [0, rowCount): absorb( i, h ) folds row i into its block's running digest h, in row order within the block.
template <class Absorb>
inline std::uint64_t rowsDigest( std::size_t rowCount, std::uint64_t seed, Absorb&& absorb )
{
    const std::size_t          blocks = ( rowCount + kDigestItemsPerBlock - 1 ) / kDigestItemsPerBlock;
    std::vector<std::uint64_t> part( blocks, 0 );
    forEachDigestBlock( blocks, [ & ]( std::size_t b ) noexcept
    {
        std::uint64_t     h   = hashutil::hashMix( seed ^ hashutil::hashMix( b ) );
        const std::size_t end = std::min( rowCount, ( b + 1 ) * kDigestItemsPerBlock );
        for( std::size_t i = b * kDigestItemsPerBlock; i < end; ++i )
        {
            absorb( i, h );
        }
        part[ b ] = h;
    } );
    std::uint64_t h = hashutil::hashMix( seed ^ std::uint64_t( rowCount ) );
    for( const std::uint64_t p : part )
    {
        h = hashutil::hashMix( h ^ p );
    }
    return h;
}

// The digest of the MULTISET of items: item( i, out ) sets out to row i's item digest and returns true when row i holds an item.
// The modular sum of the item digests and their count: order- and partition-free, so a row that holds no item cannot move it.
template <class Item>
inline std::uint64_t multisetDigest( std::size_t rowCount, std::uint64_t seed, Item&& item )
{
    const std::size_t          blocks = ( rowCount + kDigestItemsPerBlock - 1 ) / kDigestItemsPerBlock;
    std::vector<std::uint64_t> sum( blocks, 0 ), count( blocks, 0 );
    forEachDigestBlock( blocks, [ & ]( std::size_t b ) noexcept
    {
        std::uint64_t     s = 0, n = 0, d = 0, carry = 0;
        const std::size_t end = std::min( rowCount, ( b + 1 ) * kDigestItemsPerBlock );
        for( std::size_t i = b * kDigestItemsPerBlock; i < end; ++i )
        {
            if( item( i, d ) )
            {
                carry = 0;
                s     = infra::platform::addWithCarry64( s, hashutil::hashMix( seed ^ d ), carry );   // modulo 2^64 by intent; the carry is dropped
                ++n;
            }
        }
        sum[ b ]   = s;
        count[ b ] = n;
    } );
    std::uint64_t total = 0, items = 0, carry = 0;
    for( std::size_t b = 0; b < blocks; ++b )
    {
        carry = 0;
        total = infra::platform::addWithCarry64( total, sum[ b ], carry );
        items += count[ b ];
    }
    return hashutil::hashMix( hashutil::hashMix( seed ^ total ) ^ items );
}

// The digest of a raw array's bytes (its length included).
template <class T>
inline std::uint64_t bytesDigest( const T* rows, std::size_t rowCount, std::uint64_t seed )
{
    const std::size_t byteCount = rowCount * sizeof( T );
    const char* const bytes     = reinterpret_cast<const char*>( rows );
    const std::size_t blocks    = ( byteCount + kDigestBytesPerBlock - 1 ) / kDigestBytesPerBlock;
    std::vector<std::uint64_t> part( blocks, 0 );
    forEachDigestBlock( blocks, [ & ]( std::size_t b ) noexcept
    {
        const std::size_t from = b * kDigestBytesPerBlock;
        part[ b ]              = depwatch::digest64( std::string_view( bytes + from, std::min( kDigestBytesPerBlock, byteCount - from ) ) );
    } );
    std::uint64_t h = hashutil::hashMix( seed ^ std::uint64_t( byteCount ) );
    for( const std::uint64_t p : part )
    {
        h = hashutil::hashMix( h ^ p );
    }
    return h;
}

inline void absorbInto( std::uint64_t& h, std::uint64_t v ) noexcept
{
    h = hashutil::hashMix( h ^ v );
}
inline std::uint64_t textDigest( std::string_view text ) noexcept
{
    return TextPool::hashOf( text );   // the bytes, never the pool id
}

// Everything the derived QMetrics columns read (see the table at the top), one digest per component.
inline std::vector<std::uint64_t> qmetricsKey( const IngestResult& ing, const Graph& g )
{
    const std::size_t          S = ing.symbols.size();
    std::vector<std::uint64_t> key( std::size_t( QmKey::Count ), 0 );

    std::uint64_t shape = 0x5157'4b53'4841'5045ull;
    absorbInto( shape, S );
    absorbInto( shape, ing.files.size() );
    absorbInto( shape, g.wOutDeg.size() );
    key[ std::size_t( QmKey::Shape ) ] = shape;

    key[ std::size_t( QmKey::Files ) ] = rowsDigest( ing.files.size(), textDigest( ing.crawlRoot ), [ & ]( std::size_t f, std::uint64_t& h ) noexcept { absorbInto( h, textDigest( ing.files[ f ] ) ); } );

    key[ std::size_t( QmKey::Symbols ) ] = rowsDigest( S, 0x5359'4d42'4f4c'5321ull, [ & ]( std::size_t i, std::uint64_t& h ) noexcept
    {
        const Symbol& s = ing.symbols[ i ];
        absorbInto( h, hashutil::packPair( s.id, s.fileId ) );
        absorbInto( h, hashutil::packPair( std::uint32_t( s.kind ), std::uint32_t( s.testScope ) ) );
        absorbInto( h, textDigest( s.name ) );
        absorbInto( h, textDigest( s.scope ) );
    } );

    // the references LCOM4 collects into methodRefNames, and nothing else of the stream
    std::vector<std::uint8_t> isMethod( S, 0 );
    for( std::size_t i = 0; i < S; ++i )
    {
        isMethod[ i ] = ing.symbols[ i ].kind == SymKind::Method ? 1 : 0;
    }
    key[ std::size_t( QmKey::Refs ) ] = multisetDigest( ing.references.size(), 0x5245'4653'4d45'5448ull, [ & ]( std::size_t k, std::uint64_t& d ) noexcept
    {
        const Reference& r = ing.references[ k ];
        if( r.fromSymbol != kNoNode && r.fromSymbol < S && isMethod[ r.fromSymbol ] != 0 && !isSlotJoinRecord( r ) )
        {
            d = hashutil::hashMix( hashutil::packPair( r.fromSymbol, 0x4d45'5448u ) ) ^ textDigest( r.calleeName );
            return true;
        }
        return false;
    } );

    std::uint64_t graph = bytesDigest( g.outOff.data(), g.outOff.size(), 0x4752'4150'484f'5554ull );
    absorbInto( graph, bytesDigest( g.outTargets.data(), g.outTargets.size(), 0x4752'4150'4854'4752ull ) );
    absorbInto( graph, rowsDigest( g.composeEdges.size(), 0x434f'4d50'4f53'4521ull, [ & ]( std::size_t e, std::uint64_t& h ) noexcept
    {
        absorbInto( h, g.composeEdges[ e ].ownerSym );
        absorbInto( h, textDigest( g.composeEdges[ e ].fieldName ) );
    } ) );
    key[ std::size_t( QmKey::Graph ) ] = graph;
    return key;
}

// Everything computeImpure reads, one digest per component.
inline std::vector<std::uint64_t> impureKey( const IngestResult& ing, const Graph& g )
{
    const std::size_t          S = ing.symbols.size();
    std::vector<std::uint64_t> key( std::size_t( ImKey::Count ), 0 );

    std::uint64_t shape = 0x494d'5053'4841'5045ull;
    absorbInto( shape, S );
    absorbInto( shape, g.inEdges.rows() );
    key[ std::size_t( ImKey::Shape ) ] = shape;

    key[ std::size_t( ImKey::Refs ) ] = multisetDigest( ing.references.size(), 0x494d'5053'4545'4453ull, [ & ]( std::size_t k, std::uint64_t& d ) noexcept
    {
        const Reference& r = ing.references[ k ];
        d                  = r.fromSymbol;
        return isImpureSeed( r, S );
    } );

    const std::size_t    rows = g.inEdges.rows();
    const std::uint32_t* ro   = g.inEdges.rowOffsets();
    const std::size_t    nnz  = rows != 0 && ro != nullptr ? ro[ rows ] : 0;
    std::uint64_t        graph = bytesDigest( ro, ro != nullptr ? rows + 1 : 0, 0x494d'5052'4f57'4f46ull );
    absorbInto( graph, bytesDigest( g.inEdges.colIndices(), nnz, 0x494d'5043'4f4c'5321ull ) );
    key[ std::size_t( ImKey::Graph ) ] = graph;
    return key;
}

// The first component the two keys disagree on that the faults do not blind, or null when they agree.
inline const char* firstMovedComponent( std::span<const std::uint64_t> stored, std::span<const std::uint64_t> now, std::span<const char* const> names, const QmFaults& faults )
{
    if( stored.size() != now.size() )
    {
        return "shape";
    }
    for( std::size_t c = 0; c < now.size(); ++c )
    {
        if( stored[ c ] != now[ c ] && !faults.blinds( names[ c ] ) )
        {
            return names[ c ];
        }
    }
    return nullptr;
}

// ── (4) QMETRICS ═════════════════════════════════════════════════════════════════════════════════════════════════════
struct QmRecord
{
    std::vector<std::uint64_t> key;
    std::uint64_t              symbolCount = 0;
    std::vector<std::uint8_t>  tested;       // one per symbol: 0 / 1
    std::vector<std::uint32_t> lcom4At;      // the symbols whose lcom4 is not kLcom4NA, ascending
    std::vector<std::uint32_t> lcom4Value;   // parallel to lcom4At
};

inline void writeQmRecord( warmsnap::Out& o, const QmRecord& r )
{
    o.vec( r.key );
    o.u64( r.symbolCount );
    o.vec( r.tested );
    o.vec( r.lcom4At );
    o.vec( r.lcom4Value );
}

inline bool readQmPayload( std::string_view payload, QmRecord& r )
{
    warmsnap::In in{ payload };
    in.vec( r.key );
    r.symbolCount = in.u64();
    in.vec( r.tested );
    in.vec( r.lcom4At );
    in.vec( r.lcom4Value );
    if( !VALIDATE( in.ok && in.left() == 0 && r.key.size() == std::size_t( QmKey::Count ) && r.tested.size() == r.symbolCount && r.lcom4At.size() == r.lcom4Value.size(),
                   "verbfs qmetrics: the record's arrays disagree" ) )
    {
        return false;
    }
    const bool rowsOk = std::ranges::all_of( r.tested, []( std::uint8_t t ) { return t <= 1; } )
                     && std::ranges::all_of( r.lcom4At, [ & ]( std::uint32_t at ) { return at < r.symbolCount; } )
                     && std::ranges::adjacent_find( r.lcom4At, std::greater_equal<>() ) == r.lcom4At.end();
    return VALIDATE( rowsOk, "verbfs qmetrics: a stored row lies outside the record's index" );
}

inline LoadedRecord<QmRecord>& qmetricsLoaded() noexcept
{
    static LoadedRecord<QmRecord> slot;
    return slot;
}

// The record, once per process (re-read only when this process wrote a newer one).
template <class Rec, class Parse>
inline std::shared_ptr<const Rec> loadQmOnce( LoadedRecord<Rec>& slot, std::uint32_t partNo, std::string_view partName, std::string_view rootKey, bool noSum, Parse&& parse,
                                              Why& why )
{
    const std::lock_guard<std::mutex> hold( slot.guard );
    if( !slot.loaded )
    {
        slot.loaded           = true;
        const RecordFile file = readQmRecord( partNo, partName, rootKey, noSum );
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
                DISCLOSE( Diagnostics::answerUnchanged, "a VERB-FS QMETRICS record whose payload does not parse is not read: the computation runs in full" );
                slot.why = Why::Shape;
            }
        }
    }
    why = slot.why;
    return slot.record;
}

// The shapes the derived columns' reads assume: a CSR with one row per symbol. A graph of any other shape is computed, never stored.
inline bool graphFitsIndex( const IngestResult& ing, const Graph& g ) noexcept
{
    const std::size_t S = ing.symbols.size();
    return g.wOutDeg.size() == S && g.outOff.size() == S + 1 && g.outOff.back() <= g.outTargets.size();
}

inline bool keepQMetrics( const ArmedRoot& armed, std::vector<std::uint64_t> key, const QMetrics& q )
{
    auto rec         = std::make_shared<QmRecord>();
    rec->key         = std::move( key );
    rec->symbolCount = q.tested.size();
    rec->tested      = q.tested;
    for( std::uint32_t i = 0; i < std::uint32_t( q.lcom4.size() ); ++i )
    {
        if( q.lcom4[ i ] != kLcom4NA )
        {
            rec->lcom4At.push_back( i );
            rec->lcom4Value.push_back( q.lcom4[ i ] );
        }
    }
    warmsnap::Out o = beginRecord();
    writeQmRecord( o, *rec );
    if( !commitQmRecord( kPartQMetrics, "qmetrics", armed.rootKey, o ) )
    {
        return false;
    }
    replaceLoaded( qmetricsLoaded(), std::shared_ptr<const QmRecord>( std::move( rec ) ) );
    return true;
}

// The stored derived columns, onto a QMetrics whose direct columns are already filled for this index.
inline void applyStoredQMetrics( const QmRecord& rec, QMetrics& q )
{
    const std::size_t S = q.tested.size();
    std::copy_n( rec.tested.begin(), std::min( S, rec.tested.size() ), q.tested.begin() );   // equal sizes unless the any-digest mutant
    for( std::size_t k = 0; k < rec.lcom4At.size(); ++k )
    {
        if( rec.lcom4At[ k ] < S )
        {
            q.lcom4[ rec.lcom4At[ k ] ] = rec.lcom4Value[ k ];
        }
    }
}

inline QMetrics serveQMetrics( const IngestResult& ing, const Graph& g )
{
    const ArmedRoot* const armed = armedFor( ing );
    if( armed == nullptr )
    {
        return computeQMetricsComputed( ing, g );
    }
    const QmFaults    faults = qmFaults();
    const std::size_t S      = ing.symbols.size();
    const char*       why    = "fit";
    bool              served = false, wrote = false;
    QMetrics          q;
    if( graphFitsIndex( ing, g ) )
    {
        std::vector<std::uint64_t> key       = qmetricsKey( ing, g );
        Why                        recordWhy = Why::Absent;
        const auto                 record    = loadQmOnce( qmetricsLoaded(), kPartQMetrics, "qmetrics", armed->rootKey, faults.noSum, readQmPayload, recordWhy );
        why = record == nullptr ? ( recordWhy == Why::Ok ? "absent" : kWhyNames[ std::size_t( recordWhy ) ] )
            : faults.anyDigest  ? nullptr
                                : firstMovedComponent( record->key, key, kQmKeyNames, faults );
        if( why == nullptr && record->symbolCount != S && !faults.anyDigest )
        {
            why = "shape";   // a symbol-count change moves the shape component first; said again where the arrays are sized
        }
        if( record != nullptr && why == nullptr )
        {
            q = sizedQMetrics( S );
            fillQMetricsDirect( ing, g, q );
            applyStoredQMetrics( *record, q );
            served = true;
            why    = "ok";
        }
        else
        {
            q = computeQMetricsComputed( ing, g );
            try
            {
                wrote = keepQMetrics( *armed, std::move( key ), q );
            }
            catch( ... )
            {
                DISCLOSE( Diagnostics::answerUnchanged, "a qmetrics record that could not be assembled is not written: the next run computes in full, as today" );
            }
        }
    }
    else
    {
        q = computeQMetricsComputed( ing, g );
    }
    if( memstats::enabled() )
    {
        rw::emitTo( stderr, "[verbfs] qmetrics served={} why={} symbols={} wrote={}{}{}\n", served ? 1 : 0, why, S, wrote ? 1 : 0, faults.name() != nullptr ? " fault=" : "",
                    faults.name() != nullptr ? faults.name() : "" );
    }
    return q;
}

// ── (5) IMPURE ═══════════════════════════════════════════════════════════════════════════════════════════════════════
struct ImRecord
{
    std::vector<std::uint64_t> key;
    std::uint64_t              symbolCount = 0;
    std::vector<char>          impure;   // one per symbol: 0 / 1
};

inline void writeImRecord( warmsnap::Out& o, const ImRecord& r )
{
    o.vec( r.key );
    o.u64( r.symbolCount );
    o.vec( r.impure );
}

inline bool readImPayload( std::string_view payload, ImRecord& r )
{
    warmsnap::In in{ payload };
    in.vec( r.key );
    r.symbolCount = in.u64();
    in.vec( r.impure );
    if( !VALIDATE( in.ok && in.left() == 0 && r.key.size() == std::size_t( ImKey::Count ) && r.impure.size() == r.symbolCount, "verbfs impure: the record's arrays disagree" ) )
    {
        return false;
    }
    return VALIDATE( std::ranges::all_of( r.impure, []( char c ) { return c == 0 || c == 1; } ), "verbfs impure: a stored flag is out of range" );
}

inline LoadedRecord<ImRecord>& impureLoaded() noexcept
{
    static LoadedRecord<ImRecord> slot;
    return slot;
}

inline bool keepImpure( const ArmedRoot& armed, std::vector<std::uint64_t> key, const std::vector<char>& impure )
{
    auto rec         = std::make_shared<ImRecord>();
    rec->key         = std::move( key );
    rec->symbolCount = impure.size();
    rec->impure      = impure;
    warmsnap::Out o  = beginRecord();
    writeImRecord( o, *rec );
    if( !commitQmRecord( kPartImpure, "impure", armed.rootKey, o ) )
    {
        return false;
    }
    replaceLoaded( impureLoaded(), std::shared_ptr<const ImRecord>( std::move( rec ) ) );
    return true;
}

inline std::vector<char> serveImpure( const IngestResult& ing, const Graph& g )
{
    const ArmedRoot* const armed = armedFor( ing );
    if( armed == nullptr )
    {
        return computeImpureComputed( ing, g );
    }
    const QmFaults             faults    = qmFaults();
    const std::size_t          S         = ing.symbols.size();
    std::vector<std::uint64_t> key       = impureKey( ing, g );
    Why                        recordWhy = Why::Absent;
    const auto                 record    = loadQmOnce( impureLoaded(), kPartImpure, "impure", armed->rootKey, faults.noSum, readImPayload, recordWhy );
    const char* why = record == nullptr ? ( recordWhy == Why::Ok ? "absent" : kWhyNames[ std::size_t( recordWhy ) ] )
                    : faults.anyDigest  ? nullptr
                                        : firstMovedComponent( record->key, key, kImKeyNames, faults );
    if( why == nullptr && record->symbolCount != S && !faults.anyDigest )
    {
        why = "shape";
    }
    bool              served = false, wrote = false;
    std::vector<char> impure;
    if( record != nullptr && why == nullptr )
    {
        impure.assign( S, 0 );
        std::copy_n( record->impure.begin(), std::min( S, record->impure.size() ), impure.begin() );   // equal sizes unless the any-digest mutant
        served = true;
        why    = "ok";
    }
    else
    {
        impure = computeImpureComputed( ing, g );
        try
        {
            wrote = keepImpure( *armed, std::move( key ), impure );
        }
        catch( ... )
        {
            DISCLOSE( Diagnostics::answerUnchanged, "an impure record that could not be assembled is not written: the next run computes in full, as today" );
        }
    }
    if( memstats::enabled() )
    {
        rw::emitTo( stderr, "[verbfs] impure served={} why={} symbols={} wrote={}{}{}\n", served ? 1 : 0, why, S, wrote ? 1 : 0, faults.name() != nullptr ? " fault=" : "",
                    faults.name() != nullptr ? faults.name() : "" );
    }
    return impure;
}

// ── arming ──────────────────────────────────────────────────────────────────────────────────────────────────────────
// Called by ingest() right after verbfs::arm, on the main thread before any verb runs: installs both seams exactly when that
// armed a root (so RIPWIRE_NO_VERBFS=1, and every run verbfs::arm is not called for, leaves them null).
inline void armQMetrics() noexcept
{
    if( !armedRoot().on )
    {
        return;
    }
    DerivedSeams& s = derivedSeams();
    s.qmetrics      = &serveQMetrics;
    s.impure        = &serveImpure;
}

}   // namespace rw::verbfs
