#pragma once
// warmsnap_model.h — the MODEL section of the warm snapshot (warmsnap.h): the assembled IngestResult, stored whole.
//
// WHAT A LOAD SKIPS. On a tree the TREE section vouches for, ingest() returns this instead of opening the parse cache:
// no record is read or decoded, no definition is deduplicated, no reference sorted or attributed, no post-pass run.
// Every family is here — symbols, fields, references, bindings, includes, the side tables — so every verb reads the
// model it always read; there is no "light" model and no list of verbs that may use it.
//
// LAYOUT: fat, fixed-stride rows (the owner's ruling: spend disk and resident bytes for CPU). A family whose rows hold
// pool ids (Reference, Binding) is a raw row array over ONE name table: each distinct text is stored once, interned
// once at load (in parallel — TextPool::intern is sharded), and a row is then filled with no hashing at all. Pool ids
// themselves never reach the file: they are a property of one process.
//
// WHEN IT IS SERVED. Only after replayTree() succeeded in this run (every crawled file still carries the signature
// recorded when this model was built from it), only while the parse cache blob still carries ITS recorded signature
// (so "the blob was deleted" or "another configuration rewrote it" is a cold run, as it always was), and never for a
// tree holding a document a bridge extracts (its text depends on whether markitdown ran, not on the tree).
//
// A new IngestResult field that is not stored here would load as its default. The size pin below makes that a compile
// error; the fields deliberately NOT stored are listed at it.
#include "warmsnap.h"

#include "scip.h"     // scipwire::Reader::varint

#include <numeric>   // std::iota
#include "docparse.h"   // markitdownMayRun: a bridge document's text depends on it

namespace rw::warmsnap
{

#if defined( _LIBCPP_VERSION ) && defined( __LP64__ )
// Not stored: files / crawlRoot / crawlRootPrefixes / skippedOversize (the TREE section's), reparsedFiles (0: nothing was
// re-extracted), memoryStop (a stopped ingest is never recorded), rustCrateRoots (derived on first use), and the five
// multi-root vectors (a multi-root merge does not use the snapshot).
static_assert( sizeof( IngestResult ) == 1232 && sizeof( Symbol ) == 112 && sizeof( Reference ) == 64 && sizeof( Binding ) == 36 && sizeof( RefColdText ) == 20,
               "the model changed shape: store and load the new field in writeModel / readModel below, bump warmsnap::kVersion, then re-pin these sizes" );
#endif

// ── rows ────────────────────────────────────────────────────────────────────────────────────────────────────────────
struct SymRow
{
    std::uint32_t fileId, line, sigStartByte, sigEndByte, endByte, cx, ccx, loc, locals;
    std::uint16_t ppAlt, humps, deepLoc, ev, params;
    std::uint8_t  kind, lang;
    std::array<std::uint8_t, kEvWhyTagCount> evWhy;
    std::uint8_t  maxNest, arityExact, bits, paramsMin, extentSuspect, rankFlags;   // bits: testScope 1, internalLinkage 2, scopeRootsStd 4, fnLocal 8
    std::uint8_t  steer, dispatchShare;                                             // QD-TANGLE (model.h Symbol::steer / ::dispatchShare)
};
static_assert( RawRow<SymRow> && sizeof( SymRow ) == 64, "SymRow is a raw 64 B row" );

// ── references and bindings: a delta + varint row stream ────────────────────────────────────────────────────────────
// These two families are most of the model (vscode: 2.0 M references, 1.5 M bindings), and as fixed 52 B / 36 B rows they
// alone took the snapshot past the registered disk ceiling. A row is instead: its SHAPE (one index into a small table of
// the distinct flag / enum / which-optional-fields-follow combinations), the position fields as deltas against the row
// before, and name-table indices — the table ordered by use count, so a hot name is one or two bytes. About 12 B a
// reference. The stream is cut every kRowsPerChunk rows, each chunk starting from zero state, so chunks decode in
// parallel straight into the model's rows.
inline constexpr std::size_t kRowsPerChunk = 4096;

struct VarOut
{
    std::string bytes;
    void v( std::uint64_t x )
    {
        for( ; x >= 0x80; x >>= 7 ) { bytes.push_back( char( std::uint8_t( x & 0x7f ) | 0x80 ) ); }
        bytes.push_back( char( std::uint8_t( x ) ) );
    }
    void z( std::int64_t x ) { v( x >= 0 ? std::uint64_t( x ) * 2 : std::uint64_t( -( x + 1 ) ) * 2 + 1 ); }   // zigzag, without a wrapping shift
};
struct VarIn
{
    const unsigned char* p  = nullptr;
    const unsigned char* e  = nullptr;
    bool                 ok = true;
    std::uint64_t v() noexcept   // scipwire::Reader's LEB128 reader: one bounds- and overlong-checked varint in the tree
    {
        scipwire::Reader reader{ p, e };
        std::uint64_t    x = 0;
        if( !reader.varint( x ) ) { ok = false; }
        p = reader.p;
        return ok ? x : 0;
    }
    std::int64_t z() noexcept
    {
        const std::uint64_t u = v();
        return ( u & 1 ) != 0 ? -std::int64_t( u / 2 ) - 1 : std::int64_t( u / 2 );
    }
    std::uint32_t u32() noexcept
    {
        const std::uint64_t x = v();
        if( x > 0xFFFFFFFFull ) { ok = false; }
        return std::uint32_t( x & 0xFFFFFFFFull );
    }
    // a field stored as a delta against `prev`: the sum must be a u32 again
    std::uint32_t delta( std::uint32_t prev ) noexcept
    {
        const std::int64_t x = std::int64_t( prev ) + z();
        if( x < 0 || x > 0xFFFFFFFFll ) { ok = false; }
        return ok ? std::uint32_t( x ) : 0u;
    }
};

enum : std::uint16_t
{
    kRefInherit = 1, kRefDocLink = 2, kRefCompose = 4, kRefArgCountKnown = 8, kRefViaArrow = 16, kRefQualifierRootsStd = 32, kRefMemberCall = 64,
    kRefMemberFactory = 128, kRefForwarded = 256, kRefTrailingLambda = 512
};
// which optional fields follow a reference row's fixed ones
enum : std::uint8_t { kHasQualifier = 1, kHasRecvVar = 2, kHasMemberRoot = 4, kHasBaseBind = 8, kHasLitAt = 16, kHasCold = 32, kHasArgCount = 64 };

// a row stream's frame: its chunk offsets, then its bytes
inline void writeStream( Out& o, std::size_t rowCount, const std::vector<std::uint64_t>& chunkAt, const std::string& bytes )
{
    o.u64( rowCount );
    o.vec( chunkAt );
    o.u64( bytes.size() );
    o.put( bytes.data(), bytes.size() );
}
struct Stream
{
    std::size_t                rowCount = 0;
    std::vector<std::uint64_t> chunkAt;
    std::string_view           bytes;
    VarIn chunk( std::size_t c ) const noexcept
    {
        const unsigned char* const base = reinterpret_cast<const unsigned char*>( bytes.data() );
        return VarIn{ base + chunkAt[ c ], base + chunkAt[ c + 1 ], true };
    }
};
inline bool readStream( In& in, Stream& st )
{
    st.rowCount = std::size_t( in.u64() );
    in.vec( st.chunkAt );
    const std::size_t n  = in.count( 1 );
    const char* const at = in.take( n );
    st.bytes             = at != nullptr ? std::string_view( at, n ) : std::string_view{};
    const bool fits = in.ok && st.rowCount <= n && st.chunkAt.size() == ( st.rowCount + kRowsPerChunk - 1 ) / kRowsPerChunk + 1 && std::ranges::is_sorted( st.chunkAt )
                   && st.chunkAt.front() == 0 && st.chunkAt.back() == n;
    if( !VALIDATE( fits, "warmsnap: a row stream's chunk table does not fit its bytes" ) ) { in.ok = false; }
    return in.ok;
}

// The distinct pool texts of one section, in first-use order. A pool text's std::string has one address for the life of
// the process (TextPool never moves a slot), so the address IS the identity and writing a row hashes a pointer, not a text.
struct NameTable
{
    HashMap<const std::string*, std::uint32_t> index;
    std::vector<const std::string*>            texts;
    std::uint32_t of( const std::string& text )
    {
        const auto [ it, fresh ] = index.try_emplace( &text, std::uint32_t( texts.size() ) );
        if( fresh ) { texts.push_back( &text ); }
        return it->second;
    }
};

inline void writeTexts( Out& o, const std::vector<std::string_view>& texts )
{
    std::vector<std::uint32_t> ends;
    ends.reserve( texts.size() );
    std::string blob;
    for( const std::string_view t : texts )
    {
        blob.append( t );
        ends.push_back( std::uint32_t( blob.size() ) );
    }
    o.vec( ends );
    o.u64( blob.size() );
    o.put( blob.data(), blob.size() );
}
// the texts as views into the section: `ends` and the blob stay where the file's bytes are
inline bool readTexts( In& in, std::vector<std::uint32_t>& ends, std::string_view& blob )
{
    in.vec( ends );
    const std::size_t n  = in.count( 1 );
    const char* const at = in.take( n );
    blob                 = at != nullptr ? std::string_view( at, n ) : std::string_view{};
    const bool fits = in.ok && std::ranges::is_sorted( ends ) && ( ends.empty() ? n == 0 : ends.back() == n );
    if( !VALIDATE( fits, "warmsnap: a text table's bounds do not fit its bytes" ) ) { in.ok = false; }
    return in.ok;
}
inline std::string_view textAt( const std::vector<std::uint32_t>& ends, std::string_view blob, std::size_t i ) noexcept
{
    const std::uint32_t from = i == 0 ? 0u : ends[ i - 1 ];
    return blob.substr( from, ends[ i ] - from );
}

// What the recording run's parse cache line said, replayed on a load so RIPWIRE_CACHE_STATS still describes the run.
struct BlobFacts
{
    // No stat signature of the blob. The snapshot's FILENAME carries the identity of the blob this model was assembled
    // from (warmsnap.h snapshotPath, ingest_cache.h cacheBlobIdentity), so "is this still the same blob" is not a
    // question a stored field can be wrong about: a rewritten or replaced blob resolves to a different name, or none.
    std::uint64_t cachedRecords = 0;
    std::uint64_t blobEntries   = 0;
    // One path per bridge-format document (pdf, docx, ...) in the tree: where the doc pass would find a cached extraction
    // of it. The model is recorded only when markitdown could not run and none of these existed, so every such document
    // extracted to nothing; it is served only while both are still true (bridgeDocsStillEmpty).
    std::vector<std::string> bridgeBlobs;
};

// The blob facts a recorded model carries: what this run's load read, or, on a run that opened with no blob
// (Session::coldBlob), what the next run's load reads from the blob this run just published: one record per crawled file.
inline BlobFacts recordedBlobFacts( const Session& s, std::uint64_t recordsRead, std::uint64_t blobEntries, std::size_t files )
{
    return s.coldBlob ? BlobFacts{ files, files, {} } : BlobFacts{ recordsRead, blobEntries, {} };
}

inline bool bridgeDocsStillEmpty( const std::vector<std::string>& bridgeBlobs )
{
    if( bridgeBlobs.empty() )
    {
        return true;
    }
    return !docparse::markitdownMayRun() && std::ranges::none_of( bridgeBlobs, []( const std::string& path ) { os::stat_t st; return os::stat( path.c_str(), &st ) == 0; } );
}

// one symbol family (symbols, then fields): raw rows and two text tables
inline void writeSymbolFamily( Out& o, const std::vector<Symbol>& family )
{
    std::vector<SymRow>           rows( family.size() );
    std::vector<std::string_view> names, scopes;
    names.reserve( family.size() );
    scopes.reserve( family.size() );
    for( std::size_t i = 0; i < family.size(); ++i )
    {
        const Symbol& s = family[ i ];
        ENSURES( s.id == i, "a symbol's id is its index in its family" );
        rows[ i ] = SymRow{ s.fileId, s.line, s.sigStartByte, s.sigEndByte, s.endByte, s.cx, s.ccx, s.loc, s.locals, s.ppAlt, s.humps, s.deepLoc, s.ev, s.params,
                            std::uint8_t( s.kind ), std::uint8_t( s.lang ), s.evWhy, s.maxNest, s.arityExact,
                            std::uint8_t( s.testScope | ( s.internalLinkage << 1 ) | ( s.scopeRootsStd << 2 ) | ( s.fnLocal << 3 ) ), std::uint8_t( s.paramsMin ),
                            std::uint8_t( s.extentSuspect ), std::uint8_t( s.rankFlags ), s.steer, s.dispatchShare };
        names.push_back( s.name );
        scopes.push_back( s.scope );
    }
    o.vec( rows );
    writeTexts( o, names );
    writeTexts( o, scopes );
}

// Every reference's and binding's texts as name-table indices, and the table itself written to `o`.
struct RefNameIds { std::uint32_t callee, qualifier, recvVar, memberRoot, cold[ 5 ]; };
struct BindNameIds { std::uint32_t var, importedName, typeName; };
struct RowNameIds
{
    std::vector<RefNameIds>      refNames;    // first-use numbering
    std::vector<BindNameIds>     bindNames;
    std::vector<std::uint32_t> stored;      // first-use index -> the index the file stores (by use count)
};
inline RowNameIds numberNames( Out& o, const IngestResult& ing )
{
    // references + bindings: one name table (ordered by use), two shape tables, two row streams
    NameTable names;
    names.index.reserve( ing.references.size() / 4 + 1024 );
    names.of( kNoRefColdText );   // index 0 is the empty text
    std::vector<std::uint32_t> uses{ 0 };
    const auto name = [ & ]( const std::string& text )
    {
        const std::uint32_t at = text.empty() ? 0u : names.of( text );
        if( at == uses.size() ) { uses.push_back( 0 ); }
        ++uses[ at ];
        return at;
    };
    // pass 1: every row's name indices in first-use numbering (so the use counts exist before a byte is written)
    RowNameIds n;
    n.refNames.resize( ing.references.size() );
    n.bindNames.resize( ing.bindings.size() );
    for( std::size_t i = 0; i < ing.references.size(); ++i )
    {
        const Reference& r = ing.references[ i ];
        n.refNames[ i ] = { name( r.calleeName.str() ), name( r.qualifier.str() ), name( r.recvVar.str() ), name( r.memberRoot.str() ),
                          { name( r.fieldName() ), name( r.composeRel() ), name( r.memberPath() ), name( r.memberCtor() ), name( r.memberVia() ) } };
    }
    for( std::size_t i = 0; i < ing.bindings.size(); ++i )
    {
        const Binding& b = ing.bindings[ i ];
        n.bindNames[ i ] = { name( b.var.str() ), name( b.importedName.str() ), name( b.typeName.str() ) };
    }
    // the stored numbering: the empty text stays 0, the rest by use count descending (ties in first-use order: deterministic)
    std::vector<std::uint32_t> order( names.texts.size() );
    std::iota( order.begin(), order.end(), 0u );
    std::stable_sort( order.begin() + 1, order.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return uses[ a ] > uses[ b ]; } );
    n.stored.resize( order.size() );
    {
        std::vector<std::string_view> texts( order.size() );
        for( std::uint32_t at = 0; at < order.size(); ++at )
        {
            n.stored[ order[ at ] ] = at;
            texts[ at ]           = *names.texts[ order[ at ] ];
        }
        writeTexts( o, texts );
    }
    return n;
}

inline void writeRefRows( Out& o, const IngestResult& ing, const RowNameIds& names )
{
    HashMap<std::uint64_t, std::uint32_t> shapeIndex;
    std::vector<std::uint64_t>            shapes, chunkAt;
    VarOut                                rows;
    std::uint32_t prevFile = 0, prevStart = 0, prevLine = 0, prevFrom = 0;
    for( std::size_t i = 0; i < ing.references.size(); ++i )
    {
        if( i % kRowsPerChunk == 0 )
        {
            chunkAt.push_back( rows.bytes.size() );
            prevFile = prevStart = prevLine = prevFrom = 0;
        }
        const Reference& r = ing.references[ i ];
        const RefNameIds&  n = names.refNames[ i ];
        const std::uint64_t flags = std::uint64_t( ( r.isInherit ? kRefInherit : 0 ) | ( r.isDocLink ? kRefDocLink : 0 ) | ( r.isCompose ? kRefCompose : 0 )
                                  | ( r.argCountKnown ? kRefArgCountKnown : 0 ) | ( r.viaArrow ? kRefViaArrow : 0 ) | ( r.qualifierRootsStd ? kRefQualifierRootsStd : 0 )
                                  | ( r.memberCall ? kRefMemberCall : 0 ) | ( r.memberFactory ? kRefMemberFactory : 0 ) | ( r.forwarded ? kRefForwarded : 0 )
                                  | ( r.trailingLambda ? kRefTrailingLambda : 0 ) );
        const std::uint64_t has = std::uint64_t( ( n.qualifier != 0 ? kHasQualifier : 0 ) | ( n.recvVar != 0 ? kHasRecvVar : 0 ) | ( n.memberRoot != 0 ? kHasMemberRoot : 0 )
                                | ( r.baseBind != 0 ? kHasBaseBind : 0 ) | ( r.litAt != 0 ? kHasLitAt : 0 ) | ( r.hasColdBlock() ? kHasCold : 0 ) | ( r.argCount != 0 ? kHasArgCount : 0 ) );
        const std::uint64_t shape = flags | ( std::uint64_t( r.lang ) << 16 ) | ( std::uint64_t( r.role ) << 24 ) | ( std::uint64_t( r.recv ) << 32 ) | ( has << 40 );
        const auto [ it, fresh ] = shapeIndex.try_emplace( shape, std::uint32_t( shapes.size() ) );
        if( fresh ) { shapes.push_back( shape ); }
        rows.v( it->second );
        rows.z( std::int64_t( r.fileId ) - prevFile );
        rows.z( std::int64_t( r.startByte ) - prevStart );
        rows.z( std::int64_t( r.line ) - prevLine );
        rows.z( std::int64_t( r.fromSymbol ) - prevFrom );
        rows.v( names.stored[ n.callee ] );
        if( ( has & kHasQualifier ) != 0 ) { rows.v( names.stored[ n.qualifier ] ); }
        if( ( has & kHasRecvVar ) != 0 ) { rows.v( names.stored[ n.recvVar ] ); }
        if( ( has & kHasMemberRoot ) != 0 ) { rows.v( names.stored[ n.memberRoot ] ); }
        if( ( has & kHasBaseBind ) != 0 ) { rows.v( r.baseBind ); }
        if( ( has & kHasLitAt ) != 0 ) { rows.v( r.litAt ); }
        if( ( has & kHasCold ) != 0 ) { for( const std::uint32_t c : n.cold ) { rows.v( names.stored[ c ] ); } }
        if( ( has & kHasArgCount ) != 0 ) { rows.v( r.argCount ); }
        prevFile = r.fileId;  prevStart = r.startByte;  prevLine = r.line;  prevFrom = r.fromSymbol;
    }
    chunkAt.push_back( rows.bytes.size() );
    o.vec( shapes );
    writeStream( o, ing.references.size(), chunkAt, rows.bytes );
}

inline void writeBindRows( Out& o, const IngestResult& ing, const RowNameIds& names )
{
    HashMap<std::uint64_t, std::uint32_t> shapeIndex;
    std::vector<std::uint64_t>            shapes, chunkAt;
    VarOut                                rows;
    std::uint32_t prevFile = 0, prevStart = 0, prevFrom = 0;
    for( std::size_t i = 0; i < ing.bindings.size(); ++i )
    {
        if( i % kRowsPerChunk == 0 )
        {
            chunkAt.push_back( rows.bytes.size() );
            prevFile = prevStart = prevFrom = 0;
        }
        const Binding&   b = ing.bindings[ i ];
        const BindNameIds& n = names.bindNames[ i ];
        const std::uint64_t shape = std::uint64_t( b.kind ) | ( std::uint64_t( b.isFromAssignment ? 1 : 0 ) << 8 ) | ( std::uint64_t( b.resultIndex ) << 16 )
                                  | ( std::uint64_t( b.unwrapDepth ) << 24 ) | ( std::uint64_t( n.importedName != 0 ? 1 : 0 ) << 32 );
        const auto [ it, fresh ] = shapeIndex.try_emplace( shape, std::uint32_t( shapes.size() ) );
        if( fresh ) { shapes.push_back( shape ); }
        rows.v( it->second );
        rows.z( std::int64_t( b.fileId ) - prevFile );
        rows.z( std::int64_t( b.startByte ) - prevStart );
        rows.z( std::int64_t( b.spanStart ) - b.startByte );
        rows.z( std::int64_t( b.spanEnd ) - b.spanStart );
        rows.z( std::int64_t( b.fromSymbol ) - prevFrom );
        rows.v( names.stored[ n.var ] );
        rows.v( names.stored[ n.typeName ] );
        if( n.importedName != 0 ) { rows.v( names.stored[ n.importedName ] ); }
        prevFile = b.fileId;  prevStart = b.startByte;  prevFrom = b.fromSymbol;
    }
    chunkAt.push_back( rows.bytes.size() );
    o.vec( shapes );
    writeStream( o, ing.bindings.size(), chunkAt, rows.bytes );
}

// the small families: includes, constant opens, construct hits, FFI aliases, routes, document text, the lexical statistics
inline void writeSideFamilies( Out& o, const IngestResult& ing )
{
    o.u64( ing.includes.size() );
    for( const Include& i : ing.includes )
    {
        o.u32( i.fileId );
        o.u32( i.byte );
        o.u8( std::uint8_t( ( i.isAngle ? 1 : 0 ) | ( i.isLazy ? 2 : 0 ) | ( i.isSymbolic ? 4 : 0 ) | ( i.isValueUse ? 8 : 0 ) ) );
        o.str( i.target );
    }
    o.u64( ing.constOpens.size() );
    for( const ConstOpen& c : ing.constOpens ) { o.u32( c.fileId ); o.u32( c.startByte ); o.u32( c.endByte ); o.u8( c.namespaceOnly ? 1 : 0 ); o.str( c.written ); }
    o.u64( ing.constructHits.size() );
    for( const ConstructHit& h : ing.constructHits ) { o.u32( h.fileId ); o.u32( h.startByte ); o.u32( h.line ); o.u8( h.tag ); }
    o.u8( ing.constructHitsForFiles == ing.files.size() ? 1 : 0 );
    o.u64( ing.bindingAliases.size() );
    for( const BindingAlias& a : ing.bindingAliases ) { o.u32( a.fileId ); o.u8( std::uint8_t( a.kind ) ); o.u8( a.lowConf ? 1 : 0 ); o.str( a.aliasName ); o.str( a.targetName ); o.str( a.targetScope ); }
    o.u64( ing.routeDefs.size() );
    for( const RouteDef& d : ing.routeDefs ) { o.u32( d.fileId ); o.u32( d.line ); o.u8( std::uint8_t( d.method ) ); o.str( d.path ); o.str( d.handlerName ); }
    o.u64( ing.routeUses.size() );
    for( const RouteUse& u : ing.routeUses ) { o.u32( u.fileId ); o.u32( u.line ); o.u32( u.fromSymbol ); o.u8( std::uint8_t( u.method ) ); o.str( u.path ); }
    {
        // ascending fileId: the order the doc pass inserts in, so a reader that walks the map meets the same order
        std::vector<std::uint32_t> docFiles;
        for( const auto& [ fileId, text ] : ing.docText ) { docFiles.push_back( fileId ); }
        std::ranges::sort( docFiles );
        o.u64( docFiles.size() );
        for( const std::uint32_t fileId : docFiles ) { o.u32( fileId ); o.str( ing.docText.find( fileId )->second ); }
    }
    o.u8( ing.hasLexStats ? 1 : 0 );
    o.vec( ing.lexTokenRowOffsets );
    o.vec( ing.lexTokenHashes );
    o.vec( ing.lexTokenTfs );
    o.vec( ing.lexDocBodyDl );
    o.vec( ing.lexFileSig );
}

inline std::string writeModel( const IngestResult& ing, const BlobFacts& blob )
{
    PROFILE_SCOPE_DESCRIBE( "warmsnap: serialize the model section" );
    Out o;
    o.bytes.reserve( ing.references.size() * 14 + ing.bindings.size() * 16 + ing.symbols.size() * ( sizeof( SymRow ) + 48 ) + ( 1u << 20 ) );
    o.u64( blob.cachedRecords );
    o.u64( blob.blobEntries );
    o.strs( blob.bridgeBlobs );
    o.u64( ing.files.size() );
    writeCrawlSkips( o, ing.crawlSkips );
    o.vec( ing.fileHealth );
    o.vec( ing.nestRefusedFile );

    writeSymbolFamily( o, ing.symbols );
    writeSymbolFamily( o, ing.fields );
    o.vec( ing.aliasTargets );
    o.vec( ing.fnLocalScopes );
    o.vec( ing.tangleBlocks );   // QD-TANGLE BLOCK FACTS (model.h TangleBlockFacts)
    o.vec( ing.cloneKeys );

    const RowNameIds names = numberNames( o, ing );
    writeRefRows( o, ing, names );
    writeBindRows( o, ing, names );
    writeSideFamilies( o, ing );
    o.u64( 0x454e'444d'4f44'454cull );
    return std::move( o.bytes );
}

inline bool readSymbolFamily( In& in, std::vector<Symbol>& family, std::size_t fileCount )
{
    std::vector<SymRow>        rows;
    std::vector<std::uint32_t> nameEnds, scopeEnds;
    std::string_view           nameBlob, scopeBlob;
    in.vec( rows );
    if( !readTexts( in, nameEnds, nameBlob ) || !readTexts( in, scopeEnds, scopeBlob ) || !VALIDATE( nameEnds.size() == rows.size() && scopeEnds.size() == rows.size(), "warmsnap: a symbol family's tables disagree on its size" ) )
    {
        return false;
    }
    family.resize( rows.size() );
    std::atomic<bool> bad{ false };
    parallelFor( rows.size(), [ & ]( std::size_t i )
    {
        const SymRow& r = rows[ i ];
        Symbol&       s = family[ i ];
        if( r.kind >= kSymKindCount || r.lang >= kLangCount || r.fileId >= fileCount )
        {
            bad.store( true, std::memory_order_relaxed );
            return;
        }
        s.id = NodeId( i );              s.kind = SymKind( r.kind );      s.lang = Lang( r.lang );           s.ppAlt = r.ppAlt;
        s.fileId = r.fileId;             s.line = r.line;                 s.sigStartByte = r.sigStartByte;   s.sigEndByte = r.sigEndByte;
        s.endByte = r.endByte;           s.cx = r.cx;                     s.ccx = r.ccx;                     s.loc = r.loc;
        s.locals = r.locals;             s.humps = r.humps;               s.deepLoc = r.deepLoc;             s.ev = r.ev;
        s.evWhy = r.evWhy;               s.params = r.params;             s.maxNest = r.maxNest;             s.arityExact = r.arityExact;
        s.testScope = r.bits & 1;        s.internalLinkage = ( r.bits >> 1 ) & 1;  s.scopeRootsStd = ( r.bits >> 2 ) & 1;  s.fnLocal = ( r.bits >> 3 ) & 1;
        s.paramsMin = r.paramsMin & 15;  s.extentSuspect = r.extentSuspect & 15;   s.rankFlags = r.rankFlags & 15;
        s.steer = r.steer;               s.dispatchShare = r.dispatchShare;
        s.name  = textAt( nameEnds, nameBlob, i );
        s.scope = textAt( scopeEnds, scopeBlob, i );
    } );
    if( !VALIDATE( !bad.load(), "warmsnap: a symbol row names a kind, language or file this model does not have" ) )
    {
        return false;
    }
    return true;
}

// what a row needs to resolve an index: the name table (texts, and the same texts interned), and the bounds an id must respect
struct RowTables
{
    const std::vector<std::uint32_t>& nameEnds;
    std::string_view                  nameBlob;
    std::vector<rw::InternedText>     names;
    std::size_t                       fileCount   = 0;
    std::size_t                       symbolCount = 0;
    bool symOk( NodeId id ) const noexcept { return id == kNoNode || id < symbolCount; }
};

// Decode one row stream chunk by chunk, in parallel, straight into the model's rows. False: some row did not decode.
inline bool readRefRows( const Stream& refStream, const std::vector<std::uint64_t>& refShapes, const RowTables& t, IngestResult& ing )
{
    std::atomic<bool> bad{ false };
    const std::size_t rowCount = refStream.rowCount;
    if( rowCount > refStream.bytes.size() )   // readStream already held the count to the stream's bytes (a row is at least six): said again at the allocation
    {
        return false;
    }
    {
        // SEPARATE SCOPE, because these are two full write passes over the same memory and only one of
        // them is parallel. `Reference` is 64 B and is NOT trivially default constructible (every field
        // carries an `= 0` NSDMI), so resize() VALUE-INITIALISES every row -- at llvm-project scale,
        // where the map header accounts for at least 5.69 M call references before the non-call roles,
        // that is ~400-580 MB written SERIALLY and then written again by the decode below. Whether the
        // zero-fill or the decode owns the 254.6 ms this function costs is not something the enclosing
        // scope could ever say, and the two call for completely different changes.
        PROFILE_SCOPE_DESCRIBE( "warmsnap/model: resize the reference vector (serial value-init of 64 B rows)" );
        ing.references.resize( rowCount );
    }
    PROFILE_SCOPE_DESCRIBE( "warmsnap/model: the parallel reference decode itself" );
    // itemsPerWorker = 1: one item here is a 4096-row CHUNK costing ~163 us, so a single chunk is worth a
    // worker. Under the 2048 default this decode ran on ONE core (measured effective threads 1.00 at both
    // envoy's 287 chunks and llvm-project's 1,449) despite the format being cut into chunks precisely so
    // that it could be decoded in parallel.
    parallelFor( refStream.chunkAt.size() - 1, [ & ]( std::size_t c )
    {
        // INSIDE the lambda, so this fires once per chunk and its total is THREAD time, while the
        // scope outside is WALL. total_here / wall_outside is the effective thread count, and that
        // ratio is what decides the change: near the core count means the region is already well
        // parallelised and the only route left is less work per row; near 1 means the parallelism is
        // not arriving and the fix is scheduling, not the row body. Guessing between those two is how
        // a cache-locality rewrite gets written for a load-balance problem.
        PROFILE_SCOPE_DESCRIBE( "warmsnap/model: one reference chunk (per-chunk THREAD time; /wall = effective threads)" );
        VarIn         row = refStream.chunk( c );
        std::uint32_t prevFile = 0, prevStart = 0, prevLine = 0, prevFrom = 0;
        const std::size_t last = std::min( refStream.rowCount, ( c + 1 ) * kRowsPerChunk );
        for( std::size_t i = c * kRowsPerChunk; i < last && row.ok; ++i )
        {
            const std::uint32_t shapeAt = row.u32();
            if( shapeAt >= refShapes.size() ) { row.ok = false; break; }
            const std::uint64_t shape = refShapes[ shapeAt ];
            const std::uint16_t flags = std::uint16_t( shape & 0xffff );
            const std::uint8_t  has   = std::uint8_t( ( shape >> 40 ) & 0xff );
            Reference& x = ing.references[ i ];
            x.fileId     = prevFile  = row.delta( prevFile );
            x.startByte  = prevStart = row.delta( prevStart );
            x.line       = prevLine  = row.delta( prevLine );
            x.fromSymbol = prevFrom  = row.delta( prevFrom );
            const auto nameIn = [ & ]() noexcept
            {
                const std::uint32_t at = row.u32();
                if( at >= t.names.size() ) { row.ok = false; }
                return row.ok ? at : 0u;
            };
            x.calleeName = t.names[ nameIn() ];
            if( ( has & kHasQualifier ) != 0 ) { x.qualifier = t.names[ nameIn() ]; }
            if( ( has & kHasRecvVar ) != 0 ) { x.recvVar = t.names[ nameIn() ]; }
            if( ( has & kHasMemberRoot ) != 0 ) { x.memberRoot = t.names[ nameIn() ]; }
            if( ( has & kHasBaseBind ) != 0 ) { x.baseBind = row.u32(); }
            if( ( has & kHasLitAt ) != 0 ) { x.litAt = row.u32(); }
            if( ( has & kHasCold ) != 0 )
            {
                std::uint32_t cold[ 5 ];
                for( std::uint32_t& at : cold ) { at = nameIn(); }
                // a block exists once any text is non-empty and keeps its empty ones: the same block the build's five setters left
                x.setFieldName( textAt( t.nameEnds, t.nameBlob, cold[ 0 ] ) );
                x.setComposeRel( textAt( t.nameEnds, t.nameBlob, cold[ 1 ] ) );
                x.setMemberPath( textAt( t.nameEnds, t.nameBlob, cold[ 2 ] ) );
                x.setMemberCtor( textAt( t.nameEnds, t.nameBlob, cold[ 3 ] ) );
                x.setMemberVia( textAt( t.nameEnds, t.nameBlob, cold[ 4 ] ) );
            }
            if( ( has & kHasArgCount ) != 0 )
            {
                const std::uint32_t args = row.u32();
                if( args > 0xFFFFu ) { row.ok = false; }
                x.argCount = std::uint16_t( args & 0xFFFFu );
            }
            x.lang = Lang( ( shape >> 16 ) & 0xff );  x.role = RefRole( ( shape >> 24 ) & 0xff );  x.recv = RecvKind( ( shape >> 32 ) & 0xff );
            x.isInherit = ( flags & kRefInherit ) != 0;                  x.isDocLink = ( flags & kRefDocLink ) != 0;        x.isCompose = ( flags & kRefCompose ) != 0;
            x.argCountKnown = ( flags & kRefArgCountKnown ) != 0;        x.viaArrow = ( flags & kRefViaArrow ) != 0;        x.qualifierRootsStd = ( flags & kRefQualifierRootsStd ) != 0;
            x.memberCall = ( flags & kRefMemberCall ) != 0;              x.memberFactory = ( flags & kRefMemberFactory ) != 0;
            x.forwarded = ( flags & kRefForwarded ) != 0;                x.trailingLambda = ( flags & kRefTrailingLambda ) != 0;
            if( x.fileId >= t.fileCount || !t.symOk( x.fromSymbol ) ) { row.ok = false; }
        }
        if( !row.ok || row.p != row.e ) { bad.store( true, std::memory_order_relaxed ); }
    }, 1 );
    return !bad.load();
}

inline bool readBindRows( const Stream& bindStream, const std::vector<std::uint64_t>& bindShapes, const RowTables& t, IngestResult& ing )
{
    std::atomic<bool> bad{ false };
    const std::size_t rowCount = bindStream.rowCount;
    if( rowCount > bindStream.bytes.size() )
    {
        return false;
    }
    ing.bindings.resize( rowCount );
    // itemsPerWorker = 1, for the same reason as the reference chunks above.
    parallelFor( bindStream.chunkAt.size() - 1, [ & ]( std::size_t c )
    {
        VarIn         row = bindStream.chunk( c );
        std::uint32_t prevFile = 0, prevStart = 0, prevFrom = 0;
        const std::size_t last = std::min( bindStream.rowCount, ( c + 1 ) * kRowsPerChunk );
        for( std::size_t i = c * kRowsPerChunk; i < last && row.ok; ++i )
        {
            const std::uint32_t shapeAt = row.u32();
            if( shapeAt >= bindShapes.size() ) { row.ok = false; break; }
            const std::uint64_t shape = bindShapes[ shapeAt ];
            Binding& b = ing.bindings[ i ];
            b.fileId     = prevFile  = row.delta( prevFile );
            b.startByte  = prevStart = row.delta( prevStart );
            b.spanStart  = row.delta( b.startByte );
            b.spanEnd    = row.delta( b.spanStart );
            b.fromSymbol = prevFrom  = row.delta( prevFrom );
            const auto nameIn = [ & ]() noexcept
            {
                const std::uint32_t at = row.u32();
                if( at >= t.names.size() ) { row.ok = false; }
                return row.ok ? at : 0u;
            };
            b.var      = t.names[ nameIn() ];
            b.typeName = t.names[ nameIn() ];
            if( ( ( shape >> 32 ) & 1 ) != 0 ) { b.importedName = t.names[ nameIn() ]; }
            b.kind = LocalBindKind( shape & 0xff );  b.isFromAssignment = ( ( shape >> 8 ) & 1 ) != 0;
            b.resultIndex = std::uint8_t( ( shape >> 16 ) & 0xff );  b.unwrapDepth = std::uint8_t( ( shape >> 24 ) & 0xff );
            if( b.fileId >= t.fileCount || !t.symOk( b.fromSymbol ) ) { row.ok = false; }
        }
        if( !row.ok || row.p != row.e ) { bad.store( true, std::memory_order_relaxed ); }
    }, 1 );
    return !bad.load();
}

inline bool readRowStreams( In& in, IngestResult& ing, std::size_t fileCount )
{
    std::vector<std::uint32_t> nameEnds;
    std::string_view           nameBlob;
    std::vector<std::uint64_t> refShapes, bindShapes;
    Stream                     refStream, bindStream;
    if( !readTexts( in, nameEnds, nameBlob ) )
    {
        return false;
    }
    in.vec( refShapes );
    if( !readStream( in, refStream ) )
    {
        return false;
    }
    in.vec( bindShapes );
    if( !readStream( in, bindStream ) || !VALIDATE( !nameEnds.empty(), "warmsnap: the name table has no empty text" ) )
    {
        return false;
    }
    RowTables t{ nameEnds, nameBlob, std::vector<rw::InternedText>( nameEnds.size() ), fileCount, ing.symbols.size() };
    parallelFor( t.names.size(), [ & ]( std::size_t i ) { t.names[ i ] = textAt( nameEnds, nameBlob, i ); } );
    for( const std::uint64_t shape : refShapes )
    {
        if( !VALIDATE( ( ( shape >> 16 ) & 0xff ) < kLangCount && ( ( shape >> 24 ) & 0xff ) < kRefRoleCount && ( ( shape >> 32 ) & 0xff ) < kRecvKindCount && ( shape >> 48 ) == 0,
                       "warmsnap: a reference shape names a language, role or receiver this build does not know" ) )
        {
            return false;
        }
    }
    for( const std::uint64_t shape : bindShapes )
    {
        if( !VALIDATE( ( shape & 0xff ) < kLocalBindKindCount && ( shape >> 33 ) == 0, "warmsnap: a binding shape names a kind this build does not know" ) )
        {
            return false;
        }
    }
    const bool decoded = readRefRows( refStream, refShapes, t, ing ) && readBindRows( bindStream, bindShapes, t, ing );
    return VALIDATE( decoded, "warmsnap: a reference or binding row stream does not decode to this model" );
}

inline void readSideFamilies( In& in, IngestResult& ing, std::size_t fileCount )
{
    for( std::size_t i = 0, n = in.count( 13 ); i < n && in.ok; ++i )
    {
        Include inc;
        inc.fileId = in.u32();
        inc.byte   = in.u32();
        const std::uint8_t flags = in.u8();
        inc.isAngle = ( flags & 1 ) != 0;  inc.isLazy = ( flags & 2 ) != 0;  inc.isSymbolic = ( flags & 4 ) != 0;  inc.isValueUse = ( flags & 8 ) != 0;
        inc.target  = in.str();
        ing.includes.push_back( std::move( inc ) );
    }
    for( std::size_t i = 0, n = in.count( 17 ); i < n && in.ok; ++i )
    {
        ConstOpen c;
        c.fileId = in.u32();  c.startByte = in.u32();  c.endByte = in.u32();  c.namespaceOnly = in.u8() != 0;  c.written = in.str();
        ing.constOpens.push_back( std::move( c ) );
    }
    for( std::size_t i = 0, n = in.count( 13 ); i < n && in.ok; ++i )
    {
        ConstructHit h;
        h.fileId = in.u32();  h.startByte = in.u32();  h.line = in.u32();  h.tag = in.u8();
        ing.constructHits.push_back( h );
    }
    ing.constructHitsForFiles = in.u8() != 0 ? fileCount : SIZE_MAX;
    for( std::size_t i = 0, n = in.count( 18 ); i < n && in.ok; ++i )
    {
        BindingAlias a;
        a.fileId = in.u32();
        const std::uint8_t kind = in.u8();
        if( !VALIDATE( kind < kBindKindCount, "warmsnap: a binding kind this build does not know" ) ) { in.ok = false; }
        a.kind = BindKind( kind );  a.lowConf = in.u8() != 0;  a.aliasName = in.str();  a.targetName = in.str();  a.targetScope = in.str();
        ing.bindingAliases.push_back( std::move( a ) );
    }
    const auto method = [ & ]() noexcept
    {
        const std::uint8_t m = in.u8();
        if( !VALIDATE( m < kHttpMethodCount, "warmsnap: an HTTP method this build does not know" ) ) { in.ok = false; }
        return in.ok ? HttpMethod( m ) : HttpMethod::Unknown;
    };
    for( std::size_t i = 0, n = in.count( 17 ); i < n && in.ok; ++i )
    {
        RouteDef d;
        d.fileId = in.u32();  d.line = in.u32();  d.method = method();  d.path = in.str();  d.handlerName = in.str();
        ing.routeDefs.push_back( std::move( d ) );
    }
    for( std::size_t i = 0, n = in.count( 17 ); i < n && in.ok; ++i )
    {
        RouteUse u;
        u.fileId = in.u32();  u.line = in.u32();  u.fromSymbol = in.u32();  u.method = method();  u.path = in.str();
        ing.routeUses.push_back( std::move( u ) );
    }
    for( std::size_t i = 0, n = in.count( 8 ); i < n && in.ok; ++i )
    {
        const std::uint32_t fileId = in.u32();
        ing.docText.emplace( fileId, in.str() );
    }
    ing.hasLexStats = in.u8() != 0;
    in.vec( ing.lexTokenRowOffsets );
    in.vec( ing.lexTokenHashes );
    in.vec( ing.lexTokenTfs );
    in.vec( ing.lexDocBodyDl );
    in.vec( ing.lexFileSig );
}

// Fill `ing` (whose crawl fields replayTree already set) from the section. False: nothing in `ing` may be used.
inline bool readModel( std::string_view section, IngestResult& ing, BlobFacts& blob )
{
    PROFILE_SCOPE_DESCRIBE( "warmsnap: load the model section" );
    In in{ section };
    blob.cachedRecords = in.u64();
    blob.blobEntries   = in.u64();
    in.strs( blob.bridgeBlobs );
    if( !in.ok || !bridgeDocsStillEmpty( blob.bridgeBlobs ) )
    {
        return false;
    }
    const std::size_t fileCount = std::size_t( in.u64() );
    if( !VALIDATE( in.ok && fileCount == ing.files.size(), "warmsnap: the model section describes another crawl" ) )
    {
        return false;
    }
    readCrawlSkips( in, ing.crawlSkips );
    in.vec( ing.fileHealth );
    in.vec( ing.nestRefusedFile );

    if( !readSymbolFamily( in, ing.symbols, fileCount ) || !readSymbolFamily( in, ing.fields, fileCount ) )
    {
        return false;
    }
    in.vec( ing.aliasTargets );
    in.vec( ing.fnLocalScopes );
    in.vec( ing.tangleBlocks );   // QD-TANGLE BLOCK FACTS (model.h TangleBlockFacts)
    in.vec( ing.cloneKeys );

    if( !readRowStreams( in, ing, fileCount ) )
    {
        return false;
    }

    readSideFamilies( in, ing, fileCount );
    const std::size_t symbolCount = ing.symbols.size();
    const auto        symOk       = [ & ]( NodeId id ) noexcept { return id == kNoNode || id < symbolCount; };
    const std::uint64_t endMark = in.u64();
    const bool shaped = in.ok && endMark == 0x454e'444d'4f44'454cull && in.p == in.e && ing.fileHealth.size() == fileCount && ing.nestRefusedFile.size() == fileCount
                     && ( ing.cloneKeys.empty() || ing.cloneKeys.size() == symbolCount )
                     && std::ranges::all_of( ing.aliasTargets, [ & ]( const AliasTarget& t ) { return t.id < symbolCount; } )
                     && std::ranges::all_of( ing.fnLocalScopes, [ & ]( const FnLocalScope& f ) { return f.id < symbolCount; } )
                     && std::ranges::all_of( ing.tangleBlocks, [ & ]( const TangleBlockFacts& f ) { return f.id < symbolCount; } )
                     && std::ranges::is_sorted( ing.tangleBlocks, {}, &TangleBlockFacts::id )
                     && std::ranges::all_of( ing.routeUses, [ & ]( const RouteUse& u ) { return symOk( u.fromSymbol ) && u.fileId < fileCount; } )
                     && std::ranges::all_of( ing.includes, [ & ]( const Include& i ) { return i.fileId < fileCount; } )
                     && ( !ing.hasLexStats || ( ing.lexTokenRowOffsets.size() == symbolCount + 1 && ing.lexDocBodyDl.size() == symbolCount
                                                && ing.lexTokenHashes.size() == ing.lexTokenTfs.size() && ing.lexTokenRowOffsets.back() == ing.lexTokenHashes.size()
                                                && std::ranges::is_sorted( ing.lexTokenRowOffsets ) ) );
    return VALIDATE( shaped, "warmsnap: the model section does not parse to this crawl's shape" );
}

}   // namespace rw::warmsnap
