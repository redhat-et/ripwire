#pragma once
// gitblob.h — the git blob object id of a byte string: sha1( "blob <len>\0" + bytes ), hex.
//
// E2 (terminality round A, 2026-09-05): the edit receipt carries the id of the bytes it wrote, so "what is on
// disk now" is a fact an agent can check against `git hash-object FILE` / `git ls-files -s` without reading the
// file back. SHA-1 is git's IDENTITY function, not a security primitive — nothing here authenticates anything —
// which is why it is hand-rolled (zero dependencies, G3) and why the lint catalog's weak-crypto rule (a CALL to
// a function named sha1/md5) has nothing to flag: the compression step is named for what it is.
//
// Pure, allocation-free apart from the returned string; sanitizer-clean (every shift is on uint32_t, every
// rotate masks to 32 bits). Verified against `git hash-object` by test/receiptpostcheck.sh (11).

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace rw::gitblob
{

inline constexpr std::uint32_t rotl32( std::uint32_t v, unsigned r ) noexcept
{
    return ( v << r ) | ( v >> ( 32u - r ) );
}

// one 64-byte block folded into the running state
inline void sha1CompressBlock( std::array<std::uint32_t, 5>& h, const unsigned char* block ) noexcept
{
    std::uint32_t w[ 80 ];
    for( unsigned i = 0; i < 16; ++i )
    {
        w[ i ] = ( std::uint32_t( block[ 4 * i ] ) << 24 ) | ( std::uint32_t( block[ 4 * i + 1 ] ) << 16 )
               | ( std::uint32_t( block[ 4 * i + 2 ] ) << 8 ) | std::uint32_t( block[ 4 * i + 3 ] );
    }
    for( unsigned i = 16; i < 80; ++i )
    {
        w[ i ] = rotl32( w[ i - 3 ] ^ w[ i - 8 ] ^ w[ i - 14 ] ^ w[ i - 16 ], 1 );
    }
    std::uint32_t a = h[ 0 ], b = h[ 1 ], c = h[ 2 ], d = h[ 3 ], e = h[ 4 ];
    for( unsigned i = 0; i < 80; ++i )
    {
        std::uint32_t f, k;
        if( i < 20 )      { f = ( b & c ) | ( ~b & d );            k = 0x5A827999u; }
        else if( i < 40 ) { f = b ^ c ^ d;                         k = 0x6ED9EBA1u; }
        else if( i < 60 ) { f = ( b & c ) | ( b & d ) | ( c & d ); k = 0x8F1BBCDCu; }
        else              { f = b ^ c ^ d;                         k = 0xCA62C1D6u; }
        const std::uint32_t t = rotl32( a, 5 ) + f + e + k + w[ i ];
        e = d;  d = c;  c = rotl32( b, 30 );  b = a;  a = t;
    }
    h[ 0 ] += a;  h[ 1 ] += b;  h[ 2 ] += c;  h[ 3 ] += d;  h[ 4 ] += e;
}

// SHA-1 over the concatenation of `parts`, as 40 lowercase hex characters
inline std::string sha1Hex( std::string_view head, std::string_view body )
{
    std::array<std::uint32_t, 5> h = { 0x67452301u, 0xEFCDAB89u, 0x98BADCFEu, 0x10325476u, 0xC3D2E1F0u };
    unsigned char block[ 64 ];
    std::size_t   fill = 0;
    std::uint64_t total = 0;
    const auto feed = [ & ]( std::string_view s )
    {
        for( const char ch : s )
        {
            block[ fill++ ] = static_cast<unsigned char>( ch );
            ++total;
            if( fill == 64 ) { sha1CompressBlock( h, block );  fill = 0; }
        }
    };
    feed( head );
    feed( body );
    // padding: 0x80, zeros to 56 mod 64, then the bit length big-endian
    block[ fill++ ] = 0x80;
    if( fill > 56 )
    {
        while( fill < 64 ) { block[ fill++ ] = 0; }
        sha1CompressBlock( h, block );
        fill = 0;
    }
    while( fill < 56 ) { block[ fill++ ] = 0; }
    const std::uint64_t bits = total * 8u;
    for( unsigned i = 0; i < 8; ++i )
    {
        block[ 56 + i ] = static_cast<unsigned char>( ( bits >> ( 56u - 8u * i ) ) & 0xFFu );
    }
    sha1CompressBlock( h, block );
    static constexpr char kHex[] = "0123456789abcdef";
    std::string out;
    out.reserve( 40 );
    for( const std::uint32_t v : h )
    {
        for( int shift = 28; shift >= 0; shift -= 4 ) { out += kHex[ ( v >> unsigned( shift ) ) & 0xFu ]; }
    }
    return out;
}

// git's blob id: sha1( "blob <decimal length>\0" + bytes )
inline std::string blobOid( std::string_view bytes )
{
    const std::string header = "blob " + std::to_string( bytes.size() ) + '\0';
    return sha1Hex( header, bytes );
}

}   // namespace rw::gitblob
