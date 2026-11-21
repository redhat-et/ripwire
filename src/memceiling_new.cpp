// memceiling_new.cpp — the memory ceiling's operator new where largealloc.cpp is not linked (Linux, Windows, other POSIX).
// It replaces the global allocation functions ONLY to ask memceiling::onAllocate before each block (memceiling.h); the
// blocks themselves come from malloc and go back to free, exactly what the default operator new does. THE ONE translation
// unit replacing them on these platforms — CMake never links it beside largealloc.cpp or alloccount.cpp.
//
// NOT ROUTED: over-aligned new (the library's aligned forms use their own aligned allocation; infra/sparseCsr.h, its one
// direct caller, is not read by the ceiling) and malloc itself (tree-sitter's own) — the same gaps largealloc.cpp states.
#include "memceiling.h"
#include <cstdlib>
#include <new>

void* operator new( std::size_t n )
{
    rw::memceiling::onAllocate( n );   // disarmed: one relaxed load; armed: may refuse the run before the block is taken
    for( ;; )
    {
        if( void* p = std::malloc( n != 0 ? n : 1 ) )
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

void operator delete( void* p ) noexcept { std::free( p ); }
void operator delete[]( void* p ) noexcept { std::free( p ); }
void operator delete( void* p, std::size_t ) noexcept { std::free( p ); }
void operator delete[]( void* p, std::size_t ) noexcept { std::free( p ); }
void operator delete( void* p, const std::nothrow_t& ) noexcept { std::free( p ); }
void operator delete[]( void* p, const std::nothrow_t& ) noexcept { std::free( p ); }
