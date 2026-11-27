// readers_ingest.cpp — crash-fuzz entry points for the ingest-cache readers. These live in ingest.cpp's section
// headers (ingest_cache.h, ingest_astquery.h), which refuse any includer but that one translation unit
// (RIPWIRE_INGEST_TU), so this file IS that translation unit plus three entry points: the whole of ingest.cpp is
// compiled here, instrumented, and linked with the grammar objects. It replaces src/ingest.cpp in these targets and
// is never linked beside it.
//
//   ingestrecord — readFileRecord over one record's bytes (first byte: ignored — it chose the lean or rich family before
//                  format 56 made them one; kept so the seed corpus still frames). This is what a
//                  checksum-valid blob reaches: the record digest is over the same bytes, so the harness skips it.
//   ingestframe  — openCacheFrame over a whole blob: the harness stamps the real magic/version/parserVer/arch into
//                  the header and rebuilds the table checksum, so the fuzzer reaches the offset-table arithmetic.
//   stiermemo    — spanTierMemoLoad over a memo blob (header identity stamped to match), then spanTierAt at every
//                  recorded boundary: the loader is where the bytes are read, the lookup is where they are used.
//
// Oracle: no sanitizer report, no hardening trap, no ASSUME, no uncaught exception.

#include "ingest.cpp"

#include "fuzzsupport.h"

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>
#include <string_view>
#include <vector>

namespace rwfuzz
{

int ingestrecord( const std::uint8_t* data, std::size_t size )
{
    std::string_view in( reinterpret_cast<const char*>( data ), size );
    takeByte( in );   // the seed corpus' family byte (one family since format 56)
    rw::ByteR        r{ in.data(), in.data() + in.size() };
    std::vector<std::uint64_t> dict;
    std::string                rel;
    rw::FileFacts              facts;
    noteAccepted( rw::readFileRecord( r, dict, rel, facts ) );
    return 0;
}

int ingestframe( const std::uint8_t* data, std::size_t size )
{
    std::string_view in( reinterpret_cast<const char*>( data ), size );
    takeByte( in );   // the seed corpus' family byte (one family since format 56)
    std::string      blob( in );
    if( blob.size() < rw::kCacheHeaderBytes + rw::kCacheTrailerBytes )
    {
        blob.resize( rw::kCacheHeaderBytes + rw::kCacheTrailerBytes, '\0' );
    }
    const std::uint32_t magic     = rw::kCacheMagic;
    const std::uint32_t version   = rw::kCacheVersion;
    const std::uint32_t parserVer = rw::kParserVer;
    std::memcpy( blob.data() + 0, &magic, 4 );
    std::memcpy( blob.data() + 4, &version, 4 );
    std::memcpy( blob.data() + 8, &parserVer, 4 );
    blob[ 12 ] = char( rw::kArtifactArch );
    // The trailer's table offset and entry count are the fuzzer's; the checksum over header + table is rebuilt
    // whenever the table it names lies inside the blob, so a well-framed mutant reaches the per-entry checks.
    std::uint64_t tableOffset = 0;
    std::uint32_t entryCount  = 0;
    const std::size_t trailerAt = blob.size() - rw::kCacheTrailerBytes;
    std::memcpy( &tableOffset, blob.data() + trailerAt, 8 );
    std::memcpy( &entryCount, blob.data() + trailerAt + 8, 4 );
    std::memcpy( blob.data() + 21, &entryCount, 4 );
    const std::uint64_t tableBytes = std::uint64_t( entryCount ) * rw::kCacheEntryBytes;
    if( tableOffset <= trailerAt && tableBytes <= trailerAt - tableOffset )
    {
        std::string hdrTable( blob.data(), rw::kCacheHeaderBytes );
        hdrTable.append( blob.data() + tableOffset, std::size_t( tableBytes ) );
        const std::uint64_t tableSum = rw::blobChecksum( hdrTable );
        std::memcpy( blob.data() + trailerAt + 16, &tableSum, 8 );
    }
    const rw::CacheFrame frame = rw::openCacheFrame( writeScratch( "ingest.cache", blob ) );
    noteAccepted( frame.ok );
    return 0;
}

int stiermemo( const std::uint8_t* data, std::size_t size )
{
    static const std::string target = writeScratch( "memo_target.cpp", "int memoTarget() { return 0; }\n" );
    const rw::StatInfo       now{ 1000, 31, 1000 };   // mtime, size, ctime: older than any blob written below
    std::string              blob;
    const auto               put32 = [ & ]( std::uint32_t v ) { blob.append( reinterpret_cast<const char*>( &v ), 4 ); };
    const auto               put64 = [ & ]( long long v ) { blob.append( reinterpret_cast<const char*>( &v ), 8 ); };
    put32( rw::kSpanTierMemoMagic );
    put32( rw::kSpanTierMemoVersion );
    put64( now.sizeBytes );
    put64( now.mtimeNs );
    put64( now.ctimeNs );
    put32( std::uint32_t( target.size() ) );
    blob += target;
    blob += bytesOf( data, size );   // spanCount, then the three arrays
    const std::string memoPath = rw::spanTierMemoPath( target );
    std::error_code   ec;
    std::filesystem::create_directories( std::filesystem::path( memoPath ).parent_path(), ec );
    {
        std::FILE* fp = std::fopen( memoPath.c_str(), "wb" );
        if( fp == nullptr )
        {
            std::abort();
        }
        const bool wrote = std::fwrite( blob.data(), 1, blob.size(), fp ) == blob.size();
        if( std::fclose( fp ) != 0 || !wrote )
        {
            std::abort();
        }
    }
    rw::SpanTierMap map;
    const bool      loaded = rw::spanTierMemoLoad( target, now, map );
    noteAccepted( loaded );
    if( loaded )
    {
        const std::size_t spanCount = map.startByte.size();
        for( std::size_t spanIndex = 0; spanIndex < spanCount && spanIndex < 4096; ++spanIndex )
        {
            (void)rw::spanTierAt( map, map.startByte[ spanIndex ] );
            (void)rw::spanTierAt( map, map.endByte[ spanIndex ] );
        }
    }
    return 0;
}

}   // namespace rwfuzz
