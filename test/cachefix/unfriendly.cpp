// cachefix/unfriendly.cpp — the RECALL half of the cache-rules fixture: every cache-* rule in
// src/cachelint.h must fire here, at the exact pinned lines cachelintcheck.sh asserts.
// Parsed only, never run. Line numbers are load-bearing — do not reflow.
#include <cstdlib>
#include <list>
#include <map>
#include <memory>
#include <vector>

struct Node { int v; Node* next; };

// cache-node-container: node-based std containers — one heap node per element.
std::map<int, int> g_lookup;                                 // L13: cache-node-container
std::list<Node> g_items;                                     // L14: cache-node-container

// cache-vector-of-raw-ptr / cache-vector-of-indirect: an indirection per element.
std::vector<Node*> g_ptrs;                                   // L17: cache-vector-of-raw-ptr
std::vector<std::unique_ptr<Node>> g_owned;                  // L18: cache-vector-of-indirect
std::vector<std::vector<int>> g_grid;                        // L19: cache-vector-of-indirect (2-D via row pointers)

void heapAllocInLoop( int n, std::vector<int*>& sink )       // L21: cache-vector-of-raw-ptr (param position)
{
    for( int i = 0; i < n; ++i )
    {
        sink[ i ] = new int( i );                            // L25: cache-heap-alloc-in-loop
        void* raw = std::malloc( 16 );                       // L26: cache-heap-alloc-in-loop
        std::free( raw );
    }
}

int pointerChase( const Node* head )
{
    int sum = 0;
    const Node* p = head;
    while( p != nullptr )
    {
        sum += p->v;
        p = p->next;                                         // L38: cache-pointer-chase-loop
    }
    return sum;
}

void gatherScatter( std::vector<float>& a, const std::vector<int>& idx )
{
    for( std::size_t i = 0; i < idx.size(); ++i )
    {
        a[ idx[ i ] ] += 1.0f;                               // L47: cache-gather-subscript
    }
}

int sharedByValue( std::shared_ptr<Node> sp )                // L51: cache-shared-ptr-by-value
{
    return sp ? sp->v : 0;
}

// The unqualified spellings (post `using namespace std;`) exercise the unqualified query arms.
using namespace std;

void unqualifiedForms( int n )
{
    vector<unique_ptr<Node>> owned;                          // L61: cache-vector-of-indirect
    for( int i = 0; i < n; ++i )
    {
        char* c = static_cast<char*>( malloc( 8 ) );         // L64: cache-heap-alloc-in-loop
        free( c );
    }
    (void)owned;
}

int sharedUnqualified( shared_ptr<Node> sp )                 // L70: cache-shared-ptr-by-value
{
    return sp ? sp->v : 0;
}

void prefetchWalk( const Node* p )
{
    while( p != nullptr )
    {
        __builtin_prefetch( p->next );                       // L79: cache-manual-prefetch
        p = p->next;                                         // L80: cache-pointer-chase-loop (second site)
    }
}
