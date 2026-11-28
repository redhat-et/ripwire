#pragma once
// warmsnap_graph.h — the GRAPH section of the warm snapshot (warmsnap.h): the resolved Graph, stored and loaded.
//
// EVERY field buildGraph computes is here, in declaration order, except three that are a pure per-symbol function of
// the model: canonId and localityKey are the largest strings in the graph (25 MB on vscode, more than the registered disk
// ceiling leaves), so readGraph recomputes them with buildGraph step 1a's two calls (canonicalId, localityKeyOf) — which
// the gate's byte identity holds to that step. pinCensus is never stored: a census run does not use the snapshot.
//
// A new Graph field that is not written here would load as its default — a wrong answer at exit 0. The size pin below
// turns that into a compile error on the build every lane runs.
#include "graph.h"
#include "warmsnap.h"
#include "infra/emit.h"   // rw::emitTo, faultSwitchOnOnce — RIPWIRE_STATS's `[warmsnap] deps` line, the DEPS-REREAD mutants
#include "memstats.h"     // memstats::enabled — RIPWIRE_STATS gates that line

namespace rw::warmsnap
{

#if defined( _LIBCPP_VERSION ) && defined( __LP64__ )
static_assert( sizeof( Graph ) == 1560, "Graph changed: store and load the new field in writeGraph / readGraph below, bump warmsnap::kVersion, then re-pin this size" );
#endif

// A per-symbol array almost every symbol leaves at zero (ambOut, declinedOut, ...): its size, then the non-zero rows.
inline void writeSparse( Out& o, const std::vector<std::uint32_t>& v )
{
    std::vector<std::uint32_t> at, value;
    for( std::size_t i = 0; i < v.size(); ++i )
    {
        if( v[ i ] != 0 )
        {
            at.push_back( std::uint32_t( i ) );
            value.push_back( v[ i ] );
        }
    }
    o.u64( v.size() );
    o.vec( at );
    o.vec( value );
}
inline void readSparse( In& in, std::vector<std::uint32_t>& v, std::size_t limit )
{
    const std::uint64_t        size = in.u64();
    std::vector<std::uint32_t> at, value;
    in.vec( at );
    in.vec( value );
    if( !VALIDATE( in.ok && size <= limit && at.size() == value.size() && std::ranges::all_of( at, [ & ]( std::uint32_t i ) { return i < size; } ),
                   "warmsnap: a sparse array's rows lie outside it" ) )
    {
        in.ok = false;
        return;
    }
    v.assign( std::size_t( size ), 0u );
    for( std::size_t k = 0; k < at.size(); ++k ) { v[ at[ k ] ] = value[ k ]; }
}

// A per-symbol list almost every symbol leaves empty (implementors, mentions): the row count, then the non-empty rows.
template <class T>
inline void writeNested( Out& o, const std::vector<std::vector<T>>& rows )
{
    std::vector<std::uint32_t> at, length;
    std::vector<T>             flat;
    for( std::size_t i = 0; i < rows.size(); ++i )
    {
        if( !rows[ i ].empty() )
        {
            at.push_back( std::uint32_t( i ) );
            length.push_back( std::uint32_t( rows[ i ].size() ) );
            flat.insert( flat.end(), rows[ i ].begin(), rows[ i ].end() );
        }
    }
    o.u64( rows.size() );
    o.vec( at );
    o.vec( length );
    o.vec( flat );
}
template <class T>
inline void readNested( In& in, std::vector<std::vector<T>>& rows, std::size_t limit )
{
    const std::uint64_t        size = in.u64();
    std::vector<std::uint32_t> at, length;
    std::vector<T>             flat;
    in.vec( at );
    in.vec( length );
    in.vec( flat );
    rows.clear();
    if( !VALIDATE( in.ok && size <= limit && at.size() == length.size(), "warmsnap: a nested array's row table does not parse" ) )
    {
        in.ok = false;
        return;
    }
    rows.resize( std::size_t( size ) );
    std::size_t from = 0;
    for( std::size_t k = 0; k < at.size(); ++k )
    {
        if( !VALIDATE( at[ k ] < size && length[ k ] <= flat.size() - from, "warmsnap: a nested row lies outside its array" ) )
        {
            in.ok = false;
            return;
        }
        rows[ at[ k ] ].assign( flat.begin() + std::ptrdiff_t( from ), flat.begin() + std::ptrdiff_t( from + length[ k ] ) );
        from += length[ k ];
    }
}

// The default map's PageRank — uniform teleport, the one rank that is a function of the Graph alone — stored beside the
// graph it ranks and handed to the one call site that asks for exactly that (main.cpp, the default rank). A query-dependent
// rank (--for's personalization, churn, --map-diff) is never stored: its teleport is not the graph's.
inline std::optional<RankedGraph>& storedDefaultRank() noexcept
{
    static std::optional<RankedGraph> rank;
    return rank;
}
inline RankedGraph defaultRank( const Graph& g )
{
    std::optional<RankedGraph>& stored = storedDefaultRank();
    if( stored && stored->rank.size() == g.wOutDeg.size() )
    {
        RankedGraph rank = std::move( *stored );
        stored.reset();
        return rank;
    }
    return rankGraph( g );
}

// ── the dependency rows (DEPS-REREAD) ───────────────────────────────────────────────────────────────────────────────
// Every read the resolver made outside the parse cache is stored with what it answered and is REPEATED on every served
// run (depsStillAnswer). On llvm-project that is 7,838 files — in-tree headers the C++ contract and typedef checks read
// through readConfigBytes — and repeating them one after another was 132 ms of readGraph's 184 ms (PHASESPLIT_1125).
//
// A content row (Seam::WholeFile, Seam::ConfigBytes) also stores the stat signature its file had right after the build,
// under THE ONE IDENTITY RULE the parse cache's stat gate and verbfs.h use, not a new one: a signature is kept only when
// it is SETTLED — mtime and ctime both older than kRacySlackNs before the recording run began (Session::startNs). The
// signature is taken after the log is disarmed, so after every read it vouches for: a run starts at S, reads at R >= S,
// stats at A >= R. Settled at A means no write touched the object after S - 2 s (a write moves ctime to its own time,
// and no file system in use keeps a coarser granule than 2 s), so the bytes read at R are the bytes that signature
// names. A later run that finds the same signature finds the same object, unwritten since: ctime cannot be set back by
// an unprivileged writer (`touch -r` and `cp -p` restore mtime and move ctime), and a file replaced by rename, or a
// symlink retargeted (the signature follows links, as both seams do), is another inode. So the repeated read would
// answer what it answered then, and is skipped. Everything else is read and digested exactly as before:
//   - no signature kept (StatSig{}): the row was unsettled when recorded (the racy case), or its file could not be
//     stat'd, or the read found nothing (WholeFile kAbsent; ConfigBytes' empty answer, which is also how it reads an
//     unreadable or oversize file) — those reads cost an open, and the empty answer is the one a process's own
//     permissions could change without the file moving;
//   - a signature that differs now, or a stat that now fails (deleted, a dangling link, a parent that went away);
//   - the two existence probes, which are one stat already.
// Outside the rule, as outside the parse cache's gate: a clock moved backward, raw block-device writes, a file system
// with no distinct ctime, and a file another process context of the same user cannot read though nothing about it moved.
inline constexpr std::size_t kDepRowMinBytes = sizeof( std::uint32_t ) + 1 + sizeof( std::uint64_t ) + sizeof( StatSig );   // empty path, seam, answer, signature

inline bool depReadsContent( depwatch::Seam seam ) noexcept
{
    return seam == depwatch::Seam::WholeFile || seam == depwatch::Seam::ConfigBytes;
}

// The DEPS-REREAD mutants (non-NDEBUG; test/depsrereadcheck.sh turns each arm red with one). Each breaks ONE clause above.
struct FaultDepsRacy {};       // RIPWIRE_FAULT_WARMSNAP_DEPS_RACY: keep a signature that is not settled
struct FaultDepsSizeMtime {};  // RIPWIRE_FAULT_WARMSNAP_DEPS_SIZEMTIME: compare size and mtime only (no inode, device, ctime)
struct FaultDepsGone {};       // RIPWIRE_FAULT_WARMSNAP_DEPS_GONE: read a stat that now fails as "unchanged"
struct FaultDepsNoSig {};      // RIPWIRE_FAULT_WARMSNAP_DEPS_NOSIG: skip a row stored with no signature

// One stored dependency row: the read, and its file's settled signature or StatSig{} (see above).
struct RecordedDep
{
    depwatch::Dep dep;
    StatSig       sig;
};

// Each row with what its file looks like now, after the build that read it.
inline std::vector<RecordedDep> withSettledSigs( const Session& s, std::vector<depwatch::Dep>&& deps )
{
    PROFILE_SCOPE_DESCRIBE( "warmsnap: stat the resolver's recorded reads" );
    std::vector<RecordedDep> rows( deps.size() );
    const long long          racyFrom  = s.startNs - kRacySlackNs;
    const bool               keepYoung = rw::faultSwitchOnOnce<FaultDepsRacy>( "RIPWIRE_FAULT_WARMSNAP_DEPS_RACY" );
    const std::uint64_t      emptyRead = depwatch::digest64( {} );
    parallelFor( deps.size(), [ & ]( std::size_t i ) noexcept
    {
        rows[ i ].dep            = std::move( deps[ i ] );
        const depwatch::Dep& d   = rows[ i ].dep;
        const bool readSomething = d.seam == depwatch::Seam::WholeFile ? d.answer != depwatch::kAbsent : d.answer != emptyRead;
        if( !depReadsContent( d.seam ) || !readSomething )
        {
            return;
        }
        const StatSig sig = statSig( d.path.c_str(), true );
        if( sig.size >= 0 && ( keepYoung || ( sig.mtimeNs < racyFrom && sig.ctimeNs < racyFrom ) ) )
        {
            rows[ i ].sig = sig;
        }
    } );
    return rows;
}

// True when row `stored`'s file provably still holds the bytes its read answered — the read may be skipped.
inline bool depUnmoved( const StatSig& stored, const std::string& path ) noexcept
{
    if( stored == StatSig{} )
    {
        return rw::faultSwitchOnOnce<FaultDepsNoSig>( "RIPWIRE_FAULT_WARMSNAP_DEPS_NOSIG" );   // nothing kept: always read
    }
    const StatSig now = statSig( path.c_str(), true );
    if( now.size < 0 && rw::faultSwitchOnOnce<FaultDepsGone>( "RIPWIRE_FAULT_WARMSNAP_DEPS_GONE" ) )
    {
        return true;
    }
    if( rw::faultSwitchOnOnce<FaultDepsSizeMtime>( "RIPWIRE_FAULT_WARMSNAP_DEPS_SIZEMTIME" ) )
    {
        return now.size == stored.size && now.mtimeNs == stored.mtimeNs;
    }
    return now == stored;   // a stored signature is never the failed-stat one (size -1), so a stat that fails now never matches
}

// The GRAPH section, into `o` (a streaming Out on a recording run: warmsnap.h recordSection).
inline void writeGraph( Out& o, const Graph& g, const IngestResult& ing, const std::vector<RecordedDep>& deps, const RankedGraph& rank )
{
    PROFILE_SCOPE_DESCRIBE( "warmsnap: serialize the graph section" );
    o.u64( ing.symbols.size() );
    o.u64( ing.files.size() );
    o.u64( ing.references.size() );
    // the files the resolver read outside the parse cache, what each read answered, and the file's settled signature
    o.each( deps, [ & ]( const RecordedDep& d ) { o.str( d.dep.path ); o.u8( std::uint8_t( d.dep.seam ) ); o.u64( d.dep.answer ); o.pod( d.sig ); } );

    o.u64( g.inEdges.rows() );
    o.u64( g.inEdges.cols() );
    o.rows( g.inEdges.rowOffsets(), g.inEdges.rowOffsets() != nullptr ? g.inEdges.rows() + 1 : 0 );
    o.rows( g.inEdges.colIndices(), g.inEdges.nnz() );
    o.rows( g.inEdges.values(), g.inEdges.nnz() );
    o.vec( g.wOutDeg );
    o.vec( g.outOff );
    o.vec( g.outTargets );
    o.vec( g.outVals );
    o.vec( g.outProv );
    o.vec( g.outNameOnly );
    o.vec( g.outAnchorMiss );
    writeNested( o, g.implementors );
    writeNested( o, g.implementorBound );
    o.vec( g.baseOutsideClauses );
    o.vec( g.rubyMainMixins );
    writeNested( o, g.mentions );
    writeSparse( o, g.ambOut );
    writeSparse( o, g.unresolvedOut );
    writeSparse( o, g.locPinOut );
    o.u64( g.unindexedFiles );
    o.u64( g.rubyBasesUnscoped );
    {
        std::vector<std::uint32_t> from, to;
        for( std::size_t f = 0; f < g.importAdj.size(); ++f )
        {
            for( const std::uint32_t t : g.importAdj[ f ] )
            {
                from.push_back( std::uint32_t( f ) );
                to.push_back( t );
            }
        }
        o.u64( g.importAdj.size() );
        o.vec( from );
        o.vec( to );
    }
    o.u64( g.externalCalls );
    writeSparse( o, g.declinedOut );
    o.u64( g.inertDeclinedCalls );
    o.vec( g.inertDeclinedCaller );
    o.vec( g.declinedListOff );
    o.vec( g.declinedListCand );
    o.vec( g.declinedListCallCount );
    o.vec( g.declinedSiteCaller );
    o.vec( g.declinedSiteList );
    o.vec( g.declinedSiteRef );
    o.vec( g.declinedSiteKind );
    o.u64( g.declinedSiteBound.size() );
    for( const auto& [ record, text ] : g.declinedSiteBound ) { o.u32( record ); o.str( text ); }
    o.vec( g.gateDeclinedTarget );
    o.u64( g.gateDeclinedCalls );
    o.u64( g.stdMemberDeclinedCalls );
    o.u64( g.stdMemberDeclines.size() );
    for( const auto& [ caller, name ] : g.stdMemberDeclines ) { o.u32( caller ); o.pod( name ); }
    o.u64( g.unresolvedSites.size() );   // CALLEE-GAP: the callees answer's <unres> line
    for( const auto& [ caller, ref ] : g.unresolvedSites ) { o.u32( caller ); o.u32( ref ); }
    o.vec( g.keptForwards );
    o.vec( g.provenSites );
    o.pod( g.callDispositions );
    o.u64( g.composeEdges.size() );
    for( const ComposeEdge& e : g.composeEdges ) { o.u32( e.ownerSym ); o.u32( e.typeSym ); o.str( e.fieldName ); o.str( e.typeName ); o.str( e.ownerName ); o.str( e.rel ); }
    o.u64( g.routeEdges.size() );
    for( const RouteEdge& e : g.routeEdges ) { o.u32( e.fromSym ); o.u32( e.toSym ); o.u8( std::uint8_t( e.method ) ); o.str( e.path ); o.str( e.fromName ); o.str( e.toName ); }
    o.u64( g.bindLabel.rows.size() );
    for( const auto& [ id, label ] : g.bindLabel.rows ) { o.u32( id ); o.str( label ); }
    o.u32( g.unrankedNodeCount );
    o.vec( g.priorWeight );
    o.vec( rank.rank );
    o.u32( rank.iterationCount );
    o.u8( rank.hasConverged ? 1 : 0 );
    o.u64( 0x454e'4447'5241'5048ull );   // the end mark: a reader that consumed a different shape does not land on it
}

// One recorded read repeated through the seam that made it: what it answers now. An unknown seam answers nothing.
inline std::optional<std::uint64_t> repeatDepRead( depwatch::Seam seam, const std::string& path )
{
    switch( seam )
    {
        case depwatch::Seam::WholeFile:
        {
            const std::optional<std::string> bytes = docparse::detail::readWholeFile( path );
            return bytes ? depwatch::digest64( *bytes ) : depwatch::kAbsent;
        }
        case depwatch::Seam::ConfigBytes:
        {
            return depwatch::digest64( readConfigBytes( path ) );
        }
        case depwatch::Seam::StatExists:
        {
            os::stat_t st;
            return os::stat( path.c_str(), &st ) == 0 ? depwatch::kPresent : depwatch::kAbsent;
        }
        case depwatch::Seam::FsExists:
        {
            std::error_code ec;
            return std::filesystem::exists( path, ec ) ? depwatch::kPresent : depwatch::kAbsent;
        }
        default:
        {
            return std::nullopt;
        }
    }
}

// Every read the recorded build made outside the parse cache still answers what it answered: each is repeated through
// its seam unless its stored signature proves the file unmoved (the rule above writeGraph). All rows are decoded, then
// checked on parallelFor — each slot its own, so the verdict (every row agrees) and the counts do not depend on timing,
// and every row is checked even after one disagrees, so the stats line is a function of the tree alone.
inline bool depsStillAnswer( In& in )
{
    PROFILE_SCOPE_DESCRIBE( "warmsnap: repeat the resolver's recorded reads" );
    struct Row
    {
        std::string   path;
        std::uint64_t answer = 0;
        StatSig       sig;
        std::uint8_t  seam   = 0;
    };
    const std::size_t n = in.count( kDepRowMinBytes );
    if( n > in.left() ) { in.ok = false; return false; }   // count() already held n to the bytes left: said again where the allocation is
    std::vector<Row> rows;
    rows.reserve( n );
    for( std::size_t i = 0; i < n && in.ok; ++i )
    {
        Row r;
        r.path   = in.str();
        r.seam   = in.u8();
        r.answer = in.u64();
        r.sig    = in.pod<StatSig>();
        rows.push_back( std::move( r ) );
    }
    if( !in.ok )
    {
        return false;
    }
    enum Outcome : std::uint8_t { Skipped, Read, Probed };
    std::vector<std::uint8_t> outcome( rows.size(), Read );
    std::atomic<bool>         moved{ false };
    parallelFor( rows.size(), [ & ]( std::size_t i )
    {
        const Row&           r    = rows[ i ];
        const depwatch::Seam seam = depwatch::Seam( r.seam );
        if( depReadsContent( seam ) && depUnmoved( r.sig, r.path ) )
        {
            outcome[ i ] = Skipped;
            return;
        }
        outcome[ i ] = depReadsContent( seam ) ? Read : Probed;
        if( const std::optional<std::uint64_t> now = repeatDepRead( seam, r.path ); !now || *now != r.answer )
        {
            moved.store( true, std::memory_order_relaxed );
        }
    } );
    if( memstats::enabled() )
    {
        const auto tally = [ & ]( Outcome o ) { return std::ranges::count( outcome, std::uint8_t( o ) ); };
        rw::emitTo( stderr, "[warmsnap] deps rows={} read={} probed={} skipped={}\n", rows.size(), tally( Read ), tally( Probed ), tally( Skipped ) );
    }
    return !moved.load();
}

// The stored graph, or nothing: `s.why` then says which guard refused it.
inline std::optional<Graph> readGraph( Session& s, const IngestResult& ing )
{
    PROFILE_SCOPE_DESCRIBE( "warmsnap: load the graph section" );
    const auto refuse = [ & ]( Why w ) noexcept -> std::optional<Graph>
    {
        s.graphWhy = w;
        s.refuse( w );
        return std::nullopt;
    };
    if( !s.fileOk || s.graphSection.empty() )
    {
        return refuse( s.fileOk ? Why::NoSection : s.why );
    }
    if( !s.treeKeyValid || s.fileTreeKey != s.treeKey )
    {
        return refuse( Why::Stale );
    }
    if( !sectionIntact( s, Sec::Graph ) )
    {
        return refuse( Why::Checksum );
    }
    In in{ s.graphSection };
    const std::size_t N = ing.symbols.size();
    const std::uint64_t symbolCount = in.u64(), fileCount = in.u64(), referenceCount = in.u64();
    if( !VALIDATE( symbolCount == N && fileCount == ing.files.size() && referenceCount == ing.references.size(), "warmsnap: the graph section describes another model" ) )
    {
        return refuse( Why::Stale );
    }
    if( !depsStillAnswer( in ) )
    {
        return refuse( in.ok ? Why::Dep : Why::Checksum );
    }
    Graph g;
    {
        const std::size_t rows = std::size_t( in.u64() );
        const std::size_t cols = std::size_t( in.u64() );
        std::vector<std::uint32_t> rowOff, col;
        std::vector<float>         val;
        in.vec( rowOff );
        in.vec( col );
        in.vec( val );
        if( !VALIDATE( in.ok && rows == N && cols == N && col.size() == val.size() && ( rowOff.empty() ? col.empty() : rowOff.size() == rows + 1 && rowOff.back() == col.size() ),
                       "warmsnap: the in-edge CSR's shape does not fit the model" ) )
        {
            return refuse( Why::Checksum );
        }
        if( !rowOff.empty() )
        {
            g.inEdges = sparseCsr<float>( rows, cols, col.size() );
            std::memcpy( g.inEdges.rowOffsets(), rowOff.data(), rowOff.size() * sizeof( std::uint32_t ) );
            if( !col.empty() )
            {
                std::memcpy( g.inEdges.colIndices(), col.data(), col.size() * sizeof( std::uint32_t ) );
                std::memcpy( g.inEdges.values(), val.data(), val.size() * sizeof( float ) );
            }
        }
    }
    in.vec( g.wOutDeg );
    in.vec( g.outOff );
    in.vec( g.outTargets );
    in.vec( g.outVals );
    in.vec( g.outProv );
    in.vec( g.outNameOnly );
    in.vec( g.outAnchorMiss );
    readNested( in, g.implementors, N );
    readNested( in, g.implementorBound, N );
    in.vec( g.baseOutsideClauses );
    in.vec( g.rubyMainMixins );
    readNested( in, g.mentions, N );
    readSparse( in, g.ambOut, N );
    readSparse( in, g.unresolvedOut, N );
    readSparse( in, g.locPinOut, N );
    g.unindexedFiles    = std::size_t( in.u64() );
    g.rubyBasesUnscoped = std::size_t( in.u64() );
    {
        const std::uint64_t        adjFiles = in.u64();
        std::vector<std::uint32_t> from, to;
        in.vec( from );
        in.vec( to );
        const bool fits = in.ok && adjFiles <= ing.files.size() && from.size() == to.size()
                       && std::ranges::all_of( from, [ & ]( std::uint32_t f ) { return f < adjFiles; } );
        if( !VALIDATE( fits, "warmsnap: the import adjacency does not fit the model" ) )
        {
            return refuse( Why::Checksum );
        }
        if( adjFiles != 0 )
        {
            g.importAdj = rw::FileAdjacency::fromEdges( std::uint32_t( adjFiles ), from, to, /*dedup=*/false );   // a stable counting sort: each row keeps its stored order
        }
    }
    g.externalCalls      = std::size_t( in.u64() );
    readSparse( in, g.declinedOut, N );
    g.inertDeclinedCalls = std::size_t( in.u64() );
    in.vec( g.inertDeclinedCaller );
    in.vec( g.declinedListOff );
    in.vec( g.declinedListCand );
    in.vec( g.declinedListCallCount );
    in.vec( g.declinedSiteCaller );
    in.vec( g.declinedSiteList );
    in.vec( g.declinedSiteRef );
    {
        std::vector<std::uint8_t> kinds;
        in.vec( kinds );
        g.declinedSiteKind.resize( kinds.size() );
        std::ranges::transform( kinds, g.declinedSiteKind.begin(), []( std::uint8_t k ) { return DeclinedSiteKind( k ); } );
    }
    for( std::size_t i = 0, n = in.count( 8 ); i < n && in.ok; ++i )
    {
        const std::uint32_t record = in.u32();
        g.declinedSiteBound.emplace_back( record, in.str() );
    }
    in.vec( g.gateDeclinedTarget );
    g.gateDeclinedCalls      = std::size_t( in.u64() );
    g.stdMemberDeclinedCalls = std::size_t( in.u64() );
    for( std::size_t i = 0, n = in.count( 6 ); i < n && in.ok; ++i )
    {
        const NodeId caller = in.u32();
        g.stdMemberDeclines.emplace_back( caller, in.pod<std::uint16_t>() );
    }
    for( std::size_t i = 0, n = in.count( 8 ); i < n && in.ok; ++i )
    {
        const NodeId caller = in.u32();
        g.unresolvedSites.emplace_back( caller, in.u32() );
    }
    in.vec( g.keptForwards );
    in.vec( g.provenSites );
    g.callDispositions = in.pod<CallDispositionCounts>();
    for( std::size_t i = 0, n = in.count( 24 ); i < n && in.ok; ++i )
    {
        ComposeEdge e;
        e.ownerSym  = in.u32();
        e.typeSym   = in.u32();
        e.fieldName = in.str();
        e.typeName  = in.str();
        e.ownerName = in.str();
        e.rel       = in.str();
        g.composeEdges.push_back( std::move( e ) );
    }
    for( std::size_t i = 0, n = in.count( 21 ); i < n && in.ok; ++i )
    {
        RouteEdge e;
        e.fromSym = in.u32();
        e.toSym   = in.u32();
        const std::uint8_t method = in.u8();
        if( !VALIDATE( method < kHttpMethodCount, "warmsnap: an HTTP method this build does not know" ) ) { in.ok = false; }
        e.method   = HttpMethod( method );
        e.path     = in.str();
        e.fromName = in.str();
        e.toName   = in.str();
        g.routeEdges.push_back( std::move( e ) );
    }
    for( std::size_t i = 0, n = in.count( 8 ); i < n && in.ok; ++i )
    {
        const NodeId id = in.u32();
        g.bindLabel.add( id, in.str() );
    }
    g.unrankedNodeCount = in.u32();
    in.vec( g.priorWeight );
    RankedGraph rank;
    in.vec( rank.rank );
    rank.iterationCount = in.u32();
    rank.hasConverged   = in.u8() != 0;
    const std::uint64_t endMark = in.u64();
    // every id an answer will index with lies inside the family it indexes: a section that parses may still not be this model's
    const auto symbolIds = [ & ]( const auto& ids ) { return std::ranges::all_of( ids, [ & ]( NodeId id ) { return id < N; } ); };
    const auto refIds    = [ & ]( const auto& ids ) { return std::ranges::all_of( ids, [ & ]( std::uint32_t id ) { return id < ing.references.size(); } ); };
    const auto nestedIds = [ & ]( const std::vector<std::vector<NodeId>>& rows ) { return std::ranges::all_of( rows, symbolIds ); };
    const auto unresolvedSitesIn = [ & ]( const std::vector<std::pair<NodeId, std::uint32_t>>& sites )
    {
        return std::ranges::is_sorted( sites ) && std::ranges::all_of( sites, [ & ]( const auto& p ) { return p.first < N && p.second < ing.references.size(); } );
    };
    const auto provenSitesIn = [ & ]( const std::vector<ProvenSite>& sites )
    {
        return std::ranges::is_sorted( sites ) && std::ranges::all_of( sites, [ & ]( const ProvenSite& p ) { return p.ref < ing.references.size() && p.target < N; } );
    };
    const bool inRange = in.ok && symbolIds( g.outTargets ) && symbolIds( std::span<const std::uint32_t>( g.inEdges.colIndices(), g.inEdges.nnz() ) ) && nestedIds( g.implementors )
                      && nestedIds( g.mentions ) && refIds( g.declinedSiteRef ) && refIds( g.keptForwards ) && provenSitesIn( g.provenSites ) && refIds( g.baseOutsideClauses ) && symbolIds( g.declinedSiteCaller )
                      && symbolIds( g.declinedListCand ) && symbolIds( g.inertDeclinedCaller ) && std::ranges::is_sorted( g.outOff ) && std::ranges::is_sorted( g.declinedListOff )
                      && !g.declinedListOff.empty() && g.declinedListOff.back() == g.declinedListCand.size() && g.declinedListCallCount.size() + 1 == g.declinedListOff.size()
                      && g.declinedSiteList.size() == g.declinedSiteCaller.size() && g.declinedSiteRef.size() == g.declinedSiteCaller.size()
                      && g.declinedSiteKind.size() == g.declinedSiteCaller.size() && unresolvedSitesIn( g.unresolvedSites ) && ( g.outVals.empty() || g.outVals.size() == g.outTargets.size() )
                      && ( g.outProv.empty() || g.outProv.size() == g.outTargets.size() ) && ( g.outNameOnly.empty() || g.outNameOnly.size() == g.outTargets.size() )
                      && ( g.outAnchorMiss.empty() || g.outAnchorMiss.size() == g.outTargets.size() ) && g.implementorBound.size() <= N
                      && ( g.priorWeight.empty() || g.priorWeight.size() == N ) && ( g.gateDeclinedTarget.empty() || g.gateDeclinedTarget.size() == N );
    const bool sized = inRange && rank.rank.size() == N && endMark == 0x454e'4447'5241'5048ull && in.p == in.e && g.wOutDeg.size() == N && g.ambOut.size() == N && g.unresolvedOut.size() == N
                    && g.locPinOut.size() == N && g.declinedOut.size() == N && ( g.outOff.empty() ? g.outTargets.empty() : g.outOff.size() == N + 1 && g.outOff.back() == g.outTargets.size() );
    if( !VALIDATE( sized, "warmsnap: the graph section does not parse to this model's shape" ) )
    {
        return refuse( Why::Checksum );
    }
    // canonId and localityKey: buildGraph step 1a's two assignments, per symbol and independent, so here on every core
    g.canonId.resize( N );
    g.localityKey.resize( N );
    parallelFor( N, [ & ]( std::size_t i )
    {
        const Symbol& sym = ing.symbols[ i ];
        g.canonId[ i ]    = canonicalId( ing.files[ sym.fileId ], sym.scope, sym.name );
        if( sym.scope.empty() ) { g.localityKey[ i ] = localityKeyOf( ing.files[ sym.fileId ], sym.scope, sym.name ); }
    } );
    storedDefaultRank() = std::move( rank );
    s.graphLoaded = true;
    s.graphWhy    = Why::Ok;
    return g;
}

// Run buildGraph with the dependency log armed and turn its outcome into the GRAPH section. Reads of crawled files are
// dropped from the log: the tree key already pins their content. An unrecordable log stores nothing.
inline Graph buildGraphRecorded( Session& s, const IngestResult& ing )
{
    depwatch::Log log;
    Graph g = [ & ]
    {
        const depwatch::Armed armed( &log );
        return buildGraph( ing, nullptr, false );
    }();
    if( !s.on() || s.blobUnpublished || !mayStoreBuilt( s, ing.reparsedFiles, ing.memoryStop.isSet() ) )   // the edit rule: warmsnap.h recordsWhatItBuilt; a failed blob write stores nothing (as for MODEL)
    {
        return g;
    }
    std::vector<depwatch::Dep> deps;
    for( depwatch::Dep& d : log.deps )
    {
        if( d.seam == depwatch::Seam::Count )
        {
            return g;
        }
        if( d.seam != depwatch::Seam::WholeFile || !std::binary_search( ing.files.begin(), ing.files.end(), d.path ) )
        {
            deps.push_back( std::move( d ) );
        }
    }
    // one row per (seam, path, answer): a path read twice with one answer is one fact, and the order the resolver happened to read in is not one
    std::ranges::sort( deps, []( const depwatch::Dep& a, const depwatch::Dep& b ) { return std::tie( a.seam, a.path, a.answer ) < std::tie( b.seam, b.path, b.answer ); } );
    deps.erase( std::unique( deps.begin(), deps.end(), []( const depwatch::Dep& a, const depwatch::Dep& b ) { return a.seam == b.seam && a.path == b.path && a.answer == b.answer; } ), deps.end() );
    RankedGraph rank = rankGraph( g );   // once, on the run that records: this run's own map takes it from the slot too
    const std::vector<RecordedDep> rows = withSettledSigs( s, std::move( deps ) );   // stat'd now, after the build that read them
    recordSection( s, Sec::Graph, [ & ]( Out& o ) { writeGraph( o, g, ing, rows, rank ); } );
    storedDefaultRank() = std::move( rank );
    return g;
}

}   // namespace rw::warmsnap
