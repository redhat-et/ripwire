#pragma once
// verbfs_slotreg.h — SLOTREG: the two query-independent indexes a served --for rebuilt on every call, kept per index in
// the VERB-FS record family (src/verbfs.h; lane SLOTREG-PERSIST, 2026-11-25).
//
// WHY. On llvm-project a served warm --for spent 324 ms in rw::spliceSlotJoinRows (forslots.h) and 235 ms in
// rw::spliceRegRows (regindex.h) (results/PHASESPLIT_1125, lane 5b d76c740fb). Split by what reads the question:
//   * spliceRegRows builds RegIndex (every registry key, its registration sites, its consumers, and the names whose
//     re-export chain was cut) from the whole IngestResult; only the gate and the render after it read the question.
//     The whole index is query-independent. Part `regindex` keeps it.
//   * spliceSlotJoinRows builds a NARROW ValueRefIndex (valuerefindex.h narrowFor: the shown functions' values and every
//     slot store), so the value index itself is per question. Inside it, the first header-static question builds the
//     C-family #include adjacency (includeChainAdjOf, reversed: header -> the files that include it) from the whole
//     IngestResult: ~40 % of the phase on llvm (sample profile, results/SLOTREG_1125). Part `slotjoin` keeps it, and every
//     ValueRefIndex of the primary index (--uses, --callers, --callees as well) reads it through the same seam.
//
// THE KEY. Neither build reads the question, the clock or the disk beyond the crawled files; each reads a large share of
// the model (RegIndex::indexFacts walks every symbol, binding and reference). A digest of the fields they read, the way
// clones.h cloneInputDigest keys the clone groups, would walk the same 12.5 M references and 3.6 M bindings the build
// walks, so it would cost about what it saves. The model already has an identity that costs nothing: the warm snapshot
// serves a MODEL section only under (this build's source identity, the options key, the tree key) — warmsnap.h "WHEN IT
// IS SERVED": the producer's SHA-256 of src/ and queries/, every option, path spelling and RIPWIRE_/GIT_ environment
// variable, and a digest of every crawled file's path and content hash. A model is a function of those three, or the
// snapshot itself would serve a wrong model. So a record entry is keyed on
//     digest64( "slotreg/1", producer identity, optionsKey, treeKey, the five family sizes )
// and holds what these two builds return for that model. A build is a deterministic function of the model and the
// source (the determinism contract), so an equal key means an equal index. Any other key builds as before.
//
// WHICH INGESTRESULT. The key names a model; an entry may only be served for an IngestResult that IS that model. ingest()
// notes the key with the identity of the result's own row arrays (files, symbols, references, bindings, includes: data
// pointer and size) at the two places the snapshot vouches for it — the model it served (loadWarmModel), or a model it
// assembled from cache records alone under a tree key every file's content hash pins (the conditions recordWarmModel
// stores a model under: no re-parse, no memory stop, treeKeyValid) — and forgets it at the start of every ingest() in the
// process. A move keeps the arrays;
// a copy, a merge (multi-root), an --ignore-tests filter or any other ingest has other arrays or other sizes, and builds.
//
// WHAT A BUILD MAY READ. The tree key pins the content of every crawled file and nothing else, so a build is kept only
// when the process-wide dependency log (infra/depwatch.h, the graph section's own rule in warmsnap_graph.h) saw no read
// but whole-file reads of crawled files. A build that read a config (the whole-corpus include adjacency reads tsconfig
// files) is answered, and not kept: `nowrite=reads` on the stats line.
//
// FORMAT. verbfs.h's record file (header: magic, kVersion, the part, layout key, length, checksum) per part, holding up to
// kSlotRegEntriesKept entries, most recent first: a root alternates between the lean and the rich ingest, whose options
// keys differ. Every count read is bounded where it allocates; every id is checked against the model it is served to.
// The payload layout has no version of its own: the source identity is in the key, so a build whose layout differs never
// matches an entry another build wrote.
//
// STATS (RIPWIRE_STATS=1, stderr only): `[verbfs] slotreg index=<regindex|slotjoin> served=1 why=ok …` or
// `served=0 why=<absent|version|shape|checksum|key|model> built=1 wrote=<0|1>[ nowrite=<model|reads>]`.

#include "verbfs.h"
#include "verbfs_slotreg_seam.h"
#include "regindex.h"             // RegKey / RegSite — the stored keys are the index's own type
#include "infra/fileSetStore.h"   // FileAdjacency
#include "infra/hashutil.h"       // hashMix

#include <algorithm>
#include <cstdint>
#include <format>
#include <iterator>
#include <memory>
#include <mutex>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw::verbfs::slotreg
{

inline constexpr std::size_t kSlotRegEntriesKept = 2;   // the lean and the rich ingest of one root
inline constexpr std::uint8_t kWhyKey   = std::uint8_t( Why::Count );       // a record, but no entry for this model
inline constexpr std::uint8_t kWhyModel = std::uint8_t( Why::Count ) + 1;   // this IngestResult is not an identified model

// The two parts, found by NAME in verbfs.h's registration line, so a merge that reorders that list cannot misfile them.
consteval Part partNamed( std::string_view name )
{
    const auto at = std::ranges::find( kPartNames, name );
    return at == std::end( kPartNames ) ? Part( 0 ) : Part( std::uint32_t( at - std::begin( kPartNames ) ) );   // 0: the assert below names it
}
inline constexpr Part kPartRegIndex = partNamed( "regindex" );
inline constexpr Part kPartSlotJoin = partNamed( "slotjoin" );
static_assert( kPartRegIndex != Part( 0 ) && kPartSlotJoin != Part( 0 ), "register regindex and slotjoin in verbfs.h kPartNames" );

inline const char* whyName( std::uint8_t why ) noexcept
{
    return why == kWhyKey ? "key" : why == kWhyModel ? "model" : why < std::size( kWhyNames ) ? kWhyNames[ why ] : "?";
}

inline const char* faultName() noexcept
{
    return faultAnyKey() ? " fault=anykey" : faultEmptyRefused() ? " fault=emptyrefused" : faultStaleRows() ? " fault=stalerows" : "";
}

// ── the model identity ──────────────────────────────────────────────────────────────────────────────────────────────
struct ModelId
{
    bool          on  = false;
    std::uint64_t key = 0;
    const void*   rows[ 5 ]  = {};
    std::size_t   sizes[ 5 ] = {};
};

inline ModelId rowsOf( const IngestResult& ing ) noexcept
{
    ModelId id;
    const void*       rows[]  = { ing.files.data(), ing.symbols.data(), ing.references.data(), ing.bindings.data(), ing.includes.data() };
    const std::size_t sizes[] = { ing.files.size(), ing.symbols.size(), ing.references.size(), ing.bindings.size(), ing.includes.size() };
    std::ranges::copy( rows, id.rows );
    std::ranges::copy( sizes, id.sizes );
    return id;
}

// The one noted model, behind its own lock: ingest() may run on another thread (--quality-delta's HEAD index) while a verb reads it.
class NotedModel
{
public:
    void store( const ModelId& id )
    {
        const std::scoped_lock hold( m_guard );
        m_id = id;
    }
    ModelId load()
    {
        const std::scoped_lock hold( m_guard );
        return m_id;
    }

private:
    std::mutex m_guard;
    ModelId    m_id;
};

inline NotedModel& notedModel() noexcept
{
    static NotedModel noted;
    return noted;
}

// ingest() entry: whatever this call returns is not yet a model anyone has vouched for.
inline void forgetModel()
{
    notedModel().store( ModelId{} );
}

// ingest() exit, on the two paths the warm snapshot vouches for (see the note at the top).
inline void noteModel( const IngestResult& ing, const warmsnap::Session& snap )
{
    ModelId id = rowsOf( ing );
    id.on      = snap.on() && snap.treeKeyValid && ing.reparsedFiles == 0 && !ing.memoryStop.isSet();
    if( id.on )
    {
        warmsnap::Out o;
        o.str( "slotreg/1" );
        o.str( quality::producerIdentity() );
        o.u64( snap.optionsKey );
        o.u64( snap.treeKey );
        for( const std::size_t n : id.sizes )
        {
            o.u64( n );
        }
        id.key = depwatch::digest64( o.bytes );
    }
    notedModel().store( id.on ? id : ModelId{} );
}

// The key of `ing` when it is the noted model, else 0 with `found` false.
inline std::uint64_t modelKeyOf( const IngestResult& ing, bool& found )
{
    const ModelId now = rowsOf( ing );
    const ModelId id  = notedModel().load();
    found = id.on && std::ranges::equal( id.rows, now.rows ) && std::ranges::equal( id.sizes, now.sizes );
    return found ? id.key : 0;
}

inline void statsLine( std::string_view index, const Serve& tried, std::string_view detail )
{
    if( memstats::enabled() )
    {
        rw::emitTo( stderr, "[verbfs] slotreg index={} served={} why={}{}{}\n", index, tried.served ? 1 : 0, tried.served ? "ok" : whyName( tried.why ), detail, faultName() );
    }
}

// One part's record: where it lives in this process, and its payload's reader and writer.
template<class Rec>
struct PartIo
{
    LoadedRecord<Rec>& slot;
    Part               part;
    bool ( *parse )( std::string_view, Rec& );
    void ( *write )( warmsnap::Out&, const Rec& );
};

// The lookup both parts share: the armed root, the model key, the loaded record, and the entry for that key.
template<class Rec, class Entry = typename decltype( Rec::entries )::value_type>
inline const Entry* findEntry( const IngestResult& ing, const PartIo<Rec>& io, Serve& tried, std::shared_ptr<const Rec>& hold )
{
    const ArmedRoot* const armed = armedFor( ing );
    bool                   found = false;
    const std::uint64_t    key   = modelKeyOf( ing, found );
    if( armed == nullptr || ( !found && !faultAnyKey() ) )
    {
        tried.why = kWhyModel;
        return nullptr;
    }
    Why why = Why::Absent;
    hold    = loadOnce( io.slot, io.part, armed->rootKey, io.parse, why );
    if( hold == nullptr )
    {
        tried.why = std::uint8_t( why );
        return nullptr;
    }
    for( const Entry& e : hold->entries )
    {
        if( e.key == key || faultAnyKey() )
        {
            return &e;
        }
    }
    tried.why = kWhyKey;
    return nullptr;
}

// A refused record (version, shape, checksum) — the case the EMPTYREFUSED mutant answers as an empty index.
inline bool refused( const Serve& tried ) noexcept
{
    return tried.why == std::uint8_t( Why::Version ) || tried.why == std::uint8_t( Why::Shape ) || tried.why == std::uint8_t( Why::Checksum );
}

// The record write both parts share: the fresh entry first, then the stored ones of other models, up to the cap. "" when it
// wrote, else the stats line's reason.
template<class Rec, class Entry = typename decltype( Rec::entries )::value_type>
inline std::string_view keepEntry( const IngestResult& ing, const PartIo<Rec>& io, Entry fresh, bool readsPinned )
{
    const ArmedRoot* const armed = armedFor( ing );
    bool                   found = false;
    fresh.key                    = modelKeyOf( ing, found );
    if( armed == nullptr || !found )
    {
        return " wrote=0 nowrite=model";
    }
    if( !readsPinned )
    {
        return " wrote=0 nowrite=reads";
    }
    auto merged = std::make_shared<Rec>();
    Why  why    = Why::Absent;
    if( const auto old = loadOnce( io.slot, io.part, armed->rootKey, io.parse, why ) )
    {
        std::ranges::copy_if( old->entries | std::views::take( kSlotRegEntriesKept - 1 ), std::back_inserter( merged->entries ),
                              [ & ]( const Entry& e ) { return e.key != fresh.key; } );
    }
    merged->entries.insert( merged->entries.begin(), std::move( fresh ) );
    merged->entries.resize( std::min( merged->entries.size(), kSlotRegEntriesKept ) );
    warmsnap::Out o = beginRecord();
    io.write( o, *merged );
    if( !commitRecord( io.part, armed->rootKey, o ) )
    {
        return " wrote=0 nowrite=io";
    }
    replaceLoaded( io.slot, std::shared_ptr<const Rec>( std::move( merged ) ) );
    return " wrote=1";
}

// A counted family of rows, bounded where it allocates (crashsweepcheck S1); `one()` reads a row. False once `in` fails.
template<class T, class Fn>
inline bool readEach( warmsnap::In& in, std::size_t rowBytes, std::vector<T>& out, Fn&& one )
{
    const std::size_t n = in.count( rowBytes );
    if( n > in.left() )
    {
        in.ok = false;
        return false;
    }
    out.reserve( n );
    for( std::size_t i = 0; i < n && in.ok; ++i )
    {
        out.push_back( one() );
    }
    return in.ok;
}

// ═══ (1) the registrar index ═════════════════════════════════════════════════════════════════════════════════════════
struct RegEntry
{
    std::uint64_t            key = 0;
    std::vector<RegKey>      keys;
    std::vector<std::string> cut;
};

struct RegRecord
{
    std::vector<RegEntry> entries;
};

inline void writeRegRecord( warmsnap::Out& o, const RegRecord& r )
{
    o.each( r.entries, [ &o ]( const RegEntry& e )
    {
        o.u64( e.key );
        o.each( e.keys, [ &o ]( const RegKey& k )
        {
            o.u32( k.key );
            o.u32( k.registrar );
            o.each( k.sites, [ &o ]( const RegSite& s )
            {
                o.u32( s.registrarDef );
                o.u32( s.siteRef );
                o.str( s.registered );
                o.str( s.as );
                o.u32( s.key );
                o.u8( s.test ? 1 : 0 );
            } );
            o.vec( k.consumers );
            o.each( k.consumerTest, [ &o ]( bool test ) { o.u8( test ? 1 : 0 ); } );   // the u64 count and one byte each: what In::vec reads back
        } );
        o.strs( e.cut );
    } );
}

inline RegKey readRegKey( warmsnap::In& in )
{
    RegKey k;
    k.key       = in.u32();
    k.registrar = in.u32();
    readEach( in, 21, k.sites, [ &in ]   // a site's fixed part: four ids, two string lengths, the test flag
    {
        RegSite s;
        s.registrarDef = in.u32();
        s.siteRef      = in.u32();
        s.registered   = in.str();
        s.as           = in.str();
        s.key          = in.u32();
        s.test         = in.u8() != 0;
        return s;
    } );
    in.vec( k.consumers );
    std::vector<std::uint8_t> tests;
    in.vec( tests );
    if( !VALIDATE( tests.size() == k.consumers.size(), "verbfs: a registrar key's consumers and their test flags disagree" ) )
    {
        in.ok = false;
    }
    k.consumerTest.assign( tests.begin(), tests.end() );
    return k;
}

inline bool readRegRecord( std::string_view payload, RegRecord& r )
{
    warmsnap::In in{ payload };
    readEach( in, 24, r.entries, [ &in ]   // an entry's fixed part: its key and two counts
    {
        RegEntry e;
        e.key = in.u64();
        readEach( in, 32, e.keys, [ &in ] { return readRegKey( in ); } );   // a key's fixed part: two ids, three counts
        in.strs( e.cut );
        return e;
    } );
    return VALIDATE( in.ok && in.left() == 0 && r.entries.size() <= kSlotRegEntriesKept, "verbfs: the registrar record does not parse" );
}

inline LoadedRecord<RegRecord>& regLoaded() noexcept
{
    static LoadedRecord<RegRecord> slot;
    return slot;
}

inline PartIo<RegRecord> regIo() noexcept
{
    return { regLoaded(), kPartRegIndex, &readRegRecord, &writeRegRecord };
}

// Every id an entry names is one this index holds (the key matched, so this is a corruption guard, not a proof).
inline bool regEntryFits( const IngestResult& ing, const RegEntry& e ) noexcept
{
    const auto sym   = [ & ]( NodeId id ) { return id < ing.symbols.size(); };
    const auto symOr = [ & ]( NodeId id ) { return id == kNoNode || sym( id ); };
    return std::ranges::all_of( e.keys, [ & ]( const RegKey& k )
    {
        return sym( k.key ) && symOr( k.registrar ) && std::ranges::all_of( k.consumers, sym )
            && std::ranges::all_of( k.sites, [ & ]( const RegSite& s ) { return symOr( s.registrarDef ) && sym( s.key ) && s.siteRef < ing.references.size(); } );
    } ) && std::ranges::is_sorted( e.cut, rw::sortutil::svLess );
}

inline Serve serveReg( const IngestResult& ing, std::vector<RegKey>& keys, std::vector<std::string>& cut )
{
    Serve                            tried;
    std::shared_ptr<const RegRecord> hold;
    const RegEntry*                  hit = findEntry( ing, regIo(), tried, hold );
    if( hit != nullptr && !VALIDATE( faultAnyKey() || regEntryFits( ing, *hit ), "verbfs: a stored registrar key names an id this index does not hold" ) )
    {
        hit       = nullptr;
        tried.why = std::uint8_t( Why::Shape );
    }
    if( hit != nullptr )
    {
        keys         = hit->keys;
        cut          = hit->cut;
        tried.served = true;
        if( faultStaleRows() && !keys.empty() && !keys.back().sites.empty() )
        {
            keys.back().sites.pop_back();   // the mutant: rows that no longer match the model, as an in-place edit after ingest() would leave them
        }
        statsLine( "regindex", tried, std::format( " keys={} cut={}", keys.size(), cut.size() ) );
    }
    else if( faultEmptyRefused() && refused( tried ) )
    {
        tried.served = true;   // the mutant: a refused record answers as no keys at all
        statsLine( "regindex", tried, " keys=0 cut=0" );
    }
    return tried;
}

inline void keepReg( const IngestResult& ing, Serve tried, const std::vector<RegKey>& keys, const std::vector<std::string>& cut, bool readsPinned )
{
    const std::string_view wrote = keepEntry( ing, regIo(), RegEntry{ 0, keys, cut }, readsPinned );
    statsLine( "regindex", tried, std::format( " built=1{} keys={}", wrote, keys.size() ) );
}

// ═══ (2) the slot join's include adjacency ═══════════════════════════════════════════════════════════════════════════
struct JoinEntry
{
    std::uint64_t              key = 0;
    std::vector<std::uint32_t> off;   // files + 1 row offsets
    std::vector<std::uint32_t> tgt;   // the includers, row by row
};

struct JoinRecord
{
    std::vector<JoinEntry> entries;
};

inline void writeJoinRecord( warmsnap::Out& o, const JoinRecord& r )
{
    o.each( r.entries, [ &o ]( const JoinEntry& e )
    {
        o.u64( e.key );
        o.vec( e.off );
        o.vec( e.tgt );
    } );
}

inline bool readJoinRecord( std::string_view payload, JoinRecord& r )
{
    warmsnap::In in{ payload };
    readEach( in, 24, r.entries, [ &in ]   // an entry's fixed part: its key and two counts
    {
        JoinEntry e;
        e.key = in.u64();
        in.vec( e.off );
        in.vec( e.tgt );
        return e;
    } );
    return VALIDATE( in.ok && in.left() == 0 && r.entries.size() <= kSlotRegEntriesKept, "verbfs: the slot-join record does not parse" );
}

inline LoadedRecord<JoinRecord>& joinLoaded() noexcept
{
    static LoadedRecord<JoinRecord> slot;
    return slot;
}

inline PartIo<JoinRecord> joinIo() noexcept
{
    return { joinLoaded(), kPartSlotJoin, &readJoinRecord, &writeJoinRecord };
}

// A CSR of this index's file count whose offsets climb from 0 to the target count, every target a file of the index.
inline bool joinEntryFits( const IngestResult& ing, const JoinEntry& e ) noexcept
{
    const std::size_t files = ing.files.size();
    return e.off.size() == files + 1 && e.off.front() == 0 && e.off.back() == e.tgt.size() && std::ranges::is_sorted( e.off )
        && std::ranges::all_of( e.tgt, [ & ]( std::uint32_t t ) { return t < files; } );
}

inline Serve serveJoin( const IngestResult& ing, FileAdjacency& includers )
{
    Serve                             tried;
    std::shared_ptr<const JoinRecord> hold;
    const JoinEntry*                  hit = findEntry( ing, joinIo(), tried, hold );
    if( hit != nullptr && !VALIDATE( joinEntryFits( ing, *hit ), "verbfs: a stored include adjacency does not fit this index" ) )
    {
        hit       = nullptr;
        tried.why = std::uint8_t( Why::Shape );
    }
    const std::uint32_t files = std::uint32_t( ing.files.size() );
    if( hit != nullptr )
    {
        std::vector<std::uint32_t> from( hit->tgt.size() );
        for( std::uint32_t f = 0; f < files; ++f )
        {
            std::fill( from.begin() + hit->off[ f ], from.begin() + hit->off[ f + 1 ], f );
        }
        const std::size_t edges = faultStaleRows() && !from.empty() ? from.size() - 1 : from.size();   // the mutant drops the last edge
        includers               = FileAdjacency::fromEdges( files, std::span( from ).first( edges ), std::span( hit->tgt ).first( edges ), /*dedup=*/false );   // the stored rows, in their stored order
        tried.served = true;
        statsLine( "slotjoin", tried, std::format( " files={} edges={}", files, hit->tgt.size() ) );
    }
    else if( faultEmptyRefused() && refused( tried ) )
    {
        includers    = FileAdjacency( files );   // the mutant: a refused record answers as no include edges at all
        tried.served = true;
        statsLine( "slotjoin", tried, std::format( " files={} edges=0", files ) );
    }
    return tried;
}

inline void keepJoin( const IngestResult& ing, Serve tried, const FileAdjacency& includers, bool readsPinned )
{
    JoinEntry fresh;
    fresh.off.reserve( includers.size() + 1 );
    fresh.off.push_back( 0 );
    fresh.tgt.reserve( includers.edgeCount() );
    for( std::size_t f = 0; f < includers.size(); ++f )
    {
        std::ranges::copy( includers[ f ], std::back_inserter( fresh.tgt ) );
        fresh.off.push_back( std::uint32_t( fresh.tgt.size() ) );
    }
    const std::size_t      edges = fresh.tgt.size();
    const std::string_view wrote = keepEntry( ing, joinIo(), std::move( fresh ), readsPinned );
    statsLine( "slotjoin", tried, std::format( " built=1{} edges={}", wrote, edges ) );
}

// ── arming ──────────────────────────────────────────────────────────────────────────────────────────────────────────
// Beside verbfs::arm, in ingest(): only where VERB-FS armed (the kill switch, --no-cache and every unarmed run install nothing).
inline void arm() noexcept
{
    if( !armedRoot().on )
    {
        return;
    }
    Seams& s    = seams();
    s.regServe  = &serveReg;
    s.regKeep   = &keepReg;
    s.joinServe = &serveJoin;
    s.joinKeep  = &keepJoin;
}

}   // namespace rw::verbfs::slotreg
