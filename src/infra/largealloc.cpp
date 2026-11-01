// largealloc.cpp — on macOS, every operator new of 256 KiB or more gets its own mmap region and munmap gives its pages
// back on delete. THE ONE translation unit that replaces the global allocation functions (with alloccount.cpp, an
// instrument CMake never links beside this one).
//
// WHY. The default macOS zone keeps freed large blocks resident (vmmap: "MALLOC_LARGE (empty)"), and they count in the
// peak footprint. An index walks growth ladders (each worker's vector<RawRef> doubles through 8-65 MB blocks) and frees
// short-lived arrays, so about half of the peak was blocks nothing held: `--deps` on Envoy 1,515 to 767 MB, cockroach
// 1,848 to 984, vscode 2,873 to 1,482, wall unchanged (test/largeallocpeakcheck.sh keeps the ratio).
// COMPARED BEFORE CHOSEN. A chunked worker store with no ladder removed only 0-17 %, because every other large free is
// still kept, and added nothing worth its code on top of this route. `MallocLargeCache=0` gives the same peak, but
// libmalloc reads that undocumented variable only at process start, so it would cost a re-exec on every run. glibc does
// not need any of this: on the gate's fixture a fixed mmap threshold moved max RSS by 2 %, so Linux has no route.
//
// THE MEMORY GUARD STAYS HONEST: the footprint it reads (os::mem_footprint, the kernel's phys_footprint) counts these
// regions like any other dirty page, so --max-memory holds with no change.
//
// NOT ROUTED: over-aligned new (no new-expression in ripwire asks for a large one; the library's aligned forms use
// posix_memalign and free, never these functions); malloc itself (tree-sitter's own, about 2 % of the large bytes).
// RIPWIRE_TEST_LARGEALLOC=off turns the route off for one run, so the gate can compare the same binary with and without.
#include "infra/largealloc.h"
#include <cstdlib>
#include <new>

namespace
{
// 64 K slots hold far more than the few dozen large blocks that live at once; an index makes a few thousand in a run.
constinit rw::largealloc::BlockTable<std::size_t( 1 ) << 16, 4096> g_blocks;

void* allocOrNull( std::size_t n ) noexcept
{
    if( n >= rw::largealloc::kMinBytes )
    {
        static const bool off = []
        { const char* v = std::getenv( "RIPWIRE_TEST_LARGEALLOC" ); return v != nullptr && v[ 0 ] == 'o' && v[ 1 ] == 'f'; }();
        if( !off )
        {
            if( void* p = rw::largealloc::allocate( g_blocks, n ) )
            {
                return p;
            }
        }
    }
    return std::malloc( n != 0 ? n : 1 );
}
} // namespace

void* operator new( std::size_t n )
{
    for( ;; )
    {
        if( void* p = allocOrNull( n ) )
        {
            return p;
        }
        const std::new_handler h = std::get_new_handler();
        if( h == nullptr )
        {
            throw std::bad_alloc();
        }
        h();
    }
}
void* operator new[]( std::size_t n ) { return ::operator new( n ); }
void* operator new( std::size_t n, const std::nothrow_t& ) noexcept
{
    try
    {
        return ::operator new( n );
    }
    catch( ... )
    {
        return nullptr;
    }
}
void* operator new[]( std::size_t n, const std::nothrow_t& t ) noexcept { return ::operator new( n, t ); }

void operator delete( void* p ) noexcept
{
    if( p != nullptr && !rw::largealloc::release( g_blocks, p ) )
    {
        std::free( p );
    }
}
void operator delete[]( void* p ) noexcept { ::operator delete( p ); }
void operator delete( void* p, std::size_t ) noexcept { ::operator delete( p ); }
void operator delete[]( void* p, std::size_t ) noexcept { ::operator delete( p ); }
void operator delete( void* p, const std::nothrow_t& ) noexcept { ::operator delete( p ); }
void operator delete[]( void* p, const std::nothrow_t& ) noexcept { ::operator delete( p ); }
