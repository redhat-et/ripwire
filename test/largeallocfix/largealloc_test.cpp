// largealloc_test.cpp — driven by test/largeallocpeakcheck.sh. Compiled alone with src/largealloc.h (the table and
// the route, every POSIX host) and, with LINK_OPERATORS, with src/largealloc.cpp (the replaced forms, macOS).
#include "largealloc.h"
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>
#include <string>
#include <thread>
#include <vector>
#if defined( __APPLE__ )
#include <malloc/malloc.h>
#endif

static int g_fail = 0;
#define CHECK( c ) do { if( !( c ) ) { std::printf( "  FAIL line %d: %s\n", __LINE__, #c ); g_fail = 1; } } while( 0 )

using namespace rw::largealloc;

static void tableArms()
{
    using Tiny = BlockTable<16, 8>;
    static Tiny t;
    // Every address below shares one home slot's neighbourhood only by chance, so fill past the table's size: the route
    // must say no at some point and say yes again once a block is forgotten, and never lose a pointer it accepted.
    std::vector<std::uint64_t> in;
    for( std::uint64_t i = 1; i <= 64; ++i )
    {
        const std::uint64_t p = i * 4096 + kHeader;
        if( t.remember( p ) )
        {
            in.push_back( p );
        }
    }
    CHECK( !in.empty() && in.size() <= 16 );
    CHECK( !t.remember( 4096 * 1000 + kHeader ) || in.size() < 16 );
    for( std::uint64_t p : in )
    {
        CHECK( t.forget( p ) );
        CHECK( !t.forget( p ) );
    }
    CHECK( !t.forget( 12345 * 4096 + kHeader ) );   // an all-tombstone table ends the probe at the limit, not in a loop
    CHECK( t.remember( 4096 * 7 + kHeader ) );      // tombstones are reused
    CHECK( t.forget( 4096 * 7 + kHeader ) );
}

static void routeArms()
{
    static BlockTable<64, 8> t;
    CHECK( allocate( t, kMinBytes - 1 ) == nullptr );
    CHECK( allocate( t, kMaxRouted + 1 ) == nullptr );
    CHECK( allocate( t, std::size_t( -1 ) ) == nullptr );   // no wrap in the rounding: a wrapped size would map a small region
    for( std::size_t n : { kMinBytes, kMinBytes + 1, kRoundTo * 32 - kHeader, kRoundTo * 32 - kHeader + 1, std::size_t( 9 ) << 20 } )
    {
        void* p = allocate( t, n );
        CHECK( p != nullptr );
        CHECK( ( reinterpret_cast<std::uintptr_t>( p ) & 15 ) == 0 );
        std::memset( p, 0xAB, n );   // the whole request is writable (no off-by-header)
        CHECK( static_cast<unsigned char*>( p )[ n - 1 ] == 0xAB );
        CHECK( release( t, p ) );
    }
    // An ordinary block sitting exactly kHeader into a page is not ours: release says no and it stays free-able.
    std::vector<void*> held;
    bool               sawLookalike = false;
    for( int i = 0; i < 200000 && !sawLookalike; ++i )
    {
        void* m = std::malloc( 32 );
        held.push_back( m );
        if( ( reinterpret_cast<std::uintptr_t>( m ) & kPageFilter ) == kHeader )
        {
            sawLookalike = true;
            CHECK( !release( t, m ) );
        }
    }
    for( void* m : held )
    {
        std::free( m );
    }
    // A busy table: the route refuses, and unmaps what it had mapped.
    static BlockTable<4, 2> full;
    std::vector<void*>      live;
    int                     refused = 0;
    for( int i = 0; i < 16; ++i )
    {
        if( void* p = allocate( full, kMinBytes ) )
        {
            live.push_back( p );
        }
        else
        {
            ++refused;
        }
    }
    CHECK( refused > 0 && live.size() <= 4 );
    for( void* p : live )
    {
        CHECK( release( full, p ) );
    }
    // Eight threads, blocks freed on a different thread from the one that made them.
    static BlockTable<std::size_t( 1 ) << 12, 256> shared;
    std::atomic<void*> mailbox[ 8 ];
    for( auto& m : mailbox )
    {
        m.store( nullptr );
    }
    std::atomic<int>         bad{ 0 };
    std::vector<std::thread> ts;
    for( unsigned k = 0; k < 8; ++k )
    {
        ts.emplace_back( [ &, k ]
        {
            for( int i = 0; i < 2000; ++i )
            {
                void* p = allocate( shared, kMinBytes + i );
                if( p == nullptr )
                {
                    bad.fetch_add( 1 );
                    continue;
                }
                *static_cast<std::uint64_t*>( p ) = reinterpret_cast<std::uint64_t>( p );
                if( void* q = mailbox[ ( k + 1 ) % 8 ].exchange( p ) )
                {
                    if( *static_cast<std::uint64_t*>( q ) != reinterpret_cast<std::uint64_t>( q ) || !release( shared, q ) )
                    {
                        bad.fetch_add( 1 );
                    }
                }
            }
        } );
    }
    for( auto& th : ts )
    {
        th.join();
    }
    for( auto& m : mailbox )
    {
        if( void* q = m.exchange( nullptr ) )
        {
            CHECK( release( shared, q ) );
        }
    }
    CHECK( bad.load() == 0 );
}

#if defined( LINK_OPERATORS )
static int g_handlerCalls = 0;
static void handlerOnce()
{
    ++g_handlerCalls;
    std::set_new_handler( nullptr );
}
static bool isZoneBlock( void* p )
{
    return malloc_size( p ) != 0;
}
static void operatorArms()
{
    const std::size_t big = kMinBytes * 2;
    void*             a   = ::operator new( big );
    CHECK( !isZoneBlock( a ) );   // routed, the point of the file
    ::operator delete( a );
    void* b = ::operator new[]( big );
    CHECK( !isZoneBlock( b ) );
    ::operator delete[]( b );
    void* c = ::operator new( big, std::nothrow );
    CHECK( c != nullptr && !isZoneBlock( c ) );
    ::operator delete( c, big );   // sized delete
    void* d = ::operator new[]( big, std::nothrow );
    CHECK( d != nullptr );
    ::operator delete[]( d, big );
    void* e = ::operator new( big );
    ::operator delete( e, std::nothrow );
    void* f = ::operator new( 64 );
    CHECK( isZoneBlock( f ) );   // small: the zone, as before
    ::operator delete( f );
    void* z = ::operator new( 0 );
    CHECK( z != nullptr );
    ::operator delete( z );
    ::operator delete( nullptr );
    void* al = ::operator new( big, std::align_val_t( 4096 ) );
    CHECK( ( reinterpret_cast<std::uintptr_t>( al ) & 4095 ) == 0 );
    ::operator delete( al, std::align_val_t( 4096 ) );   // the library's aligned pair never meets the route
    // Failure paths: too big for anything.
    const std::size_t huge = std::size_t( -1 ) - 4096;
    CHECK( ::operator new( huge, std::nothrow ) == nullptr );
    CHECK( ::operator new[]( huge, std::nothrow ) == nullptr );
    bool threw = false;
    try
    {
        void* never = ::operator new( huge );
        ::operator delete( never );
    }
    catch( const std::bad_alloc& )
    {
        threw = true;
    }
    CHECK( threw );
    std::set_new_handler( handlerOnce );
    threw = false;
    try
    {
        void* never = ::operator new( huge );
        ::operator delete( never );
    }
    catch( const std::bad_alloc& )
    {
        threw = true;
    }
    CHECK( threw && g_handlerCalls == 1 );
    // A block held from one thread into another, and through a vector that really grows past the threshold.
    std::vector<char>* v = new std::vector<char>( big * 4, 'x' );
    std::thread( [ v ] { v->resize( big * 16, 'y' ); delete v; } ).join();
    std::string s( big, 's' );   // libc++'s own string paths use the same pair
    s.append( big, 't' );
    CHECK( s.size() == big * 2 );
}
#endif

int main()
{
    tableArms();
    routeArms();
#if defined( LINK_OPERATORS )
    operatorArms();
#endif
    if( g_fail == 0 )
    {
        std::printf( "UNIT_OK\n" );
    }
    return g_fail;
}
