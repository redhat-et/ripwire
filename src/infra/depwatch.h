#pragma once
// depwatch.h — which files did a computation read, and what did each read answer?
//
// A cached result is only as good as the list of what it was computed from. When the computation opens files itself — a
// manifest, a config above the root, a source file's own bytes — a cache of its result has to know every one of them: a
// result served after one changed is a wrong answer at exit 0. The read seams report here (a whole-file read, a capped
// config read, two existence probes), and the cache's owner stores what they saw. On the next run each recorded read is
// REPEATED through the same seam and its answer compared.
//
// One log per process, armed by its owner for the span of one computation. Unarmed (every other run, every other caller) a
// seam costs one relaxed atomic load. A mutex guards the rows: a serial computation today, and a parallel one tomorrow
// must not have to remember this file.
#include "hashutil.h"   // multiplyModulo64

#include <atomic>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

namespace rw::depwatch
{

enum class Seam : std::uint8_t
{
    WholeFile,     // the whole-file reader
    ConfigBytes,   // the capped config reader (1 MiB; unreadable reads as empty)
    StatExists,    // os::stat( path ) == 0
    FsExists,      // std::filesystem::exists( path, ec )
    Count
};

// what a seam answered: a digest of the bytes, or one of two fixed values for "no such file" / "exists"
inline constexpr std::uint64_t kAbsent  = 0x6162'7365'6e74'0001ull;
inline constexpr std::uint64_t kPresent = 0x7072'6573'656e'7401ull;

// 64-bit digest of a byte run: four independent multiply-rotate lanes over 8-byte words, folded. A corruption and
// change detector (the snapshot's checksum and every content comparison it makes), never an identity anyone can forge
// against: the inputs are the user's own tree and the user's own cache file.
inline std::uint64_t digest64( std::string_view bytes ) noexcept
{
    constexpr std::uint64_t kMulA = 0x9e37'79b9'7f4a'7c15ull;
    constexpr std::uint64_t kMulB = 0xc2b2'ae3d'27d4'eb4full;
    std::uint64_t lane[ 4 ] = { 0x2437'53c1'9f0a'1b63ull, 0x8f1b'bcdc'ca62'c1d6ull, 0x5be0'cd19'137e'2179ull, 0x1f83'd9ab'fb41'bd6bull };
    const char*   p         = bytes.data();
    std::size_t   n         = bytes.size();
    const auto    word      = []( const char* at ) noexcept { std::uint64_t w; std::memcpy( &w, at, 8 ); return w; };
    const auto    mix       = []( std::uint64_t h, std::uint64_t w ) noexcept
    {
        h ^= hashutil::multiplyModulo64( w, kMulB );   // modulo 2^64 by intent: the sanitizer-clean multiply (infra/hashutil.h)
        // rotate left by 31, masking first so no set bit is shifted out: std::rotl's own shift trips the `integer` sanitizer group
        const std::uint64_t rotated = ( ( h & ( ~std::uint64_t( 0 ) >> 31 ) ) << 31 ) | ( h >> 33 );
        return hashutil::multiplyModulo64( rotated, kMulA );
    };
    for( ; n >= 32; n -= 32, p += 32 )
    {
        lane[ 0 ] = mix( lane[ 0 ], word( p ) );
        lane[ 1 ] = mix( lane[ 1 ], word( p + 8 ) );
        lane[ 2 ] = mix( lane[ 2 ], word( p + 16 ) );
        lane[ 3 ] = mix( lane[ 3 ], word( p + 24 ) );
    }
    std::uint64_t h = mix( mix( mix( mix( hashutil::multiplyModulo64( bytes.size(), kMulA ), lane[ 0 ] ), lane[ 1 ] ), lane[ 2 ] ), lane[ 3 ] );
    for( ; n >= 8; n -= 8, p += 8 )
    {
        h = mix( h, word( p ) );
    }
    std::uint64_t tail = 0;
    for( std::size_t i = 0; i < n; ++i )
    {
        tail |= std::uint64_t( static_cast<unsigned char>( p[ i ] ) ) << ( 8 * i );
    }
    h = mix( h, tail ^ ( std::uint64_t( n ) << 56 ) );
    h ^= h >> 29;
    h = hashutil::multiplyModulo64( h, kMulB );
    h ^= h >> 32;
    return h;
}

struct Dep
{
    std::string   path;
    Seam          seam   = Seam::WholeFile;
    std::uint64_t answer = kAbsent;
};

struct Log
{
    std::mutex       guard;
    std::vector<Dep> deps;
};

inline std::atomic<Log*>& activeLog() noexcept
{
    static std::atomic<Log*> log{ nullptr };
    return log;
}

// One row into the armed log, if any. A row that cannot be stored (allocation) poisons the log instead: its owner reads
// Seam::Count as "this computation's reads are not all here — store nothing".
inline void record( Seam seam, const std::string& path, std::uint64_t answer ) noexcept
{
    Log* const log = activeLog().load( std::memory_order_relaxed );
    if( log == nullptr )
    {
        return;
    }
    const std::lock_guard<std::mutex> hold( log->guard );
    try
    {
        log->deps.push_back( Dep{ path, seam, answer } );
    }
    catch( ... )
    {
        log->deps.clear();
        log->deps.push_back( Dep{ std::string(), Seam::Count, 0 } );
    }
}

inline bool armed() noexcept { return activeLog().load( std::memory_order_relaxed ) != nullptr; }

// A read seam's report. `bytes == nullptr` is "the seam found nothing to read". The digest is taken only while a log is armed.
inline void note( Seam seam, const std::string& path, const std::string* bytes ) noexcept
{
    if( armed() ) { record( seam, path, bytes == nullptr ? kAbsent : digest64( *bytes ) ); }
}

inline void noteExists( Seam seam, const std::string& path, bool exists ) noexcept { record( seam, path, exists ? kPresent : kAbsent ); }

// An existence probe's answer, reported and handed back: `if( !noted( seam, path, exists( path ) ) )` reads as the probe did.
inline bool noted( Seam seam, const std::string& path, bool exists ) noexcept
{
    noteExists( seam, path, exists );
    return exists;
}

// Arms `log` for this scope. One owner at a time: a nested arm (there is none) would leave the outer one unarmed.
class Armed
{
public:
    explicit Armed( Log* log ) noexcept { activeLog().store( log, std::memory_order_relaxed ); }
    ~Armed() { activeLog().store( nullptr, std::memory_order_relaxed ); }
    Armed( const Armed& )            = delete;
    Armed& operator=( const Armed& ) = delete;
};

}   // namespace rw::depwatch
