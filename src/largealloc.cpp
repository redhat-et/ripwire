// largealloc.cpp — on macOS, every operator new of 256 KiB or more gets its own mmap region and munmap gives its pages
// back on delete. THE ONE translation unit that replaces the global allocation functions (with alloccount.cpp, an
// instrument CMake never links beside this one).
//
// WHY. The default macOS zone keeps freed large blocks resident (vmmap: "MALLOC_LARGE (empty)"), and they count in the
// peak footprint. An index walks growth ladders (each worker's vector<RawRef> doubles through 8-65 MB blocks) and frees
// short-lived arrays, so about half of the peak was blocks nothing held: `--deps` on Envoy 1,515 to 767 MB, cockroach
// 1,848 to 984, vscode 2,873 to 1,482, CPU flat (test/largeallocpeakcheck.sh keeps the ratio).
// COMPARED BEFORE CHOSEN. A chunked worker store with no ladder removed only 0-17 %, because every other large free is
// still kept, and added nothing worth its code on top of this route. `MallocLargeCache=0` gives the same peak, but
// libmalloc reads that undocumented variable only at process start, so it would cost a re-exec on every run. glibc does
// not need any of this: on the gate's fixture a fixed mmap threshold moved max RSS by 2 %, so Linux has no route.
//
// THE MEMORY GUARD: the footprint it reads (os::mem_footprint, the kernel's phys_footprint) counts these regions like any
// other dirty page while they live, so --max-memory still stops a run that is over its limit at a reading. But a block
// returned early is gone from the NEXT reading, so a run can peak above its cap, pass every reading and finish: the cap can
// be exceeded in that band. The run says so (memguard.h "the overshoot": one stderr line, memory_peak= in the map header,
// `_memory_peak` in the MCP envelope); it is disclosed, not enforced (owner, 2026-11-01).
//
// NOT ROUTED: over-aligned new (the library's aligned forms use posix_memalign and free, never these functions; the one
// direct caller, infra/sparseCsr.h, pairs it with the aligned delete, and those frees stay retained); malloc itself (tree-sitter's own, about 2 % of the large bytes).
// RIPWIRE_TEST_LARGEALLOC=off turns the route off for one run, so the gate can compare the same binary with and without.
//
// NEVER INLINED (RW_ALLOC_FN below, on every form). The compiler knows these functions by name: a caller's `operator new`
// is, to the optimizer, a fresh block of exactly n bytes whose contents are indeterminate. The route keeps the region's
// size 16 bytes BEFORE that block, and release() reads it back. Under LTO the body of operator delete was inlined into
// functions that also held the matching new, where that read is a load from outside (before) a block the optimizer
// believes it knows whole: it folded the load to "any value" and passed munmap whatever the length register last held.
// At least 15 of the 46,669 inlined frees in the 0.7.0 candidate (no profile) were built that way (pageRankDouble's score array among them), and
// the length a preceding memcpy left behind was a pointer: a multi-gigabyte unmap. Low in the address space that range
// reaches a region the kernel will not remove, the call fails with EINVAL and the block only leaks; above it the call
// succeeds and takes every later mapping with it, which on llvm-project was the loaded graph (a warm --for then read
// unmapped memory: 6 of 9 fully warm runs). Kept out of line, the read happens where the pointer is only a pointer, as
// it does in every allocator that lives behind a library boundary and in every non-LTO build of this file.
// test/largeallocpeakcheck.sh arm L builds this file under -O2 -flto and holds both halves: freed blocks leave the
// footprint, and munmap is called from these functions and nowhere else (arm S asks the same of the binary under test).
#include "largealloc.h"
#include "memceiling.h"   // the memory guard's allocator line: onAllocate before every block
#include <cstdlib>
#include <new>

#define RW_ALLOC_FN [[gnu::noinline]]

namespace
{
// 64 K slots hold far more than the few dozen large blocks that live at once; an index makes a few thousand in a run.
constinit rw::largealloc::BlockTable<std::size_t( 1 ) << 16, 4096> g_blocks;

void* allocOrNull( std::size_t n ) noexcept
{
    rw::memceiling::onAllocate( n );   // disarmed: one relaxed load; armed: may refuse the run before the block is taken
    if( n >= rw::largealloc::kMinBytes )
    {
        // the variable's name is also the route's mark: test/largeallocpeakcheck.sh finds it in the binary to tell a build
        // that links this file from one that does not, so no other source file spells it
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

RW_ALLOC_FN void* operator new( std::size_t n )
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
RW_ALLOC_FN void* operator new[]( std::size_t n ) { return ::operator new( n ); }
RW_ALLOC_FN void* operator new( std::size_t n, const std::nothrow_t& ) noexcept
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
RW_ALLOC_FN void* operator new[]( std::size_t n, const std::nothrow_t& t ) noexcept { return ::operator new( n, t ); }

RW_ALLOC_FN void operator delete( void* p ) noexcept
{
    if( p != nullptr && !rw::largealloc::release( g_blocks, p ) )
    {
        std::free( p );
    }
}
RW_ALLOC_FN void operator delete[]( void* p ) noexcept { ::operator delete( p ); }
RW_ALLOC_FN void operator delete( void* p, std::size_t ) noexcept { ::operator delete( p ); }
RW_ALLOC_FN void operator delete[]( void* p, std::size_t ) noexcept { ::operator delete( p ); }
RW_ALLOC_FN void operator delete( void* p, const std::nothrow_t& ) noexcept { ::operator delete( p ); }
RW_ALLOC_FN void operator delete[]( void* p, const std::nothrow_t& ) noexcept { ::operator delete( p ); }
